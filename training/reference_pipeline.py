"""Reference implementation of the app-side recognition steps.

This file follows the "Recognition models" section of docs/ARCHITECTURE.md
literally and is meant to be ported to Dart line by line. It is also the single
source of truth for the geometry helpers used to build the training data, so
the models are trained on exactly the crops they get at run time.

Conventions
-----------
* Images are numpy arrays. RGB uint8 (H, W, 3) or greyscale (H, W) uint8/float32.
* Coordinates are *continuous* pixel coordinates: (0, 0) is the top-left corner
  of the top-left pixel, the centre of pixel (i, j) is (i + 0.5, j + 0.5).
  (OpenCV addresses pixel centres with integers; `warp_region` converts.)
* Quads are 4x2 arrays in the order TL, TR, BR, BL (by position in the image).
* Greyscale = (0.299 R + 0.587 G + 0.114 B) / 255, float in [0, 1].

Pipeline (process_image)
------------------------
1. gray -> letterbox 384x384 (scale s = 384 / max(w, h), top-left, white fill)
2. detector -> 96x96x9 -> local maxima >= 0.35 -> coarse quads (original px)
3. per board: square crop around the coarse quad (side 1.25 * max bbox side),
   resized to 256x256 -> corners model -> 4 refined corners (original px)
4. perspective warp of the refined quad to 256x256 -> squares model ->
   argmax per square -> FEN placement (as drawn: image top row first)
"""
import numpy as np
import cv2

DET_SIZE = 384
DET_STRIDE = 4
DET_THRESHOLD = 0.35
COR_SIZE = 256
COR_STRIDE = 4
CROP_FACTOR = 1.25
SQ_SIZE = 256
FEN_CHARS = ["", "P", "N", "B", "R", "Q", "K", "p", "n", "b", "r", "q", "k"]


# ---------------------------------------------------------------- basics
def to_gray(img):
    """RGB uint8 (or already grey) -> float32 grey in [0, 1]."""
    if img.ndim == 2:
        g = img.astype(np.float32)
        return g / 255.0 if img.dtype == np.uint8 else g
    f = img[..., :3].astype(np.float32)
    return (0.299 * f[..., 0] + 0.587 * f[..., 1] + 0.114 * f[..., 2]) / 255.0


def to_gray_u8(img):
    """Same grey, rounded to uint8 (used to store training data compactly)."""
    return np.clip(np.round(to_gray(img) * 255.0), 0, 255).astype(np.uint8)


def apply_h(H, pts):
    """Apply a 3x3 homography to an Nx2 array of points."""
    pts = np.asarray(pts, np.float64).reshape(-1, 2)
    p = np.hstack([pts, np.ones((len(pts), 1))]) @ np.asarray(H, np.float64).T
    return p[:, :2] / p[:, 2:3]


def _fill_value(img):
    return 255 if img.dtype == np.uint8 else 1.0


# ---------------------------------------------------------------- step 1
def letterbox(gray):
    """Scale so the longer side is 384, place at (0, 0), fill with white.
    Returns (384x384 image, s)."""
    h, w = gray.shape[:2]
    s = DET_SIZE / max(w, h)
    nw, nh = max(1, int(round(w * s))), max(1, int(round(h * s)))
    small = cv2.resize(gray, (nw, nh), interpolation=cv2.INTER_AREA)
    canvas = np.full((DET_SIZE, DET_SIZE), _fill_value(gray), gray.dtype)
    canvas[:nh, :nw] = small[:DET_SIZE, :DET_SIZE]
    return canvas, s


# ---------------------------------------------------------------- step 2
def decode_detector(out, s, threshold=DET_THRESHOLD):
    """out: (96, 96, 9). Returns a list of {'score', 'quad' (4x2, original px),
    'cell' (x, y)}. A board is a cell whose heat value is >= threshold and is
    the maximum of its 3x3 neighbourhood (exact ties between neighbours keep
    only the first cell in raster order)."""
    heat = out[..., 0]
    n = heat.shape[0]
    pad = np.pad(heat, 1, constant_values=-1.0)
    neigh = np.max([pad[1 + dy:1 + dy + n, 1 + dx:1 + dx + n]
                    for dy in (-1, 0, 1) for dx in (-1, 0, 1) if (dy, dx) != (0, 0)], axis=0)
    ys, xs = np.nonzero((heat >= threshold) & (heat >= neigh))
    accepted = []
    for y, x in zip(ys, xs):  # raster order
        if any(abs(x - ax) <= 1 and abs(y - ay) <= 1 and heat[ay, ax] == heat[y, x]
               for ax, ay in accepted):
            continue
        accepted.append((x, y))
    dets = []
    for x, y in accepted:
        cx, cy = (x + 0.5) * DET_STRIDE, (y + 0.5) * DET_STRIDE
        off = out[y, x, 1:9] * DET_SIZE
        quad = np.array([[cx + off[0], cy + off[1]], [cx + off[2], cy + off[3]],
                         [cx + off[4], cy + off[5]], [cx + off[6], cy + off[7]]]) / s
        dets.append({"score": float(heat[y, x]), "quad": quad, "cell": (int(x), int(y))})
    return dets


