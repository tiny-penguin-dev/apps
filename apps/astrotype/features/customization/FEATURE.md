# Astrotype: Keyboard styles

Appearance becomes a section of three pages (General, Styling, Effects) so people can
make the keyboard their own: themes with a light and a dark look, their own theme down
to the key borders and spacing, and effects that build up as they type fast, from
sparks to falling snow to an aurora moving behind the keys.

Gabriel, 6 Nov 2026: "Split the appearance page into a full section with multiple
pages under. 1. General: most of the options the appearance page has right now except
the trails and flashes. 2. Styling: key colors, the key foreground color, spacing
between keys, a border for keys, etc. Easy to use but also powerful. Support light and
dark. A standard set of themes, but allow custom. 3. Effects: tap circles, swipe
effects, etc. Make the effects grow as you type more and get into a flow, kinda like
combos, and everything gets crazy. Customizable: stars, particle effects, Metal
shaders. This should make the keyboard feel super cool."

On Pro (6 Nov 2026): all of it is Pro, except the base default style and the base
default effects (what the keyboard has today), which stay free.

On the plan (6 Nov 2026): "Looks good overall. But add more advanced stuff for the
effects that morph the letters and maybe even use Metal. Go ahead and build it and
we'll test it for real."

## Changes after testing (Gabriel, 6 Nov 2026)

- The keyboard's background is never themed: it stays the system's see-through
  backdrop. Themes set the keys, letters, borders, thumbs and accent only (the
  `background` colour in saved themes is ignored).
- No flow meter line and no level-name pop. The combo count shows on the space bar
  ("Astrotype  ×12"), and the space bar bounces when a level is reached.
- The higher levels never showed in testing because Low Power Mode was on (it caps
  flow at Toboggan). The Effects page now says so when Low Power Mode is on.
- Flow drains sooner: after 1 s without typing, the space bar count drops 1 a second
  and the effects fade with it (was a 2.5 s wait, then 1.5 a second).
  Building up is unchanged. Tapping space no longer counts as a word on its own.
- See-through keys is set for the light and the dark look apart (in the editor's
  Colours, under the look picker), not once in the shape.

## Product

Status: Approved 2026-11-06 (Gabriel: "Go ahead and build it")

- **The problem:** the keyboard has one look: Apple's grey keys, with trails and
  flashes on or off. People spend hours a day looking at their keyboard and like to
  make it theirs. Fast typists also get nothing back for being fast; a keyboard that
  reacts to a good run is more fun to practise on, and more fun to show a friend.
- **Who wants it:** most people will pick a theme and stop there. A smaller group will
  build their own theme or tune the effects, and want real control.
- **Basics or powerful:** picking a theme or an effects preset is basic (one tap). Your
  own theme and the flow levels are powerful, one level down.
