import 'package:debatly/data/models/conformity_stats.dart';
import 'package:debatly/data/models/debate_profile.dart';
import 'package:debatly/data/models/vote_history_entry.dart';
import 'package:debatly/data/repositories/question_repository.dart';
import 'package:debatly/features/account/providers/session_providers.dart';
import 'package:debatly/features/monetization/widgets/pro_paywall_screen.dart';
import 'package:debatly/features/questions/providers/question_providers.dart';
import 'package:debatly/features/questions/widgets/conformity_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';

/// The debate-profile section under the conformity axis. Release guarantees:
///   * locked: a progress line + bar driven by the counter FURTHER from the
///     unlock threshold — never an empty hole;
///   * provisional (6–11 on the limiting counter): type + grid shown with the
///     "profil wstępny" tag; full (12+) drops the tag;
///   * the TYPE, both percentages and share are visible to FREE users — only
///     the depth row (trend/categories/moved) is the PRO upsell;
///   * PRO renders the real depth blocks instead of the locked row.
void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    required DebateProfile debateProfile,
    required bool premium,
    bool withheldDepth = false,
  }) async {
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        questionRepositoryProvider.overrideWithValue(
          _ProfileRepo(debateProfile, withheldDepth: withheldDepth),
        ),
        isPremiumProvider.overrideWithValue(premium),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LocalizedTestApp(
          home: Scaffold(body: Center(child: ConformityAxisButton())),
        ),
      ),
    );
    await tester.tap(find.byType(ConformityAxisButton));
    await tester.pumpAndSettle();
  }

  testWidgets('locked: progress follows the counter further from the threshold '
      '(20 votes, 4 gate answers → 2 missing, bar at 4/6)', (tester) async {
    await pumpPanel(
      tester,
      premium: false,
      debateProfile: const DebateProfile(
        totalVotes: 20,
        majorityVotes: 9,
        minorityVotes: 8,
        gateHeld: 3,
        gateMoved: 1,
      ),
    );

    expect(
      find.text('Jeszcze 2 kontry po głosowaniu i poznasz swój typ.'),
      findsOneWidget,
    );
    expect(find.text('4 / 6'), findsOneWidget);
    // No type leaks through the lock.
    expect(find.text('POSZUKIWACZ'), findsNothing);
    expect(find.text('FILAR'), findsNothing);
  });

  testWidgets(
    'locked: the pre-gate veteran (50 votes, 0 gates) is asked for kontry, '
    'not for the answers they already gave',
    (tester) async {
      // The gate shipped 2026-08-19, so a long-standing account arrives with
      // a null outcome on every old vote row and sits at 0 / 6. The bar is
      // right; the sentence next to it is what has to carry the reason.
      await pumpPanel(
        tester,
        premium: false,
        debateProfile: const DebateProfile(
          totalVotes: 50,
          majorityVotes: 30,
          minorityVotes: 20,
          gateHeld: 0,
          gateMoved: 0,
        ),
      );

      expect(
        find.text('Jeszcze 6 kontr po głosowaniu i poznasz swój typ.'),
        findsOneWidget,
      );
      expect(find.text('0 / 6'), findsOneWidget);
    },
  );

  testWidgets(
    'provisional free profile: grid with the active type, the "wstępny" tag, '
    'both percentages, and the locked PRO depth row',
    (tester) async {
      // 8 votes / 7 gate answers → provisional; 25% majority + 29% moved
      // → against the crowd, movable → POSZUKIWACZ.
      await pumpPanel(
        tester,
        premium: false,
        debateProfile: const DebateProfile(
          totalVotes: 8,
          majorityVotes: 2,
          minorityVotes: 6,
          gateHeld: 5,
          gateMoved: 2,
        ),
      );

      // All four cells render; the active one is the seeker. SAMOTNY WILK
      // appears exactly ONCE — the axis rungs are positional phrases now, so
      // the noun exists only as the 2×2 type.
      expect(find.text('POSZUKIWACZ'), findsOneWidget);
      expect(find.text('FILAR'), findsOneWidget);
      expect(find.text('SAMOTNY WILK'), findsOneWidget);
      expect(find.text('PŁYNIE Z PRĄDEM'), findsOneWidget);
      expect(
        find.text('Nie kupujesz cudzych opinii, ale szukasz lepszych.'),
        findsOneWidget,
      );
      expect(find.text('profil wstępny'), findsOneWidget);
      // Both axis percentages are FREE.
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('29%'), findsOneWidget);
      // The depth is the upsell, not the type: four locked rows, and the
      // flips row carries the user's REAL moved count — the number sells,
      // the padlock alone doesn't.
      expect(find.text('Zdania, które Cię przewróciły'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Twój najbardziej samotny głos'), findsOneWidget);
      expect(find.text('Twój typ ma tylko …% użytkowników'), findsOneWidget);
      expect(find.text('Trend w czasie'), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(4));
      // No PRO blocks for free.
      expect(find.text('ZDANIA, KTÓRE CIĘ PRZEWRÓCIŁY'), findsNothing);
    },
  );

  testWidgets(
    'a locked row with a zero counter is not shown at all — an empty vault '
    'teaches the feature is worthless',
    (tester) async {
      await pumpPanel(
        tester,
        premium: false,
        debateProfile: const DebateProfile(
          totalVotes: 9,
          majorityVotes: 3,
          minorityVotes: 5,
          gateHeld: 7,
          gateMoved: 0,
        ),
      );

      expect(find.text('Zdania, które Cię przewróciły'), findsNothing);
      // The counter-less rows still render.
      expect(find.text('Twój najbardziej samotny głos'), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(3));
    },
  );

  testWidgets(
    'tapping a locked row opens the paywall with the portrait headline',
    (tester) async {
      await pumpPanel(
        tester,
        premium: false,
        debateProfile: const DebateProfile(
          totalVotes: 8,
          majorityVotes: 2,
          minorityVotes: 6,
          gateHeld: 5,
          gateMoved: 2,
        ),
      );

      // The row can sit below the panel's fold on the test viewport — scroll
      // it into view first (the panel body is a SingleChildScrollView).
      await tester.ensureVisible(find.text('Twój najbardziej samotny głos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Twój najbardziej samotny głos'));
      await tester.pumpAndSettle();

      expect(find.byType(ProPaywallScreen), findsOneWidget);
      // The one sanctioned per-entry headline: the portrait, not the catalog.
      expect(find.text('8 GŁOSÓW.\nZOBACZ, CO MÓWIĄ O TOBIE.'), findsOneWidget);
    },
  );

  testWidgets('full profile drops the provisional tag', (tester) async {
    await pumpPanel(
      tester,
      premium: false,
      debateProfile: const DebateProfile(
        totalVotes: 30,
        majorityVotes: 20,
        minorityVotes: 8,
        gateHeld: 11,
        gateMoved: 1,
      ),
    );

    // 71% with the crowd, 8% moved → FILAR, full.
    expect(find.text('FILAR'), findsOneWidget);
    expect(find.text('profil wstępny'), findsNothing);
  });

  testWidgets('PRO sees the depth blocks instead of the locked row', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      premium: true,
      debateProfile: const DebateProfile(
        totalVotes: 47,
        majorityVotes: 15,
        minorityVotes: 29,
        gateHeld: 9,
        gateMoved: 3,
      ),
    );

    expect(find.text('TREND W CZASIE'), findsOneWidget);
    expect(find.text('ZDANIA, KTÓRE CIĘ PRZEWRÓCIŁY'), findsOneWidget);
    expect(find.text('TWÓJ NAJBARDZIEJ SAMOTNY GŁOS'), findsOneWidget);
    // Rarity: the mock repo's canned 9% renders as the spark one-liner.
    expect(find.text('Twój typ ma 9% użytkowników'), findsOneWidget);
    // The MockQuestionRepository canned moved-list quote renders.
    expect(find.textContaining('Zgodziłeś się w sekundę'), findsOneWidget);
    // The English-labelled category breakdown is gone from the UI (the RPC
    // stays live server-side until the labels are localized).
    expect(find.text('TWOJE KATEGORIE'), findsNothing);
    // No locked rows for PRO.
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
  });

  testWidgets(
    'PRO: a row whose value the server withholds says so instead of vanishing',
    (tester) async {
      // `get_type_rarity` returns NULL below the server's 20-unlocked-profile
      // floor — which is where the live population actually is — and the
      // loneliest vote is null for anyone whose every vote sat with the
      // majority. Both rows were SOLD to the free user as locked rows one
      // screen earlier, so a user who paid 19,99 zł for them and then found
      // them simply gone had no way to read that as anything but a cheat.
      await pumpPanel(
        tester,
        premium: true,
        withheldDepth: true,
        debateProfile: const DebateProfile(
          totalVotes: 47,
          majorityVotes: 47,
          minorityVotes: 0,
          gateHeld: 9,
          gateMoved: 3,
        ),
      );

      for (final title in const [
        'TWÓJ TYP MA TYLKO …% UŻYTKOWNIKÓW',
        'TWÓJ NAJBARDZIEJ SAMOTNY GŁOS',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text('Jeszcze za mało danych.'), findsNWidgets(2));
    },
  );
}

