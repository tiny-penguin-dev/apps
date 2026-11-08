# Astrotype: Typing speed

The keyboard measures how fast you type in every app, and the app shows it as your
everyday speed with a graph. Practice measures you too, on the same graph, so the
main game of the app becomes "get your everyday speed up".

Gabriel, 8 Nov 2026: "a feature for typing speed. Basically something like words per
minute average or something like that, where we record your typing speed always and
show you a graph in the app." And: "consider what to do with like short sentences…
That shouldn't count. So maybe it only counts if you write a certain minimum number of
words. And we can remove outliers… pick within median or mean… whatever you think is
the most accurate one. And make it part of the main game of the app… it should be
practice, but measuring your speed, and include your daily speed as well, your normal
speed as well. Don't remove the practice though."

## Product

Status: Draft

- **The problem:** the only speed Astrotype knows is the speed test, three sentences
  typed while trying hard. People want to know if they're actually typing faster day to
  day, in their own messages, and whether two thumbs is paying off.
- **Who wants it:** everyone who opens the app. It's the first thing on Home.
- **Basics or powerful:** basic. Nothing to set up; it fills in as you type.
- **What counts** (the part that makes the number honest):
  - A **run** is a stretch of typing with no pause longer than 5 seconds, in one field.
    It ends at a 5-second pause, when the keyboard goes away or when you move to another
    field. Its time runs from the first touch to the last letter that went in.
  - Speed is the usual typing-test measure, the same as the speed test: characters
    that stayed in the text (spaces and punctuation included, backspaced ones not)
    divided by 5, per minute.
  - **A run counts only with at least 10 words.** "ok", "on my way" and other quick
    replies don't count, so they can't drag the number down or push it up.
  - **Outliers:** a run over 200 words per minute is thrown away (that is a paste or a
    glitch, not typing). Text replacements count as the shortcut you typed, not the
    phrase they wrote.
  - **A day's speed is the median of that day's runs**, and it needs at least 3 runs.
    The median is the middle run, so one very fast or very slow run can't swing it, which
    makes it more accurate than an average for this. A day without 3 runs is a gap on
    the graph, never a zero.
  - **Your everyday speed** (the big number) is the median of the last 7 days that have
    a speed. It shows once there are 3 such days.
  - **Fastest run:** the quickest run of at least 20 words in the range.
  - Not counted: passwords and other fields that don't learn, emoji search, and the
    app's own practice fields (those are practice, shown as practice).
- **Practice measures you:** the speed test becomes **Speed practice**. Its results are
  the coral dots on the same graph, and the result screen says how it compares with your
  everyday speed ("11 faster than your everyday 46"). Drills and Practice words stay as
  they are.
- **Private:** only numbers are kept (when a run started, how long it took, how many
  characters and words), never what was typed or in which app. They stay on this
  iPhone. Settings → Privacy and sharing has **Measure my speed** (on by default) and
  **Delete speed history**.
- **Full Access:** the keyboard can only hand the numbers to the app with Full Access
  (the same App Group as sync). Without it, Home asks for it, and practice still works.
- **Free** (Gabriel, 8 Nov 2026): everyday speed, the graph and practice are free for
  everyone. It's the clearest proof the keyboard and the Pro trial are working.

### What we measure

With "Share anonymous usage data" on, as for the other metrics:

| Metric | What it tells us |
|---|---|
| `speed.everyday` (gauge: words per minute, once a day with a speed) | Whether people really get faster with Astrotype, outside practice |
| `speed.opened` (count) | Whether people look at the graph |

### Open questions

None. (Pro or free: free, Gabriel 8 Nov 2026. PRODUCT.md's "history" in Pro now means
drill history; the build PR updates its table.)

### Later

- Speed by thumb style (one thumb vs two) and by language.
- Sync the history across devices over iCloud.
- Milestones from the everyday speed (first 40 everyday), and a weekly goal.
- Accuracy next to speed (how many words needed a fix).

## Design

Status: Draft

Mockup: [`design/mockups/typing-speed.html`](design/mockups/typing-speed.html).

- **Home** ([before](design/screens/01-before.png), [after](design/screens/02-home.png)):
  the Speed test card becomes **Your speed**: the everyday speed big, a "▲ 2 this week"
  chip, a small graph of the last 30 days (everyday as a teal line, practice as coral
  dots), and under it **Practice for speed** with the best practice chip. Tapping the
  card opens Your speed. The rest of Home stays.
  - First days ([new](design/screens/03-home-new.png)): "Day 1 of 3" and what to expect.
  - No Full Access ([off](design/screens/04-home-off.png)): what turning it on gives,
    with Turn on and Practice for speed.
- **Your speed** ([week](design/screens/05-week.png), [month](design/screens/06-month.png),
  [year](design/screens/07-year.png)): the number for the range, Week / Month / Year,
  the graph (a year is drawn by week), tap a day for its numbers (speed, runs, words,
  practice). Four tiles: Everyday, Best practice, Fastest run, Words counted. Practice
  for speed. A note on how it's counted, linking to Privacy and sharing.
- **Speed practice** ([practice](design/screens/08-practice.png),
  [result](design/screens/09-result.png)): today's speed test, renamed, with the
  everyday speed as the target. The result compares with the everyday speed and shows
  the graph. The Apple keyboard comparison stays on the result as today.
- **Privacy and sharing** ([privacy](design/screens/10-privacy.png)): a Typing speed
  group with the switch and the delete row.
- **Sizes and dark:** [home dark](design/screens/11-home-dark.png),
  [week dark](design/screens/12-week-dark.png), [home small](design/screens/13-home-small.png),
  [week small](design/screens/14-week-small.png), [home wide](design/screens/15-home-wide.png),
  [week wide](design/screens/16-week-wide.png). Wide keeps Home's two columns with Your
  speed leading the left one; the tiles go to one row of four.
- **Motion:** the line draws in left to right on open; none with Reduce Motion.
- **Accessibility:** the graph is a Swift Charts chart with audio graph and a summary
  label ("Everyday speed, last 7 days, 46 words per minute, up 2"); each day is a
  VoiceOver element with its numbers.
- **Copy:** "Your speed", "words per minute, everyday typing", "Practice for speed",
  "Not enough typing to count", "Measure my speed", "Delete speed history".

## Build

Status: Draft

- **Core** (`AstrotypeCore`, `App/TypingSpeed.swift`, pure, tests on Linux):
  - `SpeedRun` (started, seconds, characters, words) and `SpeedMeter`: touches and
    committed text in, with times passed in; finished runs out (5-second pause, field
    change, hide). The 10-word and 200 wpm rules live here.
  - `SpeedHistory`: runs folded into days (median, run count, words, fastest run),
    `everyday(now:)`, ranges for week, month and year (weeks for a year). A year of days.
- **Keyboard:** `KeyboardModel` feeds the meter from what it already knows (touch
  times, what went into the field, `Field.learns`); finished runs go to a small
  `SpeedRunStore` in the App Group (Full Access only, the last 14 days of runs). Off
  when "Measure my speed" is off.
- **App:** `AppModel` folds new runs into `SpeedHistory` (a file in the app's own
  container) on launch and foreground; `speedTest` results join it as practice.
  `HomeView`'s speed card, `SpeedHistoryView` with Swift Charts, the Privacy rows,
  the renamed practice and its result line.
- **Metrics:** `speed.everyday`, `speed.opened` in `LiveMetrics`; PRODUCT.md's table.
- One PR for Core + keyboard (numbers start collecting in TestFlight), one for the app
  screens.
