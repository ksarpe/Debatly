import 'package:debatly/core/locale/app_locale.dart';
import 'package:debatly/data/models/user_stats.dart';
import 'package:debatly/features/account/providers/grace_providers.dart';
import 'package:debatly/features/account/providers/stats_providers.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/grace_lost_overlay.dart';
import 'package:debatly/features/questions/widgets/stat_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';
import 'support/test_prefs.dart';

/// The local-day stamp `markVotedToday` writes (yyyy-mm-dd, device local).
String _todayStamp() {
  final now = DateTime.now();
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '${now.year}-$m-$d';
}

const _streak = UserStats(
  currentStreak: 4,
  longestStreak: 4,
  rankTier: 1,
  rankName: 'Prowokator',
  nextRankStreak: 7,
);

Future<void> _pumpChip(
  WidgetTester tester, {
  required Map<String, Object> prefs,
  UserStats stats = _streak,
}) async {
  final sp = await mockSharedPreferences(prefs);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        userStatsProvider.overrideWith((_) async => stats),
        dailyFetchDayProvider.overrideWithValue('2026-01-01'),
      ],
      child: const LocalizedTestApp(
        home: Scaffold(body: Center(child: StreakChip())),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('StreakChip cooling', () {
    testWidgets('a live streak with no vote today wears the cooling tooltip', (
      tester,
    ) async {
      await _pumpChip(tester, prefs: {});
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'Dziś jeszcze bez głosu — seria stygnie');
    });

    testWidgets('a vote stamped today keeps the warm tooltip', (tester) async {
      await _pumpChip(
        tester,
        prefs: {'reminder_last_vote_date': _todayStamp()},
      );
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'Twoja seria');
    });

    testWidgets('no streak is never "cooling"', (tester) async {
      await _pumpChip(tester, prefs: {}, stats: UserStats.empty);
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'Twoja seria');
    });
  });

  group('showGraceLostOverlay', () {
    testWidgets('names the graces left and closes on tap', (tester) async {
      var done = 0;
      late BuildContext ctx;
      await tester.pumpWidget(
        LocalizedTestApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      );

      showGraceLostOverlay(ctx, gracesLeft: 2, onDone: () => done++);
      await tester.pump();
      // One frame anchors the ticker, then the whole 1.5 s timeline plays.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 1500));

      expect(find.text('ŁASKA PRZEPADŁA'), findsOneWidget);
      expect(find.text('Zostały Ci jeszcze 2 łaski'), findsOneWidget);
      expect(
        find.text('Zagłosuj dziś, żeby ranga nie spadła.'),
        findsOneWidget,
      );
      // The copy has actually faded in (it is built from t=0 at opacity 0).
      final textOpacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.text('ŁASKA PRZEPADŁA'),
          matching: find.byType(Opacity),
        ),
      );
      expect(textOpacity.opacity, 1.0);

      await tester.tap(find.text('ŁASKA PRZEPADŁA'));
      await tester.pumpAndSettle();

      expect(find.text('ŁASKA PRZEPADŁA'), findsNothing);
      expect(done, 1);
    });

    testWidgets('fades itself out after the hold', (tester) async {
      var done = 0;
      late BuildContext ctx;
      await tester.pumpWidget(
        LocalizedTestApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      );

      showGraceLostOverlay(ctx, gracesLeft: 1, onDone: () => done++);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('Została Ci jeszcze 1 łaska'), findsOneWidget);

      // The frame that reports the animation complete arms the 2.2 s hold;
      // past it the overlay fades itself out (0.26 s) and removes its entry.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 2300));
      await tester.pumpAndSettle();

      expect(find.text('Została Ci jeszcze 1 łaska'), findsNothing);
      expect(done, 1);
    });
  });

  group('GraceLostController', () {
    test('fires once per lost grace and re-seeds across resets', () async {
      final sp = await mockSharedPreferences();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(container.dispose);
      final ctl = container.read(graceLostControllerProvider.notifier);

      UserStats withGrace(int? left) => UserStats(
        currentStreak: 4,
        longestStreak: 4,
        rankTier: 1,
        rankName: 'Prowokator',
        graceDaysLeft: left,
      );

      // Intact: nothing, and no baseline written.
      expect(await ctl.evaluate(withGrace(null)), isNull);
      expect(ctl.debugLastSeen(), isNull);

      // First missed day: 2 left → announce, then the same sync is silent.
      expect(await ctl.evaluate(withGrace(2)), 2);
      expect(await ctl.evaluate(withGrace(2)), isNull);

      // Next day: 1 left → announce again.
      expect(await ctl.evaluate(withGrace(1)), 1);

      // The tier dropped, window reset to 3: silent, but re-seeded so that
      // tomorrow's 2 fires.
      expect(await ctl.evaluate(withGrace(3)), isNull);
      expect(ctl.debugLastSeen(), 3);
      expect(await ctl.evaluate(withGrace(2)), 2);

      // A vote makes the streak intact again: baseline cleared.
      expect(await ctl.evaluate(withGrace(null)), isNull);
      expect(ctl.debugLastSeen(), isNull);
    });
  });
}
