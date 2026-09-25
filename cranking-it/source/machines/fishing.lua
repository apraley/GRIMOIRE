-- CRANKING IT :: No.II FISHING LINE
--
-- The crank IS the reel handle. Behind it:
--   * a spool of line of length L (cranking forward shortens it through the
--     reel's gearing, cranking back pays it out; holding A opens the bail so
--     the line runs free for casting and sinking the lure).
--   * a live fish at the far end with mass, thrust, stamina and a
--     per-species behaviour state machine (darts, runs, rolls, sulks, jumps).
--   * line tension comes from stretch: the distance rod-tip -> fish minus L,
--     through two springs in series: the line (stretchier when long) and the
--     rod (softer when raised). Raising the rod also moves the tip back, so
--     "pumping" (lift, then lower while reeling) drags the fish in.
--   * the drag: when tension exceeds the drag setting the spool slips (it
--     has inertia, so sudden surges still spike), the handle turns but gains
--     nothing and the reel screams. Tension over the line's strength for a
--     moment snaps it; tension near zero for too long lets the fish throw
--     the hook; tension while a fish is in the air tears the hook out.
-- Before the fight: cast (hold A, crank back, flick forward, release A to
-- stop the lure), then jig or retrieve in the way each species likes, wait
-- through the nibbles and strike (one sharp crank) when the tip dives.

local gfx <const> = playdate.graphics
local floor <const> = math.floor
local abs <const> = math.abs
local sqrt <const> = math.sqrt
local sin <const>, cos <const>, rad <const> = math.sin, math.cos, math.rad
local min <const>, max <const> = math.min, math.max
local clamp <const> = U.clamp

------------------------------------------------------------------------
-- world constants (metres, seconds, kilograms-force)
------------------------------------------------------------------------
local PX <const> = 7                 -- pixels per metre
local OX <const>, OY <const> = 46, 94 -- screen position of X=0 (boat) at the waterline
local BUTT_X <const>, BUTT_Y <const> = 0.3, -2.3
local ROD_LEN <const> = 4.4
local G <const> = 9.8
local MAXX <const> = 48.5
local BED_N <const> = 56
local RETRIEVE <const> = 1.15        -- metres of line per crank turn
local STRIKE <const> = 16            -- degrees in a single frame (480 deg/s) = a strike
local MAXF <const> = 5
local MAXP <const> = 44
local TRIP <const> = 240             -- standard trip: 5 AM to 9 AM, a minute per hour... per 60 s
local SUBSTEPS <const> = 3
local DRAG_FRAC <const> = { 0.2, 0.4, 0.6, 0.8, 1.15 }
local DRAG_NAME <const> = { "I", "II", "III", "IV", "LOCK" }

-- species: kg range, strength = str + strK*kg (kgf), top speed, endurance,
-- what attracts them, their depth band, spawn weight, slack tolerance
local SPECIES <const> = {
  { id = "perch", name = "PERCH", hint = "QUICK DARTS", kg0 = 0.3, kg1 = 1.4, str = 1.4, strK = 1.2,
    speed = 2.4, endu = 0.8, likes = "jig", d0 = 1.5, d1 = 8, w = 5, slack = 2.2, window = 0.75, len = 1.0 },
  { id = "pike", name = "PIKE", hint = "LONG RUNS", kg0 = 2.0, kg1 = 9.0, str = 2.4, strK = 0.44,
    speed = 3.4, endu = 1.2, likes = "retrieve", d0 = 1.0, d1 = 6, w = 3, slack = 2.0, window = 0.9, len = 1.5 },
  { id = "eel", name = "EEL", hint = "ROLLS & TWISTS", kg0 = 0.8, kg1 = 3.2, str = 1.9, strK = 0.8,
    speed = 1.8, endu = 1.3, likes = "bottom", d0 = 5, d1 = 18, w = 2, slack = 2.6, window = 1.0, len = 1.6 },
  { id = "cat", name = "CATFISH", hint = "SULKS DEEP", kg0 = 3.0, kg1 = 12.0, str = 1.6, strK = 0.36,
    speed = 1.5, endu = 1.6, likes = "still", d0 = 7, d1 = 18, w = 2, slack = 2.8, window = 1.1, len = 1.3 },
  { id = "trout", name = "SEA TROUT", hint = "JUMPS - GIVE SLACK!", kg0 = 1.0, kg1 = 5.0, str = 2.0, strK = 0.75,
    speed = 3.6, endu = 1.0, likes = "fast", d0 = 0.5, d1 = 4, w = 2, slack = 1.4, window = 0.7, len = 1.2 },
  { id = "grey", name = "THE OLD GREY", hint = "STILL PULLING", kg0 = 24, kg1 = 40, str = 5.4, strK = 0.045,
    speed = 2.9, endu = 3.2, likes = "any", d0 = 6, d1 = 18, w = 0, slack = 2.4, window = 0.9, len = 1.0 },
}
local NSPECIES_COMMON <const> = 5
local SPAWN_W = { 5, 3, 2, 2, 2 }

