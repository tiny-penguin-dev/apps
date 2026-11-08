#!/usr/bin/env python3
"""Check a build number is higher than every build the app already has.

App Store Connect rejects an upload whose build number isn't higher than the
last one. Build numbers are the commit time in Pacific time, so this only
happens for the hour clocks go back each November, or for builds made right
after the switch from UTC numbers (8 Nov 2026). Prints "ok" or "behind <newest>".

Usage: asc-check-build-number.py <bundle-id> <build-number>
Env:   see asc.py
"""

import re
import sys
import urllib.parse

from asc import call, find, run


def main(bundle_id, build_number):
    app_id = find("/apps", bundle_id, "bundleId")[0]["id"]
    query = urllib.parse.urlencode(
        {"filter[app]": app_id, "sort": "-uploadedDate", "limit": 50, "fields[builds]": "version"}
    )
    numbers = [b["attributes"]["version"] for b in call("GET", f"/builds?{query}")["data"]]
    newest = max((n for n in numbers if re.fullmatch(r"\d{12}", n)), default=None)
    print("ok" if newest is None or build_number > newest else f"behind {newest}")


if __name__ == "__main__":
    run(main, *sys.argv[1:])
