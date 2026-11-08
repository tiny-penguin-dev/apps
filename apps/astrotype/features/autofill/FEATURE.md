# Astrotype: autofill

When a field asks for your name, email, address or phone, the guesses bar offers your
own details, so one tap fills it. Uses the details people already set up for text
replacements (`{name}`, `{email}`, `{phone}`, `{address}`).

## Product

Status: Approved 2026-11-08 (Gabriel: "1. Free 2 yes 3. Both. Build it")

- **The ask** (Gabriel, 8 Nov 2026): know what kind of field we're in (email, username,
  password, card, address…) and offer autofill from the person's profile, like text
  replacements. Guess the kind when apps don't label their fields well. Passwords and
  cards later, ideally through 1Password or Apple Passwords, so we never store them.

### What a keyboard can see (checked 8 Nov 2026)

A keyboard only sees what `UITextDocumentProxy` gives it:

| Can see | Can't see |
|---|---|
| Keyboard type (email, URL, number, …) | Accessibility label or identifier |
| Content type (name, email, address parts, username, card number, one-time code, …) | Placeholder text or the label next to the field |
| Return key, capitals, corrections, secure entry | Which app it's in, or the web page |
| Text before and after the cursor (a few hundred characters) | Other fields on the screen |
| Selected text, and a per-field id that changes each time | Anything in the app's view tree |

- Content type is the useful one. Apps set it so Apple's own AutoFill works, and
  Safari and web views turn a web form's `autocomplete` (for example `given-name`,
  `street-address`, `email`) into the same content types. So well built forms tell us
  exactly what they want.
- Badly built forms only give us traits: an email keyboard (probably email), capitals
  on each word (probably a name or an address), or nothing.
- Password and phone-pad fields aren't ours: iOS always switches to its own keyboard.
  Apps can also refuse third-party keyboards everywhere.

### 1Password and Apple Passwords

- **Neither has an API a keyboard can use.** 1Password's SDKs are for developer
  secrets on servers, not your vault. Apple Passwords and the keychain are closed to
  other apps.
- **The good news:** password fields already switch to Apple's keyboard, and its bar
  already shows 1Password and Apple Passwords through iOS AutoFill. So passwords work
  today without us doing anything.
- **The gap** is the username or email field just before it, where our keyboard stays
  and Apple's "Passwords" suggestion isn't shown. Later we could show a key button in
  the bar on username fields that switches to the next keyboard. Card fields are not
  secure fields, so ours shows there: we never fill cards, same button.

### What it does

- **Fields that say what they want.** When the keyboard opens on (or moves to) an empty
  field with one of these content types, the bar shows the matching detail in the
  middle slot. Tap it to fill the field. No space after it.

  | Field asks for | Bar offers |
  |---|---|
  | Name, given name, family name, nickname | full name, first name, last name |
  | Email | email |
  | Phone | phone |
  | Street address, city, state, postal code, country, full address | that part |
  | Company, job title | those, if set |
  | Username | your username, then your email |
  | Password, new password, card, one-time code | nothing (iOS or the app handles them) |

- **Fields that don't say.** We guess from what we can see:
  1. An email keyboard: email.
  2. Capitals on each word and nothing else: name first, address second.
  3. **Start typing:** in any field, typing the first 2 letters of one of your details
     ("ga" for Gabriel, "gab" for your email) offers it in the bar. This works even in
     the worst forms and in chats, and needs nothing from the app.
  4. **Chat phrases:** "my email is", "my address is", "call me at", "me llamo" and
     the like, right before the cursor (with the space), offer that detail. Only the
     few words before the cursor are read, on the phone.
- **Your details** grows from 4 lines into a small profile: first name, last name,
  email, phone, username, street, city, state, postal code, country, and (optional)
  company and job title. `{name}` and `{address}` keep writing the full name and full address. A
  "Fill from contacts" button in the app opens Apple's contact picker so you can pick
  your own card in one tap (no Contacts permission needed).
- **Where it lives:** Settings → Typing → Autofill: "Offer your details" (on by
  default) and the Your details sheet. Text replacements keeps its link to the same
  sheet. Free.
- **Privacy:** details stay on the phone and sync only through your iCloud settings
  like today. Nothing about fields or details is ever sent, and nothing is learned
  from these fields.

### Scope

- *Now:* content-type autofill, the email-keyboard and capitals guesses, start-typing
  matches, chat phrases, the bigger Your details sheet with Fill from contacts.
- *Later:* more than one address (home, work), a birthday, the "switch keyboard"
  button for usernames and cards.
- *Never:* storing passwords or cards, or reading other apps' saved logins.

### What we measure

Nothing new from the keyboard (`docs/telemetry.md`: it sends crash reports only). In
the app, `details.saved`: counted once when Your details go from empty to set, so we
can see if the feature gets set up. Never what was written.

### Answered (Gabriel, 8 Nov 2026)

1. Free.
2. Yes to chat phrases. This changes the field-types plan's "never read what's in a
   field": only the few words right before the cursor, to offer a detail, never to
   decide the field's kind, and never sent anywhere.
3. Username fields offer both: your username and your email.

## Design

Status: Approved 2026-11-08 (Gabriel: "Build it", built straight from the plan with no
mockup, like text replacements)

- **On the bar, nothing typed:** the details take the middle in place of the next
  words, up to three, each with a person icon in front (`person.crop.circle.fill`, dim
  ink) and the detail in the readings' ink, so it reads as yours, not a guess. A long
  detail (an address) is cut short at 220 pt. Tapping one writes it at the cursor
  with no space after it.
- **On the bar, typing:** a detail you're typing takes the place of the last guess, on
  the left, so it is dropped last on a narrow bar. Tapped, it goes in place of what was
  typed, and the bar offers what was typed back (as after a text replacement);
  backspace reopens it.
- **Settings → Typing → Autofill:** a switch, "Offer your details", and a "Your
  details" row (name and email when set, "Not set yet" otherwise). Footnote: "Also when
  you start typing one of them, or write "my email is". Passwords and cards switch to
  Apple's keyboard, where your password app fills them."
- **Your details sheet:** "Fill from contacts" at the top (Apple's contact picker, no
  permission), then Name (first, last), Contact (email, phone, username), Address
  (street, city, state, postal code, country) and More (company, job title).
- **Accessibility:** each detail on the bar reads as the detail, with the hint "Fills
  in your detail" or "Finishes it with your detail".

## Build

Status: Built 2026-11-08

- `Autofill` (AstrotypeCore): `Slot` (one detail and how to read it from
  `PersonalDetails`), `offers(for:details:before:)` for an empty field or a chat
  phrase, `completion(of:slots:details:)` for a detail being typed. Tested in
  `AutofillTests`.
- `Field` gains `asks` and `autofillSlots`; `KeyboardViewController.field` maps the
  `UITextContentType`s (`autofillSlots` table).
- `PersonalDetails` is split (first and last name, address parts, username, company,
  job title); older saved details still read, and `name` and `address` are written
  too for older keyboards on other devices.
- `Composer.State.autofill` and `Composer.fill(autofill:time:)`, which writes through
  the replacement path (`literal`, so no variables). Logged as `af` with the index only.
- `BarView.autofill` / `onAutofill`; `KeyboardSettings.autofill`; app:
  `YourDetailsSheet`, Settings → Typing → Autofill.
