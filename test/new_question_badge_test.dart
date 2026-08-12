import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/data/models/question.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/account/providers/stats_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/new_question_badge.dart';
import 'package:debatly/features/questions/widgets/question_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// The "NOWE" pill over a freshly-added question. What matters for release:
///   * a question whose id is in the recent-ids set wears the pill, so its
///     thin vote count reads as "just added", not "nobody cares";
///   * an older question shows NO pill — the badge must stay meaningful;
///   * tapping the pill explains itself (the tooltip carries the "community is
///     just starting to vote" line — that explanation is the badge's job).
void main() {
  Future<void> pumpFeed(
    WidgetTester tester, {
    required Set<String> recentIds,
  }) async {
    const daily = Question(id: 'd', category: 'X', questionText: 'Czy warto?');
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(),
        ),
        questionsProvider.overrideWith((ref) async => [daily]),
        todaysDailyQuestionProvider.overrideWith((ref) async => daily),
        isPremiumProvider.overrideWithValue(true),
        freeUnlockCreditsProvider.overrideWithValue(0),
        deckShuffleSeedProvider.overrideWithValue(1),
        sessionProvider.overrideWith(_FakeSession.new),
        questionRepositoryProvider.overrideWithValue(
          _RecentIdsRepo(recentIds: recentIds),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(home: Scaffold(body: QuestionBody())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a question younger than the window wears the NOWE pill', (
    tester,
  ) async {
    await pumpFeed(tester, recentIds: {'d'});
    expect(find.byType(NewQuestionBadge), findsOneWidget);
    expect(find.text('NOWE'), findsOneWidget);
  });

  testWidgets('an older question shows no pill', (tester) async {
    await pumpFeed(tester, recentIds: {'someone-else'});
    expect(find.byType(NewQuestionBadge), findsNothing);
  });

  testWidgets('tapping the pill explains why the vote count may be thin', (
    tester,
  ) async {
    await pumpFeed(tester, recentIds: {'d'});
    await tester.tap(find.byType(NewQuestionBadge));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('dopiero zaczyna głosować'),
      findsOneWidget,
      reason: 'the tap-tooltip is what turns the badge into an explanation',
    );
  });
}

class _FakeSession extends SessionNotifier {
  @override
  Future<SessionState> build() async =>
      const SessionState(userId: 'u1', isAnonymous: false);
}

/// Serves a configurable recent-ids set, with a voted panel state so the feed
/// renders its stable post-vote shape.
class _RecentIdsRepo extends MockQuestionRepository {
  _RecentIdsRepo({required this.recentIds});

  final Set<String> recentIds;

  @override
  Future<Set<String>> fetchRecentQuestionIds({required DateTime since}) async =>
      recentIds;

  @override
  Future<VoteResult> getDailyVoteState(String questionId) async =>
      const VoteResult(yesCount: 3, noCount: 1, myChoice: VoteResult.yes);
}
