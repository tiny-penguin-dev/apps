# Astrotype: a small language model for the next word

Replace the word pairs behind next-word guesses with a small model that runs on
the phone and reads the last 10 to 20 words, so its guesses fit the sentence instead
of only the word before.

## Product

Status: Draft

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
  model on 6 Nov 2026.
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
    word with context; learning from you inside the model itself.
  - Never: sending anything typed off the phone to make guesses.
- **What we measure:** `nextword.picked` already counts taps on guesses; its share of
  words written should go up. No new metric. Offline, the test set above.
- **Open questions** for Gabriel:
  1. **What text should it learn from?** This matters more than the model. It needs
     a lot of casual English and Spanish we're allowed to use.
     - **A. Web text plus written chat messages** (recommended): a large public web
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
     through a session there, or slower in the cloud.

## Design

Status: Not needed (no screen changes: the bar, the setting and the copy stay as in
features/next-word)

## Build

Status: Not started (a sketch, to be filled in once Product is approved)

- **Approach:** a word-level LSTM per language, the same kind Gboard shipped (theirs
  is 1.4 MB, 10,000 words, and beat their word pairs in live tests). About 20,000
  words per language, words and outputs sharing one table, stored in 8 bits.
  Trained in `ml/nextword/` with PyTorch; exported to our own small binary file.
- **Running it:** plain Swift with Accelerate instead of Core ML, so we control the
  memory exactly (weights memory-mapped, one small state per language) and the tests
  run on Linux too. One step per word typed, kept in step with the text before the
  cursor and re-read from it when the cursor jumps.
- **Core pieces:** `WordModel` in `AstrotypeCore` (load, `step(word)`,
  `topNext(limit:)`, reset from text); `NextWords.guesses` takes it in place of the
  pairs and keeps the same mixing with your habits.
- **Phases:**
  1. *Test set and measuring:* build the test set; `astrotype-tools` reports top-three
     and keystrokes saved for today's pairs. Done when: a baseline number is written
     here for both languages.
  2. *Train and pick:* train English and Spanish models, measure on the test set.
     Done when: the model beats the pairs by 5+ points within size and speed limits,
     or we stop and say why.
  3. *In the keyboard:* `WordModel`, guesses from it, memory and speed checked on
     Gabriel's phone. Done when: "I left my phone at the" offers "office" or "house"
     style words, not "same"; memory overlay shows under 10 MB more.
  4. *Swipe readings (if it helps):* use the model to rank swipe readings; ship only if
     the replay accuracy goes up.
- **Risks:** training text is the main risk (questions above). Memory while the leak
  is still open. A model trained on web text may suggest odd or rude words; we keep
  the lexicon filter and add a blocklist.
- **Last step:** fold into `PRODUCT.md` and `features/next-word/FEATURE.md`.
