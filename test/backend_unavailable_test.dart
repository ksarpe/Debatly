import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/core/startup/supabase_init_provider.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/onboarding/screens/app_entry.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/screens/question_screen.dart';
import 'package:debatly/services/supabase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// A Supabase init that FAILS is not the same thing as a build with no
/// credentials, and the difference is the whole point of these tests.
///
/// Both used to read as `!SupabaseService.isInitialised`, so a real user whose
/// init threw (or outran its bound — `Supabase.initialize` awaits the deeplink
/// observer, which on a launch from a password-reset link goes to the network)
/// was handed [MockQuestionRepository]: invented questions, a hard-coded daily,
/// a fabricated split, a streak frozen at 0, and every vote discarded. Nothing
/// on screen said so.
void main() {
  group('init status', () {
    test('no credentials is mock mode; credentials that never came up are '
        'a failure — the distinction the whole fix rests on', () {
      expect(
        SupabaseService.statusFor(configured: false, initialised: false),
        SupabaseInitStatus.notConfigured,
      );
      expect(
        SupabaseService.statusFor(configured: true, initialised: false),
        SupabaseInitStatus.failed,
      );
      expect(
        SupabaseService.statusFor(configured: true, initialised: true),
        SupabaseInitStatus.ready,
      );
    });
  });

  group('question repository', () {
    ProviderContainer containerFor(SupabaseInitStatus status) {
      final container = ProviderContainer(
        overrides: [supabaseInitProvider.overrideWith(() => _FakeInit(status))],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('serves mock data ONLY when there is no backend configured', () {
      expect(
        containerFor(
          SupabaseInitStatus.notConfigured,
        ).read(questionRepositoryProvider),
        isA<MockQuestionRepository>(),
      );
    });

    test('refuses to substitute mock data for a backend that is down', () {
      expect(
        () => containerFor(
          SupabaseInitStatus.failed,
        ).read(questionRepositoryProvider),
        // Riverpod wraps whatever a provider throws, so unwrap before asserting.
        throwsA(
          isA<ProviderException>().having(
            (e) => e.exception,
            'exception',
            isA<SupabaseUnavailableException>(),
          ),
        ),
      );
    });
  });

  group('home gate', () {
    Future<ProviderContainer> pumpGate(
      WidgetTester tester,
      SupabaseInitStatus status,
    ) async {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await mockSharedPreferences(),
          ),
          supabaseInitProvider.overrideWith(() => _FakeInit(status)),
          sessionProvider.overrideWith(() => FakeSession(guestSession())),
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
      return container;
    }

    testWidgets('a backend that never came up gets a named error state and a '
        'retry — never the feed', (tester) async {
      await pumpGate(tester, SupabaseInitStatus.failed);

      expect(find.byType(QuestionScreen), findsNothing);
      expect(find.text('BRAK POŁĄCZENIA Z DEBATLY'), findsOneWidget);
      expect(find.text('SPRÓBUJ PONOWNIE'), findsOneWidget);
    });

    testWidgets('a backend that came up late reloads the session, so the '
        'guest the failed launch never minted still gets minted', (
      tester,
    ) async {
      final container = await pumpGate(tester, SupabaseInitStatus.failed);
      expect(find.byType(QuestionScreen), findsNothing);

      // The init landing after the launch gave up on it — the app has to
      // converge on the real backend rather than sit on the retry button.
      var sessionLoads = 0;
      container.listen(sessionProvider, (previous, next) => sessionLoads++);
      (container.read(supabaseInitProvider.notifier) as _FakeInit).emit(
        SupabaseInitStatus.ready,
      );
      await tester.pumpAndSettle();

      expect(find.text('BRAK POŁĄCZENIA Z DEBATLY'), findsNothing);
      expect(sessionLoads, greaterThan(0));
    });
  });
}

/// A [SupabaseInitNotifier] pinned to a status the test drives, standing in for
/// a real `Supabase.initialize` (which a widget test can neither run nor fail).
class _FakeInit extends SupabaseInitNotifier {
  _FakeInit(this._status);

  SupabaseInitStatus _status;

  @override
  SupabaseInitStatus build() => _status;

  /// Stands in for a late init landing (or a retry succeeding).
  void emit(SupabaseInitStatus next) {
    _status = next;
    state = next;
  }
}
