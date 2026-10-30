#!/usr/bin/env python3
"""Get App Store Connect ready for an app before a TestFlight upload.

Registers the bundle ID if it doesn't exist yet, then checks that an app
record uses it. Apple's API can't create app records, so a missing one
stops the run with the steps to create it by hand.

Usage: asc-prepare-app.py <bundle-id> <name>
Env:   see asc.py
"""

import sys

from asc import call, find, run


def main(bundle_id, name):
    if find("/bundleIds", bundle_id, "identifier"):
        print(f"Bundle ID {bundle_id} is registered.")
    else:
        call(
            "POST",
            "/bundleIds",
            {
                "data": {
                    "type": "bundleIds",
                    "attributes": {"identifier": bundle_id, "name": name, "platform": "IOS"},
                }
            },
        )
        print(f"Registered bundle ID {bundle_id}.")

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
    run(main, sys.argv[1], sys.argv[2])
