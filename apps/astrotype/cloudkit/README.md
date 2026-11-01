# CloudKit setup

The app uploads training samples to the **public database** of the iCloud container
`iCloud.com.tinypenguin.astrotype`, one `Sample` record per word (`schema.ckdb`).
Anyone signed into iCloud can create records and only edit their own. Reading needs a
token or key that only the team can make. `ml/download_samples.py` pulls them down.

With "Send practice sessions" on (Settings → Privacy, off by default), the app also
sends the touches of its own speed tests and drills as `PracticeSession` records to the
public database (`AstrotypeCore/App/PracticeRecording.swift` describes the JSON).

The keyboard's learned words and settings sync through the **private database** of the
same container: one `KeyboardData` record per account, which every device of that
account reads, merges with its own copy and writes back (`AstrotypeCore/Sync`). Both
the app and the keyboard extension (with Full Access) use it, so the extension's App ID
needs iCloud with this container too (see `docs/ios-release.md`, "Entitlements").

## One-time setup

The container `iCloud.com.tinypenguin.astrotype` is new with the rename (1 Nov 2026); the
old `iCloud.com.tinypenguin.stackwrite` container and its key are not used any more, so
all three steps are done again for it, and `schema.ckdb` carries all three record types.

1. **Container.** The TestFlight workflow turns iCloud on for the App ID and lets
   automatic signing register the container (see `docs/ios-release.md`). If that fails,
   create it by hand in developer.apple.com → Identifiers → iCloud Containers, then turn
   on iCloud (CloudKit) for `com.tinypenguin.astrotype` with this container.
2. **Schema.** The "Astrotype CloudKit schema" workflow
   (`.github/workflows/astrotype-cloudkit.yml`) imports `schema.ckdb` into the
   development environment whenever the file changes on `main`, or when run by hand.
   It needs the repo secret `CLOUDKIT_MANAGEMENT_TOKEN`: in the CloudKit Console
   (icloud.developer.apple.com) open your account's Settings → Tokens, create a
   management token and paste it into Settings → Secrets and variables → Actions
   (`cktool` reads it from that variable; nothing goes in a Keychain).
   Apple's `cktool` cannot deploy to production, so after a green run open the console
   → this container → Schema → **Deploy Schema Changes…** and confirm. TestFlight and
   App Store builds use production; builds run from Xcode use development.

   The same thing by hand on the Mac:

       xcrun cktool save-token --type management        # paste the token
       xcrun cktool import-schema --team-id YNMFSUHQ46 \
         --container-id iCloud.com.tinypenguin.astrotype \
         --environment development --file schema.ckdb

3. **Download key.** Make a key pair for `download_samples.py`:

       mkdir -p ~/.config/astrotype
       openssl ecparam -name prime256v1 -genkey -noout -out ~/.config/astrotype/cloudkit-key.pem
       openssl ec -in ~/.config/astrotype/cloudkit-key.pem -pubout

   In the console → Settings → Tokens & Keys → Server-to-Server Keys, add a key with that
   public key (production environment), and put its Key ID in
   `~/.config/astrotype/cloudkit-key-id`.

## Adding a record type

TestFlight builds use the production environment, which never creates record types on
its own: a new type (like `KeyboardData` in Phase 5) reaches development through the
workflow when `schema.ckdb` lands on `main`, and is then deployed in the console, before
the build that uses it goes out. Until then the sync fails with "unknown record type"
and the keyboard keeps working from its local copy.

## Changing the schema

Edit `schema.ckdb`; merging it imports it to development. Test with a build from Xcode,
then deploy to production in the console. Production only allows adding fields and
types, never removing them, so treat it as append-only. Keep `SampleUploader.swift` and
`ml/download_samples.py` in step.
