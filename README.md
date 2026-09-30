# offline-app-core

A shared Defold library for small, fully offline Android apps. It holds only
generic code: no texts, no art. The apps that use it are the owner's three
series, *Games of Dharma*, *Paths of Dharma* and *Anatomy of Illusion*, and
they bring their own content.

## Use it in an app

In the app's `game.project`, add the library and the official Defold
extensions it talks to:

```ini
[project]
dependencies#0 = https://github.com/apolloninen-source/offline-app-core/archive/<commit>.zip
dependencies#1 = https://github.com/defold/extension-admob/archive/refs/tags/4.2.2.zip
dependencies#2 = https://github.com/defold/extension-iap/archive/refs/tags/8.4.1.zip
dependencies#3 = https://github.com/britzl/defold-sharing/archive/refs/tags/4.7.0.zip   # for "Export notes"

[admob]
app_id_android = ca-app-pub-3940256099942544~3347511713   # Google's test app ID; the app's own at release
test_ads_in_debug = 1

[iap]
auto_finish_transactions = 0
```

AdMob 4.2.2 is the newest release that works with Defold 1.13 (4.3.0 needs
1.14, not yet released). These are native extensions: bundling needs
Defold's build server, which bob.jar and the editor use by default.
Measured with all three (Yaksha's Riddles, release): a 26 MB APK for arm64
and armv7, an 18 MB Play bundle; players download only their phone's part.

Pin the core to an exact commit (or a release tag, once tags exist), never
a branch, so an app always builds the same. GitHub serves a zip for any
commit at `archive/<full commit hash>.zip`. Then, in Lua:
`local rng = require "core.rng"` and so on.

`auto_finish_transactions = 0` matters: "Remove ads" must be acknowledged,
not finished, or Google Play treats it as consumed (see `core/purchase.lua`).

## Modules

| Module | What it does |
|---|---|
| `core.reader` | Reads a long text split into parts and sections (the Mahabharata's Parvas, the Ramayana's books), with footnotes, one part in memory at a time |
| `core.rng` | Deterministic random numbers (FNV-1a and mulberry32): the same daily challenge on every phone. Never use `math.random` for anything players compare. |
| `core.day` | Calendar days as numbers (day 0 = 1970-01-01), in the player's local date, like Wordle; challenge numbers from the app's launch day |
| `core.save` | The player's saved state, on the phone only, with defaults filled in for new fields |
| `core.streak` | Daily streaks: current, best, days played |
| `core.share` | Result text and a WhatsApp link (`wa.me`), with no extension needed |
| `core.ads` | The shared ad rules and the AdMob link: at most one App open ad and one interstitial a day, a banner only under the text in the reader (in its own space, never over the text), nothing after "Remove ads", ad content rated PG at most, never personalized. An app can switch any of them off. |
| `/consent` | Native extension: Google's consent form (UMP) for Android, as the Lua module `consent` (see "EU consent") |
| `core.purchase` | The one-time "Remove ads" purchase through Google Play Billing |
| `core/reader_ui/` | The reader screen: contents, a part's sections (with a jump list of its sub-parts), and the text. Drag to scroll; footnotes as superscripts, tap a paragraph to read its notes; the Android back key goes up a level and returns to the place in the list. It remembers where the player stopped ("Continue" on the contents) and keeps **bookmarks with notes**, which can be exported as a .txt file. Long sections are cut at sentence ends and only what is on screen is drawn. Add `/core/reader_ui/reader.collection` to a collection to use it. |
| `core.bookmarks` | The reading position and bookmarks with notes, as pure functions on the reader's save |
| `core.notes_export` | "Export notes": the player's notes as one .txt file, written in the app's folder and handed to the phone's share sheet (Files, Drive, email) through the Sharing extension, since Android apps cannot write into Downloads directly |
| `core.ui.page` | The first piece of the UI kit: a scrolling page of text blocks, buttons and bands inside a gui_script, with drag, tap and culling. Each app brings its own colours and art. |
| `core.ui.note_editor` | A full-screen editor for a short note (a riddle reading, a bookmark's note), above where the keyboard opens, with Done and Cancel |
| `core.ui.text_input` | A text field's contents and editing, for notes the player writes (an own reading of a riddle, a reflection after practice): typed text, words the keyboard is still composing, backspace and Enter, lengths in characters. Open the phone's keyboard with `gui.show_keyboard`. |
| `core/fonts/` | Gentium Plus (SIL Open Font License, see `GentiumPlus-OFL.txt`), as `body.font` and `title.font`, with the accented letters the translations use |

Without the AdMob and IAP extensions (desktop builds, tests), the ad and
purchase calls do nothing, but the rules still run.

## Reader screen settings

In the app's `game.project`:

```ini
[reader]
book_dir = /shared/reader/data/   # where the book's JSON is (bundled with custom_resources)
open = 3,281                      # optional: open a part (and section) at start
background = #F3E9D2              # optional colours, hex
ink = #2B1D12
accent = #8B2E16
muted = #7A6A58
field = #E7D9BA                   # optional: the note editor's box
save_id = yaksha                  # the app's save folder, for the position and bookmarks
start_hidden = 1                  # inside a game: open it with a message (below)
```

### Inside a game

Add `reader.collection` to the game's collection (as a collection instance
with the id `reader`), set `start_hidden = 1` under `[reader]`, and open it
with a message:

```lua
msg.post("/reader/reader#gui", "open", { part = 3, section = 311 })  -- or no part: the contents
```

The sender becomes the owner: the contents get a "‹ Back" link, and going
back from the contents (or the Android back key there) hides the reader and
sends `reader_closed` to the owner, which shows its own screen again.

## Tests

The tests run inside the real Defold engine. With Defold's `bob.jar`
(1.13.0, Java 25+) and a desktop `dmengine`:

```sh
java -jar bob.jar --root . --variant debug resolve build
cd build/default && dmengine --config=core.selftest=1 ./game.projectc
# -> core tests: 88 passed, 0 failed   (exit code = number of failures)
```

`tools/rng_reference.py` is the reference for the random generator; the
tests compare against its values.

## Still to build

In this order, as production continues:

1. The reader screen: done (`core/reader_ui/`), with the reading position,
   bookmarks with notes and export. Next: a larger text size option.
2. A UI kit: started with `core.ui.page` and `core.ui.text_input`. Next:
   frames and screen transitions. Each series supplies its own look
   (Mughal miniature, ink and gold, optical line art).
3. Fonts: done (Gentium Plus). Each series may add a display font of its own.
   Letters outside the font (emoji, Devanagari) typed into a text field are
   kept and shared, but not drawn.
4. Sound generated in code: bells, tones, wind.
5. Google Play Games leaderboards (for the Games of Dharma series only).

## Ads are never personalized

A rule for every app: no ad profile follows the player, and player data is
never traded. `core.ads` turns on Google's restricted data processing
before AdMob starts, so Google serves non-personalized ads. No other ad
networks or analytics are ever added. `core/android/AndroidManifest.xml`
removes the advertising ID and Android's ad tracking permissions (Topics,
Attribution); every app uses it (`[android] manifest =
/core/android/AndroidManifest.xml`).

