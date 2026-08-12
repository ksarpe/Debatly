# data/ — one-shot content edits

Question seeds, catalog edits and deletes, copy-editing passes, rank-ladder
reseeds. Pure `insert` / `update` / `delete` — **no DDL**. If your new file
creates or alters anything, it goes in [`../schema/`](../schema/) instead.

Most of these are large generated `VALUES` lists. Grep them; don't read them
whole.

Destructive edits have a pre-edit row snapshot of the same name in
[`../../backups/`](../../backups/) — that is what you restore from, by writing
a new migration, never by applying the snapshot directly.

Read [`../README.md`](../README.md) first: these are reference copies of what
already ran on prod, and `supabase db push` must never be used.
