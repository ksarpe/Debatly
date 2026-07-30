// Batch-exports REAL in-app screens as store screenshots, at three device
// sizes (phone / 7" tablet / 10" tablet), for the Play Store & App Store.
//
// Unlike tool/export_store_screenshots.dart (which renders only the branded
// share poster), this renders the actual app UI — a question with the TAK/NIE
// vote, a feed question, the rank ladder, the shareable rank poster and
// the PRO history — using the app's real presentational widgets
// (StyledQuestionText, VoteButtonsRow/VoteResultsRow, RankShareCard) plus
// faithful, provider-free reconstructions of the surrounding chrome. Rendering
// head-less (no emulator, no backend) keeps every screenshot deterministic and
// pixel-exact.
//
// Run it like a test (it uses the test harness only for a FlutterView + fonts;
// it lives outside test/ and isn't *_test.dart, so it's not part of the suite):
//
//   flutter test tool/export_app_screenshots.dart
//
// Output → build/store_screenshots/app/<device>/<locale>/NN_name.png
//   phone     360×640  @3 ⇒ 1080×1920
//   tablet7   600×960  @2 ⇒ 1200×1920
//   tablet10  800×1280 @2 ⇒ 1600×2560
// All three satisfy Google Play's size + aspect-ratio rules.
//
// Optional overrides (OS env vars):
//   SCREENSHOT_LOCALES   comma list, default "pl"   (any of pl,en)
//   SCREENSHOT_OUT_DIR   default "build/store_screenshots/app"
import 'dart:io';
import 'dart:ui' as ui;

import 'package:debatly/core/theme/app_theme.dart';
import 'package:debatly/data/models/rank.dart';
import 'package:debatly/data/models/vote_result.dart';
import 'package:debatly/features/questions/widgets/rank_share_card.dart';
import 'package:debatly/features/questions/widgets/rank_sheet.dart'
    show rankIcon;
import 'package:debatly/features/questions/widgets/styled_question_text.dart';
import 'package:debatly/features/questions/widgets/vote_visuals.dart';
import 'package:debatly/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// ─── device targets ─────────────────────────────────────────────────────────

class _Device {
  const _Device(this.name, this.size, this.dpr);
  final String name;
  final Size size; // logical
  final double dpr;
}

const _devices = <_Device>[
  _Device('phone', Size(360, 640), 3), // 1080×1920
  _Device('tablet7', Size(600, 960), 2), // 1200×1920
  _Device('tablet10', Size(800, 1280), 2), // 1600×2560
];

// ─── screens ────────────────────────────────────────────────────────────────

class _Screen {
  const _Screen(this.name, this.build);
  final String name;
  final Widget Function(String lang) build;
}

const _screens = <_Screen>[
  _Screen('01_question_vote', _preVoteScreen),
  _Screen('02_vote_result', _votedScreen),
  _Screen('03_feed_question', _feedQuestionScreen),
  _Screen('04_rank_ladder', _rankLadderScreen),
  _Screen('05_rank_share', _rankShareScreen),
  _Screen('06_history', _historyScreen),
];

// ─── entrypoint ──────────────────────────────────────────────────────────────

