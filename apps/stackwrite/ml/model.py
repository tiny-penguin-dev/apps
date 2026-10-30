import torch, torch.nn as nn
from synth import FEATURES

N_CLASSES = 27  # blank + a..z


class ResBlock(nn.Module):
    def __init__(self, ch, dil):
        super().__init__()
        self.dw = nn.Conv1d(ch, ch, 5, padding=2 * dil, dilation=dil, groups=ch)
        self.norm = nn.BatchNorm1d(ch)
        self.pw1 = nn.Conv1d(ch, ch * 2, 1)
        self.pw2 = nn.Conv1d(ch * 2, ch, 1)
        self.act = nn.GELU()

    def forward(self, x):
        return x + self.pw2(self.act(self.pw1(self.norm(self.dw(x)))))


class ConvStrokeNet(nn.Module):
    """All-convolution version: much faster on CPU / Neural Engine, easy Core ML export.
    Receptive field ~5 letters in both directions."""

    def __init__(self, ch=128, dils=(1, 2, 4, 8, 1, 2, 4, 8)):
        super().__init__()
        self.stem = nn.Sequential(
            nn.Conv1d(FEATURES, 64, 5, padding=2), nn.GELU(),
            nn.Conv1d(64, 128, 5, stride=2, padding=2), nn.GELU(),
            nn.Conv1d(128, ch, 5, stride=2, padding=2), nn.GELU(),
        )
        self.blocks = nn.Sequential(*[ResBlock(ch, d) for d in dils])
        self.out = nn.Conv1d(ch, N_CLASSES, 1)

    out_lens = staticmethod(lambda lens: (((lens - 1) // 2 + 1) - 1) // 2 + 1)

    def forward(self, x, lens=None):
        h = self.blocks(self.stem(x.transpose(1, 2)))
        return self.out(h).transpose(1, 2).log_softmax(-1)


class StrokeNet(nn.Module):
    """Conv front-end (4x downsample) + 2-layer BiLSTM + per-frame letter scores (CTC)."""

    def __init__(self, hidden=128):
        super().__init__()
        self.conv = nn.Sequential(
            nn.Conv1d(FEATURES, 64, 5, padding=2), nn.ReLU(),
            nn.Conv1d(64, 96, 5, stride=2, padding=2), nn.ReLU(),
            nn.Conv1d(96, 128, 5, stride=2, padding=2), nn.ReLU(),
        )
        self.rnn = nn.LSTM(128, hidden, num_layers=2, bidirectional=True, batch_first=True, dropout=0.1)
        self.out = nn.Linear(2 * hidden, N_CLASSES)

    @staticmethod
    def out_lens(lens):
        for _ in range(2):
            lens = (lens - 1) // 2 + 1
        return lens

    def forward(self, x, lens=None):
        """x: (B, T, F) -> log-probs (B, T', 27)."""
        h = self.conv(x.transpose(1, 2)).transpose(1, 2)
        if lens is not None:
            ol = self.out_lens(lens)
            packed = nn.utils.rnn.pack_padded_sequence(h, ol.cpu(), batch_first=True, enforce_sorted=False)
            h, _ = self.rnn(packed)
            h, _ = nn.utils.rnn.pad_packed_sequence(h, batch_first=True, total_length=ol.max().item())
        else:
            h, _ = self.rnn(h)
        return self.out(h).log_softmax(-1)
