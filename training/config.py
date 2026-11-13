"""Shared constants. They mirror the "Recognition models" contract in
docs/ARCHITECTURE.md and must not change without changing the app."""

DET_SIZE = 384      # detector input is 384x384x1
DET_OUT = 96        # detector output is 96x96x9 (stride 4)
DET_STRIDE = 4
DET_THRESHOLD = 0.35
COR_SIZE = 256      # corners input is 256x256x1
COR_OUT = 64        # corners output is 64x64x4 (stride 4)
COR_STRIDE = 4
COR_CROP_FACTOR = 1.25
SQ_SIZE = 256       # squares input is 256x256x1, output 8x8x13

# Class order of the squares model. "w" = drawn as a white piece.
CLASS_NAMES = ["empty", "wP", "wN", "wB", "wR", "wQ", "wK",
               "bP", "bN", "bB", "bR", "bQ", "bK"]
FEN_CHARS = ["", "P", "N", "B", "R", "Q", "K", "p", "n", "b", "r", "q", "k"]


def labels_to_fen(labels):
    """8x8 array of class ids (row 0 = top of the image) -> FEN placement."""
    ranks = []
    for r in range(8):
        s, empty = "", 0
        for c in range(8):
            k = int(labels[r][c])
            if k == 0:
                empty += 1
            else:
                if empty:
                    s += str(empty)
                    empty = 0
                s += FEN_CHARS[k]
        if empty:
            s += str(empty)
        ranks.append(s)
    return "/".join(ranks)
