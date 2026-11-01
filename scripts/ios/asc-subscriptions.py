#!/usr/bin/env python3
"""Keep an app's App Store subscriptions in sync with its store/subscriptions.json.

The file lists subscription groups and their plans: product ID, length, US
price, launch (introductory) offer, the name and description people see, and
the screenshot for App Review. Prices and offers are set in the US, and Apple's
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

- period: ONE_WEEK, ONE_MONTH, TWO_MONTHS, THREE_MONTHS, SIX_MONTHS, ONE_YEAR.
- level: order in the group, 1 is the top plan (people move up and down levels).
- introOffer mode: FREE_TRIAL (no price), PAY_AS_YOU_GO (price each period, for
  "periods" periods), PAY_UP_FRONT (one price for "duration").
- reviewScreenshot: a file next to subscriptions.json.

Nothing is ever deleted: a group, plan, language or offer missing from the file
is left as it is in App Store Connect. A price change keeps the old price for
people who already subscribe.

Usage: asc-subscriptions.py <bundle-id> <subscriptions.json> [--apply]
       Without --apply it only prints what it would change.
       With no file yet, it prints what App Store Connect has, in the file's
       format, to start from.
Env:   see asc.py. The API key needs the App Manager or Admin role.
"""

import hashlib
import json
import os
import sys

from asc import ApiError, call, find, get_all, get_all_with_included, run, upload_parts

BASE_TERRITORY = "USA"
APPLY = False


def change(description, action, check=None):
    """Print a change, and make it when running with --apply. A dry run calls `check`
    instead, which reads what the change would need, so mistakes show up before main."""
    print(("" if APPLY else "Would: ") + description)
    if APPLY:
        return action()
    if check:
        check()
    return None


def check_price(sub_id, price):
    print(f"  ${price} is a US price point; Apple has a matching price in "
          f"{len(price_points_everywhere(sub_id, price))} countries.")


def post(type_, attributes, relationships):
    rels = {name: {"data": ({"type": t, "id": i} if not isinstance(i, list)
                            else [{"type": t, "id": x} for x in i])}
            for name, (t, i) in relationships.items()}
    return call("POST", f"/{type_}", {"data": {"type": type_, "attributes": attributes,
                                               "relationships": rels}})["data"]


def patch(type_, id_, attributes):
    call("PATCH", f"/{type_}/{id_}", {"data": {"type": type_, "id": id_, "attributes": attributes}})


# ---------------------------------------------------------------------------
# Reading what App Store Connect has


def us_price(sub_id):
    """The subscription's current US price, like "49.99", or None."""
    prices, included = get_all_with_included(
        f"/subscriptions/{sub_id}/prices?filter[territory]={BASE_TERRITORY}"
        "&include=subscriptionPricePoint&limit=200")
    if not prices:
        return None
    # The latest start date wins (no start date means it started long ago).
    current = max(prices, key=lambda p: p["attributes"].get("startDate") or "")
    point = included.get(("subscriptionPricePoints",
                          current["relationships"]["subscriptionPricePoint"]["data"]["id"]))
    return point["attributes"]["customerPrice"] if point else None


def intro_offers(sub_id):
    """All of the subscription's launch offers, and the US one in the file's format."""
    offers, included = get_all_with_included(
        f"/subscriptions/{sub_id}/introductoryOffers"
        "?include=subscriptionPricePoint,territory&limit=200")
    us = None
    for offer in offers:
        territory = (offer["relationships"].get("territory") or {}).get("data") or {}
        if territory.get("id") != BASE_TERRITORY:
            continue
        a = offer["attributes"]
        us = {"mode": a["offerMode"], "duration": a["duration"], "periods": a["numberOfPeriods"]}
        point = (offer["relationships"].get("subscriptionPricePoint") or {}).get("data")
        if point and ("subscriptionPricePoints", point["id"]) in included:
            us["price"] = included[("subscriptionPricePoints", point["id"])]["attributes"]["customerPrice"]
    return offers, us


def review_screenshot(sub_id):
    """The App Review screenshot resource, or None."""
    try:
        return call("GET", f"/subscriptions/{sub_id}/appStoreReviewScreenshot")["data"]
    except ApiError as e:
        if e.code == 404:
            return None
        raise


