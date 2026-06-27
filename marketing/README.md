# Marketing assets

## `screenshots/` — final store art

The canonical, in-repo home for the PNGs uploaded to the Play Store / App Store
listings. These are hand-picked final captures (real device frames), so the set
is small and committed directly.

Naming is `<scene>_<locale>.png` (e.g. `landing_pl_pytanie_dnia.png`) or the
older `<scene>_fullhd.png` exports. The Polish (`*_pl.png`) set reflects the
current UI; the older `*_fullhd.png` English set predates some UI changes
(category filter removed, History button added) — recapture before reusing.

## Relationship to the generator

`tool/export_store_screenshots.dart` renders branded **share-card posters**
(the same `QuestionShareCard` the in-app share button produces) from the
question lists in `tool/store_screenshots/`. Its output goes to
`build/store_screenshots/<locale>/` — git-ignored and ephemeral. When you want
to keep a generated poster as listing art, copy the chosen PNG into this folder.

See [`tool/README.md`](../tool/README.md) for how to run the generator.
