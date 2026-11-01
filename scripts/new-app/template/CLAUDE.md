# CLAUDE.md: __DISPLAY__

Read `PRODUCT.md`, `DESIGN.md` and `BUILD.md` first, and check their status lines
(see `docs/app-workflow.md`).

## Layout

- `ios/__NAME__.xcodeproj`: one app target, `__NAME__`, with a shared scheme
- `ios/__NAME__/`: app sources and assets (a synchronized folder, so new files are
  picked up without editing the project)
- `ios/Config/`: `__NAME__.xcconfig` (bundle ID `__BUNDLE__`, version, display name),
  `Project.xcconfig`, and `testflight.json` (TestFlight testers)

## Crash reports and metrics

Sentry, through `ios/__NAME__/Telemetry.swift`. Add the metrics listed in `PRODUCT.md`
("What we measure") with `Telemetry.count`/`duration`/`gauge`, and never send anything
personal. The DSN comes from the `SENTRY_DSN___ENV__` repo secret at archive time. See
`docs/telemetry.md`.

## Build and ship

- CI: `.github/workflows/__SLUG__-ios.yml`. PRs build for the simulator; pushes to
  `main` that touch `apps/__SLUG__/ios/` upload to TestFlight.
- There's no Xcode in Claude's container: push and read the workflow run to check a build.
- One-time Apple setup is in `docs/ios-release.md` ("One-time setup for each new app").

Keep this file up to date as the app grows (build, run and test commands, layout).
