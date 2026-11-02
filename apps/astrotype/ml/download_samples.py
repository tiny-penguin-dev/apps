"""Download training samples uploaded by the app from CloudKit.

    python3 download_samples.py                 # → samples/cloud/<id>.json, only new ones
    python3 finetune.py samples/cloud           # then train on them
    python3 download_samples.py --type PracticeSession   # → samples/practice/<id>.json
    swift run -c release astrotype-tools replay ../../ml/samples/practice   # (in ios/AstrotypeKit)

Uses a CloudKit server-to-server key (see ../cloudkit/README.md): the private key
at ~/.config/astrotype/cloudkit-key.pem and its Key ID in
~/.config/astrotype/cloudkit-key-id (or --key / --key-id, or the CLOUDKIT_KEY_PATH
and CLOUDKIT_KEY_ID environment variables). Standard library plus `openssl`.
"""
import argparse, base64, hashlib, json, os, subprocess, sys
import urllib.error, urllib.request
from datetime import datetime, timezone
from pathlib import Path

CONTAINER = "iCloud.com.tinypenguin.astrotype"
CONFIG = Path.home() / ".config/astrotype"


def signed_post(subpath, body, key_id, key_path):
    data = json.dumps(body).encode()
    date = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    payload = f"{date}:{base64.b64encode(hashlib.sha256(data).digest()).decode()}:{subpath}"
    signature = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(key_path)],
                               input=payload.encode(), capture_output=True, check=True).stdout
    req = urllib.request.Request(
        "https://api.apple-cloudkit.com" + subpath, data=data, method="POST",
        headers={"Content-Type": "application/json",
                 "X-Apple-CloudKit-Request-KeyID": key_id,
                 "X-Apple-CloudKit-Request-ISO8601Date": date,
                 "X-Apple-CloudKit-Request-SignatureV1": base64.b64encode(signature).decode()})
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"CloudKit error {e.code}: {e.read().decode()}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--type", default="Sample", help="the record type: Sample (v1 handwriting) or PracticeSession (v2 keyboard)")
    ap.add_argument("--out", help="default samples/cloud for Sample, samples/practice for PracticeSession")
    ap.add_argument("--key", default=os.environ.get("CLOUDKIT_KEY_PATH", str(CONFIG / "cloudkit-key.pem")))
    ap.add_argument("--key-id", default=os.environ.get("CLOUDKIT_KEY_ID"))
    ap.add_argument("--development", action="store_true", help="read the development environment (builds run from Xcode)")
    a = ap.parse_args()

    key_id = a.key_id or (CONFIG / "cloudkit-key-id").read_text().strip()
    env = "development" if a.development else "production"
    subpath = f"/database/1/{CONTAINER}/{env}/public/records/query"
    out = Path(a.out) if a.out else Path(__file__).parent / ("samples/cloud" if a.type == "Sample" else "samples/practice")
    out.mkdir(parents=True, exist_ok=True)

    marker, new, seen = None, 0, 0
    while True:
        body = {"zoneID": {"zoneName": "_defaultZone"}, "resultsLimit": 200, "desiredKeys": ["json"],
                "query": {"recordType": a.type,
                          "sortBy": [{"systemFieldName": "createdTimestamp", "ascending": True}]}}
        if marker:
            body["continuationMarker"] = marker
        page = signed_post(subpath, body, key_id, a.key)
        for record in page.get("records", []):
            if "serverErrorCode" in record:
                print(f"skipping {record.get('recordName')}: {record['serverErrorCode']}")
                continue
            seen += 1
            path = out / f"{record['recordName']}.json"
            text = record.get("fields", {}).get("json", {}).get("value")
            if text and not path.exists():
                path.write_text(text)
                new += 1
        marker = page.get("continuationMarker")
        if not marker:
            break
    print(f"{seen} {a.type} records in CloudKit ({env}), {new} new, saved in {out}")


if __name__ == "__main__":
    main()