/// Mock repo with a canned profile and instant conformity stats, so the panel
/// settles in one pumpAndSettle. The PRO depth lists come from
/// [MockQuestionRepository]'s canned values.
class _ProfileRepo extends MockQuestionRepository {
  _ProfileRepo(this.profile, {this.withheldDepth = false});

  final DebateProfile profile;

  /// Serves the "server has nothing for you" shape of the PRO depth: a null
  /// rarity (population under the floor) and a history in which every vote
  /// sat with the majority (no loneliest vote).
  final bool withheldDepth;

  @override
  Future<ConformityStats> fetchConformityStats() async =>
      const ConformityStats(totalVotes: 10, majorityVotes: 6, minorityVotes: 4);

  @override
  Future<DebateProfile> fetchDebateProfile() async => profile;

  @override
  Future<int?> fetchTypeRarity() async =>
      withheldDepth ? null : super.fetchTypeRarity();

  @override
  Future<List<VoteHistoryEntry>> fetchVoteHistory() async {
    if (!withheldDepth) return super.fetchVoteHistory();
    return [
      VoteHistoryEntry.fromJson({
        'question_id': 'q-1',
        'category': 'Ethics',
        'question_text': 'Czy większość ma rację?',
        'voted_at': '2026-07-10T18:42:07+00:00',
        'yes_count': 90,
        'no_count': 10,
        'my_choice': 1,
      }),
    ];
  }
}
