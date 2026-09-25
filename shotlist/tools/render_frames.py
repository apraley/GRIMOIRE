#!/usr/bin/env python3
"""Render SHOT LIST headless display lists (tests/*.json frames) to PNG.

The Lua harness records Playdate graphics calls; this rasterises them at 1-bit
(400x240) so screens can be reviewed without the Simulator. Text uses a stand-in
TTF stretched to the harness's Asheville-like metrics, so layout (positions,
widths, truncation) is faithful even though glyph shapes differ from the device.

usage: render_frames.py OUT_DIR frame.json [frame.json ...]
       render_frames.py --sheet OUT.png frame.json [...]   (contact sheet, 2x)
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

W, H = 400, 240
FONT_DIR = "/usr/share/fonts/truetype/dejavu/"
FONTS = {
    "normal": ImageFont.truetype(FONT_DIR + "DejaVuSans.ttf", 12),
    "bold": ImageFont.truetype(FONT_DIR + "DejaVuSans-Bold.ttf", 12),
    "italic": ImageFont.truetype(FONT_DIR + "DejaVuSans.ttf", 12),
}
BLACK, WHITE, CLEAR = 0, 1, 2
FILL_WHITE = 3


def dither_mask(size, alpha):
    m = Image.new("1", size, 0)
    px = m.load()
    for y in range(size[1]):
        for x in range(size[0]):
            if (x + y) % 2 == 0:
                px[x, y] = 1
    return m


_DITHER = None


def render(cmds, w=W, h=H, bg=255):
    global _DITHER
    if _DITHER is None:
        _DITHER = dither_mask((W, H), 0.5)
    img = Image.new("L", (w, h), bg)
    clip = None
    for c in cmds:
        op = c["op"]
        if op == "clip":
            clip = (c["x"], c["y"], c["x"] + c["w"], c["y"] + c["h"]) if "x" in c else None
            continue
        if op == "clear":
            img.paste(0 if c.get("c", 1) == BLACK else 255, (0, 0, w, h))
            continue
        mask = Image.new("1", (w, h), 0)
        d = ImageDraw.Draw(mask)
        lw = int(c.get("lw") or 1)
        if op == "fillRect":
            if c["w"] > 0 and c["h"] > 0:
                r = c.get("r")
                box = [c["x"], c["y"], c["x"] + c["w"] - 1, c["y"] + c["h"] - 1]
                if r:
                    d.rounded_rectangle(box, radius=r, fill=1)
                else:
                    d.rectangle(box, fill=1)
        elif op == "drawRect":
            box = [c["x"], c["y"], c["x"] + c["w"] - 1, c["y"] + c["h"] - 1]
            if c.get("r"):
                d.rounded_rectangle(box, radius=c["r"], outline=1, width=lw)
            else:
                d.rectangle(box, outline=1, width=lw)
        elif op == "line":
            d.line([c["x1"], c["y1"], c["x2"], c["y2"]], fill=1, width=lw)
        elif op == "fillCircle":
            r = c["r"]
            d.ellipse([c["x"] - r, c["y"] - r, c["x"] + r, c["y"] + r], fill=1)
        elif op == "drawCircle":
            r = c["r"]
            d.ellipse([c["x"] - r, c["y"] - r, c["x"] + r, c["y"] + r], outline=1, width=lw)
        elif op == "tri":
            p = c["p"]
            d.polygon([(p[0], p[1]), (p[2], p[3]), (p[4], p[5])], fill=1)
        elif op == "text":
            s = c["s"]
            tw = max(1, int(c["w"]))
            f = FONTS.get(c.get("font", "normal"), FONTS["normal"])
            box = f.getbbox(s) if s else (0, 0, 1, 1)
            nat = max(1, box[2])
            tmp = Image.new("L", (nat + 2, 18), 0)
            ImageDraw.Draw(tmp).text((0, 1), s, font=f, fill=255)
            tmp = tmp.resize((tw, 18), Image.NEAREST).point(lambda v: 255 if v > 110 else 0).convert("1")
            mask.paste(tmp, (int(c["x"]), int(c["y"])), tmp)
        elif op == "image":
            sub = c["img"]
            bgv = 255 if sub.get("bg", 1) == WHITE else (0 if sub.get("bg") == BLACK else 255)
            simg = render(sub["cmds"], sub["w"], sub["h"], bgv)
            s = c.get("s", 1)
            simg = simg.resize((int(sub["w"] * s), int(sub["h"] * c.get("ys", s))), Image.NEAREST)
            img.paste(simg, (int(c["x"]), int(c["y"])))
            continue
        else:
            continue
        if c.get("alpha") is not None:
            full = Image.new("1", (w, h), 0)
            full.paste(_DITHER.crop((0, 0, w, h)), (0, 0))
            mask = Image.composite(mask, Image.new("1", (w, h), 0), full)
        if clip:
            cm = Image.new("1", (w, h), 0)
            ImageDraw.Draw(cm).rectangle([clip[0], clip[1], clip[2] - 1, clip[3] - 1], fill=1)
            mask = Image.composite(mask, Image.new("1", (w, h), 0), cm)
        white = (op == "text" and c.get("mode") == FILL_WHITE) or (op != "text" and c.get("color") == WHITE)
        img.paste(255 if white else 0, (0, 0, w, h), mask)
    return img


def load(path):
    with open(path) as fh:
        return json.load(fh)


def main(argv):
    if argv and argv[0] == "--sheet":
        out, files = argv[1], argv[2:]
        frames = [(os.path.splitext(os.path.basename(f))[0], render(load(f)["cmds"])) for f in files]
        cols = 2
        rows = (len(frames) + cols - 1) // cols
        sheet = Image.new("L", (cols * (W * 2 + 20), rows * (H * 2 + 40)), 200)
        d = ImageDraw.Draw(sheet)
        for i, (name, im) in enumerate(frames):
            x, y = (i % cols) * (W * 2 + 20) + 10, (i // cols) * (H * 2 + 40) + 28
            d.text((x, y - 20), name, fill=0, font=FONTS["bold"])
            sheet.paste(im.resize((W * 2, H * 2), Image.NEAREST), (x, y))
        sheet.save(out)
        return
    out, files = argv[0], argv[1:]
    os.makedirs(out, exist_ok=True)
    for f in files:
        name = os.path.splitext(os.path.basename(f))[0]
        render(load(f)["cmds"]).resize((W * 2, H * 2), Image.NEAREST).save(os.path.join(out, name + ".png"))


if __name__ == "__main__":
    main(sys.argv[1:])
