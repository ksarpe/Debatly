import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/app_toast.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sub_screen_chrome.dart';
import '../../../data/models/question.dart';
import '../../../services/review_service.dart';
import '../../onboarding/providers/onboarding_providers.dart';
import '../../onboarding/screens/onboarding_screen.dart';
import '../../questions/providers/question_providers.dart';
import '../../questions/providers/swipe_hint_providers.dart';
import '../providers/review_providers.dart';
import '../widgets/settings_nav_row.dart';
import '../widgets/settings_primitives.dart';

// Developer/tester tools reached from the DEV section in settings. Visible only
// behind [devToolsEnabledProvider] (debug builds, DEV_TOOLS builds or listed
// tester accounts), so the copy is deliberately unlocalised.

/// Sub-screen with tester utilities: replay/reset the onboarding tutorial and
/// pin an arbitrary question onto the home deck.
class DevToolsScreen extends ConsumerWidget {
  const DevToolsScreen({super.key});

  void _previewOnboarding(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) =>
            OnboardingScreen(onFinish: () => Navigator.of(ctx).maybePop()),
      ),
    );
  }

  Future<void> _resetOnboarding(BuildContext context, WidgetRef ref) async {
    final overlay = AppToast.capture(context);
    await ref.read(onboardingControllerProvider.notifier).reset();
    await ref.read(swipeDiscoveredControllerProvider.notifier).reset();
    AppToast.showOn(
      overlay,
      'Onboarding pokaże się przy następnym uruchomieniu aplikacji',
      type: ToastType.success,
    );
  }

  void _openCatalogPicker(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const _DevQuestionPickerScreen()),
    );
  }

  Future<void> _openCustomQuestion(BuildContext context, WidgetRef ref) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _CustomQuestionDialog(),
    );
    if (text == null || text.isEmpty || !context.mounted) return;
    // A synthetic id the question providers short-circuit on (the vote/smaczki
    // RPCs take uuid params, so it must never reach the server): smaczki come
    // back empty and a vote is faked locally — the pin previews both vote
    // states without server errors.
    pinDevQuestion(
      context,
      ref,
      Question(
        id: kDevCustomQuestionId,
        category: 'general',
        questionText: text,
      ),
    );
  }

  void _unpin(BuildContext context, WidgetRef ref) {
    ref.read(devPinnedQuestionProvider.notifier).unpin();
    ref.read(questionIndexProvider.notifier).toDaily();
    AppToast.show(context, 'Odpięto pytanie testowe', type: ToastType.info);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = ref.watch(devPinnedQuestionProvider);

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
                        title: 'DEV',
                        onClose: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(height: 24),

                      const SettingsSectionLabel('ONBOARDING'),
                      const SizedBox(height: 12),
                      SettingsCard(
                        children: [
                          SettingsNavRow(
                            icon: Icons.play_circle_outline,
                            title: 'Podgląd onboardingu',
                            subtitle: 'Otwiera tutorial, nie zmienia flag',
                            onTap: () => _previewOnboarding(context),
                          ),
                          const SettingsRowDivider(),
                          SettingsNavRow(
                            icon: Icons.replay_rounded,
                            title: 'Zresetuj onboarding',
                            subtitle:
                                'Uruchomi się przy następnym starcie aplikacji',
                            onTap: () => _resetOnboarding(context, ref),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      const SettingsSectionLabel('PYTANIE TESTOWE'),
                      const SizedBox(height: 12),
                      SettingsCard(
                        children: [
                          SettingsNavRow(
                            icon: Icons.list_alt_rounded,
                            title: 'Wybierz z katalogu',
                            subtitle: 'Wyszukaj i pokaż pytanie na ekranie',
                            onTap: () => _openCatalogPicker(context),
                          ),
                          const SettingsRowDivider(),
                          SettingsNavRow(
                            icon: Icons.edit_note_rounded,
                            title: 'Własne pytanie',
                            subtitle: 'Wpisz dowolny tekst (tylko podgląd UI)',
                            onTap: () => _openCustomQuestion(context, ref),
                          ),
                          if (pinned != null) ...[
                            const SettingsRowDivider(),
                            SettingsNavRow(
                              icon: Icons.push_pin_outlined,
                              iconColor: kDanger,
                              titleColor: kDanger,
                              title: 'Odepnij pytanie testowe',
                              subtitle: pinned.questionText.isNotEmpty
                                  ? pinned.questionText
                                  : (pinned.teaser ?? pinned.id),
                              onTap: () => _unpin(context, ref),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 28),

                      const SettingsSectionLabel('PROŚBA O OCENĘ'),
                      const SizedBox(height: 12),
                      const _ReviewDevSection(),
                      const SizedBox(height: 16),
                      Text(
                        'Sekcja widoczna tylko w buildach debug / DEV_TOOLS '
                        'oraz na kontach testerów. Przypięte pytanie żyje do '
                        'zamknięcia aplikacji.',
                        style: TextStyle(
                          color: context.colors.subtle,
                          fontSize: 12,
                          height: 1.4,
                        ),
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

/// Tester tools for the store-review flow: fire the native sheet on demand and
/// reset the vote-milestone odometer so the 3rd/7th-vote asks can be replayed.
/// Stateful so the odometer subtitle refreshes right after a reset.
class _ReviewDevSection extends ConsumerStatefulWidget {
  const _ReviewDevSection();

  @override
  ConsumerState<_ReviewDevSection> createState() => _ReviewDevSectionState();
}

class _ReviewDevSectionState extends ConsumerState<_ReviewDevSection> {
  Future<void> _requestNow() async {
    final overlay = AppToast.capture(context);
    await ReviewService.requestReview();
    AppToast.showOn(
      overlay,
      'Poproszono system o arkusz oceny. W buildzie debug zwykle się nie '
      'pokaże — Android wymaga instalacji z Play, iOS produkcji.',
      type: ToastType.info,
    );
  }

  Future<void> _reset() async {
    final overlay = AppToast.capture(context);
    await ref.read(reviewPromptControllerProvider.notifier).debugReset();
    if (mounted) setState(() {});
    AppToast.showOn(
      overlay,
      'Zresetowano — prośba wróci po 3. i 7. głosie',
      type: ToastType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref
        .read(reviewPromptControllerProvider.notifier)
        .debugState();
    return SettingsCard(
      children: [
        SettingsNavRow(
          icon: Icons.star_rate_rounded,
          title: 'Pokaż arkusz oceny teraz',
          subtitle: 'Natywna prośba systemu, bez zmiany liczników',
          onTap: _requestNow,
        ),
        const SettingsRowDivider(),
        SettingsNavRow(
          icon: Icons.restart_alt_rounded,
          title: 'Zresetuj liczniki prośby o ocenę',
          subtitle:
              'Głosy: ${state.votes} · zużyty próg: '
              '${state.lastMilestone == 0 ? 'brak' : state.lastMilestone} '
              '(progi: ${kReviewVoteMilestones.join(', ')})',
          onTap: _reset,
        ),
      ],
    );
  }
}

/// The "Własne pytanie" prompt. Owns its [TextEditingController] as State so
/// the framework disposes it only after the dialog route — including its exit
/// animation, during which the (focused, IME-attached) TextField is still
/// live — is fully torn down. Disposing it inline right after `showDialog`
/// returned threw "A TextEditingController was used after being disposed" the
/// moment "Pokaż" was tapped.
class _CustomQuestionDialog extends StatefulWidget {
  const _CustomQuestionDialog();

  @override
  State<_CustomQuestionDialog> createState() => _CustomQuestionDialogState();
}

class _CustomQuestionDialogState extends State<_CustomQuestionDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Własne pytanie'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 4,
        minLines: 2,
        decoration: const InputDecoration(
          hintText: 'Czy…? (tekst pytania do podglądu na ekranie)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Pokaż'),
        ),
      ],
    );
  }
}

/// Pins [q] onto the deck, jumps the index to it and unwinds back to the home
/// screen so the tester lands straight on the pinned question.
void pinDevQuestion(BuildContext context, WidgetRef ref, Question q) {
  ref.read(devPinnedQuestionProvider.notifier).pin(q);
  final deck = ref.read(questionDeckProvider);
  final index = deck.indexWhere((x) => x.id == q.id);
  ref.read(questionIndexProvider.notifier).jumpTo(index < 0 ? 0 : index);
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// Full-catalog browser with a search box; tapping a row pins that question.
///
/// Reads the repository directly (not [questionsProvider]) so it also works on
/// a FREE tester account, where the catalog provider is intentionally empty.
/// On a free account the server withholds locked text — those rows show their
/// teaser and pin as the locked card, which is itself useful for testing.
class _DevQuestionPickerScreen extends ConsumerStatefulWidget {
  const _DevQuestionPickerScreen();

  @override
  ConsumerState<_DevQuestionPickerScreen> createState() =>
      _DevQuestionPickerScreenState();
}

class _DevQuestionPickerScreenState
    extends ConsumerState<_DevQuestionPickerScreen> {
  late final Future<List<Question>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = ref.read(questionRepositoryProvider).fetchQuestions();
  }

  List<Question> _filter(List<Question> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((question) {
      return question.questionText.toLowerCase().contains(q) ||
          (question.teaser ?? '').toLowerCase().contains(q) ||
          question.category.toLowerCase().contains(q) ||
          question.id.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          const TopGlow(),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SubScreenHeader(
                        title: 'Wybierz pytanie',
                        onClose: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        autofocus: false,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          hintText: 'Szukaj po treści, kategorii lub ID…',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: context.colors.cardSurface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: context.colors.hairline,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: FutureBuilder<List<Question>>(
                          future: _future,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (snapshot.hasError) {
                              return Center(
                                child: Text(
                                  'Nie udało się pobrać katalogu:\n'
                                  '${snapshot.error}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: context.colors.subtle,
                                  ),
                                ),
                              );
                            }
                            final visible = _filter(
                              snapshot.data ?? const <Question>[],
                            );
                            if (visible.isEmpty) {
                              return Center(
                                child: Text(
                                  'Brak pytań pasujących do wyszukiwania',
                                  style: TextStyle(
                                    color: context.colors.subtle,
                                  ),
                                ),
                              );
                            }
                            return ListView.separated(
                              padding: EdgeInsets.only(
                                bottom:
                                    24 + MediaQuery.paddingOf(context).bottom,
                              ),
                              itemCount: visible.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final q = visible[i];
                                final locked = q.isLocked ?? false;
                                final title = q.questionText.isNotEmpty
                                    ? q.questionText
                                    : (q.teaser ?? '(brak podglądu treści)');
                                return Material(
                                  color: context.colors.cardSurface,
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () =>
                                        pinDevQuestion(context, ref, q),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        12,
                                        14,
                                        12,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: context.colors.ink,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              height: 1.3,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            [
                                              q.category,
                                              if (q.isPremium) 'premium',
                                              if (locked) 'zablokowane',
                                            ].join(' · '),
                                            style: TextStyle(
                                              color: context.colors.subtle,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
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
