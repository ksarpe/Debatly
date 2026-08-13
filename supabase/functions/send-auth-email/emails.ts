// ============================================================================
// Copy + HTML layout for the auth emails, in every language the app ships.
//
// Kept apart from index.ts so the wording can be edited without touching the
// webhook/verification path, and so the layout is written ONCE instead of being
// copy-pasted per action per language (3 actions x 2 languages = 6 templates
// that would otherwise drift apart).
//
// The markup rules are the email-client ones, not the browser ones:
//   * layout on <table>, never flex/grid;
//   * every style inline — Gmail strips <style> blocks;
//   * the CTA is a <td bgcolor> wrapping an <a>, so Outlook's Word renderer
//     keeps the orange even though it drops the border-radius;
//   * colours stated explicitly on each element, no prefers-color-scheme —
//     Gmail and Outlook ignore it and the half-applied result looks worse than
//     a deliberately light email.
// ============================================================================

export const SUPPORTED_LOCALES = ["pl", "en"] as const;
export type Locale = (typeof SUPPORTED_LOCALES)[number];

/** Every action GoTrue can ask us to send, mapped onto a template. */
export type EmailKind = "signup" | "recovery" | "email_change" | "generic";

/** Palette lifted from lib/core/theme/app_theme.dart so the mails match the app. */
const C = {
  page: "#F6F6F9",
  card: "#FFFFFF",
  border: "#E2E2EA",
  header: "#000000",
  spark: "#F97316",
  ink: "#15161A",
  subtle: "#5E5E66",
  muted: "#8A8A8A",
  footer: "#A0A0A8",
  noticeBg: "#FFF7ED",
  noticeBorder: "#FDD9B5",
  noticeInk: "#7C4A17",
} as const;

const FONT =
  "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif";

interface Copy {
  subject: string;
  preheader: string;
  heading: string;
  /** `{email}` is replaced with the (escaped) recipient address. */
  intro: string;
  cta: string;
  /** Optional highlighted box — used for the reset link's expiry warning. */
  notice?: string;
  fallback: string;
  ignore: string;
  footer: string;
  noReply: string;
}

