"""Terminal presentation: colour, boxes, tables, menus, pagers."""
from __future__ import annotations

import os
import shutil
import sys

from .util import clamp01, truncate, wrap

_NOCOLOR = bool(os.environ.get("NO_COLOR")) or not sys.stdout.isatty()

C = {
    "reset": "\033[0m", "b": "\033[1m", "dim": "\033[2m", "it": "\033[3m",
    "u": "\033[4m", "rev": "\033[7m",
    "k": "\033[30m", "r": "\033[31m", "g": "\033[32m", "y": "\033[33m",
    "bl": "\033[34m", "m": "\033[35m", "c": "\033[36m", "w": "\033[37m",
    "K": "\033[90m", "R": "\033[91m", "G": "\033[92m", "Y": "\033[93m",
    "B": "\033[94m", "M": "\033[95m", "Cy": "\033[96m", "W": "\033[97m",
    "bgr": "\033[41m", "bgg": "\033[42m", "bgy": "\033[43m", "bgb": "\033[44m",
    "bgm": "\033[45m", "bgc": "\033[46m", "bgk": "\033[100m",
}


def set_color(enabled: bool) -> None:
    global _NOCOLOR
    _NOCOLOR = not enabled


def color_enabled() -> bool:
    return not _NOCOLOR


def c(text: str, *styles: str) -> str:
    if _NOCOLOR or not styles:
        return text
    return "".join(C.get(s, "") for s in styles) + text + C["reset"]


def strip(text: str) -> str:
    out, i = [], 0
    while i < len(text):
        if text[i] == "\033":
            j = text.find("m", i)
            if j == -1:
                break
            i = j + 1
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def vlen(text: str) -> int:
    return len(strip(text))


def pad(text: str, width: int, align: str = "<") -> str:
    n = width - vlen(text)
    if n <= 0:
        return text
    if align == ">":
        return " " * n + text
    if align == "^":
        left = n // 2
        return " " * left + text + " " * (n - left)
    return text + " " * n


def term_width(default: int = 100) -> int:
    try:
        w = shutil.get_terminal_size((default, 30)).columns
    except Exception:
        w = default
    return max(64, min(w, 160))


# ------------------------------------------------------------- output ----

def out(*lines: str) -> None:
    for ln in lines:
        print(ln)


def rule(char: str = "─", style: str = "K", width: int | None = None) -> str:
    return c(char * (width or term_width()), style)


def header(title: str, sub: str = "", style: str = "Cy") -> str:
    w = term_width()
    left = f"── {title} "
    right = f" {sub} ──" if sub else "──"
    fill = max(0, w - vlen(left) - vlen(right))
    return c(left, "b", style) + c("─" * fill, "K") + c(right, "K")


def box(title: str, lines: list[str], style: str = "K", width: int | None = None) -> list[str]:
    w = width or term_width()
    inner = w - 2
    top = c("┌─ ", style) + c(title, "b") + c(" " + "─" * max(0, inner - 4 - vlen(title)) + "┐", style)
    body = [c("│", style) + pad(" " + ln, inner) + c("│", style) for ln in lines]
    bot = c("└" + "─" * inner + "┘", style)
    return [top] + body + [bot]


def table(rows: list[list[str]], headers: list[str] | None = None,
          aligns: list[str] | None = None, gap: str = "  ",
          hstyle: tuple[str, ...] = ("b", "K")) -> list[str]:
    if not rows and not headers:
        return []
    ncol = max(len(r) for r in (rows + ([headers] if headers else []))) if (rows or headers) else 0
    grid = [list(r) + [""] * (ncol - len(r)) for r in rows]
    widths = [0] * ncol
    if headers:
        for i, h in enumerate(headers):
            widths[i] = max(widths[i], vlen(h))
    for r in grid:
        for i, cell in enumerate(r):
            widths[i] = max(widths[i], vlen(str(cell)))
    aligns = (aligns or []) + ["<"] * (ncol - len(aligns or []))
    lines = []
    if headers:
        lines.append(gap.join(c(pad(h, widths[i], aligns[i]), *hstyle)
                              for i, h in enumerate(headers)))
    for r in grid:
        lines.append(gap.join(pad(str(cell), widths[i], aligns[i]) for i, cell in enumerate(r)))
    return lines


