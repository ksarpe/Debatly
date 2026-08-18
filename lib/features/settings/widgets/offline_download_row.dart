import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../providers/offline_download_providers.dart';
import 'settings_primitives.dart';

/// Premium-only "download everything for offline" row.
///
/// Drives [offlineDownloadControllerProvider], which walks the catalog + every
/// question's smaczki through the caching repository so the whole
/// premium-readable set lands on device. The subtitle reflects state — ready /
/// in-progress (done/total) / last-downloaded date — and the trailing glyph
/// flips between a download arrow, a spinner and a green check.
class OfflineDownloadRow extends ConsumerWidget {
  const OfflineDownloadRow({super.key, required this.localeCode});

  final String localeCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(offlineDownloadControllerProvider);
    final l10n = context.l10n;

    final subtitle = switch (state.status) {
      OfflineDownloadStatus.running => l10n.offlineDownloadProgress(
        state.done,
        state.total,
      ),
      _ when state.lastSyncAt != null => l10n.offlineDownloadSynced(
        formatLongDate(state.lastSyncAt!, localeCode),
      ),
      _ => l10n.offlineDownloadReady,
    };

    return InkWell(
      onTap: state.isRunning ? null : () => _download(context, ref),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(
              Icons.cloud_download_outlined,
              color: context.colors.subtle,
              size: 22,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsOfflineQuestions,
                    style: AppTypography.body(
                      fontSize: 15,
                    ).copyWith(color: context.colors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.support(
                      fontSize: 13,
                    ).copyWith(color: context.colors.subtle),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _trailing(state),
          ],
        ),
      ),
    );
  }

  Widget _trailing(OfflineDownloadState state) {
    if (state.isRunning) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.2),
      );
    }
    if (state.status != OfflineDownloadStatus.error &&
        state.lastSyncAt != null) {
      return const Icon(
        Icons.check_circle_rounded,
        color: kPremiumGreen,
        size: 22,
      );
    }
    return const Icon(Icons.download_rounded, color: AppTheme.spark, size: 22);
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    // Capture the overlay, the strings AND the controller before the (long)
    // await so the completion toast survives even if the user leaves Settings
    // mid-download — which is the expected case, since the walk takes minutes
    // and keeps running in the background. `ref` is tied to this widget's
    // element, so reading it after the await would throw once that happens; the
    // download reports its own terminal state instead.
    final overlay = AppToast.capture(context);
    final completeMsg = context.l10n.offlineDownloadComplete;
    final failMsg = context.l10n.offlineDownloadFailed;
    final controller = ref.read(offlineDownloadControllerProvider.notifier);

    final result = await controller.download();

    switch (result.status) {
      case OfflineDownloadStatus.done:
        AppToast.showOn(overlay, completeMsg, type: ToastType.success);
      case OfflineDownloadStatus.error:
        AppToast.showOn(overlay, failMsg, type: ToastType.error);
      case OfflineDownloadStatus.idle:
      case OfflineDownloadStatus.running:
        break;
    }
  }
}
