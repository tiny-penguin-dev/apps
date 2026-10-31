# Squawk: product definition

Status: Draft

Squawk is a wake-up alarm for people who don't wake up on the first ring. Instead of one
alarm, you get a short wake-up plan: a soft peep, then a real squawk, then a very loud
SQUAWK if you're still in bed. A little penguin named Squawk runs the show.

Easy by default. Powerful when you want it.

> Guesses marked **(assumed)** are waiting on Gabriel's answers. See "Open questions".

## 1. The problem

- Most alarm apps give you one alarm. Heavy sleepers fake a plan by setting five alarms
  (6:50, 6:55, 7:00, 7:05...), which is messy to set up and messy to turn off.
- Snooze is too easy. You hit it half asleep and don't remember doing it.
- The apps that do fix this (wake-up challenges, puzzles) feel like punishment. They're
  grey, stressful and full of ads.
- The Clock app is reliable but plain. Third-party alarms used to be unreliable on iPhone
  because they couldn't ring through silent mode. AlarmKit (iOS 26) fixes that, so now
  a third-party alarm can be as reliable as the Clock app.

## 2. Who it's for

**Main user (assumed): heavy sleepers and snoozers.** People who set several alarms today,
sleep through a single one, or snooze for 30 minutes without meaning to.

Also for:
- People who want a gentler start (soft sound first, loud only if needed).
- Tinkerers who want to tune every detail (sounds, timing, "prove you're awake" steps).

Not for (now): sleep tracking fans, people who want bedtime stories or sleep sounds.

## 3. Principles

1. **One tap to a good alarm.** A new alarm already has a smart wake-up plan. You only
   pick the time.
2. **Reliable first, cute second.** It must ring every time. Fun never gets in the way of
   that.
3. **Power stays hidden until asked.** Advanced options live one level down, behind
   "Customize". The main screen never gets crowded.
4. **Encouraging, not punishing.** Squawk cheers you on. Even the hard mode feels like a
   game, not a fine.
5. **Your data stays yours.** No account, no server. Everything is on the phone, synced
   with iCloud **(assumed)**.

## 4. Key ideas (the words we use)

| Word | What it means |
|---|---|
| **Alarm** | A wake-up time, the days it repeats, and its wake-up plan. Can also be one-time (a single date). |
| **Wake-up plan** | The list of steps for one alarm. |
| **Step** | One ring in the plan. Has a time relative to the wake-up time (like "10 min before"), a sound, a color and a name. |
| **Wake-up style** | A ready-made plan you pick from: Gentle, Nudge, Heavy sleeper. |
| **Wake-up check** | Something you must do to fully turn off the alarm, like scanning the tag on your bathroom mirror. Until you do it, the last step keeps coming back. |
| **Skip / change once** | Change only the next morning (sleep in Saturday, earlier flight Tuesday) without editing the alarm. |

Naming idea for steps that fits the penguin: **Peep** (soft), **Squawk** (normal),
**SQUAWK!** (loud). These are the default step names.

## 5. Core flows

### 5.1 First launch
1. Squawk the penguin waddles in and says hi.
2. One screen explains why we need alarm permission (AlarmKit), then asks.
3. "When do you want to wake up?" Big time wheel. Pick days (weekdays preselected).
4. "How hard is it to wake you up?" Pick a wake-up style (Nudge preselected).
5. Done. Home screen shows the alarm, and the penguin settles down to sleep.

Goal: a working alarm in **under 30 seconds**.

### 5.2 Add or edit an alarm (basic)
- Time, days (or a single date), wake-up style, on/off. That's all on the main edit screen.
- A preview of the plan as a small timeline: `6:50 Peep · 7:00 Squawk · 7:05 SQUAWK!`
- A "Customize" button opens the powerful options (5.4).

### 5.3 Waking up
1. Step 1 rings. It's a real full-screen alarm on the lock screen, even in silent mode or
   Focus. Tapping Stop silences this step only. The next step still comes.
2. If you open the app (or tap "I'm up"), the rest of the plan is cancelled for today.
3. Opening the app in the morning shows Squawk reacting: proud if you got up early,
   sleepy-grumpy if you made it to the loud step.
4. With a wake-up check on, the last step keeps ringing every 30 seconds (for up to 10
   minutes) until you complete the check.

### 5.4 Customize (powerful)
- Add, remove or reorder steps. Change each step's time, sound, color, name.
- Loop the sound or play it once.
- Add a wake-up check (5.5).
- Skip or change the next morning only.
- Run actions when the alarm starts or ends (later, see scope).

### 5.5 Wake-up checks
Pick one or more. When there are several, you must do all of them.

| Check | How it works | Version |
|---|---|---|
| Scan a tag | Tap your phone on an NFC sticker you placed somewhere far from bed. | v1 |
| Scan a code | Scan any QR code or barcode you picked (your coffee bag, a toothpaste tube). Works on every iPhone, no sticker needed. | v1 |
| Penguin game | A quick tap game with Squawk (catch the fish, count the penguins). Wakes up your brain. | v1 **(assumed)** |
| Run a Shortcut | Use the "Turn off Squawk" action in any Shortcut or automation. | later |
| Walk it off | Take a number of steps. | later |

There's always an emergency way out (for example: type a long sentence, or a 10-minute
cap), so nobody is ever stuck with a ringing phone.

