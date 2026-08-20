import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/data/models/question.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/onboarding/screens/app_entry.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/screens/question_screen.dart';
import 'package:debatly/features/update/providers/update_gate_providers.dart';
import 'package:debatly/features/update/screens/update_required_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// The force-update gate (v2.1.0+): a build below the server's
/// `app_update_gate.min_version` gets the blocking update screen instead of
/// the feed. Everything about the gate FAILS OPEN — no backend answer, an
/// error, an unparsable version — because a network blip must never lock a
/// user out.
void main() {
  group('isVersionBelow', () {
    test('plain semantic comparisons', () {
      expect(isVersionBelow('2.0.9', '2.1.0'), isTrue);
      expect(isVersionBelow('2.1.0', '2.1.0'), isFalse);
      expect(isVersionBelow('2.1.1', '2.1.0'), isFalse);
      expect(isVersionBelow('1.9.9', '2.0.0'), isTrue);
    });

    test('segments compare numerically, not lexically', () {
      expect(isVersionBelow('2.9.0', '2.10.0'), isTrue);
      expect(isVersionBelow('2.10.0', '2.9.0'), isFalse);
    });

    test('missing segments count as zero', () {
      expect(isVersionBelow('2.1', '2.1.0'), isFalse);
      expect(isVersionBelow('2.1', '2.1.1'), isTrue);
      expect(isVersionBelow('2', '3'), isTrue);
    });

    test('suffix junk inside a segment is ignored past its digits', () {
      expect(isVersionBelow('2.1.0-beta', '2.1.1'), isTrue);
      expect(isVersionBelow('2.1.5-rc1', '2.1.0'), isFalse);
    });

    test('unparsable on either side fails OPEN', () {
      expect(isVersionBelow('abc', '2.1.0'), isFalse);
      expect(isVersionBelow('2.1.0', 'abc'), isFalse);
      expect(isVersionBelow('', '2.1.0'), isFalse);
      expect(isVersionBelow('2.1.0', ''), isFalse);
    });
  });

  group('updateRequiredProvider', () {
    ProviderContainer harness({
      Future<String?> Function()? min,
      String current = '2.1.0',
    }) {
      final container = ProviderContainer(
        overrides: [
          minSupportedVersionProvider.overrideWith(
            (ref) => min == null ? Future.value(null) : min(),
          ),
          currentAppVersionProvider.overrideWith((ref) async => current),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('an older build must update', () async {
      final c = harness(min: () async => '9.9.9');
      expect(await c.read(updateRequiredProvider.future), isTrue);
    });

    test('a build at (or past) the minimum runs', () async {
      final c = harness(min: () async => '2.1.0');
      expect(await c.read(updateRequiredProvider.future), isFalse);
    });

    test('no gate answer fails open', () async {
      final c = harness();
      expect(await c.read(updateRequiredProvider.future), isFalse);
    });

    test('an unreadable own version fails open', () async {
      // PackageInfo unavailable → currentAppVersionProvider resolves '' (it
      // never throws: a throwing provider would be RETRIED by Riverpod 3 and
      // the gate check would hang instead of failing open).
      final c = harness(min: () async => '2.2.0', current: '');
      expect(await c.read(updateRequiredProvider.future), isFalse);
    });
  });

  group('HomeGate', () {
    Question q(String id) => Question(
      id: id,
      category: id.toUpperCase(),
      questionText: 'Question $id?',
    );

    Future<void> pumpGate(
      WidgetTester tester, {
      required bool mustUpdate,
    }) async {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await mockSharedPreferences(),
          ),
          sessionProvider.overrideWith(() => FakeSession(guestSession())),
          questionsProvider.overrideWith((ref) async => const <Question>[]),
          todaysDailyQuestionProvider.overrideWith((ref) async => q('daily')),
          deckShuffleSeedProvider.overrideWithValue(1),
          updateRequiredProvider.overrideWith((ref) async => mustUpdate),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const LocalizedTestApp(home: HomeGate()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a gated build gets the update screen, never the feed', (
      tester,
    ) async {
      await pumpGate(tester, mustUpdate: true);

      expect(find.byType(UpdateRequiredScreen), findsOneWidget);
      expect(find.byType(QuestionScreen), findsNothing);
      // The one action on the dead end: the store button.
      expect(find.text('ZAKTUALIZUJ'), findsOneWidget);
    });

    testWidgets('an allowed build lands on the feed as always', (tester) async {
      await pumpGate(tester, mustUpdate: false);

      expect(find.byType(QuestionScreen), findsOneWidget);
      expect(find.byType(UpdateRequiredScreen), findsNothing);
    });
  });
}
