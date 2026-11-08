# Astrotype: a small language model for the next word

Replace the word pairs behind next-word guesses with a small model that runs on
the phone and reads the last 10 to 20 words, so its guesses fit the sentence instead
of only the word before.

## Product

Status: Approved 2026-11-06 (Gabriel: "build our own", in the project thread)

- **The problem:** the next-word guesses (features/next-word) feel bad. They look at
  one word only: after "the" they offer the same three words whether you wrote "I
  left my phone at the" or "what's the". They also learned from Tatoeba, which is
  short textbook sentences ("Tom is a teacher"), not how people text. On those
  sentences the next word is in the top three about 34% of the time; on real typing
  it is lower. Gabriel, 6 Nov 2026: "We would probably need some sort of ML model… to
  take into account a longer stretch of words."
- **Who wants it:** everyone. The guesses are basics, on by default and free.
- **Basics or powerful:** basics. Nothing new to learn or turn on. The "Guess the
  next word" switch keeps working.
- **How it works:** the same as now for the person. After each word the bar offers
  the likely next words, but a small model picks them using the last 10 to 20 words.
  - It runs on the phone. Nothing typed leaves the device.
  - One model per language (English and Spanish), shipped in the app like the
    dictionaries. With both languages on, the one that fits the sentence decides, as
    today.
  - Your own habits still mix in on top ("Learns from you"), the same way they do
    now, so a phrase you write a lot climbs over the model's guess.
  - The word pairs stay for words the model doesn't know, and as a fallback if the
    model can't load.
- **Why not Apple's model:** Apple doesn't give other keyboards its next-word
  guesses. Its on-phone AI (Foundation Models) is fast for writing a reply, and it
  wouldn't count against our memory, but a keyboard would call it after every word,
  extensions get rate-limited (one developer hit the limit after 4 calls from a
  Safari extension), it returns text without scores so it can't be mixed with your
  own words, and it only works with Apple Intelligence on. Gabriel chose our own
  model on 6 Nov 2026 ("don't test the Apple one, build our own").
- **What it changes:** where next-word guesses come from. Later (phase 4, if it
  measures better), the same model also helps choose between swipe readings, which
  today uses the word pairs too ("I'll be *there*" vs "*three*").
