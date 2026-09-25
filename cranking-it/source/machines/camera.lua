-- CRANKING IT :: No.3 FILM CAMERA
--
-- The crank IS the film-advance knob of a folding roll-film camera.
--   * Clockwise winds the film through a ratchet (a click every 15 degrees).
--     Counter-clockwise is caught by the pawl and does nothing.
--   * The take-up spool fattens as film collects on it, so the knob turns
--     LESS per frame as the roll goes on (about 1.3 turns at frame 1, 1.05
--     at frame 12). Counting turns fails: you read the backing paper's
--     numbers through the red window and stop when the next one is centred.
--   * There is no double-exposure interlock. The shutter fires wherever the
--     film is: an under-wound frame overlaps its neighbour, an unwound one
--     is a full double exposure, over-winding wastes the fixed-length roll.
--   * The crank must be STILL while you compose and expose: a turning crank
--     jolts the camera and, during an exposure, drags the film (smear).
--   * Rewind is a different physical action: hold B and back the crank one
--     full turn to release the rewind, then crank backward many turns. Racing
--     it makes static sparks that mark the negatives.
-- Each exposure stores the scene state (time, framing, settings, camera
-- motion). Subjects move on closed-form paths, so every thumbnail on the
-- contact sheet is rendered from those numbers - once when the shutter
-- closes, and again after a resume.

local gfx <const> = playdate.graphics
local floor <const> = math.floor
local abs <const> = math.abs
local min <const>, max <const> = math.min, math.max
local sin <const>, cos <const>, rad <const>, sqrt <const> = math.sin, math.cos, math.rad, math.sqrt

------------------------------------------------------------------------
-- constants
------------------------------------------------------------------------
local VX <const>, VY <const>, VS <const> = 5, 22, 168   -- viewfinder window
local WORLD_W <const> = 800
local OY_MAX <const> = 32
local HORIZON <const> = 110
local SUNX <const> = 318
local FRAMES <const> = 12
local FILM_END <const> = 12.62        -- knob stops here (frame units)
local FILM_LO <const>, FILM_HI <const> = 0.3, 12.82
local FW <const> = 0.9                -- exposed width of a frame, in frame units
local THUMB <const> = 56
local LOUPE <const> = 112
local UNIT <const> = 62               -- contact sheet px per frame unit
local DAY_STD <const> = 210
local DAY_END <const> = 480
local REW_DPF <const> = 290           -- rewind knob degrees per frame
local LIT_EV <const> = 11.5
local FRAME_PX <const> = VS / FW      -- world px per frame unit (film smear)

local S_FERRY <const>, S_GULL <const>, S_DOG <const>, S_COUPLE <const> = 1, 2, 3, 4
local S_CYCLIST <const>, S_LIGHT <const>, S_SPIRE <const>, S_SAIL <const>, S_FIGURE <const> = 5, 6, 7, 8, 9
local SUBJ_NAME <const> = { "FERRY", "GULL", "DOG", "COUPLE", "CYCLIST", "LIGHTHOUSE", "SPIRE", "SAILBOAT", "FIGURE" }
local R_ANY <const>, R_CENTRED <const>, R_WHOLE <const>, R_SHARP <const>, R_LIT <const>, R_PANNED <const> = 1, 2, 3, 4, 5, 6
local REQ_NAME <const> = { "", ", CENTRED", ", WHOLE", ", SHARP", ", LIT", ", PANNED" }
local REQ_SHORT <const> = { "ANY", "CENTRED", "WHOLE", "SHARP", "LIT", "PANNED" }
-- pool of brief items {subject, requirement}
local POOL <const> = {
  { S_FERRY, R_WHOLE }, { S_FERRY, R_CENTRED }, { S_GULL, R_SHARP }, { S_DOG, R_SHARP },
  { S_COUPLE, R_CENTRED }, { S_CYCLIST, R_CENTRED }, { S_CYCLIST, R_PANNED },
  { S_SPIRE, R_CENTRED }, { S_SAIL, R_CENTRED },
}

local APERTURES <const> = { "f/2.8", "f/4", "f/5.6", "f/8", "f/11", "f/16", "f/22" }
local SHUTTERS <const> = { "1s", "1/2", "1/4", "1/8", "1/15", "1/30", "1/60", "1/125", "1/250", "1/500" }
local NUMS = {}
for i = 0, 40 do NUMS[i] = tostring(i) end

-- static world geometry (world units, 800 x 200)
local HEAD <const> = { 220, 110, 262, 104, 300, 99, 350, 96, 400, 99, 450, 102, 520, 106, 570, 110 }
local CLIFF <const> = { 0, 68, 40, 64, 118, 66, 150, 73, 172, 92, 188, 116, 196, 140, 204, 200, 0, 200 }
local FIG_X <const> = { 382, 136, 606, 508 }
local FIG_Y <const> = { 124, 70, 144, 124 }

------------------------------------------------------------------------
-- drawing transform (world -> target), shared by viewfinder, thumbnails,
-- loupe and icons so every image of the harbour is drawn by the same code
------------------------------------------------------------------------
local XO, YO, XS, X0, Y0, VW = 0, 0, 1, 0, 0, WORLD_W
local GHOST = false  -- motion-blur ghost pass: ink only, 50% pattern
local FAINT = false

local function setXf(ox, oy, s, x0, y0, vw) XO, YO, XS, X0, Y0, VW = ox, oy, s, x0, y0, vw end
local function tx(wx) return X0 + (wx - XO) * XS end
local function ty(wy) return Y0 + (wy - YO) * XS end
local function off(x0, x1) return x1 < XO - 4 or x0 > XO + VW + 4 end
local function R(x, y, w, h) gfx.fillRect(tx(x), ty(y), max(1, w * XS), max(1, h * XS)) end
local function RO(x, y, w, h) gfx.drawRect(tx(x), ty(y), max(1, w * XS), max(1, h * XS)) end
local function L(x1, y1, x2, y2) gfx.drawLine(tx(x1), ty(y1), tx(x2), ty(y2)) end
local function C(x, y, r) gfx.fillCircleAtPoint(tx(x), ty(y), max(0.7, r * XS)) end
local function CO(x, y, r) gfx.drawCircleAtPoint(tx(x), ty(y), max(1, r * XS)) end
local function T(x1, y1, x2, y2, x3, y3) gfx.fillTriangle(tx(x1), ty(y1), tx(x2), ty(y2), tx(x3), ty(y3)) end
local function LW(w) gfx.setLineWidth(max(1, floor(w * XS + 0.5))) end
local PL = Art.poly
local function pv(i, x, y) PL[2 * i - 1] = tx(x) PL[2 * i] = ty(y) end
local function polyFrom(t)
  local n = #t // 2
  for i = 1, n do pv(i, t[2 * i - 1], t[2 * i]) end
  return n * 2
end

local function ink()
  if GHOST then gfx.setPattern(Art.pat.gray50)
  elseif FAINT then gfx.setPattern(Art.pat.gray50)
  else gfx.setColor(gfx.kColorBlack) end
end
-- returns false in ghost passes (only ink smears)
local function paper()
  if GHOST or FAINT then return false end
  gfx.setColor(gfx.kColorWhite)
  return true
end

------------------------------------------------------------------------
-- closed-form subject paths
------------------------------------------------------------------------
local function triw(ph)
  local x = ph % 1
  if x < 0.5 then return 4 * x - 1, 1 end
  return 3 - 4 * x, -1
end

local function ferryAt(W, t)
  local v, d = triw((t + W.ferryPh) / (4 * W.ferryAmp / W.ferryV))
  return W.ferryMid + W.ferryAmp * v, d
end
local function sailAt(W, t)
  local v, d = triw((t + W.sailPh) / (4 * W.sailAmp / W.sailV))
  return W.sailMid + W.sailAmp * v, d
end
local function cycAt(W, t)
  local v, d = triw((t + W.cycPh) / (4 * 96 / W.cycV))
  return 683 + 96 * v, d
end
local function dogAt(W, t)
  local v, d = triw((t + W.dogPh) / (4 * 100 / W.dogV))
  return 682 + 100 * v, d
end
local function gullAt(W, i, t)
  local g = W.gulls[i]
  local x = (g.x0 + g.v * t) % 920 - 60
  local y = g.y0 + g.amp * sin(t * g.w + g.ph)
  return x, y, g.v > 0 and 1 or -1
end
local function coupleAt(W, t) return W.coupleX + 40 * sin(t * 0.16 + W.couplePh) end
-- returns spot index 1..4 or 0
local function figureAt(W, t)
  local ft = W.figT
  for k = 1, #ft do
    if t < ft[k] then return 0 end
    if t < ft[k] + 7 then return W.figS[k] end
  end
  return 0
end

-- centre + half extents of subject k at time t (sub = gull index)
local function subjBox(W, k, t, sub)
  if k == S_FERRY then local x = ferryAt(W, t) return x, 109, 36, 15
  elseif k == S_GULL then local x, y = gullAt(W, sub or 1, t) return x, y, 8, 4
  elseif k == S_DOG then local x = dogAt(W, t) return x, 138, 10, 6
  elseif k == S_COUPLE then return coupleAt(W, t), 115, 7, 10
  elseif k == S_CYCLIST then local x = cycAt(W, t) return x, 131, 13, 13
  elseif k == S_LIGHT then return 70, 38, 12, 34
  elseif k == S_SPIRE then return W.churchX, 71, 9, 57
  elseif k == S_SAIL then local x = sailAt(W, t) return x + 1, 102, 7, 7
  elseif k == S_FIGURE then
    local s = figureAt(W, t)
    if s == 0 then return nil end
    return FIG_X[s], FIG_Y[s] - 12, 4, 13
  end
end

-- visible fraction of a box in a VS x VS frame at (ox, oy)
local function visFrac(cx, cy, hw, hh, ox, oy)
  local x0, x1 = max(cx - hw, ox), min(cx + hw, ox + VS)
  local y0, y1 = max(cy - hh, oy), min(cy + hh, oy + VS)
  if x1 <= x0 or y1 <= y0 then return 0 end
  return (x1 - x0) * (y1 - y0) / (4 * hw * hh)
end

------------------------------------------------------------------------
-- world generation (from its own seed so it can be rebuilt on resume)
------------------------------------------------------------------------
local function genWorld(seed, diff)
  local r = U.rng(seed)
  local sp = 1 + 0.12 * (diff - 1)
  local W = {}
  W.ferryMid, W.ferryAmp = r:between(270, 290), r:between(66, 80)
  W.ferryV, W.ferryPh = r:between(11, 14) * sp, r:between(0, 60)
  W.sailMid, W.sailAmp = r:between(330, 420), r:between(50, 90)
  W.sailV, W.sailPh = r:between(3, 5), r:between(0, 100)
  W.cycV, W.cycPh = r:between(31, 36) * sp, r:between(0, 40)
  W.dogV, W.dogPh = r:between(40, 50) * sp, r:between(0, 40)
  W.coupleX, W.couplePh = r:between(420, 470), r:between(0, 6)
  W.lightPh, W.lightV = r:between(0, 360), 50
  W.gulls = {}
  for i = 1, 3 do
    W.gulls[i] = { x0 = r:between(0, 900), v = r:between(50, 64) * sp * (r:chance(0.5) and 1 or -1),
      y0 = r:between(30, 78), amp = r:between(6, 15), w = r:between(0.4, 0.9), ph = r:between(0, 6.28) }
  end
  W.clouds = {}
  for i = 1, 2 + diff do
    W.clouds[i] = { x0 = r:between(0, 1100), y = r:between(18, 44), v = r:between(4, 8) * (r:chance(0.5) and 1 or -1),
      size = r:between(20, 34) }
  end
  -- houses along the quay, one of them the church
  W.hx, W.hw, W.hh, W.roof = {}, {}, {}, {}
  W.winX, W.winY, W.winLit = {}, {}, {}
  local churchSlot = r:range(2, 4)
  local x, i = 568, 0
  while x < 786 do
    i = i + 1
    local w = r:range(22, 34)
    if i == churchSlot then w = 20 end
    if x + w > 798 then w = 798 - x end
    W.hx[i], W.hw[i] = x, w
    if i == churchSlot then
      W.churchX = x + w / 2
      W.hh[i], W.roof[i] = 64, 0
    else
      W.hh[i], W.roof[i] = r:range(30, 54), r:range(1, 3)
      local base = 128 - W.hh[i]
      for wy = base + 8, 118, 11 do
        for wx = x + 4, x + w - 7, 8 do
          local n = #W.winX + 1
          W.winX[n], W.winY[n] = wx, wy
          W.winLit[n] = r:chance(0.45)
        end
      end
    end
    x = x + w + r:range(0, 3)
  end
  -- appearances of the stranger
  W.figT, W.figS = {}, {}
  local ft = r:between(35, 60)
  for k = 1, 24 do
    W.figT[k], W.figS[k] = ft, r:range(1, 4)
    ft = ft + r:between(50, 80)
  end
  return W
