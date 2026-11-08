# iOS builds and TestFlight

iOS apps build and ship with GitHub Actions on macOS runners. There's no Xcode Cloud.

The jobs run on GitHub's `xcode-27` runner image (Xcode 27.1 by default, on macOS 27).
GitHub's `macos-26` image only has Xcode 26, so Xcode 27 needs this label until a
`macos-27` image exists. The image is still marked "preview" by GitHub; if a build
breaks because of the runner, switching `runs-on` back to `macos-26` in
`.github/workflows/ios-app.yml` is the quick way out. The installed versions are listed
at https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md.

## How it works

- `.github/workflows/ios-app.yml` is a reusable workflow shared by every iOS app. It
  builds the app for the simulator, then, when asked, archives it and uploads it to
  TestFlight.
- Each app has a small caller workflow (e.g. `astrotype-ios.yml`) that passes the
  app's folder and scheme, and only runs when that app's files change.
- Pull requests only build. Pushes to `main` build and upload to TestFlight. You can
  also run an app's workflow by hand from the Actions tab.
- Build number = the commit time in UTC (`YYYYMMDDHHMM`), so it always goes up.
  The marketing version lives in the app's xcconfig (`MARKETING_VERSION`).
- Signing is automatic. The upload step uses an App Store Connect API key with
  cloud-managed signing, so no certificates or profiles live in the repo or in secrets.

## Entitlements (iCloud and other capabilities)

An app that sets `CODE_SIGN_ENTITLEMENTS` in its xcconfig is archived with an ad hoc
signature instead of unsigned, because export only keeps entitlements the archived app
was signed with. The workflow then checks that every key in the entitlements file is in
the archive, and stops before uploading if one is missing. Export uses the production
CloudKit environment.

For iCloud, the workflow turns the capability on for the bundle ID through the API
(`scripts/ios/asc-prepare-app.py`). The container itself is a one-time manual step:
Apple's API has no way to create one, and automatic signing with the API key doesn't
either (export fails with "No profiles for <bundle ID>"). Before the first upload:

1. developer.apple.com → Identifiers → **+** → iCloud Containers. Register
   `iCloud.<bundle ID>`.
2. Open the App ID, tick iCloud with CloudKit support, click Configure, tick that
   container and save.

App Groups (sharing data with an extension, like a widget) work the same way: the
workflow turns the App Groups capability on, but the group itself is made and linked by
hand. Register `group.<bundle ID>` under Identifiers → App Groups, then on the app's App
ID and each extension's App ID tick App Groups, click Configure, pick the group and save.

WeatherKit: the workflow turns the capability on. If weather requests still fail on a
TestFlight build, check developer.apple.com → Identifiers → the App ID → App Services and
tick WeatherKit. It can take about 30 minutes to start working.

## Extensions (widgets)

An extension is a second target in the app's project, embedded in the app, with its own
xcconfig, Info.plist and entitlements in `Config/`, and a bundle ID that starts with the
app's (`com.tinypenguin.squawk.widget`). The workflow finds it from the scheme's build
settings, registers its bundle ID and turns on its capabilities; export signs it along
with the app. Keep `MARKETING_VERSION` in one xcconfig both targets include, since the
versions must match. Squawk's widget is the example.

## Shared build settings

- `config/ios/Project.xcconfig`: project-level settings for every app (team, iOS
  version, Swift version, Debug/Release defaults).
- `config/ios/App.xcconfig`: settings for an app target (icon, generated Info.plist,
  iPhone only).
- Each app's `Config/*.xcconfig` includes these and adds its own bundle ID, version and
  display name. The `.pbxproj` itself has no build settings.

## One-time setup for the repo

