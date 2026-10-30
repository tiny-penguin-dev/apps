"""Read recorded samples (the app's JSON format, see ../SAMPLES.md).

Accepts any mix of: folders (searched recursively for *.json), .zip files
exported from the app, and .jsonl files with one sample per line.
"""
import json, zipfile
from pathlib import Path
import numpy as np
from letters import ALPHABET

FORMAT_VERSION = 1


def _from_bytes(raw, where):
    try:
        s = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"skipping {where}: {e}")
        return None
    if not isinstance(s, dict) or "points" not in s or "label" not in s:
        return None
    if s.get("version", 1) > FORMAT_VERSION:
        print(f"skipping {where}: format version {s['version']} is newer than this script")
        return None
    return s


def read(paths):
    """Yields sample dicts from every path."""
    for p in map(Path, paths):
        if p.is_dir():
            for f in sorted(p.rglob("*.json")):
                if not f.name.startswith("._"):
                    s = _from_bytes(f.read_bytes(), f)
                    if s: yield s
            for f in sorted(p.rglob("*.jsonl")):
                yield from read([f])
            for f in sorted(p.rglob("*.zip")):
                yield from read([f])
        elif p.suffix == ".zip":
            with zipfile.ZipFile(p) as z:
                for name in sorted(z.namelist()):
                    if name.endswith(".json") and "__MACOSX" not in name and not Path(name).name.startswith("._"):
                        s = _from_bytes(z.read(name), f"{p}:{name}")
                        if s: yield s
        elif p.suffix == ".jsonl":
            for i, line in enumerate(p.read_text().splitlines()):
                if line.strip():
                    s = _from_bytes(line, f"{p}:{i + 1}")
                    if s: yield s
        elif p.suffix == ".json":
            s = _from_bytes(p.read_bytes(), p)
            if s: yield s


def load(paths, dedupe=True):
    """All usable samples: label is a-z only and the stroke has at least 2 points."""
    out, seen, skipped = [], set(), 0
    for s in read(paths):
        if dedupe and s.get("id") in seen:
            continue
        seen.add(s.get("id"))
        label = s["label"].lower()
        if not label or any(c not in ALPHABET for c in label) or len(s["points"]) < 2:
            skipped += 1
            continue
        s["label"] = label
        out.append(s)
    if skipped:
        print(f"skipped {skipped} samples the model can't learn yet (not a-z, or empty)")
    return out


def path_of(sample):
    """The stroke as an (N, 2) array in box units, y up."""
    return np.asarray(sample["points"], dtype=float)[:, :2]
