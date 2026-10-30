"""Write export/lexicon.tsv and export/golden.json (Swift parity test cases).

Run after every retrain or change to featurize / model / decoder:
    python3 make_golden.py --model runs/final.pt
"""
import argparse, json
import numpy as np, torch
from synth import Synth, featurize, lexicon, STEP
from model import ConvStrokeNet
from decode import build_trie, beam_search

CASES = [("a", "natural"), ("the", "natural"), ("hello", "futural"),
         ("coffee", "scripts"), ("keyboard", "natural"), ("yesterday", "futural")]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="runs/final.pt")
    ap.add_argument("--out_dir", default="export")
    a = ap.parse_args()

    words, freqs = lexicon()
    with open(f"{a.out_dir}/lexicon.tsv", "w") as f:
        for w, fr in zip(words, freqs):
            f.write(f"{w}\t{fr:.6e}\n")

    m = ConvStrokeNet(); m.load_state_dict(torch.load(a.model)); m.eval()
    trie = build_trie(words, freqs)
    s = Synth(seed=2026); rng = np.random.default_rng(2026)
    cases = []
    for w, style in CASES:
        path = s.word(w, rng=rng, style=style)
        feats = featurize(path)
        with torch.no_grad():
            lp = m(torch.from_numpy(feats)[None])[0].numpy()
        top = [[x, round(float(sc), 3)] for x, sc in beam_search(lp, trie) if np.isfinite(sc)]
        cases.append({"word": w, "style": style,
                      "raw_path_box_units_y_up": np.round(path, 5).tolist(),
                      "features": np.round(feats, 5).tolist(),
                      "logprobs": np.round(lp, 4).tolist(),
                      "expected_top_words": top})
        print(w, feats.shape, top[:2])
    json.dump({"step": STEP, "decoder": {"beam": 24, "lm_weight": 0.35, "char_prune": -8.0, "topk": 5},
               "cases": cases}, open(f"{a.out_dir}/golden.json", "w"))


if __name__ == "__main__":
    main()
