# iOS builds and TestFlight

iOS apps build and ship with GitHub Actions on macOS runners. There's no Xcode Cloud.

## How it works

- `.github/workflows/ios-app.yml` is a reusable workflow shared by every iOS app. It
  builds the app for the simulator, then, when asked, archives it and uploads it to
  TestFlight.
- Each app has a small caller workflow (e.g. `stackwrite-ios.yml`) that passes the
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
(`scripts/ios/asc-prepare-app.py`) and expects automatic signing at export to register
the container and link it. If export fails on the container, create it by hand as a
fallback: developer.apple.com → Identifiers → iCloud Containers → +, then turn on iCloud
(CloudKit) for the App ID and tick that container.

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

## One-time setup for each new app

1. Push to `main` (or run the app's workflow by hand). The TestFlight job registers
   the bundle ID through the API if it's missing (`scripts/ios/asc-prepare-app.py`),
   then stops with an error if there's no app record for it yet.
2. Create the app record: App Store Connect → Apps → **+** → New App, pick that bundle
   ID. Apple's API can't create app records, so this is the one manual step.
3. Re-run the workflow. The build appears in TestFlight after Apple finishes processing
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

## Adding a new iOS app

1. Copy `apps/stackwrite/ios/` as a starting point: the `.xcodeproj`, `Config/` and the
   source folder.
2. Rename the target, scheme and folders, and set the bundle ID, version and display
   name in the app's xcconfig, and list the testers in `Config/testflight.json`.
3. Copy `.github/workflows/stackwrite-ios.yml` and change the name, paths, `app-dir` and
   `scheme`.
4. Do the per-app Apple setup above.
