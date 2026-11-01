# Crash reports and metrics (Sentry)

Every Tiny Penguin app uses [Sentry](https://sentry.io) for two things:

- **Crash reports and errors**, with readable stack traces
- **Metrics**: simple counts and timings, like "alarms created" or "how long setup
  took" (Sentry Metrics)

One tool keeps it simple: the numbers sit next to the crashes, and nothing else needs
setting up. Sentry is good at counts and spotting changes. It's weaker at product
questions like funnels (install → first alarm → Pro trial) and retention over weeks.
If we find we need those, add [TelemetryDeck](https://telemetrydeck.com) later for that
job only. Don't add it up front.

## What we collect, and what we never do

Tiny Penguin apps have no accounts and keep data on the device. Telemetry follows that:

- **Never** send names, emails, user or device IDs, contacts, locations, free text, or
  anything someone typed or recorded.
- **Never** track people across apps or websites, and no ads SDKs. No App Tracking
  Transparency prompt is ever needed.
- Metric attributes are small fixed values, like `{"plan": "pro"}` or
  `{"rings": "3"}`, never something a person wrote.
- `sendDefaultPii` stays off, so Sentry doesn't attach IP addresses or user info.
- Each app has a **Share anonymous usage data** switch in Settings (on by default),
  wired to `Telemetry.isEnabled`.

## In the app

New apps get this from the `new-app` template (`scripts/new-app/template/`):

- The `sentry-cocoa` Swift package (product `Sentry`), already added to the project.
- `Telemetry.swift`: a small wrapper so app code never imports Sentry directly.
  `Telemetry.start()` runs in the App's `init`.
- `PrivacyInfo.xcprivacy`: the app's privacy manifest (see below). Sentry ships its
  own manifest for the SDK.
- `Config/Info.plist` with a `SentryDSN` key filled from the `SENTRY_DSN` build setting.

Using it:

```swift
Telemetry.count("alarm.created")
Telemetry.count("alarm.dismissed", ["method": "math"])
Telemetry.duration("onboarding.finished", seconds: elapsed)
Telemetry.gauge("alarms.total", value: Double(alarms.count))
Telemetry.report(error)   // a handled error that shouldn't have happened
```

Metric names are lowercase and dotted: `<thing>.<what happened>`. List every metric in
the app's `PRODUCT.md` under "What we measure" (or a feature's `FEATURE.md`), so they're
agreed before they're built.

## The DSN (no secrets in the repo)

The DSN tells the app where to send events. It's baked into the app at build time and
never committed:

- **TestFlight and App Store builds**: CI passes the `SENTRY_DSN_<APP>` repo secret
  (for example `SENTRY_DSN_SQUAWK`) as the `SENTRY_DSN` build setting when it archives.
- **Simulator builds in CI and local builds**: no DSN, so Sentry stays off.
- **To test Sentry from a local build**: create `Config/Secrets.xcconfig` (gitignored)
  with `SENTRY_DSN = https:/$()/<key>@<host>/<project>`. The `$()` is needed because
  xcconfig treats `//` as the start of a comment.

## Debug symbols

After each TestFlight upload, the reusable workflow (`.github/workflows/ios-app.yml`)
uploads the archive's dSYMs to Sentry with `sentry-cli`, so crash reports show file
names and line numbers. The app's caller workflow passes `sentry-project: <slug>`. If
the upload fails it only warns, since the build is already in TestFlight.

## One-time setup

For the repo (once):

| Where | Name | Value |
|---|---|---|
| Repo secret | `SENTRY_AUTH_TOKEN` | A Sentry organization auth token (Settings → Developer Settings → Organization Tokens). It can upload debug files. |
| Repo variable | `SENTRY_ORG` | The Sentry organization slug |

For each new app:

1. In Sentry, create a project for the app (platform: Apple iOS), named after the
   app's folder, for example `squawk`.
2. Copy its DSN (Project Settings → Client Keys) into a repo secret named
   `SENTRY_DSN_<APP>`, the folder name in capitals with `-` as `_`.
3. Push to `main`. The next TestFlight build sends crash reports and metrics. Until the
   DSN secret exists, the TestFlight run warns and the build ships with Sentry off.

## App Store privacy

`PrivacyInfo.xcprivacy` and the App Store privacy label must say the same thing. With
the template as it is, in App Store Connect → App Privacy, answer:

- **Data used to track you:** none
- **Data not linked to you:**
  - Diagnostics → Crash Data (purpose: App Functionality)
  - Diagnostics → Performance Data (purpose: App Functionality)
  - Diagnostics → Other Diagnostic Data (purpose: App Functionality)
  - Usage Data → Product Interaction (purpose: Analytics)

If an app collects anything else, add it to both the manifest and the label in the same
PR. The manifest also declares `UserDefaults` use (reason `CA92.1`), which
`Telemetry.isEnabled` needs.

## Adding Sentry to an app made before this

StackWrite predates this setup. To add Sentry to an existing app: add the
`sentry-cocoa` package to the target in Xcode, copy `Telemetry.swift` and
`PrivacyInfo.xcprivacy` from the template (merging with any manifest the app already
has), add the `SentryDSN` key and `SENTRY_DSN =` setting as in the template's
`Info.plist` and xcconfig, and switch the caller workflow to the template's
`sentry-project` input and explicit secrets.
