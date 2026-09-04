'use client';

import { supabase } from './supabase';

/**
 * Every write goes through a security-definer admin_* RPC that checks
 * admin_require() in the database. The browser holds only the publishable key
 * plus the user's own JWT — there is no direct table access from here.
 */
async function rpc(fn, args = {}) {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw decorate(error);
  return data;
}

/**
 * Kolejność ma znaczenie: DAY_LOCKED musi trafić przed gołe LOCKED wersji
 * roboczej, bo inaczej blokada kalendarza tłumaczy się na komunikat o draftach.
 */
const ERRORS = [
  ['DAY_LOCKED',
    'Dziś i jutro są już opublikowane — dzisiejsze pytanie jest na ekranach, '
    + 'a jutrzejsze poszło w zapowiedź ściany dnia i w zaplanowane powiadomienia. '
    + 'Najbliższy dzień, który można zmienić, to pojutrze.'],
  ['CALENDAR_CHANGED',
    'Kalendarz zmienił się, odkąd otworzyłeś tę stronę — na tym dniu stoi już '
    + 'inne pytanie. Odśwież i wybierz dzień jeszcze raz; nic nie zostało zmienione.'],
  ['QUESTION_USED',
    'To pytanie jest już pytaniem dnia w dniu, którego nie da się ruszyć (dziś, '
    + 'jutro albo w przeszłości). Jedno pytanie może być pytaniem dnia tylko raz.'],
  ['QUESTION_INACTIVE',
    'To pytanie jest nieaktywne — nocne porządkowanie i tak usunęłoby je z kalendarza.'],
  ['CONFLICT',
    'Ktoś zmienił to pytanie, odkąd zacząłeś edycję. Odśwież, żeby zobaczyć aktualną '
    + 'wersję — Twoje zmiany nie zostały nadpisane.'],
  ['FORBIDDEN', 'Brak uprawnień do tej operacji.'],
  ['LOCKED', 'Ta wersja robocza czeka już na zatwierdzenie i nie można jej edytować.'],
];

function decorate(error) {
  const msg = error.message || '';
  const e = new Error(msg);
  e.raw = error;
  e.isConflict = msg.includes('CONFLICT') || msg.includes('CALENDAR_CHANGED');
  e.isForbidden = msg.includes('FORBIDDEN');
  e.friendly = ERRORS.find(([code]) => msg.includes(code))?.[1] ?? msg;
  return e;
}

