# CLAUDE.md: Squawk

Squawk is in the **Build** stage. Read `PRODUCT.md`, `DESIGN.md` and `BUILD.md` first.

- `PRODUCT.md`, `DESIGN.md` and `BUILD.md` are approved. Build phase by phase, one PR each.
- The mascot lives in the `PenguinKit` local package. Keep it free of Squawk-specific code
  so it can move to `packages/` when a second app needs it.
- Ideas come from the Morning alarm in `lanata/lanata-server` (`apps/ios/Lanata/Screens/Morning/`,
  especially `AlarmKit/MorningAlarmScheduler.swift`). Copy the ideas, not the code: Squawk
  has no server and no account.

## Code

- `ios/Squawk.xcodeproj`: the app (scheme `Squawk`, bundle ID `com.tinypenguin.squawk`,
  iOS 26+). Build settings are in `ios/Config/Squawk.xcconfig`, not the `.pbxproj`.
- `ios/Squawk/`: app screens, `DesignSystem/` (`Theme.swift` colors and type from
  `DESIGN.md`, `Components.swift`, `Motion.swift` with fish confetti, wobble and shake) and
  `Telemetry.swift` (Sentry crash reports and metrics, see `docs/telemetry.md`). App code
  calls `Telemetry`, never Sentry directly. List new metrics in `PRODUCT.md` first.
