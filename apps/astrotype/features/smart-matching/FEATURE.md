# Smart matching

Status: Approved 2026-11-02 (Gabriel asked for the plan to be written and built without
a review round: "assume it's accepted, and just build it well and scalable")

The keyboard's guesses get smarter in three ways that each ship on their own: they use
the words before the cursor, they learn the person's own words and thumbs, and the
defaults everyone gets are tuned from practice sessions people choose to share. English
first; every language-specific piece sits behind one `Language` so the next language is
data, not code.

## Product

**The problem.** The matcher (`BUILD.md` "Core pieces") scores a swipe by its shape
against the dictionary, the word's frequency and the words the person taught it. It knows
nothing about the sentence, so "going to the" followed by a swipe that fits both "store"
and "stare" is a coin toss, and it treats every thumb the same, so a person who always
lands a little low on the right half pays for it on every word.

**What changes for people.**

- *It reads the sentence.* The previous words make the likely next word win: "going to
  the store", "thank you so much", "see you soon". Starting a sentence is context too
  ("I", "the", "we").
- *It learns you.* Pairs of words you type become likely for you ("flotilla ships"),
  words you use often rise, and the keys shift a little toward where your thumbs actually
  land. All of it stays on the phone, in the keyboard's own files, and follows you to your
  other devices with the learned words when Full Access is on. One switch in Settings
  turns it off and one button forgets it.
- *You can help, and see exactly what you give.* "Send practice sessions" stays off by
  default. Before anything is sent, a screen shows what a session holds: the words you
  were asked to type and the paths of your thumbs over the keys, as a list and as a
  picture, with no sentence of your own, no name, no account. Sessions are per word, so
  nobody at Tiny Penguin can read a sentence back. Corrections you make in other apps
  (picking another word in the bar) can be included as the word pair, never the text
  around it, and only if you turn that on too.
- *The defaults get better.* Shared sessions feed a harness that replays them through
  the engine and reports how often the first guess was right. Every change to the matcher
  is measured against it before it ships.

**Basics versus powerful.** Context and personal learning are on for everyone and need no
setting (the basics). The switches (learning on or off, forget, what to share) are in
Settings → Privacy and Settings → Typing (powerful). Nothing here is Pro-only: a Free
keyboard that guesses badly sells nothing.

**Never.** Nothing typed in another app leaves the phone unless the person turned on the
corrections share, and then only word pairs with no text around them. No model trained on
shared data ever contains a sentence anyone wrote. The extension never talks to the
network with anything typed (its crash reports hold no text); uploads happen in the app.

**Languages.** English now. A language is a `Language` value: its lexicon, its word-pair
model, its alphabet (which letters the trie knows) and its sentence rules. Adding one is
adding its files under `Resources/<code>/` and a line in the table; the matcher, the
personal models and the harness read whatever the language gives them.

**What we measure** (`docs/telemetry.md`, anonymous, with "Share anonymous usage data"):
`guess.fixed` (a word swapped from the bar; the rate against `word.committed` is the
in-the-wild miss rate), `practice.shared` (sessions uploaded, by kind) and
`personal.reset`. Nothing about which words.

## Design

Screens in `DESIGN.md`'s system; small, and mostly text.

- **Settings → Typing → "Learns from you"** (toggle, on): "Your word pairs and where your
  thumbs land, kept on this phone." Under it a line with what it knows ("214 word pairs,
  thumbs mapped") and a ghost button "Forget everything".
- **Settings → Privacy → "Send practice sessions"** (toggle, off) gains "What gets shared"
  underneath, a link to the sheet below, and a second toggle "Include corrections from
  other apps" (off, only with Full Access), with the line "The word you wrote and the
  word you meant. Never the text around them."
- **What gets shared** (sheet): the fields of one real pending session, in plain words,
  with the keyboard drawn and the recorded thumb paths on it in the two colours. "Every
  session has: the words we asked you to type, your thumbs' paths over the keys, your
  phone model and system version, a random ID for this install. Nothing else." A button
  "Send 3 sessions now" and the pending count.
