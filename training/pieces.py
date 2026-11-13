"""Piece images: Lichess SVG sets (rasterised with cairosvg) and Unicode chess
glyphs drawn with whatever fonts are installed.

Every style stores 12 RGBA uint8 images of size PIECE_PX x PIECE_PX in the class
order wP wN wB wR wQ wK bP bN bB bR bQ bK (class id = index + 1).
"""
import os
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor

import cv2
import numpy as np
from PIL import Image, ImageDraw

import fonts

PIECE_PX = 128
CODES = ["wP", "wN", "wB", "wR", "wQ", "wK", "bP", "bN", "bB", "bR", "bQ", "bK"]
URL = ("https://raw.githubusercontent.com/lichess-org/lila/master/"
       "public/piece/{set}/{code}.svg")

# About 30 candidates; sets that 404 are skipped. "letter" and "disguised"
# are deliberately absent (not recognisable chess pieces).
CANDIDATE_SETS = [
    "merida", "alpha", "leipzig", "cburnett", "pirouetti", "chessnut", "chess7",
    "reillycraig", "companion", "riohacha", "kosal", "fresca", "cardinal",
    "gioco", "tatiana", "staunty", "governor", "dubrovny", "icpieces",
    "mpchess", "kiwen-suwi", "horsey", "anarcandy", "maestro", "fantasy",
    "celtic", "spatial", "caliente", "california", "cooke", "monarchy", "shapes",
]
# Sets kept out of training completely (first 3 that exist are used).
HOLDOUT_PREFERRED = ["tatiana", "kosal", "riohacha", "gioco", "staunty"]
# Never held out.
ALWAYS_TRAIN = ["merida", "alpha", "leipzig", "cburnett"]

# Unicode order K Q R B N P; our order is P N B R Q K.
_W = {"P": "♙", "N": "♘", "B": "♗", "R": "♖", "Q": "♕", "K": "♔"}
_B = {"P": "♟", "N": "♞", "B": "♝", "R": "♜", "Q": "♛", "K": "♚"}
_ORDER = "PNBRQK"


class PieceStyle:
    def __init__(self, name, kind, imgs, holdout=False, hollow=None):
        self.name = name
        self.kind = kind          # "svg" or "glyph"
        self.imgs = imgs          # 12 x RGBA uint8
        self.holdout = holdout
        self.hollow = hollow      # optional 12 images, white pieces see-through


class PieceLibrary:
    def __init__(self, styles):
        self.styles = styles

    def pick(self, rng, holdout=False, kind=None):
        cand = [s for s in self.styles if s.holdout == holdout
                and (kind is None or s.kind == kind)]
        if not cand:
            cand = [s for s in self.styles if kind is None or s.kind == kind] or self.styles
        return cand[int(rng.integers(len(cand)))]

    def summary(self):
        tr = [s.name for s in self.styles if not s.holdout]
        ho = [s.name for s in self.styles if s.holdout]
        return tr, ho


# --------------------------------------------------------------------------
# SVG sets
# --------------------------------------------------------------------------
def _fetch(args):
    cache_dir, name, code = args
    path = os.path.join(cache_dir, name, code + ".svg")
    if os.path.exists(path) and os.path.getsize(path) > 50:
        return name, code, open(path, "rb").read()
    url = URL.format(set=name, code=code)
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=30) as r:
                data = r.read()
            if b"<svg" in data and b"</svg>" in data:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "wb") as f:
                    f.write(data)
                return name, code, data
            return name, code, None
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return name, code, None
        except Exception:
            pass
    return name, code, None


def download_sets(cache_dir, names=CANDIDATE_SETS):
    """Returns {set: {code: svg bytes}} for complete sets only."""
    jobs = [(cache_dir, n, c) for n in names for c in CODES]
    got = {}
    with ThreadPoolExecutor(8) as ex:
        for name, code, data in ex.map(_fetch, jobs):
            got.setdefault(name, {})[code] = data
    ok = {}
    for n in names:
        d = got.get(n, {})
        if all(d.get(c) for c in CODES):
            ok[n] = d
        else:
            have = sum(1 for c in CODES if d.get(c))
            print(f"  piece set {n}: skipped ({have}/12 files available)")
    return ok


def rasterize(svg_bytes, size=PIECE_PX):
    import cairosvg
    png = cairosvg.svg2png(bytestring=svg_bytes, output_width=size, output_height=size)
    im = cv2.imdecode(np.frombuffer(png, np.uint8), cv2.IMREAD_UNCHANGED)
    if im.ndim == 2:
        im = cv2.cvtColor(im, cv2.COLOR_GRAY2BGRA)
    elif im.shape[2] == 3:
        im = cv2.cvtColor(im, cv2.COLOR_BGR2BGRA)
    return cv2.cvtColor(im, cv2.COLOR_BGRA2RGBA)


