# StackWrite v2: design

Status: Draft

Builds on `PRODUCT.md` (approved 2026-11-01).

## Mockups

- Clickable mockup: `design/mockups/stackwrite.html` (Artifact link:
  https://claude.ai/artifact/PckLFxQcL1QDv5R3kSDZzc)
- Screenshots: `design/screens/`

The keyboard in the mockup is real: keys tap, swipes draw trails and are decoded against
the app's own 1,500 most common words, and on a phone both thumbs work at once. It is a
sketch of the feel, not the engine: the matcher is a crude subsequence lookup, so it
guesses wrong more often than the real one will.

## Look

- **Feeling:** ice and speed. A pale glacier background, cool teal for actions, and two
  thumb colors that show up everywhere typing happens.
- **Colors (light / dark):**
  - Background: glacier `#F3F8FA` / deep water `#111A24`
  - Cards and keys: white `#FFFFFF` / `#1A2634` (keys `#2A3A4A`)
  - Text: penguin navy `#1E2945` / `#EEF4F8`
  - Main color (buttons, links, open word): teal `#139FB5` / `#2FC6DC`
  - Left thumb: the same teal. Right thumb: coral `#FF6F86` / `#FF8A9E`. Every trail,
    key flash and drill hint uses these two, so people learn which thumb did what.
  - Pro: sun yellow `#FFC24D`. Done and on: mint `#2FBF96`. Ice `#D9EDF3` for chips.
  - Keyboard background: `#DCE6EC` / `#131E29`, close to Apple's so the keyboard feels at
    home in any app.
- **Type:** SF Pro Rounded in the app. On the keys, the same face at 21 pt, bold, so
  letters read at a glance under a moving thumb. Numbers use tabular figures.
- **Shapes:** big round corners in the app (18 to 28 pt), pill buttons with a pressable
  bottom edge. Keys are 7 pt radius like Apple's, because the keyboard must feel like a
  keyboard, not like the app.
- **App icon idea:** Pip facing you with both flippers up, a teal and a coral trail
  crossing behind, on glacier white.

## Screens

| # | Screen | What it's for | Screenshot |
|---|---|---|---|
| 1 | Hello | Pip waddles in, flippers typing. "Type with both thumbs." One button. | [01](design/screens/01-hello.png) |
| 2 | Turn on the keyboard | The three Settings steps, a status chip that flips to "On" when the keyboard appears, "Open Settings". | [02](design/screens/02-turn-on.png) |
| 3 | Keep your words everywhere | The Full Access ask, with its one reason (iCloud sync of words and settings) and "Nothing you type is ever sent anywhere". Skippable. | [03](design/screens/03-sync.png) |
| 4 | Try it | A practice field with the keyboard up. Five words, each with a thumb-by-thumb hint. "Show me" replays the word with trails. | [04](design/screens/04-try.png), [dark](design/screens/04-try-dark.png) |
| 5 | Home | "Both flippers, go." Speed test card (best, versus Apple's keyboard), trial status, drills, this week, Settings. A yellow banner if the keyboard is not on. | [05](design/screens/05-home.png), [dark](design/screens/05-home-dark.png) |
| 6 | Speed test | A sentence to type with the typed part turning mint, a timer, the keyboard. | [06](design/screens/06-speed.png) |
| 7 | Speed test result | Pip running, the words per minute, fixes, versus Apple's, fish confetti on a new best. | [07](design/screens/07-result.png) |
| 8 | Drill | One habit per drill. Word cards, the keys of the next word outlined in the thumb's color. | [08](design/screens/08-drill.png) |
| 9 | Settings | Typing (two-thumb, autospace and its delay, learned words), gestures, layout, look, sync, Pro. | [09](design/screens/09-settings.png) |
| 10 | StackWrite Pro | Pip proud, four perks, yearly and monthly, "Start 14 days free". Prices are placeholders for Gabriel. | [10](design/screens/10-pro.png) |
| 11 | Trial over | Pip asleep in a nightcap. What is resting, what still works, the person's own best speed as the reason to keep Pro. | [11](design/screens/11-trial-over.png) |
| 12 | Typing in Messages | The keyboard in another app. Bar in "Fix" mode after a commit, the open word underlined in the field. | [12](design/screens/12-messages.png), [dark](design/screens/12-messages-dark.png) |
| 13 | Free keyboard | After the trial: taps and one-finger swipes. A second thumb shows "Two thumbs is in StackWrite Pro" in the bar instead of typing. | [13](design/screens/13-free.png) |

Not drawn yet (simple, same style): the numbers and symbols pages, the in-keyboard
settings panel (gear under the `123` hold menu, for when Full Access is off), learned
words list, snippets editor, split and one-handed layouts, the milestone sheet.

## The keyboard

This is the product, so it gets its own section.

- **Layout:** Apple's QWERTY proportions, so muscle memory carries over. Rows of 10, 9
  and 7 letters, shift and backspace on the third row, `123`, globe, space and return on
  the fourth. Space reads "StackWrite" when idle, like Apple's reads the language.
- **The bar** above the keys has three states:
  - *Idle:* a short note ("Both thumbs, one word") or, with nothing to say, empty.
  - *Open word:* up to three guesses, the first one in a white pill. That one is what
    space writes. Tapping any guess writes it.
  - *Fix:* right after a commit, the label FIX and the other readings of the last word.
    Tap one and it replaces the word just written. Any new tap or swipe clears it.
- **Pieces:** a touch is a tap if it lifts within 18 pt of where it landed and crossed no
  other key, otherwise a swipe. Taps flash the key in the thumb's color and leave a ring
  that pings out. Swipes draw a 9 pt rounded trail in the thumb's color that fades over a
  second after lift. Which thumb: left half of the keyboard is teal, right half coral.
  (The real engine will tell thumbs apart by touch identity and position, not only by
  side.)
- **The open word** shows in the text field underlined in teal, so the person sees what
  space will write without looking at the bar.
- **Commit:** space, punctuation, or autospace after 0.9 s with no finger down (the
  delay is a setting, 0.5 to 1.5 s). On autospace the bar gives a tiny squeeze so the
  person notices the word went in.
- **Backspace:** with an open word, removes the last piece. Otherwise one character.
  Swipe left on it deletes the last word; the keys to the left of it do not need to be
  crossed, 40 pt of travel is enough.
- **Shift:** one tap capitalises the next word, two taps lock caps. Sentence starts are
  capitalised automatically.
- **Free mode:** one active thumb at a time. A second touch does not type; the bar says
  "Two thumbs is in StackWrite Pro" for 1.6 s. Nothing shakes, nothing is lost.
- **Not in the mockup, in the build:** slide on space to move the cursor, the numbers
  page, edge swipes, snippets, long-press accents, the globe key switching keyboards.

## Flows

- **First launch** (PRODUCT 5.1): Hello → Turn on the keyboard → Keep your words
  everywhere → Try it (five words) → Home. Everyone starts on the Pro trial, so Try it
  teaches two thumbs from the first word.
- **Typing a word** (5.2): pieces → open word in the bar and the field → space, pause or
  punctuation commits → the bar offers fixes for a moment → next word.
- **Learning** (5.3): tapping out an unknown word letter by letter learns it on commit.
  Hold a guess in the bar and slide up or down to boost or forget it (not in the mockup).
- **Practice** (5.4): Home → Speed test → Result → Again or Done. Home → Drill → five words
  → back to Home with the drill ticked.
- **Customize** (5.5): Home → Settings. Pro rows carry the PRO badge and open the Pro
  screen when the trial is over.
- **Trial end:** on the first launch after the trial ends, the Trial over sheet. From then
  on, the Free keyboard with its one-line nudge, never a popup inside another app.
- **Keyboard not on:** the Home banner, and Settings' sync row, both lead back to the
  setup screens.

## Mascot

Pip is Tiny Penguin's penguin with both flippers up, typing. The same family as Squawk's
penguin (navy arch body, white belly, golden beak and feet) so the studio's apps look
related, drawn with simpler shapes: flippers are rotated ellipses so they can swing.

| Mood | Looks | Where |
|---|---|---|
| Typing | Flippers up, alternating like two thumbs | Hello, Full Access, Home |
| Awake | Flippers down, breathing | Setup, Settings |
| Proud | Happy closed eyes, pink cheeks, hopping | Pro, a new best |
| Running | Flippers up, bouncing fast | Speed test result |
| Asleep | Closed eyes, coral nightcap, floating z's | Trial over, empty history |

Pip never appears on the keyboard itself. Outfits (Pro and milestone rewards): scarf,
beanie, headphones, a tiny keyboard necklace.

## Motion

- **Trails and flashes** are the main animation and they carry meaning: which thumb,
  which keys, where the swipe went. They are quick (the trail fades in 1.2 s, the tap ring
  in 0.6 s) so they never lag behind typing.
- **Keys** scale up 6% when hit and spring back.
- **Springs** in the app: screens slide in with a small overshoot, buttons squash, toggles
  wobble.
- **Pip:** waddles in on Hello, flippers type while idle on Home, hops when proud, bounces
  on the result screen.
- **Speed test:** the typed words turn mint one by one. A wrong word shakes the field.
- **Success:** fish confetti on a new best and when the keyboard is first turned on.
- **Haptics:** a light tap on every commit, a softer one on each key hit if Full Access
  allows it (checked in the build), success on a new best, error on a wrong drill word.
- **Sounds:** none in v1. Key clicks are a later setting.
- **Reduce Motion:** trails still draw (they are information) but do not fade with
  motion, just disappear; no key scaling, no waddle, hop or confetti; screens fade.
- **Battery saver and Zen mode:** a setting that turns trails and flashes off.

## Copy

- Hello: "Type with both thumbs." / "Tap with one, swipe with the other, mix them any
  way you like. Press space when the word looks right. I'm Pip, I'll show you." /
  **Let's go**
- Turn on: "Turn on StackWrite" / "iPhone keyboards switch on in Settings. It takes three
  taps, and I'll know when it's done." / **Open Settings**, I'll do it later / chip: "Not
  on yet" → "On" / "StackWrite is on. Hold 🌐 in any app to pick it."
- Full Access: "Keep your words everywhere" / "StackWrite learns your words. With Full
  Access they sync over iCloud to your other devices, along with your settings. That is
  the only thing it is used for. Nothing you type is ever sent anywhere." / **Open
  Settings**, Skip for now
- Try it: "Type this word" / "Left thumb taps s and e. Right thumb swipes o→m, then
  t→h→i→n→g. Space when it says something." / **Show me**, or just try it
- Home: "Both flippers, go." / banner: "StackWrite isn't on yet." **Turn on** / "Pro
  trial · 11 days left."
- Bar notes: "Both thumbs, one word" / "Tap or swipe. Space writes the word." / FIX /
  free: "One finger at a time", "Two thumbs is in StackWrite Pro"
- Speed test: "Type this" / result: "52" "words per minute" / "3 words needed a fix.
  That's 21 faster than Apple's keyboard and a new best." / **Again**, Done
- Drill: "Switching thumbs" / "Left swipes w→e, right swipes n→t. Keys light up to show
  which thumb."
- Pro: "StackWrite Pro" / "The fast keyboard, all of it." / **Start 14 days free** / "Then
  $19.99 a year. Renews automatically, cancel anytime."
- Trial over: "Your trial ended" / "Two-thumb typing, gestures and layouts are resting.
  The keyboard still works with taps and one-finger swipes, and your learned words are
  safe." / **Keep two-thumb typing**, Stay on the free keyboard
- Errors: "I couldn't sync your words. Check that iCloud is on for StackWrite in
  Settings." No puns in errors.

## Accessibility

- **Dynamic Type:** the app scales fully. The keyboard follows the system keyboard's
  sizing instead, because its height is what people's thumbs have learned; the bar text
  scales one step.
- **VoiceOver:** the keyboard works like Apple's (touch to hear a key, double-tap or lift
  to type; swipe typing is off under VoiceOver). The bar reads "Suggestions" with each
  guess, the first as "selected". Pip images read their mood ("Pip the penguin, typing").
  Trails and flashes carry no information VoiceOver needs: the bar does.
- **Order:** title, main content, the main button.
- **Contrast:** text and buttons meet WCAG AA in both themes; the teal button uses navy
  text in dark mode. Teal and coral are also different in brightness, so the two thumbs
  stay apart for people who cannot tell the hues.
- **Reduce Motion:** see Motion. Trails remain, because they say which keys a swipe hit.
- **One thumb:** everything works with one finger and swipes; two thumbs is faster, never
  required.

## Open questions

1. Pro prices: $19.99 a year and $2.99 a month are placeholders on the Pro screen. Pick
   the real ones.
2. The mascot's name: Pip is a placeholder.
3. The app icon: Pip with trails, or a plainer keyboard mark with the two colors?
