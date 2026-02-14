import { serve } from "std/http/server.ts";
import { createClient } from "@supabase/supabase-js";

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
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Create admin client for privileged operations
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

    // Extract JWT token and validate user
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(token);
    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Verify admin email
    const adminEmail = "seiffn162004@gmail.com";
    if (user.email?.toLowerCase() !== adminEmail) {
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get request body
    const { email, action } = await req.json();

    if (!email && action !== "list") {
      return new Response(
        JSON.stringify({ error: "Bad request" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const targetEmail = action !== "list" ? email.toLowerCase().trim() : "";

    // ACTION: LIST - Get all gifted users
    if (action === "list") {
      const { data: giftedUsers, error: listError } = await supabaseAdmin
        .from("profiles")
        .select("full_name, email, plan, pro_expires_at")
        .not("pro_expires_at", "is", null)
        .order("pro_expires_at", { ascending: false });

      if (listError) {
        console.error("List error:", listError.message);
        return new Response(
          JSON.stringify({ error: "Something went wrong" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({ users: giftedUsers || [] }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ACTION: SEARCH - Find user by email
    if (action === "search") {
      const { data: profile, error: searchError } = await supabaseAdmin
        .from("profiles")
        .select("id, email, full_name, plan, pro_expires_at")
        .ilike("email", targetEmail)
        .maybeSingle();

      if (searchError) {
        console.error("Search error:", searchError.message);
        return new Response(
          JSON.stringify({ error: "Something went wrong" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      if (!profile) {
        return new Response(
          JSON.stringify({ found: false, message: "Could not find email" }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({
          found: true,
          profile: {
            name: profile.full_name,
            email: profile.email,
            plan: profile.plan,
            pro_expires_at: profile.pro_expires_at,
          }
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ACTION: GIFT - Gift pro plan
    if (action === "gift") {
      // Check if user already has active pro
      const { data: existingProfile } = await supabaseAdmin
        .from("profiles")
        .select("plan, pro_expires_at")
        .ilike("email", targetEmail)
        .maybeSingle();

      if (existingProfile?.plan === "pro" && existingProfile?.pro_expires_at) {
        const expiryDate = new Date(existingProfile.pro_expires_at);
        if (expiryDate > new Date()) {
          return new Response(
            JSON.stringify({
              error: `This user already has an active Pro plan (expires ${expiryDate.toISOString().substring(0, 10)})`,
              already_pro: true,
            }),
            { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      }

      // Calculate expiry: 1 month from now
      const expiresAt = new Date();
      expiresAt.setMonth(expiresAt.getMonth() + 1);

      const { error: updateError } = await supabaseAdmin
        .from("profiles")
        .update({
          plan: "pro",
          pro_expires_at: expiresAt.toISOString(),
          pro_gift_message: "You have been gifted Pro for 1 month. Congratulations! 🎉",
        })
        .ilike("email", targetEmail);

      if (updateError) {
        console.error("Gift error:", updateError.message);
        return new Response(
          JSON.stringify({ error: "Something went wrong" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      console.log(`🎁 Pro gifted to ${targetEmail}, expires: ${expiresAt.toISOString()}`);

      return new Response(
        JSON.stringify({
          success: true,
          message: `Pro plan gifted to ${targetEmail}`,
          expires_at: expiresAt.toISOString(),
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ error: "Bad request" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (e) {
    console.error("Gift-pro error:", e);
    return new Response(
      JSON.stringify({ error: "Something went wrong" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
