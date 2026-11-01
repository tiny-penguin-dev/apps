"""Export a trained model to Core ML (.mlpackage) and ONNX.

Phrase model (train_phrases.py):
  Input  "strokes": (1, T, 9) float32, T = resampled points over all strokes (16..2048)
  Output "logprobs": (1, ceil(T/4), 28): 0 = blank, 1..26 = a..z, 27 = space
The older single-word model has 5 features and 27 classes (no space).
"""
import argparse, json
import numpy as np, torch
from model import ConvStrokeNet
from synth import STEP
import phrases


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--out", default="export/Astrotype")
    a = ap.parse_args()

    sd = torch.load(a.model, map_location="cpu")
    FEATURES, classes = sd["stem.0.weight"].shape[1], sd["out.weight"].shape[0]
    m = ConvStrokeNet(features=FEATURES, classes=classes); m.load_state_dict(sd); m.eval()
    phrase = classes == phrases.N_CLASSES
    ex = torch.randn(1, 200, FEATURES)
    traced = torch.jit.trace(m, ex)

    import coremltools as ct
    T = ct.RangeDim(lower_bound=16, upper_bound=2048, default=200)
    ml = ct.convert(
        traced,
        inputs=[ct.TensorType(name="strokes", shape=(1, T, FEATURES), dtype=np.float32)],
        outputs=[ct.TensorType(name="logprobs")],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS16,
    )
    ml.short_description = ("Stacked handwriting recognizer with finger lifts (CTC, a-z and space)" if phrase
                            else "Stacked one-stroke handwriting recognizer (CTC, a-z)")
    ml.user_defined_metadata["resample_step_box_units"] = str(STEP)
    ml.user_defined_metadata["features"] = (
        "x-0.5, y-0.5, cos(dir), sin(dir), turn/pi, stroke start, log1p(lift/0.25), "
        "log1p(lift/writer lift), log(stroke length + 0.01)" if phrase
        else "x-0.5, y-0.5, cos(dir), sin(dir), turn/pi")
    ml.save(a.out + ".mlpackage")

    torch.onnx.export(m, ex, a.out + ".onnx", input_names=["strokes"], output_names=["logprobs"],
                      dynamic_axes={"strokes": {1: "T"}, "logprobs": {1: "T4"}}, opset_version=17,
                      dynamo=False)
    json.dump({"step": STEP, "features": FEATURES, "classes": phrases.CLASSES if phrase else phrases.ALPHABET,
               "blank": 0},
              open(a.out + ".json", "w"), indent=1)
    print("saved", a.out + ".mlpackage", a.out + ".onnx")


if __name__ == "__main__":
    main()