export const api = {
  me: () => rpc('admin_me'),
  claimInvite: () => rpc('admin_claim_invite'),

  // Licznik sprzedaży /live: liczniki + przychód + ostatnie eventy RevenueCat
  // (billing_events). Strona odpytuje to cyklicznie i gra dźwięk przy nowym zakupie.
  // Domyślnie tylko prawdziwe pieniądze — sandbox, testy z dashboardu RevenueCat
  // i ręczne granty promo są odfiltrowane po stronie serwera (includeTest = podgląd).
  liveSales: (includeTest = false) => rpc('admin_live_sales', { p_include_test: includeTest }),

  // Cały dashboard /stats jednym strzałem; p_days = null → od początku.
  // Konta wewnętrzne (nasze maile) są domyślnie wycięte z każdej liczby.
  // Głosy przychodzą też w rozbiciu na plan, jaki konto miało W CHWILI głosu
  // (totals.votes_pro/votes_free, daily[].votes_pro/votes_free, top_voters[]) —
  // patrz admin_user_pro_window w 20260903120000.
  dashboardStats: (days = null, includeInternal = false) =>
    rpc('admin_dashboard_stats', { p_days: days, p_include_internal: includeInternal }),

  listQuestions: ({ search = null, onlyActive = true, onlyEnReview = false, onlyFavorites = false, onlyUnverified = false, onlyNeedsReview = false, onlyUntagged = false, limit = 50, offset = 0 } = {}) =>
    rpc('admin_list_questions', {
      p_search: search,
      p_only_active: onlyActive,
      p_only_en_review: onlyEnReview,
      p_only_favorites: onlyFavorites,
      p_only_unverified: onlyUnverified,
      p_only_needs_review: onlyNeedsReview,
      p_only_untagged: onlyUntagged,
      p_limit: limit,
      p_offset: offset,
    }),

  // Gwiazdka "ulubione" — per admin, bez draftu. Zwraca nowy stan (true = on).
  toggleFavorite: (questionId) =>
    rpc('admin_toggle_favorite', { p_question_id: questionId }),

  // Zielony ptaszek "zweryfikowane" (pytanie + smaczki) — globalny, bez draftu.
  // Zwraca nowy stan (true = zweryfikowane).
  toggleVerified: (questionId) =>
    rpc('admin_toggle_verified', { p_question_id: questionId }),

  // Chorągiewka "do weryfikacji" — globalna, bez draftu. Zwraca nowy stan (true = oflagowane).
  toggleNeedsReview: (questionId) =>
    rpc('admin_toggle_needs_review', { p_question_id: questionId }),

  getQuestion: (id) => rpc('admin_get_question', { p_id: id }),

  // true = "EN do weryfikacji" (każdy admin); false = zweryfikowane (tylko approver)
  setEnReview: (questionId, flag) =>
    rpc('admin_set_en_review', { p_question_id: questionId, p_flag: flag }),

  history: (questionId) => rpc('admin_question_history', { p_question_id: questionId }),

  saveDraft: ({ action, payload, questionId = null, draftId = null, title = null }) =>
    rpc('admin_save_draft', {
      p_action: action,
      p_payload: payload,
      p_question_id: questionId,
      p_draft_id: draftId,
      p_title: title,
    }),

  submitDraft: (draftId) => rpc('admin_submit_draft', { p_draft_id: draftId }),

  // Never trust a quiet success here. admin_approve_draft once sat on prod as a
  // hand-pasted no-op stub returning {"disabled": true}; the panel read that as
  // "published" and left the draft in Oczekujące. A real apply always names the
  // action it performed, so anything else is a failure, not a success.
  approveDraft: async (draftId) => {
    const res = await rpc('admin_approve_draft', { p_draft_id: draftId });
    if (!res || !res.action) {
      const e = new Error(`APPROVE_NOOP: ${JSON.stringify(res)}`);
      e.friendly = 'Serwer przyjął zatwierdzenie, ale nic nie opublikował — '
        + 'funkcja admin_approve_draft w bazie jest wyłączona lub przestarzała. '
        + 'Nic nie zostało zmienione.';
      throw e;
    }
    return res;
  },
  // Kalendarz pytań dnia (daily_picks). Okno dni z dziurami włącznie — dzień bez
  // wpisu to "losowanie osobiste dla wszystkich", i to też trzeba widzieć.
  // Każdy wiersz niesie stan całego kalendarza (cal_*), tak jak total_count na
  // liście pytań.
  listDailyPicks: (from = null, days = 45) =>
    rpc('admin_list_daily_picks', { p_from: from, p_days: days }),

  // Wyszukiwarka do podmiany. scheduled_on != null ⇒ zamiana miejscami,
  // null ⇒ podmiana (stare pytanie ląduje na końcu kalendarza).
  searchDailyCandidates: ({ search = null, onlyFavorites = false, onlyUnscheduled = false, limit = 30 } = {}) =>
    rpc('admin_search_daily_candidates', {
      p_search: search,
      p_only_favorites: onlyFavorites,
      p_only_unscheduled: onlyUnscheduled,
      p_limit: limit,
    }),

  // Jedyny zapis kalendarza (tylko approver). expected = pytanie, które panel
  // miał na ekranie dla tego dnia, expectEmpty = panel widział pusty dzień —
  // niezgodność którejkolwiek strony jest odrzucana (CALENDAR_CHANGED) zamiast
  // nadpisywać cudzą zmianę. Bez expectEmpty pusty dzień nie miał żadnej
  // blokady: NULL w expected znaczy "pomiń sprawdzenie" (wygoda SQL-editora),
  // a NULL to dokładnie to, co panel wysyłał dla dziury w kalendarzu.
  // Baza pilnuje też podłogi "pojutrze".
  setDailyPick: (date, questionId, expectedQuestionId = null, expectEmpty = false) =>
    rpc('admin_set_daily_pick', {
      p_date: date,
      p_question_id: questionId,
      p_expected_question_id: expectedQuestionId,
      p_expect_empty: expectEmpty,
    }),

  // To samo co nocny cron 02:47 UTC — usuwa martwe przyszłe wpisy i ściąga
  // resztę na kolejne dni. Warto odpalić PRZED przypięciem dnia reklamowego,
  // żeby przesunięcie dat wydarzyło się teraz, a nie w nocy.
  compactDailyPicks: () => rpc('admin_compact_daily_picks'),

  // Dziennik marketingowy: wiersz = dzień. Zwraca { tracking_since, rows } —
  // pola ręczne (filmik, wejścia, pobrania) + policzone przez bazę
  // installs_tracked / purchases / revenue_pln, także dla dni bez wpisu.
  // Upsert nadpisuje cały wiersz (NULL = pole wyczyszczone), ostatni zapis wygrywa.
  listMarketing: () => rpc('admin_list_marketing_stats'),
  upsertMarketingDay: ({ day, video, videoViews, storeVisitsGoogle, storeVisitsAppstore, downloadsGoogle, downloadsAppstore, notes }) =>
    rpc('admin_upsert_marketing_day', {
      p_day: day,
      p_video: video,
      p_video_views: videoViews,
      p_store_visits_google: storeVisitsGoogle,
      p_store_visits_appstore: storeVisitsAppstore,
      p_downloads_google: downloadsGoogle,
      p_downloads_appstore: downloadsAppstore,
      p_notes: notes,
    }),
  deleteMarketingDay: (day) => rpc('admin_delete_marketing_day', { p_day: day }),

  // Propozycje pytań od użytkowników ("Zaproponuj pytanie" w aplikacji).
  // Skrzynka wejściowa — przyjęcie propozycji niczego nie publikuje; przyjęty
  // pomysł przepisuje się na pytanie zwykłym flow (+ Nowe pytanie).
  listSuggestions: (status = null) =>
    rpc('admin_list_question_suggestions', { p_status: status }),
  // note: null = zostaw notatkę; '' = wyczyść; tekst = nadpisz.
  setSuggestionStatus: (id, status, note = null) =>
    rpc('admin_set_question_suggestion_status', { p_id: id, p_status: status, p_note: note }),
  deleteSuggestion: (id) => rpc('admin_delete_question_suggestion', { p_id: id }),
};

