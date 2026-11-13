"""Generate the synthetic training set into --out (numpy files).

  det_x.npy  (N,384,384) uint8   letterboxed greyscale pages
  det_q.npy  (N,10,4,2)  float32 board quads in letterbox px (first det_n valid)
  det_n.npy  (N,)        int8
  cor_x.npy  (M,256,256) uint8   corner-model crops;  cor_y.npy (M,4,2) float32 crop px
  sq_x.npy   (K,256,256) uint8   squares-model warps; sq_y.npy  (K,8,8) uint8
"""
import argparse
import json
import multiprocessing as mp
import os
import time
from collections import Counter

import numpy as np

import pieces
import synth

LIB = None
SQ_PER_BOARD = 2


def _init():
    import cv2
    cv2.setNumThreads(1)


ONLY_SQ = False


def _work(seed):
    s = synth.make_sample(seed, LIB, mix="squares" if ONLY_SQ else "all")
    a = synth.to_training(seed, s, SQ_PER_BOARD, squares_only=ONLY_SQ)
    a["cat"] = s.category
    return a


def _finalize_npy(path, n, row_shape, dtype):
    """Shrink an over-allocated .npy (header + truncate) to exactly n rows."""
    with open(path, "r+b") as f:
        np.lib.format.read_magic(f)
        np.lib.format.read_array_header_1_0(f)
        off = f.tell()
        hdr = {"descr": np.lib.format.dtype_to_descr(np.dtype(dtype)), "fortran_order": False,
               "shape": (n,) + tuple(row_shape)}
        f.seek(0)
        np.lib.format.write_array_header_1_0(f, hdr)
        assert f.tell() == off, "npy header length changed"
        f.truncate(off + n * int(np.prod(row_shape)) * np.dtype(dtype).itemsize)


def only_squares(args, t0):
    cap = args.pages * 4 * args.sq_per_board
    X = np.lib.format.open_memmap(os.path.join(args.out, "sq_x.npy"), mode="w+", dtype=np.uint8, shape=(cap, 256, 256))
    Y = np.lib.format.open_memmap(os.path.join(args.out, "sq_y.npy"), mode="w+", dtype=np.uint8, shape=(cap, 8, 8))
    n, cats = 0, Counter()
    t1 = time.time()
    with mp.get_context("fork").Pool(args.workers, initializer=_init) as pool:
        for i, a in enumerate(pool.imap(_work, range(args.seed0, args.seed0 + args.pages), chunksize=8)):
            for x, y in zip(a["sq_x"], a["sq_y"]):
                if n < cap:
                    X[n], Y[n] = x, y
                    n += 1
            cats[a["cat"]] += 1
            if (i + 1) % 1000 == 0 or i + 1 == args.pages:
                el = time.time() - t1
                print(f"  {i + 1}/{args.pages} pages, {n} squares samples, {el:.0f}s ({(i + 1) / el:.1f} pages/s)", flush=True)
    X.flush(); Y.flush()
    del X, Y
    _finalize_npy(os.path.join(args.out, "sq_x.npy"), n, (256, 256), np.uint8)
    _finalize_npy(os.path.join(args.out, "sq_y.npy"), n, (8, 8), np.uint8)
    meta = dict(pages=args.pages, boards=n // args.sq_per_board, squares_samples=n, categories=dict(cats),
                seconds=time.time() - t0, squares_only=True,
                svg_sets_train=[s.name for s in LIB.styles if s.kind == "svg" and not s.holdout],
                svg_sets_holdout=[s.name for s in LIB.styles if s.kind == "svg" and s.holdout],
                glyph_styles=[s.name for s in LIB.styles if s.kind == "glyph"],
                glyph_holdout=[s.name for s in LIB.styles if s.kind == "glyph" and s.holdout])
    json.dump(meta, open(os.path.join(args.out, "meta.json"), "w"), indent=1)
    print("data ready:", json.dumps(meta), flush=True)


def main():
    global LIB, SQ_PER_BOARD, ONLY_SQ
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--pages", type=int, default=10000)
    ap.add_argument("--seed0", type=int, default=1_000_000)
    ap.add_argument("--sq-per-board", type=int, default=2)
    ap.add_argument("--only-squares", action="store_true", help="write only the squares set (retraining squares)")
    ap.add_argument("--workers", type=int, default=os.cpu_count())
    ap.add_argument("--cache", default="work/svg_cache")
    ap.add_argument("--min-svg-sets", type=int, default=8)
    args = ap.parse_args()
    SQ_PER_BOARD = args.sq_per_board
    ONLY_SQ = args.only_squares
    os.makedirs(args.out, exist_ok=True)
    t0 = time.time()
    print("building piece library ...", flush=True)
    LIB = pieces.build_library(args.cache, min_svg_sets=args.min_svg_sets)
    print(f"library ready in {time.time() - t0:.0f}s", flush=True)

    if ONLY_SQ:
        return only_squares(args, t0)
    det_x, det_q, det_n, cor_x, cor_y, sq_x, sq_y = [], [], [], [], [], [], []
    cats = Counter()
    t1 = time.time()
    ctx = mp.get_context("fork")
    with ctx.Pool(args.workers, initializer=_init) as pool:
        for i, a in enumerate(pool.imap(_work, range(args.seed0, args.seed0 + args.pages), chunksize=8)):
            det_x.append(a["det_x"]); det_q.append(a["det_q"]); det_n.append(a["det_n"])
            cor_x += a["cor_x"]; cor_y += a["cor_y"]; sq_x += a["sq_x"]; sq_y += a["sq_y"]
            cats[a["cat"]] += 1
            if (i + 1) % 500 == 0 or i + 1 == args.pages:
                el = time.time() - t1
                print(f"  {i + 1}/{args.pages} pages, {len(cor_x)} boards, {el:.0f}s "
                      f"({(i + 1) / el:.1f} pages/s)", flush=True)

    def dump(name, lst, dtype=None):
        arr = np.lib.format.open_memmap(os.path.join(args.out, name + ".npy"), mode="w+",
                                        dtype=dtype or lst[0].dtype, shape=(len(lst),) + lst[0].shape)
        for j in range(len(lst)):
            arr[j] = lst[j]
            lst[j] = None
        arr.flush()
        del arr
    dump("det_x", det_x); dump("det_q", det_q)
    np.save(os.path.join(args.out, "det_n.npy"), np.array(det_n, np.int8))
    dump("cor_x", cor_x); dump("cor_y", cor_y); dump("sq_x", sq_x); dump("sq_y", sq_y)
    meta = dict(pages=args.pages, boards=len(cor_y), squares_samples=len(sq_y),
                categories=dict(cats), seconds=time.time() - t0,
                svg_sets_train=[s.name for s in LIB.styles if s.kind == "svg" and not s.holdout],
                svg_sets_holdout=[s.name for s in LIB.styles if s.kind == "svg" and s.holdout],
                glyph_styles=[s.name for s in LIB.styles if s.kind == "glyph"],
                glyph_holdout=[s.name for s in LIB.styles if s.kind == "glyph" and s.holdout])
    json.dump(meta, open(os.path.join(args.out, "meta.json"), "w"), indent=1)
    print("data ready:", json.dumps(meta), flush=True)


if __name__ == "__main__":
    main()
