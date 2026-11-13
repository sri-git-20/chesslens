"""Chess diagram rendering: book style (greyscale, hatching, frames,
coordinates) and screenshot style (coloured themes, highlights, anti-aliasing).

Coordinates returned in `BoardRender.quad` are continuous image coordinates:
(0, 0) is the top-left corner of the top-left pixel.
"""
from dataclasses import dataclass

import cv2
import numpy as np
from PIL import Image, ImageDraw

import fonts

_PARITY = (np.add.outer(np.arange(8), np.arange(8)) % 2 == 1)  # True = dark square


@dataclass
class BoardRender:
    img: np.ndarray      # HxWx3 uint8 RGB
    quad: np.ndarray     # 4x2 float, playing-area corners TL, TR, BR, BL
    labels: np.ndarray   # 8x8 class ids as drawn (row 0 = image top)
    flipped: bool


def orient(placement, flipped):
    """Black at the bottom = the board is turned by 180 degrees."""
    return placement[::-1, ::-1].copy() if flipped else placement.copy()


# --------------------------------------------------------------------------
# styles
# --------------------------------------------------------------------------
def sample_book_style(rng, lib, holdout):
    t = rng.random()
    if t < 0.35:
        dark = ("solid", int(rng.integers(120, 226)))
    elif t < 0.75:
        ang = float(rng.choice([45, 45, -45, 0, 90, 30, 60, rng.uniform(0, 180)]))
        dark = ("hatch", ang, float(rng.uniform(0.07, 0.22)), float(rng.uniform(0.02, 0.07)),
                int(rng.integers(0, 110)), bool(rng.random() < 0.12))
    else:
        dark = ("dots", float(rng.uniform(0.08, 0.2)), float(rng.uniform(0.012, 0.045)),
                int(rng.integers(0, 90)), bool(rng.random() < 0.5))
    use_glyph = rng.random() < 0.45
    ps = lib.pick(rng, holdout, "glyph" if use_glyph else "svg")
    return dict(
        kind="book", dark=dark, light=int(rng.choice([255, 255, 255, 250, 245])),
        ft_frac=float(rng.uniform(0.015, 0.09)), gap_frac=float(rng.choice([0, 0, 0, 0.04, 0.08, 0.14])),
        double=bool(rng.random() < 0.15), coords=bool(rng.random() < 0.5),
        coords_far=bool(rng.random() < 0.15), grid=bool(rng.random() < 0.15),
        frame=bool(rng.random() < 0.93), pad_frac=float(rng.uniform(0.02, 0.3)),
        piece=ps, piece_scale=float(rng.uniform(0.8, 0.98)),
        halo=float(rng.choice([0, 0.6, 1.0])) if dark[0] != "solid" else float(rng.choice([0, 0, 0.5])),
        hollow_p=float(rng.choice([0, 0.3, 0.8])) if ps.hollow is not None else 0.0,
        font=fonts.pick(rng, "sans" if rng.random() < 0.5 else "serif"),
        invert=bool(rng.random() < 0.03),
    )


THEMES = [  # (light, dark)
    ((240, 217, 181), (181, 136, 99)),    # lichess brown
    ((222, 227, 230), (140, 162, 173)),   # blue
    ((238, 238, 210), (118, 150, 86)),    # green
    ((204, 204, 204), (136, 136, 136)),   # grey
    ((234, 233, 210), (75, 115, 153)),    # chess.com blue
    ((241, 217, 192), (169, 122, 101)),
    ((255, 255, 255), (170, 170, 170)),
    ((225, 225, 200), (145, 130, 95)),
]


