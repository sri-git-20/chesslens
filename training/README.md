# ChessLens recognition training

Trains and exports the three models described in `docs/ARCHITECTURE.md`
("Recognition models"): `detector` (find diagrams on a page), `corners` (precise
board corners) and `squares` (read the 64 squares). Everything runs in GitHub
Actions (`.github/workflows/train.yml`); the code needs TensorFlow, cairosvg,
python-chess, OpenCV and Pillow (`requirements.txt`).

## Running it

* Push to `m2-training` with changes under `training/`: runs a **smoke** run
  (tiny data, about 1 min per model) to shake out errors. Put `[full]` in the head
  commit message, or use *Run workflow* with `mode=full`, for the real run
  (about 3 h on `ubuntu-latest`). Full runs commit the outputs back to the branch.
* Locally (needs the same dependencies and network for the piece sets):

```
cd training
python gen_data.py --out work/data --pages 10000            # synthetic data
python train.py --model detector --data work/data --minutes 45
python train.py --model corners  --data work/data --minutes 35
python train.py --model squares  --data work/data --minutes 70 --batch 64
python export_tflite.py --weights work/models --data work/data --out ../app/assets/models
python evaluate.py --models ../app/assets/models --pages 100
python make_fixtures.py
python write_docs.py
```

`localtest.py` renders a few samples with glyph pieces only (no network, no TF) and
writes previews to `/tmp/prev`; `CL_GLYPH_ONLY=1` makes `gen_data.py` skip the SVG sets.

## Files

| File | Purpose |
|---|---|
| `pieces.py` | Lichess SVG sets (downloaded, rasterised with cairosvg; 3 sets are held out for testing) and Unicode figurine glyphs from installed fonts (white = outline or outline+fill, black = filled; one font held out) |
| `positions.py` | random legal games (python-chess), thinned and sparse endgame-like positions |
| `boards.py` | book diagrams (grey / hatched / dotted dark squares, frames, coordinates, halos) and screenshot boards (themes, last-move highlight, coordinates, move dots) |
| `pages.py` | book pages (text in several fonts, tables and figures as negatives, 1-8 diagrams in 1-3 columns, captions, paper tint), single-diagram crops, phone/desktop screenshots |
| `camera.py` | phone-photo simulation (rotation, perspective, paper curl, shadows, blur, noise, JPEG), screenshot rescaling, clean scans |
| `synth.py` | sample generation and the training targets (detector heat-map + offsets, corner heat-maps) |
| `reference_pipeline.py` | **the app-side steps**, written to be ported to Dart; also the single source of the crop/warp geometry used to build training data |
| `models.py` | Keras definitions (fully convolutional, regular convolutions, FPN-style decoders) |
| `train.py` | time-budgeted training with a time-based cosine schedule |
| `export_tflite.py` | TFLite export (float32 I/O, float16 weights) and verification against Keras |
| `evaluate.py` | metrics per group (clean / photo / screenshot x seen / held-out piece styles) |
| `make_fixtures.py`, `write_docs.py` | fixtures for the app tests, `MODELS.md` and `REPORT.md` |

## Conventions that matter for the app

* Coordinates are continuous pixel coordinates (pixel edges at integers).
* Quads: TL, TR, BR, BL by position in the image.
* The squares labels are "as drawn": orientation does not change them.
* The warp for the squares model and the crop for the corners model are bilinear,
  preceded by an area-average shrink when the source region is more than 1.5x
  larger than 256 px (see `warp_region`); use the same in the app.
