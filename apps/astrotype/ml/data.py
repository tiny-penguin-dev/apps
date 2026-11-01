"""Pre-generate synthetic datasets to .npz (fast to load, no CPU contention while training)."""
import argparse, multiprocessing as mp
import numpy as np
from synth import Synth, featurize, lexicon, random_word
from letters import ALPHABET

CHAR2ID = {c: i + 1 for i, c in enumerate(ALPHABET)}  # 0 = CTC blank


def _work(args):
    n, seed, styles, words, probs, p_random = args
    rng = np.random.default_rng(seed)
    s = Synth(styles, seed=seed)
    feats, labels = [], []
    for _ in range(n):
        w = random_word(rng) if rng.random() < p_random else words[rng.choice(len(words), p=probs)]
        f = featurize(s.word(w, rng=rng))
        feats.append(f.astype(np.float16))
        labels.append(w)
    return feats, labels


def build(n, seed, styles, out, p_random=0.25, procs=2):
    words, freqs = lexicon()
    probs = freqs ** 0.3
    probs = probs / probs.sum()
    chunk = n // procs
    jobs = [(chunk, seed * 1000 + i, styles, words, probs, p_random) for i in range(procs)]
    with mp.Pool(procs) as pool:
        res = pool.map(_work, jobs)
    feats = [f for r in res for f in r[0]]
    labels = [l for r in res for l in r[1]]
    lens = np.array([len(f) for f in feats])
    np.savez(out, X=np.concatenate(feats), lens=lens, labels=np.array(labels))
    print(f"{out}: {len(feats)} samples, mean len {lens.mean():.0f}, max {lens.max()}")


def load(path):
    d = np.load(path)
    X, lens, labels = d["X"], d["lens"], d["labels"]
    offs = np.concatenate([[0], np.cumsum(lens)])
    return [X[offs[i]:offs[i + 1]] for i in range(len(lens))], [str(l) for l in labels]


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=100000)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--styles", default="natural,futural,scripts")
    ap.add_argument("--p_random", type=float, default=0.25)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    build(a.n, a.seed, a.styles.split(","), a.out, a.p_random)
