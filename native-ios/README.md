# Push Language Native

A separate SwiftUI iOS app being migrated from the Flutter app. Requires iOS
15 or newer and Xcode with an iOS SDK. No Flutter runtime is used. FirebaseCore
and FirebaseAuth are resolved through Swift Package Manager (Firebase 11.15.0).

## Run

1. Open `PushLanguage.xcodeproj` in Xcode.
2. Select the **PushLanguage** scheme and an iPhone or iPad simulator.
3. Run with **Product > Run**.

For a physical device, select your development team in the app target's
**Signing & Capabilities** settings and choose a unique bundle identifier.
The native app deliberately uses a different bundle identifier from Flutter,
so it does not replace the existing app or share its sandbox.

## Current scope

Step 1 provides a native app entry point and four navigable tabs matching the
Flutter shell's order and labels: World, List word to push, Search, and Setting.
Step 2 implements offline dictionary search and full word details, including
IPA, part-of-speech headings, meanings, and examples. Search waits 280 ms after
typing, requires at least two characters, and returns at most 50 entries:
exact matches first, prefixes next, then substrings for queries of at least
three characters. Duplicate headwords retain their original file order.
Cancelled searches cannot overwrite newer results. Loading failures are shown
explicitly with a Retry action.

The original `../assets/data/EV/anhviet109K.dict` is referenced directly by the
Xcode project's resource phase, not duplicated in source control. A byte-offset
index is built in memory on a background actor and definitions are decoded only
when opened. The legacy `.index` and `.ini` files are unnecessary here: Flutter's
active search also derives its numeric offsets from the `.dict` file.

Native parsing handles UTF-8 BOMs and retains unsectioned definition content,
which Flutter's detail grouping can omit. All dictionary attribution and license
metadata remain in the original bundled file; review its GPL notice and applicable
distribution obligations before publishing.

The remaining tabs explicitly identify features that are not implemented yet.
No fake sign-in or simulated saves are provided.

Step 3 adds Apple text-to-speech (English US) to word details with normal, slow,
and stop controls. Playback stops when leaving details, when the app becomes
inactive, or when an audio interruption begins. The audio session uses playback
mode, ducks other audio, and restores other audio on completion or stop.
Unavailable voices and audio-session failures are displayed on screen; tap
Pronounce or Slow again to retry. No microphone permission is required.

This is an intentional staged difference from Flutter: there are no online
pronunciation requests, recording downloads, prefetching, or audio caches yet.
Speech uses installed system voices; voice availability may vary by device.
The slow rate is relative to Apple's default rate rather than Flutter's rate
scale. Check normal/slow output and silent-switch behavior on a physical device.

Step 4 adds SQLite saved-word persistence, World search, create/edit forms,
confirmed deletion and clear-all, and saved-word details with pronunciation.
Search combines saved words first (including empty and single-character queries)
with dictionary results for queries of at least two characters. Saved-word
ranking, SQL LIKE wildcard behavior, and pushed-word filtering match Flutter.

Dictionary meanings can be saved individually to World. Re-saving the same
case-insensitive headword and exact trimmed meaning reports that it already
exists rather than duplicating it. Manual additions still allow duplicates,
matching Flutter. Each dictionary meaning retains its own section's part of
speech instead of the final section's label.

The native database lives at `Application Support/PushLanguage/push_language.db`
inside the native app's sandbox. Native schema version 6 extends the version-5
`contacts` layout with `practiceScore`, `correctAnswers`, and `incorrectAnswers`.
Existing version-5 native databases migrate transactionally with all words,
membership, IDs, dictionary data, and audio records preserved. Existing words
start with 0 points and 0 answer counts. `dictionary` and `cached_audio` remain
unchanged. The app seeds the same nine starter
words only on first initialization. Clearing words does not reseed them or remove
the other tables. Editing preserves membership and learning progress. SQL values use bound parameters.
Database failures are reported, never recovered by deleting user data.
Unsupported versions and unversioned nonempty databases are rejected without
modification; older Flutter schema migration/import is not implemented yet.
The native app cannot read existing Flutter data from its separate sandbox.