- **Settings → Privacy → "Practice words"** (Phase D): a practice screen that shows one
  common word or short phrase at a time from the word-pair model, so recordings cover
  more than the speed test's twelve sentences. Same look as the speed test, no timer.
- **Motion and accessibility** as the rest of the app: everything is `Row`s and `Card`s.

## Build

### Architecture

All in `AstrotypeCore`, pure and tested, per `docs/building.md`:

- `Language`: `code`, `lexicon: Lexicon`, `ngrams: NgramModel?`, bundled from
  `Resources/<code>/` (`lexicon.tsv`, `bigrams.bin`). `Lexicon.bundled()` stays and means
  English.
- `WordContext`: the previous words from the text before the cursor (`<s>` at a sentence
  start), lowercase, inside the current sentence.
- `NgramModel`: a word-pair model in a compact binary (`ASNG` v1: the vocabulary sorted,
  one offset per previous word, UInt16 next ids and UInt8 quantised log probabilities;
  about 1 MB for 300,000 pairs). `contextBonus(for:after:unigramLogPrior:)` is
  `log(λ·P(w|prev) + (1−λ)·P(w)) − log P(w)`, clamped, so an unseen pair costs a little and
  a strong pair gains a lot. The same type builds the binary (`Builder`), so the format
  has one source of truth; `astrotype-tools build-ngrams` wraps it and
  `ml/ngrams/count_pairs.py` counts a corpus.
- `Matcher` gets `language` and `context: [String]`; the score gains
  `contextWeight × contextBonus`. `Composer.setContext` fills the context.
- `PersonalModel` (Phase B): the person's word counts and word-pair counts, fading with
  a 90-day half-life, and per-key, per-thumb landing offsets, in one versioned value.
  Each install writes only its own shard (a random `InstallID`), so merging copies is
  "the newer shard per device" and nothing is counted twice; a forget drops every shard
  that began before it. Stored by a `PersonalStore` (`personal.json`, mirrored to the
  App Group like the words) and synced inside the same `SyncSnapshot`. The composer
  emits `.settled(SettledWord)` when a word is final (the next word starts, space or
  punctuation after the fix bar, the cursor moves), with the word before it and where
  the thumbs landed; `PersonalLearner` learns from it and builds the `PersonalIndex`
  the engine reads. The matcher adds a word term (how much more the person uses a word
  than the dictionary expects, never negative) and a pair term (`log(1 + pairCount)`),
  capped together at 0.8; the composer reads every touch through the thumb's offset
  for the key under it, capped at 0.4 of a key.
- `Replay` (the harness): plays a `PracticeRecording` through a `Composer` with the same
  language and layout, commits where the person did, and reports first-guess accuracy,
  top-three accuracy and the misses. `astrotype-tools replay <folder>` prints it;
  fixtures from the drill and Try it words keep it at 100% in `swift test`.
- `PracticeRecording` v2 adds `commits` (word and time) so a session replays exactly.
- `SharedWord` (Phase C, version 3): what is shared, one word at a time: the word
  meant, what went in when it was a miss, the word asked for before it (practice only),
  the touches with times from the word's own first touch, the day (no time), and the
  device line the app stamps on at upload. `SharedWord.words(of:)` splits a recording
  (shuffled, so the order is gone); `SharedWord.correction` makes one from a settled
  word that was fixed from the bar. They wait in a `SharedWordStore` in the App Group
  (the keyboard writes corrections there with Full Access) and go up as
  `PracticeSession` records (no schema change); `Replay.run(_: SharedWord)` replays one
  with its previous word as the context.

### Phases

Each a PR, merged when green, like `BUILD.md`'s phases.

- **A. Context and the harness** (this PR): `Language`, `WordContext`, `NgramModel` with
  the English model from Tatoeba, the matcher's context term, `Replay`, the tools
  executable, recording v2, `download_samples.py --type PracticeSession`, fixtures and
  tests.
- **B. Learns you**: `PersonalModel` and `TouchModel`, fed by the composer's commits,
  stored and synced; "Learns from you" in Settings with forget.
