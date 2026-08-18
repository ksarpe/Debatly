import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/question_search_field.dart';
import '../../../core/widgets/sub_screen_chrome.dart';
import '../../../data/models/vote_history_entry.dart';
import '../../../data/models/vote_result.dart';
import '../../account/providers/session_providers.dart';
import '../../monetization/widgets/pro_paywall_screen.dart';
import '../providers/question_providers.dart';

/// Opens the "question history": every question the user voted on, laid out as
/// date-grouped result cards, so a past vote's split is never lost once the
/// feed moves on. Pushed as a sub-screen (title + X to close) so it matches the
/// Favorites screen rather than sliding up as a drag sheet.
///
/// The screen gates itself: premium sees the full record, a free account sees
/// only today's card(s) — the daily question is always free — with the older
/// history behind a locked panel that opens the paywall. Safe to open from
/// anywhere without a premium check up front.
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

/// Full-screen history of the user's votes. Mirrors the Favorites screen: a
/// [TopGlow], a [SubScreenHeader] (title + close), then the body — the answered
/// count with an expandable search, and the date-grouped grid of vote cards
/// (free accounts: today only, older history locked behind the paywall).
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
                      const _HistoryBody(),
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

/// The history body: the answered count with an expandable search on one row,
/// then the vote cards grouped under day headers, two to a row (or a loading /
/// error / empty state). The list itself doesn't scroll — the screen's outer
/// [SingleChildScrollView] does.
///
/// Free accounts see only entries from the local today (the always-free daily);
/// everything older sits behind [_LockedHistoryPanel]. The answered count still
/// shows the lifetime total (via the non-gated conformity stats), so a locked
/// history reads as "148 answered — and they're in there".
///
/// Long histories (≥ [kQuestionSearchMinItems] visible cards) grow a search
/// icon that expands into a text filter, accent-insensitive.
class _HistoryBody extends ConsumerStatefulWidget {
  const _HistoryBody();

  @override
  ConsumerState<_HistoryBody> createState() => _HistoryBodyState();
}

/// How many cards render before the rest hides behind "load more". All rows
/// are already fetched (the RPC returns the record in one shot); the cap only
/// bounds how many card widgets build at once, so a 500-vote history doesn't
/// jank the screen open. Revealing more is instant — no request behind it.
const int _kHistoryPageSize = 30;

class _HistoryBodyState extends ConsumerState<_HistoryBody> {
  String _query = '';
  bool _searchOpen = false;
  int _shown = _kHistoryPageSize;

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(voteHistoryProvider);
    final isPremium = ref.watch(isPremiumProvider);
    final statsAsync = ref.watch(conformityStatsProvider);
    final lang = Localizations.localeOf(context).languageCode;

