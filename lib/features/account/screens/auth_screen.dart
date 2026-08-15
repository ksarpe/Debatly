import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/app_locale.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/purchases_service.dart';
import '../../../services/supabase_service.dart';
import '../providers/session_providers.dart';
import '../widgets/auth_brand_glyph.dart';
import '../widgets/auth_circle_icon_button.dart';
import '../widgets/auth_legal_consent_text.dart';
import '../widgets/auth_notice.dart';
import '../widgets/auth_or_divider.dart';
import '../widgets/auth_primary_button.dart';
import '../widgets/auth_segmented_tabs.dart';
import '../widgets/auth_social_button.dart';

/// Presents the sign-in / register form as a modal bottom sheet that slides up
/// from the bottom of the screen.
Future<void> showAuthSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.cardSurface,
    isScrollControlled: true,
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
      body: SafeArea(child: Center(child: const _AuthCard())),
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
  final _confirmPasswordController = TextEditingController();

  AuthMode _mode = AuthMode.password;
  bool _isSubmitting = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _isLogin => _mode == AuthMode.password;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isConfigured = SupabaseService.isInitialised;

    // Registration is a POST-purchase feature, and that is the whole account
    // model: you buy PRO and play on the anonymous identity every user gets at
    // launch; an account exists only to SECURE that purchase (see
    // `promptSaveProAccount`). So before PRO the sheet is sign-in only — no
    // accounts are minted in front of the paywall, and someone who already
    // bought just signs back in to reach their purchase. The social buttons
    // stay for them (a Google/Apple account holder has no password to type);
    // Supabase's id-token flow cannot refuse a brand-new social identity,
    // which is an accepted edge — such a user still lands on the wall,
    // entitled to nothing.
    final canRegister = ref.watch(isPremiumProvider);
    if (!canRegister && _mode == AuthMode.register) _mode = AuthMode.password;
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
      constraints: BoxConstraints(maxWidth: 480, maxHeight: maxHeight),
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
                // (the gesture nav-bar height) keeps the last controls (Continue
                // with Google, legal consent) off the navigation bar on
                // edge-to-edge devices. It collapses to 0 while the keyboard is
                // up, where the spacer below the scroll view takes over.
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
                      _buildBrandHeader(context),
                      const SizedBox(height: 20),
                      // Pre-PRO the register tab doesn't exist — the sheet
                      // opens straight on the sign-in form, no tab bar at all.
                      if (canRegister) ...[
                        AuthSegmentedTabs(
                          mode: _mode,
                          enabled: !_isSubmitting,
                          onChanged: _changeMode,
                        ),
                        const SizedBox(height: 14),
                      ],
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
                      _fieldLabel(context.l10n.authEmailLabel),
                      TextFormField(
                        controller: _emailController,
                        enabled: !_isSubmitting,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        style: TextStyle(color: context.colors.ink),
                        decoration: _fieldDecoration(hint: 'you@example.com'),
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: 14),
                      _fieldLabel(context.l10n.authPasswordLabel),
                      TextFormField(
                        controller: _passwordController,
                        enabled: !_isSubmitting,
                        obscureText: _obscurePassword,
                        textInputAction: _isLogin
                            ? TextInputAction.done
                            : TextInputAction.next,
                        autofillHints: _isLogin
                            ? const [AutofillHints.password]
                            : const [AutofillHints.newPassword],
                        style: TextStyle(color: context.colors.ink),
                        decoration: _fieldDecoration(
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
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        validator: _validatePassword,
                        onFieldSubmitted: (_) {
                          if (_isLogin) _submit();
                        },
                      ),
                      if (!_isLogin) ...[
                        const SizedBox(height: 14),
                        _fieldLabel(context.l10n.authConfirmPasswordLabel),
                        TextFormField(
                          controller: _confirmPasswordController,
                          enabled: !_isSubmitting,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          style: TextStyle(color: context.colors.ink),
                          decoration: _fieldDecoration(hint: '••••••••'),
                          validator: _validateConfirmPassword,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                      ],
                      if (_isLogin) ...[
                        // The button below carries its own 14px of vertical
                        // padding (the touch target), so the gap above it is
                        // only what's left of the old 10px rhythm.
                        const SizedBox(height: 2),
                        Align(
                          alignment: Alignment.centerRight,
                          // A TextButton, not a bare GestureDetector around the
                          // Text: that gave the link a hit area exactly the size
                          // of its glyphs (265x19), well under Apple's 44pt and
                          // Material's 48dp minimum, so the tap regularly missed.
                          child: TextButton(
                            onPressed: (_isSubmitting || !isConfigured)
                                ? null
                                : _forgotPassword,
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.spark,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              minimumSize: const Size(
                                kMinTouchTarget,
                                kMinTouchTarget,
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            child: Text(context.l10n.authForgotPassword),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      AuthPrimaryButton(
                        label: _isLogin
                            ? context.l10n.signIn
                            : context.l10n.authCreateAccount,
                        loading: _isSubmitting,
                        onPressed: isConfigured ? _submit : null,
                      ),
                      const SizedBox(height: 16),
                      const AuthOrDivider(),
                      const SizedBox(height: 14),
                      ..._buildSocialButtons(
                        isApplePlatform: isApplePlatform,
                        isConfigured: isConfigured,
                        canUseGoogle: canUseGoogle,
                      ),
                      // Terms/privacy consent shown at the account-creation
                      // point (register tab). Sign-in is an existing user, so
                      // it doesn't need the line.
                      if (!_isLogin) ...[
                        const SizedBox(height: 16),
                        AuthLegalConsentText(
                          onTapTerms: () =>
                              _openLegalUrl(AppConfig.termsOfServiceUrl),
                          onTapPrivacy: () =>
                              _openLegalUrl(AppConfig.privacyPolicyUrl),
                        ),
                      ],
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

  Widget _buildCloseRow(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: AuthCircleIconButton(
        icon: Icons.close,
        onTap: () => Navigator.of(context).maybePop(),
      ),
    );
  }

  /// Brand header shown above the sign-in / sign-up tabs: the app icon in a
  /// softly glowing rounded tile, with a greeting headline and a one-line
  /// subtitle underneath. It gives the sheet an identity instead of opening
  /// cold on a form. The copy follows the active tab (sign-in vs register).
  Widget _buildBrandHeader(BuildContext context) {
    final title = _isLogin
        ? context.l10n.authWelcomeBackTitle
        : context.l10n.authRegisterTitle;
    final subtitle = _isLogin
        ? context.l10n.authWelcomeBackSubtitle
        : context.l10n.authRegisterSubtitle;

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
                color: AppTheme.spark.withValues(alpha: 0.30),
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
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.colors.ink,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.colors.subtle,
            fontSize: 13.5,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  void _changeMode(AuthMode mode) {
    if (_isSubmitting || mode == _mode) return;
    setState(() {
      _mode = mode;
      _formKey.currentState?.reset();
    });
  }

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 2),
    child: Text(
      text,
      style: TextStyle(
        color: context.colors.subtle,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    ),
  );

  InputDecoration _fieldDecoration({String? hint, Widget? suffixIcon}) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: context.colors.subtle),
      filled: true,
      fillColor: context.colors.accent,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: border(context.colors.hairline),
      focusedBorder: border(AppTheme.spark, 1.5),
      errorBorder: border(const Color(0xFFE5484D)),
      focusedErrorBorder: border(const Color(0xFFE5484D), 1.5),
      disabledBorder: border(context.colors.hairline),
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
    final password = value ?? '';
    if (password.isEmpty) return context.l10n.authEnterPassword;
    if (_mode == AuthMode.register && password.length < 6) {
      return context.l10n.authMinPassword;
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value != _passwordController.text) {
      return context.l10n.authPasswordsMismatch;
    }
    return null;
  }

  Future<void> _submit() async {
    if (_isSubmitting || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _isSubmitting = true);

    // Read before the network calls: dismissing the sheet mid-request unmounts
    // this widget, and the session still has to be refreshed afterwards.
    final session = ref.read(sessionProvider.notifier);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      switch (_mode) {
        case AuthMode.password:
          await SupabaseService.signInWithPassword(
            email: email,
            password: password,
          );
          await session.refresh();
          if (!mounted) return;
          Navigator.of(context).maybePop();
        case AuthMode.register:
          await SupabaseService.registerWithPassword(
            email: email,
            password: password,
            locale: ref.read(localeControllerProvider).languageCode,
          );
          await session.refresh();
          if (!mounted) return;
          final created = SupabaseService.currentUserHasAccount;
          _showMessage(
            created
                ? context.l10n.authAccountCreated
                : context.l10n.authConfirmEmail,
            type: created ? ToastType.success : ToastType.info,
          );
          if (SupabaseService.currentUserHasAccount) {
            Navigator.of(context).maybePop();
          }
      }
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message, type: ToastType.error);
    } catch (error) {
      if (mounted) _showMessage(error.toString(), type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _signInWithGoogle() =>
      _socialSignIn(SupabaseService.signInWithGoogle);

  Future<void> _signInWithApple() =>
      _socialSignIn(SupabaseService.signInWithApple);

  /// Shared body for both social buttons: run the native flow, carry a guest's
  /// entitlement over to the identity it just created, then re-read the
  /// session. A cancelled picker / sheet comes back null and is not an error.
  Future<void> _socialSignIn(Future<User?> Function() signIn) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    // Read before the native flow: the sheet can be dismissed mid-request, and
    // the previous identity is what decides whether PRO has to be moved.
    final session = ref.read(sessionProvider.notifier);
    final previous = ref.read(sessionProvider).value;
    try {
      final user = await signIn();
      if (user == null) return; // user cancelled the picker / sheet
      await _carryEntitlementToNewIdentity(previous: previous, next: user.id);
      await session.refresh();
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message, type: ToastType.error);
    } catch (error) {
      if (mounted) _showMessage(error.toString(), type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Moves a just-bought entitlement onto the account the user signed into.
  ///
  /// Registering with email/password UPGRADES the anonymous user in place
  /// (`updateUser`, same UUID), so PRO follows on its own. The social buttons
  /// cannot: `signInWithIdToken` mints a SEPARATE Supabase user, and
  /// RevenueCat does not move purchases between two identified app user ids on
  /// `logIn` alone. Left as-is, a guest who buys PRO and then takes the
  /// "save your PRO to an account" nudge straight to Google lands on a fresh
  /// uid RevenueCat has never seen — `sync-entitlement` gets a 404, `isPremium`
  /// goes false, and the hard paywall slams shut on someone who paid a minute
  /// ago.
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
    required String next,
  }) async {
    if (previous == null || !previous.isPremium) return;
    final previousUserId = previous.userId;
    // Same uid = an in-place upgrade; nothing moved, nothing to carry.
    if (previousUserId == null || previousUserId == next) return;
    await PurchasesService.identify(next);
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
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message, type: ToastType.error);
    } catch (error) {
      if (mounted) _showMessage(error.toString(), type: ToastType.error);
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
