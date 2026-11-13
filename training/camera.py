"""Image degradation: scanner / phone camera / screenshot simulation.

Every function takes an RGB uint8 image and a list of 4x2 board quads (continuous
pixel coordinates) and returns the degraded image plus the transformed quads.
"""
import cv2
import numpy as np


def _resize(img, scale):
    h, w = img.shape[:2]
    nw, nh = max(32, int(round(w * scale))), max(32, int(round(h * scale)))
    interp = cv2.INTER_AREA if scale < 1 else cv2.INTER_LINEAR
    return cv2.resize(img, (nw, nh), interpolation=interp), np.array([nw / w, nh / h])


def _jpeg(img, q):
    ok, buf = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, int(q)])
    return cv2.imdecode(buf, cv2.IMREAD_UNCHANGED) if ok else img


def _inside(quad, w, h, m=1.0):
    return bool(np.all(quad[:, 0] >= m) and np.all(quad[:, 0] <= w - m)
                and np.all(quad[:, 1] >= m) and np.all(quad[:, 1] <= h - m))


def _curl(pts, w, h, amp, freq, phase, ax):
    """Smooth displacement of page points (paper curl)."""
    d = np.zeros_like(pts)
    d[..., 1] = amp * h * np.sin(2 * np.pi * freq * pts[..., 0] / w + phase)
    d[..., 0] = ax * w * np.sin(2 * np.pi * 0.5 * pts[..., 1] / h + phase)
    return d


