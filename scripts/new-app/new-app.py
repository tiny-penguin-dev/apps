#!/usr/bin/env python3
"""Create a new iOS app in this repo from the template next to this script.

Makes apps/<slug>/ios (Xcode project with Sentry, config, placeholder app and icon), the
app's CI workflow, and a CLAUDE.md and README.md if the app doesn't have them
yet. Existing files are never overwritten.

Usage: scripts/new-app/new-app.py <Name> [--slug squawk] [--display "Squawk"]
                                         [--bundle com.tinypenguin.squawk]
  <Name>     Xcode target and scheme name, PascalCase (e.g. Squawk)
  --slug     folder name under apps/ (default: Name in lowercase)
  --display  name shown under the icon (default: Name)
  --bundle   bundle ID (default: com.tinypenguin.<slug>)
"""

import argparse
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TEMPLATE = HERE / "template"
REPO = HERE.parent.parent


def make_icon(path: Path, display: str) -> None:
    """A placeholder icon: a round penguin on a soft color. Replace before release."""
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("  Pillow isn't installed, so no placeholder icon was made. Add a 1024x1024 "
              f"AppIcon.png to {path.parent} before uploading.")
        return
    size = 1024
    hues = [(255, 183, 77), (129, 212, 250), (165, 214, 167), (244, 143, 177), (179, 157, 219)]
    bg = hues[sum(map(ord, display)) % len(hues)]
    img = Image.new("RGB", (size, size), bg)
    d = ImageDraw.Draw(img)
    d.ellipse((262, 200, 762, 900), fill=(38, 50, 56))          # body
    d.ellipse((337, 380, 687, 880), fill=(255, 255, 255))       # belly
    d.ellipse((402, 300, 462, 360), fill=(255, 255, 255))       # eyes
    d.ellipse((562, 300, 622, 360), fill=(255, 255, 255))
    d.ellipse((420, 318, 452, 350), fill=(38, 50, 56))
    d.ellipse((580, 318, 612, 350), fill=(38, 50, 56))
    d.polygon([(462, 380), (562, 380), (512, 450)], fill=(255, 167, 38))  # beak
    d.ellipse((392, 870, 492, 930), fill=(255, 167, 38))        # feet
    d.ellipse((532, 870, 632, 930), fill=(255, 167, 38))
    img.save(path)


def fill(text: str, values: dict) -> str:
    for key, value in values.items():
        text = text.replace(key, value)
    return text


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("name")
    p.add_argument("--slug")
    p.add_argument("--display")
    p.add_argument("--bundle")
    a = p.parse_args()

    if not re.fullmatch(r"[A-Z][A-Za-z0-9]*", a.name):
        sys.exit("Name must be PascalCase letters and digits, like Squawk or Astrotype.")
    slug = a.slug or a.name.lower()
    if not re.fullmatch(r"[a-z][a-z0-9-]*", slug):
        sys.exit("Slug must be lowercase letters, digits and dashes.")
    display = a.display or a.name
    bundle = a.bundle or f"com.tinypenguin.{slug.replace('-', '')}"
    env = slug.upper().replace("-", "_")  # e.g. SQUAWK, for names in capitals
    values = {"__NAME__": a.name, "__SLUG__": slug, "__DISPLAY__": display, "__BUNDLE__": bundle,
              "__ENV__": env}

    app_dir = REPO / "apps" / slug
    if (app_dir / "ios").exists():
        sys.exit(f"{app_dir / 'ios'} already exists.")
    workflow = REPO / ".github" / "workflows" / f"{slug}-ios.yml"
    if workflow.exists():
        sys.exit(f"{workflow} already exists.")

    made = []
    for src in sorted(TEMPLATE.rglob("*")):
        if src.is_dir() or src.name == "workflow.yml":
            continue
        rel = fill(str(src.relative_to(TEMPLATE)), values)
        dest = app_dir / rel
        if dest.exists():
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(fill(src.read_text(), values))
        made.append(dest)

    workflow.write_text(fill((TEMPLATE / "workflow.yml").read_text(), values))
    made.append(workflow)

    icon = app_dir / "ios" / a.name / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
    make_icon(icon, display)
    if icon.exists():
        made.append(icon)

    for path in made:
        print("  created", path.relative_to(REPO))
    print(f"\n{display} is set up: bundle ID {bundle}, scheme {a.name}, folder apps/{slug}.")
    print("Next: add a row to the apps table in README.md, push, and do the one-time Apple")
    print('setup in docs/ios-release.md ("One-time setup for each new app").')
    print(f"Sentry: the first TestFlight run creates the Sentry project {slug} (docs/telemetry.md).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