def localizations(path):
    return {loc["attributes"]["locale"]: loc for loc in get_all(path)}


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
            shot = review_screenshot(sub["id"])
            g["subscriptions"].append({
                "productId": a["productId"],
                "name": a["name"],
                "period": a.get("subscriptionPeriod"),
                "level": a.get("groupLevel"),
                "familySharable": a.get("familySharable", False),
                "price": us_price(sub["id"]),
                "introOffer": intro_offers(sub["id"])[1],
                "localizations": {
                    locale: {"name": loc["attributes"]["name"], "description": loc["attributes"].get("description")}
                    for locale, loc in localizations(
                        f"/subscriptions/{sub['id']}/subscriptionLocalizations?limit=50").items()
                },
                "reviewNote": a.get("reviewNote"),
                "reviewScreenshot": shot and {"checksum": shot["attributes"].get("sourceFileChecksum")},
                "state": a.get("state"),
            })
        groups.append(g)
    return {"groups": groups}


# ---------------------------------------------------------------------------
# Prices: a US price point and Apple's matching one in every other country


def us_price_point(sub_id, price):
    for point in get_all(f"/subscriptions/{sub_id}/pricePoints?filter[territory]={BASE_TERRITORY}&limit=200"):
        if point["attributes"]["customerPrice"] == price:
            return point["id"]
    sys.exit(f"::error::${price} isn't one of Apple's US price points.")


def price_points_everywhere(sub_id, price):
    """{territory: price point id} for this US price in every country."""
    us = us_price_point(sub_id, price)
    points = {BASE_TERRITORY: us}
    others, _ = get_all_with_included(f"/subscriptionPricePoints/{us}/equalizations?include=territory&limit=200")
    for point in others:
        points[point["relationships"]["territory"]["data"]["id"]] = point["id"]
    return points


def set_price(sub_id, price, is_new):
    points = price_points_everywhere(sub_id, price)
    for territory, point in points.items():
        post("subscriptionPrices", {"preserveCurrentPrice": not is_new},
             {"subscription": ("subscriptions", sub_id),
              "subscriptionPricePoint": ("subscriptionPricePoints", point),
              "territory": ("territories", territory)})
    print(f"  Set in {len(points)} countries.")


def set_intro_offer(sub_id, offer, existing):
    for old in existing:
        call("DELETE", f"/subscriptionIntroductoryOffers/{old['id']}")
    attrs = {"offerMode": offer["mode"], "duration": offer["duration"], "numberOfPeriods": offer.get("periods", 1)}
    if offer["mode"] == "FREE_TRIAL":
        territories = [t["id"] for t in get_all("/territories?limit=200")]
        points = {t: None for t in territories}
    else:
        points = price_points_everywhere(sub_id, offer["price"])
    for territory, point in points.items():
        rels = {"subscription": ("subscriptions", sub_id), "territory": ("territories", territory)}
        if point:
            rels["subscriptionPricePoint"] = ("subscriptionPricePoints", point)
        try:
            post("subscriptionIntroductoryOffers", attrs, rels)
        except ApiError as e:
            # Some countries don't sell the plan; skip them rather than stop.
            print(f"  Skipped {territory}: {e}")
    print(f"  Set in {len(points)} countries.")


# ---------------------------------------------------------------------------
# Syncing


def sync_localizations(kind, parent_rel, parent_id, current, wanted, fields):
    """kind: subscriptionLocalizations or subscriptionGroupLocalizations."""
    for locale, values in wanted.items():
        attrs = {api: values.get(key) for key, api in fields.items() if key in values}
        loc = current.get(locale)
        if not loc:
            change(f"add {locale} {attrs}",
                   lambda: post(kind, {"locale": locale, **attrs}, {parent_rel: parent_rel_ref(parent_rel, parent_id)}))
            continue
        diff = {k: v for k, v in attrs.items() if loc["attributes"].get(k) != v}
        if diff:
            change(f"update {locale} {diff}", lambda: patch(kind, loc["id"], diff))


def parent_rel_ref(rel, id_):
    return ({"subscription": "subscriptions", "subscriptionGroup": "subscriptionGroups"}[rel], id_)


def sync_review_screenshot(sub_id, path):
    with open(path, "rb") as f:
        data = f.read()
    md5 = hashlib.md5(data).hexdigest()
    current = review_screenshot(sub_id) if sub_id else None
    if current and current["attributes"].get("sourceFileChecksum") == md5:
        return

    def upload():
        if current:
            call("DELETE", f"/subscriptionAppStoreReviewScreenshots/{current['id']}")
        shot = post("subscriptionAppStoreReviewScreenshots",
                    {"fileName": os.path.basename(path), "fileSize": len(data)},
                    {"subscription": ("subscriptions", sub_id)})
        upload_parts(shot["attributes"]["uploadOperations"], data)
        patch("subscriptionAppStoreReviewScreenshots", shot["id"], {"uploaded": True, "sourceFileChecksum": md5})

    change(f"upload review screenshot {os.path.basename(path)}", upload)


