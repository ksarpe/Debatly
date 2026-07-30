import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/supabase_service.dart';
import '../providers/session_providers.dart';
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
    final canUseGoogle = isConfigured && AppConfig.hasGoogleSignIn;
    // Sign in with Apple is offered on Apple platforms only (where it's an App
    // Store requirement); everywhere else we show Google. Both never share the
    // sheet — a user on Android has no use for an Apple button, and vice versa.
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
                      AuthSegmentedTabs(
                        mode: _mode,
                        enabled: !_isSubmitting,
                        onChanged: _changeMode,
                      ),

                      const SizedBox(height: 14),
                      if (!isConfigured) ...[
                        AuthNotice(
                          icon: Icons.info_outline,
                          text: context.l10n.authMissingSupabaseConfig,
                        ),
                        const SizedBox(height: 14),
                      ] else if (!isApplePlatform &&
                          !AppConfig.hasGoogleSignIn) ...[
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
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: (_isSubmitting || !isConfigured)
                                ? null
                                : _forgotPassword,
                            child: Text(
                              context.l10n.authForgotPassword,
                              style: const TextStyle(
                                color: AppTheme.spark,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
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
                      if (isApplePlatform)
                        AuthSocialButton(
                          icon: Icon(
                            Icons.apple,
                            color: context.colors.ink,
                            size: 22,
                          ),
                          label: context.l10n.authContinueWithApple,
                          onPressed: isConfigured && !_isSubmitting
                              ? _signInWithApple
                              : null,
                        )
                      else
                        AuthSocialButton(
                          icon: Text(
                            'G',
                            style: TextStyle(
                              color: context.colors.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          label: context.l10n.authContinueWithGoogle,
                          onPressed: canUseGoogle && !_isSubmitting
                              ? _signInWithGoogle
                              : null,
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
  /// softly glowing rounded tile. It gives the sheet an identity instead of
  /// opening cold on a form.
  Widget _buildBrandHeader(BuildContext context) {
    return Center(
      child: Container(
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

  Future<void> _signInWithGoogle() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final session = ref.read(sessionProvider.notifier);
    try {
      final user = await SupabaseService.signInWithGoogle();
      if (user == null) return; // user cancelled the picker
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

  Future<void> _signInWithApple() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final session = ref.read(sessionProvider.notifier);
    try {
      final user = await SupabaseService.signInWithApple();
      if (user == null) return; // user cancelled the sheet
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
