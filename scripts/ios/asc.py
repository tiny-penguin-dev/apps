"""Minimal App Store Connect API client shared by the scripts in this folder.

Uses only the standard library plus the `openssl` command, so CI needs
nothing installed.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (path to the .p8 file)
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


def run(main, *args):
    """Run a script's main, turning API errors into a GitHub Actions error."""
    try:
        main(*args)
    except ApiError as e:
        print(f"::error::{e}")
        sys.exit(1)
