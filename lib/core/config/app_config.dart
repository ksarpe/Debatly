/// Centralised configuration / secrets.
///
/// Values are read from `--dart-define` at build time so keys never get
/// committed. Run with, e.g.:
///
/// ```
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=... \
///   --dart-define=REVENUECAT_API_KEY=...
/// ```
class AppConfig {
  AppConfig._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Google "Web" OAuth client id. Passed as serverClientId for native Google
  /// sign-in so Google returns an ID token Supabase can verify.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  static const String revenueCatApiKey = String.fromEnvironment(
    'REVENUECAT_API_KEY',
    defaultValue: '',
  );

  /// Public URL of the privacy policy, opened from the Privacy & data screen.
  /// Defaults to the live page on the marketing site (a public, non-secret URL,
  /// so it's baked in to guarantee the legal link works in every build); still
  /// overridable via `--dart-define=PRIVACY_POLICY_URL=...`.
  static const String privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: 'https://debatly.app/privacy',
  );

  /// Public URL of the terms of service, opened from the Privacy & data screen.
  /// See [privacyPolicyUrl] for the baked-in/overridable rationale.
  static const String termsOfServiceUrl = String.fromEnvironment(
    'TERMS_OF_SERVICE_URL',
    defaultValue: 'https://debatly.app/terms',
  );

  /// Public URL where users can request account + data deletion from the web,
  /// without the app. Required by the Google Play Data safety form (the in-app
  /// deletion in Settings covers the on-device path). Surfaced on the Privacy &
  /// data screen as a fallback to the in-app flow.
  static const String deleteAccountUrl = String.fromEnvironment(
    'DELETE_ACCOUNT_URL',
    defaultValue: 'https://debatly.app/delete-account',
  );

  /// Landing page the confirmation link in the sign-up email redirects to once
  /// Supabase has verified the address. Passed as `emailRedirectTo` when the
  /// account is created; without it the user lands on the project's bare Site
  /// URL. See [privacyPolicyUrl] for the baked-in/overridable rationale.
  static const String emailConfirmedUrl = String.fromEnvironment(
    'EMAIL_CONFIRMED_URL',
    defaultValue: 'https://debatly.app/email-potwierdzony',
  );

  /// Where the password-reset mail sends the user, so the new password can be
  /// typed IN THE APP.
  ///
  /// This is a WEB page that forwards into the app, not the `debatly://` deep
  /// link itself. Both end in the same place on a phone, but only this one
  /// survives being opened somewhere else: a desktop browser handed a
  /// `debatly://` redirect shows a protocol error, and our domain is never
  /// reached, so nothing can explain what happened. The bridge page
  /// ([site/reset-hasla](../../../site/README.md)) hops into the app on a phone
  /// and explains itself anywhere else.
  ///
  /// The reset can only ever be completed on the install that ASKED for it: the
  /// flow is PKCE, and the `code_verifier` that redeems the recovery code lives
  /// in that app's storage. No web page can finish it — the bridge exists to
  /// route people to the right device, not to shortcut them past it.
  ///
  /// Once the link is back in the app, `supabase_flutter` picks it up on its own
  /// (it listens for incoming links and hands anything carrying a `code` to
  /// `getSessionFromUrl`), which emits `AuthChangeEvent.passwordRecovery` — see
  /// [PasswordRecoveryListener].
  ///
  /// DEPLOY ORDER MATTERS. This URL must be live AND allow-listed in the
  /// Supabase dashboard (Authentication → URL Configuration → Redirect URLs)
  /// BEFORE a build carrying it ships, or every reset link lands on a 404 and
  /// email/password accounts become unrecoverable again. The escape hatch is
  /// `--dart-define=PASSWORD_RESET_REDIRECT_URL=debatly://reset-password`,
  /// which restores the app-only behaviour without a code change.
  ///
  /// The `debatly://` scheme stays registered natively either way
  /// (`AndroidManifest.xml` intent-filter, `CFBundleURLSchemes` in
  /// `Info.plist`) — the bridge page forwards into it.
  static const String passwordResetRedirectUrl = String.fromEnvironment(
    'PASSWORD_RESET_REDIRECT_URL',
    defaultValue: 'https://debatly.app/reset-hasla',
  );

  /// Sentry DSN (the project's ingest URL, found in Sentry under
  /// `Settings → Projects → your project → Client Keys (DSN)`). When empty, Sentry is
  /// initialised in a disabled state so the app still runs against mock data with
  /// no error reporting — see [Monitoring]. Not a secret in the password sense
  /// (it only allows sending events), but kept out of git like the other keys.
  static const String sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue: '',
  );

  /// Logical deployment name shown on every Sentry event, so you can filter
  /// dev/staging noise away from real user crashes. Defaults are resolved in
  /// [Monitoring] from the build mode when this is left blank.
  static const String sentryEnvironment = String.fromEnvironment(
    'SENTRY_ENVIRONMENT',
    defaultValue: '',
  );

  /// Fraction of transactions sampled for performance tracing (0.0–1.0). The
  /// Developer plan has a monthly performance-unit budget, so we sample rather
  /// than trace every navigation. Passed as a string so it fits the dart-define
  /// model; falls back to a conservative 20%.
  static const String _sentryTracesSampleRateRaw = String.fromEnvironment(
    'SENTRY_TRACES_SAMPLE_RATE',
    defaultValue: '0.2',
  );

  static double get sentryTracesSampleRate =>
      double.tryParse(_sentryTracesSampleRateRaw)?.clamp(0.0, 1.0) ?? 0.2;

  static bool get hasSentry => sentryDsn.isNotEmpty;

  static bool get hasSupabaseCredentials =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get hasGoogleSignIn => googleServerClientId.isNotEmpty;

  static bool get hasPrivacyPolicy => privacyPolicyUrl.isNotEmpty;

  static bool get hasTermsOfService => termsOfServiceUrl.isNotEmpty;

  static bool get hasDeleteAccountUrl => deleteAccountUrl.isNotEmpty;
}
