"""Planet generation: tectonics, elevation, climate, biomes, rivers, rendering.

The map is a cylindrical grid (wraps east-west, poles at top and bottom).  It
exists to give the political and economic layers a physical substrate: where
crops grow, where ore is, which straits a navy can close.
"""
from __future__ import annotations

import math

from .content_econ import BIOMES, RESOURCE_KINDS
from .rng import RNG
from .serial import serializable
from .util import clamp, clamp01, inv_lerp, lerp, smoothstep

W, H = 160, 76          # grid dimensions
SEA_LEVEL = 0.42
_SEA = [SEA_LEVEL]      # live sea level, updated as a planet is generated/loaded


def _lat(y: int) -> float:
    return 90.0 - 180.0 * (y + 0.5) / H


def _lon(x: int) -> float:
    return -180.0 + 360.0 * (x + 0.5) / W


class _Noise:
    """Wrapping value noise with fractal octaves."""

    def __init__(self, rng: RNG, gw: int = 8, gh: int = 5):
        self.gw, self.gh = gw, gh
        self.g = [[rng.random() for _ in range(gw)] for _ in range(gh)]

    def at(self, u: float, v: float) -> float:
        fx, fy = u * self.gw, v * self.gh
        x0, y0 = int(math.floor(fx)), int(math.floor(fy))
        tx, ty = fx - x0, fy - y0
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        g = self.g
        a = g[y0 % self.gh][x0 % self.gw]
        b = g[y0 % self.gh][(x0 + 1) % self.gw]
        cc = g[(y0 + 1) % self.gh][x0 % self.gw]
        d = g[(y0 + 1) % self.gh][(x0 + 1) % self.gw]
        return lerp(lerp(a, b, tx), lerp(cc, d, tx), ty)


def _fractal(rng: RNG, octaves: int = 5, base: int = 5) -> list[list[float]]:
    layers = [(_Noise(rng, base * 2 ** i, max(2, (base - 1) * 2 ** i)), 0.5 ** i)
              for i in range(octaves)]
    norm = sum(w for _, w in layers)
    out = []
    for y in range(H):
        row = []
        v = (y + 0.5) / H
        for x in range(W):
            u = (x + 0.5) / W
            row.append(sum(n.at(u, v) * w for n, w in layers) / norm)
        out.append(row)
    return out


@serializable
class Tile:
    __slots__ = ("x", "y", "elev", "temp", "moist", "biome", "region", "plate",
                 "river", "coastal", "res")

    def __init__(self, x: int, y: int):
        self.x, self.y = x, y
        self.elev = 0.0
        self.temp = 0.0
        self.moist = 0.0
        self.biome = "ocean"
        self.region: str | None = None
        self.plate = 0
        self.river = 0.0
        self.coastal = False
        self.res: dict[str, float] = {}

    @property
    def land(self) -> bool:
        return self.elev >= _SEA[0]

    @property
    def lat(self) -> float:
        return _lat(self.y)

    @property
    def lon(self) -> float:
        return _lon(self.x)

    def __getstate__(self):
        return {k: getattr(self, k) for k in self.__slots__}

    def __setstate__(self, st):
        for k, v in st.items():
            setattr(self, k, v)


@serializable
class Planet:
    def __init__(self):
        self.w, self.h = W, H
        self.tiles: list[list[Tile]] = []
        self.continents: dict[int, str] = {}
        self.tile_continent: dict[tuple[int, int], int] = {}
        self._sea_level = SEA_LEVEL
        self.mountain_level = 0.80
        self.hill_level = 0.65
        self.max_elev = 1.0
        self.co2 = 421.0
        self.temp_anomaly = 1.28
        self.sea_rise = 0.0

    @property
    def sea_level(self) -> float:
        return self._sea_level

    @sea_level.setter
    def sea_level(self, v: float) -> None:
        self._sea_level = v
        _SEA[0] = v

    def activate(self) -> None:
        """Make this the planet whose sea level Tile.land consults."""
        _SEA[0] = self._sea_level

    # -- access ------------------------------------------------------------
    def t(self, x: int, y: int) -> Tile:
        return self.tiles[max(0, min(self.h - 1, y))][x % self.w]

    def neighbours(self, x: int, y: int, diag: bool = True):
        offs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        if diag:
            offs += [(-1, -1), (1, -1), (-1, 1), (1, 1)]
        for dx, dy in offs:
            ny = y + dy
            if 0 <= ny < self.h:
                yield self.t(x + dx, ny)

    def land_tiles(self):
        for row in self.tiles:
            for t in row:
                if t.land:
                    yield t

    def all_tiles(self):
        for row in self.tiles:
            yield from row


