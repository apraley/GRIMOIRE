-- CRANKING IT :: No.IX SAILBOAT WINCH
--
-- The crank IS the handle of a two-speed self-tailing sheet winch on a
-- small racing keelboat.
--
--   * Wind: a true wind with slow shifts plus gust / lull patches that drift
--     downwind across the water. Boat velocity turns it into the apparent
--     wind (AWA / AWS) that the sails actually feel.
--   * Sails: each sail's angle is LIMITED by its sheet. The wind blows the
--     sail out to that limit; if the sheet is looser than the apparent wind
--     the sail streams and luffs. Angle of attack -> lift & drag curves
--     (luff below ~11 deg, best ~14-26, stall beyond) -> drive (boat speed
--     against hull + keel drag) and side force (heel). Too much heel costs
--     speed and makes the boat round up; far too much is a knockdown.
--   * Jib: two sheets. The leeward one trims it. After a tack the old sheet
--     is now to windward and holds the jib BACKED until it is cast off.
--   * Winch: the sheet load is the sail force. Clockwise hauls the active
--     sheet: HIGH gear moves 1.3 m per handle turn but can only pull about a
--     third of what LOW gear (0.45 m per turn) can. If the load exceeds the
--     current gear's capacity the drum stalls - the handle turns, the pawls
--     don't click, the winch groans. Counter-clockwise eases under control.
--     Holding B throws the sheet off the winch and it runs free.
-- The furious moment: tack, cast off the old jib sheet, then grind the new
-- one in from fully eased - HIGH while the sail flogs, LOW as it fills.

local gfx <const> = playdate.graphics
local floor <const>, abs <const>, sqrt <const> = math.floor, math.abs, math.sqrt
local sin <const>, cos <const>, rad <const>, deg <const>, atan <const> = math.sin, math.cos, math.rad, math.deg, math.atan
local min <const>, max <const> = math.min, math.max
local clamp <const> = U.clamp
local angleDiff <const> = U.angleDiff

------------------------------------------------------------------------
-- constants
------------------------------------------------------------------------
local KN <const> = 5                      -- world units per second per knot
local JIB_P <const>, MAIN <const>, JIB_S <const> = 1, 2, 3
local HIGH <const>, LOW <const> = 1, 2
local LINE_NAME <const> = { "JIB P", "MAIN", "JIB S" }
local LMAX <const> = { 10.5, 7.5, 10.5 }    -- metres of sheet that can be let out
local PER_TURN <const> = { 1.3, 0.45 }    -- metres of sheet per handle turn
local DRUM_CIRC <const> = 1.3             -- drum circumference (m)
local CAP_STD <const> = { 105, 300 }      -- load each gear can pull
local CAP_TUT <const> = { 40, 150 }
local AREA_MAIN <const>, AREA_JIB <const> = 1.0, 0.75
local MASS <const> = 160
local HULL_C1 <const>, HULL_C2 <const>, HULL_V <const> = 4.4, 70, 5.8
local IND_C <const> = 0.0048              -- keel induced drag
local WINDAGE <const> = 0.08
local LAY <const> = 44                    -- close-hauled true wind angle (laylines)
local RUN_TWA <const> = 150               -- deepest sensible downwind angle
local NPATCH <const> = 7
local NSTREAK <const> = 12
local NSPRAY <const> = 24
local NWAKE <const> = 18
local SEA_W <const>, SEA_CX <const> = 290, 145

-- triangle course: windward, wing, leeward, then a beat to the finish line
local COURSE <const> = { 0, -700, -450, -330, 60, 60 }
local FIN_Y <const>, FIN_HALF <const> = -360, 75
local ROUND_R <const> = 46
local RACE_LIMIT <const> = 420

-- rival boat's polar (knots at 12 kn true wind), index = TWA / 10
local POLAR <const> = { [0] = 0, 0, 0, 2.0, 6.0, 6.6, 7.0, 7.2, 7.3, 7.3, 7.2, 7.1, 6.9, 6.6, 6.2, 5.7, 5.3, 4.9, 4.5 }

local ST_LUFF <const>, ST_DRAW <const>, ST_STALL <const>, ST_BACK <const> = 1, 2, 3, 4
local ST_NAME <const> = { "LUFF", "DRAW", "STALL", "BACKED" }

local POS_NAME <const> = { "IN IRONS", "CLOSE HAULED", "CLOSE REACH", "BEAM REACH", "BROAD REACH", "RUNNING" }

local MARK_LABEL <const> = { "1", "2", "3" }
local HINTS <const> = { { "CRANK", "HAUL/EASE" }, { "A", "GEAR" }, { "B", "LINE/CAST" }, { "DPAD", "STEER" } }

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------
-- compass bearing of a world vector (y grows downward / south)
local function compass(dx, dy) return deg(atan(dx, -dy)) % 360 end

local function liftC(a)
  if a <= 0 then return 0 end
  if a < 20 then return 1.45 * sin(rad(a * 4.5)) end
  local cl = 1.45 - (a - 20) * 0.0157
  return cl < 0 and 0 or cl
end

local function dragC(a)
  if a <= 0 then return 0.06 end
  local s = sin(rad(a))
  local cd = 0.07 + 1.1 * s * s
  if a < 8 then cd = cd + 0.05 end -- flogging cloth
  return cd
end

local function jibDelta(L) return 10 + L * 9.6 end
local function mainDelta(L) return 4 + L * 10.8 end

local function polar(a)
  a = abs(a)
  local i = floor(a / 10)
  if i >= 18 then return POLAR[18] end
  local f = a / 10 - i
  return POLAR[i] + (POLAR[i + 1] - POLAR[i]) * f
end

local function pointOfSail(twa)
  local a = abs(twa)
  if a < 36 then return 1 elseif a < 60 then return 2 elseif a < 80 then return 3
  elseif a < 110 then return 4 elseif a < 152 then return 5 end
  return 6
end

local function sailState(alpha, atMax)
  if alpha < -0.5 then return ST_BACK end
  if alpha < 11 then return ST_LUFF end
  if alpha <= 26 or atMax then return ST_DRAW end
  return ST_STALL
end

------------------------------------------------------------------------
-- cached art
------------------------------------------------------------------------
local HULL_PTS <const> = { 20, 0, 15, -5, 6, -8, -6, -8.5, -17, -7, -17, 7, -6, 8.5, 6, 8, 15, 5 }
local HULL_IMG = { {}, {} }
local BS <const> = 2.0                   -- boat drawing scale (px per hull unit)
local HIMG <const> = 84

local DECK_PTS <const> = { 17.5, 0, 13.2, -3.8, 5, -6.4, -6, -6.9, -15.6, -5.6, -15.6, 5.6, -6, 6.9, 5, 6.4, 13.2, 3.8 }
local CABIN_PTS <const> = { 7, -3.2, 7, 3.2, -4, 4.4, -4, -4.4 }
local WELL_PTS <const> = { -6, -4, -6, 4, -14.5, 3.6, -14.5, -3.6 }

local function buildHull(style, i)
  local img = gfx.image.new(HIMG, HIMG, gfx.kColorClear)
  gfx.pushContext(img)
  local a = rad(i * 10)
  local c = HIMG / 2
  local fx, fy, rx, ry = sin(a) * BS, -cos(a) * BS, cos(a) * BS, sin(a) * BS
  local P = Art.poly
  local function load(pts)
    local n = 0
    for k = 1, #pts, 2 do
      P[n + 1] = c + fx * pts[k] + rx * pts[k + 1]
      P[n + 2] = c + fy * pts[k] + ry * pts[k + 1]
      n = n + 2
    end
    return n
  end
  -- hull: black sheer strake, then the deck
  gfx.setColor(gfx.kColorBlack)
  Art.polyFill(load(HULL_PTS))
  if style == 1 then
    -- teak-grey deck so the white sails stand out over it
    gfx.setPattern(Art.pat.gray25)
    Art.polyFill(load(DECK_PTS))
    gfx.setPattern(Art.pat.gray75)
    Art.polyFill(load(WELL_PTS))
    gfx.setColor(gfx.kColorWhite)
    Art.polyFill(load(CABIN_PTS))
    gfx.setColor(gfx.kColorBlack)
    Art.polyStroke(load(CABIN_PTS))
    -- sheet winches either side of the cockpit
    gfx.fillCircleAtPoint(c + fx * -9 + rx * -6, c + fy * -9 + ry * -6, 2)
    gfx.fillCircleAtPoint(c + fx * -9 + rx * 6, c + fy * -9 + ry * 6, 2)
  else
    gfx.setPattern(Art.pat.gray75)
    Art.polyFill(load(DECK_PTS))
    gfx.setColor(gfx.kColorWhite)
    Art.polyStroke(load(CABIN_PTS))
  end
  gfx.popContext()
  HULL_IMG[style][i] = img
  return img
end

local function hullImage(style, hd)
  local i = floor(hd / 10 + 0.5) % 36
  return HULL_IMG[style][i] or buildHull(style, i)
end

local function seaTile()
  return Art.cached("winch_sea", 128, 128, function()
    local r = U.rng(4242)
    gfx.setColor(gfx.kColorBlack)
    for _ = 1, 22 do
      local x, y = r:range(2, 118), r:range(2, 122)
      local w = r:range(3, 5)
      gfx.drawLine(x, y + 1, x + w, y)
      gfx.drawLine(x + w, y, x + w * 2, y + 1)
    end
    for _ = 1, 10 do gfx.drawPixel(r:range(0, 127), r:range(0, 127)) end
  end)
end

