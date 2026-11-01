#!/usr/bin/env python3
"""Upload an app's App Store screenshots from the repo to App Store Connect.

Screenshots live in the app's store/screenshots/ folder, one folder per
language, in the order they should appear:

    apps/<name>/store/screenshots/en-US/1-home.png
                                        2-rings.png

The device each one is for comes from its size (a 1320 x 2868 PNG is a 6.9"
iPhone screenshot). They go to the app's version that can still be edited
(the one being prepared for review). A set whose files already match, by name
and checksum, is left alone. A set that changed is replaced as a whole, so
removing or reordering files works too.

Usage: asc-upload-screenshots.py <bundle-id> <screenshots-folder>
Env:   see asc.py. The API key needs the App Manager or Admin role.
"""

import hashlib
import os
import struct
import sys
import time

from asc import call, find, get_all, run, upload_parts

# Screenshot size (short side, long side) -> App Store Connect display type.
DISPLAY_TYPES = {
    (1320, 2868): "APP_IPHONE_67",  # 6.9" iPhone
    (1290, 2796): "APP_IPHONE_67",
    (1260, 2736): "APP_IPHONE_67",
    (1284, 2778): "APP_IPHONE_65",  # 6.5" iPhone
    (1242, 2688): "APP_IPHONE_65",
    (1206, 2622): "APP_IPHONE_61",  # 6.3" iPhone
    (1179, 2556): "APP_IPHONE_61",
    (1242, 2208): "APP_IPHONE_55",  # 5.5" iPhone
    (2064, 2752): "APP_IPAD_PRO_3GEN_129",  # 13" iPad
    (2048, 2732): "APP_IPAD_PRO_3GEN_129",
    (1668, 2388): "APP_IPAD_PRO_3GEN_11",  # 11" iPad
}
MAX_PER_SET = 10

# Version states where screenshots can still change.
EDITABLE = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
    "READY_FOR_REVIEW",
}


def image_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", head[16:24])
    with open(path, "rb") as f:  # JPEG: walk the segments to the frame header
        data = f.read()
    i = 2
    while i < len(data):
        marker, length = data[i + 1], struct.unpack(">H", data[i + 2 : i + 4])[0]
        if marker in (0xC0, 0xC1, 0xC2):
            h, w = struct.unpack(">HH", data[i + 5 : i + 9])
            return w, h
        i += 2 + length
    raise ValueError(f"{path}: not a PNG or JPEG")


def local_sets(folder):
    """{locale: {display type: [(file name, path, md5)]}} from the folder."""
    sets = {}
    for locale in sorted(os.listdir(folder)):
        locale_dir = os.path.join(folder, locale)
        if not os.path.isdir(locale_dir):
            continue
        for name in sorted(os.listdir(locale_dir)):
            if not name.lower().endswith((".png", ".jpg", ".jpeg")):
                continue
            path = os.path.join(locale_dir, name)
            size = tuple(sorted(image_size(path)))
            if size not in DISPLAY_TYPES:
                sys.exit(f"::error::{path} is {size[0]} x {size[1]}, which isn't an App Store screenshot size.")
            with open(path, "rb") as f:
                md5 = hashlib.md5(f.read()).hexdigest()
            sets.setdefault(locale, {}).setdefault(DISPLAY_TYPES[size], []).append((name, path, md5))
    for locale, by_type in sets.items():
        for display_type, files in by_type.items():
            if len(files) > MAX_PER_SET:
                sys.exit(f"::error::{locale} has {len(files)} {display_type} screenshots; the App Store takes {MAX_PER_SET}.")
    return sets


def editable_version(app_id):
    versions = get_all(f"/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=50")
    for version in versions:
        attrs = version["attributes"]
        if (attrs.get("appVersionState") or attrs.get("appStoreState")) in EDITABLE:
            return version
    return None


def localization(version_id, locale, existing):
    for loc in existing:
        if loc["attributes"]["locale"] == locale:
            return loc["id"]
    loc = call(
        "POST",
        "/appStoreVersionLocalizations",
        {
            "data": {
                "type": "appStoreVersionLocalizations",
                "attributes": {"locale": locale},
                "relationships": {
                    "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}
                },
            }
        },
    )["data"]
    print(f"Added language {locale}.")
    return loc["id"]