# ---------------------------------------------------------------- geometry
def warp_region(img, src_quad, out=256, fill=None):
    """Perspective-warp the region `src_quad` (TL, TR, BR, BL) of `img` onto an
    out x out square: TL -> (0, 0), TR -> (out, 0), BR -> (out, out),
    BL -> (0, out). Samples outside the image are white. Bilinear sampling,
    preceded by an area-average shrink when the region is much larger than the
    output (to avoid aliasing).
    Returns (warped, H) with H mapping original -> output continuous coords."""
    if fill is None:
        fill = _fill_value(img)
    h, w = img.shape[:2]
    src = np.asarray(src_quad, np.float64).reshape(4, 2)
    dst = np.array([[0, 0], [out, 0], [out, out], [0, out]], np.float64)
    H_plain = cv2.getPerspectiveTransform(src.astype(np.float32), dst.astype(np.float32)).astype(np.float64)
    x0 = int(max(0, np.floor(src[:, 0].min()) - 2))
    x1 = int(min(w, np.ceil(src[:, 0].max()) + 2))
    y0 = int(max(0, np.floor(src[:, 1].min()) - 2))
    y1 = int(min(h, np.ceil(src[:, 1].max()) + 2))
    if x1 - x0 < 2 or y1 - y0 < 2:
        return np.full((out, out), fill, img.dtype), H_plain
    roi = img[y0:y1, x0:x1]
    side = np.mean([np.linalg.norm(src[i] - src[(i + 1) % 4]) for i in range(4)])
    fx = fy = 1.0
    if side / out > 1.5:
        f = out / side
        nw, nh = max(1, int(round(roi.shape[1] * f))), max(1, int(round(roi.shape[0] * f)))
        roi = cv2.resize(roi, (nw, nh), interpolation=cv2.INTER_AREA)
        fx, fy = nw / (x1 - x0), nh / (y1 - y0)
    S = np.array([[fx, 0, -x0 * fx], [0, fy, -y0 * fy], [0, 0, 1.0]])
    src_s = (src - [x0, y0]) * [fx, fy]
    Hs = cv2.getPerspectiveTransform(src_s.astype(np.float32), dst.astype(np.float32)).astype(np.float64)
    T = np.array([[1, 0, -0.5], [0, 1, -0.5], [0, 0, 1.0]])     # continuous -> OpenCV
    Tp = np.array([[1, 0, 0.5], [0, 1, 0.5], [0, 0, 1.0]])
    warped = cv2.warpPerspective(roi, T @ Hs @ Tp, (out, out), flags=cv2.INTER_LINEAR,
                                 borderMode=cv2.BORDER_CONSTANT, borderValue=fill)
    return warped, Hs @ S


def coarse_square(quad):
    """Square around the coarse quad: centre = bbox centre, side
    L = 1.25 * max(bbox width, bbox height). Returns the 4 corners TL, TR, BR, BL."""
    q = np.asarray(quad, np.float64)
    mn, mx = q.min(0), q.max(0)
    c = (mn + mx) / 2
    L = CROP_FACTOR * max(mx[0] - mn[0], mx[1] - mn[1])
    L = max(L, 8.0)
    return np.array([[c[0] - L / 2, c[1] - L / 2], [c[0] + L / 2, c[1] - L / 2],
                     [c[0] + L / 2, c[1] + L / 2], [c[0] - L / 2, c[1] + L / 2]])


def crop_for_corners(img, coarse_quad):
    """256x256 crop for the corners model. Returns (crop, H) (H: original -> crop)."""
    return warp_region(img, coarse_square(coarse_quad), COR_SIZE)