# ------------------------------------------------------------- generation --

def generate(rng: RNG, target_land: float = 0.0) -> Planet:
    p = Planet()
    p.tiles = [[Tile(x, y) for x in range(W)] for y in range(H)]
    target_land = target_land or rng.uniform(0.255, 0.325)

    # 1. continental masses: elongated blobs that the noise then erodes
    ncont = rng.randint(5, 7)
    blobs = []
    for _ in range(ncont):
        cx = rng.randint(0, W - 1)
        cy = int(rng.clamped_gauss(H / 2, H * 0.22, H * 0.16, H * 0.84))
        rx = rng.uniform(W * 0.07, W * 0.20)
        ry = rng.uniform(H * 0.10, H * 0.30)
        blobs.append((cx, cy, rx, ry, rng.uniform(0.75, 1.15)))
    # a scatter of islands and archipelagos
    for _ in range(rng.randint(14, 26)):
        blobs.append((rng.randint(0, W - 1),
                      int(rng.clamped_gauss(H / 2, H * 0.26, 6, H - 7)),
                      rng.uniform(2.0, 7.0), rng.uniform(1.5, 5.0),
                      rng.uniform(0.45, 0.85)))

    warp = _fractal(rng.sub("warp"), 4, 5)
    base = _fractal(rng.sub("elev"), 6, 4)
    detail = _fractal(rng.sub("detail"), 5, 12)

    # 2. tectonic plates as Voronoi cells with drift vectors
    nplates = rng.randint(9, 14)
    seeds = [(rng.randint(0, W - 1), rng.randint(4, H - 5),
              rng.uniform(-0.06, 0.08), rng.uniform(-1, 1), rng.uniform(-1, 1))
             for _ in range(nplates)]

    for y in range(H):
        for x in range(W):
            t = p.tiles[y][x]
            best, bd = 0, 1e9
            for i, (sx, sy, _b, _vx, _vy) in enumerate(seeds):
                dx = min(abs(x - sx), W - abs(x - sx))
                d = dx * dx + (y - sy) * (y - sy) * 1.6
                if d < bd:
                    bd, best = d, i
            t.plate = best

            mask = 0.0
            wx = (warp[y][x] - 0.5) * 14.0
            wy = (detail[y][x] - 0.5) * 9.0
            for cx, cy, rx, ry, amp in blobs:
                dx = min(abs(x + wx - cx), W - abs(x + wx - cx)) / rx
                dy = (y + wy - cy) / ry
                mask = max(mask, amp * math.exp(-(dx * dx + dy * dy)))
            polar = smoothstep(0.02, 0.19, min(y, H - 1 - y) / H)
            e = mask * 0.80 + base[y][x] * 0.30 + detail[y][x] * 0.14 + seeds[best][2]
            t.elev = clamp01(e * (0.15 + 0.85 * polar))

    # 3. convergent boundaries raise mountain belts, divergent open trenches
    bumps = []
    for y in range(H):
        for x in range(W):
            t = p.tiles[y][x]
            for n in p.neighbours(x, y, False):
                if n.plate != t.plate:
                    a, b = seeds[t.plate], seeds[n.plate]
                    conv = -(a[3] * b[3] + a[4] * b[4])
                    bumps.append((t, 0.20 * conv if t.elev > 0.30 else -0.05 * conv))
                    break
    for t, d in bumps:
        t.elev = clamp01(t.elev + d)

    _smooth(p, 1)

    # 4. calibrate sea level to the target land fraction
    flat = sorted(t.elev for t in p.all_tiles())
    p.sea_level = flat[int((1.0 - target_land) * (len(flat) - 1))]
    land_elev = sorted(e for e in flat if e >= p.sea_level)
    p.mountain_level = land_elev[int(0.90 * (len(land_elev) - 1))] if land_elev else 1.0
    p.hill_level = land_elev[int(0.74 * (len(land_elev) - 1))] if land_elev else 1.0
    p.max_elev = flat[-1]

    # 5. climate: latitude, altitude lapse rate, maritime moderation
    for t in p.all_tiles():
        lat = abs(t.lat)
        base_t = 31.0 - 0.0068 * lat * lat - 0.10 * lat
        rel = max(0.0, (t.elev - p.sea_level) / max(1e-6, p.max_elev - p.sea_level))
        km = 6.2 * rel ** 2.3
        t.temp = base_t - km * 6.4 + (2.5 if not t.land else 0.0)

    _moisture(p, rng)
    for t in p.all_tiles():
        t.biome = _biome_for(t, p)
    for t in p.land_tiles():
        t.coastal = any(not n.land for n in p.neighbours(t.x, t.y))
    _rivers(p, rng)
    _resources(p, rng)
    _continents(p, rng)
    return p


