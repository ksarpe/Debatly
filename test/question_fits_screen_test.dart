import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/core/theme/app_theme.dart';
import 'package:debatly/data/models/question.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/daily_vote_panel.dart';
import 'package:debatly/features/questions/widgets/favorite_star_button.dart';
import 'package:debatly/features/questions/widgets/go_deeper_button.dart';
import 'package:debatly/features/questions/widgets/question_body.dart';
import 'package:debatly/features/questions/widgets/share_question_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// A long question used to grow past its space: the size the length heuristic
/// alone picks only knows the character count, so on a short screen (or at a
/// large system font) the text pushed the vote panel and the share / favorites
/// pills below it down into — and past — the bottom overlay.
///
/// The question must now shrink to the space it actually has, so the whole
/// centred group stays clear of the "go deeper" overlay at the foot of the
/// screen.
void main() {
  const long =
      'Czy człowiek, który nigdy nie zawiódł bliskich, po prostu nie miał '
      'okazji, czy naprawdę jest lepszy od innych?';

  Future<void> pumpFeed(
    WidgetTester tester, {
    required String text,
    required Size size,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final daily = Question(id: 'd', category: 'X', questionText: text);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(),
        ),
        questionsProvider.overrideWith((ref) async => [daily]),
        todaysDailyQuestionProvider.overrideWith((ref) async => daily),
        isPremiumProvider.overrideWithValue(true),
        deckShuffleSeedProvider.overrideWithValue(1),
        sessionProvider.overrideWith(_FakeSession.new),
        questionRepositoryProvider.overrideWithValue(_VotedRepo()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: const Scaffold(body: QuestionBody()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectFeedDoesNotCollide(WidgetTester tester) {
    final vote = tester.getRect(find.byType(DailyVotePanel));
    final share = tester.getRect(find.byType(ShareQuestionButton));
    final star = tester.getRect(find.byType(FavoriteStarButton));
    final goDeeper = tester.getRect(find.byType(GoDeeperButton));

    expect(
      vote.bottom,
      lessThanOrEqualTo(share.top),
      reason: 'the vote panel must sit above the share pill, never over it',
    );
    expect(share.bottom, lessThanOrEqualTo(goDeeper.top));
    expect(star.bottom, lessThanOrEqualTo(goDeeper.top));
    expect(
      tester.takeException(),
      isNull,
      reason: 'nothing may overflow its box',
    );
  }

  testWidgets('a long question shrinks instead of running into the pills', (
    tester,
  ) async {
    await pumpFeed(tester, text: long, size: const Size(375, 667));
    expectFeedDoesNotCollide(tester);
  });

  testWidgets('...and still fits at a large system font', (tester) async {
    await pumpFeed(
      tester,
      text: long,
      size: const Size(375, 667),
      textScale: 1.5,
    );
    expectFeedDoesNotCollide(tester);
  });

  testWidgets('a short question keeps the group centred on the screen', (
    tester,
  ) async {
    await pumpFeed(tester, text: 'Czy warto?', size: const Size(393, 851));
    expectFeedDoesNotCollide(tester);

    // The question + vote + pills group is still centred against the whole
    // screen — the cap only bites when the content is too tall for its space.
    final top = tester.getRect(find.byType(Scaffold)).top;
    final group = tester
        .getRect(find.byType(DailyVotePanel))
        .expandToInclude(tester.getRect(find.byType(ShareQuestionButton)));
    expect(group.center.dy, greaterThan(top + 851 * 0.4));
    expect(group.center.dy, lessThan(top + 851 * 0.6));
  });

  test('the fit only shrinks the text when the box demands it', () {
    const text = 'Czy warto?';
    final preferred = QuestionTextStyles.fontSizeFor(text);

    expect(
      QuestionTextStyles.fitFontSize(text, maxWidth: 400, maxHeight: 600),
      preferred,
      reason: 'plenty of room — the length-based size is the intended look',
    );
    expect(
      QuestionTextStyles.fitFontSize(text, maxWidth: 400, maxHeight: 24),
      lessThan(preferred),
    );
    expect(
      QuestionTextStyles.fitFontSize(text, maxWidth: 400, maxHeight: 1),
      QuestionTextStyles.hardMinFontSize,
      reason: 'it bottoms out rather than vanishing',
    );
    expect(
      QuestionTextStyles.fitFontSize(
        text,
        maxWidth: 400,
        maxHeight: double.infinity,
      ),
      preferred,
      reason: 'an unbounded box changes nothing',
    );
  });
}

class _FakeSession extends SessionNotifier {
  @override
  Future<SessionState> build() async =>
      const SessionState(userId: 'u1', isAnonymous: false);
}

/// Serves a question the user has already voted on, so the panel renders its
/// tallest state (the split bars plus the "Twój głos" caption).
class _VotedRepo extends MockQuestionRepository {
  @override
  Future<VoteResult> getDailyVoteState(String questionId) async =>
      const VoteResult(yesCount: 61, noCount: 39, myChoice: VoteResult.yes);
}
