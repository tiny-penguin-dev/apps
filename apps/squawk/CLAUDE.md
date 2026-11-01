# CLAUDE.md: Squawk

Squawk is in the **Build** stage. Read `PRODUCT.md`, `DESIGN.md` and `BUILD.md` first.

- `PRODUCT.md`, `DESIGN.md` and `BUILD.md` are approved. Build phase by phase, one PR each.
- The mascot lives in the `PenguinKit` local package. Keep it free of Squawk-specific code
  so it can move to `packages/` when a second app needs it.
- Ideas come from the Morning alarm in `lanata/lanata-server` (`apps/ios/Lanata/Screens/Morning/`,
  especially `AlarmKit/MorningAlarmScheduler.swift`). Copy the ideas, not the code: Squawk
  has no server and no account.

Build, run and test steps go here once there's code.
