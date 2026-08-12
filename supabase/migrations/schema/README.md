# schema/ — files that define the database

Tables, RPCs, views, RLS policies, grants, indexes. Anything containing DDL
belongs here, even when it also seeds rows.

Looking for the *current* shape of the database? Read
[`../../schema.sql`](../../schema.sql) (8 KB, current) instead of reading these
41 files. Come here only for the history of how something got that way.

Read [`../README.md`](../README.md) before applying anything — these are
reference copies, and `supabase db push` must never be used.
