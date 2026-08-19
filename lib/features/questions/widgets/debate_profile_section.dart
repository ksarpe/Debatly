import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/share/widget_to_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/debate_profile.dart';
import '../../../data/models/vote_history_entry.dart';
import '../../../data/models/vote_result.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../services/analytics.dart';
import '../../account/providers/session_providers.dart';
import '../../account/widgets/save_pro_prompt.dart';
import '../../monetization/widgets/pro_paywall_screen.dart';
import '../providers/question_providers.dart';
import 'profile_share_card.dart';

/// The localized display name of a 2×2 profile type.
String profileTypeName(AppLocalizations l10n, DebateProfileType type) {
  return switch (type) {
    DebateProfileType.pillar => l10n.profileTypePillar,
    DebateProfileType.flow => l10n.profileTypeFlow,
    DebateProfileType.wolf => l10n.profileTypeWolf,
    DebateProfileType.seeker => l10n.profileTypeSeeker,
  };
}

/// The localized one-line description of a 2×2 profile type.
String profileTypeDescription(AppLocalizations l10n, DebateProfileType type) {
  return switch (type) {
    DebateProfileType.pillar => l10n.profileDescPillar,
    DebateProfileType.flow => l10n.profileDescFlow,
    DebateProfileType.wolf => l10n.profileDescWolf,
    DebateProfileType.seeker => l10n.profileDescSeeker,
  };
}

/// The debate-profile block rendered UNDER the conformity axis in the same
/// panel — an extension of the axis, deliberately not a screen of its own.
///
/// Three states off `get_debate_profile`:
///  * locked — a progress bar toward the unlock threshold, driven by the
///    counter that is FURTHER behind (votes vs qualifying gate answers);
///  * provisional (6–11) — the 2×2 grid and type with a "profil wstępny" tag;
///  * full (12+) — the same without the tag.
///
/// The free/PRO split follows one rule: **the present is free, the past and
/// the comparison are paid.** The type, both current percentages and the
/// share card are FREE — a free user who never sees their type never wants
/// the depth behind it. The depth (trend over time, type rarity, the
/// arguments that flipped you, the loneliest vote) is PRO, shown to free
/// users as locked rows whose visible counters do the selling.
class DebateProfileSection extends ConsumerWidget {
  const DebateProfileSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(debateProfileProvider);
    final profile = profileAsync.value;
    // Loading/error: render nothing — the axis above stands on its own, and
    // the section reappears the moment the (prefetched) profile lands.
    if (profile == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 22),
        const Divider(height: 1),
        const SizedBox(height: 16),
        if (profile.stage == DebateProfileStage.locked)
          _LockedProfileView(profile: profile)
        else
          _UnlockedProfileView(profile: profile),
      ],
    );
  }
}

/// Pre-unlock retention hook: never an empty hole. Shows how close the type
/// is, counting on whichever requirement (votes / answered gates) is further
/// from the threshold.
class _LockedProfileView extends StatelessWidget {
  const _LockedProfileView({required this.profile});

  final DebateProfile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final done = profile.limitingCounter;
    final total = profile.unlockMin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.profileSectionTitle.toUpperCase(),
          style: AppTypography.eyebrow(
            fontSize: 11,
            tracking: 0.18,
          ).copyWith(color: context.colors.subtle),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.profileProgress(profile.answersToUnlock),
          style: AppTypography.body(
            fontSize: 14,
            height: 1.4,
          ).copyWith(color: context.colors.ink),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : (done / total).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: AppTheme.spark.withValues(alpha: 0.18),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppTheme.spark,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$done / $total',
              style: AppTypography.numeric(
                16,
              ).copyWith(color: context.colors.subtle),
            ),
          ],
        ),
      ],
    );
  }
}

/// The unlocked profile: header (+ provisional tag + share), the 2×2 grid,
/// the active type's description, both axis percentages, then the PRO depth
/// (real for PRO, one locked upsell row for free).
class _UnlockedProfileView extends ConsumerStatefulWidget {
  const _UnlockedProfileView({required this.profile});

  final DebateProfile profile;

  @override
  ConsumerState<_UnlockedProfileView> createState() =>
      _UnlockedProfileViewState();
}

class _UnlockedProfileViewState extends ConsumerState<_UnlockedProfileView> {
  bool _sharing = false;
  bool _busy = false;

