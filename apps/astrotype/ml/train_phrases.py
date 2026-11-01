"""Train the phrase model: multi-stroke writing, spaces predicted by the model.

Phrases are synthesized on the fly by worker processes, so every step sees
new writing. Starts from the single-word model (--init) by widening its
input layer to the new features and adding the space class.

    python train_phrases.py --init runs/final.pt --out runs/phrase.pt --minutes 60
"""
import argparse, math, time
import numpy as np, torch, torch.nn as nn
from torch.utils.data import DataLoader, IterableDataset, get_worker_info
from model import ConvStrokeNet
from phrases import (CLASSES, FEATURES, N_CLASSES, PhraseSynth, featurize_strokes,
                     labels_to_ids, random_phrase)
from synth import lexicon
from train import edit, pick_device, save


def word_list():
    words, freqs = lexicon()
    probs = freqs ** 0.3
    return words, probs / probs.sum()


def make_sample(synth, rng, words, probs, p_random=0.15):
    w = synth.writer(rng)
    strokes, text = synth.phrase(random_phrase(rng, words, probs, p_random=p_random), rng, w)
    # In the app the usual lift comes from the writer's recent history; here
    # half the time it's a noisy version of the true one, half from the phrase.
    scale = w["lift"] * rng.lognormal(0, 0.25) if rng.random() < 0.5 else None
    return featurize_strokes(strokes, lift_scale=scale), text


class Phrases(IterableDataset):
    def __init__(self, seed, words, probs):
        self.seed, self.words, self.probs = seed, words, probs

    def __iter__(self):
        info = get_worker_info()
        rng = np.random.default_rng([self.seed, info.id if info else 0, int(time.time())])
        synth = PhraseSynth()
        while True:
            yield make_sample(synth, rng, self.words, self.probs)


def collate(items):
    fs, ls = zip(*items)
    lens = torch.tensor([len(f) for f in fs])
    x = torch.zeros(len(fs), lens.max(), FEATURES)
    for i, f in enumerate(fs):
        x[i, :len(f)] = torch.from_numpy(f)
    tgt = torch.tensor([i for l in ls for i in labels_to_ids(l)])
    tlens = torch.tensor([len(l) for l in ls])
    return x, lens, tgt, tlens, list(ls)


def fixed_set(n, seed, words, probs, p_random=0.15):
    rng, synth = np.random.default_rng(seed), PhraseSynth()
    return [make_sample(synth, rng, words, probs, p_random) for _ in range(n)]


def greedy(lp, ol):
    best = lp.argmax(-1)
    out = []
    for b in range(len(best)):
        seq, prev = [], 0
        for k in best[b, :ol[b]].tolist():
            if k != prev and k != 0:
                seq.append(CLASSES[k - 1])
            prev = k
        out.append(" ".join("".join(seq).split()))
    return out


@torch.no_grad()
def evaluate(model, items):
    """Greedy (no dictionary): character error rate, word breaks right, exact."""
    model.eval()
    dev = next(model.parameters()).device
    errs = chars = exact = breaks = 0
    for i in range(0, len(items), 128):
        x, lens, _, _, ls = collate(items[i:i + 128])
        lp = model(x.to(dev), lens).cpu()
        for p, t in zip(greedy(lp, model.out_lens(lens)), ls):
            errs += edit(p, t); chars += len(t); exact += p == t
            breaks += p.count(" ") == t.count(" ")
    model.train()
    n = len(items)
    return errs / chars, breaks / n, exact / n


def warm_start(model, path):
    """Load a single-word model: copy its weights, widen the first conv with
    zeros for the new features, and start the space class like the blank."""
    old = torch.load(path, map_location="cpu")
    new = model.state_dict()
    for k, v in old.items():
        if new[k].shape == v.shape:
            new[k] = v
        elif k == "stem.0.weight":
            new[k].zero_(); new[k][:, :v.shape[1]] = v
        elif k.startswith("out."):
            new[k][:v.shape[0]] = v
            new[k][v.shape[0]:] = v[:1] if k.endswith("weight") else v[:1] - 2.0
    model.load_state_dict(new)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--minutes", type=float, default=60)
    ap.add_argument("--lr", type=float, default=1.5e-3)
    ap.add_argument("--bs", type=int, default=64)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--init", help="single-word model to start from (runs/final.pt)")
    ap.add_argument("--resume", help="phrase model to continue training")
    ap.add_argument("--out", required=True)
    ap.add_argument("--device", default="auto", help="auto, cpu, mps or cuda")
    a = ap.parse_args()
    dev = pick_device(a.device)
    print(f"device: {dev}", flush=True)

    words, probs = word_list()
    val = fixed_set(1000, 12345, words, probs)
    model = ConvStrokeNet(features=FEATURES, classes=N_CLASSES)
    if a.resume:
        model.load_state_dict(torch.load(a.resume, map_location="cpu"))
    elif a.init:
        warm_start(model, a.init)
    model.to(dev)
    print(f"params: {sum(p.numel() for p in model.parameters()):,}", flush=True)

    loader = DataLoader(Phrases(1, words, probs), batch_size=a.bs, collate_fn=collate,
                        num_workers=a.workers, persistent_workers=a.workers > 0)
    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=1e-4)
    ctc = nn.CTCLoss(blank=0, zero_infinity=True)
    t0, step, ema, budget = time.time(), 0, None, a.minutes * 60
    for x, lens, tgt, tlens, _ in loader:
        frac = (time.time() - t0) / budget
        if frac >= 1:
            break
        lr = a.lr * min(1, step / 300) * 0.5 * (1 + math.cos(math.pi * frac))
        for g in opt.param_groups: g["lr"] = lr
        lp = model(x.to(dev), lens)
        # CTC loss runs on the CPU: MPS doesn't implement it.
        loss = ctc(lp.transpose(0, 1).cpu(), tgt, model.out_lens(lens), tlens)
        opt.zero_grad(); loss.backward()
        nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        opt.step()
        ema = loss.item() if ema is None else 0.98 * ema + 0.02 * loss.item()
        step += 1
        if step % 250 == 0:
            c, b, e = evaluate(model, val)
            print(f"step {step} {(time.time()-t0)/60:.1f}m lr={lr:.2e} loss={ema:.3f} | "
                  f"cer={c:.3f} breaks={b:.3f} exact={e:.3f}", flush=True)
            save(model, a.out)
    save(model, a.out)
    c, b, e = evaluate(model, val)
    print(f"FINAL cer={c:.4f} breaks={b:.4f} exact={e:.4f}", flush=True)


if __name__ == "__main__":
    main()