    return historyAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 48),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => _HistoryMessage(
        icon: Icons.cloud_off_rounded,
        title: context.l10n.historyLoadError,
        action: TextButton(
          onPressed: () => ref.invalidate(voteHistoryProvider),
          child: Text(
            context.l10n.tryAgain.toUpperCase(),
            style: AppTypography.action(fontSize: 13),
          ),
        ),
      ),
      data: (entries) {
        // Free tier: the daily is always free, so today's votes are too — the
        // server already trims to the last 48h, the client trims to the local
        // calendar day the user actually means by "today".
        final visible = isPremium
            ? entries
            : entries.where((e) => _isLocalToday(e.votedAt)).toList();
        // Lifetime total from the non-gated conformity stats, so free accounts
        // see their real record size, not just today's slice.
        final answered = statsAsync.asData?.value.totalVotes ?? visible.length;
        final searchable = visible.length >= kQuestionSearchMinItems;
        final matching = visible
            .where((e) => matchesQuestionQuery(e.questionText, _query))
            .toList();
        // The page cap cuts at an exact card count (mid-day if needed) — a
        // reveal regroups, so a split day just grows more cards under the same
        // header. Whole-group rounding would defeat the cap on a heavy voting
        // day (a PRO user can clear 50 questions in an evening).
        final shown = matching.take(_shown).toList();
        final hidden = matching.length - shown.length;
        final groups = _groupByLocalDay(shown);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (answered > 0 || visible.isNotEmpty) ...[
              _CountSearchHeader(
                answered: answered,
                searchable: searchable,
                searchOpen: _searchOpen,
                onOpenSearch: () => setState(() => _searchOpen = true),
                onCloseSearch: () => setState(() {
                  _searchOpen = false;
                  _query = '';
                  _shown = _kHistoryPageSize;
                }),
                // A new query is a new view — start it from the first page.
                onQuery: (value) => setState(() {
                  _query = value;
                  _shown = _kHistoryPageSize;
                }),
              ),
              const SizedBox(height: 12),
            ],
            if (visible.isEmpty)
              _HistoryMessage(
                icon: Icons.history_toggle_off_rounded,
                title: context.l10n.historyEmptyTitle,
                subtitle: context.l10n.historyEmptyBody,
              )
            else if (matching.isEmpty)
              _HistoryMessage(
                icon: Icons.search_off_rounded,
                title: context.l10n.searchNoResultsTitle,
                subtitle: context.l10n.searchNoResultsBody,
              )
            else ...[
              for (final group in groups) ...[
                _DayHeader(label: _formatDayHeader(group.day, lang)),
                const SizedBox(height: 8),
                _DayGrid(entries: group.entries),
                const SizedBox(height: 16),
              ],
              if (hidden > 0)
                _LoadMoreButton(
                  hidden: hidden,
                  onTap: () => setState(() => _shown += _kHistoryPageSize),
                ),
            ],
            if (!isPremium) ...[
              const SizedBox(height: 4),
              const _LockedHistoryPanel(),
            ],
          ],
        );
      },
    );
  }
}

/// The row under the title: "N answered" on the left, a bare magnifier on the
/// right. Tapping the magnifier swaps the whole row for the search field
/// (autofocused); its X clears the text, then collapses back to this row.
class _CountSearchHeader extends StatelessWidget {
  const _CountSearchHeader({
    required this.answered,
    required this.searchable,
    required this.searchOpen,
    required this.onOpenSearch,
    required this.onCloseSearch,
    required this.onQuery,
  });

  final int answered;
  final bool searchable;
  final bool searchOpen;
  final VoidCallback onOpenSearch;
  final VoidCallback onCloseSearch;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    final child = searchOpen
        ? KeyedSubtree(
            key: const ValueKey('history-search'),
            child: QuestionSearchField(
              autofocus: true,
              onChanged: onQuery,
              onClose: onCloseSearch,
            ),
          )
        : KeyedSubtree(
            key: const ValueKey('history-count'),
            child: Row(
              children: [
                Expanded(
                  // A number-led stat line — set in the condensed numeral face,
                  // uppercase, like every other count in the app.
                  child: Text(
                    context.l10n.historyAnsweredCount(answered).toUpperCase(),
                    style: AppTypography.numeric(
                      20,
                    ).copyWith(color: context.colors.ink),
                  ),
                ),
                if (searchable)
                  IconButton(
                    tooltip: context.l10n.historySearchTooltip,
                    onPressed: onOpenSearch,
                    icon: const Icon(
                      Icons.search_rounded,
                      size: 24,
                      color: AppTheme.spark,
                    ),
                  ),
              ],
            ),
          );

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 140),
        child: child,
      ),
    );
  }
}

/// A quiet day header over each group of cards, e.g. PL "18 SIE", EN "AUG 18"
/// (with the year appended once the group leaves the current year).
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTypography.eyebrow(
        fontSize: 11,
      ).copyWith(color: context.colors.subtle),
    );
  }
}

