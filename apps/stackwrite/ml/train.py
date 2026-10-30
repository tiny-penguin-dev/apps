import argparse, time, math
import numpy as np, torch, torch.nn as nn
from model import ConvStrokeNet as StrokeNet
from data import load, CHAR2ID
from letters import ALPHABET

torch.set_num_threads(2)


def batches(feats, labels, bs, rng):
    order = np.argsort([len(f) + rng.uniform(0, 30) for f in feats])
    chunks = [order[i:i + bs] for i in range(0, len(order), bs)]
    rng.shuffle(chunks)
    for idx in chunks:
        yield collate([feats[i] for i in idx], [labels[i] for i in idx])


def collate(fs, ls):
    lens = torch.tensor([len(f) for f in fs])
    x = torch.zeros(len(fs), lens.max(), fs[0].shape[1])
    for i, f in enumerate(fs):
        x[i, :len(f)] = torch.from_numpy(f.astype(np.float32))
    tgt = torch.tensor([CHAR2ID[c] for l in ls for c in l])
    tlens = torch.tensor([len(l) for l in ls])
    return x, lens, tgt, tlens, ls


def greedy(lp, ol):
    best = lp.argmax(-1)
    out = []
    for b in range(len(best)):
        seq, prev = [], 0
        for k in best[b, :ol[b]].tolist():
            if k != prev and k != 0:
                seq.append(ALPHABET[k - 1])
            prev = k
        out.append("".join(seq))
    return out


def edit(a, b):
    d = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        prev, d[0] = d[0], i
        for j, cb in enumerate(b, 1):
            prev, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, prev + (ca != cb))
    return d[-1]


@torch.no_grad()
def evaluate(model, feats, labels, n=None):
    model.eval()
    n = n or len(feats)
    errs = chars = exact = 0
    for i in range(0, n, 128):
        x, lens, _, _, ls = collate(feats[i:i + 128], labels[i:i + 128])
        lp = model(x, lens)
        for p, t in zip(greedy(lp, model.out_lens(lens)), ls):
            errs += edit(p, t); chars += len(t); exact += p == t
    model.train()
    return errs / chars, exact / n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--train", nargs="+", required=True)
    ap.add_argument("--val", nargs="+", required=True)
    ap.add_argument("--minutes", type=float, default=20)
    ap.add_argument("--lr", type=float, default=2e-3)
    ap.add_argument("--bs", type=int, default=64)
    ap.add_argument("--init")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    feats, labels = [], []
    for p in a.train:
        f, l = load(p); feats += f; labels += l
    vals = {p: load(p) for p in a.val}
    print(f"train samples: {len(feats)}", flush=True)

    model = StrokeNet()
    if a.init:
        model.load_state_dict(torch.load(a.init))
    print(f"params: {sum(p.numel() for p in model.parameters()):,}", flush=True)
    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=1e-4)
    ctc = nn.CTCLoss(blank=0, zero_infinity=True)
    rng = np.random.default_rng(0)

    t0, step, ema, budget = time.time(), 0, None, a.minutes * 60
    done = False
    while not done:
        for x, lens, tgt, tlens, _ in batches(feats, labels, a.bs, rng):
            frac = (time.time() - t0) / budget
            if frac >= 1:
                done = True; break
            # warmup then cosine decay, driven by wall-clock budget
            lr = a.lr * min(1, step / 300) * 0.5 * (1 + math.cos(math.pi * frac))
            for g in opt.param_groups: g["lr"] = lr
            lp = model(x, lens)
            loss = ctc(lp.transpose(0, 1), tgt, model.out_lens(lens), tlens)
            opt.zero_grad(); loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
            ema = loss.item() if ema is None else 0.98 * ema + 0.02 * loss.item()
            step += 1
            if step % 250 == 0:
                msg = " ".join(f"{p.split('/')[-1][:-4]}: cer={c:.3f} exact={e:.3f}"
                               for p, (vf, vl) in vals.items() for c, e in [evaluate(model, vf, vl, 512)])
                print(f"step {step} {(time.time()-t0)/60:.1f}m lr={lr:.2e} loss={ema:.3f} | {msg}", flush=True)
                torch.save(model.state_dict(), a.out)
    torch.save(model.state_dict(), a.out)
    for p, (vf, vl) in vals.items():
        c, e = evaluate(model, vf, vl)
        print(f"FINAL {p}: cer={c:.4f} exact={e:.4f}", flush=True)


if __name__ == "__main__":
    main()