------------------------------------------------------------------------
-- definition
------------------------------------------------------------------------
local Winch = Machine.define({
  id = "winch",
  number = 9,
  title = "SAILBOAT WINCH",
  tagline = "Grind. Tack. Grind harder.",
  description = "A two-speed sheet winch on a racing keelboat. Trim the sails to the wind, and grind like mad through every tack.",
  howto = "Crank clockwise hauls the active sheet, back eases it. Trim until the tell-tales DRAW. Load too high? The drum stalls: A for LOW gear. Tack: hold B to cast off the old jib sheet, then grind in the new one.",
  controls = { { "CRANK", "haul (cw) / ease (ccw)" }, { "A", "winch gear HIGH / LOW" }, { "B", "next line; hold: cast off" }, { "DPAD", "steer the tiller" } },
  modes = { "tutorial", "standard", "endless" },
  medals = { standard = { 3000, 5800, 8000 }, endless = { 800, 2000, 3500 } },
  scoreLabel = "POINTS",
  unlockCost = 8,
  achievements = {
    { id = "win", name = "LINE HONOURS", desc = "Beat the rival boat home." },
    { id = "tack", name = "CLEAN TACK", desc = "Jib drawing 5s after a tack." },
    { id = "gybe", name = "GYBE-HO", desc = "Gybe with the mainsheet in." },
    { id = "grinder", name = "GRINDER", desc = "Crank 120 winch turns in a race." },
    { id = "patrol", name = "HARBOUR PATROL", desc = "Collect 12 buoys in Endless." },
  },
  challenges = {
    { id = "onegear", name = "SNAPPED PAWL", desc = "No LOW gear. Head up to ease the load, then trim.", mode = "standard", difficulty = 2, goal = 4000, reward = 2, cost = 2 },
    { id = "squall", name = "SQUALL LINE", desc = "Violent gusts. Ease or be knocked flat.", mode = "standard", difficulty = 3, goal = 5000, reward = 3, cost = 2 },
    { id = "fog", name = "SEA FOG", desc = "Endless patrol in thick fog.", mode = "endless", difficulty = 2, mods = { fog = true }, goal = 1200, reward = 3, cost = 3 },
  },
  records = {
    { "wins", "Races won" },
    { "fastest", "Fastest race", function(v) return (v and v > 0) and string.format("%.1fs", v / 10) or "-" end },
    { "tacks", "Tacks" },
    { "turns", "Winch turns" },
    { "buoys", "Best patrol" },
  },
  drawIcon = function(cx, cy)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(cx - 22, cy - 22, 44, 44)
    gfx.setColor(gfx.kColorWhite)
    -- sea
    for i = 0, 2 do
      local y = cy + 14 + i * 3
      for x = cx - 20, cx + 16, 8 do gfx.drawLine(x, y, x + 4, y - 1) end
    end
    -- hull
    gfx.fillPolygon(cx - 19, cy + 8, cx + 19, cy + 8, cx + 13, cy + 13, cx - 14, cy + 13)
    -- main and jib
    gfx.fillPolygon(cx - 1, cy - 20, cx - 1, cy + 5, cx + 15, cy + 5)
    gfx.fillPolygon(cx - 4, cy - 17, cx - 4, cy + 5, cx - 17, cy + 5)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(cx + 3, cy - 8, cx + 8, cy - 2)
    -- the winch, top view, with its handle
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(cx + 13, cy - 13, 7)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(cx + 13, cy - 13, 4)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(cx + 13, cy - 13, 1)
    gfx.setLineWidth(2)
    gfx.drawLine(cx + 13, cy - 13, cx + 20, cy - 20)
    gfx.setLineWidth(1)
  end,
})

------------------------------------------------------------------------
-- setup
------------------------------------------------------------------------
function Winch:enter(params)
  local d = self.difficulty
  local rng = self.rng
  self.tut = self.mode == "tutorial"
  self.endless = self.mode == "endless"
  self.chal = params.challengeId
  self.t, self.raceT = 0, 0

  -- wind
  self.twd0 = 0
  self.ph1, self.ph2, self.ph3 = rng:between(0, 6.28), rng:between(0, 6.28), rng:between(0, 6.28)
  if self.tut then
    self.tws0, self.shiftAmp, self.gustMin, self.gustMax, self.gustRate = 9, 0, 0, 0, 0
  else
    local T = { { 11, 6, 0.22, 0.40, 4.2 }, { 13, 9, 0.28, 0.50, 3.6 }, { 15, 12, 0.35, 0.62, 3.0 } }
    local w = T[d] or T[1]
    self.tws0, self.shiftAmp, self.gustMin, self.gustMax, self.gustRate = w[1], w[2], w[3], w[4], w[5]
    if self.chal == "squall" then self.gustMax, self.gustRate = 0.9, 2.4 end
  end
  self.windT = 0
  self.twdNow, self.twsNow = self.twd0, self.tws0
  self.spawnT = 1
  self.knockHeel = ({ 46, 44, 42 })[d] or 46
  self.righting = ({ 1800, 1650, 1500 })[d] or 1800

  -- winch
  local base = self.tut and CAP_TUT or CAP_STD
  local mult = ({ 1, 0.94, 0.88 })[d] or 1
  self.cap = { base[1] * mult, base[2] * mult }
  self.gear = HIGH
  self.sel = MAIN
  self.crankIn = 0
  self.crankRps = 0
  self.handleDeg = 0
  self.drumDeg = 0
  self.pawl = 0
  self.strain = 0
  self.stallT = 0
  self.effort = 0
  self.bDown, self.bT, self.bCast = false, 0, false
  self.turns = 0
  self.blockT = 0

  -- the boat
  local b = {
    x = -30, y = 30, hd = 315, v = 1.5, heel = 0, heelV = 0, rudder = 0,
    L = { 6, 5, 10.5 }, T = { 0, 0, 0 }, run = { false, false, false },
    tackSide = 1, boom = 0, jib = 0, aM = 0, aJ = 0, alphaM = 0, alphaJ = 0,
    stM = ST_LUFF, stJ = ST_LUFF, lee = JIB_P, awa = 45, aws = 10, twa = 45, tws = 10, twd = 0,
    gust = 0, knock = 0, drive = 0, side = 0, turn = 0, backed = false,
  }
  if self.tut then
    b.x, b.y, b.hd, b.v = 0, 0, 90, 0
    b.tackSide = -1
    b.L[JIB_P], b.L[MAIN], b.L[JIB_S] = 10.5, 7.5, 10.5
  elseif self.endless then
    b.x, b.y = 0, 0
  end
  self.b = b
  self.camX, self.camY = b.x, b.y
  self.seaCY = self.tut and 98 or 122

  -- race state
  self.mark = 1
  self.penalty = 0
  self.crashes, self.knocks = 0, 0
  self.tacks, self.gybes = 0, 0
  self.sinceTack = 99
  self.tackWatch = false
  self.done = false
  self.score = 0
  self.hdrSec = -1
  self.hdrStr = "LESSON"
  if not self.tut and not self.endless then
    self.rival = { x = 34, y = 44, hd = 315, v = 1.2, mark = 1, tack = 1, direct = false, done = false, finT = 0, boom = 0, prevY = 44 }
    self.skill = ({ 0.78, 0.83, 0.87 })[d] or 0.78
    if self.chal == "squall" then self.skill = 0.95 end
  end
  -- endless patrol
  self.buoys = 0
  self.strikes = 0
  self.timeLeft = self.endless and 80 or 0
  self.buoyT = 0
  self.bx, self.by = 0, -300
  if self.endless then self:spawnBuoy() end

  -- wind patches, streaks, fx pools (preallocated, reused)
  self.patches = {}
  for i = 1, NPATCH do self.patches[i] = { on = false, x = 0, y = 0, r = 60, g = 0, sh = 0, age = 0 } end
  if self.gustRate > 0 then for _ = 1, 4 do self:spawnPatch(true) end end
  self.streaks = {}
  for i = 1, NSTREAK * 2 do self.streaks[i] = 0 end
  for i = 1, NSTREAK do
    self.streaks[i * 2 - 1] = b.x + rng:between(-170, 170)
    self.streaks[i * 2] = b.y + rng:between(-130, 130)
  end
  self.spX, self.spY, self.spVX, self.spVY, self.spL = {}, {}, {}, {}, {}
  for i = 1, NSPRAY do self.spX[i], self.spY[i], self.spVX[i], self.spVY[i], self.spL[i] = 0, 0, 0, 0, 0 end
  self.spI = 0
  self.wkX, self.wkY, self.wkH, self.wkA = {}, {}, {}, {}
  for i = 1, NWAKE do self.wkX[i], self.wkY[i], self.wkH[i], self.wkA[i] = b.x, b.y, b.hd, 99 end
  self.wkI, self.wkT = 0, 0
  self.flapT = 0
  self.msg, self.msgT = nil, 0
  self.gearFlash = 0

  -- prebuild hull sprites (cached across runs)
  for i = 0, 35 do
    if not HULL_IMG[1][i] then buildHull(1, i) end
    if not HULL_IMG[2][i] then buildHull(2, i) end
  end

  -- sound
  self.windHum = Audio.Hum.new(Audio.NOISE)
  self.strainHum = Audio.Hum.new(Audio.SAW)
  self.whirrHum = Audio.Hum.new(Audio.TRIANGLE)

  if self.tut then
    self:setupCoach()
  else
    self:say("GO!  TRIM AND SAIL", 2)
    Audio.sfx.horn(0.6, 0.4)
  end
end

function Winch:exit()
  self.windHum:stop()
  self.strainHum:stop()
  self.whirrHum:stop()
end

function Winch:say(text, secs)
  self.msg, self.msgT = text, secs or 1.8
end

function Winch:setupCoach()
  local s = self
  local b = self.b
  self.coach = UI.Coach.new({
    { text = "You're on the winch. Crank CLOCKWISE to haul in the MAIN sheet. Hear the pawls click.",
      check = function() return b.L[MAIN] < 5.5 end },
    { text = "Keep hauling. As the sail fills, the load climbs until HIGH gear STALLS the drum.",
      check = function() return s.stallT > 0.25 or (s.gear == LOW and b.alphaM > 8) end },
    { text = "Press A for LOW gear: slower, but three times the pull.",
      check = function() return s.gear == LOW end },
    { text = "Trim until the MAIN tell-tales read DRAW. Over-trimmed? Crank back to ease.",
      check = function() return b.stM == ST_DRAW end, hold = 1.0 },
    { text = "Tap B to put the jib's working sheet, JIB S, on the winch.",
      check = function() return s.sel == JIB_S end },
    { text = "Grind the jib in: HIGH gear for the slack, LOW when it loads up. Trim it to DRAW.",
      check = function() return b.stJ == ST_DRAW end, hold = 1.0 },
    { text = "Steer LEFT, up toward the wind, to CLOSE HAULED. Trim in as the sails luff.",
      check = function() return pointOfSail(b.twa) == 2 and b.v > 2.3 end, hold = 1.5 },
    { text = "TACK! Hold LEFT and turn the bow through the wind to the other side.",
      enter = function() s.tutTacks = s.tacks end,
      check = function() return s.tacks > (s.tutTacks or 0) and b.twa > 20 end },
    { text = "The old JIB S sheet holds the jib BACKED. With it selected, HOLD B to cast it off.",
      check = function() return b.run[JIB_S] or b.L[JIB_S] > 5 end },
    { text = "JIB P drops on the winch. GRIND! HIGH for the slack, LOW when it stalls. Trim to DRAW.",
      check = function() return b.lee == JIB_P and b.stJ == ST_DRAW end, hold = 0.8 },
  }, { x = 4, w = 392, y = 174, h = 46, anchor = "bottom" })
