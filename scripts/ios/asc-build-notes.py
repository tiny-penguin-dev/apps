#!/usr/bin/env python3
"""Set a TestFlight build's "What to Test" to what changed since the last build.

Finds the app's previous build in App Store Connect, turns its build number
(the commit time in Pacific time, YYYYMMDDHHMM; UTC before 8 Nov 2026) back into
the commit it was built from, and
lists the commit titles that touched the app's folder since then. Then waits
for the new build to show up in App Store Connect and sets its notes.

Needs the full git history (checkout with fetch-depth: 0).

Usage: asc-build-notes.py <bundle-id> <build-number> <app-folder> [--dry-run]
Env:   see asc.py
"""

import datetime
import os
import re
import subprocess
import sys
import time
import urllib.parse
from zoneinfo import ZoneInfo

from asc import call, find, run

LOCALE = "en-US"
MAX_LINES = 25
MAX_CHARS = 4000  # Apple's limit for What to Test
WAIT_SECONDS = 20 * 60
# Build numbers are commit times in this zone (scripts/ios/build-number.sh).
# Builds before 8 Nov 2026 were numbered in UTC.
ZONES = ("America/Los_Angeles", "UTC")


def previous_build_number(app_id, build_number):
    """The newest earlier build's number, or None for an app's first build."""
    query = urllib.parse.urlencode(
        {"filter[app]": app_id, "sort": "-uploadedDate", "limit": 20, "fields[builds]": "version"}
    )
    numbers = [b["attributes"]["version"] for b in call("GET", f"/builds?{query}")["data"]]
    earlier = [n for n in numbers if re.fullmatch(r"\d{12}", n) and n < build_number]
    return max(earlier) if earlier else None


def build_commit(build_number):
    """The commit on main a build number came from, or None if none matches."""
    for zone in ZONES:
        out = subprocess.run(
            ["git", "log", "--first-parent", "--format=%H %cd",
             "--date=format-local:%Y%m%d%H%M", "HEAD"],
            capture_output=True, text=True, check=True, env={**os.environ, "TZ": zone},
        ).stdout
        # Newest first, so this is the last commit in that minute: the one built.
        for line in out.splitlines():
            sha, minute = line.split()
            if minute == build_number:
                return sha
    return None


def change_titles(since_build, app_folder):
    """Titles of commits that touched the app after the given build's commit."""
    args = ["git", "log", "--first-parent", "--no-merges", "--format=%s"]
    since = build_commit(since_build) if since_build else None
    if since:
        args.append(f"{since}..HEAD")
    elif since_build:
        # Built from a commit that isn't on this branch: fall back to its time.
        # Everything in that minute was already in that build.
        built = datetime.datetime.strptime(since_build, "%Y%m%d%H%M")
        after = built.replace(tzinfo=ZoneInfo(ZONES[0])) + datetime.timedelta(seconds=59)
        args += [f"--after={after.isoformat()}", "HEAD"]
    else:
        args += ["-10", "HEAD"]
    args += ["--", f":(top){app_folder}"]
    titles = subprocess.run(args, capture_output=True, text=True, check=True).stdout.splitlines()
    return [tidy(t) for t in titles if t.strip()]


def tidy(title):
    # "Astrotype: fix extra spaces (#58)" -> "Fix extra spaces"
    title = re.sub(r"\s*\(#\d+\)$", "", title.strip())
    title = re.sub(r"^[\w .-]{1,30}:\s+", "", title)
    return title[:1].upper() + title[1:]


def notes_text(titles, since_build):
    if not titles:
        return "No app changes since the last build (build setup only)."
    heading = "What's new since the last build:" if since_build else "Latest changes:"
    lines = [f"• {t}" for t in titles[:MAX_LINES]]
    if len(titles) > MAX_LINES:
        lines.append(f"• …and {len(titles) - MAX_LINES} more")
    return (heading + "\n" + "\n".join(lines))[:MAX_CHARS]


def wait_for_build(app_id, build_number):
    query = urllib.parse.urlencode({"filter[app]": app_id, "filter[version]": build_number})
    deadline = time.time() + WAIT_SECONDS
    while True:
        builds = call("GET", f"/builds?{query}")["data"]
        if builds:
            return builds[0]["id"]
        if time.time() > deadline:
            return None
        time.sleep(20)


def set_notes(build_id, text):
    existing = call("GET", f"/builds/{build_id}/betaBuildLocalizations")["data"]
    match = next((l for l in existing if l["attributes"]["locale"] == LOCALE), None)
    if match:
        call(
            "PATCH",
            f"/betaBuildLocalizations/{match['id']}",
            {"data": {"type": "betaBuildLocalizations", "id": match["id"],
                      "attributes": {"whatsNew": text}}},
        )
    else:
        call(
            "POST",
            "/betaBuildLocalizations",
            {
                "data": {
                    "type": "betaBuildLocalizations",
                    "attributes": {"locale": LOCALE, "whatsNew": text},
                    "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
                }
            },
        )


def main(bundle_id, build_number, app_folder, *flags):
    app_id = find("/apps", bundle_id, "bundleId")[0]["id"]
    since = previous_build_number(app_id, build_number)
    text = notes_text(change_titles(since, app_folder), since)
    print(f"Previous build: {since or 'none'}\n\n{text}\n")
    if "--dry-run" in flags:
        return

    build_id = wait_for_build(app_id, build_number)
    if not build_id:
        print(f"::warning::Build {build_number} didn't show up in App Store Connect in time, so it has no What to Test notes.")
        return
    set_notes(build_id, text)
    print(f"Set What to Test for build {build_number}.")


if __name__ == "__main__":
    run(main, *sys.argv[1:])
