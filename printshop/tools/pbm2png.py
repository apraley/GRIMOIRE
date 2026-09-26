#!/usr/bin/env python3
"""Converts tests/out/*.pbm screenshots to 2x PNGs and a contact sheet."""
import pathlib
from PIL import Image
out = pathlib.Path(__file__).resolve().parent.parent / "tests/out"
imgs = []
for p in sorted(out.glob("*.pbm")):
    im = Image.open(p).convert("1")
    im.resize((800, 480), Image.NEAREST).save(p.with_suffix(".png"))
    imgs.append(im)
print(len(imgs), "screenshots")