/// One day's cards, two to a row. [IntrinsicHeight] keeps each pair the same
/// height, so a short question stretches to match its longer neighbour instead
/// of leaving a ragged grid.
class _DayGrid extends StatelessWidget {
  const _DayGrid({required this.entries});

  final List<VoteHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _HistoryCard(entry: entries[i])),
              const SizedBox(width: 10),
              Expanded(
                child: i + 1 < entries.length
                    ? _HistoryCard(entry: entries[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
      if (i + 2 < entries.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }
}

/// The full-width "Load N more" pill under the visible cards — the rest of the
/// (already fetched) history reveals a page at a time, so a long record doesn't
/// build hundreds of cards on open.
class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.hidden, required this.onTap});

  final int hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.accent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 52,
          child: Center(
            child: Text(
              context.l10n.historyLoadMore(hidden).toUpperCase(),
              style: AppTypography.action(
                fontSize: 13,
              ).copyWith(color: context.colors.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// One vote card: "YOU: YES/NO" in the vote's colour, the community split in
/// the corner ("64 vs 36", the user's side first), and the question text. The
/// whole card is tinted by the user's side — green for TAK, red for NIE — so a
/// page of history reads as the user's voting record at a glance.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry});

  final VoteHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final votes = entry.votes;
    final mineYes = votes.myChoice == VoteResult.yes;
    final mineNo = votes.myChoice == VoteResult.no;
    final side = mineYes
        ? AppTheme.yes
        : mineNo
        ? AppTheme.no
        : context.colors.subtle;
    final voteLabel = mineYes
        ? context.l10n.voteYes
        : mineNo
        ? context.l10n.voteNo
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: side.withValues(alpha: 0.10),
        border: Border.all(color: side.withValues(alpha: 0.40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: voteLabel == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          context.l10n.historyYourVote(voteLabel).toUpperCase(),
                          style: AppTypography.eyebrow(
                            fontSize: 10.5,
                            tracking: 0.14,
                          ).copyWith(color: side),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              _CornerSplit(votes: votes),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            entry.questionText,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.body(
              fontSize: 14,
              height: 1.32,
            ).copyWith(color: context.colors.ink),
          ),
        ],
      ),
    );
  }
}

/// The corner split, user's side leading: "64 vs 36" with each number in its
/// side's colour, so the pair reads green-vs-red at a glance. Collapses to a
/// quiet "no votes" note when nobody voted.
class _CornerSplit extends StatelessWidget {
  const _CornerSplit({required this.votes});

  final VoteResult votes;

  @override
  Widget build(BuildContext context) {
    if (votes.total == 0) {
      return Text(
        context.l10n.historyNoVotes,
        style: AppTypography.support(
          fontSize: 11,
        ).copyWith(color: context.colors.subtle),
      );
    }

    final mineNo = votes.myChoice == VoteResult.no;
    final firstPct = mineNo ? votes.noPct : votes.yesPct;
    final secondPct = mineNo ? votes.yesPct : votes.noPct;
    final firstColor = mineNo ? AppTheme.no : AppTheme.yes;
    final secondColor = mineNo ? AppTheme.yes : AppTheme.no;

    TextStyle pct(Color color) =>
        AppTypography.numeric(16).copyWith(color: color);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('$firstPct', style: pct(firstColor)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Text(
            context.l10n.historyVersus.toUpperCase(),
            style: AppTypography.eyebrow(
              fontSize: 10,
              tracking: 0.12,
            ).copyWith(color: context.colors.subtle),
          ),
        ),
        Text('$secondPct', style: pct(secondColor)),
      ],
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
            title.toUpperCase(),
            textAlign: TextAlign.center,
            style: AppTypography.title(
              fontSize: 30,
            ).copyWith(color: context.colors.ink),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: AppTypography.support(
                fontSize: 13,
              ).copyWith(color: context.colors.subtle),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    );
  }
}