- **Limits we hold it to:**
  - Size: at most 5 MB per language in the app.
  - Memory: at most 10 MB more with both languages on. The weights are read straight
    from the app file (memory-mapped), so iOS can drop and reload them instead of
    counting them against the ~177 MB keyboard limit. Ships after the memory leak fix
    (PRs #137, #139) is confirmed.
  - Speed: under 5 ms per word on an iPhone XS (the oldest phone on iOS 18), so it
    never lags behind fast swiping.
- **How we know it's better:** a test set of casual sentences the model never saw
  in training, in both languages, plus Gabriel's own typing recordings if he shares
  them. We measure today's word pairs and the model on the same test: how often the
  next word is one of the three guesses, and how many keystrokes taps on guesses
  save. It ships only if it clearly beats the pairs (at least 5 points more in the
  top three) within the limits above.
- **Scope:**
  - In this version: next-word guesses from the model, English and Spanish, your
    habits mixed in, the test set.
  - Later: helping choose between swipe readings (phase 4); finishing a half-typed
    word with context; tuning the model to how you write, on your phone (below).
  - Never: sending anything typed off the phone to make guesses.
- **Tuned to you, later (Gabriel, 6 Nov 2026):** once the general model ships and
  measures well, the app tunes a small part of it (the last layer, or a small add-on)
  to how the person writes, on the phone, overnight while it charges. The keyboard
  keeps recent sentences on the phone (never in fields that don't learn), the app
  learns from them and then deletes them. It needs Full Access (the keyboard can only
  hand text to the app through the App Group) and its own clearly worded switch.
  Without it, the person's word habits keep mixing in on top as today. Apple's model
  can't be tuned on the phone, another reason for our own.
- **What we measure:** `nextword.picked` already counts taps on guesses; its share of
  words written should go up. No new metric. Offline, the test set above.
- **Decided** (Gabriel said build it with these open; the recommended answers are
  what we build, and he can change them):
  1. **What text should it learn from?** This matters more than the model. It needs
     a lot of casual English and Spanish we're allowed to use.
     - **A. Web text plus written chat messages** (recommended, going with this): a large public web
       collection that allows this use (FineWeb, ODC-BY, English and Spanish), filtered
       toward casual writing (forums, comments, reviews), plus a few hundred thousand
       short text-message style lines written by an AI model to cover how people
       actually text, plus Tatoeba.
     - **B. Web text only:** simpler and fully real text, but it reads more like
       articles than messages.
     - **C. Movie subtitles:** the most chat-like, but the rights are unclear, so I'd
       avoid it.
  2. **Train where?** A model this size trains in a few hours on a Mac with an M chip
     (the handwriting model in `ml/` was trained that way). I can run it on your Mac
     through a session there, or slower in the cloud. Going with: his Mac (the cloud
     machine has 4 CPU cores and no GPU); the data and test set are made in the cloud.

## Design

Status: Not needed (no screen changes: the bar, the setting and the copy stay as in
features/next-word)

## Build

Status: Approved 2026-11-06 (Gabriel: "build our own… very efficient, low memory, uses
the most native Apple stuff… okay if it only runs on newest OSs and newest phones")

- **Approach:** a tiny word-level transformer per language, run by Core ML on the
  Neural Engine, Apple's fastest and most battery-friendly way to run a model.
  - *Why a transformer, not an LSTM:* the Neural Engine runs transformer layers well
    and LSTMs poorly (they fall back to the CPU). Apple's own keyboard model is a
    small transformer too.
  - *Size:* about 16,000 words per language (the commonest in the lexicon; rarer
    words fall back to the pairs), 4 layers, 256 wide, words in and out sharing one
    table: about 7 million weights. Stored at 4 bits per weight (Core ML
    palettization), about 3.5 MB per language. Trained in `ml/nextword/` with
    PyTorch, exported with coremltools.
  - *One step per word:* a stateful Core ML model (`MLState`, iOS 18) keeps what it
    read so far on the Neural Engine, so each new word costs one small step instead of
    rereading the sentence. It reads up to the last 64 words; a cursor jump or a new
    field resets it from the text before the cursor.
  - *Loading:* the model loads in the background when the keyboard opens; the pairs
    answer until it's ready, and whenever it isn't available (load failed, memory
    warning). Only the active languages load.
  - *iOS:* stays iOS 18 (the app's minimum), since everything above is there in 18.
    Phones without a Neural Engine fast enough fall back to the GPU or CPU; we measure
    on Gabriel's phone and the oldest one we can.
- **Core pieces:**
  - `WordVocabulary` (`AstrotypeCore`, pure, tested on Linux): word ↔ id per
    language, and turning the text before the cursor into ids (`WordContext` already
    splits it into words).
  - `NextWordModel` (protocol in `AstrotypeCore`): `reset(to ids:)`, `append(id)`,
    `topNext(limit:) -> [(word, probability)]`. The live one, `CoreMLNextWordModel`
    (`AstrotypeUI`, Core ML), and a fake for tests.
  - `NextWords.guesses` takes the model's top words in place of the pairs' when one is
    loaded, with the same mixing with your habits; the pairs stay for unknown words.
  - `astrotype-tools nexteval` scores any model on the test set (top-1, top-3,
    keystrokes saved) so the pairs and each trained model are compared the same way.
- **Phases:**
  1. *Text, test set and baseline:* gather and clean the training text (option A) and
     hold back a test set for both languages; `nexteval` reports today's pairs on it.
     Done when: the baseline numbers are written here.
  2. *Train and pick:* train on Gabriel's Mac, export 4-bit Core ML, measure. Done
     when: the model beats the pairs by 5+ points in the top three within 5 MB per
     language, or we stop and say why.
  3. *In the keyboard:* `CoreMLNextWordModel`, guesses from it, memory and speed
     shown on the stats overlay. Done when: "I left my phone at the" offers words
     like "house" or "office", not "same"; under 10 MB more memory with both
     languages; under 5 ms per word on Gabriel's phone.
  4. *Swipe readings (if it helps):* use the model to rank swipe readings; ship only if
     the replay accuracy goes up.
     Done 7 Nov 2026: a word the model knows gets `Matcher.modelWeight` (0.12) times
     the log ratio of the model's probability (mixed 0.9 with its plain frequency) to
     its plain frequency, in place of the pairs' bonus. On 600 held-out sentences typed
     by `SyntheticTyping`, wrong first guesses went from 3.3% to 2.5% (noise 0.2) and
     17.6% to 16.3% (noise 0.35). Weight 0.09-0.15 all scored about the same; above
     that it starts overriding clear swipes. Keeping the pairs as well didn't help.
  5. *Tuned to you (later, its own plan):* sentences kept on the phone, tuning in the
     app in a background task while charging, the switch. Done when: the test on the
     person's own held-back sentences beats the general model.
- **Risks:** training text is the main risk. Memory while the leak is still open.
  Core ML's first load on a phone compiles the model for the Neural Engine and can
  take a second or two (cached after); the pairs cover it. A model trained on web
  text may suggest odd or rude words; we keep the lexicon filter and add a blocklist.
- **Metrics:** none new; `nextword.picked` share of words written.
- **Last step:** fold into `PRODUCT.md` and `features/next-word/FEATURE.md`.
