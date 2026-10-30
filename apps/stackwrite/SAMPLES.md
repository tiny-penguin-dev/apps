# Recorded samples

One recorded word is one finger stroke plus the word it spells. The app saves each one
as a JSON file, and the same format is used for export, upload and training. The Swift
type is `StrokeSample` (`ios/StackWriteKit`); the Python reader is `ml/samples.py`.

```json
{
  "version": 1,
  "id": "6F1C…",
  "label": "hello",
  "labelSource": "prompt",
  "points": [[0.41230, 0.55120, 0.0], [0.41388, 0.54870, 0.0083], …],
  "padWidth": 300, "padHeight": 300,
  "writer": "random ID per install",
  "session": "random ID per sitting",
  "device": "iPhone17,1", "system": "iOS 26.1", "app": "0.1.0 (202610300400)",
  "createdAt": "2026-10-30T04:00:00Z",
  "prompt": "people water again stack hello",
  "recognized": ["hello", "hells", "jello"]
}
```

| Field | Meaning |
|---|---|
| `version` | Format version. Bump it when a field changes meaning; readers skip newer versions. |
| `label` | The word written, lowercase a–z (what the model can learn today). |
| `labelSource` | `prompt` (asked to write it), `picked` (chose it from the suggestions), `committed` (kept the keyboard's top guess). Prompted labels are the most reliable. |
| `points` | `[x, y, t]`: box units (pad is 1×1, (0,0) bottom-left, y up), `t` in seconds since touch down. |
| `padWidth`, `padHeight` | The pad's size in points. A non-square pad is normalized by its height with x centered. |
| `writer`, `session` | Group samples by person and by sitting without knowing who wrote them. |
| `prompt` | The words shown together, when prompted. |
| `recognized` | What the model read at the time, best first. |

The app keeps samples in `Documents/Samples/<id>.json` (also visible in the Files app)
and can export them as a zip. With uploads on, it sends each one to the public CloudKit
database as a `Sample` record named after its `id`, with the JSON in its `json` field
(`cloudkit/`), then moves the file to `Documents/Samples/Uploaded/`.
`ml/download_samples.py` saves them back as JSON files. `ml/import_captures.py` and
`ml/finetune.py` read folders, zips and `.jsonl` files of them.
