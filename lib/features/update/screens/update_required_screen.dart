import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// The blocking "update required" screen — what [HomeGate] renders instead of
/// the feed once [updateRequiredProvider] says this build is below the
/// server's minimum (`app_update_gate`).
///
/// Deliberately a dead end with exactly one action: the store button. No
/// dismiss, no "later" — the gate only ever fires because the owner decided
/// this version must not talk to the backend anymore, and a maybe-later
/// version of that decision is not a decision. System back still leaves the
/// app (this sits at the root), so it is not a trap either.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  static const String _playUrl =
      'https://play.google.com/store/apps/details?id=com.aknsoftware.debatly';
  static const String _appStoreUrl = 'https://apps.apple.com/app/id6788246198';

  Future<void> _openStore(BuildContext context) async {
    final uri = Uri.parse(
      defaultTargetPlatform == TargetPlatform.iOS ? _appStoreUrl : _playUrl,
    );
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      AppToast.info(context, context.l10n.noConnection);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.system_update_alt,
                    color: context.colors.subtle,
                    size: 40,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.updateRequiredTitle.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: AppTypography.title(
                      fontSize: 30,
                    ).copyWith(color: context.colors.ink),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.updateRequiredBody,
                    textAlign: TextAlign.center,
                    style: AppTypography.body(
                      fontSize: 14,
                    ).copyWith(color: context.colors.subtle),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => _openStore(context),
                    child: Text(
                      context.l10n.updateRequiredCta.toUpperCase(),
                      style: AppTypography.action(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