def kv(pairs: list[tuple[str, str]], cols: int = 2, keyw: int = 22) -> list[str]:
    chunks = []
    for i in range(0, len(pairs), cols):
        row = pairs[i:i + cols]
        chunks.append("   ".join(c(pad(k + ":", keyw), "K") + str(v) for k, v in row))
    return chunks


def bullet(text: str, mark: str = "•", style: str = "K", width: int | None = None) -> list[str]:
    w = (width or term_width()) - 3
    ls = wrap(text, w)
    return [c(f" {mark} ", style) + ls[0]] + ["   " + l for l in ls[1:]]


def para(text: str, indent: str = "", width: int | None = None) -> list[str]:
    return wrap(text, (width or term_width()) - len(indent), indent)


def meter(x: float, width: int = 12, lo: float = 0.0, hi: float = 1.0,
          full: str = "█", empty: str = "░") -> str:
    """An inline bar (no label, no colour) for embedding mid-line."""
    t = clamp01((x - lo) / (hi - lo) if hi > lo else 0)
    n = int(round(t * width))
    return full * n + empty * (width - n)


def gauge(label: str, x: float, lo: float = 0.0, hi: float = 1.0, width: int = 18,
          good_high: bool = True, suffix: str = "") -> str:
    t = clamp01((x - lo) / (hi - lo) if hi > lo else 0)
    n = int(round(t * width))
    q = t if good_high else 1 - t
    col = "G" if q > 0.66 else ("Y" if q > 0.33 else "R")
    bar = c("█" * n, col) + c("░" * (width - n), "K")
    return f"{pad(label, 20)}{bar} {pad(suffix or f'{x:.2f}', 8, '>')}"


def heat(x: float, lo: float = 0.0, hi: float = 1.0, good_high: bool = True) -> str:
    t = clamp01((x - lo) / (hi - lo) if hi > lo else 0)
    q = t if good_high else 1 - t
    return "G" if q > 0.7 else ("g" if q > 0.55 else ("y" if q > 0.4 else ("r" if q > 0.2 else "R")))


def tint(text: str, x: float, lo: float = 0.0, hi: float = 1.0, good_high: bool = True) -> str:
    return c(text, heat(x, lo, hi, good_high))


def delta(x: float, places: int = 1, suffix: str = "", invert: bool = False) -> str:
    s = f"{'+' if x >= 0 else ''}{x:.{places}f}{suffix}"
    good = (x >= 0) != invert
    return c(s, "G" if x > 0 else ("R" if x < 0 else "K")) if not invert else \
        c(s, "G" if good else "R")


def banner(text: str, style: str = "Cy") -> list[str]:
    w = term_width()
    return [c("╔" + "═" * (w - 2) + "╗", style),
            c("║", style) + c(pad(text, w - 2, "^"), "b") + c("║", style),
            c("╚" + "═" * (w - 2) + "╝", style)]


def columns(items: list[str], cols: int = 3, width: int | None = None) -> list[str]:
    if not items:
        return []
    w = (width or term_width()) // cols
    rows = (len(items) + cols - 1) // cols
    out_lines = []
    for r in range(rows):
        line = ""
        for cx in range(cols):
            i = cx * rows + r
            if i < len(items):
                line += pad(truncate(items[i], w - 2), w)
        out_lines.append(line.rstrip())
    return out_lines


def page(lines: list[str], size: int = 0) -> None:
    """Print lines, pausing every `size` rows when output is long."""
    size = size or max(12, shutil.get_terminal_size((100, 30)).lines - 6)
    if len(lines) <= size * 1.5 or not sys.stdin.isatty():
        out(*lines)
        return
    i = 0
    while i < len(lines):
        out(*lines[i:i + size])
        i += size
        if i < len(lines):
            try:
                r = input(c(f"  ── more ({i}/{len(lines)}) — enter to continue, q to stop ── ", "K"))
            except (EOFError, KeyboardInterrupt):
                return
            if r.strip().lower().startswith("q"):
                return
