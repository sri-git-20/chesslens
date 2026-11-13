import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 1024
GREEN_TOP, GREEN_BOT = (58, 107, 79), (36, 72, 52)
CREAM = (246, 240, 225)
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

def background(size):
    img = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        c = tuple(round(a + (b - a) * t) for a, b in zip(GREEN_TOP, GREEN_BOT))
        d.line([(0, y), (size, y)], fill=c)
    return img

def foreground(size, scale):
    """Knight in viewfinder brackets on transparent canvas; scale = content size / canvas."""
    fg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(fg)
    c = size / 2
    box = size * scale          # side of the bracket square
    half = box / 2
    arm = box * 0.24            # bracket arm length
    w = max(4, round(size * 0.028))
    for sx in (-1, 1):
        for sy in (-1, 1):
            x0, y0 = c + sx * half, c + sy * half
            d.line([(x0, y0), (x0 - sx * arm, y0)], fill=CREAM, width=w)
            d.line([(x0, y0), (x0, y0 - sy * arm)], fill=CREAM, width=w)
            r = w / 2
            d.ellipse([x0 - r, y0 - r, x0 + r, y0 + r], fill=CREAM)
    # Knight glyph, sized to sit inside the brackets.
    font = ImageFont.truetype(FONT, round(box * 0.86))
    glyph = "♞"
    l, t, r_, b = d.textbbox((0, 0), glyph, font=font)
    gx = c - (l + r_) / 2
    gy = c - (t + b) / 2 + box * 0.01
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((gx, gy + size * 0.012), glyph, font=font, fill=(0, 0, 0, 90))
    fg = Image.alpha_composite(fg, shadow.filter(ImageFilter.GaussianBlur(size * 0.01)))
    ImageDraw.Draw(fg).text((gx, gy), glyph, font=font, fill=CREAM)
    return fg

if __name__ == "__main__":
    full = background(S).convert("RGBA")
    full = Image.alpha_composite(full, foreground(S, 0.62))
    full.convert("RGB").save("icon.png")
    # Adaptive foreground: keep content inside the 66% safe zone.
    foreground(S, 0.46).save("icon_foreground.png")
    full.convert("RGB").resize((256, 256), Image.LANCZOS).save("preview_256.png")
    # Preview how a round mask would look.
    mask = Image.new("L", (S, S), 0); ImageDraw.Draw(mask).ellipse([0, 0, S, S], fill=255)
    round_ = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    adapt = Image.alpha_composite(background(S).convert("RGBA"), foreground(S, 0.46))
    round_.paste(adapt, (0, 0), mask)
    round_.resize((256, 256), Image.LANCZOS).save("preview_round.png")
    print("ok")
