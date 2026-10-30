"""Write export/lexicon.tsv and export/golden.json (Swift parity test cases).

Run after every retrain or change to featurize / model / decoder:
    python3 make_golden.py --model runs/phrase.pt
"""
import argparse, json
import numpy as np, torch
from decode_phrase import beam_search, build_trie
from model import ConvStrokeNet
from phrases import FEATURES, N_CLASSES, PhraseSynth, featurize_strokes
from synth import lexicon, STEP

# (words, lift scale passed to featurize or None to measure it from the phrase)
CASES = [(["hello"], None), (["the", "cat"], None), (["keyboard", "is", "here"], 0.15),
         (["television"], None), (["good", "morning", "friend"], None), (["i", "think", "so"], 0.3)]
DECODER = dict(beam=32, lm_weight=0.5, word_bonus=0.5, break_pen=-4.0, swallow_pen=-1.5,
               char_prune=-8.0, topk=5)


def rounded(strokes):
    """What the JSON holds: x, y to 5 decimals, t to 4."""
    return [np.column_stack([np.round(s[:, :2], 5), np.round(s[:, 2], 4)]) for s in strokes]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="runs/phrase.pt")
    ap.add_argument("--out_dir", default="export")
    a = ap.parse_args()

    words, freqs = lexicon()
    with open(f"{a.out_dir}/lexicon.tsv", "w") as f:
        for w, fr in zip(words, freqs):
            f.write(f"{w}\t{fr:.6e}\n")

    m = ConvStrokeNet(features=FEATURES, classes=N_CLASSES)
    m.load_state_dict(torch.load(a.model, map_location="cpu")); m.eval()
    trie = build_trie(words, freqs)
    s = PhraseSynth(seed=2026); rng = np.random.default_rng(2026)
    cases = []
    for phrase, scale in CASES:
        strokes, text = s.phrase(phrase, rng)
        strokes = rounded(strokes)
        feats = featurize_strokes(strokes, lift_scale=scale)
        with torch.no_grad():
            lp = m(torch.from_numpy(feats)[None])[0].numpy()
        top = [[x, round(float(sc), 3)] for x, sc in beam_search(lp, trie, **DECODER)]
        # Live typing: the same phrase cut off halfway through its strokes.
        cut = strokes[: max(1, len(strokes) // 2)]
        cut_lp = m(torch.from_numpy(featurize_strokes(cut, lift_scale=scale))[None])[0].detach().numpy()
        partial = [[x, round(float(sc), 3)] for x, sc in beam_search(cut_lp, trie, partial=True, **DECODER)]
        cases.append({"text": text, "lift_scale": scale, "strokes": [x.tolist() for x in strokes],
                      "cut_strokes": len(cut),
                      "features": np.round(feats, 5).tolist(),
                      "logprobs": np.round(lp, 4).tolist(),
                      "cut_logprobs": np.round(cut_lp, 4).tolist(),
                      "expected_top": top, "expected_partial": partial})
        print(f"{text!r}: {len(strokes)} strokes, {feats.shape[0]} rows; {top[:2]}; partial {partial[:2]}")
    json.dump({"step": STEP, "decoder": DECODER, "cases": cases}, open(f"{a.out_dir}/golden.json", "w"))


if __name__ == "__main__":
    main()
