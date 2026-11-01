import argparse, time
import numpy as np, torch
from model import ConvStrokeNet
from data import load
from train import collate, greedy, edit
from decode import build_trie, beam_search
from synth import lexicon

torch.set_num_threads(2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--sets", nargs="+", required=True)
    ap.add_argument("--n", type=int, default=1000)
    ap.add_argument("--lm_weight", type=float, default=0.35)
    a = ap.parse_args()

    m = ConvStrokeNet(); m.load_state_dict(torch.load(a.model)); m.eval()
    words, freqs = lexicon()
    trie = build_trie(words, freqs)
    for path in a.sets:
        feats, labels = load(path)
        feats, labels = feats[:a.n], labels[:a.n]
        g_err = chars = g_ok = top1 = top3 = 0
        dec_t, net_t, examples = 0.0, 0.0, []
        for i in range(0, len(feats), 64):
            x, lens, _, _, ls = collate(feats[i:i + 64], labels[i:i + 64])
            t = time.time()
            with torch.no_grad():
                lp = m(x, lens)
            net_t += time.time() - t
            ol = m.out_lens(lens)
            for b, (g, truth) in enumerate(zip(greedy(lp, ol), ls)):
                g_err += edit(g, truth); chars += len(truth); g_ok += g == truth
                t = time.time()
                cands = beam_search(lp[b, :ol[b]].numpy(), trie, lm_weight=a.lm_weight)
                dec_t += time.time() - t
                ws = [w for w, _ in cands]
                top1 += bool(ws) and ws[0] == truth
                top3 += truth in ws[:3]
                if len(examples) < 12:
                    examples.append((truth, g, ws[:3]))
        n = len(feats)
        print(f"\n== {path}  ({n} words)")
        print(f"letters only (no dictionary): char error {g_err/chars:.1%}, whole word right {g_ok/n:.1%}")
        print(f"with dictionary:               top-1 {top1/n:.1%}, in top-3 {top3/n:.1%}")
        print(f"speed: model {1000*net_t/n:.1f} ms/word (batched CPU), decoder {1000*dec_t/n:.1f} ms/word (python)")
        for truth, g, ws in examples:
            print(f"   {truth:12s} letters→ {g:12s} words→ {ws}")


if __name__ == "__main__":
    main()
