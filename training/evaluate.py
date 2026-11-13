"""Evaluate the exported .tflite models on a held-out synthetic test set.

Groups: clean scans / phone-photo simulation / screenshots, each with piece styles
seen in training ("seen") and styles never used in training ("held-out").
Test seeds never overlap training seeds.

Metrics
  detection recall / precision    coarse quad matches a ground-truth quad
                                  (mean corner distance < 20 % of board size)
  corner error                    corners model on a jittered ground-truth coarse quad,
                                  in pixels of the 256x256 crop (mean / median / p95)
  square accuracy, exact board    squares model on the warp of the *refined* quad
                                  (stage-wise: ground-truth coarse quad + jitter ->
                                  corners model -> squares model)
  e2e board exact / page ok       through reference_pipeline.process_image on the full page
"""
import argparse
import json
import multiprocessing as mp
import os
import time

import cv2
import numpy as np

import pieces
import reference_pipeline as rp
import synth

LIB = None
GROUPS = [(c, h) for c in ("clean", "photo", "screenshot") for h in (False, True)]


def _init():
    cv2.setNumThreads(1)


def _make(args):
    seed, cat, hold = args
    return synth.make_sample(seed, LIB, cat, hold)


def quad_cost(a, b):
    size = synth.board_size(b)
    return float(np.mean(np.linalg.norm(a - b, axis=1)) / size)


def match(det_quads, gt_quads, thr=0.2):
    pairs, used = {}, set()
    cand = sorted(((quad_cost(d, g), di, gi) for di, d in enumerate(det_quads)
                   for gi, g in enumerate(gt_quads)))
    for c, di, gi in cand:
        if c < thr and di not in pairs and gi not in used:
            pairs[di] = gi
            used.add(gi)
    return pairs


class Acc:
    def __init__(self):
        self.d = dict(pages=0, gt=0, tp=0, det=0, cerr=[], sq_gt=0, sq_ref=0, sq_n=0, ex_gt=0, ex_ref=0,
                      boards=0, e2e_ex=0, e2e_sq=0, e2e_sq_n=0, page_ok=0, fp=0, secs=0.0)

    def merge(self, o):
        for k, v in o.d.items():
            self.d[k] = self.d[k] + v

    def summary(self):
        d = self.d
        r = lambda a, b: float(a) / b if b else float("nan")
        e = np.array(d["cerr"]) if d["cerr"] else np.array([np.nan])
        return dict(
            pages=d["pages"], boards=d["gt"], detections=d["det"],
            det_recall=r(d["tp"], d["gt"]), det_precision=r(d["tp"], d["det"]),
            false_positives=d["fp"],
            corner_err_mean=float(np.nanmean(e)), corner_err_median=float(np.nanmedian(e)),
            corner_err_p95=float(np.nanpercentile(e, 95)),
            square_acc_gtquad=r(d["sq_gt"], d["sq_n"]), square_acc=r(d["sq_ref"], d["sq_n"]),
            board_exact_gtquad=r(d["ex_gt"], d["boards"]), board_exact=r(d["ex_ref"], d["boards"]),
            e2e_board_exact=r(d["e2e_ex"], d["gt"]), e2e_square_acc=r(d["e2e_sq"], d["e2e_sq_n"]),
            page_ok=r(d["page_ok"], d["pages"]), sec_per_page=r(d["secs"], d["pages"]))