def sync_subscription(group_id, current, wanted, folder):
    pid = wanted["productId"]
    print(f"-- {pid}")
    fields = {"name": "name", "period": "subscriptionPeriod", "level": "groupLevel",
              "familySharable": "familySharable", "reviewNote": "reviewNote"}
    attrs = {api: wanted[key] for key, api in fields.items() if key in wanted}
    is_new = current is None
    if is_new:
        created = change(f"create plan {pid}", lambda: post(
            "subscriptions", {"productId": pid, **{k: v for k, v in attrs.items() if k != "groupLevel"}},
            {"group": ("subscriptionGroups", group_id)}))
        sub_id = created["id"] if created else None
        if sub_id:
            territories = [t["id"] for t in get_all("/territories?limit=200")]
            post("subscriptionAvailabilities", {"availableInNewTerritories": True},
                 {"subscription": ("subscriptions", sub_id), "availableTerritories": ("territories", territories)})
            print(f"  Available in {len(territories)} countries.")
    else:
        sub_id = current["id"]
        diff = {k: v for k, v in attrs.items() if current["attributes"].get(k) != v}
        if diff:
            change(f"update {diff}", lambda: patch("subscriptions", sub_id, diff))

    if not sub_id:  # dry run of a new plan: nothing to read yet
        for key in ("price", "introOffer", "localizations", "reviewScreenshot"):
            if wanted.get(key):
                print(f"Would: set {key} {wanted[key] if key != 'localizations' else list(wanted[key])}")
        return

    sync_localizations("subscriptionLocalizations", "subscription", sub_id,
                       localizations(f"/subscriptions/{sub_id}/subscriptionLocalizations?limit=50"),
                       wanted.get("localizations", {}), {"name": "name", "description": "description"})

    if wanted.get("price"):
        have = None if is_new else us_price(sub_id)
        if have != wanted["price"]:
            change(f"set price ${have} -> ${wanted['price']} (current subscribers keep their price)",
                   lambda: set_price(sub_id, wanted["price"], is_new or have is None),
                   lambda: check_price(sub_id, wanted["price"]))

    if wanted.get("introOffer"):
        offers, have = intro_offers(sub_id)
        want = {k: v for k, v in wanted["introOffer"].items()}
        want.setdefault("periods", 1)
        if have != want:
            change(f"set launch offer {have} -> {want}", lambda: set_intro_offer(sub_id, want, offers),
                   (lambda: check_price(sub_id, want["price"])) if want.get("price") else None)

    if wanted.get("reviewScreenshot"):
        sync_review_screenshot(sub_id, os.path.join(folder, wanted["reviewScreenshot"]))

    if APPLY:
        state = call("GET", f"/subscriptions/{sub_id}")["data"]["attributes"].get("state")
        print(f"  State: {state}")


def sync(app_id, config, folder):
    groups = {g["attributes"]["referenceName"]: g for g in get_all(f"/apps/{app_id}/subscriptionGroups?limit=50")}
    for wanted in config["groups"]:
        print(f"== {wanted['name']}")
        group = groups.get(wanted["name"])
        if group:
            group_id = group["id"]
        else:
            created = change(f"create group {wanted['name']}", lambda: post(
                "subscriptionGroups", {"referenceName": wanted["name"]}, {"app": ("apps", app_id)}))
            group_id = created["id"] if created else None
        if not group_id:
            print(f"Would: add {len(wanted.get('subscriptions', []))} plans to it")
            continue
        sync_localizations("subscriptionGroupLocalizations", "subscriptionGroup", group_id,
                           localizations(f"/subscriptionGroups/{group_id}/subscriptionGroupLocalizations?limit=50"),
                           wanted.get("localizations", {}), {"name": "name", "appName": "customAppName"})
        subs = {s["attributes"]["productId"]: s
                for s in get_all(f"/subscriptionGroups/{group_id}/subscriptions?limit=50")}
        for sub in wanted.get("subscriptions", []):
            sync_subscription(group_id, subs.get(sub["productId"]), sub, folder)


def main(bundle_id, config_path, *flags):
    global APPLY
    APPLY = "--apply" in flags
    apps = find("/apps", bundle_id, "bundleId")
    if not apps:
        sys.exit(f"::error::No App Store Connect app uses {bundle_id} yet.")
    app_id = apps[0]["id"]
    if not os.path.exists(config_path):
        print(f"No {config_path} yet. App Store Connect has:")
        print(json.dumps(export(app_id), indent=2))
        return
    with open(config_path) as f:
        config = json.load(f)
    sync(app_id, config, os.path.dirname(config_path))
    print("Done." if APPLY else "Dry run: nothing changed. Changes apply on main.")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    run(main, *sys.argv[1:])
