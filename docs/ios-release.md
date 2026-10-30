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

1. Register the bundle ID: developer.apple.com → Identifiers → **+** → App ID.
2. Create the app record: App Store Connect → Apps → **+** → New App, pick that bundle ID.
3. Push to `main` (or run the app's workflow by hand). The build appears in TestFlight
   after Apple finishes processing it.

## Adding a new iOS app

1. Copy `apps/stackwrite/ios/` as a starting point: the `.xcodeproj`, `Config/` and the
   source folder.
2. Rename the target, scheme and folders, and set the bundle ID, version and display
   name in the app's xcconfig.
3. Copy `.github/workflows/stackwrite-ios.yml` and change the name, paths, `app-dir` and
   `scheme`.
4. Do the per-app Apple setup above.