const COPY: Record<Locale, Record<EmailKind, Copy>> = {
  pl: {
    signup: {
      subject: "Potwierdź adres e-mail",
      preheader: "Jeden klik i Twoje konto Debatly jest gotowe.",
      heading: "Potwierdź swój adres e-mail",
      intro:
        "Cześć! Kliknij poniższy przycisk, żeby potwierdzić adres <strong style=\"color:{ink};font-weight:600;\">{email}</strong> i dokończyć zakładanie konta w Debatly.",
      cta: "Potwierdź adres e-mail",
      fallback: "Przycisk nie działa? Wklej ten adres do przeglądarki:",
      ignore: "Jeśli to nie Ty zakładałeś konto — po prostu zignoruj tę wiadomość.",
      footer: "Debatly — TAK czy NIE?",
      noReply: "Wiadomość wysłana automatycznie, prosimy na nią nie odpowiadać.",
    },
    recovery: {
      subject: "Reset hasła w Debatly",
      preheader: "Ustaw nowe hasło do Debatly — link jest ważny przez godzinę.",
      heading: "Ustaw nowe hasło",
      intro:
        "Ktoś poprosił o zresetowanie hasła do konta <strong style=\"color:{ink};font-weight:600;\">{email}</strong>. Kliknij przycisk, żeby ustawić nowe.",
      cta: "Ustaw nowe hasło",
      notice:
        "Link jest ważny <strong style=\"font-weight:600;\">przez 1 godzinę</strong> i można go użyć tylko raz. Jeśli to nie Ty prosiłeś o reset — zignoruj tę wiadomość, hasło pozostanie bez zmian.",
      fallback: "Przycisk nie działa? Wklej ten adres do przeglądarki:",
      ignore: "",
      footer: "Debatly — TAK czy NIE?",
      noReply: "Wiadomość wysłana automatycznie, prosimy na nią nie odpowiadać.",
    },
    email_change: {
      subject: "Potwierdź nowy adres e-mail",
      preheader: "Potwierdź ten adres, żeby przypisać go do konta Debatly.",
      heading: "Potwierdź nowy adres e-mail",
      intro:
        "Kliknij przycisk, żeby przypisać adres <strong style=\"color:{ink};font-weight:600;\">{email}</strong> do swojego konta Debatly. Twoje serie, głosy i odkryte smaczki zostają — zmienia się tylko adres, którym się logujesz.",
      cta: "Potwierdź adres e-mail",
      fallback: "Przycisk nie działa? Wklej ten adres do przeglądarki:",
      ignore: "Jeśli to nie Ty — zignoruj tę wiadomość, nic się nie zmieni.",
      footer: "Debatly — TAK czy NIE?",
      noReply: "Wiadomość wysłana automatycznie, prosimy na nią nie odpowiadać.",
    },
    generic: {
      subject: "Potwierdź działanie w Debatly",
      preheader: "Potwierdź działanie na swoim koncie Debatly.",
      heading: "Potwierdź działanie",
      intro:
        "Kliknij poniższy przycisk, żeby potwierdzić działanie na koncie <strong style=\"color:{ink};font-weight:600;\">{email}</strong>.",
      cta: "Potwierdź",
      fallback: "Przycisk nie działa? Wklej ten adres do przeglądarki:",
      ignore: "Jeśli to nie Ty — zignoruj tę wiadomość, nic się nie zmieni.",
      footer: "Debatly — TAK czy NIE?",
      noReply: "Wiadomość wysłana automatycznie, prosimy na nią nie odpowiadać.",
    },
  },
  en: {
    signup: {
      subject: "Confirm your email address",
      preheader: "One click and your Debatly account is ready.",
      heading: "Confirm your email address",
      intro:
        "Hi! Tap the button below to confirm <strong style=\"color:{ink};font-weight:600;\">{email}</strong> and finish setting up your Debatly account.",
      cta: "Confirm email address",
      fallback: "Button not working? Paste this address into your browser:",
      ignore: "Didn't sign up? Just ignore this message.",
      footer: "Debatly — YES or NO?",
      noReply: "This message was sent automatically; please don't reply to it.",
    },
    recovery: {
      subject: "Reset your Debatly password",
      preheader: "Set a new Debatly password — the link is valid for an hour.",
      heading: "Set a new password",
      intro:
        "Someone asked to reset the password for <strong style=\"color:{ink};font-weight:600;\">{email}</strong>. Tap the button to set a new one.",
      cta: "Set a new password",
      notice:
        "The link is valid for <strong style=\"font-weight:600;\">1 hour</strong> and works only once. If you didn't ask for a reset, ignore this email — your password stays as it is.",
      fallback: "Button not working? Paste this address into your browser:",
      ignore: "",
      footer: "Debatly — YES or NO?",
      noReply: "This message was sent automatically; please don't reply to it.",
    },
    email_change: {
      subject: "Confirm your new email address",
      preheader: "Confirm this address to attach it to your Debatly account.",
      heading: "Confirm your new email address",
      intro:
        "Tap the button to attach <strong style=\"color:{ink};font-weight:600;\">{email}</strong> to your Debatly account. Your streak, votes and unlocked takes stay exactly where they are — only the address you sign in with changes.",
      cta: "Confirm email address",
      fallback: "Button not working? Paste this address into your browser:",
      ignore: "Not you? Ignore this email and nothing will change.",
      footer: "Debatly — YES or NO?",
      noReply: "This message was sent automatically; please don't reply to it.",
    },
    generic: {
      subject: "Confirm an action on your Debatly account",
      preheader: "Confirm an action on your Debatly account.",
      heading: "Confirm this action",
      intro:
        "Tap the button below to confirm an action on the account <strong style=\"color:{ink};font-weight:600;\">{email}</strong>.",
      cta: "Confirm",
      fallback: "Button not working? Paste this address into your browser:",
      ignore: "Not you? Ignore this email and nothing will change.",
      footer: "Debatly — YES or NO?",
      noReply: "This message was sent automatically; please don't reply to it.",
    },
  },
};

