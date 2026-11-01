"""Teach the phrase model real handwriting: recorded samples in, a new model
(optionally in the app) out.

    python3 download_samples.py
    python3 finetune_phrases.py samples/cloud                  # train and score
    python3 finetune_phrases.py samples/cloud --ship           # ...and put it in the app

Uses phrase recordings (version 2) and the older one-word, one-stroke ones
(version 1). About 15% of them, whole sessions, are held back to score on.
Every batch is half your writing (slightly reshaped and re-timed each time,
so the model doesn't memorize exact strokes) and half fresh synthetic
phrases, so it keeps what it knew.
"""
import argparse, json, math, shutil, subprocess, sys, time
from pathlib import Path
import numpy as np, torch, torch.nn as nn
from torch.utils.data import DataLoader

import samples as S
from decode_phrase import build_trie
from eval_phrases import score
from eval_real import read, writer_scales
from import_captures import split
from model import ConvStrokeNet
from phrases import FEATURES, N_CLASSES, featurize_strokes
from synth import lexicon
from train import pick_device, save
from train_phrases import Phrases, collate, word_list

HERE = Path(__file__).parent
IOS_MODEL = HERE.parent / "ios" / "Astrotype" / "Model"


def augment(strokes, rng):
    """Small changes a writer makes from one time to the next: size, slant,
    rotation, position and speed."""
    A = np.array([[1, rng.normal(0, 0.08)], [0, 1]]) * rng.uniform(0.9, 1.1)
    r = rng.normal(0, 0.05)
    A = A @ np.array([[np.cos(r), -np.sin(r)], [np.sin(r), np.cos(r)]])
    shift = rng.normal(0, 0.03, 2)
    speed = rng.uniform(0.8, 1.25)
    out = []
    for s in strokes:
        xy = (s[:, :2] - 0.5) @ A.T + 0.5 + shift
        out.append(np.column_stack([xy, s[:, 2] * speed]))
    return out


def as_list(batch):
    return batch


def run(*args):
    print("$", " ".join(map(str, args)), flush=True)
    subprocess.run([sys.executable, *map(str, args)], cwd=HERE, check=True)


