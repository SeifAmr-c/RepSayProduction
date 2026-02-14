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
    whisperForm.append("language", "ar"); // Arabic (Egyptian Arabic will be detected)

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
You are a fitness assistant. The following is a transcription of someone describing their workout in Egyptian Arabic.

TRANSCRIPTION:
${transcription}

TASK:
1. First, determine if this transcription is about a gym workout or fitness exercise
2. If it's NOT about gym/fitness, return: {"not_gym_related": true}
3. If it IS about gym/fitness:
   - Translate the content to English
   - Extract all exercises mentioned with their sets, reps, and weights
   - Determine a smart workout name based on the muscle groups and exercises

WORKOUT NAMING RULES (VERY IMPORTANT):
1. "Strength & Conditioning" - ONLY use this name if the workout contains ANY of these specific exercises:
   Squat, Deadlift, Clean, Press, Sprint, Jump, Carry, Farmer's Walk, Farmer's Carry, Sled Push, Sled Pull, Tire Flips, Sandbag Carries, Turkish Get-Up, Power Clean, Hang Clean, Clean & Jerk, Snatch, Push Jerk, Box Jumps, Broad Jumps, Med Ball Slams, Kettlebell Swings, Sprints, Rowing, Assault Bike, Air Bike, Jump Rope, Burpees, Mountain Climbers, Battle Ropes, High Knees, Shuttle Runs

2. "Push Day" - If the workout targets Chest + Shoulders + Triceps (or any combination of these)

3. "Pull Day" - If the workout targets Back + Biceps (or any combination of these)

4. "Leg Day" - If the workout primarily targets Legs (Quads, Hamstrings, Glutes, Calves)

5. "Chest & Triceps" - If only chest and triceps exercises

6. "Back & Biceps" - If only back and biceps exercises

7. "Shoulders" - If only shoulder exercises

8. "Arms" - If only biceps and triceps (no chest or back)

9. "Full Body" - If multiple unrelated muscle groups are trained

10. Single muscle name (e.g., "Chest", "Back", "Legs") - If only one muscle group is targeted

EXERCISE RULES:
- If weight is not mentioned, use 0
- If sets/reps are not mentioned, estimate based on context or use reasonable defaults (3 sets, 10 reps)
- Exercise names should be in proper English (e.g., "Bench Press", "Squats", "Deadlifts", "Tricep Extensions", "Lat Pulldowns")

Return ONLY valid JSON in one of these formats (no markdown, no explanation):

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
          { role: "system", content: "You are a fitness assistant that extracts workout data from Arabic transcriptions. Always respond with valid JSON only." },
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