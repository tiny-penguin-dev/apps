# Astrotype: Text replacements

Type a shortcut as a word and the keyboard writes a phrase in its place, like iOS's
own text replacement. A phrase can hold variables (`{date}`, `{time}`, …) that fill in
as it goes in.

## Product

Status: Approved 2026-11-08 (Gabriel asked to build the basic version straight away
and merge it, then propose what comes next)

- **The ask** (Gabriel, 8 Nov 2026): "things you type and what they get replaced by",
  plus smart replacements: "text replacement that inserts a date or something like
  that… kind of like variables". Start with a predefined set of variables.
- Snippets and text replacements are one feature here: a snippet is a replacement
  with a longer phrase. Nothing about them needs a second list or screen yet.
- Free, like iOS's own.

## Design

Status: Approved 2026-11-08 (built straight from the ask)

- **Settings → Your words → Text replacements**: a list (shortcut bold, phrase below),
  newest first, search, swipe or Select to delete, + to add, tap to edit. A switch to
  also use the iPhone's own replacements (on by default).
- **The sheet**: Shortcut (one word of 2 to 24 characters; symbols allowed since
  phase 2), Phrase (several lines allowed), chips that add each variable,
  and "Right now it writes" with the variables filled in.
- **On the keyboard**: tap or swipe the shortcut. While it is the open word, the bar's
  chosen pill shows the phrase (what space will write). Space, punctuation, autospace
  or tapping the pill writes the phrase. Right after, the bar (or the pencil, when next
  words show) offers the shortcut as typed, to take it back; backspace right after
  reopens the shortcut. A capital on the shortcut (sentence start, shift) capitalises
  the phrase.
- **Where**: everywhere the keyboard learns, and in email and web address fields (a
  shortcut for your address). Not in passwords, codes, numbers, fields with
  corrections off, emoji search or the app's practice fields.

### Variables

`{date}` Nov 8, 2026 · `{time}` 8:51 AM · `{day}` Sunday · `{month}` November ·
`{year}` 2026 · `{tomorrow}` · `{yesterday}`, written in the phone's language and time
zone. A name in braces that is no variable stays as written.

## Build

Status: Approved 2026-11-08

- `TextReplacement` / `TextReplacements` (Core, `Engine/TextReplacements.swift`): the
  lookup (own beat the phone's on the same shortcut), shortcut rules, `expand` for the
  variables.
- Kept in `KeyboardSettings.textReplacements` (+ `usesPhoneReplacements`), so they
  reach the keyboard through the App Group and sync through iCloud with the settings.
- `Composer.Settings.replacements` / `replacesText` (from `Field.replacesText`);
  `Composer.commit` writes the phrase (`replace`), `State.replacement` is the bar's
  preview, `Committed.replaced` keeps it out of learning. The one clock read is
  `Composer.wallClock`.
- `Matcher.shortcuts`: the shortcuts are searched with the person's own words at a
  fairly common word's prior (`shortcutPrior`), so a swipe can land on one.
- The phone's replacements: `KeyboardViewController.readPhoneReplacements`
  (`requestSupplementaryLexicon`, entries whose shortcut differs from the text; the
  rest are contact names), into `KeyboardModel.phoneReplacements`. Not stored.
- Tests: `TextReplacementTests`.

## Phase 2: more powers

Status: Approved 2026-11-08 (Gabriel: "Okay, do all of them" to the seven ideas
proposed after the first build)

### Design

- **More variables**: `{date+7}` / `{date-1}` (days from today), `{next friday}` (any
  weekday, English or the phone's language), `{pick:thanks|cheers|ty}` (one at random;
  the bar shows the pick space will write), `{name}` `{email}` `{phone}` `{address}`
  (Your details), `{clipboard}` (what was copied; needs Full Access, read only as the
  phrase goes in, the bar shows "[clipboard]").
- **`{cursor}`**: the cursor lands there after the phrase goes in. No space is added
  after such a phrase; the bar goes idle (no taking back, since the cursor moved).
- **Blanks `{?who}`**: the shortcut stays as typed and the bar becomes the "Not it?"
  field asking "Who?". The keys type into it as written (shift for capitals, space
  types a space, 123 for digits); return or Save goes to the next blank, then the
  phrase goes in with the answers. ✕ leaves the shortcut as typed. A blank left empty
  writes nothing; a blank name used twice is asked once.
- **Snippet page**: a text button at the bar's right end (where the pencil goes when
  there is nothing to fix) opens a list of every replacement (the person's, then the
  iPhone's A to Z) in place of the bar and keys, over a strip with ABC, the title and
  delete. Tapping one writes its phrase at the cursor (an open word goes in first) and
  brings the letters back.
- **Suggest as you type**: with two letters typed, a shortcut they begin shows on the
  bar in the last guess's place, as its phrase. Tapping it writes the phrase.
- **Shortcuts with symbols**: a shortcut can be any 2 to 24 characters with no spaces,
  not only digits (";addr", "@@", "addr1"). Letters after a symbol (";" then "addr")
  are matched when the word goes in; one the keys don't type as a word ("@@") is
  replaced at space or return. Their letters are offered as words, so "addr" types
  as written.
- **Copy the iPhone's list in**: with Full Access the keyboard writes the iPhone's
  replacements to the App Group; Text replacements then offers "Copy N from your
  iPhone", which adds the ones with a new shortcut to the person's list to edit.
- **Your details**: a row on Text replacements opens a sheet (name, email, phone,
  address), kept with the keyboard settings and synced like them.

### Build

- `TextReplacements` (Core): `PersonalDetails`, `Context` (date, locale, time zone,
  clipboard and random closures, details, filled blanks), `expand(_:in:) -> Expansion`
  (text + `cursorFromEnd`), `blanks(in:)`, `completion(of:)`, the relaxed `shortcut(_:)`
  and `isWord`.
- `Composer`: `Settings.details`; `clipboard` and `random` closures (the pick is
  rolled once per phrase, `pickRoll`, so the bar and the field agree);
  `putReplacement` / `finishReplacement` write a phrase (cursor via `.moveCursor`);
  blanks reuse the "Not it?" field with a `Filling` and `State.fillPrompt`;
  `replaceToken` for symbol shortcuts at space/return; `completion` adds the shortcut
  guess and `State.previews` holds each bar word's phrase; `write(replacement:)` for
  the snippet page (logged as `TypingEvent.Kind.snippet`, replayed by `TypingReplay`).
- UI: `BarView` (`previews`, `fillPrompt`, `offersSnippets` / `onSnippets`),
  `SnippetsPageView`, `KeyboardView.showSnippets`, `KeyboardModel.snippets`,
  `write(replacement:)`, the pasteboard for `{clipboard}`.
- `PhoneReplacementsFile` + `KeyboardFiles.phoneReplacements`; the keyboard writes it in
  `readPhoneReplacements` (now read even with "Use your iPhone's too" off).
- App: `TextReplacementsView` (Your details sheet, Copy from your iPhone, the variable
  list, the cursor shown in the preview), `AppModel.copyReplacements`, `saveDetails`.
- Tests: `TextReplacementTests`.

## Later

Recurring dates ("{next friday}" in other languages' grammar), snippet folders, and
snippets synced as their own list if they outgrow the settings file.
