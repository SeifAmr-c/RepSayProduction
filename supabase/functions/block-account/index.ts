import { serve } from "std/http/server.ts";
import { createClient } from "supabase-js";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Get the authorization header from the request
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "No authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Create admin client for privileged operations
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

    // Extract JWT token (remove "Bearer " prefix)
    const token = authHeader.replace("Bearer ", "");

    // Validate JWT and get user using admin client
    const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(token);
    if (userError || !user) {
      console.error("JWT validation failed:", userError?.message);
      return new Response(
        JSON.stringify({ error: "Invalid or expired session" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const userId = user.id;
    const userEmail = user.email;
    console.log(`🚫 Blocking account for user: ${userId}, email: ${userEmail}`);

    // 1. Add email to blocked_emails table
    if (userEmail) {
      await supabaseAdmin.from("blocked_emails").upsert({
        email: userEmail.toLowerCase(),
        blocked_at: new Date().toISOString(),
        reason: "AI misuse - exceeded failed voice recording attempts"
      });
    }

    // 2. Delete all workout_sets for user's workouts
    const { data: workouts } = await supabaseAdmin
      .from("workouts")
      .select("id")
      .eq("user_id", userId);

    if (workouts) {
      for (const w of workouts) {
        await supabaseAdmin.from("workout_sets").delete().eq("workout_id", w.id);
      }
    }

    // 3. Delete user's workouts
    await supabaseAdmin.from("workouts").delete().eq("user_id", userId);

    // 4. Get user's role to check if coach
    const { data: profile } = await supabaseAdmin
      .from("profiles")
      .select("role")
      .eq("id", userId)
      .maybeSingle();

    // 5. If coach, delete all clients and their data
    if (profile?.role === "coach") {
      const { data: clients } = await supabaseAdmin
        .from("clients")
        .select("id")
        .eq("coach_id", userId);

      if (clients) {
        for (const c of clients) {
          // Delete client's workout sets
          const { data: clientWorkouts } = await supabaseAdmin
            .from("workouts")
            .select("id")
            .eq("client_id", c.id);

          if (clientWorkouts) {
            for (const w of clientWorkouts) {
              await supabaseAdmin.from("workout_sets").delete().eq("workout_id", w.id);
            }
          }
          // Delete client's workouts
          await supabaseAdmin.from("workouts").delete().eq("client_id", c.id);
        }
        // Delete all clients
        await supabaseAdmin.from("clients").delete().eq("coach_id", userId);
      }
    }

    // 6. Delete profile
    await supabaseAdmin.from("profiles").delete().eq("id", userId);

    // 7. Delete user from auth.users
    const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(userId);
    if (deleteError) {
      console.error("Error deleting auth user:", deleteError);
      return new Response(
        JSON.stringify({ error: "Failed to delete auth user", details: deleteError.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`✅ Account blocked and deleted: ${userEmail}`);
    return new Response(
      JSON.stringify({ success: true, message: "Account blocked and deleted" }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Block account error:", error);
    const errorMessage = error instanceof Error ? error.message : "Unknown error";
    return new Response(
      JSON.stringify({ error: "Internal server error", details: errorMessage }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
