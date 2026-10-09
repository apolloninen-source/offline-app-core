# Starting a new app

Every app of the three series is fitted onto this library, not rewritten.
What the library brings, ready: the reader (contents, sub-part jumps,
footnotes, resume, highlights, bookmarks and notes, the Marks page, export),
the note editor, backup and restore, sharing to WhatsApp, the daily seed and
streaks, ads (App open, interstitial, the reader's banner; never
personalized; EU consent first), "Remove ads", and the Android manifest
without tracking permissions.

What each app brings: its game screen, its book's data, its colours and art,
its icon and its AdMob IDs.

1. **Settings.** Copy `game.project.example` into the app's settings and
   fill in the `<...>` parts. Pin the library to a commit.
2. **Collection.** Copy `main.collection.example`: the reader, and the app's
   own GUI. The app opens the reader with
   `msg.post("/reader/reader#gui", "open", { part = p, section = s })` and
   gets `reader_closed` back.
3. **Start-up, in the app's GUI script:**
   ```lua
   local save = require("core.save").open("<app>", { ... })
   require("core.ads").init(save, { interstitial = false, on_consent = refresh_privacy_link })
   require("core.purchase").init(save, "remove_ads")
   ```
   Show "Privacy choices" where `ads.privacy_options_required()`, and a
   "Backup & restore" page with `core.backup` (files `{ "save", "reader" }`).
4. **Icon.** An adaptive icon (Android 8+) through `bundle_resources`:
   `bundle/android/res/drawable-anydpi-v26/icon.xml` naming two 432 x 432
   layers in `drawable-nodpi/` (`icon_background.png`, `icon_foreground.png`;
   keep the important part in the middle 61 %), plus the old-style
   `icons/icon_36..192.png` and a 512 px icon for the Play Store.
   games-of-dharma's `tools/yaksha_icon.py` shows the whole pipeline.
5. **AdMob.** A new app in AdMob, its App open unit (and banner / interstitial
   if used), each capped at one a day where it applies; the app in the GDPR
   message with Google as the only ad partner.
6. **Rules that never change:** no data trade, data to Google only, ads
   never personalized, no banner or anything else over the text.
