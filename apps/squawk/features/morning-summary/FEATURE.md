# Squawk: Morning summary

The Good morning screen also shows today's weather and your first calendar event, so the
first thing you see after getting up tells you what the day looks like.

## Product

Status: Approved 2026-11-03 (Gabriel, in the project thread)

### The problem

After the alarm, most people open the Weather app and then the Calendar app before they
even leave the bed. Squawk is already the first screen they see when they get up (Good
morning), but it only talks about how the morning went. Two quick facts, "Rainy, 12°" and
"Standup at 9:30", would save those two app opens and make Good morning worth a look
every day, not just on streak days.

### Who wants it

Most people who use Squawk on workdays. It's nice polish, not a reason to get up, so it
must never get in the way of the alarm or the wake-up check.

### Basics or powerful

Powerful: it's part of Squawk Pro (Gabriel, 3 Nov 2026). It's off until you turn it on,
because each half needs a permission (location for the weather, calendar for the event).
Nothing is asked during setup.

### How it works

- **On Good morning**, under Squawk's reaction and above "This week", one **Today** card
  shows:
  - **Weather:** a symbol, the temperature now, today's high and low, and one short line
    when something matters ("Rain from 3 pm", "Windy this morning"). Units follow the
    phone's settings.
  - **First event:** the next event today that hasn't ended, with its time and title
    ("9:30 · Standup"), plus "and 3 more" when there are more. All-day events are left
    out. If the day is empty: "Nothing on the calendar today."
- **Turning it on:** the first few times Good morning shows, a small card offers "Add the
  weather and your day", with the Pro tag for people without Pro (tapping it opens the Pro
  screen, like other Pro things). With Pro, tapping it asks for the two permissions, one after the other, with
  a line before each saying why. "Not now" hides the card for good. It can also be turned
  on later in Settings → Morning summary, with a switch for each half.
- **One half is fine.** Say yes to the calendar and no to location, and the card shows
  only the event. If a permission is turned off later in iOS Settings, that half quietly
  disappears and Settings shows how to turn it back on.
- **Never slows the morning.** The card appears when the data is ready. If the weather
  doesn't load in a few seconds (no signal), the weather half is simply left out, with no
  spinner and no error.
- **Shown on Good morning only.** Not on the ringing screen (iOS draws it), not on the
  wake-up check, not on the home screen.

### How it works with Apple's services, and its limits

- **Weather comes from Apple's WeatherKit.** No account, no server of ours, and it's free
  for the app up to 500,000 requests a month, far more than Squawk will use. Apple requires
  its Weather logo and a link to its data sources on any screen that shows the weather, so
  the card has a small Apple Weather mark.
- **Location is asked "while using the app", approximate.** A rough location is enough for
  the weather, and it's only read when Good morning shows. It goes to Apple to get the
  forecast; it never goes to us or to Sentry.
- **Calendar needs full read access.** iOS has no "read only today" option for apps, so the
  prompt asks for full access. Squawk only reads today's events, on the phone, and never
  changes the calendar.
- **No widget or lock screen version** in this version, so the summary doesn't need to run
  in the background.

### What it changes

- Good morning gets the Today card and, until it's set up, the offer card.
- Settings gets a Morning summary row with two switches.
- The privacy manifest and App Store privacy answers: no change, since we don't collect the
  location or calendar data (it stays on the phone, and the weather request goes to Apple).
  The app gets two new permission texts (location while using, calendar full access) and
  the WeatherKit capability.

### Scope

- **In this version:** weather and first event on Good morning for Pro, the offer card,
  the Settings switches.
