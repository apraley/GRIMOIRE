-- CRANKING IT :: No.XIII ONE BILLION YEARS
--
-- The crank is geological time, and its SPEED is the time scale. A
-- logarithmic governor maps how fast you turn to how much time one turn is
-- worth: a slow turn is a year (one degree = one day, the seasons march round
-- the handle), a furious one is a billion years (one degree = 2.8 million
-- years). Nothing stops the flow and nothing reverses it: cranking backward
-- only brakes the governor and the world rests.
--
-- Underneath: a 64x32 height field carried by drifting plates (collisions
-- raise mountains, rifts open oceans), erosion, a hypsometric sea level fed by
-- the planet's water, a climate of sun + CO2 + ice albedo (snowballs,
-- hothouses, ice ages), life with a diversity index, extinctions and
-- procedurally named clades, a civilization that lasts a few thousand years,
-- and a sun that brightens, boils the oceans and finally swallows the world.
--
-- The planet's fate is dealt at birth: a timeline of milestones, each with a
-- window of years. A milestone is WITNESSED only if you pass through enough
-- of its window slowly - while the crank's rate (years per second) is under
-- the window's limit. The ruler at the bottom is a logarithmic horizon: the
-- marks show how far ahead the milestones are, the bright hand shows how far
-- one second of cranking carries you, the eye shows how slow you must be.

local gfx <const> = playdate.graphics
local floor <const> = math.floor
local abs <const> = math.abs
local sqrt <const> = math.sqrt
local sin <const>, cos <const> = math.sin, math.cos
local exp <const>, log <const> = math.exp, math.log
local min <const>, max <const> = math.min, math.max
local pi <const> = math.pi
local asin <const> = math.asin
local TAU <const> = 2 * math.pi
local LN10 <const> = math.log(10)
local LN2 <const> = math.log(2)

-- world grid
local W <const>, H <const> = 64, 32
local N <const> = W * H
local SLICE <const> = 256            -- cells eroded/classified per frame
local MAXP <const> = 10              -- plate slots
local NHB <const>, HB0 <const>, HBW <const> = 80, -8000, 250 -- height histogram
local UPLIFT <const>, ARC <const>, RIDGE <const>, MAXH <const> = 1300, 700, -2600, 8200
local NOSEA <const> = -99999

-- the governor: crank speed (deg/s) -> log10(years per turn)
local VLO <const>, VHI <const> = 20, 720
local LMAX <const> = 9
local LOGV <const> = math.log(VHI / VLO)
local TMIN <const> = 2.0             -- seconds a window must last to be seen

-- screen layout
local GX <const>, GY <const>, GR <const> = 190, 100, 74
local SUNX <const>, SUNY <const> = 350, 50
local RYT <const> = 196              -- ruler band top
local RX0 <const>, RX1 <const> = 44, 392
local RY <const> = 210               -- ruler base line
local PXD <const> = (RX1 - RX0) / 10 -- pixels per decade (1 yr .. 10 Gyr)
local GRAPHX <const>, GRAPHY <const>, GRAPHW <const>, GRAPHH <const> = 282, 152, 110, 22

-- light from the sun (screen space: x right, y down, z toward the viewer)
local SX, SY, SZ
do
  local x, y, z = 0.9, -0.28, 0.16
  local l = sqrt(x * x + y * y + z * z)
  SX, SY, SZ = x / l, y / l, z / l
end
local SUNANG <const> = math.deg(math.atan(SX, -SY)) -- drawArc angle of the sun

------------------------------------------------------------------------
-- surface classes and their 1-bit look at four light levels
------------------------------------------------------------------------
local C_LAVA <const>, C_DEEP <const>, C_SEA <const>, C_ROCK <const>, C_BASIN <const> = 0, 1, 2, 3, 4
local C_DESERT <const>, C_GRASS <const>, C_FOREST <const>, C_MOUNT <const>, C_PEAK <const> = 5, 6, 7, 8, 9
local C_ICE <const>, C_CLOUD <const>, C_SALT <const> = 10, 11, 12

local P = Art.pat
-- 1 = white. Hand-made textures for this machine.
local PT_SEA3 = { 0x00, 0x1c, 0x00, 0x00, 0x00, 0xc1, 0x00, 0x00 }
local PT_SEA2 = { 0x00, 0x00, 0x18, 0x00, 0x00, 0x00, 0x81, 0x00 }
local PT_DEEP3 = { 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x80 }
local PT_LAVA3 = { 0x7e, 0xbd, 0xdb, 0xe7, 0xe7, 0xdb, 0xbd, 0x7e }
local PT_LAVA2 = { 0x81, 0x42, 0x24, 0x18, 0x00, 0x18, 0x24, 0x42 }
local PT_LAVA1 = { 0x80, 0x40, 0x00, 0x08, 0x00, 0x10, 0x00, 0x02 }
local PT_EMBER = { 0x00, 0x40, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00 }
local PT_GRASS3 = { 0xdd, 0xff, 0x77, 0xff, 0xdd, 0xff, 0x77, 0xff }
local PT_GRASS2 = { 0xaa, 0x77, 0xaa, 0xdd, 0xaa, 0x77, 0xaa, 0xdd }
local PT_FOREST3 = { 0x22, 0x77, 0x22, 0x00, 0x88, 0xdd, 0x88, 0x00 }
local PT_FOREST2 = { 0x00, 0x22, 0x00, 0x00, 0x00, 0x88, 0x00, 0x00 }
local PT_MOUNT3 = { 0xbf, 0xdf, 0xef, 0xff, 0xfb, 0xfd, 0xfe, 0xff }
local PT_BASIN3 = { 0x55, 0xbb, 0x55, 0xee, 0x55, 0xbb, 0x55, 0xee }
local PT_SALT3 = { 0xff, 0xef, 0xff, 0xfe, 0xff, 0xbf, 0xff, 0xfb }
local PT_CLOUD3 = { 0xff, 0xff, 0xf7, 0xff, 0xff, 0xff, 0x7f, 0xff }
-- overlays (with masks: pattern rows then mask rows)
local PT_SHADE50 = { 0, 0, 0, 0, 0, 0, 0, 0, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55 }
local PT_SHADE25 = { 0, 0, 0, 0, 0, 0, 0, 0, 0x88, 0x22, 0x88, 0x22, 0x88, 0x22, 0x88, 0x22 }
local PT_SHADE75 = { 0, 0, 0, 0, 0, 0, 0, 0, 0x77, 0xdd, 0x77, 0xdd, 0x77, 0xdd, 0x77, 0xdd }
local PT_GIANT = { 0xee, 0xbb, 0xdd, 0x77, 0xee, 0xbb, 0xdd, 0x77 }

