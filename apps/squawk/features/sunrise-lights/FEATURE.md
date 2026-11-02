# Squawk: Sunrise lights

A step that slowly brightens your lights and warms them toward daylight before the alarm,
with the length, brightness and color all up to you.

## Product

Status: Approved 2026-11-02 (Gabriel, decision card)

### The problem

Today "+ Sunrise" adds four separate light steps (10%, 40%, 80%, 100% at 30, 20 and 10
minutes before, and at wake-up). The room jumps in big steps, the timeline fills up with
light cards, and there's no way to say "make it 45 minutes" or "stay warm the whole time"
without editing each step by hand.

### Who wants it

The same people as Home steps: people with smart lights and a Home hub. Pro, like every
Home step.

### Basics or powerful

Powerful. It lives one level down, next to the other Home things.

### How it works

- **Sunrise lights is a new thing a step can do**, next to Ring, Lights, Scene, Plug and
  Blinds. It starts at the step's time and runs for its length.
- **You choose:**
  - **Length:** 5 to 60 minutes, in 5 minute jumps. Default 30.
  - **Brightness:** start and end, 1 to 100%. Default 5% to 100%.
  - **Color:** start and end, from warm to daylight. Default warm to near daylight.
  - **Which lights:** one or several, like the Lights step.
- **"+ Sunrise lights"** (the quick add, renamed from "+ Sunrise") opens the same screen and
  places the sunrise so it **ends at your wake-up time**. Change the length and the start
  moves with it.
- **On the timeline** it's one card: "6:30 · Bedroom lamp · 30 min · 5% → 100%" with a
  little rising bar strip, instead of three or four light cards.
- **Moving the step moves the whole sunrise.** Skip a morning or change it once, and the
  sunrise follows, like every other step.
- **The guided setup's "Sunrise" answer** now makes one Sunrise lights step (30 minutes,
  ending at wake-up) instead of four light steps.
- Brightness rises slowly at first and faster near the end, which feels closer to a real
  sunrise than a straight line.

### How it works in HomeKit, and its limits

HomeKit has no "fade over 30 minutes" command for apps. An automation can only set a light
to a value at a time. So Squawk spreads the sunrise into **small timed changes**: up to
10 changes over the length (a 30 minute sunrise changes every 3 minutes, a 10 minute one
every minute). Each change is a Home automation run by the hub, like today's light steps.

What that means for people:

- **It brightens in small steps, not perfectly smoothly.** Most lights soften each change a
  little on their own, so it reads as a slow glow, but you can catch a jump if you watch.
- **More automations in the Home app.** One sunrise is about 11 "Squawk · …" automations per
  day group (more for days with a one-time change, which are planned a few weeks ahead).
  They're still Squawk's: it keeps them in sync and removes them when the alarm goes.
- **Lights without color** only get brighter; **on/off lights** just turn on at the start.
- **Needs a Home hub**, like every timed Home step.

### What it changes

- "+ Sunrise" becomes "+ Sunrise lights" and makes one step instead of four.
- Alarms that already have the old four sunrise steps keep them as they are. Nothing is
  converted.
- The Add something sheet gets a "Sunrise lights" row.

### Scope

- **In this version:** the Sunrise lights step, the quick add, the guide answer.
- **Later:** a sunrise that follows the real sunrise time, a "sunset" for bedtime, smoother
  fades if Apple adds them for apps.
- **Never:** controlling lights outside the Home app.

### What we measure

| Metric | What it tells us |
|---|---|
| `step.added` (`kind`: `sunrise`) | How often people add Sunrise lights (already counted per kind) |
| `step.sunrise_added` (`minutes`) | Whether the quick add is used, and which lengths people pick |
| `home.sync_failed` (`reason`) | Watch that the extra automations don't cause sync failures |

### Decisions

- Quick add ends the sunrise at wake-up; added from a step, it starts at that step.
- Up to 10 light changes per sunrise, to keep the Home app from filling up.

## Design

Status: Approved 2026-11-02 (Gabriel, decision card)

Builds on the approved steps design (`../steps/FEATURE.md`). Same cards, sliders and
icons; one new icon and one new small component.

### Mockups

