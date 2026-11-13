"""Writes ChessLens launcher icons into the Android and iOS projects.

Run from the repository root:  python3 tools/icon/install_icons.py
Needs Pillow and the DejaVu Sans font (for the knight glyph).
"""
import json, os, sys
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
import make_icon as m

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RES = os.path.join(ROOT, "app/android/app/src/main/res")
IOS = os.path.join(ROOT, "app/ios/Runner/Assets.xcassets/AppIcon.appiconset")
S = 1024

full = m.background(S).convert("RGBA")
full = Image.alpha_composite(full, m.foreground(S, 0.62)).convert("RGB")
full.save(os.path.join(ROOT, "tools/icon/icon_1024.png"))

# Android legacy icons and adaptive layers (108dp canvas, 66% safe zone).
legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
for density, px in legacy.items():
    d = os.path.join(RES, f"mipmap-{density}")
    os.makedirs(d, exist_ok=True)
    full.resize((px, px), Image.LANCZOS).save(os.path.join(d, "ic_launcher.png"))
    fg_px = px * 108 // 48
    m.foreground(S, 0.46).resize((fg_px, fg_px), Image.LANCZOS).save(
        os.path.join(d, "ic_launcher_foreground.png"))

os.makedirs(os.path.join(RES, "mipmap-anydpi-v26"), exist_ok=True)
with open(os.path.join(RES, "mipmap-anydpi-v26/ic_launcher.xml"), "w") as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '</adaptive-icon>\n')
with open(os.path.join(RES, "values/ic_launcher_colors.xml"), "w") as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
            '    <color name="ic_launcher_background">#2F5A42</color>\n</resources>\n')

# iOS: same file names and sizes as the existing Contents.json.
images = json.load(open(os.path.join(IOS, "Contents.json")))["images"]
for img in images:
    name = img.get("filename")
    if not name:
        continue
    pt = float(img["size"].split("x")[0])
    px = round(pt * float(img["scale"].rstrip("x")))
    full.resize((px, px), Image.LANCZOS).save(os.path.join(IOS, name))
print("icons written")
