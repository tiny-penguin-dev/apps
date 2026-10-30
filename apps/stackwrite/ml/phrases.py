"""Synthetic multi-word writing with finger lifts, and the features for it.

Writing model: letters still stack in one spot, but the finger may lift
between letters (and between strokes of a letter). Words follow each other
in the same spot with no explicit gap; what separates them is evidence the
model has to weigh: a longer lift, a tap, or nothing at all (then only the
dictionary can split them). Thinking pauses inside words make sure a pause
alone never decides.

A recording is a list of strokes, each an (N, 3) array of x, y, t: box units
(y up) and seconds since the first touch. See ../SAMPLES.md (version 2).
"""
import numpy as np
from letters import ALPHABET
from synth import Synth, affine, connector, densify, random_word, wobble, STEP

SPACE = " "
CLASSES = ALPHABET + SPACE           # model classes 1..27; 0 is the CTC blank
CHAR2ID = {c: i + 1 for i, c in enumerate(CLASSES)}
N_CLASSES = len(CLASSES) + 1
FEATURES = 9


# ---------------------------------------------------------------- features
def featurize_strokes(strokes, step=STEP, lift_scale=None):
    """List of (N, 3) strokes → (T, 9) float32.

    Per point: x-0.5, y-0.5, cos(dir), sin(dir), turn/pi (as in synth.featurize,
    within a stroke), then stroke-start flag, lift before this stroke
    (log1p(seconds / 0.25)), the same lift relative to this writer's usual lift
    (log1p(lift / lift_scale)), and log of the stroke's length. The last three
    are only nonzero on a stroke's first point, except stroke length, which is
    on every point so taps stand out.
    """
    lifts = [s[0, 2] - p[-1, 2] for p, s in zip(strokes, strokes[1:])]
    if lift_scale is None:
        lift_scale = writer_lift_scale(lifts)
    rows, prev_end = [], None
    for k, s in enumerate(strokes):
        s = np.asarray(s, float)
        xy = s[:, :2]
        d = np.linalg.norm(np.diff(xy, axis=0), axis=1)
        length = float(d.sum())
        cum = np.concatenate([[0], np.cumsum(d)])
        if length < step:
            p = xy[[0, -1]] if length > 1e-4 else xy[:1]
        else:
            t = np.arange(0, length, step)
            p = np.stack([np.interp(t, cum, xy[:, 0]), np.interp(t, cum, xy[:, 1])], 1)
        if len(p) > 1:
            dd = np.diff(p, axis=0)
            ang = np.arctan2(dd[:, 1], dd[:, 0])
            ang = np.concatenate([ang, ang[-1:]])
        else:
            ang = np.zeros(1)
        turn = np.diff(ang, prepend=ang[0])
        turn = (turn + np.pi) % (2 * np.pi) - np.pi
        moving = len(p) > 1
        f = np.zeros((len(p), FEATURES), np.float32)
        f[:, 0] = p[:, 0] - 0.5
        f[:, 1] = p[:, 1] - 0.5
        f[:, 2] = np.cos(ang) * moving
        f[:, 3] = np.sin(ang) * moving
        f[:, 4] = turn / np.pi
        f[0, 5] = 1.0
        if k > 0:
            lift = max(0.0, s[0, 2] - prev_end)
            f[0, 6] = np.log1p(lift / 0.25)
            f[0, 7] = np.log1p(lift / lift_scale)
        f[:, 8] = np.log(length + 0.01)
        rows.append(f)
        prev_end = s[-1, 2]
    return np.vstack(rows) if rows else np.zeros((0, FEATURES), np.float32)


