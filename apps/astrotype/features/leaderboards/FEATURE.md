# Astrotype: Leaderboards

See how your typing speed stacks up against everyone using Astrotype, and against your
friends, so getting your speed up has somewhere to go.

Gabriel, 8 Nov 2026: "Could we do leaderboards?" Then: "Make it free, friends and
everyone. But prioritize everyone because i doubt many people will have many friends
using this."

## Product

Status: Approved 2026-11-09 (Gabriel: "Ok build")

- **The problem:** Your speed (built 8 Nov 2026) tells you how fast you type, but not
  whether that's fast. A number like 46 means more next to everyone else's, and a rank
  to climb gives a reason to practise and to keep typing with Astrotype.
- **Who wants it:** anyone who opens Your speed. It's opt-in, because it shares a number
  with other people.
- **Basics or powerful:** basic. One tap to join, nothing to set up.
- **How it works:**
  - Built on Apple's **Game Center**. No accounts or server of our own: people join with
    the Game Center account already on their iPhone, and show up under their Game
    Center nickname. Apple stores the scores.
  - **Two leaderboards, both reset every Monday**, so a newcomer can be near the top in
    their first week and last week's score doesn't stick around forever:
    - **Everyday speed** (the main one): your everyday speed, as on Home.
    - **Speed practice**: your best Speed practice this week.
  - **Everyone first.** The leaderboard opens on Everyone: your rank and how many people
    you're faster than ("Faster than 93% of people this week"), the top 10, and the
    people just above and below you. **Friends** is the second tab, for Game Center
    friends who use Astrotype, with an invite link when there are none.
  - **What gets posted:**
    - Everyday speed is posted when it changes, once this week has **at least 3 days with
      a speed** (the same days as the graph). On Home the number still shows from the
      first day; the leaderboard just waits for a steadier one.
    - Speed practice is posted after a test on the Astrotype keyboard (not the Apple
      keyboard comparison) with **at most 2 wrong words**. Wrong words already don't count
      toward the speed.
    - Each board only takes scores from 1 to 200 words per minute (Game Center's score
      range, set in App Store Connect), so a broken or faked score far above that is
      rejected by Apple.
    - Game Center keeps your best score of the week on each board.
  - **Joining:** a "See where you rank" card on Your speed and a Leaderboard row.
    Tapping Join shows Apple's Game Center sign-in if you're not signed in, then the
    leaderboard. If Game Center is off or restricted (for example by Screen Time), the
    card says so and links to Settings.
  - **Leaving:** Settings → Privacy and sharing → **Show me on leaderboards**. Turning it
    off stops posting. Apple can't delete a posted score, but both boards reset on
    Monday, so you're gone from them within a week. The copy says this plainly.
- **What it changes:**
  - Your speed gets a **Leaderboard** card under the tiles (your rank, or the join card).
  - Home's Your speed card gets a rank chip ("#1,204 this week") once you've joined.
  - The Speed practice result adds your rank on the Practice board.
  - Privacy and sharing gets a Leaderboards group.
- **Private:** only the two numbers go to Game Center, with your Game Center nickname.
  Never what you typed, in which app, or your runs. Nothing is posted until you join.
- **Free** (Gabriel, 8 Nov 2026), like Your speed.
- **Scope:**
  - In this version: the two weekly boards, Everyone and Friends, join and leave, rank on
    Home and the result.
  - Later: all-time boards, boards by thumb style (one thumb vs two) and by language,
    a weekly "you moved up 300 places" note, Game Center achievements (first 40 everyday).
  - Never: our own accounts or server for scores; posting anything but the numbers.

### What we measure

With "Share anonymous usage data" on, as for the other metrics:

| Metric | What it tells us |
|---|---|
| `leaderboard.joined` (count) | How many people opt in |
| `leaderboard.opened` (count, tag `board`: everyday or practice, `scope`: everyone or friends) | Whether people come back to it, and whether Friends gets used at all |

`speed.everyday` already tells us whether people get faster; no new speed metric.

### Open questions

None. (Free, friends and everyone with everyone first: Gabriel, 8 Nov 2026.)

## Design

Status: Approved 2026-11-09 (Gabriel: "Ok build")

