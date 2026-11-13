# ChessLens recognition models

Trained 2026-11-13 by `training/` (GitHub Actions workflow `train.yml`). All three models are
LiteRT/TFLite, **float32 input and output** (weights stored as float16), built-in ops only.

## Contract (unchanged from docs/ARCHITECTURE.md)

Input grayscale `(0.299 R + 0.587 G + 0.114 B) / 255` in [0, 1], NHWC, no other preprocessing.

| Model | Size | Input | Output | Params | Train time | max abs diff vs Keras |
|---|---|---|---|---|---|---|
| detector.tflite | 1.39 MB | `[1, 384, 384, 1]` | `[1, 96, 96, 9]` | 687,733 | 55 min | 0.0071 |
| corners.tflite | 1.59 MB | `[1, 256, 256, 1]` | `[1, 64, 64, 4]` | 785,060 | 30 min | 0.0016 |
| squares.tflite | 1.78 MB | `[1, 256, 256, 1]` | `[1, 8, 8, 13]` | 886,269 | 65 min | 0.0035 |

* `detector`: letterbox (scale `384/max(w,h)`, top-left, fill 1.0); output ch 0 = sigmoid centre heat-map,
  ch 1-8 = offsets TL.x, TL.y, TR.x, TR.y, BR.x, BR.y, BL.x, BL.y from the cell centre, divided by 384.
* `corners`: sigmoid heat-maps TL, TR, BR, BL (64x64, stride 4).
* `squares`: softmax per square, `[0, row, col, class]`, row 0 = image top.
* Class order: 0 empty, 1 wP, 2 wN, 3 wB, 4 wR, 5 wQ, 6 wK, 7 bP, 8 bN, 9 bB, 10 bR, 11 bQ, 12 bK
  ("w" = drawn as a white piece; white outline pieces in books count as white).

## Data

10000 synthetic pages (22166 diagrams, 44332 squares crops); page mix {'photo': 4715, 'clean': 2785, 'screenshot': 2500}. SVG piece sets used for training: merida, alpha, leipzig, cburnett, pirouetti, chessnut, chess7, reillycraig, companion, fresca, cardinal, gioco, staunty, governor, dubrovny, icpieces, mpchess, kiwen-suwi, horsey, anarcandy, maestro, fantasy, celtic, spatial, caliente, california, cooke, shapes; held out for testing only: riohacha, kosal, tatiana. Unicode glyph piece styles: 10 (held-out: glyph:FreeSerif:hollow, glyph:FreeSerif:filled).

## Metrics (held-out synthetic test set, 600 pages)

| Group | Pages | Boards | Det. recall | Det. precision | Corner err px (mean/p95) | Square acc | Board exact | E2E board exact | Page OK |
|---|---|---|---|---|---|---|---|---|---|
| clean/seen | 100 | 302 | 100.00% | 100.00% | 0.53 / 0.90 | 98.42% | 57.95% | 57.28% | 51.00% |
| clean/heldout | 100 | 281 | 97.15% | 97.15% | 0.52 / 0.82 | 97.93% | 60.14% | 58.01% | 52.00% |
| photo/seen | 100 | 254 | 95.67% | 97.59% | 0.74 / 1.44 | 96.77% | 47.64% | 43.70% | 50.00% |
| photo/heldout | 100 | 274 | 95.62% | 95.62% | 0.74 / 1.27 | 95.84% | 45.62% | 37.59% | 40.00% |
| screenshot/seen | 100 | 100 | 100.00% | 99.01% | 0.52 / 0.81 | 99.86% | 93.00% | 90.00% | 90.00% |
| screenshot/heldout | 100 | 100 | 100.00% | 98.04% | 0.49 / 0.75 | 98.61% | 68.00% | 70.00% | 70.00% |
| clean/all | 200 | 583 | 98.63% | 98.63% | 0.53 / 0.83 | 98.18% | 59.01% | 57.63% | 51.50% |
| photo/all | 200 | 528 | 95.64% | 96.56% | 0.74 / 1.35 | 96.29% | 46.59% | 40.53% | 45.00% |
| screenshot/all | 200 | 200 | 100.00% | 98.52% | 0.50 / 0.78 | 99.23% | 80.50% | 80.00% | 80.00% |
| all | 600 | 1311 | 97.64% | 97.78% | 0.61 / 1.12 | 97.58% | 57.28% | 54.16% | 58.83% |

Targets:

| Target | Result | Required | Met |
|---|---|---|---|
| Detection recall (all groups) | 97.64% | >= 98.0% | **NO** |
| Square accuracy, clean scans | 98.18% | >= 99.7% | **NO** |
| Board exact match, clean scans | 59.01% | >= 95.0% | **NO** |
| Board exact match, phone photo sim. | 46.59% | >= 85.0% | **NO** |

See `training/REPORT.md` for definitions, timings and known weaknesses.
Reference implementation of the app-side steps: `training/reference_pipeline.py`.