World now has To Learn and Mastered segmented tabs; its search applies to the
selected tab. Each row shows its practice score out of 5. Saved-word details show
score, lifetime correct/incorrect answer counts, and Mark as Mastered beside the
push-list button. Mark as Mastered sets the score to 5, moves the saved item to
Mastered, and atomically removes its push membership. It does not fabricate correct
answer counts. Learn Again returns it to To Learn at 0 points, retaining lifetime
answer counts; it must be explicitly added to reminders again. Mastered words
cannot be pushed until relearned. Add Word opens new items in To Learn.
Remove All Words explicitly clears both tabs and all progress, not just search
results or the current tab. Ordinary deletion removes only the selected item.
Saved-word Search continues to include both learning states, with mastered state
available in details. Re-saving an existing dictionary meaning preserves progress.

Step 5 adds a persistent push list without a word-count limit, membership
controls in saved-word details, and confirmed removal that leaves the saved word
in World. Open a saved word from World or Search to add/remove membership.
Pushed words remain in World but are excluded from saved-word Search results,
matching Flutter. Dictionary meanings are saved to World first, then selected
for push from saved-word details.
World rows show a blue bell with an accessible "In Push List" label for selected words, with
accessible membership values that update after changes and persist on relaunch.

The push tab offers notification permission, an iOS Settings link when denied,
interval selection (1, 5, 10, 20, 30, 60, 120 minutes; default 10), and Refresh
Reminders. Native interval preferences persist across launches, unlike Flutter's
in-memory settings. Permission is requested only after tapping Enable
Notifications, not on launch or when adding a word.

Beside the interval controls, both the push tab and Settings offer Words per
reminder with choices 1, 2, 3, 4, 5 (default 5). This shared preference persists
across launches. Each notification independently samples up to that many distinct
saved-word IDs from the full push list, without repeating an ID inside that
notification. Words may recur in later notifications; this is not a round-robin
cycle. If the list is shorter than the chosen count, every available word is used.
Different saved meanings of the same headword remain distinct saved words.

Reminder hours is shared between the push tab and Settings. The default is an
enabled 07:00-20:00 window using the device's local time, including on upgrades
without a saved window. Open its editor to choose start/end hours and minutes;
Save persists the entire setting and rebuilds pending reminders. Back discards
unsaved edits. Turn off Limit reminder hours for all-day reminders (the chosen
times are retained). Equal start/end times are rejected; use the switch for a
full day. A start later than the end defines an overnight window, such as
20:00-07:00.
The push tab uses a single scrolling list for its controls and words so the extra
settings do not squeeze the word list on small screens or with larger text.
Its Reminder settings group starts collapsed on each launch. Tap the summary
row/chevron to expand or collapse interval, words per reminder, reminder hours,
Refresh Reminders, and scheduling explanations. The compact summary always shows
the current interval, word count, and allowed hours (or All day); status and errors
remain visible while collapsed. The word section displays its total count.
Expanding/collapsing only changes presentation, never notification scheduling or
saved preferences. The Setting tab retains its full controls.

The start is inclusive and the end exclusive: 07:00-20:00 allows 07:00 through
19:59, not 20:00. The first candidate is now plus the selected interval. If a
candidate falls outside the window, it moves to the next opening, with subsequent
candidates spaced from that opening, so missed reminders never pile up together.
All 50 notifications remain inside the window, even when spread across multiple
days. For example, at 19:55 with a 10-minute interval, the next reminder is at
07:00 the following day, then 07:10. Empty push lists still schedule nothing.
Random word selection and the five words-per-notification choices are unchanged.

A non-blocking reminder appears above every tab when notification permission has
not been requested or has been denied, even with an empty push list. Tap Enable
Notifications to request permission, or Open iOS Settings after denial to turn on
Allow Notifications. The reminder is translated into English/Vietnamese and
disappears when permission is allowed. Returning from Settings rechecks permission
and rebuilds reminders. Failure to open Settings is reported with manual instructions.

