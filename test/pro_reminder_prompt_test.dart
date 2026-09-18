import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/monetization/widgets/pro_reminder_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// The post-purchase reminder ask: the ONLY place a paying user is asked for
/// notifications, because the wall's ask (`WallReminderAsk`) lives on a surface
/// PRO never sees again. Once per install, either answer final — Settings keep
/// the toggle afterwards.
void main() {
  /// Pumps a screen whose button runs [promptProReminder], and returns the
  /// container so the test can read the persisted flags back.
  Future<ProviderContainer> pumpPrompt(
    WidgetTester tester, {
    bool isPremium = true,
    bool alreadyAsked = false,
    bool remindersOn = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await mockSharedPreferences({
            if (alreadyAsked) kProReminderAskedPrefKey: true,
            if (remindersOn) 'reminders_enabled': true,
          }),
        ),
        sessionProvider.overrideWith(
          () => FakeSession(guestSession(isPremium: isPremium)),
        ),
        isPremiumProvider.overrideWithValue(isPremium),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => promptProReminder(context, ref),
                child: const Text('buy'),
              ),
            ),
          ),
        ),
      ),
    );
    // The fake session resolves on a microtask; the prompt reads it
    // synchronously and no-ops while it is still loading, exactly as it would
    // for a purchase that landed before the session was known.
    await container.read(sessionProvider.future);
    await tester.pumpAndSettle();

    await tester.tap(find.text('buy'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('a fresh buyer is asked once, and "later" is final', (
    tester,
  ) async {
    final container = await pumpPrompt(tester);

    // The ask names the time the reminder will fire, so the promise is
    // checkable against what Settings shows later.
    expect(find.text('DO JUTRA?'), findsOneWidget);
    expect(find.textContaining('20:00'), findsOneWidget);

    await tester.tap(find.text('PÓŹNIEJ'));
    await tester.pumpAndSettle();

    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getBool(kProReminderAskedPrefKey), isTrue);
    // A decline must never switch the reminder on behind the user's back.
    expect(prefs.getBool('reminders_enabled'), isNot(true));
    expect(find.text('DO JUTRA?'), findsNothing);
  });

  testWidgets('"remind me" never traps the buyer — with no notification '
      'plugin the ask still closes and marks itself answered', (tester) async {
    // The native plugin is not initialised in the test host, so the permission
    // request resolves false: the dialog must still close and record the ask
    // instead of stalling or re-opening on the next purchase settle.
    final container = await pumpPrompt(tester);

    await tester.tap(find.text('PRZYPOMINAJ MI'));
    await tester.pumpAndSettle();

    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getBool(kProReminderAskedPrefKey), isTrue);
    // Denied by the (absent) OS → the reminder was NOT switched on.
    expect(prefs.getBool('reminders_enabled'), isNot(true));
    expect(find.text('DO JUTRA?'), findsNothing);
  });

  testWidgets('asked is asked — a second purchase settle stays quiet', (
    tester,
  ) async {
    await pumpPrompt(tester, alreadyAsked: true);
    expect(find.text('DO JUTRA?'), findsNothing);
  });

  testWidgets('nothing to ask when the reminder is already on', (tester) async {
    await pumpPrompt(tester, remindersOn: true);
    expect(find.text('DO JUTRA?'), findsNothing);
  });

  testWidgets('a free session is never asked — this rides on the purchase', (
    tester,
  ) async {
    final container = await pumpPrompt(tester, isPremium: false);
    expect(find.text('DO JUTRA?'), findsNothing);
    // And the one-shot is left unspent for the purchase that may still come.
    expect(
      container
          .read(sharedPreferencesProvider)
          .getBool(kProReminderAskedPrefKey),
      isNot(true),
    );
  });
}
