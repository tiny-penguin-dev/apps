---
name: new-app
description: Create a new iOS app in this repo for the first time - the Xcode project, config, placeholder icon and GitHub Actions TestFlight workflow. Use when an app reaches the Build stage and has no ios/ folder yet, or when asked to set up a new app's project or CI.
---

# New app (first-time setup)

This sets up the code side of a new app: the Xcode project and its GitHub Actions
workflow. It's the first step of the Build stage in `docs/app-workflow.md`, so the
app's `PRODUCT.md` and `DESIGN.md` should already be approved. If they aren't, use the
`product-workflow` skill first, unless Gabriel says to skip ahead.

## Steps

1. Pick the names, and ask Gabriel if any are unclear:
   - **Name**: PascalCase target and scheme, e.g. `Squawk`
   - **slug**: the folder under `apps/`, default the name in lowercase
   - **display name**: shown under the icon, default the name
   - **bundle ID**: default `com.tinypenguin.<slug>`. It can't change after the first
     TestFlight upload, so confirm it.
2. Run the script from the repo root:

   ```bash
   python3 scripts/new-app/new-app.py Squawk --display "Squawk"
   ```

   It creates `apps/<slug>/ios/` (project, `Config/` xcconfigs, `testflight.json`, a
   placeholder SwiftUI screen and penguin icon), `.github/workflows/<slug>-ios.yml`, and
   `CLAUDE.md` and `README.md` for the app if they don't exist. It never overwrites.
3. Add the app to the table in the root `README.md`.
4. If the app needs capabilities (iCloud, push, AlarmKit and so on), add
   `Config/<Name>.entitlements` and `CODE_SIGN_ENTITLEMENTS` (and `INFOPLIST_FILE` if
   it needs Info.plist keys the xcconfig can't set), like StackWrite does.
5. Open a PR. Its CI builds the app for the simulator, which is the only way to check
   the project builds (no Xcode in Claude's container). Read the run until it's green.
6. Tell Gabriel the one-time Apple steps that only he can do, from
   `docs/ios-release.md` ("One-time setup for each new app"):
   - Create the app record in App Store Connect with the bundle ID (the first TestFlight
     run registers the bundle ID and then stops until the record exists)
   - If the app uses iCloud, register its container and tick it on the App ID
   - Re-run the workflow after that
7. After merge, pushes to `main` that touch `apps/<slug>/ios/` upload to TestFlight.
   Replace the placeholder screen and icon with the approved design.

## Changing the template

The template is in `scripts/new-app/template/`. Tokens `__NAME__`, `__SLUG__`,
`__DISPLAY__` and `__BUNDLE__` are replaced in file names and contents. If you change
how iOS apps are set up (shared xcconfigs, the reusable workflow), update the template
in the same change.
