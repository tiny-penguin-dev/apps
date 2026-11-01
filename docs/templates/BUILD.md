# <App name>: build plan

Status: Draft

Builds on `PRODUCT.md` (approved <date>) and `DESIGN.md` (approved <date>).

## Architecture

A few lines: main frameworks, how data is stored, the main pieces of the app, laid out
in the four places from `docs/building.md` (Core, Services, Model, UI).
Crash reports and metrics use Sentry through `Telemetry` (`docs/telemetry.md`).

## Core pieces

The reusable and central code (the design system, the model, the store, any local
package), with a few lines of Swift showing how each is called from a screen or a test
(`docs/building.md`, rule 3). These get tests before they are used.

## Metrics

Which phase adds each metric from "What we measure" in `PRODUCT.md`.

## Phases

Each phase is one PR and leaves something to try in TestFlight.

### Phase 1: <name>

What's in it. Phase 1 usually sets up the project and the design system.

**Done when:** a check you can see on a phone, at the small size, the largest text size
and the wide size.

### Phase 2: <name>

...

## Risks

What might not work, and how we'll find out early.

## Open questions

Questions for Gabriel.