void main() {
  // Fonts must load OUTSIDE the testWidgets fake-async zone (FontLoader does
  // real platform-channel async the fake clock never pumps).
  setUpAll(_loadFonts);

  testWidgets('export app screenshots', (tester) async {
    final locales = (Platform.environment['SCREENSHOT_LOCALES'] ?? 'pl')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final outRoot =
        Platform.environment['SCREENSHOT_OUT_DIR'] ??
        'build/store_screenshots/app';

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var total = 0;
    for (final device in _devices) {
      tester.view.devicePixelRatio = device.dpr;
      tester.view.physicalSize = device.size * device.dpr;

      for (final locale in locales) {
        final dir = Directory('$outRoot/${device.name}/$locale');
        if (dir.existsSync()) dir.deleteSync(recursive: true);
        dir.createSync(recursive: true);

        for (final screen in _screens) {
          final key = GlobalKey();
          await tester.pumpWidget(
            _Harness(
              locale: locale,
              size: device.size,
              captureKey: key,
              child: screen.build(locale),
            ),
          );
          // Two settle pumps: build Localizations + lay out the (static) tree.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));

          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: device.dpr);
            try {
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              File(
                '${dir.path}/${screen.name}.png',
              ).writeAsBytesSync(data!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
          total++;
        }
        final px = device.size * device.dpr;
        stderr.writeln(
          '✓ ${device.name}/$locale: ${_screens.length} screen(s) '
          '@ ${px.width.toInt()}×${px.height.toInt()} → ${dir.path}',
        );
      }
    }
    stderr.writeln('Done — $total PNG(s) written under $outRoot/.');
    expect(total, greaterThan(0));
  });
}

/// Wraps a screen in the app's dark theme + localizations, sized to [size], with
/// a keyed [RepaintBoundary] as the capture node.
class _Harness extends StatelessWidget {
  const _Harness({
    required this.locale,
    required this.size,
    required this.captureKey,
    required this.child,
  });

  final String locale;
  final Size size;
  final GlobalKey captureKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = AppTheme.dark;
    final theme = base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Roboto'),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(locale),
      supportedLocales: const [Locale('pl'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: theme,
      // A clean, non-inherited base text style: forces Roboto (so text with no
      // fontFamily that isn't under a Scaffold/Material — e.g. RankShareCard's
      // headline/tagline — renders real glyphs, not head-less tofu) and clears
      // the debug fallback's yellow double-underline that `.merge` would inherit.
      home: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: 'Roboto',
          color: Colors.white,
          fontSize: 14,
          decoration: TextDecoration.none,
        ),
        child: RepaintBoundary(
          key: captureKey,
          child: SizedBox.fromSize(size: size, child: child),
        ),
      ),
    );
  }
}

// ─── screen builders ─────────────────────────────────────────────────────────

String _q(String lang, String pl, String en) => lang == 'pl' ? pl : en;

const _kVoteQuestionPl = 'Czy zdrada myślami jest zdradą?';
const _kVoteQuestionEn = 'Is emotional cheating still cheating?';
const _kFeedQuestionPl = 'Czy pieniądze potrafią kupić szczęście?';
const _kFeedQuestionEn = 'Can money buy happiness?';

Widget _preVoteScreen(String lang) => _QuestionCanvas(
  lang: lang,
  showGoDeeper: false,
  question: _q(lang, _kVoteQuestionPl, _kVoteQuestionEn),
  belowQuestion: VoteButtonsRow(busy: false, onVote: (_) {}),
);

Widget _votedScreen(String lang) => _QuestionCanvas(
  lang: lang,
  showGoDeeper: false,
  question: _q(lang, _kVoteQuestionPl, _kVoteQuestionEn),
  belowQuestion: const VoteResultsRow(
    result: VoteResult(yesCount: 63, noCount: 37, myChoice: VoteResult.yes),
  ),
);

Widget _feedQuestionScreen(String lang) => _QuestionCanvas(
  lang: lang,
  showGoDeeper: true,
  question: _q(lang, _kFeedQuestionPl, _kFeedQuestionEn),
  belowQuestion: null,
);

Widget _rankLadderScreen(String lang) => _RankLadderCanvas(lang: lang);

Widget _rankShareScreen(String lang) => _RankShareCanvas(lang: lang);

Widget _historyScreen(String lang) => _HistoryCanvas(lang: lang);

// ─── question canvas ─────────────────────────────────────────────────────────

/// A faithful hand-composition of the main [QuestionScreen]: the top status
/// chips, the styled question centred on the canvas, the vote right under it,
/// with share/history pills and a swipe hint.
class _QuestionCanvas extends StatelessWidget {
  const _QuestionCanvas({
    required this.lang,
    required this.showGoDeeper,
    required this.question,
    required this.belowQuestion,
  });

