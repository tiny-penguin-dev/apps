"""The next-word model: a tiny word-level transformer (features/next-word-model).

It reads up to `context` words before the cursor and scores every word in its
vocabulary as the next one. Words in and out share one table. The keyboard runs it
with Core ML on the Neural Engine at a fixed length: the words before the cursor sit at
the right end of the window, padding fills the left, and only the last position's
scores are returned (`export.py`). Positions count from the first word, not the
window, so scoring every prefix of a sentence in one pass (training, `evaluate.py`)
gives exactly what the keyboard gets for each prefix on its own.
"""
import torch
import torch.nn as nn
import torch.nn.functional as F

PAD, BOS, UNK, BREAK = 0, 1, 2, 3
SPECIALS = ["<pad>", "<s>", "<unk>", ","]


class Vocabulary:
    """Word ↔ id. The specials come first; then the words, commonest first."""

    def __init__(self, words):
        self.words = SPECIALS + [w for w in words if w not in SPECIALS]
        self.ids = {w: i for i, w in enumerate(self.words)}

    def __len__(self):
        return len(self.words)

    def encode(self, tokens):
        return [self.ids.get(t, UNK) for t in tokens]

    def save(self, path):
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(self.words) + "\n")

    @classmethod
    def load(cls, path):
        with open(path, encoding="utf-8") as f:
            words = [line.rstrip("\n") for line in f if line.strip()]
        return cls(words[len(SPECIALS):])


class Block(nn.Module):
    def __init__(self, dim, heads, ff):
        super().__init__()
        self.heads = heads
        self.head_dim = dim // heads
        self.scale = self.head_dim ** -0.5
        self.norm1 = nn.LayerNorm(dim)
        self.qkv = nn.Linear(dim, 3 * dim)
        self.out = nn.Linear(dim, dim)
        self.norm2 = nn.LayerNorm(dim)
        self.ff1 = nn.Linear(dim, ff)
        self.ff2 = nn.Linear(ff, dim)

    def forward(self, x, mask):
        # Shapes stay symbolic (unflatten/flatten, no x.shape arithmetic), so the
        # Core ML export has no shape math to fold.
        h, hd = self.heads, self.head_dim
        q, k, v = self.qkv(self.norm1(x)).chunk(3, dim=-1)
        q = q.unflatten(-1, (h, hd)).transpose(1, 2)
        k = k.unflatten(-1, (h, hd)).transpose(1, 2)
        v = v.unflatten(-1, (h, hd)).transpose(1, 2)
        att = (q @ k.transpose(-2, -1)) * self.scale + mask
        y = (att.softmax(-1) @ v).transpose(1, 2).flatten(2)
        x = x + self.out(y)
        return x + self.ff2(F.gelu(self.ff1(self.norm2(x))))


class NextWordModel(nn.Module):
    def __init__(self, vocab_size, dim=256, layers=4, heads=4, ff=1024, context=32):
        super().__init__()
        self.context = context
        self.embed = nn.Embedding(vocab_size, dim)
        self.position = nn.Embedding(context, dim)
        self.blocks = nn.ModuleList(Block(dim, heads, ff) for _ in range(layers))
        self.norm = nn.LayerNorm(dim)
        self.config = dict(vocab_size=vocab_size, dim=dim, layers=layers, heads=heads, ff=ff, context=context)

    def hidden(self, ids):
        """ids: [batch, t] with PAD on the left; returns [batch, t, dim]."""
        b, t = ids.shape
        # Positions count from the first real word, so the padding on the left changes
        # nothing: a sentence's start reads the same wherever it sits in the window.
        positions = ((ids != PAD).long().cumsum(1) - 1).clamp(min=0)
        x = self.embed(ids) + self.position(positions)
        causal = torch.full((t, t), -1e4, device=ids.device).triu(1)
        pad = (ids == PAD).float()[:, None, None, :] * -1e4
        mask = causal[None, None] + pad
        for block in self.blocks:
            x = block(x, mask)
        return self.norm(x)

    def forward(self, ids):
        """Scores for the word after every position: [batch, t, vocab]."""
        return self.hidden(ids) @ self.embed.weight.T

    def next_scores(self, ids):
        """Log-probabilities of the next word after the last position: [batch, vocab]."""
        return (self.hidden(ids)[:, -1] @ self.embed.weight.T).log_softmax(-1)
