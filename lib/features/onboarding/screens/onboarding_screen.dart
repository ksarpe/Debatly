import 'package:flutter/material.dart';

import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/analytics.dart';
import '../widgets/onboarding_bridge_card.dart';
import '../widgets/onboarding_dots.dart';
import '../widgets/onboarding_intro_card.dart';
import '../widgets/onboarding_notifications_card.dart';
import '../widgets/onboarding_primary_button.dart';
import '../widgets/spark_logo.dart';
import '../widgets/taste_vote_card.dart';

/// The first-launch tutorial: a swipeable deck that welcomes the user, lands
/// them straight on real questions to vote on (with a taste of the smaczki
/// behind them), then explains the freemium model on the bridge card — one
/// free question a day, forever; the paywall sheet only if THEY ask — and
/// asks for the daily reminder. Reaching the end hands over to the home gate,
/// which for every tier is the feed with today's daily. No wall anywhere in
/// this flow.
///
/// There is deliberately NO account step here: the session starts anonymously
/// on its own, sign-in for returning PRO users lives as a link on the paywall,
/// and account creation is pitched AFTER a purchase (see promptSaveProAccount)
/// — asking before the offer only adds friction in front of the price.
///
/// It owns no persistence; reaching the end calls [onFinish], and `AppEntry`
/// records that the tutorial is done and swaps in the live app.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinish});

  /// Invoked once the user is through onboarding — off the last card, or via
  /// "Skip".
  final VoidCallback onFinish;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  /// Index of the taste-vote page / the bridge / the notifications page in
  /// the deck. Set from the page list each build (constant in practice).
  int _votePageIndex = 0;
  int _bridgePageIndex = 0;
  int _notifyPageIndex = 0;

  /// Funnel steps already reported, so swiping back and forth doesn't re-count
  /// a page as "reached" twice.
  final Set<String> _loggedSteps = {};

  @override
  void initState() {
    super.initState();
    _logStep('onboarding_started');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _logStep(String event, [Map<String, Object?> props = const {}]) {
    if (_loggedSteps.add(event)) Analytics.log(event, props);
  }

  /// Reports reaching a page, by its position in the deck. The welcome card is
  /// covered by `onboarding_started`; the interactive pages are the funnel.
  /// (`onboarding_q_shown` for the SECOND question fires inside the taste
  /// card, which is the only place that knows when round two starts.)
  void _onPageChanged(int i) {
    setState(() => _index = i);
    if (i == _notifyPageIndex) {
      _logStep('onboarding_notify_shown');
    } else if (i == _bridgePageIndex) {
      _logStep('bridge_shown');
    } else if (i == _votePageIndex) {
      _logStep('onboarding_taste_shown');
      _logStep('onboarding_q_shown', {'index': 0});
    }
  }

  void _next() {
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// "Skip" leaves the tutorial immediately — the next screen is the home
  /// gate (the feed with today's daily), and nothing in here is required to
  /// use the app.
  void _skip() {
    Analytics.log('onboarding_skipped', {'from_page': _index});
    _finish('skipped');
  }

  void _finish(String path) {
    _logStep('onboarding_finished', {'path': path});
    _logStep('onboarding_completed');
    widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // A deliberately short funnel: a warm welcome, then straight into the real
    // moment — a juicy question to actually vote on. The taste card is the aha;
    // one swipe is all it takes to reach it (the welcome copy already carries
    // the "vote and see which side you're on" pitch, so no feature card stands
    // in the way).
    final introCards = <Widget>[
      OnboardingIntroCard(
        glyph: const SparkLogo(size: 52),
        title: l10n.onboardingWelcomeTitle,
        body: l10n.onboardingWelcomeBody,
      ),
    ];

    // The interactive "taste" vote sits among the intro pages. The user must vote
    // (or skip) to move on, so the split reveal — the payoff — isn't missed;
    // voting unveils its own "Continue".
    final votePage = TasteVoteCard(onContinue: _next);

    // Having just lived the loop twice, the user gets the model explained on
    // the bridge: one free question a day forever, the whole catalog behind
    // the (dismissible) paywall sheet — and the free path is the louder
    // button. It carries its own CTAs, so the deck's shared "Next" hides.
    final bridgePage = OnboardingBridgeCard(onContinue: _next);

    // Straight after the aha, while the app still feels fresh, we ask to turn on
    // the daily reminder. The card carries its own buttons (Enable / Not now),
    // both of which end the tutorial — the feed with today's daily is next.
    final notifyPage = OnboardingNotificationsCard(
      onContinue: () => _finish('direct'),
    );

    _votePageIndex = introCards.length;
    _bridgePageIndex = introCards.length + 1;
    _notifyPageIndex = introCards.length + 2;

    final pageCount = _notifyPageIndex + 1;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        // Cap the content width and centre it so cards and buttons don't stretch
        // edge-to-edge on tablets. Matches the auth sheet's 480 cap; a no-op on
        // phones, which are narrower.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                // Top bar: a quiet "Skip" that leaves the tutorial.
                SizedBox(
                  height: 48,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _skip,
                      style: TextButton.styleFrom(
                        foregroundColor: context.colors.subtle,
                      ),
                      child: Text(l10n.onboardingSkip),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _controller,
                    onPageChanged: _onPageChanged,
                    // The taste-vote page is a gate, not a slide: swiping is
                    // disabled there, so the only ways off it are living the
                    // vote loop (its own "Continue") or the "Skip" up top.
                    // Everywhere else the deck swipes normally.
                    physics: _index == _votePageIndex
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    children: [...introCards, votePage, bridgePage, notifyPage],
                  ),
                ),
                // Progress dots + the "Next" CTA on the pages that are pure
                // copy (the welcome card); the taste-vote page (its
                // "Continue" revealed after voting), the bridge (its own two
                // CTAs) and the notifications page carry their own buttons.
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                  child: Column(
                    children: [
                      OnboardingDots(count: pageCount, index: _index),
                      const SizedBox(height: 20),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        child:
                            (_index == _votePageIndex ||
                                _index == _bridgePageIndex ||
                                _index == _notifyPageIndex)
                            ? const SizedBox(width: double.infinity)
                            : OnboardingPrimaryButton(
                                label: l10n.onboardingNext,
                                onPressed: _next,
                              ),
                      ),
                    ],
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
