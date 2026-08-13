import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/question_search_field.dart';
import '../../../core/widgets/sub_screen_chrome.dart';
import '../../../data/models/vote_history_entry.dart';
import '../../../data/models/vote_result.dart';
import '../../account/providers/session_providers.dart';
import '../../monetization/widgets/pro_paywall_sheet.dart';
import '../providers/question_providers.dart';

/// Gold accent for the PRO upsell, matching the "go Premium" hooks elsewhere.
const Color _kGold = Color(0xFFFFC857);

/// Opens the PRO "question history": a full-screen table of every question the
/// user voted on and how the community voted, so a past vote's split is never
/// lost once the feed moves on. Pushed as a sub-screen (title + X to close) so
/// it matches the Favorites screen rather than sliding up as a drag sheet.
///
/// The screen gates itself: premium sees the history, everyone else sees a PRO
/// upsell — so it's safe to open from anywhere without a premium check up front.
Future<void> openHistory(BuildContext context) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const HistoryScreen()));
}

/// Scroll offset past which the header's own X has left the viewport, so the
/// floating one takes over. Derived from the header's placement: 8px of top
/// padding plus the 38px button, minus a few pixels so the swap overlaps
/// instead of leaving a moment with no close button on screen.
const double _kFloatingCloseFrom = 42;