end

------------------------------------------------------------------------
-- wind
------------------------------------------------------------------------
function Winch:spawnPatch(initial)
  local slot
  for i = 1, NPATCH do if not self.patches[i].on then slot = self.patches[i] break end end
  if not slot then return end
  local rng = self.rng
  local b = self.b
  local tr = rad(self.twdNow)
  local dx, dy = -sin(tr), cos(tr)          -- direction the wind blows toward
  local up = initial and rng:between(-320, 380) or rng:between(430, 480)
  local cross = rng:between(-400, 400)
  slot.x = b.x - dx * up + dy * cross
  slot.y = b.y - dy * up - dx * cross
  slot.r = rng:between(55, 115)
  if rng:chance(0.72) then
    slot.g = rng:between(self.gustMin, self.gustMax)
  else
    slot.g = rng:between(-0.35, -0.15)
  end
  slot.sh = rng:between(-4 - self.shiftAmp * 0.6, 4 + self.shiftAmp * 0.6)
  slot.age = 0
  slot.on = true
end

-- true wind speed & direction at a point: base breeze + patches
function Winch:windAt(x, y)
  local gsum, ssum = 0, 0
  local P = self.patches
  for i = 1, NPATCH do
    local p = P[i]
    if p.on then
      local dx, dy = x - p.x, y - p.y
      local r = p.r
      local d2 = dx * dx + dy * dy
      if d2 < r * r then
        local f = 1 - sqrt(d2) / r
        f = f * f * (3 - 2 * f)
        if p.age < 1.5 then f = f * p.age / 1.5 end
        gsum = gsum + p.g * f
        ssum = ssum + p.sh * f
      end
    end
  end
  return self.twsNow * (1 + gsum), self.twdNow + ssum, gsum
end

function Winch:updateWind(dt)
  self.windT = self.windT + dt
  local wt = self.windT
  self.twdNow = self.twd0 + self.shiftAmp * (sin(wt * 0.0885 + self.ph1) + 0.5 * sin(wt * 0.2166 + self.ph2))
  self.twsNow = self.tws0 * (1 + 0.05 * sin(wt * 0.48 + self.ph3))
  local tr = rad(self.twdNow)
  local dx, dy = -sin(tr), cos(tr)
  local spd = self.twsNow * KN * 0.5
  local b = self.b
  local nAct = 0
  for i = 1, NPATCH do
    local p = self.patches[i]
    if p.on then
      p.x = p.x + dx * spd * dt
      p.y = p.y + dy * spd * dt
      p.age = p.age + dt
      local rx, ry = p.x - b.x, p.y - b.y
      local along = rx * dx + ry * dy
      if along > 480 or abs(rx * dy - ry * dx) > 720 then p.on = false else nAct = nAct + 1 end
    end
  end
  if self.gustRate > 0 then
    self.spawnT = self.spawnT - dt
    if self.spawnT <= 0 then
      if nAct < NPATCH then self:spawnPatch(false) end
      self.spawnT = self.rng:between(self.gustRate * 0.6, self.gustRate * 1.4)
    end
  end
  -- cat's-paw streaks drift with the wind, wrapped around the camera
  local S = self.streaks
  local sv = self.twsNow * KN * 0.9 * dt
  local cx, cy = self.camX, self.camY
  for i = 1, NSTREAK do
    local x = S[i * 2 - 1] + dx * sv
    local y = S[i * 2] + dy * sv
    S[i * 2 - 1] = cx + (x - cx + 170) % 340 - 170
    S[i * 2] = cy + (y - cy + 130) % 260 - 130
  end
end

------------------------------------------------------------------------
-- input
------------------------------------------------------------------------
function Winch:cranked(change)
  if self.finished then return end
  self.crankIn = self.crankIn + change
end

function Winch:buttonDown(btn)
  if self.finished then return end
  if btn == Input.A then
    if self.chal == "onegear" then
      Audio.sfx.denied()
      self:say("LOW GEAR PAWL SNAPPED", 1.2)
      return
    end
    self.gear = self.gear == HIGH and LOW or HIGH
    self.gearFlash = 0.4
    Audio.sfx.clack(0.5)
    Audio.play(Audio.SQUARE, self.gear == HIGH and 900 or 500, 0.15, 0.04)
  elseif btn == Input.B then
    self.bDown, self.bT, self.bCast = true, 0, false
  elseif btn == Input.UP then
    self:selectLine((self.sel + 1) % 3 + 1)
  elseif btn == Input.DOWN then
    self:selectLine(self.sel % 3 + 1)
  end
end

function Winch:buttonUp(btn)
  if btn == Input.B then
    if self.bDown and not self.bCast and not self.finished then
      -- MAIN -> working jib sheet -> lazy jib sheet -> MAIN
      local lee = self.b.lee
      local sel = self.sel
      self:selectLine(sel == MAIN and lee or (sel == lee and 4 - lee or MAIN))
    end
    self.bDown = false
  end
end

function Winch:selectLine(i)
  self.sel = i
  Audio.sfx.tick(1200, 0.2)
  Audio.play(Audio.TRIANGLE, 300, 0.2, 0.05)
end

function Winch:castOff(i)
  local b = self.b
  b.run[i] = true
  Audio.sfx.whoosh(0.35)
  Audio.sfx.snap(0.25)
  if i ~= MAIN then
    -- the crew drops the other jib sheet onto the winch
    self.sel = 4 - i
    if not self.tut then self:say(i == JIB_P and "JIB S ON THE WINCH: GRIND!" or "JIB P ON THE WINCH: GRIND!", 1.6) end
  elseif not self.tut then
    self:say("MAIN DUMPED", 1.2)
  end
end

------------------------------------------------------------------------
-- the winch: crank -> sheet length through the gear, against the load
------------------------------------------------------------------------
function Winch:winch(ch, dt)
  local b = self.b
  local sel = self.sel
  self.handleDeg = (self.handleDeg + ch) % 360
  local rps = abs(ch) / dt / 360
  self.crankRps = U.damp(self.crankRps, rps, 8, dt)
  local moved = 0
  local straining = false
  if ch ~= 0 then
    if b.run[sel] then
      b.run[sel] = false
      Audio.sfx.clack(0.35)
    end
    local gear = self.gear
    local per = PER_TURN[gear] * ch / 360
    if ch > 0 then
      -- a hand can put out only so much power: grinding faster pulls less
      local cap = self.cap[gear] * (1.12 - 0.22 * clamp(self.crankRps / 3, 0, 1))
      local T = b.T[sel]
      local e = clamp((cap - T) / (0.25 * cap), 0, 1)
      self.effort = U.damp(self.effort, 1 - e, 10, dt)
      local d = per * e
      if d >= b.L[sel] then
        d = b.L[sel]
        self.blockT = self.blockT + dt
        if self.blockT > 0 and self.blockT < dt * 1.5 then Audio.sfx.thunk(0.3) end
      else
        self.blockT = 0
      end
      b.L[sel] = b.L[sel] - d
      moved = -d
      if e < 0.1 then straining = true end
    else
      local d = -per
      local room = LMAX[sel] - b.L[sel]
      if d > room then d = room end
      b.L[sel] = b.L[sel] + d
      moved = d
      self.effort = U.damp(self.effort, 0, 10, dt)
    end
    self.turns = self.turns + abs(ch) / 360
  else
    self.effort = U.damp(self.effort, 0, 4, dt)
  end
  if straining then
    self.strain = min(1, self.strain + dt * 6)
    self.stallT = self.stallT + dt
  else
    self.strain = max(0, self.strain - dt * 4)
    if ch <= 0 or not straining then self.stallT = max(0, self.stallT - dt * 2) end
  end
  -- drum turns with the line; pawls click as it turns in the haul direction
  local drumTurn = -moved / DRUM_CIRC
  self.drumDeg = (self.drumDeg + drumTurn * 360) % 360
  self.pawl = self.pawl + abs(drumTurn) * 12
  local clicks = 0
  while self.pawl >= 1 do
    self.pawl = self.pawl - 1
    if clicks < 2 then
      local load = b.T[sel] / self.cap[LOW]
      if moved < 0 then
        if self.gear == HIGH then
          Audio.play(Audio.SQUARE, 2300 - load * 500, 0.12 + load * 0.1, 0.008, 0.001, 0.012, 0, 0.01)
        else
          Audio.play(Audio.SQUARE, 1250 - load * 350, 0.16 + load * 0.12, 0.012, 0.001, 0.02, 0, 0.01)
          Audio.sfx.click(0.12)
        end
      else
        Audio.play(Audio.TRIANGLE, 700, 0.06, 0.01)
      end
    end
    clicks = clicks + 1
  end
end