def sample_screen_style(rng, lib, holdout):
    if rng.random() < 0.85:
        light, dark = THEMES[int(rng.integers(len(THEMES)))]
    else:  # random colours
        h = rng.uniform(0, 180)
        hsv = np.array([[[h, rng.uniform(20, 120), rng.uniform(200, 250)]],
                        [[h, rng.uniform(60, 180), rng.uniform(90, 190)]]], np.uint8)
        rgb = cv2.cvtColor(hsv, cv2.COLOR_HSV2RGB)
        light, dark = tuple(int(v) for v in rgb[0, 0]), tuple(int(v) for v in rgb[1, 0])
    if rng.random() < 0.05:
        light, dark = dark, light
    ps = lib.pick(rng, holdout, "glyph" if rng.random() < 0.08 else "svg")
    return dict(
        kind="screen", light=light, dark=dark, piece=ps,
        piece_scale=float(rng.uniform(0.9, 1.0)),
        highlight=bool(rng.random() < 0.4),
        hl_color=[(155, 199, 0), (205, 210, 106), (255, 255, 51), (20, 85, 30)][int(rng.integers(4))],
        coords=str(rng.choice(["inside", "inside", "outside", "none"])),
        border=int(rng.choice([0, 0, 0, 1, 2, 4])),
        font=fonts.pick(rng, "sans"),
        dots=bool(rng.random() < 0.08),
    )


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
def _blend_piece(canvas, piece, px, py, gray, halo):
    """Alpha-blend an RGBA uint8 piece into a float32 canvas at (px, py)."""
    ph, pw = piece.shape[:2]
    x0, y0 = max(px, 0), max(py, 0)
    x1, y1 = min(px + pw, canvas.shape[1]), min(py + ph, canvas.shape[0])
    if x1 <= x0 or y1 <= y0:
        return
    p = piece[y0 - py:y1 - py, x0 - px:x1 - px].astype(np.float32)
    a = p[..., 3:4] / 255.0
    rgb = p[..., :3]
    if gray:
        g = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
        rgb = np.repeat(g[..., None], 3, 2)
    roi = canvas[y0:y1, x0:x1]
    if halo > 0:  # white halo around the piece, as printed on hatched squares
        k = max(1, int(round(pw / 16)))
        ha = cv2.dilate(a[..., 0], cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * k + 1, 2 * k + 1)))
        ha = cv2.GaussianBlur(ha, (0, 0), 0.6)[..., None] * halo
        roi[:] = roi * (1 - ha) + 255.0 * ha
    roi[:] = roi * (1 - a) + rgb * a


def _draw_pieces(canvas, x0, y0, sq, labels, style, rng, scale, gray, halo, hollow_p):
    ps = style["piece"] if isinstance(style, dict) else style
    for r in range(8):
        for c in range(8):
            cls = int(labels[r, c])
            if cls == 0:
                continue
            imgs = ps.imgs
            if ps.hollow is not None and cls <= 6 and rng.random() < hollow_p:
                imgs = ps.hollow
            s = int(round(sq * scale * rng.uniform(0.97, 1.03)))
            s = max(4, s)
            piece = cv2.resize(imgs[cls - 1], (s, s), interpolation=cv2.INTER_AREA)
            dx, dy = rng.uniform(-0.03, 0.03) * sq, rng.uniform(-0.02, 0.03) * sq
            px = int(round(x0 + c * sq + (sq - s) / 2 + dx))
            py = int(round(y0 + r * sq + (sq - s) / 2 + dy))
            _blend_piece(canvas, piece, px, py, gray, halo)


def _hatch(B, sq, angle, sp_frac, w_frac, ink, cross):
    pat = np.full((B, B), 255, np.uint8)
    sp = max(3.0, sp_frac * sq)
    wd = max(1, int(round(w_frac * sq)))
    for ang in ([angle, angle + 90] if cross else [angle]):
        t = np.deg2rad(ang)
        d = np.array([np.cos(t), np.sin(t)])
        n = np.array([-np.sin(t), np.cos(t)])
        c = np.array([B / 2.0, B / 2.0])
        m = int(B * 0.75 / sp) + 1
        for k in range(-m, m + 1):
            p0 = c + n * k * sp - d * B
            p1 = c + n * k * sp + d * B
            cv2.line(pat, tuple(int(v * 16) for v in p0), tuple(int(v * 16) for v in p1),
                     int(ink), wd, cv2.LINE_AA, 4)
    return pat


