import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sub_screen_chrome.dart';
import '../widgets/settings_nav_row.dart';
import '../widgets/settings_primitives.dart';

/// Reached from the "Privacy & data" account row. Two parts:
///
/// 1. **Documents** — outbound links to the privacy policy, terms, and the web
///    account-deletion page, opened in the system browser. The URLs default to
///    the live marketing site ([AppConfig.privacyPolicyUrl] /
///    [AppConfig.termsOfServiceUrl] / [AppConfig.deleteAccountUrl]) but each row
///    is still guarded on a non-empty URL, so blanking one via `--dart-define`
///    hides that row rather than showing a dead link.
/// 2. **What we store** — a plain-language summary of the data the app keeps and
///    why, mirroring the categories actually collected (account, activity,
///    purchases, ads).
class PrivacyDataScreen extends StatelessWidget {
  const PrivacyDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasPolicy = AppConfig.hasPrivacyPolicy;
    final hasTerms = AppConfig.hasTermsOfService;
    final hasDeleteUrl = AppConfig.hasDeleteAccountUrl;
    final hasDocs = hasPolicy || hasTerms || hasDeleteUrl;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          const TopGlow(),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                32 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SubScreenHeader(
                        title: l10n.settingsPrivacy,
                        onClose: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(height: 24),

                      // ---- Documents (only when URLs are configured) --------
                      if (hasDocs) ...[
                        SettingsSectionLabel(l10n.privacyDocsSection),
                        const SizedBox(height: 12),
                        SettingsCard(
                          children: [
                            if (hasPolicy)
                              SettingsNavRow(
                                icon: Icons.description_outlined,
                                title: l10n.privacyPolicy,
                                subtitle: l10n.privacyOpenInBrowser,
                                onTap: () => _openUrl(
                                  context,
                                  AppConfig.privacyPolicyUrl,
                                ),
                              ),
                            if (hasPolicy && hasTerms)
                              const SettingsRowDivider(),
                            if (hasTerms)
                              SettingsNavRow(
                                icon: Icons.gavel_rounded,
                                title: l10n.privacyTerms,
                                subtitle: l10n.privacyOpenInBrowser,
                                onTap: () => _openUrl(
                                  context,
                                  AppConfig.termsOfServiceUrl,
                                ),
                              ),
                            if ((hasPolicy || hasTerms) && hasDeleteUrl)
                              const SettingsRowDivider(),
                            if (hasDeleteUrl)
                              SettingsNavRow(
                                icon: Icons.person_remove_outlined,
                                title: l10n.privacyDeleteAccount,
                                subtitle: l10n.privacyOpenInBrowser,
                                onTap: () => _openUrl(
                                  context,
                                  AppConfig.deleteAccountUrl,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 28),
                      ],

                      // ---- What we store ------------------------------------
                      SettingsSectionLabel(l10n.privacyDataSection),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                        child: Text(
                          l10n.privacyDataIntro,
                          style: AppTypography.support(
                            fontSize: 13,
                            height: 1.4,
                          ).copyWith(color: context.colors.subtle),
                        ),
                      ),
                      SettingsCard(
                        children: [
                          _PrivacyDataRow(
                            icon: Icons.person_outline_rounded,
                            title: l10n.privacyDataAccountTitle,
                            body: l10n.privacyDataAccountBody,
                          ),
                          const SettingsRowDivider(),
                          _PrivacyDataRow(
                            icon: Icons.insights_rounded,
                            title: l10n.privacyDataActivityTitle,
                            body: l10n.privacyDataActivityBody,
                          ),
                          const SettingsRowDivider(),
                          _PrivacyDataRow(
                            icon: Icons.workspace_premium_outlined,
                            title: l10n.privacyDataPurchasesTitle,
                            body: l10n.privacyDataPurchasesBody,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens [url] in the system browser, surfacing a snackbar if it can't be
  /// launched (mirrors [ManageSubscriptionSheet]'s deep-link handling).
  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    final overlay = AppToast.capture(context);
    final failed = context.l10n.privacyLinkFailed;
    var opened = false;
    if (uri != null) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened) {
      AppToast.showOn(overlay, failed, type: ToastType.error);
    }
  }
}

/// Left-aligned screen title with a floating close button, matching the
/// profile header but for pushed sub-screens.
/// Non-interactive informational row: icon, title and a wrapping body. Used by
/// the "What we store" summary, so it deliberately has no chevron.
class _PrivacyDataRow extends StatelessWidget {
  const _PrivacyDataRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: context.colors.subtle, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.body(
                    fontSize: 15,
                  ).copyWith(color: context.colors.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: AppTypography.support(
                    fontSize: 13,
                    height: 1.4,
                  ).copyWith(color: context.colors.subtle),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
