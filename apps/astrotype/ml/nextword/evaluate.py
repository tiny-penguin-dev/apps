"""Score a next-word model on held-back sentences, by the same rules as the app's
`NextWordEval` (`astrotype-tools nexteval` scores the word pairs that way):

    python3 evaluate.py runs/en/model.pt data/en/test.txt

At every offerable word (letters only, not a contraction, "a" and "i" the only single
letters) the model's three best offerable words for the words before it in the
sentence are compared with the word that came. Prints top-1, top-3 and the share of
letters a tap on the bar would have saved.
"""
import argparse, os, sys
from dataclasses import dataclass

import torch

from model import BOS, PAD, NextWordModel, Vocabulary

# PracticeWords.contractions, word for word: dropped-apostrophe forms the keyboard never offers.
CONTRACTIONS = set("""dont doesnt didnt cant couldnt wouldnt shouldnt wont isnt arent wasnt werent havent hasnt
hadnt im ive id youre youve youll youd theyre theyve theyll theyd hes shes thats whats wheres theres weve itll
whos aint lets ill wed hed shed""".split())


def offerable(word):
    if not word or len(word) > 24 or not all("a" <= c <= "z" for c in word) or word in CONTRACTIONS:
        return False
    return len(word) > 1 or word in ("a", "i")


def read_sentences(path):
    with open(path, encoding="utf-8") as f:
        return [line.split() for line in f if line.strip()]


@dataclass
class Score:
    words: int = 0
    hits1: int = 0
    hits3: int = 0
    letters: int = 0
    saved: int = 0

    @property
    def top1(self):
        return self.hits1 / max(1, self.words)

    @property
    def top3(self):
        return self.hits3 / max(1, self.words)

    def summary(self):
        return (f"{self.words} words · top-1 {self.top1 * 100:.1f}% · top-3 {self.top3 * 100:.1f}% · "
                f"letters saved {self.saved / max(1, self.letters) * 100:.1f}%")


@torch.no_grad()
def evaluate(model, vocab, sentences, dev, batch=256):
    model.eval()
    rows = model.embed.num_embeddings
    allowed = torch.tensor([offerable(w) for w in vocab.words] + [False] * (rows - len(vocab)), device=dev)
    score = Score()
    ctx = model.context
    for i in range(0, len(sentences), batch):
        group = sentences[i : i + batch]
        ids = torch.full((len(group), ctx), PAD, dtype=torch.long)
        for j, s in enumerate(group):
            seq = ([BOS] + vocab.encode(s))[:ctx]
            ids[j, ctx - len(seq):] = torch.tensor(seq)
        logits = model(ids.to(dev)).masked_fill(~allowed, -1e9)
        top = logits.topk(3, dim=-1).indices.cpu()
        for j, s in enumerate(group):
            seq_len = min(len(s) + 1, ctx)
            start = ctx - seq_len
            # Position start+k has read <s> and the first k words: it guesses word k.
            # make_text.py keeps sentences within the window, so every word is scored.
            for k, word in enumerate(s[: seq_len]):
                if not offerable(word):
                    continue
                guesses = [vocab.words[t] for t in top[j, start + k].tolist()]
                score.words += 1
                score.letters += len(word)
                if guesses[0] == word:
                    score.hits1 += 1
                if word in guesses:
                    score.hits3 += 1
                    score.saved += len(word)
    return score


def load(path, dev="cpu"):
    ckpt = torch.load(path, map_location=dev)
    c = ckpt["config"]
    model = NextWordModel(c["vocab_size"], dim=c["dim"], layers=c["layers"], heads=c["heads"], ff=c["ff"],
                          context=c["context"])
    model.load_state_dict(ckpt["state"])
    vocab = Vocabulary.load(os.path.join(os.path.dirname(path), "vocab.txt"))
    return model.to(dev), vocab


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("model")
    ap.add_argument("test")
    ap.add_argument("--limit", type=int)
    a = ap.parse_args()
    model, vocab = load(a.model)
    sentences = read_sentences(a.test)[: a.limit]
    print(evaluate(model, vocab, sentences, "cpu").summary())


if __name__ == "__main__":
    sys.exit(main())
