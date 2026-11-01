# Squawk: product definition

Status: Approved 2026-10-31

Squawk is a wake-up alarm for people who don't wake up on the first ring. It starts as one
simple alarm. When you need more, add extra rings to the same alarm: a soft one before,
a loud one after if you're still in bed. A little penguin named Squawk runs the show.

Easy by default. Powerful when you want it.

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

**Main user: heavy sleepers and snoozers who don't get out of bed easily.** People who
set several alarms today, sleep through a single one, or snooze for 30 minutes without
meaning to.

Also for:
- Anyone who wants a happier wake-up: soft sound first, loud only if needed, lights
  coming on, a penguin saying good morning.
- Tinkerers who want to tune every detail (sounds, timing, "prove you're awake" checks).

Not for (now): sleep tracking fans, people who want bedtime stories or sleep sounds.

## 2b. What makes it different

- **A plan, not five alarms.** One alarm can hold extra rings, so you don't set five.
- **One alarm, different times per day.** Weekdays at 7:00 but Friday at 7:30 is still one
  alarm. No copying the whole setup to change a time.
- **As reliable as the Clock app.** AlarmKit lets it ring through silent mode and Focus.
- **Fun instead of punishment.** A penguin who cheers you on, instead of grey puzzle screens and ads.
- **The penguin twist:** the app is named after the sound a penguin makes, the sounds go
  from a tiny peep to a full colony squawk, and Squawk the penguin reacts to every morning.

## 3. Principles

1. **One tap to a good alarm.** A new alarm is one ring at the time you pick. Extra rings
   are a choice, never a default.
2. **Reliable first, cute second.** It must ring every time. Fun never gets in the way of
   that.
3. **Power stays hidden until asked.** Advanced options live one level down, behind
   "Customize". The main screen never gets crowded.
4. **Encouraging, not punishing.** Squawk cheers you on. Even the hard mode feels like a
   game, not a fine.
5. **Your data stays yours.** No account, no server. Everything lives on the phone.
   iCloud sync only if it turns out we need it (for example, to keep alarms after
   switching phones).
6. **Built to grow.** v1 is small, but the pieces are made so new checks, actions and
   conditions can be added without redoing the app (see "Built to grow").

## 4. Key ideas (the words we use)

| Word | What it means |
|---|---|
| **Alarm** | A wake-up time, the days it repeats, and its rings. Can also be one-time (a single date). |
| **Day time** | A different wake-up time for some days of the same alarm (Friday 7:30 while the rest is 7:00). Everything else is shared. |
| **Ring** | One ring of the alarm. Every alarm has one. Extra rings sit before or after the wake-up time ("10 min before"), each with its own sound and color. |
| **Wake-up check** | Something you must do to fully turn off the alarm, like scanning the tag on your bathroom mirror. Until you do it, the last ring keeps coming back. |
| **Skip / change once** | Change only the next morning (sleep in Saturday, earlier flight Tuesday) without editing the alarm. |

Rings don't have names by default. They show their time and sound ("6:50 · Little peep").
A name can be added if someone wants one.

## 5. Core flows

### 5.1 First launch
1. Squawk the penguin waddles in and says hi.
2. One screen explains why we need alarm permission (AlarmKit), then asks.
3. "When do you want to wake up?" Big time wheel. Pick days (weekdays preselected).
4. Done. Home screen shows the alarm, and the penguin settles down to sleep.

Goal: a working alarm in **under 30 seconds**.

### 5.2 Add or edit an alarm (basic)
- Time, days (or a single date), sound, on/off. That's all on the main edit screen.
- **Different time on some days:** tap "Different times on some days", pick the days, set
  their time. The alarm shows it plainly: `Mon–Thu 7:00 · Fri 7:30`. Rings, sound and
  checks stay shared, so changing them once changes every day.
- **Add a ring:** one tap adds a ring 10 minutes before (soft) or 5 minutes after (loud).
  The alarm then shows a small timeline: `6:50 · 7:00 · 7:05`.
- A "More options" row opens the powerful options (5.4).

### 5.3 Waking up
1. The first ring goes off. It's a real full-screen alarm on the lock screen, even in silent mode or
   Focus. Tapping Stop silences this ring only. The next ring still comes.
2. If you open the app (or tap "I'm up"), the rest of the plan is cancelled for today.
3. Opening the app in the morning shows Squawk reacting: proud if you got up early,
   sleepy-grumpy if it took the last ring.
4. With a wake-up check on, the last ring keeps coming back every 30 seconds (for up to 10
   minutes) until you complete the check.

### 5.4 More options (powerful)
- Any number of rings. Change each ring's time, sound, color and name.
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
| Penguin game | A quick tap game with Squawk (catch the fish, count the penguins). Wakes up your brain. | v1 |
| Run a Shortcut | Use the "Turn off Squawk" action in any Shortcut or automation. | later |
| Walk it off | Take a number of steps. | later |

There's always an emergency way out: solve a math question (like 47 × 8) to turn it off.
It takes real thinking, so it wakes you up too. The 10-minute cap also still applies, so
nobody is ever stuck with a ringing phone.

## 6. Basics vs powerful features

| Basics (free) | Powerful (Pro subscription) |
|---|---|
| Unlimited alarms, repeat days or one date | Any number of rings |
| Different times on some days | Wake-up checks |
| Up to 2 rings per alarm | All sounds, colors and ring names |
| Default sounds | |
| Skip next morning | Change next morning only (new time) |
| Penguin reactions and streaks | Extra penguin outfits and app icons |
| | Later: app blocking, "only when home", morning actions |

**Pro pricing (auto-renewing subscription):**

| | Launch price | Later |
|---|---|---|
| Monthly | $2.99 | $4.99 |
| Yearly | $29.99 | $49.99 |

