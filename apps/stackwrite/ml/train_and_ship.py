"""Retrain StackWrite on everything recorded and put the model in the app if
it's better. Run by the "StackWrite train" GitHub workflow, or by hand:

    python3 train_and_ship.py                 # download, train, score, ship if better
    python3 train_and_ship.py --minutes 15    # train longer
    python3 train_and_ship.py --force         # train even if nothing new was recorded

Steps:
1. Download new samples from iCloud (download_samples.py).
2. Stop if nothing new arrived since the model in the app was trained.
3. Fine-tune models/base.pt (the synthetic-only phrase model) on all samples,
   holding back whole sessions to score on (finetune_phrases.py).
4. Score the new model and the one in the app (models/shipped.pt) on the same
   held-back samples. Ship only if the new one has a lower word error and
   reads synthetic phrases nearly as well (at most 3 points worse).
5. Shipping: export Core ML, regenerate golden.json, copy the model into the
   app, and record it as models/shipped.pt and models/shipped.json.
   Committing and pushing is up to the caller (the workflow or you).

Writes runs/report.md either way, and `shipped=true|false` to $GITHUB_OUTPUT
when it runs in GitHub Actions.
"""
import argparse, json, os, shutil, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path

import samples as S

HERE = Path(__file__).parent
MODELS = HERE / "models"
IOS_MODEL = HERE.parent / "ios" / "StackWrite" / "Model"
MAX_SYNTH_DROP = 0.03


def run(*args):
    print("$", " ".join(map(str, args)), flush=True)
    subprocess.run([sys.executable, *map(str, args)], cwd=HERE, check=True)


def pct(x):
    return "–" if x is None else f"{x:.1%}"


def finish(shipped, lines):
    report = "\n".join(lines) + "\n"
    (HERE / "runs").mkdir(exist_ok=True)
    (HERE / "runs/report.md").write_text(report)
    print("\n" + report)
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as f:
            f.write(f"shipped={'true' if shipped else 'false'}\n")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write(report)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--minutes", type=float, default=6)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--force", action="store_true", help="train even with no new samples")
    ap.add_argument("--ship-anyway", action="store_true", help="ship even if it doesn't score better")
    ap.add_argument("--no-download", action="store_true")
    a = ap.parse_args()

    if not a.no_download:
        run("download_samples.py")
    samples = HERE / "samples/cloud"
    items = S.load([samples], phrases=True)
    shipped_info = json.loads((MODELS / "shipped.json").read_text()) if (MODELS / "shipped.json").exists() else {}
    new = len(items) - shipped_info.get("samples", 0)
    if new <= 0 and not a.force:
        return finish(False, ["## StackWrite training", "",
                              f"Nothing new: {len(items)} samples, the same as the model in the app was trained on."])

    run("finetune_phrases.py", samples, "--init", "models/base.pt", "--out", "runs/candidate.pt",
        "--minutes", a.minutes, "--workers", a.workers,
        "--compare", "models/shipped.pt", "--report", "runs/scores.json")
    scores = json.loads((HERE / "runs/scores.json").read_text())
    cand = scores["models"]["runs/candidate.pt"]
    old = scores["models"].get("models/shipped.pt")

    def wer(r, key="held_back"):
        return r.get(key, {}).get("wer") if r else None

    def exact(r, key="held_back"):
        return r.get(key, {}).get("exact") if r else None

    better = old is None or wer(cand) is None or wer(old) is None or wer(cand) < wer(old)
    keeps_synth = old is None or cand["synthetic_exact"] >= old["synthetic_exact"] - MAX_SYNTH_DROP
    ship = a.ship_anyway or (better and keeps_synth)

    lines = ["## StackWrite training", "",
             f"{scores['samples']} samples ({scores['phrases']} phrases with finger lifts, {max(new, 0)} new). "
             f"Trained {a.minutes:g} min on {scores['trained_on']}, scored on {scores['held_back']} held back "
             f"({scores['held_back_phrase_count']} of them phrases).", "",
             "| | In the app now | New model |", "|---|---|---|",
             f"| Held back: exactly right | {pct(exact(old))} | {pct(exact(cand))} |",
             f"| Held back: word error | {pct(wer(old))} | {pct(wer(cand))} |",
             f"| Held-back phrases: exactly right | {pct(exact(old, 'held_back_phrases'))} | "
             f"{pct(exact(cand, 'held_back_phrases'))} |",
             f"| Synthetic phrases: exactly right | {pct(old and old['synthetic_exact'])} | "
             f"{pct(cand['synthetic_exact'])} |", ""]
    if not ship:
        why = "it doesn't read the held-back samples better" if not better else \
            "it got worse at synthetic phrases (it may be forgetting what it knew)"
        lines.append(f"**Not shipped:** {why}. The app keeps its current model.")
        return finish(False, lines)

    run("export.py", "--model", "runs/candidate.pt", "--out", "export/StackWrite")
    run("make_golden.py", "--model", "runs/candidate.pt")
    shutil.rmtree(IOS_MODEL / "StrokeModel.mlpackage", ignore_errors=True)
    shutil.copytree(HERE / "export/StackWrite.mlpackage", IOS_MODEL / "StrokeModel.mlpackage")
    shutil.copy(HERE / "export/lexicon.tsv", IOS_MODEL / "lexicon.tsv")
    shutil.copy(HERE / "runs/candidate.pt", MODELS / "shipped.pt")
    (MODELS / "shipped.json").write_text(json.dumps({
        "trained": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "samples": len(items), "minutes": a.minutes, "scores": cand}, indent=1) + "\n")
    lines.append("**Shipped:** the new model is in the app.")
    finish(True, lines)


if __name__ == "__main__":
    main()
