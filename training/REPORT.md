# Training report (2026-11-13)

Everything below was produced by the CI job; numbers come from `work/metrics.json` of that run.

## Result vs targets

| Target | Result | Required | Met |
|---|---|---|---|
| Detection recall (all groups) | 97.64% | >= 98.0% | **NO** |
| Square accuracy, clean scans | 98.18% | >= 99.7% | **NO** |
| Board exact match, clean scans | 59.01% | >= 95.0% | **NO** |
| Board exact match, phone photo sim. | 46.59% | >= 85.0% | **NO** |

## Full metrics

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
| detector | 687,733 | 55 min | 115,200 | 0.3828 |
| corners | 785,060 | 30 min | 103,680 | 6.7759 |
| squares | 886,269 | 65 min | 230,400 | 0.0282 |

## Timings

- generate_data: 6.7 min
- train_detector: 55.1 min
- train_corners: 30.2 min
- train_squares: 65.2 min
- export: 0.2 min
- evaluate: 1.3 min
- fixtures: 0.1 min

## Weakest groups (by page accuracy)

- `photo/heldout`: page OK 40.00%, board exact 45.62%, detection recall 95.62%, false positives 12
- `photo/all`: page OK 45.00%, board exact 46.59%, detection recall 95.64%, false positives 18
- `photo/seen`: page OK 50.00%, board exact 47.64%, detection recall 95.67%, false positives 6

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
