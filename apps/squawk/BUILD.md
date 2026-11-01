# Squawk: build plan

Status: Approved 2026-11-01

Builds on `PRODUCT.md` (approved 2026-10-31) and `DESIGN.md` (approved 2026-10-31).

## Architecture

- **SwiftUI app, iOS 26+, iPhone only.** Project and CI from `scripts/new-app/new-app.py`,
  bundle ID `com.tinypenguin.squawk` (registered, App Store Connect record exists).
- **Two local Swift packages inside `apps/squawk/ios/`**, so the app target stays thin:
  - `PenguinKit`: the mascot (see below). Knows nothing about alarms or Squawk.
  - `SquawkKit`: the alarm model, storage, scheduling and checks. No UI.
- **Data:** a small JSON file on the phone (`FileAlarmStore`), behind one `AlarmStore`
  protocol, so iCloud sync can be added later without touching screens. No account, no
  server. (Planned as SwiftData; a versioned JSON file turned out simpler for a short
  list of alarms and runs in the package tests.)
- **Model (open lists, like Lanata's Morning):** `Alarm` has a time, days or a date,
  `dayTimes` (different time on some days), `rings` (one by default) and `checks`
  (`WakeUpCheck` enum: `.tag`, `.code`, `.game`; later `.shortcut`, `.steps`). Actions and
  conditions join the same way when their version comes. Adding a kind is one enum case.
- **One planner and one scheduler.** `AlarmPlanner` (in `SquawkKit`, unit tested) turns saved alarms into AlarmKit alarms: each group
  of days with the same time becomes one weekly repeating alarm per ring. Alarms with
  checks are planned a few mornings ahead and re-planned whenever the app opens or a
  morning ends. `AlarmKitScheduler` in the app hands that plan to AlarmKit. Every screen
  goes through them; nothing else talks to AlarmKit.
- **Pro is checked in one place** (`ProAccess`, StoreKit 2). Moving a feature between free
  and Pro is a one-line change.
- **Sentry** for crash reports and metrics, the Tiny Penguin default, set up the way the
  `new-app` skill describes. No personal data in events.
- **Mornings log** (on device): when each ring fired and when you got up. Drives the
  penguin reactions and streaks, and logs scheduling errors.

### The mascot (`PenguinKit`)

Built to be shared, but kept inside Squawk until a second app needs it (repo rule: no
package for one app). Then it moves to `packages/PenguinKit` as is.

- `PenguinView(mood:style:)` draws penguin 2 from SwiftUI `Shape`s, using the same
  200×200 numbers as the mockup, so it scales to any size and stays sharp.
- `PenguinMood`: asleep, awake, proud, grumpy, squawk, faint. Each mood sets eyes, beak,
  flippers, cheeks and its animation (breathe, hop, wave, shake, floating z's).
- `PenguinStyle`: body, belly, beak and cheek colors, plus optional accessories
  (nightcap, scarf, beanie, sunglasses, party hat). Another app can use its own colors
  and outfits without touching the drawing code.
- Respects Reduce Motion (keeps the pose, drops the movement).
- Comes with a preview gallery of every mood and style, and the app has a hidden debug
  screen showing them all, for checking on a real phone.
- No app-specific strings, sounds or assets inside, so it can move without changes.

## Phases

Each phase is one PR and leaves something to try in TestFlight.

### Phase 1: Project and Squawk the penguin

Xcode project and CI from the `new-app` script, with the AlarmKit entitlement. The
`PenguinKit` package with all six moods, animations, outfits and the debug gallery. The
app opens to the welcome screen with Squawk waddling in. App icon from the penguin.

**Done when:** the TestFlight build opens to Squawk waving hello, and the debug gallery
shows every mood animating on the phone.

### Phase 2: One reliable alarm

`SquawkKit` model and SwiftData store, `AlarmScheduler` on AlarmKit, first launch
(welcome, permission, pick a time), home with sleeping Squawk and the sleep bubble, edit
alarm (time, days or date, different time on some days, sound, on/off, label), and the
bundled sounds (the 8 Lanata alarm sounds, cleared by Gabriel for a public app).

**Done when:** a new user sets an alarm in under 30 seconds, and it rings on the lock
screen with the phone on silent and in a Focus.

### Phase 3: Extra rings and next morning only

"+ Soft ring before" / "+ Loud ring after", the timeline, Customize (any number of rings,
each with time, sound, color and optional name, loop or play once), skip or change the
next morning only.

**Done when:** an alarm with three rings rings three times, opening the app cancels the
rest for today, and skipping tomorrow leaves the day after untouched.

### Phase 4: Wake-up checks

The check flow and its open list: scan a tag (NFC), scan a code (VisionKit), penguin game,
and the math way out. The last ring comes back every 30 seconds for up to 10 minutes
until the checks are done, with "Snooze" as the honest button label.

**Done when:** with a tag check on, the alarm keeps coming back until the tag is scanned,
the math question also turns it off, and it stops by itself after 10 minutes.

### Phase 5: Good mornings

Mornings log, Good morning screen with Squawk's reaction (proud, fine, grumpy, faint),
streaks, fish confetti, and the toggle wobbles and other small motion from `DESIGN.md`.

**Done when:** getting up on the first ring shows proud Squawk and the streak goes up;
needing the last ring shows grumpy Squawk.

### Phase 6: Squawk Pro

StoreKit 2 subscription (monthly and yearly, launch prices as introductory offers),
`ProAccess`, the Pro screen, Pro badges, and Pro-only outfits and app icons. Free alarms
stop at 2 rings.

**Done when:** in TestFlight's sandbox, buying Pro unlocks more rings, checks and outfits,
and restoring works after reinstalling.

### Phase 7: Widget and polish

Next-alarm widget, dark mode pass, Dynamic Type and VoiceOver pass, App Store screenshots
with Squawk.

**Done when:** the widget shows the next alarm on the home and lock screens, and every
screen works at the largest text size and with VoiceOver.

## Risks

- **AlarmKit behaviour on real phones** (silent mode, Focus, repeating per day). The
  simulator can't ring, so phase 2 goes to TestFlight early and we test it for a few
  mornings before building more on it.
- **Re-planning alarms with checks** depends on the app opening. Planning several
  mornings ahead covers most cases; the mornings log will show if any are missed.
- **NFC needs its entitlement** and a real phone. Code scanning is the fallback for
  phones without a tag.
- **No Xcode in Claude's container.** Every change is checked by the GitHub Actions build;
  `PenguinKit` and `SquawkKit` get unit tests that run in CI.

## Open questions

None right now. Answered: bundle ID `com.tinypenguin.squawk`; sounds reuse the Lanata
alarm sounds.