end

------------------------------------------------------------------------
-- static world (cached at full scale, drawn as vectors for thumbnails)
------------------------------------------------------------------------
local function drawLighthouse()
  ink()
  -- tower
  if paper() then pv(1, 60, 70) pv(2, 80, 70) pv(3, 76, 24) pv(4, 64, 24) Art.polyFill(8) end
  ink()
  for b = 0, 2 do
    local y0 = 30 + b * 14
    local y1 = y0 + 6
    local lx0, lx1 = 64 - (y0 - 24) / 46 * 4, 64 - (y1 - 24) / 46 * 4
    pv(1, lx1, y1) pv(2, 140 - lx1, y1) pv(3, 140 - lx0, y0) pv(4, lx0, y0)
    Art.polyFill(8)
  end
  L(60, 70, 64, 24) L(80, 70, 76, 24)
  R(59, 21, 22, 3)                     -- gallery
  L(59, 18, 59, 21) L(81, 18, 81, 21)
  RO(64, 10, 12, 11)                   -- lamp room
  L(68, 10, 68, 21) L(72, 10, 72, 21)
  T(61, 11, 79, 11, 70, 3)             -- cap
  L(70, 3, 70, 0)
  R(68, 62, 4, 8)                      -- door
  -- keeper's cottage
  if paper() then R(96, 56, 28, 13) end
  ink()
  RO(96, 56, 28, 13)
  T(93, 57, 127, 57, 110, 46)
  R(114, 49, 3, 6)
  R(100, 60, 5, 5) R(113, 61, 4, 8)
end

local function drawChurch(cx, base)
  ink()
  if paper() then R(cx - 8, base - 64, 16, 64) end
  ink()
  RO(cx - 8, base - 64, 16, 64)
  T(cx - 9, base - 64, cx + 9, base - 64, cx, base - 114)
  L(cx, base - 114, cx, base - 120)
  L(cx - 2, base - 118, cx + 2, base - 118)
  CO(cx, base - 52, 4)
  L(cx, base - 52, cx, base - 55)
  R(cx - 3, base - 38, 6, 8)
  R(cx - 3, base - 12, 6, 12)
end

local function drawStatic(W)
  -- distant headland across the bay
  if not off(220, 570) then
    gfx.setPattern(Art.pat.gray25)
    Art.polyFill(polyFrom(HEAD))
  end
  -- sea
  if not off(150, 570) then
    gfx.setPattern(Art.pat.gray6)
    R(150, 110, 420, 90)
    ink()
    L(150, 110, 570, 110)
    -- woodcut wave strokes, spaced wider toward the viewer
    local y, gap, row = 114, 5, 0
    while y < 200 do
      local len = 4 + row * 1.6
      local x = 150 + ((row * 37) % 23)
      while x < 566 do
        if not off(x, x + len) then L(x, y, x + len, y) end
        x = x + len + 10 + ((row * 13 + floor(x)) % 17)
      end
      row = row + 1
      y = y + gap
      gap = gap + 1
    end
  end
  -- cliff and rocks
  if not off(0, 210) then
    gfx.setPattern(Art.pat.hatch)
    Art.polyFill(polyFrom(CLIFF))
    ink()
    LW(2)
    for i = 1, #CLIFF - 4, 2 do L(CLIFF[i], CLIFF[i + 1], CLIFF[i + 2], CLIFF[i + 3]) end
    gfx.setLineWidth(1)
    L(20, 84, 90, 88) L(60, 104, 150, 110) L(30, 130, 170, 138)
    C(200, 150, 7) C(214, 156, 5) C(190, 170, 9)
    if paper() then L(193, 158, 207, 158) L(206, 161, 220, 161) end
    ink()
    -- grass tufts
    for gx = 8, 150, 14 do L(gx, 66, gx - 2, 62) L(gx, 66, gx + 2, 62) end
    drawLighthouse()
  end
  -- pier
  if not off(366, 582) then
    ink()
    R(370, 124, 210, 4)
    L(370, 118, 580, 118)
    for px = 372, 578, 10 do L(px, 118, px, 124) end
    for px = 374, 578, 14 do R(px, 128, 2, 20) end
    -- lamp post at the end
    R(375, 104, 2, 20)
    RO(373, 99, 6, 5)
  end
  -- quay, road and town
  if not off(556, 800) then
    ink()
    gfx.setPattern(Art.pat.bricks)
    R(560, 146, 240, 54)
    ink()
    L(560, 128, 800, 128)
    L(560, 146, 800, 146)
    L(560, 128, 560, 200)
    for dx = 572, 800, 22 do L(dx, 137, dx + 8, 137) end
    -- moored boat
    T(538, 150, 558, 150, 555, 156) R(541, 150, 14, 2)
    for i = 1, #W.hx do
      local x, w, h = W.hx[i], W.hw[i], W.hh[i]
      if not off(x, x + w) then
        if W.roof[i] == 0 then
          drawChurch(x + w / 2, 128)
        else
          local top = 128 - h
          if paper() then R(x, top, w, h) end
          if i % 3 == 0 then gfx.setPattern(Art.pat.gray12) R(x, top, w, h) end
          ink()
          RO(x, top, w, h)
          if W.roof[i] == 1 then
            T(x - 2, top, x + w + 2, top, x + w / 2, top - 12)
          elseif W.roof[i] == 2 then
            R(x - 1, top - 3, w + 2, 3)
            R(x + w - 8, top - 10, 4, 7)
          else
            gfx.setPattern(Art.pat.hatchD)
            T(x - 2, top, x + w + 2, top, x + w / 2, top - 16)
            ink()
            L(x - 2, top, x + w / 2, top - 16) L(x + w + 2, top, x + w / 2, top - 16)
          end
          R(x + w / 2 - 3, 119, 6, 9)
        end
      end
    end
    for n = 1, #W.winX do
      if not off(W.winX[n], W.winX[n] + 3) then R(W.winX[n], W.winY[n], 3, 4) end
    end
  end
end

------------------------------------------------------------------------
-- sky and moving subjects
------------------------------------------------------------------------
local function evBaseAt(self, wt)
  if self.tut then return 14 end
  local u = wt / self.dayLen
  local ev = 15 - 1.5 * u - 5.5 * U.smoothstep((u - 0.55) / 0.45)
  if u > 1 then ev = ev - 2.6 * (u - 1) end
  return max(3.5, ev)
end

local function sunY(self, wt)
  if self.tut then return -60 end -- high overhead, out of the lesson's frame
  local u = wt / self.dayLen
  return 22 + (HORIZON + 14 - 22) * U.smoothstep(u / 0.95)
end

local function cloudX(c, t) return (c.x0 + c.v * t) % 1100 - 150 end

local function drawSky(self, W, t)
  local sy = sunY(self, t)
  if sy < HORIZON + 10 and not off(SUNX - 12, SUNX + 12) then
    ink()
    C(SUNX, sy, 10)
    if paper() then C(SUNX, sy, 8) end
    ink()
    if sy < 80 then
      for a = 0, 7 do
        local s, c = sin(a * 0.785), cos(a * 0.785)
        L(SUNX + s * 12, sy - c * 12, SUNX + s * 16, sy - c * 16)
      end
    end
  end
  for i = 1, #W.clouds do
    local c = W.clouds[i]
    local cx, cy, s = cloudX(c, t), c.y, c.size
    if not off(cx - s * 1.2, cx + s * 1.2) then
      ink()
      C(cx - s * 0.5, cy, s * 0.45 + 1) C(cx, cy - s * 0.2, s * 0.55 + 1) C(cx + s * 0.55, cy, s * 0.4 + 1)
      if paper() then
        C(cx - s * 0.5, cy, s * 0.45) C(cx, cy - s * 0.2, s * 0.55) C(cx + s * 0.55, cy, s * 0.4)
        R(cx - s, cy + s * 0.18, s * 2, s * 0.4)
      end
      ink()
      L(cx - s * 0.9, cy + s * 0.2, cx + s * 0.95, cy + s * 0.2)
      L(cx - s * 0.5, cy + s * 0.14, cx + s * 0.1, cy + s * 0.14)
    end
  end
end

local function drawFerry(x, d)
  if off(x - 40, x + 40) then return end
  ink()
  pv(1, x - d * 33, 113) pv(2, x + d * 37, 111) pv(3, x + d * 29, 124) pv(4, x - d * 31, 124)
  Art.polyFill(8)
  local cx = x - d * 3
  if paper() then R(cx - 14, 104, 26, 9) end
  ink()
  RO(cx - 14, 104, 26, 9)
  C(cx - 8, 108.5, 1.3) C(cx - 2, 108.5, 1.3) C(cx + 4, 108.5, 1.3)
  local fx = x - d * 9
  R(fx - 3, 94, 6, 10)
  if paper() then R(fx - 3, 97, 6, 2) end
  ink()
  L(x + d * 30, 111, x + d * 22, 98) L(x + d * 22, 98, fx, 94)
  if not GHOST then gfx.setPattern(Art.pat.gray50) end
  for k = 1, 3 do C(fx - d * (5 + k * 8), 91 - k * 3, 2 + k) end
end

local function drawSail(x)
  if off(x - 8, x + 10) then return end
  ink()
  R(x - 6, 108, 12, 2)
  L(x, 95, x, 108)
  if paper() then T(x + 1, 96, x + 1, 107, x + 8, 107) end
  ink()
  L(x + 1, 96, x + 8, 107) L(x + 8, 107, x + 1, 107)
end

local function drawGull(x, y, fl)
  if off(x - 8, x + 8) then return end
  ink()
  LW(XS < 0.5 and 1 or 2)
  local up = fl * 3.5
  L(x - 8, y - up, x - 3, y) L(x - 3, y, x, y + 1) L(x, y + 1, x + 3, y) L(x + 3, y, x + 8, y - up)
  gfx.setLineWidth(1)
end

local function drawCouple(x)
  if off(x - 8, x + 8) then return end
  ink()
  C(x - 3, 107, 2) R(x - 5, 102.5, 4, 2)
  R(x - 5, 109, 4, 8)
  L(x - 4, 117, x - 5, 124) L(x - 2, 117, x - 1, 124)
  C(x + 3, 108, 2)
  T(x + 3, 110, x - 0.5, 121, x + 6.5, 121)
  L(x + 2, 121, x + 2, 124) L(x + 4, 121, x + 4, 124)
  L(x - 1, 112, x + 1.5, 113)
