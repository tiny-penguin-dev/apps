"""Letter shapes for the stacked, one-stroke writing style.

Every letter is a list of strokes; each stroke is a list of (x, y) points.
Coordinates: baseline y=0, x-height y=1, ascender y~2, descender y~-1, width ~0..1.

Three sources ("styles"):
  - "natural": hand-authored one-stroke paths, drawn the way people tend to
    write each letter with a finger without lifting (circles counter-clockwise,
    stems top to bottom, dots/crossbars last).
  - "futural": Hershey single-line print font.
  - "scripts": Hershey single-line script (cursive) font.
"""
import numpy as np

C = None  # corner marker: the point before it is a sharp corner

# Control points per letter. `C` after a point means "sharp corner here".
NATURAL = {
    "a": [(.9, .85), (.5, 1), (.1, .6), (.2, .1), (.6, .05), (.9, .5), (.9, 1), C, (.9, .2), (1, 0)],
    "b": [(.1, 2), (.1, 0), C, (.1, .5), (.5, 1), (.9, .5), (.5, 0), (.1, .15)],
    "c": [(.9, .85), (.5, 1), (.1, .5), (.5, 0), (.9, .15)],
    "d": [(.9, .85), (.5, 1), (.1, .5), (.5, 0), (.9, .3), (.9, 2), C, (.9, 0)],
    "e": [(.1, .5), (.9, .55), (.7, .95), (.4, 1), (.1, .5), (.4, 0), (.9, .15)],
    "f": [(.9, 1.9), (.6, 2), (.4, 1.7), (.4, 0), C, (.1, 1), C, (.8, 1)],
    "g": [(.9, .85), (.5, 1), (.1, .6), (.5, .2), (.9, .6), (.9, 1), C, (.9, -.6), (.5, -1), (.1, -.7)],
    "h": [(.1, 2), (.1, 0), C, (.1, .6), (.5, 1), (.9, .6), (.9, 0)],
    "i": [(.5, 1), (.5, 0), C, (.5, 1.5), C, (.5, 1.65)],
    "j": [(.6, 1), (.6, -.6), (.4, -1), (.1, -.8), C, (.6, 1.5), C, (.6, 1.65)],
    "k": [(.1, 2), (.1, 0), C, (.1, .45), C, (.9, 1), C, (.25, .45), C, (.9, 0)],
    "l": [(.5, 2), (.5, .1), (.7, 0)],
    "m": [(.1, 1), (.1, 0), C, (.1, .7), (.3, 1), (.5, .7), (.5, 0), C, (.5, .7), (.7, 1), (.9, .7), (.9, 0)],
    "n": [(.1, 1), (.1, 0), C, (.1, .7), (.5, 1), (.9, .7), (.9, 0)],
    "o": [(.6, 1), (.2, .8), (.1, .4), (.5, 0), (.9, .4), (.8, .85), (.5, 1)],
    "p": [(.1, 1), (.1, -1), C, (.1, .6), (.5, 1), (.9, .5), (.5, 0), (.1, .2)],
    "q": [(.9, .85), (.5, 1), (.1, .5), (.5, 0), (.9, .4), (.9, 1), C, (.9, -1), (1, -.8)],
    "r": [(.1, 1), (.1, 0), C, (.1, .6), (.4, .95), (.8, 1)],
    "s": [(.85, .9), (.5, 1), (.15, .8), (.3, .55), (.7, .45), (.85, .2), (.5, 0), (.1, .1)],
    "t": [(.5, 1.7), (.5, .1), (.7, 0), C, (.1, 1), C, (.9, 1)],
    "u": [(.1, 1), (.1, .3), (.5, 0), (.9, .3), (.9, 1), C, (.9, 0)],
    "v": [(.1, 1), (.5, 0), C, (.9, 1)],
    "w": [(0, 1), (.25, 0), C, (.5, .8), C, (.75, 0), C, (1, 1)],
    "x": [(.1, 1), (.9, 0), C, (.9, 1), C, (.1, 0)],
    "y": [(.1, 1), (.5, 0), C, (.9, 1), C, (.3, -1)],
    "z": [(.1, 1), (.9, 1), C, (.1, 0), C, (.9, 0)],
}

ALPHABET = "abcdefghijklmnopqrstuvwxyz"


def _catmull_rom(pts, n_per_seg=8):
    pts = np.asarray(pts, float)
    if len(pts) < 3:
        t = np.linspace(0, 1, n_per_seg + 1)[:, None]
        return pts[0] + t * (pts[-1] - pts[0])
    p = np.vstack([pts[0], pts, pts[-1]])
    out = []
    t = np.linspace(0, 1, n_per_seg, endpoint=False)[:, None]
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t**2
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * t**3))
    out.append(p[-2][None])
    return np.vstack(out)


def _natural_letter(spec):
    """Split control points at corners, smooth each piece, join into one path."""
    pieces, cur = [], []
    for item in spec:
        if item is C:
            pieces.append(cur)
            cur = [cur[-1]]
        else:
            cur.append(item)
    pieces.append(cur)
    path = [_catmull_rom(pc) for pc in pieces if len(pc) >= 2]
    return [np.vstack(path)]


def _hershey(font_name):
    from HersheyFonts import HersheyFonts
    f = HersheyFonts()
    f.load_default_font(font_name)

    def strokes(ch):
        out = []
        for a, b in f.lines_for_text(ch):
            if out and out[-1][-1] == a:
                out[-1].append(b)
            else:
                out.append([a, b])
        return [np.asarray(s, float) for s in out]

    raw = {ch: strokes(ch) for ch in ALPHABET}
    # Figure out orientation (b has an ascender, p has a descender).
    top = lambda ch: max(s[:, 1].max() for s in raw[ch])
    y_up = top("b") > top("p")
    sign = 1.0 if y_up else -1.0
    xs = np.vstack(raw["x"]) * [1, sign]
    base, xh = xs[:, 1].min(), xs[:, 1].max() - xs[:, 1].min()
    letters = {}
    for ch, ss in raw.items():
        ss = [(s * [1, sign] - [0, base]) / xh for s in ss]
        minx = min(s[:, 0].min() for s in ss)
        letters[ch] = [s - [minx, 0] for s in ss]
    return letters


def load_styles():
    styles = {"natural": {ch: _natural_letter(NATURAL[ch]) for ch in ALPHABET}}
    for name in ("futural", "scripts"):
        styles[name] = _hershey(name)
    return styles
