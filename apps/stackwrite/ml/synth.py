"""Synthetic data: whole words written as ONE finger stroke, every letter stacked
in the same spot.

Coordinates are in "box units": the writing area is a 1x1 square, (0,0) bottom-left.
The keyboard knows its own box size, so on device we divide touch points by the box
height and get the same units.
"""
import numpy as np
from letters import ALPHABET, load_styles

STEP = 0.04          # resample spacing in box units (keep in sync with the app)
FEATURES = 5         # x, y, cos(dir), sin(dir), turn


# ---------------------------------------------------------------- geometry utils
def resample(path, step=STEP):
    d = np.linalg.norm(np.diff(path, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(d)])
    if s[-1] < step:
        return path[[0, -1]]
    t = np.arange(0, s[-1], step)
    return np.stack([np.interp(t, s, path[:, 0]), np.interp(t, s, path[:, 1])], 1)


def densify(path, max_seg=0.05):
    out = [path[0]]
    for a, b in zip(path[:-1], path[1:]):
        n = max(1, int(np.ceil(np.linalg.norm(b - a) / max_seg)))
        out.append(a + (b - a) * np.linspace(0, 1, n + 1)[1:, None])
    return np.vstack([out[0][None]] + out[1:])


def affine(rng, scale=(0.85, 1.15), shear=0.12, rot=0.08):
    sx = rng.uniform(*scale)
    sy = sx * rng.uniform(0.9, 1.1)
    sh = rng.uniform(-shear, shear)
    a = rng.uniform(-rot, rot)
    R = np.array([[np.cos(a), -np.sin(a)], [np.sin(a), np.cos(a)]])
    return R @ np.array([[sx, sh], [0, sy]])


def wobble(path, rng, amp):
    """Smooth low-frequency distortion along the path (hand wobble)."""
    d = np.linalg.norm(np.diff(path, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(d)])
    out = path.copy()
    for k in range(2):
        f = rng.uniform(0.3, 1.5, 3)
        ph = rng.uniform(0, 2 * np.pi, 3)
        out[:, k] += amp * sum(np.sin(2 * np.pi * fi * s + p) for fi, p in zip(f, ph)) / 3
    return out


def connector(a, b, rng):
    """The in-air move between letters/strokes, drawn because the finger never lifts."""
    mid = (a + b) / 2
    perp = np.array([-(b - a)[1], (b - a)[0]])
    mid = mid + perp * rng.uniform(-0.25, 0.25)
    return np.vstack([a, mid, b])


# ---------------------------------------------------------------- word synthesis
class Synth:
    def __init__(self, style_names=None, seed=0):
        all_styles = load_styles()
        names = style_names or list(all_styles)
        self.styles = {n: all_styles[n] for n in names}
        self.names = names
        self.rng = np.random.default_rng(seed)

    def letter(self, ch, style, rng):
        strokes = [s.copy() for s in self.styles[style][ch]]
        # center horizontally so letters stack on top of each other
        cx = (min(s[:, 0].min() for s in strokes) + max(s[:, 0].max() for s in strokes)) / 2
        A = affine(rng)
        pts = []
        for i, s in enumerate(strokes):
            s = densify(s - [cx, 0])
            s = s @ A.T
            if i > 0:
                pts.append(connector(pts[-1][-1], s[0], rng))
            pts.append(s)
        path = np.vstack(pts)
        # sloppy start/end: trim a little, or add a tiny hook
        n = len(path)
        lo = rng.integers(0, max(1, n // 12)) if rng.random() < 0.3 else 0
        hi = n - (rng.integers(0, max(1, n // 12)) if rng.random() < 0.3 else 0)
        return path[lo:max(hi, lo + 2)]

    def word(self, word, rng=None, style=None, return_letters=False):
        rng = rng or self.rng
        style = style or rng.choice(self.names)
        mix = rng.random() < 0.15  # occasionally mix styles letter by letter
        W = affine(rng, scale=(0.9, 1.1), shear=0.35, rot=0.15)
        xh = rng.uniform(0.28, 0.5)            # x-height in box units
        base = np.array([0.5, rng.uniform(0.25, 0.4)])
        drift_sd = rng.uniform(0.0, 0.12)        # how much the "spot" wanders, in x-heights
        offset = np.zeros(2)
        parts, letters = [], []
        for i, ch in enumerate(word):
            st = rng.choice(self.names) if mix else style
            L = self.letter(ch, st, rng)
            offset = offset + rng.normal(0, drift_sd, 2)
            offset = offset * 0.7  # people drift back toward the center
            L = (L + offset) @ W.T
            if parts:
                parts.append(connector(parts[-1][-1], L[0], rng))
            parts.append(L)
            letters.append(L)
        path = np.vstack(parts) * xh + base
        # people keep the word inside the box: shrink if it spills out too far
        lo, hi = path.min(0), path.max(0)
        span = (hi - lo).max()
        if span > 1.05:
            k = rng.uniform(0.85, 1.0) / span
            c = (lo + hi) / 2
            path = (path - c) * k + 0.5
        path = wobble(path, rng, amp=rng.uniform(0, 0.02))
        path = path + rng.normal(0, 0.002, path.shape)
        if return_letters:
            return path, [l * xh + base for l in letters]
        return path


# ---------------------------------------------------------------- features
def featurize(path, step=STEP):
    """Raw touch path (box units) -> (T, 5) float32 model input."""
    p = resample(np.asarray(path, float), step)
    if len(p) < 3:
        p = np.vstack([p, p[-1:] + 1e-3, p[-1:] + 2e-3])
    d = np.diff(p, axis=0)
    ang = np.arctan2(d[:, 1], d[:, 0])
    ang = np.concatenate([ang, ang[-1:]])
    turn = np.diff(ang, prepend=ang[0])
    turn = (turn + np.pi) % (2 * np.pi) - np.pi
    f = np.stack([p[:, 0] - 0.5, p[:, 1] - 0.5, np.cos(ang), np.sin(ang), turn / np.pi], 1)
    return f.astype(np.float32)


# ---------------------------------------------------------------- word lists
def lexicon(n=40000):
    from wordfreq import top_n_list, word_frequency
    words = [w for w in top_n_list("en", n * 2) if w.isascii() and w.isalpha() and w.islower()
             and len(w) <= 14]
    words = list(dict.fromkeys(words))[:n]
    freqs = np.array([word_frequency(w, "en") for w in words])
    return words, freqs


def random_word(rng):
    n = rng.integers(1, 9)
    return "".join(rng.choice(list(ALPHABET), n))