def report(name, model, items, scales, trie, show=0):
    if not items:
        return None
    truths, _, decoded = read(model, items, scales, trie)
    s = score(decoded, truths)
    print(f"{name}: {s['exact']:.1%} exactly right, word error {s['wer']:.1%}, word count right {s['breaks']:.1%}")
    for t, d in [(t, d) for t, d in zip(truths, decoded) if t != d][:show]:
        print(f"    want {t!r:30} got {d!r}")
    return s


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+", help="folders, .zip or .jsonl files of samples")
    ap.add_argument("--init", default="runs/phrase.pt", help="phrase model to start from")
    ap.add_argument("--out", default="runs/phrase_mine.pt")
    ap.add_argument("--minutes", type=float, default=5)
    ap.add_argument("--lr", type=float, default=5e-4)
    ap.add_argument("--bs", type=int, default=64)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--test", type=float, default=0.15, help="share of samples held back for scoring")
    ap.add_argument("--writer", help="only use samples from this writer ID")
    ap.add_argument("--device", default="auto")
    ap.add_argument("--ship", action="store_true", help="export the new model into the iOS app")
    ap.add_argument("--compare", nargs="*", default=[], help="other models to score on the same held-back samples")
    ap.add_argument("--report", help="write the scores here as JSON")
    a = ap.parse_args()

    items = S.load(a.inputs, phrases=True)
    if a.writer:
        items = [s for s in items if s.get("writer") == a.writer]
    if len(items) < 20:
        sys.exit(f"Only {len(items)} usable samples. Record at least 50 phrases first.")
    # Hold back sessions of phrases and of old one-word recordings separately,
    # so the score covers writing with lifts whenever there is more than one session of it.
    train_items, test_items = [], []
    for kind in (True, False):
        group = [s for s in items if (s.get("version", 1) >= 2) == kind]
        tr, te = split(group, a.test) if a.test > 0 and group else (group, [])
        train_items += tr; test_items += te
    scales = writer_scales(items)
    print(f"{len(items)} samples ({sum(len(s['strokes']) > 1 for s in items)} with finger lifts): "
          f"{len(train_items)} to train on, {len(test_items)} held back")

    dev = pick_device(a.device)
    words, probs = word_list()
    trie = build_trie(*lexicon())
    from train_phrases import fixed_set
    synth_val = fixed_set(150, 4242, words, probs, p_random=0.0)

    model = ConvStrokeNet(features=FEATURES, classes=N_CLASSES)
    model.load_state_dict(torch.load(HERE / a.init, map_location="cpu"))
    model.to(dev)

    def synth_score(m):
        from train_phrases import evaluate
        c, b, e = evaluate(m, synth_val)
        return c, e

    before = report("your held-back phrases, before", model, test_items, scales, trie)
    c0, e0 = synth_score(model)

    # Fine-tune.
    half = a.bs // 2
    loader = iter(DataLoader(Phrases(2, words, probs), batch_size=half, collate_fn=as_list,
                             num_workers=a.workers, persistent_workers=a.workers > 0))
    rng = np.random.default_rng(0)
    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=1e-4)
    ctc = nn.CTCLoss(blank=0, zero_infinity=True)
    model.train()
    t0, step, ema, budget = time.time(), 0, None, a.minutes * 60
    while (frac := (time.time() - t0) / budget) < 1:
        mine = [train_items[i] for i in rng.integers(0, len(train_items), half)]
        batch = [(featurize_strokes(augment(S.strokes_of(s), rng),
                                    lift_scale=scales.get(s.get("writer")) * rng.lognormal(0, 0.15)), s["label"])
                 for s in mine] + next(loader)
        x, lens, tgt, tlens, _ = collate(batch)
        lr = a.lr * min(1, step / 50) * 0.5 * (1 + math.cos(math.pi * frac))
        for g in opt.param_groups: g["lr"] = lr
        lp = model(x.to(dev), lens)
        loss = ctc(lp.transpose(0, 1).cpu(), tgt, model.out_lens(lens), tlens)
        opt.zero_grad(); loss.backward()
        nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        opt.step()
        ema = loss.item() if ema is None else 0.95 * ema + 0.05 * loss.item()
        step += 1
        if step % 100 == 0:
            print(f"step {step} {(time.time() - t0) / 60:.1f}m loss={ema:.3f}", flush=True)
    out = HERE / a.out
    save(model, out)

    print()
    c1, e1 = synth_score(model)
    print(f"synthetic phrases (no dictionary): {e0:.1%} → {e1:.1%} exactly right (should stay high)")
    if before:
        after = report("your held-back phrases, after", model, test_items, scales, trie, show=12)
        print(f"  ({before['exact']:.1%} → {after['exact']:.1%} exactly right)")
    report("phrases it trained on (optimistic)", model, train_items, scales, trie)
    print(f"\nnew weights: {out}")

    if a.report:
        phrases = [s for s in test_items if s.get("version", 1) >= 2]

        def scores(m):
            c, e = synth_score(m)
            r = {"synthetic_exact": e}
            for key, group in (("held_back", test_items), ("held_back_phrases", phrases)):
                if group:
                    truths, _, decoded = read(m, group, scales, trie)
                    r[key] = score(decoded, truths)
            return r

        result = {"samples": len(items), "phrases": sum(s.get("version", 1) >= 2 for s in items),
                  "trained_on": len(train_items), "held_back": len(test_items),
                  "held_back_phrase_count": len(phrases), "minutes": a.minutes,
                  "models": {str(a.out): scores(model)}}
        for path in a.compare:
            if (HERE / path).exists():
                other = ConvStrokeNet(features=FEATURES, classes=N_CLASSES)
                other.load_state_dict(torch.load(HERE / path, map_location="cpu"))
                result["models"][str(path)] = scores(other.to(dev))
        Path(HERE / a.report).write_text(json.dumps(result, indent=1))
        print(f"scores: {a.report}")

    if a.ship:
        run("export.py", "--model", out, "--out", "export/Astrotype")
        run("make_golden.py", "--model", out)
        IOS_MODEL.mkdir(parents=True, exist_ok=True)
        shutil.rmtree(IOS_MODEL / "StrokeModel.mlpackage", ignore_errors=True)
        shutil.copytree(HERE / "export/Astrotype.mlpackage", IOS_MODEL / "StrokeModel.mlpackage")
        shutil.copy(HERE / "export/lexicon.tsv", IOS_MODEL / "lexicon.tsv")
        print(f"copied the model into {IOS_MODEL}")


if __name__ == "__main__":
    main()
