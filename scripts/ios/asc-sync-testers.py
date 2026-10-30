#!/usr/bin/env python3
"""Sync an app's internal TestFlight group with its testers file.

Creates the group if needed, gives it every build, adds the testers the
file lists and removes anyone else. Run after asc-prepare-app.py, which
makes sure the app record exists.

Testers file (the app's Config/testflight.json):
    {"group": "Team", "testers": ["someone@example.com"]}

Usage: asc-sync-testers.py <bundle-id> <testers-file>
Env:   see asc.py
"""

import json
import os
import sys
import urllib.parse

from asc import ApiError, call, find, get_all, run


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


def main(bundle_id, testers_file):
    if not os.path.exists(testers_file):
        print(f"No {testers_file}: skipping TestFlight testers.")
        return
    with open(testers_file) as f:
        config = json.load(f)
    name = config.get("group", "Team")
    wanted = {email.strip().lower() for email in config.get("testers", [])}
    app_id = find("/apps", bundle_id, "bundleId")[0]["id"]
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


if __name__ == "__main__":
    run(main, sys.argv[1], sys.argv[2])