def _light_field(rng, w, h, s):
    """Smooth multiplicative lighting field (gradient, shadows, vignette)."""
    n = 64
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / (n - 1) - 0.5
    ang = rng.uniform(0, 2 * np.pi)
    field = 1 + s * rng.uniform(0, 0.45) * (xx * np.cos(ang) + yy * np.sin(ang)) * 2
    if rng.random() < 0.55 * s + 0.05:
        for _ in range(int(rng.integers(1, 3))):
            cx, cy = rng.uniform(-0.4, 0.4, 2)
            rx, ry = rng.uniform(0.15, 0.6, 2)
            m = (((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2) < 1
            sh = np.where(m, rng.uniform(0.55, 0.9), 1.0).astype(np.float32)
            field = field * cv2.GaussianBlur(sh, (0, 0), rng.uniform(0.8, 3.0))
    if rng.random() < 0.3 * s:
        field = field * (1 - rng.uniform(0.1, 0.4) * (xx ** 2 + yy ** 2) * 2)
    return cv2.resize(field.astype(np.float32), (w, h), interpolation=cv2.INTER_LINEAR)


def _bg_colour(rng):
    t = rng.random()
    if t < 0.35:
        v = int(rng.integers(20, 90))
        return (v, v, v)
    if t < 0.6:
        return (int(rng.integers(90, 160)), int(rng.integers(60, 110)), int(rng.integers(30, 70)))
    if t < 0.8:
        v = int(rng.integers(150, 235))
        return (v, v, v)
    return tuple(int(v) for v in rng.integers(30, 220, 3))


def photo(rng, img, quads, severity):
    """Phone-photo simulation. severity 0..1; 0 gives a (nearly) clean scan."""
    s = float(severity)
    quads = [q.copy() for q in quads]
    scale = min(rng.uniform(900, 2600) / max(img.shape[:2]), 1.3) if s > 0 else rng.uniform(0.7, 1.2)
    img, f = _resize(img, scale)
    quads = [q * f for q in quads]
    h, w = img.shape[:2]
    src = np.array([[0, 0], [w, 0], [w, h], [0, h]], np.float32)
    if s > 0:
        ang = np.deg2rad(rng.uniform(-8, 8) * s ** 0.7)
        k = rng.uniform(1.0 - 0.2 * s, 1.0) if rng.random() < 0.8 else rng.uniform(1.0, 1.08)
        persp = 0.04 * s * rng.uniform(0.3, 1.0)
    else:
        ang = np.deg2rad(rng.uniform(-0.6, 0.6)) if rng.random() < 0.4 else 0.0
        k, persp = 1.0, 0.0
    c, sn = np.cos(ang), np.sin(ang)
    R = np.array([[c, -sn], [sn, c]], np.float32)
    dst = (src - [w / 2, h / 2]) @ R.T * k + [w / 2, h / 2]
    dst = dst + rng.normal(0, persp, (4, 2)) * [w, h]
    dst = dst.astype(np.float32)
    H = cv2.getPerspectiveTransform(src, dst)
    Hinv = np.linalg.inv(H)
    amp = 0.012 * s * rng.uniform(0, 1) if rng.random() < 0.6 else 0.0
    freq, phase, ax = rng.uniform(0.4, 1.6), rng.uniform(0, 6.28), 0.004 * s * rng.uniform(-1, 1)
    # inverse map on a coarse grid (fixed-point for the curl), then upsample
    gw, gh = max(2, int(np.ceil(w / 8))), max(2, int(np.ceil(h / 8)))
    xs = (np.arange(gw) + 0.5) * (w / gw)
    ys = (np.arange(gh) + 0.5) * (h / gh)
    q = np.stack(np.meshgrid(xs, ys), -1).astype(np.float32)
    p = cv2.perspectiveTransform(q.reshape(-1, 1, 2), Hinv).reshape(gh, gw, 2)
    sp = p.copy()
    for _ in range(4):
        sp = p - _curl(sp, w, h, amp, freq, phase, ax)
    maps = cv2.resize((sp - 0.5).astype(np.float32), (w, h), interpolation=cv2.INTER_LINEAR)
    bg = _bg_colour(rng) if s > 0 else (255, 255, 255)
    out = cv2.remap(img, maps[..., 0], maps[..., 1], cv2.INTER_LINEAR,
                    borderMode=cv2.BORDER_CONSTANT, borderValue=bg)
    new_q = []
    for qd in quads:
        pp = qd.astype(np.float32)
        pp = pp + _curl(pp, w, h, amp, freq, phase, ax)
        new_q.append(cv2.perspectiveTransform(pp.reshape(-1, 1, 2), H).reshape(4, 2).astype(np.float64))
    # photometrics
    f32 = out.astype(np.float32)
    if s > 0:
        f32 *= _light_field(rng, w, h, s)[..., None]
        cvar = 1 - s * rng.uniform(0, 0.55) if rng.random() < 0.5 else 1.0
        f32 = (f32 - 128) * cvar + 128 + rng.uniform(-20, 20) * s
        f32 *= (1 + rng.uniform(-0.05, 0.05, 3) * s)[None, None, :]
        if rng.random() < 0.3:
            g = rng.uniform(0.8, 1.3)
            f32 = 255 * np.power(np.clip(f32, 0, 255) / 255, g)
        bl = rng.random()
        if bl < 0.65:
            sg = s * rng.uniform(0.3, 2.0)
            if sg > 0.3:
                f32 = cv2.GaussianBlur(f32, (0, 0), sg)
        elif bl < 0.85:
            L = int(rng.integers(3, 4 + int(8 * s)))
            kern = np.zeros((L, L), np.float32)
            a = rng.uniform(0, np.pi)
            cv2.line(kern, (L // 2 - int(np.cos(a) * L / 2), L // 2 - int(np.sin(a) * L / 2)),
                     (L // 2 + int(np.cos(a) * L / 2), L // 2 + int(np.sin(a) * L / 2)), 1.0, 1)
            f32 = cv2.filter2D(f32, -1, kern / max(kern.sum(), 1e-6))
        ns = s * rng.uniform(0, 9)
    else:
        if rng.random() < 0.5:
            f32 = cv2.GaussianBlur(f32, (0, 0), rng.uniform(0.3, 0.7))
        ns = rng.uniform(0, 2)
    if ns > 0.3:
        n = rng.standard_normal((h, w, 1), dtype=np.float32) * ns
        n = n + rng.standard_normal((h, w, 3), dtype=np.float32) * ns * 0.3
        f32 = f32 + n
    out = np.clip(f32, 0, 255).astype(np.uint8)
    if s > 0 and rng.random() < 0.85:
        out = _jpeg(out, 95 - s * rng.uniform(0, 70))
    elif s == 0 and rng.random() < 0.4:
        out = _jpeg(out, rng.uniform(85, 98))
    keep = [i for i, qd in enumerate(new_q) if _inside(qd, w, h)]
    return out, new_q, keep


def screenshot(rng, img, quads):
    """Screenshot: rescale (anti-aliased), rare blur, JPEG."""
    sc = rng.uniform(0.5, 1.3)
    if max(img.shape[:2]) * sc > 1600:
        sc = 1600 / max(img.shape[:2])
    img, f = _resize(img, sc)
    quads = [q * f for q in quads]
    if rng.random() < 0.15:
        img = cv2.GaussianBlur(img, (0, 0), rng.uniform(0.4, 1.0))
    if rng.random() < 0.4:
        img = _jpeg(img, rng.uniform(55, 95))
    h, w = img.shape[:2]
    keep = [i for i, qd in enumerate(quads) if _inside(qd, w, h, 0.0)]
    return img, quads, keep
