"""Teach the model real handwriting: one command from recorded samples to a
new model in the app.

    python3 finetune.py ~/Downloads/StackWrite-samples-*.zip            # train and score
    python3 finetune.py samples/ --minutes 5 --ship                     # ...and put it in the app

Steps:
1. Import the samples (import_captures.py). About 15% of them, whole sessions,
   are held back to score the model on words it didn't train on.
2. Build ~4k synthetic "replay" words once (data/replay_4k.npz), so the model
   keeps what it knew while it learns the new writing.
3. Score the starting model on the held-back words.
4. Fine-tune (train.py) on replay + your samples repeated to about the same size.
   Uses the Apple GPU (mps) when there is one.
5. Score again. With --ship: export Core ML, regenerate golden.json and the
   lexicon, and copy the model into the iOS app (ios/StackWrite/Model).
"""
import argparse, shutil, subprocess, sys
from itertools import groupby
from pathlib import Path
import numpy as np, torch

import samples as S
from import_captures import to_npz, split
from data import load
from decode import build_trie, beam_search
from model import ConvStrokeNet
from synth import lexicon
from train import collate

HERE = Path(__file__).parent
IOS_MODEL = HERE.parent / "ios" / "StackWrite" / "Model"


def run(*args):
    shown = []
    for x, group in groupby(map(str, args)):
        name = Path(x).name if "/" in x else x
        n = len(list(group))
        shown.append(f"{name} (x{n})" if n > 1 else name)
    print("$", " ".join(shown), flush=True)
    subprocess.run([sys.executable, *map(str, args)], cwd=HERE, check=True)


@torch.no_grad()
def score(weights, npz, trie):
    """Top-1 and top-3 word accuracy with the dictionary decoder."""
    m = ConvStrokeNet(); m.load_state_dict(torch.load(weights, map_location="cpu")); m.eval()
    feats, labels = load(npz)
    top1 = top3 = 0
    misses = []
    for i in range(0, len(feats), 64):
        x, lens, _, _, ls = collate(feats[i:i + 64], labels[i:i + 64])
        lp = m(x, lens)
        ol = m.out_lens(lens)
        for b, truth in enumerate(ls):
            ws = [w for w, _ in beam_search(lp[b, :ol[b]].numpy(), trie)]
            top1 += bool(ws) and ws[0] == truth
            top3 += truth in ws[:3]
            if (not ws or ws[0] != truth) and len(misses) < 8:
                misses.append(f"{truth} → {ws[:3]}")
    n = max(len(feats), 1)
    return top1 / n, top3 / n, misses


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+", help="folders, .zip or .jsonl files of samples")
    ap.add_argument("--name", default="mine", help="names the outputs: data/<name>.npz, runs/<name>.pt")
    ap.add_argument("--init", default="runs/final.pt", help="model to start from")
    ap.add_argument("--minutes", type=float, default=3)
    ap.add_argument("--lr", type=float, default=5e-4)
    ap.add_argument("--test", type=float, default=0.15, help="share of samples held back for scoring")
    ap.add_argument("--writer", help="only use samples from this writer ID")
    ap.add_argument("--device", default="auto")
    ap.add_argument("--ship", action="store_true", help="export the new model into the iOS app")
    a = ap.parse_args()

    (HERE / "data").mkdir(exist_ok=True)
    (HERE / "runs").mkdir(exist_ok=True)

    # 1. import
    items = S.load(a.inputs)
    if a.writer:
        items = [s for s in items if s.get("writer") == a.writer]
    if len(items) < 20:
        sys.exit(f"Only {len(items)} usable samples. Record at least 50 words first.")
    train_items, test_items = split(items, a.test) if a.test > 0 else (items, [])
    mine, mine_test = HERE / f"data/{a.name}.npz", HERE / f"data/{a.name}_test.npz"
    to_npz(train_items, mine)
    if test_items:
        to_npz(test_items, mine_test)

    # 2. replay data
    replay = HERE / "data/replay_4k.npz"
    if not replay.exists():
        run("data.py", "--n", 4000, "--seed", 7, "--styles", "natural,futural,scripts", "--out", replay)
    synth_test = HERE / "data/test_small.npz"
    if not synth_test.exists():
        run("data.py", "--n", 400, "--seed", 5, "--styles", "natural,futural,scripts", "--p_random", 0,
            "--out", synth_test)

    words, freqs = lexicon()
    trie = build_trie(words, freqs)

    # 3. score before
    if test_items:
        b1, b3, _ = score(HERE / a.init, mine_test, trie)
        print(f"\nbefore: {b1:.1%} top-1, {b3:.1%} in top 3 on {len(test_items)} held-back words\n")

    # 4. fine-tune: your samples repeated to about the size of the replay set
    repeats = max(1, round(4000 / max(len(train_items), 1)))
    out = HERE / f"runs/{a.name}.pt"
    val = [mine_test] if test_items else [synth_test]
    run("train.py", "--train", replay, *([mine] * repeats), "--val", *val, synth_test,
        "--minutes", a.minutes, "--lr", a.lr, "--init", a.init, "--out", out, "--device", a.device)

    # 5. score after
    s1, s3, _ = score(HERE / a.init, synth_test, trie)
    n1, n3, _ = score(out, synth_test, trie)
    print(f"\nsynthetic words: {s1:.1%} → {n1:.1%} top-1 (should stay high)")
    if test_items:
        a1, a3, misses = score(out, mine_test, trie)
        print(f"your held-back words: {b1:.1%} → {a1:.1%} top-1, {b3:.1%} → {a3:.1%} in top 3")
        for m in misses:
            print("   ", m)
    print(f"\nnew weights: {out}")

    if a.ship:
        run("export.py", "--model", out, "--out", "export/StackWrite")
        run("make_golden.py", "--model", out)
        IOS_MODEL.mkdir(parents=True, exist_ok=True)
        shutil.rmtree(IOS_MODEL / "StrokeModel.mlpackage", ignore_errors=True)
        shutil.copytree(HERE / "export/StackWrite.mlpackage", IOS_MODEL / "StrokeModel.mlpackage")
        shutil.copy(HERE / "export/lexicon.tsv", IOS_MODEL / "lexicon.tsv")
        print(f"copied the model into {IOS_MODEL}. To make it the default, copy {out} to runs/final.pt "
              "and commit it with export/ and the app's Model folder.")


if __name__ == "__main__":
    main()
