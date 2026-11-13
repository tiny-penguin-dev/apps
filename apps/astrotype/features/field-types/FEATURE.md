# Astrotype: field types

The keyboard changes for the field it is typing in, like Apple's does: an @ and a dot in
email fields, a slash and ".com" in web addresses, "go" or "search" on the return key,
and no autospace or corrections where they would get in the way.

## Product

Status: Approved 2026-11-03 (Gabriel: "Build it")

- **The problem:** today the keyboard looks and acts the same in every field. In an
  email, web address, username or search field it only stops learning
  (`features/smart-matching`). Autospace still drops a space after "name" in
  "name@example.com", a pecked "gmial" can still turn into a guess, the first letter is
  still capitalised, and "@" or "." means a trip to the numbers page. The return key
  always says return, so the person can't see that it will search, send or go. Apple's
  keyboard does all of this, so people notice when we don't.
- **Who wants it:** everyone. Everybody types an email address or a web address
  sooner or later, and those are the moments a swipe keyboard feels clumsy.
- **Basics or powerful:** basics. It just happens, with no setting.
- **How it works:** the keyboard reads what the app says about the field (its keyboard
  type, return key type, content type, capitalisation and correction settings) each
  time it opens and when the field changes, and picks one of these kinds:

  | Kind | When | Bottom row | Typing |
  |---|---|---|---|
  | Text | everything else | 123, 🌐, space, return | as today |
  | Email | email keyboard, or an email or username field | 123, 🌐, space, @, ., return | literal |
  | Web address | URL keyboard, or a URL field | 123, 🌐, ., /, .com, return | literal |
  | Web search | web search keyboard | 123, 🌐, space, ., return | as today, no autospace |
  | Social | Twitter keyboard | 123, 🌐, space, @, #, return | as today |
  | Numbers | number, decimal and numbers-and-punctuation keyboards | opens on the 123 page | literal |

  *Literal* typing means: taps write exactly the letters tapped (no guess replaces
  them), no autospace, no space after a word or a guess from the bar, no ". " on a
  double space, no automatic capitals, and nothing learned. A swipe still shows its
  guesses in the bar (a swipe has no literal reading), and the top guess goes in with no
  space after it. "@", ".", "/" and ".com" end the open word with no space.

  Apart from the kind, every field gets:

  - **The return key's word.** "go", "search", "send", "join", "next", "done",
    "route", "continue" or "emergency call" when the app asks for one, as Apple's
    does; action words (all but "next") on a blue key. The return arrow otherwise.
  - **A return key that waits for text** when the app asks for that (the send button
    in Messages-like apps): dimmed and does nothing while the field is empty.
  - **The app's capitals:** none, each word, every letter or sentences, as the field
    asks. Today it is always sentences.
  - **The app's corrections:** when the field turns corrections off, taps write
    exactly what was tapped. Autospace stays in plain text fields with corrections
    off, because that is spacing, not correcting.

  Password and phone number fields are not ours: iOS always swaps in its own keyboard
  there.
- **What it changes:** `KeyboardViewController.fieldAllowsLearning` becomes one reading
  of the field that drives learning, the bottom row, the return key, capitals and
  corrections. The bar, the 123 hold menu, the in-keyboard settings and every gesture
  work the same in every kind. No setting changes, so it doesn't touch the settings
  redesign.
- **Scope:**
  - *Now:* the six kinds, the return key's word and colour, return waiting for text,
    capitals and corrections from the field.
  - *Later:* holding ".com" for .org, .net, .edu and the country ending (Apple's
    long-press), and suggesting the person's own email address in the bar (would need
    contacts or a setting, so it needs its own product decision).
  - *Never:* reading what's already in the field to guess its kind, or anything that
    sends field details anywhere. (Autofill reads the few words before the cursor to
    offer a detail after "my email is", never to pick the kind: features/autofill.)
- **What we measure:** nothing new. The field kind is never sent (`docs/telemetry.md`:
  the keyboard sends crash reports only). Fewer `guess.fixed` in other apps is a side
  effect we can see but not split by field.
- **Answered** (3 Nov 2026, Gabriel said "Build it", so the recommendations stand):
  1. Swipes stay on in email and web fields and are still guessed; only taps are
     typed exactly. Swiping "gmail" is still faster than tapping it.
  2. The action return key is Apple's blue, not our teal, since the keycaps are
     Apple's (DESIGN.md "Keycaps").

## Design

Status: Approved 2026-11-03 (Gabriel: "Build it")

- **Mockups:** `design/mockups/field-types.html` (Artifact link:
  https://claude.ai/artifact/VyRZhYMMwqd79HuPNZXJJd), a phone with a field picker (Message,
  Email, Web address, Web search, Social, Numbers, Username). Each shows an app's field
  and our keyboard with that field's bottom row and return key; taps type into the
  field with that kind's rules, so the difference between literal and normal typing
  can be tried. Size buttons show the small (Duo outer) and wide (Duo inner) sizes,
  and it follows light and dark.
- **What changes:** only the bottom row and the return key. The three letter rows, the
  bar and the key sizes are the same in every kind. Before (every field today) and
  after:
  - Text, before and after: [text](design/screens/01-text.png)
  - Email: [before](design/screens/00-email-before.png),
    [after](design/screens/02-email.png)
  - Web address: [after](design/screens/03-url.png), [dark](design/screens/03-url-dark.png)
  - Web search: [after](design/screens/04-search.png)
  - Social: [after](design/screens/05-social.png)
  - Numbers: [after](design/screens/06-numbers.png)
  - Username: [after](design/screens/07-username.png)
  - Sizes: [email small](design/screens/02-email-small.png),
    [email wide](design/screens/02-email-wide.png)