- **How it works:**
  - *Appearance* (from Settings) becomes a short page: a live keyboard in your current
    style at the top (tap and swipe on it), then three links: **General**, **Styling**
    and **Effects**, each with a one-line summary.
  - *General:* everything Appearance has today except trails and flashes: Height,
    Guesses bar, Haptics, Underline the open word, and the wide-screen layout.
  - *Styling:*
    - **Light or dark:** always the phone's mode. (A Like my phone / Light / Dark switch
      was here; Gabriel removed it on 8 Nov 2026 after it locked the keys dark on a light
      phone, since the glass behind the keys always follows the phone.) A Light look /
      Dark look switch under the preview flips only the preview and the cards, never
      saved, so both looks can be checked.
    - **Themes:** eight ready-made themes, each with a light and a dark look. Classic
      (today's Apple-like keys, free), Iceberg (pale blue, Astrotype's teal), Tuxedo
      (black keys, an orange beak for the thumb colour), Krill (pink and coral),
      Midnight (deep blue, thin glowing borders), Paper (outlined keys on cream),
      Arcade (neon outlines, mono letters), Bold (high contrast, thick borders).
    - **Your themes:** "New theme" copies the current theme and opens the editor. You
      can keep several. Tap one to use it, tap it again to change it.
    - **The editor:** a name, then "Light look / Dark look" with "Same colours in
      both". Colours: Background, Keys, Letters, Shift-delete-123 keys, and under "More
      colours" the two thumb colours, the border and the accent. Each colour is a row
      of suggested swatches plus the full colour picker. Shape: Space between keys,
      Corners, Border (None, Thin, Bold), Shadow (None, Soft, Raised), See-through keys
      (Glass to Solid). Letters: Rounded, Classic or Mono, and Show letters (blank
      keys, for show-offs). The keyboard under the editor shows every change live, in
      the look being edited. A "Hard to read" chip appears when letters and keys are
      too close in colour (contrast under 3:1).
  - *Effects:*
    - **Effects** on or off (off: keys just press, saves the most battery).
    - **Start from:** presets that set everything below: Calm (today's look, free),
      Arcade, Glitch, Rainbow, Space, Zen and Sugar Rush. Changing anything shows "Your
      mix". (Gabriel, 7 Nov 2026: quicker and wilder, flying in every direction instead
      of one side; Sparkle and Aurora went.)
      - *Arcade:* 8-bit pixel blasts, dashed pixel trails, blocky letters that hop,
        pixel fountains, and a neon retro grid racing in under a striped sun.
      - *Glitch:* split-colour bars, a jittering red/cyan trail, Glitch letters, static
        and keys that jolt at Blizzard, rows that tear over a glitching sky at the top.
      - *Rainbow:* fireworks, rainbow key flashes and trails, Disco letters (spin and
        flash through the rainbow), confetti cannons from both corners, a prism sky.
      - *Space:* stars in every direction, comets, Warp letters, stars rushing out from
        the middle, and at the top a black hole the letters lean into.
      - *Zen:* still fun but slow: petals, a silk trail, Wave letters, petals drifting in
        from both sides, rippling water.
      - *Sugar Rush:* the girly one, just as fast: hearts everywhere, candy-pink
        flashes, heart trails, Jelly letters, heart cannons, candy clouds with hearts.
      Each new level also blasts the preset's particles out from the middle.
    - **Keys:** what the keys themselves do, drawn by Metal over them (Gabriel, 7 Nov
      2026: "make it affect keys in cool ways"): Plain (free), Neon (outlines flare,
      lights chase round the keys with flow), Glitch (outlines split red and cyan,
      blocks corrupt, slices tear), Holo foil (a rainbow sheen), Warp (stars rush out of
      a key; at the top each key's edge facing the black hole burns), Ripple (rings run
      through the keys) and Candy gloss (a shine, pink glow, sparkles). It shares the
      Metal letters' layer, so it costs no second drawable.
    - **Build-up per touch** (Gabriel, 8 Nov 2026): with flow on, each touch's effect
      starts muted (about a third: fewer, smaller, slower particles, a gentler glitch,
      letters and keys bend less) and grows with the flow score to full strength at
      Blizzard. A pause or delete that drains flow calms them again.
    - **Edges:** the keyboard doesn't reach the screen's edges, so skies fade out before
      theirs and particles start a little in from the sides.
    - **Taps:** None, Ring (today), Ripple, Sparks, Stars, Snow, Pixels, Fireworks,
      Glitch, Hearts, Petals. **Key flash:** Thumb colours (today), Theme colour,
      Rainbow, Candy pinks, Off.
    - **Swipes:** trail None, Line (today), Comet, Glitter, Rainbow, Pixels, Glitch,
      Hearts, Silk.
    - **Letters:** what the letters themselves do when a thumb hits them. None
      (today), Pop (the letter bounces up), and seven drawn by Metal: Jelly (it
      squashes and wobbles), Wave (a ripple runs out from the touch through the
      letters around it), Glitch (red and cyan split apart and the letter slices
      sideways), Liquid (it melts and drips, then pulls back together), Pixel (blocky,
      hops like a sprite), Disco (spins and flashes) and Warp (stretches out from the
      middle). With flow on they get stronger at each level, and at Aurora the letters
      shimmer in the thumb colours.
    - **Flow** ("Build up as I type"): words typed fast without fixes fill a flow meter;
      each level adds more. A pause or a delete calms it down. Four levels, penguin
      themed, each one its own switch:
      1. **Waddle** (about 5 words): a combo count (×12) on the bar, taps and letter
         effects grow a little.
      2. **Toboggan** (about 15): trails become comets, finished words throw sparks.
      3. **Blizzard** (about 30): stars, snow, confetti, pixels, static, warp, petals or
         hearts fly across the keys from every side, keys glow.
      4. **Aurora** (about 50): a sky moves behind the keys: Aurora, Starfield, Ice,
         Retro grid, Glitch, Prism, Black hole, Ripples or Candy clouds (Metal shaders).
      "Builds" (Slowly to Quickly) scales the word counts. Each new level pops its name
      on the bar with a soft haptic.
  - *In the keyboard (hold 123):* the Trails tile becomes **Effects**, and a Theme row
    shows your themes as small swatches to switch between. This is how people without
    Full Access pick a theme, since the app can't reach their keyboard.