- `ios/SquawkKit/`: local Swift package with the alarm model (`Alarm`, `Ring`,
  `TimeOfDay`, `Weekday`), one-morning changes (`MorningChange` in `Mornings.swift`:
  skip, new time, or "already up"), `AlarmPlanner` (alarms → the AlarmKit alarms to
  schedule; a weekday whose next morning has a change rings as one-off alarms for a
  few weeks, since AlarmKit can't skip one week of a repeating alarm), the mornings log
  (`MorningsLog.swift`: how each morning went, the streak and this week's dots, saved
  in `mornings.json`),
  `FileAlarmStore` (JSON in Application Support) and the sound list. No UI, no AlarmKit.
- `ios/Squawk/Alarms/`: `AlarmsModel` (the app's alarms; every change saves and
  re-plans; opening the app mid-morning cancels the rest of it) and `AlarmKitScheduler`,
  the only code that talks to AlarmKit. Re-plans run one at a time, and the scheduler
  only cancels or adds the AlarmKit alarms that changed (it remembers what it made in
  UserDefaults). "I'm up" on the ringing screen runs
  `SquawkUpIntent`.
- "Turn off Squawk" (`Alarms/TurnOffSquawkIntent.swift`): the Shortcuts action, also
  the "Run a Shortcut" wake-up check. It runs in the background and calls
  `AlarmsModel.turnOffFromShortcut()`; `Alarm.shortcutTurnOff` decides what it may do.
  It ends a morning with no checks or only Shortcut checks, and only ticks off the
  Shortcut check when there are others. It never skips another check.
- Wake-up checks: `ios/Squawk/Checks/` (`TagReader` reads an NFC sticker's id with
  CoreNFC, `CodeScanner` wraps VisionKit's barcode scanner), `Screens/CheckFlowView.swift`
  (tag, code, penguin game, math way out) and `Screens/ChecksSetup.swift`. An alarm with
  a check is planned as one-off rings 5 mornings ahead, and its last ring repeats
  every 30 s for 10 minutes; doing the check marks the morning done. To stay under
  AlarmKit's per-app limit, only the next 2 minutes of repeats are scheduled, plus a
  backup every 2 minutes; Snooze (`SquawkStopIntent`) re-plans to schedule the next ones. Since the 5 mornings run out
  if nobody opens the app, `RunOutReminder` (`Alarms/RunOutReminder.swift`, the app's only
  local notification) says "Open Squawk to keep your alarms" at 8 PM the evening before the
  last planned morning (`AlarmPlanner.runOutReminder`, which also covers a changed weekday's
  one-off weeks). Every re-plan moves it. Saving a repeating alarm with a check asks for
  notification permission. NFC needs the
  entitlement in `Config/Squawk.entitlements`; CI turns the capability on.
- Squawk Pro: `ProAccess` in `SquawkKit/Pro.swift` is the one place that says what's
  free (2 rings, the 3 quick-add sounds, skip next morning, outfits earned with a
  streak) and what needs Pro; move a feature to free by adding it to `ProFeature.free`.
  Losing Pro never changes an alarm that's already set. `StoreKitProStore` reads the
  subscription; `Squawk/Pro/` has `ProModel`, the Pro screen (Apple's
  `SubscriptionStoreView` with our header), outfits and app icons. Screens gate with
  `ProLinkButton`/`ProBadge` and `.proSheet($paywall)`. Product IDs are in
  `ProProducts`; the launch prices are introductory offers in App Store Connect.
  `Config/Squawk.storekit` lets Xcode test buying without App Store Connect.
- Wake-up steps and Home (`features/steps/FEATURE.md`): a step is the rings and Home
  things at one time, grouped by `Alarm.steps` (not stored). Home things are
  `HomeAction`s in `Alarm.homeActions` (timed) and `Alarm.upActions` ("When you're up").
  `HomePlanner` turns them into Home automations with the same rules as rings.
  `Squawk/Home/`: `HomeAccess` (permission, hub, devices; created lazily since it shows
  the iOS prompt) and `HomeSync`, the only code that writes to HomeKit: action sets plus
  triggers named "Squawk · …", remembered in UserDefaults and re-synced on every
  reschedule. HomeKit refuses changes while the app is in the background ("Request not
  handled", e.g. after "I'm up" or Snooze on the lock screen), so `HomeAccess` holds that
  sync and runs it, with a fresh plan, the next time the app is active. Sunrise lights (`features/sunrise-lights/FEATURE.md`) are a `HomeAction`
  of kind `.sunrise` with a `Sunrise` (length, start/end brightness and warmth); HomeKit
  can't fade, so `Alarm.homeSteps` spreads each one into up to 10 timed light changes and
  `HomePlanner` plans from `homeSteps`, not `steps`. "+" on Home opens the guided setup (`Screens/NewAlarmFlow.swift`, answers
  in `NewAlarmGuide`), with "All options" going to `EditAlarmView`.
- Morning summary (`features/morning-summary/FEATURE.md`, Pro): the Today card on Good
  morning with the weather and the first event of the day. The rules (`Agenda`,
  `WeatherNote`, `SummarySettings`, `withTimeout`) and the `WeatherSource`/`AgendaSource`
  protocols with fakes are in `SquawkKit/MorningSummary.swift`. `Squawk/Summary/` has
  `MorningSummaryModel` (switches, permissions, loading; the weather is dropped after 6 s)
  and the live sources: WeatherKit with approximate "while using" location, and EventKit
  (read only). WeatherKit needs its entitlement and the App Service on the App ID
  (`docs/ios-release.md`). Apple's Weather mark and "Data sources" link must stay on the card.
- `ios/SquawkWidget/`: the next-alarm widget (home screen small and medium, lock screen).
  The app saves a `WidgetSnapshot` (next wake-ups and the streak, in `SquawkKit`) to the
  App Group `group.com.tinypenguin.squawk` whenever alarms or mornings change
  (`Alarms/WidgetBridge.swift`); the widget shows each wake-up until it passes. Its
  settings are in `Config/SquawkWidget.xcconfig`; the version is shared in
  `Config/Version.xcconfig`.
- `ios/Squawk/Sounds/`: the bundled alarm mp3s (from Lanata, cleared for a public app).
  AlarmKit only plays bundled mp3s.
- `ios/PenguinKit/`: local Swift package with the mascot. `PenguinGeometry` holds every
  part as a path on a 200×200 canvas, matching penguin 2 in
  `design/mockups/penguins-front.html`. `PenguinView(mood:style:accessory:waving:)` draws
  and animates it. `PenguinGallery` shows every mood (in the app: long-press anywhere).
  Change the penguin in both places, mockup and package, so they stay the same.

## Build and test

- No Xcode in Claude's container. Push and read the `Squawk iOS` workflow run
  (`.github/workflows/squawk-ios.yml`): it runs `swift test` on `PenguinKit` and `SquawkKit`, then builds
  for the simulator. Pushes to `main` upload to TestFlight.
- Locally: open `ios/Squawk.xcodeproj` in Xcode 27, or
  `swift test --package-path ios/PenguinKit` (and `ios/SquawkKit`).
- Alarms can't ring in the simulator. Test ringing on a phone from TestFlight.

## App Store screenshots

- Mock screenshots for now, made from the design mockup: `store/screenshots/en-US/*.png`
  (1320 x 2868, the 6.9" iPhone size). Captions and screens are listed in
  `design/appstore/make-screenshots.mjs`; rerun it with `node` after changing them.
- CI uploads `store/screenshots/` to App Store Connect when it changes on `main`
  (`docs/ios-release.md`, "App Store listing").

## Subscriptions

- The Pro plans live in `store/subscriptions.json` (prices, launch offers, names,
  review screenshot `store/pro-review.png`) and sync to App Store Connect from `main`.
  Product IDs must match `ProProducts` in SquawkKit.
- Swap them for real app screenshots before the public release.
