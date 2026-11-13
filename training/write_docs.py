"""Write app/assets/models/MODELS.md and training/REPORT.md from the run outputs."""
import argparse
import datetime
import json
import os

TARGETS = [  # (label, group, key, minimum)
    ("Detection recall (all groups)", "all", "det_recall", 0.98),
    ("Square accuracy, clean scans", "clean/all", "square_acc", 0.997),
    ("Board exact match, clean scans", "clean/all", "board_exact", 0.95),
    ("Board exact match, phone photo sim.", "photo/all", "board_exact", 0.85),
]


def pct(v):
    return "n/a" if v != v else f"{100 * v:.2f}%"


def table(m):
    rows = ["| Group | Pages | Boards | Det. recall | Det. precision | Corner err px (mean/p95) | Square acc | Board exact | E2E board exact | Page OK |",
            "|---|---|---|---|---|---|---|---|---|---|"]
    for k, v in m.items():
        if not isinstance(v, dict):
            continue
        rows.append(f"| {k} | {v['pages']} | {v['boards']} | {pct(v['det_recall'])} | {pct(v['det_precision'])} | "
                    f"{v['corner_err_mean']:.2f} / {v['corner_err_p95']:.2f} | {pct(v['square_acc'])} | "
                    f"{pct(v['board_exact'])} | {pct(v['e2e_board_exact'])} | {pct(v['page_ok'])} |")
    return "\n".join(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--work", default="work")
    ap.add_argument("--models-dir", default="../app/assets/models")
    ap.add_argument("--report", default="REPORT.md")
    ap.add_argument("--mode", default="full")
    args = ap.parse_args()
    W = args.work
    metrics = json.load(open(f"{W}/metrics.json"))
    meta = json.load(open(f"{W}/data/meta.json"))
    exp = json.load(open(f"{W}/models/export.json"))
    tr = {n: json.load(open(f"{W}/models/{n}_train.json")) for n in ("detector", "corners", "squares")}
    timings = {}
    if os.path.exists(f"{W}/timings.txt"):
        for line in open(f"{W}/timings.txt"):
            k, v = line.split()
            timings[k] = int(v)
    today = datetime.date.today().isoformat()
    tbl = table(metrics)
    tgt = ["| Target | Result | Required | Met |", "|---|---|---|---|"]
    for label, g, k, mn in TARGETS:
        v = metrics[g][k]
        tgt.append(f"| {label} | {pct(v)} | >= {100 * mn:.1f}% | {'yes' if v >= mn else '**NO**'} |")
    tgt = "\n".join(tgt)
    sizes = "\n".join(f"| {n}.tflite | {exp[n]['bytes'] / 1e6:.2f} MB | `{exp[n]['input']}` | `{exp[n]['output']}` | "
                      f"{tr[n]['params']:,} | {tr[n]['seconds'] / 60:.0f} min | {exp[n]['max_abs_diff']:.4f} |"
                      for n in ("detector", "corners", "squares"))
    data = (f"{meta['pages']} synthetic pages ({meta['boards']} diagrams, {meta['squares_samples']} squares crops); "
            f"page mix {meta['categories']}. SVG piece sets used for training: {', '.join(meta['svg_sets_train'])}; "
            f"held out for testing only: {', '.join(meta['svg_sets_holdout'])}. Unicode glyph piece styles: "
            f"{len(meta['glyph_styles'])} (held-out: {', '.join(meta['glyph_holdout']) or 'none'}).")
    mode_note = "" if args.mode == "full" else "\n> SMOKE RUN: tiny data and training, numbers are meaningless.\n"
    md = f"""# ChessLens recognition models

Trained {today} by `training/` (GitHub Actions workflow `train.yml`). All three models are
LiteRT/TFLite, **float32 input and output** (weights stored as float16), built-in ops only.
{mode_note}
## Contract (unchanged from docs/ARCHITECTURE.md)

Input grayscale `(0.299 R + 0.587 G + 0.114 B) / 255` in [0, 1], NHWC, no other preprocessing.

| Model | Size | Input | Output | Params | Train time | max abs diff vs Keras |
|---|---|---|---|---|---|---|
{sizes}

* `detector`: letterbox (scale `384/max(w,h)`, top-left, fill 1.0); output ch 0 = sigmoid centre heat-map,
  ch 1-8 = offsets TL.x, TL.y, TR.x, TR.y, BR.x, BR.y, BL.x, BL.y from the cell centre, divided by 384.
* `corners`: sigmoid heat-maps TL, TR, BR, BL (64x64, stride 4).
* `squares`: softmax per square, `[0, row, col, class]`, row 0 = image top.
* Class order: 0 empty, 1 wP, 2 wN, 3 wB, 4 wR, 5 wQ, 6 wK, 7 bP, 8 bN, 9 bB, 10 bR, 11 bQ, 12 bK
  ("w" = drawn as a white piece; white outline pieces in books count as white).

## Data

{data}

## Metrics (held-out synthetic test set, {metrics['all']['pages']} pages)

{tbl}

Targets:

{tgt}

See `training/REPORT.md` for definitions, timings and known weaknesses.
Reference implementation of the app-side steps: `training/reference_pipeline.py`.
"""
    os.makedirs(args.models_dir, exist_ok=True)
    open(f"{args.models_dir}/MODELS.md", "w").write(md)

    # --------------- REPORT.md: weak spots computed from the numbers
    weak = []
    for k, v in metrics.items():
        if isinstance(v, dict) and k != "all":
            weak.append((v["page_ok"], k, v))
    weak.sort(key=lambda t: t[0])
    wl = "\n".join(f"- `{k}`: page OK {pct(p)}, board exact {pct(v['board_exact'])}, "
                   f"detection recall {pct(v['det_recall'])}, false positives {v['false_positives']}"
                   for p, k, v in weak[:3])
    tim = "\n".join(f"- {k}: {v / 60:.1f} min" for k, v in timings.items())
    rep = f"""# Training report ({today})
{mode_note}
Everything below was produced by the CI job; numbers come from `work/metrics.json` of that run.

## Result vs targets

{tgt}

## Full metrics

{tbl}

Definitions (see `training/evaluate.py`): detection recall/precision use the coarse quad from the detector
(a match = mean corner distance < 20 % of the board size); corner error is the corners model on a
jittered ground-truth coarse quad, in pixels of the 256x256 crop; square accuracy / board exact use
the squares model on the warp of the *refined* quad; "E2E board exact" and "Page OK" go through
`reference_pipeline.process_image` on the whole page (an undetected board counts as wrong).
`seen` = piece styles used in training, `heldout` = piece sets / glyph font never used in training.
Evaluation data is synthetic: real photos will be harder (see weaknesses).

## Training

| Model | Params | Time | Samples seen (approx.) | Final loss |
|---|---|---|---|---|
""" + "\n".join(f"| {n} | {tr[n]['params']:,} | {tr[n]['seconds'] / 60:.0f} min | {tr[n]['samples_seen']:,} | "
                f"{tr[n]['final']['loss']:.4f} |" for n in tr) + f"""

## Timings

{tim}

## Weakest groups (by page accuracy)

{wl}

## Known weaknesses

- Everything is trained and evaluated on synthetic data. Piece shapes in real books (hand-drawn figurine
  fonts, low-resolution scans of 1960s prints, very ornate sets) may differ from the ~30 Lichess sets and
  the Unicode fonts used here; the held-out sets measure generalisation to other *vector* sets only.
- Boards that are partly cut off by the image edge, heavily curved pages near the spine, extreme
  perspective (more than ~10 degrees tilt) and motion blur are not covered.
- Pages rotated by 90/180 degrees are not covered (rotation augmentation is +/-8 degrees); the app should
  rotate by EXIF orientation first.
- Non-8x8 grids, three-dimensional boards and boards with unusual markings are not covered; tables and
  figures are only used as a small set of negatives.
- The squares model reads what is drawn, so promotion pieces, upside-down pieces or alternative symbols
  (e.g. letters instead of figurines) are not recognised.
- Orientation (White at the bottom or top) is not predicted here; the labels are as drawn.
"""
    open(args.report, "w").write(rep)
    print("docs written")


if __name__ == "__main__":
    main()
