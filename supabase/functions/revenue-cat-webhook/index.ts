// ============================================================================
// RevenueCat webhook  ->  updates `subscriptions` + `profiles.is_premium`.
//
// Setup
//   1. RevenueCat dashboard: Project > Integrations > Webhooks
//        URL:  https://<project-ref>.functions.supabase.co/revenue-cat-webhook
//        (NOTE the hyphen before "cat". This folder is named to MATCH the live
//        slug, so `deploy` updates the live function instead of creating a
//        second one beside it. It used to be `revenuecat-webhook`, and a deploy
//        with that name would have left RevenueCat still calling the old
//        function while the code moved on — renewals and cancellations
//        silently drifting. Keep folder and slug identical.)
//        Authorization header: pick a long random secret.
//   2. Store the SAME secret for this function:
//        supabase secrets set REVENUECAT_WEBHOOK_SECRET="<that-secret>"
//      (Optional) override the entitlement that maps to app-wide premium:
//        supabase secrets set PREMIUM_ENTITLEMENT="premium"
//   3. In the Flutter app, tie RevenueCat to the Supabase user:
//        await Purchases.logIn(supabaseUserId);   // app_user_id == auth.uid()
//   4. Deploy:
//        supabase functions deploy revenue-cat-webhook --no-verify-jwt
//      (--no-verify-jwt because RevenueCat calls it, not a logged-in user;
//       we authenticate via the Authorization secret instead.)
// ============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const WEBHOOK_SECRET = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");

// The ONE entitlement whose state maps onto the app-wide `profiles.is_premium`
// flag the RLS gate reads. Only events touching this entitlement flip premium;
// any other entitlement (a future cosmetic, consumable, etc.) records a
// `subscriptions` row but must NOT grant/revoke catalog access.
const PREMIUM_ENTITLEMENT = Deno.env.get("PREMIUM_ENTITLEMENT") ?? "premium";

// Constant-time string comparison so the shared-secret check can't be probed
// byte-by-byte via response-timing. Length is allowed to short-circuit (the
// secret's length is not sensitive); the bytes are compared in constant time.
function secretMatches(provided: string | null): boolean {
  if (!WEBHOOK_SECRET || provided === null) return false;
  const enc = new TextEncoder();
  const a = enc.encode(provided);
  const b = enc.encode(WEBHOOK_SECRET);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

// Event types that, on their own, mean the entitlement is granted right now.
// TRANSFER is handled separately (it moves an entitlement between identities and
// has no single app_user_id), so it is NOT listed here.
const GRANTING_TYPES = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "UNCANCELLATION",
  "NON_RENEWING_PURCHASE",
  "PRODUCT_CHANGE",
  "SUBSCRIPTION_EXTENDED",
]);

// Event types that end access immediately. BILLING_ISSUE is deliberately NOT
// here: the store keeps retrying payment through a grace period and RevenueCat
// carries the grace end in expiration_at_ms, so it takes the expiry branch
// below — an immediate revoke would cut a paying user off mid-grace. (With no
// expiration_at_ms it still resolves to inactive via the GRANTING_TYPES check.)
const REVOKING_TYPES = ["EXPIRATION", "SUBSCRIPTION_PAUSED"];

// Statuses meaning auto-renew is off or at risk, for `subscriptions.will_renew`.
const NON_RENEWING_STATUSES = ["CANCELLATION", "BILLING_ISSUE", ...REVOKING_TYPES];