/**
 * Soft length hints, not DB constraints — the schema has none. Taken from the
 * live catalog (543 questions): the longest PL question is 109 chars, the
 * longest smaczek 73. Past these the text starts wrapping badly on a phone,
 * so the counter warns rather than blocks.
 */
export const LIMITS = { question: 110, smaczek: 75 };

/**
 * Which answer a smaczek attacks (`question_smaczki.side`). No value = untagged,
 * which the server serves as if neutral — so the tag never blocks anything, it
 * only decides whether the argument lands on the person who actually gave that
 * answer. The app shows the matching one first, and for a free user that is the
 * one it unlocks.
 */
export const SIDES = [
  { value: 'attacks_yes', label: '⚔ przeciw TAK', hint: 'dostanie go ktoś, kto zagłosował TAK' },
  { value: 'attacks_no', label: '⚔ przeciw NIE', hint: 'dostanie go ktoś, kto zagłosował NIE' },
  { value: 'neutral', label: '◇ neutralny', hint: 'osobisty/praktyczny — działa w obie strony' },
];

// `Intimacy` (2026-09-02) is the "Seks i intymność" mode: PRO-only in the app
// and never the daily — keep it out of daily_picks (the DB refuses it once the
// exclusion migration lands, until then the calendar tab is on its own).
export const CATEGORIES = [
  'Connection', 'Culture', 'Dreams', 'Environment', 'Ethics', 'Family',
  'Freedom', 'Friendship', 'Health', 'Intimacy', 'Justice', 'Lifestyle',
  'Money', 'Reflection', 'Relationships', 'Society', 'Technology', 'Work',
];
