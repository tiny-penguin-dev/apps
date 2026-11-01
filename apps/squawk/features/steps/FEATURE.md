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