def decode_corners(heat):
    """heat: (64, 64, 4) -> 4x2 corner positions in crop pixels (continuous).
    Per channel: arg-max cell, refined with the value-weighted mean of its 3x3
    neighbourhood; crop pixel = (x + 0.5) * 4."""
    n = heat.shape[0]
    pts = []
    for k in range(4):
        m = heat[..., k]
        iy, ix = np.unravel_index(np.argmax(m), m.shape)
        ya, yb = max(0, iy - 1), min(n, iy + 2)
        xa, xb = max(0, ix - 1), min(n, ix + 2)
        win = m[ya:yb, xa:xb].astype(np.float64)
        gy, gx = np.mgrid[ya:yb, xa:xb]
        tot = win.sum()
        if tot <= 0:
            mx_, my_ = float(ix), float(iy)
        else:
            mx_, my_ = (win * gx).sum() / tot, (win * gy).sum() / tot
        pts.append([(mx_ + 0.5) * COR_STRIDE, (my_ + 0.5) * COR_STRIDE])
    return np.array(pts)


def refine_quad(img, coarse_quad, corners_model):
    """Run the corners model on the crop around `coarse_quad`; returns the
    refined quad in original pixels."""
    crop, H = crop_for_corners(img, coarse_quad)
    heat = corners_model(crop)
    return apply_h(np.linalg.inv(H), decode_corners(heat))


def warp_board(img, quad):
    """256x256 warp of the playing area for the squares model."""
    return warp_region(img, quad, SQ_SIZE)[0]


# ---------------------------------------------------------------- step 4
def read_squares(out):
    """out: (8, 8, 13) softmax -> (classes 8x8 int, confidence 8x8 float)."""
    return np.argmax(out, axis=-1), np.max(out, axis=-1)


def placement_fen(classes):
    """8x8 class ids (row 0 = top of the image) -> FEN piece placement as drawn."""
    ranks = []
    for r in range(8):
        s, empty = "", 0
        for c in range(8):
            k = int(classes[r][c])
            if k == 0:
                empty += 1
            else:
                s += (str(empty) if empty else "") + FEN_CHARS[k]
                empty = 0
        ranks.append(s + (str(empty) if empty else ""))
    return "/".join(ranks)


def reading_order(dets):
    """Sort boards top-to-bottom, left-to-right (rows = similar centre y)."""
    if not dets:
        return dets
    def cen(d):
        q = d["quad"]
        return q[:, 0].mean(), q[:, 1].mean()
    def hgt(d):
        q = d["quad"]
        return q[:, 1].max() - q[:, 1].min()
    order = sorted(dets, key=lambda d: cen(d)[1])
    rows, cur = [], [order[0]]
    for d in order[1:]:
        if abs(cen(d)[1] - np.mean([cen(x)[1] for x in cur])) < 0.5 * np.mean([hgt(x) for x in cur]):
            cur.append(d)
        else:
            rows.append(cur)
            cur = [d]
    rows.append(cur)
    return [d for r in rows for d in sorted(r, key=lambda d: cen(d)[0])]


# ---------------------------------------------------------------- models
class TFLiteModel:
    """Thin wrapper: call with a 2-D float image, get the output without the
    batch dimension."""

    def __init__(self, path, threads=4):
        try:
            from ai_edge_litert.interpreter import Interpreter
        except ImportError:
            import tensorflow as tf
            Interpreter = tf.lite.Interpreter
        self.it = Interpreter(model_path=path, num_threads=threads)
        self.it.allocate_tensors()
        self.inp = self.it.get_input_details()[0]
        self.out = self.it.get_output_details()[0]

    def __call__(self, img2d):
        x = np.asarray(img2d, np.float32)
        if x.max() > 1.5:       # uint8-valued input
            x = x / 255.0
        self.it.set_tensor(self.inp["index"], x[None, :, :, None])
        self.it.invoke()
        return self.it.get_tensor(self.out["index"])[0].copy()


class Models:
    def __init__(self, model_dir, threads=4):
        self.detector = TFLiteModel(f"{model_dir}/detector.tflite", threads)
        self.corners = TFLiteModel(f"{model_dir}/corners.tflite", threads)
        self.squares = TFLiteModel(f"{model_dir}/squares.tflite", threads)


def process_image(models, img, threshold=DET_THRESHOLD):
    """Full pipeline on an RGB (or grey) image. Returns a list (reading order)
    of dicts: score, coarse_quad, quad (refined), classes (8x8), confidence
    (8x8), fen (placement as drawn)."""
    gray = to_gray(img)
    lb, s = letterbox(gray)
    dets = reading_order(decode_detector(models.detector(lb), s, threshold))
    results = []
    for d in dets:
        quad = refine_quad(gray, d["quad"], models.corners)
        classes, conf = read_squares(models.squares(warp_board(gray, quad)))
        results.append({"score": d["score"], "coarse_quad": d["quad"], "quad": quad,
                        "classes": classes, "confidence": conf, "fen": placement_fen(classes)})
    return results
