# Store-screenshot exporter

Renders branded question posters (the **same** `QuestionShareCard` the in-app
share button shares) to PNGs you can upload to the Play Store / App Store. One
asset, two jobs — the share image doubles as store-screenshot source art.

## Use it

```bash
flutter test tool/export_store_screenshots.dart
```

Output → `build/store_screenshots/<locale>/01.png, 02.png, …` at **1080×1920**.
The output folder for each locale is wiped and rewritten on every run.

`build/` is ephemeral and git-ignored. To keep a generated poster as listing
art, copy the chosen PNG into [`marketing/screenshots/`](../marketing/screenshots)
— the canonical, committed home for final store art (see
[`marketing/README.md`](../marketing/README.md)).

## Change the questions

Edit, one question per line (blank lines and `#` comments are ignored):

- `tool/store_screenshots/questions.pl.txt` — Polish screenshots
- `tool/store_screenshots/questions.en.txt` — English screenshots

The line's order is the file number (`01.png`, `02.png`, …). A missing
per-locale file falls back to `questions.txt` if you add one.

## Options (optional OS env vars)

| Var                      | Default                  | Notes                                   |
| ------------------------ | ------------------------ | --------------------------------------- |
| `SCREENSHOT_LOCALES`     | `pl,en`                  | comma list; must have a questions file  |
| `SCREENSHOT_OUT_DIR`     | `build/store_screenshots`| output root                             |
| `SCREENSHOT_PIXEL_RATIO` | `3`                      | 3 ⇒ 360×640 logical ⇒ 1080×1920 px      |

PowerShell example (only Polish, bigger 4× export):

```powershell
$env:SCREENSHOT_LOCALES='pl'; $env:SCREENSHOT_PIXEL_RATIO='4'; flutter test tool/export_store_screenshots.dart
```

## Notes

- 1080×1920 (9:16) is accepted as-is by Google Play. For the App Store's exact
  device sizes (e.g. 1290×2796), pad/scale these in the console — the art is the
  source, the final crop is manual.
- The poster's look lives in
  [`lib/features/questions/widgets/share_question_card.dart`](../lib/features/questions/widgets/share_question_card.dart);
  the off-screen renderer is
  [`lib/core/share/widget_to_image.dart`](../lib/core/share/widget_to_image.dart).
- `build/` is git-ignored, so exported PNGs aren't committed.
