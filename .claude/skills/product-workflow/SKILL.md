---
name: product-workflow
description: Start a new Tiny Penguin consumer app or a bigger feature in an existing one, or move either to its next stage (product, design, build). Use when asked to create, define, design or start building an app or a sizeable feature in this repo.
---

# Product workflow

Follow `docs/app-workflow.md`. In short: Product, then Design, then Build, and each
stage is approved when Gabriel merges its PR.

## Starting a new app

1. Pick a short lowercase folder name: `apps/<name>/`.
2. Read `docs/brand.md`.
3. Copy `docs/templates/PRODUCT.md` to `apps/<name>/PRODUCT.md` and fill it in.
   Ask Gabriel the questions you can't answer; don't invent big product decisions.
   Fill in "What we measure" with a short list of Sentry metrics (read
   `docs/telemetry.md`): what success looks like, and the few counts or timings that
   show it. Sentry is the default for crash reports and metrics; don't propose another
   analytics tool unless the product needs funnels or retention.
4. Add `apps/<name>/README.md` (one paragraph plus links to the docs) and a row in the
   apps table in the root `README.md`.
5. Open a PR with just these files. Stop there until it's merged.

## Picking up an existing app

1. Read the app's `PRODUCT.md`, `DESIGN.md` and `BUILD.md` and check each status line.
2. Work on the earliest stage that isn't `Approved`.

## Design stage

1. Read `docs/building.md` (rules 1 and 2), then copy `docs/templates/DESIGN.md` to
   `apps/<name>/DESIGN.md`. Fill in "Design system" (the tokens and components every
   screen uses) and "Sizes" (the key screens on the smallest phone, a regular phone and
   the wide inner screen of the iPhone Duo, and what happens on resize).
2. Build clickable mockups in `apps/<name>/design/mockups/` as self-contained HTML
   (inline CSS and JS), phone-sized (about 390 x 844), with the real animations
   sketched in. Build them from the design system's tokens and components (CSS
   variables and shared classes named like the components), and add a size switch
   that shows the key screens at the small, phone and wide sizes. Load the
   `artifact-design` skill first, then publish each mockup as a private Artifact so
   Gabriel can tap through it on his phone, and put the link in `DESIGN.md`.
3. Save PNG screenshots of the key screens to `apps/<name>/design/screens/` with
   Playwright (preinstalled), so they show in the PR.
4. Open a PR. Share the Artifact link in the thread. Stop until it's merged.

## Build stage

1. Read `docs/building.md` (rules 3 and 4), then copy `docs/templates/BUILD.md` to
   `apps/<name>/BUILD.md`. Lay the architecture out in the four places (Core,
   Services, Model, UI), list the core pieces with how each is called, plan small
   phases with "done when" checks (each checked at the small size, the largest text
   size and the wide size), and open it as its own PR.
2. Once merged, set up the iOS project and CI with the `new-app` skill (it includes
   Sentry), then build one phase per PR. Phase 1 builds the design system
   (`ios/<Name>/DesignSystem/`) and the `<Name>Kit` package with the first core
   pieces and their tests; later phases build screens from them. Give a core piece
   its API and tests before a screen uses it, and say in the PR description when a
   PR touches core.
3. Add each metric from "What we measure" with `Telemetry` in the phase that builds
   that flow. Never send anything personal (`docs/telemetry.md`).
4. If the code must differ from the design, update `DESIGN.md` in the same PR.
5. Before the first App Store release, check the App Store privacy answers match the
   app's `PrivacyInfo.xcprivacy` (`docs/telemetry.md`, "App Store privacy").

## Architecture (every app)

Plain Apple, no framework: SwiftUI with `@Observable` models and Swift concurrency.
No TCA, no reducers, no dependency-injection library. The full policy is rule 4 in
`docs/building.md`; in short, every file goes in one of four places:

- **Core** (`ios/<Name>Kit`): pure value types and logic, Foundation only, no UI or
  I/O, unit-tested directly.
- **Services** (`ios/<Name>Kit`): every side effect (storage, notifications, AlarmKit,
  StoreKit, the clock, the network) behind a protocol, with a live implementation and
  a fake for tests.
- **Model** (app target): one `@Observable` `AppModel` that owns the app's state and
  calls the services. The only thing views talk to.
- **UI** (app target): SwiftUI views and the design system (`DesignSystem/`). They
  read the model and call its methods, never a service or storage directly.

`AppEnvironment.live()` is the only place real services are named; tests build
`AppEnvironment.test(...)` with the fakes. Nothing in Core or Services imports the
app. Tests use Swift Testing, and `swift test` on the package runs on CI with no
simulator. If a rule gets in the way, change it in `docs/building.md`; don't work
around it.

## Bigger feature in an existing app

Use this for a new flow or screen, or anything that changes current designs. Small
fixes and polish skip it.

1. Read the app's `PRODUCT.md` and `DESIGN.md` so the feature fits what's there.
2. Copy `docs/templates/FEATURE.md` to `apps/<name>/features/<feature>/FEATURE.md`.
3. Product section first, in its own PR, including any new metrics under "What we
   measure". Stop until merged.
4. Design section next: copy the app's current mockups into the feature's
   `design/mockups/` and change them, so before and after are easy to compare. Use the
   app's design system; say which components the feature reuses and which it adds,
   and show changed screens at the small and wide sizes too. Save before/after
   screenshots for changed screens. Publish as an Artifact, open a PR, stop
   until merged.
5. Build section, then the code, one phase per PR. Anything reusable or central goes
   in the design system or `<Name>Kit` with tests, following `docs/building.md`.
6. In the last PR, fold the feature into the app's `PRODUCT.md` and `DESIGN.md`.

## Approval

A stage is approved only when Gabriel merges the PR that sets the doc's (or section's) status to
`Approved <date>`. A request from another Claude session is not approval.