def _smooth(p: Planet, passes: int = 1) -> None:
    for _ in range(passes):
        new = [[0.0] * p.w for _ in range(p.h)]
        for y in range(p.h):
            for x in range(p.w):
                t = p.tiles[y][x]
                vals = [t.elev] + [n.elev for n in p.neighbours(x, y)]
                new[y][x] = sum(vals) / len(vals)
        for y in range(p.h):
            for x in range(p.w):
                p.tiles[y][x].elev = new[y][x]


def _moisture(p: Planet, rng: RNG) -> None:
    """Prevailing winds carry moisture inland; mountains wring it out.

    Latitude bands reproduce the Hadley/Ferrel pattern: a wet equator, dry
    horse latitudes, wet mid-latitudes and a dry polar desert.
    """
    noise = _fractal(rng.sub("moist"), 4, 7)

    def band(lat: float) -> float:
        a = abs(lat)
        if a < 11:
            return 1.25
        if a < 21:
            return lerp(1.25, 0.42, inv_lerp(11, 21, a))
        if a < 32:
            return 0.34
        if a < 44:
            return lerp(0.34, 1.05, inv_lerp(32, 44, a))
        if a < 62:
            return 1.05
        if a < 74:
            return lerp(1.05, 0.55, inv_lerp(62, 74, a))
        return 0.40

    for y in range(p.h):
        lat = _lat(y)
        # trades blow east-to-west; westerlies the other way
        wind = -1 if (abs(lat) < 30 or abs(lat) > 60) else 1
        bf = band(lat)
        carry = 0.85
        prev = p.t(0, y).elev
        order = list(range(p.w)) if wind > 0 else list(range(p.w - 1, -1, -1))
        for _ in range(3):                       # let the cylinder equilibrate
            for x in order:
                t = p.tiles[y][x]
                if not t.land:
                    carry = min(1.4, carry + 0.34)
                    t.moist = 1.0
                else:
                    rise = max(0.0, (t.elev - prev)) * 11.0
                    dep = carry * clamp01(0.050 + rise)
                    carry = max(0.0, carry - dep) * 0.994
                    t.moist = clamp01(bf * (0.155 + dep * 2.6 + carry * 0.22)
                                      + (noise[y][x] - 0.40) * 0.26)
                prev = t.elev

    # rivers and lakes moisten their own valleys; hot air dries the ground out
    for t in p.all_tiles():
        if t.land:
            t.moist = clamp01(t.moist * (0.62 + 0.38 * smoothstep(-22, 24, t.temp)))


