import 'question.dart';

/// The "modes" a PRO user can pin the feed to — owner-curated groupings of
/// `questions.category` (2026-09-02), chosen so every row has weight and the
/// couples / parenting ones match where the traffic comes from:
/// Relationships 65 + Friendship 12, Family 64, Money 30 + Work 29, Ethics
/// 39 + Society 39 + Justice 29 + Culture 31. Health, Technology, Environment
/// and the tiny tail stay under "all topics" only.
///
/// [intimacy] (category `Intimacy`, 2026-09-02) is the PRO-only adult-themes
/// mode — sex, the body, taboo, in a mature register with no explicit
/// content — and ALWAYS the first row on the modes screen (the declaration
/// order here IS the screen order). Its questions never become the daily:
/// the server keeps the category out of `daily_picks`, out of the personal
/// fallback draw and out of the wall's teaser, so a free user never meets
/// one. The label is the topic ("Seks i intymność"), deliberately NOT an age
/// badge like "+18": the app's store ratings (3+ / 14+ depending on the
/// store) rest on the content being text-only discussion, and a self-applied
/// adult badge would claim a rating the content does not need.
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
  intimacy({'Intimacy'}),
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
