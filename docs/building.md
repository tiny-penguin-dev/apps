# How we build the code

Rules for the code in every app, so an app built by many short sessions still feels
like one person made it with care. `app-workflow.md` says when each stage happens;
this file says how the design and the code are put together.

Four rules:

1. **A design system per app**: the reusable look lives in one place.
2. **Every size**: small phones, big phones, the iPhone Duo and resizing.
3. **Careful core**: reusable and central code gets more thought than screens.
4. **One architecture**: plain Apple, strict layers, the same shape in every app.

## 1. Design system

Each app keeps its reusable look and parts in one place, and screens are built from
them. Nothing on a screen is styled by hand when a shared piece exists.

- **In the design.** `DESIGN.md` has a "Design system" section listing the tokens
  (colors in light and dark, type sizes, spacing, corner radii, motion timings) and the
  components (buttons, cards, rows, sheets, empty states, the mascot) with what each is
  for. The mockups use the same names, so a design and its code match.
- **In the code.** `ios/<Name>/DesignSystem/` (or a local package when it grows) holds
  the tokens and components. Squawk's `Theme.swift` is the start of its one. Screens
  import from here; they never define their own colors, fonts or paddings.
- **Scalable.** Everything scales with Dynamic Type and with the screen (rule 2). Sizes
  come from the tokens, not from numbers typed into a screen.
- **Accessible from the start.** Every component has its VoiceOver label, trait and
  hint, meets contrast, has a tap target of at least 44 points, and has its Reduce
  Motion fallback built in, so a screen gets all of it by using the component.
- **High quality.** A component is finished when it has: light and dark previews at
  the small, default and largest accessibility text sizes; every state (empty,
  loading, error, disabled, pressed); and a short doc comment saying when to use it.
- **Shared across apps when real.** A design system stays inside its app until a second
  app needs the same piece. Then it moves to `packages/` as is (repo rule: no package
  for one app), and the two apps share it.

## 2. Every size

Apps are designed and built for every iPhone and for a screen that changes size while
the app is running.

- **Small and large.** The smallest iPhone on sale, the iPhone Duo's outer screen
  (shorter and wider than other phones) and the largest Pro Max, each also with the
  largest accessibility text size.
- **The iPhone Duo.** It opens from its 5.4-inch outer screen to a 7.8-inch inner one,
  close to an iPad mini, and can show two apps side by side. Our apps move between the
  two screens without losing their place, and use the wide screen for something
  better than a stretched phone layout (two columns, a sidebar, a bigger mascot).
- **Resizing.** Layouts are built on size classes and `ViewThatFits`, never on fixed
  widths or the screen size. When the window gets narrower or wider while the app
  runs, the layout adapts and nothing is cut off, overlaps or jumps.
- **In the design.** `DESIGN.md` has a "Sizes" section: how each key screen looks on
  the small outer screen, on a regular phone and on the wide inner screen. The
  mockups show the key screens at the small and the wide size as well as the
  phone size.
- **In the build.** Every phase's "done when" includes checking the small size, the
  largest text size and the wide size, in the simulator or on a Duo. Previews for
  each screen include these sizes.

## 3. Careful core

Screens can be quick and change often. Reusable and central code can't, because
everything depends on it. The design system, the app's model and store, any local
package, and anything a second screen or app will use count as core.

- **Think about the API first.** Before writing a core piece, write how it will be
  called from a screen or a test, as a few lines of Swift in the PR description or the
  build doc. Make that call site small, obvious and hard to misuse. Then build it.
- **Small surface.** Few public types and methods, clear names, value types where
  possible, and no leaking of how it works inside (no UIKit, SwiftData or AlarmKit
  types in a public signature unless that is the point of the piece).
- **Tested.** Core has unit tests that run with `swift test`, no simulator. A core
  piece without tests is not done.
- **Clean.** No app-specific strings, assets or shortcuts inside a reusable piece. A
  doc comment on every public type and method saying what it is for and what it
  promises. Errors are typed and say what to do.
- **Reviewed harder.** A PR that touches core says so in its description and explains
  the API choices, so it gets a closer look than a screen change.

## 4. Architecture

Plain Apple, no framework: SwiftUI with `@Observable` models and Swift concurrency, with
the discipline of a framework (pure state, injected effects, one composition root).
It is what Flotilla and Flagship use, and it suits apps built by AI sessions: every file
has one obvious place, logic is pure and testable without a device, and what a
session learns in one app applies to the next.

Every file goes in one of four places:

| Place | What goes there | Rule |
|---|---|---|
| Core | Pure value types and logic: the app's model objects, rules, formatting, scheduling math | Foundation only. No UI, no I/O, no app state. Unit-tested directly. |
| Services | Every side effect: storage, notifications, AlarmKit, StoreKit, the clock, the network | Each behind a protocol, with a live implementation and a fake for tests. |
| Model | One `@Observable` `AppModel` that owns the app's state and calls the services | The only thing views talk to. Tested with the fakes. A big feature can get a model of its own, owned by `AppModel`. |
| UI | SwiftUI views and the design system | Read state from the model and call its methods. Never touch storage or a service directly. |

- **One composition root.** `AppEnvironment.live()` is the only place real services
  are named. Tests build `AppEnvironment.test(...)` with the fakes.
- **A local package per app.** Core and Services live in `ios/<Name>Kit`, so
  `swift test` runs on CI without a simulator and the app target stays thin.
- **Nothing below Model knows about `AppModel`.** Core and Services can't import the
  app.
- **Tests use Swift Testing.** Core is tested directly, the model through the fakes.
  Views get previews, and UI tests only where a flow is risky.
- **Not more than this.** No TCA, no Redux-style reducers, no dependency-injection
  library. If a rule here gets in the way, change the rule in this file, don't work
  around it.