def make_hollow(imgs):
    """White pieces drawn as outlines only: interior (bright) becomes transparent."""
    out = []
    for i, im in enumerate(imgs):
        if i >= 6:
            out.append(im)
            continue
        f = im.astype(np.float32)
        g = 0.299 * f[..., 0] + 0.587 * f[..., 1] + 0.114 * f[..., 2]
        a = f[..., 3] / 255.0 * np.clip((235.0 - g) / 120.0, 0, 1)
        o = np.zeros_like(im)
        o[..., :3] = np.clip(g, 0, 255).astype(np.uint8)[..., None]
        o[..., 3] = np.clip(a * 255, 0, 255).astype(np.uint8)
        out.append(o)
    return out


# --------------------------------------------------------------------------
# Unicode glyph pieces
# --------------------------------------------------------------------------
def _glyph_mask(font, ch, canvas=420, origin=(100, 310)):
    im = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(im).text(origin, ch, font=font, fill=255, anchor="ls")
    return np.asarray(im)


def font_has_chess(path):
    try:
        f = fonts.load(path, 200)
        k, kw = _glyph_mask(f, _B["K"]), _glyph_mask(f, _W["K"])
        tofu = _glyph_mask(f, "\U0010FFFF")
        if k.max() == 0 or kw.max() == 0:
            return False
        if np.array_equal(k, tofu) or np.array_equal(k, kw):
            return False
        return True
    except Exception:
        return False


def build_glyph_styles(path, holdout=False):
    """Two styles per font: white = hollow outline, or white = outline + white
    fill. Black is always the filled glyph."""
    f = fonts.load(path, 200)
    mo = {p: _glyph_mask(f, _W[p]) for p in _ORDER}   # outline glyphs
    mf = {p: _glyph_mask(f, _B[p]) for p in _ORDER}   # filled glyphs
    allm = list(mo.values()) + list(mf.values())
    ys, xs = np.where(np.max(np.stack(allm), 0) > 40)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    sc = 0.92 * PIECE_PX / max(x1 - x0, y1 - y0)
    w, h = max(1, round((x1 - x0) * sc)), max(1, round((y1 - y0) * sc))
    ox, oy = (PIECE_PX - w) // 2, (PIECE_PX - h) // 2

    def fit(m):
        c = cv2.resize(m[y0:y1, x0:x1], (w, h), interpolation=cv2.INTER_AREA)
        out = np.zeros((PIECE_PX, PIECE_PX), np.uint8)
        out[oy:oy + h, ox:ox + w] = c
        return out.astype(np.float32) / 255.0

    def rgba(rgb, a):
        o = np.zeros((PIECE_PX, PIECE_PX, 4), np.uint8)
        o[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)[..., None]
        o[..., 3] = np.clip(a * 255, 0, 255).astype(np.uint8)
        return o

    hollow, filled = [], []
    for p in _ORDER:
        outline, fill = fit(mo[p]), fit(mf[p])
        hollow.append(rgba(np.zeros((PIECE_PX, PIECE_PX), np.float32), outline))
        a = np.maximum(outline, fill)
        filled.append(rgba(255.0 * (1 - outline), a))
    blacks = [rgba(np.zeros((PIECE_PX, PIECE_PX), np.float32), fit(mf[p])) for p in _ORDER]
    base = os.path.splitext(os.path.basename(path))[0]
    return [PieceStyle(f"glyph:{base}:hollow", "glyph", hollow + blacks, holdout),
            PieceStyle(f"glyph:{base}:filled", "glyph", filled + blacks, holdout)]


# --------------------------------------------------------------------------
def build_library(cache_dir, log=print, min_svg_sets=6):
    styles = []
    if os.environ.get("CL_GLYPH_ONLY"):   # local testing without network
        sets = {}
        min_svg_sets = 0
    else:
        sets = download_sets(cache_dir)
    names = list(sets.keys())
    if len(names) < min_svg_sets:
        raise RuntimeError(f"only {len(names)} piece sets available: {names}")
    holdout = [n for n in HOLDOUT_PREFERRED if n in names][:3]
    if len(holdout) < 2:
        extra = [n for n in names if n not in ALWAYS_TRAIN and n not in holdout]
        holdout += extra[:3 - len(holdout)]
    for n in names:
        try:
            imgs = [rasterize(sets[n][c]) for c in CODES]
        except Exception as e:  # rasterisation failure: skip this set
            log(f"  piece set {n}: rasterize failed: {e!r}")
            continue
        styles.append(PieceStyle(n, "svg", imgs, n in holdout, make_hollow(imgs)))
    # Unicode glyph fonts. Hold out one font if there are at least three.
    gfonts = [p for p in fonts.GLYPH_CANDIDATES if font_has_chess(p)]
    ho_font = None
    if len(gfonts) >= 3:
        pref = [p for p in gfonts if "freeserif" in p.lower()] or gfonts[-1:]
        ho_font = pref[0]
    for p in gfonts:
        styles += build_glyph_styles(p, holdout=(p == ho_font))
    log(f"  glyph fonts: {[os.path.basename(p) for p in gfonts]} (held out: "
        f"{os.path.basename(ho_font) if ho_font else None})")
    lib = PieceLibrary(styles)
    tr, ho = lib.summary()
    log(f"  piece styles: {len(tr)} train {tr}")
    log(f"  piece styles: {len(ho)} held-out {ho}")
    return lib
