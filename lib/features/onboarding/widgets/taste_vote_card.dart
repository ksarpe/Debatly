import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/vote_result.dart';
import '../../../services/analytics.dart';
import '../../../services/supabase_service.dart';
import '../../questions/widgets/falling_words_text.dart';
import '../../questions/widgets/vote_visuals.dart';
import 'onboarding_primary_button.dart';

/// The onboarding "aha", staged as a mind-change loop run twice: the user
/// votes, and the takeover serves four COUNTER-arguments — the pool depends
/// on which side they picked, and every line argues against it. Then a stance
/// choice instead of a re-vote: "Zmieniam zdanie" jumps straight to the
/// reveal under a gotcha headline, "Zostaję przy swoim" under a respectful
/// one — both in the question font, both over the live split.
///
/// The reactions escalate across the rounds: round one plays the moment
/// itself ("A jednak, mamy Cię!" / "Warto trzymać swoje stanowisko!", closed
/// by "Zobaczmy kolejne"), while round two sells the catalog — "Widzisz? Nic
/// nie jest oczywiste." / "Ciebie nie da się ruszyć?" with a teaser subline,
/// closed by "Co jeszcze macie?", the question the bridge card's "To były
/// dwa. Zostało 500." then answers.
///
/// This is a no-stakes TASTE: the votes are never cast, so it works instantly,
/// offline and pre-login, and never touches the streak/credit logic. The real,
/// counting vote happens on the daily right after onboarding. The revealed
/// splits ARE live, though: each question's all-time tally is fetched in the
/// background while the user reads (see [_loadLiveSplit]), falling back to a
/// curated 50/50 when there's no backend to ask. It reuses the exact
/// [VoteButtonsRow] / [VoteResultsRow] visuals — and the same word-by-word
/// [FallingWordsText] entrance — so it looks like the real thing.
class TasteVoteCard extends StatefulWidget {
  const TasteVoteCard({super.key, required this.onContinue, this.fastForward});

  /// Advances to the next onboarding page once the user has had their moment.
  final VoidCallback onContinue;

  /// The screen's "hurry up" signal — fired when a tap lands on no control.
  /// During the arguments takeover it sprints the 5.6s stagger to the end
  /// (all four counter-arguments + the stance pair at once); during the
  /// interlude it jumps straight into round two. The beats themselves are
  /// never skipped — only their waiting.
  final Listenable? fastForward;

  @override
  State<TasteVoteCard> createState() => _TasteVoteCardState();
}

/// One round's beats, in order: first gut vote → the counter-arguments
/// takeover (ending in the stance choice) → the community-split reveal.
/// [interlude] is the "let's try another…" beat bridging round one's result
/// into round two.
enum _Stage { vote, arguments, result, interlude }