- **Later:** Squawk reacts to the weather (a tiny umbrella when it rains), picking which
  calendars count, a heads-up the night before ("Rain tomorrow, maybe set it 10 minutes
  earlier?"), the summary on the widget.
- **Never:** reading or changing anything beyond today's events, or sending the location or
  event titles anywhere but Apple's weather request.

### What we measure

No locations, temperatures or event titles, only what happened.

| Metric | What it tells us |
|---|---|
| `pro.shown` (`from`: `summary`) | Whether the summary makes people curious about Pro (existing metric, new value) |
| `summary.enabled` (`part`: weather / calendar) | How many people turn each half on |
| `summary.declined` (`part`: weather / calendar / offer) | Which permission people say no to, and how often "Not now" wins |
| `summary.shown` (`weather`: yes / no, `event`: yes / none / off) | How often the card has something to show |
| `summary.weather_failed` (`reason`: timeout / error) | Whether the weather loads fast enough in the morning |

### Decisions

Gabriel, 3 Nov 2026:

1. **Pro**, not free. It's a `ProFeature`; losing Pro hides the card but keeps the
   permissions as they are.
2. **Permissions are asked from the offer card on Good morning or from Settings**, never
   during first setup, so setup stays under 30 seconds.
3. **Weather uses approximate location "while using"**, not a city picked once, so it's
   right when you travel.
4. **An empty calendar day says "Nothing on the calendar today."** rather than hiding the
   event half.

## Design

Status: Skipped. Gabriel asked to build it straight after the Product section (3 Nov 2026).
The screens below are what was built, from the existing design system.

- **Good morning:** under the reaction (and any "When you're up" chips or new outfit), a
  **Today** card: "Today", the weather row (multicolor SF Symbol, "12°" big, "H 16° · L 9°"
  muted, the note in orange: "Rain from 3 PM", "Snow now", "Windy today"), a divider, the
  event row (calendar icon, "9:30 · Standup" or "Now · Flight", "and 2 more" muted, or
  "Nothing on the calendar today."), and Apple's Weather mark with "Data sources". The card
  springs in when its data arrives (a fade with Reduce Motion).
- **Offer card** (until it's on or "Not now"): sun icon, "Add the weather and your day",
  "See today's weather and your first event right here. Squawk asks for your rough
  location and your calendar. Both stay between your phone and Apple." and "Turn it on" /
  "Not now". Without Pro it has the PRO tag and opens the Pro screen.
- **Settings:** a "Morning summary" card under Pro, with a Weather switch and a First event
  switch (PRO tag and Pro screen without Pro). When iOS Settings turned one off: "Location
  is off for Squawk in iOS Settings." and "Open iOS Settings".
- **Pro screen:** a new line, "Today's weather and first event when you're up".
- **Design system:** reuses `Card`, `ProBadge`, `LinkButtonStyle`, `Theme` colors and
  fonts. No new tokens.
- **Sizes and accessibility:** the card sits in Good morning's 560 pt column, so it's the
  same on the Duo's wide screen. At accessibility text sizes the weather row stacks. Each
  row reads as one VoiceOver element ("Drizzle, 12°. High 16°, low 9°. Rain from 3 PM").

## Build

Status: Built 2026-11-03

- **Core** (`SquawkKit/MorningSummary.swift`, tested): `Agenda(events:now:)` picks the
  next timed event today that hasn't ended and counts the rest; `WeatherNote.pick` finds
  the first hour today with a likely (50%+) rain or snow, else wind of 40 km/h or more;
  `SummarySettings` holds the two switches and when to offer; `withTimeout` drops a slow
  request. `WeatherSource` and `AgendaSource` are the protocols, with fakes.
- **Services** (`Squawk/Summary/LiveSummarySources.swift`): WeatherKit with approximate
  "while using" location (a location from the last hour is reused), and EventKit with full
  access, read only.
- **Model:** `MorningSummaryModel` (switches, permissions, loading both halves in parallel,
  metrics), in the environment from `RootView`.
- **Pro:** `ProFeature.summary`.
- **Setup:** the WeatherKit entitlement, location and calendar permission texts, and the
  WeatherKit capability in `scripts/ios/asc-prepare-app.py`.
- **Risks:** WeatherKit may need its App Service ticked by hand (`docs/ios-release.md`).
  Weather only loads with signal; without it the card shows just the event.
- Folded into `PRODUCT.md`, `DESIGN.md` and the app's `CLAUDE.md`.