------------------------------------------------------------------------
-- physics
------------------------------------------------------------------------
function Winch:physics(dt)
  local b = self.b
  local tws, twd, gust = self:windAt(b.x, b.y)
  b.tws, b.twd, b.gust = tws, twd, gust
  local hr = rad(b.hd)
  local fx, fy = sin(hr), -cos(hr)
  local tr = rad(twd)
  -- apparent wind (knots): true wind minus boat velocity
  local ax = -sin(tr) * tws - fx * b.v
  local ay = cos(tr) * tws - fy * b.v
  local aws = sqrt(ax * ax + ay * ay)
  local awa = angleDiff(b.hd, deg(atan(-ax, ay)))
  b.awa, b.aws = awa, aws
  b.twa = angleDiff(b.hd, twd)

  local absA = abs(awa)
  local wside = awa >= 0 and 1 or -1         -- wind from starboard = +1
  -- heeling spills wind from the sails
  local q = aws * aws * cos(rad(b.heel))
  if b.knock > 0 then q = q * 0.25 end
  local beta = rad(absA)
  local sb, cb = sin(beta), cos(beta)

  -- MAIN: sheet limits the boom angle, the wind pushes it out to it
  local freeM = absA < 85 and absA or 85
  local dM = mainDelta(b.L[MAIN])
  local aM = dM < freeM and dM or freeM
  local alphaM = absA - aM
  local clM, cdM = liftC(alphaM), dragC(alphaM)
  local qm = q * AREA_MAIN
  local drive = qm * (clM * sb - cdM * cb)
  local side = qm * (clM * cb + cdM * sb)
  local fM = qm * sqrt(clM * clM + cdM * cdM)
  b.T[MAIN] = (dM < freeM) and fM * 0.55 or fM * 0.04
  b.aM, b.alphaM = aM, alphaM
  b.stM = (dM < freeM) and sailState(alphaM, aM >= 84.5) or ((freeM >= 85 and absA > 112) and ST_DRAW or ST_LUFF)

  -- JIB: leeward sheet trims it; a tight windward sheet backs it
  local lee = wside > 0 and JIB_P or JIB_S
  local win = 4 - lee
  b.lee = lee
  local freeJ = absA < 84 and absA or 84
  local dLee = jibDelta(b.L[lee])
  local dWin = jibDelta(b.L[win]) - 22
  local aJ, bind = freeJ, 0
  if dLee < aJ then aJ, bind = dLee, lee end
  if dWin < aJ then aJ, bind = dWin, win end
  local qj = q * AREA_JIB
  if absA > 140 then qj = qj * max(0.3, 1 - (absA - 140) / 40 * 0.7) end -- blanketed by the main
  local backYaw = 0
  b.T[JIB_P], b.T[JIB_S] = 0, 0
  if aJ < -1 then
    -- backed: the wind presses on the wrong side of the jib
    local cd = 0.9
    drive = drive - qj * cd * cb
    side = side + qj * cd * sb
    backYaw = qj * cd
    b.T[win] = qj * cd * 0.5
    b.alphaJ = -1
    b.stJ = ST_BACK
    b.backed = true
  else
    local alphaJ = absA - aJ
    local clJ, cdJ = liftC(alphaJ), dragC(alphaJ)
    drive = drive + qj * (clJ * sb - cdJ * cb)
    side = side + qj * (clJ * cb + cdJ * sb)
    local fJ = qj * sqrt(clJ * clJ + cdJ * cdJ)
    if bind ~= 0 then b.T[bind] = fJ * 0.5 else b.T[lee] = fJ * 0.04 end
    b.alphaJ = alphaJ
    b.stJ = bind ~= 0 and sailState(alphaJ, aJ >= 83.5) or ((freeJ >= 84 and absA > 112) and ST_DRAW or ST_LUFF)
    b.backed = false
  end
  b.aJ = aJ
  drive = drive - q * WINDAGE * cb
  b.drive, b.side = drive, side

  -- display angles swing toward their targets (fast when crossing over)
  local tB = -wside * aM
  local rateB = (tB * b.boom < 0) and 420 or 160
  b.boom = U.approach(b.boom, tB, rateB * dt)
  local tJ = -wside * aJ
  b.jib = U.approach(b.jib, tJ, ((tJ * b.jib < 0) and 500 or 200) * dt)

  -- heel: side force against the keel's righting moment
  local heelT = deg(atan(side > 0 and side or 0, self.righting))
  if b.knock > 0 then heelT = 30 + 40 * (b.knock / 2.5) end
  -- roll: a sprung, damped mass, so a sudden gust overshoots
  b.heelV = b.heelV + ((heelT - b.heel) * 9 - b.heelV * 3.2) * dt
  b.heel = clamp(b.heel + b.heelV * dt, -5, 80)

  -- speed: drive against hull, wave-making, keel induced and rudder drag
  local v = b.v
  local ind = 0
  if drive > 0 then ind = min(IND_C * side * side / (v * v + 1.5), drive * 0.85) end
  local hull = HULL_C1 * v * abs(v)
  if v > HULL_V then hull = hull + HULL_C2 * (v - HULL_V) * (v - HULL_V) end
  local rud = abs(b.rudder) * v * abs(v) * 1.8
  local heelDrag = b.heel > 25 and (b.heel - 25) * 0.9 * v or 0
  local acc = (drive - ind - hull - rud - heelDrag) / MASS
  b.v = clamp(v + acc * dt, -1, 14)

  -- steering: rudder needs flow; heel adds weather helm; a backed jib
  -- pushes the bow away from the wind
  local steer = 7 + 5.5 * abs(b.v)
  if b.heel > 30 then steer = steer * max(0.2, 1 - (b.heel - 30) / 25) end
  local rate = b.rudder * steer * (b.v >= -0.1 and 1 or -1)
  if b.heel > 22 then rate = rate + wside * (b.heel - 22) * 1.4 end
  if backYaw > 0 then rate = rate - wside * min(22, backYaw * 0.06) end
  if b.knock > 0 then rate = rate + wside * 12 end
  rate = clamp(rate, -70, 70)
  b.turn = rate
  b.hd = (b.hd + rate * dt) % 360
  b.x = b.x + fx * b.v * KN * dt
  b.y = b.y + fy * b.v * KN * dt
end

------------------------------------------------------------------------
-- events: tacks, gybes, knockdowns, cast-off lines
------------------------------------------------------------------------
function Winch:events(dt)
  local b = self.b
  -- lines running free after a cast-off
  local running = 0
  for i = 1, 3 do
    if b.run[i] then
      local rate = 4 + b.T[i] * 0.03
      b.L[i] = b.L[i] + rate * dt
      running = max(running, rate)
      if b.L[i] >= LMAX[i] then b.L[i] = LMAX[i] b.run[i] = false Audio.sfx.thud(0.2) end
    end
  end
  self.runRate = running

  local twa = b.twa
  local s = twa > 5 and 1 or (twa < -5 and -1 or 0)
  if s ~= 0 and s ~= b.tackSide then
    if abs(twa) < 90 then self:onTack() else self:onGybe() end
    b.tackSide = s
  end
  self.sinceTack = self.sinceTack + dt
  if self.tackWatch and self.sinceTack < 5 and b.stJ == ST_DRAW and not b.backed
    and (b.awa >= 0) == (b.twa >= 0) and abs(b.twa) < 90 then
    self.tackWatch = false
    self:award("tack")
    if not self.tut then self:say("CLEAN TACK", 1.2) end
  elseif self.tackWatch and self.sinceTack >= 5 then
    self.tackWatch = false
  end

  -- knockdown
  if b.knock > 0 then
    b.knock = b.knock - dt
    if b.knock <= 0 then b.knock = 0 end
  elseif not self.tut and b.heel > self.knockHeel then
    b.knock = 2.5
    b.v = b.v * 0.35
    self.knocks = self.knocks + 1
    self:shake(8)
    self:flash(2)
    Audio.sfx.splash(0.9)
    Audio.sfx.thud(0.8)
    self:burst(14)
    if self.endless then
      self.strikes = self.strikes + 1
      self:say(self.strikes >= 3 and "CAPSIZED" or "KNOCKDOWN!  EASE IN GUSTS", 2)
    else
      self.penalty = self.penalty + 400
      self:say("KNOCKDOWN!  EASE IN GUSTS", 2)
    end
  end

end

function Winch:onTack()
  local b = self.b
  self.tacks = self.tacks + 1
  self.sinceTack = 0
  self.tackWatch = true
  Audio.sfx.whoosh(0.3)
  if not self.tut then
    local old = 4 - b.lee
    if b.L[old] < 4 then self:say("TACK!  HOLD B: CAST OFF", 1.6) else self:say("TACK!  GRIND!", 1.2) end
  end
end

function Winch:onGybe()
  local b = self.b
  self.gybes = self.gybes + 1
  local sev = b.aM
  if b.aws < 3 then sev = sev * 0.3 end
  if sev > 40 then
    self.crashes = self.crashes + 1
    if not self.endless then self.penalty = self.penalty + 300 end
    b.v = b.v * 0.55
    b.heel = min(60, b.heel + 18)
    self:shake(7)
    self:flash(1)
    Audio.sfx.clank(0.9)
    Audio.sfx.thud(0.9)
    self:burst(10)
    self:say("CRASH GYBE!  MAIN IN FIRST", 2)
  elseif sev > 24 then
    self:shake(3)
    Audio.sfx.clack(0.7)
    self:say("HARD GYBE", 1.2)
  else
    Audio.sfx.whoosh(0.3)
    Audio.sfx.clack(0.3)
    self:award("gybe")
    self:say("GYBE-HO!", 1.2)
  end
end

------------------------------------------------------------------------
-- rival
------------------------------------------------------------------------
function Winch:updateRival(dt)
  local r = self.rival
  local tws, twd = self:windAt(r.x, r.y)
  local want = r.hd
  if not r.done then
    local mx, my
    if r.mark <= 3 then mx, my = COURSE[r.mark * 2 - 1], COURSE[r.mark * 2]
    else mx, my = 0, FIN_Y - 40 end
    local brg = compass(mx - r.x, my - r.y)
    local rel = angleDiff(twd, brg)
    local ar = abs(rel)
    if ar < LAY - (r.direct and 5 or 0) then
      r.direct = false
      want = twd - r.tack * LAY
    elseif ar > RUN_TWA + (r.direct and 6 or 0) then
      r.direct = false
      want = twd - r.tack * RUN_TWA
    else
      r.direct = true
      want = brg
    end
  end
  local d = angleDiff(r.hd, want)
  local step = 36 * dt
  r.hd = (r.hd + clamp(d, -step, step)) % 360
  local twa = angleDiff(r.hd, twd)
  local s = twa > 5 and 1 or (twa < -5 and -1 or 0)
  if s ~= 0 and s ~= r.tack then
    r.tack = s
    r.v = r.v * (abs(twa) < 90 and 0.55 or 0.85)
  end
  local target = polar(twa) * (tws / 12) ^ 0.7 * self.skill
  if r.done then target = 1 end
  r.v = r.v + (target - r.v) * min(1, dt * 0.45)
  local hr = rad(r.hd)
  r.prevY = r.y
  r.x = r.x + sin(hr) * r.v * KN * dt
  r.y = r.y - cos(hr) * r.v * KN * dt
  r.boom = U.approach(r.boom, -s * clamp(abs(twa) - 38, 6, 80), 200 * dt)
  if not r.done then
    if r.mark <= 3 then
      local dx, dy = r.x - COURSE[r.mark * 2 - 1], r.y - COURSE[r.mark * 2]
      if dx * dx + dy * dy < ROUND_R * ROUND_R then r.mark = r.mark + 1 end
    elseif r.prevY > FIN_Y and r.y <= FIN_Y and abs(r.x) <= FIN_HALF then
      r.done = true
      r.finT = self.raceT
      if not self.done then
        self:say("THE RIVAL HAS FINISHED", 2)
        Audio.sfx.horn(0.4, 0.3)
      end
    end
  end
end

