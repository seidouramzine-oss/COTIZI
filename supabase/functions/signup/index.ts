// Inscription COTIZI : numéro de téléphone + mot de passe.
// Le numéro sert d'identifiant ; on crée un compte Supabase dont l'email
// technique est dérivé du numéro (aucun email n'est jamais envoyé).
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function phoneToEmail(phone: string) {
  return `${phone.replace("+", "")}@phone.cotizi.app`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée" }, 405);

  let body: { phone?: unknown; password?: unknown; full_name?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Requête invalide" }, 400);
  }

  const phone = typeof body.phone === "string" ? body.phone.trim() : "";
  const password = typeof body.password === "string" ? body.password : "";
  const fullName = typeof body.full_name === "string" ? body.full_name.trim() : "";

  if (!/^\+[1-9]\d{7,14}$/.test(phone)) {
    return json({ error: "Numéro de téléphone invalide" }, 400);
  }
  if (password.length < 6) {
    return json({ error: "Le mot de passe doit contenir au moins 6 caractères" }, 400);
  }
  if (fullName.length < 2 || fullName.length > 60) {
    return json({ error: "Indiquez votre nom (2 à 60 caractères)" }, 400);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { error } = await admin.auth.admin.createUser({
    email: phoneToEmail(phone),
    password,
    email_confirm: true,
    user_metadata: { phone, full_name: fullName },
    app_metadata: { signup: "cotizi" },
  });

  if (error) {
    const msg = error.message.toLowerCase();
    if (msg.includes("already") || msg.includes("exists") || msg.includes("registered")) {
      return json({ error: "Ce numéro est déjà inscrit. Connectez-vous." }, 409);
    }
    console.error("createUser failed", error);
    return json({ error: "Inscription impossible pour le moment" }, 500);
  }

  return json({ ok: true });
});
