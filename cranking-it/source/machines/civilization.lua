-- CRANKING IT :: No.XII HAND-CRANKED CIVILIZATION
--
-- The crank is the Wheel of History, and history has friction.
--
--   * Every 30 degrees of forward crank is a detent (a "season"): one
--     simulation substep. Twelve of them (one full turn) make a generation,
--     whose length in years depends on the era (Stone Age 250 years per
--     turn ... Modern 6). Idle crank = history waits for the hand.
--   * Crank SPEED is a political variable. Each era and government has a
--     tempo band: below it the realm stagnates, above it history is rushed
--     and breeds unrest (revolts, collapse). Inside it, faster = bolder
--     progress, and a STEADY hand (low speed variance) grows culture and
--     earns HANDS (influence).
--   * Cranking BACKWARD never rewinds time: it is friction - conservatism.
--     Unrest cools and order rises, but knowledge erodes a little.
--   * Events lock the wheel with a ratchet (the crank clicks against a
--     pawl) until you intervene: 2-3 choices with trade-offs.
-- The simulation runs per region (population, food, disease, devastation)
-- and per polity (government, wars, conquest), with six technology tracks,
-- climate cycles, exploration of offshore islands, culture and faith. A
-- civilization can last thousands of years, fall into a dark age and
-- recover - or fall for good. Work per frame is bounded: at most four
-- substeps, a fixed number of regions and polities.

local gfx <const> = playdate.graphics
local floor <const> = math.floor
local abs <const> = math.abs
local sin <const>, cos <const>, rad <const> = math.sin, math.cos, math.rad
local sqrt <const> = math.sqrt
local log <const> = math.log

local COLS <const>, ROWS <const>, CELL <const> = 34, 23, 8
local MX <const>, MY <const> = 0, 18
local MW <const>, MH <const> = COLS * CELL, ROWS * CELL
local NCELL <const> = COLS * ROWS
local MAXR <const> = 16
local MAXP <const> = 6
local MAXSHIP <const> = 4
local SUBDEG <const> = 30
local MAX_SUBSTEPS <const> = 4
local STANDARD_END <const> = 5000

local SEA <const>, PLAIN <const>, FOREST <const>, HILL <const>, MOUNT <const> = 0, 1, 2, 3, 4
local AGRI <const>, METAL <const>, SAIL <const>, MEDIC <const>, LETTERS <const>, INDUSTRY <const> = 1, 2, 3, 4, 5, 6

local ERAS <const> = {
  { name = "STONE AGE", say = "The Stone Age.", ypg = 250, lo = 0.18, hi = 0.80 },
  { name = "BRONZE AGE", say = "Bronze is poured. The Bronze Age begins.", ypg = 120, lo = 0.22, hi = 0.88 },
  { name = "IRON AGE", say = "Iron is forged. The Iron Age begins.", ypg = 70, lo = 0.26, hi = 0.96 },
  { name = "MIDDLE AGES", say = "Bells and walls: the Middle Ages.", ypg = 40, lo = 0.30, hi = 1.05 },
  { name = "AGE OF SAIL", say = "Sails on every horizon: the Age of Sail.", ypg = 30, lo = 0.35, hi = 1.18 },
  { name = "INDUSTRIAL", say = "Smoke and engines: the Industrial Age.", ypg = 16, lo = 0.42, hi = 1.35 },
  { name = "MODERN", say = "Wires hum. The Modern Age begins.", ypg = 10, lo = 0.50, hi = 1.55 },
}
local TRIBES <const>, CHIEFDOM <const>, KINGDOM <const>, EMPIRE <const>, THEOCRACY <const>, REPUBLIC <const>, WARLORDS <const> = 1, 2, 3, 4, 5, 6, 7
local GOV <const> = {
  { name = "TRIBES", pace = 1.12, stab = 52, aggr = 0.30, cult = 0.6, tech = 0.85 },
  { name = "CHIEFDOM", pace = 1.05, stab = 55, aggr = 0.45, cult = 0.8, tech = 0.9 },
  { name = "KINGDOM", pace = 1.00, stab = 60, aggr = 0.55, cult = 1.0, tech = 1.0 },
  { name = "EMPIRE", pace = 0.92, stab = 64, aggr = 0.75, cult = 1.1, tech = 1.0 },
  { name = "THEOCRACY", pace = 0.82, stab = 70, aggr = 0.35, cult = 1.25, tech = 0.75 },
  { name = "REPUBLIC", pace = 1.22, stab = 56, aggr = 0.30, cult = 1.2, tech = 1.3 },
  { name = "WARLORDS", pace = 1.00, stab = 32, aggr = 0.95, cult = 0.4, tech = 0.5 },
}
local GOV_PREFIX <const> = { "TRIBES OF ", "CHIEFDOM OF ", "KINGDOM OF ", "EMPIRE OF ", "HOLY ", "REPUBLIC OF ", "WARLORDS OF " }
local SYL <const> = { "AS", "TER", "KOR", "VA", "MER", "I", "DEN", "NIN", "E", "SAL", "ORN", "UL", "BRA", "DO",
  "KES", "TRA", "MO", "RIL", "VEN", "GA", "THA", "LON", "SE", "RU", "PEL", "AM", "OS", "HAR" }
local DIFF_PACE <const> = { 1.1, 1.0, 0.92 }
local ERA_TECH <const> = { 1.0, 0.75, 0.55, 0.42, 0.34, 0.3, 0.25 }
local TECH_NAMES <const> = { "AGRICULTURE", "METALS", "SAILS", "MEDICINE", "LETTERS", "INDUSTRY" }

local Civ = Machine.define({
  id = "civilization",
  number = 12,
  title = "HAND-CRANKED CIVILIZATION",
  tagline = "History has friction.",
  description = "Each turn of the crank is a generation. Rush history and it revolts; stall it and it rots. Keep a steady hand for 5000 years.",
  howto = "Crank to turn the Wheel of History: one turn = one generation. Keep the TEMPO needle in the steady band. Backward = friction (order up, progress down). Events lock the wheel: UP/DOWN, A. B spends a HAND to calm the realm.",
  controls = { { "CRANK", "wheel of history" }, { "B", "steady hand" }, { "A", "chronicle / decide" }, { "DPAD", "choose" } },
  modes = { "tutorial", "standard", "endless" },
  medals = { standard = { 2500, 5500, 7000 }, endless = { 4000, 9000, 15000 } },
  scoreLabel = "HISTORY",
  unlockCost = 12,
  achievements = {
    { id = "millennium", name = "A THOUSAND YEARS", desc = "Reach the year 1000." },
    { id = "statue", name = "THE HAND", desc = "Raise the statue of the hand." },
    { id = "survive", name = "FIVE THOUSAND", desc = "Reach the year 5000." },
    { id = "phoenix", name = "FROM THE ASHES", desc = "Recover from a dark age." },
    { id = "newlands", name = "NEW LANDS", desc = "Discover an island." },
  },
  challenges = {
    { id = "heavy", name = "HEAVY WHEEL", desc = "The realm tolerates much less haste.", mode = "standard", difficulty = 2, goal = 4500, reward = 3, cost = 2 },
    { id = "plague", name = "PLAGUE YEARS", desc = "Sickness comes twice as often.", mode = "standard", difficulty = 2, goal = 4000, reward = 2, cost = 2 },
    { id = "ages", name = "AGES OF MAN", desc = "Endless. Rise, fall, rise again.", mode = "endless", difficulty = 3, goal = 9000, reward = 3, cost = 3 },
  },
  records = {
    { "years", "Longest history", function(v) return v > 0 and (U.commas(v) .. " yrs") or "-" end },
    { "peakpop", "Peak population", function(v)
      if v <= 0 then return "-" end
      if v >= 1000 then return string.format("%.1fM", v / 1000) end
      return floor(v) .. "K"
    end },
    { "statues", "Statues of the hand" },
    { "falls", "Civilizations fallen" },
  },
  drawIcon = function(cx, cy)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(cx - 22, cy - 22, 44, 44)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(cx, cy, 19)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    gfx.drawCircleAtPoint(cx, cy, 15)
    gfx.setLineWidth(1)
    for i = 0, 7 do
      local a = rad(i * 45 + 10)
      gfx.drawLine(cx + sin(a) * 4, cy - cos(a) * 4, cx + sin(a) * 15, cy - cos(a) * 15)
    end
    -- a walled city at the hub
    gfx.fillRect(cx - 5, cy - 3, 10, 7)
    gfx.fillRect(cx - 2, cy - 8, 4, 5)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(cx - 1, cy, 2, 4)
    gfx.setColor(gfx.kColorBlack)
    -- the crank handle on the rim
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(cx + 12, cy - 12, 5)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(cx + 12, cy - 12, 3)
  end,
})

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------
local function cellIdx(c, r) return r * COLS + c + 1 end