Mockup: [`design/mockups/leaderboards.html`](design/mockups/leaderboards.html)
(Artifact: https://claude.ai/artifact/3rZqZUVdtPxWgZquX14xV1).

- **Your speed** ([before](design/screens/01-week-before.png),
  [after](design/screens/02-week.png)): a Leaderboard card under the tiles with the
  rank, "Faster than 93% this week", and a ›. Tapping it opens the Leaderboard.
  - Not joined ([join](design/screens/03-join.png)): "See where you rank", what's
    shared (your Game Center name and these two numbers), and **Join**.
- **Home** ([home](design/screens/04-home.png)): the Your speed card's chip row adds
  "#1,204 this week". Nothing else on Home changes.
- **Leaderboard** (new screen, Route `.leaderboard`):
  - Everyday / Practice as a segmented control, Everyone / Friends under it, Everyone
    first ([everyone](design/screens/05-everyone.png),
    [practice](design/screens/06-practice.png)).
  - The top: your rank big, "of 18,400 this week", "Faster than 93%", your score, and
    the days left until Monday's reset.
  - Then the top 10, then "Around you" (5 above and 5 below), your row highlighted in
    accent. Each row: rank, a circle with the initial, nickname, words per minute.
  - Friends ([friends](design/screens/07-friends.png),
    [no friends](design/screens/08-friends-empty.png)): the full list (it's short),
    or "None of your Game Center friends use Astrotype yet" with **Invite a friend**
    (share sheet with the App Store link).
  - Not on the board yet ([waiting](design/screens/09-waiting.png)): "Type on 2 more days
    this week to get on the board", with the week's 7 dots showing which days counted,
    and the board below so there's still something to look at.
- **Speed practice result** ([result](design/screens/10-result.png)): a line under the
  comparison: "#312 this week on Practice ›".
- **Privacy and sharing** ([privacy](design/screens/11-privacy.png)): a Leaderboards
  group: **Show me on leaderboards** and the note "Shares your Game Center name and your
  weekly speeds. Turning it off stops sharing; your scores leave the boards when they
  reset on Monday."
- **Sizes and dark:** [leaderboard dark](design/screens/12-everyone-dark.png),
  [small](design/screens/13-everyone-small.png), [wide](design/screens/14-everyone-wide.png).
  Wide puts Top 10 and Around you side by side.
- **Design system:** reuses Card, Chip, the segmented control (`seg`), Group rows,
  Toggle, StatTile and the primary button. Adds **RankRow** (rank, avatar circle,
  name, score; a "you" style with an accent fill) and **RankHero** (big rank, "of N",
  percent chip). No new colours.
- **Motion:** the rank counts up to its number on open, and your row slides into place
  in Around you; none with Reduce Motion.
- **Accessibility:** each row reads "Rank 1,204, you, 46 words per minute". The hero
  reads "You're 1,204th of 18,400 this week, faster than 93 percent". Dynamic Type
  wraps names before scores; scores never truncate.
- **Copy:** "Leaderboard", "See where you rank", "Join", "Faster than 93% this week",
  "Around you", "Top 10", "Resets Monday", "Type on 2 more days this week to get on the
  board", "None of your Game Center friends use Astrotype yet", "Invite a friend",
  "Show me on leaderboards".

### Open questions

None.

## Build

Status: Approved 2026-11-09 (Gabriel: "Ok build")

Built 9 Nov 2026 in one PR:

- **Core** (`AstrotypeCore/App/Leaderboards.swift`, tests in `LeaderboardTests`):
  `Leaderboard` (the two boards and their Game Center IDs), `LeaderboardRules` (what gets
  posted: everyday once the last 7 days have 3 days with a speed, practice on the
  Astrotype keyboard with at most 2 wrong words, scores 1 to 200), `LeaderboardPage`
  (`fasterThan`, `around`), the `LeaderboardService` protocol and
  `MemoryLeaderboardService`. `AppState.leaderboards` (joined, off by default).
- **App:** `App/GameCenterLeaderboards` (GameKit: quiet sign-in on launch, Apple's sheet
  only on Join, the top 10 and the 11 around you, friends with the friends-list ask).
  `AppModel` joins, leaves, posts on launch and foreground (Game Center keeps the best of
  the week, so posting again is harmless) and after a practice result, and loads the
  boards. `Speed/LeaderboardView.swift`: `LeaderboardView` (Route `.leaderboard`),
  `LeaderboardCard` on Your speed, `RankRow`. Home's `SpeedCard` shows the rank chip,
  the result shows the Practice rank, Privacy and sharing has Show me on leaderboards.
- **Weekly reset:** both boards start Monday 9 Nov 2026 at 08:00 UTC (midnight in
  California, morning in Europe) and reset every 7 days. The screen reads the reset from
  Game Center, so it says the right day wherever you are.
- **App Store Connect:** `store/game-center.json`, synced by `scripts/ios/asc-game-center.py`
  in the App Store workflow (turns Game Center on, creates the two boards with their
  score range and recurrence). The `com.apple.developer.game-center` entitlement and
  `NSGKFriendListUsageDescription` are in `Config/`.
- **Not yet:** the invite shares text without a link until Astrotype has an App Store
  page. Before the first release, add both leaderboards to the version in App Store
  Connect (Game Center section) so they go live with it.
