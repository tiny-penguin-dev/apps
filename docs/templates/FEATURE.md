# <App name>: <feature name>

One sentence: what the feature is and why it matters.

## Product

Status: Draft

- **The problem:** what people can't do today, or what's annoying
- **Who wants it:** everyone, or a smaller group of power users
- **Basics or powerful:** is this part of the simple path, or tucked away?
- **How it works:** the flow in plain words
- **What it changes:** existing flows or features this touches
- **Scope:** in this version / later / never
- **What we measure:** new Sentry metrics (name, count or duration, what it tells us),
  see `docs/telemetry.md`
- **Open questions** for Gabriel

## Design

Status: Not started

- **Mockups:** `design/mockups/<file>.html` (Artifact link: <url>)
- **What changes:** each existing screen that changes, with before/after screenshots
- **New screens:** what's on them and what you can do there
- **Motion and copy:** new animations, haptics, labels and messages, in the brand voice
- **Design system:** which existing components it uses, and any new token or component
  it adds (`docs/building.md`, rule 1)
- **Sizes:** the changed screens on the smallest phone and the wide iPhone Duo screen
- **Accessibility:** anything new for Dynamic Type, VoiceOver or Reduce Motion
- **Open questions** for Gabriel

## Build

Status: Not started

- **Approach:** a few lines on how it fits the current code and its layers
- **Core pieces:** anything reusable or central it adds or changes, with how it is
  called (`docs/building.md`, rule 3)
- **Phases:** one PR each, with a "done when" check you can see on a phone
- **Risks**
- **Metrics:** add the ones listed under Product with `Telemetry`
- **Last step:** fold this feature into the app's `PRODUCT.md` and `DESIGN.md`
