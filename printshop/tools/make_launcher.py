#!/usr/bin/env python3
"""Crops the rasterized launcher renders into source/launcher/*.png."""
import pathlib
from PIL import Image
root = pathlib.Path(__file__).resolve().parent.parent
out = root / "source/launcher"
out.mkdir(exist_ok=True)
Image.open(root / "tests/out/card.pbm").convert("1").crop((0, 0, 350, 155)).save(out / "card.png")
Image.open(root / "tests/out/icon.pbm").convert("1").crop((0, 0, 32, 32)).save(out / "icon.png")
print("wrote", out / "card.png", out / "icon.png")