- **Flow, exactly:** each finished word adds 1 to the score, 1.5 if it came within
  1.5 s of the last one. A delete takes 3 off. After 2.5 s without typing the score
  drains at 1.5 a second; at zero the combo count resets. Thresholds are 5, 15, 30 and
  50, times 1.5 at Slowly and 0.5 at Quickly. Pure and tested, in Core.
- **Letters on Metal:** while a Metal letter effect is on, the letter keys' labels are
  drawn by one `CAMetalLayer` over the keys from a small glyph atlas (the 26 letters,
  both cases, in the theme's font, about 1 MB), each letter on a small grid so it can
  bend. It only draws while something moves, then keeps its last frame. If Metal is
  missing or the phone is in Low Power Mode, letters fall back to Pop.
- **Free and Pro** (Gabriel, 6 Nov 2026):
  - *Free:* the Classic theme in light and dark, the Calm
    effects (ring taps, line trails, thumb-colour flashes), and Effects off. That is the
    keyboard as it is today.
  - *Pro:* the other seven themes, your own themes, every other tap, trail and flash,
    the other presets, and flow.
  - Free people can still try everything on the live keyboards in Settings; choosing a
    Pro item opens the Pro screen. When Pro ends, the keyboard goes back to Classic and
    Calm, and remembers what you had, so it comes back if you subscribe again.
- **What it changes:** the Appearance page (screen 9's sub-page) becomes a section; the
  "Trails and flashes" switch becomes the Effects page (on by default, set to Calm, so
  nothing looks different after the update); the keyboard panel's Trails tile becomes
  Effects; `KeySurfaceView`'s trails, rings and flashes move into an effects layer that
  every effect draws through; keys and the bar draw from the chosen style instead of
  fixed `Theme` tokens.
- **Performance and memory:** the extension must stay under 40 MB and never drop a
  touch.
  - Keys never move or change size for an effect, and spacing only changes how keys
    are drawn: each key's touch area still reaches its neighbours (`Layout` is
    unchanged), so accuracy is the same in every theme.
  - Taps, trails and falling things are Core Animation layers (`CAShapeLayer`,
    `CAEmitterLayer`) on the GPU, capped at about 250 particles.
  - The Aurora sky is one small `CAMetalLayer` at half resolution with a precompiled
    shader, made only when flow first reaches Aurora and freed when flow drops back
    down. It runs at 30 to 60 fps, and only while it is showing. Budget: under 6 MB
    for all effects together, checked with the Debug page's memory readout and
    `keyboard.memory_peak`.
  - In Low Power Mode, or when the phone reports a serious thermal state, flow stops at
    Toboggan (no falling things, no sky).
  - Reduce Motion: no particles or moving sky; taps show a still dot, trails show and
    go, and flow shows only as the meter, the count and the key glow.
- **Scope:** this version: the three pages, eight themes, your own themes, the effects
  and flow above, the panel's Theme row. Later: share a theme with a friend (a link or
  code), custom key sounds, a background photo, per-app themes, themes that change with
  the time of day. Never: effects that move or resize keys, anything that slows a
  touch, ads or paid one-off theme packs.