------------------------------------------------------------------------
-- course progress & scoring
------------------------------------------------------------------------
function Winch:spawnBuoy()
  local rng = self.rng
  local a = rng:between(0, 360)
  local dist = rng:between(240, 400)
  self.bx = self.b.x + sin(rad(a)) * dist
  self.by = self.b.y - cos(rad(a)) * dist
  self.buoyUp = abs(angleDiff(self.twdNow, a)) < 60
  self.buoyT = 0
end

function Winch:progress(dt, prevY)
  local b = self.b
  if self.tut or self.done then return end
  if self.endless then
    self.timeLeft = self.timeLeft - dt
    self.buoyT = self.buoyT + dt
    local dx, dy = b.x - self.bx, b.y - self.by
    if dx * dx + dy * dy < 40 * 40 then
      self.buoys = self.buoys + 1
      local pts = 100 + (self.buoyUp and 60 or 0) + (self.buoyT < 25 and 40 or 0)
      self.score = self.score + pts
      self.timeLeft = self.timeLeft + (self.difficulty >= 3 and 20 or 24)
      self.tws0 = min(self.tws0 + 0.5, 11 + self.difficulty * 2 + 6)
      self.gustMax = min(self.gustMax + 0.02, 0.85)
      Audio.sfx.bell(1100, 0.5)
      Audio.sfx.coin()
      self:say(self.buoyUp and "BUOY!  UPWIND BONUS" or "BUOY!", 1.4)
      if self.buoys >= 12 then self:award("patrol") end
      self:spawnBuoy()
    end
    if self.timeLeft <= 0 or self.strikes >= 3 then
      self.timeLeft = max(0, self.timeLeft)
      self:endRun()
    end
    return
  end
  self.raceT = self.raceT + dt
  if self.mark <= 3 then
    local mx, my = COURSE[self.mark * 2 - 1], COURSE[self.mark * 2]
    local dx, dy = b.x - mx, b.y - my
    if dx * dx + dy * dy < ROUND_R * ROUND_R then
      self.mark = self.mark + 1
      Audio.sfx.bell(880, 0.5)
      if self.mark == 2 then self:say("MARK 1!  BEAR AWAY, EASE", 1.8)
      elseif self.mark == 3 then self:say("MARK 2!  GYBE: MAIN IN FIRST", 2.2)
      else self:say("MARK 3!  HARDEN UP, BEAT HOME", 2) end
    end
  elseif prevY > FIN_Y and b.y <= FIN_Y and abs(b.x) <= FIN_HALF then
    self:endRun()
    return
  end
  if self.raceT >= RACE_LIMIT then self:endRun() end
end

