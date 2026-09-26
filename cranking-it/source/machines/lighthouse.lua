-- CRANKING IT :: No.VIII THE LIGHTHOUSE
--
-- The crank PUSHES THE LENS CARRIAGE. The great Fresnel lens floats on a
-- bath of mercury: enormous inertia, almost no friction.
--   * each degree of crank is a small torque impulse. It goes into the
--     carriage first and reaches the lens over about a second (the push
--     "leans" into the mass), so the lens answers late and keeps answering
--     after the hand stops. Counter-cranking brakes, a little harder.
--   * mercury drag bleeds speed very slowly (worse on colder, harder
--     nights); storm gusts shudder the tower and jostle the lens.
--   * the lens has G panels groups of N bull's-eyes: every sweep of a group
--     is a group of N flashes. Tonight's characteristic (e.g. Fl(2) 8s) is a
--     group every T seconds, so the lens must turn at 360 / (G * T) deg/s.
-- Ships don't read a gauge: each one times the flashes it actually sees
-- (only when a beam sweeps across it and fog doesn't hide it). A steady,
-- correct rhythm identifies the harbour; a wrong or ragged one sends it
-- toward the light itself - and the rocks in front of it. A beam falling on
-- a ship close to the surf shows its crew the danger; B blows the fog horn.

local gfx <const> = playdate.graphics
local floor <const> = math.floor
local abs <const> = math.abs
local min <const>, max <const> = math.min, math.max
local sin <const>, cos <const>, rad <const>, deg <const> = math.sin, math.cos, math.rad, math.deg
local atan <const> = math.atan
local exp <const>, sqrt <const> = math.exp, math.sqrt

------------------------------------------------------------------------
-- constants
------------------------------------------------------------------------
local CW <const> = 284             -- chart width
local CY0 <const>, CY1 <const> = 18, 222
local PX <const> = 284             -- panel x
local GAIN <const> = 0.0125        -- deg/s of lens speed per crank degree
local SEP <const> = 11             -- degrees between bull's-eyes in a group
local MAXS <const> = 7             -- ships
local MAXF <const> = 6             -- fog patches
local MAXD <const> = 18            -- debris
local WAKE <const> = 8
local NIGHT <const> = 210
local WARN_R <const> = 20
local HORN_R <const> = 150
local STRIP_N <const> = 16

local NAMES <const> = {
  "ALBA", "KESTREL", "MARY ANN", "PERSEVERANCE", "GREY GULL", "HOPE", "NINEFOLD",
  "SAINT AGNES", "CORMORANT", "LADY PELL", "MERIDIAN", "THE ORPHAN", "WHITBY ROSE",
  "BRASS MONKEY", "ELSPETH", "FAIR ISLE", "HALCYON", "OLD TOM",
}
local CHARS <const> = { -- { flashes, groups, period }
  { 1, 3, 6 }, { 2, 2, 8 }, { 2, 3, 6 }, { 3, 2, 10 }, { 1, 2, 7 }, { 3, 3, 8 }, { 2, 2, 10 },
}

local HINTS <const> = { { "CRANK", "PUSH LENS" }, { "B", "FOG HORN" } }

local lastBgKey = nil

local fmtA, fmtB, fmtC, fmtStr = {}, {}, {}, {}
-- cached multi-value format: allocates only when a value changes
local function fmt2(slot, f, a, b)
  if fmtA[slot] ~= a or fmtB[slot] ~= b or not fmtStr[slot] then
    fmtA[slot], fmtB[slot] = a, b
    fmtStr[slot] = string.format(f, a, b)
  end
  return fmtStr[slot]
end
local function fmt3(slot, f, a, b, c)
  if fmtA[slot] ~= a or fmtB[slot] ~= b or fmtC[slot] ~= c or not fmtStr[slot] then
    fmtA[slot], fmtB[slot], fmtC[slot] = a, b, c
    fmtStr[slot] = string.format(f, a, b, c)
  end
  return fmtStr[slot]
end

------------------------------------------------------------------------
-- icon
------------------------------------------------------------------------
local function drawIcon(cx, cy)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(cx - 22, cy - 22, 44, 44)
  local lx, ly = cx, cy - 11
  -- two beams sweeping out over the sea
  gfx.setColor(gfx.kColorWhite)
  gfx.fillTriangle(lx, ly, cx - 22, cy - 21, cx - 22, cy - 11)
  gfx.setPattern(Art.pat.gray50)
  gfx.fillTriangle(lx, ly, cx + 22, cy - 9, cx + 22, cy + 1)
  -- the rock it stands on
  gfx.setColor(gfx.kColorWhite)
  gfx.fillEllipseInRect(cx - 14, cy + 13, 28, 14)
  -- tapering tower with bands
  gfx.fillPolygon(cx - 4, cy - 6, cx + 4, cy - 6, cx + 7, cy + 16, cx - 7, cy + 16)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillPolygon(cx - 5, cy + 1, cx + 5, cy + 1, cx + 5, cy + 5, cx - 5, cy + 5)
  gfx.fillPolygon(cx - 6, cy + 9, cx + 6, cy + 9, cx + 7, cy + 13, cx - 7, cy + 13)
  gfx.fillRect(cx - 1, cy + 13, 2, 3)
  -- gallery, lantern, cap
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(cx - 6, cy - 8, 12, 2)
  gfx.fillRect(cx - 3, cy - 14, 6, 6)
  gfx.fillTriangle(cx - 4, cy - 14, cx + 4, cy - 14, cx, cy - 19)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(cx - 3, cy - 14, 6, 6)
  gfx.drawLine(cx, cy - 13, cx, cy - 10)
  -- swell
  gfx.setColor(gfx.kColorWhite)
  gfx.drawLine(cx - 21, cy + 12, cx - 17, cy + 10)
  gfx.drawLine(cx - 17, cy + 10, cx - 13, cy + 12)
  gfx.drawLine(cx + 13, cy + 8, cx + 17, cy + 6)
  gfx.drawLine(cx + 17, cy + 6, cx + 21, cy + 8)
  gfx.drawLine(cx - 20, cy + 19, cx - 16, cy + 17)
  gfx.drawLine(cx + 15, cy + 18, cx + 19, cy + 16)
  gfx.setColor(gfx.kColorBlack)
end

local L = Machine.define({
  id = "lighthouse",
  number = 8,
  title = "THE LIGHTHOUSE",
  tagline = "Keep time. Bring them home.",
  description = "A four-ton lens floating on mercury. Keep its flashes to the harbour's rhythm and ships will find their way.",
  howto = "Crank pushes the heavy lens; it answers late and coasts. Counter-crank brakes. Keep the period in the band: ships time your flashes. Beams on a ship near rocks warn it. B = fog horn.",
  controls = { { "CRANK", "push / brake the lens" }, { "B", "fog horn (limited)" } },
  modes = { "tutorial", "standard", "endless" },
  medals = { standard = { 700, 1250, 1700 }, endless = { 800, 2000, 3500 } },
  scoreLabel = "POINTS",
  unlockCost = 7,
  achievements = {
    { id = "home", name = "SAFE HARBOUR", desc = "Bring your first ship home." },
    { id = "surf", name = "SEEN THE SURF", desc = "Warn a lost ship with the beam." },
    { id = "true", name = "TRUE LIGHT", desc = "Stay in the band 95% of a night." },
    { id = "clean", name = "NOT ON MY WATCH", desc = "A whole night without a wreck." },
    { id = "convoy", name = "CONVOY", desc = "Three ships home in 25 seconds." },
  },
  challenges = {
    { id = "pea", name = "PEA SOUPER", desc = "Thick fog rolls in all night.", mode = "standard", difficulty = 2,
      mods = { peasouper = true }, goal = 1000, reward = 2, cost = 2 },
    { id = "gale", name = "FULL GALE", desc = "Squalls shake the tower all night.", mode = "standard", difficulty = 3,
      mods = { gale = true }, goal = 1000, reward = 3, cost = 2 },
    { id = "silent", name = "BROKEN HORN", desc = "Endless, and the fog horn is broken.", mode = "endless", difficulty = 2,
      mods = { nohorn = true }, goal = 1800, reward = 3, cost = 3 },
  },
  records = {
    { "home", "Ships brought home" },
    { "wrecks", "Wrecks" },
    { "bestBand", "Best night in band", function(v) return string.format("%d%%", v) end },
  },
  drawIcon = drawIcon,
})

------------------------------------------------------------------------
-- map
------------------------------------------------------------------------
function L:makeMap(seed)
  local mr = U.rng(seed)
  self.mapSeed = seed
  local hx = mr:range(36, 62)
  local lx = mr:range(172, 212)
  local bulge = mr:range(44, 54)
  local ph1, ph2 = mr:float() * 6, mr:float() * 6
  local coast = {}
  for x = 0, CW do
    local base = 207 + sin(x * 0.05 + ph1) * 3 + sin(x * 0.13 + ph2) * 2
    local d = (x - lx) / 30
    local y = base - bulge * exp(-d * d)
    if abs(x - hx) < 11 then y = 250 end
    coast[x] = y
  end
  self.coast = coast
  self.hx = hx
  self.lx, self.ly = lx, floor(coast[lx] + 9)
  local shore = min(coast[hx - 16], coast[hx + 16])
  self.cx, self.cy = hx + 2, floor(shore - 44)   -- channel outer mark
  self.mx, self.my = hx, floor(shore + 4)        -- harbour mouth
  self.hbx, self.hby = hx, 232                    -- inside
  -- rocks: the Teeth, strewn across the way to the light
  local rocks = {}
  local tries = 0
  while #rocks < 5 and tries < 200 do
    tries = tries + 1
    local sx, sy = lx + mr:range(-70, 30), 60
    local f = mr:between(0.5, 0.86)
    local x = sx + (lx - sx) * f + mr:between(-16, 16)
    local y = sy + (self.ly - sy) * f + mr:between(-8, 8)
    local r = mr:range(4, 7)
    local ok = x > hx + 72 and x < CW - 8 and y < coast[floor(U.clamp(x, 0, CW))] - r - 5
    for i = 1, #rocks do
      local q = rocks[i]
      if U.dist(x, y, q.x, q.y) < r + q.r + 7 then ok = false end
    end
    if ok then rocks[#rocks + 1] = { x = floor(x), y = floor(y), r = r } end
  end
  -- an outlier: the Widow
  for _ = 1, 30 do
    local x, y = mr:range(hx + 110, CW - 14), mr:range(96, 130)
    local ok = y < coast[x] - 14
    for i = 1, #rocks do if U.dist(x, y, rocks[i].x, rocks[i].y) < 22 then ok = false end end
    if ok then rocks[#rocks + 1] = { x = x, y = y, r = 5 } break end
  end
  self.rocks = rocks
  -- centre of the Teeth (the lure of a lost ship is the light itself)
  if lastBgKey then Art.uncache(lastBgKey) end
  lastBgKey = "lh_bg" .. seed
  self.bgKey = lastBgKey
end

function L:buildBackground()
  local s = self
  return Art.cached(self.bgKey, CW, CY1 - CY0, function(w, h)
    -- night sea
    gfx.setPattern(Art.pat.gray87)
    gfx.fillRect(0, 0, w, h)
    -- land
    local coast = s.coast
    gfx.setPattern(Art.pat.gray25)
    for x = 0, CW do
      local y = floor(coast[x]) - CY0
      if y < h then gfx.fillRect(x, y, 1, h - y) end
    end
    -- coastline and surf fringe
    for x = 0, CW - 1 do
      local y0, y1 = floor(coast[x]) - CY0, floor(coast[x + 1]) - CY0
      if y0 < h and y1 < h then
        gfx.setColor(gfx.kColorWhite)
        gfx.drawLine(x, y0, x + 1, y1)
        gfx.setColor(gfx.kColorBlack)
        gfx.drawLine(x, y0 + 1, x + 1, y1 + 1)
        if x % 3 == 0 then
          gfx.setColor(gfx.kColorWhite)
          gfx.drawPixel(x, y0 - 3)
        end
      end
    end
    -- harbour: quays and moored boats
    local hx = s.hx
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(hx - 13, s.my - CY0, 3, h)
    gfx.fillRect(hx + 11, s.my - CY0, 3, h)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawLine(hx - 11, s.my - CY0, hx - 11, h)
    gfx.drawLine(hx + 11, s.my - CY0, hx + 11, h)
    -- town lights
    for i = 0, 5 do
      gfx.fillRect(hx - 30 + (i * 7) % 20, h - 10 + (i * 5) % 8, 2, 2)
      gfx.fillRect(hx + 18 + (i * 11) % 22, h - 12 + (i * 3) % 9, 2, 2)
    end
    -- labels
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(hx + 16, h - 17, 44, 16)
    UI.textW("PORT", hx + 38, h - 17, "center")
    -- leading line into the channel (dashed)
    gfx.setColor(gfx.kColorWhite)
    local y0, y1 = s.cy - CY0 - 30, s.my - CY0
    for y = y0, y1, 6 do gfx.drawLine(s.cx, y, s.cx + (s.mx - s.cx) * (y - y0) / max(1, y1 - y0), y + 2) end
    -- lighthouse: a round tower seen from above, gallery and lantern
    local lx, ly = s.lx, s.ly - CY0
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(lx, ly, 9)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawCircleAtPoint(lx, ly, 8)
    gfx.fillCircleAtPoint(lx, ly, 5)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawCircleAtPoint(lx, ly, 3)
    -- keeper's cottage
    gfx.fillRect(lx + 14, ly + 4, 12, 9)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawLine(lx + 14, ly + 8, lx + 25, ly + 8)
    gfx.setColor(gfx.kColorBlack)
  end)
end

------------------------------------------------------------------------
-- setup
------------------------------------------------------------------------
function L:enter(params)
  local rng = self.rng
  self.t = 0
  local d = self.difficulty
  local tut = self.mode == "tutorial"
  self:makeMap(rng:range(1, 1000000))
  -- tonight's characteristic
  local c = tut and CHARS[2] or CHARS[rng:range(1, #CHARS)]
  self:setChar(c[1], c[2], c[3])
  self.tol = tut and 0.15 or (({ 0.12, 0.09, 0.07 })[d] or 0.12)
  self.need = (d >= 3) and 3 or 2
  self.badNeed = 2
  self.tau = tut and 9999 or (({ 150, 100, 70 })[d] or 150)
  self.shipSpeed = ({ 6.5, 7.5, 8.5 })[d] or 6.5
  -- lens
  self.omega = 0
  self.drive = 0
  self.lens = rng:range(0, 359)
  self.push = 0
  self.pushVis = 0
  self.idle = 0
  self.gust = 0
  -- run state
  self.score = 0
  self.home = 0
  self.wrecks = 0
  self.warned = 0
  self.horns = self:mod("nohorn") and 0 or 3
  self.hornT = 0
  self.bandT, self.bandTotal = 0, 0
  self.nameIdx = rng:range(1, #NAMES)
  self.spawnT = tut and 9999 or 5
  self.spawned = 0
  self.homeTimes = { -99, -99, -99 }
  self.msg, self.msgT = "", 0
  self.flashN = 0
  self.stripT = {}
  for i = 1, STRIP_N do self.stripT[i] = -99 end
  self.stripI = 0
  self.lastNorthGroup = -99
  self.lastNorthFlash = -99
  -- weather
  self.phase = 1
  self.phaseT = 0
  self.weather = "CLEAR"
  self.rain = 0
  self.rainTarget = 0
  self.vis = 999
  self.windX, self.windY = 3, 0.5
  self.gale = 0
  self.fog = {}
  for i = 1, MAXF do
    self.fog[i] = { x = rng:range(0, CW), y = rng:range(30, 180), r = rng:range(22, 40), dens = 0, target = 0 }
  end
  self:makeWeather()
  -- ships
  self.ships = {}
  for i = 1, MAXS do
    local s = { active = false, wx = {}, wy = {} }
    for k = 1, WAKE do s.wx[k], s.wy[k] = -10, -10 end
    self.ships[i] = s
  end
  self.debris = {}
  for i = 1, MAXD do self.debris[i] = { life = 0, x = 0, y = 0, vx = 0, vy = 0 } end
  -- sound
  self.hum = Audio.Hum.new(Audio.TRIANGLE)
  self.grind = Audio.Hum.new(Audio.NOISE)
  self.rainHum = Audio.Hum.new(Audio.NOISE)
  if tut then self:setupCoach() end
end

function L:setChar(n, g, T)
  self.charN, self.charG, self.charT = n, g, T
  self.omegaT = 360 / (g * T)
  self.charStr = string.format("Fl(%d) %ds", n, T)
  -- beam offsets
  self.beams = {}
  for gi = 0, g - 1 do
    for fi = 0, n - 1 do
      self.beams[#self.beams + 1] = gi * 360 / g + fi * SEP
    end
  end
  self.groupGap = max(1.0, 2.6 * SEP / self.omegaT)
end

function L:exit()
  self.hum:stop()
  self.grind:stop()
  self.rainHum:stop()
end

-- weather schedule: a list of phases drawn from the rng
local KINDS <const> = { "CLEAR", "MIST", "FOG BANK", "SQUALL" }
function L:makeWeather()
  local rng = self.rng
  self.wx = {}
  self.wt = {}
  if self.mode == "tutorial" then
    self.wx[1], self.wt[1] = 1, 99999
    return
  end
  local t = 0
  local first = 30 + rng:range(0, 15)
  self.wx[1], self.wt[1] = 1, first
  t = first
  local sev = 0
  for i = 2, 14 do
    local k
    if self:mod("peasouper") then k = (i % 2 == 0) and 3 or 2
    elseif self:mod("gale") then k = (i % 2 == 0) and 4 or 2
    else
      local w = { 3, 4 + sev, 1 + sev, 2 + sev }
      k = rng:weighted(w)
      if k == self.wx[i - 1] then k = (k % 4) + 1 end
    end
    local len = rng:range(28, 45)
    self.wx[i], self.wt[i] = k, t + len
    t = t + len
    sev = sev + 1
  end
end

function L:setupCoach()
  local s = self
  self.coach = UI.Coach.new({
    { text = "The lens floats on mercury. Crank CLOCKWISE to push it round. It is heavy: keep pushing.",
      check = function() return s.omega > s.omegaT * 0.45 end },
    { text = "Bring the needle into the white band of the CHRONOMETER, then stop. It coasts on.",
      check = function() return s:inBand() and s.idle > 0.6 end, hold = 1.2 },
    { text = "Now push it TOO FAST, past the band. Feel how late it answers.",
      check = function() return s:period() < s.charT * (1 - s.tol * 1.3) end },
    { text = "Counter-crank (ANTI-clockwise) to brake. Settle it back in the band.",
      check = function() return s:inBand() and s.idle > 0.5 end, hold = 1.5 },
    { text = "A ship! It times your flashes. Hold the rhythm until it knows the harbour.",
      enter = function() s:spawnShip(1) end,
      check = function() return s:countState("home") > 0 or s.home > 0 end },
    { text = "It has found the channel. Keep the light steady and see it in.",
      check = function() return s.home > 0 end },
    { text = "This one is lost, steering for the rocks. Press B: the fog horn turns it away.",
      enter = function() s:spawnShip(2) end,
      check = function() return s.hornT > 0 and s:countState("turn") > 0 end },
  }, { y = 20, h = 46, x = 4, w = 392 })
end

------------------------------------------------------------------------
-- queries
------------------------------------------------------------------------
function L:period()
  local w = abs(self.omega)
  if w < 0.05 then return 999 end
  return 360 / (self.charG * w)
end

function L:inBand()
  return abs(self:period() - self.charT) <= self.tol * self.charT
end

function L:countState(st)
  local n = 0
  for i = 1, MAXS do
    local s = self.ships[i]
    if s.active and s.state == st then n = n + 1 end
  end
  return n
end

------------------------------------------------------------------------
-- ships
------------------------------------------------------------------------
function L:pickApproach(s)
  local rng = self.rng
  s.tx = self.cx + rng:range(8, 70)
  s.ty = rng:range(52, 84)
end

-- kind: 0 normal, 1 tutorial reader, 2 tutorial lost ship
function L:spawnShip(kind)
  local s
  for i = 1, MAXS do
    if not self.ships[i].active then s = self.ships[i] break end
  end
  if not s then return end
  local rng = self.rng
  s.active = true
  local side = rng:range(1, 5)
  if kind == 2 then
    -- already lost, bearing down on the Teeth
    local r = self.rocks[1]
    s.x, s.y = r.x - 20, r.y - 70
  elseif side <= 3 then
    s.x, s.y = rng:range(self.cx + 10, CW - 20), CY0 + 2
  elseif side == 4 then
    s.x, s.y = 0, rng:range(34, 80)
  else
    s.x, s.y = CW, rng:range(34, 90)
  end
  if kind == 1 then s.x, s.y = self.cx + 40, CY0 + 2 end
  self:pickApproach(s)
  s.hdg = deg(atan(s.tx - s.x, -(s.ty - s.y))) % 360
  s.spd = self.shipSpeed * rng:between(0.85, 1.15)
  s.state = kind == 2 and "lost" or "approach"
  s.conf, s.bad = 0, 0
  s.lastFlash, s.groupStart, s.groupCount = -99, -99, 0
  s.turnT = 0
  s.wp = 0
  s.lit = 0
  s.sink = 0
  s.clean = true
  s.warnedOnce = false
  s.groupBearing = 0
  s.mark = 0
  s.name = NAMES[self.nameIdx]
  self.nameIdx = self.nameIdx % #NAMES + 1
  for k = 1, WAKE do s.wx[k], s.wy[k] = s.x, s.y end
  s.wakeT = 0
  s.wi = 1
  self.spawned = self.spawned + 1
end

function L:say(str, secs)
  self.msg, self.msgT = str, secs or 3
end

-- a ship has seen one flash at time t
function L:onFlash(s, t, b)
  s.lit = 0.35
  if t - s.lastFlash > self.groupGap then
    if s.groupStart > -50 then
      -- a navigator allows for his own motion across the beam's path
      local db = U.angleDiff(s.groupBearing, b)
      local dir = self.omega >= 0 and 1 or -1
      self:readGroup(s, t - s.groupStart - db * dir / self.omegaT, s.groupCount)
    end
    s.groupStart = t
    s.groupBearing = b
    s.groupCount = 1
  else
    s.groupCount = s.groupCount + 1
  end
  s.lastFlash = t
end

function L:readGroup(s, interval, count)
  if s.state == "home" or s.state == "wreck" or s.state == "safe" then return end
  local T, tol = self.charT, self.tol
  -- a group partly hidden by fog can't be read either way
  if count < self.charN then return end
  local good = count == self.charN and abs(interval - T) <= tol * T
  local missed = count == self.charN and (abs(interval - 2 * T) <= tol * 2 * T or abs(interval - 3 * T) <= tol * 3 * T)
  if good then
    s.conf = s.conf + 1
    s.mark = 0.6
    Audio.play(Audio.SINE, 1318, 0.05, 0.03, 0.001, 0.08, 0, 0.05)
    -- a crew that took it for another light needs more convincing
    if s.conf >= self.need + (s.state == "misread" and 1 or 0) then self:identified(s) end
  elseif not missed then
    s.bad = s.bad + 1
    s.conf = 0
    s.clean = false
    s.mark = 0.6
    if s.bad >= self.badNeed and (s.state == "approach" or s.state == "standoff") then
      s.state = "misread"
      s.clean = false
      self:say(s.name .. ": WRONG LIGHT!", 3)
      Audio.play(Audio.SQUARE, 330, 0.12, 0.12, 0.002, 0.1, 0.3, 0.05)
      Audio.play(Audio.SQUARE, 262, 0.12, 0.18, 0.002, 0.1, 0.3, 0.05, 0.14)
    end
  end
end

function L:identified(s)
  s.state = "home"
  s.wp = 1
  s.bad = 0
  Audio.play(Audio.SINE, 1175, 0.28, 0.4, 0.001, 0.6, 0, 0.3)
  Audio.play(Audio.SINE, 1175, 0.28, 0.4, 0.001, 0.6, 0, 0.3, 0.35)
  self:say(s.name .. " KNOWS THE LIGHT", 2.5)
end

function L:turnAway(s, fromX, fromY, secs)
  s.state = "turn"
  s.turnT = secs
  s.hdg0 = deg(atan(s.x - fromX, -(s.y - fromY))) % 360
  s.bad = 0
  s.clean = false
end

function L:wreck(s, why)
  s.state = "wreck"
  s.sink = 0
  self.wrecks = self.wrecks + 1
  self:statAdd("wrecks", 1)
  if self.mode ~= "tutorial" then self.score = self.score - 150 end
  self:say(s.name .. why, 3.5)
  Audio.sfx.snap(0.7)
  Audio.sfx.thud(1)
  Audio.sfx.splash(0.6)
  Audio.sfx.creak(0.5)
  Audio.play(Audio.SAW, 90, 0.3, 0.8, 0.01, 0.6, 0.2, 0.4, 0.2)
  self:shake(5)
  for _ = 1, 10 do
    for i = 1, MAXD do
      local d = self.debris[i]
      if d.life <= 0 then
        d.life = self.rng:between(0.8, 2.2)
        d.x, d.y = s.x, s.y
        local a = self.rng:float() * 6.283
        local v = self.rng:between(4, 18)
        d.vx, d.vy = cos(a) * v, sin(a) * v
        break
      end
    end
  end
  if self.mode == "endless" and self.wrecks >= 3 then self:endRun() end
end

function L:reachHome(s)
  s.state = "safe"
  s.sink = 0
  self.home = self.home + 1
  self:statAdd("home", 1)
  self:award("home")
  local gain = 100 + (s.clean and 50 or 0)
  if self.mode ~= "tutorial" then self.score = self.score + gain end
  self:say(s.name .. " IS HOME  +" .. gain, 2.5)
  Audio.sfx.coin()
  Audio.sfx.bell(1568, 0.2)
  local ht = self.homeTimes
  ht[1], ht[2], ht[3] = ht[2], ht[3], self.t
  if self.t - ht[1] <= 25 then self:award("convoy") end
end

function L:nearestRock(x, y)
  local best, bd = nil, 1e9
  for i = 1, #self.rocks do
    local r = self.rocks[i]
    local d = U.dist(x, y, r.x, r.y) - r.r
    if d < bd then best, bd = r, d end
  end
  return best, bd
end

function L:steer(s, want, rate, dt)
  local d = U.angleDiff(s.hdg, want)
  local step = rate * dt
  if d > step then d = step elseif d < -step then d = -step end
  s.hdg = (s.hdg + d) % 360
end

function L:updateShip(s, dt)
  local st = s.state
  if s.lit > 0 then s.lit = s.lit - dt end
  if s.mark > 0 then s.mark = s.mark - dt end
  if st == "wreck" then
    s.sink = s.sink + dt
    if s.sink > 4 then s.active = false end
    return
  elseif st == "safe" then
    s.sink = s.sink + dt
    s.y = s.y + 4 * dt
    if s.sink > 2 then s.active = false end
    return
  end
  local speed = s.spd
  local want = s.hdg
  local rate = 32
  if st == "approach" then
    want = deg(atan(s.tx - s.x, -(s.ty - s.y))) % 360
    if U.dist(s.x, s.y, s.tx, s.ty) < 8 then
      -- not sure yet: heave to and keep timing the light
      s.state = "standoff"
      s.turnT = self.charT * 2.3 + 4
    end
  elseif st == "standoff" then
    want = s.hdg + 40
    speed = speed * 0.3
    s.turnT = s.turnT - dt
    if s.turnT <= 0 then
      -- no light it trusts: it creeps toward the only light it can see
      s.state = "lost"
      s.clean = false
      self:say(s.name .. " IS LOST", 2.5)
    end
  elseif st == "lost" or st == "misread" then
    want = deg(atan(self.lx - s.x, -(self.ly - s.y))) % 360
    speed = speed * 0.8
  elseif st == "turn" then
    want = s.hdg0
    rate = 70
    speed = speed * 0.3
    s.turnT = s.turnT - dt
    if s.turnT <= 0 then
      s.state = "approach"
      s.conf = 0
      self:pickApproach(s)
      -- re-approach from further out
      s.ty = s.ty - 12
    end
  elseif st == "home" then
    local tx, ty
    if s.wp == 1 then tx, ty = self.cx, self.cy
    elseif s.wp == 2 then tx, ty = self.mx, self.my
    else tx, ty = self.hbx, self.hby end
    want = deg(atan(tx - s.x, -(ty - s.y))) % 360
    if U.dist(s.x, s.y, tx, ty) < 7 then
      s.wp = s.wp + 1
      if s.wp > 3 then self:reachHome(s) return end
    end
    -- they know these waters: give the rocks a wide berth
    local r, d = self:nearestRock(s.x, s.y)
    if r and d < 22 then
      local br = deg(atan(r.x - s.x, -(r.y - s.y))) % 360
      local off = U.angleDiff(want, br)
      if abs(off) < 90 then want = br + (off > 0 and -95 or 95) rate = 80 end
      if d < 10 then speed = speed * 0.4 end
    end
    if s.wp >= 2 then speed = speed * 0.8 rate = 60 end
  end
  self:steer(s, want, rate, dt)
  local h = rad(s.hdg)
  s.x = s.x + (sin(h) * speed + self.windX * self.gale * 0.3) * dt
  s.y = s.y + (-cos(h) * speed + self.windY * self.gale * 0.3) * dt
  s.x = U.clamp(s.x, -4, CW + 4)
  s.y = max(CY0 - 4, s.y)
  -- wake
  s.wakeT = s.wakeT + dt
  if s.wakeT > 0.45 then
    s.wakeT = 0
    s.wi = s.wi % WAKE + 1
    s.wx[s.wi], s.wy[s.wi] = s.x, s.y
  end
  -- rocks and shore
  if s.state ~= "home" or s.wp < 2 then
    local r, d = self:nearestRock(s.x, s.y)
    if r and d < 1.5 then self:wreck(s, " STRUCK THE TEETH!") return end
    local xi = floor(U.clamp(s.x, 0, CW))
    if s.y > self.coast[xi] - 2 then self:wreck(s, " RAN AGROUND!") return end
  end
end

------------------------------------------------------------------------
-- flashes, visibility
------------------------------------------------------------------------
-- how much fog lies between the light and (x, y), 0..
function L:fogBetween(x, y)
  local lx, ly = self.lx, self.ly
  local dx, dy = x - lx, y - ly
  local len2 = dx * dx + dy * dy
  local occ = 0
  for i = 1, MAXF do
    local f = self.fog[i]
    if f.dens > 0.02 then
      local t = ((f.x - lx) * dx + (f.y - ly) * dy) / max(1, len2)
      if t < 0 then t = 0 elseif t > 1 then t = 1 end
      local px, py = lx + dx * t, ly + dy * t
      local d = U.dist(px, py, f.x, f.y)
      if d < f.r then occ = occ + f.dens * (1 - d / f.r) * 1.6 end
    end
  end
  return occ
end

function L:visible(x, y)
  if U.dist(x, y, self.lx, self.ly) > self.vis then return false end
  return self:fogBetween(x, y) < 0.55
end

-- did a beam sweep across bearing b between lens angles a0 and a1?
local function swept(b, a0, a1, off)
  local da = a1 - a0
  if da >= 0 then return (b - a0 - off) % 360 < da end
  return (a0 + off - b) % 360 < -da
end

function L:flashes(a0, a1)
  local t = self.t
  local beams = self.beams
  local nb = #beams
  -- the keeper's recorder watches due north
  for k = 1, nb do
    if swept(0, a0, a1, beams[k]) then
      self.stripI = self.stripI % STRIP_N + 1
      self.stripT[self.stripI] = t
      Audio.play(Audio.SQUARE, 880, 0.035, 0.01, 0.001, 0.02, 0, 0.01)
      if t - self.lastNorthFlash > self.groupGap then self.lastNorthGroup = t end
      self.lastNorthFlash = t
    end
  end
  for i = 1, MAXS do
    local s = self.ships[i]
    if s.active and s.state ~= "wreck" and s.state ~= "safe" then
      local b = deg(atan(s.x - self.lx, -(s.y - self.ly))) % 360
      for k = 1, nb do
        if swept(b, a0, a1, beams[k]) and self:visible(s.x, s.y) then
          self:onFlash(s, t, b)
          -- lit close to the surf: the crew sees the danger
          if s.state == "lost" or s.state == "misread" or s.state == "approach" or s.state == "standoff" then
            local _, d = self:nearestRock(s.x, s.y)
            local xi = floor(U.clamp(s.x, 0, CW))
            if d < WARN_R or s.y > self.coast[xi] - 16 then
              local r = self:nearestRock(s.x, s.y)
              if d < WARN_R then self:turnAway(s, r.x, r.y, 5) else self:turnAway(s, s.x, s.y + 20, 5) end
              self.warned = self.warned + 1
              if self.mode ~= "tutorial" and not s.warnedOnce then self.score = self.score + 15 end
              s.warnedOnce = true
              self:award("surf")
              self:say(s.name .. " SIGHTS THE SURF", 2.5)
              Audio.play(Audio.SINE, 988, 0.25, 0.3, 0.001, 0.4, 0, 0.2)
            end
          end
          break
        end
      end
    end
  end
end

------------------------------------------------------------------------
-- input
------------------------------------------------------------------------
function L:cranked(change)
  if self.finished then return end
  self.push = self.push + change
end

function L:buttonDown(b)
  if self.finished then return end
  if b == Input.B then
    if self.horns <= 0 then
      Audio.sfx.denied()
      self:say(self:mod("nohorn") and "THE HORN IS BROKEN" or "NO AIR LEFT IN THE HORN", 2)
      return
    end
    self.horns = self.horns - 1
    self.hornT = 3
    Audio.sfx.horn(1.8, 0.7)
    local n = 0
    for i = 1, MAXS do
      local s = self.ships[i]
      if s.active and (s.state == "approach" or s.state == "standoff" or s.state == "lost" or s.state == "misread")
        and U.dist(s.x, s.y, self.lx, self.ly) < HORN_R then
        self:turnAway(s, self.lx, self.ly, 6)
        n = n + 1
      end
    end
    if n > 0 then self:say("THE HORN TURNS THEM AWAY", 2) end
  end
end

------------------------------------------------------------------------
-- update
------------------------------------------------------------------------
function L:updateWeather(dt)
  local t = self.t
  if self.mode == "endless" and self.phase >= #self.wx - 1 then
    -- extend the schedule: nights get worse
    local n = #self.wx
    local k = self.rng:range(2, 4)
    self.wx[n + 1], self.wt[n + 1] = k, self.wt[n] + self.rng:range(25, 40)
  end
  while self.phase < #self.wx and t >= self.wt[self.phase] do
    self.phase = self.phase + 1
    local k = self.wx[self.phase]
    self.weather = KINDS[k]
    self:applyWeather(k)
  end
  local k = self.wx[self.phase]
  -- drift fog
  for i = 1, MAXF do
    local f = self.fog[i]
    f.dens = U.approach(f.dens, f.target, dt * 0.08)
    f.x = f.x + self.windX * dt
    f.y = f.y + self.windY * dt
    if f.x > CW + f.r then f.x = -f.r f.y = self.rng:range(30, 190) end
    if f.x < -f.r - 1 then f.x = CW + f.r end
    if f.y > CY1 + f.r then f.y = CY0 - f.r end
    if f.y < CY0 - f.r - 1 then f.y = CY1 + f.r end
  end
  self.rain = U.approach(self.rain, self.rainTarget, dt * 0.3)
  self.vis = 999 - self.rain * 820
  self.gale = U.approach(self.gale, k == 4 and 1 or 0, dt * 0.2)
end

function L:applyWeather(k)
  local rng = self.rng
  local d = self.difficulty
  local fogN, fogD = 0, 0
  if k == 2 then fogN, fogD = 2 + d // 2, 0.55 + 0.1 * d
  elseif k == 3 then fogN, fogD = 3 + d // 2, 0.68 + 0.08 * d
  elseif k == 4 then fogN, fogD = 1, 0.5 end
  if self:mod("peasouper") then fogN, fogD = fogN + 1, fogD + 0.15 end
  for i = 1, MAXF do
    local f = self.fog[i]
    if i <= fogN then
      f.target = fogD * rng:between(0.8, 1.1)
      f.r = rng:range(24, 44)
      if f.dens < 0.05 then f.x = rng:range(0, CW) f.y = rng:range(30, 170) end
    else
      f.target = 0
    end
  end
  self.rainTarget = (k == 4) and 0.75 or 0
  local a = rng:between(-0.6, 0.6)
  local w = (k == 4) and 9 or 3
  self.windX, self.windY = cos(a) * w, sin(a) * w * 0.5
end

function L:endRun()
  if self.finished then return end
  self.hum:stop()
  self.grind:stop()
  self.rainHum:stop()
  local frac = self.bandTotal > 0 and self.bandT / self.bandTotal or 0
  local pct = floor(frac * 100 + 0.5)
  local bonus = floor(frac * 500)
  self.score = max(0, self.score + bonus)
  self:statMax("bestBand", pct)
  if frac >= 0.95 and self.mode == "standard" then self:award("true") end
  if self.mode == "standard" and self.wrecks == 0 and self.home >= 5 then self:award("clean") end
  local ok = self.home > self.wrecks
  if ok then Audio.sfx.success() else Audio.sfx.fail() end
  local title
  if self.mode == "endless" then title = "THREE ON THE ROCKS"
  elseif self.wrecks == 0 and self.home > 0 then title = "A QUIET NIGHT"
  elseif ok then title = "DAWN" else title = "BLACK NIGHT" end
  self:finish({ success = ok, score = self.score, title = title, delay = 1.8,
    lines = {
      "Ships home: " .. self.home,
      "Wrecks: " .. self.wrecks,
      "Warned off: " .. self.warned,
      "In band: " .. pct .. "%  (+" .. bonus .. ")",
    } })
end

function L:update(dt)
  self.t = self.t + dt
  if self.finished then return end
  -- lens: impulses lean into the carriage, then reach the lens
  local p = self.push
  self.push = 0
  if p ~= 0 then
    local g = GAIN
    if p * self.omega < 0 then g = GAIN * 1.4 end
    self.drive = self.drive + p * g
    self.idle = 0
  else
    self.idle = (self.idle or 0) + dt
  end
  self.pushVis = U.damp(self.pushVis, abs(p) / dt, 6, dt)
  local tr = self.drive * min(1, dt / 0.75)
  self.drive = self.drive - tr
  self.omega = self.omega + tr
  self.omega = self.omega * exp(-dt / self.tau)
  if self.gale > 0.05 or self:mod("gale") then
    self.gust = U.damp(self.gust, self.rng:gauss() * 1.4, 1.5, dt)
    self.omega = self.omega + self.gust * self.gale * dt
  end
  self.omega = U.clamp(self.omega, -120, 120)
  local a0 = self.lens
  local a1 = a0 + self.omega * dt
  self:flashes(a0, a1)
  self.lens = a1 % 360
  -- band keeping
  if self.mode ~= "tutorial" and self.t > 12 then
    self.bandTotal = self.bandTotal + dt
    if self:inBand() then self.bandT = self.bandT + dt end
  end
  -- weather and ships
  self:updateWeather(dt)
  for i = 1, MAXS do
    local s = self.ships[i]
    if s.active then self:updateShip(s, dt) end
  end
  for i = 1, MAXD do
    local d = self.debris[i]
    if d.life > 0 then
      d.life = d.life - dt
      d.x, d.y = d.x + d.vx * dt, d.y + d.vy * dt
      d.vx, d.vy = d.vx * 0.96, d.vy * 0.96
    end
  end
  if self.hornT > 0 then self.hornT = self.hornT - dt end
  -- the keeper pumps the reservoir back up: one blast a minute
  if not self:mod("nohorn") and self.mode ~= "tutorial" and self.horns < 3 then
    self.hornCharge = (self.hornCharge or 0) + dt
    if self.hornCharge >= 60 then
      self.hornCharge = 0
      self.horns = self.horns + 1
      Audio.play(Audio.NOISE, 500, 0.1, 0.3, 0.05, 0.2, 0, 0.1)
    end
  end
  if self.msgT > 0 then self.msgT = self.msgT - dt end
  -- spawning
  if self.mode ~= "tutorial" then
    self.spawnT = self.spawnT - dt
    if self.spawnT <= 0 then
      local base = ({ 17, 14, 12 })[self.difficulty] or 17
      if self.mode == "endless" then base = max(8, base - self.t / 40) end
      self.spawnT = base * self.rng:between(0.7, 1.3)
      if self.mode == "endless" or self.t < NIGHT - 40 then self:spawnShip(0) end
    end
  end
  -- sound: the rumble of four tons on mercury, the grind of the push
  local w = abs(self.omega)
  self.hum:set(30 + w * 0.9, w > 0.5 and (0.05 + min(0.12, w / 250)) or 0)
  self.grind:set(260 + min(400, self.pushVis), min(0.1, self.pushVis / 5000))
  self.rainHum:set(1400, self.rain * 0.06)
  if self.mode == "standard" and self.t >= NIGHT then self:endRun() end
end

------------------------------------------------------------------------
-- drawing
------------------------------------------------------------------------
function L:drawBeams()
  local lx, ly = self.lx, self.ly
  local beams = self.beams
  local a0 = self.lens
  local R = 330
  gfx.setColor(gfx.kColorWhite)
  for k = 1, #beams do
    local b = a0 + beams[k]
    local bb = b % 360
    -- the landward side of the lantern is screened
    if bb > 250 or bb < 110 then
      -- a pie slice of light: soft outer wedge, brighter core
      gfx.setDitherPattern(0.6, gfx.kDitherTypeBayer4x4)
      gfx.fillEllipseInRect(lx - R, ly - R, R * 2, R * 2, (b - 4.5) % 360, (b + 4.5) % 360)
      gfx.setDitherPattern(0.25, gfx.kDitherTypeBayer4x4)
      gfx.fillEllipseInRect(lx - R, ly - R, R * 2, R * 2, (b - 1.6) % 360, (b + 1.6) % 360)
      gfx.setColor(gfx.kColorWhite)
      local br = rad(b)
      gfx.drawLine(lx, ly, lx + sin(br) * 70, ly - cos(br) * 70)
    end
  end
  gfx.setColor(gfx.kColorBlack)
end

function L:drawRocks()
  local t = self.t
  for i = 1, #self.rocks do
    local r = self.rocks[i]
    local ph = floor((t * 2 + i) % 3)
    gfx.setColor(gfx.kColorWhite)
    gfx.setDitherPattern(0.5, gfx.kDitherTypeBayer4x4)
    gfx.drawCircleAtPoint(r.x, r.y, r.r + 3 + ph)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawCircleAtPoint(r.x, r.y, r.r + 1)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(r.x, r.y, r.r)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawPixel(r.x - 1, r.y - 2)
    gfx.setColor(gfx.kColorBlack)
  end
end

function L:drawFog()
  gfx.setColor(gfx.kColorWhite)
  for i = 1, MAXF do
    local f = self.fog[i]
    if f.dens > 0.03 then
      gfx.setDitherPattern(1 - f.dens * 0.55, gfx.kDitherTypeBayer4x4)
      gfx.fillCircleAtPoint(f.x, f.y, f.r)
      gfx.setDitherPattern(1 - f.dens * 0.5, gfx.kDitherTypeBayer4x4)
      gfx.fillCircleAtPoint(f.x + f.r * 0.3, f.y - f.r * 0.2, f.r * 0.6)
      gfx.fillCircleAtPoint(f.x - f.r * 0.4, f.y + f.r * 0.15, f.r * 0.5)
    end
  end
  gfx.setColor(gfx.kColorBlack)
end

function L:drawRain()
  if self.rain < 0.05 then return end
  local n = floor(40 * self.rain)
  local t = self.t
  gfx.setColor(gfx.kColorWhite)
  for i = 1, n do
    local x = (i * 73 + floor(t * 190) + i * i * 7) % CW
    local y = CY0 + (i * 47 + floor(t * 260)) % (CY1 - CY0)
    gfx.drawLine(x, y, x - 3, y + 6)
  end
  gfx.setColor(gfx.kColorBlack)
end

function L:drawShip(s)
  local x, y = s.x, s.y
  local h = rad(s.hdg)
  local sh, ch = sin(h), cos(h)
  -- wake: dotted trail of where it has been
  gfx.setColor(gfx.kColorWhite)
  for k = 1, WAKE do
    local idx = (s.wi - k) % WAKE + 1
    local wx, wy = s.wx[idx], s.wy[idx]
    if k <= 5 or (k % 2 == 0) then
      gfx.drawPixel(floor(wx - ch * (k % 2)), floor(wy - sh * (k % 2)))
      gfx.drawPixel(floor(wx + ch * (k % 2)), floor(wy + sh * (k % 2)))
    end
  end
  if s.state == "wreck" then
    local k = s.sink
    gfx.setColor(gfx.kColorWhite)
    gfx.drawCircleAtPoint(x, y, 3 + k * 3)
    if k < 2.5 then
      gfx.setColor(gfx.kColorBlack)
      gfx.fillTriangle(x - 4, y + 2, x + 4, y + 2, x + 1, y - 5 + k * 2)
      gfx.setColor(gfx.kColorWhite)
      gfx.drawLine(x + 1, y - 5 + k * 2, x + 1, y - 9 + k * 2)
    end
    gfx.setColor(gfx.kColorBlack)
    return
  end
  -- hull: a white capsule along the heading, dark deckhouse amidships
  local bx, by = x + sh * 6, y - ch * 6
  local tx, ty = x - sh * 5, y + ch * 5
  if s.lit > 0 then
    gfx.setColor(gfx.kColorWhite)
    gfx.drawCircleAtPoint(x, y, 11)
  end
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(7)
  gfx.drawLine(bx, by, tx, ty)
  gfx.setColor(gfx.kColorWhite)
  gfx.setLineWidth(4)
  gfx.drawLine(bx, by, tx, ty)
  gfx.setLineWidth(1)
  gfx.drawLine(bx + sh * 2, by - ch * 2, bx, by)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(floor(x - sh) - 1, floor(y + ch) - 1, 3, 3)
  -- status flag above the ship
  local fx, fy = floor(x) + 6, floor(y) - 14
  local st = s.state
  if st == "home" or st == "safe" then
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(fx - 1, fy - 1, 9, 9)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(fx + 1, fy + 4, fx + 3, fy + 6)
    gfx.drawLine(fx + 3, fy + 6, fx + 7, fy)
  elseif st == "lost" or st == "misread" then
    local on = (self.t * 4) % 2 < 1.3
    gfx.setColor(on and gfx.kColorWhite or gfx.kColorBlack)
    gfx.fillRect(fx - 1, fy - 1, 7, 10)
    gfx.setColor(on and gfx.kColorBlack or gfx.kColorWhite)
    gfx.fillRect(fx + 2, fy + 1, 2, 4)
    gfx.fillRect(fx + 2, fy + 6, 2, 2)
  elseif st == "turn" then
    gfx.setColor(gfx.kColorWhite)
    gfx.drawCircleAtPoint(fx + 3, fy + 3, 4)
  else
    -- reading: pips for each good group it has timed
    gfx.setColor(gfx.kColorWhite)
    for k = 1, self.need do
      if k <= s.conf then
        gfx.fillRect(fx + (k - 1) * 4, fy + 2, 3, 3)
      else
        gfx.drawPixel(fx + (k - 1) * 4 + 1, fy + 3)
      end
    end
  end
  gfx.setColor(gfx.kColorBlack)
end

function L:drawChart()
  self:buildBackground():draw(0, CY0)
  -- glints on the swell
  gfx.setColor(gfx.kColorWhite)
  local t = self.t
  for i = 1, 14 do
    local x = (i * 97 + floor(t * 3) * (i % 3 + 1)) % CW
    local y = CY0 + 6 + (i * 53) % 150
    if y < self.coast[x] - 6 and (floor(t * 2) + i) % 4 ~= 0 then
      gfx.drawLine(x, y, x + 3, y)
    end
  end
  -- channel buoys: port (solid) and starboard (ringed), blinking
  local bob = floor(t * 2) % 2
  local by = self.cy + 26
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(self.cx - 13, by + bob, 3)
  gfx.drawCircleAtPoint(self.cx + 15, by - bob, 4)
  if floor(t * 1.5) % 2 == 0 then
    gfx.drawCircleAtPoint(self.cx - 13, by + bob, 6)
    gfx.fillCircleAtPoint(self.cx + 15, by - bob, 2)
  end
  -- fairway buoy at the outer mark
  gfx.drawCircleAtPoint(self.cx, self.cy, 3)
  gfx.drawPixel(self.cx, self.cy)
  self:drawBeams()
  self:drawRocks()
  for i = 1, MAXS do
    local s = self.ships[i]
    if s.active then self:drawShip(s) end
  end
  -- debris
  gfx.setColor(gfx.kColorWhite)
  for i = 1, MAXD do
    local d = self.debris[i]
    if d.life > 0 then gfx.fillRect(floor(d.x), floor(d.y), 2, 1) end
  end
  self:drawFog()
  self:drawRain()
  -- horn rings
  if self.hornT > 0 then
    gfx.setColor(gfx.kColorWhite)
    local k = 3 - self.hornT
    for j = 0, 2 do
      local r = (k * 70 + j * 22) % 160
      if r > 8 then gfx.drawCircleAtPoint(self.lx, self.ly, r) end
    end
  end
  -- lantern glow
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(self.lx, self.ly, 3)
  gfx.setColor(gfx.kColorBlack)
  -- ticker
  if self.msgT > 0 then
    local w = UI.width(self.msg, UI.bold) + 12
    local x = floor(CW / 2 - w / 2)
    if x < 2 then x = 2 end
    local y = self.mode == "tutorial" and 200 or 21
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(x, y, w, 18)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawRect(x + 1, y + 1, w - 2, 16)
    UI.textW(self.msg, x + 6, y + 1, "left", UI.bold)
  end
end

function L:drawPanel()
  local x0 = PX
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x0, CY0, 400 - x0, CY1 - CY0)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(x0, CY0, 3, CY1 - CY0)
  local cx = x0 + 59
  -- characteristic plate
  gfx.fillRect(x0 + 8, 22, 104, 20)
  UI.textW(self.charStr, cx, 23, "center", UI.bold)
  -- chronometer: lens period with the tolerance band
  local mcx, mcy, r = cx, 124, 44
  local T = self.charT
  gfx.setColor(gfx.kColorBlack)
  gfx.fillEllipseInRect(mcx - r, mcy - r, r * 2, r * 2, 270, 90)
  local tol = self.tol
  local bandA = tol * 140
  gfx.setColor(gfx.kColorWhite)
  gfx.fillEllipseInRect(mcx - r + 4, mcy - r + 4, (r - 4) * 2, (r - 4) * 2, 360 - bandA, bandA)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillEllipseInRect(mcx - r + 18, mcy - r + 18, (r - 18) * 2, (r - 18) * 2, 270, 90)
  gfx.setColor(gfx.kColorWhite)
  for i = 0, 10 do
    local a = rad(-70 + i * 14)
    gfx.drawLine(mcx + sin(a) * (r - 16), mcy - cos(a) * (r - 16), mcx + sin(a) * (r - 11), mcy - cos(a) * (r - 11))
  end
  UI.text("SLOW", x0 + 6, mcy + 2)
  UI.text("FAST", x0 + 113, mcy + 2, "right")
  -- needle: period, slow to the left
  local P = self:period()
  local v = U.clamp((T - P) / T, -0.55, 0.55)
  local a = rad(v * 140)
  -- where the carriage is taking it (pending push)
  local wf = abs(self.omega + self.drive)
  local Pf = wf > 0.05 and 360 / (self.charG * wf) or 999
  local vf = U.clamp((T - Pf) / T, -0.55, 0.55)
  local af = rad(vf * 140)
  gfx.setColor(gfx.kColorWhite)
  gfx.setDitherPattern(0.5, gfx.kDitherTypeBayer4x4)
  gfx.setLineWidth(3)
  gfx.drawLine(mcx, mcy, mcx + sin(af) * (r - 6), mcy - cos(af) * (r - 6))
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(3)
  gfx.drawLine(mcx, mcy, mcx + sin(a) * (r - 4), mcy - cos(a) * (r - 4))
  gfx.setColor(gfx.kColorWhite)
  gfx.setLineWidth(1)
  gfx.drawLine(mcx, mcy, mcx + sin(a) * (r - 4), mcy - cos(a) * (r - 4))
  gfx.fillCircleAtPoint(mcx, mcy, 4)
  gfx.setColor(gfx.kColorBlack)
  if P < 99 then
    local tenths = floor(P * 10 + 0.5)
    UI.text(fmt2("lh_per", "%d.%d", tenths // 10, tenths % 10), mcx, mcy + 2, "center", UI.bold)
  else
    UI.text("--", mcx, mcy + 2, "center", UI.bold)
  end
  -- flash recorder (due north, last 14 s)
  local sx, sy, sw, sh = x0 + 6, 48, 108, 24
  gfx.drawRect(sx, sy, sw, sh)
  local now = self.t
  local scale = (sw - 4) / 14
  -- reference ticks: where tonight's groups should fall
  local g0 = self.lastNorthGroup
  if g0 > -50 then
    for k = 0, 3 do
      local tt = g0 - k * T
      local px = floor(sx + sw - 2 - (now - tt) * scale)
      if px > sx then gfx.drawLine(px, sy + 1, px, sy + 5) end
    end
  end
  for i = 1, STRIP_N do
    local ft = self.stripT[i]
    local age = now - ft
    if age < 14 then
      local px = floor(sx + sw - 2 - age * scale)
      gfx.fillRect(px, sy + 8, 2, sh - 10)
    end
  end
  -- lens seen from above: panels turning
  local lcx, lcy = x0 + 22, 167
  gfx.drawCircleAtPoint(lcx, lcy, 16)
  gfx.setPattern(Art.pat.gray25)
  gfx.fillCircleAtPoint(lcx, lcy, 14)
  gfx.setColor(gfx.kColorBlack)
  local beams = self.beams
  for k = 1, #beams do
    local ba = rad(self.lens + beams[k])
    gfx.setLineWidth(3)
    gfx.drawLine(lcx + sin(ba) * 5, lcy - cos(ba) * 5, lcx + sin(ba) * 14, lcy - cos(ba) * 14)
    gfx.setLineWidth(1)
  end
  gfx.fillCircleAtPoint(lcx, lcy, 4)
  -- tallies
  UI.text(U.cached("lh_home", "HOME %d", self.home), x0 + 44, 152)
  UI.text(U.cached("lh_wreck", "LOST %d", self.wrecks), x0 + 44, 170)
  -- horn charges
  UI.text("HORN", x0 + 8, 192)
  for i = 1, 3 do
    local hx = x0 + 60 + (i - 1) * 16
    -- a little brass horn: mouthpiece and bell
    if i <= self.horns then
      gfx.fillRect(hx - 3, 198, 6, 3)
      gfx.fillEllipseInRect(hx + 2, 192, 9, 15)
    else
      gfx.drawRect(hx - 3, 198, 6, 3)
      gfx.drawEllipseInRect(hx + 2, 192, 9, 15)
    end
  end
  -- weather
  UI.text(self.weather, cx, 206, "center")
end

function L:draw()
  gfx.clear(gfx.kColorBlack)
  self:drawChart()
  self:drawPanel()
  local right
  if self.mode == "standard" then
    local left = max(0, floor(NIGHT - self.t))
    right = fmt3("lh_hdr", "%d  %d:%02d", max(0, self.score), left // 60, left % 60)
  elseif self.mode == "endless" then
    right = U.cached("lh_hdr", "%d", self.score)
  else
    right = "LESSON"
  end
  UI.header(8, "THE LIGHTHOUSE", right)
  UI.hints(HINTS)
end

------------------------------------------------------------------------
-- suspend / resume
------------------------------------------------------------------------
local SHIP_FIELDS <const> = { "x", "y", "hdg", "spd", "state", "conf", "bad", "tx", "ty", "wp", "turnT", "hdg0", "clean", "name" }

function L:serialize()
  local ships = {}
  for i = 1, MAXS do
    local s = self.ships[i]
    if s.active and s.state ~= "wreck" and s.state ~= "safe" then
      local q = {}
      for _, k in ipairs(SHIP_FIELDS) do q[k] = s[k] end
      if q.hdg0 == nil then q.hdg0 = 0 end
      ships[#ships + 1] = q
    end
  end
  local fog = {}
  for i = 1, MAXF do
    local f = self.fog[i]
    fog[i] = { x = f.x, y = f.y, r = f.r, dens = f.dens, target = f.target }
  end
  return {
    t = self.t, omega = self.omega, drive = self.drive, lens = self.lens,
    score = self.score, home = self.home, wrecks = self.wrecks, warned = self.warned,
    horns = self.horns, bandT = self.bandT, bandTotal = self.bandTotal,
    nameIdx = self.nameIdx, spawnT = self.spawnT, spawned = self.spawned,
    mapSeed = self.mapSeed, char = { self.charN, self.charG, self.charT },
    wx = self.wx, wt = self.wt, phase = self.phase, rain = self.rain, rainTarget = self.rainTarget,
    windX = self.windX, windY = self.windY, gale = self.gale, weather = self.weather,
    rng = self.rng:state(), ships = ships, fog = fog,
  }
end

function L:deserialize(t)
  if t.mapSeed and t.mapSeed ~= self.mapSeed then self:makeMap(t.mapSeed) end
  if t.char then self:setChar(t.char[1], t.char[2], t.char[3]) end
  self.t = t.t or 0
  self.omega, self.drive, self.lens = t.omega or 0, t.drive or 0, t.lens or 0
  self.score, self.home, self.wrecks = t.score or 0, t.home or 0, t.wrecks or 0
  self.warned, self.horns = t.warned or 0, t.horns or 0
  self.bandT, self.bandTotal = t.bandT or 0, t.bandTotal or 0
  self.nameIdx, self.spawnT, self.spawned = t.nameIdx or 1, t.spawnT or 5, t.spawned or 0
  if t.wx and t.wt then self.wx, self.wt = t.wx, t.wt end
  self.phase = t.phase or 1
  self.rain, self.rainTarget = t.rain or 0, t.rainTarget or 0
  self.windX, self.windY, self.gale = t.windX or 3, t.windY or 0, t.gale or 0
  self.weather = t.weather or "CLEAR"
  if t.rng then self.rng:setState(t.rng) end
  if t.fog then
    for i = 1, min(#t.fog, MAXF) do
      local f, q = self.fog[i], t.fog[i]
      f.x, f.y, f.r, f.dens, f.target = q.x, q.y, q.r, q.dens, q.target
    end
  end
  for i = 1, MAXS do self.ships[i].active = false end
  local list = t.ships or {}
  for j = 1, min(#list, MAXS) do
    local s, q = self.ships[j], list[j]
    for _, k in ipairs(SHIP_FIELDS) do s[k] = q[k] end
    s.active = true
    s.lastFlash, s.groupStart, s.groupCount = -99, -99, 0
    s.lit, s.sink, s.mark, s.wakeT, s.wi = 0, 0, 0, 0, 1
    for k = 1, WAKE do s.wx[k], s.wy[k] = s.x, s.y end
  end
end