class _TasteVoteCardState extends State<TasteVoteCard>
    with SingleTickerProviderStateMixin {
  /// The catalog ids of the two taste questions, in play order ("Czy osoby
  /// otyłe powinny płacić za dwa miejsca w samolocie?" then "Czy powinieneś
  /// mówić nowemu partnerowi, z iloma osobami spałeś?"), so their real
  /// all-time splits can be fetched. The on-card text stays in the ARBs — the
  /// catalog rows only supply the tallies — so the two must be kept in sync by
  /// hand when swapping a taste question.
  static const List<String> _kQuestionIds = [
    '8b54aec1-b9a0-41b7-9a2d-766d886cfe50',
    'ad75972d-1304-4058-b237-cddd2714eded',
  ];

  /// The live all-time splits per round, fetched in the background by
  /// [_loadLiveSplit]. Null until they arrive (or forever in mock mode /
  /// offline) — each reveal then falls back to a dead-even 1:1, so neither
  /// side feels alone right after being made to doubt.
  final List<VoteResult?> _live = [null, null];

  _Stage _stage = _Stage.vote;

  /// Which question is on stage: 0 or 1, indexing [_kQuestionIds].
  int _round = 0;

  /// The gut pick, before the arguments. Reset for round two.
  int? _firstChoice;

  /// The considered pick, after the arguments; highlights its side in the split.
  int? _secondChoice;

  /// Times the takeover: the title stands alone for the first second, the
  /// arguments land at 1.0s / 2.0s / 3.0s / 4.0s, then a full beat of silence
  /// before the stance pair closes the run at 5.3s. See the [Interval]s in
  /// [_argumentsStage].
  static const double _argsRunMs = 5600;

  // Created eagerly in [initState]: a lazy `late final` initializer would run
  // on first touch, and if the card is disposed while still on the first vote
  // stage that first touch is `dispose()` itself — creating a Ticker during
  // teardown, when the TickerMode ancestor lookup is no longer safe.
  late final AnimationController _argsIn;

  /// Auto-advances the "let's try another…" interlude into round two.
  Timer? _interludeTimer;

  @override
  void initState() {
    super.initState();
    _argsIn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    );
    for (var round = 0; round < _kQuestionIds.length; round++) {
      unawaited(_loadLiveSplit(round));
    }
    widget.fastForward?.addListener(_onFastForward);
  }

  @override
  void didUpdateWidget(TasteVoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fastForward != widget.fastForward) {
      oldWidget.fastForward?.removeListener(_onFastForward);
      widget.fastForward?.addListener(_onFastForward);
    }
  }

  /// A tap outside any control while a timed beat is playing: finish the beat
  /// now. The arguments run dashes to its end (a 300ms sprint, not a hard
  /// jump, so the remaining lines fade in rather than pop), the interlude's
  /// two-second pause is cut short into round two's question.
  void _onFastForward() {
    if (_stage == _Stage.arguments && !_argsIn.isCompleted) {
      _argsIn.animateTo(
        1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else if (_stage == _Stage.interlude) {
      _interludeTimer?.cancel();
      _enterNextRound();
    }
  }

  /// Fetches one taste question's real community tally while the user is busy
  /// voting and reading — by that round's reveal it has long since landed.
  /// Fire-and-forget: any failure just keeps the curated 50/50 fallback, and a
  /// result that arrives after the round's reveal is already on screen is
  /// dropped so the split never jumps mid-look.
  Future<void> _loadLiveSplit(int round) async {
    final split = await SupabaseService.fetchVoteSplit(_kQuestionIds[round]);
    if (!mounted) return;
    final revealed =
        _round > round || (_round == round && _stage == _Stage.result);
    if (revealed) return;
    if (split == null || split.yes + split.no == 0) return;
    setState(() {
      _live[round] = VoteResult(yesCount: split.yes, noCount: split.no);
    });
  }

  @override
  void dispose() {
    widget.fastForward?.removeListener(_onFastForward);
    _interludeTimer?.cancel();
    _argsIn.dispose();
    super.dispose();
  }

  void _onFirstVote(int choice) {
    setState(() {
      _firstChoice = choice;
      _stage = _Stage.arguments;
    });
    _argsIn.forward(from: 0);
    Analytics.log('onboarding_taste_voted', {
      'choice': choice == VoteResult.yes ? 'tak' : 'nie',
      'round': _round + 1,
    });
    // The freemium funnel's canonical per-question event (0-indexed); the
    // richer taste event above stays for continuity.
    Analytics.log('onboarding_q_voted', {'index': _round});
  }

  /// The takeover ends in a stance, not a re-vote: the user either concedes
  /// to the counter-arguments or holds the line, and lands straight on the
  /// reveal. Reported through the `onboarding_taste_revoted` event the old
  /// re-vote used, so the changed-mind funnel stays comparable across
  /// releases.
  void _onStanceChosen({required bool changedMind}) {
    final first = _firstChoice!;
    final second = !changedMind
        ? first
        : (first == VoteResult.yes ? VoteResult.no : VoteResult.yes);
    setState(() {
      _secondChoice = second;
      _stage = _Stage.result;
    });
    Analytics.log('onboarding_taste_revoted', {
      'choice': second == VoteResult.yes ? 'tak' : 'nie',
      'changed_mind': changedMind,
      'round': _round + 1,
    });
  }

  /// The result stage's button: after round one it rolls into the interlude
  /// and, two seconds later, round two; after round two it leaves the card.
  void _onResultContinue() {
    if (_round + 1 >= _kQuestionIds.length) {
      widget.onContinue();
      return;
    }
    setState(() {
      _round += 1;
      _stage = _Stage.interlude;
      _firstChoice = null;
      _secondChoice = null;
    });
    _interludeTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      _enterNextRound();
    });
  }

  /// Puts round two's question on stage — off the interlude timer, or early
  /// via [_onFastForward].
  void _enterNextRound() {
    setState(() => _stage = _Stage.vote);
    // Round two's question is on stage (round one's `onboarding_q_shown`
    // fires from the screen when the taste page is reached).
    Analytics.log('onboarding_q_shown', {'index': _round});
  }

  @override
  Widget build(BuildContext context) {
    // Centred, but scrollable so the taller stages (the four arguments, or
    // the headline + split + Continue) never overflow on short screens or
    // large text. The whole card swaps per stage: the arguments takeover
    // replaces the question entirely, then the stance reveal takes over from
    // it.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: switch (_stage) {
            _Stage.vote => _questionStage(
              context,
              key: 'taste-vote-$_round',
              children: [VoteButtonsRow(busy: false, onVote: _onFirstVote)],
            ),
            _Stage.arguments => _argumentsStage(context),
            _Stage.result => _stanceResultStage(context),
            _Stage.interlude => _interludeStage(context),
          },
        ),
      ),
    );
  }

  /// The vote stage: the "TWÓJ RUCH" kicker + question text on top,
  /// [children] (the TAK/NIE buttons) underneath.
  Widget _questionStage(
    BuildContext context, {
    required String key,
    required List<Widget> children,
  }) {
    final l10n = context.l10n;
    final question = _round == 0
        ? l10n.onboardingTasteQuestion
        : l10n.onboardingTasteQuestion2;
    return Column(
      key: ValueKey(key),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.onboardingTasteKicker.toUpperCase(),
          style: AppTypography.eyebrow(
            fontSize: 11,
          ).copyWith(color: AppTheme.spark),
        ),
        const SizedBox(height: 22),
        // The same word-by-word entrance as the real feed; keyed per round
        // (see the caller's ValueKey), so the question re-assembles for
        // round two.
        FallingWordsText(question),
        const SizedBox(height: 34),
        ...children,
      ],
    );
  }

  /// The reveal: a stance-aware headline in the question font — the gotcha
  /// for a changed mind, the respectful nod for a held one — a small subline,
  /// the live split, and the continue CTA. Round one's copy plays the moment
  /// ("A jednak, mamy Cię!" → "Zobaczmy kolejne"); round two's teases the
  /// catalog ("A to było dopiero drugie pytanie…" → "Co jeszcze macie?"),
  /// setting up the bridge card's "To były dwa. Zostało 500." as the answer.
  Widget _stanceResultStage(BuildContext context) {
    final l10n = context.l10n;
    final changed = _secondChoice != _firstChoice;
    final (title, sub) = _round == 0
        ? (changed
              ? (l10n.onboardingTasteGotYouTitle, l10n.onboardingTasteGotYouSub)
              : (
                  l10n.onboardingTasteStandFirmTitle,
                  l10n.onboardingTasteStandFirmSub,
                ))
        : (changed
              ? (
                  l10n.onboardingTasteQ2GotYouTitle,
                  l10n.onboardingTasteQ2GotYouSub,
                )
              : (
                  l10n.onboardingTasteQ2StandFirmTitle,
                  l10n.onboardingTasteQ2StandFirmSub,
                ));
    return Column(
      key: ValueKey('taste-stance-result-$_round'),
      mainAxisSize: MainAxisSize.min,
      children: [
        FallingWordsText(title),
        const SizedBox(height: 14),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: AppTypography.body(
            fontSize: 15,
            height: 1.4,
          ).copyWith(color: context.colors.subtle),
        ),
        const SizedBox(height: 30),
        VoteResultsRow(
          result: VoteResult(
            yesCount: _live[_round]?.yesCount ?? 1,
            noCount: _live[_round]?.noCount ?? 1,
            myChoice: _secondChoice,
          ),
        ),
        const SizedBox(height: 24),
        OnboardingPrimaryButton(
          label: _round == 0
              ? l10n.onboardingTasteSeeNext
              : l10n.onboardingTasteWhatElse,
          onPressed: _onResultContinue,
        ),
      ],
    );
  }

  /// The takeover after the gut vote: a bare title — "Ale chwila…" in round
  /// one, "Czy aby na pewno?" in round two — alone at centre stage, then the
  /// four COUNTER-arguments landing one by one — no card chrome, just a bare
  /// orange number and a larger line. The pool depends on the side just
  /// picked, so every line argues against it; the closing beat is the stance
  /// pair — "Zmieniam zdanie" over a quiet "Zostaję przy swoim".
  Widget _argumentsStage(BuildContext context) {
    final l10n = context.l10n;
    final title = _round == 0
        ? l10n.onboardingTasteHoldOnTitle
        : l10n.onboardingTasteSureTitle;
    final votedYes = _firstChoice == VoteResult.yes;
    final smaczki = _round == 0
        ? (votedYes
              ? [
                  l10n.onboardingTasteVotedTakSmaczek1,
                  l10n.onboardingTasteVotedTakSmaczek2,
                  l10n.onboardingTasteVotedTakSmaczek3,
                  l10n.onboardingTasteVotedTakSmaczek4,
                ]
              : [
                  l10n.onboardingTasteVotedNieSmaczek1,
                  l10n.onboardingTasteVotedNieSmaczek2,
                  l10n.onboardingTasteVotedNieSmaczek3,
                  l10n.onboardingTasteVotedNieSmaczek4,
                ])
        : (votedYes
              ? [
                  l10n.onboardingTasteQ2VotedTakSmaczek1,
                  l10n.onboardingTasteQ2VotedTakSmaczek2,
                  l10n.onboardingTasteQ2VotedTakSmaczek3,
                  l10n.onboardingTasteQ2VotedTakSmaczek4,
                ]
              : [
                  l10n.onboardingTasteQ2VotedNieSmaczek1,
                  l10n.onboardingTasteQ2VotedNieSmaczek2,
                  l10n.onboardingTasteQ2VotedNieSmaczek3,
                  l10n.onboardingTasteQ2VotedNieSmaczek4,
                ]);
    return Column(
      key: ValueKey('taste-args-$_round'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title.toUpperCase(),
          textAlign: TextAlign.center,
          style: AppTypography.title().copyWith(color: context.colors.ink),
        ),
        const SizedBox(height: 34),
        for (var i = 0; i < smaczki.length; i++) ...[
          if (i > 0) const SizedBox(height: 20),
          _StaggeredIn(
            listenable: _argsIn,
            // A beat of silence after the title, then one argument per
            // second: each lands over a 300ms window at 1.0s / 2.0s / 3.0s /
            // 4.0s of the run.
            interval: Interval(
              (1000 + i * 1000) / _argsRunMs,
              (1300 + i * 1000) / _argsRunMs,
              curve: Curves.easeOut,
            ),
            child: _ArgumentLine(number: i + 1, text: smaczki[i]),
          ),
        ],
        const SizedBox(height: 32),
        _StaggeredIn(
          listenable: _argsIn,
          // A full second after the last argument has settled, so it gets read
          // as an argument — not skipped past chasing the appearing button.
          interval: const Interval(5300 / _argsRunMs, 1, curve: Curves.easeOut),
          // The stance pair, in the bridge card's loud/quiet pairing —
          // conceding to the arguments is the aha we're selling, so it gets
          // the gradient.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OnboardingPrimaryButton(
                label: l10n.onboardingTasteChangeMind,
                onPressed: () => _onStanceChosen(changedMind: true),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => _onStanceChosen(changedMind: false),
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.subtle,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  l10n.onboardingTasteStandFirm.toUpperCase(),
                  style: AppTypography.action(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The bridge between the two rounds: "Spróbujmy z kolejnym…" pops in alone
  /// at centre stage and, two seconds later (see [_onResultContinue]'s timer),
  /// round two's question takes over.
  Widget _interludeStage(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: const ValueKey('taste-interlude'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutBack,
      // easeOutBack overshoots past 1 for the pop — fine for scale, clamped
      // for opacity.
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
      ),
      child: Text(
        context.l10n.onboardingTasteNextTitle.toUpperCase(),
        textAlign: TextAlign.center,
        style: AppTypography.title().copyWith(color: context.colors.ink),
      ),
    );
  }
}

/// Fades + slides [child] up into place over the slice of the parent animation
/// given by [interval] — the one-by-one entrance of the argument lines. While
/// still invisible the child also ignores pointers, so the not-yet-revealed
/// button can't be tapped early.
class _StaggeredIn extends StatelessWidget {
  const _StaggeredIn({
    required this.listenable,
    required this.interval,
    required this.child,
  });

  final Animation<double> listenable;
  final Interval interval;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: listenable, curve: interval);
    return AnimatedBuilder(
      animation: t,
      builder: (_, inner) =>
          IgnorePointer(ignoring: t.value < 0.05, child: inner),
      child: FadeTransition(
        opacity: t,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.25),
            end: Offset.zero,
          ).animate(t),
          child: child,
        ),
      ),
    );
  }
}

/// One argument in the takeover — no card background, just a bare orange
/// number (the smaczki identity) and the line itself, a step larger than body
/// text so it reads like a statement, not a list item.
class _ArgumentLine extends StatelessWidget {
  const _ArgumentLine({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$number',
          // Height matched to the first line of the 15px/1.35 body text so the
          // bare number keeps hanging off the statement's opening line.
          style: AppTypography.numeric(
            20,
            height: 1.0,
          ).copyWith(color: AppTheme.spark),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            text,
            style: AppTypography.body(
              fontSize: 15,
              height: 1.35,
            ).copyWith(color: context.colors.ink),
          ),
        ),
      ],
    );
  }
}