def screenshot_set(localization_id, display_type):
    """The set's id and its current screenshots, in order."""
    sets = call(
        "GET",
        f"/appStoreVersionLocalizations/{localization_id}/appScreenshotSets"
        f"?filter[screenshotDisplayType]={display_type}&include=appScreenshots&limit[appScreenshots]=50",
    )
    if sets["data"]:
        s = sets["data"][0]
        included = {i["id"]: i for i in sets.get("included", []) if i["type"] == "appScreenshots"}
        order = [r["id"] for r in s["relationships"]["appScreenshots"].get("data", [])]
        return s["id"], [included[i] for i in order if i in included]
    s = call(
        "POST",
        "/appScreenshotSets",
        {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": display_type},
                "relationships": {
                    "appStoreVersionLocalization": {
                        "data": {"type": "appStoreVersionLocalizations", "id": localization_id}
                    }
                },
            }
        },
    )["data"]
    return s["id"], []


def upload(set_id, name, path, md5):
    with open(path, "rb") as f:
        data = f.read()
    shot = call(
        "POST",
        "/appScreenshots",
        {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": name, "fileSize": len(data)},
                "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}},
            }
        },
    )["data"]
    upload_parts(shot["attributes"]["uploadOperations"], data)
    call(
        "PATCH",
        f"/appScreenshots/{shot['id']}",
        {"data": {"type": "appScreenshots", "id": shot["id"],
                  "attributes": {"uploaded": True, "sourceFileChecksum": md5}}},
    )
    return shot["id"]


def wait_until_processed(ids):
    deadline = time.time() + 300
    pending = set(ids)
    while pending and time.time() < deadline:
        for shot_id in list(pending):
            attrs = call("GET", f"/appScreenshots/{shot_id}")["data"]["attributes"]
            state = (attrs.get("assetDeliveryState") or {}).get("state")
            if state == "FAILED":
                errors = attrs["assetDeliveryState"].get("errors")
                sys.exit(f"::error::App Store Connect couldn't process {attrs['fileName']}: {errors}")
            if state == "COMPLETE":
                pending.discard(shot_id)
        if pending:
            time.sleep(5)
    if pending:
        print(f"{len(pending)} screenshots are still processing in App Store Connect; that finishes on its own.")


def matches(current, files):
    """True when the set already holds these files, in this order. App Store Connect
    only reports a screenshot's checksum once it has finished processing, so one
    still processing counts as a match by name."""
    if len(current) != len(files):
        return False
    for shot, (name, _, md5) in zip(current, files):
        attrs = shot["attributes"]
        state = (attrs.get("assetDeliveryState") or {}).get("state")
        if attrs["fileName"] != name:
            return False
        if attrs.get("sourceFileChecksum") != md5 and not (
            attrs.get("sourceFileChecksum") is None and state == "UPLOAD_COMPLETE"
        ):
            return False
    return True


def sync_set(localization_id, locale, display_type, files):
    set_id, current = screenshot_set(localization_id, display_type)
    have = [(s["attributes"]["fileName"], s["attributes"].get("sourceFileChecksum")) for s in current]
    want = [(name, md5) for name, _, md5 in files]
    if matches(current, files):
        print(f"{locale} {display_type}: up to date ({len(files)} screenshots).")
        return
    print(f"{locale} {display_type}: uploading {len(files)} screenshots (replacing {len(current)}).")
    if current:
        print(f"  App Store Connect has: {have}")
        print(f"  The repo has:          {want}")
    for s in current:
        call("DELETE", f"/appScreenshots/{s['id']}")
    ids = [upload(set_id, name, path, md5) for name, path, md5 in files]
    call(
        "PATCH",
        f"/appScreenshotSets/{set_id}/relationships/appScreenshots",
        {"data": [{"type": "appScreenshots", "id": i} for i in ids]},
    )
    wait_until_processed(ids)


def main(bundle_id, folder):
    sets = local_sets(folder)
    if not sets:
        print(f"No screenshots in {folder}.")
        return
    apps = find("/apps", bundle_id, "bundleId")
    if not apps:
        sys.exit(f"::error::No App Store Connect app uses {bundle_id} yet. Create it first (docs/ios-release.md).")
    version = editable_version(apps[0]["id"])
    if not version:
        print("::warning::Skipping screenshots: no app version can be edited right now. "
              "Add a new version in App Store Connect, then re-run this workflow.")
        return
    print(f"Version {version['attributes']['versionString']}.")
    existing = get_all(f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")
    for locale, by_type in sets.items():
        loc_id = localization(version["id"], locale, existing)
        for display_type, files in by_type.items():
            sync_set(loc_id, locale, display_type, files)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    run(main, *sys.argv[1:3])
