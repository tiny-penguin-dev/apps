"""Train the next-word model on `make_text.py`'s sentences.

    python3 train.py data/en --out runs/en --minutes 120
    python3 train.py data/en --out runs/en-small --dim 128 --layers 2 --minutes 20   # a quick check

Builds the vocabulary from the training text (the `--vocab` commonest words, all from
the lexicon since `make_text.py` writes anything else as `<unk>`), then trains on
sentences right-aligned in a window of `--context` tokens, starting with `<s>`.
Uses Apple's GPU (MPS) on a Mac, CUDA if there is one, else the CPU. A long training
can run in pieces (GitHub Actions stops a job after 6 hours): each piece saves
`<out>/last.pt`, and `--resume` carries on from it with `--total-minutes` keeping the
learning rate on one schedule. Every few
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


def count_words(path):
    """Word counts over a sentence file, one line at a time."""
    counts = collections.Counter()
    with open(path, encoding="utf-8") as f:
        for line in f:
            counts.update(line.split())
    return counts


def windows(path, vocab, context):
    """Each sentence as `<s> w1 … wn`, cut to context+1 tokens, right-aligned with PAD.
    Read one line at a time into a compact Int32 table, so a few million sentences fit
    in a small runner's memory."""
    with open(path, encoding="utf-8") as f:
        n = sum(1 for line in f if line.strip())
    out = torch.full((n, context + 1), PAD, dtype=torch.int32)
    i = 0
    with open(path, encoding="utf-8") as f:
        for line in f:
            words = line.split()
            if not words:
                continue
            ids = ([BOS] + vocab.encode(words))[: context + 1]
            out[i, context + 1 - len(ids):] = torch.tensor(ids, dtype=torch.int32)
            i += 1
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
    ap.add_argument("--minutes", type=float, default=60, help="minutes to train in this run")
    ap.add_argument("--total-minutes", type=float, help="minutes over all runs, for the learning-rate fall-off "
                    "(defaults to --minutes)")
    ap.add_argument("--resume", help="a last.pt to carry on from (its folder's vocab.txt is reused)")
    ap.add_argument("--eval-every", type=float, default=10, help="minutes between test scores")
    ap.add_argument("--eval-sentences", type=int, default=5000)
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args()
    random.seed(a.seed)
    torch.manual_seed(a.seed)
    os.makedirs(a.out, exist_ok=True)
    dev = device()

    train_path = os.path.join(a.data, "train.txt")
    test = read_sentences(os.path.join(a.data, "test.txt"))[: a.eval_sentences]
    if a.resume:
        vocab = Vocabulary.load(os.path.join(os.path.dirname(a.resume), "vocab.txt"))
    else:
        counts = count_words(train_path)
        vocab = Vocabulary([w for w, _ in counts.most_common(a.vocab + 4)][: a.vocab + 4])
    vocab.save(os.path.join(a.out, "vocab.txt"))
    data = windows(train_path, vocab, a.context)
    print(f"{len(data)} sentences, vocab {len(vocab)}, device {dev}", flush=True)

    # A multiple of 64 rows, so Core ML can compress the word table in groups of 16
    # (`export.py`); the spare rows are never a word and never offered.
    rows = -(-len(vocab) // 64) * 64
    model = NextWordModel(rows, dim=a.dim, layers=a.layers, heads=a.heads, ff=4 * a.dim, context=a.context).to(dev)
    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=0.01)
    best, step, done_before = -1.0, 0, 0.0
    if a.resume:
        ckpt = torch.load(a.resume, map_location=dev)
        model = NextWordModel(**ckpt["config"]).to(dev)
        model.load_state_dict(ckpt["state"])
        opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=0.01)
        opt.load_state_dict(ckpt["opt"])
        best, step, done_before = ckpt["best"], ckpt["step"], ckpt["minutes"]
        print(f"carrying on from step {step}, {done_before:.0f} minutes in, best top-3 {best * 100:.1f}%", flush=True)
    print(f"{sum(p.numel() for p in model.parameters()) / 1e6:.1f}M weights", flush=True)
    started = time.time()
    end = started + a.minutes * 60
    total = (a.total_minutes or a.minutes) * 60
    next_eval = started + a.eval_every * 60

    def save_last():
        torch.save({"config": model.config, "state": model.state_dict(), "opt": opt.state_dict(), "step": step,
                    "best": best, "minutes": done_before + (time.time() - started) / 60},
                   os.path.join(a.out, "last.pt"))
    while True:
        perm = torch.randperm(len(data))
        for i in range(0, len(data) - a.batch + 1, a.batch):
            now = time.time()
            # Warm up for 300 steps, then fall off linearly with the time left over all runs.
            left = total - done_before * 60 - (now - started)
            lr = a.lr * min(1, (step + 1) / 300) * max(0.05, left / total)
            for g in opt.param_groups:
                g["lr"] = lr
            batch = data[perm[i : i + a.batch]].long().to(dev)
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
                save_last()
                model.train()
                next_eval = now + a.eval_every * 60
            if now >= end:
                print(f"done, best top-3 {best * 100:.1f}%", flush=True)
                return


if __name__ == "__main__":
    main()
