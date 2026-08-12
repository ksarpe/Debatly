import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../services/purchases_service.dart';
import '../../account/providers/session_providers.dart';
import 'settings_primitives.dart';

/// Explains the active subscription and deep-links to the store's
/// subscription-management page.
///
/// Crucial product/UX point: neither the App Store nor Google Play lets an app
/// cancel a subscription itself — cancellation always happens in the store's own
/// "Subscriptions" screen. So this sheet doesn't (and can't) cancel anything; it
/// surfaces the renewal status and is a one-tap shortcut out to the right place,
/// with copy that differs per store.
class ManageSubscriptionSheet extends ConsumerStatefulWidget {
  const ManageSubscriptionSheet({super.key, required this.localeCode});

  final String localeCode;

  @override
  ConsumerState<ManageSubscriptionSheet> createState() =>
      _ManageSubscriptionSheetState();
}

class _ManageSubscriptionSheetState
    extends ConsumerState<ManageSubscriptionSheet> {
  bool _opening = false;
  bool _openFailed = false;

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(premiumStatusProvider);
    final status = statusAsync.value;
    final store = status?.store ?? PremiumStore.other;
    final l10n = context.l10n;

    return SafeArea(
      // The sheet opens scroll-controlled (no 9/16 cap), so on a short window or
      // at a large system font its content can be taller than the screen — and
      // a Column that overflows is painted but no longer hit-tested, which would
      // put the "manage in the store" button out of reach.
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colors.hairline,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Icon(
                    Icons.workspace_premium,
                    color: kPremiumGreen,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n.manageSubSheetTitle,
                    style: TextStyle(
                      color: context.colors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ---- Status card -------------------------------------------------
              if (statusAsync.isLoading && status == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: kPremiumGreen,
                      ),
                    ),
                  ),
                )
              else
                _StatusCard(status: status, localeCode: widget.localeCode),

              const SizedBox(height: 14),
              Text(
                _storeNote(l10n, store),
                style: TextStyle(
                  color: context.colors.subtle,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              if (_openFailed) ...[
                const SizedBox(height: 12),
                Text(
                  _storeOpenFailed(l10n, store),
                  style: const TextStyle(
                    color: kDanger,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 20),

              _ManageButton(
                label: _storeButton(l10n, store),
                busy: _opening,
                onTap: () => _manage(status),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: TextButton.styleFrom(
                    foregroundColor: context.colors.subtle,
                  ),
                  child: Text(l10n.later),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _manage(PremiumStatus? status) async {
    setState(() {
      _opening = true;
      _openFailed = false;
    });
    final opened = await PurchasesService.openManagement(status?.managementUrl);
    if (!mounted) return;
    if (opened) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _opening = false;
        _openFailed = true;
      });
    }
  }
}

/// The renewal/cancellation status block inside the manage sheet.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.localeCode});

  final PremiumStatus? status;
  final String localeCode;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cancelled = status?.isCancelled ?? false;
    final expiry = status?.expirationDate;

    final headline = cancelled
        ? l10n.manageSubStatusCancelled
        : l10n.manageSubStatusActive;
    final headlineColor = cancelled ? kGold : kPremiumGreen;

    String? dateLine;
    if (expiry != null) {
      final date = formatLongDate(expiry, localeCode);
      dateLine = cancelled
          ? l10n.manageSubActiveUntil(date)
          : l10n.manageSubRenewsOn(date);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                cancelled
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_rounded,
                color: headlineColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                headline,
                style: TextStyle(
                  color: headlineColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (dateLine != null) ...[
            const SizedBox(height: 8),
            Text(
              dateLine,
              style: TextStyle(color: context.colors.ink, fontSize: 14),
            ),
          ],
          if (status != null) ...[
            const SizedBox(height: 4),
            Text(
              _storeBilledLabel(l10n, status!.store),
              style: TextStyle(color: context.colors.subtle, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

/// Full-width gold "Manage in …" button, matching the premium accent.
class _ManageButton extends StatelessWidget {
  const _ManageButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kGold,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 54,
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.black,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.open_in_new_rounded,
                        color: Colors.black,
                        size: 19,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// "Billed through …" line for the status card.
String _storeBilledLabel(AppLocalizations l10n, PremiumStore store) {
  switch (store) {
    case PremiumStore.appStore:
      return l10n.manageSubBilledAppStore;
    case PremiumStore.playStore:
      return l10n.manageSubBilledPlayStore;
    case PremiumStore.web:
    case PremiumStore.other:
      return l10n.manageSubBilledWeb;
  }
}

/// Explanatory note about where cancellation actually happens, per store.
String _storeNote(AppLocalizations l10n, PremiumStore store) {
  switch (store) {
    case PremiumStore.appStore:
      return l10n.manageSubNoteAppStore;
    case PremiumStore.playStore:
      return l10n.manageSubNotePlayStore;
    case PremiumStore.web:
    case PremiumStore.other:
      return l10n.manageSubNoteWeb;
  }
}

/// Label for the primary "Manage in …" button, per store.
String _storeButton(AppLocalizations l10n, PremiumStore store) {
  switch (store) {
    case PremiumStore.appStore:
      return l10n.manageSubButtonAppStore;
    case PremiumStore.playStore:
      return l10n.manageSubButtonPlayStore;
    case PremiumStore.web:
    case PremiumStore.other:
      return l10n.manageSubButtonGeneric;
  }
}

/// Fallback instructions shown if the management deep link can't be opened.
String _storeOpenFailed(AppLocalizations l10n, PremiumStore store) {
  switch (store) {
    case PremiumStore.appStore:
      return l10n.manageSubOpenFailedAppStore;
    case PremiumStore.playStore:
      return l10n.manageSubOpenFailedPlayStore;
    case PremiumStore.web:
    case PremiumStore.other:
      return l10n.manageSubOpenFailedGeneric;
  }
}
