import { serve } from "std/http/server.ts";
import { createClient } from "supabase-js";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiKey) throw new Error("Missing OPENAI_API_KEY in Supabase Secrets");

    const body = await req.json();
    const { storage_path, duration, client_id } = body;
    console.log(`📝 Processing: ${storage_path} for Client: ${client_id}`);

    // 1. Download Audio
    const { data: fileData, error: downloadError } = await supabase
      .storage
      .from("workouts-audio")
      .download(storage_path);

    if (downloadError) throw new Error(`Download failed: ${downloadError.message}`);

    // 2. Convert to FormData for Whisper API
    const audioBlob = new Blob([await fileData.arrayBuffer()], { type: "audio/mp4" });

    // Create FormData for Whisper
    const whisperForm = new FormData();
    whisperForm.append("file", audioBlob, "audio.m4a");
    whisperForm.append("model", "whisper-1");
    // No language forced — Whisper auto-detects English, Arabic, or mixed

    console.log("🎤 Transcribing with Whisper...");

    // 3. Call OpenAI Whisper for transcription
    const whisperRes = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openaiKey}`,
      },
      body: whisperForm,
    });

    if (!whisperRes.ok) {
      const errText = await whisperRes.text();
      console.error("❌ Whisper API Error:", errText);
      throw new Error(`Whisper failed: ${whisperRes.status} - ${errText}`);
    }

    const whisperJson = await whisperRes.json();
    const transcription = whisperJson.text;
    console.log("📜 Transcription:", transcription);

    // ⚠️ VALIDATION: Check if transcription is empty or too short
    if (!transcription || transcription.trim().length < 5) {
      console.log("❌ Empty or too short transcription detected");
      return new Response(JSON.stringify({ 
        error: "EMPTY_RECORDING",
        message: "Sorry, we could not detect any workout details. Please try again and speak clearly."
      }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 4. Call GPT-4o-mini to translate and extract exercises
    const gptPrompt = `
You are an expert fitness assistant that understands gym terminology in English, Egyptian Arabic, and mixed English-Arabic speech.

The user may speak in:
- Pure English
- Pure Egyptian Arabic
- Mixed (English exercise names with Arabic sentence structure)

TRANSCRIPTION:
${transcription}

TASK:
1. First, determine if this transcription is about a gym workout or fitness exercise
2. If it's NOT about gym/fitness, return: {"not_gym_related": true}
3. If it IS about gym/fitness:
   - Translate the content to English
   - Extract all exercises mentioned with their sets, reps, and weights
   - Determine a smart workout name based on the PRIMARY muscle groups

═══════════════════════════════════════
CRITICAL: EXERCISE NAME DISAMBIGUATION
═══════════════════════════════════════
These exercises are commonly confused in Arabic speech recognition. Pay VERY careful attention:

• "لاتيرال رايز" / "lateral raise" / "رفع جانبي" → "Lateral Raises" (SHOULDERS - side delt raise with dumbbells)
  ⚠️ This is NOT "Lat Pulldown". These are completely different exercises.

• "لات بول داون" / "lat pull down" / "سحب" → "Lat Pulldown" (BACK - pulling a bar down to chest)
  ⚠️ This is NOT "Lateral Raises". This is a back exercise.

• "بوش" / "push" / "بوش اب" → Could mean "Push-ups" or refer to "Push Day" workout
• "بنش" / "bench" → "Bench Press" (CHEST)
• "فلاي" / "fly" → "Chest Flyes" (CHEST)
• "كيبل فلاي" → "Cable Flyes" (CHEST)
• "تراي" / "ترايسبس" → "Triceps" exercises
• "باي" / "بايسبس" → "Biceps" exercises  
• "ديد ليفت" / "ديدليفت" → "Deadlift" (BACK/LEGS)
• "سكوات" → "Squats" (LEGS)
• "ليج برس" → "Leg Press" (LEGS)
• "شولدر برس" → "Shoulder Press" (SHOULDERS)
• "كتف" → Shoulders exercises
• "ضهر" → Back exercises
• "صدر" → Chest exercises
• "رجل" → Leg exercises

═══════════════════════════════════════
EXERCISE → MUSCLE GROUP MAPPING
═══════════════════════════════════════
CHEST: Bench Press, Incline Bench Press, Decline Bench Press, Chest Flyes, Cable Flyes, Dumbbell Flyes, Chest Press, Pec Deck, Push-ups, Dips (if chest-focused)
SHOULDERS: Lateral Raises, Front Raises, Rear Delt Flyes, Shoulder Press, Military Press, Arnold Press, Upright Rows, Face Pulls, Shrugs
TRICEPS: Tricep Extensions, Tricep Pushdowns, Skull Crushers, Overhead Tricep Extensions, Close-Grip Bench Press, Dips (if tricep-focused), Tricep Kickbacks
BACK: Lat Pulldown, Seated Rows, Bent-Over Rows, T-Bar Rows, Pull-ups, Cable Rows, Deadlift, Back Extensions
BICEPS: Bicep Curls, Hammer Curls, Preacher Curls, Concentration Curls, Cable Curls, Incline Curls
LEGS: Squats, Leg Press, Leg Extensions, Leg Curls, Lunges, Romanian Deadlift, Calf Raises, Hip Thrusts, Bulgarian Split Squats

