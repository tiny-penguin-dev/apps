# Astrotype: autofill

When a field asks for your name, email, address or phone, the guesses bar offers your
own details, so one tap fills it. Uses the details people already set up for text
replacements (`{name}`, `{email}`, `{phone}`, `{address}`).

## Product

Status: Draft

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
  | Username | email (most usernames are emails) |
  | Password, new password, card, one-time code | nothing (iOS or the app handles them) |

- **Fields that don't say.** We guess from what we can see:
  1. An email keyboard: email.
  2. Capitals on each word and nothing else: name first, address second.
  3. **Start typing:** in any field, typing the first 2 letters of one of your details
     ("ga" for Gabriel, "gab" for your email) offers it in the bar. This works even in
     the worst forms and in chats, and needs nothing from the app.
  4. **Chat phrases** (asks first, see question 2): "my email is", "my address is",
     "call me at" just before the cursor offers that detail.
- **Your details** grows from 4 lines into a small profile: first name, last name,
  email, phone, street, city, state, postal code, country, and (optional) company and
  birthday. `{name}` and `{address}` keep writing the full name and full address. A
  "Fill from contacts" button in the app opens Apple's contact picker so you can pick
  your own card in one tap (no Contacts permission needed).
- **Where it lives:** Settings → Typing → Autofill (on by default), with the Your
  details sheet. Text replacements keeps its link to the same sheet.
- **Privacy:** details stay on the phone and sync only through your iCloud settings
  like today. Nothing about fields or details is ever sent, and nothing is learned
  from these fields.

### Scope

- *Now:* content-type autofill, the email-keyboard and capitals guesses, start-typing
  matches, the bigger Your details sheet with Fill from contacts.
- *Later:* chat phrases (if yes to question 2), more than one address (home, work),
  the "switch keyboard" button for usernames and cards.
- *Never:* storing passwords or cards, or reading other apps' saved logins.

### What we measure

Nothing new from the keyboard (`docs/telemetry.md`: it sends crash reports only). In
the app, an anonymous count of people who filled in Your details, so we can see if the
feature gets set up.

### Open questions for Gabriel

1. **Free or Pro?** Recommend free: Apple's keyboard does this, so it's part of being
   on par with it.
2. **Chat phrases:** the field-types plan said we'd never read what's in a field to
   guess its kind. Start-typing only looks at the word you're typing, so it's fine.
   Chat phrases look a few words back (on the phone only). OK to do that later?
   Recommend yes, later.
3. **Username fields:** offer your email (recommended), or let you set a separate
   username?

## Design

Status: Draft. Mockups come once the product questions are answered.

- The detail shows in the bar's middle slot as one pill (or name split into full /
  first / last), with a small person icon so it reads as "yours", not a guess.
- Tapping it fills the field; the bar then goes back to normal.
- Your details sheet: grouped fields (Name, Contact, Address, More) with Fill from
  contacts at the top.

## Build

Status: Not started

- `Field.Content` gains the profile content types; `KeyboardViewController.field`
  maps the extra `UITextContentType`s.
- `PersonalDetails` gains the split fields, keeping old saved settings readable and
  `{name}` / `{address}` writing the joined values.
- A small `Autofill` in AstrotypeCore: given a `Field` and the open word, which details
  to offer. Unit tested like `FieldTests`.
- The bar shows the offer through the same path as text replacement pills.