end

local function drawCyclist(x, d, t)
  if off(x - 14, x + 14) then return end
  ink()
  CO(x - 7, 139, 5) CO(x + 7, 139, 5)
  local sx = x - d * 2
  L(x - d * 7, 139, sx, 132) L(sx, 132, x + d * 7, 139) L(sx, 132, x + d * 5, 128) L(x + d * 5, 128, x + d * 7, 139)
  L(sx, 131, x + d * 3, 123)
  C(x + d * 4, 120, 2.6)
  L(x + d * 3, 124, x + d * 6, 128)
  local a = t * 9
  local px, py = x + cos(a) * 3, 136 + sin(a) * 3
  L(sx, 131, px, py)
  L(sx, 131, x - cos(a) * 3, 136 - sin(a) * 3)
end

local function drawDog(x, d, t)
  if off(x - 11, x + 11) then return end
  ink()
  local run = sin(t * 15)
  R(x - 6, 134.5, 12, 4.5)
  C(x + d * 7, 133.5, 2.8)
  T(x + d * 6, 131, x + d * 8, 131, x + d * 6.5, 128.5)
  L(x - d * 6, 135, x - d * 9, 131 + run * 2)
  L(x - 4, 139, x - 4 - run * 2.5, 144) L(x - 2, 139, x - 2 + run * 2.5, 144)
  L(x + 4, 139, x + 4 + run * 2.5, 144) L(x + 2, 139, x + 2 - run * 2.5, 144)
end

local function drawFigure(s)
  local x, f = FIG_X[s], FIG_Y[s]
  if off(x - 5, x + 5) then return end
  ink()
  R(x - 3.5, f - 23, 7, 1.2)
  R(x - 2, f - 26, 4, 3)
  C(x, f - 20, 2)
  T(x, f - 18, x - 3.5, f, x + 3.5, f)
  R(x - 1.5, f - 18, 3, 5)
end

-- everything that moves
local function drawSubjects(W, t)
  drawSail(sailAt(W, t))
  drawFerry(ferryAt(W, t))
  drawCouple(coupleAt(W, t))
  local dx, dd = dogAt(W, t)
  local cx, cd = cycAt(W, t)
  drawCyclist(cx, cd, t)
  drawDog(dx, dd, t)
  for i = 1, 3 do
    local gx, gy = gullAt(W, i, t)
    drawGull(gx, gy, sin(t * 9 + i * 2))
  end
end

-- one subject only (for motion-blur smears)
local function drawOne(W, k, sub, t)
  if k == S_FERRY then drawFerry(ferryAt(W, t))
  elseif k == S_SAIL then drawSail(sailAt(W, t))
  elseif k == S_COUPLE then drawCouple(coupleAt(W, t))
  elseif k == S_CYCLIST then local x, d = cycAt(W, t) drawCyclist(x, d, t)
  elseif k == S_DOG then local x, d = dogAt(W, t) drawDog(x, d, t)
  elseif k == S_GULL then local gx, gy = gullAt(W, sub, t) drawGull(gx, gy, sin(t * 9 + sub * 2))
  end
end

-- lamp, beam and lit windows (drawn after the dusk overlay)
local function drawLights(self, W, t, evb)
  if evb >= LIT_EV + 1 then return end
  local night = U.clamp((LIT_EV + 1 - evb) / 3, 0, 1)
  gfx.setColor(gfx.kColorWhite)
  if night > 0.3 then
    for n = 1, #W.winX do
      if W.winLit[n] and not off(W.winX[n], W.winX[n] + 3) then R(W.winX[n], W.winY[n], 3, 4) end
    end
  end
  if evb < LIT_EV and not off(0, 330) then
    local th = rad(W.lightPh + t * W.lightV)
    local s, c = sin(th), cos(th)
    if abs(s) > 0.12 then
      gfx.setColor(gfx.kColorWhite)
      gfx.setDitherPattern(0.5, gfx.kDitherTypeBayer4x4)
      local ex = 70 + s * 300
      T(70, 15, ex, 15 - 26 * abs(s), ex, 15 + 30 * abs(s))
    end
    gfx.setColor(gfx.kColorWhite)
    local f = c > 0 and c ^ 8 or 0
    C(70, 15, 3 + f * 9)
    gfx.setColor(gfx.kColorBlack)
    if f > 0.5 then CO(70, 15, 3 + f * 9) end
  end
  gfx.setColor(gfx.kColorBlack)
end

------------------------------------------------------------------------
-- background cache (one per world seed)
------------------------------------------------------------------------
local bgImg, bgSeed = nil, nil
local function background(W, seed)
  if bgImg and bgSeed == seed then return bgImg end
  bgImg = gfx.image.new(WORLD_W, 200, gfx.kColorClear)
  bgSeed = seed
  gfx.pushContext(bgImg)
  setXf(0, 0, 1, 0, 0, WORLD_W)
  GHOST, FAINT = false, false
  drawStatic(W)
  gfx.popContext()
  return bgImg
end

------------------------------------------------------------------------
-- definition
------------------------------------------------------------------------
local Cam = Machine.define({
  id = "camera",
  number = 3,
  title = "FILM CAMERA",
  tagline = "Wind on. Compose. Click.",
  description = "Wind each frame by the red window, meter the light and fill the client's shot list before the sun goes.",
  howto = "Crank clockwise until the next number sits under the red window's mark. Hold B + D-pad: shutter/aperture. A shoots. Hold B, crank back a turn to release the rewind, then crank back many turns.",
  controls = { { "CRANK", "wind the film" }, { "DPAD", "aim the camera" }, { "B", "+ D-pad: exposure" }, { "A", "release the shutter" } },
  modes = { "tutorial", "standard", "endless" },
  medals = { standard = { 250, 400, 540 }, endless = { 600, 1200, 2000 } },
  scoreLabel = "POINTS",
  unlockCost = 3,
  achievements = {
    { id = "first", name = "FIRST ROLL", desc = "Develop your first roll." },
    { id = "clean", name = "NO OVERLAPS", desc = "10+ frames, none overlapping." },
    { id = "brief", name = "CLIENT PLEASED", desc = "Fulfil every item of a brief." },
    { id = "stranger", name = "THE STRANGER", desc = "Photograph the figure." },
    { id = "panned", name = "PANNING SHOT", desc = "Sharp subject, streaked town." },
  },
  challenges = {
    { id = "nometer", name = "BROKEN METER", desc = "No light meter. Judge the light.", mode = "standard", difficulty = 2, goal = 300, reward = 3, cost = 2 },
    { id = "rusty", name = "RUSTED KNOB", desc = "The advance knob sticks and jumps.", mode = "standard", difficulty = 1, mods = { rusty = true }, goal = 300, reward = 2, cost = 2 },
    { id = "dusk", name = "LAST LIGHT", desc = "Start the roll at dusk.", mode = "standard", difficulty = 2, goal = 260, reward = 3, cost = 3 },
  },
  records = {
    { "rolls", "Rolls developed" },
    { "frames", "Frames exposed" },
    { "bestFrame", "Best frame", function(v) return (v or 0) .. "/100" end },
    { "stranger", "Strangers caught" },
  },
  drawIcon = function(cx, cy)
    gfx.setColor(gfx.kColorBlack)
    -- body
    gfx.fillRoundRect(cx - 22, cy - 12, 20, 28, 3)
    -- bellows
    for i = 0, 3 do
      local x = cx - 2 + i * 5
      local h = 11 - i
      gfx.drawLine(x, cy - h, x + 5, cy - h + 1)
      gfx.drawLine(x, cy + h + 2, x + 5, cy + h + 1)
      gfx.drawLine(x + 2, cy - h + 1, x + 2, cy + h + 1)
    end
    gfx.fillRect(cx + 17, cy - 10, 4, 24)
    -- lens
    gfx.fillCircleAtPoint(cx + 16, cy + 2, 8)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(cx + 16, cy + 2, 5)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(cx + 16, cy + 2, 2)
    -- knob and red window
    gfx.fillRect(cx - 18, cy - 18, 9, 6)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(cx - 17, cy - 17, 7, 1)
    gfx.fillCircleAtPoint(cx - 12, cy + 4, 3)
    gfx.drawLine(cx - 20, cy - 8, cx - 5, cy - 8)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(cx - 13, cy + 3, 2, 2)
  end,
})

Cam.HINTS_SHOOT = { { "CRANK", "WIND" }, { "A", "SHOOT" }, { "B", "+DPAD EXPOSE" }, { "DPAD", "AIM" } }
Cam.HINTS_REWIND = { { "CRANK", "BACKWARD: REWIND" } }
Cam.HINTS_SHEET = { { "DPAD", "LOUPE" }, { "B", "BRIEF" }, { "A", "DONE" } }
Cam.HINTS_SHEET_E = { { "DPAD", "LOUPE" }, { "B", "BRIEF" }, { "A", "NEXT ROLL" } }

