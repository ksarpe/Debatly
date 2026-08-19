import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/data/models/question.dart';
import 'package:debatly/data/models/smaczek.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/go_deeper_button.dart';
import 'package:debatly/features/questions/widgets/question_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// The smaczki sheet is VOTE-GATED, for both tiers: an argument read before
/// taking a side has no target, and a vote cast after reading the arguments is
/// no longer the reflex the community split claims to measure (that number
/// goes on the share card as "X% said TAK od razu").
///
/// The bottom-bar pill stays VISIBLE before the vote — knowing something waits
/// there is part of the reason to vote — but tapping it answers with the
/// "Najpierw zagłosuj" hook instead of the sheet.
///
/// Entry-point audit (why the feed's pill covers everything): the sheet's one
/// and only opener in the app is the feed's bottom bar (`showSmaczkiSheet` in
/// question_body.dart). There is no deep link to a question (app_links handles
/// auth codes only), notifications carry no navigation payload (they open the
/// app on the feed), the favorites screen is display-only, the vote-history
/// screen lists only questions that BY DEFINITION carry a vote, and the DEV
/// pin lands the question in this same feed. Gating this one tap therefore
/// gates every path — this test is the regression lock on that fact.
void main() {
  const lockedToast = 'Najpierw zagłosuj. Potem sprawdzę, czy się utrzymasz.';

  Question q(String id, [String? text]) =>
      Question(id: id, category: 'TEST', questionText: text ?? 'Czy $id?');

  /// Pumps the feed body with a controllable vote state and tier.
  Future<void> pumpFeed(
    WidgetTester tester, {
    required bool voted,
    bool premium = false,
    _VoteStateRepo? repo,
  }) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences(),
        ),
        sessionProvider.overrideWith(
          () => FakeSession(guestSession(isPremium: premium)),
        ),
        isPremiumProvider.overrideWithValue(premium),
        questionsProvider.overrideWith((ref) async => const <Question>[]),
        todaysDailyQuestionProvider.overrideWith(
          (ref) async => q('daily', 'Czy pytanie dnia jest darmowe?'),
        ),
        deckShuffleSeedProvider.overrideWithValue(1),
        questionRepositoryProvider.overrideWithValue(
          repo ?? _VoteStateRepo(voted),
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

  /// The first readable smaczek of the mock catalog — its presence is the
  /// "sheet is open" signal, its absence the "sheet stayed closed" one.
  final sheetContent = find.textContaining('Zgodziłeś się w sekundę');

  testWidgets(
    'before the vote the pill is visible but answers with the hook toast — '
    'no sheet',
    (tester) async {
      await pumpFeed(tester, voted: false);

      // The pill is there (the promise must stay visible)...
      expect(find.byType(GoDeeperButton), findsOneWidget);

      // ...but a tap gets the hook instead of the arguments.
      await tester.tap(find.byType(GoDeeperButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(lockedToast), findsOneWidget);
      expect(sheetContent, findsNothing);

      // Let the toast's auto-dismiss timer run out.
      await tester.pumpAndSettle();
    },
  );

  testWidgets('the gate is NOT a PRO perk — a premium user is blocked too', (
    tester,
  ) async {
    await pumpFeed(tester, voted: false, premium: true);

    await tester.tap(find.byType(GoDeeperButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(lockedToast), findsOneWidget);
    expect(sheetContent, findsNothing);

    await tester.pumpAndSettle();
  });

  testWidgets('after the vote the sheet opens exactly as before', (
    tester,
  ) async {
    await pumpFeed(tester, voted: true, premium: true);

    await tester.tap(find.byType(GoDeeperButton));
    await tester.pumpAndSettle();

    expect(sheetContent, findsOneWidget);
    expect(find.text(lockedToast), findsNothing);
  });

  testWidgets(
    'pre-vote free feed prefetches METADATA only — the full-text RPC is '
    'never called, so no readable argument can reach the device',
    (tester) async {
      final repo = _VoteStateRepo(false);
      await pumpFeed(tester, voted: false, repo: repo);

      expect(repo.metaCallIds, isNotEmpty);
      expect(repo.fullCallIds, isEmpty);
    },
  );

  testWidgets('post-vote the feed warms the full set for the sheet', (
    tester,
  ) async {
    final repo = _VoteStateRepo(true);
    await pumpFeed(tester, voted: true, repo: repo);

    expect(repo.fullCallIds, isNotEmpty);
  });
}

/// Mock repo whose vote state the test controls, recording which smaczki RPC
/// each fetch hits — the regression lock on the pre-vote text leak. The
/// smaczki come from [MockQuestionRepository]'s canned list — the
/// sheet-content marker above.
class _VoteStateRepo extends MockQuestionRepository {
  _VoteStateRepo(this.voted);

  final bool voted;
  final List<String> fullCallIds = [];
  final List<String> metaCallIds = [];

  @override
  Future<VoteResult> getDailyVoteState(String questionId) async => voted
      ? const VoteResult(yesCount: 61, noCount: 39, myChoice: VoteResult.yes)
      : VoteResult.empty;

  @override
  Future<List<Smaczek>> fetchSmaczki(String questionId) {
    fullCallIds.add(questionId);
    return super.fetchSmaczki(questionId);
  }

  @override
  Future<List<SmaczekMeta>> fetchSmaczkiMeta(String questionId) {
    metaCallIds.add(questionId);
    return super.fetchSmaczkiMeta(questionId);
  }
}