local PT_GLINT = { 0x22, 0x88, 0x55, 0x88, 0x22, 0x88, 0x55, 0x88 }
local PATS = {}
local PIDX = {}
local function patIndex(t)
  if t == nil then return 0 end
  for i = 1, #PATS do if PATS[i] == t then return i end end
  PATS[#PATS + 1] = t
  return #PATS
end
-- index = cl * 4 + level + 1, level 3 = full sun .. 0 = night
local function classPats(cl, l3, l2, l1, l0)
  PIDX[cl * 4 + 4] = patIndex(l3)
  PIDX[cl * 4 + 3] = patIndex(l2)
  PIDX[cl * 4 + 2] = patIndex(l1)
  PIDX[cl * 4 + 1] = patIndex(l0)
end
classPats(C_LAVA, PT_LAVA3, PT_LAVA2, PT_LAVA1, PT_EMBER)
classPats(C_DEEP, PT_DEEP3, PT_DEEP3, nil, nil)
classPats(C_SEA, PT_SEA3, PT_SEA2, PT_DEEP3, nil)
classPats(C_ROCK, P.gray25, P.gray50, P.gray75, nil)
classPats(C_BASIN, PT_BASIN3, P.gray75, P.gray87, nil)
classPats(C_DESERT, P.gray6, P.gray25, P.gray75, nil)
classPats(C_GRASS, PT_GRASS3, PT_GRASS2, P.gray87, nil)
classPats(C_FOREST, PT_FOREST3, PT_FOREST2, nil, nil)
classPats(C_MOUNT, PT_MOUNT3, P.hatchD, P.gray75, nil)
classPats(C_PEAK, P.white, P.gray12, P.gray50, nil)
classPats(C_ICE, P.white, P.gray12, P.gray50, nil)
classPats(C_CLOUD, PT_CLOUD3, P.gray25, P.gray75, nil)
classPats(C_SALT, PT_SALT3, P.gray50, P.gray75, nil)
local glintP = patIndex(PT_GLINT)

------------------------------------------------------------------------
-- milestones
------------------------------------------------------------------------
-- w = window in years, pts = score when witnessed (rarer = narrower = more)
local EV = {
  rain = { name = "THE FIRST RAIN", w = 2e6, pts = 100, line = "It is raining. It will rain for a very long time." },
  coast = { name = "THE FIRST COAST", w = 4e6, pts = 100, line = "The first coast." },
  bombard = { name = "THE BOMBARDMENT", w = 2e7, pts = 150, line = "The sky is still throwing stones." },
  cells = { name = "FIRST CELLS", w = 1e6, pts = 250, line = "Something in the warm vents is copying itself." },
  oxygen = { name = "THE GREAT OXIDATION", w = 2e7, pts = 150, line = "Something is breathing out oxygen." },
  snow = { name = "SNOWBALL", w = 1e5, pts = 300, line = "The ice has reached the equator." },
  thaw = { name = "THE THAW", w = 3e5, pts = 250, line = "The volcanoes win. The ice lets go." },
  complex = { name = "COMPLEX LIFE", w = 2e6, pts = 150, line = "Two cells decide to stay together." },
  bloom = { name = "THE BLOOM", w = 1e7, pts = 150, line = "Eyes. Shells. Everything at once." },
  land = { name = "GREEN EDGES", w = 2e6, pts = 200, line = "Green at the edges of the land." },
  forest = { name = "THE FIRST FORESTS", w = 5e6, pts = 150, line = "The continents darken with forest." },
  traps = { name = "THE GREAT DYING", w = 1e6, pts = 300, line = "The ground opens for a million years." },
  impact = { name = "THE IMPACT", w = 1e4, pts = 500, line = "A second sun, briefly." },
  stone = { name = "A STONE FALLS", w = 5e3, pts = 350, line = "A stone from the dark. A long winter." },
  erupt = { name = "THE LONG ERUPTION", w = 5e5, pts = 250, line = "A province of fire." },
  iceage = { name = "THE ICE AGES", w = 1e6, pts = 200, line = "The ice breathes in and out." },
  minds = { name = "THEY LOOK UP", w = 1e5, pts = 400, line = "Something has noticed the sky." },
  cities = { name = "CITY LIGHTS", w = 1.2e4, pts = 1000, line = "Lights on the night side." },
  quiet = { name = "THE QUIET", w = 5e4, pts = 300, line = "They have gone quiet." },
  comet = { name = "A COMET", w = 400, pts = 600, line = "A visitor with a long tail." },
  lastforest = { name = "THE LAST FOREST", w = 5e6, pts = 200, line = "The last forest, in the far north." },
  boil = { name = "THE OCEANS BOIL", w = 3e7, pts = 200, line = "The sea rises into the sky and stays there." },
  lastlife = { name = "THE LAST LIFE", w = 1e6, pts = 400, line = "Something small, still copying itself, in the last shadow." },
  giant = { name = "THE RED GIANT", w = 4e7, pts = 300, line = "The sun comes to collect." },
  rift = { name = "RIFT", w = 0, pts = 0 },
  volcano = { name = "A VOLCANO WAKES", w = 3e6, pts = 0, line = "A mountain clears its throat." },
}

-- stage: 0 barren, 1 cells, 2 breathing, 3 complex, 4 bloom, 5 land, 6 forests, 7 minds, 8 sterile
local KST <const> = { [0] = 0, 30, 80, 260, 900, 1500, 2300, 2600, 0 }
local STAGE_NAMES <const> = { [0] = "BARREN", "FIRST CELLS", "MICROBIAL MATS", "SOFT BODIES", "SHELLS AND EYES",
  "LIFE ASHORE", "FORESTS", "MINDS", "STERILE" }

local SYL1 <const> = { "Vel", "Thal", "Or", "Ish", "Kor", "Mer", "Ann", "Sil", "Pyr", "Ost", "Qua", "Hel",
  "Dra", "Ul", "Zen", "Bor", "Cal", "Nym", "Esk", "Tor", "Ves", "Lun" }
local SYL2 <const> = { "a", "e", "i", "o", "u", "ae", "y", "ai" }
local SYL3 <const> = { "n", "r", "l", "th", "ss", "v", "m", "k", "d", "st", "rr", "nd" }
local SYL4 <const> = { "ids", "opods", "arians", "ites", "oids", "ellids", "acea", "ornes", "anths", "urids" }

local ROMAN_WORLD = {}
for i = 1, 20 do ROMAN_WORLD[i] = "WORLD " .. U.roman(i) end

------------------------------------------------------------------------
-- file-level scratch (no allocation in update/draw)
------------------------------------------------------------------------
local ROWLAT, ROWTL, ROWWET, ROWDRY, ROWWIND = {}, {}, {}, {}, {}
for r = 0, H - 1 do
  local lat = 90 - (r + 0.5) * 180 / H
  ROWLAT[r] = lat
  local a = abs(lat)
  ROWTL[r] = 14 - 0.55 * a
  ROWWET[r] = (a < 14) or (a > 42 and a < 66)
  ROWDRY[r] = (a > 17 and a < 36)
  ROWWIND[r] = (a < 30) and -1 or ((a < 60) and 1 or -0.5)
end
local colS, colC, colA = {}, {}, {}
local bxs, bcol = {}, {}
local stY, stH, stRow, stCos, stSin, stRc = {}, {}, {}, {}, {}, {}
local rowY, rowCos, rowSin = {}, {}, {}
local iceAll, iceLand, coff = {}, {}, {}
local rowP, rowH, colP, colH = {}, {}, {}, {}
local histB = {}
local cntP, totP = {}, {}
local upD, upE = {}, {}
for i = 0, W do colS[i], colC[i], colA[i], rowP[i], rowH[i] = 0, 0, 0, 0, 0 end
for i = 0, H do colP[i], colH[i], rowY[i], rowCos[i], rowSin[i], coff[i] = 0, 0, 0, 0, 0, 0 iceAll[i] = false iceLand[i] = false end
for i = 1, NHB do histB[i] = 0 end
local stripN, stripR = 0, -1

-- 3x5 pixel font for the ruler labels (only drawn into cached art)
local TINY <const> = {
  ["1"] = { 2, 6, 2, 2, 7 }, ["0"] = { 7, 5, 5, 5, 7 }, Y = { 5, 5, 2, 2, 2 }, K = { 5, 6, 4, 6, 5 },
  M = { 5, 7, 7, 5, 5 }, G = { 3, 4, 5, 5, 3 },
}
local function tinyText(s, x, y)
  for i = 1, #s do
    local g = TINY[s:sub(i, i)]
    if g then
      for r = 1, 5 do
        for c = 0, 2 do
          if ((g[r] >> (2 - c)) & 1) == 1 then gfx.drawPixel(x + (i - 1) * 4 + c, y + r - 1) end
        end
      end
    end
  end
end

local function smooth(t) return t * t * (3 - 2 * t) end

-- adds value noise (lattice gw x gh, wraps in x) scaled by amp into out[1..N]
local function addNoise(rng, out, gw, gh, amp)
  local lat = {}
  for j = 0, gh do for i = 0, gw - 1 do lat[j * gw + i + 1] = rng:float() * 2 - 1 end end
  for r = 0, H - 1 do
    local fy = (r + 0.5) / H * gh
    local j0 = floor(fy)
    local ty = smooth(fy - j0)
    for c = 0, W - 1 do
      local fx = (c + 0.5) / W * gw
      local i0 = floor(fx)
      local tx = smooth(fx - i0)
      local i1 = (i0 + 1) % gw
      i0 = i0 % gw
      local a0, a1 = lat[j0 * gw + i0 + 1], lat[j0 * gw + i1 + 1]
      local b0, b1 = lat[(j0 + 1) * gw + i0 + 1], lat[(j0 + 1) * gw + i1 + 1]
      local a = a0 + (a1 - a0) * tx
      local b = b0 + (b1 - b0) * tx
      out[r * W + c + 1] = out[r * W + c + 1] + (a + (b - a) * ty) * amp
    end
  end
end

-- split a time in Myr into (whole Myr, years within it)
local function tsplit(t)
  local em = floor(t)
  return em, (t - em) * 1e6
end

------------------------------------------------------------------------
-- definition
------------------------------------------------------------------------
local M = Machine.define({
  id = "billion",
  number = 13,
  title = "ONE BILLION YEARS",
  tagline = "Speed is the time scale.",
  description = "A barren planet. Turn slowly and a degree is a day. Turn hard and a turn is a billion years.",
  howto = "Crank speed is the time scale: slow = seasons, fast = drifting continents. Slow down as a mark on the ruler reaches NOW to witness it. Backward: time rests.",
  controls = { { "CRANK", "time (speed = scale)" }, { "DPAD", "turn the globe" }, { "A", "hide instruments" }, { "B", "hold: rest (endless)" } },
  modes = { "tutorial", "standard", "endless" },
  medals = { standard = { 1200, 3200, 5400 }, endless = { 2500, 6500, 12000 } },
  scoreLabel = "WITNESSED",
  unlockCost = 15,
  achievements = {
    { id = "first", name = "FIRST LIGHT", desc = "Witness a milestone." },
    { id = "lights", name = "SOMEONE ELSE", desc = "Witness the city lights." },
    { id = "comet", name = "ONCE IN A LIFETIME", desc = "Witness a comet." },
    { id = "deep", name = "DEEP TIME", desc = "Witness 15 milestones on a world." },
    { id = "sunrise", name = "THE LAST SUNRISE", desc = "Witness the red giant." },
  },
  challenges = {
    { id = "blind", name = "NO HORIZON", desc = "The ruler is dark. Feel the ages coming.", mode = "standard", difficulty = 2, goal = 1500, reward = 3, cost = 2 },
    { id = "rusty", name = "SEIZED AXLE", desc = "The crank sticks and lurches.", mode = "standard", difficulty = 2, mods = { rusty = true }, goal = 2000, reward = 2, cost = 2 },
    { id = "worlds", name = "SECOND GENESIS", desc = "Endless, with the narrowest windows.", mode = "endless", difficulty = 3, goal = 6000, reward = 3, cost = 3 },
  },
  records = {
    { "witnessed", "Milestones witnessed" },
    { "civs", "Civilizations seen" },
    { "worlds", "Worlds ended" },
    { "bestWorld", "Most seen on a world" },
  },
  drawIcon = function(cx, cy)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(cx - 22, cy - 22, 44, 44)
    -- the swollen sun
    gfx.setPattern(Art.pat.gray50)
    gfx.fillCircleAtPoint(cx + 22, cy - 22, 22)
    gfx.setPattern(PT_GIANT)
    gfx.fillCircleAtPoint(cx + 22, cy - 22, 17)
    -- the world, lit from the upper right
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(cx - 5, cy + 5, 16)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(cx - 5, cy + 5, 14)
    gfx.setPattern(PT_FOREST3)
    gfx.fillCircleAtPoint(cx - 2, cy + 8, 6)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(cx - 11, cy + 10, 14)
    -- city lights on the night side
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(cx - 14, cy + 2, 2, 2)
    gfx.fillRect(cx - 10, cy + 5, 1, 1)
    gfx.fillRect(cx - 16, cy + 8, 1, 1)
    gfx.fillRect(cx - 12, cy + 11, 2, 1)
    gfx.fillRect(cx - 7, cy + 14, 1, 1)
    -- a moon
    gfx.fillCircleAtPoint(cx - 16, cy - 14, 3)
    gfx.setColor(gfx.kColorBlack)
  end,
})

M.HINTS = { { "CRANK", "TIME" }, { "DPAD", "LOOK" }, { "A", "INSTRUMENTS" } }
M.HINTS_END = { { "CRANK", "TIME" }, { "DPAD", "LOOK" }, { "A", "INSTR." }, { "B", "REST" } }

------------------------------------------------------------------------
-- world generation
------------------------------------------------------------------------
function M:allocWorld()
  self.h, self.pl, self.cls, self.nz, self.cf, self.trap = {}, {}, {}, {}, {}, {}
  for i = 1, N do
    self.h[i], self.pl[i], self.cls[i], self.nz[i], self.cf[i], self.trap[i] = 0, 1, C_LAVA, 0, 0, 0
  end
  self.vx, self.vy, self.ox, self.oy = {}, {}, {}, {}
  for p = 1, MAXP do self.vx[p], self.vy[p], self.ox[p], self.oy[p] = 0, 0, 0, 0 end
  self.histD = {}
  for i = 1, GRAPHW do self.histD[i] = 0 end
  self.cities = {}
  self.cityJx, self.cityJy = {}, {}
  for i = 1, 96 do self.cities[i] = 0 self.cityJx[i] = 0 self.cityJy[i] = 0 end
  self.trapList = {}
  self.flashI, self.flashT = {}, {}
  for i = 1, 6 do self.flashI[i] = 1 self.flashT[i] = 0 end
  self.debrisA, self.debrisR = {}, {}
  for i = 1, 60 do self.debrisA[i] = 0 self.debrisR[i] = 0 end
end

function M:randomVelocities()
  local rng = self.rng
  for p = 1, MAXP do
    local a = rng:float() * TAU
    local sp = rng:between(0.03, 0.09)
    self.vx[p] = cos(a) * sp
    self.vy[p] = sin(a) * sp * 0.35
  end
end

function M:genTerrain(mature)
  local rng = self.rng
  local h, pl = self.h, self.pl
  local nf = {}
  local warp = {}
  for i = 1, N do nf[i] = 0 warp[i] = 0 end
  addNoise(rng, nf, 4, 2, 1.0)
  addNoise(rng, nf, 8, 4, 0.5)
  addNoise(rng, nf, 16, 8, 0.25)
  addNoise(rng, nf, 32, 16, 0.12)
  addNoise(rng, warp, 8, 4, 1.0)
  addNoise(rng, warp, 16, 8, 0.5)
  -- plates: nearest seed, with a noisy distance for ragged borders
  local np = 7
  local sx, sy, cont = {}, {}, {}
  for p = 1, np do
    sx[p] = rng:float() * W
    sy[p] = rng:between(3, H - 3)
    cont[p] = p <= (mature and 3 or 2)
  end
  for r = 0, H - 1 do
    for c = 0, W - 1 do
      local i = r * W + c + 1
      local best, bd = 1, 1e9
      for p = 1, np do
        local dx = abs(c + 0.5 - sx[p])
        if dx > W / 2 then dx = W - dx end
        local dy = (r + 0.5 - sy[p]) * 1.7
        local d = sqrt(dx * dx + dy * dy) + warp[i] * 7
        if d < bd then bd, best = d, p end
      end
      pl[i] = best
      local f = nf[i] * 0.95 + (cont[best] and (mature and 0.42 or 0.3) or -0.38)
      if f > 0 then h[i] = 60 + f * 2600 else h[i] = -1200 + f * 5200 end
      if h[i] < -1000 and h[i] > -1200 then h[i] = -1200 end
    end
  end
  for i = 1, N do
    self.nz[i] = rng:float()
    self.cf[i] = 0
  end
  addNoise(rng, self.cf, 8, 4, 0.6)
  addNoise(rng, self.cf, 16, 8, 0.4)
  addNoise(rng, self.cf, 32, 16, 0.2)
  for p = 1, MAXP do self.ox[p], self.oy[p] = 0, 0 end
  self:randomVelocities()
  -- slots beyond the seeded plates start empty
  for p = np + 1, MAXP do self.vx[p], self.vy[p] = 0, 0 end
  for i = 1, N do self.trap[i] = 0 end
  self.trapList = {}
  for i = 1, #self.debrisA do
    self.debrisA[i] = rng:float() * TAU
    self.debrisR[i] = rng:between(0.3, 1.6)
  end
end

------------------------------------------------------------------------
-- the fate of a planet: milestone timeline
------------------------------------------------------------------------
function M:makeFate(planet)
  local rng = self.rng
  local d = self.difficulty
  local wmul = (d == 1 and 1 or (d == 2 and 0.7 or 0.5)) * (0.85 ^ (planet - 1))
  local pmul = 1 + 0.25 * (planet - 1)
  local reveal = (d == 1 and 1e5 or (d == 2 and 2e4 or 5e3))
  local ev = {}
  local function add(k, t, wOverride)
    local def = EV[k]
    local em, ey = tsplit(t)
    local w = (wOverride or def.w) * ((def.pts > 0) and wmul or 1)
    local e = { k = k, em = em, ey = ey, w = w, pts = floor(def.pts * pmul), st = 0, seen = 0,
      wit = false, miss = false, rev = false, lim = w / TMIN, reveal = w * reveal }
    if k == "comet" then e.reveal = w * reveal * 0.02 end
    ev[#ev + 1] = e
    return e
  end
  local B = rng.between
  local rain = B(rng, 70, 110)
  add("rain", rain)
  add("coast", rain + B(rng, 8, 16))
  add("bombard", B(rng, 330, 430))
  local cells = B(rng, 600, 850)
  add("cells", cells)
  local oxygen = B(rng, 2150, 2400)
  add("oxygen", oxygen)
  local snow1 = oxygen + B(rng, 50, 110)
  add("snow", snow1)
  add("thaw", snow1 + B(rng, 15, 40))
  local complex = B(rng, 3550, 3700)
  add("complex", complex)
  local last = complex
  if rng:chance(0.7) then
    local s2 = complex + B(rng, 60, 130)
    add("snow", s2)
    last = s2 + B(rng, 10, 30)
    add("thaw", last)
  end
  local bloom = last + B(rng, 100, 160)
  add("bloom", bloom)
  local landT = bloom + B(rng, 60, 100)
  add("land", landT)
  local forest = landT + B(rng, 50, 90)
  add("forest", forest)
  local traps = forest + B(rng, 60, 120)
  add("traps", traps)
  local impact = traps + B(rng, 120, 180)
  add("impact", impact)
  local ice = impact + B(rng, 50, 65)
  local iceE = add("iceage", ice)
  local minds = ice + B(rng, 1.2, 1.8)
  local mindsE = add("minds", minds)
  -- cities begin near the end of the minds window
  local cityW = EV.cities.w * wmul
  local cm, cy = mindsE.em, mindsE.ey + mindsE.w * B(rng, 0.85, 0.93)
  while cy >= 1e6 do cm, cy = cm + 1, cy - 1e6 end
  local citiesE = add("cities", cm + cy * 1e-6)
  citiesE.em, citiesE.ey = cm, cy
  local qm, qy = cm, cy + cityW
  while qy >= 1e6 do qm, qy = qm + 1, qy - 1e6 end
  local quietE = add("quiet", qm + qy * 1e-6)
  quietE.em, quietE.ey = qm, qy
  -- glacial rhythm phased so the cities rise in a warm interglacial
  local dcy = ((cm - iceE.em) * 1e6 + (cy - iceE.ey)) / 1e5
  self.icePhase = -TAU * dcy - pi / 2
  local lf = cm + B(rng, 550, 650)
  add("lastforest", lf)
  local boil = lf + B(rng, 300, 380)
  add("boil", boil)
  local lastlife = boil + B(rng, 40, 80)
  add("lastlife", lastlife)
  local giant = lastlife + B(rng, 250, 330)
  add("giant", giant)
  -- the extras: stones, an eruption, a comet
  for _ = 1, 2 do add("stone", B(rng, 1200, traps - 20)) end
  add("erupt", B(rng, 2600, complex - 50))
  add("comet", B(rng, ice + 0.2, cm - 0.02))
  -- silent rifts that reorganize the plates
  local t = B(rng, 500, 700)
  while t < giant - 300 do
    add("rift", t)
    t = t + B(rng, 380, 620)
  end
  table.sort(ev, function(a, b)
    if a.em ~= b.em then return a.em < b.em end
    return a.ey < b.ey
  end)
  -- key times (float Myr) for the continuous climate
  self.fate = {
    lastforest = lf, boil = boil, lastlife = lastlife, giant = giant,
    giantEnd = giant + EV.giant.w * wmul * 1e-6, iceStart = ice,
  }
  self.ev = ev
  self.evFirst = 1
  self.scorable = 0
  for i = 1, #ev do if ev[i].pts > 0 then self.scorable = self.scorable + 1 end end
end

function M:newClade(adj)
  local rng = self.rng
  local name = rng:pick(SYL1) .. rng:pick(SYL2) .. rng:pick(SYL3) .. rng:pick(SYL4)
  self.clade = name
  self:log("The age of the " .. adj .. " " .. name .. ".")
end

------------------------------------------------------------------------
-- lifecycle
------------------------------------------------------------------------
function M:resetState()
  self.my, self.ky, self.fy = 0, 0, 0
  self.water, self.co2, self.T = 0, 41, 1500
  self.spike, self.hot, self.dust = 0, 0, 0
  self.lum = 0.72
  self.stage, self.D, self.vegF = 0, 0, 0
  self.sea = NOSEA
  self.mf = 1
  self.snowball, self.rained, self.boiling, self.boiled, self.dying = false, false, false, false, false
  self.cityN, self.cityOrigin = 0, 0
  self.ring = 0
  self.clade = nil
  self.sweepI, self.sweepAcc, self.sweepDt = 1, 0, 0
  self.aC, self.aO, self.aD = 0, 0, 0
  self.planetWit = 0
  self.graphFill = 0
  self.ending = false
  for i = 1, GRAPHW do self.histD[i] = 0 end
end

function M:enter(params)
  self.vt = 0
  self.fwd, self.back = 0, 0
  self.vS, self.L, self.ypt, self.rate, self.rateS = 0, 0, 1, 0, 0
  self.rot = 16
  self.spin = 0
  self.score = 0
  self.witN = 0
  self.planet = 1
  self.held = 0
  self.backAcc = 0
  self.hideHud = false
  self.need = ({ 0.4, 0.5, 0.6 })[self.difficulty] or 0.4
  self.blind = self.params.challengeId == "blind"
  self.tut = self.mode == "tutorial"
  self.logWrapped, self.logT = nil, 99
  self.wmsg, self.wmsgT, self.wmsgName = nil, 0, nil
  self.rarest, self.rarestPts = nil, 0
  self.endT = 0
  self.restHold = 0
  self.upN = 0
  self.focus = nil
  self.yearTick = 0
  self.creakAcc = 0
  self.twinkleT = 0
  self.dateV, self.dateS, self.dateU = -1, "", ""
  self.scaleV, self.scaleS = -99, ""
  self.graphV, self.graphS = -1, ""
  self:allocWorld()
  self:resetState()

  self.droneA = Audio.Hum.new(Audio.SINE, 0.4, 0.6)
  self.droneB = Audio.Hum.new(Audio.TRIANGLE, 0.4, 0.6)
  self.wind = Audio.Hum.new(Audio.NOISE, 0.3, 0.5)

  if self.tut then
    self:setupTutorialWorld()
    self:setupCoach()
  else
    self:genTerrain(false)
    self:makeFate(1)
    self:fullSweep()
  end
  self:faceLand()
end

-- turn the globe so the largest landmass faces the viewer
function M:faceLand()
  local h = self.h
  local best, bc = 0, -1
  for c0 = 0, W - 1, 2 do
    local n = 0
    for dc = -8, 8 do
      local c = (c0 + dc) % W
      for r = 4, H - 5 do if h[r * W + c + 1] > -1000 then n = n + 1 end end
    end
    if n > bc then best, bc = c0, n end
  end
  -- centre it a little west of noon, so the evening side shows too
  self.rot = (best + 0.5 - 6) % W
end

function M:exit()
  self.droneA:stop()
  self.droneB:stop()
  self.wind:stop()
end

function M:setupTutorialWorld()
  self:genTerrain(true)
  self.my, self.ky, self.fy = 4300, 0, 0
  self.water, self.co2, self.T = 1, 1.7, 17
  self.stage, self.D = 6, 2300
  self.rained = true
  self.mf = 0
  self.lum = 1
  self.clade = "Velanids"
  self.ev = {}
  self.evFirst = 1
  self.scorable = 0
  self.fate = { lastforest = 1e9, boil = 1e9, lastlife = 1e9, giant = 1e9, giantEnd = 1e9, iceStart = -1 }
  self.icePhase = 0
  self.tutSlow, self.tutShifts, self.tutBack, self.tutWit = 0, 0, 0, false
  self:fullSweep()
  self:fullSweep() -- second pass: sea level from the first histogram
end

function M:setupCoach()
  local s = self
  self.coach = UI.Coach.new({
    { text = "Crank slowly: one turn is a year. Watch a season pass on the ice caps.",
      enter = function() s.tutSlow = 0 end,
      check = function() return s.tutSlow >= 1 end },
    { text = "Now crank FAST: speed is the scale. Watch the continents drift.",
      enter = function() s.tutShifts = 0 end,
      check = function() return s.tutShifts >= 10 end },
    { text = "Crank backward. Time never runs back - it only rests.",
      enter = function() s.tutBack = 0 end,
      check = function() return s.tutBack >= 180 end },
    { text = "A mark rides the ruler to NOW. Slow down, hand left of the eye, to witness it.",
      enter = function() s:spawnTutorialEvent() end,
      check = function() return s.tutWit end },
  }, { y = 20, h = 46 })
end

function M:spawnTutorialEvent()
  local em, ey = self.my + 50 + self.rng:range(0, 20), self.ky
  local e = { k = "volcano", em = em, ey = ey, w = EV.volcano.w, pts = 1, st = 0, seen = 0,
    wit = false, miss = false, rev = true, lim = EV.volcano.w / TMIN, reveal = 1e12 }
  -- keep the list sorted: drop finished tutorial events
  local ev = {}
  for i = 1, #self.ev do if self.ev[i].st < 2 then ev[#ev + 1] = self.ev[i] end end
  ev[#ev + 1] = e
  self.ev = ev
  self.evFirst = 1
end

------------------------------------------------------------------------
-- time
------------------------------------------------------------------------
-- years from now until (em, ey); negative = in the past
function M:deltaYears(em, ey)
  return (em - self.my) * 1e6 + (ey - self.ky) - self.fy
end

function M:nowMyr() return self.my + (self.ky + self.fy) * 1e-6 end

function M:advance(dY)
  local fy = self.fy + dY
  if fy >= 1 then
    local w = floor(fy)
    fy = fy - w
    local ky = self.ky + w
    if ky >= 1e6 then
      local m = floor(ky / 1e6)
      self.my = self.my + m
      ky = ky - m * 1e6
    end
    self.ky = ky
    if dY < 0.9 then self.yearTick = 1 end
  end
  self.fy = fy
end

------------------------------------------------------------------------
-- events
------------------------------------------------------------------------
function M:processEvents(dY, dt)
  local ev = self.ev
  local rate = dY / dt
  self.tooFast = false
  self.aCiv, self.aMinds, self.aImpact, self.aBombard, self.aComet, self.aGiant = nil, nil, nil, nil, nil, nil
  self.aRain = nil
  local n = #ev
  local i = self.evFirst
  local budget = 12
  while i <= n do
    local e = ev[i]
    if e.st < 2 then
      local ds = self:deltaYears(e.em, e.ey)
      if ds > 0 then break end
      if e.st == 0 then
        if budget <= 0 then break end
        budget = budget - 1
        e.st = 1
        e.rev = true
        self:onStart(e, -ds, rate)
        if self.ev ~= ev then return end
      end
      local de = ds + e.w
      if e.w > 0 and e.pts > 0 and not e.wit then
        local o = min(0, de) - max(-dY, ds)
        if o > 0 then
          if rate <= e.lim then
            e.seen = e.seen + o / e.w
          else
            self.tooFast = true
          end
          if e.seen >= self.need then self:witness(e) end
        end
      end
      if de <= 0 then
        e.st = 2
        self:onEnd(e)
        if self.ev ~= ev or self.finished then return end
      else
        local k = e.k
        if k == "cities" then self.aCiv = e
        elseif k == "minds" then self.aMinds = e
        elseif k == "impact" or k == "stone" then self.aImpact = e
        elseif k == "bombard" then self.aBombard = e
        elseif k == "comet" then self.aComet = e
        elseif k == "giant" then self.aGiant = e
        elseif k == "rain" then self.aRain = e
        end
      end
    end
    i = i + 1
  end
  while self.evFirst <= n and ev[self.evFirst].st == 2 do self.evFirst = self.evFirst + 1 end
end

-- upcoming milestones for the ruler; reveal them when close enough
function M:scanUpcoming()
  local ev = self.ev
  local cnt = 0
  local focus = nil
  for i = self.evFirst, #ev do
    local e = ev[i]
    if e.st == 1 and e.pts > 0 and not e.wit and e.w > 0 then
      if not focus or e.lim < focus.lim then focus = e end
    elseif e.st == 0 and e.pts > 0 then
      local ds = self:deltaYears(e.em, e.ey)
      if not e.rev and ds < e.reveal then e.rev = true end
      if e.rev and cnt < 5 then
        cnt = cnt + 1
        upD[cnt], upE[cnt] = ds, e
      end
      if cnt >= 5 or ds > 2e10 then break end
    end
  end
  self.upN = cnt
  if not focus and cnt > 0 then focus = upE[1] end
  self.focus = focus
end

function M:witness(e)
  e.wit = true
  if self.tut then
    self.tutWit = true
  else
    self.score = self.score + e.pts
    self.witN = self.witN + 1
    self.planetWit = self.planetWit + 1
    self:statAdd("witnessed", 1)
    self:statMax("bestWorld", self.planetWit)
    self:award("first")
    if e.k == "cities" then self:award("lights") self:statAdd("civs", 1) end
    if e.k == "comet" then self:award("comet") end
    if e.k == "giant" then self:award("sunrise") end
    if self.planetWit >= 15 then self:award("deep") end
    if e.pts > self.rarestPts then self.rarestPts, self.rarest = e.pts, EV[e.k].name end
  end
  self.wmsg, self.wmsgT, self.wmsgName, self.wmsgPts = "WITNESSED", 3, EV[e.k].name, e.pts
  Audio.sfx.bell(660, 0.35)
  Audio.play(Audio.SINE, 990, 0.25, 0.6, 0.01, 0.8, 0, 0.5, 0.12)
  Audio.play(Audio.SINE, 1320, 0.18, 0.8, 0.01, 1.0, 0, 0.6, 0.26)
end

function M:onStart(e, since, rate)
  local k = e.k
  local def = EV[k]
  if def.line and (rate < 5e8 or e.pts >= 300) then self:log(def.line) end
  if e.pts > 0 and rate < e.lim * 20 then Audio.sfx.bell(330, 0.15) end
  if k == "rain" then
    self.rained = true
  elseif k == "coast" then
    self.water = max(self.water, 0.12)
  elseif k == "rift" then
    self:rift()
  elseif k == "cells" then
    self.stage = max(self.stage, 1)
    self.clade = "first copiers"
  elseif k == "oxygen" then
    self.stage = max(self.stage, 2)
  elseif k == "snow" then
    self.snowball = true
    self.D = self.D * 0.4
    Audio.sfx.whoosh(0.2)
  elseif k == "thaw" then
    self.snowball = false
    self.hot = 26
  elseif k == "complex" then
    self.stage = max(self.stage, 3)
    self:newClade("soft")
  elseif k == "bloom" then
    self.stage = max(self.stage, 4)
    self:newClade("armoured")
  elseif k == "land" then
    self.stage = max(self.stage, 5)
    self:newClade("creeping")
  elseif k == "forest" then
    self.stage = max(self.stage, 6)
    self:newClade("tall")
  elseif k == "traps" then
    self:startTraps(22)
    self.spike = 14
    self.D = self.D * 0.35
    Audio.sfx.thud(0.6)
  elseif k == "erupt" or k == "volcano" then
    self:startTraps(k == "volcano" and 6 or 10)
    self.spike = self.spike + (k == "volcano" and 0 or 5)
    Audio.sfx.thud(0.4)
  elseif k == "impact" or k == "stone" then
    self:impact(k == "impact" and 0.3 or 0.7, k == "impact" and 18 or 9)
    if rate < 1e6 then self:shake(k == "impact" and 6 or 3) end
    Audio.sfx.thud(0.9)
    Audio.sfx.whoosh(0.5)
  elseif k == "iceage" then
    self.fate.iceStart = e.em + e.ey * 1e-6
  elseif k == "minds" then
    self.stage = max(self.stage, 7)
    self.cityOrigin = self:pickNightLand()
    self:newClade("upright")
  elseif k == "cities" then
    self:startCiv()
  elseif k == "lastforest" then
    self.dying = true
  elseif k == "boil" then
    self.boiling = true
  elseif k == "giant" then
    Audio.sfx.horn(2.5, 0.35)
  end
end

function M:onEnd(e)
  local k = e.k
  if k == "traps" or k == "erupt" or k == "volcano" then
    self:endTraps()
    if k == "traps" then self.D = self.D * 0.3 self:newClade("burrowing") end
  elseif k == "impact" then
    self:newClade("warm-blooded")
  elseif k == "cities" then
    self.cityN = 0
    self.ring = 1
  elseif k == "boil" then
    self.boiled = true
  elseif k == "lastlife" then
    self.D = 0
    self.stage = 8
    self.clade = nil
  elseif k == "giant" then
    self:worldEnd()
  end
  if e.pts > 0 and e.w > 0 and not e.wit then
    e.miss = true
    if self.tut then
      self:log("It passed unseen. Another stirs.")
      self:spawnTutorialEvent()
    elseif self.rateS < e.lim * 200 then
      self.wmsg, self.wmsgT, self.wmsgName, self.wmsgPts = "PASSED UNSEEN", 2.2, EV[k].name, 0
      Audio.play(Audio.SINE, 196, 0.2, 0.5, 0.02, 0.5, 0, 0.3)
    end
  end
end

function M:worldEnd()
  self:statAdd("worlds", 1)
  if self.mode == "standard" then
    self.ending = true
    self.endT = 0
    local lines = {
      "Witnessed " .. self.planetWit .. " of " .. self.scorable,
      "Rarest seen: " .. (self.rarest or "nothing"),
      string.format("World's age: %.2f bn years", self:nowMyr() / 1000),
    }
    self:finish({ success = true, score = self.score, title = "THE LAST SUNRISE", lines = lines, delay = 3.2 })
  elseif self.mode == "endless" then
    if self.planetWit < 3 then
      self.ending = true
      self.endT = 0
      self:finish({ success = self.score > 0, score = self.score, title = "THE LAMP GUTTERS",
        lines = { "Worlds turned: " .. self.planet, "Milestones witnessed: " .. self.witN,
          "The last world went by almost unseen." }, delay = 3.2 })
    else
      self:newPlanet()
    end
  end
end

function M:newPlanet()
  self.planet = self.planet + 1
  self:resetState()
  self:genTerrain(false)
  self:makeFate(self.planet)
  self:fullSweep()
  self:faceLand()
  self:log("From the debris, another world.")
  Audio.sfx.gear()
end

------------------------------------------------------------------------
-- tectonics
------------------------------------------------------------------------
function M:shiftX(p, d)
  local h, pl = self.h, self.pl
  local rng = self.rng
  for r = 0, H - 1 do
    local base = r * W
    local any = false
    for c = 0, W - 1 do
      local q = pl[base + c + 1]
      rowP[c] = q
      rowH[c] = h[base + c + 1]
      if q == p then any = true end
    end
    if any then
      for c = 0, W - 1 do
        if rowP[c] == p then
          local dc = (c + d) % W
          local di = base + dc + 1
          local q = rowP[dc]
          local hs = rowH[c]
          if q == p then
            h[di] = hs
          else
            local hd = rowH[dc]
            if hs > -1000 then
              if hd > -1000 then h[di] = min(MAXH, max(hs, hd) + UPLIFT) else h[di] = hs + 250 end
              pl[di] = p
            elseif hd > -1000 then
              h[di] = min(MAXH, hd + ARC)
            else
              h[di] = (rng:float() < 0.03) and 900 or hs
              pl[di] = p
            end
          end
          if rowP[(c - d) % W] ~= p then h[base + c + 1] = RIDGE end
        end
      end
    end
  end
end

function M:shiftY(p, d)
  local h, pl = self.h, self.pl
  for c = 0, W - 1 do
    local any = false
    for r = 0, H - 1 do
      local q = pl[r * W + c + 1]
      colP[r] = q
      colH[r] = h[r * W + c + 1]
      if q == p then any = true end
    end
    if any then
      for r = 0, H - 1 do
        if colP[r] == p then
          local dr = r + d
          if dr >= 0 and dr < H then
            local di = dr * W + c + 1
            local q = colP[dr]
            local hs = colH[r]
            if q == p then
              h[di] = hs
            else
              local hd = colH[dr]
              if hs > -1000 then
                if hd > -1000 then h[di] = min(MAXH, max(hs, hd) + UPLIFT) else h[di] = hs + 250 end
                pl[di] = p
              elseif hd > -1000 then
                h[di] = min(MAXH, hd + ARC)
              else
                h[di] = hs
                pl[di] = p
              end
            end
          end
          local sr = r - d
          if sr < 0 or sr >= H or colP[sr] ~= p then h[r * W + c + 1] = RIDGE end
        end
      end
    end
  end
end

function M:tectonics(dtM)
  if dtM <= 0 then return end
  local vx, vy, ox, oy = self.vx, self.vy, self.ox, self.oy
  local best, bv, bdir = 0, 0.999, 0
  for p = 1, MAXP do
    ox[p] = U.clamp(ox[p] + vx[p] * dtM, -2.5, 2.5)
    oy[p] = U.clamp(oy[p] + vy[p] * dtM, -2.5, 2.5)
    if abs(ox[p]) > bv then best, bv, bdir = p, abs(ox[p]), 1 end
    if abs(oy[p]) > bv then best, bv, bdir = p, abs(oy[p]), 2 end
  end
  if best > 0 then
    if bdir == 1 then
      local d = ox[best] > 0 and 1 or -1
      self:shiftX(best, d)
      ox[best] = ox[best] - d
    else
      local d = oy[best] > 0 and 1 or -1
      self:shiftY(best, d)
      oy[best] = oy[best] - d
    end
    if self.tut then self.tutShifts = self.tutShifts + 1 end
  end
  -- hotspots raise volcanic islands now and then
  if self.rng:float() < min(1, dtM * 0.02) then
    local i = self.rng:range(1, N)
    if self.h[i] < -1000 then self.h[i] = 800 end
  end
end

-- tear the largest continental plate in two; the halves drift apart
function M:rift()
  local h, pl = self.h, self.pl
  local rng = self.rng
  for p = 1, MAXP do cntP[p], totP[p] = 0, 0 end
  for i = 1, N do
    local p = pl[i]
    totP[p] = totP[p] + 1
    if h[i] > -1000 then cntP[p] = cntP[p] + 1 end
  end
  local best, bc = 1, -1
  for p = 1, MAXP do if cntP[p] > bc then best, bc = p, cntP[p] end end
  local free = nil
  for p = 1, MAXP do if totP[p] == 0 then free = p break end end
  if rng:chance(0.5) then self:randomVelocities() end
  if not free or bc < 24 then return end
  -- pivot: a random continental cell of that plate
  local k = rng:range(1, bc)
  local pr, pc = 0, 0
  for i = 1, N do
    if pl[i] == best and h[i] > -1000 then
      k = k - 1
      if k <= 0 then pr, pc = (i - 1) // W, (i - 1) % W break end
    end
  end
  local a = rng:float() * pi
  local nx, ny = cos(a), sin(a)
  for i = 1, N do
    if pl[i] == best then
      local r, c = (i - 1) // W, (i - 1) % W
      local dx = c - pc
      if dx > W / 2 then dx = dx - W elseif dx < -W / 2 then dx = dx + W end
      if dx * nx + (r - pr) * ny * 1.7 > 0 then pl[i] = free end
    end
  end
  local sp = rng:between(0.05, 0.09)
  self.vx[free], self.vy[free] = nx * sp, ny * sp * 0.35
  self.vx[best], self.vy[best] = -nx * sp, -ny * sp * 0.35
  self.ox[free], self.oy[free] = 0, 0
  if self.rateS < 5e7 then self:log("A continent tears along an old seam.") end
end

------------------------------------------------------------------------
-- local catastrophes
------------------------------------------------------------------------
-- a cell on the visible face of the globe (so slow watchers see it)
function M:frontCell(rowLo, rowHi, landOnly)
  local rng = self.rng
  local best = nil
  for _ = 1, 30 do
    local c = floor(self.rot - 0.5 + rng:between(-7, 7)) % W
    local r = rng:range(rowLo, rowHi)
    local i = r * W + c + 1
    if not landOnly or self.h[i] > self.sea then return i end
    best = best or i
  end
  return best
end

function M:impact(sev, rad)
  local i = self:frontCell(8, 23, false)
  local r0, c0 = (i - 1) // W, (i - 1) % W
  local h = self.h
  local rr = rad > 12 and 2 or 1
  for dr = -rr, rr do
    for dc = -rr, rr do
      local r = r0 + dr
      if r >= 0 and r < H then
        local j = r * W + (c0 + dc) % W + 1
        if dr == 0 and dc == 0 then h[j] = h[j] - 1800
        elseif abs(dr) + abs(dc) <= rr then h[j] = h[j] + 350 end
      end
    end
  end
  self.dust = rad
  self.D = self.D * sev
  self.impactCell = i
  self:addFlash(i)
end

function M:addFlash(i)
  local fi, ft = self.flashI, self.flashT
  local slot, oldest = 1, 1e9
  for k = 1, #fi do if ft[k] < oldest then slot, oldest = k, ft[k] end end
  fi[slot], ft[slot] = i, 1
end

function M:startTraps(n)
  local i = self:frontCell(6, 25, true)
  local r0, c0 = (i - 1) // W, (i - 1) % W
  local rng = self.rng
  local list = self.trapList
  for _ = 1, n do
    local r = U.clamp(r0 + rng:range(-2, 2), 0, H - 1)
    local j = r * W + (c0 + rng:range(-3, 3)) % W + 1
    if self.trap[j] == 0 then
      self.trap[j] = 1
      list[#list + 1] = j
    end
  end
end

function M:endTraps()
  local list = self.trapList
  for k = 1, #list do
    local j = list[k]
    self.trap[j] = 0
    self.h[j] = max(self.h[j], 400) + 500 -- a basalt plateau remains
  end
  self.trapList = {}
end

-- a land cell on the visible night side (the lights must be seen)
function M:pickNightLand()
  local h, sea = self.h, self.sea
  local rng = self.rng
  local best, bs = 1, -1e9
  for _ = 1, 400 do
    local r = rng:range(6, 25)
    local c = rng:range(0, W - 1)
    local i = r * W + c + 1
    if h[i] > sea and h[i] < sea + 1700 then
      local lam = (c + 0.5 - self.rot) * TAU / W
      local ca = cos(lam)
      local lat = ROWLAT[r] * pi / 180
      local light = cos(lat) * (sin(lam) * SX + ca * SZ) - sin(lat) * SY
      -- just past sunset: the spin carries them deeper into the night
      local score = (ca > 0.6 and 2 or 0) - abs(light + 0.2) * 3 + rng:float() * 0.3
      if score > bs then best, bs = i, score end
    end
  end
  return best
end

function M:startCiv()
  local o = self:pickNightLand()
  self.cityOrigin = o
  local r0, c0 = (o - 1) // W, (o - 1) % W
  local h, sea = self.h, self.sea
  local rng = self.rng
  -- the nearest land, with a little restlessness
  local n = 0
  local cand, cd = {}, {}
  for i = 1, N do
    if h[i] > sea and h[i] < sea + 2400 then
      local r, c = (i - 1) // W, (i - 1) % W
      local dx = abs(c - c0)
      if dx > W / 2 then dx = W - dx end
      local d = dx * dx + (r - r0) * (r - r0) * 2 + rng:float() * 6
      n = n + 1
      cand[n], cd[n] = i, d
    end
  end
  local idx = {}
  for k = 1, n do idx[k] = k end
  table.sort(idx, function(a, b) return cd[a] < cd[b] end)
  local m = min(96, n)
  for k = 1, m do
    self.cities[k] = cand[idx[k]]
    self.cityJx[k] = rng:range(-3, 3)
    self.cityJy[k] = rng:range(-2, 2)
  end
  self.cityMax = m
  self.cityN = 0
end

------------------------------------------------------------------------
-- climate & life
------------------------------------------------------------------------
function M:climate(dtM, t)
  local f = self.fate
  if self.tut then
    self.lum = 1
    self.T = self.T + (17 - self.T) * (1 - exp(-dtM / 0.05))
    self.water, self.mf = 1, 0
    return
  end
  local L
  if t < 4500 then L = 0.72 + 0.28 * t / 4500 else L = 1 + 0.1 * (t - 4500) / 1000 end
  self.lum = L
  local Tform = 1600 * exp(-t / 22)
  local target = 1 + 40 * exp(-t / 1100)
  self.co2 = self.co2 + (target - self.co2) * (1 - exp(-dtM / 80))
  self.spike = self.spike * exp(-dtM / 3)
  self.hot = self.hot * exp(-dtM / 4)
  self.dust = self.dust * exp(-dtM / 0.004)
  local ch4 = (self.stage < 2) and 8 or 0
  local glac = 0
  if f.iceStart > 0 and t > f.iceStart and t < f.iceStart + 4 then
    glac = -7 * (0.5 + 0.5 * sin(TAU * (t - f.iceStart) * 10 + self.icePhase))
  end
  local run = 0
  local t0 = f.lastforest - 300
  if t > t0 then
    if t < f.boil then
      local u = (t - t0) / (f.boil - t0)
      run = 80 * u * u
    else
      run = 80 + 1100 * min(1, (t - f.boil) / max(1, f.giantEnd - f.boil))
    end
  end
  local Teq = 14 + 70 * (L - 1) + 5.5 * log(self.co2) / LN2 + ch4 + self.spike + self.hot - self.dust + glac + run + Tform
  if self.snowball then Teq = -48 + run end
  self.T = self.T + (Teq - self.T) * (1 - exp(-dtM / 0.02))
  -- water: rains in, boils away
  local wT = self.rained and 1 or 0
  if self.boiling then wT = 0 end
  self.water = self.water + (wT - self.water) * (1 - exp(-dtM / (self.boiling and 25 or 60)))
  self.mf = U.clamp((self.T - 250) / 500, 0, 1)
end

function M:life(dtM, t)
  local st = self.stage
  local K = KST[st] or 0
  local T = self.T
  local hab = 1
  if self.snowball then hab = 0.12
  elseif T > 40 then hab = max(0, 1 - (T - 40) / 35)
  elseif T < -2 then hab = max(0.1, 1 + (T + 2) / 20) end
  if self.dying then
    local f = self.fate
    hab = hab * U.clamp(1 - (t - f.lastforest) / max(1, f.lastlife - f.lastforest), 0, 1)
  end
  K = K * hab
  local D = self.D
  if D < K then D = D + (K - D) * (1 - exp(-dtM / 18)) else D = D + (K - D) * (1 - exp(-dtM / 1.5)) end
  self.D = D
  local v = 0
  if st >= 6 and st <= 7 then v = 1 elseif st == 5 then v = 0.45 end
  if v > 0 then
    local ks = KST[st]
    v = v * U.clamp(D / ks, 0.2, 1)
  end
  if self.boiling then v = 0 end
  self.vegF = v
  -- the tree-of-life graph over the planet's whole span
  if not self.tut then
    local b = floor(t / self.fate.giantEnd * GRAPHW) + 1
    if b > GRAPHW then b = GRAPHW end
    for k = self.graphFill + 1, b do self.histD[k] = D end
    if b >= 1 then self.histD[b] = D end
    if b > self.graphFill then self.graphFill = b end
  end
end

------------------------------------------------------------------------
-- erosion + classification, a slice of cells per frame
------------------------------------------------------------------------
function M:endSweep()
  local dtS = self.sweepAcc
  self.sweepDt = dtS
  self.sweepAcc = 0
  self.aC = 1 - exp(-dtS / 220)
  self.aO = 1 - exp(-dtS / 90)
  self.aD = 1 - exp(-dtS / 500)
  -- sea level: the height below which the water fits
  local weff = self.water * (self.snowball and 0.85 or 1)
  if weff < 0.01 then
    self.sea = NOSEA
  else
    local target = 0.62 * weff * N
    local cum = 0
    local sea = HB0
    for b = 1, NHB do
      local c = histB[b]
      if cum + c >= target then
        sea = HB0 + (b - 1 + (target - cum) / max(1, c)) * HBW
        break
      end
      cum = cum + c
      sea = HB0 + b * HBW
    end
    self.sea = sea
  end
  for b = 1, NHB do histB[b] = 0 end
end

function M:sweepCells(count)
  local h, cls, trap, nz = self.h, self.cls, self.trap, self.nz
  local i = self.sweepI
  local aC, aO, aD = self.aC, self.aO, self.aD
  local sea, water = self.sea, self.water
  local vegF, mf, T = self.vegF, self.mf, self.T
  local dry = water < 0.02
  local boiled = self.boiled
  for _ = 1, count do
    local r = (i - 1) // W
    local c = (i - 1) - r * W
    local base = r * W
    local hv = h[i]
    local ie = base + (c + 1) % W + 1
    local iw = base + (c - 1) % W + 1
    local he, hw = h[ie], h[iw]
    if hv > -1000 then
      hv = hv + (100 - hv) * aC
      -- mountains spread into neighbouring land
      if he > -1000 and hw > -1000 then hv = hv + ((he + hw) * 0.5 - hv) * aD end
    else
      hv = hv + (-4300 - hv) * aO
    end
    h[i] = hv
    local b = floor((hv - HB0) / HBW) + 1
    if b < 1 then b = 1 elseif b > NHB then b = NHB end
    histB[b] = histB[b] + 1
    -- classify
    local cl
    if trap[i] > 0 or nz[i] < mf then
      cl = C_LAVA
    elseif hv < sea then
      cl = (sea - hv > 1800) and C_DEEP or C_SEA
    elseif dry then
      if hv < -1000 then cl = boiled and C_SALT or C_BASIN
      elseif hv > 1900 then cl = C_MOUNT
      else cl = C_ROCK end
    else
      local e = hv - sea
      local tl = T + ROWTL[r] - e * 0.0065
      if hv > 2500 and tl < -3 then cl = C_PEAK
      elseif hv > 1900 then cl = C_MOUNT
      elseif vegF > 0 then
        local wet = ROWWET[r] or he < sea or hw < sea
          or h[base + (c + 2) % W + 1] < sea or h[base + (c - 2) % W + 1] < sea
          or (r > 0 and h[i - W] < sea) or (r < H - 1 and h[i + W] < sea)
        local v = vegF
        if not wet then v = v * 0.3 end
        if tl < -2 or tl > 44 then v = 0 end
        if v > 0.55 then cl = C_FOREST
        elseif v > 0.2 then cl = C_GRASS
        elseif ROWDRY[r] or tl > 30 then cl = C_DESERT
        else cl = C_ROCK end
      else
        cl = (hv < -1000) and C_BASIN or C_ROCK
      end
    end
    cls[i] = cl
    i = i + 1
    if i > N then
      i = 1
      self.sweepI = 1
      self:endSweep()
      sea, aC, aO, aD = self.sea, self.aC, self.aO, self.aD
    end
  end
  self.sweepI = i
end

function M:fullSweep()
  self.sweepI = 1
  self:sweepCells(N)
end

------------------------------------------------------------------------
-- input
------------------------------------------------------------------------
function M:cranked(change)
  if change > 0 then self.fwd = self.fwd + change else self.back = self.back - change end
end

function M:buttonDown(b)
  if b == Input.A then
    self.hideHud = not self.hideHud
    Audio.sfx.click(0.2)
  end
end

------------------------------------------------------------------------
-- update
------------------------------------------------------------------------
function M:update(dt)
  self.vt = self.vt + dt
  local fwd, back = self.fwd, self.back
  self.fwd, self.back = 0, 0
  if self.wmsgT > 0 then self.wmsgT = self.wmsgT - dt end
  self.logT = self.logT + dt
  if self.ending then
    self.endT = self.endT + dt
    self.droneA:set(40, max(0, 0.12 - self.endT * 0.04))
    self.droneB:set(60, 0)
    self.wind:set(300, max(0, 0.1 - self.endT * 0.03))
    return
  end

  -- the governor: speed -> log time scale. Backward = brake.
  if back > 0 then
    self.vS = U.damp(self.vS, 0, 16, dt)
    self.held = 0.8
    self.backAcc = self.backAcc + back
    self.creakAcc = self.creakAcc + back
    if self.tut then self.tutBack = self.tutBack + back end
    if self.creakAcc > 70 then
      self.creakAcc = 0
      Audio.sfx.creak(0.12)
      Audio.play(Audio.SINE, 55, 0.2, 0.25, 0.02, 0.2, 0, 0.1)
    end
  else
    self.vS = U.damp(self.vS, fwd / dt, fwd > 0 and 5 or 2.5, dt)
  end
  if self.held > 0 then self.held = self.held - dt end
  local u = 0
  if self.vS > VLO then u = min(1, log(self.vS / VLO) / LOGV) end
  self.L = u * LMAX
  local ypt = exp(self.L * LN10)
  self.ypt = ypt
  local dY = 0
  if back == 0 and fwd > 0 then dY = fwd * ypt / 360 end
  self.rate = dY / dt
  self.rateS = U.damp(self.rateS, self.rate, 6, dt)
  if self.tut and ypt <= 30 then self.tutSlow = self.tutSlow + dY end

  self:advance(dY)
  self:processEvents(dY, dt)
  if self.finished then return end
  self:scanUpcoming()
  local dtM = dY * 1e-6
  local t = self:nowMyr()
  if dtM > 0 then
    self:climate(dtM, t)
    self:life(dtM, t)
    if t > 30 then self:tectonics(dtM) end
    -- the bombardment: craters rain down through its window
    local bo = self.aBombard
    if bo then
      local expct = dY / bo.w * 50
      local k = 0
      while k < 2 and self.rng:float() < expct do
        k = k + 1
        expct = expct - 1
        local i = self.rng:range(1, N)
        self.h[i] = self.h[i] - 900
        if self.rateS < 3e6 then self:addFlash(i) end
      end
    end
  end
  self.sweepAcc = self.sweepAcc + dtM
  self:sweepCells(SLICE)
  self:visuals(dt, dY)
  self:audio(dt)

  -- endless: hold B to rest the crank for good
  if self.mode == "endless" then
    if Input.held(Input.B) and fwd == 0 and back == 0 then
      self.restHold = self.restHold + dt
      if self.restHold > 2.5 then
        self.ending = true
        self.restEnd = true
        self:finish({ success = self.score > 0, score = self.score, title = "THE KEEPER RESTS",
          lines = { "Worlds turned: " .. self.planet, "Milestones witnessed: " .. self.witN,
            "Rarest seen: " .. (self.rarest or "nothing") }, delay = 2.5 })
      end
    else
      self.restHold = 0
    end
  end
end

function M:visuals(dt, dY)
  -- the world only turns while time flows; the d-pad turns the view
  local target = dY > 0 and 0.04 or 0
  self.spin = U.approach(self.spin, target, 0.004)
  local rot = self.rot + self.spin
  if Input.held(Input.LEFT) then rot = rot - 0.35 end
  if Input.held(Input.RIGHT) then rot = rot + 0.35 end
  self.rot = rot % W
  -- weather: clouds ride their winds (only meaningful at the slowest scales)
  local days = dY * 365
  if days > 0 then
    local d = min(days * 0.05, 64)
    for r = 0, H - 1 do coff[r] = (coff[r] + ROWWIND[r] * d) % W end
  end
  -- seasons and ice
  local T = self.T
  local iceLat
  if self.snowball then iceLat = 0
  elseif T >= 28 then iceLat = 95
  else iceLat = U.clamp(72 - (15 - T) * 2.6, 0, 95) end
  if self.mf > 0.5 then iceLat = 95 end
  local amp = U.clamp(1 - self.rateS / 4, 0, 1) * 9
  local season = sin(self.fy * TAU)
  for r = 0, H - 1 do
    local lat = ROWLAT[r]
    local edge = iceLat + (lat > 0 and season or -season) * amp
    local a = abs(lat)
    iceAll[r] = a >= edge
    iceLand[r] = a >= edge - 9
  end
  -- impact flashes fade
  local ft = self.flashT
  for k = 1, #ft do if ft[k] > 0 then ft[k] = ft[k] - dt * 1.5 end end
  if self.ring > 0 then self.ring = max(0, self.ring - dY / 3e8) end
  -- civilization progress
  local civ = self.aCiv
  if civ then
    local p = -self:deltaYears(civ.em, civ.ey) / civ.w
    local m = self.cityMax or 0
    local n
    if p < 0.6 then n = floor(m * (p / 0.6) ^ 1.5)
    elseif p < 0.88 then n = m
    else n = floor(m * max(0, 1 - (p - 0.88) / 0.1)) end
    self.cityN = U.clamp(n, 0, m)
    self.civP = p
  end
  if self.logT > 16 then self.logWrapped = nil end
end

function M:audio(dt)
  local L = self.L
  local moving = self.rate > 0
  local base = 38 + L * 16
  self.droneA:set(base, moving and 0.14 or 0.07)
  self.droneB:set(base * 1.5, (moving and 0.02 or 0.01) + 0.05 * L / LMAX)
  local wv = L / LMAX
  self.wind:set(180 + L * 120, moving and (0.01 + 0.09 * wv * wv) or 0)
  -- the year turning, at the slowest scale: a soft tick on the handle
  if self.yearTick > 0 then
    self.yearTick = 0
    Audio.sfx.tick(1200, 0.08)
  end
  -- the city lights have a sound, if you are slow enough to hear it
  if self.cityN > 0 and self.rate < 2e4 then
    self.twinkleT = self.twinkleT - dt
    if self.twinkleT <= 0 then
      self.twinkleT = 0.18 + self.rng:float() * 0.4
      Audio.play(Audio.TRIANGLE, 1400 + self.rng:float() * 1400, 0.06, 0.05, 0.002, 0.08, 0, 0.05)
    end
  end
end

------------------------------------------------------------------------
-- drawing
------------------------------------------------------------------------
local function buildStrips(R)
  local n = 0
  for r = 0, H - 1 do
    local latT = (90 - r * 180 / H) * pi / 180
    local latB = (90 - (r + 1) * 180 / H) * pi / 180
    local ya = floor(GY - R * sin(latT) + 0.5)
    local yb = floor(GY - R * sin(latB) + 0.5)
    local latC = (latT + latB) * 0.5
    rowY[r] = GY - R * sin(latC)
    rowCos[r] = cos(latC)
    rowSin[r] = -sin(latC)
    local y = ya
    while y < yb do
      local hgt = min(4, yb - y)
      if yb - y == 5 then hgt = 3 end
      n = n + 1
      local yc = y + hgt * 0.5
      local s = (yc - GY) / R
      stY[n], stH[n], stRow[n] = y, hgt, r
      stSin[n] = s
      stCos[n] = sqrt(max(0, 1 - s * s))
      -- extent: widest line of the strip, the ring mask trims the rest
      local se = (s < 0) and (y + hgt - GY) / R or (y - GY) / R
      if (y <= GY) and (y + hgt >= GY) then se = 0 end
      stRc[n] = R * sqrt(max(0, 1 - se * se))
      y = y + hgt
    end
  end
  stripN, stripR = n, R
end

function M:drawGlobe(R, lava)
  if stripR ~= R then buildStrips(R) end
  local rot = self.rot
  local step = TAU / W
  for c = 0, W - 1 do
    local a = (c + 0.5 - rot) * step
    local s, co = sin(a), cos(a)
    colS[c], colC[c] = s, co
    colA[c] = s * SX + co * SZ
  end
  -- visible boundaries, left limb to right limb
  local kk = floor(rot - W / 4)
  local nb = 0
  local half = pi / 2
  for j = 0, W / 2 + 2 do
    local a = (kk + j - rot) * step
    nb = nb + 1
    bcol[nb] = (kk + j) % W
    if j == 0 then bxs[nb] = -1
    elseif a >= half then bxs[nb] = 1 break
    else bxs[nb] = sin(a) end
  end
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(GX, GY, R)
  local cls = self.cls
  local cf = self.cf
  local cloudy = 0
  local rate = self.rateS
  if rate < 0.25 and self.water > 0.3 and not self.snowball then cloudy = 0.62 - (self.T - 15) * 0.004 end
  local steam = (self.boiling and not self.boiled) or self.aRain ~= nil
  local fillRect, setPattern = gfx.fillRect, gfx.setPattern
  for s = 1, stripN do
    local y, hgt, r = stY[s], stH[s], stRow[s]
    local cphi, rc = stCos[s], stRc[s]
    local B = stSin[s] * SY
    local base = r * W
    local allIce, landIce = iceAll[r], iceLand[r]
    local co = floor(coff[r])
    local runP, runX = 0, 0
    local x0 = floor(GX + rc * bxs[1] + 0.5)
    for m = 1, nb - 1 do
      local x1 = floor(GX + rc * bxs[m + 1] + 0.5)
      if x1 > x0 then
        local col = bcol[m]
        local cl = lava and C_LAVA or cls[base + col + 1]
        if cl ~= C_LAVA then
          if allIce then cl = C_ICE
          elseif landIce and cl >= C_ROCK and cl ~= C_PEAK and cl ~= C_SALT then cl = C_ICE end
        end
        local lit = cphi * colA[col] + B
        local lev = (lit > 0.22) and 3 or ((lit > 0.06) and 2 or ((lit > -0.04) and 1 or 0))
        if steam then
          if cf[base + (col + co) % W + 1] > -0.35 then cl = C_CLOUD end
        elseif cloudy > 0 and lev > 0 and cf[base + (col + co) % W + 1] > cloudy then cl = C_CLOUD end
        local p = PIDX[cl * 4 + lev + 1]
        if lit > 0.8 and cl <= C_SEA and cl >= C_DEEP then p = glintP end
        if p ~= runP then
          if runP > 0 then
            setPattern(PATS[runP])
            fillRect(runX, y, x0 - runX, hgt)
          end
          runP, runX = p, x0
        end
        x0 = x1
      end
    end
    if runP > 0 then
      setPattern(PATS[runP])
      fillRect(runX, y, x0 - runX, hgt)
    end
  end
end

-- The globe is the heaviest Lua work in the anthology (~1700 cell
-- evaluations). It is rendered into a cached image at most every other
-- frame (15 Hz) and blitted in between; the planet turns slowly enough
-- that the difference is invisible, and the frame budget halves.
function M:drawGlobeCached(R)
  local size = 2 * R + 4
  local img = self.globeImg
  if not img or self.globeSize ~= size then
    img = gfx.image.new(size, size, gfx.kColorClear)
    self.globeImg, self.globeSize = img, size
    self.globeAge = 99
  end
  self.globeAge = (self.globeAge or 99) + 1
  local ox, oy = GX - R - 2, GY - R - 2
  if self.globeAge >= 2 then
    self.globeAge = 0
    gfx.pushContext(img)
    gfx.clear(gfx.kColorClear)
    gfx.setDrawOffset(-ox, -oy)
    self:drawGlobe(R, false)
    gfx.popContext()
  end
  img:draw(ox, oy)
end

-- the molten proto-planet, gathering itself out of the debris
function M:drawProto(R)
  gfx.setPattern(PT_LAVA3)
  gfx.fillCircleAtPoint(GX, GY, R)
  gfx.setPattern(PT_SHADE50)
  gfx.fillCircleAtPoint(GX - R * 0.35, GY + R * 0.12, R)
  gfx.setPattern(PT_SHADE75)
  gfx.fillCircleAtPoint(GX - R * 0.7, GY + R * 0.25, R)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawArc(GX, GY, R + 1, SUNANG - 60, SUNANG + 60)
  gfx.setColor(gfx.kColorBlack)
end

function M:project(i, R)
  local r = (i - 1) // W
  local c = (i - 1) - r * W
  local vis = colC[c]
  local x = GX + R * rowCos[r] * colS[c]
  local y = rowY[r]
  local lit = rowCos[r] * colA[c] + rowSin[r] * SY
  return x, y, vis, lit
end

function M:drawSun(r, giant)
  if giant then
    gfx.setPattern(Art.pat.gray75)
    gfx.fillCircleAtPoint(SUNX, SUNY, r + 10)
    gfx.setPattern(Art.pat.gray50)
    gfx.fillCircleAtPoint(SUNX, SUNY, r + 4)
    gfx.setPattern(PT_GIANT)
    gfx.fillCircleAtPoint(SUNX, SUNY, r)
    gfx.setPattern(Art.pat.gray12)
    gfx.fillCircleAtPoint(SUNX + r * 0.1, SUNY - r * 0.05, r * 0.72)
  else
    gfx.setPattern(Art.pat.gray87)
    gfx.fillCircleAtPoint(SUNX, SUNY, r + 10)
    gfx.setPattern(Art.pat.gray50)
    gfx.fillCircleAtPoint(SUNX, SUNY, r + 4)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(SUNX, SUNY, r)
  end
  gfx.setColor(gfx.kColorBlack)
end

function M:sunRadius(t)
  local f = self.fate
  if self.tut then return 12 end
  local g0 = f.giant - 250
  local r = 9 + 4 * min(1, t / 4500) + 3 * U.clamp((t - 4500) / (g0 - 4500), 0, 1)
  if t > g0 then
    local u = U.clamp((t - g0) / (f.giantEnd - g0), 0, 1)
    local re = 250
    r = r * (re / r) ^ (u * u * u)
  end
  return r
end

function M:drawMoon(front, t)
  if t < 30 then return end
  local a = GR + 22 + 10 * min(1, t / 6000)
  local b = a * 0.2
  if self.rateS > 1.5 then
    -- too fast to see it move: the moon smears into its orbit
    gfx.setColor(gfx.kColorWhite)
    local k0 = front and 0 or 24
    for k = k0, k0 + 23, 2 do
      local th = k * TAU / 48
      local x, y = GX + a * cos(th), GY + b * sin(th)
      if front or abs(x - GX) > GR + 2 then gfx.drawPixel(x, y) end
    end
    gfx.setColor(gfx.kColorBlack)
    return
  end
  local th = (self.fy * 13 % 1) * TAU
  local sn = sin(th)
  if (sn >= 0) ~= front then return end
  local x, y = GX + a * cos(th), GY + b * sn
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(x, y, 5)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(x - 3, y + 1, 4)
end

function M:drawLife(R)
  -- city lights on the night side; dark specks by day
  local n = self.cityN
  if n > 0 then
    local cities, jx, jy = self.cities, self.cityJx, self.cityJy
    for k = 1, n do
      local x, y, vis, lit = self:project(cities[k], R)
      if vis > 0.08 then
        x, y = floor(x + jx[k]), floor(y + jy[k])
        if lit < -0.04 then
          gfx.setColor(gfx.kColorWhite)
          if k <= 12 then gfx.fillRect(x, y, 2, 2) else gfx.drawPixel(x, y) end
          if k % 3 == 0 then gfx.drawPixel(x + 3, y + 1) end
        else
          gfx.setColor(gfx.kColorBlack)
          gfx.drawPixel(x, y)
        end
      end
    end
    gfx.setColor(gfx.kColorBlack)
  end
  -- campfires: the first minds
  local mi = self.aMinds
  if mi and not self.aCiv and self.cityOrigin > 0 then
    local p = -self:deltaYears(mi.em, mi.ey) / mi.w
    if p > 0.3 then
      local x, y, vis, lit = self:project(self.cityOrigin, R)
      if vis > 0.1 and lit < 0 then
        gfx.setColor(gfx.kColorWhite)
        local k = floor(p * 5)
        for q = 0, k do
          if (floor(self.vt * 7) + q) % 3 ~= 0 then gfx.drawPixel(x + (q * 3) % 7 - 3, y + (q * 5) % 5 - 2) end
        end
        gfx.setColor(gfx.kColorBlack)
      end
    end
  end
  -- satellites, late in the civilization
  if self.aCiv and (self.civP or 0) > 0.55 then
    gfx.setColor(gfx.kColorWhite)
    for k = 1, 7 do
      local th = self.vt * (0.6 + k * 0.13) + k * 1.9
      local rr = R + 7 + k * 2
      local x = GX + rr * cos(th)
      local y = GY + rr * sin(th) * (0.25 + (k % 3) * 0.2)
      if sin(th) > 0 or abs(x - GX) > R then gfx.drawPixel(x, y) end
    end
    gfx.setColor(gfx.kColorBlack)
  end
  -- what they left in orbit
  if self.ring > 0 then
    gfx.setColor(gfx.kColorWhite)
    local every = self.ring > 0.5 and 2 or (self.ring > 0.2 and 3 or 5)
    local a, b = R + 16, (R + 16) * 0.22
    for k = 0, 71, every do
      local th = k * TAU / 72
      local x, y = GX + a * cos(th), GY + b * sin(th)
      if sin(th) > 0 or abs(x - GX) > R + 1 then gfx.drawPixel(x, y) end
    end
    gfx.setColor(gfx.kColorBlack)
  end
end

function M:drawEvents(R)
  -- flashes: impacts seen at a slow enough rate
  local fi, ft = self.flashI, self.flashT
  for k = 1, #fi do
    local v = ft[k]
    if v > 0 then
      local x, y, vis = self:project(fi[k], R)
      if vis > 0 then
        gfx.setColor(gfx.kColorWhite)
        local rr = floor((1 - v) * 14) + 2
        gfx.drawCircleAtPoint(x, y, rr)
        if v > 0.6 then gfx.fillCircleAtPoint(x, y, 3) end
        gfx.setColor(gfx.kColorBlack)
      end
    end
  end
  -- impact winter: the world darkens and clears over thousands of years
  if self.dust > 1 then
    local d = self.dust
    gfx.setPattern(d > 12 and PT_SHADE75 or (d > 6 and PT_SHADE50 or PT_SHADE25))
    gfx.fillCircleAtPoint(GX, GY, R)
  end
  -- the fireball, at the very slowest scales
  local im = self.aImpact
  if im and self.impactCell then
    local age = -self:deltaYears(im.em, im.ey)
    if age < 3 then
      local x, y, vis = self:project(self.impactCell, R)
      if vis > 0 then
        gfx.setColor(gfx.kColorWhite)
        gfx.fillCircleAtPoint(x, y, 4 + (3 - age) * 3)
        gfx.drawCircleAtPoint(x, y, 8 + age * 12)
        gfx.setColor(gfx.kColorBlack)
      end
    end
  end
end

function M:drawComet()
  local c = self.aComet
  if not c then return end
  local u = U.clamp(-self:deltaYears(c.em, c.ey) / c.w, 0, 1)
  local x = 30 + 330 * u
  local y = 150 - 110 * sin(u * pi)
  local dx, dy = x - SUNX, y - SUNY
  local l = sqrt(dx * dx + dy * dy) + 0.01
  dx, dy = dx / l, dy / l
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(x, y, 2)
  for k = 1, 22 do
    if k < 8 or k % 2 == 0 then gfx.drawPixel(x + dx * k * 1.4, y + dy * k * 1.4) end
    if k % 3 == 0 then gfx.drawPixel(x + dx * k * 1.2 + dy * 2, y + dy * k * 1.2 - dx * 2) end
  end
  gfx.setColor(gfx.kColorBlack)
end

function M:drawDebris(R, t)
  local u = U.clamp(t / 30, 0, 1)
  gfx.setColor(gfx.kColorWhite)
  local da, dr = self.debrisA, self.debrisR
  for k = 1, #da do
    local rr = R + (GR * 0.9) * dr[k] * (1 - u)
    local th = da[k] + self.vt * (0.9 / (0.4 + dr[k]))
    local x, y = GX + rr * cos(th), GY + rr * sin(th) * 0.45
    if sin(th) > 0 or abs(x - GX) > R then gfx.drawPixel(x, y) end
  end
  gfx.setColor(gfx.kColorBlack)
end

-- the ruler: a logarithmic horizon, NOW at the left, 1 yr .. 10 Gyr
local function rulerX(years)
  if years < 1 then return RX0 end
  local x = RX0 + log(years) / LN10 * PXD
  if x > RX1 then x = RX1 end
  return x
end

-- a small solid wedge (pointing down for dir 1, up for -1), without polygons
local function wedge(x, y, size, dir)
  for k = 0, size - 1 do
    local hw = size - 1 - k
    gfx.fillRect(x - hw, y + k * dir, 2 * hw + 1, 1)
  end
end

local function drawEye(x, y, open)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawLine(x - 5, y, x - 2, y - 2)
  gfx.drawLine(x - 2, y - 2, x + 2, y - 2)
  gfx.drawLine(x + 2, y - 2, x + 5, y)
  gfx.drawLine(x - 5, y, x - 2, y + 2)
  gfx.drawLine(x - 2, y + 2, x + 2, y + 2)
  gfx.drawLine(x + 2, y + 2, x + 5, y)
  if open then gfx.fillRect(x - 1, y - 1, 3, 3) end
  gfx.setColor(gfx.kColorBlack)
end

local function buildRuler(w, h)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(0, 0, w, h)
  gfx.setColor(gfx.kColorWhite)
  local by = RY - RYT
  gfx.drawLine(RX0, by, RX1, by)
  for d = 0, 10 do
    local x = floor(RX0 + d * PXD + 0.5)
    local major = d % 3 == 0
    gfx.drawLine(x, by, x, by + (major and 4 or 2))
    if d < 10 then
      for k = 2, 9 do
        local xm = floor(RX0 + (d + log(k) / LN10) * PXD + 0.5)
        gfx.drawPixel(xm, by + 1)
      end
    end
  end
  tinyText("1Y", floor(RX0 - 3), by + 7)
  tinyText("1K", floor(RX0 + 3 * PXD - 3), by + 7)
  tinyText("1M", floor(RX0 + 6 * PXD - 3), by + 7)
  tinyText("1G", floor(RX0 + 9 * PXD - 3), by + 7)
  UI.textW("NOW", 4, 3, "left")
  gfx.setColor(gfx.kColorBlack)
end

function M:drawRuler()
  local img = Art.cached("bil_ruler", 400, 26, buildRuler)
  img:draw(0, RYT)
  if self.blind then
    UI.textW("the horizon is dark", 220, RYT + 2, "center")
    return
  end
  local focus = self.focus
  -- milestones ahead
  gfx.setColor(gfx.kColorWhite)
  for k = self.upN, 1, -1 do
    local e = upE[k]
    local x = floor(rulerX(upD[k]))
    if e == focus then
      wedge(x, RY - 6, 5, 1)
      gfx.fillRect(x - 1, RY - 12, 3, 6)
    else
      wedge(x, RY - 5, 4, 1)
    end
  end
  -- something happening now
  if focus and focus.st == 1 then
    local on = floor(self.vt * 4) % 2 == 0
    gfx.setColor(gfx.kColorWhite)
    if on then gfx.fillCircleAtPoint(RX0, RY - 5, 4) else gfx.drawCircleAtPoint(RX0, RY - 5, 4) end
  end
  -- the eye: how slow you must go to witness the focus
  if focus then
    local ex = floor(rulerX(focus.lim))
    gfx.setColor(gfx.kColorWhite)
    for y = RYT + 12, RY - 1, 2 do gfx.drawPixel(ex, y) end
    drawEye(ex, RYT + 7, focus.st == 1 and self.rate <= focus.lim and self.rate > 0)
  end
  -- the hand: how far one second of cranking goes
  local hx = floor(rulerX(self.rateS))
  local blink = self.tooFast and floor(self.vt * 8) % 2 == 0
  gfx.setColor(gfx.kColorWhite)
  if not blink then
    gfx.fillRect(hx - 1, RY - 3, 3, 12)
    wedge(hx, RY + 9, 5, -1)
  else
    gfx.drawRect(hx - 1, RY - 3, 3, 12)
  end
  gfx.setColor(gfx.kColorBlack)
end

function M:dateText()
  local my, ky = self.my, self.ky
  local v, s, unit
  if my >= 1000 then
    v = my
    if v ~= self.dateV then self.dateS = string.format("%.3f", my / 1000) end
    unit = "BILLION YEARS"
  elseif my >= 10 then
    v = my
    if v ~= self.dateV then self.dateS = string.format("%d", my) end
    unit = "MILLION YEARS"
  elseif my >= 1 then
    v = floor(my * 100 + ky / 1e4)
    if v ~= self.dateV then self.dateS = string.format("%.2f", v / 100) end
    unit = "MILLION YEARS"
  else
    v = floor(ky)
    if v ~= self.dateV then
      if v >= 1000 then self.dateS = string.format("%d,%03d", v // 1000, v % 1000)
      else self.dateS = string.format("%d", v) end
    end
    unit = "YEARS"
  end
  self.dateV = v
  return self.dateS, unit
end

function M:scaleText()
  if self.held > 0 then return "time is held" end
  local ypd = self.ypt / 360
  local v
  if ypd < 1 / 300 then v = -1
  elseif ypd < 1 then v = -floor(ypd * 365 + 0.5)
  else
    local e = floor(log(ypd) / LN10)
    local q = 10 ^ max(0, e - 1)
    v = floor(ypd / q + 0.5) * q
  end
  if v ~= self.scaleV then
    self.scaleV = v
    if v == -1 then self.scaleS = "1 degree = 1 day"
    elseif v < 0 then self.scaleS = string.format("1 degree = %d days", -v)
    elseif v < 1000 then self.scaleS = string.format("1 degree = %d years", floor(v))
    elseif v < 1e6 then self.scaleS = string.format("1 degree = %d,%03d years", floor(v / 1000), floor(v % 1000))
    else self.scaleS = string.format("1 degree = %.1f million years", v / 1e6) end
  end
  return self.scaleS
end

function M:eonName(t)
  if self.tut then return "THE LESSON" end
  local f = self.fate
  if t < 30 then return "COALESCING" end
  if self.stage == 8 or t > f.lastlife then return (t > f.giant) and "THE LAST SUNRISE" or "THE FURNACE" end
  if self.dying then return "THE DRYING" end
  if self.stage == 7 then return "THE AGE OF MINDS" end
  if self.snowball then return "SNOWBALL" end
  if self.stage >= 4 then return "PHANEROZOIC" end
  if self.stage >= 2 then return (self.stage == 2 and t > 2900 and t < 3500) and "THE BORING BILLION" or "PROTEROZOIC" end
  if self.stage >= 1 or t > 500 then return "ARCHEAN" end
  return "HADEAN"
end

function M:drawHud(t)
  -- when the swollen sun reaches the instruments, give them a dark card
  if self.bigSun then
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 19, 116, 136)
    gfx.fillRect(GRAPHX - 4, 74, 400 - GRAPHX + 4, 108)
    gfx.fillRect(GX - 100, 176, 200, 18)
  end
  -- date, top left
  local ds, unit = self:dateText()
  UI.textW(ds, 6, 21, "left", UI.bold)
  UI.textW(unit, 6, 37)
  local eon = self:eonName(t)
  if self.rateS < 3 then
    local q = floor(self.fy * 4) % 4
    eon = (q == 0) and "WINTER" or ((q == 1) and "SPRING" or ((q == 2) and "SUMMER" or "AUTUMN"))
  end
  gfx.setColor(gfx.kColorWhite)
  gfx.drawLine(6, 55, 70, 55)
  UI.textW(eon, 6, 57)

  -- the scale, under the globe
  UI.textW(self:scaleText(), GX, 177, "center")

  if self.hideHud then return end

  -- the witness panel
  local e = self.focus
  local y0 = 88
  if self.wmsgT > 0 and self.wmsgName then
    drawEye(12, y0 + 8, self.wmsg == "WITNESSED")
    UI.textW(self.wmsg, 24, y0, "left", UI.bold)
    UI.textBlock(self.wmsgName, 6, y0 + 18, 104, UI.font, 0, nil, true)
    if self.wmsgPts and self.wmsgPts > 0 and not self.tut then
      UI.textW(U.cached("bil_pts", "+%d", self.wmsgPts), 6, y0 + 52, "left", UI.bold)
    end
  elseif e then
    local ds2 = (e.st == 1) and 0 or self:deltaYears(e.em, e.ey)
    local eta = ds2 / max(1, self.rateS)
    if e.st == 1 or eta < 6 or ds2 < e.w * 3 then
      local status
      if e.st == 1 then
        if self.rate == 0 then status = "HOLDING"
        elseif self.tooFast then status = (floor(self.vt * 6) % 2 == 0) and "SLOWER!" or ""
        else status = "WATCHING" end
      elseif self.rateS > e.lim and eta < 4 then
        status = (floor(self.vt * 5) % 2 == 0) and "SLOW DOWN" or ""
      else
        status = "APPROACHING"
      end
      drawEye(12, y0 + 8, e.st == 1 and self.rate > 0 and not self.tooFast)
      UI.textW(status, 24, y0, "left", UI.bold)
      UI.textBlock(EV[e.k].name, 6, y0 + 18, 104, UI.font, 0, nil, true)
      if e.st == 1 then
        local f = U.clamp(e.seen / self.need, 0, 1)
        gfx.setColor(gfx.kColorWhite)
        gfx.drawRect(6, y0 + 54, 100, 7)
        gfx.fillRect(8, y0 + 56, floor(96 * f), 3)
        gfx.setColor(gfx.kColorBlack)
      end
    end
  end

  -- log, right column
  local lw = self.logWrapped
  if lw then
    local nShown = min(#lw, 1 + floor(self.logT * 2.5))
    gfx.setColor(gfx.kColorWhite)
    gfx.drawLine(GRAPHX, 76, GRAPHX + 20, 76)
    for k = 1, min(nShown, 3) do UI.textW(lw[k], GRAPHX, 62 + k * 16) end
  end

  -- the tree of life
  if not self.tut and self.graphFill > 0 and self.stage > 0 then
    local hist = self.histD
    gfx.setColor(gfx.kColorWhite)
    gfx.drawLine(GRAPHX, GRAPHY + GRAPHH, GRAPHX + GRAPHW - 1, GRAPHY + GRAPHH)
    local nf = self.graphFill
    for k = 1, nf do
      local hh = floor(sqrt(hist[k] / 2600) * GRAPHH + 0.5)
      if hh > 0 then gfx.drawLine(GRAPHX + k - 1, GRAPHY + GRAPHH - hh, GRAPHX + k - 1, GRAPHY + GRAPHH) end
    end
    if floor(self.vt * 2) % 2 == 0 then gfx.drawLine(GRAPHX + nf - 1, GRAPHY, GRAPHX + nf - 1, GRAPHY + 3) end
    gfx.setColor(gfx.kColorBlack)
    if self.D >= 1 then
      local dv = floor(self.D)
      if dv ~= self.graphV then
        self.graphV = dv
        self.graphS = string.format("LIFE %d", dv)
      end
      UI.textW(self.graphS, GRAPHX, GRAPHY - 17)
    end
  end
end

local function buildStars(w, h)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(0, 0, w, h)
  local r = U.rng(1313)
  gfx.setColor(gfx.kColorWhite)
  for _ = 1, 150 do
    local x, y = r:range(0, w - 1), r:range(18, h - 44)
    gfx.drawPixel(x, y)
    if r:chance(0.08) then gfx.drawPixel(x + 1, y) gfx.drawPixel(x, y + 1) end
  end
  gfx.setColor(gfx.kColorBlack)
end

local function buildRing(w, h)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(w // 2, h // 2, GR + 9)
  gfx.setColor(gfx.kColorClear)
  gfx.fillCircleAtPoint(w // 2, h // 2, GR)
end

function M:draw()
  gfx.clear(gfx.kColorBlack)
  local stars = Art.cached("bil_stars", 400, 240, buildStars)
  stars:draw(0, 0)
  local t = self:nowMyr()
  local sr = self:sunRadius(t)
  local giant = sr > 24
  self.bigSun = sr > 70
  local dSun = sqrt((SUNX - GX) ^ 2 + (SUNY - GY) ^ 2)
  local sunFront = sr > dSun + GR * 0.25
  if not sunFront then self:drawSun(sr, giant) end
  self:drawComet()
  self:drawMoon(false, t)
  -- the planet, coalescing from debris during its first tens of millions of years
  local R = GR
  if t < 30 and not self.tut then R = floor(GR * (0.15 + 0.85 * smooth(t / 30)) + 0.5) end
  if R < GR then
    self:drawProto(R)
  else
    self:drawGlobeCached(R)
  end
  if R == GR then
    local ring = Art.cached("bil_ring", 2 * GR + 24, 2 * GR + 24, buildRing)
    ring:draw(GX - GR - 12, GY - GR - 12)
    -- atmosphere on the lit limb
    if self.water > 0.2 and not (self.mf > 0.9) then
      gfx.setColor(gfx.kColorWhite)
      gfx.drawArc(GX, GY, GR + 2, SUNANG - 70, SUNANG + 70)
      if self.stage >= 2 and self.stage < 8 then gfx.drawArc(GX, GY, GR + 3, SUNANG - 35, SUNANG + 35) end
      gfx.setColor(gfx.kColorBlack)
    end
  else
    self:drawDebris(R, t)
  end
  self:drawLife(R)
  self:drawEvents(R)
  self:drawMoon(true, t)
  if sunFront then self:drawSun(sr, giant) end

  self:drawHud(t)
  if not self.hideHud then self:drawRuler() end

  local right
  if self.tut then right = "LESSON"
  elseif self.mode == "endless" then
    right = ROMAN_WORLD[min(self.planet, 20)] .. U.cached("bil_hdr", "  SEEN %d", self.witN)
  else
    right = U.cached("bil_hdr", "SEEN %d", self.witN) .. U.cached("bil_hdr2", "/%d", self.scorable)
  end
  UI.header(13, "ONE BILLION YEARS", right)
  gfx.setColor(gfx.kColorWhite)
  for x = 0, 399, 4 do gfx.drawPixel(x, 18) end
  gfx.setColor(gfx.kColorBlack)
  UI.hints(self.mode == "endless" and M.HINTS_END or M.HINTS)

  -- the end: the sun fills everything
  if self.ending then
    local a = U.clamp(self.endT / 2.2, 0, 1)
    if self.restEnd then
      gfx.setPattern(a < 0.5 and PT_SHADE50 or PT_SHADE75)
      gfx.fillRect(0, 19, 400, 203)
    else
      gfx.setPattern(a < 0.33 and Art.pat.gray75 or (a < 0.66 and Art.pat.gray25 or Art.pat.white))
      gfx.fillRect(0, 0, 400, 240)
      if a >= 0.66 then UI.text("THE LAST SUNRISE", 200, 112, "center", UI.bold) end
    end
    gfx.setColor(gfx.kColorBlack)
  end
end

function M:log(str)
  if not str then return end
  self.logWrapped = UI.wrap(str, 114, UI.font)
  self.logT = 0
end

------------------------------------------------------------------------
-- suspend / resume
------------------------------------------------------------------------
function M:serialize()
  if self.tut then return nil end
  local hs, ps = {}, {}
  for i = 1, N do hs[i] = floor(self.h[i] + 0.5) ps[i] = self.pl[i] end
  local evs = {}
  for i, e in ipairs(self.ev) do
    evs[i] = { k = e.k, em = e.em, ey = e.ey, w = e.w, pts = e.pts, st = e.st, seen = e.seen,
      wit = e.wit, miss = e.miss, rev = e.rev, lim = e.lim, reveal = e.reveal }
  end
  local cities, jx, jy = {}, {}, {}
  for k = 1, (self.cityMax or 0) do cities[k] = self.cities[k] jx[k] = self.cityJx[k] jy[k] = self.cityJy[k] end
  local vx, vy, ox, oy = {}, {}, {}, {}
  for p = 1, MAXP do vx[p], vy[p], ox[p], oy[p] = self.vx[p], self.vy[p], self.ox[p], self.oy[p] end
  local traps = {}
  for k = 1, #self.trapList do traps[k] = self.trapList[k] end
  local hd = {}
  for k = 1, GRAPHW do hd[k] = floor(self.histD[k]) end
  local f = self.fate
  return {
    v = 1, my = self.my, ky = self.ky, fy = self.fy, rot = self.rot, planet = self.planet,
    score = self.score, witN = self.witN, planetWit = self.planetWit,
    water = self.water, co2 = self.co2, T = self.T, spike = self.spike, hot = self.hot, dust = self.dust,
    stage = self.stage, D = self.D, sea = self.sea, mf = self.mf,
    snowball = self.snowball, rained = self.rained, boiling = self.boiling, boiled = self.boiled, dying = self.dying,
    ring = self.ring, clade = self.clade or "", cityMax = self.cityMax or 0, cityOrigin = self.cityOrigin,
    rarest = self.rarest or "", rarestPts = self.rarestPts, icePhase = self.icePhase,
    fate = { lastforest = f.lastforest, boil = f.boil, lastlife = f.lastlife, giant = f.giant,
      giantEnd = f.giantEnd, iceStart = f.iceStart },
    h = hs, pl = ps, ev = evs, evFirst = self.evFirst, scorable = self.scorable,
    cities = cities, jx = jx, jy = jy, vx = vx, vy = vy, ox = ox, oy = oy, traps = traps,
    histD = hd, graphFill = self.graphFill, rng = self.rng:state(),
  }
end

function M:deserialize(t)
  if type(t) ~= "table" or t.v ~= 1 or self.tut then return end
  for _, k in ipairs({ "my", "ky", "fy", "rot", "planet", "score", "witN", "planetWit", "water", "co2", "T",
    "spike", "hot", "dust", "stage", "D", "sea", "mf", "snowball", "rained", "boiling", "boiled", "dying",
    "ring", "cityOrigin", "rarestPts", "icePhase", "evFirst", "scorable", "graphFill" }) do
    if t[k] ~= nil then self[k] = t[k] end
  end
  self.clade = (t.clade ~= "") and t.clade or nil
  self.rarest = (t.rarest ~= "") and t.rarest or nil
  self.fate = t.fate
  for i = 1, N do self.h[i] = t.h[i] self.pl[i] = t.pl[i] end
  self.ev = t.ev
  self.cityMax = t.cityMax
  for k = 1, t.cityMax do self.cities[k] = t.cities[k] self.cityJx[k] = t.jx[k] self.cityJy[k] = t.jy[k] end
  for p = 1, MAXP do self.vx[p], self.vy[p], self.ox[p], self.oy[p] = t.vx[p], t.vy[p], t.ox[p], t.oy[p] end
  for i = 1, N do self.trap[i] = 0 end
  self.trapList = {}
  for k = 1, #t.traps do self.trap[t.traps[k]] = 1 self.trapList[k] = t.traps[k] end
  for k = 1, GRAPHW do self.histD[k] = t.histD[k] end
  self.rng:setState(t.rng)
  self:fullSweep()
  self:fullSweep()
end
