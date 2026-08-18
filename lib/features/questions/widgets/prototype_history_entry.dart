// PROTOTYPE — DELETE OR FOLD IN WHEN APPROVED. Not production code.
//
// Question: what should the post-vote "see your history" entry point look
// like, and what should the free tier's gated history look like?
//
// Verdict so far: the quiet link won — a small borderless "Zobacz swoją
// historię" button under the result bars, nothing else (the variant switcher,
// the boxed-card and teaser-first variants, and the muted hook line are gone).
// Still open: final copy + promotion to real code (ARB strings, analytics).
//
// Tapping: PRO → the real HistoryScreen; free → _PrototypeGatedHistory below
// (newest entry visible, rest blurred under a big lock + "see your full
// history" upsell → paywall). LONG-PRESS the button to preview the free path
// — mock mode always resolves premium, so there's no other way to reach it.
//
// Everything is kDebugMode-gated and skipped under `flutter test`; strings
// are hard-coded PL/EN on purpose (they move to the ARBs when promoted).

import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sub_screen_chrome.dart';
import '../../../data/models/vote_history_entry.dart';
import '../../../data/models/vote_result.dart';
import '../../account/providers/session_providers.dart';
import '../../monetization/widgets/pro_paywall_screen.dart';
import '../providers/question_providers.dart';
import '../screens/history_screen.dart';

/// Prototype-only override, flipped by long-pressing the button: pretend to
/// be a free user so the gated history is reachable in mock mode (which
/// always resolves premium). Top-level so it survives the vote panel
/// remounting on every swipe / vote.
final ValueNotifier<bool> _forceFree = ValueNotifier<bool>(false);

bool _isPl(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'pl';

String _t(BuildContext context, String pl, String en) =>
    _isPl(context) ? pl : en;

/// The post-vote "see your history" entry: a small borderless link mounted
/// under [VoteResultsRow] once a vote is cast. Renders nothing outside debug
/// builds — a stray merge can't ship it.
class PrototypeHistoryEntry extends ConsumerWidget {
  const PrototypeHistoryEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Debug builds only — and not in `flutter test`, which also runs in debug
    // mode and would otherwise see the prototype in every post-vote layout.
    if (!kDebugMode || Platform.environment.containsKey('FLUTTER_TEST')) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<bool>(
      valueListenable: _forceFree,
      builder: (context, forceFree, _) {
        final isPremium = ref.watch(isPremiumProvider) && !forceFree;

        return TextButton.icon(
          onPressed: () => _openHistory(context, isPremium: isPremium),
          // Prototype-only: long-press flips the FREE preview (the tiny lock
          // next to the label shows it's on).
          onLongPress: () => _forceFree.value = !forceFree,
          icon: Icon(
            Icons.history_rounded,
            size: 17,
            color: context.colors.ink,
          ),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _t(
                    context,
                    'Zobacz swoją historię',
                    'See your history',
                  ).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.action(
                    fontSize: 13,
                  ).copyWith(color: context.colors.ink),
                ),
              ),
              if (!isPremium) ...[
                const SizedBox(width: 5),
                Icon(
                  Icons.lock_rounded,
                  size: 12,
                  color: context.colors.subtle,
                ),
              ],
            ],
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: const Size(0, 36),
          ),
        );
      },
    );
  }

  void _openHistory(BuildContext context, {required bool isPremium}) {
    if (isPremium) {
      openHistory(context);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const _PrototypeGatedHistory()),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// The free tier's gated history: the newest entry in the clear, everything
// older blurred under one big lock + "see your full history" → paywall.
// ---------------------------------------------------------------------------

class _PrototypeGatedHistory extends ConsumerWidget {
  const _PrototypeGatedHistory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(voteHistoryProvider);
    final lang = Localizations.localeOf(context).languageCode;

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
                        title: context.l10n.historyTitle,
                        onClose: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(height: 16),
                      historyAsync.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.only(top: 48),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (_, _) => Padding(
                          padding: const EdgeInsets.only(top: 48),
                          child: Center(
                            child: Text(
                              context.l10n.historyLoadError,
                              style: AppTypography.body(
                                fontSize: 14,
                              ).copyWith(color: context.colors.subtle),
                            ),
                          ),
                        ),
                        data: (entries) =>
                            _GatedBody(entries: entries, lang: lang),
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
}

class _GatedBody extends StatelessWidget {
  const _GatedBody({required this.entries, required this.lang});

  final List<VoteHistoryEntry> entries;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final newest = entries.isNotEmpty ? entries.first : _fakeEntries.first;
    // The blurred stack behind the lock. Pad with fakes so it always has
    // enough body to sell "there's more here" — it's unreadable anyway.
    final locked = <VoteHistoryEntry>[...entries.skip(1).take(4)];
    while (locked.length < 4) {
      locked.add(_fakeEntries[locked.length % _fakeEntries.length]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t(context, 'TWÓJ OSTATNI GŁOS', 'YOUR LATEST VOTE'),
          style: AppTypography.eyebrow(
            fontSize: 11,
          ).copyWith(color: context.colors.subtle),
        ),
        const SizedBox(height: 10),
        _ProtoRow(entry: newest, lang: lang),
        const SizedBox(height: 22),
        _LockedStack(locked: locked, lang: lang),
      ],
    );
  }
}

