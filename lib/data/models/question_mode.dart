import 'question.dart';

/// The four "modes" a PRO user can pin the feed to — owner-curated groupings
/// of `questions.category` (2026-09-02), chosen so every tile has weight and
/// the first two match where the traffic comes from (couples / parenting
/// content): Relationships 65 + Friendship 12, Family 64, Money 30 + Work 29,
/// Ethics 39 + Society 39 + Justice 29 + Culture 31. Health, Technology,
/// Environment and the tiny tail stay under "all questions" only.
///
/// A mode is a CLIENT-SIDE filter over the loaded catalog: the deck keeps the
/// daily at index 0 and follows it with the mode's questions in the usual
/// unseen-first order (see `questionDeckProvider`). Nothing is fetched or
/// recorded differently — a question voted inside a mode is marked seen
/// exactly like one met in the plain feed, so it moves to the archive tail on
/// the next launch either way.
///
/// The category strings are the catalog's own (English labels, see
/// `questions.category`); a category no mode names simply belongs to none.
enum QuestionMode {
  relationships({'Relationships', 'Friendship'}),
  family({'Family'}),
  moneyWork({'Money', 'Work'}),
  society({'Ethics', 'Society', 'Justice', 'Culture'});

  const QuestionMode(this.categories);

  /// The `questions.category` values this mode collects.
  final Set<String> categories;

  bool includes(Question question) => categories.contains(question.category);

  /// The mode a category belongs to, or null for one no mode names.
  static QuestionMode? forCategory(String category) {
    for (final mode in values) {
      if (mode.categories.contains(category)) return mode;
    }
    return null;
  }
}