The launch price is an introductory offer for early users.

The basics must be a complete, good alarm on their own. Pro is for people who want more,
not a paywall on reliability.

## 7. The penguin twist (look and feel)

- **Squawk the penguin** lives on the home screen. Asleep when an alarm is set (with a
  little "7h 40m of sleep" bubble), awake and stretching after you get up.
- **Reactions** after each morning: proud (up on the first ring), fine, grumpy (needed the
  last ring), dramatic faint (hit the 10-minute cap).
- **Streaks**: "5 mornings up on the first ring" with small rewards (outfits: scarf,
  beanie, sunglasses).
- **Sounds**: a mix of friendly tones and penguin-ish sounds, from a soft peep to a full
  colony squawk. All bundled as mp3 (AlarmKit needs that).
- **Animation everywhere it's cheap**: toggles that wobble, a timeline that waddles in,
  confetti of fish when you finish a wake-up check.
- **Copy tone**: short, warm, a bit silly. "Rise and waddle." "Up on the first ring!"
- Shared Tiny Penguin look and voice come from [`docs/brand.md`](../../docs/brand.md).

## 8. Platform and AlarmKit limits

These shape the design, so they're listed here, not just in the build doc.

- **iOS 26 or later**, iPhone only to start. Apple Watch later.
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
- Different times on some days fit AlarmKit well: each group of days with the same time
  becomes one weekly repeating alarm per ring.
- App blocking (later) needs Apple's Screen Time permission and a special entitlement.

## 8b. Built to grow

v1 ships few features, but its shape must make the later ones easy. Like Lanata's
Morning model, these are open lists, so adding a new kind is adding one case, not a redesign:

- **Wake-up checks** (tag, code, game; later Shortcut, steps).
- **Actions** when the alarm starts or ends (later HomeKit lights, music, Shortcut).
- **Conditions** for whether an alarm rings at all (later "only when home").
- **Storage** sits behind one layer, so iCloud sync can be added without touching screens.
- **Pro** is checked in one place, so moving a feature between free and Pro is one change.
- One piece owns turning saved alarms into AlarmKit alarms, so every feature uses the
  same reliable path.

The build doc turns this into the real structure.

## 9. Scope

### v1
- Alarms: time, days or single date, on/off, labels.
- One ring by default, extra rings when you want them.
- Different times on some days, inside one alarm.
- Skip / change next morning only.
- Wake-up checks: scan a tag, scan a code, penguin game.
- Penguin home screen, reactions, streaks.
- Widget showing the next alarm.
- Everything stored on the phone, no account.
- Free basics + Pro subscription.

### Later
- "Only ring when I'm home" (location).
- App blocking during the morning (Screen Time).
- Morning actions: turn on lights with HomeKit (next version), start music, run a Shortcut.
- iCloud sync, if people need it.
- Shortcut and step-count wake-up checks.
- Apple Watch app.
- Morning summary (weather, first calendar event) after you get up.

### Never
- Sleep tracking, sleep sounds, bedtime stories.
- Social features, sharing alarms with friends.
- Android.
- Ads.

## 10. What success looks like

- First alarm set in under 30 seconds for most new users.
- Zero missed alarms that are our fault (we track scheduling errors on device).
- Most mornings end before the last ring (people actually get up earlier).
- People keep using it: still active after 30 days.
- Reviews mention "cute" and "it actually wakes me up".

## 10b. What we measure

Anonymous counts only, sent to Sentry (see `docs/telemetry.md`). No names, labels or
anything typed. People can turn this off in Settings.

| Metric | What it tells us |
|---|---|
| `onboarding.finished` (duration) | How long first setup takes (goal: under 30 seconds) |
| `alarm.created` (`kind`: repeat / once) | How many alarms people make |
| `alarm.deleted` | Alarms people give up on |
| `alarm.schedule_failed` | AlarmKit refused a ring (goal: zero) |
| `alarms.total` (gauge) | How many alarms people keep |
| `alarm.ring_added` (`kind`: soft / loud / custom) | Whether people use extra rings, and which |
| `morning.changed` (`kind`: skip / time) | How often people skip or move just the next morning |
| `morning.up` (`from`: app / button) | How mornings end early: opening the app or tapping "I'm up" |

More get added here as phases land (rings, checks, mornings, Pro).

## 11. Open questions

1. Do people who subscribe at the launch price keep it after prices go up?

Answered (31 Oct 2026): heavy sleepers plus anyone who wants a happier wake-up; free
basics with a Pro subscription; on-device, no account, iCloud only if needed; mascot
named Squawk; v1 scope as above, built to grow; iPhone only to start; HomeKit lights in
the next version; emergency exit is a math question; one ring by default, extra rings
are a choice; different times per day inside one alarm; Pro pricing in section 6.

## 12. Where the ideas came from

Squawk adapts the morning alarm in Lanata (`lanata-server`, the "Morning" feature in the
iOS app) for normal people:

| Lanata | Squawk |
|---|---|
| Separate morning per schedule | One alarm with different times on some days |
| Morning with phases (offset, sound, color) | Alarm with one ring, plus extra rings if wanted |
| Dismiss conditions (NFC tag, Shortcut) | Wake-up checks, plus code scan and a penguin game |
| Last phase repeats every 30s for 10 min | Same, with friendlier labels and an emergency exit |
| One-off overrides from the server | "Skip / change next morning", stored on device |
| Start condition: location zone | "Only when home" (later) |
| App block window around the alarm | App blocking (later, Pro) |
| Webhook actions on start / dismiss | Morning actions via HomeKit / Shortcuts (later) |
| Server-synced, user accounts | On-device, no account (iCloud later if needed) |
