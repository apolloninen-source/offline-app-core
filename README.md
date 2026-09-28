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
dependencies#1 = https://github.com/defold/extension-admob/archive/master.zip
dependencies#2 = https://github.com/defold/extension-iap/archive/master.zip

[iap]
auto_finish_transactions = 0
```

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
| `core.ads` | The shared ad rules and the AdMob link: at most one App open ad and one interstitial a day, never banners, nothing after "Remove ads". An app can switch either ad off. |
| `core.purchase` | The one-time "Remove ads" purchase through Google Play Billing |
| `core/reader_ui/` | The reader screen: contents, a part's sections, and the text. Drag to scroll; footnotes as superscripts, tap a paragraph to read its notes; the Android back key goes up a level. Long sections are cut at sentence ends and only what is on screen is drawn. Add `/core/reader_ui/reader.collection` to a collection to use it. |
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
```

Or send it a message: `msg.post("reader:/reader#gui", "open", { part = 3, section = 281 })`.

## Tests

The tests run inside the real Defold engine. With Defold's `bob.jar`
(1.13.0, Java 25+) and a desktop `dmengine`:

```sh
java -jar bob.jar --root . --variant debug resolve build
cd build/default && dmengine --config=core.selftest=1 ./game.projectc
# -> core tests: 56 passed, 0 failed   (exit code = number of failures)
```

`tools/rng_reference.py` is the reference for the random generator; the
tests compare against its values.

## Still to build

In this order, as production continues:

1. The reader screen: done (`core/reader_ui/`). Next: remember the reading
   position, and a larger text size option.
2. A UI kit: frames, buttons and screens. Each series supplies its own look
   (Mughal miniature, ink and gold, optical line art).
3. Fonts: done (Gentium Plus). Each series may add a display font of its own.
4. Sound generated in code: bells, tones, wind.
5. Google Play Games leaderboards (for the Games of Dharma series only).

## Open item before any release

**EU consent.** For ads to show in the EEA and UK, Google requires a
certified consent tool to run before ads are initialised. The AdMob
extension does not include one. This must be solved before release; India
and most other markets are unaffected. `core/ads.lua` marks the place.

## Licence

No licence has been chosen yet. The repository is public so that apps can
fetch it as a Defold dependency.
