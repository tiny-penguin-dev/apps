"""Export a trained next-word model to Core ML for the keyboard.

    python3 export.py runs/en/model.pt ../../ios/AstrotypeKit/Sources/AstrotypeCore/Resources/en/

Writes `nextword.mlpackage` (weights palettized to 4 bits, for iOS 18) and
`nextword-vocab.txt` (one word per line, ids in order) into the folder. The model
takes `ids`, Int32 [1, context], the words before the cursor right-aligned with 0
(padding) on the left and `<s>` (1) before the sentence's first word, and returns
`scores`, Float16 [1, vocabulary], log-probabilities of the next word. Runs on the
Neural Engine (compute units: CPU and Neural Engine).

Prints the size and checks the export against PyTorch on a few sentences (on a Mac,
where Core ML can run; elsewhere it only converts).
"""
import argparse, os, shutil, sys

import numpy as np
import torch
import torch.nn as nn

from evaluate import load
from model import BOS, PAD


class ForExport(nn.Module):
    """The model with its masks fixed for one window length, last position only."""

    def __init__(self, model):
        super().__init__()
        self.model = model
        t = model.context
        self.register_buffer("causal", torch.full((t, t), -1e4).triu(1)[None, None])

    def forward(self, ids):
        m = self.model
        ids = ids.long()
        real = (ids != PAD).float()
        positions = (real.cumsum(1) - 1).clamp(min=0).long()
        x = m.embed(ids) + m.position(positions)
        mask = self.causal + (1 - real)[:, None, None, :] * -1e4
        for block in m.blocks:
            x = block(x, mask)
        h = m.norm(x)[:, -1]
        return (h @ m.embed.weight.T).log_softmax(-1)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("model")
    ap.add_argument("out")
    ap.add_argument("--bits", type=int, default=4)
    a = ap.parse_args()

    import coremltools as ct
    import coremltools.optimize.coreml as cto

    model, vocab = load(a.model)
    model.eval()
    wrapper = ForExport(model).eval()
    t = model.context
    example = torch.full((1, t), PAD, dtype=torch.int32)
    example[0, -3:] = torch.tensor([BOS, 5, 6])
    traced = torch.jit.trace(wrapper, example)
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="ids", shape=(1, t), dtype=np.int32)],
        outputs=[ct.TensorType(name="scores", dtype=np.float16)],
        minimum_deployment_target=ct.target.iOS18,
        compute_units=ct.ComputeUnit.CPU_AND_NE,
        compute_precision=ct.precision.FLOAT16,
    )
    if a.bits < 16:
        config = cto.OptimizationConfig(global_config=cto.OpPalettizerConfig(
            mode="kmeans", nbits=a.bits, granularity="per_grouped_channel", group_size=16, weight_threshold=2048))
        mlmodel = cto.palettize_weights(mlmodel, config)
    mlmodel.short_description = "Astrotype next-word model (features/next-word-model)"
    os.makedirs(a.out, exist_ok=True)
    path = os.path.join(a.out, "nextword.mlpackage")
    if os.path.exists(path):
        shutil.rmtree(path)
    mlmodel.save(path)
    vocab.save(os.path.join(a.out, "nextword-vocab.txt"))
    size = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(path) for f in fs)
    print(f"{path}: {size / 1e6:.2f} MB, vocabulary {len(vocab)}, window {t}")

    if sys.platform == "darwin":
        sentence = ["i", "left", "my", "phone", "at", "the"]
        ids = ([BOS] + vocab.encode(sentence))[-t:]
        x = np.zeros((1, t), dtype=np.int32)
        x[0, t - len(ids):] = ids
        got = mlmodel.predict({"ids": x})["scores"][0]
        want = wrapper(torch.tensor(x)).detach().numpy()[0]
        top_got = [vocab.words[i] for i in np.argsort(-got)[:5]]
        top_want = [vocab.words[i] for i in np.argsort(-want)[:5]]
        print("Core ML:", top_got)
        print("PyTorch:", top_want)


if __name__ == "__main__":
    main()