  final String lang;
  final bool showGoDeeper;
  final String question;
  final Widget? belowQuestion;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(lang: lang),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  // Cap the reading width so the question wraps to a few lines
                  // (and stays centred with margins on wide tablets) instead of
                  // sprawling into one thin line.
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StyledQuestionText(question),
                        if (belowQuestion != null) ...[
                          const SizedBox(height: 28),
                          belowQuestion!,
                        ],
                        const SizedBox(height: 24),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ActionPill(
                              icon: Icons.ios_share_rounded,
                              label: _q(lang, 'Udostępnij', 'Share'),
                            ),
                            const SizedBox(width: 12),
                            _ActionPill(
                              icon: Icons.history_rounded,
                              label: _q(lang, 'Historia', 'History'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (showGoDeeper)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _GoDeeperPill(lang: lang),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 20, top: 8),
              child: Text(
                _q(lang, 'Przesuń, aby zobaczyć więcej', 'Swipe for more'),
                style: TextStyle(color: context.colors.subtle, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The centred status cluster (streak flame + free-unlock credit) with the
/// settings icon on the right — mirrors [QuestionScreen]'s app bar.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.lang});
  final String lang;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Row(
        children: [
          const SizedBox(width: 40),
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ChipPill(
                    icon: Icons.local_fire_department_rounded,
                    iconColor: const Color(0xFFF59E0B),
                    label: '12',
                  ),
                  const SizedBox(width: 8),
                  _ChipPill(
                    icon: Icons.lock_open_rounded,
                    iconColor: AppTheme.spark,
                    label: '1',
                  ),
                ],
              ),
            ),
          ),
          Icon(Icons.person_outline, color: context.colors.ink, size: 24),
        ],
      ),
    );
  }
}

class _ChipPill extends StatelessWidget {
  const _ChipPill({
    required this.icon,
    required this.iconColor,
    required this.label,
  });
  final IconData icon;
  final Color iconColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: context.colors.accent,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 15),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// An outlined pill (share / history) matching the app's quiet action pills.
