# Squawk: Morning music

Your favorite playlist starts when you get up, and can play on your HomePod, so the
morning sounds like music instead of an alarm.

## Product

Status: Approved 2026-11-03 (Gabriel)

### The problem

Squawk can ring, turn on lights and run Home scenes, but it can't play music. Lots of
people like to wake up and have a playlist or the radio come on in the kitchen or
bedroom. Today they'd set that up in the Home app by hand, and it wouldn't know when they
skip a morning or change tomorrow's time.

### Who wants it

People with Apple Music, and often a HomePod. A smaller group, so it's tucked away next to
the other Home things.

### Basics or powerful

Powerful, and Pro like every Home step. The basic alarm doesn't change.

### What Apple allows, and its limits

We checked this first, because it shapes everything below.

- **An app can't make a Home automation that plays music.** Apps can only make
  automations that change devices (lights, plugs, blinds, scenes). "Play Audio" on a
  HomePod exists only in Apple's Home app, and it needs Apple Music.
- **An app can't pick the speaker by itself.** Only you can send music to a HomePod, by
  tapping the AirPlay button (or from Control Center).
- **An alarm can't play music.** AlarmKit only plays the alarm sounds built into Squawk,
  on the phone.

So "play my playlist on the kitchen HomePod at 6:45, before I'm up" can't be done by
Squawk alone. We offer two ways instead.

### How it works

**1. Music when you're up (the main way).** A new thing for "When you're up":

- Pick an Apple Music playlist (or album or station) for the alarm.
- When the morning ends (you tap "I'm up", finish the wake-up check, or open Squawk after
  the last ring), Squawk opens and starts the playlist.
- The good-morning screen shows what's playing with a big AirPlay button. One tap on
  "Play on HomePod" picks the speaker. If the phone is already on a HomePod or AirPlay
  speaker, it just keeps playing there.
- Skips and one-time changes just work, because it runs from the alarm itself.
- "I'm up" today stops the alarm without opening Squawk. With music on, it opens Squawk
  instead, since music can only start from the app.

**2. Music before you're up, in the Home app (for HomePod owners).** For people who want
the music to start at a set time, like 10 minutes before the alarm:

- A "Music on HomePod at a time" row explains that Apple only allows this in the Home app,
  then walks you through it in a few short screens: open the Home app, add an automation
  at 6:50 on these days, pick the HomePod, pick Play Audio and your playlist.
- Squawk shows the exact time and days to enter, and a button that opens the Home app.
- The catch: it's your automation, not Squawk's. If you skip a morning or change the
  alarm, the music still plays at the old time unless you change it in the Home app.
  Squawk says this plainly before you start.
- To check in Build: whether Squawk can find that automation and move or pause it for
  you. If it can, this way follows skips and changes too, and the catch goes away.

### What it changes

- "When you're up" gets a "Music" row in Add something.
- With music on, "I'm up" opens Squawk instead of staying on the lock screen.
- The good-morning screen gets a small "now playing" card with the AirPlay button.
- Squawk asks for Apple Music access the first time you pick a playlist.

### Scope

- **In this version:** music when you're up (Apple Music), the guided Home app setup.
- **Later:** a gentle volume fade-in, a different playlist per day, Spotify (needs the
  Spotify app open, so it's harder).
- **Never:** Squawk-made Home automations that play music (Apple doesn't allow it), or
  choosing the speaker for you.

### What we measure

| Metric | What it tells us |
|---|---|
| `step.added` (`kind`: `music`) | How often people add music (already counted per kind) |
| `music.played` (`airplay`: yes / no) | How often it plays, and how often it goes to a HomePod or other speaker |
| `music.failed` (`reason`) | When music couldn't start (no Apple Music, no access, offline) |
| `music.home_guide_finished` | Whether the Home app walkthrough is used and finished |

### Decisions

Approved by Gabriel (3 Nov 2026), with the draft's answers:

1. With music on, "I'm up" opens Squawk, since music can only start from the app.
2. Apple Music only for now. Spotify waits for later.
3. Pro, like the other Home things.
