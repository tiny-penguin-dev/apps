#!/usr/bin/env python3
"""Keep an app's App Store subscriptions in sync with its store/subscriptions.json.

The file lists subscription groups and their plans: product ID, length, US
price, launch (introductory) offer, the name and description people see, and
the screenshot for App Review. Prices and offers are set in the US and Apple's
matching price is used in every other country.

    {
      "groups": [{
        "name": "Squawk Pro",
        "localizations": {"en-US": {"name": "Squawk Pro"}},
        "subscriptions": [{
          "productId": "com.tinypenguin.squawk.pro.yearly",
          "name": "Pro Yearly",
          "period": "ONE_YEAR",
          "level": 1,
          "familySharable": false,
          "price": "49.99",
          "introOffer": {"mode": "PAY_UP_FRONT", "duration": "ONE_YEAR", "periods": 1, "price": "29.99"},
          "localizations": {"en-US": {"name": "Squawk Pro", "description": "..."}},
          "reviewNote": "...",
          "reviewScreenshot": "pro-review.png"
        }]
      }]
    }

Nothing is ever deleted: a plan or language missing from the file is left as
it is in App Store Connect. A price change keeps the old price for people who
already subscribe.

Usage: asc-subscriptions.py <bundle-id> <subscriptions.json> [--apply]
       Without --apply it only prints what it would change.
       With a file that doesn't exist yet, it prints what App Store Connect has,
       in the file's format, to start from.
Env:   see asc.py. The API key needs the App Manager or Admin role.
"""

import hashlib
import json
import os
import sys
import urllib.request

from asc import call, find, get_all, run

BASE_TERRITORY = "USA"


# ---------------------------------------------------------------------------
# Reading what App Store Connect has


def us_price(sub_id):
    """The subscription's current US price, as a string like "49.99", or None."""
    prices = call(
        "GET",
        f"/subscriptions/{sub_id}/prices?filter[territory]={BASE_TERRITORY}"
        "&include=subscriptionPricePoint&limit=50",
    )
    points = {i["id"]: i for i in prices.get("included", []) if i["type"] == "subscriptionPricePoints"}
    # The current price is the one with the latest start date that has started.
    current = None
    for price in prices["data"]:
        start = price["attributes"].get("startDate") or ""
        if current is None or start > (current["attributes"].get("startDate") or ""):
            current = price
    if not current:
        return None
    point = points.get(current["relationships"]["subscriptionPricePoint"]["data"]["id"])
    return point["attributes"]["customerPrice"] if point else None


def us_intro_offer(sub_id):
    offers = call(
        "GET",
        f"/subscriptions/{sub_id}/introductoryOffers?filter[territory]={BASE_TERRITORY}"
        "&include=subscriptionPricePoint&limit=50",
    )
    if not offers["data"]:
        return None
    points = {i["id"]: i for i in offers.get("included", []) if i["type"] == "subscriptionPricePoints"}
    attrs = offers["data"][0]["attributes"]
    offer = {"mode": attrs["offerMode"], "duration": attrs["duration"], "periods": attrs["numberOfPeriods"]}
    point_ref = (offers["data"][0]["relationships"].get("subscriptionPricePoint") or {}).get("data")
    if point_ref and point_ref["id"] in points:
        offer["price"] = points[point_ref["id"]]["attributes"]["customerPrice"]
    return offer


def review_screenshot(sub_id):
    """The App Review screenshot's file name and checksum, or None."""
    try:
        shot = call("GET", f"/subscriptions/{sub_id}/appStoreReviewScreenshot")["data"]
    except Exception:  # 404 when there isn't one
        return None
    if not shot:
        return None
    a = shot["attributes"]
    return {"fileName": a.get("fileName"), "checksum": a.get("sourceFileChecksum"),
            "state": (a.get("assetDeliveryState") or {}).get("state")}


def localizations(path):
    return {
        loc["attributes"]["locale"]: loc
        for loc in get_all(path)
    }


def export(app_id):
    groups = []
    for group in get_all(f"/apps/{app_id}/subscriptionGroups?limit=50"):
        g = {
            "name": group["attributes"]["referenceName"],
            "localizations": {
                locale: {k: v for k, v in {"name": loc["attributes"]["name"],
                                            "appName": loc["attributes"].get("customAppName")}.items() if v}
                for locale, loc in localizations(
                    f"/subscriptionGroups/{group['id']}/subscriptionGroupLocalizations?limit=50").items()
            },
            "subscriptions": [],
        }
        for sub in get_all(f"/subscriptionGroups/{group['id']}/subscriptions?limit=50"):
            a = sub["attributes"]
            s = {
                "productId": a["productId"],
                "name": a["name"],
                "period": a.get("subscriptionPeriod"),
                "level": a.get("groupLevel"),
                "familySharable": a.get("familySharable", False),
                "price": us_price(sub["id"]),
                "introOffer": us_intro_offer(sub["id"]),
                "localizations": {
                    locale: {"name": loc["attributes"]["name"], "description": loc["attributes"].get("description")}
                    for locale, loc in localizations(
                        f"/subscriptions/{sub['id']}/subscriptionLocalizations?limit=50").items()
                },
                "reviewNote": a.get("reviewNote"),
                "reviewScreenshot": review_screenshot(sub["id"]),
                "state": a.get("state"),
            }
            g["subscriptions"].append(s)
        groups.append(g)
    return {"groups": groups}


def main(bundle_id, config_path, *flags):
    apps = find("/apps", bundle_id, "bundleId")
    if not apps:
        sys.exit(f"::error::No App Store Connect app uses {bundle_id} yet.")
    app_id = apps[0]["id"]
    if not os.path.exists(config_path):
        print(f"{config_path} doesn't exist yet. App Store Connect has:")
        print(json.dumps(export(app_id), indent=2))
        return
    sys.exit("::error::Syncing isn't written yet.")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    run(main, *sys.argv[1:])