/// The free tier's locked older history: ghost tiles under a big padlock.
/// Tapping anywhere opens the paywall ([PaywallSource.history]); on purchase
/// the session refreshes and the history refetches into the full record.
class _LockedHistoryPanel extends ConsumerStatefulWidget {
  const _LockedHistoryPanel();

  @override
  ConsumerState<_LockedHistoryPanel> createState() =>
      _LockedHistoryPanelState();
}

class _LockedHistoryPanelState extends ConsumerState<_LockedHistoryPanel> {
  bool _opening = false;

  Future<void> _unlock() async {
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
        // The RPC returns more rows for premium — refetch, don't just rebuild.
        ref.invalidate(voteHistoryProvider);
        AppToast.success(context, context.l10n.settingsPremiumActiveToast);
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: context.colors.cardSurface,
        border: Border.all(color: context.colors.hairline),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _opening ? null : _unlock,
          child: Stack(
            children: [
              // Ghost tiles behind the lock — the shape of the hidden cards.
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.30,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Expanded(
                            child: _GhostRow(color: context.colors.accent),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: _GhostRow(color: context.colors.accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 30,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.spark.withValues(alpha: 0.14),
                        border: Border.all(
                          color: AppTheme.spark.withValues(alpha: 0.45),
                        ),
                      ),
                      child: _opening
                          ? const Padding(
                              padding: EdgeInsets.all(18),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: AppTheme.spark,
                              ),
                            )
                          : const Icon(
                              Icons.lock_rounded,
                              color: AppTheme.spark,
                              size: 30,
                            ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      context.l10n.historyLockedTitle.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: AppTypography.title(
                        fontSize: 30,
                      ).copyWith(color: context.colors.ink),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.l10n.historyLockedBody,
                      textAlign: TextAlign.center,
                      style: AppTypography.support(
                        fontSize: 13,
                        height: 1.45,
                      ).copyWith(color: context.colors.subtle),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pair of blank card-shaped tiles for the locked panel's background.
class _GhostRow extends StatelessWidget {
  const _GhostRow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget tile() => Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
    return Row(children: [tile(), const SizedBox(width: 10), tile()]);
  }
}

/// One day's worth of history, in feed order (newest vote first).
class _DayGroup {
  _DayGroup(this.day) : entries = [];

  /// Midnight (local) of the group's calendar day.
  final DateTime day;
  final List<VoteHistoryEntry> entries;
}

/// Splits [entries] (already newest-first) into consecutive local-day groups.
List<_DayGroup> _groupByLocalDay(List<VoteHistoryEntry> entries) {
  final groups = <_DayGroup>[];
  for (final entry in entries) {
    final local = entry.votedAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    if (groups.isEmpty || groups.last.day != day) {
      groups.add(_DayGroup(day));
    }
    groups.last.entries.add(entry);
  }
  return groups;
}

/// True when the (UTC) vote timestamp falls on the user's local today — the
/// free tier's window into the history.
bool _isLocalToday(DateTime votedAt) {
  final local = votedAt.toLocal();
  final now = DateTime.now();
  return local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
}

/// Locale-aware day header, e.g. PL "18 SIE", EN "AUG 18"; the year is appended
/// once the group leaves the current year ("18 SIE 2025"). Hand-rolled to avoid
/// pulling in `intl`'s date initialisation (the rest of the app formats dates
/// the same way — see settings_screen).
String _formatDayHeader(DateTime day, String lang) {
  const monthsPl = [
    'STY',
    'LUT',
    'MAR',
    'KWI',
    'MAJ',
    'CZE',
    'LIP',
    'SIE',
    'WRZ',
    'PAŹ',
    'LIS',
    'GRU',
  ];
  const monthsEn = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  final sameYear = day.year == DateTime.now().year;
  if (lang == 'pl') {
    final base = '${day.day} ${monthsPl[day.month - 1]}';
    return sameYear ? base : '$base ${day.year}';
  }
  final base = '${monthsEn[day.month - 1]} ${day.day}';
  return sameYear ? base : '$base, ${day.year}';
}