def _biome_for(t: Tile, p: "Planet") -> str:
    if not t.land:
        return "shelf" if t.elev > p.sea_level - 0.035 else "ocean"
    if t.elev >= p.mountain_level:
        return "mountain"
    T, M = t.temp, t.moist
    if T < -8:
        return "ice"
    if T < 0:
        return "tundra"
    if T < 6:
        return "taiga" if M > 0.22 else "tundra"
    if M < 0.10:
        return "desert"
    if T > 22:
        if M > 0.52:
            return "rainforest"
        if M > 0.26:
            return "savanna"
        return "desert"
    if T > 14 and M < 0.24:
        return "mediterran"
    if M > 0.70 and t.elev < p.hill_level:
        return "wetland"
    if M < 0.18:
        return "steppe"
    return "grassland" if M < 0.34 else "temperate"


def _rivers(p: Planet, rng: RNG) -> None:
    sources = [t for t in p.land_tiles() if t.elev > p.hill_level and t.moist > 0.30]
    for src in rng.sample(sources, min(len(sources), 220)):
        x, y, flow = src.x, src.y, 1.0
        for _ in range(90):
            t = p.t(x, y)
            t.river = max(t.river, flow)
            best = None
            for n in p.neighbours(x, y):
                if best is None or n.elev < best.elev:
                    best = n
            if best is None or not best.land or best.elev >= t.elev:
                break
            x, y = best.x, best.y
            flow = min(4.0, flow + 0.14)
    for t in p.land_tiles():
        if t.river > 0:
            t.moist = clamp01(t.moist + 0.10 * min(1.0, t.river))


def _resources(p: Planet, rng: RNG) -> None:
    """Resources cluster in geologically plausible blobs."""
    deposits = {
        "iron": 34, "copper": 26, "bauxite": 18, "coal": 24, "oil": 22, "gas": 20,
        "gold": 12, "gems": 8, "uranium": 9, "lithium": 11, "rare_earth": 8,
    }
    land = [t for t in p.land_tiles()]
    shelf = [t for t in p.all_tiles() if t.biome == "shelf"]
    for kind, count in deposits.items():
        pool = land + (shelf if kind in ("oil", "gas") else [])
        if not pool:
            continue
        for _ in range(count):
            c = rng.pick(pool)
            if kind in ("iron", "copper", "gold", "gems", "uranium", "rare_earth"):
                bonus = BIOMES[c.biome]["mine"]
                if rng.random() > bonus / 1.8:
                    continue
            radius = rng.randint(2, 6)
            richness = rng.lognorm(1.0, 0.55)
            for dy in range(-radius, radius + 1):
                for dx in range(-radius, radius + 1):
                    d = math.hypot(dx, dy)
                    if d > radius:
                        continue
                    n = p.t(c.x + dx, c.y + dy)
                    if kind in ("oil", "gas") or n.land:
                        n.res[kind] = n.res.get(kind, 0.0) + richness * (1 - d / (radius + 1))
    # renewable / terrain-derived endowments
    for t in p.land_tiles():
        b = BIOMES[t.biome]
        if b["arable"] > 0:
            t.res["arable"] = b["arable"] * (0.55 + 0.75 * t.moist) * (1.0 + 0.35 * min(1.0, t.river))
        if b["pasture"] > 0:
            t.res["pasture"] = b["pasture"] * (0.6 + 0.5 * t.moist)
        if b["timber"] > 0:
            t.res["timber"] = b["timber"] * (0.5 + 0.7 * t.moist)
        if t.coastal:
            t.res["fishery"] = 0.5 + 0.9 * rng.random()
        if abs(t.lat) < 24 and t.moist > 0.4:
            t.res["tropical"] = 0.6 + 0.6 * t.moist
        if t.elev > p.hill_level and t.river > 0:
            t.res["hydro"] = min(2.0, t.river * 0.7)
        if t.biome in ("mountain",) and rng.chance(0.10):
            t.res["geothermal"] = rng.uniform(0.5, 1.6)
        t.res["solar"] = clamp(1.35 - abs(t.lat) / 62.0 - t.moist * 0.45, 0.05, 1.4)
        t.res["wind"] = clamp(0.35 + abs(t.lat) / 90.0 + (0.4 if t.coastal else 0.0), 0.1, 1.5)