------------------------------------------------------------------------
-- roll setup
------------------------------------------------------------------------
function Cam:makeBrief()
  local items = {}
  if self.tut then
    items[1] = { s = S_FERRY, r = R_WHOLE }
    items[2] = { s = S_GULL, r = R_SHARP }
    return items
  end
  local n = 5 + self.difficulty
  if self.mode == "endless" then n = min(8, 4 + self.roll) end
  local pool = {}
  for i = 1, #POOL do pool[i] = POOL[i] end
  self.rng:shuffle(pool)
  local used = {}
  local lateRoll = self.mode == "endless" and self.roll >= 2
  -- the lighthouse lit at dusk closes every standard brief
  local wantLit = self.mode ~= "endless" or evBaseAt(self, self.wt) < 13
  local room = wantLit and n - 1 or n
  for i = 1, #pool do
    if #items >= room then break end
    local p = pool[i]
    local ok = not used[p[1]]
    if p[2] == R_PANNED and self.difficulty < 2 and not lateRoll then ok = false end
    if ok then
      used[p[1]] = true
      items[#items + 1] = { s = p[1], r = p[2] }
    end
  end
  if wantLit then items[#items + 1] = { s = S_LIGHT, r = R_LIT } end
  return items
end

function Cam:briefTexts()
  self.briefText = {}
  for i = 1, #self.brief do
    local b = self.brief[i]
    self.briefText[i] = SUBJ_NAME[b.s] .. REQ_NAME[b.r]
  end
end

function Cam:startRoll()
  self.filmPos = 0
  self.knobA = 0
  self.shots = {}
  self.phase = "shoot"
  self.rewArm = 0
  self.pawl = 0
  self.endHit = false
  self.ticked = {}
  if self.tut then
    self.dpfBase, self.dpfK = 400, 0
  else
    self.dpfBase = self.rng:between(455, 505) + (self.difficulty - 1) * self.rng:between(-30, 30)
    self.dpfK = 0.018 + 0.005 * (self.difficulty - 1)
  end
  self.brief = self:makeBrief()
  self:briefTexts()
  self:buildBriefCard()
  for i = 1, #self.brief do self.ticked[i] = false end
  self.sheetT = 0
  self.sel = 0
  self.devel = nil
  self.rollScore = 0
  self.rewT = 0
end

function Cam:enter(params)
  self.tut = self.mode == "tutorial"
  self.t = 0
  self.roll = 1
  self.score = 0
  self.rollScores = {}
  self.dayLen = self.mode == "endless" and DAY_END or DAY_STD
  self.wt = 0
  if self.params.challengeId == "dusk" then self.wt = DAY_STD * 0.6 end
  self.noMeter = self.params.challengeId == "nometer"
  self.tolE = self.difficulty >= 3 and 0.5 or (self.difficulty == 2 and 0.6 or 0.7)
  self.worldSeed = self.rng:range(1, 1000000000)
  self.W = genWorld(self.worldSeed, self.difficulty)
  self.bg = background(self.W, self.worldSeed)
  self.tracker = Crank.Tracker.new()
  self.ox, self.oy = self.tut and 430 or 200, 16
  self.panVx, self.panVy, self.holdX = 0, 0, 0
  self.aI, self.sI = 4, 8
  self.needle, self.eNow, self.evNow = 0, 0, 13
  self.msg, self.msgT = nil, 0
  self.exp = { active = false, t = 0, te = 0 }
  self.blackT = 0
  self.flashT = 0
  self.sparks = 0
  self.rewVel = 0
  self.lastMinute = -1
  self.clockStr = ""
  self.thumbs = {}
  self.tmpS = gfx.image.new(THUMB, THUMB, gfx.kColorWhite)
  self.tmpL = gfx.image.new(LOUPE, LOUPE, gfx.kColorWhite)
  self.loupeImg = gfx.image.new(LOUPE, LOUPE, gfx.kColorWhite)
  self.loupeFor = -1
  self.sheetImg = gfx.image.new(258, 200, gfx.kColorWhite)
  self.sea = Audio.Hum.new(Audio.NOISE)
  self.whirr = Audio.Hum.new(Audio.TRIANGLE)
  self.sheetAck = false
  self.nightWarned = false
  self:startRoll()
  if self.tut then self:setupCoach() end
end

function Cam:exit()
  self.sea:stop()
  self.whirr:stop()
end

------------------------------------------------------------------------
-- tutorial
------------------------------------------------------------------------
function Cam:lastShot() return self.shots[#self.shots] end

function Cam:setupCoach()
  local s = self
  self.coach = UI.Coach.new({
    { text = "D-pad aims the camera. Find the FERRY out on the water.",
      check = function() return s:liveVis(S_FERRY) > 0.9 end, hold = 0.4 },
    { text = "Crank CLOCKWISE to wind on. Stop when 1 sits under the red window's mark.",
      check = function() return abs(s.filmPos - 1) < 0.1 and s.tracker.idle > 0.3 end, hold = 0.3 },
    { text = "Hold B: LEFT/RIGHT shutter, UP/DOWN aperture. Bring the needle to 0.",
      check = function() return abs(s.eNow) <= 0.6 end, hold = 0.5 },
    { text = "Keep the crank still. Frame the whole ferry and press A.",
      check = function()
        local r = s:lastShot()
        if not r then return false end
        local f = s:subjEval(r, S_FERRY)
        return f > 0.7 and abs(r.e) < 1.6
      end },
    { text = "Wind to 2. Short winds overlap frames - watch the window, not the knob.",
      check = function()
        local r = s:lastShot()
        return r and abs(s.filmPos - (floor(r.p + 0.5) + 1)) < 0.1 and s.tracker.idle > 0.3
      end, hold = 0.3 },
    { text = "Gulls are fast. Set 1/250 or faster, re-meter, shoot a gull.",
      check = function()
        for i = 1, #s.shots do
          local f, _, b = s:subjEval(s.shots[i], S_GULL)
          if f > 0.5 and b <= 1.5 then return true end
        end
        return false
      end },
    { text = "Hold B and crank BACKWARD one full turn to release the rewind.",
      check = function() return s.phase ~= "shoot" end },
    { text = "Now crank backward, many turns, to rewind the film.",
      check = function() return s.phase == "sheet" end },
    { text = "Your contact sheet! Circled frames are keepers. Press A.",
      check = function() return s.sheetAck end },
  }, { y = 176, h = 46, anchor = "bottom" })
end

------------------------------------------------------------------------
-- light
------------------------------------------------------------------------
function Cam:cover(t)
  if self.tut then return 0 end
  local c = 0
  local W = self.W
  for i = 1, #W.clouds do
    local cl = W.clouds[i]
    local d = abs(cloudX(cl, t) - SUNX)
    if d < cl.size then c = max(c, 1 - d / cl.size) end
  end
  return c
end

function Cam:sceneEV(ox, oy, t)
  local cov = self:cover(t)
  local ev = evBaseAt(self, t) - 1.6 * cov
  local sky = U.clamp((HORIZON - oy) / VS, 0, 1)
  ev = ev + (sky - 0.45) * 1.4
  local cx = ox + VS / 2
  ev = ev - 1.1 * U.clamp((200 - cx) / 90, 0, 1) - 0.7 * U.clamp((cx - 540) / 90, 0, 1)
  local sy = sunY(self, t)
  if sy < HORIZON and SUNX > ox and SUNX < ox + VS and sy > oy and sy < oy + VS then
    ev = ev + 1.8 * (1 - cov)
  end
  return ev
end

function Cam:dpf() return self.dpfBase / (1 + self.dpfK * self.filmPos) end

------------------------------------------------------------------------
-- evaluation of an exposure (pure: depends only on the record)
------------------------------------------------------------------------
-- returns visible fraction, centre distance (0 = dead centre, 1 = edge),
-- subject blur px, background blur px
function Cam:subjEval(rec, k)
  local W = self.W
  local bb = sqrt(rec.cdx * rec.cdx + rec.cdy * rec.cdy) + rec.shake
  local n = (k == S_GULL) and 3 or 1
  local bf, bd, bbl = 0, 9, 99
  for sub = 1, n do
    local cx, cy, hw, hh = subjBox(W, k, rec.t0, sub)
    if cx then
      local f = visFrac(cx, cy, hw, hh, rec.ox, rec.oy)
      if f > 0 then
        local d = sqrt((cx - rec.ox - VS / 2) ^ 2 + (cy - rec.oy - VS / 2) ^ 2) / (VS / 2)
        local cx2, cy2 = subjBox(W, k, rec.t0 + rec.te, sub)
        local rx, ry = cx2 - cx - rec.cdx, cy2 - cy - rec.cdy
        local b = sqrt(rx * rx + ry * ry) + rec.shake
        if f > bf + 0.05 or (f >= bf - 0.05 and d < bd) then bf, bd, bbl = f, d, b end
      end
    end
  end
  return bf, bd, bbl, bb
end

local function expoFactor(e, tol)
  local ae = abs(e)
  if ae <= tol then return 1 end
  if ae <= 1.3 then return 0.75 end
  return max(0, 0.75 - (ae - 1.3) * 0.45)
end

-- quality 0..1 of a record for subject k under requirement r (no overlap)
function Cam:quality(rec, k, r)
  local f, d, b, bb = self:subjEval(rec, k)
  if f < 0.25 then return 0 end
  local comp
  if r == R_WHOLE then
    comp = f >= 0.97 and 1 or (f >= 0.6 and 0.35 or 0.1)
  elseif r == R_CENTRED then
    if f < 0.6 then comp = 0.2 else comp = d <= 0.15 and 1 or max(0.25, 1 - (d - 0.15) * 1.6) end
  else
    comp = f >= 0.5 and (0.78 + 0.22 * max(0, 1 - d)) or f
  end
  local sharp
  if r == R_SHARP then
    sharp = b <= 1.2 and 1 or (b <= 2.5 and 0.5 or 0.15)
  elseif r == R_PANNED then
    if b <= 2.5 then sharp = bb >= 6 and 1 or 0.4 else sharp = 0.2 end
  else
    sharp = b <= 1.5 and 1 or (b <= 6 and 1 - (b - 1.5) / 9 or 0.3)
  end
  local lit = 1
  if r == R_LIT then lit = evBaseAt(self, rec.t0) < LIT_EV and 1 or 0.25 end
  return comp * sharp * lit * expoFactor(rec.e, self.tolE)
end

-- live visibility of a subject in the current framing (optionally
-- weighted toward the centre of the finder)
function Cam:liveVis(k, centred)
  local best = 0
  local n = (k == S_GULL) and 3 or 1
  for sub = 1, n do
    local cx, cy, hw, hh = subjBox(self.W, k, self.wt, sub)
    if cx then
      local v = visFrac(cx, cy, hw, hh, self.ox, self.oy)
      if centred then
        local d = abs(cx - self.ox - VS / 2) + abs(cy - self.oy - VS / 2)
        v = v * (1 - min(0.6, d / VS))
      end
      best = max(best, v)
    end
  end
  return best
end

------------------------------------------------------------------------
-- rendering an exposure into an image (thumbnail or loupe)
------------------------------------------------------------------------
function Cam:renderShot(rec, img, tmp, size)
  local s = size / VS
  local W = self.W
  local evb = evBaseAt(self, rec.t0)
  -- sharp layer: sky + static world, darkened by dusk
  gfx.pushContext(tmp)
  gfx.clear(gfx.kColorWhite)
  GHOST, FAINT = false, false
  setXf(rec.ox, rec.oy, s, 0, 0, VS)
  drawSky(self, W, rec.t0)
  drawStatic(W)
  local dim = U.clamp((12.5 - evb) / 11, 0, 0.45)
  if dim > 0.02 then
    gfx.setColor(gfx.kColorBlack)
    gfx.setDitherPattern(dim, gfx.kDitherTypeBayer4x4)
    gfx.fillRect(0, 0, size, size)
    gfx.setColor(gfx.kColorBlack)
  end
  gfx.popContext()

  gfx.pushContext(img)
  gfx.clear(gfx.kColorWhite)
  tmp:draw(0, 0)
  -- camera motion smears the whole frame
  local cdx, cdy = rec.cdx * s, rec.cdy * s
  local cb = sqrt(cdx * cdx + cdy * cdy) + rec.shake * s
  if cb > 0.8 then
    local n = min(5, floor(cb / 1.2) + 1)
    local jx = rec.shake * s * 0.7
    for k = 1, n - 1 do
      local f = k / (n - 1)
      tmp:drawFaded(-cdx * f + jx * (k % 2 == 0 and 1 or -1) * f, -cdy * f + jx * 0.5 * f, 0.5, gfx.kDitherTypeBayer4x4)
    end
  end
  -- moving subjects: drawn at the start, smeared along their motion
  setXf(rec.ox, rec.oy, s, 0, 0, VS)
  local t0, t1 = rec.t0, rec.t0 + rec.te
  for k = 1, 8 do
    if k ~= S_LIGHT and k ~= S_SPIRE then
      local nsub = (k == S_GULL) and 3 or 1
      for sub = 1, nsub do
        local ax, ay = subjBox(W, k, t0, sub)
        local bx, by = subjBox(W, k, t1, sub)
        local mx = (bx - ax - rec.cdx) * s
        local my = (by - ay - rec.cdy) * s
        local blur = sqrt(mx * mx + my * my) + rec.shake * s
        if blur < 1 then
          GHOST = false
          drawOne(W, k, sub, t0)
        else
          local n = min(6, floor(blur / 1.3) + 2)
          for g = 0, n - 1 do
            local f = g / (n - 1)
            -- follow the subject in time, the camera in space
            setXf(rec.ox + rec.cdx * f, rec.oy + rec.cdy * f, s, 0, 0, VS)
            GHOST = blur > 3 or g > 0
            drawOne(W, k, sub, t0 + rec.te * f)
          end
          setXf(rec.ox, rec.oy, s, 0, 0, VS)
        end
      end
    end
  end
  GHOST = false
  -- the stranger appears on film, solid
  local fs = figureAt(W, t0)
  if fs > 0 then drawFigure(fs) end
  drawLights(self, W, t0, evb)
  -- exposure error: dither toward white (over) or black (under)
  local e = rec.e
  if e > self.tolE then
    local c = U.clamp((e - 0.4) / 3, 0, 0.94)
    gfx.setColor(gfx.kColorWhite)
    gfx.setDitherPattern(1 - c, gfx.kDitherTypeBayer4x4)
    gfx.fillRect(0, 0, size, size)
  elseif e < -self.tolE then
    local c = U.clamp((-e - 0.4) / 3, 0, 0.94)
    gfx.setColor(gfx.kColorBlack)
    gfx.setDitherPattern(c, gfx.kDitherTypeBayer4x4)
    gfx.fillRect(0, 0, size, size)
  end
  -- static discharge from a racing rewind: branching sparks
  if (rec.st or 0) > 0 then
    gfx.setColor(gfx.kColorXOR)
    local h = floor(rec.t0 * 1000) % 997
    for k = 1, rec.st do
      local x = (h * (k + 3) * 7) % size
      local y = 0
      while y < size do
        local nx = x + ((h + y * 13 + k) % 7) - 3
        gfx.drawLine(x, y, nx, y + size / 6)
        x, y = nx, y + size / 6
      end
    end
  end
  gfx.setColor(gfx.kColorBlack)
  gfx.popContext()
end

------------------------------------------------------------------------
-- shutter
------------------------------------------------------------------------
function Cam:shoot()
  local ex = self.exp
  if ex.active or self.phase ~= "shoot" then return end
  local te = 2 ^ -(self.sI - 1)
  ex.active = true
  ex.t = 0
  ex.te = te
  ex.p = self.filmPos
  ex.t0 = self.wt
  ex.ox, ex.oy = self.ox, self.oy
  ex.crank = 0
  ex.film0 = self.filmPos
  ex.ev = self:sceneEV(self.ox, self.oy, self.wt)
  ex.e = ex.ev - (self.aI + self.sI + 1)
  -- a turning crank jolts the camera as the shutter trips
  ex.jolt = min(4, abs(self.tracker.vel) / 150)
  self.blackT = 2 / 30
  if self.filmPos < 0.55 then self.msg, self.msgT = "THAT WAS THE LEADER - WIND ON TO 1", 2 end
  Audio.play(Audio.NOISE, 6000, 0.35, 0.008, 0.001, 0.012, 0, 0.01)
  Audio.play(Audio.SQUARE, 900, 0.12, 0.01, 0.001, 0.015, 0, 0.01)
  if te >= 0.2 then Audio.play(Audio.SQUARE, 150, 0.06, te, 0.01, 0.02, 0.8, 0.02) end
end

function Cam:endExposure()
  local ex = self.exp
  ex.active = false
  local te = ex.te
  local cdx, cdy
  if te >= 1 / 30 then
    cdx, cdy = self.ox - ex.ox, self.oy - ex.oy
  else
    cdx, cdy = self.panVx * te, self.panVy * te
  end
  -- cranking during the exposure drags the film across the gate
  local smear = (self.filmPos - ex.film0) * FRAME_PX
  local shake = ex.jolt + ex.crank * 0.05
  if te > 1 / 30 then shake = shake + (te - 1 / 30) * 11 end
  local rec = {
    p = ex.p, t0 = ex.t0, te = te, ox = ex.ox, oy = ex.oy,
    cdx = cdx - smear, cdy = cdy, shake = shake, ev = ex.ev, e = ex.e, st = 0,
  }
  local i = #self.shots + 1
  self.shots[i] = rec
  if not self.thumbs[i] then self.thumbs[i] = gfx.image.new(THUMB, THUMB, gfx.kColorWhite) end
  self:renderShot(rec, self.thumbs[i], self.tmpS, THUMB)
  -- pencil ticks on the brief: framed (quality is only revealed later)
  for b = 1, #self.brief do
    local f = self:subjEval(rec, self.brief[b].s)
    if f >= 0.6 then self.ticked[b] = true end
  end
  self:statAdd("frames", 1)
  Audio.sfx.clack(0.5)
  self.flashT = 0.12
end

------------------------------------------------------------------------
-- rewind & development
------------------------------------------------------------------------
function Cam:startRewind()
  self.phase = "rewind"
  self.rewArm = 0
  self.rewFrom = max(0.5, self.filmPos)
  Audio.sfx.clank(0.35)
  self.msg, self.msgT = "REWIND RELEASED", 1.6
  self:shake(1)
end

function Cam:finishRewind()
  self.filmPos = 0
  self.whirr:stop()
  Audio.sfx.whoosh(0.3)
  Audio.sfx.thunk(0.5)
  self:develop()
  self.phase = "sheet"
  self.sheetT = 0
  Audio.sfx.splash(0.35)
end

function Cam:develop(replay)
  local shots = self.shots
  local n = #shots
  local D = { ov = {}, q = {}, note = {}, keeper = {}, ruined = {}, itemPts = {}, itemShot = {}, order = {} }
  self.devel = D
  -- overlap: shared film between exposures, plus film that was never there
  for i = 1, n do
    local p = shots[i].p
    local ov = 0
    for j = 1, n do
      if j ~= i then ov = max(ov, max(0, FW - abs(p - shots[j].p)) / FW) end
    end
    local lo, hi = p - FW / 2, p + FW / 2
    local out = (max(0, FILM_LO - lo) + max(0, hi - FILM_HI)) / FW
    D.ov[i] = U.clamp(max(ov, out), 0, 1)
    if shots[i].st > 0 then self:renderShot(shots[i], self.thumbs[i], self.tmpS, THUMB) end
    D.order[i] = i
  end
  table.sort(D.order, function(a, b) return shots[a].p < shots[b].p end)
  local function ovFactor(i)
    local o = D.ov[i]
    if o > 0.8 then return 0 end
    if o < 0.04 then return 1 end
    return max(0, 1 - o * 2.4)
  end
  -- best frame for each brief item
  local itemsTotal = 0
  local all = true
  for b = 1, #self.brief do
    local it = self.brief[b]
    local best, bi = 0, 0
    for i = 1, n do
      local q = self:quality(shots[i], it.s, it.r) * ovFactor(i)
      if q > best then best, bi = q, i end
    end
    local pts = floor(best * 100 + 0.5)
    D.itemPts[b], D.itemShot[b] = pts, bi
    itemsTotal = itemsTotal + pts
    if pts < 60 then all = false end
  end
  -- every frame: its best subject, keepers, notes
  local keepers, ruinedN, bestFrame = 0, 0, 0
  local strangerFound = false
  local pannedFound = false
  for i = 1, n do
    local r = shots[i]
    local q = 0
    for k = 1, 8 do q = max(q, self:quality(r, k, R_ANY)) end
    q = q * ovFactor(i)
    D.q[i] = q
    bestFrame = max(bestFrame, floor(q * 100 + 0.5))
    local used = false
    for b = 1, #self.brief do if D.itemShot[b] == i and D.itemPts[b] >= 50 then used = true end end
    D.keeper[i] = q >= 0.6 or used
    if D.keeper[i] and not used then keepers = keepers + 1 end
    local ff = self:subjEval(r, S_FIGURE)
    if ff >= 0.6 and abs(r.e) < 2 and D.ov[i] < 0.8 then strangerFound = true D.keeper[i] = true end
    local cf, _, cb, cbb = self:subjEval(r, S_CYCLIST)
    if cf > 0.6 and cb <= 2.5 and cbb >= 6 and abs(r.e) < 1.5 then pannedFound = true end
    -- the worst defect names the frame
    local note
    if D.ov[i] > 0.8 then note = "DOUBLE EXPOSURE"
    elseif D.ov[i] >= 0.04 then note = "OVERLAPPED"
    elseif r.e > 1.3 then note = string.format("OVER %+d STOPS", floor(r.e + 0.5))
    elseif r.e < -1.3 then note = string.format("UNDER %d STOPS", floor(-r.e + 0.5))
    elseif r.st > 0 then note = "STATIC MARKS"
    elseif r.shake > 2.5 then note = "CAMERA SHAKE"
    elseif q < 0.35 then note = "NOTHING IN IT"
    else note = "SHARP, WELL EXPOSED" end
    D.note[i] = note
    D.ruined[i] = D.ov[i] > 0.8 or abs(r.e) > 3 or q < 0.08
    if D.ruined[i] then ruinedN = ruinedN + 1 end
  end
  keepers = min(keepers, 6)
  local score = itemsTotal + keepers * 10 + (strangerFound and 150 or 0)
  D.itemsTotal, D.keepers, D.ruinedN, D.stranger, D.score = itemsTotal, keepers, ruinedN, strangerFound, score
  D.maxItems = #self.brief * 100
  D.pass = itemsTotal >= D.maxItems * 0.45
  self.rollScore = score
  D.ptsStr, D.qStr, D.frameStr = {}, {}, {}
  for b = 1, #self.brief do D.ptsStr[b] = tostring(D.itemPts[b]) end
  for i = 1, n do D.qStr[i] = "QUALITY " .. floor(D.q[i] * 100 + 0.5) end
  for k = 1, n do D.frameStr[D.order[k]] = "FRAME " .. k end
  D.totalStr = "TOTAL " .. score
  self:buildSheet()
  self:buildColumn()
  self.sel = 0
  self.loupeFor = -1
  if replay then return end
  -- bookkeeping
  if self.mode ~= "tutorial" then
    self.score = self.score + score
    self.rollScores[#self.rollScores + 1] = score
  end
  self:statAdd("rolls", 1)
  self:statMax("bestFrame", bestFrame)
  self:award("first")
  local clean = n >= 10
  for i = 1, n do if D.ov[i] >= 0.04 then clean = false end end
  if clean then self:award("clean") end
  if all and #self.brief >= 5 then self:award("brief") end
  if strangerFound then self:award("stranger") self:statAdd("stranger", 1) end
  if pannedFound then self:award("panned") end
end

-- frame index -> position on the sheet (main strip)
local function sheetPos(p)
  local s = U.clamp(floor((p - 0.5) / 4), 0, 2)
  local x = 4 + (p - FW / 2 - (0.5 + 4 * s)) * UNIT
  return floor(x + 0.5), 4 + s * 66, s
end

function Cam:buildSheet()
  local img = self.sheetImg
  local shots, D = self.shots, self.devel
  gfx.pushContext(img)
  gfx.clear(gfx.kColorWhite)
  gfx.setPattern(Art.pat.gray6)
  gfx.fillRect(0, 0, 258, 200)
  for s = 0, 2 do
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(2, 1 + s * 66, 252, 62)
  end
  local function stripClip(s) gfx.setClipRect(4, 4 + s * 66, 4 * UNIT, THUMB) end
  -- frames in exposure order, each clipped into every strip it touches
  for i = 1, #shots do
    local p = shots[i].p
    for s = 0, 2 do
      local x = 4 + (p - FW / 2 - (0.5 + 4 * s)) * UNIT
      if x < 4 + 4 * UNIT and x + THUMB > 4 then
        stripClip(s)
        self.thumbs[i]:draw(floor(x + 0.5), 4 + s * 66)
      end
    end
  end
  -- overlapping exposures: the earlier frame shows through the later one
  for i = 1, #shots do
    for j = i + 1, #shots do
      local pi, pj = shots[i].p, shots[j].p
      if abs(pi - pj) < FW then
        local lo, hi = max(pi, pj) - FW / 2, min(pi, pj) + FW / 2
        for s = 0, 2 do
          local base = 0.5 + 4 * s
          local x0 = 4 + (lo - base) * UNIT
          local x1 = 4 + (hi - base) * UNIT
          x0, x1 = max(x0, 4), min(x1, 4 + 4 * UNIT)
          if x1 > x0 then
            gfx.setClipRect(floor(x0), 4 + s * 66, floor(x1 - x0 + 1), THUMB)
            self.thumbs[i]:drawFaded(floor(4 + (pi - FW / 2 - base) * UNIT + 0.5), 4 + s * 66, 0.5, gfx.kDitherTypeBayer4x4)
          end
        end
      end
    end
  end
  gfx.clearClipRect()
  -- edge printing on the rebate: frame numbers
  gfx.setColor(gfx.kColorWhite)
  for s = 0, 2 do
    for k = 1, 4 do
      local x = 4 + (k - 0.5) * UNIT
      gfx.fillRect(x - 1, 1 + s * 66, 2, 2)
      gfx.fillRect(x - 1, 61 + s * 66, 2, 2)
    end
  end
  gfx.setColor(gfx.kColorBlack)
  gfx.popContext()
end

-- icons and requirements of the brief beside the contact sheet
function Cam:buildColumn()
  self.colImg = self.colImg or gfx.image.new(134, 172, gfx.kColorWhite)
  gfx.pushContext(self.colImg)
  gfx.clear(gfx.kColorWhite)
  UI.text("THE BRIEF", 67, 4, "center", UI.bold)
  local nb = #self.brief
  local rowH = nb > 7 and 18 or 20
  for b = 1, nb do
    local y = 22 + (b - 1) * rowH
    self:drawSubjIcon(self.brief[b].s, 12, y + 8, 0.9)
    UI.text(REQ_SHORT[self.brief[b].r], 27, y, "left")
  end
  gfx.popContext()
end

function Cam:renderLoupe(i)
  if self.loupeFor == i then return end
  self.loupeFor = i
  local rec = self.shots[i]
  self:renderShot(rec, self.loupeImg, self.tmpL, LOUPE)
  -- overlapping neighbours are on the same patch of film
  local img2 = self.tmpL
  for j = 1, #self.shots do
    if j ~= i and abs(self.shots[j].p - rec.p) < FW then
      local other = gfx.image.new(LOUPE, LOUPE, gfx.kColorWhite)
      self:renderShot(self.shots[j], other, img2, LOUPE)
      local dx = (self.shots[j].p - rec.p) * UNIT * 2
      gfx.pushContext(self.loupeImg)
      local x0, x1 = max(0, dx), min(LOUPE, dx + LOUPE)
      gfx.setClipRect(floor(x0), 0, floor(x1 - x0), LOUPE)
      other:drawFaded(floor(dx), 0, 0.5, gfx.kDitherTypeBayer4x4)
      gfx.clearClipRect()
      gfx.popContext()
    end
  end
  -- film that was never there prints black
  local lo, hi = rec.p - FW / 2, rec.p + FW / 2
  gfx.pushContext(self.loupeImg)
  gfx.setColor(gfx.kColorBlack)
  if lo < FILM_LO then gfx.fillRect(0, 0, (FILM_LO - lo) / FW * LOUPE, LOUPE) end
  if hi > FILM_HI then local w = (hi - FILM_HI) / FW * LOUPE gfx.fillRect(LOUPE - w, 0, w, LOUPE) end
  gfx.popContext()
end

------------------------------------------------------------------------
-- input
------------------------------------------------------------------------
function Cam:cranked(change)
  self.tracker:feed(change)
  local ex = self.exp
  if ex.active then ex.crank = ex.crank + abs(change) end
  local ph = self.phase
  if ph == "shoot" then
    if not Input.held(Input.B) then self.rewArm = 0 end
    if change < 0 and Input.held(Input.B) then
      self.rewArm = self.rewArm - change
      if floor(self.rewArm / 45) ~= floor((self.rewArm + change) / 45) then Audio.sfx.tick(500, 0.2) end
      if self.rewArm >= 360 then self:startRewind() end
      return
    end
    if change > 0 then
      self.rewArm = 0
      self.pawl = 0
      if self.filmPos >= FILM_END then
        -- the roll is finished: the knob will not turn
        if not self.endHit then
          self.endHit = true
          Audio.sfx.thud(0.6)
          Audio.sfx.creak(0.2)
          self:shake(2)
        end
        self.msg, self.msgT = "END OF ROLL - REWIND", 1.5
        return
      end
      local before = self.knobA
      self.knobA = self.knobA + change
      self.filmPos = min(FILM_END, self.filmPos + change / self:dpf())
      local clicks = floor(self.knobA / 15) - floor(before / 15)
      if clicks > 0 then
        local stiff = self.filmPos > 11.5 and 0.7 or 1
        Audio.play(Audio.SQUARE, 2600 * stiff, 0.12, 0.006, 0.001, 0.01, 0, 0.005)
        Audio.play(Audio.NOISE, 3500, 0.1, 0.006, 0.001, 0.01, 0, 0.005)
      end
    elseif change < 0 then
      local before = self.pawl
      self.pawl = self.pawl - change
      if floor(self.pawl / 15) ~= floor(before / 15) then
        Audio.play(Audio.NOISE, 1600, 0.14, 0.006, 0.001, 0.012, 0, 0.005)
      end
      if self.pawl > 120 and before <= 120 then
        self.msg, self.msgT = "RATCHET. HOLD B TO REWIND", 1.6
      end
    end
  elseif ph == "rewind" then
    if change < 0 then
      local before = self.filmPos
      self.filmPos = self.filmPos + change / REW_DPF
      if floor(before * 10) ~= floor(self.filmPos * 10) then
        Audio.play(Audio.TRIANGLE, 600 + min(900, -change * 12), 0.1, 0.008, 0.001, 0.01, 0, 0.005)
      end
      -- racing the rewind in dry air sparks static onto the frames passing
      if -change > 36 then
        self.sparks = self.sparks + (-change - 36) * 0.004
        if self.sparks >= 1 then
          self.sparks = 0
          local bi, bd = 0, 0.5
          for i = 1, #self.shots do
            local d = abs(self.shots[i].p - self.filmPos)
            if d < bd then bi, bd = i, d end
          end
          if bi > 0 then self.shots[bi].st = min(3, self.shots[bi].st + 1) end
          Audio.sfx.snap(0.3)
          self.flashT = 0.1
          self:shake(1)
        end
      end
      if self.filmPos <= 0 then self:finishRewind() end
    end
  end
end

function Cam:buttonDown(b)
  if self.phase == "shoot" then
    if b == Input.A then
      if not Input.held(Input.B) then self:shoot() end
    end
  elseif self.phase == "sheet" then
    local D = self.devel
    local n = #self.shots
    if b == Input.A then
      if self.sheetT < 1.4 then self.sheetT = 1.4 + #self.shots * 0.3 return end
      self.sheetAck = true
      if self.tut then return end
      if self.mode == "endless" and D.pass then
        self.roll = self.roll + 1
        Audio.sfx.menuSelect()
        self:startRoll()
        return
      end
      self:finishRun()
    elseif (b == Input.RIGHT or b == Input.DOWN) and n > 0 then
      local k = U.indexOf(D.order, self.sel) or 0
      self.sel = D.order[k % n + 1]
      Audio.sfx.menuMove()
    elseif (b == Input.LEFT or b == Input.UP) and n > 0 then
      local k = U.indexOf(D.order, self.sel) or 1
      self.sel = D.order[(k - 2) % n + 1]
      Audio.sfx.menuMove()
    elseif b == Input.B then
      self.sel = 0
      Audio.sfx.back()
    end
  end
end

function Cam:finishRun()
  local D = self.devel
  if self.mode == "endless" then
    self:finish({ success = self.roll > 1 or D.pass, score = self.score, title = "THE LIGHT IS GONE",
      lines = { "Rolls developed: " .. self.roll, "Last roll: " .. D.score .. " pts",
        "Brief: " .. D.itemsTotal .. "/" .. D.maxItems } , delay = 0.8 })
  else
    local good = 0
    for b = 1, #self.brief do if D.itemPts[b] >= 60 then good = good + 1 end end
    self:finish({ success = D.itemsTotal > 0, score = self.score,
      title = good == #self.brief and "CLIENT DELIGHTED" or (good >= #self.brief // 2 and "PRINTS DELIVERED" or "RESHOOT NEEDED"),
      lines = { "Brief: " .. good .. "/" .. #self.brief .. "  (" .. D.itemsTotal .. " pts)",
        "Keepers: " .. D.keepers .. "   Ruined: " .. D.ruinedN,
        D.stranger and "Someone is in one of them." or ("Frames exposed: " .. #self.shots) }, delay = 0.8 })
  end
end

------------------------------------------------------------------------
-- update
------------------------------------------------------------------------
function Cam:updateAim(dt)
  if Input.held(Input.B) then
    self.panVx, self.panVy, self.holdX = 0, 0, 0
    local changed = false
    if Input.repeated(Input.LEFT) and self.sI > 1 then self.sI = self.sI - 1 changed = true end
    if Input.repeated(Input.RIGHT) and self.sI < #SHUTTERS then self.sI = self.sI + 1 changed = true end
    if Input.repeated(Input.UP) and self.aI > 1 then self.aI = self.aI - 1 changed = true end
    if Input.repeated(Input.DOWN) and self.aI < #APERTURES then self.aI = self.aI + 1 changed = true end
    if changed then Audio.play(Audio.SQUARE, 1500 + self.sI * 60, 0.12, 0.008, 0.001, 0.012, 0, 0.005) end
    return
  end
  local ax, ay = Input.axisX(), Input.axisY()
  local sp = 0
  if ax ~= 0 then
    self.holdX = self.holdX + dt
    sp = self.holdX < 0.8 and 40 or min(170, 40 + (self.holdX - 0.8) * 220)
  else
    self.holdX = 0
  end
  local nox = U.clamp(self.ox + ax * sp * dt, 0, WORLD_W - VS)
  local noy = U.clamp(self.oy + ay * 36 * dt, 0, OY_MAX)
  self.panVx, self.panVy = (nox - self.ox) / dt, (noy - self.oy) / dt
  self.ox, self.oy = nox, noy
end

function Cam:update(dt)
  self.t = self.t + dt
  self.tracker:update(dt)
  if self.msgT > 0 then self.msgT = self.msgT - dt end
  if self.blackT > 0 then self.blackT = self.blackT - dt end
  if self.flashT > 0 then self.flashT = self.flashT - dt end
  local ph = self.phase
  if ph ~= "sheet" then self.wt = self.wt + dt end
  if ph == "shoot" then self:updateAim(dt) else self.panVx, self.panVy = 0, 0 end
  local ex = self.exp
  if ex.active then
    ex.t = ex.t + dt
    if ex.t >= ex.te then self:endExposure() end
  end
  local ev = self:sceneEV(self.ox, self.oy, self.wt)
  self.evNow = ev
  self.eNow = ev - (self.aI + self.sI + 1)
  self.needle = U.damp(self.needle, U.clamp(self.eNow, -3.4, 3.4), 10, dt)

  -- sounds of the harbour
  if ph ~= "sheet" then
    self.sea:set(900, 0.025 + 0.012 * sin(self.t * 0.7))
    if math.random() < dt * 0.1 then
      Audio.play(Audio.SINE, 1500, 0.06, 0.1, 0.01, 0.08, 0.3, 0.05)
      Audio.play(Audio.SINE, 1250, 0.05, 0.12, 0.01, 0.1, 0.3, 0.05, 0.14)
    end
  else
    self.sea:stop()
  end
  if ph == "rewind" then
    local v = max(0, -self.tracker.vel)
    self.whirr:set(80 + v * 0.25, v > 20 and 0.05 or 0)
  end

  -- the day ends
  if not self.tut and ph ~= "sheet" then
    local limit = self.mode == "endless" and self.dayLen * 1.6 or self.dayLen
    if self.wt > limit and not self.nightWarned then
      self.nightWarned = true
      self.msg, self.msgT = "NIGHT FALLS - REWIND", 3
      Audio.sfx.bell(440, 0.3)
    end
    if self.wt > limit + 45 then
      self.whirr:stop()
      self.sea:stop()
      if self.mode == "endless" then
        self:finish({ success = self.roll > 1, score = self.score, title = "THE LIGHT IS GONE",
          lines = { "Rolls developed: " .. (self.roll - 1), "The last roll never left the camera." } })
      else
        self:finish({ success = false, score = self.score, title = "UNDEVELOPED",
          lines = { "The film never left the camera.", "Rewind before the shop shuts." } })
      end
    end
  end

  if ph == "sheet" then
    local before = self.sheetT
    self.sheetT = self.sheetT + dt
    -- grease pencil squeaks as each keeper is circled
    local n = #self.shots
    for i = 1, n do
      local tc = 1.4 + (i - 1) * 0.3
      if before < tc and self.sheetT >= tc then
        local D = self.devel
        local k = D.order[i]
        if D.keeper[k] then
          Audio.play(Audio.SINE, 2200, 0.05, 0.05, 0.005, 0.04, 0.2, 0.02)
          Audio.play(Audio.SINE, 2500, 0.04, 0.05, 0.005, 0.04, 0.2, 0.02, 0.06)
        elseif D.ruined[k] then
          Audio.play(Audio.NOISE, 2000, 0.08, 0.05, 0.005, 0.05, 0, 0.02)
        end
      end
    end
    local tEnd = 1.4 + n * 0.3
    if before < tEnd and self.sheetT >= tEnd then
      if self.devel.itemsTotal >= self.devel.maxItems * 0.6 then Audio.sfx.success() else Audio.sfx.bell(660, 0.3) end
    end
    if self.sel > 0 then self:renderLoupe(self.sel) end
  end
end

------------------------------------------------------------------------
-- drawing: camera
------------------------------------------------------------------------
function Cam:drawViewfinder()
  local W = self.W
  local wt = self.wt
  local evb = evBaseAt(self, wt)
  gfx.setClipRect(VX, VY, VS, VS)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(VX, VY, VS, VS)
  GHOST, FAINT = false, false
  setXf(self.ox, self.oy, 1, VX, VY, VS)
  drawSky(self, W, wt)
  self.bg:draw(VX - floor(self.ox + 0.5), VY - floor(self.oy + 0.5))
  setXf(floor(self.ox + 0.5), floor(self.oy + 0.5), 1, VX, VY, VS)
  -- a glint on the water
  gfx.setColor(gfx.kColorWhite)
  for i = 0, 5 do
    local gx = 170 + (i * 71 + floor(self.t * (6 + i))) % 380
    local gy = 118 + (i * 17) % 60
    if not off(gx, gx + 6) then L(gx, gy, gx + 3 + i % 3, gy) end
  end
  drawSubjects(W, wt)
  local dk = U.clamp((13.5 - evb) / 9, 0, 0.6)
  if dk > 0.02 then
    gfx.setColor(gfx.kColorBlack)
    gfx.setDitherPattern(dk, gfx.kDitherTypeBayer4x4)
    gfx.fillRect(VX, VY, VS, VS)
  end
  drawLights(self, W, wt, evb)
  -- the stranger: you are never quite sure you saw it
  local fs = figureAt(W, wt)
  if fs > 0 and floor(self.t * 12) % 5 ~= 0 then
    FAINT = true
    drawFigure(fs)
    FAINT = false
  end
  gfx.setColor(gfx.kColorBlack)
  -- ground glass: thirds and centre ring (XOR so they read on anything)
  gfx.setColor(gfx.kColorXOR)
  for k = 1, 2 do
    local x = VX + k * VS / 3
    local y = VY + k * VS / 3
    for d = 0, VS - 1, 6 do
      gfx.fillRect(x, VY + d, 1, 2)
      gfx.fillRect(VX + d, y, 2, 1)
    end
  end
  gfx.drawCircleAtPoint(VX + VS / 2, VY + VS / 2, 12)
  gfx.fillRect(VX + VS / 2 - 3, VY + VS / 2, 7, 1)
  gfx.fillRect(VX + VS / 2, VY + VS / 2 - 3, 1, 7)
  gfx.clearClipRect()
  gfx.setColor(gfx.kColorBlack)
  -- shutter blink
  if self.blackT > 0 then
    gfx.fillRect(VX, VY, VS, VS)
  elseif self.exp.active then
    gfx.setColor(gfx.kColorWhite)
    gfx.setLineWidth(3)
    gfx.drawRect(VX + 2, VY + 2, VS - 4, VS - 4)
    gfx.setLineWidth(1)
    UI.panel(VX + 44, VY + 6, 80, 22, "ink")
    UI.textW("OPEN", VX + VS / 2, VY + 9, "center", UI.bold)
  end
  if self.flashT > 0 then
    gfx.setColor(gfx.kColorWhite)
    gfx.setLineWidth(2)
    gfx.drawRect(VX, VY, VS, VS)
    gfx.setLineWidth(1)
  end
  gfx.setColor(gfx.kColorBlack)
end

function Cam:drawRewinding()
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(VX, VY, VS, VS)
  -- the rewind crank and the film running back into the cassette
  local cx, cy = VX + VS / 2, VY + 70
  local a = rad(self.filmPos * REW_DPF)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(cx, cy, 34)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(cx, cy, 30)
  gfx.setColor(gfx.kColorWhite)
  gfx.setLineWidth(3)
  gfx.drawLine(cx, cy, cx + sin(a) * 26, cy - cos(a) * 26)
  gfx.setLineWidth(1)
  gfx.fillCircleAtPoint(cx + sin(a) * 26, cy - cos(a) * 26, 5)
  gfx.fillCircleAtPoint(cx, cy, 4)
  for i = 0, 11 do
    local b = a + i * 0.5236
    gfx.drawLine(cx + sin(b) * 31, cy - cos(b) * 31, cx + sin(b) * 34, cy - cos(b) * 34)
  end
  UI.textW("REWINDING", cx, VY + 116, "center", UI.bold)
  local turns = self.filmPos * REW_DPF / 360
  UI.textW(U.cached("cam_turns", "%.1f turns left", floor(turns * 10) / 10), cx, VY + 136, "center")
  -- progress of film back into the cassette
  local f = U.clamp(self.filmPos / max(1, self.rewFrom or 1), 0, 1)
  gfx.drawRect(VX + 24, VY + 156, VS - 48, 6)
  gfx.fillRect(VX + 26, VY + 158, floor((VS - 52) * f), 2)
  gfx.setColor(gfx.kColorBlack)
end

-- red window, knob, settings, meter, brief card
function Cam:drawBack()
  local x0 = 178
  gfx.setPattern(Art.pat.gray75)
  gfx.fillRect(x0, 18, 222, 204)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawLine(x0, 18, x0, 222)
  -- red window
  gfx.fillRoundRect(184, 23, 122, 42, 10)
  gfx.setPattern(Art.pat.gray87)
  gfx.fillRoundRect(190, 29, 110, 30, 12)
  local cxw = 245
  local fp = self.filmPos
  gfx.setClipRect(192, 29, 106, 30)
  local PX <const> = 150
  for k = floor(fp) - 1, floor(fp) + 2 do
    local x = cxw + (k - fp) * PX
    if k >= 1 and k <= FRAMES then
      UI.textW(NUMS[k], x, 36, "center", UI.bold)
      -- the backing paper's warning dots before each number
      gfx.setColor(gfx.kColorWhite)
      for d = 1, 4 do gfx.fillCircleAtPoint(x - PX * (0.5 - d * 0.075), 44, 0.8 + d * 0.5) end
    elseif k == 0 then
      UI.textW("START", x - 22, 36, "left", UI.bold)
      gfx.setColor(gfx.kColorWhite)
      gfx.fillTriangle(x + 40, 38, x + 40, 50, x + 48, 44)
    elseif k == FRAMES + 1 then
      UI.textW("END", x - 14, 36, "left", UI.bold)
    end
  end
  gfx.clearClipRect()
  gfx.setColor(gfx.kColorWhite)
  gfx.fillTriangle(cxw - 5, 23, cxw + 5, 23, cxw, 29)
  gfx.fillTriangle(cxw - 5, 65, cxw + 5, 65, cxw, 59)
  gfx.setColor(gfx.kColorBlack)
  -- advance knob (turns with the crank; the rewind knob in rewind)
  local kx, ky = 352, 44
  local ka = rad(self.phase == "rewind" and self.filmPos * REW_DPF or self.knobA)
  gfx.fillCircleAtPoint(kx, ky, 25)
  gfx.setColor(gfx.kColorWhite)
  for i = 0, 17 do
    local a = ka + i * 0.349
    gfx.drawLine(kx + sin(a) * 19, ky - cos(a) * 19, kx + sin(a) * 24, ky - cos(a) * 24)
  end
  gfx.fillCircleAtPoint(kx, ky, 15)
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(3)
  gfx.drawLine(kx, ky, kx + sin(ka) * 12, ky - cos(ka) * 12)
  gfx.setLineWidth(1)
  gfx.fillCircleAtPoint(kx, ky, 3)
  if self.phase == "rewind" then UI.text("R", kx + 6, ky + 1, "left", UI.bold) end
  -- settings plate
  local held = Input.held(Input.B) and self.phase == "shoot"
  UI.panel(184, 70, 210, 26, held and "ink" or "plain")
  local draw = held and UI.textW or UI.text
  draw(SHUTTERS[self.sI], 236, 75, "center", UI.bold)
  draw(APERTURES[self.aI], 306, 75, "center", UI.bold)
  draw(U.cached("cam_exp", "%d/12", #self.shots), 390, 75, "right")
  if held then
    gfx.setColor(gfx.kColorWhite)
    gfx.fillTriangle(196, 83, 202, 78, 202, 88)
    gfx.fillTriangle(276, 83, 270, 78, 270, 88)
    gfx.fillTriangle(284, 80, 290, 74, 296 - 0, 80)
    gfx.fillTriangle(284, 86, 296, 86, 290, 92)
    gfx.setColor(gfx.kColorBlack)
  end
  -- light meter
  UI.panel(184, 100, 210, 30, "plain")
  local mx0, mx1, my = 214, 364, 120
  gfx.drawLine(mx0, my, mx1, my)
  for i = -3, 3 do
    local x = (mx0 + mx1) / 2 + i * (mx1 - mx0) / 6
    gfx.fillRect(x, my - (i == 0 and 6 or 3), i == 0 and 2 or 1, i == 0 and 6 or 3)
  end
  UI.text("-", 194, 110, "left", UI.bold)
  UI.text("+", 384, 110, "right", UI.bold)
  if self.noMeter then
    UI.text("BROKEN", 289, 104, "center")
  else
    local nx = (mx0 + mx1) / 2 + U.clamp(self.needle, -3.25, 3.25) * (mx1 - mx0) / 6
    gfx.fillTriangle(nx - 5, my - 14, nx + 5, my - 14, nx, my - 5)
    gfx.fillRect(nx, my - 5, 1, 8)
  end
  -- the brief: pictures of what to shoot, ticked in pencil
  self.briefImg:draw(184, 134)
  gfx.setColor(gfx.kColorBlack)
  for i = 1, #self.brief do
    if self.ticked[i] then
      -- a pencil tick across the little picture
      local x = 184 + 6 + ((i - 1) // 4) * 100 + 6
      local y = 134 + 6 + ((i - 1) % 4) * 19 + 5
      for pass = 1, 2 do
        gfx.setColor(pass == 1 and gfx.kColorWhite or gfx.kColorBlack)
        gfx.setLineWidth(pass == 1 and 5 or 2)
        gfx.drawLine(x, y + 4, x + 4, y + 9)
        gfx.drawLine(x + 4, y + 9, x + 14, y - 3)
      end
    end
  end
  gfx.setLineWidth(1)
  gfx.setColor(gfx.kColorBlack)
end

-- the brief card is static for a roll: render it once
function Cam:buildBriefCard()
  self.briefImg = self.briefImg or gfx.image.new(210, 86, gfx.kColorWhite)
  gfx.pushContext(self.briefImg)
  gfx.clear(gfx.kColorWhite)
  UI.panel(0, 0, 210, 86, "paper")
  gfx.setColor(gfx.kColorBlack)
  gfx.drawLine(104, 8, 104, 78)
  for i = 1, #self.brief do
    local x = 6 + ((i - 1) // 4) * 100
    local y = 6 + ((i - 1) % 4) * 19
    self:drawSubjIcon(self.brief[i].s, x + 14, y + 9, 1)
    UI.text(REQ_SHORT[self.brief[i].r], x + 30, y + 1, "left")
  end
  gfx.popContext()
end

-- small picture of a subject, centred on (cx, cy)
local ICON_POS <const> = {
  { 1000, 109 }, { 1000, 60 }, { 1000, 138 }, { 1000, 115 }, { 1000, 131 }, { 70, 38 }, { 1000, 71 }, { 1000, 102 },
}
local ICON_S <const> = { 0.36, 1, 0.95, 0.8, 0.62, 0.24, 0.15, 0.9 }
function Cam:drawSubjIcon(k, cx, cy, s)
  local wx, wy = ICON_POS[k][1], ICON_POS[k][2]
  s = s * ICON_S[k]
  setXf(wx, wy, s, cx, cy, 2000)
  GHOST, FAINT = false, false
  if k == S_FERRY then drawFerry(1000, 1)
  elseif k == S_GULL then drawGull(1000, 60, 0.8)
  elseif k == S_DOG then drawDog(1000, 1, 0.3)
  elseif k == S_COUPLE then drawCouple(1000)
  elseif k == S_CYCLIST then drawCyclist(1000, 1, 0.5)
  elseif k == S_LIGHT then drawLighthouse()
  elseif k == S_SPIRE then drawChurch(1000, 128)
  elseif k == S_SAIL then drawSail(999)
  end
  gfx.setColor(gfx.kColorBlack)
end

function Cam:drawStrip()
  -- info strip under the viewfinder: what you are looking at, time of day
  local best, bi = 0.3, 0
  for i = 1, #self.brief do
    local v = self:liveVis(self.brief[i].s, true)
    if v > best then best, bi = v, i end
  end
  if self.phase == "shoot" then
    if bi > 0 then
      UI.textW(self.briefText[bi], 6, 194, "left")
    else
      UI.textW("-", 6, 194, "left")
    end
  end
  -- daylight left
  if not self.tut then
    local u = U.clamp(self.wt / self.dayLen, 0, 1)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawRect(6, 212, 166, 6)
    gfx.fillRect(8, 214, floor(162 * (1 - u)), 2)
    gfx.setColor(gfx.kColorBlack)
  end
end

------------------------------------------------------------------------
-- drawing: contact sheet
------------------------------------------------------------------------
function Cam:drawSheet()
  local D = self.devel
  gfx.clear(gfx.kColorWhite)
  gfx.setPattern(Art.pat.grain)
  gfx.fillRect(0, 18, 400, 204)
  local st = self.sheetT
  if st < 1.2 then
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(0, 20, 258, 200)
    self.sheetImg:drawFaded(0, 20, st / 1.2, gfx.kDitherTypeBayer4x4)
  else
    self.sheetImg:draw(0, 20)
  end
  -- grease pencil: circles on keepers, crosses on the ruined
  local n = #self.shots
  for oi = 1, n do
    local i = D.order[oi]
    local tc = 1.4 + (oi - 1) * 0.3
    if st > tc then
      local x, y = sheetPos(self.shots[i].p)
      y = y + 20
      local prog = U.clamp((st - tc) / 0.25, 0, 1)
      if D.keeper[i] then
        gfx.setColor(gfx.kColorWhite)
        gfx.setLineWidth(4)
        gfx.drawEllipseInRect(x - 3, y - 3, THUMB + 6, THUMB + 6, 200, 200 + 350 * prog)
        gfx.setColor(gfx.kColorBlack)
        gfx.setLineWidth(2)
        gfx.drawEllipseInRect(x - 3, y - 3, THUMB + 6, THUMB + 6, 200, 200 + 350 * prog)
        gfx.setLineWidth(1)
      elseif D.ruined[i] then
        gfx.setColor(gfx.kColorWhite)
        gfx.setLineWidth(4)
        local d = (THUMB - 16) * prog
        gfx.drawLine(x + 8, y + 8, x + 8 + d, y + 8 + d)
        gfx.drawLine(x + THUMB - 8, y + 8, x + THUMB - 8 - d, y + 8 + d)
        gfx.setColor(gfx.kColorBlack)
        gfx.setLineWidth(2)
        gfx.drawLine(x + 8, y + 8, x + 8 + d, y + 8 + d)
        gfx.drawLine(x + THUMB - 8, y + 8, x + THUMB - 8 - d, y + 8 + d)
        gfx.setLineWidth(1)
      end
    end
  end
  -- the loupe sits on the selected frame
  if self.sel > 0 then
    local x, y = sheetPos(self.shots[self.sel].p)
    y = y + 20
    gfx.setColor(gfx.kColorXOR)
    gfx.setLineWidth(3)
    gfx.drawRect(x + 1, y + 1, THUMB - 2, THUMB - 2)
    gfx.setLineWidth(1)
    local cx = x + THUMB / 2
    gfx.setColor(gfx.kColorBlack)
    gfx.fillTriangle(cx - 8, y - 4, cx + 8, y - 4, cx, y + 6)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillTriangle(cx - 5, y - 3, cx + 5, y - 3, cx, y + 3)
    gfx.setColor(gfx.kColorBlack)
  end
  -- right column
  UI.panel(260, 20, 138, 200, "paper")
  if self.sel > 0 then
    local i = self.sel
    self.loupeImg:draw(273, 28)
    gfx.drawRect(272, 27, LOUPE + 2, LOUPE + 2)
    UI.text(D.frameStr[i], 329, 144, "center", UI.bold)
    UI.textLines(D.note[i], 268, 160, 124, 2, UI.font, -2)
    UI.text(D.qStr[i], 329, 196, "center")
  else
    self.colImg:draw(262, 22)
    local nb = #self.brief
    local rowH = nb > 7 and 18 or 20
    if st > 1.4 + n * 0.3 then
      for b = 1, nb do UI.text(D.ptsStr[b], 393, 44 + (b - 1) * rowH, "right", UI.bold) end
    end
    if st > 1.4 + n * 0.3 then
      gfx.drawLine(268, 196, 390, 196)
      UI.text(D.totalStr, 329, 200, "center", UI.bold)
    end
  end
end

------------------------------------------------------------------------
-- draw
------------------------------------------------------------------------
function Cam:clock()
  local minutes = floor(U.clamp(self.wt / self.dayLen, 0, 2) * 420) + 13 * 60
  if self.tut then minutes = 14 * 60 end
  if minutes ~= self.lastMinute then
    self.lastMinute = minutes
    local h = (minutes // 60) % 24
    local h12 = h % 12
    if h12 == 0 then h12 = 12 end
    local pre = self.mode == "endless" and ("ROLL " .. self.roll .. "  ") or ""
    self.clockStr = pre .. string.format("%d:%02d %s", h12, minutes % 60, h >= 12 and "PM" or "AM")
  end
  return self.clockStr
end

function Cam:draw()
  if self.phase == "sheet" then
    self:drawSheet()
    UI.header(3, "FILM CAMERA", self.tut and "LESSON" or "CONTACT SHEET")
    if not self.tut then UI.hints(self.mode == "endless" and self.devel.pass and Cam.HINTS_SHEET_E or Cam.HINTS_SHEET) end
    return
  end
  gfx.clear(gfx.kColorWhite)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(0, 18, 178, 204)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawRect(VX - 2, VY - 2, VS + 4, VS + 4)
  gfx.setColor(gfx.kColorBlack)
  if self.phase == "rewind" then self:drawRewinding() else self:drawViewfinder() end
  self:drawStrip()
  self:drawBack()
  UI.header(3, "FILM CAMERA", self.tut and "LESSON" or self:clock())
  if self.msgT > 0 and self.msg then
    UI.panel(VX + 4, VY + VS - 48, VS - 8, 42, "ink")
    UI.textBlock(self.msg, VX + 10, VY + VS - 44, VS - 20, UI.font, 0, nil, true, "center")
  end
  if not self.tut then UI.hints(self.phase == "rewind" and Cam.HINTS_REWIND or Cam.HINTS_SHOOT) end
end

------------------------------------------------------------------------
-- suspend / resume
------------------------------------------------------------------------
function Cam:serialize()
  local shots = {}
  for i = 1, #self.shots do
    local r = self.shots[i]
    shots[i] = { p = r.p, t0 = r.t0, te = r.te, ox = r.ox, oy = r.oy, cdx = r.cdx, cdy = r.cdy,
      shake = r.shake, ev = r.ev, e = r.e, st = r.st }
  end
  local brief = {}
  for i = 1, #self.brief do brief[i] = { s = self.brief[i].s, r = self.brief[i].r } end
  local ticked = {}
  for i = 1, #self.brief do ticked[i] = self.ticked[i] and true or false end
  return {
    phase = self.phase, wt = self.wt, t = self.t, rng = self.rng:state(), worldSeed = self.worldSeed,
    roll = self.roll, score = self.score, filmPos = self.filmPos, knobA = self.knobA,
    dpfBase = self.dpfBase, dpfK = self.dpfK, ox = self.ox, oy = self.oy, aI = self.aI, sI = self.sI,
    brief = brief, ticked = ticked, shots = shots, rollScores = self.rollScores,
    rewFrom = self.rewFrom or 0, nightWarned = self.nightWarned,
  }
end

function Cam:deserialize(t)
  self.rng:setState(t.rng)
  self.worldSeed = t.worldSeed
  self.W = genWorld(self.worldSeed, self.difficulty)
  self.bg = background(self.W, self.worldSeed)
  self.wt, self.t = t.wt, t.t or 0
  self.roll, self.score = t.roll, t.score
  self.filmPos, self.knobA = t.filmPos, t.knobA or 0
  self.dpfBase, self.dpfK = t.dpfBase, t.dpfK
  self.ox, self.oy, self.aI, self.sI = t.ox, t.oy, t.aI, t.sI
  self.brief = t.brief
  self:briefTexts()
  self:buildBriefCard()
  self.ticked = t.ticked or {}
  self.rollScores = t.rollScores or {}
  self.rewFrom = t.rewFrom
  self.nightWarned = t.nightWarned
  self.shots = t.shots or {}
  for i = 1, #self.shots do
    local r = self.shots[i]
    r.st = r.st or 0
    if not self.thumbs[i] then self.thumbs[i] = gfx.image.new(THUMB, THUMB, gfx.kColorWhite) end
    self:renderShot(r, self.thumbs[i], self.tmpS, THUMB)
  end
  self.phase = t.phase or "shoot"
  if self.phase == "sheet" then
    -- the score was already banked when this sheet was developed
    self:develop(true)
    self.sheetT = 5
  end
end
