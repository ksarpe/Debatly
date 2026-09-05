import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/feedback/app_toast.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../services/purchases_service.dart';
import '../../../services/supabase_service.dart';
import '../providers/session_providers.dart';
import '../providers/stats_providers.dart';
import '../widgets/auth_brand_glyph.dart';
import '../widgets/auth_circle_icon_button.dart';
import '../widgets/auth_error_text.dart';
import '../widgets/auth_field.dart';
import '../widgets/auth_legal_consent_text.dart';
import '../widgets/auth_notice.dart';
import '../widgets/auth_or_divider.dart';
import '../widgets/auth_primary_button.dart';
import '../widgets/auth_social_button.dart';

/// Presents the account sheet — "Continue with Apple / Google" — as a modal
/// bottom sheet that slides up from the bottom of the screen.
///
/// Social-only since 2026-09-05. One button covers both "create" and "sign
/// back in": for a guest the picked identity is linked onto their anonymous
/// user IN PLACE (same UUID — streak, votes, favourites and PRO all kept), and
/// only when that identity already belongs to another account does the flow
/// switch to it, after asking (see `SupabaseService.signInWithIdTokenOn`). So
/// there is no register/sign-in split for the UI to get wrong any more — every
/// entry point (the save-PRO and secure-streak prompts, Settings, the paywall
/// footer, the restore chooser) opens the same sheet.
///
/// The email/password form is LEGACY: it only signs in, never registers, and
/// hides behind the "I have a password" link. It exists for the accounts made
/// before the switch — the PRO buyers among them have no other key to their
/// history — and goes once they have linked a social identity from Settings or
/// gone quiet (stage 2, see CLAUDE.md).
Future<void> showAuthSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.cardSurface,
    isScrollControlled: true,
    // Tablets: hug the form (the card inside caps itself the same) rather
    // than framing a wide band of empty sheet around it.
    constraints: const BoxConstraints(maxWidth: kFormMaxWidth),
    showDragHandle: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _AuthCard(),
  );
}

/// Full-screen fallback so the auth flow can still be pushed as a route (and
/// rendered in isolation by tests). Reuses the exact same card.
class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: const SafeArea(child: Center(child: _AuthCard())),
    );
  }
}

class _AuthCard extends ConsumerStatefulWidget {
  const _AuthCard();

  @override
  ConsumerState<_AuthCard> createState() => _AuthCardState();
}