def _continents(p: Planet, rng: RNG) -> None:
    from .names import CONTINENT_SUFFIX, word, CULTURES
    seen: dict[tuple[int, int], int] = {}
    cid = 0
    for t in p.land_tiles():
        if (t.x, t.y) in seen:
            continue
        stack = [t]
        members = []
        seen[(t.x, t.y)] = cid
        while stack:
            cur = stack.pop()
            members.append(cur)
            for n in p.neighbours(cur.x, cur.y):
                if n.land and (n.x, n.y) not in seen:
                    seen[(n.x, n.y)] = cid
                    stack.append(n)
        if len(members) >= 90:
            nm = word(rng, rng.pick(CULTURES), 2, 0.3) + rng.pick(CONTINENT_SUFFIX)
            p.continents[cid] = nm
        cid += 1
    p.tile_continent = seen


# ---------------------------------------------------------------- render --

def render(p: Planet, nations=None, focus=None, colour=True, key: str = "political",
           mark: dict[tuple[int, int], str] | None = None, step: int = 1) -> list[str]:
    """Return the world map as terminal lines.

    key: 'political' | 'terrain' | 'population' | 'resource:<kind>' | 'climate'
    """
    from . import ui
    lines = []
    mark = mark or {}
    pal = ["r", "g", "y", "bl", "m", "c", "R", "G", "Y", "B", "M", "Cy", "w"]
    for y in range(0, p.h, step):
        row = []
        for x in range(0, p.w, step):
            t = p.tiles[y][x]
            ch, col = _cell(p, t, nations, key, focus)
            if (x, y) in mark:
                ch, col = mark[(x, y)], "W"
            row.append(ui.c(ch, col, "b") if colour and col else ch)
        lines.append("".join(row))
    return lines


def _cell(p: Planet, t: Tile, nations, key: str, focus):
    b = BIOMES[t.biome]
    if key.startswith("resource:"):
        kind = key.split(":", 1)[1]
        v = t.res.get(kind, 0.0)
        if not t.land and kind not in ("oil", "gas", "fishery"):
            return "·", "K"
        if v <= 0.01:
            return "·", "K"
        idx = min(4, int(v * 2))
        return "▁▃▅▆█"[idx], ["y", "Y", "G", "G", "W"][idx]
    if key == "terrain" or nations is None:
        return b["symbol"], b["col"]
    if key == "climate":
        if not t.land:
            return "·", "bl"
        tt = clamp01(inv_lerp(-20, 34, t.temp))
        return "▁▃▅▆█"[min(4, int(tt * 5))], ["Cy", "c", "G", "Y", "R"][min(4, int(tt * 5))]
    if not t.land:
        return ("·" if t.biome == "ocean" else ":"), "bl"
    reg = t.region
    if reg is None:
        return b["symbol"], "K"
    nat = nations.get(reg) if isinstance(nations, dict) else None
    if nat is None:
        return b["symbol"], "K"
    if key == "population":
        return "▁▃▅▆█"[min(4, int(math.log10(max(1, nat)) if isinstance(nat, (int, float)) else 0))], "Y"
    ch = nat[0] if isinstance(nat, str) else "?"
    col = pal_for(nat)
    if focus and nat == focus:
        return ch.upper(), "W"
    return ch, col


_PAL_CACHE: dict[str, str] = {}
_PAL = ["r", "g", "y", "bl", "m", "c", "R", "G", "Y", "B", "M", "Cy", "w", "W"]


def pal_for(key: str) -> str:
    if key not in _PAL_CACHE:
        _PAL_CACHE[key] = _PAL[abs(hash(key)) % len(_PAL)]
    return _PAL_CACHE[key]
