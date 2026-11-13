"""Write sample images + expected.json for the app's Dart-port tests.

    python make_fixtures.py --models ../app/assets/models --out ../app/test/fixtures/scan

expected.json per image: ground-truth board quads (TL, TR, BR, BL; continuous
pixel coordinates, (0,0) = top-left corner of the top-left pixel) with the FEN
placement *as drawn* (image top row first), and the reference pipeline's own
output on the saved file.
"""
import argparse
import json
import os

import cv2
import numpy as np

import pieces
import reference_pipeline as rp
import synth
from config import CLASS_NAMES, labels_to_fen

LIB = None


def r2(a):
    return [[round(float(x), 2) for x in p] for p in np.asarray(a)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", default="../app/assets/models")
    ap.add_argument("--out", default="../app/test/fixtures/scan")
    ap.add_argument("--cache", default="work/svg_cache")
    args = ap.parse_args()
    lib = pieces.build_library(args.cache, min_svg_sets=8)
    os.makedirs(args.out, exist_ok=True)
    models = rp.Models(args.models)
    wanted = {
        "clean_page_many.png": lambda s: s.category == "clean" and s.kind == "book" and len(s.boards) >= 4,
        "clean_page_black_side.png": lambda s: s.category == "clean" and s.kind == "book"
        and len(s.boards) >= 2 and any(b["flipped"] for b in s.boards),
        "clean_page_two.png": lambda s: s.category == "clean" and s.kind == "book" and len(s.boards) == 2,
        "photo_page_many.jpg": lambda s: s.category == "photo" and s.kind == "book" and len(s.boards) >= 3,
        "photo_page_black_side.jpg": lambda s: s.category == "photo" and s.kind == "book"
        and len(s.boards) >= 2 and any(b["flipped"] for b in s.boards),
        "photo_single_diagram.jpg": lambda s: s.category == "photo" and s.kind == "crop",
        "single_diagram_clean.png": lambda s: s.category == "clean" and s.kind == "crop",
        "screenshot_phone.png": lambda s: s.category == "screenshot" and s.img.shape[0] > 1.5 * s.img.shape[1],
        "screenshot_desktop.png": lambda s: s.category == "screenshot" and s.img.shape[1] > 1.3 * s.img.shape[0],
    }
    found = {}
    for seed in range(8_000_000, 8_000_600):
        if len(found) == len(wanted):
            break
        s = synth.make_sample(seed, lib, None, holdout=bool(seed % 2))
        for name, pred in wanted.items():
            if name not in found and s.boards and pred(s):
                found[name] = s
                break
    images = []
    for name in wanted:
        if name not in found:
            print("fixture not found:", name)
            continue
        s = found[name]
        path = os.path.join(args.out, name)
        if name.endswith(".jpg"):
            cv2.imwrite(path, cv2.cvtColor(s.img, cv2.COLOR_RGB2BGR), [cv2.IMWRITE_JPEG_QUALITY, 90])
        else:
            cv2.imwrite(path, cv2.cvtColor(s.img, cv2.COLOR_RGB2BGR))
        img = cv2.cvtColor(cv2.imread(path), cv2.COLOR_BGR2RGB)   # what the app will decode
        res = rp.process_image(models, img)
        h, w = img.shape[:2]
        images.append(dict(
            file=name, width=w, height=h, category=s.category,
            boards=[dict(quad=r2(b["quad"]), fen=labels_to_fen(b["labels"]), black_at_bottom=bool(b["flipped"]))
                    for b in s.boards],
            reference=dict(
                letterbox_scale=384.0 / max(w, h),
                boards=[dict(score=round(r["score"], 4), coarse_quad=r2(r["coarse_quad"]), quad=r2(r["quad"]),
                             fen=r["fen"], confidence=[round(float(c), 4) for c in r["confidence"].reshape(-1)])
                        for r in res])))
        print(f"{name}: {len(s.boards)} boards, reference found {len(res)}")
    doc = dict(
        version=1,
        notes=["Quads: TL, TR, BR, BL by position in the image; continuous pixel coordinates "
               "((0,0) = top-left corner of the top-left pixel).",
               "fen = piece placement as drawn: the top row of the image is the first FEN rank, "
               "independent of orientation.",
               "confidence: 64 softmax maxima, row-major from the image top-left.",
               "reference = output of training/reference_pipeline.py on the saved file; a correct Dart "
               "port should match it closely (floating point differences only)."],
        class_order=CLASS_NAMES, images=images)
    json.dump(doc, open(os.path.join(args.out, "expected.json"), "w"), indent=1)
    print("fixtures written:", len(images))


if __name__ == "__main__":
    main()