class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: context.colors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: context.colors.subtle),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: context.colors.subtle,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// The glowing "go deeper" spark pill shown on feed questions.
class _GoDeeperPill extends StatelessWidget {
  const _GoDeeperPill({required this.lang});
  final String lang;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: AppTheme.spark.withValues(alpha: 0.14),
        border: Border.all(color: AppTheme.spark.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.spark.withValues(alpha: 0.30),
            blurRadius: 18,
            spreadRadius: -6,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            size: 16,
            color: AppTheme.spark,
          ),
          const SizedBox(width: 8),
          Text(
            _q(lang, 'Wejdź głębiej', 'Go deeper'),
            style: const TextStyle(
              color: AppTheme.spark,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── rank ladder (reconstruction of rank_sheet) ──────────────────────────────

class _RankLadderCanvas extends StatelessWidget {
  const _RankLadderCanvas({required this.lang});
  final String lang;

  @override
  Widget build(BuildContext context) {
    const streak = 12;
    const longest = 21;
    final ladder = [...kDefaultRanks]..sort((a, b) => a.tier.compareTo(b.tier));
    final current = ladder.lastWhere((r) => streak >= r.minStreak);
    final next = ladder.cast<Rank?>().firstWhere(
      (r) => r!.minStreak > streak,
      orElse: () => null,
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.spark.withValues(alpha: 0.14),
                          border: Border.all(
                            color: AppTheme.spark.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Icon(
                          rankIcon(current.icon),
                          color: AppTheme.spark,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _q(lang, 'TWOJA RANGA', 'YOUR RANK'),
                              style: TextStyle(
                                color: context.colors.subtle,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              current.nameFor(lang),
                              style: TextStyle(
                                color: context.colors.ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(
                                  Icons.local_fire_department_rounded,
                                  color: Color(0xFFF59E0B),
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _q(lang, 'passa 12 dni', '12-day streak'),
                                  style: TextStyle(
                                    color: context.colors.ink,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Progress to next rank
                  if (next != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value:
                            (streak - current.minStreak) /
                            (next.minStreak - current.minStreak),
                        minHeight: 8,
                        backgroundColor: context.colors.accent,
                        valueColor: const AlwaysStoppedAnimation(
                          AppTheme.spark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _q(
                        lang,
                        '${next.minStreak - streak} dni do: ${next.nameFor(lang)}',
                        '${next.minStreak - streak} days to: ${next.nameFor(lang)}',
                      ),
                      style: TextStyle(
                        color: context.colors.subtle,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(
                        Icons.emoji_events_outlined,
                        color: context.colors.subtle,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _q(
                          lang,
                          'Najdłuższa passa: $longest dni',
                          'Longest streak: $longest days',
                        ),
                        style: TextStyle(
                          color: context.colors.subtle,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Divider(color: context.colors.accent, height: 1),
                  const SizedBox(height: 16),
                  Text(
                    _q(lang, 'DRABINA RANG', 'RANK LADDER'),
                    style: TextStyle(
                      color: context.colors.subtle,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        children: [
                          for (final r in ladder)
                            _LadderRow(
                              rank: r,
                              lang: lang,
                              unlocked: streak >= r.minStreak,
                              isCurrent: r.tier == current.tier,
                              obscured:
                                  streak < r.minStreak && r.tier != next?.tier,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LadderRow extends StatelessWidget {
  const _LadderRow({
    required this.rank,
    required this.lang,
    required this.unlocked,
    required this.isCurrent,
    required this.obscured,
  });

  final Rank rank;
  final String lang;
  final bool unlocked;
  final bool isCurrent;
  final bool obscured;

  @override
  Widget build(BuildContext context) {
    final fg = unlocked ? context.colors.ink : context.colors.subtle;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isCurrent
            ? AppTheme.spark.withValues(alpha: 0.12)
            : context.colors.accent,
        border: isCurrent
            ? Border.all(color: AppTheme.spark.withValues(alpha: 0.5))
            : null,
      ),
      child: Row(
        children: [
          _blur(
            Icon(
              rankIcon(rank.icon),
              color: unlocked ? AppTheme.spark : context.colors.subtle,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _blur(
              Text(
                rank.nameFor(lang),
                style: TextStyle(
                  color: fg,
                  fontSize: 15,
                  fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
          Text(
            _q(lang, 'od ${rank.minStreak}', 'from ${rank.minStreak}'),
            style: TextStyle(color: context.colors.subtle, fontSize: 12),
          ),
          const SizedBox(width: 8),
          Icon(
            unlocked ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
            color: unlocked ? AppTheme.spark : context.colors.subtle,
            size: 16,
          ),
        ],
      ),
    );
  }

  Widget _blur(Widget child) {
    if (!obscured) return child;
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: child,
    );
  }
}

// ─── rank share poster ───────────────────────────────────────────────────────

class _RankShareCanvas extends StatelessWidget {
  const _RankShareCanvas({required this.lang});
  final String lang;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => RankShareCard(
        rankName: _q(lang, 'Adwokat diabła', "Devil's Advocate"),
        headline: _q(lang, 'Moja nowa ranga', 'My new rank'),
        streakLine: _q(lang, '12 dni z rzędu', '12 days in a row'),
        tagline: AppLocalizations.of(context).shareCardTagline,
        iconKey: 'mask',
        size: Size(constraints.maxWidth, constraints.maxHeight),
      ),
    );
  }
}

// ─── PRO history (reconstruction of history_screen) ──────────────────────────

class _HistoryEntry {
  const _HistoryEntry(this.datePl, this.dateEn, this.question, this.result);
  final String datePl;
  final String dateEn;
  final String question;
  final VoteResult result;
}

const _historyEntries = <_HistoryEntry>[
  _HistoryEntry(
    '4 lip 2026',
    'Jul 4, 2026',
    'Czy zdrada myślami jest zdradą?',
    VoteResult(yesCount: 63, noCount: 37, myChoice: VoteResult.yes),
  ),
  _HistoryEntry(
    '3 lip 2026',
    'Jul 3, 2026',
    'Czy pieniądze potrafią kupić szczęście?',
    VoteResult(yesCount: 48, noCount: 52, myChoice: VoteResult.no),
  ),
  _HistoryEntry(
    '2 lip 2026',
    'Jul 2, 2026',
    'Czy powiedziałbyś przyjacielowi gorzką prawdę?',
    VoteResult(yesCount: 71, noCount: 29, myChoice: VoteResult.yes),
  ),
  _HistoryEntry(
    '1 lip 2026',
    'Jul 1, 2026',
    'Czy można kochać dwie osoby naraz?',
    VoteResult(yesCount: 39, noCount: 61, myChoice: VoteResult.no),
  ),
];

class _HistoryCanvas extends StatelessWidget {
  const _HistoryCanvas({required this.lang});
  final String lang;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _q(lang, 'Historia', 'History'),
                        style: TextStyle(
                          color: context.colors.ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.close_rounded, color: context.colors.subtle),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _q(
                      lang,
                      'Wszystkie pytania, na które oddałeś głos — razem '
                          'z wynikami głosowania.',
                      'Every question you voted on, with how people voted.',
                    ),
                    style: TextStyle(
                      color: context.colors.subtle,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final e in _historyEntries) ...[
                            _HistoryRow(entry: e, lang: lang),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.lang});
  final _HistoryEntry entry;
  final String lang;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: context.colors.accent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 13,
                color: context.colors.subtle,
              ),
              const SizedBox(width: 6),
              Text(
                lang == 'pl' ? entry.datePl : entry.dateEn,
                style: TextStyle(
                  color: context.colors.subtle,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              Text(
                _q(
                  lang,
                  '${entry.result.total} głosów',
                  '${entry.result.total} votes',
                ),
                style: TextStyle(color: context.colors.subtle, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            entry.question,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 14.5,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _MiniVoteBar(result: entry.result),
        ],
      ),
    );
  }
}

class _MiniVoteBar extends StatelessWidget {
  const _MiniVoteBar({required this.result});
  final VoteResult result;

  @override
  Widget build(BuildContext context) {
    final mineYes = result.myChoice == VoteResult.yes;
    final mineNo = result.myChoice == VoteResult.no;
    return Column(
      children: [
        Row(
          children: [
            _SideLabel(
              label: 'TAK',
              pct: result.yesPct,
              color: AppTheme.yes,
              mine: mineYes,
            ),
            const Spacer(),
            _SideLabel(
              label: 'NIE',
              pct: result.noPct,
              color: AppTheme.no,
              mine: mineNo,
              trailing: true,
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(color: AppTheme.no.withValues(alpha: 0.85)),
                ),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: result.yesFraction.clamp(0.0, 1.0),
                  child: ColoredBox(
                    color: AppTheme.yes.withValues(alpha: 0.95),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SideLabel extends StatelessWidget {
  const _SideLabel({
    required this.label,
    required this.pct,
    required this.color,
    required this.mine,
    this.trailing = false,
  });
  final String label;
  final int pct;
  final Color color;
  final bool mine;
  final bool trailing;

  @override
  Widget build(BuildContext context) {
    final name = Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
      ),
    );
    final percent = Text(
      '$pct%',
      style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800),
    );
    final check = mine
        ? Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(Icons.check_circle_rounded, color: color, size: 13),
          )
        : const SizedBox.shrink();
    return Row(
      children: trailing
          ? [percent, const SizedBox(width: 6), name, check]
          : [name, const SizedBox(width: 6), percent, check],
    );
  }
}

// ─── fonts ────────────────────────────────────────────────────────────────────

/// Loads the fonts the real widgets need into the head-less render: the bundled
/// `Anton` display face plus `Roboto` (body text) and `MaterialIcons` from the
/// Flutter SDK's cached font artifacts.
Future<void> _loadFonts() async {
  await _load('Anton', ['assets/fonts/Anton-Regular.ttf']);
  final materialFonts = '${_flutterRoot()}/bin/cache/artifacts/material_fonts';
  await _load('MaterialIcons', ['$materialFonts/materialicons-regular.otf']);
  await _load('Roboto', [
    '$materialFonts/roboto-regular.ttf',
    '$materialFonts/roboto-medium.ttf',
    '$materialFonts/roboto-bold.ttf',
  ]);
}

Future<void> _load(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    loader.addFont(file.readAsBytes().then((b) => b.buffer.asByteData()));
    any = true;
  }
  if (!any) {
    stderr.writeln('⚠ font not found, glyphs may be blank: $family');
    return;
  }
  await loader.load();
}

/// Locates the Flutter SDK root: prefers $FLUTTER_ROOT, else walks up from the
/// test runner executable to the dir that contains `bin/cache`.
String _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env.replaceAll(r'\', '/');
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.path != dir.parent.path) {
    if (Directory('${dir.path}/bin/cache').existsSync()) {
      return dir.path.replaceAll(r'\', '/');
    }
    dir = dir.parent;
  }
  throw StateError('Could not locate the Flutter SDK; set FLUTTER_ROOT.');
}
