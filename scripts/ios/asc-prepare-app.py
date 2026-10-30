#!/usr/bin/env python3
"""Get App Store Connect ready for an app before a TestFlight upload.

Registers the bundle ID if it doesn't exist yet, then checks that an app
record uses it. Apple's API can't create app records, so a missing one
stops the run with the steps to create it by hand.

Uses only the standard library plus the `openssl` command, so CI needs
nothing installed.

Usage: asc-prepare-app.py <bundle-id> <name>
Env:   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (path to the .p8 file)
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(sig):
    # openssl gives an ES256 signature as DER (SEQUENCE of two INTEGERs);
    # a JWT needs the two 32-byte numbers back to back.
    def read_int(buf, i):
        assert buf[i] == 0x02
        n = buf[i + 1]
        value = buf[i + 2 : i + 2 + n].lstrip(b"\x00")
        return value.rjust(32, b"\x00"), i + 2 + n

    assert sig[0] == 0x30
    i = 2 if sig[1] < 0x80 else 2 + (sig[1] & 0x7F)
    r, i = read_int(sig, i)
    s, _ = read_int(sig, i)
    return r + s


def token():
    now = int(time.time())
    header = {"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}
    claims = {
        "iss": os.environ["ASC_ISSUER_ID"],
        "iat": now,
        "exp": now + 600,
        "aud": "appstoreconnect-v1",
    }
    signing_input = (
        b64url(json.dumps(header).encode()) + "." + b64url(json.dumps(claims).encode())
    )
    sig = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", os.environ["ASC_KEY_PATH"]],
        input=signing_input.encode(),
        capture_output=True,
        check=True,
    ).stdout
    return signing_input + "." + b64url(der_to_raw(sig))


def call(method, path, body=None):
    req = urllib.request.Request(
        API + path,
        method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        print(f"::error::App Store Connect {method} {path} failed ({e.code}): {e.read().decode()}")
        sys.exit(1)


def find(path, identifier, key):
    query = urllib.parse.urlencode({f"filter[{key}]": identifier, "limit": 200})
    data = call("GET", f"{path}?{query}")["data"]
    # The filter also matches longer IDs that start with this one.
    return [d for d in data if d["attributes"][key] == identifier]


def main():
    bundle_id, name = sys.argv[1], sys.argv[2]

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
    main()
