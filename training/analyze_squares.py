"""Error analysis of the squares model on fresh synthetic data.

    python analyze_squares.py --models ../app/assets/models --pages 300

Prints accuracy by background style, piece kind, seen/held-out, board pixel size, square colour,
hollow white pieces, a confusion matrix, and saves the worst misclassified warps to work/analysis.
"""
import argparse
import collections
import multiprocessing as mp
import os

import cv2
import numpy as np

import pieces
import reference_pipeline as rp
import synth
from config import CLASS_NAMES

LIB = None


def _init():
    cv2.setNumThreads(1)


def _make(a):
    seed, cat, hold = a
    return synth.make_sample(seed, LIB, cat, hold)


def bucket(px):
    return "<100" if px < 100 else "100-160" if px < 160 else "160-250" if px < 250 else ">=250"


def main():
    global LIB
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", default="../app/assets/models")
    ap.add_argument("--pages", type=int, default=300)
    ap.add_argument("--cache", default="work/svg_cache")
    ap.add_argument("--out", default="work/analysis")
    args = ap.parse_args()
    LIB = pieces.build_library(args.cache, min_svg_sets=8)
    os.makedirs(args.out, exist_ok=True)
    jobs = [(7_000_000 + i, ["clean", "photo", "screenshot"][i % 3], bool((i // 3) % 2)) for i in range(args.pages)]
    rows = []      # (cat, held, dark, pkind, bucket, sqcolor, hollow, true, pred, conf)
    boards = []    # (err_count, warp, true, pred, tag)
    cm = np.zeros((13, 13), int)
    rng = np.random.default_rng(1)
    with mp.get_context("fork").Pool(2, initializer=_init) as pool:
        model = rp.TFLiteModel(f"{args.models}/squares.tflite")
        for job, s in zip(jobs, pool.imap(_make, jobs, chunksize=4)):
            gray = rp.to_gray(s.img)
            for b in s.boards:
                q = synth.jitter_fine(rng, b["quad"]) if rng.random() < 0.5 else b["quad"]
                warp = rp.warp_board(gray, q)
                cls, conf = rp.read_squares(model(warp))
                m = b["meta"]
                px = synth.board_size(b["quad"])
                for r in range(8):
                    for c in range(8):
                        t, p = int(b["labels"][r, c]), int(cls[r, c])
                        cm[t, p] += 1
                        rows.append((job[1], job[2], m["dark"], m["pkind"], bucket(px),
                                     "dark" if (r + c) % 2 else "light", bool(m["hollow"][r, c]) if t else False,
                                     t, p, float(conf[r, c])))
                n_err = int((cls != b["labels"]).sum())
                if n_err:
                    boards.append((n_err, warp, b["labels"], cls, f"{job[1]}_{m['dark']}_{m['piece'].replace(':', '-')}_{int(px)}px"))
    R = np.array([(r[7] == r[8]) for r in rows])
    print(f"squares: {len(rows)}, accuracy {R.mean():.4f}, boards with errors {len(boards)}")

    def report(title, keyf, filt=lambda r: True):
        d = collections.defaultdict(list)
        for r in rows:
            if filt(r):
                d[keyf(r)].append(r[7] == r[8])
        print(f"--- by {title}")
        for k, v in sorted(d.items(), key=lambda kv: str(kv[0])):
            print(f"  {str(k):24s} n={len(v):7d} acc={np.mean(v):.4f} err={len(v) - sum(v)}")
    report("category", lambda r: r[0])
    report("seen/held-out", lambda r: "held" if r[1] else "seen")
    report("dark-square style", lambda r: r[2])
    report("piece kind", lambda r: r[3])
    report("board px size", lambda r: r[4])
    report("square colour", lambda r: r[5])
    report("hollow white piece (white pieces only)", lambda r: r[6], lambda r: 1 <= r[7] <= 6)
    report("true class", lambda r: CLASS_NAMES[r[7]])
    report("category x size", lambda r: (r[0], r[4]))
    report("dark style x size", lambda r: (r[2], r[4]))
    print("--- top confusions (true -> pred)")
    pairs = sorted(((cm[t, p], t, p) for t in range(13) for p in range(13) if t != p), reverse=True)[:25]
    for n, t, p in pairs:
        print(f"  {CLASS_NAMES[t]:>5s} -> {CLASS_NAMES[p]:<5s} {n}")
    print("--- confidence: mean conf of errors vs correct")
    ce = [r[9] for r in rows if r[7] != r[8]]
    cc = [r[9] for r in rows if r[7] == r[8]]
    print(f"  errors {np.mean(ce):.3f} (share <0.85: {np.mean(np.array(ce) < .85):.2f}), correct {np.mean(cc):.3f}")
    print("--- confusion matrix rows=true")
    print("       " + " ".join(f"{n:>5s}" for n in CLASS_NAMES))
    for t in range(13):
        print(f"{CLASS_NAMES[t]:>6s} " + " ".join(f"{cm[t, p]:5d}" for p in range(13)))
    boards.sort(key=lambda b: -b[0])
    for i, (n, warp, t, p, tag) in enumerate(boards[:40]):
        im = cv2.cvtColor(warp, cv2.COLOR_GRAY2BGR) if warp.dtype == np.uint8 else cv2.cvtColor((warp * 255).astype(np.uint8), cv2.COLOR_GRAY2BGR)
        for r in range(8):
            for c in range(8):
                if t[r, c] != p[r, c]:
                    cv2.rectangle(im, (c * 32, r * 32), (c * 32 + 31, r * 32 + 31), (0, 0, 255), 1)
                    cv2.putText(im, f"{CLASS_NAMES[t[r, c]]}>{CLASS_NAMES[p[r, c]]}", (c * 32 + 1, r * 32 + 12),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.3, (255, 0, 0), 1)
        cv2.imwrite(os.path.join(args.out, f"{i:02d}_{n}err_{tag}.png"), im)


if __name__ == "__main__":
    main()
