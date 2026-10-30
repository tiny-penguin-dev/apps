#!/usr/bin/env python3
"""Get App Store Connect ready for an app before a TestFlight upload.

Registers the bundle ID if it doesn't exist yet, then checks that an app
record uses it. Apple's API can't create app records, so a missing one
stops the run with the steps to create it by hand.

Then syncs the app's internal TestFlight group with its testers file
(the app's Config/testflight.json): creates the group if needed, gives it
every build, adds the testers it lists and removes anyone else.

Uses only the standard library plus the `openssl` command, so CI needs
nothing installed.

Usage: asc-prepare-app.py <bundle-id> <name> <testers-file>
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


class ApiError(Exception):
    def __init__(self, method, path, code, body):
        super().__init__(f"App Store Connect {method} {path} failed ({code}): {body}")
        self.code = code


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
        path if path.startswith("https:") else API + path,
        method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raise ApiError(method, path, e.code, e.read().decode()) from None


def get_all(path):
    items = []
    while path:
        page = call("GET", path)
        items += page["data"]
        path = page.get("links", {}).get("next")
    return items


def find(path, identifier, key):
    query = urllib.parse.urlencode({f"filter[{key}]": identifier, "limit": 200})
    data = call("GET", f"{path}?{query}")["data"]
    # The filter also matches longer IDs that start with this one.
    return [d for d in data if d["attributes"][key] == identifier]


def tester_group(app_id, name):
    """The app's internal group with this name, set to get every build."""
    query = urllib.parse.urlencode({"filter[app]": app_id, "filter[name]": name})
    for group in call("GET", f"/betaGroups?{query}")["data"]:
        attrs = group["attributes"]
        if attrs["name"] != name or not attrs.get("isInternalGroup"):
            continue
        if not attrs.get("hasAccessToAllBuilds"):
            call(
                "PATCH",
                f"/betaGroups/{group['id']}",
                {"data": {"type": "betaGroups", "id": group["id"],
                          "attributes": {"hasAccessToAllBuilds": True}}},
            )
            print(f"Tester group {name} now gets every build.")
        return group["id"]

    group = call(
        "POST",
        "/betaGroups",
        {
            "data": {
                "type": "betaGroups",
                "attributes": {"name": name, "isInternalGroup": True, "hasAccessToAllBuilds": True},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        },
    )["data"]
    print(f"Created internal tester group {name}.")
    return group["id"]


def add_tester(group_id, email):
    try:
        call(
            "POST",
            "/betaTesters",
            {
                "data": {
                    "type": "betaTesters",
                    "attributes": {"email": email},
                    "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group_id}]}},
                }
            },
        )
    except ApiError as e:
        if e.code != 409:
            raise
        # Already a tester elsewhere in the account: add them to this group.
        tester = find("/betaTesters", email, "email")[0]
        call(
            "POST",
            f"/betaGroups/{group_id}/relationships/betaTesters",
            {"data": [{"type": "betaTesters", "id": tester["id"]}]},
        )


def sync_testers(app_id, testers_file):
    if not os.path.exists(testers_file):
        print(f"No {testers_file}: skipping TestFlight testers.")
        return
    with open(testers_file) as f:
        config = json.load(f)
    name = config.get("group", "Team")
    wanted = {email.strip().lower() for email in config.get("testers", [])}
    group_id = tester_group(app_id, name)

    current = {t["attributes"]["email"].lower(): t["id"]
               for t in get_all(f"/betaGroups/{group_id}/betaTesters?limit=200")}
    for email in sorted(wanted - current.keys()):
        try:
            add_tester(group_id, email)
            print(f"Added {email} to {name}.")
        except ApiError as e:
            # One tester shouldn't stop the upload. Internal testers must be
            # App Store Connect users who can see this app.
            print(f"::warning::Couldn't add {email} to TestFlight group {name}: {e}")
    removed = sorted(current.keys() - wanted)
    if removed:
        call(
            "DELETE",
            f"/betaGroups/{group_id}/relationships/betaTesters",
            {"data": [{"type": "betaTesters", "id": current[email]} for email in removed]},
        )
        print(f"Removed {', '.join(removed)} from {name}.")
    print(f"Tester group {name} is in sync: {len(wanted)} tester(s).")


def main():
    try:
        prepare(sys.argv[1], sys.argv[2], sys.argv[3])
    except ApiError as e:
        print(f"::error::{e}")
        sys.exit(1)


def prepare(bundle_id, name, testers_file):

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

    apps = find("/apps", bundle_id, "bundleId")
    if apps:
        print(f"App record for {bundle_id} exists.")
        sync_testers(apps[0]["id"], testers_file)
    else:
        print(
            f"::error::No App Store Connect app uses {bundle_id} yet. Apple's API can't "
            "create one: in App Store Connect go to Apps, +, New App, and pick that "
            "bundle ID. Then re-run this workflow."
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
