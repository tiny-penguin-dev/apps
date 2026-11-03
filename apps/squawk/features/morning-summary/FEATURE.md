# Squawk: Morning summary

The Good morning screen also shows today's weather and your first calendar event, so the
first thing you see after getting up tells you what the day looks like.

## Product

Status: Draft

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

Basics, but off until you turn it on, because each half needs a permission (location for
the weather, calendar for the event). Nothing is asked during setup.

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
  weather and your day". Tapping it asks for the two permissions, one after the other, with
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

- **In this version:** weather and first event on Good morning, the offer card, the
  Settings switches.
- **Later:** Squawk reacts to the weather (a tiny umbrella when it rains), picking which
  calendars count, a heads-up the night before ("Rain tomorrow, maybe set it 10 minutes
  earlier?"), the summary on the widget.
- **Never:** reading or changing anything beyond today's events, or sending the location or
  event titles anywhere but Apple's weather request.

### What we measure

No locations, temperatures or event titles, only what happened.

| Metric | What it tells us |
|---|---|
| `summary.enabled` (`part`: weather / calendar) | How many people turn each half on |
| `summary.declined` (`part`: weather / calendar / offer) | Which permission people say no to, and how often "Not now" wins |
| `summary.shown` (`weather`: yes / no, `event`: yes / none / off) | How often the card has something to show |
| `summary.weather_failed` (`reason`: timeout / error) | Whether the weather loads fast enough in the morning |

### Free or Pro

Free (proposed). It's cheap to run, it makes Good morning useful every day, and it doesn't
compete with the Pro features that help you get up.

### Open questions for Gabriel

1. **Free or Pro?** Proposed: free, see above.
2. **Where to ask for permissions?** Proposed: the offer card on Good morning plus a
   Settings row, not during setup, so first setup stays under 30 seconds.
3. **Weather location:** proposed approximate location "while using". The other option is
   picking a city once in Settings, with no location permission, but it's wrong when you
   travel.
4. **Empty calendar:** proposed to say "Nothing on the calendar today" rather than hide
   the event half.

## Design

Status: Not started

## Build

Status: Not started