def _dots(B, sq, sp_frac, r_frac, ink, stagger):
    st = max(3, int(round(sp_frac * sq)))
    tile = np.full((st * 2, st * 2), 255, np.uint8)
    r = max(0.6, r_frac * sq)
    pts = [(st / 2, st / 2), (st * 1.5, st * 1.5)] if stagger else \
          [(st / 2, st / 2), (st * 1.5, st / 2), (st / 2, st * 1.5), (st * 1.5, st * 1.5)]
    for x, y in pts:
        cv2.circle(tile, (int(x * 16), int(y * 16)), int(r * 16), int(ink), -1, cv2.LINE_AA, 4)
    reps = B // (2 * st) + 1
    return np.tile(tile, (reps, reps))[:B, :B]


def _text(img_u8, items, font_path, size, fill):
    """Draw [(x, y, text)] centred at (x, y) on an RGB uint8 image."""
    im = Image.fromarray(img_u8)
    d = ImageDraw.Draw(im)
    f = fonts.load(font_path, size)
    for x, y, s in items:
        d.text((x, y), s, font=f, fill=fill, anchor="mm")
    return np.asarray(im).copy()


# --------------------------------------------------------------------------
# book board
# --------------------------------------------------------------------------
def render_book_board(rng, placement, style, sq, flipped):
    labels = orient(placement, flipped)
    B = 8 * sq
    ft = max(1, min(6, int(round(style["ft_frac"] * sq)))) if style["frame"] else 0
    gap = int(round(style["gap_frac"] * sq)) if style["frame"] else 0
    dbl = (ft + 3) if (style["double"] and style["frame"]) else 0
    cm = int(round(0.55 * sq)) if style["coords"] else 0
    pad = max(1, int(round(style["pad_frac"] * sq)))
    o = pad + cm + dbl + ft + gap
    S = B + 2 * o
    canvas = np.full((S, S), 255.0, np.float32)
    # frame
    f0 = pad + cm
    if style["frame"]:
        if dbl:
            e = f0 + 0
            cv2.rectangle(canvas, (e - dbl + 1, e - dbl + 1), (S - e + dbl - 2, S - e + dbl - 2), 40.0, 1)
        canvas[f0:S - f0, f0:S - f0] = 0.0
        canvas[f0 + ft:S - f0 - ft, f0 + ft:S - f0 - ft] = 255.0
    # board
    light = float(style["light"])
    dk = style["dark"]
    if dk[0] == "solid":
        pat = np.full((B, B), float(dk[1]), np.float32)
    elif dk[0] == "hatch":
        pat = _hatch(B, sq, dk[1], dk[2], dk[3], dk[4], dk[5]).astype(np.float32)
    else:
        pat = _dots(B, sq, dk[1], dk[2], dk[3], dk[4]).astype(np.float32)
    par = _PARITY ^ style["invert"]
    mask = np.kron(par, np.ones((sq, sq), bool))
    brd = np.where(mask, pat, light)
    if style["grid"]:
        for i in range(1, 8):
            brd[i * sq, :] = np.minimum(brd[i * sq, :], 150)
            brd[:, i * sq] = np.minimum(brd[:, i * sq], 150)
    canvas[o:o + B, o:o + B] = brd
    # pieces (greyscale)
    rgb = np.repeat(canvas[..., None], 3, 2)
    _draw_pieces(rgb, o, o, sq, labels, style, rng, style["piece_scale"], True,
                 style["halo"], style["hollow_p"])
    img = np.clip(rgb, 0, 255).astype(np.uint8)
    # coordinates outside the frame
    if style["coords"]:
        files = "abcdefgh"[::-1] if flipped else "abcdefgh"
        ranks = "12345678" if flipped else "87654321"
        fs = max(6, int(round(0.34 * sq)))
        items = []
        mid = pad + cm // 2
        for i in range(8):
            c = o + i * sq + sq / 2
            items.append((c, S - mid, files[i]))
            items.append((mid, c, ranks[i]))
            if style["coords_far"]:
                items.append((c, mid, files[i]))
                items.append((S - mid, c, ranks[i]))
        img = _text(img, items, style["font"], fs, (20, 20, 20))
    quad = np.array([[o, o], [o + B, o], [o + B, o + B], [o, o + B]], np.float64)
    return BoardRender(img, quad, labels, flipped)