def writer_lift_scale(lifts, default=0.2):
    """This writer's usual lift between letters: the median of the shorter
    half of lifts (word breaks and pauses are the long ones)."""
    lifts = np.sort([l for l in lifts if l > 0])
    if len(lifts) < 4:
        return default
    return float(np.clip(np.median(lifts[: max(2, len(lifts) // 2)]), 0.05, 1.0))


def labels_to_ids(text):
    return [CHAR2ID[c] for c in text]


# ---------------------------------------------------------------- synthesis
class PhraseSynth(Synth):
    """Writes phrases as timed, multi-stroke, stacked letters."""

    def writer(self, rng):
        """One synthetic writer's habits."""
        return dict(
            speed=rng.uniform(1.2, 4.0),                # box units per second
            lift=rng.lognormal(np.log(0.15), 0.4),      # usual lift between letters
            # lifts between letters (else joins); some people join everything
            p_lift_letter=0.0 if rng.random() < 0.15 else rng.uniform(0.3, 1.0),
            p_lift_inner=rng.uniform(0.6, 1.0),         # lifts inside a letter (t bar, i dot)
            p_tap=rng.uniform(0.0, 0.8),                # taps to end a word
            p_pause=rng.uniform(0.3, 0.95),             # longer lift between words
            p_think=rng.uniform(0.0, 0.08),             # thinking pause inside a word
            style=rng.choice(self.names),
        )

    def _letter_strokes(self, ch, style, rng, w):
        """One letter as a list of point arrays, with joins where the finger stays down."""
        strokes = [s.copy() for s in self.styles[style][ch]]
        cx = (min(s[:, 0].min() for s in strokes) + max(s[:, 0].max() for s in strokes)) / 2
        A = affine(rng)
        out = []
        for i, s in enumerate(strokes):
            s = densify(s - [cx, 0]) @ A.T
            if i > 0 and rng.random() > w["p_lift_inner"]:
                out[-1] = np.vstack([out[-1], connector(out[-1][-1], s[0], rng)[1:], s[1:]])
            else:
                out.append(s)
        return out

    def phrase(self, words, rng, w=None):
        """Returns (strokes, text). Each stroke is (N, 3): x, y, t."""
        w = w or self.writer(rng)
        style = w["style"]
        W = affine(rng, scale=(0.9, 1.1), shear=0.35, rot=0.15)
        xh = rng.uniform(0.25, 0.5)
        base = np.array([0.5, rng.uniform(0.25, 0.4)])
        drift_sd = rng.uniform(0.0, 0.12)

        # Build strokes in letter units, with a "gap kind" before each stroke.
        strokes, gaps = [], []          # gaps[i]: seconds of lift before stroke i
        lift = lambda: w["lift"] * rng.lognormal(0, 0.35)
        for wi, word in enumerate(words):
            offset = rng.normal(0, 0.15, 2)
            for li, ch in enumerate(word):
                offset = (offset + rng.normal(0, drift_sd, 2)) * 0.7
                parts = [(s + offset) @ W.T for s in self._letter_strokes(ch, style, rng, w)]
                for pi, s in enumerate(parts):
                    first_of_letter = pi == 0
                    joined = (first_of_letter and li > 0 and strokes
                              and rng.random() > w["p_lift_letter"])
                    if joined:
                        prev = strokes[-1]
                        strokes[-1] = np.vstack([prev, connector(prev[-1], s[0], rng)[1:], s[1:]])
                        continue
                    if not strokes:
                        gaps.append(0.0)
                    elif first_of_letter and li == 0:
                        gaps.append(None)       # word break, decided below
                    elif first_of_letter and rng.random() < w["p_think"]:
                        gaps.append(lift() * rng.uniform(3, 10))   # thinking pause mid-word
                    else:
                        gaps.append(lift())
                    strokes.append(s)

        # Scale into the box, keep it inside, add wobble.
        allpts = np.vstack(strokes)
        sizes = [len(s) for s in strokes]
        allpts = allpts * xh + base
        lo, hi = allpts.min(0), allpts.max(0)
        span = (hi - lo).max()
        if span > 1.05:
            k = rng.uniform(0.85, 1.0) / span
            allpts = (allpts - (lo + hi) / 2) * k + 0.5
        allpts = wobble(allpts, rng, amp=rng.uniform(0, 0.02)) + rng.normal(0, 0.002, allpts.shape)
        strokes = np.split(allpts, np.cumsum(sizes)[:-1])

        # Word breaks: a longer lift, a tap, both, or nothing.
        out_strokes, out_gaps = [], []
        for s, g in zip(strokes, gaps):
            if g is None:
                pause = rng.random() < w["p_pause"]
                g = lift() * (rng.uniform(2.5, 8) if pause else 1.0)
                if rng.random() < w["p_tap"]:
                    tap = rng.uniform(0.15, 0.85, 2) + rng.normal(0, 0.003, (rng.integers(1, 4), 2))
                    out_strokes.append(tap)
                    out_gaps.append(lift() * rng.uniform(0.5, 1.5))
                    g = lift()
            out_strokes.append(s)
            out_gaps.append(g)

        # Timestamps: constant-ish speed while drawing, gaps while lifted.
        timed, t = [], 0.0
        for s, g in zip(out_strokes, out_gaps):
            t += g
            d = np.linalg.norm(np.diff(s, axis=0), axis=1) if len(s) > 1 else np.zeros(0)
            ts = t + np.concatenate([[0], np.cumsum(d)]) / (w["speed"] * rng.uniform(0.8, 1.2))
            if len(s) <= 3:                       # taps last a moment
                ts = t + np.linspace(0, rng.uniform(0.03, 0.1), len(s))
            timed.append(np.column_stack([s, ts]))
            t = ts[-1]
        return timed, " ".join(words)


def random_phrase(rng, words, probs, n=(1, 4), p_random=0.15):
    """1-4 dictionary words; some are random letters so the model reads
    letters, not just words it has memorized."""
    k = rng.integers(n[0], n[1] + 1)
    out = [words[i] for i in rng.choice(len(words), k, p=probs)]
    return [random_word(rng) if rng.random() < p_random else w for w in out]