- **C. Sharing you can see**: per-word sessions, the "What gets shared" sheet, the
  corrections record from the extension (App Group, Full Access) and its toggle,
  `practice.shared` metric.
- **D. Practice words and tuning**: the practice-words screen; a tuning pass of the
  matcher's weights against the harness, recorded in this doc (on synthetic typing
  until enough real sessions are shared; the same commands run on real ones).
- **E. Learned matcher** (only if D's numbers say so): a small model trained on shared
  sessions, shipped as Core ML, the geometric matcher as the fallback. Never in the
  extension if it costs the 40 MB budget.

### Limits that hold

The extension's 40 MB, a guess in a few milliseconds (the context term is one binary
search per candidate), typing without Full Access, nothing typed uploaded without the
person turning it on.

### Data sources

The English word-pair model is built from Tatoeba's English sentences
(tatoeba.org, CC BY 2.0 FR; credited in Settings → About), restricted to the lexicon's
40,000 words, with Tatoeba's stock names (Tom, Mary) dropped so they do not skew sentence
starts. `ml/ngrams/README.md` has the commands.

### Notes

**Phase A (2026-11-02).** The English model: Tatoeba's `eng_sentences.tsv` (about
1.9 million sentences), with the 571,000 sentences that name Tom, Mary, Sami, Layla
or Fadil dropped (they started a third of them), gives 10.5 million pairs over the
lexicon, 444,000 distinct with a count of two or more; the binary keeps the 300,000
most common (24,250 words, 1.1 MB, λ 0.7). `contextWeight` is 0.12, so the capped
bonus (6 in log space) is worth 0.72 in score, about the gap between the first and
second guess of an ambiguous swipe: one straight swipe p→o→t gives "put" alone,
"pot" after "the" and "put" after "to"; "or" becomes "our" after "to". The straight
fixture swipes still come out at 90% or better with context on. The harness replays a
recording to the exact guesses the live keyboard made (`ReplayTests`); real sessions
need recording v2, which ships with this phase, so the first numbers on real data
come with Phase D. The `astrotype-tools` executable builds on Linux too (the App
Group lookup is Darwin-only), so the model and the harness run in CI's toolchain.

**Phase D (2026-11-02).** "Practice words" is in Settings → Privacy next to the sharing
switches, as designed: `PracticeWords` gives one to three words at a time, phrases
walked through the word pairs from a sentence start and single words from the
commonest 4,500 by a random two-letter opening, never a dropped-apostrophe contraction
("dont"); a wrong word shakes and is taken back out, and each prompt is a recording
that is shared word by word.

No real sessions were in the container, so the tuning pass ran on synthetic typing:
`astrotype-tools synth` swipes the practice prompts through noisy aims (each thumb with
its own habit, 0.12 key low and up to 0.16 to the side, and a random miss per letter),
150 sessions of about 1,280 words per set, one set to tune and others to check. It
showed the matcher's real weakness: at a sloppy 0.32 key of noise the first guess was
right 74% of the time and in the top three only 76%, so the misses were words the
search never reached (a swipe that ended on the next key could not end the word). The
fix is `nearRadius`: each crossed key may also be read as a neighbour the path passed
within half a key of, at a cost of 0.2 per stand-in (`nearPenalty`) on top of the path
distance. Results, first guess / top three:

| Set | Before | After |
|---|---|---|
| noise 0.22 (held out) | 95.2% / 96.6% | 96.4% / 98.0% |
| noise 0.32 (held out) | 74.4% / 75.5% | 80.8% / 82.2% |

The weight search (`astrotype-tools tune`) on the tuning set also prefers a lower
`priorWeight` (0.06 to 0.09, worth about half a point on held-out sets). That is left
at 0.12: synthetic prompts pick words more evenly than people do, so they undervalue
word frequency. The first run on real shared sessions decides it:

    cd ml && python3 download_samples.py --type PracticeSession
    cd ../ios/AstrotypeKit && swift run -c release astrotype-tools tune ../../ml/samples/practice