═══════════════════════════════════════
WORKOUT NAMING RULES (STRICT PRIORITY ORDER)
═══════════════════════════════════════
Apply these rules IN ORDER. Use the FIRST rule that matches:

1. "Strength & Conditioning" — ONLY if workout contains explosive/compound movements like: Clean, Snatch, Clean & Jerk, Power Clean, Turkish Get-Up, Kettlebell Swings, Box Jumps, Battle Ropes, Sled Push/Pull, Tire Flips, Burpees, Sprints

2. "Push Day" — If exercises target 2+ of these muscle groups: Chest, Shoulders, Triceps
   Example: Bench Press + Lateral Raises + Tricep Pushdowns = "Push Day"
   Example: Bench Press + Shoulder Press + Skull Crushers = "Push Day"

3. "Pull Day" — If exercises target 2+ of these muscle groups: Back, Biceps
   Example: Lat Pulldown + Barbell Rows + Bicep Curls = "Pull Day"

4. "Leg Day" — If the workout primarily targets Legs

5. "Chest & Triceps" — If ONLY chest and triceps exercises (no shoulders)
6. "Back & Biceps" — If ONLY back and biceps exercises
7. "Shoulders" — If ONLY shoulder exercises
8. "Arms" — If ONLY biceps and triceps (no chest or back)
9. "Full Body" — If multiple unrelated muscle groups

10. Single muscle name (e.g., "Chest", "Back") — If ONLY one muscle group

⚠️ IMPORTANT: The SAME set of exercises must ALWAYS produce the SAME workout name.
If someone says "push, tricep, and lateral raises" → muscles are Chest + Triceps + Shoulders → "Push Day"
If someone says the exact same exercises but differently worded → STILL "Push Day"

═══════════════════════════════════════
EXERCISE EXTRACTION RULES
═══════════════════════════════════════
- If weight is not mentioned, use 0
- If sets/reps are not mentioned, use defaults: 3 sets, 10 reps
- Exercise names MUST be proper English names (e.g., "Bench Press" not "بنش")
- Each exercise must be a REAL, specific exercise — not a body part name
- Never output duplicate exercises

Return ONLY valid JSON (no markdown, no explanation):

For gym-related content:
{
  "workout_name": "String",
  "exercises": [
    { "name": "String", "weight": Number, "sets": Number, "reps": Number }
  ]
}

For non-gym content:
{"not_gym_related": true}
`;

    console.log("🤖 Processing with GPT-4o-mini...");

    const gptRes = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${openaiKey}`,
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: "You are an expert fitness assistant that extracts workout data from transcriptions in English, Egyptian Arabic, or mixed language. You must correctly distinguish between similar-sounding exercises (e.g., 'lateral raises' are a SHOULDER exercise, NOT 'lat pulldown' which is a BACK exercise). Always respond with valid JSON only. Never output duplicate exercises. Always use proper English exercise names." },
          { role: "user", content: gptPrompt }
        ],
        temperature: 0.3,
        max_tokens: 1000,
      }),
    });

    if (!gptRes.ok) {
      const errText = await gptRes.text();
      console.error("❌ GPT API Error:", errText);
      throw new Error(`GPT failed: ${gptRes.status} - ${errText}`);
    }

    const gptJson = await gptRes.json();
    const gptText = gptJson.choices?.[0]?.message?.content;
    if (!gptText) throw new Error("GPT returned no content");

    console.log("📊 GPT Response:", gptText);

    // 5. Parse the JSON response
    const cleanJson = gptText.replace(/```json/g, "").replace(/```/g, "").trim();
    const data = JSON.parse(cleanJson);

    // ⚠️ VALIDATION: Check if content is not gym related
    if (data.not_gym_related === true) {
      console.log("❌ Non-gym content detected");
      return new Response(JSON.stringify({ 
        error: "NOT_GYM_RELATED",
        message: "Sorry, we could not understand what you said. Please describe your workout exercises."
      }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ⚠️ VALIDATION: Check if no exercises were extracted
    if (!data.exercises || data.exercises.length === 0) {
      console.log("❌ No exercises extracted");
      return new Response(JSON.stringify({ 
        error: "NO_EXERCISES",
        message: "Sorry, we could not detect any workout details. Please try again and mention your exercises."
      }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 6. Save to DB
    const userId = storage_path.split("/")[0];

    const { data: workout, error: wError } = await supabase
      .from("workouts")
      .insert({
        user_id: userId,
        client_id: client_id || null,
        name: data.workout_name || "Workout",
        date: new Date().toISOString(),
        notes: "Processed by AI (OpenAI)",
        audio_path: storage_path,
        duration_seconds: duration || 0,
      })
      .select()
      .single();

    if (wError) throw wError;

    if (data.exercises && data.exercises.length > 0) {
      const sets = data.exercises.map((ex: any, idx: number) => ({
        workout_id: workout.id,
        exercise_name: ex.name,
        weight: ex.weight || 0,
        sets: ex.sets || 3,
        reps: ex.reps || 10,
        order_index: idx,
      }));
      await supabase.from("workout_sets").insert(sets);
    }

    console.log("✅ Workout saved successfully!");

    return new Response(JSON.stringify({ success: true, data, transcription }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (error) {
    console.error("🔥 Error:", error);
    let msg = "Unknown error";
    if (error instanceof Error) {
      msg = error.message;
    } else if (typeof error === "object" && error !== null) {
      msg = JSON.stringify(error);
    } else {
      msg = String(error);
    }
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});