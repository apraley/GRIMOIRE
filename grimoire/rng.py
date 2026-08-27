"""Deterministic, stream-separated random number generation.

Every subsystem draws from a named sub-stream so that adding a die roll in one
system does not desynchronise every other system's history.  This keeps saves
reproducible and makes debugging tractable.
"""
from __future__ import annotations

import hashlib
import math
import random
from typing import Iterable, Sequence, TypeVar

from .serial import serializable

T = TypeVar("T")


def _seed_for(master: int, stream: str) -> int:
    h = hashlib.blake2b(f"{master}:{stream}".encode(), digest_size=8).digest()
    return int.from_bytes(h, "big")


@serializable
class RNG:
    """A named random stream with game-flavoured helpers."""

    def __init__(self, seed: int, stream: str = "main"):
        self.seed = int(seed)
        self.stream = stream
        self._r = random.Random(_seed_for(self.seed, stream))
        self._kids: dict[str, "RNG"] = {}

    # -- plumbing ---------------------------------------------------------
    def sub(self, stream: str) -> "RNG":
        if stream not in self._kids:
            self._kids[stream] = RNG(self.seed, f"{self.stream}/{stream}")
        return self._kids[stream]

    def getstate(self):
        return self._r.getstate()

    def setstate(self, st) -> None:
        self._r.setstate(st)

    def __getstate__(self):
        return {"seed": self.seed, "stream": self.stream,
                "state": self._r.getstate(), "kids": self._kids}

    def __setstate__(self, st):
        self.seed = st["seed"]
        self.stream = st["stream"]
        self._kids = st.get("kids", {})
        self._r = random.Random()
        try:
            self._r.setstate(st["state"])
        except (TypeError, ValueError):
            self._r.seed(_seed_for(self.seed, self.stream))

    # -- primitives -------------------------------------------------------
    def random(self) -> float:
        return self._r.random()

    def uniform(self, a: float, b: float) -> float:
        return self._r.uniform(a, b)

    def randint(self, a: int, b: int) -> int:
        return self._r.randint(a, b)

    def chance(self, p: float) -> bool:
        return self._r.random() < p

    def gauss(self, mu: float = 0.0, sigma: float = 1.0) -> float:
        return self._r.gauss(mu, sigma)

    def clamped_gauss(self, mu: float, sigma: float, lo: float, hi: float) -> float:
        return max(lo, min(hi, self._r.gauss(mu, sigma)))

    def lognorm(self, mu: float, sigma: float) -> float:
        return math.exp(self._r.gauss(math.log(max(mu, 1e-9)), sigma))

    def expo(self, mean: float) -> float:
        return self._r.expovariate(1.0 / max(mean, 1e-9))

    def pareto(self, alpha: float = 1.6, scale: float = 1.0) -> float:
        return scale * (self._r.paretovariate(alpha))

    def beta(self, a: float, b: float) -> float:
        return self._r.betavariate(a, b)

    def triangular(self, lo: float, hi: float, mode: float) -> float:
        return self._r.triangular(lo, hi, mode)

    def poisson(self, lam: float) -> int:
        """Knuth for small lambda, normal approximation for large."""
        if lam <= 0:
            return 0
        if lam > 30:
            return max(0, int(round(self._r.gauss(lam, math.sqrt(lam)))))
        l = math.exp(-lam)
        k, p = 0, 1.0
        while True:
            k += 1
            p *= self._r.random()
            if p <= l:
                return k - 1

    def binomial(self, n: int, p: float) -> int:
        if n <= 0 or p <= 0:
            return 0
        if p >= 1:
            return n
        if n > 40:
            mu, sd = n * p, math.sqrt(n * p * (1 - p))
            return max(0, min(n, int(round(self._r.gauss(mu, sd)))))
        return sum(1 for _ in range(n) if self._r.random() < p)

    # -- collections ------------------------------------------------------
    def pick(self, seq: Sequence[T]) -> T:
        return self._r.choice(list(seq))

    def pick_or(self, seq: Sequence[T], default=None):
        seq = list(seq)
        return self._r.choice(seq) if seq else default

    def sample(self, seq: Iterable[T], k: int) -> list[T]:
        pool = list(seq)
        k = max(0, min(k, len(pool)))
        return self._r.sample(pool, k)

    def shuffled(self, seq: Iterable[T]) -> list[T]:
        pool = list(seq)
        self._r.shuffle(pool)
        return pool

    def weighted(self, options: Sequence[T], weights: Sequence[float]) -> T:
        tot = sum(max(0.0, w) for w in weights)
        if tot <= 0:
            return self.pick(options)
        r = self._r.random() * tot
        acc = 0.0
        for o, w in zip(options, weights):
            acc += max(0.0, w)
            if r <= acc:
                return o
        return options[-1]

    def weighted_dict(self, d: dict):
        keys = list(d.keys())
        return self.weighted(keys, [d[k] for k in keys])

    def weighted_sample(self, options: Sequence[T], weights: Sequence[float], k: int) -> list[T]:
        opts = list(options)
        wts = [max(0.0, w) for w in weights]
        out: list[T] = []
        for _ in range(min(k, len(opts))):
            if sum(wts) <= 0:
                break
            pickd = self.weighted(opts, wts)
            i = opts.index(pickd)
            out.append(opts.pop(i))
            wts.pop(i)
        return out

    # -- game dice --------------------------------------------------------
    def d(self, sides: int, count: int = 1) -> int:
        return sum(self._r.randint(1, sides) for _ in range(count))

    def d100(self) -> int:
        return self._r.randint(1, 100)

    def check(self, skill: float, difficulty: float = 0.5, noise: float = 0.18):
        """Opposed roll. Returns (success, margin) with margin in roughly -1..1.

        `skill` and `difficulty` are both 0..1.  Margin > 0.35 is a critical
        success, margin < -0.35 a critical failure.
        """
        roll = self._r.gauss(0.0, noise)
        margin = (skill - difficulty) + roll
        return margin > 0.0, margin

    def jitter(self, x: float, frac: float = 0.1) -> float:
        return x * (1.0 + self._r.gauss(0.0, frac))

    def spread(self, n: int, total: float, alpha: float = 1.0) -> list[float]:
        """Dirichlet-ish split of `total` into n positive parts."""
        raw = [self._r.gammavariate(alpha, 1.0) for _ in range(max(1, n))]
        s = sum(raw) or 1.0
        return [total * r / s for r in raw]
