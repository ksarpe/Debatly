#!/usr/bin/env python3
"""Generate assets/images/splash_icon_android12.png from icon.png.

Android 12+ masks the native-splash icon to a circle and only shows the inner
~2/3 of the canvas (the outer third is always clipped). A full-bleed "D" (as in
icon.png) therefore gets its edges chopped on the splash. This script re-centres
the mark and scales it down so the whole letter — shadow included — fits inside
that safe circle, padding the rest with the exact brand orange (#FF751F) so the
padding is invisible.

flutter_native_splash uses the android_12 image as-is (it does NOT add safe-zone
padding), so the padding has to live in the source PNG.

Run from the repo root:
    python tool/gen_android12_splash.py
then regenerate the drawables:
    dart run flutter_native_splash:create

Requires Pillow (`pip install Pillow`).
"""
import math
from PIL import Image

SRC = "assets/images/icon.png"
DST = "assets/images/splash_icon_android12.png"
ORANGE = (255, 117, 31)  # #FF751F, sampled from icon.png's corner
SAFE_FRACTION = 2 / 3     # Android 12 visible-circle diameter as a fraction of canvas
MARGIN = 0.98             # extra breathing room inside the safe circle


def bbox_of_mark(im, bg, thr=40):
    """Bounding box of pixels differing from the background (the "D" + shadow)."""
    px = im.load()
    w, h = im.size
    minx, miny, maxx, maxy = w, h, 0, 0
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            c = px[x, y]
            if abs(c[0] - bg[0]) + abs(c[1] - bg[1]) + abs(c[2] - bg[2]) > thr:
                minx, maxx = min(minx, x), max(maxx, x)
                miny, maxy = min(miny, y), max(maxy, y)
    return minx, miny, maxx, maxy


def main():
    src = Image.open(SRC).convert("RGB")
    w, _ = src.size
    minx, miny, maxx, maxy = bbox_of_mark(src, ORANGE)
    bw, bh = maxx - minx, maxy - miny
    half_diag = math.hypot(bw / 2, bh / 2)
    safe_r = w * SAFE_FRACTION / 2
    f = safe_r / half_diag * MARGIN

    scaled = src.resize((round(w * f), round(w * f)), Image.LANCZOS)
    bcx, bcy = (minx + maxx) / 2 * f, (miny + maxy) / 2 * f  # mark centre in scaled img
    out = Image.new("RGB", (w, w), ORANGE)
    out.paste(scaled, (round(w / 2 - bcx), round(w / 2 - bcy)))
    out.save(DST)
    print(f"{DST}: scaled to {f:.3f}, mark bbox now "
          f"{round(bw * f)}x{round(bh * f)} ({bw * f / w:.0%} of canvas), centred")


if __name__ == "__main__":
    main()