function Winch:endRun()
  if self.done then return end
  self.done = true
  self.whirrHum:stop()
  self.strainHum:stop()
  local turns = floor(self.turns)
  self:statAdd("tacks", self.tacks)
  self:statAdd("turns", turns)
  if turns >= 120 and not self.endless then self:award("grinder") end
  if self.endless then
    self:statMax("buoys", self.buoys)
    Audio.sfx.fail()
    self:finish({ success = self.buoys > 0, score = self.score,
      title = self.strikes >= 3 and "CAPSIZED" or "PATROL OVER",
      lines = { "Buoys collected: " .. self.buoys, "Knockdowns: " .. self.strikes .. "/3",
        "Tacks: " .. self.tacks .. "   Gybes: " .. self.gybes }, delay = 2.2 })
    return
  end
  local t = self.raceT
  if t >= RACE_LIMIT then
    local sc = (self.mark - 1) * 500
    Audio.sfx.fail()
    self:finish({ success = false, score = sc, title = "DID NOT FINISH",
      lines = { "Marks rounded: " .. (self.mark - 1) .. "/3", "The committee went home." }, delay = 2 })
    return
  end
  local r = self.rival
  local won = not r.done
  local timeBonus = floor(max(0, 300 - t) * 25)
  local sc = max(0, 2500 + timeBonus + (won and 2000 or 0) - self.penalty)
  self.score = sc
  self:statAdd("wins", won and 1 or 0)
  local rec = Save.machine(self.def.id).stats
  local tenths = floor(t * 10)
  if not rec.fastest or rec.fastest == 0 or tenths < rec.fastest then rec.fastest = tenths Save.markDirty() end
  if won then self:award("win") Audio.sfx.success() else Audio.sfx.bell(660, 0.5) end
  Audio.sfx.horn(0.5, 0.5)
  local gap = won and (r.done and 0 or 1) or (t - r.finT)
  self:finish({ success = true, score = sc,
    title = won and "LINE HONOURS" or "FINISHED 2ND",
    lines = {
      string.format("Time %d:%04.1f  +%d", floor(t) // 60, t % 60, timeBonus),
      won and "Beat the rival: +2000" or string.format("Rival ahead by %.1fs", gap),
      "Tacks " .. self.tacks .. "  gybes " .. self.gybes .. "  turns " .. turns,
      "Penalties -" .. self.penalty .. " (" .. self.crashes .. " crash, " .. self.knocks .. " knock)",
    }, delay = 2.5 })
end

------------------------------------------------------------------------
-- fx
------------------------------------------------------------------------
function Winch:spray(x, y, vx, vy, life)
  self.spI = self.spI % NSPRAY + 1
  local i = self.spI
  self.spX[i], self.spY[i], self.spVX[i], self.spVY[i], self.spL[i] = x, y, vx, vy, life
end

function Winch:burst(n)
  local b = self.b
  local rng = self.rng
  for _ = 1, n do
    local a = rng:between(0, 6.28)
    local s = rng:between(20, 60)
    self:spray(b.x + rng:between(-10, 10), b.y + rng:between(-10, 10), sin(a) * s, cos(a) * s, rng:between(0.4, 0.9))
  end
end

function Winch:updateFx(dt)
  local b = self.b
  local rng = self.rng
  -- bow spray: speed, heel and gusts throw water
  local hr = rad(b.hd)
  local fx, fy = sin(hr), -cos(hr)
  local rate = max(0, b.v - 3.2) * (1 + b.heel / 25) * (1 + b.gust) * 3
  if rng:chance(min(0.9, rate * dt)) then
    local side = rng:chance(0.5) and 1 or -1
    local bx, by = b.x + fx * 16, b.y + fy * 16
    local sp = 10 + b.v * 4
    self:spray(bx + fy * side * -5, by - fx * side * -5,
      -fy * side * sp + fx * b.v * 2, fx * side * sp + fy * b.v * 2, rng:between(0.3, 0.6))
  end
  for i = 1, NSPRAY do
    local l = self.spL[i]
    if l > 0 then
      self.spL[i] = l - dt
      self.spX[i] = self.spX[i] + self.spVX[i] * dt
      self.spY[i] = self.spY[i] + self.spVY[i] * dt
      self.spVX[i] = self.spVX[i] * 0.94
      self.spVY[i] = self.spVY[i] * 0.94
    end
  end
  -- wake samples
  self.wkT = self.wkT + dt
  for i = 1, NWAKE do self.wkA[i] = self.wkA[i] + dt end
  if self.wkT > 0.12 then
    self.wkT = 0
    if b.v > 0.6 then
      self.wkI = self.wkI % NWAKE + 1
      local i = self.wkI
      self.wkX[i], self.wkY[i], self.wkH[i], self.wkA[i] = b.x - fx * 17, b.y - fy * 17, b.hd, 0
    end
  end
  -- camera with a little look-ahead
  self.camX = U.damp(self.camX, b.x + fx * b.v * 5, 3, dt)
  self.camY = U.damp(self.camY, b.y + fy * b.v * 5, 3, dt)
  self.gearFlash = max(0, self.gearFlash - dt)
  if self.msgT > 0 then self.msgT = self.msgT - dt end
end

function Winch:updateAudio(dt)
  local b = self.b
  if self.done then
    self.windHum:set(200 + b.aws * 10, 0.03)
    return
  end
  self.windHum:set(180 + b.aws * 14 + b.gust * 120, 0.025 + b.aws * 0.0025 + max(0, b.gust) * 0.08)
  local s = self.strain
  if s > 0.05 then
    self.strainHum:set(46 + s * 18 + sin(self.t * 23) * 4, s * 0.28)
  else
    self.strainHum:set(0, 0)
  end
  if self.runRate > 0 then
    self.whirrHum:set(320 + self.runRate * 70, 0.12)
  else
    self.whirrHum:set(0, 0)
  end
  -- luffing sails flutter: rapid little bursts of noise
  local luff = (b.stM == ST_LUFF and b.aws > 4 and 1 or 0) + (b.stJ == ST_LUFF and b.aws > 4 and 1 or 0)
  if luff > 0 then
    self.flapT = self.flapT - dt
    if self.flapT <= 0 then
      self.flapT = 1 / (6 + b.aws * 0.5)
      Audio.play(Audio.NOISE, 700 + b.aws * 30, 0.05 + luff * 0.04, 0.02, 0.001, 0.03, 0, 0.01)
    end
  end
end

------------------------------------------------------------------------
-- frame
------------------------------------------------------------------------
function Winch:update(dt)
  self.t = self.t + dt
  local b = self.b
  local prevY = b.y
  self:updateWind(dt)
  if self.finished or self.done then
    b.rudder = U.approach(b.rudder, 0, 5 * dt)
    self.crankIn = 0
    self.strain = 0
  else
    local ax = Input.axisX()
    if b.knock > 0 then ax = 0 end
    b.rudder = U.approach(b.rudder, ax, (ax == 0 and 5 or 3.2) * dt)
    if self.bDown then
      self.bT = self.bT + dt
      if self.bT >= 0.35 and not self.bCast then
        self.bCast = true
        self:castOff(self.sel)
      end
    end
    local ch = self.crankIn
    self.crankIn = 0
    self:winch(ch, dt)
  end
  self:physics(dt)
  self:events(dt)
  if self.rival then self:updateRival(dt) end
  self:updateFx(dt)
  self:updateAudio(dt)
  self:progress(dt, prevY)
end

------------------------------------------------------------------------
-- drawing
------------------------------------------------------------------------
-- quadratic curve from (x0,y0) to (x1,y1) bulging along (nx,ny)*bulge
local function curve(x0, y0, x1, y1, nx, ny, bulge)
  local cx, cy = (x0 + x1) * 0.5 + nx * bulge * 2, (y0 + y1) * 0.5 + ny * bulge * 2
  local px, py = x0, y0
  for k = 1, 4 do
    local t = k * 0.25
    local u = 1 - t
    local x = u * u * x0 + 2 * u * t * cx + t * t * x1
    local y = u * u * y0 + 2 * u * t * cy + t * t * y1
    gfx.drawLine(px, py, x, y)
    px, py = x, y
  end
end

-- A triangular sail in the oblique view: tack, head, clew. The foot bellies
-- to leeward; a luffing sail collapses and its leech flogs; a stalled one
-- hooks its leech; a backed one shows its grey other side.
local function drawSail(tx, ty, hx, hy, cx, cy, rx, ry, side, state, t, rival)
  local dx, dy = cx - tx, cy - ty
  local len = sqrt(dx * dx + dy * dy)
  if len < 1 then return end
  local nx, ny = -dy / len, dx / len
  if (nx * rx + ny * ry) * side < 0 then nx, ny = -nx, -ny end
  local lx, ly = cx - hx, cy - hy
  local ll = sqrt(lx * lx + ly * ly)
  if ll < 1 then return end
  local qx, qy = -ly / ll, lx / ll
  if (qx * rx + qy * ry) * side < 0 then qx, qy = -qx, -qy end
  if state == ST_LUFF then
    local f = sin(t * 31)
    local px, py = cx - dx * 0.25 + nx * f * 3, cy - dy * 0.25 + ny * f * 3
    gfx.setColor(gfx.kColorWhite)
    gfx.fillTriangle(tx, ty, hx, hy, px, py)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(tx, ty, hx, hy)
    curve(hx, hy, cx, cy, qx, qy, 4 * f)
    curve(tx, ty, cx, cy, nx, ny, -3 * f)
    gfx.drawLine(hx, hy, (tx + cx) * 0.5 + nx * f * 4, (ty + cy) * 0.5 + ny * f * 4)
    return
  end
  if state == ST_BACK then gfx.setPattern(Art.pat.gray50)
  elseif rival then gfx.setPattern(Art.pat.gray12)
  else gfx.setColor(gfx.kColorWhite) end
  gfx.fillTriangle(tx, ty, hx, hy, cx, cy)
  local bulge = state == ST_STALL and 6 or 4
  if state == ST_BACK then bulge = -4 end
  -- belly of the foot, filled
  gfx.setLineWidth(3)
  curve(tx, ty, cx, cy, nx, ny, bulge * 0.5)
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(rival and 1 or 2)
  curve(tx, ty, cx, cy, nx, ny, bulge)
  curve(hx, hy, cx, cy, qx, qy, state == ST_STALL and -3 or 1.5)
  gfx.setLineWidth(1)
  gfx.drawLine(tx, ty, hx, hy)
  if not rival then
    -- a seam showing where the draft sits
    local sx, sy = (tx + hx) * 0.5, (ty + hy) * 0.5
    curve(sx, sy, cx, cy, qx, qy, state == ST_STALL and 3 or 2)
  end
end

local MAST_H <const> = 22                 -- mast height (hull units), drawn obliquely

function Winch:drawBoat(style, x, y, hd, heel, boom, jib, stM, stJ, lee, awa)
  local hr = rad(hd)
  local fx, fy, rx, ry = sin(hr) * BS, -cos(hr) * BS, cos(hr) * BS, sin(hr) * BS
  hullImage(style, hd):draw(x - HIMG / 2, y - HIMG / 2)
  local t = self.t
  -- mast: rises "up" the screen; heel leans the masthead to leeward
  local hrad = rad(heel)
  local mx, my = x + fx * 6, y + fy * 6
  local lean = sin(hrad) * MAST_H * lee
  local hx, hy = mx + rx * lean, my + ry * lean - MAST_H * BS * cos(hrad) * 0.85
  -- boom end (main clew)
  local ba = rad(boom)
  local bl, bc = 6 - 17 * cos(ba), 17 * sin(ba)
  local ex, ey = x + fx * bl + rx * bc, y + fy * bl + ry * bc
  -- jib: tack at the stemhead, head 80% up the mast, clew on its sheet
  local ja = rad(jib)
  local jl, jc = 19 - 15 * cos(ja), 15 * sin(ja)
  local cx, cy = x + fx * jl + rx * jc, y + fy * jl + ry * jc
  local sx, sy = x + fx * 19, y + fy * 19
  local jhx, jhy = mx + (hx - mx) * 0.8, my + (hy - my) * 0.8
  gfx.setColor(gfx.kColorBlack)
  if style == 1 then
    -- mainsheet to the traveller; jib sheets: taut to leeward, lazy to windward
    gfx.drawLine(ex, ey, x - fx * 13, y - fy * 13)
    local js = jib >= 0 and 1 or -1
    gfx.drawLine(cx, cy, x - fx * 3 + rx * 7 * js, y - fy * 3 + ry * 7 * js)
    local lx, ly = x - fx * 3 - rx * 7 * js, y - fy * 3 - ry * 7 * js
    local mx2, my2 = (cx + lx) * 0.5 - fx * 3, (cy + ly) * 0.5 - fy * 3
    gfx.setPattern(Art.pat.gray50)
    gfx.drawLine(cx, cy, mx2, my2)
    gfx.drawLine(mx2, my2, lx, ly)
    gfx.setColor(gfx.kColorBlack)
  end
  gfx.setLineWidth(2)
  gfx.drawLine(mx, my, ex, ey)
  gfx.setLineWidth(1)
  -- nearer sail (lower on screen) is drawn last
  local jibFirst = sy < my
  if jibFirst then drawSail(sx, sy, jhx, jhy, cx, cy, rx, ry, jib >= 0 and 1 or -1, stJ, t + 0.7, style == 2) end
  drawSail(mx, my, hx, hy, ex, ey, rx, ry, boom >= 0 and 1 or -1, stM, t, style == 2)
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(2)
  gfx.drawLine(mx, my, hx, hy)
  gfx.setLineWidth(1)
  if not jibFirst then drawSail(sx, sy, jhx, jhy, cx, cy, rx, ry, jib >= 0 and 1 or -1, stJ, t + 0.7, style == 2) end
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(hx, hy, 2)
  if awa then
    -- masthead wind indicator streams with the apparent wind
    local wa = rad(hd + awa + 180)
    gfx.drawLine(hx, hy, hx + sin(wa) * 9, hy - cos(wa) * 9)
    gfx.fillCircleAtPoint(hx + sin(wa) * 9, hy - cos(wa) * 9, 1)
  end
end

function Winch:drawSea()
  local b = self.b
  local ox, oy = SEA_CX - self.camX, self.seaCY - self.camY
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(0, 18, SEA_W, 204)
  -- gust patches: darker ripple fields
  local P = self.patches
  for i = 1, NPATCH do
    local p = P[i]
    if p.on and p.g > 0 then
      local sx, sy = p.x + ox, p.y + oy
      local r = p.r * min(1, p.age / 1.5 + 0.3)
      if sx > -r and sx < SEA_W + r and sy > 18 - r and sy < 222 + r then
        gfx.setPattern(Art.pat.gray12)
        gfx.fillCircleAtPoint(sx, sy, r)
        if p.g > 0.3 then
          gfx.setPattern(p.g > 0.5 and Art.pat.gray50 or Art.pat.gray25)
          gfx.fillCircleAtPoint(sx, sy, r * 0.55)
        end
      end
    end
  end
  -- ripples (world-anchored tile)
  local tile = seaTile()
  local tx0 = floor(ox) % 128 - 128
  local ty0 = floor(oy) % 128 - 128
  for tx = tx0, SEA_W, 128 do
    for ty = ty0, 222, 128 do tile:draw(tx, ty) end
  end
  -- lulls: glassy calm patches
  gfx.setColor(gfx.kColorWhite)
  for i = 1, NPATCH do
    local p = P[i]
    if p.on and p.g < 0 then
      local sx, sy = p.x + ox, p.y + oy
      local r = p.r * 0.7
      if sx > -r and sx < SEA_W + r and sy > 18 - r and sy < 222 + r then
        gfx.fillCircleAtPoint(sx, sy, r)
      end
    end
  end
  -- cat's-paw streaks along the wind
  gfx.setColor(gfx.kColorBlack)
  local tr = rad(self.twdNow)
  local wx, wy = -sin(tr), cos(tr)
  local S = self.streaks
  for i = 1, NSTREAK do
    local sx, sy = S[i * 2 - 1] + ox, S[i * 2] + oy
    if sx > 0 and sx < SEA_W and sy > 18 and sy < 222 then
      local l = 5 + (i % 3) * 3
      gfx.drawLine(sx, sy, sx + wx * l, sy + wy * l)
    end
  end
  self:drawCourse(ox, oy)
  -- wake: a widening V of foam behind the stern
  local n = NWAKE
  for k = 0, n - 2 do
    local i = (self.wkI - 1 - k) % n + 1
    local j = (self.wkI - 2 - k) % n + 1
    local ai, aj = self.wkA[i], self.wkA[j]
    if ai < 2.2 and aj < 2.2 and k % 2 == 0 then
      local hi, hj = rad(self.wkH[i]), rad(self.wkH[j])
      local si, sj = 2 + ai * 7, 2 + aj * 7
      local xi, yi = self.wkX[i] + ox, self.wkY[i] + oy
      local xj, yj = self.wkX[j] + ox, self.wkY[j] + oy
      gfx.drawLine(xi + cos(hi) * si, yi + sin(hi) * si, xj + cos(hj) * sj, yj + sin(hj) * sj)
      gfx.drawLine(xi - cos(hi) * si, yi - sin(hi) * si, xj - cos(hj) * sj, yj - sin(hj) * sj)
    end
  end
  -- rival
  local r = self.rival
  if r then
    local sx, sy = r.x + ox, r.y + oy
    if sx > -30 and sx < SEA_W + 30 and sy > -10 and sy < 250 then
      local twa = angleDiff(r.hd, self.twdNow)
      self:drawBoat(2, sx, sy, r.hd, min(20, r.v * 3), r.boom, r.boom * 0.8, ST_DRAW, ST_DRAW, twa >= 0 and -1 or 1)
    end
  end
  -- the boat
  local bsx, bsy = b.x + ox, b.y + oy
  self:drawBoat(1, bsx, bsy, b.hd, b.heel, b.boom, b.jib, b.stM, b.stJ, b.awa >= 0 and -1 or 1, b.awa)
  -- spray
  gfx.setColor(gfx.kColorBlack)
  for i = 1, NSPRAY do
    if self.spL[i] > 0 then
      local s = self.spL[i] > 0.3 and 2 or 1
      gfx.fillRect(self.spX[i] + ox, self.spY[i] + oy, s, s)
    end
  end
end

local function dashed(x0, y0, x1, y1, dash)
  local dx, dy = x1 - x0, y1 - y0
  local len = sqrt(dx * dx + dy * dy)
  if len < 1 then return end
  local n = min(60, floor(len / (dash * 2)))
  local ux, uy = dx / len * dash, dy / len * dash
  for k = 0, n do
    local x, y = x0 + ux * k * 2, y0 + uy * k * 2
    gfx.drawLine(x, y, x + ux, y + uy)
  end
end

local function buoy(sx, sy, big)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(sx, sy, big and 6 or 5)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(sx, sy, 2)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawLine(sx, sy - 2, sx, sy - 12)
  gfx.fillRect(sx + 1, sy - 12, 6, 4)
end

function Winch:markPos()
  if self.endless then return self.bx, self.by end
  if self.mark <= 3 then return COURSE[self.mark * 2 - 1], COURSE[self.mark * 2] end
  return 0, FIN_Y
end

function Winch:drawCourse(ox, oy)
  if self.tut then return end
  gfx.setColor(gfx.kColorBlack)
  local mx, my = self:markPos()
  -- laylines from an upwind mark
  local brg = compass(mx - self.b.x, my - self.b.y)
  if abs(angleDiff(self.twdNow, brg)) < 70 then
    local sx, sy = mx + ox, my + oy
    for k = -1, 1, 2 do
      local a = rad(self.twdNow + 180 + k * LAY)
      dashed(sx, sy, sx + sin(a) * 520, sy - cos(a) * 520, 4)
    end
  end
  if self.endless then
    local sx, sy = self.bx + ox, self.by + oy
    buoy(sx, sy, true)
    gfx.drawCircleAtPoint(sx, sy, 10 + (self.t * 8) % 8)
    return
  end
  -- finish line & committee boat
  local fy = FIN_Y + oy
  gfx.setPattern(Art.pat.gray50)
  gfx.drawLine(-FIN_HALF + ox, fy, FIN_HALF + ox, fy)
  gfx.setColor(gfx.kColorBlack)
  dashed(-FIN_HALF + ox, fy, FIN_HALF + ox, fy, 3)
  buoy(-FIN_HALF + ox, fy, false)
  gfx.fillRect(FIN_HALF + ox - 6, fy - 4, 14, 8)
  gfx.drawLine(FIN_HALF + ox, fy - 4, FIN_HALF + ox, fy - 16)
  gfx.fillRect(FIN_HALF + ox + 1, fy - 16, 7, 5)
  for i = 1, 3 do
    local sx, sy = COURSE[i * 2 - 1] + ox, COURSE[i * 2] + oy
    if sx > -20 and sx < SEA_W + 20 and sy > 0 and sy < 240 then
      buoy(sx, sy, i == self.mark)
      if i == self.mark then gfx.drawCircleAtPoint(sx, sy, 10 + (self.t * 8) % 8) end
      Art.haloText(UI.bold, MARK_LABEL[i], sx + 8, sy - 6)
    end
  end
end

-- tell-tale streamers: windward lifts when luffing, leeward curls when stalled
local function telltale(x, y, state, t)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(x, y, 2, 14)
  local f = floor(t * 12) % 2
  if state == ST_LUFF or state == ST_BACK then
    gfx.drawLine(x + 2, y + 3, x + 6, y + f * 2)
    gfx.drawLine(x + 6, y + f * 2, x + 10, y + 3 - f)
    gfx.drawLine(x + 10, y + 3 - f, x + 14, y + f)
  else
    gfx.drawLine(x + 2, y + 3, x + 15, y + 3)
  end
  if state == ST_STALL or state == ST_BACK then
    gfx.drawLine(x + 2, y + 10, x + 7, y + 10)
    gfx.drawCircleAtPoint(x + 9, y + 9 - f, 2)
  else
    gfx.drawLine(x + 2, y + 10, x + 15, y + 10)
  end
end

function Winch:drawOverlays()
  local b = self.b
  -- tell-tales box
  local x, y = 4, 22
  local bh = self.tut and 58 or 40
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x, y, 118, bh)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(x, y, 118, bh)
  if self.tut then
    -- the lesson covers the HUD's speed readout
    UI.text("SPEED", x + 4, y + 38)
    UI.text(U.cached("w_spd", "%.1f", floor(b.v * 10 + 0.5) / 10), x + 58, y + 38, "left", UI.bold)
  end
  UI.text("JIB", x + 4, y + 2)
  telltale(x + 38, y + 3, b.stJ, self.t)
  UI.text(ST_NAME[b.stJ], x + 58, y + 2, "left", b.stJ == ST_DRAW and UI.bold or UI.font)
  UI.text("MAIN", x + 4, y + 20)
  telltale(x + 38, y + 21, b.stM, self.t + 0.3)
  UI.text(ST_NAME[b.stM], x + 58, y + 20, "left", b.stM == ST_DRAW and UI.bold or UI.font)
  -- wind compass: arrow flies downwind from the direction the wind comes from
  local cx, cy, r = 266, 42, 17
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(cx, cy, r)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawCircleAtPoint(cx, cy, r)
  gfx.drawLine(cx, cy - r, cx, cy - r + 4)
  local a = rad(b.twd)
  local ux, uy = sin(a), -cos(a)
  local tx, ty = cx + ux * (r - 2), cy + uy * (r - 2)
  local hx, hy = cx - ux * (r - 9), cy - uy * (r - 9)
  gfx.setLineWidth(3)
  gfx.drawLine(tx, ty, hx, hy)
  gfx.setLineWidth(1)
  gfx.fillTriangle(hx + uy * 5, hy - ux * 5, hx - uy * 5, hy + ux * 5, cx - ux * (r - 1), cy - uy * (r - 1))
  -- the boat's heading as a tick
  local h = rad(b.hd)
  gfx.fillCircleAtPoint(cx + sin(h) * (r - 3), cy - cos(h) * (r - 3), 2)
  Art.haloText(UI.bold, U.cached("w_tws", "%d KN", floor(b.tws + 0.5)), cx - 18, cy + r + 1)
  local pos = pointOfSail(b.twa)
  Art.haloText(UI.font, POS_NAME[pos], x + 2, y + bh + 2)
  if b.gust > 0.18 then Art.haloText(UI.bold, "GUST!", 204, 24) end

  -- next-mark pointer when it's off screen
  if not self.tut then
    local mx, my = self:markPos()
    local sx, sy = mx - self.camX + SEA_CX, my - self.camY + self.seaCY
    if sx < 8 or sx > SEA_W - 8 or sy < 26 or sy > 214 then
      -- a bearing pointer on a ring around the boat
      local bx, by = b.x - self.camX + SEA_CX, b.y - self.camY + self.seaCY
      local dx, dy = mx - b.x, my - b.y
      local d = sqrt(dx * dx + dy * dy)
      local ux2, uy2 = dx / d, dy / d
      local px, py = bx + ux2 * 56, by + uy2 * 56
      gfx.setColor(gfx.kColorBlack)
      gfx.fillTriangle(px + ux2 * 9, py + uy2 * 9, px - uy2 * 6, py + ux2 * 6, px + uy2 * 6, py - ux2 * 6)
      gfx.setColor(gfx.kColorWhite)
      gfx.fillCircleAtPoint(px, py, 2)
      local label = U.cached("w_mdist", "%dm", floor(d / 10) * 5)
      local lw = UI.width(label)
      Art.haloText(UI.font, label, px + ux2 * 22 - lw / 2, py + uy2 * 18 - 8)
    end
    self:drawMinimap()
  end
  -- banner
  if self.msgT > 0 and self.msg then
    -- low on the water, clear of the boat and its rig
    local w = UI.width(self.msg) + 20
    local cx = w <= 216 and 174 or SEA_CX
    UI.panel(cx - w / 2, 194, w, 24, "ink")
    UI.textW(self.msg, cx, 198, "center")
  end