/// Full-screen PRO history of the user's votes. Mirrors the Favorites screen: a
/// [TopGlow], a [SubScreenHeader] (title + close), then the body — the premium
/// list of voted questions, or the PRO upsell for everyone else.
///
/// A long history can be scrolled far past the header, so a second, *pinned* X
/// fades in at the same spot once the header's own has scrolled away — closing
/// the screen is always one tap, without scrolling back to the top.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showFloatingClose = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scrollController.offset > _kFloatingCloseFrom;
    if (show != _showFloatingClose) {
      setState(() => _showFloatingClose = show);
    }
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final isPremium = ref.watch(isPremiumProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          const TopGlow(),
          SafeArea(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                32 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SubScreenHeader(
                        title: context.l10n.historyTitle,
                        onClose: _close,
                      ),
                      const SizedBox(height: 16),
                      isPremium ? const _HistoryBody() : const _HistoryUpsell(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Same padding / max width as the scrolling column, so the pinned X
          // lands exactly where the header's one was — it reads as the button
          // sticking rather than a second control appearing.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, left: 20, right: 20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: IgnorePointer(
                      ignoring: !_showFloatingClose,
                      child: AnimatedOpacity(
                        opacity: _showFloatingClose ? 1 : 0,
                        duration: const Duration(milliseconds: 140),
                        child: SubScreenCloseButton(onTap: _close),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The premium view: a short subtitle, then the list of voted questions (or a
/// loading / error / empty state). The list itself doesn't scroll — the screen's
/// outer [SingleChildScrollView] does — so rows are laid out as a plain Column.
///
/// Long histories (≥ [kQuestionSearchMinItems] rows) grow a search field that
/// filters rows by question text, accent-insensitively.
class _HistoryBody extends ConsumerStatefulWidget {
  const _HistoryBody();

  @override
  ConsumerState<_HistoryBody> createState() => _HistoryBodyState();
}

class _HistoryBodyState extends ConsumerState<_HistoryBody> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(voteHistoryProvider);
    final lang = Localizations.localeOf(context).languageCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.historySubtitle,
          style: TextStyle(
            color: context.colors.subtle,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 16),
        historyAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => _HistoryMessage(
            icon: Icons.cloud_off_rounded,
            title: context.l10n.historyLoadError,
            action: TextButton(
              onPressed: () => ref.invalidate(voteHistoryProvider),
              child: Text(context.l10n.tryAgain),
            ),
          ),
          data: (entries) {
            if (entries.isEmpty) {
              return _HistoryMessage(
                icon: Icons.history_toggle_off_rounded,
                title: context.l10n.historyEmptyTitle,
                subtitle: context.l10n.historyEmptyBody,
              );
            }
            final matching = entries
                .where((e) => matchesQuestionQuery(e.questionText, _query))
                .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (entries.length >= kQuestionSearchMinItems) ...[
                  QuestionSearchField(
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 14),
                ],
                if (matching.isEmpty)
                  _HistoryMessage(
                    icon: Icons.search_off_rounded,
                    title: context.l10n.searchNoResultsTitle,
                    subtitle: context.l10n.searchNoResultsBody,
                  )
                else
                  for (final entry in matching) ...[
                    _HistoryRow(entry: entry, lang: lang),
                    const SizedBox(height: 10),
                  ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One history row: when the user voted, the question text, and the community
/// split.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.lang});

  final VoteHistoryEntry entry;
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
                _formatDate(entry.votedAt, lang),
                style: TextStyle(
                  color: context.colors.subtle,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            entry.questionText,
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
          _MiniVoteBar(result: entry.votes),
        ],
      ),
    );
  }
}

/// The compact community split for one past question: a TAK%/NIE% label line
/// over a single split bar, with a check on the side the caller voted. Collapses
/// to a quiet "no votes" line when nobody voted.
class _MiniVoteBar extends StatelessWidget {
  const _MiniVoteBar({required this.result});

  final VoteResult result;

  @override
  Widget build(BuildContext context) {
    if (result.total == 0) {
      return Text(
        context.l10n.historyNoVotes,
        style: TextStyle(
          color: context.colors.subtle,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    final mineYes = result.myChoice == VoteResult.yes;
    final mineNo = result.myChoice == VoteResult.no;

    return Column(
      children: [
        Row(
          children: [
            _SideLabel(
              label: context.l10n.voteYes,
              pct: result.yesPct,
              color: AppTheme.yes,
              mine: mineYes,
            ),
            const Spacer(),
            _SideLabel(
              label: context.l10n.voteNo,
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
                // Full-width NIE (red) track …
                Positioned.fill(
                  child: ColoredBox(color: AppTheme.no.withValues(alpha: 0.85)),
                ),
                // … overlaid by the TAK (green) portion from the left.
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

  /// When true the percentage leads and the label follows (the NIE side), so the
  /// two sides read symmetrically from the centre out.
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

/// Centred message block for the empty / error states.
class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: context.colors.subtle, size: 40),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.subtle, fontSize: 13),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    );
  }
}

/// The non-premium view: explains the history is a PRO feature and offers the
/// paywall. On purchase the session refreshes and the parent screen rebuilds into
/// the real history (it watches [isPremiumProvider]).
class _HistoryUpsell extends ConsumerStatefulWidget {
  const _HistoryUpsell();

  @override
  ConsumerState<_HistoryUpsell> createState() => _HistoryUpsellState();
}

class _HistoryUpsellState extends ConsumerState<_HistoryUpsell> {
  bool _opening = false;

  Future<void> _goPro() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final purchased = await showProPaywall(
        context,
        source: PaywallSource.history,
      );
      if (!mounted) return;
      if (purchased) {
        await ref.read(sessionProvider.notifier).refresh();
        if (!mounted) return;
        AppToast.success(context, context.l10n.settingsPremiumActiveToast);
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 32, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kGold.withValues(alpha: 0.14),
              border: Border.all(color: _kGold.withValues(alpha: 0.45)),
            ),
            child: const Icon(Icons.history_rounded, color: _kGold, size: 30),
          ),
          const SizedBox(height: 18),
          Text(
            context.l10n.historyPremiumTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.l10n.historyPremiumBody,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colors.subtle,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
          _GoProButton(busy: _opening, onTap: _goPro),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _GoProButton extends StatelessWidget {
  const _GoProButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kGold,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.black,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.workspace_premium_rounded,
                        color: Colors.black,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        context.l10n.goPro,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// A quiet outlined "Historia" pill, sized and styled to sit next to the share
/// pill under every readable question. Opens [openHistory]; the screen itself
/// gates premium, so this is shown to everyone (free users land on the PRO
/// upsell).
class HistoryButton extends StatelessWidget {
  const HistoryButton({super.key});

  static const _radius = BorderRadius.all(Radius.circular(30));

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.historyTooltip,
      child: Tooltip(
        message: context.l10n.historyTooltip,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: _radius,
            side: BorderSide(color: context.colors.hairline),
          ),
          child: InkWell(
            borderRadius: _radius,
            onTap: () => openHistory(context),
            // Sized to the touch target, matching the share pill beside it.
            child: SizedBox(
              width: kMinTouchTarget,
              height: kMinTouchTarget,
              child: Center(
                child: Icon(
                  Icons.history_rounded,
                  size: 20,
                  color: context.colors.subtle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Short, locale-aware date for a history row, e.g. PL "22 cze 2026", EN
/// "Jun 22, 2026". Hand-rolled to avoid pulling in `intl`'s date initialisation
/// (the rest of the app formats dates the same way — see settings_screen).
String _formatDate(DateTime date, String lang) {
  const monthsPl = [
    'sty',
    'lut',
    'mar',
    'kwi',
    'maj',
    'cze',
    'lip',
    'sie',
    'wrz',
    'paź',
    'lis',
    'gru',
  ];
  const monthsEn = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final d = date.toLocal();
  if (lang == 'pl') {
    return '${d.day} ${monthsPl[d.month - 1]} ${d.year}';
  }
  return '${monthsEn[d.month - 1]} ${d.day}, ${d.year}';
}
