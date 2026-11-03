# Astrotype: Spanish and more languages

Astrotype types Spanish as well as English, and the way it does it makes every later
language a set of files, not new code.

## Product

Status: Approved 2026-11-03

- **The problem:** Astrotype only knows English. Anyone who writes in Spanish, even part
  of the time, has to switch to Apple's keyboard, and a swipe keyboard you leave every
  few messages is one you stop using. PRODUCT.md already lists "more languages,
  starting with Spanish" under Later.

- **Who wants it:** Spanish speakers, and above all people who write in both English and
  Spanish, often in the same message.

- **Basics or powerful:** a language picker in Settings, set once and forgotten.
  Every language is free: anyone can type in Spanish, or English, or any language that
  comes later. Two languages at once is Pro (Gabriel, 3 Nov 2026). This changes
  PRODUCT.md section 6 ("Extra languages" in the Pro column becomes "Two languages at
  once", and the free column's "English" becomes "any one language"); the Build stage's
  last step folds it in.

- **How it works:**
  - *Settings → Languages* lists English and Español with a switch each. Free, turning
    one on turns the other off; with Pro (or the trial) both can be on.
  - *To start* the keyboard takes the phone's language: a Spanish phone (its first
    preferred language is Spanish) starts in Spanish, any other phone in English. If the
    phone's preferred languages include both, setup asks once ("Which languages do you
    type in?", both ticked) on the step after the keyboard is turned on, and the two-week
    trial covers having both (Gabriel, 3 Nov 2026: pick the right one by itself, or ask
    in setup). Anyone else never sees the question.
  - *When the trial ends* without Pro and two are on, the keyboard keeps the first one in
    the phone's preferred languages and turns the other off, with a line on the Languages
    page saying so and that Pro brings it back. Nothing learned in either language is
    lost.
  - *Both at once.* With two languages on, the keyboard guesses from both word lists
    together, so "see you mañana" needs no switching. The word pairs keep each
    language's words with its own kind: after "el" the Spanish guess wins, after "the"
    the English one. There is no language key and nothing to switch (Gabriel,
    3 Nov 2026, over one language at a time switched with a key).
  - *Accents come by themselves.* You swipe or tap the plain letters and the keyboard
    writes the word with its accents: c-a-n-c-i-o-n gives "canción", a-n-o gives "año"
    when "año" is likelier there than "ano". The guess bar shows the accented word, and
    the other spelling is one tap away when both exist ("esta", "está").
  - *Typing accents by hand.* Holding a vowel shows its accented letters (á, é, í, ó,
    ú, ü) and holding n shows ñ, like Apple's keyboard. A letter picked this way is kept
    as typed. The layout stays QWERTY with no extra key, so the keys stay where your
    thumbs know them.
  - *Spanish punctuation.* ¿ and ¡ are on the symbols page and on a hold of ? and !.
    A sentence that starts with them gets its capital after them ("¿Qué tal?").
  - *Learned words, word pairs from you, and corrections* work the same in both
    languages; what the keyboard learns from you is not split by language.

- **Size:** each language is about 2 MB in the app (a word list and its word pairs),
  about 1 MB of the App Store download. Languages ship inside the app, not as downloads:
  the keyboard can only read downloaded files with Full Access on, and it must type
  without it. Only the languages that are switched on are loaded, so the keyboard's
  40 MB limit doesn't grow with how many ship.

- **What it changes:** the matcher reads from more than one word list; the word list
  knows letters beyond a to z (accents and ñ); Settings gains a Languages page; the
  in-keyboard panel (for people without Full Access) gains the same switches; the
  speed test, drills and practice words stay English for now.

- **Scope:**
  - *This version:* Spanish, both-at-once typing, automatic accents, held-key accents,
    ¿ and ¡, the Languages page, Spanish in Settings → About's credits.
  - *Later:* more languages on the same files (Portuguese, French, Italian and German
    are the next likely ones); Spanish practice words and speed test; translating the
    app itself into Spanish (a separate piece of work).
  - *Never:* a language that needs Full Access to type, or a download the keyboard
    can't read. At around 15 languages we look again at downloading the extras.

- **Data:** the word list from `wordfreq`'s Spanish counts (the same source as English)
  and the word pairs from Tatoeba's Spanish sentences, built with the tools in
  `ml/ngrams/`, credited in Settings → About like the English ones.

- **What we measure** (`docs/telemetry.md`, anonymous):
  - `languages.enabled` (`set`, for example `en`, `en+es`, `es`): which languages people
    turn on, sent when they change. Tells us whether to do more languages and which,
    and how many people turn on a second language (a Pro reason).
  - `guess.fixed` split by the fixed word's language, so we see if Spanish guesses are
    worse than English ones.

