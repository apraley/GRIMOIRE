"""Numeric helpers, formatting, and small data structures used everywhere."""
from __future__ import annotations

import math
from collections import deque
from typing import Iterable, Sequence

from .serial import serializable


# ---------------------------------------------------------------- math ----

def clamp(x: float, lo: float, hi: float) -> float:
    return lo if x < lo else (hi if x > hi else x)


def clamp01(x: float) -> float:
    return clamp(x, 0.0, 1.0)


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def inv_lerp(a: float, b: float, x: float) -> float:
    if b == a:
        return 0.0
    return (x - a) / (b - a)


def smoothstep(a: float, b: float, x: float) -> float:
    t = clamp01(inv_lerp(a, b, x))
    return t * t * (3 - 2 * t)


def sigmoid(x: float, k: float = 1.0) -> float:
    x = clamp(x * k, -60, 60)
    return 1.0 / (1.0 + math.exp(-x))


def logit(p: float) -> float:
    p = clamp(p, 1e-6, 1 - 1e-6)
    return math.log(p / (1 - p))


def softmax(vals: Sequence[float], temp: float = 1.0) -> list[float]:
    if not vals:
        return []
    m = max(vals)
    ex = [math.exp(clamp((v - m) / max(temp, 1e-6), -60, 60)) for v in vals]
    s = sum(ex) or 1.0
    return [e / s for e in ex]


def approach(cur: float, target: float, rate: float) -> float:
    """Exponential relaxation toward a target. rate in [0,1] per step."""
    return cur + (target - cur) * clamp01(rate)


def decay(cur: float, rate: float, floor: float = 0.0) -> float:
    return floor + (cur - floor) * clamp01(1.0 - rate)


def mean(vals: Iterable[float]) -> float:
    vs = list(vals)
    return sum(vs) / len(vs) if vs else 0.0


def wmean(pairs: Iterable[tuple[float, float]]) -> float:
    """pairs of (value, weight)."""
    num = 0.0
    den = 0.0
    for v, w in pairs:
        num += v * w
        den += w
    return num / den if den else 0.0


def stdev(vals: Iterable[float]) -> float:
    vs = list(vals)
    if len(vs) < 2:
        return 0.0
    m = mean(vs)
    return math.sqrt(sum((v - m) ** 2 for v in vs) / (len(vs) - 1))


def gini(vals: Sequence[float]) -> float:
    vs = sorted(v for v in vals if v >= 0)
    n = len(vs)
    if n == 0:
        return 0.0
    tot = sum(vs)
    if tot <= 0:
        return 0.0
    cum = 0.0
    for i, v in enumerate(vs, 1):
        cum += i * v
    return clamp01((2 * cum) / (n * tot) - (n + 1) / n)


def herfindahl(shares: Iterable[float]) -> float:
    """Market concentration, 0..1."""
    ss = [s for s in shares if s > 0]
    tot = sum(ss) or 1.0
    return sum((s / tot) ** 2 for s in ss)


def cobb_douglas(factors: Sequence[float], exponents: Sequence[float]) -> float:
    out = 1.0
    for f, e in zip(factors, exponents):
        out *= max(f, 1e-9) ** e
    return out


def ces(inputs: Sequence[float], weights: Sequence[float], rho: float = -0.5) -> float:
    """Constant-elasticity-of-substitution aggregator."""
    tot = 0.0
    for x, w in zip(inputs, weights):
        tot += w * max(x, 1e-9) ** rho
    return max(tot, 1e-9) ** (1.0 / rho)


def haversine(lat1: float, lon1: float, lat2: float, lon2: float, radius: float = 6371.0) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * radius * math.asin(min(1.0, math.sqrt(a)))


# ---------------------------------------------------------- formatting ----

_SUFFIX = [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "k")]


def fmt_num(x: float, places: int = 1) -> str:
    neg = x < 0
    x = abs(float(x))
    for scale, suf in _SUFFIX:
        if x >= scale:
            s = f"{x / scale:.{places}f}{suf}"
            break
    else:
        s = f"{x:.{places}f}" if x < 100 else f"{x:.0f}"
    return ("-" + s) if neg else s


def fmt_money(x: float, unit: str = "$", places: int = 1) -> str:
    return unit + fmt_num(x, places)


def fmt_int(x: float) -> str:
    return f"{int(round(x)):,}"


