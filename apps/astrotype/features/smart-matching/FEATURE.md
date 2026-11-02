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
network (it still sends no telemetry); uploads happen in the app.

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
- `PersonalModel` (Phase B): the person's word counts and word-pair counts with decay,
  and per-key, per-thumb landing offsets (`TouchModel`), in one versioned, mergeable value
  like `LearnedWords`, stored by a `PersonalStore` beside the words and synced the same
  way. The matcher adds `personalWeight × log(1 + pairCount)` and reads taps and swipes
  through the thumb's offset.
- `Replay` (the harness): plays a `PracticeRecording` through a `Composer` with the same
  language and layout, commits where the person did, and reports first-guess accuracy,
  top-three accuracy and the misses. `astrotype-tools replay <folder>` prints it;
  fixtures from the drill and Try it words keep it at 100% in `swift test`.
- `PracticeRecording` v2 adds `commits` (word and time) so a session replays exactly;
  Phase C makes sessions per word and adds the correction records.

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
  matcher's weights against the harness on real sessions, recorded in this doc.
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