class _AuthCardState extends ConsumerState<_AuthCard> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSubmitting = false;
  bool _obscurePassword = true;

  /// Whether the legacy email/password form is unfolded. Off by default: the
  /// sheet opens on the social buttons alone, and the form is one deliberate
  /// tap away for the accounts that still need it.
  bool _showPasswordForm = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isConfigured = SupabaseService.isInitialised;

    final canUseGoogle = isConfigured && AppConfig.hasGoogleSignIn;
    // Apple platforms get BOTH social buttons, Apple first; Android gets Google
    // alone. See `_buildSocialButtons` for why.
    final isApplePlatform =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;

    // Let the sheet grow to fit its content — short forms stay compact, longer
    // ones make it taller — but never past the screen (minus the status bar) so
    // it can't overflow; scrolling is the fallback. The keyboard inset is
    // handled by the spacer below the scroll view, not here.
    final maxHeight = media.size.height - media.padding.top - 24;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: kFormMaxWidth,
        maxHeight: maxHeight,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                // `useSafeArea: true` on the sheet is `SafeArea(bottom: false)`
                // — Flutter lets the sheet background reach the bottom edge and
                // leaves the bottom system inset to us. `media.padding.bottom`
                // (the gesture nav-bar height) keeps the last controls off the
                // navigation bar on edge-to-edge devices. It collapses to 0
                // while the keyboard is up, where the spacer below the scroll
                // view takes over.
                padding: EdgeInsets.fromLTRB(
                  20,
                  4,
                  20,
                  24 + media.padding.bottom,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCloseRow(context),
                      _buildBrandHeader(
                        context,
                        isApplePlatform: isApplePlatform,
                      ),
                      const SizedBox(height: 22),
                      if (!isConfigured) ...[
                        AuthNotice(
                          icon: Icons.info_outline,
                          text: context.l10n.authMissingSupabaseConfig,
                        ),
                        const SizedBox(height: 14),
                      ] else if (!isApplePlatform &&
                          !AppConfig.hasGoogleSignIn) ...[
                        // Android only: there Google is the sole social option,
                        // so a missing client id leaves a dead button and has to
                        // be explained. On Apple platforms the same build still
                        // has Sign in with Apple, and the Google button simply
                        // isn't rendered — nothing to warn about.
                        AuthNotice(
                          icon: Icons.info_outline,
                          text: context.l10n.authMissingGoogleConfig,
                        ),
                        const SizedBox(height: 14),
                      ],
                      ..._buildSocialButtons(
                        isApplePlatform: isApplePlatform,
                        isConfigured: isConfigured,
                        canUseGoogle: canUseGoogle,
                      ),
                      // Terms/privacy consent under the buttons that can CREATE
                      // the account — with social-only auth that is every tap
                      // here, so the line is always on.
                      const SizedBox(height: 16),
                      AuthLegalConsentText(
                        onTapTerms: () =>
                            _openLegalUrl(AppConfig.termsOfServiceUrl),
                        onTapPrivacy: () =>
                            _openLegalUrl(AppConfig.privacyPolicyUrl),
                      ),
                      const SizedBox(height: 12),
                      if (!_showPasswordForm)
                        _buildLegacyLink(context)
                      else
                        ..._buildPasswordForm(
                          context,
                          isConfigured: isConfigured,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // Keyboard avoidance: the sheet is pinned to the screen bottom
            // (behind the keyboard), so this spacer lifts the scroll viewport's
            // bottom up to the keyboard's top edge. Without it, focusing the
            // email/password field auto-scrolls it to where the keyboard would
            // cover it. Zero-height when the keyboard is closed.
            SizedBox(height: media.viewInsets.bottom),
          ],
        ),
      ),
    );
  }

  /// The social sign-in buttons, in the order the platform calls for.
  ///
  /// Apple platforms show BOTH, Apple first. Offering Google there is what makes
  /// an account portable: one created on Android through Google has no password
  /// to fall back on, and signing in with Apple instead doesn't reach it —
  /// Supabase only auto-links identities on a matching verified email, and
  /// Apple's Hide My Email hands it a `@privaterelay.appleid.com` address that
  /// matches nothing. Without a Google button on iOS, switching phones quietly
  /// starts a second, empty account: no favourites, no votes, no streak, no
  /// rank, and PRO stranded on the old one. App Store Review Guideline 4.8 makes
  /// Sign in with Apple mandatory next to a third-party login and asks for it to
  /// be at least as prominent, which is exactly the order below.
  ///
  /// Android stays Google-only: Play has no matching rule, and Sign in with
  /// Apple there would mean the browser redirect flow (an Apple Services ID plus
  /// a hosted redirect endpoint) instead of a native sheet.
  List<Widget> _buildSocialButtons({
    required bool isApplePlatform,
    required bool isConfigured,
    required bool canUseGoogle,
  }) {
    final google = AuthSocialButton(
      icon: const GoogleGlyph(),
      label: context.l10n.authContinueWithGoogle,
      onPressed: canUseGoogle && !_isSubmitting ? _signInWithGoogle : null,
    );

    if (!isApplePlatform) return [google];

    return [
      AuthSocialButton(
        icon: AppleGlyph(color: context.colors.ink),
        label: context.l10n.authContinueWithApple,
        onPressed: isConfigured && !_isSubmitting ? _signInWithApple : null,
      ),
      // A build with no Google client id still signs in with Apple here, so the
      // second button is dropped rather than shown dead.
      if (canUseGoogle) ...[const SizedBox(height: 10), google],
    ];
  }

  /// The one-line door to the legacy email/password sign-in. A TextButton, not
  /// bare text, for the same reason as "forgot password?": a hit area the size
  /// of the glyphs misses under Apple's 44pt and Material's 48dp minimum.
  /// Unfolding is harmless, so it stays tappable even in a keyless build — the
  /// form's own controls are what a missing backend disables.
  Widget _buildLegacyLink(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: _isSubmitting
            ? null
            : () => setState(() => _showPasswordForm = true),
        style: TextButton.styleFrom(
          foregroundColor: context.colors.subtle,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          minimumSize: const Size(kMinTouchTarget, kMinTouchTarget),
          textStyle: AppTypography.action(fontSize: 12.5),
        ),
        child: Text(context.l10n.authLegacyEmailLink.toUpperCase()),
      ),
    );
  }

  /// The unfolded legacy form: email, password, "forgot password?", sign in.
  /// Sign-in ONLY — there is no register path here any more, so no confirm
  /// field and no minimum-length rule (that belongs to setting a password).
  List<Widget> _buildPasswordForm(
    BuildContext context, {
    required bool isConfigured,
  }) {
    return [
      const AuthOrDivider(),
      const SizedBox(height: 14),
      authFieldLabel(context, context.l10n.authEmailLabel),
      TextFormField(
        controller: _emailController,
        enabled: !_isSubmitting,
        // The user just asked for this form; put the caret where they need it.
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.email],
        style: AppTypography.body(
          fontSize: 15,
        ).copyWith(color: context.colors.ink),
        decoration: authFieldDecoration(context, hint: 'you@example.com'),
        validator: _validateEmail,
      ),
      const SizedBox(height: 14),
      authFieldLabel(context, context.l10n.authPasswordLabel),
      TextFormField(
        controller: _passwordController,
        enabled: !_isSubmitting,
        obscureText: _obscurePassword,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.password],
        style: AppTypography.body(
          fontSize: 15,
        ).copyWith(color: context.colors.ink),
        decoration: authFieldDecoration(
          context,
          hint: '••••••••',
          suffixIcon: IconButton(
            tooltip: _obscurePassword
                ? context.l10n.authShowPassword
                : context.l10n.authHidePassword,
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: context.colors.subtle,
              size: 20,
            ),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        validator: _validatePassword,
        onFieldSubmitted: (_) => _submit(),
      ),
      // The button below carries its own 14px of vertical padding (the touch
      // target), so the gap above it is only what's left of the old 10px
      // rhythm.
      const SizedBox(height: 2),
      Align(
        alignment: Alignment.centerRight,
        // A TextButton, not a bare GestureDetector around the Text: that gave
        // the link a hit area exactly the size of its glyphs (265x19), well
        // under Apple's 44pt and Material's 48dp minimum, so the tap regularly
        // missed.
        child: TextButton(
          onPressed: (_isSubmitting || !isConfigured) ? null : _forgotPassword,
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.spark,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            minimumSize: const Size(kMinTouchTarget, kMinTouchTarget),
            textStyle: AppTypography.action(fontSize: 12.5),
          ),
          child: Text(context.l10n.authForgotPassword.toUpperCase()),
        ),
      ),
      const SizedBox(height: 14),
      AuthPrimaryButton(
        label: context.l10n.signIn,
        loading: _isSubmitting,
        onPressed: isConfigured ? _submit : null,
      ),
    ];
  }

  Widget _buildCloseRow(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: AuthCircleIconButton(
        icon: Icons.close,
        onTap: () => Navigator.of(context).maybePop(),
      ),
    );
  }

  /// Brand header above the buttons: the app icon in a softly glowing rounded
  /// tile, a headline and a one-line subtitle. One copy for every entry point
  /// — with a single button covering "create" and "sign back in" there is no
  /// mode for it to follow. The subtitle names only the providers this platform
  /// actually shows.
  Widget _buildBrandHeader(
    BuildContext context, {
    required bool isApplePlatform,
  }) {
    final subtitle = isApplePlatform
        ? context.l10n.authSheetSubtitleApple
        : context.l10n.authSheetSubtitleGoogle;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppTheme.sparkGlow.withValues(alpha: 0.28),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              'assets/images/logo.png',
              width: 72,
              height: 72,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          context.l10n.authSheetTitle.toUpperCase(),
          textAlign: TextAlign.center,
          style: AppTypography.title(
            fontSize: 30,
          ).copyWith(color: context.colors.ink),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: AppTypography.support(
            fontSize: 13,
          ).copyWith(color: context.colors.subtle),
        ),
      ],
    );
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return context.l10n.authEnterEmail;
    if (!email.contains('@') || !email.contains('.')) {
      return context.l10n.authEnterValidEmail;
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if ((value ?? '').isEmpty) return context.l10n.authEnterPassword;
    return null;
  }

  /// The legacy email/password SIGN-IN. Always an identity switch: it replaces
  /// the session with the target account's, unlike the social buttons, which
  /// upgrade a guest in place.
  Future<void> _submit() async {
    if (_isSubmitting || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _isSubmitting = true);

    // Read before the network calls: dismissing the sheet mid-request unmounts
    // this widget, and the session still has to be refreshed afterwards. The
    // previous identity is what decides whether PRO has to be moved.
    final session = ref.read(sessionProvider.notifier);
    final previous = ref.read(sessionProvider).value;
    try {
      // Signing in ABANDONS the guest profile this device is on. Say so first
      // when there is something on it to lose — the streak nudge pitches "your
      // streak lives only on this phone" and hands the user straight here.
      if (!await _confirmAbandoningGuestProgress()) return;
      await SupabaseService.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // A guest who just bought PRO and then signs into their old account
      // would otherwise land on a uid RevenueCat has never seen. Carry the
      // receipt over BEFORE the reload, which is what re-reads the entitlement.
      await _carryEntitlementToNewIdentity(
        previous: previous,
        next: SupabaseService.currentUser?.id,
      );
      await session.refresh();
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } catch (error) {
      // One handler: a timed-out / disconnected call arrives as a
      // TimeoutException or a transport-wrapped AuthException, and both have to
      // read as "no connection" rather than as a raw dump.
      if (mounted) {
        _showMessage(authErrorText(context, error), type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Confirms an identity-switching sign-in when this device carries a guest's
  /// progress. Returns whether the flow should go ahead.
  ///
  /// The social buttons normally upgrade the anonymous user in place — same
  /// UUID, streak, votes and favourites all kept — and only switch accounts
  /// when the picked identity already belongs to one. The legacy password
  /// sign-in ALWAYS switches. Either way the guest profile (and everything on
  /// it) is left behind with no way back, so it is said out loud first. Silent
  /// for an account holder, who has already left any guest behind, and for a
  /// fresh guest with nothing on the line.
  Future<bool> _confirmAbandoningGuestProgress() async {
    final session = ref.read(sessionProvider).value;
    if (session == null || session.hasAccount) return true;
    // The BEST streak, not the current one: the current streak decays back
    // towards zero on missed days, so a returning guest with a month of votes
    // behind them can read 0 — and they have the most to lose.
    // Unresolved stats mean we do not KNOW what is at stake, and the cost of
    // the two mistakes is not symmetric: a needless prompt for a brand-new
    // guest costs one tap, a skipped one costs a month of votes. So only a
    // loaded, genuinely empty history skips the warning.
    final stats = ref.read(userStatsProvider);
    if (stats.hasValue && stats.value!.longestStreak <= 0) return true;

    final proceed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          context.l10n.authSwitchAccountTitle.toUpperCase(),
          style: AppTypography.title(
            fontSize: 30,
          ).copyWith(color: context.colors.ink),
        ),
        content: Text(
          context.l10n.authSwitchAccountBody,
          style: AppTypography.body(
            height: 1.4,
          ).copyWith(color: context.colors.subtle),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.subtle,
              textStyle: AppTypography.action(),
            ),
            child: Text(context.l10n.authSwitchAccountConfirm.toUpperCase()),
          ),
          // Keeping the guest profile is the safe answer, so it wears the
          // accent.
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.spark,
              textStyle: AppTypography.action(),
            ),
            child: Text(context.l10n.cancel.toUpperCase()),
          ),
        ],
      ),
    );

    return proceed == true;
  }

  // [_confirmAbandoningGuestProgress] is handed DOWN rather than run up front:
  // a guest signing in socially normally keeps their UUID (the identity links
  // in place), so asking before the picker would cry wolf at everyone. It only
  // fires on the branch that actually switches accounts.
  Future<void> _signInWithGoogle() => _socialSignIn(
    () => SupabaseService.signInWithGoogle(
      confirmSwitch: _confirmAbandoningGuestProgress,
    ),
  );

  Future<void> _signInWithApple() => _socialSignIn(
    () => SupabaseService.signInWithApple(
      confirmSwitch: _confirmAbandoningGuestProgress,
    ),
  );

  /// Shared body for both social buttons: run the native flow, carry a guest's
  /// entitlement over if the flow switched to a different identity, then
  /// re-read the session. A cancelled picker / sheet comes back null and is
  /// not an error.
  Future<void> _socialSignIn(Future<User?> Function() signIn) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    // Read before the native flow: the sheet can be dismissed mid-request, and
    // the previous identity is what decides whether PRO has to be moved.
    final session = ref.read(sessionProvider.notifier);
    final previous = ref.read(sessionProvider).value;
    try {
      // [runAuthFlowAndReload] owns the reload and suppresses the auth
      // listener's duplicate `userUpdated` reload (the in-place identity link
      // emits one mid-flow) — one sign-in costs ONE entitlement reconcile.
      var signedIn = false;
      await session.runAuthFlowAndReload(() async {
        final user = await signIn();
        if (user == null) return false; // user cancelled the picker / sheet
        await _carryEntitlementToNewIdentity(previous: previous, next: user.id);
        signedIn = true;
        return true;
      });
      if (!signedIn || !mounted) return;
      Navigator.of(context).maybePop();
    } catch (error) {
      // One handler: a timed-out / disconnected call arrives as a
      // TimeoutException or a transport-wrapped AuthException, and both have to
      // read as "no connection" rather than as a raw dump.
      if (mounted) {
        _showMessage(authErrorText(context, error), type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Moves a just-bought entitlement onto the account the user signed into.
  ///
  /// A social tap on a guest UPGRADES the anonymous user in place
  /// (`linkIdentityWithIdToken`, same UUID), so PRO follows on its own and the
  /// same-uid guard below makes this a no-op. Two flows genuinely switch
  /// identity, and RevenueCat does not move purchases between two identified
  /// app user ids on `logIn` alone:
  ///
  ///  * the legacy email/password sign-in — always, since it replaces the
  ///    session with the target account's;
  ///  * a social sign-in whose Google/Apple identity already belongs to ANOTHER
  ///    Supabase account (a reinstall / new phone signing back in).
  ///
  /// Left as-is, a guest who buys PRO and then signs back into an old account
  /// lands on a uid RevenueCat has never seen — `sync-entitlement` gets a 404,
  /// `isPremium` goes false, and the paywall slams shut on someone who paid a
  /// minute ago.
  ///
  /// So the receipt is re-posted against the NEW identity before the session is
  /// re-read. Identify first: RevenueCat is still logged in as the old uid at
  /// this point (the session reload is what normally re-identifies), and
  /// restoring before that would just hand the receipt back to the identity
  /// we're leaving.
  ///
  /// Best-effort — both calls swallow their own failures, and the paywall's
  /// restore button remains the manual path. Depends on the RevenueCat
  /// dashboard's transfer behaviour being "transfer to the new App User ID".
  Future<void> _carryEntitlementToNewIdentity({
    required SessionState? previous,
    required String? next,
  }) async {
    if (!shouldCarryEntitlement(previous: previous, next: next)) return;
    await PurchasesService.identify(next!);
    await PurchasesService.restorePurchases();
  }

  /// Sends a Supabase password-reset email. Only the email field needs to be
  /// valid here — the password can be blank — so we validate it on its own
  /// rather than the whole form.
  Future<void> _forgotPassword() async {
    if (_isSubmitting) return;

    final emailError = _validateEmail(_emailController.text);
    if (emailError != null) {
      _showMessage(emailError, type: ToastType.error);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await SupabaseService.resetPasswordForEmail(_emailController.text.trim());
      if (!mounted) return;
      _showMessage(context.l10n.authPasswordResetSent, type: ToastType.success);
    } catch (error) {
      if (mounted) {
        _showMessage(authErrorText(context, error), type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Opens a legal page (terms / privacy) in the system browser, surfacing a
  /// toast if it can't be launched. Mirrors `PrivacyDataScreen._openUrl`.
  Future<void> _openLegalUrl(String url) async {
    final uri = Uri.tryParse(url);
    var opened = false;
    if (uri != null) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && mounted) {
      _showMessage(context.l10n.privacyLinkFailed, type: ToastType.error);
    }
  }

  void _showMessage(String message, {ToastType type = ToastType.info}) {
    if (!mounted) return;
    AppToast.show(context, message, type: type);
  }
}
