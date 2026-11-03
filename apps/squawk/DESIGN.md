# Squawk: design

Status: Approved 2026-10-31

Builds on `PRODUCT.md` (approved 2026-10-31, updated in this PR: one ring by default,
different times on some days, Pro pricing).

## Mockups

- Clickable mockups: `design/mockups/squawk.html` (Artifact link:
  https://claude.ai/artifact/LhcTL2qhZeKAhPKRZu5Prb)
- Screenshots: `design/screens/`

## Look

- **Feeling:** a bright, calm dawn. Soft sky background, one warm sunrise color for
  actions, a navy penguin.
- **Colors (light / dark):**
  - Background: pale dawn blue `#F4F7FF` / night navy `#11182E`
  - Cards: white `#FFFFFF` / `#1B2443`
  - Text: penguin navy `#1E2945` / `#EEF2FF`
  - Main color (buttons, links): sunrise orange `#FF8A4C` / `#FF9A5E`
  - Soft ring: sun yellow `#FFC24D`. Loud ring: coral `#FF5C63`. Done / on: mint `#2FBF96`
  - Ice blue `#DCE7FF` for the iceberg, chips and quiet fills
- **Type:** SF Pro Rounded everywhere. Black weight for times and titles, bold for
  labels. Times use tabular numbers so they don't jump.
- **Shapes:** big round corners (18 to 28 pt), pill buttons with a soft "pressable"
  bottom edge, round day buttons.
- **App icon:** Squawk facing you with big sparkly eyes, pink cheeks and its pointy squawk grin,
  flippers up, standing on snow under a soft blue sky with clouds. Pro icons use the same pose:
  Night (white penguin asleep under the moon), Mint (happy eyes) and Ice (pale sky). Sources and
  the script that draws them are in [design/icon](design/icon), preview in
  [all-icons.png](design/icon/all-icons.png).

## Screens

| # | Screen | What it's for | Screenshot |
|---|---|---|---|
| 1 | Hello | Squawk waddles in and waves. One button: "Let's go". | [01](design/screens/01-welcome.png) |
| 2 | Allow alarms | Why we need alarm permission, then the iOS prompt. "Not now" still works, with a reminder on Home. | [02](design/screens/02-permission.png) |
| 3 | Wake-up time | Big time picker and day buttons (weekdays preselected). "Set my alarm" finishes setup. | [03](design/screens/03-time.png) |
| 4 | Home | Sleeping penguin on an iceberg with "7h 40m of sleep". Alarm cards with time, schedule (`Mon–Thu 7:00 · Fri 7:30`), on/off and "Skip tomorrow". The + button adds an alarm. Fish streak chip at the top. | [04](design/screens/04-home.png), [dark](design/screens/04-home-dark.png) |
| 5 | Edit alarm | Time, days, **different times on some days**, rings (one by default, with "+ Soft ring before" and "+ Loud ring after"), "More options", label, skip next morning. | [05](design/screens/05-edit.png), [dark](design/screens/05-edit-dark.png) |
| 6 | More options (Pro) | Any number of rings (reorder, change time, sound, color, name) and wake-up checks. The math way out is always listed. | [06](design/screens/06-customize.png) |
| 7 | Squawk Pro | What Pro adds, yearly $29.99 or monthly $2.99 (launch price), one button. | [07](design/screens/07-pro.png) |
| 8 | Ringing | Drawn by iOS (AlarmKit). We set the title (alarm label), a tinted button, "Stop" or "Snooze", and the sound. | [08](design/screens/08-ring.png) |
| 9 | Wake-up check: tag | "Go scan your tag", where it is, a pulsing scan target, grumpy penguin, time left. Link to the math way out. | [09](design/screens/09-check.png) |
| 10 | Wake-up check: game | "How many penguins?" Pick the right number. Wrong answers shake, no penalty. | [10](design/screens/10-game.png) |
| 11 | Math way out | One multiplication (like 47 × 8) and a big keypad. | [11](design/screens/11-math.png) |
| 12 | Good morning | Penguin reaction, a line about how the morning went, the Today card (weather and first event, Pro, see [morning summary](features/morning-summary/FEATURE.md)) or the offer to add it, this week's dots and streak, fish confetti. | [12](design/screens/12-morning.png) |

Not drawn yet (simple, same style): Settings (sounds, Pro, help), the code-scan check
(camera view with a friendly frame), the "change next morning only" sheet, the widget,
and empty Home (no alarms: penguin awake holding a little alarm clock, "Add your first alarm").

## Flows

- **First launch** (PRODUCT 5.1): Hello → Allow alarms → Wake-up time → Home (confetti).
  Three taps for the default 7:00 weekday alarm.
- **Add or edit** (5.2): Home → tap a card → Edit alarm → Save. The + button goes to the
  time picker, then Edit.
  - **Different time on a day:** in Edit, "+ Different time on a day" → pick a day → set
    its time. Shows as a row (`Fri 7:30 AM ✕`). ✕ puts that day back on the normal time.
    The schedule line on Home groups days by time.
  - **Add a ring:** in Edit, "+ Soft ring before" (10 min before, Little peep) or "+ Loud
    ring after" (5 min after, Whole colony). Free alarms can have 2 rings; more is Pro.
- **Waking up** (5.3): Ringing → Stop (no check) → next ring later, or open the app →
  Good morning. With a check: Snooze → back in 30 s; open the app → check screen → done
  → Good morning. The way out: check screen → math → Good morning.
- **Pro**: any Pro row (badge `PRO`) → Squawk Pro.

## Mascot

Squawk is the Tiny Penguin logo turned to face you: a navy arch body (`#172239`) with
rounded bottom corners, a white belly window with the leg notch running to the bottom
edge, golden beak and feet (`#FFB020`), white eyes, and short flippers attached to its
sides. The beak is narrow with soft corners. When it squawks, the beak opens into a
pointy grin with a little tongue. Pink cheeks show only when it's proud. Every part is
a simple shape, so it can animate in SwiftUI. All the options we looked at are in
`design/mockups/penguins-front.html` (penguin 2 was picked).

| Mood | Looks | Where |
|---|---|---|
| Asleep | Closed eyes, orange nightcap, floating "z"s, slow breathing | Home when an alarm is on |
| Awake | Open eyes, little bounce | Home when no alarm is on, onboarding |
| Proud | Happy closed eyes, pink cheeks, flippers up, hopping | Good morning (first ring), Pro |
| Grumpy | Frowning brows | Wake-up check, Good morning after the last ring |
| Squawk! | Wide eyes, beak open in a pointy grin, flippers up, shaking | App icon idea, store screenshots |
| Faint | X eyes, flopped over | Good morning after the 10-minute cap |

Outfits (Pro and streak rewards): scarf, beanie, sunglasses, party hat.

## Motion

- **Springs everywhere:** screens slide in with a small overshoot; buttons squash on press.
- **Penguin:** breathes when idle, waddles in on Hello, waves, hops when proud. Sleeping
  "z"s float up.
- **Toggles** wobble when flipped. **Day buttons** shrink a bit on tap.
- **Ring timeline chips** pop in one after another.
- **Wake-up check:** rings pulse out from the scan target. Wrong answers shake.
- **Success:** fish confetti in four colors on setup and Good morning.
- **Haptics:** light tap on toggles and day buttons, success haptic on a finished check,
  error haptic on a wrong answer.
- **Sounds:** a tiny "peep" on finishing setup (respects silent mode).
- **Reduce Motion:** no waddle, hop or confetti. Screens fade instead of slide. The
  penguin still changes mood, so the meaning stays.

## Copy

- Hello: "Hi, I'm Squawk!" / "I'll get you out of bed. Gently first, and louder only if I
  need to." / **Let's go**
- Permission: "Can I ring like a real alarm?" / "Squawk rings on your lock screen, even on
  silent or in Focus. Your iPhone will ask you to allow alarms." / **Allow alarms**, Not now
- Permission denied (Home banner): "Alarms are off in Settings, so I can't ring. Turn them
  on in Settings > Squawk." / **Open Settings**
- Time: "When do you want to wake up?" / **Set my alarm**
- Home: "Good evening" (changes with time of day) / "7h 40m of sleep" / alarm off: "Off.
  Squawk will sleep in too."
- Edit: "Different times on some days", "+ Different time on a day", "Rings", "+ Soft ring
  before", "+ Loud ring after", "More options", "Skip next morning"
- Ringing: title is the alarm label; buttons **Stop** or **Snooze** (when a check is on).
- Check: "Go scan your tag" / "It's on the Bathroom mirror." / "Can't scan? Answer a math
  question"
- Game: "How many penguins?" / "Count carefully. Sleepy brains welcome."
- Math: "Quick one" / "Solve it to turn Squawk off."
- Good morning: "Rise and waddle!" / "Up at 7:05, on the last ring. Tomorrow, let's try
  the first one." / **Start my day**. First ring: "Up on the first ring!"
- Pro: "Squawk Pro" / "For mornings that need a bigger plan." / **Get Pro** / "Launch
  price. Renews automatically, cancel anytime."
- Errors: "I couldn't set this alarm. Try again, and if it keeps happening, restart your
  iPhone." No puns in errors.

## Accessibility

- **Dynamic Type:** all text scales; the big time shrinks less than labels but still
  grows. At the largest sizes, rows stack (label above value).
- **VoiceOver:** penguin images have mood labels ("Squawk the penguin, asleep"). Alarm
  cards read as "7:00 AM, Monday to Thursday, Friday 7:30, on". Time wheels are
  adjustable ("hour, 7, swipe up or down"). Day buttons read full day names.
- **Order:** title, main content, then the main button.
- **Contrast:** text and buttons meet WCAG AA in both themes; orange buttons use navy
  text in dark mode.
- **Reduce Motion:** see Motion.
- **Wake-up checks:** the penguin game has a VoiceOver version (it reads the count as a
  question with choices), and the math way out is always available.

## Open questions

None right now.