  Future<void> _share() async {
    if (_sharing) return;
    final l10n = context.l10n;
    final profile = widget.profile;
    final view = View.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;

    setState(() => _sharing = true);
    Analytics.log('share_card_opened', {'type': 'profile'});
    try {
      final params = await _buildShareParams(
        l10n: l10n,
        profile: profile,
        view: view,
        origin: origin,
      );
      await SharePlus.instance.share(params);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Renders the [ProfileShareCard] poster and bundles it with the signoff
  /// text, degrading to text-only if the card can't be rendered — the share
  /// button never dead-ends.
  Future<ShareParams> _buildShareParams({
    required AppLocalizations l10n,
    required DebateProfile profile,
    required ui.FlutterView view,
    required Rect? origin,
  }) async {
    final typeName = profileTypeName(l10n, profile.type);
    final message = l10n.profileShareMessage(typeName);
    final crowd = profile.withCrowd
        ? l10n.profileShareCrowdWith(profile.conformityPct)
        : l10n.profileShareCrowdAgainst(100 - profile.conformityPct);
    try {
      final png = await renderWidgetToPng(
        child: ProfileShareCard(
          type: profile.type,
          typeName: typeName,
          headline: l10n.profileShareHeadline,
          questionsLine: l10n.profileShareQuestionsLine(
            profile.totalVotes,
            crowd,
          ),
          movedLine: l10n.profileShareMovedLine(profile.gateMoved),
          footer: l10n.profileShareFooter,
          provisionalTag: profile.stage == DebateProfileStage.provisional
              ? l10n.profileProvisional
              : null,
        ),
        logicalSize: const Size(360, 640),
        view: view,
      );
      if (png != null) {
        return ShareParams(
          text: message,
          subject: l10n.profileShareSubject,
          sharePositionOrigin: origin,
          files: [
            XFile.fromData(
              png,
              mimeType: 'image/png',
              name: 'debatly-profile.png',
            ),
          ],
        );
      }
    } catch (e) {
      debugPrint('profile share card render failed, sharing text only: $e');
    }
    return ShareParams(
      text: message,
      subject: l10n.profileShareSubject,
      sharePositionOrigin: origin,
    );
  }

  Future<void> _getPremium() async {
    setState(() => _busy = true);
    // The one sanctioned per-entry paywall headline: opened from the locked
    // portrait rows, it sells the PORTRAIT ("{n} głosów. Zobacz, co mówią o
    // Tobie."), not the catalog — see showProPaywall.
    final purchased = await showProPaywall(
      context,
      source: PaywallSource.profile,
      headline: context.l10n.paywallProfileHeadline(widget.profile.totalVotes),
    );
    if (!mounted) return;
    if (purchased) {
      // The session refresh flips isPremium, which rebuilds the repository —
      // the autoDispose profile providers refetch on their own and the PRO
      // depth renders in place of the locked row.
      await ref.read(sessionProvider.notifier).refresh();
      if (!mounted) return;
      setState(() => _busy = false);
      await promptSaveProAccount(context, ref);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profile = widget.profile;
    final isPremium = ref.watch(isPremiumProvider);
    final provisional = profile.stage == DebateProfileStage.provisional;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              l10n.profileSectionTitle.toUpperCase(),
              style: AppTypography.eyebrow(
                fontSize: 11,
                tracking: 0.18,
              ).copyWith(color: context.colors.subtle),
            ),
            if (provisional) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: context.colors.hairline),
                ),
                child: Text(
                  l10n.profileProvisional,
                  style: AppTypography.support(
                    fontSize: 11,
                  ).copyWith(color: context.colors.subtle),
                ),
              ),
            ],
            const Spacer(),
            IconButton(
              onPressed: _sharing ? null : _share,
              tooltip: l10n.shareLabel,
              visualDensity: VisualDensity.compact,
              icon: _sharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.share_rounded,
                      size: 20,
                      color: context.colors.subtle,
                    ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _TypeGrid(active: profile.type, l10n: l10n),
        const SizedBox(height: 12),
        Text(
          profileTypeDescription(l10n, profile.type),
          style: AppTypography.body(
            fontSize: 14,
            height: 1.4,
          ).copyWith(color: context.colors.ink),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                value: '${profile.conformityPct}%',
                label: l10n.profileStatCrowdLabel,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                value: '${profile.movedPct}%',
                label: l10n.profileStatMovedLabel,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (isPremium)
          _ProDepth(l10n: l10n)
        else
          _LockedDepthList(profile: profile, onTap: _busy ? null : _getPremium),
      ],
    );
  }
}