// Only Supabase auth uids (uuids) can be written to `subscriptions.user_id` /
// `billing_events.user_id` (uuid columns, FK -> auth.users). RevenueCat also
// sends its own identities — `$RCAnonymousID:…` aliases (purchase/restore
// before `Purchases.logIn`, and the transferred_from side of TRANSFER events)
// and arbitrary ids on dashboard test events. Writing those raises a uuid-cast
// error, the function 500s, and RevenueCat retries the same event forever.
// Such identities have no profile to grant anyway, so they are skipped.
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isSupabaseUid = (s: string): boolean => UUID_RE.test(s);

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // --- 1) Authenticate the caller via the shared secret (constant-time) ---
  if (!secretMatches(req.headers.get("Authorization"))) {
    return new Response("Unauthorized", { status: 401 });
  }

  const body = await req.json().catch(() => null);
  const event = body?.event;
  if (!event?.id) return new Response("No event", { status: 400 });

  // Which entitlement(s) this event concerns. An empty list (legacy / single-
  // entitlement projects) is treated as the premium entitlement for back-compat.
  const entitlementIds: string[] = event.entitlement_ids ??
    (event.entitlement_id ? [event.entitlement_id] : []);
  const entitlement: string = entitlementIds[0] ?? PREMIUM_ENTITLEMENT;
  const touchesPremium =
    entitlementIds.length === 0 || entitlementIds.includes(PREMIUM_ENTITLEMENT);

  // --- 2) Idempotency PRE-CHECK: if we've already recorded this event_id, the
  //         state was already applied — ACK without redoing anything. The marker
  //         is written LAST, AFTER the state writes succeed, so a prior delivery
  //         that failed mid-write left NO marker and is correctly retried here
  //         instead of being swallowed as "already processed".
  const { data: seen, error: seenErr } = await supabase
    .from("billing_events")
    .select("event_id")
    .eq("event_id", event.id)
    .maybeSingle();
  if (seenErr) {
    console.error("billing_events lookup failed:", seenErr);
    return new Response("DB error", { status: 500 });
  }
  if (seen) return new Response("Already processed", { status: 200 });

  // Records the raw event as the idempotency marker. Called only after the
  // state mutation has succeeded (or when there's nothing to mutate). A
  // concurrent duplicate delivery may lose the unique-constraint race here;
  // that 23505 is benign because the state writes are idempotent.
  const logEvent = async (markerUserId: string | null) => {
    const insert = (uid: string | null) =>
      supabase.from("billing_events").insert({
        event_id: event.id,
        user_id: uid,
        type: event.type,
        payload: body,
      });
    let { error } = await insert(markerUserId);
    // 23503: marker user was deleted from auth.users — keep the audit row
    // (and the idempotency marker) without the FK.
    if (error?.code === "23503" && markerUserId !== null) {
      ({ error } = await insert(null));
    }
    if (error && error.code !== "23505") {
      console.error("billing_events insert failed:", error);
    }
  };

  const expiresMs: number | undefined = event.expiration_at_ms;
  const expiresAt = expiresMs ? new Date(expiresMs).toISOString() : null;

  // Applies one identity's resulting entitlement state: always upsert the
  // per-entitlement `subscriptions` row, and — ONLY when this event touches the
  // premium entitlement — reflect it onto `profiles.is_premium` (the fast flag
  // the RLS gate reads). Throws on any DB error so the caller can return 500
  // WITHOUT having written the idempotency marker → RevenueCat retries.
  const applyState = async (
    uid: string,
    isActive: boolean,
    statusType: string,
  ) => {
    const { error: subErr } = await supabase.from("subscriptions").upsert({
      user_id: uid,
      rc_app_user_id: uid,
      entitlement,
      product_id: event.product_id ?? null,
      store: event.store ?? null,
      status: statusType,
      is_active: isActive,
      current_period_end: expiresAt,
      will_renew: isActive && !NON_RENEWING_STATUSES.includes(statusType),
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id,entitlement" });
    if (subErr) {
      // 23503: the auth user no longer exists (account deleted via
      // delete-account while the store subscription keeps emitting events).
      // There is nothing left to grant or revoke — ack instead of putting
      // RevenueCat into a permanent 500/retry loop.
      if (subErr.code === "23503") {
        console.warn(`user ${uid} gone (account deleted) — skipping ${statusType}`);
        return;
      }
      throw new Error(`subscriptions upsert: ${subErr.message}`);
    }

    if (touchesPremium) {
      // Write the STORE source only — `apply_store_entitlement` recomputes the
      // effective `profiles.is_premium` from the store + promotional sources, so
      // a store expiry/billing-issue can never revoke a support comp or lifetime
      // grant (and vice versa).
      const { error: rpcErr } = await supabase.rpc("apply_store_entitlement", {
        p_uid: uid,
        p_active: isActive,
        p_until: isActive ? expiresAt : null,
      });
      if (rpcErr) throw new Error(`apply_store_entitlement: ${rpcErr.message}`);
    }
  };

  try {
    if (event.type === "TRANSFER") {
      // A TRANSFER moves the entitlement from one set of identities to another.
      // It carries `transferred_from` / `transferred_to` arrays, NOT a single
      // app_user_id — so we must REVOKE the losers and GRANT the gainers. The
      // old code keyed on app_user_id (undefined here) and left the previous
      // owner premium forever; this is the anon-guest → real-account path.
      // The losing side of a guest→account transfer is usually a
      // `$RCAnonymousID:…` alias — not a Supabase uid, nothing to revoke.
      const from = (event.transferred_from ?? []).filter(isSupabaseUid);
      const to = (event.transferred_to ?? []).filter(isSupabaseUid);
      const toActive = expiresMs ? expiresMs > Date.now() : true;
      for (const uid of from) await applyState(uid, false, "TRANSFER");
      for (const uid of to) await applyState(uid, toActive, "TRANSFER");
      // Mark processed (use the first gaining identity for the audit row, if any).
      await logEvent(to[0] ?? from[0] ?? null);
      return new Response("OK (transfer)", { status: 200 });
    }

    const userId: string | undefined = event.app_user_id; // == auth.uid()
    if (!userId) {
      await logEvent(null);
      return new Response("OK (no app_user_id)", { status: 200 });
    }
    if (!isSupabaseUid(userId)) {
      // `$RCAnonymousID:…` (purchase/restore before Purchases.logIn) or a
      // dashboard test event — no Supabase user to grant. A later TRANSFER
      // moves the entitlement onto the real uid; sync-entitlement also
      // reconciles on app start.
      console.warn(`non-supabase app_user_id ${userId} — recorded, not applied`);
      await logEvent(null);
      return new Response("OK (non-supabase identity)", { status: 200 });
    }

    let isActive: boolean;
    if (REVOKING_TYPES.includes(event.type)) {
      isActive = false;
    } else if (expiresMs) {
      isActive = expiresMs > Date.now(); // CANCELLATION / BILLING_ISSUE stay active to period / grace end
    } else {
      isActive = GRANTING_TYPES.has(event.type); // lifetime / non-renewing
    }

    await applyState(userId, isActive, event.type);
    await logEvent(userId);
    return new Response("OK", { status: 200 });
  } catch (e) {
    // No marker was written → RevenueCat will retry and we'll reprocess. All
    // writes above are idempotent (upsert by key, update by id), so a retry is
    // safe.
    console.error("state write failed:", e);
    return new Response("DB error", { status: 500 });
  }
});
