import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/locale/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/question_search_field.dart';
import '../../../core/widgets/sub_screen_chrome.dart';
import '../../../data/models/question.dart';
import '../../questions/providers/favorites_providers.dart';
import '../../questions/widgets/share_question_button.dart';
import '../widgets/settings_primitives.dart';

/// Reached from the premium "Favorite questions" row: the user's saved questions
/// as readable cards, each with a share action and a star to remove it.
///
/// The list text comes from [favoriteQuestionsProvider] (favorites are readable
/// forever, so nothing here is ever locked); membership is read live from
/// [favoriteIdsProvider] so removing a card drops it instantly without a refetch.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final favoritesAsync = ref.watch(favoriteQuestionsProvider);
    final liveIds = ref.watch(
      favoriteIdsProvider.select((s) => s.value ?? const <String>{}),
    );

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          const TopGlow(),
          SafeArea(
            child: SingleChildScrollView(
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
                        title: l10n.favoritesTitle,
                        onClose: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(height: 24),
                      favoritesAsync.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.only(top: 80),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (_, _) => _FavoritesEmpty(
                          title: l10n.favoritesEmptyTitle,
                          body: l10n.favoritesEmptyBody,
                        ),
                        data: (questions) {
                          // Honour live membership: a just-removed card is gone
                          // before the provider re-fetches.
                          final visible = questions
                              .where((q) => liveIds.contains(q.id))
                              .toList();
                          if (visible.isEmpty) {
                            return _FavoritesEmpty(
                              title: l10n.favoritesEmptyTitle,
                              body: l10n.favoritesEmptyBody,
                            );
                          }
                          return _FavoritesList(questions: visible);
                        },
                      ),
                    ],
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

/// The non-empty favorites list. Once the collection is long enough
/// (≥ [kQuestionSearchMinItems] cards) a search field appears above it,
/// filtering cards by question text accent-insensitively; while a query is
/// active the field stays even if removals shrink the list below the threshold.
class _FavoritesList extends StatefulWidget {
  const _FavoritesList({required this.questions});

  final List<Question> questions;

  @override
  State<_FavoritesList> createState() => _FavoritesListState();
}

class _FavoritesListState extends State<_FavoritesList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final matching = widget.questions
        .where((q) => matchesQuestionQuery(q.questionText, _query))
        .toList();
    final showSearch =
        widget.questions.length >= kQuestionSearchMinItems ||
        _query.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSearch) ...[
          QuestionSearchField(
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 16),
        ],
        if (matching.isEmpty)
          _FavoritesEmpty(
            icon: Icons.search_off_rounded,
            title: l10n.searchNoResultsTitle,
            body: l10n.searchNoResultsBody,
          )
        else
          for (final q in matching) ...[
            _FavoriteCard(question: q),
            const SizedBox(height: 14),
          ],
      ],
    );
  }
}

/// One saved question: its full text, a share pill and a filled star that
/// removes it from favorites. Removal is always allowed (curating a list you
/// own), so this never routes through the paywall the way the home star does.
class _FavoriteCard extends ConsumerWidget {
  const _FavoriteCard({required this.question});

  final Question question;

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final overlay = AppToast.capture(context);
    final removedMsg = context.l10n.favoriteRemoved;
    final errorMsg = context.l10n.favoriteError;
    try {
      await ref.read(favoriteIdsProvider.notifier).toggle(question.id);
      AppToast.showOn(
        overlay,
        removedMsg,
        type: ToastType.info,
        icon: Icons.star_border_rounded,
      );
    } catch (_) {
      AppToast.showOn(overlay, errorMsg, type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.questionText,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 16,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShareQuestionButton(questionText: question.questionText),
              IconButton(
                onPressed: () => _remove(context, ref),
                tooltip: context.l10n.favoriteRemoveTooltip,
                icon: const Icon(Icons.star_rounded, color: kGold, size: 26),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Empty/error/no-results state for the favorites screen: a muted icon (star by
/// default, a crossed-out magnifier for empty search results) and a one-line
/// nudge.
class _FavoritesEmpty extends StatelessWidget {
  const _FavoritesEmpty({
    required this.title,
    required this.body,
    this.icon = Icons.star_border_rounded,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        children: [
          Icon(icon, size: 48, color: context.colors.subtle),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colors.subtle,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
