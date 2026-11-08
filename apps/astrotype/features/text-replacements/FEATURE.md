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
- **The sheet**: Shortcut (one word of 2 to 24 letters, since the keys only type
  letters into a word), Phrase (several lines allowed), chips that add each variable,
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

## Later

Ideas to pick from, proposed after the first build: more variables, the clipboard,
where the cursor lands, fill-in prompts, a picker on the keyboard.
