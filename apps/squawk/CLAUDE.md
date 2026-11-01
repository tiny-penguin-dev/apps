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
- `ios/Squawk/`: app screens, `Theme.swift` (colors and type from `DESIGN.md`) and
  `Telemetry.swift` (Sentry crash reports and metrics, see `docs/telemetry.md`). App code
  calls `Telemetry`, never Sentry directly. List new metrics in `PRODUCT.md` first.
- `ios/SquawkKit/`: local Swift package with the alarm model (`Alarm`, `Ring`,
  `TimeOfDay`, `Weekday`), one-morning changes (`MorningChange` in `Mornings.swift`:
  skip, new time, or "already up"), `AlarmPlanner` (alarms → the AlarmKit alarms to
  schedule; a weekday whose next morning has a change rings as one-off alarms for a
  few weeks, since AlarmKit can't skip one week of a repeating alarm),
  `FileAlarmStore` (JSON in Application Support) and the sound list. No UI, no AlarmKit.
- `ios/Squawk/Alarms/`: `AlarmsModel` (the app's alarms; every change saves and
  re-plans; opening the app mid-morning cancels the rest of it) and `AlarmKitScheduler`,
  the only code that talks to AlarmKit. "I'm up" on the ringing screen runs
  `SquawkUpIntent`.
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