/// The 2×2 grid itself: columns = resilient / movable, rows = with / against
/// the crowd. The user's cell is lit in spark; the other three stay quiet but
/// legible — all four names carry equal dignity, none reads as a punishment.
class _TypeGrid extends StatelessWidget {
  const _TypeGrid({required this.active, required this.l10n});

  final DebateProfileType active;
  final AppLocalizations l10n;

  static const List<List<DebateProfileType>> _layout = [
    [DebateProfileType.pillar, DebateProfileType.flow],
    [DebateProfileType.wolf, DebateProfileType.seeker],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in _layout)
          Padding(
            padding: EdgeInsets.only(bottom: row == _layout.last ? 0 : 8),
            child: Row(
              children: [
                for (final type in row) ...[
                  if (type != row.first) const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 52,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: type == active
                            ? AppTheme.spark
                            : context.colors.accent,
                        border: type == active
                            ? null
                            : Border.all(color: context.colors.hairline),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          profileTypeName(l10n, type).toUpperCase(),
                          maxLines: 1,
                          style:
                              AppTypography.eyebrow(
                                fontSize: 12,
                                tracking: 0.1,
                              ).copyWith(
                                color: type == active
                                    ? AppTheme.ctaForeground
                                    : context.colors.subtle,
                              ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// One of the two percentage tiles under the grid: a big number over its
/// quiet label.
class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTypography.numeric(22).copyWith(color: AppTheme.spark),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.support(
              fontSize: 11.5,
            ).copyWith(color: context.colors.subtle),
          ),
        ],
      ),
    );
  }
}

/// The free tier's view of the PRO depth: a list of locked rows, one per
/// feature, each opening the portrait paywall. The TYPE above stays free —
/// these rows sell only what sits below the surface.
///
/// The persuasion rule: **the counter is visible, the content is locked.** A
/// number sells; a bare padlock doesn't. "Zdania, które Cię przewróciły"
/// therefore shows the user's REAL moved count (free data — it rides in
/// `get_debate_profile`), and grows on its own with every gate. And a row
/// whose counter is zero is not shown at all — an empty vault teaches that
/// the feature is worthless.
class _LockedDepthList extends StatelessWidget {
  const _LockedDepthList({required this.profile, required this.onTap});

  final DebateProfile profile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (profile.gateMoved > 0)
          _LockedRow(
            label: l10n.profileLockedFlips,
            count: profile.gateMoved,
            onTap: onTap,
          ),
        _LockedRow(label: l10n.profileLockedLoneliest, onTap: onTap),
        _LockedRow(label: l10n.profileLockedRarity, onTap: onTap),
        _LockedRow(label: l10n.profileLockedTrend, onTap: onTap),
      ],
    );
  }
}

/// One locked feature row: label, the optional live counter in spark, a lock.
class _LockedRow extends StatelessWidget {
  const _LockedRow({required this.label, required this.onTap, this.count});

  final String label;
  final VoidCallback? onTap;

  /// Real per-user number shown next to the lock — the persuasion. Null for
  /// rows that have no free-tier counter.
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.colors.hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.body(
                    fontSize: 13.5,
                    height: 1.35,
                  ).copyWith(color: context.colors.ink),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 10),
                Text(
                  '$count',
                  style: AppTypography.numeric(
                    18,
                  ).copyWith(color: AppTheme.spark),
                ),
              ],
              const SizedBox(width: 10),
              Icon(Icons.lock_rounded, size: 16, color: context.colors.subtle),
            ],
          ),
        ),
      ),
    );
  }
}

/// The PRO depth — "the past and the comparison": type rarity, the monthly
/// trend, the arguments that flipped the user, and their loneliest vote.
/// (The present — type, percentages, share — is free above; the category
/// breakdown was pulled until the catalog's English category labels are
/// localized.) Each block quietly shows "not enough data" until it has
/// something real; a failed fetch renders nothing (the panel is a stat, not a
/// dead end).
class _ProDepth extends ConsumerWidget {
  const _ProDepth({required this.l10n});

  final AppLocalizations l10n;