/// The blurred older entries with the big lock and the upsell over them.
/// Tapping anywhere on it opens the paywall.
class _LockedStack extends ConsumerWidget {
  const _LockedStack({required this.locked, required this.lang});

  final List<VoteHistoryEntry> locked;
  final String lang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => showProPaywall(context, source: PaywallSource.history),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The rows, blurred and inert. ClipRect keeps the blur from
          // bleeding past the list's own bounds.
          IgnorePointer(
            child: ClipRect(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in locked) ...[
                      _ProtoRow(entry: entry, lang: lang),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // A soft scrim so the lock + copy hold contrast over any split.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.colors.background.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_rounded, size: 56, color: context.colors.ink),
              const SizedBox(height: 14),
              Text(
                _t(
                  context,
                  'Zobacz pełną historię',
                  'See your full history',
                ).toUpperCase(),
                textAlign: TextAlign.center,
                style: AppTypography.title(
                  fontSize: 30,
                ).copyWith(color: context.colors.ink),
              ),
              const SizedBox(height: 6),
              Text(
                _t(
                  context,
                  'Każde pytanie, na które zagłosujesz,\nzostaje tu na zawsze — w PRO.',
                  'Every question you vote on\nstays here forever — with PRO.',
                ),
                textAlign: TextAlign.center,
                style: AppTypography.support(
                  fontSize: 13,
                  height: 1.4,
                ).copyWith(color: context.colors.subtle),
              ),
              const SizedBox(height: 18),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppTheme.ctaGradient,
                  borderRadius: AppTheme.ctaRadius,
                  boxShadow: AppTheme.ctaGlow,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  child: Text(
                    context.l10n.goPro.toUpperCase(),
                    style: AppTypography.action(
                      fontSize: 14,
                    ).copyWith(color: AppTheme.ctaForeground),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A compact history row — a lightweight stand-in for the real screen's
/// private `_HistoryRow`, close enough to judge the gated layout.
class _ProtoRow extends StatelessWidget {
  const _ProtoRow({required this.entry, required this.lang});

  final VoteHistoryEntry entry;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final d = entry.votedAt.toLocal();
    final mineYes = entry.votes.myChoice == VoteResult.yes;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: context.colors.accent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${d.day}.${d.month.toString().padLeft(2, '0')}.${d.year}',
            style: AppTypography.support().copyWith(
              color: context.colors.subtle,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            entry.questionText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.body(
              fontSize: 14.5,
              height: 1.32,
            ).copyWith(color: context.colors.ink),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${context.l10n.voteYes.toUpperCase()} ${entry.votes.yesPct}%',
                style: AppTypography.eyebrow(
                  fontSize: 11,
                  tracking: 0.12,
                ).copyWith(color: AppTheme.yes),
              ),
              if (mineYes)
                const Padding(
                  padding: EdgeInsets.only(left: 3),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.yes,
                    size: 12,
                  ),
                ),
              const Spacer(),
              if (!mineYes && entry.votes.hasVoted)
                const Padding(
                  padding: EdgeInsets.only(right: 3),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.no,
                    size: 12,
                  ),
                ),
              Text(
                '${entry.votes.noPct}% ${context.l10n.voteNo.toUpperCase()}',
                style: AppTypography.eyebrow(
                  fontSize: 11,
                  tracking: 0.12,
                ).copyWith(color: AppTheme.no),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: AppTheme.no.withValues(alpha: 0.85),
                    ),
                  ),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: entry.votes.yesFraction.clamp(0.0, 1.0),
                    child: ColoredBox(
                      color: AppTheme.yes.withValues(alpha: 0.95),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Filler rows for the blurred stack (and the clear slot when the account has
/// no history yet) — the text is unreadable behind the blur, it just has to
/// look like a real list.
final List<VoteHistoryEntry> _fakeEntries = [
  VoteHistoryEntry(
    questionId: 'proto-1',
    category: 'general',
    questionText: 'Czy pieniądze dają szczęście?',
    votedAt: DateTime.now().subtract(const Duration(days: 1)),
    votes: const VoteResult(yesCount: 58, noCount: 42, myChoice: 1),
  ),
  VoteHistoryEntry(
    questionId: 'proto-2',
    category: 'general',
    questionText: 'Czy zdrada emocjonalna jest gorsza od fizycznej?',
    votedAt: DateTime.now().subtract(const Duration(days: 2)),
    votes: const VoteResult(yesCount: 71, noCount: 29, myChoice: 2),
  ),
  VoteHistoryEntry(
    questionId: 'proto-3',
    category: 'general',
    questionText: 'Czy praca zdalna niszczy relacje w zespole?',
    votedAt: DateTime.now().subtract(const Duration(days: 3)),
    votes: const VoteResult(yesCount: 44, noCount: 56, myChoice: 1),
  ),
  VoteHistoryEntry(
    questionId: 'proto-4',
    category: 'general',
    questionText: 'Czy sztuczna inteligencja zabierze nam pracę?',
    votedAt: DateTime.now().subtract(const Duration(days: 4)),
    votes: const VoteResult(yesCount: 63, noCount: 37, myChoice: 2),
  ),
];
