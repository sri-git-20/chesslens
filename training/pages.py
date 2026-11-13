"""Page composition: book pages (text + 1-8 diagrams in 1-3 columns), single
diagram crops, screenshot-like images and text-only negatives.

All functions return `Page(img RGB uint8, boards=[(quad, labels, flipped)])`
with quads in continuous pixel coordinates.
"""
from dataclasses import dataclass, field

import cv2
import numpy as np
from PIL import Image, ImageDraw

import fonts
import boards as B
from positions import random_position

WORDS = ("the of and to in is that it was for on are as with his they at be this from have or by one "
         "had not but what all were when we there can an your which their said if do will each about "
         "how up out them then she many some so these would other into has more her two like him see "
         "time could no make than first been its who now people my made over did down only way find "
         "use may water long little very after words called just where most know white black king "
         "queen rook bishop knight pawn move position player game endgame opening attack defence "
         "square file rank diagonal check mate stalemate sacrifice material advantage control centre "
         "tempo threat variation line analysis study composition solution key").split()
CAPTIONS = ["White to move", "Black to move", "White to play", "Black to play", "White to move and win",
            "Black to play and draw", "Mate in two", "Mate in 3", "White mates in 2", "Draw", "Win",
            "Position after 14...Qxd5", "Solution on page 212", "After 23.Rxe6"]


@dataclass
class Page:
    img: np.ndarray
    boards: list = field(default_factory=list)   # (quad 4x2, labels 8x8, flipped)
    kind: str = ""


def _sentence(rng, n):
    return " ".join(WORDS[int(rng.integers(len(WORDS)))] for _ in range(n))


def _notation(rng):
    files, pieces = "abcdefgh", ["", "", "N", "B", "R", "Q", "K"]
    out = []
    for i in range(int(rng.integers(3, 9))):
        mv = []
        for _ in range(2):
            mv.append(pieces[int(rng.integers(7))] + files[int(rng.integers(8))] + str(int(rng.integers(1, 9))))
        out.append(f"{i + 1}. {mv[0]} {mv[1]}")
    return " ".join(out)


def _paragraph(rng, d, font, x, y, width, nlines, lh, ink, max_y):
    for li in range(nlines):
        if y + lh > max_y:
            break
        line, w = "", 0
        indent = int(font.size * 1.5) if li == 0 and rng.random() < 0.5 else 0
        words = []
        target = width - indent
        while True:
            wd = _notation(rng) if rng.random() < 0.04 else WORDS[int(rng.integers(len(WORDS)))]
            if rng.random() < 0.06:
                wd = wd.capitalize()
            cand = " ".join(words + [wd])
            if font.getlength(cand) > target:
                break
            words.append(wd)
            if len(words) > 40:
                break
        d.text((x + indent, y), " ".join(words), font=font, fill=(ink, ink, ink))
        y += lh
    return y


def _table(rng, d, font, x, y, w, max_y):
    rows, cols = int(rng.integers(3, 8)), int(rng.integers(2, 6))
    rh = int(font.size * 1.6)
    if y + rows * rh > max_y:
        return y
    cw = w / cols
    for r in range(rows + 1):
        d.line([(x, y + r * rh), (x + w, y + r * rh)], fill=(40, 40, 40), width=1)
    for c in range(cols + 1):
        d.line([(x + c * cw, y), (x + c * cw, y + rows * rh)], fill=(40, 40, 40), width=1)
    for r in range(rows):
        for c in range(cols):
            d.text((x + c * cw + 4, y + r * rh + rh * 0.2), _sentence(rng, 1 if c else 2), font=font, fill=(30, 30, 30))
    return y + rows * rh + rh