local function makeName(rng)
  local n = rng:chance(0.6) and 2 or 3
  local s = ""
  for _ = 1, n do s = s .. SYL[rng:range(1, #SYL)] end
  return s
end

local function popText(k)
  if k >= 1000 then return string.format("%.1fM", k / 1000) end
  return floor(k + 0.5) .. "K"
end

local function drawHandGlyph(x, y, s)
  -- a small open hand, palm down-left of the fingers
  gfx.fillRect(x - 3 * s, y - 1 * s, 6 * s, 5 * s)
  for i = 0, 3 do gfx.fillRect(x - 3 * s + i * (1.5 * s), y - 5 * s + (i == 0 and s or 0) + (i == 3 and s or 0), s, 4 * s) end
  gfx.fillRect(x + 3 * s, y, 2 * s, s)
end

------------------------------------------------------------------------
-- world generation (map, terrain, rivers, regions)
------------------------------------------------------------------------
function Civ:genWorld(nMain)
  local rng = self.rng
  local h, m = {}, {}
  -- two octaves of value noise from coarse random grids
  local g1w, g1h = 7, 5
  local g1 = {}
  for i = 1, g1w * g1h do g1[i] = rng:float() end
  local g2w, g2h = 13, 9
  local g2 = {}
  for i = 1, g2w * g2h do g2[i] = rng:float() end
  local gm = {}
  for i = 1, g1w * g1h do gm[i] = rng:float() end
  local function sample(g, gw, gh, x, y)
    local fx, fy = x * (gw - 1), y * (gh - 1)
    local ix, iy = math.min(gw - 2, floor(fx)), math.min(gh - 2, floor(fy))
    local tx, ty = fx - ix, fy - iy
    tx, ty = U.smoothstep(tx), U.smoothstep(ty)
    local a = g[iy * gw + ix + 1]
    local b = g[iy * gw + ix + 2]
    local c = g[(iy + 1) * gw + ix + 1]
    local d = g[(iy + 1) * gw + ix + 2]
    return a + (b - a) * tx + (c - a) * ty + (a - b - c + d) * tx * ty
  end
  local ox, oy = rng:between(-0.08, 0.08), rng:between(-0.06, 0.06)
  local sorted = {}
  for r = 0, ROWS - 1 do
    for c = 0, COLS - 1 do
      local x, y = c / (COLS - 1), r / (ROWS - 1)
      local n = sample(g1, g1w, g1h, x, y) * 0.7 + sample(g2, g2w, g2h, x, y) * 0.35
      local dx, dy = (x - 0.5 - ox) / 0.5, (y - 0.5 - oy) / 0.5
      local d = dx * dx * 0.9 + dy * dy
      local i = cellIdx(c, r)
      h[i] = n - d * 0.75
      m[i] = sample(gm, g1w, g1h, 1 - x, y)
      sorted[i] = h[i]
    end
  end
  table.sort(sorted)
  local sea = sorted[floor(NCELL * 0.54)]
  local ter = {}
  for i = 1, NCELL do ter[i] = (h[i] > sea) and PLAIN or SEA end
  -- borders are always sea
  for c = 0, COLS - 1 do ter[cellIdx(c, 0)] = SEA ter[cellIdx(c, ROWS - 1)] = SEA end
  for r = 0, ROWS - 1 do ter[cellIdx(0, r)] = SEA ter[cellIdx(COLS - 1, r)] = SEA end
  -- connected components of land
  local comp = {}
  for i = 1, NCELL do comp[i] = 0 end
  local sizes = {}
  local stack = {}
  local nc = 0
  for i = 1, NCELL do
    if ter[i] ~= SEA and comp[i] == 0 then
      nc = nc + 1
      local size = 0
      stack[1] = i
      local sp = 1
      comp[i] = nc
      while sp > 0 do
        local j = stack[sp] sp = sp - 1
        size = size + 1
        local c, r = (j - 1) % COLS, (j - 1) // COLS
        for k = 1, 4 do
          local nc2, nr2 = c, r
          if k == 1 then nc2 = c + 1 elseif k == 2 then nc2 = c - 1 elseif k == 3 then nr2 = r + 1 else nr2 = r - 1 end
          if nc2 >= 0 and nc2 < COLS and nr2 >= 0 and nr2 < ROWS then
            local q = cellIdx(nc2, nr2)
            if ter[q] ~= SEA and comp[q] == 0 then comp[q] = nc sp = sp + 1 stack[sp] = q end
          end
        end
      end
      sizes[nc] = size
    end
  end
  local main = 1
  for k = 1, nc do if sizes[k] > sizes[main] then main = k end end
  -- islands: other components of size >= 4 (at most 3); tiny ones sink
  local island = {}
  for i = 1, NCELL do island[i] = 0 end
  local islandComps = {}
  for k = 1, nc do
    if k ~= main and sizes[k] >= 4 and #islandComps < 3 then islandComps[#islandComps + 1] = k end
  end
  for i = 1, NCELL do
    if ter[i] ~= SEA and comp[i] ~= main then
      local keep = false
      for q = 1, #islandComps do if islandComps[q] == comp[i] then keep = true island[i] = q end end
      if not keep then ter[i] = SEA end
    end
  end
  -- guarantee at least one island: raise a blob in open sea far from land
  if #islandComps == 0 then
    for _ = 1, 200 do
      local c, r = rng:range(2, COLS - 3), rng:range(2, ROWS - 3)
      local ok = true
      for dr = -3, 3 do for dc = -3, 3 do
        local cc, rr = c + dc, r + dr
        if cc >= 0 and cc < COLS and rr >= 0 and rr < ROWS and ter[cellIdx(cc, rr)] ~= SEA then ok = false end
      end end
      if ok then
        islandComps[1] = -1
        for dr = -1, 1 do for dc = -1, 1 do
          if abs(dr) + abs(dc) < 2 or rng:chance(0.5) then
            local q = cellIdx(c + dc, r + dr)
            ter[q] = PLAIN island[q] = 1 h[q] = sea + 0.05
          end
        end end
        break
      end
    end
  end
  -- terrain by height and moisture (mainland + islands)
  local landH = {}
  for i = 1, NCELL do if ter[i] ~= SEA then landH[#landH + 1] = h[i] end end
  table.sort(landH)
  local mountT = landH[math.max(1, floor(#landH * 0.9))]
  local hillT = landH[math.max(1, floor(#landH * 0.74))]
  for i = 1, NCELL do
    if ter[i] ~= SEA then
      if h[i] >= mountT then ter[i] = MOUNT
      elseif h[i] >= hillT then ter[i] = HILL
      elseif m[i] > 0.56 then ter[i] = FOREST end
    end
  end
  -- rivers: steepest descent from mountains to the sea
  local river = {}
  for i = 1, NCELL do river[i] = false end
  local mounts = {}
  for i = 1, NCELL do if ter[i] == MOUNT and island[i] == 0 then mounts[#mounts + 1] = i end end
  self.rivers = {}
  for _ = 1, 2 do
    if #mounts == 0 then break end
    local j = mounts[rng:range(1, #mounts)]
    local path = {}
    for _ = 1, 40 do
      path[#path + 1] = j
      river[j] = true
      local c, r = (j - 1) % COLS, (j - 1) // COLS
      local best, bh = nil, h[j]
      local seaN = nil
      for k = 1, 4 do
        local nc2, nr2 = c, r
        if k == 1 then nc2 = c + 1 elseif k == 2 then nc2 = c - 1 elseif k == 3 then nr2 = r + 1 else nr2 = r - 1 end
        local q = cellIdx(nc2, nr2)
        if ter[q] == SEA then seaN = q end
        if h[q] < bh and not river[q] then best, bh = q, h[q] end
      end
      if seaN then path[#path + 1] = seaN break end
      if not best then break end
      j = best
    end
    if #path >= 4 then self.rivers[#self.rivers + 1] = path else for q = 1, #path do river[path[q]] = false end end
  end
  self.ter, self.h, self.river, self.island = ter, h, river, island
  self:genRegions(nMain)
end

function Civ:genRegions(nMain)
  local rng = self.rng
  local ter, island = self.ter, self.island
  local mainland = {}
  for i = 1, NCELL do if ter[i] ~= SEA and island[i] == 0 then mainland[#mainland + 1] = i end end
  -- farthest point sampling for region seeds
  local seeds = { mainland[rng:range(1, #mainland)] }
  while #seeds < nMain do
    local best, bd = nil, -1
    for q = 1, #mainland do
      local i = mainland[q]
      local c, r = (i - 1) % COLS, (i - 1) // COLS
      local md = 1e9
      for s = 1, #seeds do
        local sc, sr = (seeds[s] - 1) % COLS, (seeds[s] - 1) // COLS
        local d = (c - sc) ^ 2 + (r - sr) ^ 2
        if d < md then md = d end
      end
      md = md + rng:float() * 2
      if md > bd then best, bd = i, md end
    end
    seeds[#seeds + 1] = best
  end
  local reg = {}
  for i = 1, NCELL do reg[i] = 0 end
  for q = 1, #mainland do
    local i = mainland[q]
    local c, r = (i - 1) % COLS, (i - 1) // COLS
    local bs, bd = 1, 1e9
    for s = 1, #seeds do
      local sc, sr = (seeds[s] - 1) % COLS, (seeds[s] - 1) // COLS
      local d = (c - sc) ^ 2 + (r - sr) ^ 2
      if d < bd then bs, bd = s, d end
    end
    reg[i] = bs
  end
  local NR = #seeds
  -- islands become their own regions
  local islandReg = {}
  for i = 1, NCELL do
    if island[i] > 0 then
      local k = island[i]
      if not islandReg[k] then NR = NR + 1 islandReg[k] = NR end
      reg[i] = islandReg[k]
    end
  end
  self.reg, self.NR = reg, NR
  -- region stats
  local R = self.R
  for k = 1, MAXR do
    R.cells[k], R.fert[k], R.coast[k], R.riv[k], R.isl[k] = 0, 0, false, false, false
    R.sx[k], R.sy[k] = 0, 0
  end
  for i = 1, NCELL do
    local k = reg[i]
    if k > 0 then
      local t = ter[i]
      local f = (t == PLAIN) and 1.0 or (t == FOREST and 0.6 or (t == HILL and 0.45 or 0.15))
      if self.river[i] then f = f + 0.8 R.riv[k] = true end
      local c, r = (i - 1) % COLS, (i - 1) // COLS
      local coastal = false
      for d = 1, 4 do
        local nc2, nr2 = c, r
        if d == 1 then nc2 = c + 1 elseif d == 2 then nc2 = c - 1 elseif d == 3 then nr2 = r + 1 else nr2 = r - 1 end
        if ter[cellIdx(nc2, nr2)] == SEA then coastal = true end
      end
      if coastal then f = f + 0.3 R.coast[k] = true end
      R.cells[k] = R.cells[k] + 1
      R.fert[k] = R.fert[k] + f
      R.sx[k] = R.sx[k] + c
      R.sy[k] = R.sy[k] + r
      if island[i] > 0 then R.isl[k] = true end
    end
  end
  -- settlement site: best cell near the centroid
  for k = 1, NR do
    local cx, cy = R.sx[k] / math.max(1, R.cells[k]), R.sy[k] / math.max(1, R.cells[k])
    local best, bs = nil, -1e9
    for i = 1, NCELL do
      if reg[i] == k then
        local c, r = (i - 1) % COLS, (i - 1) // COLS
        local t = ter[i]
        local sc = (t == PLAIN and 1 or (t == FOREST and 0.4 or (t == HILL and 0.3 or -2))) + (self.river[i] and 1 or 0)
        sc = sc - ((c - cx) ^ 2 + (r - cy) ^ 2) * 0.25
        if sc > bs then best, bs = i, sc end
      end
    end
    local c, r = (best - 1) % COLS, (best - 1) // COLS
    R.x[k] = MX + c * CELL + 4
    R.y[k] = MY + r * CELL + 4
  end
  -- adjacency (shared cell edges)
  local adj = self.adj
  for q = 1, MAXR * MAXR do adj[q] = 0 end
  for i = 1, NCELL do
    local a = reg[i]
    if a > 0 then
      local c, r = (i - 1) % COLS, (i - 1) // COLS
      if c < COLS - 1 then local b = reg[i + 1] if b > 0 and b ~= a then adj[(a - 1) * MAXR + b] = 1 adj[(b - 1) * MAXR + a] = 1 end end
      if r < ROWS - 1 then local b = reg[i + COLS] if b > 0 and b ~= a then adj[(a - 1) * MAXR + b] = 1 adj[(b - 1) * MAXR + a] = 1 end end
    end
  end
  -- coastal sea cells for ships
  local cs = {}
  for i = 1, NCELL do
    if ter[i] == SEA then
      local c, r = (i - 1) % COLS, (i - 1) // COLS
      if c > 0 and c < COLS - 1 and r > 0 and r < ROWS - 1 then
        local near = false
        for d = 1, 4 do
          local nc2, nr2 = c, r
          if d == 1 then nc2 = c + 1 elseif d == 2 then nc2 = c - 1 elseif d == 3 then nr2 = r + 1 else nr2 = r - 1 end
          local q = cellIdx(nc2, nr2)
          if ter[q] ~= SEA and island[q] == 0 then near = true end
        end
        if near then cs[#cs + 1] = i end
      end
    end
  end
  self.coastSea = cs
  local coastN = 0
  for k = 1, NR do if R.coast[k] and not R.isl[k] then coastN = coastN + 1 end end
  self.coastShare = coastN / math.max(1, nMain)
end

function Civ:adjacent(a, b) return self.adj[(a - 1) * MAXR + b] == 1 end

------------------------------------------------------------------------
-- map art (static, rebuilt only when an island is discovered)
------------------------------------------------------------------------
function Civ:renderMap()
  local img = self.mapImg
  local ter, reg, R = self.ter, self.reg, self.R
  local rng = U.rng(self.mapSeed)
  gfx.pushContext(img)
  gfx.clear(gfx.kColorWhite)
  -- sea
  for i = 1, NCELL do
    local visible = ter[i] ~= SEA and (reg[i] == 0 or not R.isl[reg[i]] or R.known[reg[i]])
    if not visible then
      local c, r = (i - 1) % COLS, (i - 1) // COLS
      gfx.setPattern(Art.pat.gray12)
      gfx.fillRect(c * CELL, r * CELL, CELL, CELL)
    end
  end
  gfx.setColor(gfx.kColorBlack)
  -- wave marks
  for i = 1, NCELL do
    local c, r = (i - 1) % COLS, (i - 1) // COLS
    if ter[i] == SEA and (c * 7 + r * 13) % 9 == 0 then
      local x, y = c * CELL + 1, r * CELL + 4
      gfx.drawLine(x, y, x + 2, y - 1)
      gfx.drawLine(x + 2, y - 1, x + 4, y)
    end
  end
  -- terrain glyphs
  for i = 1, NCELL do
    local t = ter[i]
    local k = reg[i]
    local visible = t ~= SEA and (k == 0 or not R.isl[k] or R.known[k])
    if visible then
      local c, r = (i - 1) % COLS, (i - 1) // COLS
      local x, y = c * CELL, r * CELL
      local j = rng:range(0, 2)
      if t == FOREST then
        if (c + r) % 2 == 0 then
          gfx.fillRect(x + 2 + j, y + 2, 3, 3)
          gfx.drawPixel(x + 3 + j, y + 1)
          gfx.drawLine(x + 3 + j, y + 5, x + 3 + j, y + 6)
        else
          gfx.drawPixel(x + 4, y + 4)
        end
      elseif t == HILL then
        if (c + r) % 2 == 1 then
          gfx.drawLine(x + 1, y + 6, x + 3, y + 4)
          gfx.drawLine(x + 3, y + 4, x + 5, y + 6)
        end
      elseif t == MOUNT then
        gfx.fillTriangle(x + 4, y, x + 8, y + 7, x + 4, y + 7)
        gfx.drawLine(x, y + 7, x + 4, y)
        gfx.drawLine(x, y + 7, x + 4, y + 7)
      elseif (c * 5 + r * 3 + j) % 7 == 0 then
        gfx.drawPixel(x + 3, y + 4)
        gfx.drawPixel(x + 5, y + 3)
      end
    end
  end
  -- coastline
  for i = 1, NCELL do
    local k = reg[i]
    local land = ter[i] ~= SEA and (k == 0 or not R.isl[k] or R.known[k])
    if land then
      local c, r = (i - 1) % COLS, (i - 1) // COLS
      local x, y = c * CELL, r * CELL
      for d = 1, 4 do
        local nc2, nr2 = c, r
        if d == 1 then nc2 = c + 1 elseif d == 2 then nc2 = c - 1 elseif d == 3 then nr2 = r + 1 else nr2 = r - 1 end
        local q = cellIdx(nc2, nr2)
        local qk = reg[q]
        local qland = ter[q] ~= SEA and (qk == 0 or not R.isl[qk] or R.known[qk])
        if not qland then
          gfx.setLineWidth(1)
          if d == 1 then gfx.drawLine(x + CELL - 1, y, x + CELL - 1, y + CELL - 1)
          elseif d == 2 then gfx.drawLine(x, y, x, y + CELL - 1)
          elseif d == 3 then gfx.drawLine(x, y + CELL - 1, x + CELL - 1, y + CELL - 1)
          else gfx.drawLine(x, y, x + CELL - 1, y) end
        end
      end
    end
  end
  -- rivers
  gfx.setColor(gfx.kColorBlack)
  for q = 1, #self.rivers do
    local p = self.rivers[q]
    for s = 1, #p - 1 do
      local a, b = p[s], p[s + 1]
      local ax, ay = ((a - 1) % COLS) * CELL + 4, ((a - 1) // COLS) * CELL + 4
      local bx, by = ((b - 1) % COLS) * CELL + 4, ((b - 1) // COLS) * CELL + 4
      gfx.setLineWidth(s > #p * 0.5 and 2 or 1)
      gfx.drawLine(ax, ay, bx, by)
    end
  end
  gfx.setLineWidth(1)
  -- frame
  gfx.drawRect(0, 0, MW, MH)
  gfx.popContext()
end

-- dotted borders between polities (rebuilt when ownership changes)
function Civ:renderBorders()
  local img = self.borderImg
  local reg, R = self.reg, self.R
  gfx.pushContext(img)
  gfx.clear(gfx.kColorClear)
  gfx.setColor(gfx.kColorBlack)
  for i = 1, NCELL do
    local a = reg[i]
    if a > 0 and R.pop[a] > 0 and R.owner[a] > 0 then
      local c, r = (i - 1) % COLS, (i - 1) // COLS
      local x, y = c * CELL, r * CELL
      if c < COLS - 1 then
        local b = reg[i + 1]
        if b > 0 and b ~= a and R.pop[b] > 0 and R.owner[b] > 0 and R.owner[b] ~= R.owner[a] then
          for yy = 0, CELL - 1, 2 do gfx.fillRect(x + CELL - 1, y + yy, 2, 1) end
        end
      end
      if r < ROWS - 1 then
        local b = reg[i + COLS]
        if b > 0 and b ~= a and R.pop[b] > 0 and R.owner[b] > 0 and R.owner[b] ~= R.owner[a] then
          for xx = 0, CELL - 1, 2 do gfx.fillRect(x + xx, y + CELL - 1, 1, 2) end
        end
      end
    end
  end
  gfx.popContext()
  self.bordersDirty = false
end

------------------------------------------------------------------------
-- civilization state
------------------------------------------------------------------------
function Civ:allocState()
  local R = {}
  for _, key in ipairs({ "cells", "fert", "coast", "riv", "isl", "sx", "sy", "x", "y", "pop", "owner", "dev",
    "sick", "level", "walls", "known", "ruin", "famine", "cap" }) do R[key] = {} end
  for k = 1, MAXR do
    R.pop[k], R.owner[k], R.dev[k], R.sick[k], R.level[k] = 0, 0, 0, 0, 0
    R.walls[k], R.known[k], R.ruin[k], R.famine[k], R.cap[k] = false, false, false, false, 1
    R.x[k], R.y[k] = 0, 0
  end
  self.R = R
  local P = {}
  for _, key in ipairs({ "alive", "gov", "name", "cap", "war", "warT", "front", "stabT" }) do P[key] = {} end
  for p = 1, MAXP do
    P.alive[p], P.gov[p], P.name[p], P.cap[p], P.war[p], P.warT[p], P.front[p], P.stabT[p] = false, 1, "", 0, 0, 0, 0, 0
  end
  self.P = P
  self.adj = {}
  for q = 1, MAXR * MAXR do self.adj[q] = 0 end
  self.T = { 0, 0, 0, 0, 0, 0 }
  self.shipX, self.shipY, self.shipTX, self.shipTY, self.shipOn = {}, {}, {}, {}, {}
  for s = 1, MAXSHIP do self.shipX[s], self.shipY[s], self.shipTX[s], self.shipTY[s], self.shipOn[s] = 0, 0, 0, 0, false end
  self.chron = {}
  for i = 1, 8 do self.chron[i] = "" end
  self.chronN = 0
end

function Civ:newCiv(first)
  local rng = self.rng
  local R, P, T = self.R, self.P, self.T
  self.civName = makeName(rng)
  self.civYear0 = self.year or 0
  self.ageYear0 = self.civYear0
  for p = 1, MAXP do P.alive[p] = false P.war[p] = 0 P.warT[p] = 0 P.front[p] = 0 P.stabT[p] = 0 end
  if first then
    for k = 1, MAXR do
      R.pop[k], R.owner[k], R.dev[k], R.sick[k] = 0, 0, 0, 0
      R.known[k] = not R.isl[k]
      R.ruin[k] = false
      R.walls[k] = false
    end
    for t = 1, 6 do T[t] = 0 end
    self.C, self.F = 0, 10
  else
    -- a new people rises from the ruins: keep a little lore, scattered settlements
    for t = 1, 6 do T[t] = T[t] * 0.35 end
    self.C = self.C * 0.25
    for k = 1, self.NR do
      if R.pop[k] > 0 then R.ruin[k] = true end
      R.pop[k] = math.min(R.pop[k], 1) R.owner[k] = 0 R.dev[k] = 0.3 R.sick[k] = 0 R.walls[k] = false
    end
  end
  -- founding peoples
  local nP = (self.mode == "tutorial") and 2 or (self.difficulty >= 3 and 4 or 3)
  local mainN = self.nMain
  local chosen = 0
  local tries = 0
  while chosen < nP and tries < 200 do
    tries = tries + 1
    local k = rng:range(1, mainN)
    local ok = R.owner[k] == 0 and R.cells[k] > 3
    for p = 1, chosen do if P.cap[p] == k or self:adjacent(k, P.cap[p]) then ok = false end end
    if ok then
      chosen = chosen + 1
      P.alive[chosen] = true
      P.gov[chosen] = TRIBES
      P.name[chosen] = makeName(rng)
      P.cap[chosen] = k
      R.owner[k] = chosen
      R.pop[k] = 3
    end
  end
  self.S = 55
  self.Un = 0
  self.G = 0
  self.K = 0
  self.co2 = 0
  self.dark = 0
  self.coldT = 0
  self.cool = 3
  self.grudge = 0
  self.hands = (self.mode == "tutorial") and 2 or 1
  self.steadyGens = 0
  self.era = 1
  self.famineN = 0
  self.plagueN = 0
  self.bordersDirty = true
  self:updateLevels()
end

function Civ:enter(params)
  self.t = 0
  self.year = 0
  self.gen = 0
  self.wheel = 0
  self.backAcc = 0
  self.falls = 0
  self.yearsBanked = 0
  self.peakPop = 0
  self.statues = 0
  self.eventsDone = 0
  self.handsUsed = 0
  self.steadyT = 0
  self.jitter = 0
  self.rps = 0
  self.wobble = 0
  self.flashHand = 0
  self.tempoPos = 0
  self.eraFlash = 0
  self.drumT = 0
  self.tickerX = 400
  self.tickerI = 0
  self.tickerT = 0
  self.showLog = false
  self.event = nil
  self.eventSel = 1
  self.lockClick = 0
  self.ending = nil
  self.tracker = Crank.Tracker.new(3)
  self.rumble = Audio.Hum.new(Audio.TRIANGLE)
  self.growl = Audio.Hum.new(Audio.SAW)
  self.heavy = self.params.challengeId == "heavy"
  self.plagueMul = (self.params.challengeId == "plague") and 2 or 1
  self.noWar = self.mode == "tutorial"
  self:allocState()
  self.nMain = (self.mode == "tutorial") and 7 or (9 + self.difficulty)
  self.mapSeed = self.rng:range(1, 1000000)
  self:genWorld(self.nMain)
  self.mapImg = gfx.image.new(MW, MH, gfx.kColorWhite)
  self.borderImg = gfx.image.new(MW, MH, gfx.kColorClear)
  self:newCiv(true)
  self:renderMap()
  self:chronicle("The first fires are lit.")
  if self.mode == "tutorial" then self:setupCoach() end
end

function Civ:exit()
  self.rumble:stop()
  self.growl:stop()
end

function Civ:setupCoach()
  local s = self
  self.coach = UI.Coach.new({
    { text = "Turn the crank: the Wheel of History. One full turn is one generation. Turn two.",
      check = function() return s.gen >= 2 end },
    { text = "Watch TEMPO. Hold a steady pace inside the white STEADY band.",
      check = function() return s.steadyT >= 2.5 end },
    { text = "Now crank FAST. Rushed history breeds UNREST.",
      check = function() return s.Un >= 30 end },
    { text = "Crank BACKWARD: friction. Unrest cools, order rises, progress slows.",
      check = function() return s.Un <= 12 and s.backTotal and s.backTotal > 240 end },
    { text = "An event locks the wheel. UP/DOWN to choose, A to decide.",
      enter = function() s:forceEvent("comet") end,
      check = function() return s.eventsDone >= 1 end },
    { text = "B spends a HAND: the steady hand calms the realm. Try it.",
      check = function() return s.handsUsed >= 1 end },
    { text = "Turn steadily for four generations. LORE only grows under a steady hand.",
      enter = function() s.lessonGen = s.gen s.lessonC = s.C end,
      check = function() return s.gen >= (s.lessonGen or 0) + 4 and s.C > (s.lessonC or 0) end },
  }, { x = 4, w = 392, y = 152, h = 46, anchor = "bottom" })
end

------------------------------------------------------------------------
-- chronicle
------------------------------------------------------------------------
function Civ:chronicle(text)
  local line = "Y" .. floor(self.year) .. "  " .. text
  self.chronN = self.chronN + 1
  self.chron[(self.chronN - 1) % 8 + 1] = line
end

function Civ:chronAt(back)
  if back >= math.min(8, self.chronN) then return nil end
  return self.chron[(self.chronN - 1 - back) % 8 + 1]
end

------------------------------------------------------------------------
-- derived quantities
------------------------------------------------------------------------
function Civ:totalPop()
  local s = 0
  for k = 1, self.NR do s = s + self.R.pop[k] end
  return s
end

function Civ:dominant()
  local P, R = self.P, self.R
  local best, bp = 0, -1
  for p = 1, MAXP do
    if P.alive[p] then
      local s = 0
      for k = 1, self.NR do if R.owner[k] == p then s = s + R.pop[k] end end
      if s > bp then best, bp = p, s end
    end
  end
  return best
end

function Civ:aliveCount()
  local n = 0
  for p = 1, MAXP do if self.P.alive[p] then n = n + 1 end end
  return n
end

function Civ:eraFor()
  local T = self.T
  if T[INDUSTRY] >= 60 and T[MEDIC] >= 45 then return 7 end
  if T[INDUSTRY] >= 22 then return 6 end
  if T[SAIL] >= 42 and T[LETTERS] >= 38 then return 5 end
  if T[METAL] >= 34 and T[LETTERS] >= 20 then return 4 end
  if T[METAL] >= 20 then return 3 end
  if T[METAL] >= 8 then return 2 end
  return 1
end

-- tempo band for the current era and government (revs per second)
function Civ:band()
  local e = ERAS[self.era]
  local d = self:dominant()
  local gv = (d > 0) and GOV[self.P.gov[d]] or GOV[WARLORDS]
  local hi = e.hi * gv.pace * (DIFF_PACE[self.difficulty] or 1)
  if self.heavy then hi = hi * 0.78 end
  if self.dark > 0 then hi = hi * 0.9 end
  return e.lo, hi
end

function Civ:updateLevels()
  local R = self.R
  for k = 1, self.NR do
    local p = R.pop[k]
    local lv = 0
    if p >= 500 then lv = R.walls[k] and 5 or 4
    elseif p >= 150 then lv = 4
    elseif p >= 40 then lv = 3
    elseif p >= 8 then lv = 2
    elseif p >= 0.8 then lv = 1 end
    if lv == 4 and R.walls[k] then lv = 5 end
    R.level[k] = lv
  end
end

local function growTech(T, t, rate) T[t] = math.min(100, T[t] + rate * (1 - T[t] / 115)) end

------------------------------------------------------------------------
-- the simulation: one substep = 1/12 generation
------------------------------------------------------------------------
function Civ:substep()
  local R, P, T = self.R, self.P, self.T
  local era = ERAS[self.era]
  local dg = 1 / 12
  local years = era.ypg * dg
  self.year = self.year + years
  local lo, hi = self:band()
  local rps = self.rps
  local steady = 1 - U.clamp(self.jitter * 2.2, 0, 1)
  self.steady = steady
  -- tempo: rushed / steady / stagnant
  local tempoMul
  if rps > hi then
    local rush = math.min(3, rps / hi - 1)
    self.Un = self.Un + 5 * rush * (1 + rush) * dg * 1.0
    tempoMul = 1.35
  elseif rps < lo then
    self.G = math.min(100, self.G + 10 * (1 - rps / lo) * dg)
    tempoMul = 0.45
  else
    tempoMul = 0.65 + 0.7 * (rps - lo) / (hi - lo)
    self.G = math.max(0, self.G - 5 * dg)
  end
  -- jerky hands are felt too
  if steady < 0.5 then self.Un = self.Un + (0.5 - steady) * 3 * dg end

  -- climate: long cycles, cold spells and industrial warming
  self.K = 0.55 * sin(self.year / 1800 * 6.283 + self.mapSeed % 7) + (self.coldT > 0 and -0.8 or 0)
  local warm = self.co2 / 100
  local climate = 1 + 0.12 * self.K - math.max(0, warm - 0.45) * 0.6
  if self.coldT > 0 then self.coldT = self.coldT - dg end

  -- regions
  local total = 0
  local famineN, sickN, cities = 0, 0, 0
  local capMul = (2 + T[AGRI] * 0.5 + T[INDUSTRY] * 1.5) * climate
  for k = 1, self.NR do
    local p = R.pop[k]
    if p > 0 then
      local cap = R.fert[k] * capMul * (1 - 0.5 * R.dev[k])
      if cap < 1 then cap = 1 end
      R.cap[k] = cap
      local g = 0.9 * (1 - R.sick[k])
      p = p + p * g * (1 - p / cap) * dg
      if p > cap then
        p = p - (p - cap) * 0.35 * dg
        R.famine[k] = p > cap * 1.08
      else
        R.famine[k] = false
      end
      if R.famine[k] then famineN = famineN + 1 end
      if R.sick[k] > 0 then
        p = p - p * R.sick[k] * 0.35 * dg
        R.sick[k] = math.max(0, R.sick[k] - (0.12 + T[MEDIC] * 0.012) * dg)
        if R.sick[k] > 0.1 then sickN = sickN + 1 end
      end
      R.dev[k] = math.max(0, R.dev[k] - 0.3 * dg)
      if p < 0.3 then
        p = 0
        R.owner[k] = 0
        self.bordersDirty = true
      end
      R.pop[k] = p
      total = total + p
      if R.level[k] >= 3 then cities = cities + 1 end
    end
  end
  self.famineN, self.sickN, self.cities = famineN, sickN, cities
  self.total = total
  if total > self.peakPop then self.peakPop = total end

  -- culture and faith
  local d = self:dominant()
  local gv = GOV[(d > 0) and P.gov[d] or WARLORDS]
  local tempoGood = (rps >= lo and rps <= hi) and 1 or 0.3
  self.C = self.C + (0.25 + cities * 0.35 + (self.statueBuilt and 0.6 or 0)) * steady * tempoGood * gv.cult * (self.S / 100) * (self.dark > 0 and 0.3 or 1) * dg
  -- order and unrest
  local wars = 0
  for p = 1, MAXP do if P.alive[p] and P.war[p] > 0 then wars = wars + 1 end end
  wars = wars // 2
  local target = gv.stab + math.min(12, sqrt(self.C)) - self.Un * 0.45 - wars * 8 - famineN * 4 - sickN * 3 + self.F * 0.08
  self.S = U.clamp(self.S + (target - self.S) * 0.35 * dg, 0, 100)
  self.Un = self.Un + (famineN * 2.5 + wars * 2 + math.max(0, self:aliveCount() == 1 and self.NR > 8 and 0.8 or 0)) * dg
  if self.grudge > 0 then
    local g = math.min(self.grudge, 4 * dg)
    self.grudge = self.grudge - g
    self.Un = self.Un + g
  end
  -- the pressures of a crowded, ageing world: bolder tempo, more strain;
  -- every civilization grows restless after its third millennium
  local age = self.year - (self.ageYear0 or 0)
  self.Un = self.Un + (0.5 * self.era * (0.4 + 0.8 * math.min(1.5, rps / hi)) + math.max(0, age - 3000) / 450) * dg
  self.Un = U.clamp(self.Un - (self.S / 100) * 6 * dg, 0, 100)

  -- knowledge
  local popF = U.clamp(0.4 + log(1 + total, 10) / 3, 0.4, 2)
  local base = 1.9 * ERA_TECH[self.era] * tempoMul * gv.tech * (1 - self.G / 140) * popF * (self.dark > 0 and 0.35 or 1) * dg
  if self.mode == "tutorial" then base = base * 1.3 end
  local grow = growTech
  grow(T, AGRI, base * 1.0)
  grow(T, METAL, base * 0.95 * (T[AGRI] >= 3 and 1 or 0.3))
  grow(T, SAIL, base * 0.8 * (0.3 + self.coastShare) * (T[METAL] >= 8 and 1 or 0.15))
  grow(T, LETTERS, base * 0.8 * (T[METAL] >= 10 and 1 or 0.1) * (0.7 + math.min(0.8, self.C / 150)))
  grow(T, MEDIC, base * 0.6 * (T[LETTERS] >= 18 and 1 or 0.1))
  grow(T, INDUSTRY, base * 1.1 * ((T[LETTERS] >= 45 and T[METAL] >= 45) and 1 or 0))
  self.co2 = U.clamp(self.co2 + (T[INDUSTRY] * 0.009 - 0.25) * dg, 0, 100)

  -- wars grind on every season
  for p = 1, MAXP do
    if P.alive[p] and P.war[p] > 0 and P.front[p] > 0 then
      local a = P.front[p]
      R.dev[a] = math.min(1, R.dev[a] + 0.12 * dg)
      R.pop[a] = R.pop[a] * (1 - 0.06 * dg)
    end
  end
  if wars > 0 then
    Audio.play(Audio.SINE, 70, 0.35, 0.06, 0.001, 0.08, 0, 0.03)
    Audio.play(Audio.NOISE, 300, 0.1, 0.02, 0.001, 0.03, 0, 0.01)
  end

  -- ships and colonists sail with history
  self:moveShips()

  local eraNow = self:eraFor()
  if eraNow > self.era then
    self.era = eraNow
    self.eraFlash = 3
    Audio.sfx.bell(660, 0.35)
    Audio.sfx.bell(990, 0.3)
    Audio.play(Audio.TRIANGLE, 1320, 0.25, 0.4, 0.002, 0.5, 0, 0.3, 0.2)
    self:chronicle(ERAS[eraNow].say)
  end
  self:updateLevels()
  self:milestones()
end

function Civ:milestones()
  local y = self.year
  if y >= 1000 then self:award("millennium") end
  if y >= STANDARD_END then self:award("survive") end
end

-- called at every generation boundary: politics, wars, events, collapse
function Civ:generation()
  local R, P, T = self.R, self.P, self.T
  local rng = self.rng
  self.gen = self.gen + 1
  Audio.sfx.thunk(0.35)
  -- hands for a steady generation inside the band
  local lo, hi = self:band()
  if (self.steady or 0) > 0.6 and self.rps >= lo and self.rps <= hi then
    self.steadyGens = self.steadyGens + 1
    if self.steadyGens >= 7 and self.hands < 5 then
      self.steadyGens = 0
      self.hands = self.hands + 1
      Audio.sfx.coin()
    end
  end
  -- colonisation of neighbouring land
  for k = 1, self.NR do
    if R.pop[k] <= 0 and R.cells[k] > 0 and (not R.isl[k] or (R.known[k] and T[SAIL] >= 25)) then
      for j = 1, self.NR do
        local reach = self:adjacent(k, j) or (R.isl[k] and R.coast[j] and not R.isl[j])
        if R.pop[j] > 6 and reach and rng:chance(0.45) then
          R.pop[k] = 1.5
          R.owner[k] = R.owner[j]
          R.ruin[k] = false
          self.bordersDirty = true
          if R.isl[k] then self:chronicle("Colonists settle the far island.") end
          break
        end
      end
    end
  end
  -- the first town, the first walls
  if not self.firstTown then
    for k = 1, self.NR do
      if R.level[k] >= 3 then
        self.firstTown = true
        self:chronicle("A town rises in " .. self:regionName(k) .. ". Streets, a market, a gaol.")
        break
      end
    end
  end
  -- walls with metalwork
  for k = 1, self.NR do
    if R.pop[k] > 120 and T[METAL] >= 25 and not R.walls[k] and rng:chance(0.25) then
      R.walls[k] = true
      if not self.firstWalls then self.firstWalls = true self:chronicle("Stone walls go up around " .. self:regionName(k) .. ".") end
    end
  end
  -- governments evolve
  local nAlive = self:aliveCount()
  local settled = 0
  for k = 1, self.NR do if R.pop[k] > 0 then settled = settled + 1 end end
  for p = 1, MAXP do
    if P.alive[p] then
      local owned, pop = 0, 0
      for k = 1, self.NR do if R.owner[k] == p then owned = owned + 1 pop = pop + R.pop[k] end end
      if owned == 0 then
        P.alive[p] = false
        P.war[p] = 0
      else
        local gv = P.gov[p]
        if gv == TRIBES and pop > 25 then
          P.gov[p] = CHIEFDOM
          self:chronicle("The tribes of " .. P.name[p] .. " follow a chief.")
        elseif gv == CHIEFDOM and T[METAL] >= 18 then
          P.gov[p] = KINGDOM
          self:chronicle(P.name[p] .. " crowns its first king.")
        elseif gv == KINGDOM and owned >= math.max(4, settled * 0.7) then
          P.gov[p] = EMPIRE
          self:chronicle("The " .. GOV_PREFIX[EMPIRE] .. P.name[p] .. " is proclaimed.")
        elseif gv == WARLORDS then
          if self.S > 50 then P.stabT[p] = P.stabT[p] + 1 else P.stabT[p] = 0 end
          if P.stabT[p] >= 3 then P.gov[p] = (T[METAL] >= 18) and KINGDOM or CHIEFDOM end
        end
        -- capital lost? move it
        if R.owner[P.cap[p]] ~= p then
          for k = 1, self.NR do if R.owner[k] == p then P.cap[p] = k break end end
        end
      end
    end
  end
  -- wars
  if not self.noWar and T[METAL] >= 6 then self:politics() end
  -- disease outbreaks
  local density = self.total / math.max(1, settled * 40)
  local pPlague = (0.03 + 0.05 * math.min(2, density) + T[SAIL] * 0.0012 - T[MEDIC] * 0.0006) * self.plagueMul
  if self.mode == "tutorial" then pPlague = 0 end
  if rng:chance(math.max(0.005, pPlague)) then self:outbreak() end
  -- spread along neighbours
  for k = 1, self.NR do
    if R.sick[k] > 0.25 then
      for j = 1, self.NR do
        if R.pop[j] > 0 and R.sick[j] < 0.1 and self:adjacent(k, j) and rng:chance(0.3 * (1 - T[MEDIC] / 120)) then R.sick[j] = R.sick[k] * 0.7 end
      end
    end
  end
  -- ships
  local want = math.min(MAXSHIP, floor(T[SAIL] / 18))
  for s = 1, MAXSHIP do
    if s <= want and not self.shipOn[s] and #self.coastSea > 0 then
      local i = self.coastSea[rng:range(1, #self.coastSea)]
      self.shipX[s] = MX + ((i - 1) % COLS) * CELL + 4
      self.shipY[s] = MY + ((i - 1) // COLS) * CELL + 4
      self:shipTarget(s)
      self.shipOn[s] = true
    elseif s > want then
      self.shipOn[s] = false
    end
  end
  -- dark age
  if self.dark > 0 then
    self.dark = self.dark - 1
    if self.dark <= 0 then
      if self.S >= 40 then
        self:chronicle("The long night ends. Lamps are lit again.")
        self:award("phoenix")
        Audio.sfx.success()
      else
        self.dark = 2
      end
    end
  end
  self:checkCollapse()
  if self.finished or self.event then return end
  -- events
  self.cool = self.cool - 1
  if self.cool <= 0 and self.mode ~= "tutorial" then self:maybeEvent() end
end

function Civ:politics()
  local R, P, T = self.R, self.P, self.T
  local rng = self.rng
  for p = 1, MAXP do
    if P.alive[p] and P.war[p] == 0 then
      for q = p + 1, MAXP do
        if P.alive[q] and P.war[q] == 0 and P.war[p] == 0 then
          -- do they share a border?
          local front = 0
          for a = 1, self.NR do
            if R.owner[a] == p then
              for b = 1, self.NR do
                if R.owner[b] == q and self:adjacent(a, b) then front = b break end
              end
            end
            if front > 0 then break end
          end
          local aggr = math.max(GOV[P.gov[p]].aggr, GOV[P.gov[q]].aggr)
          if front > 0 and rng:chance(0.07 * aggr * (1 + self.Un / 70) * (self.dark > 0 and 1.5 or 1)) then
            P.war[p], P.war[q] = q, p
            P.warT[p], P.warT[q] = 0, 0
            self:chronicle(P.name[p] .. " marches on " .. P.name[q] .. ".")
            Audio.sfx.horn(0.6, 0.35)
            if self.hands >= 1 and rng:chance(0.45) and not self.event then
              self:forceEvent("war", p, q)
            end
          end
        end
      end
    end
  end
  -- fighting
  for p = 1, MAXP do
    local q = P.war[p]
    if P.alive[p] and q > 0 and q > p and P.alive[q] then
      P.warT[p] = P.warT[p] + 1
      -- find the front: a pair of adjacent regions
      local fa, fb = 0, 0
      for a = 1, self.NR do
        if R.owner[a] == p then
          for b = 1, self.NR do
            if R.owner[b] == q and self:adjacent(a, b) and rng:chance(0.6) then fa, fb = a, b break end
          end
        end
        if fa > 0 then break end
      end
      if fa == 0 then
        P.war[p], P.war[q] = 0, 0
      else
        P.front[p], P.front[q] = fb, fa
        local sp, sq = 0, 0
        for k = 1, self.NR do
          if R.owner[k] == p then sp = sp + R.pop[k] elseif R.owner[k] == q then sq = sq + R.pop[k] end
        end
        sp = sp * (0.7 + rng:float() * 0.6) * (1 + (P.gov[p] == EMPIRE and 0.2 or 0))
        sq = sq * (0.7 + rng:float() * 0.6) * (1 + (P.gov[q] == EMPIRE and 0.2 or 0))
        local win = sp / (sp + sq + 0.001)
        if rng:chance(0.35) then
          if rng:chance(win) then self:conquer(p, q, fb) else self:conquer(q, p, fa) end
        end
        if P.alive[p] and P.alive[q] and rng:chance(0.12 * P.warT[p]) then
          P.war[p], P.war[q] = 0, 0
          P.front[p], P.front[q] = 0, 0
          self:chronicle("Peace between " .. P.name[p] .. " and " .. P.name[q] .. ".")
        end
      end
    end
  end
end

function Civ:conquer(winner, loser, k)
  local R, P = self.R, self.P
  local wasCap = P.cap[loser] == k
  R.owner[k] = winner
  R.dev[k] = math.min(1, R.dev[k] + 0.3)
  R.pop[k] = R.pop[k] * 0.8
  self.bordersDirty = true
  Audio.sfx.clank(0.4)
  if wasCap then
    for j = 1, self.NR do if R.owner[j] == loser then R.owner[j] = winner end end
    P.alive[loser] = false
    P.war[loser] = 0
    P.war[winner] = 0
    P.front[winner], P.front[loser] = 0, 0
    self:chronicle(P.name[loser] .. " falls to " .. P.name[winner] .. ".")
    self:shake(2)
  end
end

function Civ:outbreak()
  local R = self.R
  local best, bp = 0, 0
  for k = 1, self.NR do
    local w = R.pop[k] * (R.coast[k] and 1.5 or 1) * (0.5 + self.rng:float())
    if w > bp then best, bp = k, w end
  end
  if best == 0 then return end
  R.sick[best] = math.max(R.sick[best], 0.55 + self.rng:float() * 0.3)
  self.plagueRegion = best
  self:chronicle("Plague in the settlement of " .. self:regionName(best) .. ".")
  Audio.play(Audio.SINE, 147, 0.3, 0.6, 0.02, 0.6, 0, 0.3)
  Audio.play(Audio.SINE, 139, 0.25, 0.6, 0.02, 0.6, 0, 0.3, 0.3)
  if not self.event and self.cool <= 1 then self:forceEvent("plague") end
end

function Civ:regionName(k)
  local o = self.R.owner[k]
  if o > 0 then return self.P.name[o] end
  return "the wilds"
end

function Civ:checkCollapse()
  local R, P, T = self.R, self.P, self.T
  local total = self.total or self:totalPop()
  local risk = math.max(0, (self.Un - 55) / 45) * math.max(0, (62 - self.S) / 62) + math.max(0, self.co2 - 85) * 0.004
  if self.famineN >= 3 then risk = risk + 0.06 end
  self.risk = risk
  local collapse = self.rng:chance(risk * 0.6) or (self.Un >= 96 and self.S <= 18)
  if total < 2 and self.gen > 3 then collapse = true end
  if self.peakPop > 200 and total < self.peakPop * 0.25 then collapse = true end
  if not collapse or self.mode == "tutorial" then return end
  if self.dark > 0 or total < 2 then
    self:fall()
    return
  end
  -- COLLAPSE: a dark age
  self.collapses = (self.collapses or 0) + 1
  self.ageYear0 = self.year
  self.dark = 5 + self.rng:range(0, 3)
  for t = 1, 6 do T[t] = T[t] * 0.62 end
  T[LETTERS] = T[LETTERS] * 0.8
  self.era = self:eraFor()
  for k = 1, self.NR do
    if R.pop[k] > 0 then
      R.pop[k] = R.pop[k] * 0.5
      if R.walls[k] then R.walls[k] = false R.ruin[k] = true end
      R.dev[k] = math.min(1, R.dev[k] + 0.4)
    end
  end
  self:fragment()
  self.S = 35
  self.Un = 25
  self.G = 0
  self.C = self.C * 0.85
  self.co2 = self.co2 * 0.6
  self.peakPopCiv = 0
  self:chronicle("COLLAPSE. The cities burn; a dark age falls.")
  Audio.sfx.thud(1)
  Audio.sfx.fail()
  self:shake(6)
  self:flash(3)
  self.cool = 1
end

-- warlords carve up the land
function Civ:fragment()
  local R, P = self.R, self.P
  local rng = self.rng
  for p = 1, MAXP do P.alive[p] = false P.war[p] = 0 P.front[p] = 0 end
  local settled = {}
  for k = 1, self.NR do if R.pop[k] > 0 then settled[#settled + 1] = k end end
  local n = math.min(5, math.max(1, #settled // 2))
  rng:shuffle(settled)
  for p = 1, n do
    P.alive[p] = true
    P.gov[p] = WARLORDS
    P.cap[p] = settled[p]
    P.name[p] = makeName(rng)
    P.stabT[p] = 0
  end
  for q = 1, #settled do
    local k = settled[q]
    local best, bd = 1, 1e9
    for p = 1, n do
      local c = P.cap[p]
      local d = (R.x[k] - R.x[c]) ^ 2 + (R.y[k] - R.y[c]) ^ 2
      if d < bd then best, bd = p, d end
    end
    R.owner[k] = best
  end
  self.bordersDirty = true
end

function Civ:fall()
  self.falls = self.falls + 1
  self:statAdd("falls", 1)
  local civYears = floor(self.year - (self.civYear0 or 0))
  self:chronicle("The " .. self.civName .. " are gone. Grass on the roads.")
  Audio.sfx.thud(1)
  Audio.sfx.fail()
  self:shake(8)
  self:flash(4)
  self.yearsBanked = self.yearsBanked + civYears
  if self.mode == "endless" and self.falls < 3 then
    self.fallT = 3
    local old = self.civName
    self:newCiv(false)
    self:chronicle("From the ruins of the " .. old .. " rise the " .. self.civName .. ".")
    self.bordersDirty = true
    return
  end
  self:endRun(false)
end

------------------------------------------------------------------------
-- ships
------------------------------------------------------------------------
function Civ:shipTarget(s)
  local R = self.R
  local rng = self.rng
  -- explorers head for unknown islands once sails are good enough
  if self.T[SAIL] >= 30 and rng:chance(0.3) then
    for k = 1, self.NR do
      if R.isl[k] and not R.known[k] then
        self.shipTX[s], self.shipTY[s] = R.x[k], R.y[k]
        return
      end
    end
  end
  local i = self.coastSea[rng:range(1, #self.coastSea)]
  self.shipTX[s] = MX + ((i - 1) % COLS) * CELL + 4
  self.shipTY[s] = MY + ((i - 1) // COLS) * CELL + 4
end

function Civ:moveShips()
  local R = self.R
  for s = 1, MAXSHIP do
    if self.shipOn[s] then
      local dx, dy = self.shipTX[s] - self.shipX[s], self.shipTY[s] - self.shipY[s]
      local d = sqrt(dx * dx + dy * dy)
      local step = 3 + self.T[SAIL] * 0.04
      if d <= step then
        self.shipX[s], self.shipY[s] = self.shipTX[s], self.shipTY[s]
        -- landfall on an unknown island?
        for k = 1, self.NR do
          if R.isl[k] and not R.known[k] and abs(R.x[k] - self.shipX[s]) < 6 and abs(R.y[k] - self.shipY[s]) < 6 then
            self:discover(k)
          end
        end
        self:shipTarget(s)
      else
        self.shipX[s] = self.shipX[s] + dx / d * step
        self.shipY[s] = self.shipY[s] + dy / d * step
      end
    end
  end
end

function Civ:discover(k)
  local R = self.R
  if R.known[k] then return end
  R.known[k] = true
  self:renderMap()
  self:chronicle("Sailors return: there is land beyond the fog!")
  self:award("newlands")
  Audio.sfx.gear()
  self.T[SAIL] = math.min(100, self.T[SAIL] + 3)
end

------------------------------------------------------------------------
-- events: the wheel locks until the hand intervenes
------------------------------------------------------------------------
local function capName(self) local d = self:dominant() return d > 0 and self.P.name[d] or "the ruins" end
local function addAll(self, t, v) for i = 1, 6 do self.T[i] = U.clamp(self.T[i] + v, 0, 100) end end
local function popMul(self, m, onlyRiver, onlyCoast)
  local R = self.R
  for k = 1, self.NR do
    if R.pop[k] > 0 and (not onlyRiver or R.riv[k]) and (not onlyCoast or R.coast[k]) then R.pop[k] = R.pop[k] * m end
  end
end
local function setGov(self, g)
  local d = self:dominant()
  if d > 0 then self.P.gov[d] = g end
end

local EVENTS = {
  flood = { title = "THE RIVER RISES", weight = 1.0,
    cond = function(s) for k = 1, s.NR do if s.R.riv[k] and s.R.pop[k] > 5 then return true end end return false end,
    text = function(s) return "The great river breaks its banks and drowns the fields of " .. capName(s) .. "." end,
    opts = {
      { "Raise levees", "+harvests later, -order now", function(s) s.T[AGRI] = math.min(100, s.T[AGRI] + 5) s.S = s.S - 6 end },
      { "Move the capital", "+safety, -order, -lore", function(s) s.S = s.S - 10 s.Un = s.Un - 6 s.C = s.C * 0.95 end },
      { "Pray to the river", "+faith, but the river decides", function(s) s.F = s.F + 12 if s.rng:chance(0.5) then popMul(s, 0.8, true) s:chronicle("The river takes its due.") end end },
    } },
  plague = { title = "PLAGUE", weight = 0,
    text = function(s) return "A sickness comes ashore in " .. s:regionName(s.plagueRegion or 1) .. ". The healers are afraid." end,
    opts = {
      { "Close the ports", "+contains it, -sails, +unrest", function(s)
        for k = 1, s.NR do if k ~= s.plagueRegion then s.R.sick[k] = s.R.sick[k] * 0.3 end end
        s.T[SAIL] = math.max(0, s.T[SAIL] - 3) s.Un = s.Un + 6 end },
      { "Pray at the temples", "+faith, more will die", function(s) s.F = s.F + 12 local k = s.plagueRegion or 1 s.R.sick[k] = math.min(1, s.R.sick[k] * 1.3) end },
      { "Burn the quarter", "costs a HAND: it ends", function(s) for k = 1, s.NR do s.R.sick[k] = 0 end s.S = s.S - 5 end, 1 },
    } },
  revolt = { title = "THE SQUARES FILL", weight = 0,
    cond = function(s) return s.Un >= 62 end,
    text = function(s) return "Crowds fill the squares of " .. capName(s) .. ". They say history is moving too fast." end,
    opts = {
      { "Grant a charter", "a REPUBLIC: calmer, bolder", function(s) setGov(s, REPUBLIC) s.Un = s.Un - 30 s.S = s.S - 8 s:chronicle("A charter is signed. A republic is born.") end },
      { "Send the soldiers", "quiet now, resentment later", function(s) s.Un = s.Un - 22 s.S = s.S + 6 s.grudge = s.grudge + 28 end },
      { "A new dynasty", "-order, -unrest, +lore", function(s) s.Un = s.Un - 18 s.S = s.S - 12 s.C = s.C + 4 end },
    } },
  famine = { title = "EMPTY GRANARIES", weight = 1.2,
    cond = function(s) return s.famineN >= 1 end,
    text = function(s) return "The granaries of " .. capName(s) .. " are empty and the winter is long." end,
    opts = {
      { "Open the royal stores", "+order, -lore", function(s) s.S = s.S + 6 s.Un = s.Un - 10 s.C = s.C * 0.93 end },
      { "Ration and endure", "+unrest, fewer mouths", function(s) s.Un = s.Un + 10 popMul(s, 0.92) end },
      { "Seek new lands", "+sails, emigrants leave", function(s) s.T[SAIL] = math.min(100, s.T[SAIL] + 6) popMul(s, 0.95) end },
    } },
  printing = { title = "MOVEABLE TYPE", weight = 0,
    text = function(s) return "A printer in " .. capName(s) .. " sets moveable type. Pamphlets are everywhere." end,
    opts = {
      { "Let it spread", "+letters, +lore, +unrest", function(s) s.T[LETTERS] = math.min(100, s.T[LETTERS] + 10) s.C = s.C + 6 s.Un = s.Un + 10 end },
      { "License the presses", "+order, slower ideas", function(s) s.T[LETTERS] = math.min(100, s.T[LETTERS] + 3) s.S = s.S + 6 end },
    } },
  steam = { title = "THE ENGINE", weight = 0,
    text = function(s) return "Engineers in " .. capName(s) .. " harness steam. The mills want coal." end,
    opts = {
      { "Build the mills", "+industry, +smoke, +unrest", function(s) s.T[INDUSTRY] = math.min(100, s.T[INDUSTRY] + 8) s.co2 = s.co2 + 8 s.Un = s.Un + 8 end },
      { "Ban the engines", "+order, stagnation", function(s) s.S = s.S + 6 s.G = math.min(100, s.G + 18) end },
    } },
  voyage = { title = "LAND BEYOND THE FOG", weight = 1.0,
    cond = function(s)
      if s.T[SAIL] < 26 then return false end
      for k = 1, s.NR do if s.R.isl[k] and not s.R.known[k] then return true end end
      return false
    end,
    text = function(s) return "Old sailors in " .. capName(s) .. " swear there is land beyond the fog bank." end,
    opts = {
      { "Fund the voyage", "discovery, some sailors lost", function(s)
        for k = 1, s.NR do if s.R.isl[k] and not s.R.known[k] then s:discover(k) break end end
        popMul(s, 0.98, false, true) end },
      { "Stay home", "+order, stagnation", function(s) s.S = s.S + 3 s.G = math.min(100, s.G + 6) end },
    } },
  statue = { title = "A GREAT WORK", weight = 1.4,
    cond = function(s) return not s.statueBuilt and s.C >= 18 and s.era >= 2 end,
    text = function() return "The guilds propose a great work: a statue of the hand that turns the world." end,
    opts = {
      { "Raise the statue", "+lore, +faith, hungry years", function(s)
        s.statueBuilt = true
        local d = s:dominant()
        s.statueRegion = d > 0 and s.P.cap[d] or 1
        s.C = s.C + 15 s.F = s.F + 10 popMul(s, 0.92)
        s.statues = s.statues + 1
        s:statAdd("statues", 1)
        s:award("statue")
        s:chronicle("They built a statue of the hand. Not of a king. Of the hand.")
      end },
      { "Build granaries", "+agriculture", function(s) s.T[AGRI] = math.min(100, s.T[AGRI] + 6) end },
    } },
  schism = { title = "SCHISM", weight = 0.8,
    cond = function(s) return s.F >= 35 end,
    text = function() return "Two prophets preach two different hands. Families split down the middle." end,
    opts = {
      { "Tolerate both", "+lore, -order", function(s) s.C = s.C + 6 s.S = s.S - 7 end },
      { "Suppress the heresy", "+order, -lore, +unrest", function(s) s.S = s.S + 7 s.C = s.C * 0.92 s.Un = s.Un + 6 end },
      { "Found a theocracy", "a HOLY state: slow, stable", function(s) setGov(s, THEOCRACY) s.F = s.F + 15 s.T[LETTERS] = math.max(0, s.T[LETTERS] - 4) end },
    } },
  raiders = { title = "RAIDERS", weight = 1.0,
    cond = function(s) return s.G >= 35 or s.era <= 3 end,
    text = function(s) return "Longships out of the grey sea burn the coast of " .. capName(s) .. "." end,
    opts = {
      { "Pay tribute", "-lore, peace", function(s) s.C = s.C * 0.93 s.S = s.S + 2 end },
      { "Raise walls", "+metals, -people", function(s)
        s.T[METAL] = math.min(100, s.T[METAL] + 3)
        for k = 1, s.NR do if s.R.coast[k] and s.R.pop[k] > 60 then s.R.walls[k] = true end end
        popMul(s, 0.97) end },
      { "Fight on the beaches", "glory, or ruin", function(s)
        if s.rng:chance(0.55) then s.S = s.S + 9 s.C = s.C + 3 s:chronicle("The raiders are thrown back into the sea.")
        else popMul(s, 0.88, false, true) s.S = s.S - 6 s:chronicle("The coast burns for a season.") end end },
    } },
  succession = { title = "NO HEIR", weight = 1.0,
    cond = function(s) local d = s:dominant() return d > 0 and (s.P.gov[d] == KINGDOM or s.P.gov[d] == EMPIRE) end,
    text = function(s) return "The monarch of " .. capName(s) .. " dies without an heir." end,
    opts = {
      { "Crown the child", "-order, +unrest", function(s) s.S = s.S - 5 s.Un = s.Un + 5 end },
      { "Crown the general", "an EMPIRE: order, war", function(s) setGov(s, EMPIRE) s.S = s.S + 6 end },
      { "Let the lords decide", "civil war, less unrest", function(s) s:split() s.Un = s.Un - 12 end },
    } },
  comet = { title = "A COMET", weight = 0.7,
    text = function() return "A comet hangs over the harbour for forty nights. Everyone is looking up." end,
    opts = {
      { "Read it as an omen", "+faith, -unrest", function(s) s.F = s.F + 12 s.Un = s.Un - 8 end },
      { "Measure its path", "+letters, -faith", function(s) s.T[LETTERS] = math.min(100, s.T[LETTERS] + 5) s.F = math.max(0, s.F - 6) end },
    } },
  trade = { title = "MERCHANTS", weight = 1.0,
    cond = function(s) return s.T[SAIL] >= 18 end,
    text = function() return "Foreign merchants ask for a harbour. Their ships smell of spice and fever." end,
    opts = {
      { "Open the port", "+all knowledge, sickness?", function(s) addAll(s, nil, 2.5) if s.rng:chance(0.35) then s:outbreak() end end },
      { "Turn them away", "+order, stagnation", function(s) s.S = s.S + 3 s.G = math.min(100, s.G + 8) end },
    } },
  war = { title = "WAR", weight = 0,
    text = function(s) return s.warText or "Armies march." end,
    opts = {
      { "Let it be", "the stronger will win", function() end },
      { "Broker peace", "costs a HAND: +lore", function(s)
        for p = 1, MAXP do s.P.war[p] = 0 s.P.front[p] = 0 end
        s.C = s.C + 3 s:chronicle("A treaty is signed under the statue's shadow.") end, 1 },
    } },
  ruins = { title = "THE LONG NIGHT", weight = 2.0,
    cond = function(s) return s.dark > 0 end,
    text = function() return "Survivors gather in the ruins. Someone has kept the old books dry." end,
    opts = {
      { "Rebuild the old city", "+order, shorter night", function(s) s.S = s.S + 10 s.dark = math.max(1, s.dark - 2) end },
      { "Start anew elsewhere", "-unrest, fresh ideas, -lore", function(s) s.Un = s.Un - 10 s.G = 0 s.C = s.C * 0.9 addAll(s, nil, 1.5) end },
    } },
  smoke = { title = "BROWN SKY", weight = 1.2,
    cond = function(s) return s.T[INDUSTRY] >= 30 and s.co2 >= 30 end,
    text = function() return "The sky over the mills turns brown. The harbour no longer freezes." end,
    opts = {
      { "More chimneys", "+industry, +heat", function(s) s.T[INDUSTRY] = math.min(100, s.T[INDUSTRY] + 6) s.co2 = s.co2 + 12 end },
      { "Bank the fires", "-industry, cooler, +unrest", function(s) s.T[INDUSTRY] = math.max(0, s.T[INDUSTRY] - 3) s.co2 = math.max(0, s.co2 - 15) s.Un = s.Un + 6 end },
    } },
  cold = { title = "THE LITTLE ICE", weight = 0.7,
    cond = function(s) return s.era >= 3 and s.coldT <= 0 end,
    text = function() return "The harbour freezes in summer. Frost in the vineyards in June." end,
    opts = {
      { "Plant hardier grain", "+agriculture, -people", function(s) s.coldT = 3 s.T[AGRI] = math.min(100, s.T[AGRI] + 4) popMul(s, 0.95) end },
      { "Move to the south", "-order, less famine", function(s) s.coldT = 2 s.S = s.S - 6 end },
    } },
}
local EVENT_ORDER <const> = { "flood", "revolt", "famine", "voyage", "statue", "schism", "raiders", "succession", "comet", "trade", "ruins", "smoke", "cold" }
local EVENT_W = {}

function Civ:maybeEvent()
  local rng = self.rng
  -- milestone inventions fire once
  if not self.printed and self.T[LETTERS] >= 50 then self.printed = true self:forceEvent("printing") return end
  if not self.steamed and self.T[INDUSTRY] >= 4 then self.steamed = true self:forceEvent("steam") return end
  if self.Un >= 62 and rng:chance(0.7) then self:forceEvent("revolt") return end
  if not rng:chance(0.32) then return end
  for i = 1, #EVENT_ORDER do
    local ev = EVENTS[EVENT_ORDER[i]]
    EVENT_W[i] = (ev.cond == nil or ev.cond(self)) and ev.weight or 0
  end
  local total = 0
  for i = 1, #EVENT_ORDER do total = total + EVENT_W[i] end
  if total <= 0 then return end
  self:forceEvent(EVENT_ORDER[rng:weighted(EVENT_W)])
end

function Civ:forceEvent(id, p, q)
  local ev = EVENTS[id]
  if not ev or self.event then return end
  if id == "war" then self.warText = self.P.name[p] .. " marches on " .. self.P.name[q] .. ". Drums on the border roads." end
  self.event = ev
  self.eventId = id
  self.eventBody = ev.text(self)
  self.eventSel = 1
  self.eventT = 0
  self.lockClick = 0
  Audio.sfx.clank(0.5)
  Audio.sfx.thunk(0.5)
  self:shake(2)
end

function Civ:optEnabled(o) return (o[4] or 0) <= self.hands end

function Civ:decide()
  local ev = self.event
  local o = ev.opts[self.eventSel]
  if not self:optEnabled(o) then Audio.sfx.denied() return end
  if (o[4] or 0) > 0 then self.hands = self.hands - o[4] self.handsUsed = self.handsUsed + 1 self.flashHand = 1 end
  o[3](self)
  self.S = U.clamp(self.S, 0, 100)
  self.Un = U.clamp(self.Un, 0, 100)
  self.F = U.clamp(self.F, 0, 100)
  self:chronicle(ev.title .. ": " .. o[1] .. ".")
  self.event = nil
  self.eventsDone = self.eventsDone + 1
  self.cool = 3 + self.rng:range(0, 3)
  self.bordersDirty = true
  Audio.sfx.menuSelect()
  Audio.sfx.bell(440, 0.2)
  self:updateLevels()
end

-- civil war: split the dominant polity
function Civ:split()
  local R, P = self.R, self.P
  local d = self:dominant()
  if d == 0 then return end
  local slot = 0
  for p = 1, MAXP do if not P.alive[p] then slot = p break end end
  if slot == 0 then return end
  local cap = P.cap[d]
  local moved = 0
  local far, fd = 0, -1
  for k = 1, self.NR do
    if R.owner[k] == d and k ~= cap then
      local dd = (R.x[k] - R.x[cap]) ^ 2 + (R.y[k] - R.y[cap]) ^ 2
      if dd > fd then far, fd = k, dd end
    end
  end
  if far == 0 then return end
  for k = 1, self.NR do
    if R.owner[k] == d and k ~= cap then
      local da = (R.x[k] - R.x[cap]) ^ 2 + (R.y[k] - R.y[cap]) ^ 2
      local db = (R.x[k] - R.x[far]) ^ 2 + (R.y[k] - R.y[far]) ^ 2
      if db < da then R.owner[k] = slot moved = moved + 1 end
    end
  end
  P.alive[slot] = true
  P.gov[slot] = KINGDOM
  P.name[slot] = makeName(self.rng)
  P.cap[slot] = far
  P.war[slot], P.war[d] = d, slot
  P.warT[slot], P.warT[d] = 0, 0
  P.stabT[slot] = 0
  self:chronicle("Civil war: " .. P.name[slot] .. " breaks away.")
  self.bordersDirty = true
end

------------------------------------------------------------------------
-- input
------------------------------------------------------------------------
function Civ:cranked(change)
  if self.ending then return end
  self.tracker:feed(change)
  if self.event then
    -- the pawl holds the wheel: it rocks and clicks but will not turn
    self.wobble = U.clamp(self.wobble + change * 0.15, -6, 6)
    self.lockClick = self.lockClick + abs(change)
    if self.lockClick > 25 then
      self.lockClick = 0
      Audio.sfx.click(0.3)
      Audio.play(Audio.SQUARE, 220, 0.12, 0.015, 0.001, 0.02, 0, 0.01)
    end
    return
  end
  if change > 0 then
    local before = self.wheel
    self.wheel = self.wheel + change
    local steps = floor(self.wheel / SUBDEG) - floor(before / SUBDEG)
    if steps > MAX_SUBSTEPS then
      -- the wheel slips: history can only be pushed so hard
      steps = MAX_SUBSTEPS
      self.Un = math.min(100, self.Un + 0.5)
    end
    for _ = 1, steps do
      Audio.sfx.tick(260 + self.era * 30, 0.1)
      self:substep()
      self.subCount = (self.subCount or 0) + 1
      if self.subCount >= 12 then
        self.subCount = 0
        self:generation()
      end
      if self.event or self.finished or self.ending then break end
    end
    if self.wheel > 3600 then self.wheel = self.wheel - 3600 end
  elseif change < 0 then
    -- friction: conservatism
    local before = self.backAcc
    self.backAcc = self.backAcc - change
    self.backTotal = (self.backTotal or 0) - change
    local notches = floor(self.backAcc / SUBDEG) - floor(before / SUBDEG)
    for _ = 1, math.min(4, notches) do
      self.S = math.min(100, self.S + 0.9)
      self.Un = math.max(0, self.Un - 1.6)
      self.G = math.min(100, self.G + 0.35)
      for t = 1, 6 do self.T[t] = math.max(0, self.T[t] * 0.998 - 0.02) end
      Audio.play(Audio.SAW, 55, 0.2, 0.08, 0.005, 0.08, 0, 0.04)
      Audio.sfx.creak(0.08)
    end
    if self.backAcc > 3600 then self.backAcc = self.backAcc - 3600 end
  end
end

function Civ:buttonDown(b)
  if self.ending then return end
  if self.event then
    local n = #self.event.opts
    if b == Input.UP then self.eventSel = (self.eventSel - 2) % n + 1 Audio.sfx.menuMove()
    elseif b == Input.DOWN then self.eventSel = self.eventSel % n + 1 Audio.sfx.menuMove()
    elseif b == Input.A and self.eventT > 0.4 then self:decide() end
    return
  end
  if b == Input.A then
    self.showLog = not self.showLog
    Audio.sfx.menuMove()
  elseif b == Input.B then
    if self.hands >= 1 then
      self.hands = self.hands - 1
      self.handsUsed = self.handsUsed + 1
      self.Un = math.max(0, self.Un - 25)
      self.S = math.min(100, self.S + 6)
      self.flashHand = 1
      Audio.sfx.bell(330, 0.4)
      Audio.play(Audio.SINE, 165, 0.3, 0.8, 0.05, 0.6, 0, 0.3)
      self:chronicle("A steady hand is felt. The crowds go home.")
    else
      Audio.sfx.denied()
    end
  end
end

------------------------------------------------------------------------
-- update
------------------------------------------------------------------------
function Civ:endRun(success)
  if self.ending then return end
  local years = floor(self.yearsBanked + (success and (self.year - (self.civYear0 or 0)) or 0))
  local peak = floor(self.peakPop)
  local score = years + floor(peak / 50) + floor(self.C * 4)
  self.ending = true
  self:statMax("years", years)
  self:statMax("peakpop", peak)
  self.rumble:set(0, 0)
  self.growl:set(0, 0)
  local title
  if success then title = self.mode == "endless" and "THE WHEEL RESTS" or "5000 YEARS"
  else title = "CIVILIZATION FALLS" end
  if success then Audio.sfx.success() end
  self:finish({ success = success or years >= 1000, score = score, title = title, delay = 2.5,
    lines = { "Years of history: " .. U.commas(years), "Peak population: " .. popText(peak),
      "Culture: " .. floor(self.C) .. " x4", self.statueBuilt and "They built a statue of the hand." or "No statue was raised.",
      "Falls: " .. self.falls } })
end

function Civ:update(dt)
  self.t = self.t + dt
  self.tracker:update(dt)
  -- smoothed tempo and steadiness
  local v = self.tracker.vel
  local raw = self.tracker.rawVel
  self.rps = math.max(0, v / 360)
  local dev = abs(raw - v) / math.max(90, abs(v))
  if self.tracker.idle > 0.4 then dev = 0 end
  self.jitter = U.damp(self.jitter, dev, 1.5, dt)
  local lo, hi = self:band()
  if self.rps >= lo and self.rps <= hi and not self.event then self.steadyT = self.steadyT + dt else self.steadyT = 0 end
  local pos = U.clamp(self.rps / (hi * 1.6), 0, 1)
  self.tempoPos = U.damp(self.tempoPos, pos, 8, dt)
  self.wobble = U.damp(self.wobble, 0, 10, dt)
  self.flashHand = math.max(0, self.flashHand - dt * 0.6)
  self.eraFlash = math.max(0, self.eraFlash - dt)
  if self.event then self.eventT = self.eventT + dt end
  if self.fallT then self.fallT = self.fallT - dt if self.fallT <= 0 then self.fallT = nil end end

  -- the low rumble of the wheel, and a growl when history is rushed
  if self.ending or self.finished then
    self.rumble:set(0, 0)
    self.growl:set(0, 0)
  else
    local sp = math.min(2, self.rps)
    self.rumble:set(36 + sp * 22, math.min(0.3, sp * 0.22))
    if self.rps > hi then self.growl:set(48 + (self.rps - hi) * 30, math.min(0.18, (self.rps / hi - 1) * 0.2)) else self.growl:set(0, 0) end
  end

  -- chronicle ticker: newest entry slides in and rests
  if self.chronN ~= self.tickerI then
    self.tickerI = self.chronN
    self.tickerX = 400
    self.tickerW = UI.width(self:chronAt(0) or "")
    self.tickerHold = 1.8
  end
  if self.tickerX > 6 then
    self.tickerX = U.approach(self.tickerX, 6, dt * 900)
  elseif self.tickerW and self.tickerW > 388 then
    -- long entries creep left after a pause so the end can be read
    if self.tickerHold > 0 then self.tickerHold = self.tickerHold - dt
    else self.tickerX = math.max(394 - self.tickerW, self.tickerX - dt * 35) end
  end

  if self.ending then return end
  local y = self.year
  if self.mode == "standard" and y >= STANDARD_END then
    self.yearsBanked = self.yearsBanked
    self:endRun(true)
  end
  local tp = self:totalPop()
  if tp > self.peakPop then self.peakPop = tp end
end

------------------------------------------------------------------------
-- drawing
------------------------------------------------------------------------
local function drawSettlement(x, y, lv, ruin, cap)
  gfx.setColor(gfx.kColorBlack)
  if lv == 1 then
    gfx.fillRect(x - 1, y - 1, 3, 3)
  elseif lv == 2 then
    gfx.setColor(gfx.kColorWhite) gfx.fillRect(x - 4, y - 3, 8, 7) gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(x - 3, y, 3, 3)
    gfx.fillRect(x + 1, y - 1, 3, 4)
    gfx.fillRect(x - 4, y - 1, 5, 1) gfx.fillRect(x - 3, y - 2, 3, 1) gfx.fillRect(x - 2, y - 3, 1, 1)
  elseif lv == 3 then
    gfx.setColor(gfx.kColorWhite) gfx.fillRect(x - 5, y - 5, 11, 10) gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(x - 4, y - 1, 4, 5)
    gfx.fillRect(x + 1, y - 3, 4, 7)
    gfx.fillRect(x - 5, y - 2, 6, 1) gfx.fillRect(x - 4, y - 3, 4, 1) gfx.fillRect(x - 3, y - 4, 2, 1)
    gfx.setColor(gfx.kColorWhite) gfx.drawPixel(x + 3, y - 1) gfx.setColor(gfx.kColorBlack)
  elseif lv >= 4 then
    gfx.setColor(gfx.kColorWhite) gfx.fillRect(x - 7, y - 8, 15, 14) gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(x - 6, y - 2, 13, 7)
    gfx.fillRect(x - 2, y - 7, 4, 6)
    gfx.fillRect(x + 3, y - 4, 3, 3)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(x - 4, y, 1, 2) gfx.fillRect(x - 1, y, 2, 3) gfx.fillRect(x + 3, y + 1, 1, 2)
    gfx.setColor(gfx.kColorBlack)
    if lv == 5 then
      gfx.drawCircleAtPoint(x, y, 10)
      for i = 0, 7 do
        local a = rad(i * 45)
        gfx.fillRect(x + sin(a) * 10 - 1, y - cos(a) * 10 - 1, 3, 3)
      end
    end
  end
  if ruin and lv <= 1 then
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(x - 3, y + 2, x - 3, y - 2)
    gfx.drawLine(x + 2, y + 2, x + 2, y - 1)
    gfx.drawLine(x - 4, y + 3, x + 3, y + 3)
  end
  if cap then
    local fy = y - (lv >= 4 and 10 or 6)
    gfx.drawLine(x, fy, x, fy - 7)
    gfx.fillRect(x + 1, fy - 7, 5, 2) gfx.fillRect(x + 1, fy - 5, 3, 2)
  end
end

local function drawSwords(x, y, t)
  local w = floor(t * 6) % 2
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(x, y, 6)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawCircleAtPoint(x, y, 6)
  gfx.setLineWidth(2)
  gfx.drawLine(x - 4 + w, y - 4, x + 3, y + 3)
  gfx.drawLine(x + 4 - w, y - 4, x - 3, y + 3)
  gfx.setLineWidth(1)
  gfx.drawLine(x - 4, y + 1, x - 1, y + 4)
  gfx.drawLine(x + 4, y + 1, x + 1, y + 4)
end

local function drawSkull(x, y)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(x, y, 6)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(x, y - 1, 4)
  gfx.fillRect(x - 2, y + 2, 5, 3)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x - 2, y - 2, 2, 2)
  gfx.fillRect(x + 1, y - 2, 2, 2)
  gfx.drawPixel(x, y + 3)
  gfx.setColor(gfx.kColorBlack)
end

local function drawBowl(x, y)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x - 5, y - 3, 11, 7)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawLine(x - 4, y - 1, x + 4, y - 1)
  gfx.drawLine(x - 4, y - 1, x - 2, y + 2)
  gfx.drawLine(x + 4, y - 1, x + 2, y + 2)
  gfx.drawLine(x - 2, y + 2, x + 2, y + 2)
end

local function drawShip(x, y, t)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x - 5, y - 7, 11, 11)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(x - 5, y + 1, 11, 1)
  gfx.fillRect(x - 4, y + 2, 9, 2)
  gfx.drawLine(x, y + 1, x, y - 6)
  gfx.fillRect(x + 1, y - 5, 2, 5) gfx.fillRect(x + 3, y - 3, 2, 3)
end

local function drawStatue(x, y)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x - 5, y - 11, 11, 15)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(x - 4, y + 1, 9, 3)
  gfx.fillRect(x - 1, y - 3, 3, 4)
  drawHandGlyph(x, y - 6, 1)
end

function Civ:drawMap()
  local R, P = self.R, self.P
  self.mapImg:draw(MX, MY)
  if self.bordersDirty then self:renderBorders() end
  self.borderImg:draw(MX, MY)
  -- roads between neighbouring towns at peace
  if self.T[METAL] >= 8 then
    local rail = self.T[INDUSTRY] >= 25
    for a = 1, self.NR do
      if R.level[a] >= 2 then
        for b = a + 1, self.NR do
          if R.level[b] >= 2 and self:adjacent(a, b) then
            local oa, ob = R.owner[a], R.owner[b]
            local peace = oa == ob or (oa > 0 and P.war[oa] ~= ob)
            if peace then
              if rail then
                gfx.setColor(gfx.kColorBlack)
                gfx.setLineWidth(2)
              else
                gfx.setPattern(Art.pat.gray50)
                gfx.setLineWidth(2)
              end
              gfx.drawLine(R.x[a], R.y[a], R.x[b], R.y[b])
              gfx.setLineWidth(1)
            end
          end
        end
      end
    end
    gfx.setColor(gfx.kColorBlack)
  end
  -- settlements
  for k = 1, self.NR do
    local visible = not R.isl[k] or R.known[k]
    if visible and (R.level[k] > 0 or R.ruin[k]) then
      local o = R.owner[k]
      local isCap = o > 0 and P.alive[o] and P.cap[o] == k
      drawSettlement(R.x[k], R.y[k], R.level[k], R.ruin[k], isCap)
    end
  end
  if self.statueBuilt and self.statueRegion then
    local k = self.statueRegion
    drawStatue(R.x[k] + 10, R.y[k] + 2)
  end
  -- wars, plague, famine
  for p = 1, MAXP do
    local q = P.war[p]
    if P.alive[p] and q > p and P.front[p] > 0 and P.front[q] and P.front[q] > 0 then
      local a, b = P.front[p], P.front[q]
      drawSwords((R.x[a] + R.x[b]) / 2, (R.y[a] + R.y[b]) / 2, self.t)
    end
  end
  for k = 1, self.NR do
    if R.pop[k] > 0 then
      if R.sick[k] > 0.2 then drawSkull(R.x[k] - 9, R.y[k] - 8)
      elseif R.famine[k] then drawBowl(R.x[k] - 9, R.y[k] - 7) end
    end
  end
  for s = 1, MAXSHIP do
    if self.shipOn[s] then drawShip(self.shipX[s], self.shipY[s], self.t) end
  end
  -- a dark age dims the world
  if self.dark > 0 then
    gfx.setColor(gfx.kColorBlack)
    gfx.setDitherPattern(0.3, gfx.kDitherTypeBayer4x4)
    gfx.fillRect(MX + 1, MY + 1, MW - 2, MH - 2)
    gfx.setColor(gfx.kColorBlack)
  end
  -- the steady hand passes over the map
  if self.flashHand > 0 then
    local f = self.flashHand
    local hx = MX + MW * (1.1 - f * 1.2)
    gfx.setColor(gfx.kColorBlack)
    drawHandGlyph(hx, MY + 90, 6)
    gfx.setColor(gfx.kColorWhite)
    drawHandGlyph(hx + 1, MY + 89, 5)
    gfx.setColor(gfx.kColorBlack)
  end
end

function Civ:drawWheel(cx, cy, r)
  local ang = (self.wheel % 360) + self.wobble
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(cx, cy, r + 2)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(cx, cy, r - 1)
  gfx.setColor(gfx.kColorBlack)
  -- the twelve seasons of a generation
  local sub = self.subCount or 0
  for i = 0, 11 do
    local a = rad(i * 30)
    local x1, y1 = cx + sin(a) * (r - 1), cy - cos(a) * (r - 1)
    if i < sub then
      gfx.fillCircleAtPoint(x1, y1, 2)
    else
      gfx.drawPixel(x1, y1)
    end
  end
  gfx.setLineWidth(2)
  for i = 0, 5 do
    local a = rad(ang + i * 60)
    gfx.drawLine(cx, cy, cx + sin(a) * (r - 5), cy - cos(a) * (r - 5))
  end
  gfx.setLineWidth(1)
  gfx.drawCircleAtPoint(cx, cy, r - 5)
  gfx.fillCircleAtPoint(cx, cy, 4)
  -- crank handle
  local a = rad(ang)
  local hx, hy = cx + sin(a) * (r - 5), cy - cos(a) * (r - 5)
  gfx.fillCircleAtPoint(hx, hy, 3)
  -- the pawl: drops into the wheel when an event locks it
  local py = cy - r - 7
  local drop = self.event and 5 or 0
  gfx.fillRect(cx - 4, py - 3 + drop, 9, 3)
  gfx.fillRect(cx - 2, py + drop, 5, 2)
  gfx.fillRect(cx - 1, py + 2 + drop, 3, 2)
end

function Civ:drawPanel()
  local x0 = 272
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x0, 18, 128, 184)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(x0, 18, 2, 184)
  local era = ERAS[self.era]
  if self.eraFlash > 0 and floor(self.t * 6) % 2 == 0 then
    gfx.fillRect(x0 + 4, 20, 122, 17)
    UI.textW(era.name, x0 + 65, 20, "center", UI.bold)
  else
    UI.text(era.name, x0 + 65, 20, "center", UI.bold)
  end
  local n = self:aliveCount()
  if self.dark > 0 then
    UI.text("DARK AGE", x0 + 65, 36, "center")
  elseif n == 1 then
    local d = self:dominant()
    UI.text(GOV[self.P.gov[d]].name, x0 + 65, 36, "center")
  else
    UI.text(U.cached("civ_states", "%d STATES", n), x0 + 65, 36, "center")
  end
  self:drawWheel(x0 + 30, 78, 20)
  UI.text("PEOPLE", x0 + 60, 56)
  local tp = self.total or 0
  local shown
  if tp >= 1000 then shown = U.cached("civ_popm", "%.1fM", floor(tp / 100) / 10)
  else shown = U.cached("civ_popk", "%dK", floor(tp + 0.5)) end
  UI.text(shown, x0 + 124, 70, "right", UI.bold)
  UI.text(U.cached("civ_ypg", "%d YRS", ERAS[self.era].ypg), x0 + 124, 88, "right")
  -- tempo gauge
  local gx, gy, gw = x0 + 6, 118, 116
  local lo, hi = self:band()
  local sc = hi * 1.6
  local xl, xh = floor(gw * lo / sc), floor(gw * hi / sc)
  UI.text("TEMPO", x0 + 6, 102)
  gfx.setPattern(Art.pat.gray50)
  gfx.fillRect(gx, gy, xl, 10)
  gfx.setPattern(Art.pat.hatch)
  gfx.fillRect(gx + xh, gy, gw - xh, 10)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(gx, gy, gw, 10)
  local nx = gx + floor(gw * self.tempoPos)
  gfx.fillRect(nx - 4, gy - 5, 9, 2) gfx.fillRect(nx - 2, gy - 3, 5, 2)
  gfx.fillRect(nx - 1, gy - 1, 3, 12)
  -- bars
  local by = 132
  self:bar("FOOD", x0, by, U.clamp(self:foodRatio(), 0, 1))
  self:bar("ORDER", x0, by + 14, self.S / 100)
  self:bar("UNREST", x0, by + 28, self.Un / 100, true)
  UI.text("LORE", x0 + 6, by + 40)
  UI.text(U.cached("civ_lore", "%d", floor(self.C)), x0 + 124, by + 40, "right", UI.bold)
  -- hands
  UI.text("HANDS", x0 + 6, by + 54)
  gfx.setColor(gfx.kColorBlack)
  for i = 1, 5 do
    local hx = x0 + 70 + (i - 1) * 11
    if i <= self.hands then
      drawHandGlyph(hx, by + 62, 1)
    else
      gfx.fillRect(hx - 1, by + 62, 3, 1)
    end
  end
end

function Civ:foodRatio()
  local R = self.R
  local p, c = 0, 0
  for k = 1, self.NR do if R.pop[k] > 0 then p = p + R.pop[k] c = c + R.cap[k] end end
  if p <= 0 then return 1 end
  return c / p * 0.6
end

function Civ:bar(label, x0, y, v, danger)
  UI.text(label, x0 + 6, y - 3)
  local bx, bw = x0 + 64, 58
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(bx, y, bw, 8)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(bx, y, bw, 8)
  if danger then gfx.setPattern(Art.pat.gray50) end
  gfx.fillRect(bx + 2, y + 2, floor((bw - 4) * U.clamp(v, 0, 1)), 4)
  gfx.setColor(gfx.kColorBlack)
end

function Civ:drawTicker()
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(0, 202, 400, 20)
  local line = self:chronAt(0)
  if line then UI.textW(line, floor(self.tickerX), 204) end
end

function Civ:drawEvent()
  local ev = self.event
  local x, y, w, h = 10, 24, 252, 174
  UI.popup(x, y, w, h, "paper")
  UI.text(ev.title, x + w / 2, y + 8, "center", UI.bold)
  UI.textLines(self.eventBody, x + 12, y + 26, w - 24, 3, UI.font, -1)
  local oy = y + 76
  for i = 1, #ev.opts do
    local o = ev.opts[i]
    local sel = i == self.eventSel
    local enabled = self:optEnabled(o)
    local ry = oy + (i - 1) * 32
    if sel then
      gfx.setColor(gfx.kColorBlack)
      gfx.fillRoundRect(x + 8, ry, w - 16, 31, 4)
      UI.textW(o[1], x + 16, ry, "left", UI.bold)
      UI.textW(o[2], x + 16, ry + 15, "left")
    else
      UI.text(o[1], x + 16, ry, "left", UI.bold)
      UI.text(o[2], x + 16, ry + 15, "left")
    end
    if not enabled then
      gfx.setColor(sel and gfx.kColorWhite or gfx.kColorBlack)
      gfx.drawLine(x + 14, ry + 8, x + w - 20, ry + 8)
    end
    gfx.setColor(gfx.kColorBlack)
  end
end

function Civ:drawLog()
  UI.popup(10, 24, 252, 174, "paper")
  UI.text("THE CHRONICLE", 136, 32, "center", UI.bold)
  UI.text("of the " .. self.civName, 136, 48, "center")
  local y = 68
  for i = 0, 7 do
    local line = self:chronAt(i)
    if not line then break end
    local lines = UI.wrap(line, 226, UI.font)
    local n = math.min(2, #lines)
    if y + n * 14 > 192 then break end
    for j = 1, n do UI.text(lines[j], j == 1 and 22 or 34, y + (j - 1) * 14) end
    y = y + n * 14 + 4
  end
end

function Civ:draw()
  gfx.clear(gfx.kColorWhite)
  self:drawMap()
  self:drawPanel()
  self:drawTicker()
  if self.event then self:drawEvent() elseif self.showLog then self:drawLog() end
  UI.header(12, "CIVILIZATION", U.cached("civ_year", "YEAR %d", floor(self.year)))
  if self.event then UI.hints(Civ.HINTS_EVENT) else UI.hints(Civ.HINTS) end
end

Civ.HINTS = { { "CRANK", "TURN HISTORY" }, { "B", "HAND" }, { "A", "CHRONICLE" } }
Civ.HINTS_EVENT = { { "DPAD", "CHOOSE" }, { "A", "DECIDE" }, { "CRANK", "LOCKED" } }

------------------------------------------------------------------------
-- suspend / resume
------------------------------------------------------------------------
local function copyArr(src, n)
  local t = {}
  for i = 1, n do t[i] = src[i] end
  return t
end

function Civ:serialize()
  if self.ending then return nil end
  local R, P = self.R, self.P
  local NR = self.NR
  local chron = {}
  for i = math.min(8, self.chronN) - 1, 0, -1 do chron[#chron + 1] = self:chronAt(i) end
  return {
    v = 1, rng = self.rng:state(), mapSeed = self.mapSeed, year = self.year, gen = self.gen,
    subCount = self.subCount or 0, falls = self.falls, yearsBanked = self.yearsBanked, peakPop = self.peakPop,
    statues = self.statues, T = copyArr(self.T, 6), C = self.C, F = self.F, S = self.S, Un = self.Un, G = self.G,
    co2 = self.co2, dark = self.dark, coldT = self.coldT, cool = self.cool, grudge = self.grudge, hands = self.hands,
    steadyGens = self.steadyGens, era = self.era, civName = self.civName, civYear0 = self.civYear0 or 0, ageYear0 = self.ageYear0 or 0,
    statueBuilt = self.statueBuilt == true, statueRegion = self.statueRegion or 0,
    printed = self.printed == true, steamed = self.steamed == true, collapses = self.collapses or 0,
    pop = copyArr(R.pop, NR), owner = copyArr(R.owner, NR), dev = copyArr(R.dev, NR), sick = copyArr(R.sick, NR),
    walls = copyArr(R.walls, NR), known = copyArr(R.known, NR), ruin = copyArr(R.ruin, NR),
    palive = copyArr(P.alive, MAXP), pgov = copyArr(P.gov, MAXP), pname = copyArr(P.name, MAXP),
    pcap = copyArr(P.cap, MAXP), pwar = copyArr(P.war, MAXP), pwarT = copyArr(P.warT, MAXP),
    chron = chron,
  }
end

function Civ:deserialize(t)
  if type(t) ~= "table" or t.v ~= 1 then return end
  -- rebuild the same world from its seed, then restore the history
  self.rng:setState(t.rng)
  local R, P = self.R, self.P
  if t.mapSeed ~= self.mapSeed then
    -- the map is generated from the run seed in enter(); if it differs, keep ours
  end
  self.year, self.gen, self.subCount = t.year, t.gen, t.subCount
  self.falls, self.yearsBanked, self.peakPop, self.statues = t.falls, t.yearsBanked, t.peakPop, t.statues
  for i = 1, 6 do self.T[i] = t.T[i] end
  self.C, self.F, self.S, self.Un, self.G = t.C, t.F, t.S, t.Un, t.G
  self.co2, self.dark, self.coldT, self.cool, self.grudge = t.co2, t.dark, t.coldT, t.cool, t.grudge
  self.hands, self.steadyGens, self.era, self.civName, self.civYear0 = t.hands, t.steadyGens, t.era, t.civName, t.civYear0
  self.ageYear0 = t.ageYear0 or t.civYear0
  self.statueBuilt = t.statueBuilt
  self.statueRegion = (t.statueRegion or 0) > 0 and t.statueRegion or nil
  self.printed, self.steamed, self.collapses = t.printed, t.steamed, t.collapses
  for k = 1, math.min(self.NR, #t.pop) do
    R.pop[k], R.owner[k], R.dev[k], R.sick[k] = t.pop[k], t.owner[k], t.dev[k], t.sick[k]
    R.walls[k], R.known[k], R.ruin[k] = t.walls[k], t.known[k], t.ruin[k]
  end
  for p = 1, MAXP do
    P.alive[p], P.gov[p], P.name[p], P.cap[p], P.war[p], P.warT[p] = t.palive[p], t.pgov[p], t.pname[p], t.pcap[p], t.pwar[p], t.pwarT[p]
    P.front[p] = 0
  end
  self.chronN = 0
  for i = 1, #t.chron do
    self.chronN = self.chronN + 1
    self.chron[(self.chronN - 1) % 8 + 1] = t.chron[i]
  end
  self.total = self:totalPop()
  self:updateLevels()
  self:renderMap()
  self.bordersDirty = true
  self.coach = nil
  if self.mode == "tutorial" then self:setupCoach() end
end
