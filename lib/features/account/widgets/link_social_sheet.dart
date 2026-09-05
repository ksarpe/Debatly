import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/feedback/app_toast.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../services/analytics.dart';
import '../../../services/supabase_service.dart';
import '../providers/session_providers.dart';
import 'auth_brand_glyph.dart';
import 'auth_circle_icon_button.dart';
import 'auth_error_text.dart';
import 'auth_notice.dart';
import 'auth_social_button.dart';

/// "Link Apple / Google to this account" — the migration path for the
/// email/password accounts that predate the social-only sheet (2026-09-05).
///
/// Opened from the Settings row that shows only while
/// `SessionState.canLinkSocial` holds: a real account with no social identity
/// yet. On a fresh install that account's password is its only key, and the
/// sheet's legacy form is slated to go (stage 2); once a social identity is
/// linked here the "Continue with …" button reaches the same UUID instead, and
/// the row disappears on the reload that follows.
///
/// Never a sign-in: `SupabaseService.linkSocialIdentity` links onto the CURRENT
/// user and has no fallback, so an identity that already belongs to another
/// account is refused and explained, not switched to.
Future<void> showLinkSocialSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.cardSurface,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: kFormMaxWidth),
    showDragHandle: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const LinkSocialCard(),
  );
}

/// The sheet's body, public so a test can render it in isolation.
class LinkSocialCard extends ConsumerStatefulWidget {
  const LinkSocialCard({super.key});

  @override
  ConsumerState<LinkSocialCard> createState() => _LinkSocialCardState();
}

class _LinkSocialCardState extends ConsumerState<LinkSocialCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isConfigured = SupabaseService.isInitialised;
    final canUseGoogle = isConfigured && AppConfig.hasGoogleSignIn;
    // Same platform split as the auth sheet: Apple platforms get both, Apple
    // first; Android gets Google alone.
    final isApplePlatform =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + media.padding.bottom),
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
            context.l10n.linkSocialTitle.toUpperCase(),
            textAlign: TextAlign.center,
            style: AppTypography.title(
              fontSize: 28,
            ).copyWith(color: context.colors.ink),
          ),
          const SizedBox(height: 8),
          Text(
            isApplePlatform
                ? context.l10n.linkSocialBodyApple
                : context.l10n.linkSocialBodyGoogle,
            textAlign: TextAlign.center,
            style: AppTypography.support(
              fontSize: 13,
              height: 1.4,
            ).copyWith(color: context.colors.subtle),
          ),
          const SizedBox(height: 22),
          if (!isConfigured) ...[
            AuthNotice(
              icon: Icons.info_outline,
              text: context.l10n.authMissingSupabaseConfig,
            ),
            const SizedBox(height: 14),
          ] else if (!isApplePlatform && !AppConfig.hasGoogleSignIn) ...[
            AuthNotice(
              icon: Icons.info_outline,
              text: context.l10n.authMissingGoogleConfig,
            ),
            const SizedBox(height: 14),
          ],
          if (isApplePlatform) ...[
            AuthSocialButton(
              icon: AppleGlyph(color: context.colors.ink),
              label: context.l10n.authContinueWithApple,
              onPressed: isConfigured && !_busy
                  ? () => _link(OAuthProvider.apple)
                  : null,
            ),
            if (canUseGoogle) const SizedBox(height: 10),
          ],
          if (!isApplePlatform || canUseGoogle)
            AuthSocialButton(
              icon: const GoogleGlyph(),
              label: context.l10n.authContinueWithGoogle,
              onPressed: canUseGoogle && !_busy
                  ? () => _link(OAuthProvider.google)
                  : null,
            ),
        ],
      ),
    );
  }

  Future<void> _link(OAuthProvider provider) async {
    if (_busy) return;
    setState(() => _busy = true);

    // Read before the native flow: the sheet can be dismissed mid-request.
    final session = ref.read(sessionProvider.notifier);
    final l10n = context.l10n;
    final providerName = switch (provider) {
      OAuthProvider.apple => 'Apple',
      _ => 'Google',
    };
    try {
      // The link emits `userUpdated` mid-way; [runAuthFlowAndReload] owns the
      // one reload that follows (which is also what hides the Settings row).
      var linked = false;
      await session.runAuthFlowAndReload(() async {
        final user = await SupabaseService.linkSocialIdentity(provider);
        if (user == null) return false; // dismissed the native sheet
        linked = true;
        return true;
      });
      if (!linked || !mounted) return;
      Analytics.log('auth_social_linked', {'provider': provider.name});
      AppToast.show(context, l10n.linkSocialDone, type: ToastType.success);
      Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      final alreadyLinked = SupabaseService.isIdentityAlreadyLinked(error);
      Analytics.log('auth_social_link_failed', {
        'provider': provider.name,
        'code': error is AuthException
            ? (error.code ?? 'auth')
            : error.runtimeType.toString(),
      });
      AppToast.show(
        context,
        alreadyLinked
            ? l10n.linkSocialAlreadyLinked(providerName)
            : authErrorText(context, error),
        type: ToastType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