Add these repository secrets (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | The API key's Key ID |
| `ASC_ISSUER_ID` | The Issuer ID shown on the API keys page |
| `ASC_PRIVATE_KEY` | The full contents of the `.p8` file |

Create the key in App Store Connect → Users and Access → Integrations → App Store
Connect API, with the **Admin** role. Admin is needed so the build can register bundle
IDs and use cloud-managed signing.

Until these secrets exist, the TestFlight job is skipped with a warning and only the
build runs.

Sentry (crash reports and metrics) needs one `SENTRY_AUTH_TOKEN` secret; CI creates each
app's Sentry project itself. See [`telemetry.md`](telemetry.md).

## One-time setup for each new app

1. Push to `main` (or run the app's workflow by hand). The TestFlight job registers
   the bundle ID through the API if it's missing (`scripts/ios/asc-prepare-app.py`),
   then stops with an error if there's no app record for it yet.
2. Create the app record: App Store Connect → Apps → **+** → New App, pick that bundle
   ID. Apple's API can't create app records.
3. If the app uses iCloud, register its container and link it to the App ID (see
   "Entitlements" above). The API can't do this either.
4. Re-run the workflow. The build appears in TestFlight after Apple finishes processing
   it.

## TestFlight testers

Each app lists its testers in `Config/testflight.json` (next to its xcconfig):

```json
{
  "group": "Team",
  "testers": ["someone@example.com"]
}
```

Every TestFlight run syncs this list before uploading (`scripts/ios/asc-sync-testers.py`). It creates the internal group
if it's missing, sets it to get every new build, adds anyone listed and removes anyone
in the group who isn't listed. To add or remove a tester, edit the list and push.

- These are internal testers, so each one must be a user on the App Store Connect team
  (Users and Access) who can see the app. Builds reach them without Beta App Review.
  An email that can't be added shows a warning in the run but doesn't stop the upload.
- Only that one group is synced. Other groups and testers you add in App Store Connect
  are left alone.
- With no `testflight.json`, the step is skipped.
- `config/ios/App.xcconfig` sets `ITSAppUsesNonExemptEncryption = NO`, so builds don't
  wait on the export compliance question. Change it per app if an app adds its own
  encryption.

## What to Test notes

After each upload, `scripts/ios/asc-build-notes.py` fills in the build's "What to Test"
in TestFlight with what changed since the previous build. It finds the previous build in
App Store Connect, turns its build number (the commit time) back into a point in git
history, and lists the titles of the commits since then that touched `apps/<name>/`.
Titles are cleaned up for testers: "Astrotype: fix extra spaces (#58)" becomes "Fix extra
spaces". So PR titles are what testers read; write them in plain words.

It waits up to 20 minutes for the build to show up in App Store Connect. If anything goes
wrong it only warns: the build is already uploaded. Run it with `--dry-run` to print the
notes without setting them.

## App Store listing (screenshots and subscriptions)

Each app keeps parts of its App Store listing in `apps/<name>/store/`, and
`.github/workflows/app-store.yml` keeps App Store Connect in sync with it. Pull requests
print what would change (in the "Subscriptions" step of the run); pushes to `main` make
the changes. Things that already match are skipped. It runs on Linux, not a Mac runner,
and can also be run by hand from the Actions tab. The API key needs the App Manager or
Admin role.

### Screenshots

One folder per language, named so they sort in the order they should show:

```
apps/squawk/store/screenshots/en-US/1-home.png
                                    2-rings.png
```

- The device comes from the image size: 1320 x 2868 is the 6.9" iPhone, 2064 x 2752 the
  13" iPad. `scripts/ios/asc-upload-screenshots.py` lists every size it knows; any other
  size stops the run. The 6.9" iPhone set is the only one Apple requires for an
  iPhone-only app.
- They go to the version you can still edit in App Store Connect (Prepare for
  Submission, or rejected). With no such version, the run warns and skips; add the next
  version in App Store Connect and re-run the workflow.
- A set that changed is replaced as a whole, so deleting, renaming or reordering files
  works too. A new language folder adds that language to the version. Up to 10 per set.
- Pull requests don't upload screenshots; only `main` does.

### Subscriptions

`store/subscriptions.json` lists the subscription groups and plans: product ID, length,
level, US price, launch offer, the name and description people see, and the App Review
screenshot (a file next to the JSON). The format is at the top of
`scripts/ios/asc-subscriptions.py`.

- Prices and launch offers are set in US dollars, and Apple's matching price is used in
  every other country. The price has to be one of Apple's price points (like 4.99).
- A price change keeps the old price for people who already subscribe.
- Nothing is deleted. A group, plan, language or offer missing from the file stays as it
  is in App Store Connect. Remove things there by hand.
- For an app with no `subscriptions.json` yet, the run prints what App Store Connect has
  in the file's format, to start from.
- The Paid Apps agreement, and submitting the first plans for review with an app version,
  stay manual.

## Adding a new iOS app

Run the new-app script from the repo root (Claude: use the `new-app` skill):

```bash
python3 scripts/new-app/new-app.py Squawk --display "Squawk"
```

It creates `apps/<slug>/ios/` (the Xcode project, `Config/` xcconfigs,
`testflight.json`, a placeholder screen and icon) and `.github/workflows/<slug>-ios.yml`
from `scripts/new-app/template/`. The bundle ID defaults to
`com.tinypenguin.<slug>`. The app comes with Sentry set up (see
[`telemetry.md`](telemetry.md)). Then add any entitlements the app needs, push, and do the
per-app Apple setup above.
