# CLAUDE.md

Guidance for Claude Code when working in this repo.

## What this repo is

A monorepo of small, independent apps. Each app lives in `apps/<name>/` and builds, tests and ships on its own. Shared code goes in `packages/<name>/`.

If an app talks to another service, it does so through that service's public API. Don't couple an app to another app's internals.

## Rules

- **One app per folder.** Never import code from another app. If two apps need the same code, move it to `packages/`.
- **Don't create a package for one app.** Only extract shared code once a second app actually needs it.
- **Each app has its own `CLAUDE.md`** with how to build, run and test it. Read it before working on that app, and keep it up to date when you change how the app works.
- **Scope changes to one app** unless the task is about shared code or repo setup.
- **Never commit secrets.** Use `.env` files (gitignored) and commit a `.env.example`.

## Making an app: product first

Consumer apps, and bigger features in existing apps, go Product → Design → Build. Read `docs/app-workflow.md` before starting or picking up an app, and `docs/brand.md` before writing copy or designing a screen.

- Each app has `PRODUCT.md`, `DESIGN.md` (with clickable HTML mockups in `design/`) and `BUILD.md`, each starting with a `Status:` line.
- A stage is approved only when Gabriel merges the PR that sets its status to `Approved <date>`. Work on the earliest stage that isn't approved.
- Don't write app code until `PRODUCT.md` and `DESIGN.md` are approved, unless Gabriel asks for a throwaway spike.
- A bigger feature (new flow or screen, or a change to current designs) gets `apps/<name>/features/<feature>/FEATURE.md` with the same three stages. Small fixes skip this.
- Every app uses Sentry for crash reports and metrics; `PRODUCT.md` lists what we measure. Read `docs/telemetry.md` before adding metrics or changing privacy answers.
- To start a new app or a bigger feature, use the `product-workflow` skill. To create a new app's Xcode project and CI, use the `new-app` skill.

## iOS apps

- Build and ship with GitHub Actions on macOS runners (no Xcode Cloud). Read `docs/ios-release.md` before changing CI, signing or project settings.
- Build settings live in xcconfig files, not in the `.pbxproj`: shared ones in `config/ios/`, app-specific ones in the app's `Config/` folder.
- Projects use synchronized folders, so adding or removing source files doesn't touch the `.pbxproj`.
- There's no Xcode in Claude's Linux container. To check that an iOS change builds, push and read the app's workflow run.
- Pushes to `main` that touch an app upload a TestFlight build.