end

function Winch:drawMinimap()
  local x, y, w, h = 4, 152, 54, 66
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x, y, w, h)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(x, y, w, h)
  local b = self.b
  local cx, cy, s
  if self.endless then
    cx, cy, s = b.x, b.y, 0.09
  else
    cx, cy, s = -195, -320, 0.068
  end
  local mx0, my0 = x + w / 2, y + h / 2
  if self.endless then
    local bx = clamp(mx0 + (self.bx - cx) * s, x + 3, x + w - 3)
    local by = clamp(my0 + (self.by - cy) * s, y + 3, y + h - 3)
    gfx.fillCircleAtPoint(bx, by, 3)
  else
    local px, py = mx0 + (0 - cx) * s, my0 + (FIN_Y - cy) * s
    gfx.drawLine(px - 5, py, px + 5, py)
    for i = 1, 3 do
      local ax, ay = mx0 + (COURSE[i * 2 - 1] - cx) * s, my0 + (COURSE[i * 2] - cy) * s
      if i == self.mark then gfx.fillCircleAtPoint(ax, ay, 3) else gfx.drawCircleAtPoint(ax, ay, 2) end
    end
    local r = self.rival
    if r then gfx.drawRect(mx0 + (r.x - cx) * s - 1, my0 + (r.y - cy) * s - 1, 3, 3) end
  end
  local bx, by = clamp(mx0 + (b.x - cx) * s, x + 2, x + w - 2), clamp(my0 + (b.y - cy) * s, y + 2, y + h - 2)
  local h2 = rad(b.hd)
  gfx.fillRect(bx - 1, by - 1, 3, 3)
  gfx.drawLine(bx, by, bx + sin(h2) * 5, by - cos(h2) * 5)
end

