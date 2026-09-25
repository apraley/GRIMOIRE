#!/usr/bin/env python3
"""Convert a P1 PBM screenshot from the mock runtime into a 2x PNG."""
import sys
from PIL import Image

src = sys.argv[1]
with open(src) as f:
    assert f.readline().strip() == "P1"
    w, h = map(int, f.readline().split())
    bits = f.read().split()
img = Image.new("1", (w, h))
img.putdata([0 if b == "1" else 1 for b in bits])
img = img.resize((w * 2, h * 2), Image.NEAREST)
img.save(src[:-4] + ".png")
