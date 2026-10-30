#!/usr/bin/env python3
"""Get App Store Connect ready for an app before a TestFlight upload.

Registers the bundle ID if it doesn't exist yet, then checks that an app
record uses it. Apple's API can't create app records, so a missing one
stops the run with the steps to create it by hand.

With an entitlements file, also turns on the matching capabilities for the
bundle ID (iCloud with CloudKit today). Neither the API nor signing with
an API key can create iCloud containers or link them to an app, so that's
done once by hand (see docs/ios-release.md).

Usage: asc-prepare-app.py <bundle-id> <name> [entitlements-file]
Env:   see asc.py
"""

import os
import plistlib
import sys

from asc import call, find, run


# Entitlement key -> (capability type, settings) to turn on for the bundle ID.
CAPABILITIES = {
    "com.apple.developer.icloud-services": (
        "ICLOUD",
        [{"key": "ICLOUD_VERSION", "options": [{"key": "XCODE_6", "enabled": True}]}],
    ),
}


def enable_capabilities(bundle_resource_id, entitlements_file):
    with open(entitlements_file, "rb") as f:
        entitlements = plistlib.load(f)
    have = {c["attributes"]["capabilityType"]
            for c in call("GET", f"/bundleIds/{bundle_resource_id}/bundleIdCapabilities")["data"]}
    for key, (capability, settings) in CAPABILITIES.items():
        if key not in entitlements:
            continue
        if capability in have:
            print(f"Capability {capability} is on.")
            continue
        call(
            "POST",
            "/bundleIdCapabilities",
            {
                "data": {
                    "type": "bundleIdCapabilities",
                    "attributes": {"capabilityType": capability, "settings": settings},
                    "relationships": {
                        "bundleId": {"data": {"type": "bundleIds", "id": bundle_resource_id}}
                    },
                }
            },
        )
        print(f"Turned on capability {capability}.")


def main(bundle_id, name, entitlements_file=""):
    bundles = find("/bundleIds", bundle_id, "identifier")
    if bundles:
        print(f"Bundle ID {bundle_id} is registered.")
    else:
        bundle = call(
            "POST",
            "/bundleIds",
            {
                "data": {
                    "type": "bundleIds",
                    "attributes": {"identifier": bundle_id, "name": name, "platform": "IOS"},
                }
            },
        )["data"]
        bundles = [bundle]
        print(f"Registered bundle ID {bundle_id}.")

    if entitlements_file and os.path.exists(entitlements_file):
        enable_capabilities(bundles[0]["id"], entitlements_file)

    if find("/apps", bundle_id, "bundleId"):
        print(f"App record for {bundle_id} exists.")
    else:
        print(
            f"::error::No App Store Connect app uses {bundle_id} yet. Apple's API can't "
            "create one: in App Store Connect go to Apps, +, New App, and pick that "
            "bundle ID. Then re-run this workflow."
        )
        sys.exit(1)


if __name__ == "__main__":
    run(main, *sys.argv[1:4])