- **Open questions for Gabriel:** none left. Answered 3 Nov 2026: both languages at
  once rather than a switch key; every language free, two at once Pro.

## Design

Status: Approved 2026-11-03 (Gabriel asked to merge the plan and build, without a
separate design round; the screens below reuse existing components)

- **Mockups:** none; every screen is made of the existing `Row`, `Card` and
  `SetupPage` pieces, and the accent callout copies Apple's.
- **Settings → Typing → "Languages"** (a `Row` with the current set as its subtitle,
  "English, Español") opens the Languages page: one `Row` per language with a switch,
  each named in its own language ("English", "Español") with the other name under it
  ("Spanish"). Free with one on, turning another on asks for Pro (the usual Pro sheet,
  "Type in two languages at once"); turning the only one off is not possible. Under the
  list: "With two on, Astrotype guesses from both. No switching." After a trial ends
  with two on, a line at the top: "Español is off. Pro types in both at once." with
  a Pro button.
- **In-keyboard settings panel** (for people without Full Access): the same switches
  under a "Languages" heading.
- **Setup, only when the phone lists both languages:** a `SetupPage` after the keyboard
  is turned on, "Which languages do you type in?", the two languages as ticked rows and
  "Continue". The line under it: "Free types in one. Your trial covers both."
- **Accent callout:** holding a letter that has accented forms (a e i o u n, and ? !
  for ¿ ¡) for 0.35 s shows a row of keys above it in the key's style (`Theme` key
  colours, 8.5 pt corners), the plain letter first; sliding the thumb picks one and
  lifting writes it. Lifting without moving writes nothing extra. Only shown when a
  language that uses them is on (Spanish for now).
- **Symbols page:** ¿ and ¡ join the second symbols page when Spanish is on.
- **About:** a row "Spanish word pairs", "Built from Tatoeba's Spanish sentences
  (tatoeba.org, CC BY 2.0 FR)".
- **Accessibility:** the callout's keys are VoiceOver elements ("a with acute accent");
  the language switches read their full names.

## Build

Status: Approved 2026-11-03 (with the design, at Gabriel's request)

- **Approach:** the trie stays a to z and learns spellings. A word is stored under its
  plain letters (the key the thumbs actually hit: "cancion"), and the node keeps the
  real spelling ("canción") when it differs, with any other real spellings of the same
  letters ("esta", "está") as alternates for the bar. Two languages at once are one
  merged `Lexicon` with each language's frequencies scaled to the same total, plus each
  language's word pairs; the context bonus for a word comes from the languages that
  know it.
- **Core pieces** (all in `AstrotypeCore`, tested on Linux):
  - `Lexicon.fold(_:)`: lowercase, accents and ñ to a to z (`"Año"` → `"ano"`);
    `Lexicon` keeps a spelling table for nodes whose word is not its own key, and
    `word(at:)` returns the spelling. `spellings(at:)` gives all of them, best first.
  - `Language.combined(_ languages: [Language]) -> Language`: one lexicon from all,
    `ngrams` becomes a list (`[NgramModel]`) with `contextBonus` the best of the
    models that know the word. `Language.bundledCodes` gains `"es"`.
  - `KeyboardSettings.languages: [String]` (default from the phone's preferred
    languages), with `ProFeature.twoLanguages` deciding how many are used.
  - `Layout`: accent alternates per key (`Layout.alternates(for:languages:)`).
- **Phases** (one PR each, merged when green):
  - **A. Spanish in the engine:** the folded trie with spellings, the Spanish word list
    and word pairs, `Language.combined`, tools and tests (Spanish fixture swipes, both
    at once keeping English accuracy). Nothing visible yet. *Done when:* `swift test`
    shows "canción" from a c-a-n-c-i-o-n swipe with Spanish on and English accuracy
    unchanged with both on.
  - **B. The keyboard:** the languages setting, the keyboard loading the chosen ones,
    the accent callout, ¿ ¡ and the capital after them, the in-keyboard switches, the
    Pro rule. *Done when:* on a phone, both on, "see you mañana" types without
    switching.
  - **C. The app:** the Languages page, the setup question, trial end, the About
    credit, `languages.enabled`, and folding this into PRODUCT.md and DESIGN.md.
- **Risks:** a merged dictionary makes look-alike swipes more ambiguous (words spelled
  the same in both, like "no" and "a", share one entry, but "the" and "te", or "and"
  and "año", now compete). The word pairs settle most; the harness measures
  English accuracy with both on so it can't quietly drop. Memory: a second trie and
  word-pair model add about 4 MB, inside the 40 MB budget; the bar's readout and
  `keyboard.memory_peak` will show it.
- **Metrics:** `languages.enabled` (`set`) from the app with `Telemetry`.
- **Last step:** fold into PRODUCT.md (section 6's table) and DESIGN.md.