With permission, exactly 50 one-shot local notifications are queued at multiples
of the chosen interval. Each is titled "Words to push" and includes its own random
selection of words, parts of speech, and meanings. All 50 random selections are
prepared when scheduling; delivery does not require the app to be running.
They are rebuilt on app activation, significant clock/time-zone changes while
running, word mutations, or interval/word-count/window changes.
These are finite reminders, not an indefinite
background timer. iOS ultimately controls delivery, including Focus and
notification settings; banners and sound are also enabled while foregrounded.
Requests use nonrepeating calendar triggers with local date/time components,
not elapsed-time timers, to retain local wall-clock hours across time-zone changes.
The scheduler accounts for daylight-saving transitions; a wholly nonexistent
window is skipped that day. Reopen the app after changing the device clock/time
zone to rebuild the finite schedule. iOS can delay/suppress actual presentation
(for example, Focus or notification summaries); the window controls requested
delivery times, not the operating system's eventual presentation.

Rebuilds run serially, cancel stale owned requests before reading current data,
and verify that all 50 are retained. Partial failures remove partial schedules
and report an error with retry; saved membership remains intact. Only identifiers
prefixed `push-language-reminder-` are managed; unrelated notifications remain
untouched. Scheduling checks available capacity against iOS's 64 pending-request
limit. No push server, remote-notification entitlement, or background mode is
required. Home-screen widgets and notification-tap deep links remain
for later migration steps.

Step 6 adds Practice from the push tab. Starting reads a fresh snapshot of selected
words, and reports an error if none are selected. Each word receives a shuffled
typing/flashcard pair, with no five-word session limit. The per-notification word
count does not limit practice; it uses the full push-list snapshot. Each word's
answers compare trimmed lowercase strings. One correct
answer completes that saved-word identity and skips its remaining turns; incorrect
answers leave later turns available. The session is finite and can finish with
unanswered words. Each checked typing or flashcard answer is persisted before
showing feedback: correct adds 1 point and increments the correct count; incorrect
subtracts 1 down to a floor of 0 and increments the incorrect count. Points and
counts belong to each saved ID (different meanings/duplicate headwords remain
independent), persist across sessions/relaunches, and are not limited to a single
practice session. At 5 points, the word automatically moves to Mastered and is
removed from the push list in the same database transaction; pending reminders
are rebuilt without it. Manual mastery uses this same threshold.

Practice still skips a word's later turn after its first correct answer in that
session, so answering a word correctly awards at most one point per session.
Incorrect attempts in both modes each count independently. Duplicate taps while
saving or after feedback cannot double-score. A failed save leaves the answer
unchecked, with an explicit error and retry; failed writes never change progress.
Other stale sessions cannot score an already-mastered/deleted word. Backing out
keeps answers already recorded and does not award unchecked answers.

Flashcards use four choices from selected headwords and fill small pools with the
correct word, preserving Flutter's layout and behavior. Typing uses a visible,
accessible text field rather than Flutter's hidden field/dashed cells. Input removes
newlines, collapses whitespace, and is limited to the target's Swift character
count; Unicode graphemes are not split. Correct/incorrect feedback uses the original
`../assets/audio/correct.mp3` and `incorrect.mp3` resources. Audio errors are shown
without discarding the answer; audio stops on navigation, inactivity, or interruption.
Listening exercises remain deferred until recording caching is migrated, as agreed.

The Flutter source, existing iOS host, data, and configuration remain unchanged.
Flutter's Firebase configuration is intentionally not copied to the native app.

Step 7 replaces the Setting placeholder with account/audio migration status,
Language, Time to push, and a selectable Database Location screen. The interval
control shares the push tab's persisted setting and scheduling service.
Database Location reports the actual native path without opening or seeding the
database just to display it.

