"""ChessLens icon: a gold magnifying lens with a queen inside, on royal purple.

background(size) and foreground(size, scale) are used by install_icons.py.
`scale` is the side of the lens-and-handle box relative to the canvas.
"""
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BG_A, BG_B = (92, 52, 160), (36, 18, 82)          # royal purple, top-left -> bottom-right
GOLD, GOLD_LIGHT, GOLD_DARK = (242, 193, 78), (255, 226, 140), (196, 146, 40)
CREAM = (255, 248, 231)


def background(size):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(BG_A, BG_B))
    return img


def draw_queen(d, cx, top, h, fill):
    """Staunton-style queen silhouette, `h` tall, top of the crown balls at `top`."""
    P = lambda x, y: (cx + x * h, top + y * h)
    # Base and foot ring.
    d.rounded_rectangle([P(-0.40, 0.86), P(0.40, 1.0)], radius=0.05 * h, fill=fill)
    d.rounded_rectangle([P(-0.33, 0.78), P(0.33, 0.88)], radius=0.04 * h, fill=fill)
    # Body with concave sides.
    left = [P(-0.29 + 0.13 * (t / 10) ** 0.7, 0.79 - 0.43 * t / 10) for t in range(11)]
    right = [P(-x, y) for (x, y) in [((px - cx) / h, (py - top) / h) for (px, py) in left]][::-1]
    d.polygon(left + right, fill=fill)
    # Collar.
    d.rounded_rectangle([P(-0.23, 0.33), P(0.23, 0.41)], radius=0.035 * h, fill=fill)
    # Crown with five points.
    crown = [(-0.25, 0.34), (-0.37, 0.13), (-0.27, 0.24), (-0.185, 0.06), (-0.09, 0.21),
             (0.0, 0.02), (0.09, 0.21), (0.185, 0.06), (0.27, 0.24), (0.37, 0.13), (0.25, 0.34)]
    d.polygon([P(x, y) for x, y in crown], fill=fill)
    for x, y in [(-0.37, 0.10), (-0.185, 0.035), (0.0, 0.0), (0.185, 0.035), (0.37, 0.10)]:
        r = 0.05 * h
        cxp, cyp = P(x, y)
        d.ellipse([cxp - r, cyp - r + 0.02 * h, cxp + r, cyp + r + 0.02 * h], fill=fill)


def _draw(size, scale):
    """Draw at `size` (already supersampled)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size / 2
    B = size * scale
    lx, ly = c - 0.07 * B, c - 0.07 * B      # lens centre
    R = 0.37 * B                              # outer radius of the ring
    ring = 0.075 * B
    r_in = R - ring

    # Handle: from the ring at 45 degrees towards the bottom-right.
    a = math.radians(45)
    hx0, hy0 = lx + (R - ring * 0.3) * math.cos(a), ly + (R - ring * 0.3) * math.sin(a)
    hx1, hy1 = c + 0.43 * B, c + 0.43 * B
    hw = 0.12 * B
    d.line([(hx0, hy0), (hx1, hy1)], fill=GOLD_DARK, width=round(hw))
    for (x, y) in ((hx0, hy0), (hx1, hy1)):
        d.ellipse([x - hw / 2, y - hw / 2, x + hw / 2, y + hw / 2], fill=GOLD_DARK)
    # Highlight stripe on the handle.
    off = hw * 0.18
    d.line([(hx0 - off, hy0 + off), (hx1 - off, hy1 + off)], fill=GOLD, width=round(hw * 0.35))

    # Glass: slightly lighter tint than the background.
    d.ellipse([lx - r_in, ly - r_in, lx + r_in, ly + r_in], fill=(255, 255, 255, 38))

    # Reflection arc on the glass (top-left).
    gl = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(gl).arc([lx - r_in * 0.88, ly - r_in * 0.88, lx + r_in * 0.88, ly + r_in * 0.88],
                           start=196, end=238, fill=(255, 255, 255, 150), width=round(r_in * 0.09))
    img = Image.alpha_composite(img, gl)
    d = ImageDraw.Draw(img)

    # Queen.
    qh = r_in * 1.30
    qtop = ly - qh * 0.50
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw_queen(ImageDraw.Draw(shadow), lx, qtop + r_in * 0.05, qh, (20, 8, 50, 130))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(r_in * 0.05)))
    d = ImageDraw.Draw(img)
    draw_queen(d, lx, qtop, qh, CREAM)

    # Gold ring with a light inner edge.
    d.ellipse([lx - R, ly - R, lx + R, ly + R], outline=GOLD, width=round(ring))
    d.ellipse([lx - R, ly - R, lx + R, ly + R], outline=GOLD_DARK, width=round(ring * 0.18))
    ri = r_in + ring * 0.12
    d.ellipse([lx - ri, ly - ri, lx + ri, ly + ri], outline=GOLD_LIGHT, width=round(ring * 0.22))
    return img


def foreground(size, scale):
    big = _draw(size * 2, scale)
    return big.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    S = 1024
    full = Image.alpha_composite(background(S).convert("RGBA"), foreground(S, 0.80))
    full.convert("RGB").resize((256, 256), Image.LANCZOS).save("/tmp/icon_preview.png")
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, S, S], fill=255)
    adapt = Image.alpha_composite(background(S).convert("RGBA"), foreground(S, 0.52))
    out = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    out.paste(adapt, (0, 0), mask)
    out.resize((256, 256), Image.LANCZOS).save("/tmp/icon_preview_round.png")
    print("ok")
