"""Font discovery (text fonts for page paragraphs, glyph fonts for chess
figurines). Everything is optional: whatever fonts the machine has are used."""
import glob
import os
from functools import lru_cache

from PIL import ImageFont

_ALL = sorted(set(glob.glob("/usr/share/fonts/**/*.ttf", recursive=True)
                  + glob.glob("/usr/share/fonts/**/*.otf", recursive=True)))
_BAD = ("symbol", "emoji", "math", "cjk", "wqy", "japanese", "opens", "ding",
        "kacst", "lohit", "noto", "mono-bold", "extralight", "gfs")


def _usable(p):
    low = os.path.basename(p).lower()
    return not any(b in low for b in _BAD)


TEXT_FONTS = [p for p in _ALL if _usable(p)]
SERIF = [p for p in TEXT_FONTS if "serif" in p.lower() and "sans" not in p.lower()
         or "caladea" in p.lower() or "lora" in p.lower()]
SANS = [p for p in TEXT_FONTS if "sans" in p.lower() or "carlito" in p.lower()
        or "poppins" in p.lower()]
MONO = [p for p in TEXT_FONTS if "mono" in p.lower()]
if not SERIF:
    SERIF = TEXT_FONTS[:]
if not SANS:
    SANS = TEXT_FONTS[:]

# Candidate fonts for Unicode chess glyphs (checked for real glyph support
# in pieces.py).
GLYPH_CANDIDATES = [p for p in _ALL if any(
    k in os.path.basename(p).lower()
    for k in ("dejavusans.ttf", "dejavusansmono.ttf",
              "dejavuserif.ttf", "freeserif.ttf", "freesans.ttf",
              "freemono.ttf", "notosanssymbols2", "symbola"))]


@lru_cache(maxsize=512)
def load(path, size):
    size = max(6, int(size))
    if not path:
        return ImageFont.load_default()
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()


def pick(rng, kind="serif"):
    lst = {"serif": SERIF, "sans": SANS, "mono": MONO}.get(kind) or TEXT_FONTS
    if not lst:
        return None
    return lst[int(rng.integers(len(lst)))]
