// ============================================================================
// Send Email Hook  ->  renders the auth email in the USER'S language and sends
// it through Resend, replacing GoTrue's own mailer.
//
// WHY THIS EXISTS
//   GoTrue stores exactly ONE template per action, with no localisation, while
//   Debatly ships PL + EN (kSupportedLocales in lib/core/locale/app_locale.dart).
//   With the dashboard templates a Polish user can get an English password
//   reset, or the other way round. This hook takes the send over: GoTrue calls
//   it instead of mailing, hands us the user plus the token, and we decide the
//   language, the wording and the transport.
//
// SETUP
//   1. Verify the sending domain at Resend (SPF + DKIM DNS records) and take an
//      API key.
//   2. Secrets — Dashboard > Project Settings > Edge Functions > Secrets, or
//      with the CLI (which the Windows dev box does not have installed):
//        RESEND_API_KEY           re_...
//        AUTH_EMAIL_FROM          Debatly <noreply@debatly.pl>
//        SEND_EMAIL_HOOK_SECRET   v1,whsec_...   (generated in step 4)
//        DEFAULT_EMAIL_LOCALE     pl             (optional, defaults to pl)
//   3. Deploy — no JWT, GoTrue calls this with a webhook signature, not a user
//      token:
//        supabase functions deploy send-auth-email --no-verify-jwt
//   4. Dashboard > Authentication > Hooks > Send Email: enable, point it at
//      https://<project-ref>.supabase.co/functions/v1/send-auth-email and copy
//      the generated secret into SEND_EMAIL_HOOK_SECRET.
//
//   Custom SMTP in the dashboard becomes irrelevant once this is on — the mail
//   no longer goes through GoTrue's mailer at all. The HTML templates under
//   supabase/templates/ stay as the fallback for when the hook is disabled.
//
// FAILURE POLICY
//   A non-2xx here makes the originating auth call (signUp / recover / update)
//   fail for the user. That is the correct trade: a silent 200 with no mail
//   sent leaves someone waiting forever for a reset link that never existed.
//   The one thing that must NEVER fail the send is the language lookup — it
//   degrades to the default locale instead.
// ============================================================================

import { Webhook } from "npm:standardwebhooks@1.0.0";
import { createClient } from "npm:@supabase/supabase-js@2";

import {
  type EmailKind,
  type Locale,
  renderEmail,
  SUPPORTED_LOCALES,
} from "./emails.ts";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const AUTH_EMAIL_FROM = Deno.env.get("AUTH_EMAIL_FROM");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;

// The hook secret arrives as `v1,whsec_<base64>`; standardwebhooks wants the
// bare base64 part.
const HOOK_SECRET = Deno.env.get("SEND_EMAIL_HOOK_SECRET")?.replace(
  "v1,whsec_",
  "",
);

// Polish-first app, so an unknown language lands on Polish rather than English.
const DEFAULT_LOCALE =
  (Deno.env.get("DEFAULT_EMAIL_LOCALE") as Locale | undefined) ?? "pl";