-- clock labels 5:00 AM .. 9:00 AM (built once, no per-frame strings)
local CLOCK = {}
for m = 0, 240 do CLOCK[m] = string.format("%d:%02d AM", 5 + m // 60, m % 60) end
local METRES = {}
for i = 0, 99 do METRES[i] = i .. "m" end

local HINTS_READY <const> = { { "A", "HOLD+FLICK: CAST" }, { "DPAD", "ROD / DRAG" } }
local HINTS_CAST <const> = { { "A", "RELEASE: CLOSE BAIL" }, { "CRANK", "FLICK" } }
local HINTS_WATER <const> = { { "CRANK", "JIG / REEL / STRIKE" }, { "A", "BAIL" }, { "DPAD", "ROD/DRAG" } }
local HINTS_FIGHT <const> = { { "CRANK", "REEL" }, { "DPAD", "UP/DN ROD  L/R DRAG" } }

local FishingLine = Machine.define({
  id = "fishing",
  number = 2,
  title = "FISHING LINE",
  tagline = "Something pulls back.",
  description = "Cast, jig and strike. Then a live fish fights you: let the drag slip, flex the rod, and never let the line go slack.",
  howto = "Hold A, crank back, flick forward to cast; let go of A to stop the lure. Jig to tempt. When the tip DIVES, strike hard. Reel when tension is safe. L/R: drag, U/D: rod. Pump: lift, lower, reel.",
  controls = { { "CRANK", "reel in, jig, strike" }, { "A", "hold: open bail / cast" }, { "DPAD", "up/down rod, left/right drag" } },
  modes = { "tutorial", "standard", "endless" },
  medals = { standard = { 150, 450, 900 }, endless = { 200, 600, 1300 } },
  scoreLabel = "POINTS",
  unlockCost = 0,
  achievements = {
    { id = "first", name = "FIRST BITE", desc = "Land your first fish." },
    { id = "creel", name = "FULL CREEL", desc = "Land all five common species." },
    { id = "grey", name = "THE GREY LINE", desc = "Land the fish that still pulls." },
    { id = "leap", name = "BOW TO THE LEAP", desc = "Keep a sea trout on for 3 jumps." },
    { id = "finesse", name = "LIGHT HANDS", desc = "Land 10 lb+ on drag I or II." },
  },
  challenges = {
    { id = "gossamer", name = "GOSSAMER", desc = "Line breaks at 60% strength.", mode = "standard", difficulty = 2, goal = 250, reward = 2, cost = 2 },
    { id = "squall", name = "SQUALL", desc = "A heavy swell heaves the rod tip.", mode = "standard", difficulty = 2, goal = 250, reward = 3, cost = 2 },
    { id = "grey", name = "STILL PULLING", desc = "Endless. The Old Grey is hungry.", mode = "endless", difficulty = 3, goal = 900, reward = 3, cost = 3 },
  },
  records = {
    { "caught", "Fish landed" },
    { "heaviest", "Heaviest fish", function(v) return v > 0 and string.format("%.1f lb", v / 10) or "-" end },
    { "longest", "Longest cast", function(v) return v > 0 and (v .. " m") or "-" end },
    { "snapped", "Lines snapped" },
  },
  drawIcon = function(cx, cy)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(cx - 22, cy - 22, 44, 44)
    gfx.setColor(gfx.kColorWhite)
    -- sky / sea line
    gfx.fillRect(cx - 20, cy - 20, 40, 14)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(cx + 12, cy - 13, 4)
    gfx.setColor(gfx.kColorWhite)
    for i = 0, 3 do gfx.drawLine(cx - 20 + i * 10, cy - 4, cx - 15 + i * 10, cy - 6) gfx.drawLine(cx - 15 + i * 10, cy - 6, cx - 10 + i * 10, cy - 4) end
    -- bent rod and taut line
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    gfx.drawLine(cx - 20, cy - 8, cx - 12, cy - 16)
    gfx.drawLine(cx - 12, cy - 16, cx - 4, cy - 19)
    gfx.setLineWidth(1)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawLine(cx - 4, cy - 6, cx + 6, cy + 8)
    -- the fish, arching
    gfx.fillEllipseInRect(cx - 2, cy + 4, 20, 9)
    gfx.fillTriangle(cx + 16, cy + 8, cx + 21, cy + 3, cx + 21, cy + 14)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawPixel(cx + 2, cy + 7)
    gfx.drawLine(cx + 6, cy + 5, cx + 6, cy + 11)
    -- bubbles
    gfx.setColor(gfx.kColorWhite)
    gfx.drawCircleAtPoint(cx - 12, cy + 12, 2)
    gfx.drawCircleAtPoint(cx - 8, cy + 3, 1)
  end,
})

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------
local function wx(X) return OX + X * PX end
local function wy(Y) return OY + Y * PX end

function FishingLine:bedAt(x)
  local b = self.bed
  if x <= 0 then return b[1] end
  local i = floor(x)
  if i >= BED_N - 1 then return b[BED_N] end
  local f = x - i
  return b[i + 1] * (1 - f) + b[i + 2] * f
end

-- the rod tip at rest (before flex), including the swell of the sea
function FishingLine:restTip()
  local a = rad(16 + self.ra * 66)
  local sw = self.swellY
  return BUTT_X + cos(a) * ROD_LEN, BUTT_Y - sin(a) * ROD_LEN + sw
end

function FishingLine:lineStrength() return self.S end
function FishingLine:dragForce() return self.S * DRAG_FRAC[self.drag] end

------------------------------------------------------------------------
-- generation
------------------------------------------------------------------------
function FishingLine:genBed()
  local r = U.rng(self.seed + 17)
  local b = {}
  local maxD = self.tut and 7.5 or r:between(14, 17.5)
  local shelf = self.tut and 3.0 or r:between(2.2, 3.2)
  local drop = r:between(12, 24)         -- where the ledge falls away
  local ph1, ph2 = r:between(0, 6), r:between(0, 6)
  for i = 1, BED_N do
    local x = i - 1
    local t = U.smoothstep((x - drop + 6) / 12)
    local d = shelf + x * 0.12 + (maxD - shelf - x * 0.05) * t
    d = d + sin(x * 0.45 + ph1) * 0.6 + sin(x * 0.17 + ph2) * 0.9
    b[i] = clamp(d, 1.8, 17.8)
  end
  self.bed = b
  -- weed beds (pike lurk here) and rocks, purely visual + pike spawn bias
  self.weedX = { r:between(5, 14), r:between(20, 34) }
  self.rockX = { r:between(10, 20), r:between(28, 40), r:between(40, 47) }
end

-- render the static underwater cross-section once per trip
function FishingLine:buildUnder()
  local img = gfx.image.new(400, 130, gfx.kColorWhite)
  gfx.pushContext(img)
  -- depth bands, darker below
  local bands = { 0, "white", 2.5, "gray6", 6, "gray12", 10.5, "gray25" }
  for i = 1, #bands, 2 do
    local y0 = floor(bands[i] * PX)
    gfx.setPattern(Art.pat[bands[i + 1]])
    gfx.fillRect(0, y0, 400, 130 - y0)
  end
  -- shafts of light from the surface
  gfx.setColor(gfx.kColorWhite)
  for k = 0, 5 do
    local x0 = 70 + k * 58
    gfx.setDitherPattern(0.6, gfx.kDitherTypeBayer4x4)
    gfx.setColor(gfx.kColorWhite)
    gfx.setDitherPattern(0.55, gfx.kDitherTypeBayer4x4)
    gfx.fillTriangle(x0, 0, x0 + 14, 0, x0 - 18, 80)
  end
  -- the seabed polygon
  local poly = {}
  local n = 0
  poly[n + 1], poly[n + 2] = 0, 130 n = n + 2
  poly[n + 1], poly[n + 2] = 0, floor(self.bed[1] * PX) n = n + 2
  for x = 0, 400, 4 do
    local X = (x - OX) / PX
    poly[n + 1], poly[n + 2] = x, floor(self:bedAt(X) * PX) n = n + 2
  end
  poly[n + 1], poly[n + 2] = 400, 130 n = n + 2
  gfx.setColor(gfx.kColorWhite)
  gfx.fillPolygon(table.unpack(poly))
  gfx.setPattern(Art.pat.hatchD)
  gfx.fillPolygon(table.unpack(poly))
  gfx.setColor(gfx.kColorBlack)
  for x = 0, 396, 2 do
    local X0 = (x - OX) / PX
    local top = self:bedAt(X0) * PX
    gfx.setPattern(Art.pat.gray75)
    gfx.fillRect(x, top, 2, 7)
  end
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(2)
  for x = 0, 396, 4 do
    local X0, X1 = (x - OX) / PX, (x + 4 - OX) / PX
    gfx.drawLine(x, self:bedAt(X0) * PX, x + 4, self:bedAt(X1) * PX)
  end
  gfx.setLineWidth(1)
  -- woodcut gouges and pebbles in the sediment
  local r = U.rng(self.seed + 29)
  gfx.setColor(gfx.kColorWhite)
  for _ = 1, 70 do
    local x = r:range(2, 398)
    local top = self:bedAt((x - OX) / PX) * PX
    local y = top + r:range(4, 30)
    if y < 128 then
      if r:chance(0.5) then gfx.drawLine(x, y, x + r:range(3, 7), y + r:range(-1, 1)) else gfx.drawPixel(x, y) end
    end
  end
  -- rocks
  for i = 1, #self.rockX do
    local X = self.rockX[i]
    local x, y = wx(X), self:bedAt(X) * PX
    gfx.setColor(gfx.kColorBlack)
    gfx.fillEllipseInRect(x - 9, y - 7, 18, 12)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawLine(x - 5, y - 4, x - 1, y - 5)
  end
  -- weed beds: tall wavy fronds
  gfx.setColor(gfx.kColorBlack)
  for i = 1, #self.weedX do
    local X = self.weedX[i]
    for k = 0, 7 do
      local x = wx(X) + k * 5 - 18 + r:range(-2, 2)
      local y = self:bedAt((x - OX) / PX) * PX
      local h = r:range(14, math.max(16, floor(y - 12)))
      local px, py = x, y
      for s = 1, 6 do
        local ny = y - h * s / 6
        local nx = x + sin(s * 1.3 + k) * 2.5
        gfx.drawLine(px, py, nx, ny)
        px, py = nx, ny
      end
    end
  end
  gfx.popContext()
  self.underImg = img
end

local function buildSky()
  return Art.cached("fish_sky", 400, 76, function()
    gfx.setColor(gfx.kColorBlack)
    -- far headland with the lighthouse (clear of the HUD plate)
    local pts = { 100, 76, 112, 66, 130, 60, 150, 56, 168, 57, 186, 62, 200, 68, 206, 76 }
    gfx.fillPolygon(table.unpack(pts))
    local lx = 148
    gfx.fillRect(lx, 34, 7, 23)
    gfx.fillRect(lx - 2, 31, 11, 4)
    gfx.fillTriangle(lx - 2, 31, lx + 9, 31, lx + 3, 25)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(lx + 2, 36, 3, 3)
    gfx.drawLine(lx + 1, 44, lx + 5, 44)
    gfx.drawLine(lx + 1, 50, lx + 5, 50)
    gfx.setColor(gfx.kColorBlack)
    -- harbour wall and a moored schooner far off
    gfx.fillRect(206, 71, 64, 5)
    for x = 210, 266, 8 do gfx.fillRect(x, 68, 3, 3) end
    gfx.fillRect(300, 70, 26, 4)
    gfx.drawLine(308, 50, 308, 70)
    gfx.drawLine(318, 54, 318, 70)
    gfx.fillTriangle(309, 52, 309, 67, 317, 66)
    -- woodcut cloud banks: long engraved strokes, thicker at the belly
    local banks = { 60, 24, 64, 196, 12, 52, 230, 44, 30 }
    for b = 1, #banks, 3 do
      local x, y, w = banks[b], banks[b + 1], banks[b + 2]
      gfx.setColor(gfx.kColorWhite)
      gfx.fillEllipseInRect(x - 4, y - 5, w + 8, 14)
      gfx.setColor(gfx.kColorBlack)
      for k = 0, 3 do
        local inset = (k == 0 or k == 3) and w * 0.25 or (k == 1 and w * 0.08 or 0)
        gfx.drawLine(x + inset, y + k * 3, x + w - inset * 0.6, y + k * 3)
      end
      gfx.fillRect(x + w * 0.1, y + 9, w * 0.8, 1)
    end
  end)
end

local function buildBoat()
  -- 96x56 image; waterline at y = 44, rod butt (the angler's hands) at 48, 28
  return Art.cached("fish_boat", 96, 56, function()
    gfx.setColor(gfx.kColorBlack)
    -- stern lamp on its pole
    gfx.drawLine(9, 12, 9, 36)
    gfx.drawLine(9, 12, 13, 12)
    gfx.fillRect(11, 13, 5, 7)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(12, 15, 3, 3)
    gfx.setColor(gfx.kColorBlack)
    -- clinker hull
    local hull = { 0, 34, 94, 34, 86, 50, 12, 50, 4, 42 }
    gfx.fillPolygon(table.unpack(hull))
    gfx.setColor(gfx.kColorWhite)
    gfx.drawLine(3, 38, 91, 38)
    gfx.drawLine(6, 42, 89, 42)
    gfx.drawLine(10, 46, 87, 46)
    gfx.fillRect(1, 34, 92, 1)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 32, 95, 2)
    for x = 16, 88, 18 do gfx.fillRect(x, 30, 2, 3) end
    -- shipped oar
    gfx.setLineWidth(2)
    gfx.drawLine(4, 29, 58, 33)
    gfx.setLineWidth(1)
    gfx.fillEllipseInRect(0, 26, 10, 5)
    -- the angler: oilskin coat, sou'wester, seated on the thwart
    local coat = { 22, 33, 26, 16, 38, 16, 43, 33 }
    gfx.fillPolygon(table.unpack(coat))
    gfx.fillCircleAtPoint(33, 11, 5)
    gfx.fillRect(23, 5, 21, 3)      -- hat brim
    gfx.fillRect(27, 0, 12, 6)      -- crown
    gfx.setColor(gfx.kColorWhite)
    gfx.drawLine(28, 3, 38, 3)      -- hat band
    gfx.fillRect(35, 10, 2, 2)      -- an eye in the brim shadow
    gfx.drawLine(30, 19, 29, 31)    -- coat seam
    gfx.drawPixel(32, 22) gfx.drawPixel(32, 26)
    gfx.setColor(gfx.kColorBlack)
    -- arms to the rod butt
    gfx.setLineWidth(3)
    gfx.drawLine(37, 19, 45, 27)
    gfx.drawLine(30, 21, 44, 29)
    gfx.setLineWidth(1)
    gfx.fillCircleAtPoint(47, 28, 2)
    -- creel basket in the bow
    gfx.fillRect(66, 26, 13, 7)
    gfx.setColor(gfx.kColorWhite)
    for x = 68, 77, 3 do gfx.drawLine(x, 27, x, 32) end
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(66, 25, 79, 25)
  end)
end

------------------------------------------------------------------------
-- lifecycle
------------------------------------------------------------------------
function FishingLine:enter(params)
  self.tut = self.mode == "tutorial"
  local d = self.difficulty
  local cid = self.params.challengeId
  self.S = (self.tut and 9 or 6) * (d == 1 and 1 or (d == 2 and 0.92 or 0.84))
  if cid == "gossamer" then self.S = self.S * 0.6 end
  self.fishK = (d == 1 and 1 or (d == 2 and 1.12 or 1.25))
  self.windowK = (d == 1 and 1 or (d == 2 and 0.85 or 0.7))
  self.swellAmp = (cid == "squall") and 0.55 or 0.07
  self.greyChance = (cid == "grey") and 0.3 or 0.05
  self:genBed()
  self:buildUnder()
  self.skyImg = buildSky()
  self.boatImg = buildBoat()

  self.t = 0              -- trip clock (s)
  self.anim = 0
  self.score = 0
  self.caught = 0
  self.lost = 0
  self.snaps = 0
  self.heaviest = 0       -- lb*10
  self.heaviestName = "-"
  self.seen = { 0, 0, 0, 0, 0, 0 }
  self.overtime = false

  -- rig
  self.phase = "ready"
  self.ra = 0.35          -- rod angle 0 (low) .. 1 (high)
  self.drag = 3
  self.L = 1.2
  self.bail = false
  self.T = 0
  self.strain = 0
  self.slackT = 0
  self.tearT = 0
  self.spoolV = 0
  self.flex = 0
  self.swellY = 0
  self.windup = 0
  self.fwd = 0
  self.peak = 0
  self.lx, self.ly, self.lvx, self.lvy = 0, 0, 0, 0
  self.lureSpeed = 0
  self.stillT = 0
  self.onBottom = false
  self.twitch = 0
  self.biteDip = 0
  self.reelAng = 0
  self.hooked = nil
  self.phaseT = 0
  self.cin = 0
  self.msg, self.msgT = nil, 0
  self.card = nil
  self.cardT = 0
  self.cardA, self.cardB, self.cardC = "", "", ""
  self.hdrKey, self.hdrStr = -1, ""
  self.dragFlash = 0
  self.gullT = 3
  self.lapT = 1
  -- tutorial bookkeeping
  self.tutRun = 0
  self.slipAcc = 0
  self.fightReel = 0
  self.pumps = 0
  self.pumpHigh = false

  self.tracker = Crank.Tracker.new()
  self.jiggle = Crank.Jiggle.new(40)
  self.detent = Crank.Detent.new(10)

  -- fish pool (preallocated)
  self.fish = {}
  for i = 1, MAXF do self.fish[i] = { active = false, respawn = i * 1.5 } end
  self.nFish = self.tut and 0 or (d == 1 and 4 or 5)
  if not self.tut then
    for i = 1, self.nFish do self:spawnFish(self.fish[i]) end
  end

  -- particles: 1 droplet, 2 bubble, 3 ripple
  self.pk, self.px, self.py, self.pvx, self.pvy, self.pl = {}, {}, {}, {}, {}, {}
  for i = 1, MAXP do self.pk[i] = 0 self.px[i] = 0 self.py[i] = 0 self.pvx[i] = 0 self.pvy[i] = 0 self.pl[i] = 0 end
  self.pNext = 1

  self.humDrag = Audio.Hum.new(Audio.SQUARE)
  self.humLine = Audio.Hum.new(Audio.SINE)
  self.humSea = Audio.Hum.new(Audio.NOISE)

  self:resetRig()
  if self.tut then self:setupCoach() end
end

function FishingLine:exit()
  self.humDrag:stop()
  self.humLine:stop()
  self.humSea:stop()
end

function FishingLine:rewindCoach()
  local co = self.coach
  if not co then return end
  co.i = 1
  co.state = "active"
  co.t = 0
  co.holdT = 0
  for i = 1, #co.steps do co.steps[i].entered = false end
  self.tutRun = 0
  self.fish[1].active = false
end

function FishingLine:resetRig()
  if self.tut and self.coach and self.coach.i >= 2 and self.coach.i <= 4 then self:rewindCoach() end
  self.phase = "ready"
  self.hooked = nil
  self.L = 1.2
  self.T = 0
  self.strain = 0
  self.slackT = 0
  self.tearT = 0
  self.spoolV = 0
  self.windup, self.fwd, self.peak = 0, 0, 0
  local tx, ty = self:restTip()
  self.lx, self.ly = tx, ty + 1.1
  self.lvx, self.lvy = 0, 0
  self.onBottom = false
  self.biteDip = 0
end

function FishingLine:setupCoach()
  local s = self
  self.coach = UI.Coach.new({
    { text = "Hold A to open the bail. Crank BACK a little, then flick it FORWARD fast to cast.",
      check = function() return s.phase == "flight" or s.phase == "water" end },
    { text = "Let go of A to close the bail: the line stops running out and the lure sinks on it.",
      check = function() return s.phase == "water" and not s.bail and s.ly > 1 end },
    { text = "Twitch the crank back and forth, small and quick. The lure dances. Something is watching...",
      enter = function() s:spawnTutorFish() end,
      check = function() local f = s.fish[1] return f.active and (f.state == "nibble" or f.state == "bite") end },
    { text = "Nibbles make the tip quiver. WAIT. When the tip DIVES, strike: one sharp, fast crank!",
      check = function() return s.phase == "fight" end },
    { text = "Hooked! Reel in steadily. Keep the TENSION needle out of the hatched zone.",
      enter = function() s.fightReel = 0 end,
      check = function() return s.fightReel > 3 end },
    { text = "It RUNS! Press LEFT to ease the drag: the spool slips and gives line instead of snapping.",
      enter = function() s.tutRun = 99 s.slipAcc = 0 end,
      check = function() return s.slipAcc > 1.5 end },
    { text = "Now RIGHT to firm the drag. PUMP: raise the rod (UP), then lower it (DOWN) while reeling.",
      enter = function() s.pumps = 0 s.tutRun = 0 end,
      check = function() return s.pumps >= 2 and s.drag >= 3 end },
    { text = "It is tiring. Reel it all the way to the net beside the boat.",
      check = function() return s.caught > 0 end },
  }, { y = 176, h = 46, anchor = "bottom" })
end

function FishingLine:spawnTutorFish()
  local f = self.fish[1]
  self:spawnFish(f, 1)
  f.tutor = true
  f.kg = 1.6
  f.mass = f.kg * 1.5 + 0.5
  f.str = 2.2
  f.x = clamp(self.lx + 4, 6, MAXX - 2)
  f.y = clamp(self.ly, 1.5, self:bedAt(f.x) - 0.6)
  f.interest = 0.5
  self.nFish = 1
end

------------------------------------------------------------------------
-- fish
------------------------------------------------------------------------
function FishingLine:spawnFish(f, forceSp)
  local r = self.rng
  local sp = forceSp
  if not sp then
    if self.t > 50 and not self.tut and r:chance(self.greyChance) and self.seen[6] == 0 then
      sp = 6
    else
      sp = r:weighted(SPAWN_W)
    end
  end
  local S = SPECIES[sp]
  f.active = true
  f.sp = sp
  f.tutor = false
  f.kg = r:between(S.kg0, S.kg1)
  if r:chance(0.12) then f.kg = f.kg * 1.35 end -- the occasional specimen
  -- endless: the longer you last, the bigger and stronger they come
  local ramp = (self.mode == "endless") and min(0.5, self.caught * 0.04) or 0
  f.kg = f.kg * (1 + ramp)
  f.str = (S.str + S.strK * f.kg) * self.fishK * (1 + ramp * 0.5)
  f.mass = f.kg * 1.5 + 0.5
  f.x = r:between(9, MAXX - 2)
  if sp == 2 and r:chance(0.6) then f.x = clamp(self.weedX[r:range(1, 2)] + r:between(-4, 4), 5, MAXX - 2) end
  local bed = self:bedAt(f.x)
  f.y = clamp(r:between(S.d0, S.d1), 0.8, bed - 0.5)
  f.vx, f.vy = 0, 0
  f.tx, f.ty = f.x, f.y
  f.state = "wander"
  f.stT = 0
  f.interest = 0
  f.stamina = 1
  f.effort = 0
  f.dx, f.dy = 1, 0
  f.phase = r:between(0, 6)
  f.air = false
  f.jumps = 0
  f.maxJumps = r:range(2, 4)
  f.jumpsKept = 0
  f.boltT = 0
  f.bubT = r:between(0.5, 3)
  f.face = 1
end

-- how much this species likes what the lure is doing (0..1)
function FishingLine:lureMatch(sp)
  local likes = SPECIES[sp].likes
  local e = self.jiggle.energy
  local s = self.lureSpeed
  local depth = self.ly
  local nearBed = self:bedAt(self.lx) - depth < 1.6
  local m = 0.06
  if likes == "jig" then
    m = max(m, e * (s < 1.8 and 1 or 0.4))
  elseif likes == "retrieve" then
    if s > 0.35 and s < 2.4 then m = max(m, 1 - abs(s - 1.2) / 1.3) end
  elseif likes == "bottom" then
    if nearBed then m = max(m, 0.35 + e * 0.8) end
  elseif likes == "still" then
    if self.onBottom and s < 0.2 then m = max(m, min(1, self.stillT / 2.5)) end
  elseif likes == "fast" then
    if depth < 3.2 and s > 0.75 then m = max(m, min(1, (s - 0.55) / 0.9)) end
  else
    m = max(m, 0.3 + e * 0.4, (s > 0.4 and s < 2) and 0.6 or 0)
  end
  return m
end

function FishingLine:updateFishAI(f, dt)
  local S = SPECIES[f.sp]
  local r = self.rng
  local lureIn = (self.phase == "water") and self.ly > 0.1
  local dxl, dyl = self.lx - f.x, self.ly - f.y
  local dl = sqrt(dxl * dxl + dyl * dyl)
  local cruise = S.speed * 0.28
  local tx, ty, spd = f.tx, f.ty, cruise
  local sense = self.tut and 12 or 7.5

  if f.state == "wander" or f.state == "approach" then
    if lureIn and dl < sense then
      local m = self:lureMatch(f.sp)
      f.interest = f.interest + dt * (m * (1.25 - dl / sense) - 0.12)
    else
      f.interest = f.interest - dt * 0.1
    end
    f.interest = clamp(f.interest, -2.5, 1.6)
    if f.interest >= 1 and lureIn then f.state = "approach" end
    if f.state == "approach" then
      if not lureIn or f.interest < 0.6 then
        f.state = "wander"
      else
        tx, ty, spd = self.lx, self.ly, cruise * 1.8
        if dl < 0.7 then
          f.state = "nibble"
          f.stT = r:between(1.2, 2.6) * (self.tut and 1.4 or 1)
          f.nibT = 0.2
        end
      end
    else
      f.stT = f.stT - dt
      local ddx, ddy = f.tx - f.x, f.ty - f.y
      if f.stT <= 0 or ddx * ddx + ddy * ddy < 0.5 then
        f.tx = clamp(f.x + r:between(-8, 8), 4, MAXX - 1)
        local bed = self:bedAt(f.tx)
        f.ty = clamp(r:between(S.d0, S.d1), 0.7, bed - 0.4)
        f.stT = r:between(2, 5)
      end
    end
  elseif f.state == "nibble" or f.state == "bite" then
    if not lureIn or self.lureSpeed > 2.6 then
      f.state = "wander" f.interest = 0.2
    else
      tx, ty = self.lx - 0.4 * f.face, self.ly
      spd = 2.5
      f.stT = f.stT - dt
      if f.state == "nibble" then
        f.nibT = f.nibT - dt
        if f.nibT <= 0 then
          f.nibT = r:between(0.25, 0.6)
          self.twitch = 1
          Audio.sfx.tick(700, 0.12)
        end
        if f.stT <= 0 then
          f.state = "bite"
          f.stT = S.window * self.windowK * (self.tut and 1.8 or 1)
          self.biteDip = 1
          Audio.sfx.thud(0.5)
          Audio.play(Audio.TRIANGLE, 180, 0.3, 0.12, 0.001, 0.12, 0, 0.05)
        end
      else
        self.biteDip = max(self.biteDip, 0.8)
        if f.stT <= 0 then
          f.state = "flee" f.stT = 2 f.interest = -1.2
          self.biteDip = 0
          self:say("MISSED IT", 1.2)
        end
      end
    end
  elseif f.state == "flee" then
    f.stT = f.stT - dt
    tx, ty, spd = f.x + 6, f.y + 1, S.speed * 0.7
    if f.stT <= 0 then f.state = "wander" f.stT = 0 end
  end

  -- steer toward target
  local ddx, ddy = tx - f.x, ty - f.y
  local dd = sqrt(ddx * ddx + ddy * ddy)
  local vx, vy = 0, 0
  if dd > 0.05 then vx, vy = ddx / dd * spd, ddy / dd * spd end
  if dd < 0.5 then vx, vy = vx * dd * 2, vy * dd * 2 end
  f.vx = U.damp(f.vx, vx, 3, dt)
  f.vy = U.damp(f.vy, vy, 3, dt)
  f.x = clamp(f.x + f.vx * dt, 3, MAXX)
  local bed = self:bedAt(f.x)
  f.y = clamp(f.y + f.vy * dt, 0.5, bed - 0.3)
  if abs(f.vx) > 0.05 then f.face = f.vx > 0 and 1 or -1 end
  -- bubbles betray fish below
  f.bubT = f.bubT - dt
  if f.bubT <= 0 then
    f.bubT = r:between(1.5, 4.5)
    self:spawnP(2, f.x, f.y - 0.3, r:between(-0.1, 0.1), -0.9, 3)
  end
end

-- who is where on the other end: pick the hooked fish's next move
function FishingLine:behave(f, dt)
  local S = SPECIES[f.sp]
  local r = self.rng
  local id = S.id
  f.stT = f.stT - dt
  f.phase = f.phase + dt
  if f.air then return end
  if f.tutor then
    if self.tutRun > 0 then
      -- the lesson's run: stronger than drag II, weaker than drag III
      f.effort, f.dx, f.dy = 1, 0.95, 0.3
      f.str = 4.7 / (0.3 + 0.7 * f.stamina)
    else
      f.str = 2.2
      if f.stT <= 0 then
        f.stT = r:between(1, 2)
        f.effort = r:between(0.25, 0.45)
        f.dx, f.dy = r:between(0.4, 1), r:between(-0.3, 0.6)
      end
    end
  elseif id == "perch" then
    if f.stT <= 0 then
      if f.state == "dart" then
        f.state, f.stT, f.effort = "pause", r:between(0.4, 1.0), 0.25
      else
        f.state, f.stT, f.effort = "dart", r:between(0.4, 0.9), 1
        f.dx, f.dy = r:between(-0.3, 1), r:between(-0.6, 0.8)
      end
    end
  elseif id == "pike" or id == "grey" then
    if f.stT <= 0 then
      if f.state == "run" or f.state == "surge" then
        f.state, f.stT, f.effort = "rest", r:between(1.5, 3.0), 0.12
        f.dx, f.dy = r:between(-0.5, 0.5), r:between(-0.2, 0.3)
      elseif id == "grey" and r:chance(0.35) then
        f.state, f.stT, f.effort = "surge", r:between(0.5, 0.9), 1.35
        f.dx, f.dy = r:between(0.2, 1), r:between(0.3, 1)
      else
        f.state, f.stT, f.effort = "run", (id == "grey") and r:between(4, 7) or r:between(2.5, 4.5), 1
        f.dx, f.dy = 1, r:between(-0.1, 0.35)
        Audio.play(Audio.NOISE, 900, 0.18, 0.25, 0.01, 0.2)
      end
    end
  elseif id == "eel" then
    f.state = "roll"
    f.effort = 0.55 + 0.45 * sin(f.phase * 21)
    if f.stT <= 0 then
      f.stT = r:between(1.5, 3.5)
      f.dx, f.dy = r:between(-0.6, 1), r:between(0.3, 1)
    end
  elseif id == "cat" then
    local bed = self:bedAt(f.x)
    if f.state == "dive" then
      f.effort, f.dx, f.dy = 0.9, 0.3, 1
      if f.y > bed - 0.6 then f.state, f.stT = "sulk", r:between(3, 6) end
    elseif f.state == "sulk" then
      f.effort = 0.08
      if f.stT <= 0 then
        f.state, f.stT, f.effort = "shift", r:between(1.2, 2.0), 0.8
        f.dx, f.dy = (r:chance(0.7) and 1 or -1), 0.2
      end
    else
      if f.stT <= 0 then f.state = "dive" end
    end
  elseif id == "trout" then
    if f.state == "rise" then
      f.effort, f.dx, f.dy = 1, 0.35, -1
      if f.y < 0.7 then
        -- leap
        f.air = true
        f.vy = -r:between(4.5, 6.5)
        f.vx = r:between(0.5, 2.0)
        f.jumps = f.jumps + 1
        self:splash(f.x, 0, 8)
        Audio.sfx.splash(0.6)
        self:say("IT JUMPS - GIVE SLACK!", 1.0)
      end
    elseif f.stT <= 0 then
      if f.jumps < f.maxJumps and f.stamina > 0.3 and r:chance(0.55) then
        f.state = "rise"
        Audio.play(Audio.NOISE, 2400, 0.2, 0.2, 0.05, 0.15)
      else
        f.state, f.stT, f.effort = "run", r:between(1.5, 3), 0.9
        f.dx, f.dy = r:between(0.3, 1), (1.2 - f.y) * 0.5
      end
    end
  end
  -- a fresh fish that sees the boat bolts
  if f.x < 5 and f.stamina > 0.4 and f.boltT <= 0 and not f.tutor then
    f.state, f.stT, f.effort = "run", 1.6, 1
    f.dx, f.dy = 1, 0.4
    f.boltT = 4
    self:say("IT SAW THE NET!", 1.0)
  end
  f.boltT = f.boltT - dt
  if f.stamina < 0.28 then
    f.effort = f.effort * max(0.15, f.stamina / 0.28)
    f.dy = f.dy - 0.7
  end
end

------------------------------------------------------------------------
-- particles
------------------------------------------------------------------------
function FishingLine:spawnP(kind, x, y, vx, vy, life)
  local i = self.pNext
  self.pNext = i % MAXP + 1
  self.pk[i], self.px[i], self.py[i], self.pvx[i], self.pvy[i], self.pl[i] = kind, x, y, vx, vy, life
end

function FishingLine:splash(x, y, n)
  local r = self.rng
  for _ = 1, n do self:spawnP(1, x, y - 0.1, r:between(-2.5, 2.5), -r:between(2, 5), 1) end
  self:spawnP(3, x, 0, 0, 0, 1)
end

function FishingLine:updateParticles(dt)
  for i = 1, MAXP do
    local k = self.pk[i]
    if k ~= 0 then
      local l = self.pl[i] - dt
      self.pl[i] = l
      if l <= 0 then
        self.pk[i] = 0
      elseif k == 1 then
        self.pvy[i] = self.pvy[i] + G * dt
        self.px[i] = self.px[i] + self.pvx[i] * dt
        self.py[i] = self.py[i] + self.pvy[i] * dt
        if self.py[i] > 0.1 and self.pvy[i] > 0 then self.pk[i] = 0 end
      elseif k == 2 then
        self.px[i] = self.px[i] + sin(l * 7 + i) * 0.01
        self.py[i] = self.py[i] + self.pvy[i] * dt
        if self.py[i] < 0.1 then self.pk[i] = 3 self.pl[i] = 0.6 self.py[i] = 0 end
      end
    end
  end
end

function FishingLine:say(msg, secs)
  self.msg, self.msgT = msg, secs or 1.5
end

------------------------------------------------------------------------
-- input
------------------------------------------------------------------------
function FishingLine:cranked(change)
  self.cin = self.cin + change
end

function FishingLine:buttonDown(b)
  if b == Input.LEFT or b == Input.RIGHT then
    local nd = clamp(self.drag + (b == Input.RIGHT and 1 or -1), 1, #DRAG_FRAC)
    if nd ~= self.drag then
      self.drag = nd
      Audio.sfx.click(0.3)
      Audio.sfx.tick(600 + nd * 200, 0.2)
    else
      Audio.sfx.denied()
    end
    self.dragFlash = 0.6
  end
end

------------------------------------------------------------------------
-- simulation
------------------------------------------------------------------------
function FishingLine:update(dt)
  self.anim = self.anim + dt
  local c = self.cin
  self.cin = 0
  self.tracker:feed(c)
  self.tracker:update(dt)
  self.jiggle:feed(c, dt)
  self.reelAng = self.reelAng + c
  if self.msgT > 0 then self.msgT = self.msgT - dt end
  if self.cardT > 0 then self.cardT = self.cardT - dt end
  self.dragFlash = max(0, (self.dragFlash or 0) - dt)
  self.twitch = max(0, self.twitch - dt * 5)
  self.biteDip = max(0, self.biteDip - dt * 1.5)
  self.swellY = sin(self.anim * 1.3) * self.swellAmp + sin(self.anim * 2.9 + 1) * self.swellAmp * 0.45
  self:updateParticles(dt)
  self:ambience(dt)

  if self.finished then
    self.humDrag:set(0, 0)
    self.humLine:set(0, 0)
    return
  end

  -- rod angle from the d-pad
  local ay = Input.axisY()
  if ay ~= 0 then self.ra = clamp(self.ra - ay * dt * 1.7, 0, 1) end
  if self.ra > 0.75 then self.pumpHigh = true end
  if self.ra < 0.3 and self.pumpHigh and self.phase == "fight" then self.pumps = self.pumps + 1 self.pumpHigh = false end
  if self.ra < 0.3 then self.pumpHigh = false end

  -- reel ratchet clicks
  if c > 0 and self.phase ~= "flight" and not self.bail then
    if self.detent:feed(c) ~= 0 then Audio.sfx.tick(2600, 0.06) end
  end

  local ph = self.phase
  self.phaseT = self.phaseT + dt
  if ph == "ready" then self:updateReady(dt, c)
  elseif ph == "flight" then self:updateFlight(dt, c)
  elseif ph == "water" then self:updateWater(dt, c)
  elseif ph == "fight" then self:updateFight(dt, c)
  elseif ph == "landing" or ph == "lost" then
    if self.phaseT > 1.6 then self:resetRig() end
  end

  -- idle fish keep swimming, hooked or not
  for i = 1, self.nFish do
    local f = self.fish[i]
    if f.active then
      if f ~= self.hooked then self:updateFishAI(f, dt) end
    else
      f.respawn = (f.respawn or 0) - dt
      if f.respawn <= 0 and not self.tut then self:spawnFish(f) end
    end
  end

  -- sounds: drag scream and the singing line
  if self.spoolV > 0.05 then
    self.humDrag:set(700 + self.spoolV * 450 + sin(self.anim * 60) * 30, min(0.28, 0.08 + self.spoolV * 0.08))
  else
    self.humDrag:set(0, 0)
  end
  local tr = self.T / self.S
  if self.phase == "fight" and tr > 0.35 then
    self.humLine:set(160 + tr * 520, (tr - 0.35) * 0.3)
  else
    self.humLine:set(0, 0)
  end

  -- the clock
  if self.mode == "standard" then
    self.t = self.t + dt
    if self.t >= TRIP then
      self.t = TRIP
      if self.phase ~= "fight" then
        self:endTrip()
      elseif not self.overtime then
        self.overtime = true
        self:say("TIME! LAND THIS LAST ONE", 2)
        Audio.sfx.bell(660, 0.4)
      end
    end
  else
    self.t = self.t + dt
  end
end

function FishingLine:ambience(dt)
  -- sea hush (quiet noise) and gulls
  self.humSea:set(300 + sin(self.anim * 0.6) * 80, 0.025 + 0.015 * sin(self.anim * 0.9))
  self.gullT = self.gullT - dt
  if self.gullT <= 0 then
    self.gullT = 9 + (self.anim * 7.3) % 11
    Audio.play(Audio.SQUARE, 1480, 0.05, 0.08, 0.01, 0.08, 0.2, 0.05)
    Audio.play(Audio.SQUARE, 1180, 0.05, 0.14, 0.01, 0.1, 0.2, 0.08, 0.1)
    Audio.play(Audio.SQUARE, 1320, 0.04, 0.1, 0.01, 0.08, 0.2, 0.05, 0.28)
  end
  self.lapT = self.lapT - dt
  if self.lapT <= 0 then
    self.lapT = 2.2 + (self.anim * 3.1) % 2.5
    Audio.play(Audio.NOISE, 420, 0.07, 0.35, 0.15, 0.3, 0, 0.2)
  end
end

function FishingLine:updateReady(dt, c)
  self.bail = Input.held(Input.A)
  local tx, ty = self:restTip()
  -- lure dangles from the tip
  self.lx = tx + sin(self.anim * 1.6) * 0.15
  self.ly = ty + 1.1
  self.L = 1.2
  self.T = 0
  if self.bail then
    if c < 0 and self.fwd == 0 then
      self.windup = min(150, self.windup - c)
    elseif c > 0 and self.windup >= 25 then
      self.fwd = self.fwd + c
      if c > self.peak then self.peak = c end
      if (self.fwd > 15 and c < self.peak * 0.4) or self.fwd > self.windup + 60 then self:launch() end
    elseif c <= 0 and self.fwd > 15 then
      self:launch()
    end
  else
    self.windup = max(0, self.windup - dt * 300)
    self.fwd, self.peak = 0, 0
  end
end

function FishingLine:launch()
  local power = min(1, self.windup / 90 + 0.25)
  local v0 = clamp(3 + self.peak * 0.62, 3, 23) * power
  local a = rad(38)
  local tx, ty = self:restTip()
  self.lx, self.ly = tx, ty
  self.lvx, self.lvy = cos(a) * v0, -sin(a) * v0
  self.phase = "flight"
  self.phaseT = 0
  self.L = 0.5
  self.windup, self.fwd, self.peak = 0, 0, 0
  Audio.sfx.whoosh(0.35)
  Audio.play(Audio.SAW, 2200, 0.06, 0.3, 0.01, 0.3, 0.3, 0.1)
end

function FishingLine:constrainLure(tx, ty)
  local dx, dy = self.lx - tx, self.ly - ty
  local d = sqrt(dx * dx + dy * dy)
  if d > self.L and d > 0.001 then
    local k = self.L / d
    self.lx, self.ly = tx + dx * k, ty + dy * k
    local ux, uy = dx / d, dy / d
    local vr = self.lvx * ux + self.lvy * uy
    if vr > 0 then self.lvx, self.lvy = self.lvx - vr * ux, self.lvy - vr * uy end
  end
  return d
end

function FishingLine:updateFlight(dt, c)
  self.bail = Input.held(Input.A)
  local tx, ty = self:restTip()
  local v = sqrt(self.lvx * self.lvx + self.lvy * self.lvy)
  self.lvx = self.lvx - self.lvx * v * 0.012 * dt
  self.lvy = self.lvy + G * dt - self.lvy * v * 0.012 * dt
  self.lx = self.lx + self.lvx * dt
  self.ly = self.ly + self.lvy * dt
  if self.lx > MAXX then self.lx = MAXX self.lvx = 0 end
  local dx, dy = self.lx - tx, self.ly - ty
  local d = sqrt(dx * dx + dy * dy)
  if self.bail then self.L = max(self.L, d) else self:constrainLure(tx, ty) end
  -- bail shut too early on a short line: the lure swings back to the rod
  if not self.bail and self.L < -ty + 0.2 and self.phaseT > 0.8 then
    self:say("TOO SHORT", 1)
    self:resetRig()
    return
  end
  if self.ly >= 0 then
    self.ly = 0.05
    self.phase = "water"
    self.phaseT = 0
    local sp = sqrt(self.lvx * self.lvx + self.lvy * self.lvy)
    self.lvx, self.lvy = self.lvx * 0.1, 0.5
    self:splash(self.lx, 0, 3 + floor(sp * 0.4))
    Audio.sfx.splash(0.2 + sp * 0.02)
    local dist = floor(self.lx)
    if not self.tut and dist > 0 then self:statMax("longest", dist) end
    self:say(METRES[clamp(dist, 0, 99)], 1.0)
    self.stillT = 0
  end
end

function FishingLine:updateWater(dt, c)
  self.bail = Input.held(Input.A)
  local tx, ty = self:restTip()
  local ox, oy = self.lx, self.ly
  -- sinking lure with water drag
  self.lvx = U.damp(self.lvx, 0, 3, dt)
  self.lvy = U.damp(self.lvy, 0.9, 2.5, dt)
  self.lx = self.lx + self.lvx * dt
  self.ly = self.ly + self.lvy * dt
  -- bottom
  local bed = self:bedAt(self.lx)
  self.onBottom = false
  if self.ly >= bed - 0.15 then self.ly = bed - 0.15 self.lvy = 0 self.onBottom = true end
  -- line: bail open runs free, otherwise reel / backreel changes L
  if self.bail then
    local dx, dy = self.lx - tx, self.ly - ty
    self.L = max(self.L, sqrt(dx * dx + dy * dy))
  else
    if c > 0 then self.L = self.L - c / 360 * RETRIEVE
    elseif c < 0 then self.L = self.L - c / 360 * RETRIEVE * 0.8 end
    self.L = max(0.6, self.L)
    self:constrainLure(tx, ty)
  end
  if self.ly < 0.05 then self.ly = 0.05 end
  -- reeled all the way in: the lure comes up out of the water to the tip
  if not self.bail and self.L < -ty + 0.9 then self:resetRig() return end
  self.lx = clamp(self.lx, 0.3, MAXX)
  local sp = sqrt((self.lx - ox) ^ 2 + (self.ly - oy) ^ 2) / dt
  if self.onBottom and not self.bail and c == 0 then sp = 0 end
  self.lureSpeed = U.damp(self.lureSpeed, sp, 8, dt)
  if self.lureSpeed < 0.2 and self.onBottom then self.stillT = self.stillT + dt else self.stillT = 0 end
  -- small visible line load while the lure is towed
  self.T = min(self.S * 0.15, self.lureSpeed * 0.3)

  -- strike?
  if c >= STRIKE and not self.bail then
    for i = 1, self.nFish do
      local f = self.fish[i]
      if f.active and f.state == "bite" then
        self:hookFish(f)
        return
      elseif f.active and f.state == "nibble" then
        -- too early: the fish is spooked, and so are its neighbours
        f.state, f.stT, f.interest = "flee", 2.5, -2.5
        self:say("TOO EARLY - SPOOKED", 1.3)
        Audio.sfx.denied()
        for j = 1, self.nFish do
          local g = self.fish[j]
          if g.active and g ~= f then g.interest = g.interest - 0.8 end
        end
      end
    end
  end
end

function FishingLine:hookFish(f)
  self.hooked = f
  self.phase = "fight"
  self.phaseT = 0
  f.state, f.stT, f.effort = "run", 0.8, 1
  f.dx, f.dy = 1, 0.3
  if SPECIES[f.sp].id == "cat" then f.state = "dive" end
  if SPECIES[f.sp].id == "trout" then f.state, f.stT = "run", 1.0 end
  f.vx, f.vy = 0, 0
  local tx, ty = self:restTip()
  local dx, dy = f.x - tx, f.y - ty
  self.L = sqrt(dx * dx + dy * dy) - 0.1
  self.strain, self.slackT, self.tearT, self.spoolV = 0, 0, 0, 0
  self.biteDip = 0
  self.fightReel = 0
  self.card = "hooked"
  Audio.sfx.clack(0.7)
  Audio.sfx.thunk(0.6)
  self:shake(3)
  self:say("FISH ON!", 1.2)
end

function FishingLine:updateFight(dt, c)
  local f = self.hooked
  local S = self.S
  local sp = SPECIES[f.sp]
  self.bail = false
  self:behave(f, dt)

  local dragF = self:dragForce()
  local kr = S / (0.35 + 1.3 * self.ra)
  local h = dt / SUBSTEPS
  local reelPer = (c > 0) and (c / 360 * RETRIEVE / SUBSTEPS) or 0
  local backPer = (c < 0) and (-c / 360 * RETRIEVE * 0.8 / SUBSTEPS) or 0
  local T = 0
  local slipped = 0
  local reeled = 0
  local cw = f.str / (sp.speed * sp.speed)
  local tx, ty = self:restTip()
  for _ = 1, SUBSTEPS do
    local dx, dy = tx - f.x, ty - f.y
    local D = sqrt(dx * dx + dy * dy)
    local ux, uy = dx / D, dy / D
    local kl = S / (0.25 + 0.035 * self.L)
    local k = 1 / (1 / kl + 1 / kr)
    local st = D - self.L
    local rate = -(f.vx * ux + f.vy * uy) -- stretch rate from fish motion
    if st > 0 then T = max(0, k * st + 0.22 * k * rate) else T = 0 end
    -- drag: the spool slips (with inertia) when tension beats the drag
    if T > dragF then
      self.spoolV = self.spoolV + (T - dragF) * 5 * h
    else
      self.spoolV = max(0, self.spoolV - 12 * h)
    end
    if self.spoolV > 0 then
      self.L = self.L + self.spoolV * h
      slipped = slipped + self.spoolV * h
    end
    -- the handle only gains line while the drag holds
    if reelPer > 0 and T < dragF then
      self.L = self.L - reelPer
      reeled = reeled + reelPer
    end
    self.L = max(1.0, self.L + backPer)
    -- fish dynamics
    local ax, ayy
    if f.air then
      ax = T * ux * G / f.mass
      ayy = G + T * uy * G / f.mass
    else
      local F = f.str * f.effort * (0.3 + 0.7 * f.stamina)
      local dl = sqrt(f.dx * f.dx + f.dy * f.dy)
      if dl < 0.01 then dl = 1 end
      local v = sqrt(f.vx * f.vx + f.vy * f.vy)
      ax = (F * f.dx / dl + T * ux - cw * f.vx * v) * G / f.mass
      ayy = (F * f.dy / dl + T * uy - cw * f.vy * v) * G / f.mass
    end
    f.vx = f.vx + ax * h
    f.vy = f.vy + ayy * h
    -- a sulking catfish is dead weight on the bottom until lifted
    local bed = self:bedAt(f.x)
    if f.state == "sulk" and f.y > bed - 0.8 then
      local lift = -uy * T
      if lift < f.str * 0.55 + f.kg * 0.1 then f.vx, f.vy = f.vx * 0.2, max(0, f.vy) * 0.2 end
    end
    f.x = f.x + f.vx * h
    f.y = f.y + f.vy * h
    if f.x > MAXX then f.x = MAXX f.vx = min(0, f.vx) end
    if f.x < 0.8 then f.x = 0.8 f.vx = max(0, f.vx) end
    if f.y > bed - 0.25 then f.y = bed - 0.25 f.vy = min(0, f.vy) end
    if f.air then
      if f.y > 0.2 and f.vy > 0 then
        f.air = false
        f.state, f.stT = "run", 1.2
        self:splash(f.x, 0, 10)
        Audio.sfx.splash(0.7)
        self:shake(2)
        f.jumpsKept = f.jumpsKept + 1
        if sp.id == "trout" and f.jumpsKept >= 3 and not self.tut then self:award("leap") end
      end
    elseif f.y < 0.35 then
      f.y = 0.35
      f.vy = max(0, f.vy)
    end
  end
  self.T = T
  self.flex = min(1.8, T / kr)
  self.slipAcc = self.slipAcc + slipped
  self.fightReel = self.fightReel + reeled
  if abs(f.vx) > 0.2 then f.face = f.vx > 0 and 1 or -1 end
  self.lx, self.ly = f.x, f.y

  -- stamina: pulling against the line tires the fish; slack lets it recover
  local work = T / f.str
  if T > f.str * 0.15 then
    f.stamina = f.stamina - dt * (work ^ 1.2) * (0.5 + f.effort) * 0.075 / sp.endu
  else
    f.stamina = f.stamina + dt * 0.02
  end
  local floorSt = 0
  if f.tutor then floorSt = (self.coach and self.coach.i < 8) and 0.45 or 0 end
  f.stamina = clamp(f.stamina, floorSt, 1)

  -- spray and whirr when the spool runs
  if self.spoolV > 1.2 and self.rng:chance(0.3) then
    local tx2, ty2 = self:restTip()
    self:spawnP(1, tx2, ty2, self.rng:between(-1, 1), -1, 0.4)
  end

  -- failure: snap, thrown hook, torn hook
  if T > S then
    self.strain = self.strain + dt * ((T / S - 1) * 6 + 1.6)
  else
    self.strain = max(0, self.strain - dt * 0.9)
  end
  if self.strain >= 1 then self:snapLine() return end
  if T < S * 0.04 then self.slackT = self.slackT + dt else self.slackT = max(0, self.slackT - dt * 2) end
  local slackLim = sp.slack * (self.tut and 2 or 1)
  if self.slackT > slackLim then self:loseFish("IT THREW THE HOOK", "Slack line: it shook free.") return end
  if f.air and T > S * 0.42 then
    self.tearT = self.tearT + dt
    if self.tearT > 0.22 then self:loseFish("HOOK TORN OUT", "It leapt against a tight line.") return end
  else
    self.tearT = max(0, self.tearT - dt)
  end

  -- landing: a tired fish in the net zone
  if f.x < 4.6 and f.y < 3.6 and not f.air then
    if f.stamina < 0.3 then self:landFish() return end
  end
end

function FishingLine:snapLine()
  Audio.sfx.snap(0.9)
  Audio.play(Audio.SAW, 110, 0.4, 0.3, 0.001, 0.3, 0, 0.1)
  self:shake(7)
  self:flash(2)
  self.snaps = self.snaps + 1
  if not self.tut then self:statAdd("snapped", 1) end
  self:loseFish("SNAP!", "The line parted.")
  if self.mode == "standard" then self.t = min(TRIP, self.t + 15) end -- re-tying the rig
end

function FishingLine:loseFish(title, why)
  local f = self.hooked
  if f then
    f.active = false
    f.respawn = self.rng:between(2, 5)
    f.state = "wander"
  end
  self.hooked = nil
  self.phase = "lost"
  self.phaseT = 0
  self.card = nil
  self.spoolV = 0
  self.T = 0
  self:say(title, 1.8)
  if title ~= "SNAP!" then Audio.sfx.fail() end
  if not self.tut then self.lost = self.lost + 1 end
  if self.tut then self:rewindCoach() end
  if self.mode == "endless" and self.lost >= 3 then self:endTrip() end
end

function FishingLine:landFish()
  local f = self.hooked
  local sp = SPECIES[f.sp]
  local lb = f.kg * 2.2046
  local pts = floor(lb * 10)
  local bonus = 0
  if self.seen[f.sp] == 0 then bonus = 50 end
  if sp.id == "grey" then bonus = bonus + 500 end
  self.seen[f.sp] = 1
  self.caught = self.caught + 1
  if not self.tut then
    self.score = self.score + pts + bonus
    self:statAdd("caught", 1)
    self:statMax("heaviest", floor(lb * 10))
    self:statAdd("sp_" .. sp.id, 1)
    self:award("first")
    local all = true
    for i = 1, NSPECIES_COMMON do
      if Save.stat(self.def.id, "sp_" .. SPECIES[i].id) <= 0 then all = false end
    end
    if all then self:award("creel") end
    if sp.id == "grey" then self:award("grey") end
    if lb >= 10 and self.drag <= 2 then self:award("finesse") end
  end
  if floor(lb * 10) > self.heaviest then
    self.heaviest = floor(lb * 10)
    self.heaviestName = sp.name
  end
  self.cardA = sp.name
  self.cardB = string.format("%.1f lb", lb)
  self.cardC = self.tut and "" or (bonus > 0 and string.format("+%d  NEW +%d", pts, bonus) or string.format("+%d", pts))
  self.card = "landed"
  self.cardT = 2.6
  self.landSp, self.landKg = f.sp, f.kg
  f.active = false
  f.respawn = self.rng:between(1, 4)
  self.hooked = nil
  self.phase = "landing"
  self.phaseT = 0
  self.T = 0
  self.spoolV = 0
  Audio.sfx.splash(0.5)
  Audio.sfx.bell(988, 0.4)
  Audio.sfx.coin()
  self:splash(2.5, 0, 6)
  self:shake(2)
  if self.overtime then self:endTrip() end
end

function FishingLine:endTrip()
  if self.finished then return end
  local kinds = 0
  for i = 1, #self.seen do kinds = kinds + self.seen[i] end
  local lines = {
    "Landed " .. self.caught .. " (" .. kinds .. " kinds)",
    self.heaviest > 0 and string.format("Heaviest: %.1f lb %s", self.heaviest / 10, self.heaviestName) or "Heaviest: -",
    "Snapped " .. self.snaps .. ", lost " .. (self.lost - self.snaps),
  }
  local title
  if self.mode == "endless" then
    title = self.caught > 0 and "OUT OF LINE" or "SKUNKED"
  else
    title = self.caught > 0 and "HOME BY NINE" or "SKUNKED"
  end
  if self.caught > 0 then Audio.sfx.success() else Audio.sfx.fail() end
  self:finish({ success = self.caught > 0, score = self.score, title = title, lines = lines, delay = 1.6 })
end

------------------------------------------------------------------------
-- drawing
------------------------------------------------------------------------
local function drawFishShape(x, y, len, face, pat, eel)
  local h = eel and max(3, floor(len * 0.16)) or max(4, floor(len * 0.38))
  if pat then gfx.setPattern(pat) else gfx.setColor(gfx.kColorBlack) end
  gfx.fillEllipseInRect(x - len / 2, y - h / 2, len, h)
  local tx = x - face * len / 2
  local tl = eel and 2 or max(3, floor(len * 0.25))
  gfx.fillTriangle(tx + face * 2, y, tx - face * tl, y - tl * 0.8, tx - face * tl, y + tl * 0.8)
  if not pat then
    gfx.setColor(gfx.kColorWhite)
    gfx.drawPixel(x + face * (len / 2 - 3), y - 1)
    if len > 14 then gfx.drawLine(x + face * (len / 2 - 7), y - h / 2 + 2, x + face * (len / 2 - 7), y + h / 2 - 2) end
  end
  gfx.setColor(gfx.kColorBlack)
end

local function drawFishGhost(x, y, len, face, eel)
  local h = eel and max(3, floor(len * 0.16)) or max(4, floor(len * 0.38))
  gfx.setColor(gfx.kColorWhite)
  gfx.fillEllipseInRect(x - len / 2, y - h / 2, len, h)
  gfx.setColor(gfx.kColorBlack)
  gfx.setDitherPattern(0.5, gfx.kDitherTypeBayer4x4)
  gfx.drawEllipseInRect(x - len / 2, y - h / 2, len, h)
  local tx = x - face * len / 2
  gfx.drawLine(tx, y, tx - face * 4, y - 3)
  gfx.drawLine(tx, y, tx - face * 4, y + 3)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawPixel(x + face * (len / 2 - 3), y - 1)
end

function FishingLine:fishLen(f) return self:fishLenOf(f.sp, f.kg) end

local SUNX <const> = 240
function FishingLine:drawSky()
  -- dawn: dark to light over the trip (endless drifts through the day)
  local p
  if self.mode == "standard" then p = self.t / TRIP else p = 0.5 + 0.5 * sin(self.t / 60) end
  local shade = clamp(0.42 * (1 - p), 0, 0.42)
  Art.setShade(shade)
  gfx.fillRect(0, 18, 400, 76)
  -- the sun climbs out of the sea
  local sunY = floor(98 - p * 58)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(SUNX, sunY, 11)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawCircleAtPoint(SUNX, sunY, 11)
  for i = 0, 7 do
    local a = rad(i * 45 + self.anim * 6)
    gfx.drawLine(SUNX + sin(a) * 14, sunY - cos(a) * 14, SUNX + sin(a) * 18, sunY - cos(a) * 18)
  end
  self.skyImg:draw(0, 18)
  -- two gulls
  for g = 0, 1 do
    local gx = (self.anim * (9 + g * 5) + g * 170) % 460 - 30
    local gy = 34 + g * 12 + sin(self.anim * 2 + g) * 3
    local flap = floor(self.anim * 5 + g * 2) % 2
    gfx.drawLine(gx - 5, gy - 2 + flap * 3, gx, gy)
    gfx.drawLine(gx, gy, gx + 5, gy - 2 + flap * 3)
  end
end

function FishingLine:drawWater()
  self.underImg:draw(0, OY)
  -- surface: rolling line with foam dashes
  gfx.setColor(gfx.kColorBlack)
  local t = self.anim
  local amp = 1 + self.swellAmp * 4
  local px, py = 0, OY + sin(t * 1.5) * amp
  for x = 10, 400, 10 do
    local ny = OY + sin(t * 1.5 + x * 0.05) * amp + sin(t * 2.3 + x * 0.13) * 0.6
    gfx.drawLine(px, py, x, ny)
    px, py = x, ny
  end
  for x = 0, 400, 26 do
    local ox = (x + t * 8) % 400
    local yy = OY + 4 + ((x // 26) % 3) * 3
    gfx.drawLine(ox, yy, ox + 5, yy)
  end
end

function FishingLine:drawFish()
  for i = 1, self.nFish do
    local f = self.fish[i]
    if f.active then
      local x, y = wx(f.x), wy(f.y)
      local len = self:fishLen(f)
      local eel = SPECIES[f.sp].id == "eel"
      if f == self.hooked then
        local hh = eel and max(3, floor(len * 0.16)) or max(4, floor(len * 0.38))
        gfx.setColor(gfx.kColorWhite)
        gfx.fillEllipseInRect(x - len / 2 - 2, y - hh / 2 - 2, len + 4, hh + 4)
        drawFishShape(x, y, len, f.face, nil, eel)
        if f.air then
          gfx.setColor(gfx.kColorBlack)
          gfx.drawLine(x - 8, y + 6, x - 12, y + 10)
          gfx.drawLine(x + 8, y + 6, x + 12, y + 10)
        end
      else
        local dxl, dyl = f.x - self.lx, f.y - self.ly
        local nearLure = self.phase == "water" and dxl * dxl + dyl * dyl < 16
        if f.y < 3.5 then
          drawFishShape(x, y, len, f.face, Art.pat.gray75, eel)
        elseif nearLure then
          drawFishGhost(x, y, len, f.face, eel)
        end
      end
    end
  end
end

function FishingLine:drawParticles()
  for i = 1, MAXP do
    local k = self.pk[i]
    if k ~= 0 then
      local x, y = wx(self.px[i]), wy(self.py[i])
      if k == 1 then
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(x, y, 2, 2)
      elseif k == 2 then
        gfx.setColor(gfx.kColorWhite)
        gfx.fillCircleAtPoint(x, y, 2)
        gfx.setColor(gfx.kColorBlack)
        gfx.drawCircleAtPoint(x, y, 2)
      else
        local r = floor((1 - self.pl[i]) * 14) + 3
        gfx.setColor(gfx.kColorBlack)
        gfx.drawEllipseInRect(x - r, OY - 2, r * 2, 4)
      end
    end
  end
  gfx.setColor(gfx.kColorBlack)
end

-- quadratic curve helper (no allocation)
local function curve(x0, y0, cx, cy, x1, y1, n)
  local px, py = x0, y0
  for i = 1, n do
    local t = i / n
    local a, b, c = (1 - t) * (1 - t), 2 * (1 - t) * t, t * t
    local x, y = a * x0 + b * cx + c * x1, a * y0 + b * cy + c * y1
    gfx.drawLine(px, py, x, y)
    px, py = x, y
  end
end

function FishingLine:drawRig()
  local bob = floor(sin(self.anim * 1.7) * 1 + self.swellY * PX * 0.6)
  self.boatImg:draw(0, 50 + bob)
  -- rod
  local bx, by = wx(BUTT_X), wy(BUTT_Y) + bob
  local tx, ty = self:restTip()
  local ang = 16 + self.ra * 66
  if self.phase == "ready" and self.windup > 0 then ang = ang + self.windup * 0.7 end
  local a = rad(ang)
  local rtx, rty = BUTT_X + cos(a) * ROD_LEN, BUTT_Y - sin(a) * ROD_LEN + self.swellY
  local ex, ey
  if self.phase == "fight" or self.phase == "water" then ex, ey = self.lx, self.ly else ex, ey = rtx, rty + 1 end
  local ldx, ldy = ex - rtx, ey - rty
  local ld = sqrt(ldx * ldx + ldy * ldy)
  if ld < 0.01 then ld = 1 end
  local bend = self.flex
  if self.phase ~= "fight" then bend = 0.12 + self.twitch * 0.25 + self.biteDip * 0.9 end
  local ftx = rtx + ldx / ld * bend * 0.8
  local fty = rty + ldy / ld * bend * 0.8 + self.twitch * 0.1
  local sx1, sy1 = wx(ftx), wy(fty) + bob
  local cx, cy = (bx + wx(rtx)) / 2, (by + wy(rty)) / 2 + bob / 2
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(2)
  curve(bx, by, cx, cy, sx1, sy1, 6)
  gfx.setLineWidth(1)
  -- reel with turning handle
  gfx.fillCircleAtPoint(bx + 3, by + 2, 3)
  local ra = rad(self.reelAng)
  gfx.drawLine(bx + 3, by + 2, bx + 3 + sin(ra) * 5, by + 2 - cos(ra) * 5)
  gfx.fillRect(bx + 2 + sin(ra) * 5, by + 1 - cos(ra) * 5, 2, 2)
  if self.bail then
    gfx.drawCircleAtPoint(bx + 3, by + 2, 6)
  end
  -- line to the lure or fish
  local lx, ly = wx(ex), wy(ey)
  local slack = 0
  local dx, dy = ex - ftx, ey - fty
  local D = sqrt(dx * dx + dy * dy)
  if self.phase == "fight" then slack = max(0, self.L - D)
  elseif self.phase == "water" then slack = max(0, self.L - D) end
  if self.phase == "ready" or self.phase == "landing" or self.phase == "lost" then
    lx, ly = wx(self.lx), wy(self.ly) + bob
    gfx.drawLine(sx1, sy1, lx, ly)
  elseif self.phase == "flight" then
    lx, ly = wx(self.lx), wy(self.ly)
    curve(sx1, sy1, (sx1 + lx) / 2, (sy1 + ly) / 2 + (self.bail and 10 or 2), lx, ly, 6)
  else
    local sag = min(34, slack * PX * 0.7)
    local jit = (self.T > self.S * 0.8) and ((floor(self.anim * 30) % 2) * 2 - 1) or 0
    if sag > 0.5 then
      curve(sx1, sy1, (sx1 + lx) / 2, (sy1 + ly) / 2 + sag, lx, ly, 8)
    else
      gfx.drawLine(sx1, sy1, (sx1 + lx) / 2 + jit, (sy1 + ly) / 2)
      gfx.drawLine((sx1 + lx) / 2 + jit, (sy1 + ly) / 2, lx, ly)
    end
  end
  -- lure (spoon)
  if self.phase ~= "fight" and self.phase ~= "landing" then
    gfx.setColor(gfx.kColorBlack)
    gfx.fillEllipseInRect(lx - 2, ly - 1, 5, 4)
    gfx.drawLine(lx + 1, ly + 3, lx + 1, ly + 5)
    gfx.drawPixel(lx + 2, ly + 5)
  end
end

function FishingLine:drawHUD()
  local x0, y0 = 262, 21
  UI.panel(x0, y0, 136, 50, "plain")
  -- tension gauge with danger zone and a drag marker
  local tr = self.T / self.S
  local blink = self.strain > 0.25 and (floor(self.anim * 12) % 2 == 0)
  UI.text("TENSION", x0 + 6, y0 + 2)
  local gx, gy, gw = x0 + 6, y0 + 18, 124
  UI.gauge(gx, gy, gw, 10, min(1, tr), nil, 0.85)
  if blink then
    gfx.setColor(gfx.kColorXOR)
    gfx.fillRect(gx, gy, gw, 10)
    gfx.setColor(gfx.kColorBlack)
  end
  local df = min(1, DRAG_FRAC[self.drag])
  local mx = gx + floor(gw * df)
  gfx.fillTriangle(mx - 3, gy - 5, mx + 3, gy - 5, mx, gy)
  -- drag pips and line out
  UI.text("DRAG", x0 + 6, y0 + 31)
  for i = 1, #DRAG_FRAC do
    local px = x0 + 48 + (i - 1) * 9
    if i <= self.drag then gfx.fillRect(px, y0 + 35, 7, 8) else gfx.drawRect(px, y0 + 35, 7, 8) end
  end
  if self.dragFlash > 0 then UI.text(DRAG_NAME[self.drag], x0 + 96, y0 + 31, "left", UI.bold)
  else UI.text(METRES[clamp(floor(self.L), 0, 99)], x0 + 130, y0 + 31, "right") end
end

function FishingLine:drawCard()
  if self.card == "hooked" and self.hooked then
    local f = self.hooked
    local sp = SPECIES[f.sp]
    local x0, y0 = 118, 21
    UI.panel(x0, y0, 140, 50, "ink")
    UI.textW(sp.name, x0 + 70, y0 + 4, "center", UI.bold)
    UI.textW(sp.hint, x0 + 70, y0 + 19, "center")
    -- stamina bar
    gfx.setColor(gfx.kColorWhite)
    gfx.drawRect(x0 + 10, y0 + 36, 120, 8)
    gfx.fillRect(x0 + 12, y0 + 38, floor(116 * f.stamina), 4)
    gfx.setColor(gfx.kColorBlack)
  elseif self.card == "landed" and self.cardT > 0 then
    local x0, y0 = 110, 104
    UI.popup(x0, y0, 180, 70, "paper")
    UI.text(self.cardA, x0 + 90, y0 + 9, "center", UI.bold)
    drawFishShape(x0 + 90, y0 + 34, min(120, self:fishLenOf(self.landSp, self.landKg) * 1.5), 1, nil, SPECIES[self.landSp].id == "eel")
    UI.text(self.cardB, x0 + 12, y0 + 48)
    UI.text(self.cardC, x0 + 168, y0 + 48, "right", UI.bold)
  end
end

function FishingLine:fishLenOf(sp, kg) return min(84, clamp(12 + kg * 3, 12, 56) * SPECIES[sp].len + (sp == 6 and 30 or 0)) end

function FishingLine:headerText()
  if self.mode == "standard" then
    return CLOCK[clamp(floor(self.t), 0, 240)]
  elseif self.mode == "endless" then
    local key = self.caught * 10 + self.lost
    if key ~= self.hdrKey then
      self.hdrKey = key
      self.hdrStr = string.format("FISH %d  LOST %d/3", self.caught, self.lost)
    end
    return self.hdrStr
  end
  return "LESSON"
end

function FishingLine:draw()
  gfx.clear(gfx.kColorWhite)
  self:drawSky()
  self:drawWater()
  self:drawFish()
  self:drawParticles()
  self:drawRig()
  self:drawHUD()
  self:drawCard()
  -- bite cue: an exclamation over the rod tip when it dives
  if self.biteDip > 0.5 and self.phase == "water" then
    local tx, ty = self:restTip()
    local x, y = wx(tx), wy(ty) - 16
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRoundRect(x - 6, y - 6, 12, 16, 3)
    UI.textW("!", x, y - 5, "center", UI.bold)
  end
  if self.phase == "ready" and not self.finished then
    if self.bail then
      UI.text(self.windup < 25 and "CRANK BACK..." or "...FLICK!", 110, 76, "left", UI.bold)
    end
  end
  if self.msgT > 0 and self.msg then
    local w = UI.width(self.msg, UI.bold) + 20
    UI.panel(200 - w / 2, 100, w, 22, "ink")
    UI.textW(self.msg, 200, 103, "center", UI.bold)
  end
  UI.header(2, "FISHING LINE", self:headerText())
  do
    local h = HINTS_READY
    if self.phase == "flight" then h = HINTS_CAST
    elseif self.phase == "water" then h = HINTS_WATER
    elseif self.phase == "fight" then h = HINTS_FIGHT end
    UI.hints(h)
  end
end

------------------------------------------------------------------------
-- suspend / resume (the rig is re-tied; the fish in the water are new)
------------------------------------------------------------------------
function FishingLine:serialize()
  return {
    t = self.t, score = self.score, caught = self.caught, lost = self.lost,
    snaps = self.snaps, heaviest = self.heaviest, heaviestName = self.heaviestName,
    seen = self.seen, drag = self.drag, ra = self.ra, rng = self.rng:state(),
  }
end

function FishingLine:deserialize(s)
  self.t = s.t or 0
  self.score = s.score or 0
  self.caught = s.caught or 0
  self.lost = s.lost or 0
  self.snaps = s.snaps or 0
  self.heaviest = s.heaviest or 0
  self.heaviestName = s.heaviestName or "-"
  if type(s.seen) == "table" and #s.seen == 6 then self.seen = s.seen end
  self.drag = clamp(s.drag or 3, 1, #DRAG_FRAC)
  self.ra = clamp(s.ra or 0.35, 0, 1)
  if s.rng then self.rng:setState(s.rng) end
  if not self.tut then
    for i = 1, self.nFish do self:spawnFish(self.fish[i]) end
  end
  self:resetRig()
end
