# Astrotype: Spanish and more languages

Astrotype types Spanish as well as English, and the way it does it makes every later
language a set of files, not new code.

## Product

Status: Draft

- **The problem:** Astrotype only knows English. Anyone who writes in Spanish, even part
  of the time, has to switch to Apple's keyboard, and a swipe keyboard you leave every
  few messages is one you stop using. PRODUCT.md already lists "more languages,
  starting with Spanish" under Later.

- **Who wants it:** Spanish speakers, and above all people who write in both English and
  Spanish, often in the same message.

- **Basics or powerful:** a language picker in Settings, set once and forgotten.
  Extra languages are Pro, as PRODUCT.md section 6 says ("Extra languages as they are
  added"); English stays free. See the open questions.

- **How it works:**
  - *Settings → Languages* lists English and Español with a switch each. English is on
    to start. A Spanish phone (its first preferred language is Spanish) starts with both
    on, and the trial covers it.
  - *Both at once.* With two languages on, the keyboard guesses from both word lists
    together, so "see you mañana" needs no switching. The word pairs keep each
    language's words with its own kind: after "el" the Spanish guess wins, after "the"
    the English one. There is no language key and nothing to switch. (This is the open
    choice on the thread; the other way is one language at a time, switched by holding
    space.)
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
    turn on, sent when they change. Tells us whether to do more languages and which.
  - `guess.fixed` split by the fixed word's language, so we see if Spanish guesses are
    worse than English ones.

- **Open questions for Gabriel:**
  1. Both languages at once, or switching with a key? (Asked on the thread; this draft
     assumes both at once.)
  2. Should Spanish be Pro, as PRODUCT.md says, or free? Free makes Astrotype a full
     keyboard for Spanish speakers who never pay; Pro keeps the free set as it is.
  3. On a Spanish phone, should Spanish start on with English, or should the person turn
     it on?

## Design

Status: Not started

## Build

Status: Not started