const supabase = createClient(
  SUPABASE_URL,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

/** What GoTrue POSTs us. Only the fields we actually read are typed. */
interface HookPayload {
  user: {
    id: string;
    email?: string | null;
    new_email?: string | null;
    user_metadata?: Record<string, unknown> | null;
  };
  email_data: {
    token_hash: string;
    token_hash_new?: string | null;
    redirect_to?: string | null;
    email_action_type: string;
  };
}

/** Maps GoTrue's action onto one of our templates. */
function kindOf(action: string): EmailKind {
  if (action === "signup") return "signup";
  if (action === "recovery") return "recovery";
  if (action.startsWith("email_change")) return "email_change";
  // magiclink / invite / reauthentication — the app calls none of these today
  // (see supabase/templates/README.md), but a hook that 500s on an action it
  // doesn't recognise would take the whole auth call down with it.
  return "generic";
}

/**
 * Which address this particular mail goes to.
 *
 * A secure email change fans out into two mails: `email_change_current` asks
 * the OLD address to approve, `email_change_new` asks the NEW one to confirm.
 * Sending both to the same box would let a hijacked session move the account
 * without the original owner ever seeing it.
 */
function recipientOf(payload: HookPayload): string | null {
  const { user, email_data } = payload;
  if (email_data.email_action_type === "email_change_current") {
    return user.email ?? null;
  }
  if (email_data.email_action_type.startsWith("email_change")) {
    return user.new_email ?? user.email ?? null;
  }
  return user.email ?? null;
}

/**
 * Builds the link the button points at.
 *
 * `redirect_to` is client-supplied, so it is URL-encoded here (and HTML-escaped
 * again at render time). An empty one is omitted entirely, which makes GoTrue
 * fall back to the project's Site URL.
 */
function actionUrlOf(payload: HookPayload): string {
  const { email_data } = payload;
  const action = email_data.email_action_type;

  // The new-address half of an email change is confirmed with its own token;
  // both halves are verified under the `email_change` type.
  const targetsNewAddress = action === "email_change" ||
    action === "email_change_new";
  const token = targetsNewAddress && email_data.token_hash_new
    ? email_data.token_hash_new
    : email_data.token_hash;
  const verifyType = action.startsWith("email_change") ? "email_change" : action;

  const url = new URL(`${SUPABASE_URL}/auth/v1/verify`);
  url.searchParams.set("token", token);
  url.searchParams.set("type", verifyType);
  if (email_data.redirect_to) {
    url.searchParams.set("redirect_to", email_data.redirect_to);
  }
  return url.toString();
}

function normaliseLocale(value: unknown): Locale | null {
  if (typeof value !== "string") return null;
  const code = value.trim().slice(0, 2).toLowerCase();
  return (SUPPORTED_LOCALES as readonly string[]).includes(code)
    ? (code as Locale)
    : null;
}

/**
 * Resolves the language, freshest source first:
 *   1. `profiles.locale` — rewritten whenever the user changes the app language;
 *   2. `user_metadata.locale` — written at registration, so it covers the signup
 *      mail even if the profile row and this hook race;
 *   3. the configured default.
 *
 * Deliberately never throws: an unreachable database means a mail in the wrong
 * language, which beats no mail at all.
 */
async function resolveLocale(user: HookPayload["user"]): Promise<Locale> {
  try {
    const { data, error } = await supabase
      .from("profiles")
      .select("locale")
      .eq("id", user.id)
      .maybeSingle();
    if (error) {
      console.error("profiles.locale lookup failed:", error.message);
    } else {
      const fromProfile = normaliseLocale(data?.locale);
      if (fromProfile) return fromProfile;
    }
  } catch (e) {
    console.error("profiles.locale lookup threw:", e);
  }

  return normaliseLocale(user.user_metadata?.locale) ?? DEFAULT_LOCALE;
}

function fail(status: number, message: string): Response {
  console.error(message);
  return new Response(
    JSON.stringify({ error: { http_code: status, message } }),
    { status, headers: { "Content-Type": "application/json" } },
  );
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  if (!HOOK_SECRET || !RESEND_API_KEY || !AUTH_EMAIL_FROM) {
    return fail(500, "send-auth-email is not configured (missing secrets)");
  }

  // --- 1) Authenticate GoTrue via the standard-webhooks signature ------------
  // Without this anyone who learns the URL could make us mail arbitrary
  // addresses a link built from a token they supply.
  const raw = await req.text();
  let payload: HookPayload;
  try {
    const headers = Object.fromEntries(req.headers);
    payload = new Webhook(HOOK_SECRET).verify(raw, headers) as HookPayload;
  } catch (e) {
    return fail(401, `webhook signature verification failed: ${e}`);
  }

  // --- 2) Work out who, what and in which language --------------------------
  const recipient = recipientOf(payload);
  if (!recipient) {
    return fail(400, "hook payload carries no recipient address");
  }

  const kind = kindOf(payload.email_data.email_action_type);
  const locale = await resolveLocale(payload.user);
  const { subject, html, text } = renderEmail(
    kind,
    locale,
    recipient,
    actionUrlOf(payload),
  );

  // --- 3) Hand it to Resend -------------------------------------------------
  let response: Response;
  try {
    response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: AUTH_EMAIL_FROM,
        to: [recipient],
        subject,
        html,
        text,
      }),
    });
  } catch (e) {
    return fail(502, `Resend unreachable: ${e}`);
  }

  if (!response.ok) {
    const detail = await response.text().catch(() => "<no body>");
    return fail(502, `Resend rejected the message (${response.status}): ${detail}`);
  }

  // Log the ACTION and the language, never the address — these logs are not the
  // place to accumulate a list of who uses the app.
  console.log(`sent ${payload.email_data.email_action_type} in ${locale}`);
  return new Response("{}", {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