Language now switches the implemented interface between English and Vietnamese,
including tabs, forms, search prompts, practice, confirmations, reminder titles,
and app-defined errors. This intentionally goes beyond Flutter's preference-only
selector. The choice defaults to English and persists under `appLanguage`.
SwiftUI uses the selected locale and dynamic service messages use that language's
bundle. English source keys are the standard fallback; Vietnamese translations
are bundled in `vi.lproj/Localizable.strings`. User headwords, definitions,
saved meanings, IPA, database paths, and pronunciation remain unchanged.
System permission dialogs and underlying system/SQLite diagnostics may retain
the device's language. Changing language rebuilds pending reminders with the
localized title. Invalid saved language values are surfaced and repairable by
choosing a valid language. No fake account or audio-cache operations are provided.

## Next migration steps

1. Complete native Firebase registration and verify real email/password sign-in;
   then migrate Google and Apple sign-in.
2. Define an explicit export/import flow if transferring existing Flutter data
   is required; the separate sandbox is not an automatic data migration.
3. Add recording playback and caching when migrating cached-audio management.
4. Port settings, cached audio, authentication, and widget integration where
   applicable, then verify feature parity.

## Tests

Use **Product > Test** in Xcode to run tab tests, parser/search tests, real
bundled-dictionary tests, and navigation/search/detail UI tests. The Swift
pronunciation tests cover normal/slow rates, errors and retry, interruption,
stale callbacks, audio cleanup, and real Apple speech completion. UI tests cover
pronunciation controls and completion. Simulator completion is not a substitute for
listening on a physical device.

Saved-word tests cover schema compatibility, starter words, disk persistence,
CRUD, invalid input, duplicate handling, concurrent saves, ranking and pushed
flags, non-destructive errors, and clear-all. UI tests exercise forms, relaunch
persistence, confirmations, and dictionary-to-World saving. Debug UI tests use a
UUID-scoped temporary database via `PUSH_LANGUAGE_TEST_DATABASE_ID`, so they
do not modify the regular app database. They also use isolated interval
preferences and a denied-permission notification test double, so they do not
prompt for permissions or alter the app's real pending notifications. These
overrides are absent in Release.

Reminder unit tests cover all interval/word-count choices, exactly 50 delays,
independent seeded random batches, unique IDs per notification, short/empty lists,
body formatting, unlimited membership, concurrency, permission states, scheduling
cleanup, retained-request verification, edits/deletes, retries, and preference
persistence. UI tests cover adding more than five words, World membership labels,
shared word-count settings, confirmed removal,
relaunch persistence, denied permissions, and clear-all propagation. Real
notification delivery must be checked manually: enable notifications, choose
1 min, select a word, background the app, and wait for the first reminder.
Permission-reminder tests also cover empty selections, denied/undetermined/allowed
states, permission changes, English/Vietnamese messages, tab navigation, and
reminder dismissal after enabling permission. UI tests use a debug-only notification
center; verify the system permission dialog and Settings return on a real device.
Daily-window tests cover defaults, persistence and corrupt-preference repair,
start/end boundaries, minute precision, overnight windows, short windows spanning
multiple days, year/leap-day boundaries, daylight-saving transitions, all-day
mode, calendar-trigger components, and rescheduling without changing saved words
or unrelated notifications. UI tests edit hours/minutes, discard edits, share
settings across tabs, relaunch, toggle all-day mode, and check Vietnamese labels.
On a device, set a short window near the current time, select the one-minute
interval, background the app, and check that no requests are delivered outside
that window under normal notification settings.

Practice tests cover shuffled modes, correct-word skipping, finite incorrect
progression, duplicate headwords with distinct meanings, four-option padding,
input normalization, Unicode, answer locking, invalid sessions, and feedback
resource decoding/playback. UI tests exercise empty selection, answering a
single-word session, finish/restart, and back navigation. Listen to feedback sounds
on a physical device to confirm audible quality.
Mastery tests cover non-destructive v5-to-v6 migration/rollback, independent IDs,
score floor and exact 5-point promotion, persistent counters, concurrent database
connections, manual mastery/relearning, edit/dictionary dedup preservation, write
failure and retry, duplicate submissions, revision updates, and removal from all
owned reminders without affecting unrelated requests. UI tests move words between
tabs, check relaunch and Vietnamese labels, exercise five correct sessions to
automatic mastery, and verify incorrect-answer counts.