- Clickable mockup: `design/mockups/sunrise.html` (Artifact link:
  https://claude.ai/artifact/3grK2NCtHWNcuUsSLp9nX4). Use the Small / Phone / Wide switch
  for other sizes. "Preview" on the Sunrise lights screen plays the sunrise.
- Screenshots: `design/screens/`.

### What changes

| Screen | Before | After | Screenshot |
|---|---|---|---|
| Edit alarm | "+ Sunrise" adds three or four light step cards | "+ Sunrise lights" adds one card with a rising bar strip | [before](../steps/design/screens/sunrise.png) · [after](design/screens/edit.png) |
| A step | Light rows with Change | Sunrise lights row with Change, its bar strip and "starts 6:30 · bright by 7:00" | [stepdetail](design/screens/stepdetail.png) |
| Add something | Ring, Lights, Scene, Plug or switch, Blinds | Ring, Sunrise lights, Home scene, and one "Home control" row for lights, plugs and blinds. Picking any device shows the settings for that kind (Gabriel, 2 Nov 2026) | [addthing](design/screens/addthing.png) |
| Guide, lights question | "Sunrise" with three time chips | "Sunrise lights" with the bar strip and start/end times | [g3](design/screens/g3.png) |
| Home | Chips show each light step | One sunrise chip at its start time | [home](design/screens/home.png) |

### New screen: Sunrise lights

| Part | What it does |
|---|---|
| Preview | A small sky and lamp glow. "Preview" plays the whole sunrise in a few seconds with the clock and brightness ticking |
| Length | − / + in 5 minute jumps, with "6:30 → 7:00 · ends at wake-up" under it |
| Bar strip | One bar per light change, as tall as its brightness and tinted its color, so you see what the hub will do |
| Brightness | Start and End sliders side by side |
| Color | Start and End sliders, warm to daylight |
| Lights | Grouped by room, pick several, same as Pick a light |
| Note | "Your Home hub changes the lights every 3 min, in small steps. Lights without color only get brighter." |

Screenshots: [sunrise](design/screens/sunrise.png), [small](design/screens/sunrise-small.png).

### Motion and copy

- Saving slides the card into the timeline with a soft sun shimmer.
- The bar strip springs to new heights as you drag the sliders; the glow follows.
- Preview respects Reduce Motion (jumps straight to the end).
- Copy: "Sunrise lights", "ends at wake-up", "bright by 7:00", "11 light changes".

### Design system

- **Reused:** `StepCard`, `ThingRow`, `ThingIcon`, `OffsetStepper` style, `LightGlow`,
  sliders, cards, Pro tag.
- **New:** `SunriseBars` (the bar strip, from the same ramp the planner uses) and the
  `sunrise.fill` icon, tinted sun to sunrise orange.

### Sizes and accessibility

- **Small phones:** the start/end sliders stay side by side; the bar strip shrinks.
- **Wide:** same readable width as the rest of the edit screens
  ([edit-wide](design/screens/edit-wide.png)).
- **Dynamic Type:** at the largest sizes the start/end sliders stack.
- **VoiceOver:** the row reads "Sunrise lights, Bedroom lamp, 30 minutes, 5 to 100
  percent, warm to daylight". Each slider says "Start brightness" or "End color". The bar
  strip is hidden; the text says the same.

## Build

Status: Approved 2026-11-02 (Gabriel, decision card)

### Approach

- **Core (`SquawkKit`):** a new `HomeAction.Kind.sunrise` with a `Sunrise` value on the
  action (length, start/end brightness, start/end warmth). `Sunrise.points` turns it into
  the light changes (minute offset and `HomeSetting` each, up to 10 changes, brightness
  eased in). `Alarm.addSunrise(lights:sunrise:)` places it to end at wake-up.
- **Planning:** `Alarm.homeSteps` spreads each sunrise into its light changes and groups
  everything by minute, so a change that lands on another Home step shares its
  automation. `HomePlanner` plans from `homeSteps` instead of `steps`; the rest (weekly,
  changed days, skips, past midnight) is unchanged. `HomeSync` needs no change.
- **UI:** `HomeThingEditor` gets the sunrise settings for `.sunrise`; the quick add and
  the Add something sheet use it. `SunriseBars` draws the strip.
- Old saved alarms load unchanged (the new field is optional).

### Phases

One PR: core with tests, then the screen, quick add, guide and docs.

### Testing

- `swift test`: points (count, end values, easing, short lengths), `homeSteps` grouping,
  planner output for a sunrise (weekly and changed days), old alarms decoding.
- On a phone from TestFlight: add Sunrise lights, check the automations in the Home app,
  watch it run, change the length and check they update.

### Last step

Fold Sunrise lights into Squawk's `PRODUCT.md`, `DESIGN.md` and `CLAUDE.md`.
