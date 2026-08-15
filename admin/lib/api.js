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

function decorate(error) {
  const msg = error.message || '';
  const e = new Error(msg);
  e.raw = error;
  e.isConflict = msg.includes('CONFLICT');
  e.isForbidden = msg.includes('FORBIDDEN');
  e.friendly = msg.includes('CONFLICT')
    ? 'Ktoś zmienił to pytanie, odkąd zacząłeś edycję. Odśwież, żeby zobaczyć aktualną wersję — Twoje zmiany nie zostały nadpisane.'
    : msg.includes('FORBIDDEN')
      ? 'Brak uprawnień do tej operacji.'
      : msg.includes('LOCKED')
        ? 'Ta wersja robocza czeka już na zatwierdzenie i nie można jej edytować.'
        : msg;
  return e;
}

export const api = {
  me: () => rpc('admin_me'),
  claimInvite: () => rpc('admin_claim_invite'),

  // Cały dashboard /stats jednym strzałem; p_days = null → od początku.
  // Konta wewnętrzne (nasze maile) są domyślnie wycięte z każdej liczby.
  dashboardStats: (days = null, includeInternal = false) =>
    rpc('admin_dashboard_stats', { p_days: days, p_include_internal: includeInternal }),

  listQuestions: ({ search = null, onlyActive = true, onlyEnReview = false, onlyFavorites = false, limit = 50, offset = 0 } = {}) =>
    rpc('admin_list_questions', {
      p_search: search,
      p_only_active: onlyActive,
      p_only_en_review: onlyEnReview,
      p_only_favorites: onlyFavorites,
      p_limit: limit,
      p_offset: offset,
    }),

  // Gwiazdka "ulubione" — per admin, bez draftu. Zwraca nowy stan (true = on).
  toggleFavorite: (questionId) =>
    rpc('admin_toggle_favorite', { p_question_id: questionId }),

  getQuestion: (id) => rpc('admin_get_question', { p_id: id }),

  // true = "EN do weryfikacji" (każdy admin); false = zweryfikowane (tylko approver)
  setEnReview: (questionId, flag) =>
    rpc('admin_set_en_review', { p_question_id: questionId, p_flag: flag }),

  listDrafts: (status = null) => rpc('admin_list_drafts', { p_status: status }),

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
  rejectDraft: (draftId, note = null) =>
    rpc('admin_reject_draft', { p_draft_id: draftId, p_note: note }),
};

/**
 * Soft length hints, not DB constraints — the schema has none. Taken from the
 * live catalog (543 questions): the longest PL question is 109 chars, the
 * longest smaczek 73. Past these the text starts wrapping badly on a phone,
 * so the counter warns rather than blocks.
 */
export const LIMITS = { question: 110, smaczek: 75 };

export const CATEGORIES = [
  'Connection', 'Culture', 'Dreams', 'Environment', 'Ethics', 'Family',
  'Freedom', 'Friendship', 'Health', 'Justice', 'Lifestyle', 'Money',
  'Reflection', 'Relationships', 'Society', 'Technology', 'Work',
];
