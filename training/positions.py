"""Random chess positions as 8x8 arrays of class ids (row 0 = rank 8, white
orientation: col 0 = a-file). Class ids follow config.CLASS_NAMES."""
import numpy as np

try:
    import chess
except ImportError:  # local quick checks only
    chess = None

_TYPE = {1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6}  # python-chess piece_type == our id


def _from_board(b):
    arr = np.zeros((8, 8), np.int64)
    for sq, p in b.piece_map().items():
        r, f = 7 - chess.square_rank(sq), chess.square_file(sq)
        arr[r, f] = p.piece_type + (0 if p.color == chess.WHITE else 6)
    return arr


def _random_game(rng, plies):
    b = chess.Board()
    for _ in range(plies):
        moves = list(b.legal_moves)
        if not moves:
            break
        if rng.random() < 0.3:  # bias towards captures: thins the board out
            caps = [m for m in moves if b.is_capture(m)]
            if caps:
                moves = caps
        b.push(moves[int(rng.integers(len(moves)))])
    return b


def _sparse(rng):
    """Kings plus a few random pieces (endgame-like, puzzle-like)."""
    arr = np.zeros((8, 8), np.int64)
    squares = [(r, c) for r in range(8) for c in range(8)]
    rng.shuffle(squares)

    def free():
        return squares.pop()
    wk = free()
    arr[wk] = 6
    while True:
        bk = free()
        if max(abs(bk[0] - wk[0]), abs(bk[1] - wk[1])) > 1:
            arr[bk] = 12
            break
        squares.insert(0, bk)
    n = int(rng.integers(0, 12))
    for _ in range(n):
        r, c = free()
        color = int(rng.integers(2))
        t = int(rng.choice([1, 1, 1, 2, 3, 4, 5], p=[.18, .18, .14, .14, .14, .14, .08]))
        if t == 1 and r in (0, 7):
            t = int(rng.choice([2, 3, 4]))
        arr[r, c] = t + 6 * color
    return arr


def _thin(rng, arr):
    arr = arr.copy()
    for r, c in zip(*np.nonzero(arr)):
        if arr[r, c] not in (6, 12) and rng.random() < 0.35:
            arr[r, c] = 0
    return arr


def random_position(rng):
    u = rng.random()
    if chess is None:
        return _sparse(rng)
    if u < 0.55:
        return _from_board(_random_game(rng, int(rng.integers(10, 81))))
    if u < 0.65:
        return _thin(rng, _from_board(_random_game(rng, int(rng.integers(20, 81)))))
    if u < 0.97:
        return _sparse(rng)
    # a few completely random "scrambles" for rare piece/square combinations
    arr = np.zeros((8, 8), np.int64)
    for _ in range(int(rng.integers(8, 30))):
        arr[int(rng.integers(8)), int(rng.integers(8))] = int(rng.integers(1, 13))
    return arr
