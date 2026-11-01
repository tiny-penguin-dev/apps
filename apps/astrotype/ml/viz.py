import numpy as np, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection
from synth import Synth
s = Synth(seed=3)
rng = np.random.default_rng(7)
fig, axes = plt.subplots(3, 4, figsize=(12, 9.5))
for r, style in enumerate(["natural", "futural", "scripts"]):
    # first column: letters spread out so you can read them; rest: real stacked input
    word = ["hello", "coffee", "ranger", "keyboard"][0]
    for c, w in enumerate(["hello", "hello", "coffee", "quiz"]):
        ax = axes[r, c]
        path, letters = s.word(w, rng=rng, style=style, return_letters=True)
        if c == 0:
            for i, L in enumerate(letters):
                ax.plot(L[:, 0] + i * 0.45, L[:, 1], lw=2, color="#333")
            ax.set_title(f"{style}: '{w}' spread out", fontsize=10)
        else:
            seg = np.stack([path[:-1], path[1:]], 1)
            lc = LineCollection(seg, cmap="viridis", lw=2)
            lc.set_array(np.linspace(0, 1, len(seg)))
            ax.add_collection(lc)
            ax.plot(*path[0], "o", color="green"); ax.plot(*path[-1], "s", color="red")
            ax.set_xlim(-0.1, 1.1); ax.set_ylim(-0.1, 1.1)
            ax.add_patch(plt.Rectangle((0, 0), 1, 1, fill=False, ls="--", color="#aaa"))
            ax.set_title(f"'{w}' as one stacked stroke", fontsize=10)
        ax.set_aspect("equal"); ax.set_xticks([]); ax.set_yticks([])
plt.suptitle("Synthetic training data  (color = time: purple → yellow; ● start, ■ end)")
plt.tight_layout(); plt.savefig("out/samples.png", dpi=80)
