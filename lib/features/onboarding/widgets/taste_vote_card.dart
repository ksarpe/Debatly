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

/// The onboarding "aha", staged as a mind-change loop: the user votes on a real
/// question, the card is taken over by a bare "hold on…" interlude in which the
/// three arguments appear one by one, then the question returns for a second
/// vote — and only then is the community split revealed. The very first
/// interaction demonstrates both pillars — the vote AND the arguments that make
/// you doubt it — instead of describing them.
///
/// This is a no-stakes TASTE: the vote is never cast, so it works instantly,
/// offline and pre-login, and never touches the streak/credit logic. The real,
/// counting vote happens on the daily right after onboarding. The revealed
/// split IS live, though: the question's all-time tally is fetched in the
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

/// The card's four beats, in order: first gut vote → the arguments takeover →
/// the second, post-arguments vote → the community-split reveal.
enum _Stage { vote, arguments, revote, result }

class _TasteVoteCardState extends State<TasteVoteCard>
    with SingleTickerProviderStateMixin {
  /// The catalog id of the taste question ("Czy osoba otyła powinna płacić za
  /// dwa miejsca w samolocie?"), so its real all-time split can be fetched. The
  /// on-card text stays in the ARBs — the catalog row only supplies the tally.
  static const String _kQuestionId = '8b54aec1-b9a0-41b7-9a2d-766d886cfe50';

  /// The live all-time split, fetched in the background by [_loadLiveSplit].
  /// Null until it arrives (or forever in mock mode / offline) — the reveal
  /// then falls back to a dead-even 1:1, so neither side feels alone right
  /// after being made to doubt.
  VoteResult? _live;

  _Stage _stage = _Stage.vote;

  /// The gut pick, before the arguments.
  int? _firstChoice;

  /// The considered pick, after the arguments; highlights its side in the split.
  int? _secondChoice;

  /// Times the takeover: "Ale chwila…" stands alone for the first second, then
  /// the arguments land at 1.0s / 2.0s / 3.0s, and the "Przeczytane!" button
  /// closes the run. See the [Interval]s in [_argumentsStage].
  static const double _argsRunMs = 3600;

  // Created eagerly in [initState]: a lazy `late final` initializer would run
  // on first touch, and if the card is disposed while still on the first vote
  // stage that first touch is `dispose()` itself — creating a Ticker during
  // teardown, when the TickerMode ancestor lookup is no longer safe.
  late final AnimationController _argsIn;

  @override
  void initState() {
    super.initState();
    _argsIn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
    unawaited(_loadLiveSplit());
  }

  /// Fetches the taste question's real community tally while the user is busy
  /// voting and reading — by the reveal (~15s in) it has long since landed.
  /// Fire-and-forget: any failure just keeps the curated 50/50 fallback, and a
  /// result that arrives after the reveal is already on screen is dropped so
  /// the split never jumps mid-look.
  Future<void> _loadLiveSplit() async {
    final split = await SupabaseService.fetchVoteSplit(_kQuestionId);
    if (!mounted || _stage == _Stage.result) return;
    if (split == null || split.yes + split.no == 0) return;
    setState(() {
      _live = VoteResult(yesCount: split.yes, noCount: split.no);
    });
  }

  @override
  void dispose() {
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
    });
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
              key: 'taste-vote',
              children: [VoteButtonsRow(busy: false, onVote: _onFirstVote)],
            ),
            _Stage.arguments => _argumentsStage(context),
            _Stage.revote => _questionStage(
              context,
              key: 'taste-revote',
              // The changed kicker alone carries the second ask — no extra
              // caption between the question and the buttons.
              kicker: l10n.onboardingTasteRevoteKicker,
              children: [VoteButtonsRow(busy: false, onVote: _onSecondVote)],
            ),
            _Stage.result => _questionStage(
              context,
              key: 'taste-result',
              children: [
                VoteResultsRow(
                  result: VoteResult(
                    yesCount: _live?.yesCount ?? 1,
                    noCount: _live?.noCount ?? 1,
                    myChoice: _secondChoice,
                  ),
                ),
                const SizedBox(height: 24),
                OnboardingPrimaryButton(
                  label: l10n.onboardingTasteContinue,
                  onPressed: widget.onContinue,
                ),
              ],
            ),
          },
        ),
      ),
    );
  }

  /// The stages that carry the question: kicker + question text on top,
  /// [children] (buttons / results) underneath. [kicker] defaults to "TWÓJ
  /// RUCH"; the re-vote stage swaps it for "ZAGŁOSUJ PONOWNIE".
  Widget _questionStage(
    BuildContext context, {
    required String key,
    required List<Widget> children,
    String? kicker,
  }) {
    final l10n = context.l10n;
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
        // The same word-by-word entrance as the real feed; keyed per stage (see
        // the callers' ValueKeys), so the question re-assembles for the re-vote.
        FallingWordsText(l10n.onboardingTasteQuestion),
        const SizedBox(height: 34),
        ...children,
      ],
    );
  }

  /// The takeover between the two votes: a bare "Ale chwila…" alone at centre
  /// stage, then the three arguments landing one by one — no card chrome, just
  /// the numbered dot and a larger line — and finally the "read them" button.
  Widget _argumentsStage(BuildContext context) {
    final l10n = context.l10n;
    final smaczki = [
      l10n.onboardingTasteSmaczek1,
      l10n.onboardingTasteSmaczek2,
      l10n.onboardingTasteSmaczek3,
    ];
    return Column(
      key: const ValueKey('taste-args'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.onboardingTasteHoldOnTitle,
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
            // A beat of silence after the title, then one argument per second:
            // each lands over a 300ms window at 1.0s / 2.0s / 3.0s of the run.
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
          interval: const Interval(3300 / _argsRunMs, 1, curve: Curves.easeOut),
          child: OnboardingPrimaryButton(
            label: l10n.onboardingTasteRead,
            onPressed: _onArgumentsRead,
          ),
        ),
      ],
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