- **The bottom row:** 123 keeps its size and place in every kind, and so does space,
  so the thumb finds them where it always does (Gabriel, 9 Nov 2026). With two field
  keys (email @ and ., social @ and #), the first takes the emoji key's place; the key
  after space comes out of return, which gets shorter (never narrower than 123). A web
  search's "." comes out of return too. The new keys are white like the letters,
  because they type. When the globe is on the row it stays, and both keys go after
  space. In a web address there is no space bar, as in Apple's, and ".", "/" and
  ".com" share its room (".com" twice as wide as the other two). The split keyboard
  puts one key on each half beside its space, as before.
- **The return key:** the word in the key's own font at 16 pt, lower case like Apple's
  ("go", "search"). An action word is white on Apple's system blue; "next" and the
  plain return arrow stay on the dark function key. Waiting for text: the key at 40%
  and touches on it do nothing.
- **Space:** reads "Astrotype" in every kind that has one, as today.
- **Motion and copy:** no new animation. When the field changes kind while the
  keyboard is up (tapping from the To field to the body in Mail), the bottom row
  swaps with no animation, as Apple's does. New key labels only: "@", ".", "/",
  ".com", "#", and the return words above. No new bar notes.
- **Design system:** uses `Key` and the keycap styles that exist. Adds key kinds to
  `Layout` (`.symbol` already types one character; ".com" is a new `.text("…")` key
  that types a string) and one colour token, `returnAction` (Apple's system blue, `#007AFF` light and
  `#0A84FF` dark), for the action return key.
- **Sizes:** the new keys use the same unit as the letters, so they scale with the
  keyboard on every size and with the keyboard height setting. On the small size,
  space in the email row is still nearly three letter keys wide; on the wide size,
  the row is centered like the letter rows.
- **Accessibility:** VoiceOver reads the new keys by name ("at", "dot", "slash",
  "dot com", "hash") and the return key by its word ("Search", "Go"), and says
  "dimmed" while it waits for text. Nothing new for Dynamic Type or Reduce Motion.
- **Open questions:** none (see Product).

## Build

Status: Approved 2026-11-03 (built with the design, as Gabriel asked)

- **Approach:** one pure value, `Field` (AstrotypeCore), holds what the app said
  about the field and decides everything from it. The extension reads UIKit's traits
  into it (`KeyboardViewController.field`) when the keyboard appears and on every
  `textDidChange` (which also fires when the cursor moves to another field), and
  hands it to `KeyboardModel.field`. The model folds it into the engine's settings
  on top of the person's (`Field.composerSettings`: it only takes away), and the
  views read the bottom row and the return key from it.
- **Core pieces:**
  - `Field`: `kind`, `returnKey` (`label`, `isAction`, `spokenName`), `capitals`,
    `exactTaps`, `spacesWords`, `autospaces`, `learns`, `bottomRow`, `startPage`,
    `composerSettings(_:)`.

        let field = Field(keyboard: .email, returnKey: .next)
        composer.settings = field.composerSettings(personsSettings)

  - `Composer.Settings` gains `capitals`, `exactTaps` and `spacesWords`;
    `Composer.press(text:)` types a string (".com") like a character.
  - `Layout.qwerty(..., bottom:)` with `Layout.BottomRow` puts the field's keys
    beside space on the letters page; `Key.text(String)` is a key that types a string.
  - `KeyboardModel.field`, `.returnEnabled`; `TextTarget.hasText`;
    `KeySurfaceView.returnKey` and `.returnEnabled`; the `returnAction` colour token.
- **Phases:** one, this PR. Done when, on a phone: the To field in Mail shows @ and .
  and "next", and "name@example.com" typed by taps goes in exactly, with no space or
  capital; Safari's address bar shows . / .com and a blue "go"; a search field shows
  a blue "search", dimmed until something is typed; a number field opens on 123;
  Messages is unchanged. Checked at the small size, the largest text size and the
  wide size (split too).
- **Also in it:** a password, one-time code, card, phone or postal code field (when
  iOS does not swap in its own keyboard) is typed exactly, with no spaces after
  words and no capitals. A word pecked in a field that doesn't learn is no longer
  added to the learned words either (it was, before: only the personal model
  stopped).
- **Risks:** an app that sets odd traits (a search field with corrections off)
  gets exact taps there; that is what it asked for. Apps that never set a keyboard
  type keep today's keyboard.
- **Metrics:** none (see Product).
- **Last step:** folded into `DESIGN.md` ("The keyboard", "Field types") and
  `PRODUCT.md` in this PR.

## Notes as it shipped

- **Return that acts (13 Nov 2026, PR #236).** Where return is Search, Go, Send, Next
  and the rest, the app only acts on a "\n" that arrives alone, so the keyboard sends
  the word first and the "\n" a moment later (`KeyboardModel.apply`). Pecked letters go
  in as typed on such a return ("sli" searched once the app offered Slickdeals, not
  fixed to "i"), aren't learned, and look-back leaves the word before alone
  (`Composer.Settings.returnActs`).
