# Squawk: wake-up steps and Home control

Rings become **steps**: moments before or after the wake-up time where Squawk can ring,
turn on lights or run a Home scene, so a morning can start gently 30 minutes early and
build up to the alarm.

## Product

Status: Approved 2026-11-01

### The problem

Squawk can only make noise. Heavy sleepers wake up much more easily when the room gets
light first, and many people already have smart lights. Today they'd need a separate
Home automation for every alarm, and it wouldn't know when they skip a morning, sleep
in on Saturday or change tomorrow's time.

### Who wants it

People with smart lights, plugs or blinds in the Home app. That's a smaller group, so it
stays one level down and never crowds the simple path.

### Basics or powerful

Powerful. The basic alarm doesn't change: one step, one ring, set in three taps.

### How it works

**An alarm is a list of steps.** Each step happens at a time relative to the wake-up time
("30 min before", "at wake-up time", "5 min after") and does one or more things:

| Thing a step can do | Example |
|---|---|
| **Ring** | Soft peep, Morning squawk, Whole colony (what rings do today) |
| **Lights** | Bedroom lamp on at 20%, warm white |
| **Scene** | Run the "Good morning" scene from the Home app |
| **Plugs and switches** | Turn on the coffee maker |
| **Blinds** | Open the bedroom blinds halfway |

An example morning:

| When | What happens |
|---|---|
| 6:30 (30 min before) | Bedroom lamp on at 10%, warm |
| 6:50 (10 min before) | Lamp to 50%, soft peep |
| **7:00 (wake-up time)** | Lamp to 100%, Morning squawk, scan the tag to turn it off |
| 7:05 (5 min after) | Whole colony, if you're still in bed |
| When you're up | Open the blinds, turn on the coffee maker |

- **Every alarm starts with one step** at the wake-up time that rings, exactly like today.
- **Quick adds** keep it easy: "+ Soft ring before" and "+ Loud ring after" (as today),
  plus "+ Sunrise", which adds three light steps that brighten the room over the
  30 minutes before you wake up.
- **"When you're up"** is a special step. It runs when the morning ends: you finish the
  wake-up check, tap "I'm up", or open Squawk after the last ring.
- **Wake-up checks stay with the wake-up time.** The check belongs to the alarm as a
  whole, and its rings keep coming back until it's done, as today. It shows inside the
  wake-up step so the whole morning reads top to bottom.
- **Skip and change once just work.** Skip tomorrow, and the lights stay off too. Change
  tomorrow to 6:00, and every step moves with it.

**How Home control works, and its limits:**

- Squawk sets up the steps as automations in your Home, named like "Squawk · Wake up ·
  6:30". Your Home hub (an Apple TV or HomePod) runs them, so lights come on even if the
  phone is asleep, silenced or out of battery.
- **Timed Home steps need a Home hub.** iOS doesn't let an app wake itself up at an exact
  time, and an alarm app's ring can't silently run code either. So without a hub,
  Squawk explains why and offers only "When you're up", which runs from the phone.
- The automations show up in the Home app. Squawk owns them: editing the alarm updates
  them, deleting it removes them. If you change one in the Home app, Squawk puts it back
  next time it syncs.
- "When you're up" runs from the phone, since it happens while you're using Squawk.
- Squawk asks for Home access the first time you add a Home step, not before.

### What it changes

- **Rings become steps** everywhere: the edit screen, More options, the Home screen's
  timeline chips. Existing alarms turn into steps with one ring each, with nothing lost.
- **Pro:** Home steps and "When you're up" are Pro, like the other powerful options.
  The free limit stays "2 rings per alarm", so free alarms work exactly as now.
- **The words:** "Ring" in PRODUCT.md section 4 becomes "Step" (a ring is one thing a
  step can do).
- **Planning ahead:** like alarms with wake-up checks, Home steps are planned a few
  mornings ahead and re-planned when you open the app.

### Scope

- **In this version:** steps, quick adds including Sunrise, rings, lights (on/off,
  brightness, warmth or color), Home scenes, plugs and switches, blinds, "When you're
  up", skip and change once.
- **Later:** music (play a playlist on a HomePod), thermostats, running a Shortcut, fading
  lights smoothly instead of in steps, steps based on sunrise time.
- **Never:** controlling devices outside the Home app, Squawk-made scenes that live on
  without an alarm.

### What we measure

| Metric | What it tells us |
|---|---|
| `step.added` (`kind`: ring / lights / scene / plug / blinds) | Which kinds of steps people use (replaces `alarm.ring_added`) |
| `step.sunrise_added` | Whether the Sunrise quick add is useful |
| `home.connected` (`hub`: yes / no) | How many people have a Home hub when they try this |
| `home.sync_failed` (`reason`) | Automations Squawk couldn't set up (goal: near zero) |
| `morning.up_actions` | How often "When you're up" runs |

### Decisions

Answered by Gabriel (1 Nov 2026):

1. Home steps and "When you're up" are Pro.
2. Wake-up checks stay one per alarm, shown in the wake-up step.
3. "When you're up" is in this version.
4. Timed Home steps need a Home hub. Without one, only "When you're up" is offered.

## Design

Status: Draft

