// ============================================================================
// sync-entitlement  ->  reconciles `profiles.is_premium` with RevenueCat NOW.
//
// Why this exists (alongside the inbound revenue-cat-webhook):
//   The webhook is RevenueCat PUSHING us state. It is async (seconds–minutes
//   late) and a single point of failure — if its URL/secret is misconfigured,
//   NOTHING ever sets `profiles.is_premium`, so every "premium" user keeps
//   getting locked questions/smaczki even though their device shows PRO.
//
//   This function is the app PULLING the truth on demand: the client calls it
//   right after a purchase/restore and on launch, we ask RevenueCat's REST API
//   for this exact identity's entitlements, and write the result synchronously.
//   That closes the post-purchase race AND makes the gate work even if the
//   inbound webhook never lands. The webhook stays as the path for renewals /
//   expiries / cross-device changes the app isn't open to observe.
//
// Setup
//   1. RevenueCat dashboard > API keys: copy the SECRET key (starts `sk_`).
//        supabase secrets set REVENUECAT_REST_API_KEY="sk_..."
//      (Optional, same value as the webhook) the entitlement that == premium:
//        supabase secrets set PREMIUM_ENTITLEMENT="premium"
//   2. Deploy (JWT verification ON — the caller is the logged-in user/guest):
//        supabase functions deploy sync-entitlement
//
// Auth: the client invokes this with its Supabase session, so we read the
// caller from their JWT — they can only ever sync THEIR OWN entitlement. The
// app_user_id in RevenueCat is the same auth.uid() (see Purchases.logIn).
// ============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const PREMIUM_ENTITLEMENT = Deno.env.get("PREMIUM_ENTITLEMENT") ?? "premium";
const RC_API_KEY = Deno.env.get("REVENUECAT_REST_API_KEY");

// How long the RevenueCat lookup may run. The app's session reload awaits this
// function, so a slow store API must degrade to the DB truth instead of pinning
// the client's spinner (observed: 30-40 s RevenueCat responses).
const RC_TIMEOUT_MS = 6_000;

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

// Service-role client for the write (bypasses RLS; profiles has no write policy).
const admin = createClient(
  SUPABASE_URL,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// The DB-side EFFECTIVE flag, unreconciled — the answer whenever the store
// side can't be asked (no API key, RevenueCat down or over RC_TIMEOUT_MS).
// Promotional grants and store users already reflected by the webhook stay
// valid, and the client treats `reconciled: false` results as authoritative
// for the DB side while still consulting the on-device receipt.
const dbTruth = async (uid: string, why: string) => {
  console.warn(`store side unavailable (${why}) — returning DB truth without reconciliation`);
  const { data, error } = await admin
    .from("profiles")
    .select("is_premium, premium_until")
    .eq("id", uid)
    .maybeSingle();
  if (error) {
    console.error("profiles read failed:", error);
    return json(500, { error: "db_error" });
  }
  return json(200, {
    is_premium: data?.is_premium ?? false,
    premium_until: data?.premium_until ?? null,
    reconciled: false,
  });
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  // --- Identify the caller from their Supabase JWT (never trust a body uid) ---
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json(401, { error: "unauthorized" });

  const userClient = createClient(
    SUPABASE_URL,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user }, error: userErr } = await userClient.auth.getUser();
  if (userErr || !user) return json(401, { error: "unauthorized" });

  // The STORE side being unreachable must NOT break premium (or hold it up) —
  // every failure below degrades to the DB truth instead of an error status.
  if (!RC_API_KEY) return dbTruth(user.id, "REVENUECAT_REST_API_KEY not set");

  // --- Ask RevenueCat for THIS identity's entitlements ---
  // app_user_id == auth.uid() because the app calls Purchases.logIn(uid).
  let isActive = false;
  let expiresAt: string | null = null;
  try {
    const rcRes = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(user.id)}`,
      {
        headers: { Authorization: `Bearer ${RC_API_KEY}` },
        signal: AbortSignal.timeout(RC_TIMEOUT_MS),
      },
    );

    if (rcRes.ok) {
      const payload = await rcRes.json();
      const ent = payload?.subscriber?.entitlements?.[PREMIUM_ENTITLEMENT];
      if (ent) {
        // expires_date null = lifetime/non-expiring; otherwise active until then.
        const exp = (ent.expires_date as string | null) ?? null;
        isActive = exp === null || new Date(exp).getTime() > Date.now();
        expiresAt = isActive ? exp : null;
      }
    } else if (rcRes.status === 404) {
      // Unknown subscriber = never purchased on this identity → not premium.
      isActive = false;
    } else {
      console.error("RevenueCat API error", rcRes.status, await rcRes.text());
      return dbTruth(user.id, `RevenueCat responded ${rcRes.status}`);
    }
  } catch (e) {
    // Network failure or the AbortSignal timeout firing.
    console.error("RevenueCat fetch failed:", e);
    return dbTruth(user.id, "RevenueCat unreachable or over the timeout");
  }

  // --- Fold the STORE result into the DB via the source-aware reconciler. It
  //     writes ONLY the store source (leaving promotional/comp grants intact) and
  //     returns the resulting EFFECTIVE premium the gate enforces — which is what
  //     we hand back to the client, not the raw store value. ---
  const { data: effective, error: rpcErr } = await admin.rpc(
    "apply_store_entitlement",
    { p_uid: user.id, p_active: isActive, p_until: isActive ? expiresAt : null },
  );
  if (rpcErr) {
    console.error("apply_store_entitlement failed:", rpcErr);
    return json(500, { error: "db_error" });
  }

  return json(200, {
    is_premium: effective === true,
    premium_until: isActive ? expiresAt : null,
    reconciled: true,
  });
});
