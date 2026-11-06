"""Train the next-word model on `make_text.py`'s sentences.

    python3 train.py data/en --out runs/en --minutes 120
    python3 train.py data/en --out runs/en-small --dim 128 --layers 2 --minutes 20   # a quick check

Builds the vocabulary from the training text (the `--vocab` commonest words, all from
the lexicon since `make_text.py` writes anything else as `<unk>`), then trains on
sentences right-aligned in a window of `--context` tokens, starting with `<s>`.
Uses Apple's GPU (MPS) on a Mac, CUDA if there is one, else the CPU. Every few
minutes it scores the held-back sentences (`evaluate.py`'s rules) and keeps the best
checkpoint as `<out>/model.pt`, with `<out>/vocab.txt` beside it.
"""
import argparse, collections, os, random, time

import torch
import torch.nn.functional as F

from model import BOS, PAD, NextWordModel, Vocabulary
from evaluate import evaluate, read_sentences


def device():
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


def windows(sentences, vocab, context):
    """Each sentence as `<s> w1 … wn`, cut to context+1 tokens, right-aligned with PAD."""
    out = torch.full((len(sentences), context + 1), PAD, dtype=torch.long)
    for i, s in enumerate(sentences):
        ids = [BOS] + vocab.encode(s)
        ids = ids[: context + 1]
        out[i, context + 1 - len(ids):] = torch.tensor(ids)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("data", help="folder with train.txt and test.txt")
    ap.add_argument("--out", required=True)
    ap.add_argument("--vocab", type=int, default=16000)
    ap.add_argument("--dim", type=int, default=256)
    ap.add_argument("--layers", type=int, default=4)
    ap.add_argument("--heads", type=int, default=4)
    ap.add_argument("--context", type=int, default=32)
    ap.add_argument("--batch", type=int, default=256)
    ap.add_argument("--lr", type=float, default=2e-3)
    ap.add_argument("--minutes", type=float, default=60)
    ap.add_argument("--eval-every", type=float, default=10, help="minutes between test scores")
    ap.add_argument("--eval-sentences", type=int, default=5000)
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args()
    random.seed(a.seed)
    torch.manual_seed(a.seed)
    os.makedirs(a.out, exist_ok=True)
    dev = device()

    train = read_sentences(os.path.join(a.data, "train.txt"))
    test = read_sentences(os.path.join(a.data, "test.txt"))[: a.eval_sentences]
    counts = collections.Counter(w for s in train for w in s)
    vocab = Vocabulary([w for w, _ in counts.most_common(a.vocab + 4)][: a.vocab + 4])
    vocab.save(os.path.join(a.out, "vocab.txt"))
    data = windows(train, vocab, a.context)
    print(f"{len(train)} sentences, vocab {len(vocab)}, device {dev}", flush=True)

    # A multiple of 64 rows, so Core ML can compress the word table in groups of 16
    # (`export.py`); the spare rows are never a word and never offered.
    rows = -(-len(vocab) // 64) * 64
    model = NextWordModel(rows, dim=a.dim, layers=a.layers, heads=a.heads, ff=4 * a.dim, context=a.context).to(dev)
    print(f"{sum(p.numel() for p in model.parameters()) / 1e6:.1f}M weights", flush=True)
    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=0.01)
    end = time.time() + a.minutes * 60
    total = a.minutes * 60
    next_eval = time.time() + a.eval_every * 60
    best = -1.0
    step = 0
    while True:
        perm = torch.randperm(len(data))
        for i in range(0, len(data) - a.batch + 1, a.batch):
            now = time.time()
            # Warm up for 300 steps, then fall off linearly with the time left.
            lr = a.lr * min(1, (step + 1) / 300) * max(0.05, (end - now) / total)
            for g in opt.param_groups:
                g["lr"] = lr
            batch = data[perm[i : i + a.batch]].to(dev)
            inp, target = batch[:, :-1], batch[:, 1:]
            logits = model(inp)
            ignore = (inp == PAD) | (target == PAD)
            target = target.masked_fill(ignore, -100)
            loss = F.cross_entropy(logits.reshape(-1, logits.size(-1)), target.reshape(-1), ignore_index=-100)
            opt.zero_grad(set_to_none=True)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
            step += 1
            if step % 200 == 0:
                print(f"step {step} loss {loss.item():.3f} lr {lr:.2e} {(end - now) / 60:.0f} min left", flush=True)
            if now >= next_eval or now >= end:
                score = evaluate(model, vocab, test, dev)
                print(f"step {step}: {score.summary()}", flush=True)
                if score.top3 > best:
                    best = score.top3
                    torch.save({"config": model.config, "state": model.state_dict(), "step": step,
                                "score": score.__dict__}, os.path.join(a.out, "model.pt"))
                model.train()
                next_eval = now + a.eval_every * 60
            if now >= end:
                print(f"done, best top-3 {best * 100:.1f}%", flush=True)
                return


if __name__ == "__main__":
    main()