The app's own ad units go in its game.project and are used in release
builds only; debug builds always show Google's test ads:

```ini
[admob]
app_id_android = ca-app-pub-…~…

[ads]
app_open_unit = ca-app-pub-…/…
interstitial_unit = ca-app-pub-…/…
banner_unit = ca-app-pub-…/…      # the reader's banner
```

The reader keeps a band at the bottom exactly as high as the banner, so the
text scrolls above it and is never covered. To check the layout on a
desktop build, `[reader] test_banner_px = 150` pretends a banner shows.

## EU consent

For ads in the EEA, the UK and Switzerland, Google requires a certified
consent form before any ad is requested. Neither AdMob extension release
includes one, so this library has its own native extension, `/consent`,
around Google's User Messaging Platform (the form Google certifies and
offers free in AdMob). `core.ads` shows the form where the law asks for it
and starts AdMob only once ads are allowed; elsewhere nothing is shown.

- Write the form in AdMob: Privacy & messaging → GDPR (one per AdMob
  account; it names the apps it covers).
- The app shows a "Privacy choices" link where
  `ads.privacy_options_required()` is true, calling
  `ads.show_privacy_options()`.
- To see the form outside the EU while testing:
  `ads.init(save, { consent_debug = { debug_eea = true, test_device = "<id from the log>" } })`;
  `consent.reset()` forgets the answer.

Verified: the extension compiles on Defold's build server and the APK
carries Google's consent SDK and the bridge. Not yet seen on a phone.

## Licence

No licence has been chosen yet. The repository is public so that apps can
fetch it as a Defold dependency.
