# CloudKit setup

The app uploads training samples to the **public database** of the iCloud container
`iCloud.com.tinypenguin.stackwrite`, one `Sample` record per word (`schema.ckdb`).
Anyone signed into iCloud can create records and only edit their own. Reading needs a
token or key that only the team can make. `ml/download_samples.py` pulls them down.

## One-time setup

1. **Container.** It's created by Xcode's automatic signing the first time the app is
   built with the iCloud entitlement (`Config/StackWrite.entitlements`), or by hand in
   developer.apple.com → Identifiers → iCloud Containers. The App ID
   `com.tinypenguin.stackwrite` must have iCloud (CloudKit) on, with this container.
2. **Schema.** In the CloudKit Console (icloud.developer.apple.com) → this container →
   Settings → Tokens, create a management token, then on the Mac:

       xcrun cktool save-token --type management        # paste the token
       xcrun cktool import-schema --team-id YNMFSUHQ46 \
         --container-id iCloud.com.tinypenguin.stackwrite \
         --environment development --file schema.ckdb

   Then in the console: Schema → **Deploy Schema Changes…** to production. TestFlight
   and App Store builds use production; builds run from Xcode use development.
3. **Download key.** Make a key pair for `download_samples.py`:

       mkdir -p ~/.config/stackwrite
       openssl ecparam -name prime256v1 -genkey -noout -out ~/.config/stackwrite/cloudkit-key.pem
       openssl ec -in ~/.config/stackwrite/cloudkit-key.pem -pubout

   In the console → Settings → Tokens & Keys → Server-to-Server Keys, add a key with that
   public key (production environment), and put its Key ID in
   `~/.config/stackwrite/cloudkit-key-id`.

## Changing the schema

Edit `schema.ckdb`, import it to development as above, test with a build from Xcode,
then deploy to production. Production only allows adding fields and types, never
removing them, so treat it as append-only. Keep `SampleUploader.swift` and
`ml/download_samples.py` in step.