# --------------------------------------------------------------------------
# screenshot board
# --------------------------------------------------------------------------
def render_screen_board(rng, placement, style, sq, flipped):
    labels = orient(placement, flipped)
    B = 8 * sq
    cm = int(round(0.42 * sq)) if style["coords"] == "outside" else 0
    bd = style["border"]
    o = cm + bd
    S = B + 2 * o
    light, dark = np.array(style["light"], np.float32), np.array(style["dark"], np.float32)
    canvas = np.zeros((S, S, 3), np.float32)
    bg = np.clip(dark * 0.6 + 20, 0, 255) if bd or cm else dark
    canvas[:] = bg
    mask = np.kron(_PARITY, np.ones((sq, sq), bool))
    brd = np.where(mask[..., None], dark, light)
    canvas[o:o + B, o:o + B] = brd
    if style["highlight"]:
        hl = np.array(style["hl_color"], np.float32)
        for _ in range(2):
            r, c = int(rng.integers(8)), int(rng.integers(8))
            roi = canvas[o + r * sq:o + (r + 1) * sq, o + c * sq:o + (c + 1) * sq]
            roi[:] = roi * 0.6 + hl * 0.4
    _draw_pieces(canvas, o, o, sq, labels, style, rng, style["piece_scale"], False, 0.0, 0.0)
    if style["dots"]:  # legal-move hint dots
        for _ in range(int(rng.integers(1, 5))):
            r, c = int(rng.integers(8)), int(rng.integers(8))
            cv2.circle(canvas, (int(o + (c + .5) * sq), int(o + (r + .5) * sq)),
                       max(2, sq // 6), (80, 80, 80), -1, cv2.LINE_AA)
    img = np.clip(canvas, 0, 255).astype(np.uint8)
    files = "abcdefgh"[::-1] if flipped else "abcdefgh"
    ranks = "12345678" if flipped else "87654321"
    fs = max(6, int(round(0.2 * sq)))
    items_light, items_dark = [], []
    if style["coords"] == "inside":
        for i in range(8):
            # rank digit: top-left of left column; file letter: bottom-right of bottom row
            for (x, y, s, r, c) in [(o + 0.12 * sq, o + i * sq + 0.15 * sq, ranks[i], i, 0),
                                    (o + i * sq + 0.88 * sq, o + B - 0.15 * sq, files[i], 7, i)]:
                (items_dark if _PARITY[r, c] else items_light).append((x, y, s))
        # text colour = colour of the opposite square
        img = _text(img, items_dark, style["font"], fs, tuple(int(v) for v in light))
        img = _text(img, items_light, style["font"], fs, tuple(int(v) for v in dark))
    elif style["coords"] == "outside":
        items = []
        for i in range(8):
            c = o + i * sq + sq / 2
            items.append((c, S - cm / 2, files[i]))
            items.append((cm / 2, c, ranks[i]))
        img = _text(img, items, style["font"], max(6, int(0.3 * sq)), (225, 225, 225))
    quad = np.array([[o, o], [o + B, o], [o + B, o + B], [o, o + B]], np.float64)
    return BoardRender(img, quad, labels, flipped)