Settings tests cover default/invalid preferences, language persistence,
Vietnamese formatting and placeholder parity, and database path behavior. UI
tests cover switching languages without restarting, switching back, relaunch
persistence, the shared interval control, actual database location, translated
validation/practice errors, and preserved saved-word content.

## Email/password authentication (step 8)

Firebase email/password sign-in, account creation, auth-state observation,
account email/display name/UID, and confirmed sign-out are wired into Settings.
Google and Apple providers remain deferred. Credentials are passed directly to
the Firebase SDK; passwords are not persisted by app code or logged. Firebase
manages session persistence. Account creation does not automatically set a
display name; an absent name is explicitly shown.

Authentication is optional during this separate-app migration: local dictionary,
saved words, practice, and reminders remain available without signing in.
Saved words are not uploaded, partitioned by account, or deleted on sign-out.
This differs from Flutter's configured-app auth gate and avoids implying account
data isolation that neither app currently implements.

### Required native Firebase registration

1. Use the Firebase Apple/iOS app registered with bundle identifier
   `com.example.pushLanguage`. The native target now uses this identifier to match
   the supplied registration. If you customize the target identifier, register
   that exact identifier instead.
2. Download that app's `GoogleService-Info.plist`. Do not modify the Flutter file's
   BUNDLE_ID to imitate a registration: it is a different Firebase app.
3. Place the file at `PushLanguage/Configuration/GoogleService-Info.plist` inside
   this directory. It is gitignored so app-specific configuration is not committed.
4. Run `ruby native-ios/generate_project.rb` to add the configuration to the
   native app's resource phase, then reopen Xcode. Regeneration overwrites manual
   project settings; preserve customizations in the generator.
5. Enable **Email/Password** in Firebase Console > Authentication > Sign-in method.
6. Run, open Settings > Sign In, and test Sign Up, relaunch session restoration,
   Sign Out, Sign In, incorrect credentials, and offline errors.

Without configuration, or with a missing-field/bundle mismatch, Settings shows an
explicit setup-required message. Firebase is not initialized using Flutter's file.
Live authentication cannot be verified until a matching registration is supplied.
No real accounts are created by automated tests.

Changing from the earlier native bundle identifier installs a different app with
its own sandbox; saved words and preferences from that earlier app do not transfer
automatically. An installed app using `com.example.pushLanguage` can be replaced
when running this target. The Flutter project itself remains unchanged.

Auth tests cover validation, registration mismatch/missing fields, account-state
updates, sign-up/sign-in/sign-out, errors and retry, concurrency, and localization
using a unit-test client. UI tests verify the setup-required state and continued
local access; debug isolated UI tests never initialize a real Firebase backend.

The Swift dictionary tests share reference rankings and byte offsets with
`../test/dictionary_search_parity_test.dart`, which exercises the actual Flutter
search service. Run that reference test with:

```sh
flutter test test/dictionary_search_parity_test.dart
```

To run native tests from the command line, first find a simulator:

```sh
xcodebuild -showdestinations -project native-ios/PushLanguage.xcodeproj -scheme PushLanguage
```

Then, from the repository root, substitute its ID:

```sh
xcodebuild test \
  -project native-ios/PushLanguage.xcodeproj \
  -scheme PushLanguage \
  -destination 'platform=iOS Simulator,id=SIMULATOR_ID' \
  -derivedDataPath native-ios/DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

The committed Xcode project opens directly without a generator. If target or
source-file membership changes, update `generate_project.rb` as needed and run
`ruby native-ios/generate_project.rb` using Ruby with the `xcodeproj` gem
installed. Regeneration replaces project settings; put lasting customizations
in the generator too.