Phase E (a learned matcher) waits for those numbers too. A debug build decodes the
50-word fixture at 5.6 ms a word with stand-ins on.

**Phase C (2026-11-02).** Built as planned, as a page in Settings rather than a sheet
("What gets shared", from Settings → Privacy), so the list has room: the words waiting
with Remove on each, the selected one drawn on the keys with each thumb's path in its
colour, its fields in plain words (including the device line the upload adds), and
"Send N now". Whole recordings no longer go up: a session is split into its words when
it is saved, and recordings still waiting from before are split on the next upload.
"Include corrections from other apps" is a keyboard setting (it has to reach the
extension), only on while "Send practice sessions" is; turning sharing off drops what
was waiting and the corrections switch with it. Corrections carry no previous word and
are never kept from fields the keyboard does not learn from. `practice.shared` counts
each word sent, by kind.

**Phase B (2026-11-02).** Learning is live in the keyboard, with no training step to
run in the app: counting is cheap enough to do as each word settles, and the file is
written three seconds after the last word (and when the keyboard goes away). A word
counts 1 when tapped out, 0.6 when it was a kept swipe guess (so the keyboard's own
guesses do not teach it much) and 1.5 when fixed from the bar. Thumbs learn from taps
that line up one per letter and, lightly (0.3), from where a lone swipe started; a
touch more than a key from its letter is ignored. A key's offset leans on the thumb's
overall habit until it has eight touches of its own. Nothing is learned in password,
email, URL, number or one-time-code fields, or where the app turned autocorrection off.
Shards are capped at 2,000 words and 4,000 pairs (about 150 KB each), and four devices'
shards at most go into the iCloud record. The switch and "Forget everything" live in
the keyboard settings, so they reach the keyboard through the App Group and iCloud
like any setting; the in-keyboard panel (under a held 123) has both too, for people
without Full Access (forget asks twice). The app's practice fields type with the model
and never add to it. Tests: `PersonalModelTests` (counting, fading, caps, merging and
forgetting across devices, offsets with shrinkage and caps, a learned thumb turning a
low tap back into the key it meant, settling, "my pit" winning a p→o→t swipe once the
person writes it, the switch, stores and snapshots).

Real words (2 Nov 2026, after Gabriel saw "Bhrg" for "bring"): pecked letters that
spell no word went in as tapped, and a swipe that fit no word typed the keys its pieces
started and ended on. Now `Matcher.nearestWords` finds the real words (dictionary and
learned) within a weighted edit distance of the letters: a tap on a nearby key costs
by how far it landed from that key's centre, a missed or extra tap and two swapped
letters cost a fixed amount, all on the prior's scale. For pecked letters the nearest
word goes in when the keyboard is at least `1 - strictness` sure of it, its score gap
over the letters (scored at `unknownPrior`, -13) read as log odds at
`confidenceScale` 0.12; the letters stay second on the bar. Letters that begin a word
stay while typing goes on and are decided on space. A swipe that fits nothing always
becomes the nearest word. At strictness 1 letters that are not a word never go in.
The setting is "Real words" in Settings and the keyboard's panel, 0–100% in 1% steps, default 80%.

**Missed spaces (2026-11-03).** Pecked letters that spell no word but read as two
words with the space missed ("textseparately") go in split, when it is obvious
(Gabriel asked for it): both halves are real words (the dictionary's or the person's),
a half of three letters or fewer must be common (log prior -7 or better, so rare bits
like "ep" and "xt" never split a word), single letters only "a" and "i", and the best
place for the space must beat the next by 0.1 in score. The split is scored like a
guess for its rarer half plus the word pairs' say on the two together, less 0.45 for
the space (a missing letter), so a close slip ("hte" for "the") still wins. It stays in
the bar behind the letters, and the letters behind it, either way. "Split words" in
Settings and the 123-hold panel (`KeyboardSettings.splitStrictness`, 80% by default)
says how sure it must be, like "Real words"; at 0% it never splits. Only pecked words
and only two halves; a split is never learned as a word or settled for the personal
model. The settings redesign (PR #72) gives the slider its final place.
