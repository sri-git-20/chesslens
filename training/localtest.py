"""Quick local check of data generation (glyph pieces only, no network)."""
import sys, time, os
import numpy as np, cv2
import fonts, pieces, synth, camera
import reference_pipeline as rp

styles = []
for p in fonts.GLYPH_CANDIDATES:
    if pieces.font_has_chess(p):
        styles += pieces.build_glyph_styles(p, holdout=False)
print("glyph styles", [s.name for s in styles])
lib = pieces.PieceLibrary(styles)
os.makedirs("/tmp/prev", exist_ok=True)
t = time.time()
N = int(sys.argv[1]) if len(sys.argv) > 1 else 12
for i in range(N):
    cat = ["clean", "photo", "screenshot"][i % 3]
    s = synth.make_sample(1000 + i, lib, cat)
    print(i, cat, s.kind, s.img.shape, len(s.boards))
    im = s.img.copy()
    for b in s.boards:
        cv2.polylines(im, [b["quad"].astype(np.int32).reshape(-1, 1, 2)], True, (255, 0, 0), 2)
    cv2.imwrite(f"/tmp/prev/{i:02d}_{cat}.jpg", cv2.cvtColor(im, cv2.COLOR_RGB2BGR))
    a = synth.to_training(i, s)
    if a["cor_x"]:
        cv2.imwrite(f"/tmp/prev/{i:02d}_sq.png", a["sq_x"][0])
        c = cv2.cvtColor(a["cor_x"][0], cv2.COLOR_GRAY2BGR)
        for p in a["cor_y"][0]:
            cv2.circle(c, (int(p[0]), int(p[1])), 4, (0, 0, 255), -1)
        cv2.imwrite(f"/tmp/prev/{i:02d}_cor.png", c)
print("time/sample", (time.time() - t) / N)
