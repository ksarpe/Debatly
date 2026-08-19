import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/data/models/question.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/screens/question_screen.dart';
import 'package:debatly/features/questions/widgets/load_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// What the feed does when it has NOTHING to show.
///
/// An empty deck used to mean one thing — "still loading" — and rendered a bare
/// spinner with no message and no way out. But the deck is also empty when every
/// fetch SUCCEEDED and produced no question: `ensureSignedIn` returning null
/// leaves `get_daily_question` without a uid (Supabase rate-limits anonymous
/// sign-ups per IP, which a carrier CGNAT reaches), and a question with no
/// translation resolves to blank text. Both left the app spinning forever.
void main() {
  Question q(String id) => Question(
    id: id,
    category: id.toUpperCase(),
    questionText: 'Question $id?',
  );

  Future<void> pumpFeed(
    WidgetTester tester, {
    required Future<Question?> Function() daily,
    required Future<List<Question>> Function() pool,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await mockSharedPreferences(),
          ),
          sessionProvider.overrideWith(() => FakeSession(guestSession())),
          questionsProvider.overrideWith((ref) => pool()),
          todaysDailyQuestionProvider.overrideWith((ref) => daily()),
          deckShuffleSeedProvider.overrideWithValue(1),
        ],
        child: const LocalizedTestApp(home: QuestionScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a resolved-but-empty feed offers a retry, not an endless spinner',
    (tester) async {
      await pumpFeed(
        tester,
        daily: () async => null,
        pool: () async => const <Question>[],
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LoadError), findsOneWidget);
      expect(find.text('SPRÓBUJ PONOWNIE'), findsOneWidget);
    },
  );

  testWidgets('it does not blame the network when nothing actually failed', (
    tester,
  ) async {
    await pumpFeed(
      tester,
      daily: () async => null,
      pool: () async => const <Question>[],
    );

    // The fetches succeeded, so "check your internet connection" would send a
    // user with four bars chasing the wrong thing.
    expect(
      find.text(
        'Nie udało się pobrać dzisiejszego pytania. '
        'Spróbuj ponownie za chwilę.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Sprawdź połączenie z internetem i spróbuj ponownie.'),
      findsNothing,
    );
  });

  testWidgets('a thrown fetch still gets the connection copy', (tester) async {
    await pumpFeed(
      tester,
      daily: () async => throw Exception('offline'),
      pool: () async => const <Question>[],
    );

    expect(find.byType(LoadError), findsOneWidget);
    expect(
      find.text('Sprawdź połączenie z internetem i spróbuj ponownie.'),
      findsOneWidget,
    );
  });

  testWidgets('a daily that resolves is still shown — no false dead end', (
    tester,
  ) async {
    await pumpFeed(
      tester,
      daily: () async => q('daily'),
      pool: () async => const <Question>[],
    );

    expect(find.byType(LoadError), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