  /// The vote where the user's side was smallest — their loneliest moment.
  /// Only a vote actually in the minority qualifies (a "loneliest" vote that
  /// sat with 55% of the room would undercut the feature); null hides the
  /// block.
  static (VoteHistoryEntry, int)? loneliestVote(
    List<VoteHistoryEntry> history,
  ) {
    VoteHistoryEntry? best;
    var bestShare = 2.0;
    for (final entry in history) {
      final my = entry.votes.myChoice;
      final total = entry.votes.yesCount + entry.votes.noCount;
      if (my == null || total <= 0) continue;
      final mine = my == VoteResult.yes
          ? entry.votes.yesCount
          : entry.votes.noCount;
      final share = mine / total;
      if (share < bestShare) {
        bestShare = share;
        best = entry;
      }
    }
    if (best == null || bestShare > 0.5) return null;
    return (best, (bestShare * 100).round());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rarity = ref.watch(typeRarityProvider).value;
    final trend = ref.watch(profileTrendProvider).value;
    final moved = ref.watch(movedSmaczkiProvider).value;
    final history = ref.watch(voteHistoryProvider).value;
    final loneliest = history == null ? null : loneliestVote(history);
    final locale = Localizations.localeOf(context).toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Rarity: one spark-accented line, no title — the number IS the
        // content. Hidden while the server withholds it (population floor /
        // caller's own profile still locked server-side).
        if (rarity != null) ...[
          Row(
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                size: 16,
                color: AppTheme.spark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.profileRarityLine(rarity),
                  style: AppTypography.body(
                    fontSize: 13.5,
                  ).copyWith(color: context.colors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (trend != null) ...[
          _DepthTitle(text: l10n.profileLockedTrend),
          if (trend.isEmpty)
            _NotEnoughData(l10n: l10n)
          else
            for (final point
                in trend.length <= 6 ? trend : trend.sublist(trend.length - 6))
              _DepthRow(
                label: DateFormat.yMMM(locale).format(point.month),
                line: l10n.profileSliceLine(
                  point.conformityPct,
                  point.gateMoved,
                ),
              ),
          const SizedBox(height: 14),
        ],
        if (moved != null) ...[
          _DepthTitle(text: l10n.profileLockedFlips),
          if (moved.isEmpty)
            _NotEnoughData(l10n: l10n)
          else
            for (final entry in moved.take(5)) _MovedQuote(entry: entry),
          const SizedBox(height: 14),
        ],
        if (loneliest != null) ...[
          _DepthTitle(text: l10n.profileLockedLoneliest),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.colors.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loneliest.$1.questionText,
                  style: AppTypography.body(
                    fontSize: 13.5,
                    height: 1.35,
                  ).copyWith(color: context.colors.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.profileLoneliestLine(loneliest.$2),
                  style: AppTypography.support(
                    fontSize: 11.5,
                  ).copyWith(color: AppTheme.spark),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DepthTitle extends StatelessWidget {
  const _DepthTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: AppTypography.eyebrow(
          fontSize: 10.5,
          tracking: 0.14,
        ).copyWith(color: context.colors.subtle),
      ),
    );
  }
}

class _DepthRow extends StatelessWidget {
  const _DepthRow({required this.label, required this.line});

  final String label;
  final String line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.support(
                fontSize: 12.5,
              ).copyWith(color: context.colors.ink),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              line,
              style: AppTypography.support(
                fontSize: 12.5,
              ).copyWith(color: context.colors.subtle),
            ),
          ),
        ],
      ),
    );
  }
}

/// One argument that flipped the user: the smaczek as a quote, its question
/// underneath in the quiet cut.
class _MovedQuote extends StatelessWidget {
  const _MovedQuote({required this.entry});

  final MovedSmaczek entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: context.colors.accent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.smaczekText,
              style: AppTypography.body(
                fontSize: 13.5,
                height: 1.35,
              ).copyWith(color: context.colors.ink),
            ),
            const SizedBox(height: 3),
            Text(
              entry.questionText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.support(
                fontSize: 11.5,
              ).copyWith(color: context.colors.subtle),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotEnoughData extends StatelessWidget {
  const _NotEnoughData({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        l10n.profileNotEnoughData,
        style: AppTypography.support(
          fontSize: 12.5,
        ).copyWith(color: context.colors.subtle),
      ),
    );
  }
}
