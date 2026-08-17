import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/spark_cta_button.dart';
import '../../../data/models/smaczek.dart';
import '../../account/providers/session_providers.dart';
import '../../account/widgets/save_pro_prompt.dart';
import '../../monetization/widgets/pro_paywall_screen.dart';
import '../providers/question_providers.dart';

/// Opens the "Smaczki" panel as a modal sheet that slides up from the bottom.
///
/// Shows the discussion prompts for [questionId]: a free user sees the first one
/// plus the rest as blurred, locked placeholders; premium users see them all.
/// The gate is enforced server-side (the `get_question_smaczki` RPC) — locked
/// smaczki never carry real text, so the blur is purely cosmetic.
Future<void> showSmaczkiSheet(BuildContext context, String questionId) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.background,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _SmaczkiSheet(questionId: questionId),
  );
}

class _SmaczkiSheet extends ConsumerStatefulWidget {
  const _SmaczkiSheet({required this.questionId});

  final String questionId;

  @override
  ConsumerState<_SmaczkiSheet> createState() => _SmaczkiSheetState();
}

class _SmaczkiSheetState extends ConsumerState<_SmaczkiSheet> {
  /// Blocks the premium button while the paywall / purchase is in flight.
  bool _busy = false;

  Future<void> _getPremium() async {
    setState(() => _busy = true);

    final purchased = await showProPaywall(
      context,
      source: PaywallSource.smaczki,
    );
    if (!mounted) return;

    if (purchased) {
      // The entitlement is the source of truth: refresh the session so the gate
      // sees the upgrade, then drop the cached smaczki so they re-fetch — this
      // time the RPC returns the now-unlocked text.
      await ref.read(sessionProvider.notifier).refresh();
      if (!mounted) return;
      ref.invalidate(smaczkiProvider(widget.questionId));
      setState(() => _busy = false);
      // A guest's PRO rides on the anonymous identity — nudge them to save it to
      // a real account. No-ops for a user who already has an account.
      await promptSaveProAccount(context, ref);
    } else {
      AppToast.info(context, context.l10n.purchaseNotCompleted);
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final smaczkiAsync = ref.watch(smaczkiProvider(widget.questionId));

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.smaczkiTitle,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.smaczkiSubtitle,
                style: TextStyle(color: context.colors.subtle, fontSize: 13),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              Flexible(
                child: smaczkiAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      context.l10n.smaczkiLoadError(e.toString()),
                      style: TextStyle(color: context.colors.subtle),
                    ),
                  ),
                  data: (smaczki) => _SmaczkiList(
                    smaczki: smaczki,
                    busy: _busy,
                    onGetPremium: _busy ? null : _getPremium,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The resolved list: numbered cards for readable smaczki, blurred placeholders
/// for the locked ones, and a single premium upsell when anything is locked.
class _SmaczkiList extends StatelessWidget {
  const _SmaczkiList({
    required this.smaczki,
    required this.busy,
    required this.onGetPremium,
  });

  final List<Smaczek> smaczki;
  final bool busy;
  final VoidCallback? onGetPremium;

  @override
  Widget build(BuildContext context) {
    if (smaczki.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          context.l10n.smaczkiEmpty,
          style: TextStyle(color: context.colors.subtle),
        ),
      );
    }

    // Premium users get no locked rows, so the upsell only shows for free users.
    final hasLocked = smaczki.any((s) => s.isLocked);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < smaczki.length; i++)
            smaczki[i].isLocked
                ? _LockedSmaczekCard(index: i + 1)
                : _SmaczekCard(index: i + 1, text: smaczki[i].text ?? ''),
          if (hasLocked) ...[
            const SizedBox(height: 4),
            _PremiumCta(busy: busy, onTap: onGetPremium),
          ],
        ],
      ),
    );
  }
}

/// A readable smaczek: an orange index number and the prompt text.
class _SmaczekCard extends StatelessWidget {
  const _SmaczekCard({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.accent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IndexDot(index: index),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: context.colors.ink,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A locked smaczek: a blurred dummy line plus a lock icon.
///
/// The server sent `text == null` for this one, so there is no real content on
/// the client. We render a fixed placeholder ([_dummy]) under a blur — even if
/// someone removes the blur, all they find is the dummy string, never the real
/// smaczek. Tapping the premium CTA below is the only way to reveal it.
class _LockedSmaczekCard extends StatelessWidget {
  const _LockedSmaczekCard({required this.index});

  final int index;

  static const _dummy =
      'aaabbbbaaabbb aaabbbbaaabbb aaabbbbaaabbb aaabbbbaaabbb '
      'aaabbbbaaabbb aaabbbbaaabbb aaabbbbaaabbb aaabbbbaaabbb';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.accent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IndexDot(index: index, locked: true),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Text(
                  _dummy,
                  maxLines: 2,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    color: context.colors.subtle,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.lock_rounded, size: 18, color: AppTheme.spark),
        ],
      ),
    );
  }
}

/// Number to the left of each smaczek: orange when readable, muted when locked.
class _IndexDot extends StatelessWidget {
  const _IndexDot({required this.index, this.locked = false});

  final int index;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      child: Text(
        '$index',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: locked ? context.colors.subtle : AppTheme.spark,
          fontSize: 18,
          // Line box matches the 15px/1.4 smaczek text beside it, so the
          // number stays centered on the first line.
          height: 21 / 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The "unlock" button shown when some smaczki are locked. A null [onTap]
/// (while busy) disables it and swaps the label for a small spinner.
class _PremiumCta extends StatelessWidget {
  const _PremiumCta({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: SparkCtaButton(
        label: context.l10n.smaczkiUnlockCta,
        busy: busy,
        fontSize: 14,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        onTap: onTap,
      ),
    );
  }
}