def eval_sample(models, s, rng, acc, fails, tag):
    d = acc.d
    gt = s.boards
    img = s.img
    gray = rp.to_gray(img)
    d["pages"] += 1
    d["gt"] += len(gt)
    # ---- stage-wise on ground-truth boards
    for b in gt:
        q = b["quad"]
        coarse = synth.jitter_coarse(rng, q)
        crop, H = rp.crop_for_corners(gray, coarse)
        pts = rp.decode_corners(models.corners(crop))
        err = np.linalg.norm(rp.apply_h(H, q) - pts, axis=1)
        d["cerr"].append(float(err.mean()))
        refined = rp.apply_h(np.linalg.inv(H), pts)
        for key_s, key_e, qq in (("sq_gt", "ex_gt", q), ("sq_ref", "ex_ref", refined)):
            cls, _ = rp.read_squares(models.squares(rp.warp_board(gray, qq)))
            ok = (cls == b["labels"])
            d[key_s] += int(ok.sum())
            d[key_e] += int(ok.all())
        d["sq_n"] += 64
        d["boards"] += 1
    # ---- end to end
    t = time.time()
    res = rp.process_image(models, img)
    d["secs"] += time.time() - t
    d["det"] += len(res)
    pairs = match([r["coarse_quad"] for r in res], [b["quad"] for b in gt])
    d["tp"] += len(pairs)
    d["fp"] += len(res) - len(pairs)
    page_ok = len(pairs) == len(gt)
    for di, gi in pairs.items():
        ok = (res[di]["classes"] == gt[gi]["labels"])
        d["e2e_sq"] += int(ok.sum())
        d["e2e_sq_n"] += 64
        d["e2e_ex"] += int(ok.all())
        page_ok &= bool(ok.all())
    d["page_ok"] += int(page_ok)
    if not page_ok and len(fails) < 14:
        fails.append((tag, img, gt, res))


def main():
    global LIB
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", default="../app/assets/models")
    ap.add_argument("--pages", type=int, default=100, help="pages per group")
    ap.add_argument("--out", default="work/metrics.json")
    ap.add_argument("--cache", default="work/svg_cache")
    ap.add_argument("--fail-dir", default="work/failures")
    args = ap.parse_args()
    LIB = pieces.build_library(args.cache, min_svg_sets=8)
    jobs = []
    for gi, (cat, hold) in enumerate(GROUPS):
        jobs += [(9_000_000 + gi * 100_000 + i, cat, hold) for i in range(args.pages)]
    accs = {g: Acc() for g in GROUPS}
    fails = []
    rng = np.random.default_rng(42)
    t0 = time.time()
    # the pool is forked *before* TensorFlow/TFLite is initialised in this process
    with mp.get_context("fork").Pool(2, initializer=_init) as pool:
        models = rp.Models(args.models)
        for n, (job, s) in enumerate(zip(jobs, pool.imap(_make, jobs, chunksize=4))):
            g = (job[1], job[2])
            eval_sample(models, s, rng, accs[g], fails, f"{job[1]}_{'held' if job[2] else 'seen'}_{job[0]}")
            if (n + 1) % 100 == 0:
                print(f"  evaluated {n + 1}/{len(jobs)} ({time.time() - t0:.0f}s)", flush=True)
    out = {}
    for (cat, hold), a in accs.items():
        out[f"{cat}/{'heldout' if hold else 'seen'}"] = a.summary()
    for cat in ("clean", "photo", "screenshot"):
        tot = Acc()
        for hold in (False, True):
            tot.merge(accs[(cat, hold)])
        out[f"{cat}/all"] = tot.summary()
    allacc = Acc()
    for a in accs.values():
        allacc.merge(a)
    out["all"] = allacc.summary()
    out["eval_seconds"] = time.time() - t0
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    json.dump(out, open(args.out, "w"), indent=1)
    os.makedirs(args.fail_dir, exist_ok=True)
    for tag, img, gt, res in fails:
        im = img.copy()
        for b in gt:
            cv2.polylines(im, [b["quad"].astype(np.int32).reshape(-1, 1, 2)], True, (0, 200, 0), 2)
        for r in res:
            cv2.polylines(im, [r["quad"].astype(np.int32).reshape(-1, 1, 2)], True, (255, 0, 0), 2)
        cv2.imwrite(os.path.join(args.fail_dir, tag + ".jpg"), cv2.cvtColor(im, cv2.COLOR_RGB2BGR))
        from config import labels_to_fen
        with open(os.path.join(args.fail_dir, tag + ".txt"), "w") as f:
            f.write("GT:\n" + "\n".join(labels_to_fen(b["labels"]) for b in gt) + "\nPRED:\n" +
                    "\n".join(r["fen"] for r in res) + "\n")
    for k, v in out.items():
        if isinstance(v, dict):
            print(f"{k:22s} recall {v['det_recall']:.4f} prec {v['det_precision']:.4f} "
                  f"cornerErr {v['corner_err_mean']:.2f}px sqAcc {v['square_acc']:.4f} "
                  f"exact {v['board_exact']:.3f} e2eExact {v['e2e_board_exact']:.3f} pageOK {v['page_ok']:.3f}")


if __name__ == "__main__":
    main()