def fmt_pct(x: float, places: int = 1, signed: bool = False) -> str:
    v = x * 100.0
    sign = "+" if (signed and v >= 0) else ""
    return f"{sign}{v:.{places}f}%"


def fmt_signed(x: float, places: int = 1) -> str:
    return f"{'+' if x >= 0 else ''}{x:.{places}f}"


def ordinal(n: int) -> str:
    if 10 <= n % 100 <= 20:
        suf = "th"
    else:
        suf = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
    return f"{n}{suf}"


def plural(n: float, one: str, many: str | None = None) -> str:
    return one if abs(n - 1) < 1e-9 else (many or one + "s")


def titlecase(s: str) -> str:
    small = {"of", "the", "and", "in", "for", "de", "al", "von", "van"}
    parts = s.replace("_", " ").split()
    out = []
    for i, p in enumerate(parts):
        out.append(p if (p in small and i) else (p[:1].upper() + p[1:]))
    return " ".join(out)


def truncate(s: str, n: int) -> str:
    return s if len(s) <= n else s[: max(0, n - 1)] + "…"


def wrap(text: str, width: int = 88, indent: str = "") -> list[str]:
    words = text.split()
    lines: list[str] = []
    cur = indent
    for w in words:
        if len(cur) + len(w) + 1 > width and cur.strip():
            lines.append(cur.rstrip())
            cur = indent + w + " "
        else:
            cur += w + " "
    if cur.strip():
        lines.append(cur.rstrip())
    return lines or [""]


BARS = " ▁▂▃▄▅▆▇█"


def sparkline(vals: Sequence[float], width: int = 24) -> str:
    vs = list(vals)[-width:]
    if not vs:
        return ""
    lo, hi = min(vs), max(vs)
    if hi - lo < 1e-12:
        return "▄" * len(vs)
    return "".join(BARS[int(clamp01((v - lo) / (hi - lo)) * 8)] for v in vs)


def meter(x: float, width: int = 12, lo: float = 0.0, hi: float = 1.0,
          full: str = "█", empty: str = "░") -> str:
    t = clamp01(inv_lerp(lo, hi, x))
    n = int(round(t * width))
    return full * n + empty * (width - n)


# ------------------------------------------------------- data holders ----

@serializable
class Series:
    """A bounded time series with cheap statistics."""

    def __init__(self, maxlen: int = 400, initial: float | None = None):
        self.maxlen = maxlen
        self.vals: deque[float] = deque(maxlen=maxlen)
        if initial is not None:
            self.vals.append(float(initial))

    def push(self, v: float) -> None:
        self.vals.append(float(v))

    @property
    def last(self) -> float:
        return self.vals[-1] if self.vals else 0.0

    @property
    def first(self) -> float:
        return self.vals[0] if self.vals else 0.0

    def avg(self, n: int = 0) -> float:
        vs = list(self.vals)[-n:] if n else list(self.vals)
        return mean(vs)

    def change(self, n: int = 30) -> float:
        vs = list(self.vals)
        if len(vs) < 2:
            return 0.0
        old = vs[max(0, len(vs) - 1 - n)]
        if abs(old) < 1e-9:
            return 0.0
        return (vs[-1] - old) / abs(old)

    def spark(self, width: int = 24) -> str:
        return sparkline(self.vals, width)

    def __len__(self) -> int:
        return len(self.vals)


@serializable
class Counter(dict):
    """dict subclass with += semantics for floats."""

    def add(self, key, amount: float = 1.0):
        self[key] = self.get(key, 0.0) + amount
        return self[key]

    def top(self, n: int = 5):
        return sorted(self.items(), key=lambda kv: -kv[1])[:n]

    def total(self) -> float:
        return sum(self.values())

    def normalized(self) -> dict:
        t = self.total() or 1.0
        return {k: v / t for k, v in self.items()}


def top_n(d: dict, n: int = 5, key=None):
    key = key or (lambda kv: -kv[1])
    return sorted(d.items(), key=key)[:n]


def roman(n: int) -> str:
    table = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"),
             (90, "XC"), (50, "L"), (40, "XL"), (10, "X"), (9, "IX"),
             (5, "V"), (4, "IV"), (1, "I")]
    out = []
    for v, s in table:
        while n >= v:
            out.append(s)
            n -= v
    return "".join(out) or "N"