/**
 * Escapes text destined for HTML. The recipient address is attacker-chosen
 * (anyone can sign up with `"><script>…` as a local part on a domain they own),
 * and the action URL carries a client-supplied `redirect_to`, so BOTH are
 * escaped before they reach the markup — the URL additionally as an attribute
 * value, where a bare `"` would break out of the href.
 */
function esc(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/** Strips tags for the text/plain alternative, and unescapes the entities. */
function plain(html: string): string {
  return html
    .replace(/<[^>]+>/g, "")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

export interface RenderedEmail {
  subject: string;
  html: string;
  text: string;
}

/**
 * Builds the full message for one action in one language.
 *
 * A `text` alternative is always produced alongside the HTML: a message with no
 * plaintext part scores worse with spam filters, which matters a lot when the
 * whole point of this function is that password resets actually arrive.
 */
export function renderEmail(
  kind: EmailKind,
  locale: Locale,
  recipient: string,
  actionUrl: string,
): RenderedEmail {
  const copy = COPY[locale][kind];
  const email = esc(recipient);
  const url = esc(actionUrl);
  const intro = copy.intro
    .replace("{email}", email)
    .replace("{ink}", C.ink);

  const noticeBlock = copy.notice
    ? `
            <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:0 0 24px 0;background-color:${C.noticeBg};border:1px solid ${C.noticeBorder};border-radius:12px;">
              <tr>
                <td style="padding:14px 16px;font-family:${FONT};font-size:13px;line-height:20px;color:${C.noticeInk};">${copy.notice}</td>
              </tr>
            </table>`
    : "";

  const ignoreBlock = copy.ignore
    ? `
            <p style="margin:0 0 24px 0;font-size:13px;line-height:20px;color:${C.muted};">${copy.ignore}</p>`
    : "";

  const html = `<div style="display:none;max-height:0;overflow:hidden;opacity:0;mso-hide:all;">${copy.preheader}</div>
<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:${C.page};margin:0;padding:32px 12px;">
  <tr>
    <td align="center">
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="560" style="width:100%;max-width:560px;background-color:${C.card};border:1px solid ${C.border};border-radius:16px;overflow:hidden;">
        <tr>
          <td style="background-color:${C.header};padding:26px 32px;">
            <span style="font-family:${FONT};font-size:22px;font-weight:700;letter-spacing:-0.5px;color:#FFFFFF;">Debatly<span style="color:${C.spark};">.</span></span>
          </td>
        </tr>
        <tr>
          <td style="padding:32px 32px 8px 32px;font-family:${FONT};">
            <h1 style="margin:0 0 12px 0;font-size:21px;line-height:28px;font-weight:700;color:${C.ink};">${copy.heading}</h1>
            <p style="margin:0 0 24px 0;font-size:15px;line-height:24px;color:${C.subtle};">${intro}</p>

            <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 24px 0;">
              <tr>
                <td bgcolor="${C.spark}" style="border-radius:12px;">
                  <a href="${url}" target="_blank" style="display:inline-block;padding:15px 30px;font-family:${FONT};font-size:16px;font-weight:600;line-height:20px;color:#FFFFFF;text-decoration:none;border-radius:12px;">${copy.cta}</a>
                </td>
              </tr>
            </table>${noticeBlock}

            <p style="margin:0 0 24px 0;font-size:13px;line-height:20px;color:${C.muted};">${copy.fallback}<br><a href="${url}" target="_blank" style="color:${C.spark};text-decoration:underline;word-break:break-all;">${url}</a></p>${ignoreBlock}
          </td>
        </tr>
        <tr>
          <td style="padding:0 32px 28px 32px;font-family:${FONT};">
            <div style="height:1px;line-height:1px;font-size:0;background-color:${C.border};">&nbsp;</div>
            <p style="margin:16px 0 0 0;font-size:12px;line-height:18px;color:${C.footer};">${copy.footer}<br>${copy.noReply}</p>
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>`;

  const text = [
    copy.heading,
    "",
    plain(intro),
    "",
    actionUrl,
    "",
    copy.notice ? plain(copy.notice) : "",
    copy.ignore,
    "",
    "—",
    copy.footer,
    copy.noReply,
  ]
    .filter((line, i, all) => !(line === "" && all[i - 1] === ""))
    .join("\n");

  return { subject: copy.subject, html, text };
}
