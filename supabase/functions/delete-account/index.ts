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
    // This bypasses the gateway JWT verification but validates manually
    const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(token);
    if (userError || !user) {
      console.error("JWT validation failed:", userError?.message);
      return new Response(
        JSON.stringify({ error: "Invalid or expired session. Please log in again." }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Security: User can only delete their own account
    const userId = user.id;
    console.log(`🗑️ Deleting account for user: ${userId}`);

    // 1. Delete workout_sets for user's workouts
    const { data: workouts } = await supabaseAdmin
      .from("workouts")
      .select("id")
      .eq("user_id", userId);

    if (workouts) {
      for (const w of workouts) {
        await supabaseAdmin.from("workout_sets").delete().eq("workout_id", w.id);
      }
    }

    // 2. Delete user's workouts
    await supabaseAdmin.from("workouts").delete().eq("user_id", userId);

    // 3. Get user's role to check if coach
    const { data: profile } = await supabaseAdmin
      .from("profiles")
      .select("role")
      .eq("id", userId)
      .single();

    // 4. If coach, delete all clients and their data
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

    // 5. Delete profile
    await supabaseAdmin.from("profiles").delete().eq("id", userId);

    // 6. Delete user from auth.users (requires service role)
    const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(userId);
    if (deleteError) {
      console.error("Error deleting auth user:", deleteError);
      return new Response(
        JSON.stringify({ error: "Failed to delete auth user", details: deleteError.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ success: true, message: "Account deleted successfully" }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Delete account error:", error);
    const errorMessage = error instanceof Error ? error.message : "Unknown error";
    return new Response(
      JSON.stringify({ error: "Internal server error", details: errorMessage }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
