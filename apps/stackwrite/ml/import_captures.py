"""Turn recorded samples into the .npz format train.py and evaluate.py read.

    python3 import_captures.py ~/Downloads/StackWrite-samples-*.zip --out data/mine.npz
    python3 import_captures.py samples/ --out data/mine.npz --test 0.15

With --test, a share of the samples (whole sessions, so the test words were
written at a different sitting) goes to a separate test set: data/mine_test.npz.
"""
import argparse
from collections import defaultdict
import numpy as np
from synth import featurize
import samples as S


def to_npz(items, out):
    feats = [featurize(S.path_of(s)).astype(np.float16) for s in items]
    labels = [s["label"] for s in items]
    lens = np.array([len(f) for f in feats])
    np.savez(out, X=np.concatenate(feats) if feats else np.zeros((0, 5), np.float16),
             lens=lens, labels=np.array(labels))
    print(f"{out}: {len(items)} samples" + (f", mean len {lens.mean():.0f}" if len(lens) else ""))


def split(items, test, seed=0):
    """Holds out whole sessions until about `test` of the samples are set aside."""
    by_session = defaultdict(list)
    for s in items:
        by_session[s.get("session", s.get("id"))].append(s)
    keys = sorted(by_session)
    rng = np.random.default_rng(seed)
    rng.shuffle(keys)
    held, train = [], []
    for k in keys:
        (held if len(held) < test * len(items) and len(by_session) > 1 else train).extend(by_session[k])
    return train, held


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("inputs", nargs="+", help="folders, .zip or .jsonl files of samples")
    ap.add_argument("--out", required=True)
    ap.add_argument("--test", type=float, default=0, help="share held out as a test set, e.g. 0.15")
    ap.add_argument("--writer", help="only samples from this writer ID")
    a = ap.parse_args()

    items = S.load(a.inputs)
    if a.writer:
        items = [s for s in items if s.get("writer") == a.writer]
    writers = {s.get("writer") for s in items}
    print(f"{len(items)} samples from {len(writers)} writer(s)")
    if a.test > 0:
        train, held = split(items, a.test)
        to_npz(train, a.out)
        to_npz(held, a.out.replace(".npz", "_test.npz"))
    else:
        to_npz(items, a.out)


if __name__ == "__main__":
    main()
