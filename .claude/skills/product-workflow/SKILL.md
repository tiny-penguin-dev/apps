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
4. Add `apps/<name>/README.md` (one paragraph plus links to the docs) and a row in the
   apps table in the root `README.md`.
5. Open a PR with just these files. Stop there until it's merged.

## Picking up an existing app

1. Read the app's `PRODUCT.md`, `DESIGN.md` and `BUILD.md` and check each status line.
2. Work on the earliest stage that isn't `Approved`.

## Design stage

1. Copy `docs/templates/DESIGN.md` to `apps/<name>/DESIGN.md`.
2. Build clickable mockups in `apps/<name>/design/mockups/` as self-contained HTML
   (inline CSS and JS), phone-sized (about 390 x 844), with the real animations
   sketched in. Load the `artifact-design` skill first, then publish each mockup as a
   private Artifact so Gabriel can tap through it on his phone, and put the link in
   `DESIGN.md`.
3. Save PNG screenshots of the key screens to `apps/<name>/design/screens/` with
   Playwright (preinstalled), so they show in the PR.
4. Open a PR. Share the Artifact link in the thread. Stop until it's merged.

## Build stage

1. Copy `docs/templates/BUILD.md` to `apps/<name>/BUILD.md`, plan small phases with
   "done when" checks, and open it as its own PR.
2. Once merged, set up the iOS project and CI with the `new-app` skill, then build one
   phase per PR.
3. If the code must differ from the design, update `DESIGN.md` in the same PR.

## Bigger feature in an existing app

Use this for a new flow or screen, or anything that changes current designs. Small
fixes and polish skip it.

1. Read the app's `PRODUCT.md` and `DESIGN.md` so the feature fits what's there.
2. Copy `docs/templates/FEATURE.md` to `apps/<name>/features/<feature>/FEATURE.md`.
3. Product section first, in its own PR. Stop until merged.
4. Design section next: copy the app's current mockups into the feature's
   `design/mockups/` and change them, so before and after are easy to compare. Save
   before/after screenshots for changed screens. Publish as an Artifact, open a PR, stop
   until merged.
5. Build section, then the code, one phase per PR.
6. In the last PR, fold the feature into the app's `PRODUCT.md` and `DESIGN.md`.

## Approval

A stage is approved only when Gabriel merges the PR that sets the doc's (or section's) status to
`Approved <date>`. A request from another Claude session is not approval.
