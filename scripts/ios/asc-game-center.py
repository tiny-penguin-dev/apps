#!/usr/bin/env python3
"""Keep an app's Game Center leaderboards in sync with its store/game-center.json.

    {
      "leaderboards": [{
        "id": "com.tinypenguin.astrotype.board.everyday",   # what the app posts to
        "name": "Everyday speed",                           # App Store Connect only
        "sort": "DESC",                                     # DESC: higher is better
        "submission": "BEST_SCORE",                         # or MOST_RECENT_SCORE
        "range": [1, 200],                                  # scores outside are refused
        "recurrence": {"start": "2026-11-09T08:00:00.000Z", "duration": "PT168H",
                       "rule": "FREQ=DAILY;INTERVAL=7"},    # optional: a board that resets
        "localizations": {"en-US": {"name": "Everyday speed", "suffix": " wpm",
                                    "suffixSingular": " wpm"}}
      }]
    }

Turns Game Center on for the app first if needed. Nothing is ever deleted, and a
leaderboard that exists is left as it is apart from its names (Apple doesn't let most
of a live leaderboard change).

Usage: asc-game-center.py <bundle-id> <game-center.json> [--apply]
       Without --apply it only prints what it would change.
Env:   see asc.py. The API key needs the App Manager or Admin role.
"""

# Recurrence: Apple takes the duration in hours, minutes or seconds only (a week is PT168H,
# never P7D) and a rule of MINUTELY, HOURLY or DAILY (a week is FREQ=DAILY;INTERVAL=7).
import json
import os
import sys

from asc import ApiError, call, find, get_all, run

APPLY = False
FAILED = []


def change(description, action):
    print(("" if APPLY else "Would: ") + description)
    if not APPLY:
        return None
    try:
        return action()
    except ApiError as e:
        FAILED.append(description)
        print(f"::warning::Couldn't {description}: {e}")
        return None


def post(type_, attributes, relationships):
    rels = {name: {"data": {"type": t, "id": i}} for name, (t, i) in relationships.items()}
    return call("POST", f"/{type_}", {"data": {"type": type_, "attributes": attributes,
                                               "relationships": rels}})["data"]


def game_center(app_id):
    """The app's Game Center details, or None when Game Center is off."""
    try:
        return call("GET", f"/apps/{app_id}/gameCenterDetail").get("data")
    except ApiError as e:
        if e.code == 404:
            return None
        raise


def sync_localizations(board_id, wanted):
    have = {}
    if board_id:
        for loc in get_all(f"/gameCenterLeaderboards/{board_id}/localizations?limit=50"):
            have[loc["attributes"]["locale"]] = loc
    for locale, text in wanted.items():
        attributes = {"name": text["name"]}
        if "suffix" in text:
            attributes["formatterSuffix"] = text["suffix"]
        if "suffixSingular" in text:
            attributes["formatterSuffixSingular"] = text["suffixSingular"]
        current = have.get(locale)
        if current is None:
            change(f"  add {locale} name \"{text['name']}\"", lambda: post(
                "gameCenterLeaderboardLocalizations", {"locale": locale, **attributes},
                {"gameCenterLeaderboard": ("gameCenterLeaderboards", board_id)}))
            continue
        differs = {k: v for k, v in attributes.items() if current["attributes"].get(k) != v}
        if differs:
            change(f"  update {locale} {differs}", lambda: call(
                "PATCH", f"/gameCenterLeaderboardLocalizations/{current['id']}",
                {"data": {"type": "gameCenterLeaderboardLocalizations", "id": current["id"],
                          "attributes": differs}}))


def sync(app_id, config):
    detail = game_center(app_id)
    if detail is None:
        detail = change("turn on Game Center", lambda: post(
            "gameCenterDetails", {}, {"app": ("apps", app_id)}))
    detail_id = detail["id"] if detail else None
    have = {}
    if detail_id:
        for board in get_all(f"/gameCenterDetails/{detail_id}/gameCenterLeaderboards?limit=200"):
            have[board["attributes"]["vendorIdentifier"]] = board
    for wanted in config.get("leaderboards", []):
        print(f"== {wanted['id']}")
        board = have.get(wanted["id"])
        board_id = board["id"] if board else None
        if board is None:
            attributes = {
                "referenceName": wanted["name"],
                "vendorIdentifier": wanted["id"],
                "defaultFormatter": "INTEGER",
                "submissionType": wanted.get("submission", "BEST_SCORE"),
                "scoreSortType": wanted.get("sort", "DESC"),
            }
            if "range" in wanted:
                attributes["scoreRangeStart"] = str(wanted["range"][0])
                attributes["scoreRangeEnd"] = str(wanted["range"][1])
            if "recurrence" in wanted:
                attributes["recurrenceStartDate"] = wanted["recurrence"]["start"]
                attributes["recurrenceDuration"] = wanted["recurrence"]["duration"]
                attributes["recurrenceRule"] = wanted["recurrence"]["rule"]
            if not detail_id:
                print(f"Would: create leaderboard {json.dumps(attributes)}")
                continue
            created = change(f"create leaderboard {json.dumps(attributes)}", lambda: post(
                "gameCenterLeaderboards", attributes, {"gameCenterDetail": ("gameCenterDetails", detail_id)}))
            board_id = created["id"] if created else None
        else:
            print("  Exists.")
        if APPLY and not board_id:
            continue  # creating it failed; its names wait for the next run
        sync_localizations(board_id, wanted.get("localizations", {}))


def main(bundle_id, config_path, *flags):
    global APPLY
    APPLY = "--apply" in flags
    if not os.path.exists(config_path):
        print(f"No {config_path}: nothing to do.")
        return
    apps = find("/apps", bundle_id, "bundleId")
    if not apps:
        sys.exit(f"::error::No App Store Connect app uses {bundle_id} yet.")
    with open(config_path) as f:
        config = json.load(f)
    sync(apps[0]["id"], config)
    if FAILED:
        sys.exit("::error::App Store Connect refused: " + "; ".join(FAILED))
    print("Done." if APPLY else "Dry run: nothing changed. Changes apply on main.")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    run(main, *sys.argv[1:])
