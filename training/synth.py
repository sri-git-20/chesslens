"""Synthetic sample generation: one call = one page image with ground truth, plus
conversion into the three training targets."""
from dataclasses import dataclass, field

import numpy as np

import boards as B
import camera
import pages
import reference_pipeline as rp

DET, DET_OUT, MAX_BOARDS = 384, 96, 10


@dataclass
class Sample:
    img: np.ndarray                 # RGB uint8
    boards: list = field(default_factory=list)   # dicts: quad (4x2), labels (8x8), flipped
    category: str = ""              # clean | photo | screenshot
    kind: str = ""


def pick_category(rng):
    return str(rng.choice(["clean", "photo", "screenshot", "negative"], p=[.25, .45, .25, .05]))


def make_sample(seed, lib, category=None, holdout=False):
    rng = np.random.default_rng(seed)
    cat = category or pick_category(rng)
    negative = cat == "negative"
    if negative:
        cat = "clean" if rng.random() < 0.5 else "photo"
    if cat == "screenshot":
        page = pages.make_screenshot(rng, lib, holdout)
        img, quads, keep = camera.screenshot(rng, page.img, [b[0] for b in page.boards])
    else:
        if negative:
            page = pages.make_book_page(rng, lib, holdout, text_only=True)
        elif rng.random() < 0.3:
            page = pages.make_book_crop(rng, lib, holdout)
        else:
            page = pages.make_book_page(rng, lib, holdout)
        sev = 0.0 if cat == "clean" else float(rng.uniform(0.2, 1.0))
        img, quads, keep = camera.photo(rng, page.img, [b[0] for b in page.boards], sev)
    bl = [dict(quad=quads[i], labels=page.boards[i][1], flipped=page.boards[i][2], meta=page.boards[i][3]) for i in keep]
    return Sample(img, bl, cat, page.kind)


# ---------------------------------------------------------------- targets
def det_target(quads):
    """quads: (n, 4, 2) in letterboxed 384 px. Returns heat (96,96), mask (96,96)
    and offsets (96,96,8) (offsets divided by 384, from the cell centre)."""
    heat = np.zeros((DET_OUT, DET_OUT), np.float32)
    mask = np.zeros((DET_OUT, DET_OUT), np.float32)
    off = np.zeros((DET_OUT, DET_OUT, 8), np.float32)
    for q in quads:
        c = q.mean(0)
        ix, iy = int(np.clip(c[0] // 4, 0, DET_OUT - 1)), int(np.clip(c[1] // 4, 0, DET_OUT - 1))
        size = max(np.ptp(q[:, 0]), np.ptp(q[:, 1])) / 4.0
        sg = float(np.clip(size / 12.0, 0.8, 3.0))
        r = int(3 * sg) + 2
        y0, y1, x0, x1 = max(0, iy - r), min(DET_OUT, iy + r + 1), max(0, ix - r), min(DET_OUT, ix + r + 1)
        yy, xx = np.mgrid[y0:y1, x0:x1]
        g = np.exp(-((xx - ix) ** 2 + (yy - iy) ** 2) / (2 * sg * sg))
        heat[y0:y1, x0:x1] = np.maximum(heat[y0:y1, x0:x1], g)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                cx, cy = ix + dx, iy + dy
                if 0 <= cx < DET_OUT and 0 <= cy < DET_OUT:
                    centre = np.array([(cx + 0.5) * 4, (cy + 0.5) * 4])
                    off[cy, cx] = ((q - centre) / DET).reshape(8)
                    mask[cy, cx] = 1
    return heat, mask, off


def cor_target(pts):
    """pts: (4,2) corners in crop px -> heat (64,64,4); Gaussian sigma 3.2 px."""
    cell = (np.arange(64) + 0.5) * 4.0
    out = np.zeros((64, 64, 4), np.float32)
    for k in range(4):
        gx = np.exp(-((cell - pts[k, 0]) ** 2) / (2 * 3.2 ** 2))
        gy = np.exp(-((cell - pts[k, 1]) ** 2) / (2 * 3.2 ** 2))
        out[..., k] = gy[:, None] * gx[None, :]
    return out


# ---------------------------------------------------------------- arrays
def board_size(q):
    return float(np.mean([np.linalg.norm(q[i] - q[(i + 1) % 4]) for i in range(4)]))


def jitter_coarse(rng, quad):
    """Simulates the detector's coarse quad error."""
    size = board_size(quad)
    sg = 0.025 if rng.random() < 0.8 else 0.05
    return quad + np.clip(rng.normal(0, sg * size, (4, 2)), -0.1 * size, 0.1 * size)


def jitter_fine(rng, quad):
    """Simulates the corners model's error (sigma given in 256-crop pixels)."""
    size = board_size(quad)
    sg = float(rng.choice([0.8, 1.5, 3.0], p=[.4, .45, .15]))
    return quad + rng.normal(0, sg * size / 256.0, (4, 2))


def to_training(seed, sample, sq_per_board=2):
    """Returns dict of arrays for the detector, corners and squares sets."""
    rng = np.random.default_rng(seed + 7919)
    gray = rp.to_gray_u8(sample.img)
    lb, s = rp.letterbox(gray)
    quads = np.zeros((MAX_BOARDS, 4, 2), np.float32)
    n = 0
    for b in sample.boards[:MAX_BOARDS]:
        quads[n] = b["quad"] * s
        n += 1
    cx, cy, sx, sy = [], [], [], []
    for b in sample.boards:
        q = b["quad"]
        if board_size(q) < 40:
            continue
        crop, H = rp.crop_for_corners(gray, jitter_coarse(rng, q))
        cx.append(crop)
        cy.append(rp.apply_h(H, q).astype(np.float32))
        for _ in range(sq_per_board):
            sx.append(rp.warp_board(gray, jitter_fine(rng, q)))
            sy.append(b["labels"].astype(np.uint8))
    return dict(det_x=lb, det_q=quads, det_n=n, cor_x=cx, cor_y=cy, sq_x=sx, sq_y=sy)