- **What we measure:** sent from the app only (the extension never sends metrics):
  - `appearance.theme_chosen` (count, tag `theme`: the theme's id or `custom`): which
    themes people like, and whether custom themes get used.
  - `appearance.effects_chosen` (count, tags `preset` and `flow` on/off).
  - `keyboard.flow_peak` (distribution, from `keyboard-health.json` like the memory
    readings): the highest flow level reached per session, so we can tune the word
    counts.
  - The existing `keyboard.memory_peak`, watched for the effects budget.
- **Open questions** for Gabriel
  1. Default for new installs: Calm with flow off (today's look, recommended), or show
     off with Sparkle and flow on during the trial?
  2. Level names: Waddle, Toboggan, Blizzard, Aurora. Keep, or plainer (Level 1 to 4)?
  3. Should the combo count stay on the bar while you type, or only flash at each
     level-up? (Mockup: it stays.)

## Design

Status: Approved 2026-11-06 (Gabriel: "Go ahead and build it")

- **Mockups:** `design/mockups/customization.html` (Artifact link:
  https://claude.ai/artifact/3toYx2jU5GpNv6R6kvtpoe). Every keyboard in it is live:
  tap and swipe, or press "Play a burst" on Effects or "Typing in a chat" to watch flow
  climb to Aurora. The picker also switches size, light/dark and Reduce Motion, and
  "Appearance today" shows the current page.
- **What changes:**

  | Screen | Before | After |
  |---|---|---|
  | Appearance | [today](design/screens/01-before-appearance.png) | [section](design/screens/02-appearance.png) with [General](design/screens/03-general.png), [Styling](design/screens/04-styling.png), [Effects](design/screens/07-effects.png) |
  | Keyboard panel (hold 123) | Trails tile | [Effects tile and Theme row](design/screens/12-panel.png) |
  | The keyboard | one look | the chosen theme and effects ([flow at Toboggan](design/screens/09-flow-toboggan.png), [Blizzard](design/screens/10-flow-blizzard.png), [Aurora](design/screens/11-flow-aurora.png)) |

- **New screens:**
  - *Appearance* ([02](design/screens/02-appearance.png)): the live keyboard in a
    rounded card, a footnote saying to tap it, then the three links with their
    summaries ("Iceberg · follows your phone", "Aurora · flow up to Aurora"), and a
    footnote on Full Access.
  - *General* ([03](design/screens/03-general.png)): Size (Height, Guesses bar), Feel
    (Haptics, Underline), Wide screens PRO. The small `KeyboardPreview` goes, since the
    Appearance page now shows the real keyboard.
  - *Styling* ([04](design/screens/04-styling.png),
    [dark](design/screens/05-styling-dark.png)): the themes as a
    two-column grid of `ThemeCard`s (three on wide), each drawn in the look you are
    in, PRO on all but Classic. Your themes below with a dashed "New theme" card. The
    real keyboard sits at the bottom of the screen in the chosen theme, so a tap on a
    card shows it right away.
  - *Your theme* ([06](design/screens/06-own-theme.png)): name, Light look / Dark look,
    Colours (`SwatchRow`s), Shape, Letters, Delete theme. The keyboard at the bottom
    shows the look being edited.
  - *Effects* ([07](design/screens/07-effects.png),
    [flow levels](design/screens/08-effects-flow.png)): the Effects switch, presets as
    text chips, Taps and Swipes as `ChipPicker`s with a small drawing of each, then
    Flow: the switch, Builds, and the four levels as rows with a numbered dot in the
    level's colour, its word count, and its switch; Blizzard and Aurora show their
    choices under them. A Letters picker sits under Tap, its Metal ones noted.
    "Play a burst" sits top right and types a fast run on the
    keyboard below.
- **Motion and copy:**
  - Level-up: the level's name pops on the bar ("Blizzard!") with a spring, holds,
    then floats up and fades (1.1 s), with a soft haptic. The combo badge springs in at
    Waddle. The flow meter is a 3 pt line under the bar, from the left thumb's colour
    to the level's colour, that fills toward the next level and drains on a pause.
  - The sky fades in over 0.8 s at Aurora and out as flow drains.
  - Theme cards and chips squeeze to 95 to 97% on press. A theme change crossfades the
    keyboard (0.3 s).
  - Copy: "Build up as I type", "Fast words without fixes make the effects grow. A pause
    or a delete calms them down.", "Spacing only changes how keys are drawn. Each key
    still answers touches right up to its neighbours, so typing feels the same.",
    "Hard to read", "Your mix", "Classic is free and looks like Apple's keyboard."
- **Design system:**
  - New Core value `KeyboardStyle`: a theme (name, light and dark `KeyColors`, one
    `KeyShape`). The keyboard's look comes from it instead of the fixed `key`, `keyDark`,
    `keyInk`, `kb` and thumb tokens; `Theme` keeps those as the Classic theme's values.
    The mockup draws keys from the same fields (`--kkb`, `--kkey`, `--kfn`, `--kink`,
    `--kbc`, `--kbw`, `--krad`, `--kgap`, `--ksh`, `--kop`, `--kfont`, `--kleft`,
    `--kright`, `--kacc`).
  - New components: `ThemeCard`, `SwatchRow`, `ChipPicker` (one of a few, with an
    optional drawing and PRO tag), `FlowMeter`, `ComboBadge`, and in the keyboard the
    `EffectsLayer` (taps, trails, falling things) and `SkyLayer` (the shader).
  - Reuses `SettingsGroup`, `SettingsRow`, `SettingsToggle`, `SettingsSlider`,
    `SectionLabel(pro:)`, `GroupFootnote`, `Segmented`, `ProBadge`, `QuickTile`.
  - Level colours: Waddle `mint`, Toboggan `accent`, Blizzard a new violet
    (`#7B61FF`), Aurora `mint` light.
- **Sizes:** small ([13](design/screens/13-effects-small.png)) keeps the same pages; the
  docked keyboard leaves about 350 pt for settings, which scroll. Wide
  ([14](design/screens/14-styling-wide.png)) puts the Appearance page as the sidebar
  with the chosen page beside it, like Settings, and the keyboard across the full
  width under both, as it is on the Duo's inner screen. Theme cards go three across.
  Folding keeps the open page.
- **Accessibility:** theme cards read "Iceberg theme, selected, Pro". Swatches read the
  colour's name ("Teal"). The "Hard to read" chip is also spoken. Effects are
  decorative and hidden from VoiceOver; the level-up is announced ("Flow: Blizzard")
  only if the person turns on a new "Announce flow levels" switch, off by default.
  Reduce Motion as under Product. At the largest text sizes chips wrap their labels and
  the theme grid goes to one column.
- **Open questions** for Gabriel
  1. On Styling and Effects the real keyboard sits docked at the bottom (so changes show
     on the thing itself). Fine, or a smaller preview at the top?

## Build

Status: Approved 2026-11-06 (Gabriel: "Go ahead and build it")

- **Approach:** Core holds the values and the flow rules, the UI draws them.
  - `AstrotypeCore/Style/`: `KeyboardTheme` (id, name, `KeyColors` for light and
    dark, one `KeyShape`), the eight built-in themes, `KeyAppearance` (system, light,
    dark; the app's theme editor previews one look, the keyboard is always system),
    `RGBColor` (hex, contrast); `EffectsSettings` (tap, flash, trail, letters,
    flow and its levels, presets); `FlowMeter` (the score, combo and level, time passed
    in). All `Codable` inside `KeyboardSettings` (`themeID`, `customThemes`,
    `effects`), so they sync like the rest; old settings read as
    Classic and Calm. `trails` stays the Effects on/off switch.
  - `ProFeature` gains `.styles` and `.effects`. `KeyboardSettings.style(allows:)` and
    `effects(allows:)` give what the keyboard draws: Classic and Calm when Pro is off,
    the person's choice kept.
  - `AstrotypeUI`: `KeySurfaceView` and `KeyView` draw from a `KeyboardTheme` (colours,
    gap, corners, border, shadow, see-through, font, letters); the keys follow the
    phone's mode (or the field's asked keyboard appearance); the backdrop stays the system's.
    `KeyEffectsLayer` draws taps, trails, falling things, and the combo count on the space bar with Core Animation. `MetalKeyboard` (one device and queue, the
    shaders in `Shaders/KeyboardShaders.metal`, compiled by Xcode and loaded at first use) backs `SkyLayer` (behind the keys) and
    `LetterLayer` (the Metal letters).
  - The app: Appearance becomes a page with a live `StylePreview` (a real
    `KeySurfaceView` that types into nothing and feeds its own flow) and links to
    General, Styling, Your theme and Effects in `SettingsPages.swift`.
  - The keyboard panel: the Trails tile is Effects, plus a Theme row.
- **Core pieces:**

  ```swift
  let theme = settings.style(allows: entitlement.allows(.styles))   // KeyboardTheme
  let colors = theme.colors(dark: true)                             // KeyColors
  var flow = FlowMeter()
  flow.word(at: now); flow.delete(at: now); flow.tick(now: now)
  flow.level(scale: settings.effects.levelScale, cap: 4)            // 0...4
  ```

- **Phases:** one PR, so Gabriel can try it all in one TestFlight build. Done when: the
  Appearance section and its pages work; picking a theme changes the keyboard in the
  app and (with Full Access) in other apps; your own theme edits live; every tap,
  trail and letter effect draws; "Play a burst" in the app and fast typing in other
  apps climb to Aurora; the Debug page shows the keyboard under 40 MB at Aurora;
  checked at the small size, the largest text size and wide.
- **Risks:** Metal and memory in the extension (the sky and letters are made only when
  needed and freed when flow drops); no Xcode in the container, so builds are checked
  on CI.
- **Metrics:** `appearance.theme_chosen` and `appearance.effects_chosen` from the app.
  `keyboard.flow_peak` waits for a later PR (it needs the health file).
- **Last step:** fold into `PRODUCT.md` and `DESIGN.md`.
