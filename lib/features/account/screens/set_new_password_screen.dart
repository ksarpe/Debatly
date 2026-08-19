import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/network/network_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../services/supabase_service.dart';
import '../widgets/auth_circle_icon_button.dart';
import '../widgets/auth_field.dart';
import '../widgets/auth_primary_button.dart';

/// Opens the "set a new password" sheet that finishes a password recovery.
///
/// Reached only from [PasswordRecoveryListener], i.e. after the recovery link
/// has already been redeemed — which means the user IS signed in by the time
/// this shows. Dismissing it is therefore safe (they keep the session, just the
/// old password), so the sheet is not a trap.
Future<void> showSetNewPasswordSheet(BuildContext context) {
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
    builder: (_) => const SetNewPasswordCard(),
  );
}

/// The form itself. Public so a widget test can render it in isolation.
class SetNewPasswordCard extends StatefulWidget {
  const SetNewPasswordCard({super.key});

  @override
  State<SetNewPasswordCard> createState() => _SetNewPasswordCardState();
}

class _SetNewPasswordCardState extends State<SetNewPasswordCard> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isSubmitting = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final l10n = context.l10n;
    // Same rule as the sign-in sheet: grow to fit, never past the screen.
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
                      Align(
                        alignment: Alignment.centerRight,
                        child: AuthCircleIconButton(
                          icon: Icons.close,
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                      Text(
                        l10n.authSetNewPasswordTitle.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: AppTypography.title(
                          fontSize: 26,
                        ).copyWith(color: context.colors.ink),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.authSetNewPasswordSubtitle,
                        textAlign: TextAlign.center,
                        style: AppTypography.support(
                          fontSize: 13,
                        ).copyWith(color: context.colors.subtle),
                      ),
                      const SizedBox(height: 22),
                      authFieldLabel(context, l10n.authNewPasswordLabel),
                      TextFormField(
                        controller: _passwordController,
                        enabled: !_isSubmitting,
                        obscureText: _obscurePassword,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.newPassword],
                        style: AppTypography.body(
                          fontSize: 15,
                        ).copyWith(color: context.colors.ink),
                        decoration: authFieldDecoration(
                          context,
                          hint: '••••••••',
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? l10n.authShowPassword
                                : l10n.authHidePassword,
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
                      ),
                      const SizedBox(height: 14),
                      authFieldLabel(context, l10n.authConfirmPasswordLabel),
                      TextFormField(
                        controller: _confirmController,
                        enabled: !_isSubmitting,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.newPassword],
                        style: AppTypography.body(
                          fontSize: 15,
                        ).copyWith(color: context.colors.ink),
                        decoration: authFieldDecoration(
                          context,
                          hint: '••••••••',
                        ),
                        validator: _validateConfirm,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 20),
                      AuthPrimaryButton(
                        label: l10n.authSetNewPasswordCta,
                        loading: _isSubmitting,
                        onPressed: _isSubmitting ? null : _submit,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Lifts the sheet clear of the keyboard while a field has focus.
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: media.viewInsets.bottom,
            ),
          ],
        ),
      ),
    );
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return context.l10n.authEnterPassword;
    if (password.length < 6) return context.l10n.authMinPassword;
    return null;
  }

  String? _validateConfirm(String? value) {
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
    try {
      await SupabaseService.updatePassword(_passwordController.text);
      if (!mounted) return;
      AppToast.success(context, context.l10n.authPasswordUpdated);
      Navigator.of(context).maybePop();
    } catch (error) {
      // The session reload rides on the `userUpdated` event this emits, so
      // nothing to refresh here — only the failure needs saying out loud.
      if (mounted) AppToast.error(context, _errorText(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Localises what can realistically come back from `updateUser`. Offline is
  /// checked FIRST: gotrue wraps a dropped connection in an `AuthException`
  /// subclass whose message is a raw `SocketException` dump.
  String _errorText(Object error) {
    final l10n = context.l10n;
    if (isOfflineError(error)) return l10n.noConnection;
    if (error is AuthException) {
      return switch (error.code) {
        'same_password' => l10n.authErrorSamePassword,
        'weak_password' => l10n.authErrorWeakPassword,
        'over_request_rate_limit' ||
        'over_email_send_rate_limit' => l10n.authErrorTooManyRequests,
        // A recovery session that has already lapsed lands here.
        'session_not_found' ||
        'refresh_token_not_found' => l10n.authRecoveryLinkInvalid,
        _ => error.message,
      };
    }
    return l10n.authRecoveryLinkInvalid;
  }
}