Builds on the Product section above and on Squawk's approved `DESIGN.md`. Same look,
colors, type and penguin. Nothing new to learn: steps reuse the cards, chips and pill
buttons the app already has.

### Mockups

- Clickable mockup: `design/mockups/steps.html` (Artifact link:
  https://claude.ai/artifact/6GbKYZevRaBj3fagtxpnQL). Use the Small / Phone / Wide switch
  to see other screen sizes.
- Screenshots: `design/screens/`. "Before" screenshots are in Squawk's
  `design/screens/` (for example `05-edit.png`, `04-home.png`).

### What changes

| Screen | Before | After | Screenshot |
|---|---|---|---|
| Home | Ring chips under each alarm | Step chips show times with small icons (light, ring), so 6:30 💡 · 6:50 💡🔔 · 7:00 💡🔔 | [home](design/screens/home.png) |
| Edit alarm (new) | One ring, "+ Soft ring before", "+ Loud ring after" | Looks the same. One wake-up step that rings, plus the same two quick adds, then "+ Sunrise" and "+ Add a step" with a Pro tag | [edit-new](design/screens/edit-new.png) |
| Edit alarm (with steps) | List of rings | A timeline of step cards, top to bottom. The wake-up step has an orange outline and shows the check inside it. "When you're up" sits at the end as its own warm card | [edit](design/screens/edit.png) |
| More options | Rings section and checks | Rings section goes away (steps live on the edit screen). Checks stay | [customize](design/screens/customize.png) |
| Squawk Pro | Perks list | Perks become "As many steps and rings as you want" and "Lights, scenes and blinds in your morning" | [pro](design/screens/pro.png) |
| Good morning | Streak and "Start my day" | Shows what "When you're up" just did as chips (Blinds opening, Coffee maker on) | [morning](design/screens/morning.png) |

### New screens

| Screen | What it's for | Screenshot |
|---|---|---|
| A step | The step's time (− / + in 5 minute steps, shows "10 min before") and what happens, each with Change and ✕. "+ Add something" and "Remove step". The wake-up step can't be removed and always rings | [stepdetail](design/screens/stepdetail.png) |
| Add something | A sheet: Ring, Lights, Scene, Plug or switch, Blinds. Home kinds have a Pro tag for free users | [addthing](design/screens/addthing.png) |
| Home access | First time you add a Home thing. Squawk in a warm glow explains the automations ("Squawk · Wake up · 6:30") and that the hub runs them. "Connect to Home" opens the iOS prompt | [homeaccess](design/screens/homeaccess.png) |
| Pick a light | Brightness and color sliders with a live glow preview, then lights grouped by room. Pick several to set them together | [light](design/screens/light.png) |
| When you're up | What runs when the morning ends, with a note that it works without a hub | [up](design/screens/up.png) |
| No Home hub | Shown instead of Home access when there's no hub. Explains why in plain words and offers "When you're up" instead | [nohub](design/screens/nohub.png) |
| After "+ Sunrise" | Three light steps at 30, 20 and 10 minutes before, getting brighter | [sunrise](design/screens/sunrise.png) |

### Motion and copy

- Adding a step slides its card into the timeline at the right time; the connecting
  line grows to meet it. Removing one shrinks it out.
- "+ Sunrise" adds its three steps one after another with a little sunrise shimmer.
- The light glow on "Pick a light" follows the sliders as you drag.
- Times are always shown both ways: "6:50" and "10 min before".
- Copy keeps the penguin voice but stays plain about Home: "Squawk can turn on your
  lights", "This needs a Home hub".

### Design system

- **Reused:** cards, chips, pill buttons, dashed "+" buttons, Pro tag, section labels,
  the note box, sheets, the penguin.
- **New, built once in the app's design system:**
  - `StepCard`: time, offset label, list of things; highlighted style for the wake-up step.
  - `StepTimeline`: stacks step cards with the connecting line and time dots.
  - `ThingRow`: small colored icon (ring, light, scene, plug, blinds, check), name,
    detail, optional Change and ✕.
  - `OffsetStepper`: − / + time control.
  - `LightPreview`: the glow that reacts to brightness and color.
- **Icon colors:** ring uses sunrise orange, lights sun yellow, scene ice blue, plugs and
  blinds penguin navy on ice, checks mint. All from the existing palette.

### Sizes and accessibility

- **Small phones (SE):** step cards stack the things under the time instead of beside it
  ([edit-small](design/screens/edit-small.png)).
- **Wide (iPhone Duo open, resizing):** the timeline gets wider with room for full
  detail text ([edit-wide](design/screens/edit-wide.png)). Step detail opens beside the
  timeline when there's room.
- **Dynamic Type:** cards grow taller; times and things never get cut off.
- **VoiceOver:** each step reads as one item, like "6:50, 10 minutes before. Bedroom lamp
  50 percent, warm. Little peep." Icons are never the only signal; every thing has a name.
- **Dark mode:** same tokens as the rest of the app.

### Open questions

1. Should "+ Sunrise" pick the light for you (the first dimmable one), or always ask?
   The mockup asks the first time and remembers it.
2. Is 5 minutes the right step size for the time stepper, or should it go by 1 minute?