function Winch:drawHud()
  local b = self.b
  local x0 = 290
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x0, 18, 110, 204)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(x0, 18, 3, 204)
  gfx.setPattern(Art.pat.gray50)
  gfx.fillRect(x0 + 3, 18, 1, 204)

  -- the winch, seen from above: drum with wraps, self-tailer, handle
  local jit = self.strain > 0.3 and ((floor(self.t * 30) % 2) * 2 - 1) or 0
  local dx, dy = 318 + jit, 62
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(dx, dy, 21)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(dx, dy, 19)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(dx, dy, 17)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawCircleAtPoint(dx, dy, 15)
  gfx.drawCircleAtPoint(dx, dy, 12)
  gfx.fillCircleAtPoint(dx, dy, 9)
  gfx.setColor(gfx.kColorBlack)
  local da = rad(self.drumDeg)
  for k = 0, 2 do
    local a = da + k * 2.094
    gfx.drawLine(dx + sin(a) * 3, dy - cos(a) * 3, dx + sin(a) * 9, dy - cos(a) * 9)
  end
  -- the line leading off the drum
  gfx.setLineWidth(2)
  gfx.drawLine(dx - 18, dy + 6, x0 + 5, dy + 22)
  gfx.setLineWidth(1)
  local ha = rad(self.handleDeg)
  local hx, hy = dx + sin(ha) * 24, dy - cos(ha) * 24
  gfx.setLineWidth(4)
  gfx.drawLine(dx, dy, hx, hy)
  gfx.setLineWidth(1)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(hx, hy, 5)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawCircleAtPoint(hx, hy, 5)
  gfx.fillCircleAtPoint(dx, dy, 3)

  -- gear plate
  local gx, gy = 354, 22
  if self.gear == HIGH then
    UI.panel(gx, gy, 44, 18, "ink")
    UI.textW("HIGH", gx + 22, gy + 1, "center", UI.bold)
  else
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(gx, gy, 44, 18)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    gfx.drawRect(gx, gy, 44, 18)
    gfx.setLineWidth(1)
    UI.text("LOW", gx + 22, gy + 1, "center", UI.bold)
  end
  if self.gearFlash > 0 then gfx.drawRect(gx - 2, gy - 2, 48, 22) end

  -- load gauge: hatched = what this gear can't pull
  local lx, ly, lw, lh = 384, 44, 12, 58
  local scale = self.cap[LOW] * 1.35
  local load = b.T[self.sel]
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(lx, ly, lw, lh)
  local capF = self.cap[self.gear] / scale
  local zone = floor(lh * (1 - capF))
  gfx.setPattern(Art.pat.hatch)
  gfx.fillRect(lx, ly, lw, zone)
  gfx.setColor(gfx.kColorBlack)
  local fh = floor((lh - 4) * clamp(load / scale, 0, 1))
  gfx.fillRect(lx + 3, ly + lh - 2 - fh, lw - 6, fh)
  gfx.drawRect(lx, ly, lw, lh)
  gfx.fillRect(lx - 3, ly + zone, lw + 5, 2)
  UI.text("LOAD", lx - 2, ly - 1, "right")
  if self.strain > 0.3 then
    UI.panel(x0 + 6, 86, 56, 18, "ink")
    UI.textW("STALL", x0 + 34, 87, "center", UI.bold)
    if floor(self.t * 8) % 2 == 0 then gfx.drawRect(x0 + 4, 84, 60, 22) end
  end

  -- lines
  local y0 = 106
  gfx.setColor(gfx.kColorBlack)
  gfx.drawLine(x0 + 4, y0 - 2, 400, y0 - 2)
  for i = 1, 3 do
    local y = y0 + (i - 1) * 18
    local sel = i == self.sel
    if sel then
      gfx.fillRect(x0 + 4, y, 106, 17)
    end
    local draw = sel and UI.textW or UI.text
    draw(LINE_NAME[i], x0 + 8, y, "left", sel and UI.bold or UI.font)
    -- sheet out: short = trimmed in, long = eased
    local bx, bw = 350, 46
    gfx.setColor(sel and gfx.kColorWhite or gfx.kColorBlack)
    gfx.drawRect(bx, y + 4, bw, 9)
    local f = b.L[i] / LMAX[i]
    if b.run[i] and floor(self.t * 10) % 2 == 0 then
      gfx.setPattern(Art.pat.gray50)
    end
    gfx.fillRect(bx + 2, y + 6, max(1, floor((bw - 4) * f)), 5)
    gfx.setColor(gfx.kColorBlack)
    -- working jib sheet marker
    if i == b.lee then
      gfx.setColor(sel and gfx.kColorWhite or gfx.kColorBlack)
      gfx.fillTriangle(x0 + 5, y + 5, x0 + 5, y + 11, x0 + 8, y + 8)
      gfx.setColor(gfx.kColorBlack)
    end
  end
  gfx.drawLine(x0 + 4, y0 + 54, 400, y0 + 54)

  -- speed & heel
  local sy = 164
  local spd = U.cached("w_spd", "%.1f", floor(b.v * 10 + 0.5) / 10)
  UI.text(spd, x0 + 8, sy, "left", UI.bold)
  UI.text("KN", x0 + 12 + UI.width(spd, UI.bold), sy)
  UI.text("HEEL", x0 + 8, sy + 20)
  UI.text(U.cached("w_heel", "%d", floor(b.heel + 0.5)), x0 + 8, sy + 36, "left", UI.bold)
  -- inclinometer
  local cx, cy, r = 370, 214, 24
  gfx.setColor(gfx.kColorBlack)
  gfx.drawArc(cx, cy, r, 270, 450)
  gfx.setPattern(Art.pat.gray50)
  gfx.drawArc(cx, cy, r - 2, 270, 450)
  gfx.setColor(gfx.kColorBlack)
  for k = -2, 2 do
    local a = rad(k * 30)
    local r0 = (abs(k) == 1) and r - 7 or r - 4
    gfx.setLineWidth(abs(k) == 1 and 2 or 1)
    gfx.drawLine(cx + sin(a) * r0, cy - cos(a) * r0, cx + sin(a) * r, cy - cos(a) * r)
  end
  gfx.setLineWidth(1)
  local lee = b.awa >= 0 and -1 or 1
  local ha2 = rad(clamp(b.heel, 0, 80) * lee)
  gfx.setLineWidth(2)
  gfx.drawLine(cx, cy, cx + sin(ha2) * (r - 3), cy - cos(ha2) * (r - 3))
  gfx.setLineWidth(1)
  gfx.fillCircleAtPoint(cx, cy, 3)
end

function Winch:draw()
  self:drawSea()
  self:drawOverlays()
  self:drawHud()
  local right = self.hdrStr
  if not self.tut then
    local sec = floor(self.endless and self.timeLeft or self.raceT)
    local key = sec * 10 + (self.endless and self.buoys or self.mark)
    if key ~= self.hdrSec then
      self.hdrSec = key
      if self.endless then
        self.hdrStr = string.format("BUOYS %d  %d:%02d", self.buoys, sec // 60, sec % 60)
      else
        self.hdrStr = string.format("LEG %d/4  %d:%02d", min(4, self.mark), sec // 60, sec % 60)
      end
    end
    right = self.hdrStr
  end
  UI.header(9, "SAILBOAT WINCH", right)
  if not self.tut then UI.hints(HINTS) end
end

------------------------------------------------------------------------
-- suspend / resume
------------------------------------------------------------------------
function Winch:serialize()
  local b = self.b
  local patches = {}
  for i = 1, NPATCH do
    local p = self.patches[i]
    if p.on then patches[#patches + 1] = { x = p.x, y = p.y, r = p.r, g = p.g, sh = p.sh, age = p.age } end
  end
  local st = {
    rng = self.rng:state(), t = self.t, raceT = self.raceT, windT = self.windT,
    tws0 = self.tws0, gustMax = self.gustMax, spawnT = self.spawnT,
    gear = self.gear, sel = self.sel, turns = self.turns,
    boat = { x = b.x, y = b.y, hd = b.hd, v = b.v, heel = b.heel, L = { b.L[1], b.L[2], b.L[3] },
      run = { b.run[1], b.run[2], b.run[3] }, tackSide = b.tackSide, boom = b.boom, jib = b.jib, knock = b.knock },
    mark = self.mark, penalty = self.penalty, crashes = self.crashes, knocks = self.knocks,
    tacks = self.tacks, gybes = self.gybes, score = self.score,
    buoys = self.buoys, strikes = self.strikes, timeLeft = self.timeLeft, buoyT = self.buoyT,
    bx = self.bx, by = self.by, buoyUp = self.buoyUp == true,
    patches = patches,
  }
  local r = self.rival
  if r then
    st.rival = { x = r.x, y = r.y, hd = r.hd, v = r.v, mark = r.mark, tack = r.tack, direct = r.direct,
      done = r.done, finT = r.finT, boom = r.boom, prevY = r.prevY }
  end
  return st
end

function Winch:deserialize(t)
  self.rng:setState(t.rng)
  self.t, self.raceT, self.windT = t.t or 0, t.raceT or 0, t.windT or 0
  self.tws0, self.gustMax, self.spawnT = t.tws0 or self.tws0, t.gustMax or self.gustMax, t.spawnT or 1
  self.gear, self.sel, self.turns = t.gear or HIGH, t.sel or MAIN, t.turns or 0
  local b, s = self.b, t.boat
  if s then
    b.x, b.y, b.hd, b.v, b.heel = s.x, s.y, s.hd, s.v, s.heel
    for i = 1, 3 do
      b.L[i] = s.L[i]
      b.run[i] = s.run[i] == true
    end
    b.tackSide, b.boom, b.jib, b.knock = s.tackSide or 1, s.boom or 0, s.jib or 0, s.knock or 0
  end
  self.camX, self.camY = b.x, b.y
  self.mark, self.penalty = t.mark or 1, t.penalty or 0
  self.crashes, self.knocks = t.crashes or 0, t.knocks or 0
  self.tacks, self.gybes, self.score = t.tacks or 0, t.gybes or 0, t.score or 0
  self.buoys, self.strikes, self.timeLeft, self.buoyT = t.buoys or 0, t.strikes or 0, t.timeLeft or 0, t.buoyT or 0
  self.bx, self.by, self.buoyUp = t.bx or 0, t.by or 0, t.buoyUp
  for i = 1, NPATCH do self.patches[i].on = false end
  if t.patches then
    for i = 1, min(NPATCH, #t.patches) do
      local p, q = self.patches[i], t.patches[i]
      p.x, p.y, p.r, p.g, p.sh, p.age, p.on = q.x, q.y, q.r, q.g, q.sh, q.age, true
    end
  end
  if t.rival and self.rival then
    local r, q = self.rival, t.rival
    r.x, r.y, r.hd, r.v, r.mark, r.tack = q.x, q.y, q.hd, q.v, q.mark, q.tack
    r.direct, r.done, r.finT, r.boom, r.prevY = q.direct == true, q.done == true, q.finT or 0, q.boom or 0, q.prevY or q.y
  end
  for i = 1, NWAKE do self.wkX[i], self.wkY[i], self.wkA[i] = b.x, b.y, 99 end
  for i = 1, NSTREAK do
    self.streaks[i * 2 - 1] = b.x + self.rng:between(-170, 170)
    self.streaks[i * 2] = b.y + self.rng:between(-130, 130)
  end
end
