import 'package:debatly/core/feedback/haptics.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/features/questions/widgets/vote_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/localized_test_app.dart';

/// The haptic vocabulary is a *language*: "locked" has to feel different from
/// "confirmed", or the whole thing degrades into one undifferentiated buzz.
/// These tests pin the two things that can silently rot — which primitive each
/// intent maps to, and that the multi-pulse patterns actually fire every pulse
/// (they run off timers, so a regression there is invisible on screen).
void main() {
  late List<String> fired;

  setUp(() {
    fired = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            fired.add(call.arguments as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('the single-pulse intents each map to their own primitive', (
    tester,
  ) async {
    Haptics.tick();
    Haptics.nudge();
    Haptics.confirm();
    Haptics.impact();
    await tester.pump();

    expect(fired, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.heavyImpact',
    ]);
  });

  testWidgets('blocked is a two-tap refusal, not a single press', (
    tester,
  ) async {
    Haptics.blocked();
    await tester.pump();
    // The first pulse is synchronous: the refusal must not arrive a frame after
    // the finger that caused it.
    expect(fired, ['HapticFeedbackType.lightImpact']);

    await tester.pump(const Duration(milliseconds: 200));
    expect(fired, [
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.lightImpact',
    ]);
  });

  testWidgets('celebrate is a rising roll', (tester) async {
    Haptics.celebrate();
    await tester.pump(const Duration(milliseconds: 300));

    expect(fired, [
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.heavyImpact',
    ]);
  });

  testWidgets('casting a vote is felt before the argument that follows it', (
    tester,
  ) async {
    var choice = -1;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: Center(
            child: VoteButtonsRow(busy: false, onVote: (c) => choice = c),
          ),
        ),
      ),
    );

    await tester.tap(find.text('TAK'));
    await tester.pump();

    expect(choice, VoteResult.yes);
    expect(fired, ['HapticFeedbackType.mediumImpact']);
  });

  testWidgets('a disabled vote row buzzes for nothing', (tester) async {
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Scaffold(
          body: Center(child: VoteButtonsRow(busy: true, onVote: (_) {})),
        ),
      ),
    );

    await tester.tap(find.text('TAK'));
    await tester.pump();

    expect(fired, isEmpty);
  });
}
