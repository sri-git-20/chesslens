# ChessLens architecture and contracts

This file is the shared contract between the app code (`app/`) and the
recognition training pipeline (`training/`). Change it only together with
the code on both sides.

## App layout (`app/lib/src/`)

| Folder | Responsibility |
| --- | --- |
| `app.dart`, `app_info.dart` | MaterialApp, routes, static app facts |
| `theme/` | Material 3 light, dark and true-black themes; board colours |
| `settings/` | `AppSettings` + `SettingsController` (Riverpod, shared_preferences) |
| `chess/` | Position helpers on top of `dartchess`: FEN parsing, legality report, castling inference, flip |
| `engine/` | `EngineService` around `multistockfish`; UCI parsing; full-network download |
| `board/` | Board widgets around `chessground`, board editor (Review screen) |
| `analysis/` | Analysis screen: eval bar, engine lines, move tree |
| `play/` | Play against the engine |
| `solve/` | Solve mode: user moves, engine checks, plays until mate or a draw |
| `collections/` | `Collection` and `Puzzle` models, sqflite repository, list and detail screens |
| `scan/` | Image input (camera, gallery, PDF), on-device recognition, diagram selection |
| `export/` | PGN building, Lichess link, board image, sharing |
| `report/` | Error log, crash detection, pre-filled bug-report email |

State management: Riverpod (`flutter_riverpod` 3.x). Storage: sqflite for
collections and puzzles, shared_preferences for settings, app documents
directory for images.

### Core flow

Every input path ends in the Review screen (`board/review_screen.dart`):

```
ReviewArgs {
  String boardFen;            // piece placement only, e.g. "8/8/8/4k3/8/8/4P3/4K3"
  List<double>? confidence;   // 64 values, index 0 = a8 ... 63 = h1 (FEN order)
  Side sideToMove;            // default Side.white
  Side orientation;           // side shown at the bottom, default Side.white
  Uint8List? sourceCrop;      // PNG of the original diagram, shown for comparison
  int? puzzleId;              // set when editing a saved puzzle
}
```

Review validates the position with `chess/` before enabling Analyze, Play
and Solve. **No position reaches Stockfish without passing that check**:
Stockfish 19 terminates its process on an illegal position.

### Data model

```
Collection { int id; String name; DateTime createdAt; DateTime updatedAt; }

Puzzle {
  int id; int collectionId;
  String fen;                 // full FEN: placement, side to move, castling, ep, clocks
  Side orientation;
  String? pageImagePath;      // page photo in app documents, may be deleted later
  String? cropImagePath;      // diagram crop in app documents
  int? pageNumber;            // PDF page or null
  int? indexOnPage;           // 1-based reading order on the page
  PuzzleStatus status;        // unsolved, solved, failed
  int attempts;
  String? notes;
  DateTime createdAt;
}
```

## Recognition models (`app/assets/models/`)

Three LiteRT (TFLite) models, all float32 input and output, grayscale input
computed as `(0.299 R + 0.587 G + 0.114 B) / 255` in `[0, 1]`.

"Board corners" always means the four outer corners of the 8x8 playing
area (not the printed frame or the coordinate labels), named by where they
appear in the image: TL, TR, BR, BL.

### 1. `detector.tflite`: find every diagram on a page

- Input `[1, 384, 384, 1]`. Letterbox: scale the page by
  `s = 384 / max(width, height)`, place it at the top-left (0, 0) and fill
  the rest with 1.0 (white).
- Output `[1, 96, 96, 9]` (stride 4).
  - Channel 0: board-centre heatmap after sigmoid.
  - Channels 1-8: offsets from the cell centre `((col + 0.5) * 4, (row + 0.5) * 4)`
    to the corners, in the order TL.x, TL.y, TR.x, TR.y, BR.x, BR.y, BL.x, BL.y,
    divided by 384.
- Decode: cells that are the maximum of their 3x3 neighbourhood with value
  at least 0.35 are boards. Corner = cell centre + offset * 384, then divided
  by `s` for original-image pixels.

### 2. `corners.tflite`: precise corners of one board

- Crop: from the coarse quad take the bounding-box centre `c` and side
  `L = 1.25 * max(bbox width, bbox height)`. Crop the square
  `[c - L/2, c + L/2]` from the original image (outside the image = white)
  and resize to 256x256.
- Input `[1, 256, 256, 1]`.
- Output `[1, 64, 64, 4]`: sigmoid heatmaps for TL, TR, BR, BL.
- Decode per channel: arg-max cell, refined by the value-weighted mean of its
  3x3 neighbourhood; crop pixel = `(x + 0.5) * 4`; map back to the original.

### 3. `squares.tflite`: read the 64 squares

- Input `[1, 256, 256, 1]`: the playing area warped so TL -> (0, 0),
  TR -> (256, 0), BR -> (256, 256), BL -> (0, 256).
- Output `[1, 8, 8, 13]`: softmax per square, `[0, row, col, class]` with
  row 0 at the top of the image and col 0 at the left.
- Classes: 0 empty, 1 wP, 2 wN, 3 wB, 4 wR, 5 wQ, 6 wK, 7 bP, 8 bN, 9 bB,
  10 bR, 11 bQ, 12 bK. "w" means a piece drawn as a white piece.

### After the models (app side)

1. Orientation: default White at the bottom. Flip when the evidence says
   Black is at the bottom (for example, white pawns mostly on the top half
   and the white king in the top two rows). The user can always flip.
2. Legality repair: if the position is illegal (kings, pawns on the first or
   last rank, side not to move in check), try the second most likely class
   on the least confident squares; otherwise flag them for the user.
3. Confidence below 0.85 on a square outlines it in amber in Review.

### Files

- `app/assets/models/{detector,corners,squares}.tflite`
- `app/assets/models/MODELS.md`: training date, data, metrics
- `app/test/fixtures/scan/`: sample images with `expected.json`
  (board quads and FENs) produced by the training pipeline
