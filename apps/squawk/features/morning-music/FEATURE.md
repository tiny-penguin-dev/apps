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

## Design

Status: Draft

Builds on the approved steps design (`../steps/FEATURE.md`). Same cards, rows, sheets and
penguin. One new card (now playing) and two iOS-drawn pieces we don't control (the Apple
Music prompt and the AirPlay picker).

### Mockups

- Clickable mockup: `design/mockups/music.html` (Artifact link:
  https://claude.ai/artifact/28MT9ivrEnuwxPECRSJhXQ). Use the Small / Phone / Wide switch
  for other sizes.
- Screenshots: `design/screens/`.

### What changes

| Screen | Before | After | Screenshot |
|---|---|---|---|
| When you're up | Home things only | Music sits at the top with its cover and "Plays when you're up". A note says "I'm up" will open Squawk | [up](design/screens/up.png) |
| Add something (When you're up) | Home scene, Home control | Adds **Music** and **Music before you're up**, both Pro | [addup](design/screens/addup.png) |
| Edit alarm | When you're up card | Shows the music there. If you did the Home app setup, a small "Music before you're up · 6:50" card with Help | [edit](design/screens/edit.png) |
| Alarm ringing | "I'm up" stops the alarm | Same buttons. With music on, "I'm up" opens Squawk | [ring](design/screens/ring.png) |
| Good morning | Penguin, streak, Home chips | A now playing card with the cover, play/pause and a big **Play on HomePod** button, and music notes floating off the penguin | [morning](design/screens/morning.png) · [on HomePod](design/screens/morning-homepod.png) |

### New screens

| Screen | What's on it |
|---|---|
| Pick your morning music | Search Apple Music, Recently played as big covers, Your playlists as rows, Shuffle. One pick per alarm. Note: "It starts on this iPhone when you're up. Tap AirPlay on the good-morning screen to send it to a HomePod." ([music](design/screens/music.png)) |
| Apple Music access | iOS asks once, the first time you add music ([access](design/screens/access.png)) |
| No Apple Music | Friendly penguin, "Morning music uses Apple Music", Try Apple Music (Apple's own offer sheet) or Not now ([nomusic](design/screens/nomusic.png)) |
| Pick a speaker | The iOS AirPlay picker, opened by Play on HomePod ([airplay](design/screens/airplay.png)) |
| Music before you're up | Why it lives in the Home app, a time stepper (default 10 min before), and a yellow "One catch" card: it won't follow skips or changes ([hguide](design/screens/hguide.png)) |
| In the Home app | Four numbered steps with the exact time and days to enter, and Open the Home app ([hsteps](design/screens/hsteps.png)) |

### Motion and copy

- Good morning: the now playing card pops in after the penguin; the little equalizer bars
  bounce while it plays and flatten when paused; notes float up from the penguin.
- Picking a cover gives it an orange ring with a small spring.
- With Reduce Motion: no notes, no bouncing bars, the card fades in.
- Copy: "Pick your morning music", "Plays when you're up", "Play on HomePod",
  "On Kitchen HomePod", "Music before you're up", "One catch", "Show me how",
  "Open the Home app".

### Design system

- **Reused:** `ThingRow`, `ThingIcon`, cards, sheets, `StepCard`, the stepper, Pro tag,
  note box, `PenguinView`.
- **New:** `NowPlayingCard` (cover, title, where it plays, play/pause, AirPlay button
  wrapping Apple's route picker), `MusicCover` (artwork with a fallback tint) and the
  `music.note` and `homepod.fill` icons in the coral and ice tints.

### Sizes and accessibility

- **Small phones:** covers stay three across and shrink; the music list scrolls
  ([music-small](design/screens/music-small.png), [morning-small](design/screens/morning-small.png)).
- **Wide:** same readable column as the rest of Squawk ([morning-wide](design/screens/morning-wide.png)).
- **Dark mode:** [up-dark](design/screens/up-dark.png), [morning-dark](design/screens/morning-dark.png).
- **Dynamic Type:** at the largest sizes the play/pause and AirPlay buttons stack, and
  covers drop to two across.
- **VoiceOver:** the card reads "Now playing, Morning Mix, on this iPhone". The AirPlay
  button reads "Play on HomePod, choose a speaker". Covers read the playlist name and
  "selected". The equalizer and notes are hidden.

### Open questions for Gabriel

1. One playlist per alarm, or let people pick a different one per day later? (Draft: one.)
2. When you tap "Start my day", should the music keep playing? (Draft: yes, it keeps
   going until you stop it.)
