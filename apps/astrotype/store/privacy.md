# App Privacy answers

What to answer in App Store Connect → App Privacy, matching
`ios/Astrotype/PrivacyInfo.xcprivacy` (the rule in `docs/telemetry.md`: the manifest and
the label say the same thing, and a change to one changes the other in the same PR).

**Data used to track you:** none. The app has no tracking domains.

**Data linked to you:** none. Nothing is tied to a name, an email or an Apple Account.

**Data not linked to you:**

| App Store category | What it is | Purpose |
| --- | --- | --- |
| Diagnostics → Crash Data | Sentry crash reports from the app, and from the keyboard with Full Access on (stack traces, device, OS and memory; never any text) | App Functionality |
| Diagnostics → Performance Data | Sentry performance traces from the app, and the keyboard's memory use per time it is shown, sent by the app | App Functionality |
| Diagnostics → Other Diagnostic Data | Sentry's other diagnostics | App Functionality |
| Usage Data → Product Interaction | the counts in `BUILD.md` "Metrics" (keyboard turned on, speed test finished, and so on), and how many words typed with the keyboard went in as its first guess (numbers only, never the words), with "Share anonymous usage data" on | Analytics |
| User Content → Other User Content | practice words: one word at a time from a speed test or drill in the app, with its touches, the day and a random writer ID, only with "Send practice sessions" on (off by default); and, only with "Include corrections from other apps" on too, a fix made from the bar in another app (the word chosen and the guess it replaced, with its touches, nothing around it) | App Functionality |

For each, answer "No" to linked to identity and "No" to used for tracking. Both switches
are in the app's Settings → Privacy.

**Not collected, and why it is not on the label:**

- Anything typed with the keyboard, in any app. The extension works without Full Access
  (PRODUCT.md). With Full Access and "Share anonymous usage data" on, it sends only crash
  reports, set up so they cannot carry text: no breadcrumbs, logs, screenshots, session
  replay, traces, messages or user ID, and crash reasons stripped
  (`ios/AstrotypeKeyboard/KeyboardTelemetry.swift`, its own `PrivacyInfo.xcprivacy`).
- Learned words, keyboard settings and what the keyboard learns from typing (the
  person's word counts, word pairs and where their thumbs land, `personal.json`). They
  stay on the device and sync through the person's own iCloud (CloudKit private
  database) when Full Access is on; Tiny Penguin never sees them.
- Purchases. Apple handles Astrotype Pro through StoreKit; the app sees only the
  entitlement.

**Full Access text** (shown by iOS, written in the extension's `Info.plist`): the keyboard
asks for it only to sync words and settings over iCloud and for haptics; crash reports
use it too, with sharing on.
