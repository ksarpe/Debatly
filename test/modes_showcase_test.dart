import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/questions/widgets/modes_showcase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// The one-time modes showcase: the dimmed feed with a spotlight on the app
/// bar's modes icon and the "Nowość / Tryby" card. Shown once per install,
/// only while the icon is on screen; "Zamknij" and "Zobacz tryby" both close
/// it and report which.
void main() {
  /// The overlay's ring pulses forever — bounded pumps, never pumpAndSettle.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<ProviderContainer> pumpHost(
    WidgetTester tester, {
    required bool premium,
    required Widget Function(BuildContext, WidgetRef) body,
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
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          home: Scaffold(body: Consumer(builder: (c, ref, _) => body(c, ref))),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('shows the card under the spotlight; "Zamknij" closes it and '
      'reports close', (tester) async {
    ModesShowcaseAction? result;
    await pumpHost(
      tester,
      premium: false,
      body: (context, ref) => TextButton(
        onPressed: () async {
          result = await showModesShowcase(
            context,
            iconRect: const Rect.fromLTWH(720, 24, 48, 48),
            premium: false,
          );
        },
        child: const Text('go'),
      ),
    );

    await tester.tap(find.text('go'));
    await settle(tester);

    expect(find.text('NOWOŚĆ'), findsOneWidget);
    expect(find.text('TRYBY'), findsOneWidget);
    expect(find.textContaining('Tryby są częścią PRO'), findsOneWidget);
    expect(find.text('ZOBACZ TRYBY'), findsOneWidget);

    await tester.tap(find.text('ZAMKNIJ'));
    await settle(tester);

    expect(find.text('TRYBY'), findsNothing);
    expect(result, ModesShowcaseAction.close);
  });

  testWidgets('PRO wording; "Zobacz tryby" reports open', (tester) async {
    ModesShowcaseAction? result;
    await pumpHost(
      tester,
      premium: true,
      body: (context, ref) => TextButton(
        onPressed: () async {
          result = await showModesShowcase(
            context,
            iconRect: const Rect.fromLTWH(720, 24, 48, 48),
            premium: true,
          );
        },
        child: const Text('go'),
      ),
    );

    await tester.tap(find.text('go'));
    await settle(tester);
    expect(find.textContaining('Masz je w swoim PRO'), findsOneWidget);

    await tester.tap(find.text('ZOBACZ TRYBY'));
    await settle(tester);

    expect(result, ModesShowcaseAction.open);
  });

  testWidgets('never fires without the modes icon on screen, and spends '
      'nothing', (tester) async {
    // The vote panel is pumped on its own in most widget tests — no app
    // bar, no icon — so the showcase must be a silent no-op there rather
    // than a dimmed screen with nothing to point at.
    bool? shown;
    final container = await pumpHost(
      tester,
      premium: false,
      body: (context, ref) => TextButton(
        onPressed: () async =>
            shown = await maybeShowModesShowcase(context, ref),
        child: const Text('vote'),
      ),
    );

    await tester.tap(find.text('vote'));
    await settle(tester);

    expect(shown, isFalse);
    expect(find.text('TRYBY'), findsNothing);
    expect(
      container
          .read(sharedPreferencesProvider)
          .getBool(kModesShowcaseSeenPrefKey),
      isNull,
      reason: 'a skipped showcase keeps its once for a real feed',
    );
  });
}