## 6. Basics vs powerful features

| Basics (free) | Powerful (Pro, assumed) |
|---|---|
| Unlimited alarms, repeat days or one date | Fully custom steps (any number, any timing) |
| 3 wake-up styles | Wake-up checks |
| Default sounds | All sounds, colors and step names |
| Skip next morning | Change next morning only (new time) |
| Penguin reactions and streaks | Extra penguin outfits and app icons |
| | Later: app blocking, "only when home", morning actions |

The basics must be a complete, good alarm on their own. Pro is for people who want more,
not a paywall on reliability.

## 7. The penguin twist (look and feel)

- **Squawk the penguin** lives on the home screen. Asleep when an alarm is set (with a
  little "7h 40m of sleep" bubble), awake and stretching after you get up.
- **Reactions** after each morning: proud (up on the first peep), fine, grumpy (needed the
  loud step), dramatic faint (hit the 10-minute cap).
- **Streaks**: "5 mornings up on the first peep" with small rewards (outfits: scarf,
  beanie, sunglasses).
- **Sounds**: a mix of friendly tones and penguin-ish sounds, from a soft peep to a full
  colony squawk. All bundled as mp3 (AlarmKit needs that).
- **Animation everywhere it's cheap**: toggles that wobble, a timeline that waddles in,
  confetti of fish when you finish a wake-up check.
- **Copy tone**: short, warm, a bit silly. "Rise and waddle." "You beat the peep!"
- Shared Tiny Penguin look comes from `docs/brand.md` (being written in the workflow work).

## 8. Platform and AlarmKit limits

These shape the design, so they're listed here, not just in the build doc.

- **iOS 26 or later**, iPhone first **(assumed)**. Apple Watch later.
- The person must allow alarms (system permission). If they say no, we can't ring
  reliably, so the app explains this clearly and shows a fix.
- **The ringing screen is drawn by iOS, not by us.** We control the title, the button
  labels, one tint color and the sound. No custom animation on the ringing screen. All the
  fun lives in the app, widgets and Live Activities.
- **Wake-up checks can't happen on the lock screen.** The person has to open Squawk to do
  them. So "Stop" on the ringing screen only silences that ring, and the alarm comes back
  every 30 seconds. We label that button "Snooze" in that case so it's honest.
- **Custom sounds must be bundled mp3 files.** Anything else silently falls back to the
  default sound. Sounds are about 30 seconds long.
- Alarms with wake-up checks are scheduled one morning at a time, so the app has to
  re-plan the next morning after each one. If the phone is off for a few days, those
  alarms might not be set. We should plan a few mornings ahead to be safe.
- App blocking (later) needs Apple's Screen Time permission and a special entitlement.

## 9. Scope

### v1
- Alarms: time, days or single date, on/off, labels.
- Wake-up styles and fully custom steps.
- Skip / change next morning only.
- Wake-up checks: scan a tag, scan a code, penguin game.
- Penguin home screen, reactions, streaks.
- Widget showing the next alarm.
- iCloud sync between your devices.
- Free + Pro (one-time or subscription, see open questions).

### Later
- "Only ring when I'm home" (location).
- App blocking during the morning (Screen Time).
- Morning actions: turn on lights (HomeKit), start music, run a Shortcut.
- Shortcut and step-count wake-up checks.
- Apple Watch app.
- Morning summary (weather, first calendar event) after you get up.

### Not doing
- Sleep tracking, sleep sounds, bedtime stories.
- Social features, sharing alarms with friends.
- Android.
- Ads.

## 10. What success looks like

- First alarm set in under 30 seconds for most new users.
- Zero missed alarms that are our fault (we track scheduling errors on device).
- Most mornings end before the last step (people actually get up earlier).
- People keep using it: still active after 30 days.
- Reviews mention "cute" and "it actually wakes me up".

## 11. Open questions

1. Main audience: heavy sleepers vs "better mornings" crowd? (assumed heavy sleepers)
2. Pricing: free + Pro, and is Pro a one-time purchase or a subscription?
3. No account, iCloud only? (assumed yes)
4. Is the mascot called Squawk, same as the app? (assumed yes)
5. v1 scope: are wake-up checks in v1, and app blocking / location later? (assumed yes)
6. iPhone only for v1? (assumed yes)
7. Emergency way out of a wake-up check: what should it be?
8. Step names: keep Peep / Squawk / SQUAWK! or let people name them from the start?

## 12. Where the ideas came from

Squawk adapts the morning alarm in Lanata (`lanata-server`, the "Morning" feature in the
iOS app) for normal people:

| Lanata | Squawk |
|---|---|
| Morning with phases (offset, sound, color) | Alarm with a wake-up plan made of steps |
| Dismiss conditions (NFC tag, Shortcut) | Wake-up checks, plus code scan and a penguin game |
| Last phase repeats every 30s for 10 min | Same, with friendlier labels and an emergency exit |
| One-off overrides from the server | "Skip / change next morning", stored on device |
| Start condition: location zone | "Only when home" (later) |
| App block window around the alarm | App blocking (later, Pro) |
| Webhook actions on start / dismiss | Morning actions via HomeKit / Shortcuts (later) |
| Server-synced, user accounts | On-device, iCloud sync, no account |
