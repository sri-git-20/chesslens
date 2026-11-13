# ChessLens recognition models

Trained 2026-11-13 by `training/` (GitHub Actions workflow `train.yml`). All three models are
LiteRT/TFLite, **float32 input and output** (weights stored as float16), built-in ops only.


## Contract (unchanged from docs/ARCHITECTURE.md)

Input grayscale `(0.299 R + 0.587 G + 0.114 B) / 255` in [0, 1], NHWC, no other preprocessing.

| Model | Size | Input | Output | Params | Train time | max abs diff vs Keras |
|---|---|---|---|---|---|---|
| detector.tflite | 1.39 MB | `[1, 384, 384, 1]` | `[1, 96, 96, 9]` | 687,733 | 55 min | 0.0071 |
| corners.tflite | 1.59 MB | `[1, 256, 256, 1]` | `[1, 64, 64, 4]` | 785,060 | 30 min | 0.0016 |
| squares.tflite | 2.31 MB | `[1, 256, 256, 1]` | `[1, 8, 8, 13]` | 1,152,245 | 235 min | 0.0033 |

* `detector`: letterbox (scale `384/max(w,h)`, top-left, fill 1.0); output ch 0 = sigmoid centre heat-map,
  ch 1-8 = offsets TL.x, TL.y, TR.x, TR.y, BR.x, BR.y, BL.x, BL.y from the cell centre, divided by 384.
* `corners`: sigmoid heat-maps TL, TR, BR, BL (64x64, stride 4).
* `squares`: softmax per square, `[0, row, col, class]`, row 0 = image top.
* Class order: 0 empty, 1 wP, 2 wN, 3 wB, 4 wR, 5 wQ, 6 wK, 7 bP, 8 bN, 9 bB, 10 bR, 11 bQ, 12 bK
  ("w" = drawn as a white piece; white outline pieces in books count as white).

## Data

30000 synthetic pages (55678 diagrams, 111356 squares crops); page mix {'photo': 16540, 'clean': 7501, 'screenshot': 5959}. SVG piece sets used for training: merida, alpha, leipzig, cburnett, pirouetti, chessnut, chess7, reillycraig, companion, fresca, cardinal, gioco, staunty, governor, dubrovny, icpieces, mpchess, kiwen-suwi, horsey, anarcandy, maestro, fantasy, celtic, spatial, caliente, california, cooke, shapes; held out for testing only: riohacha, kosal, tatiana. Unicode glyph piece styles: 10 (held-out: glyph:FreeSerif:hollow, glyph:FreeSerif:filled).

## Metrics (held-out synthetic test set, 600 pages)

| Group | Pages | Boards | Det. recall | Det. precision | Corner err px (mean/p95) | Square acc | Board exact | E2E board exact | Page OK |
|---|---|---|---|---|---|---|---|---|---|
| clean/seen | 100 | 295 | 93.90% | 94.22% | 0.52 / 0.83 | 99.29% | 81.02% | 72.88% | 66.00% |
| clean/heldout | 100 | 290 | 88.62% | 89.24% | 0.52 / 0.84 | 98.34% | 65.86% | 57.59% | 55.00% |
| photo/seen | 100 | 266 | 87.22% | 92.06% | 0.76 / 1.68 | 98.13% | 72.56% | 64.29% | 69.00% |
| photo/heldout | 100 | 286 | 85.66% | 88.45% | 0.64 / 1.26 | 97.19% | 52.80% | 47.20% | 53.00% |
| screenshot/seen | 100 | 100 | 100.00% | 100.00% | 0.50 / 0.86 | 99.95% | 97.00% | 96.00% | 96.00% |
| screenshot/heldout | 100 | 100 | 100.00% | 100.00% | 0.50 / 0.78 | 98.86% | 75.00% | 76.00% | 76.00% |
| clean/all | 200 | 585 | 91.28% | 91.75% | 0.52 / 0.84 | 98.82% | 73.50% | 65.30% | 60.50% |
| photo/all | 200 | 552 | 86.41% | 90.17% | 0.70 / 1.40 | 97.64% | 62.32% | 55.43% | 61.00% |
| screenshot/all | 200 | 200 | 100.00% | 100.00% | 0.50 / 0.83 | 99.41% | 86.00% | 86.00% | 86.00% |
| all | 600 | 1337 | 90.58% | 92.37% | 0.59 / 1.05 | 98.42% | 70.76% | 64.32% | 69.17% |

Targets:

| Target | Result | Required | Met |
|---|---|---|---|
| Detection recall (all groups) | 90.58% | >= 98.0% | **NO** |
| Square accuracy, clean scans | 98.82% | >= 99.7% | **NO** |
| Board exact match, clean scans | 73.50% | >= 95.0% | **NO** |
| Board exact match, phone photo sim. | 62.32% | >= 85.0% | **NO** |

See `training/REPORT.md` for definitions, timings and known weaknesses.
Reference implementation of the app-side steps: `training/reference_pipeline.py`.