def _fake_figure(rng, w, h):
    img = np.full((h, w, 3), rng.integers(150, 255), np.uint8)
    gx = np.linspace(0, rng.uniform(0, 80), w)[None, :, None]
    img = np.clip(img + gx, 0, 255).astype(np.uint8)
    for _ in range(int(rng.integers(2, 8))):
        c = int(rng.integers(0, 200))
        if rng.random() < 0.5:
            cv2.ellipse(img, (int(rng.integers(w)), int(rng.integers(h))),
                        (int(rng.integers(5, w // 2 + 6)), int(rng.integers(5, h // 2 + 6))),
                        0, 0, 360, (c, c, c), int(rng.choice([1, 2, -1])))
        else:
            cv2.line(img, (int(rng.integers(w)), int(rng.integers(h))),
                     (int(rng.integers(w)), int(rng.integers(h))), (c, c, c), int(rng.integers(1, 4)))
    cv2.rectangle(img, (0, 0), (w - 1, h - 1), (0, 0, 0), 1)
    return img


def _paper(rng):
    t = rng.random()
    if t < 0.4:
        return np.array([255, 255, 255], np.float32)
    tint = rng.uniform(0, 1)
    return np.array([255 - 14 * tint * rng.uniform(.3, 1), 255 - 30 * tint, 255 - 70 * tint], np.float32)


def apply_paper(rng, arr):
    """Multiply a white-background page by a paper colour (white .. yellowish)."""
    p = _paper(rng)
    out = arr.astype(np.float32) * (p / 255.0)
    return np.clip(out, 0, 255).astype(np.uint8)


# --------------------------------------------------------------------------
def make_book_page(rng, lib, holdout, n_diag=None, text_only=False):
    W = int(rng.uniform(800, 1700))
    H = int(W * rng.uniform(1.25, 1.5))
    page = Image.new("RGB", (W, H), (255, 255, 255))
    d = ImageDraw.Draw(page)
    mx = int(W * rng.uniform(0.07, 0.14))
    top = int(H * rng.uniform(0.05, 0.1))
    bot = H - int(H * rng.uniform(0.05, 0.1))
    ncols = int(rng.choice([1, 2, 3], p=[.45, .35, .2]))
    fs = int(np.clip(W / rng.uniform(36, 58), 11, 44))
    tpath = fonts.pick(rng, "serif" if rng.random() < 0.7 else "sans")
    tfont = fonts.load(tpath, fs)
    capfont = fonts.load(fonts.pick(rng, "sans" if rng.random() < 0.5 else "serif"), max(9, int(fs * 0.85)))
    ink = int(rng.integers(0, 60))
    lh = int(fs * rng.uniform(1.25, 1.5))
    style = B.sample_book_style(rng, lib, holdout)
    flip_p = float(rng.choice([0, 0, 0.15, 0.5, 1.0]))
    n_target = 0 if text_only else (n_diag or int(rng.integers(1, 9)))
    textw = W - 2 * mx
    gap = int(W * 0.04)
    cellw = (textw - gap * (ncols - 1)) // ncols
    out = []
    y = top
    if rng.random() < 0.3:
        hf = fonts.load(tpath, int(fs * 1.6))
        d.text((W / 2, y), rng.choice(["Chapter 7", "Endgame studies", "Exercises", "Tactics", "A", "Test positions"]),
               font=hf, fill=(ink, ink, ink), anchor="ma")
        y += int(fs * 3)
    guard = 0
    while y < bot - lh and guard < 40:
        guard += 1
        if rng.random() < 0.8 or len(out) >= n_target:
            y = _paragraph(rng, d, tfont, mx, y, textw, int(rng.integers(1, 6)), lh, ink, bot)
            y += int(lh * 0.5)
        if rng.random() < 0.1:
            y = _table(rng, d, tfont, mx, y, textw, bot)
        elif rng.random() < 0.06 and y + 60 < bot:
            fw = int(textw * rng.uniform(0.3, 0.8))
            fh = int(min(bot - y - 4, fw * rng.uniform(0.4, 0.9)))
            if fh > 20:
                page.paste(Image.fromarray(_fake_figure(rng, fw, fh)), (mx + (textw - fw) // 2, y))
                y += fh + lh
        if len(out) >= n_target:
            continue
        k = ncols if rng.random() < 0.7 else int(rng.integers(1, ncols + 1))
        k = min(k, n_target - len(out))
        frame_extra = 2 * (0.55 * style["coords"] + 0.1 + style["pad_frac"] + style["gap_frac"] + style["ft_frac"])
        rows_est = int(np.ceil(n_target / ncols))
        row_px = (bot - top) / max(1.0, rows_est) * rng.uniform(0.55, 0.85) - fs * 3
        bw_t = min(cellw * rng.uniform(0.55, 0.98), max(70.0, row_px))
        sq = max(8, int(bw_t / (8 + frame_extra * 1.1)))
        caph = int(fs * 1.7)

        def fits(sq_):
            return y + 8 * sq_ + 2 * frame_extra * sq_ + caph <= bot
        if not fits(sq):
            if out:
                break
            while sq > 8 and not fits(sq):
                sq -= 1
            if not fits(sq):
                break
        row = [B.render_book_board(rng, random_position(rng), style, sq, bool(rng.random() < flip_p))
               for _ in range(k)]
        bh = max(r.img.shape[0] for r in row)
        left_aligned = rng.random() < 0.25
        for j, r in enumerate(row):
            bw = r.img.shape[1]
            x = mx + j * (cellw + gap) + (0 if left_aligned else (cellw - bw) // 2)
            page.paste(Image.fromarray(r.img), (x, y))
            out.append((r.quad + [x, y], r.labels, r.flipped, r.meta))
            if rng.random() < 0.7:
                cap = CAPTIONS[int(rng.integers(len(CAPTIONS)))] if rng.random() < 0.6 else f"No. {int(rng.integers(1, 400))}"
                d.text((x + bw / 2, y + bh + fs * 0.15), cap, font=capfont, fill=(ink, ink, ink), anchor="ma")
        y += bh + caph
    arr = apply_paper(rng, np.asarray(page))
    return Page(arr, out, "book")


def make_book_crop(rng, lib, holdout):
    """One diagram, tightly cropped (possibly with caption or nearby text)."""
    style = B.sample_book_style(rng, lib, holdout)
    sq = int(np.exp(rng.uniform(np.log(14), np.log(90))))
    r = B.render_book_board(rng, random_position(rng), style, sq, bool(rng.random() < 0.25))
    S = r.img.shape[0]
    m = int(S * rng.uniform(0, 0.12))
    extra_top = int(S * rng.uniform(0.05, 0.2)) if rng.random() < 0.35 else 0
    extra_bot = int(S * rng.uniform(0.05, 0.25)) if rng.random() < 0.5 else 0
    W, H = S + 2 * m, S + 2 * m + extra_top + extra_bot
    page = Image.new("RGB", (W, H), (255, 255, 255))
    page.paste(Image.fromarray(r.img), (m, m + extra_top))
    d = ImageDraw.Draw(page)
    fs = max(8, int(S * 0.07))
    f = fonts.load(fonts.pick(rng, "serif"), fs)
    if extra_bot > fs:
        d.text((W / 2, m + extra_top + S + 2), CAPTIONS[int(rng.integers(len(CAPTIONS)))], font=f, fill=(20, 20, 20), anchor="ma")
    if extra_top > fs:
        d.text((m, 2), _sentence(rng, 4), font=f, fill=(20, 20, 20))
    arr = apply_paper(rng, np.asarray(page))
    return Page(arr, [(r.quad + [m, m + extra_top], r.labels, r.flipped, r.meta)], "crop")


_DARK_BG = [(22, 21, 18), (38, 36, 33), (49, 46, 43), (30, 30, 40), (18, 18, 18)]
_LIGHT_BG = [(245, 245, 245), (235, 235, 230), (255, 255, 255), (222, 227, 230), (250, 244, 232)]


def _ui_text(rng, d, x, y, w, h, font, color, lines=None):
    """Move-list / chat like text lines inside a rectangle."""
    lh = int(font.size * 1.5)
    yy = y
    n = 0
    while yy + lh < y + h and n < 30:
        s = _notation(rng) if rng.random() < 0.6 else _sentence(rng, int(rng.integers(2, 6)))
        while font.getlength(s) > w and len(s) > 3:
            s = s[:-3]
        d.text((x, yy), s, font=font, fill=color)
        yy += lh
        n += 1


def make_screenshot(rng, lib, holdout):
    style = B.sample_screen_style(rng, lib, holdout)
    dark = rng.random() < 0.55
    bg = (_DARK_BG if dark else _LIGHT_BG)[int(rng.integers(5))]
    fg = (200, 200, 200) if dark else (40, 40, 40)
    panel = tuple(int(np.clip(v + (14 if dark else -12), 0, 255)) for v in bg)
    mode = str(rng.choice(["phone", "desktop", "boardfill"], p=[.4, .3, .3]))
    out_div = 8 + (0.84 if style["coords"] == "outside" else 0) + 2 * style["border"] / 40
    flipped = bool(rng.random() < 0.25)
    pos = random_position(rng)
    uf = fonts.pick(rng, "sans")
    if mode == "boardfill":
        sq = int(rng.uniform(24, 100))
        r = B.render_screen_board(rng, pos, style, sq, flipped)
        S = r.img.shape[0]
        m = int(S * rng.uniform(0, 0.08))
        img = np.full((S + 2 * m, S + 2 * m, 3), bg, np.uint8)
        img[m:m + S, m:m + S] = r.img
        return Page(img, [(r.quad + [m, m], r.labels, r.flipped, r.meta)], "screenshot")
    if mode == "phone":
        W = int(rng.uniform(450, 900))
        H = int(W * rng.uniform(1.8, 2.2))
        bw = W * rng.uniform(0.88, 1.0)
        sq = max(8, int(bw / out_div))
        r = B.render_screen_board(rng, pos, style, sq, flipped)
        S = r.img.shape[0]
        x = (W - S) // 2
        y = int(H * rng.uniform(0.1, 0.3))
        im = Image.new("RGB", (W, H), bg)
        d = ImageDraw.Draw(im)
        d.rectangle([0, 0, W, int(H * 0.05)], fill=panel)
        d.text((W * 0.05, H * 0.012), "12:30", font=fonts.load(uf, int(W * 0.035)), fill=fg)
        pf = fonts.load(uf, int(W * 0.04))
        d.rectangle([x, y - int(W * 0.1), x + int(W * 0.07), y - int(W * 0.03)], fill=panel)
        d.text((x + W * 0.09, y - W * 0.095), "Player " + _sentence(rng, 1) + " (1500)", font=pf, fill=fg)
        im.paste(Image.fromarray(r.img), (x, y))
        d.text((x + W * 0.09, y + S + W * 0.03), "You (1480)", font=pf, fill=fg)
        by = y + S + int(W * 0.12)
        _ui_text(rng, d, x, by, W - 2 * x, int(H * 0.9) - by, fonts.load(uf, int(W * 0.04)), fg)
        for i in range(4):
            bx = int(W * (0.1 + i * 0.22))
            d.rounded_rectangle([bx, int(H * 0.93), bx + int(W * 0.16), int(H * 0.97)], radius=8, fill=panel)
        return Page(np.asarray(im).copy(), [(r.quad + [x, y], r.labels, r.flipped, r.meta)], "screenshot")
    # desktop
    W = int(rng.uniform(900, 1400))
    H = int(W * rng.uniform(0.55, 0.75))
    bh = H * rng.uniform(0.7, 0.92)
    sq = max(8, int(bh / out_div))
    r = B.render_screen_board(rng, pos, style, sq, flipped)
    S = r.img.shape[0]
    x = int(W * rng.uniform(0.04, 0.2))
    y = (H - S) // 2
    im = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(im)
    px = x + S + int(W * 0.03)
    if px + 120 < W:
        d.rectangle([px, y, min(W - 10, px + int(W * 0.3)), y + S], fill=panel)
        _ui_text(rng, d, px + 10, y + 10, int(W * 0.3) - 20, S - 20, fonts.load(uf, max(10, int(S * 0.04))), fg)
    im.paste(Image.fromarray(r.img), (x, y))
    d.text((10, 8), "Analysis board", font=fonts.load(uf, 16), fill=fg)
    return Page(np.asarray(im).copy(), [(r.quad + [x, y], r.labels, r.flipped, r.meta)], "screenshot")
