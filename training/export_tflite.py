"""Export the trained Keras models to float32-I/O TFLite (float16 weights) and
verify each .tflite against Keras with the TFLite interpreter.

    python export_tflite.py --weights work/models --data work/data --out ../app/assets/models

Exits non-zero (loudly) if a shape, dtype or numerical check fails.
"""
import argparse
import json
import os
import shutil
import sys
import tempfile

import numpy as np
import tensorflow as tf

import models

EXPECTED = {"detector": ((1, 384, 384, 1), (1, 96, 96, 9)),
            "corners": ((1, 256, 256, 1), (1, 64, 64, 4)),
            "squares": ((1, 256, 256, 1), (1, 8, 8, 13))}
DATA_FILE = {"detector": "det_x.npy", "corners": "cor_x.npy", "squares": "sq_x.npy"}
# max abs difference allowed between Keras (fp32) and TFLite (fp16 weights)
TOL = {"detector": 0.02, "corners": 0.03, "squares": 0.03}


def convert(model, fp16):
    try:
        conv = tf.lite.TFLiteConverter.from_keras_model(model)
    except Exception as e:  # pragma: no cover
        print("from_keras_model failed, using SavedModel route:", repr(e))
        conv = None
    if conv is None:
        d = tempfile.mkdtemp()
        model.export(d)
        conv = tf.lite.TFLiteConverter.from_saved_model(d)
    conv.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
    if fp16:
        conv.optimizations = [tf.lite.Optimize.DEFAULT]
        conv.target_spec.supported_types = [tf.float16]
    return conv.convert()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--weights", default="work/models")
    ap.add_argument("--data", default="work/data")
    ap.add_argument("--out", default="../app/assets/models")
    ap.add_argument("--fp32", action="store_true")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    report, failed = {}, False
    for name in ["detector", "corners", "squares"]:
        print(f"== {name}", flush=True)
        w = np.load(os.path.join(args.weights, name + ".npz"))
        weights = [w[f"arr_{i}"] for i in range(len(w.files))]
        km = models.BUILDERS[name](batch=1)
        km.set_weights(weights)
        blob = convert(km, not args.fp32)
        path = os.path.join(args.out, name + ".tflite")
        with open(path, "wb") as f:
            f.write(blob)
        size = len(blob)
        it = tf.lite.Interpreter(model_path=path)
        it.allocate_tensors()
        i, o = it.get_input_details()[0], it.get_output_details()[0]
        ok = True
        shp_in, shp_out = EXPECTED[name]
        if tuple(i["shape"]) != shp_in or tuple(o["shape"]) != shp_out:
            print(f"  FAIL shapes {i['shape']} -> {o['shape']}, expected {shp_in} -> {shp_out}")
            ok = False
        if i["dtype"] != np.float32 or o["dtype"] != np.float32:
            print(f"  FAIL dtypes {i['dtype']} -> {o['dtype']}")
            ok = False
        # numerical check on real samples (tail of the training data) + a blank page
        x = np.load(os.path.join(args.data, DATA_FILE[name]), mmap_mode="r")
        samples = [np.asarray(x[-k]) for k in range(1, 9)] + [np.full(x.shape[1:], 255, np.uint8)]
        worst, agree = 0.0, []
        for s in samples:
            inp = (s.astype(np.float32) / 255.0)[None, :, :, None]
            ref = km.predict(inp, verbose=0)
            it.set_tensor(i["index"], inp)
            it.invoke()
            got = it.get_tensor(o["index"])
            worst = max(worst, float(np.abs(ref - got).max()))
            if name == "squares":
                agree.append(float((ref.argmax(-1) == got.argmax(-1)).mean()))
        print(f"  size {size / 1e6:.2f} MB  max|keras-tflite| = {worst:.5f}  "
              f"in {tuple(i['shape'])} {i['dtype'].__name__} out {tuple(o['shape'])} {o['dtype'].__name__}", flush=True)
        if worst > TOL[name]:
            print(f"  FAIL numeric difference above {TOL[name]}")
            ok = False
        if agree and min(agree) < 0.97:
            print(f"  FAIL argmax agreement {min(agree):.3f}")
            ok = False
        report[name] = dict(bytes=size, max_abs_diff=worst, input=list(i["shape"]), output=list(o["shape"]),
                            input_dtype=i["dtype"].__name__, output_dtype=o["dtype"].__name__, ok=ok)
        failed |= not ok
    json.dump(report, open(os.path.join(args.weights, "export.json"), "w"), indent=1)
    if failed:
        print("EXPORT VERIFICATION FAILED")
        sys.exit(1)
    print("export verification OK")


if __name__ == "__main__":
    main()
