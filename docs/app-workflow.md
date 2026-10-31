# How we make an app

Every Tiny Penguin consumer app goes through three stages, in order:

1. **Product**: what the app is and why anyone would want it
2. **Design**: what it looks like, how it moves and how it feels
3. **Build**: the code, shipped to TestFlight and then the App Store

Each stage ends with Gabriel approving it. Nothing in a stage starts until the stage
before it is approved. Going back is fine: if building shows a design problem, update
the design doc (and get it approved again) rather than quietly building something else.

All apps share one look and feel. Read [`brand.md`](brand.md) before writing product
copy or designing a screen.

## Where things live

```
apps/<name>/
  PRODUCT.md        stage 1: the product definition
  DESIGN.md         stage 2: screens, flows, animation, copy
  design/
    mockups/        clickable HTML mockups (one self-contained .html per flow, or one for the app)
    screens/        PNG screenshots of the mockups, so the design can be reviewed in the PR
  BUILD.md          stage 3: the build plan, in phases
  README.md         one paragraph on what the app is, plus links to the docs above
  CLAUDE.md         how to build, run and test it (written in stage 3)
  ios/              the code (stage 3)
```

Start each doc from the template in [`templates/`](templates).

## The status line

Each of the three docs starts with a status line:

```
Status: Draft
Status: Approved 2026-11-02
```

A doc is approved when Gabriel merges the PR that sets its status to `Approved <date>`.
That merged PR is the approval, nothing else is. If an approved doc changes in a way
that matters (a new feature, a dropped flow, a different screen), set it back to
`Draft` in the same PR.

## Stage 1: Product (`PRODUCT.md`)

Answers "what are we making and why". No screens, no code.

- The problem, and who has it
- What makes this app different, and its penguin twist
- The core flows, in plain words
- Features split into **basics** (what everyone uses on day one, must be dead simple)
  and **powerful** (customizations for people who want them, tucked away)
- What's in v1, what waits for later, and what we will never do
- Platform limits that shape the product (for example what an Apple framework allows)
- How we'll know it works
- Open questions for Gabriel

**Done when:** Gabriel merges the PR with `Status: Approved <date>`.

## Stage 2: Design (`DESIGN.md` + `design/`)

Answers "what does it look like and how does it feel". Builds only on the approved
product doc.

- Every screen, and the flows between them
- Clickable HTML mockups in `design/mockups/`: self-contained (inline CSS and JS, no
  build step), phone-sized, with the real animations and transitions sketched in.
  They're published as private Artifacts so Gabriel can tap through them on his phone.
- Screenshots of the key screens in `design/screens/`, so the PR shows them inline
- The mascot or characters, and where they show up
- Animation notes: what moves, when, and why it's fun
- Copy: button labels, empty states, error messages and notifications, in the brand voice
- Accessibility: Dynamic Type, VoiceOver labels, Reduce Motion fallbacks

**Done when:** Gabriel merges the PR with `Status: Approved <date>`.

## Stage 3: Build (`BUILD.md`, then code)

Answers "how do we build it, in what order". Builds only on the approved design.

- `BUILD.md` comes first, in its own PR: the architecture in a few lines, then small
  phases, each with a "done when" check that can be seen on a phone
- Then one PR per phase. Each phase should leave something Gabriel can try in TestFlight.
- Set up the iOS project and CI by following "Adding a new iOS app" in
  [`ios-release.md`](ios-release.md), and write the app's `CLAUDE.md`
- If the code has to differ from the design, update `DESIGN.md` in the same PR and say so

**Done when:** the phases in `BUILD.md` are all ticked and the app is in TestFlight.

## For Claude

- Starting a new app: use the `new-app` skill (`.claude/skills/new-app/`).
- Before working on an app, read its `PRODUCT.md`, `DESIGN.md` and `BUILD.md` and check
  their status lines. Work on the earliest stage that isn't approved yet.
- Don't write app code until `PRODUCT.md` and `DESIGN.md` are both approved, unless
  Gabriel asks for a throwaway spike. Put spikes in `apps/<name>/spikes/` and say they're
  throwaway.
- Keep stage PRs small and about one stage, so approving one is an easy yes.
- When a doc leaves an open question, ask Gabriel instead of guessing, and record the
  answer in the doc.
