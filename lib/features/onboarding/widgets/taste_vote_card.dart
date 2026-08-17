import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/vote_result.dart';
import '../../../services/analytics.dart';
import '../../../services/supabase_service.dart';
import '../../questions/widgets/falling_words_text.dart';
import '../../questions/widgets/vote_visuals.dart';
import 'onboarding_primary_button.dart';

/// The onboarding "aha", staged as a mind-change loop run twice: the user votes
/// on a real question, the card is taken over by a bare "hold on…" interlude in
/// which the four arguments appear one by one, then the question returns for a
/// second vote — and only then is the community split revealed. A short
/// "let's try another…" beat then rolls straight into a second question with
/// the same loop (its takeover titled "are you sure?"), so the very first
/// minutes demonstrate both pillars — the vote AND the arguments that make you
/// doubt it — twice over, instead of describing them.
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
  const TasteVoteCard({super.key, required this.onContinue});

  /// Advances to the next onboarding page once the user has had their moment.
  final VoidCallback onContinue;

  @override
  State<TasteVoteCard> createState() => _TasteVoteCardState();
}

/// One round's beats, in order: first gut vote → the arguments takeover → the
/// second, post-arguments vote → the community-split reveal. [interlude] is the
/// "let's try another…" beat bridging round one's result into round two.
enum _Stage { vote, arguments, revote, result, interlude }

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
  /// before the "Dobra, głosuję!" button closes the run at 5.3s. See the
  /// [Interval]s in [_argumentsStage].
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

  void _onArgumentsRead() {
    setState(() => _stage = _Stage.revote);
  }

  void _onSecondVote(int choice) {
    setState(() {
      _secondChoice = choice;
      _stage = _Stage.result;
    });
    Analytics.log('onboarding_taste_revoted', {
      'choice': choice == VoteResult.yes ? 'tak' : 'nie',
      'changed_mind': choice != _firstChoice,
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
      setState(() => _stage = _Stage.vote);
      // Round two's question is on stage (round one's `onboarding_q_shown`
      // fires from the screen when the taste page is reached).
      Analytics.log('onboarding_q_shown', {'index': _round});
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // Centred, but scrollable so the taller stages (three arguments, or the
    // split + line + Continue) never overflow on short screens or large text.
    // The whole card swaps per stage: the arguments takeover replaces the
    // question entirely, then the question fades back in for the re-vote.
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
            _Stage.revote => _questionStage(
              context,
              key: 'taste-revote-$_round',
              // The changed kicker alone carries the second ask — no extra
              // caption between the question and the buttons.
              kicker: l10n.onboardingTasteRevoteKicker,
              children: [VoteButtonsRow(busy: false, onVote: _onSecondVote)],
            ),
            _Stage.result => _questionStage(
              context,
              key: 'taste-result-$_round',
              // The reveal is the payoff — the split has to be there the
              // instant the stage lands. Re-assembling the (by now twice-read)
              // question word by word would only make it wait.
              animate: false,
              children: [
                VoteResultsRow(
                  result: VoteResult(
                    yesCount: _live[_round]?.yesCount ?? 1,
                    noCount: _live[_round]?.noCount ?? 1,
                    myChoice: _secondChoice,
                  ),
                ),
                const SizedBox(height: 24),
                OnboardingPrimaryButton(
                  label: l10n.onboardingTasteContinue,
                  onPressed: _onResultContinue,
                ),
              ],
            ),
            _Stage.interlude => _interludeStage(context),
          },
        ),
      ),
    );
  }

  /// The stages that carry the question: kicker + question text on top,
  /// [children] (buttons / results) underneath. [kicker] defaults to "TWÓJ
  /// RUCH"; the re-vote stage swaps it for "ZAGŁOSUJ PONOWNIE". [animate]
  /// controls the word-by-word entrance — off on the reveal, where the split
  /// must not be kept waiting behind the question re-typing itself.
  Widget _questionStage(
    BuildContext context, {
    required String key,
    required List<Widget> children,
    String? kicker,
    bool animate = true,
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
          kicker ?? l10n.onboardingTasteKicker,
          style: const TextStyle(
            color: AppTheme.spark,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 22),
        // The same word-by-word entrance as the real feed; keyed per stage and
        // round (see the callers' ValueKeys), so the question re-assembles for
        // the re-vote and for round two — but not for the reveal.
        FallingWordsText(question, animate: animate),
        const SizedBox(height: 34),
        ...children,
      ],
    );
  }

  /// The takeover between the two votes: a bare title — "Ale chwila…" in round
  /// one, "Czy aby na pewno?" in round two — alone at centre stage, then the
  /// four arguments landing one by one — no card chrome, just the numbered
  /// dot and a larger line — and finally, after a beat of silence, the
  /// "Dobra, głosuję!" button.
  Widget _argumentsStage(BuildContext context) {
    final l10n = context.l10n;
    final title = _round == 0
        ? l10n.onboardingTasteHoldOnTitle
        : l10n.onboardingTasteSureTitle;
    final smaczki = _round == 0
        ? [
            l10n.onboardingTasteSmaczek1,
            l10n.onboardingTasteSmaczek2,
            l10n.onboardingTasteSmaczek3,
            l10n.onboardingTasteSmaczek4,
          ]
        : [
            l10n.onboardingTasteQ2Smaczek1,
            l10n.onboardingTasteQ2Smaczek2,
            l10n.onboardingTasteQ2Smaczek3,
            l10n.onboardingTasteQ2Smaczek4,
          ];
    return Column(
      key: ValueKey('taste-args-$_round'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.colors.ink,
            fontSize: 32,
            fontWeight: FontWeight.w800,
          ),
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
          child: OnboardingPrimaryButton(
            label: l10n.onboardingTasteRead,
            onPressed: _onArgumentsRead,
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
        context.l10n.onboardingTasteNextTitle,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: context.colors.ink,
          fontSize: 32,
          fontWeight: FontWeight.w800,
        ),
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

/// One argument in the takeover — no card background, just the numbered orange
/// dot (the smaczki identity) and the line itself, a step larger than body
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
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppTheme.spark,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
