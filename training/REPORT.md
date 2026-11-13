# Training report (2026-11-13)

> SMOKE RUN: tiny data and training, numbers are meaningless.

Everything below was produced by the CI job; numbers come from `work/metrics.json` of that run.

## Result vs targets

| Target | Result | Required | Met |
|---|---|---|---|
| Detection recall (all groups) | 90.58% | >= 98.0% | **NO** |
| Square accuracy, clean scans | 98.82% | >= 99.7% | **NO** |
| Board exact match, clean scans | 73.50% | >= 95.0% | **NO** |
| Board exact match, phone photo sim. | 62.32% | >= 85.0% | **NO** |

## Full metrics

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
| squares | 1,152,245 | 235 min | 944,640 | 0.0077 |

## Timings

- generate_data: 26.2 min
- train_squares: 235.5 min
- export: 0.1 min
- evaluate: 2.0 min
- fixtures: 0.1 min

## Weakest groups (by page accuracy)

- `photo/heldout`: page OK 53.00%, board exact 52.80%, detection recall 85.66%, false positives 32
- `clean/heldout`: page OK 55.00%, board exact 65.86%, detection recall 88.62%, false positives 31
- `clean/all`: page OK 60.50%, board exact 73.50%, detection recall 91.28%, false positives 48

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
