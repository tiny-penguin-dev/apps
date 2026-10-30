# Recorded samples

One recording is the strokes of a few words plus the words they spell. The app saves each
one as a JSON file, and the same format is used for export, upload and training. The Swift
type is `StrokeSample` (`ios/StackWriteKit`); the Python reader is `ml/samples.py`.

```json
{
  "version": 2,
  "id": "6F1C…",
  "label": "hello there",
  "labelSource": "prompt",
  "strokes": [[[0.41230, 0.55120, 0.0], [0.41388, 0.54870, 0.0083], …], [[0.5, 0.6, 0.4512], …], …],
  "padWidth": 300, "padHeight": 300,
  "writer": "random ID per install",
  "session": "random ID per sitting",
  "device": "iPhone17,1", "system": "iOS 26.1", "app": "0.1.0 (202610300400)",
  "createdAt": "2026-10-30T04:00:00Z",
  "prompt": "hello there",
  "recognized": ["hello there", "hell other", "hello the re"]
}
```

| Field | Meaning |
|---|---|
| `version` | Format version. Bump it when a field changes meaning; readers skip newer versions. |
| `label` | The words written, lowercase a–z separated by single spaces (what the model can learn today). |
| `labelSource` | `prompt` (asked to write it), `picked` (chose it from the suggestions), `committed` (kept the keyboard's top guess). Prompted labels are the most reliable. |
| `strokes` | One list per stroke, touch down to lift, of `[x, y, t]`: box units (pad is 1×1, (0,0) bottom-left, y up), `t` in seconds since the first stroke's touch down, so the gap between one stroke's last `t` and the next one's first is the lift. |
| `padWidth`, `padHeight` | The pad's size in points. A non-square pad is normalized by its height with x centered. |
| `writer`, `session` | Group samples by person and by sitting without knowing who wrote them. |
| `prompt` | The words shown, when prompted. |
| `recognized` | What the model read at the time, best first. |

The app keeps samples in `Documents/Samples/<id>.json` (also visible in the Files app)
and can export them as a zip. With uploads on, it sends each one to the public CloudKit
database as a `Sample` record named after its `id`, with the JSON in its `json` field
(`cloudkit/`), then moves the file to `Documents/Samples/Uploaded/`.
`ml/download_samples.py` saves them back as JSON files. `ml/import_captures.py` and
`ml/finetune.py` read folders, zips and `.jsonl` files of them.

## Version 1

Version 1 (until 2026-10-30) held one word written as a single stroke, in `points` instead
of `strokes` (`t` since touch down). Both readers still accept it as a one-stroke recording.
