"""Export the trained model to Core ML (.mlpackage) and ONNX.

Input  "strokes": (1, T, 5) float32, T = number of resampled points (16..2048)
Output "logprobs": (1, ceil(T/4), 27) per-frame log-probabilities (0 = blank, 1..26 = a..z)
"""
import argparse, json
import numpy as np, torch
from model import ConvStrokeNet
from synth import STEP, FEATURES


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--out", default="export/StackWrite")
    a = ap.parse_args()

    m = ConvStrokeNet(); m.load_state_dict(torch.load(a.model)); m.eval()
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
    ml.short_description = "Stacked one-stroke handwriting recognizer (CTC, a-z)"
    ml.user_defined_metadata["resample_step_box_units"] = str(STEP)
    ml.user_defined_metadata["features"] = "x-0.5, y-0.5, cos(dir), sin(dir), turn/pi"
    ml.save(a.out + ".mlpackage")

    torch.onnx.export(m, ex, a.out + ".onnx", input_names=["strokes"], output_names=["logprobs"],
                      dynamic_axes={"strokes": {1: "T"}, "logprobs": {1: "T4"}}, opset_version=17,
                      dynamo=False)
    json.dump({"step": STEP, "alphabet": "abcdefghijklmnopqrstuvwxyz", "blank": 0},
              open(a.out + ".json", "w"), indent=1)
    print("saved", a.out + ".mlpackage", a.out + ".onnx")


if __name__ == "__main__":
    main()
