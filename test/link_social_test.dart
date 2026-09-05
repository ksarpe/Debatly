import 'package:debatly/core/locale/app_locale.dart'
    show sharedPreferencesProvider;
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/account/widgets/link_social_sheet.dart';
import 'package:debatly/features/settings/screens/settings_screen.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// The migration path for the email/password accounts that predate the
/// social-only auth sheet (2026-09-05): a Settings row, shown ONLY to a
/// signed-in account with no Google / Apple identity, that opens the sheet
/// linking one onto the same uid. Everyone else — guests (who get the
/// secure-account CTA), social accounts — must never see it.
void main() {
  Future<void> pumpSettings(WidgetTester tester, SessionState session) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await mockSharedPreferences(),
          ),
          sessionProvider.overrideWith(() => FakeSession(session)),
        ],
        child: const LocalizedTestApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Settings "sign in without a password" row', () {
    testWidgets('shows for a password-only account and names Google on '
        'Android', (tester) async {
      await pumpSettings(tester, passwordOnlyAccountSession());

      expect(find.text('Logowanie bez hasła'), findsOneWidget);
      // Tests report as Android, where the sheet offers Google alone — the
      // subtitle must not promise an Apple button that will not be there.
      expect(find.text('Połącz konto z Google'), findsOneWidget);
      expect(find.text('Połącz konto z Apple lub Google'), findsNothing);
    });

    testWidgets('names Apple or Google on iOS', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pumpSettings(tester, passwordOnlyAccountSession());
        expect(find.text('Połącz konto z Apple lub Google'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('hidden once a social identity is linked', (tester) async {
      await pumpSettings(tester, accountSession());
      expect(find.text('Logowanie bez hasła'), findsNothing);
    });

    testWidgets('hidden for a guest — the secure-account CTA is theirs', (
      tester,
    ) async {
      await pumpSettings(tester, guestSession());
      expect(find.text('Logowanie bez hasła'), findsNothing);
      expect(find.text('ZABEZPIECZ KONTO'), findsOneWidget);
    });

    testWidgets('tapping the row opens the link sheet', (tester) async {
      await pumpSettings(tester, passwordOnlyAccountSession());

      final row = find.text('Logowanie bez hasła');
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.text('POŁĄCZ KONTO'), findsOneWidget);
      expect(find.text('KONTYNUUJ Z GOOGLE'), findsOneWidget);
    });
  });

  group('LinkSocialCard', () {
    testWidgets('a keyless build explains itself instead of a dead button', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: LocalizedTestApp(home: Scaffold(body: LinkSocialCard())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('POŁĄCZ KONTO'), findsOneWidget);
      expect(
        find.text(
          'Brakuje konfiguracji Supabase. Uruchom aplikację z SUPABASE_URL i SUPABASE_ANON_KEY.',
        ),
        findsOneWidget,
      );
      // Android: Google is the only provider the card names.
      expect(find.text('KONTYNUUJ Z GOOGLE'), findsOneWidget);
      expect(find.text('KONTYNUUJ Z APPLE'), findsNothing);
    });

    testWidgets('Apple platforms get both buttons, Apple first', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await tester.pumpWidget(
          const ProviderScope(
            child: LocalizedTestApp(home: Scaffold(body: LinkSocialCard())),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('KONTYNUUJ Z APPLE'), findsOneWidget);
        // Google needs a client id the test build does not have, so the
        // second button is dropped rather than shown dead.
        expect(find.text('KONTYNUUJ Z GOOGLE'), findsNothing);
        final apple = tester.getTopLeft(find.text('KONTYNUUJ Z APPLE'));
        final title = tester.getTopLeft(find.text('POŁĄCZ KONTO'));
        expect(apple.dy, greaterThan(title.dy));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
