-- CRANKING IT :: No.VI ELEVATOR OPERATOR
--
-- The crank is the CAR SWITCH: a brass lever with hard stops, not a spinner.
--   * every degree of crank travel moves the lever; the lever is clamped to
--     +-100 degrees, so winding past a stop just slips (like a real lever).
--     Clockwise = UP, counter-clockwise = DOWN, +-12 degrees = STOP.
--   * lever position is the motor's speed setting (a regulated DC hoist
--     motor: force = K * (setSpeed - v), limited to FMOTOR). The motor has
--     electrical lag, so the car answers the lever a beat late.
--   * the car has mass: car + counterweight + rotating drum + passengers.
--     The counterweight balances an empty car plus ~260 kg, so an empty car
--     wants to rise and a full one wants to sink - the same lever gives
--     different speeds, and braking distance changes with load and direction.
--   * in STOP the contactors open and the brake shoes close (with a short
--     lag). The brake is strong: dropping into STOP at speed is a jolt.
--   * the hoist ropes stretch: a loaded car sags a couple of pixels and
--     bounces after hard changes of acceleration.
-- The skill is anticipation: feather the lever down to a creep before the
-- floor, drop to STOP on the sill, and never slam the passengers.

local gfx <const> = playdate.graphics
local floor <const> = math.floor
local abs <const> = math.abs
local min <const>, max <const> = math.min, math.max
local sin <const>, cos <const>, rad <const> = math.sin, math.cos, math.rad

------------------------------------------------------------------------
-- constants
------------------------------------------------------------------------
local LEVER_MAX <const> = 100
local NEUTRAL <const> = 12
local FLOOR_M <const> = 3.5          -- metres per storey
local FH <const> = 64                -- pixels per storey
local PXM <const> = FH / FLOOR_M     -- pixels per metre
local GRAV <const> = 9.81
local CAR_KG <const> = 900
local CW_KG <const> = CAR_KG + 260
local ROT_KG <const> = 450
local VMAX <const> = 3.0             -- m/s at full lever
local KMOTOR <const> = 20000         -- N per m/s of speed error
local FMOTOR <const> = 6000          -- N motor limit
local FBRAKE <const> = 9500          -- N brake
local CAP_KG <const> = 640
local CAP_SLOTS <const> = 6
local COMFORT_A <const> = 1.6        -- m/s^2 felt as a lurch above this
local PERFECT_PX <const> = 2
local GOOD_PX <const> = 6
local BOARD_PX <const> = 12
local SHIFT <const> = 180
local MAXP <const> = 24
local MAXFX <const> = 20
local MSGN <const> = 4

local CAM_Y <const> = 164            -- screen y of the car sill
local SHAFT_X0 <const>, SHAFT_X1 <const> = 114, 214
local CAR_X <const> = 120            -- left edge of the car
local CAR_W <const> = 72
local CAR_H <const> = 56
local CW_X <const> = 200
local PANEL_X <const> = 262
local DIAL_CX <const>, DIAL_CY <const>, DIAL_R <const> = 331, 86, 58
local LEV_CX <const>, LEV_CY <const> = 331, 214

local LABELS4 <const> = { "L", "1", "2", "3" }
local LABELS10 <const> = { "L", "1", "2", "3", "4", "5", "6", "7", "8", "9" }
local LABELS14 <const> = { "L", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "14" }

-- passenger kinds
local SUIT <const>, GRAN <const>, BELL <const>, CHILD <const>, DIVER <const>, GHOST <const> = 1, 2, 3, 4, 5, 6
local KIND_KG <const> = { 85, 58, 210, 32, 150, 0 }
local KIND_SLOTS <const> = { 1, 1, 2, 1, 1, 1 }
local KIND_PATIENCE <const> = { 42, 80, 62, 56, 52, 9999 }
local KIND_SENS <const> = { 0.9, 2.6, 0.5, 0.3, 0.7, 0 }
local KIND_IMPAT <const> = { 2.0, 0.6, 1.0, 1.2, 1.0, 0 }
local KIND_WEIGHT <const> = { 30, 18, 13, 12, 10 }
local BOARD_LINE <const> = { "CHOP CHOP!", "GENTLY, DEAR.", "HEAVY ONE!", "WHEEE!", "GLUB.", "THIRTEEN..." }
local JOLT_LINE <const> = { "HEY!", "MY HIP!", "WHOA!", "AGAIN!", "GLUB!", "" }

local HINTS <const> = { { "CRANK", "LEVER" }, { "A", "GATE" } }

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
  -- shaft
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(cx - 14, cy - 12, 28, 32)
  gfx.setColor(gfx.kColorBlack)
  -- cage
  gfx.drawRect(cx - 11, cy - 6, 22, 24)
  for i = 0, 4 do gfx.drawLine(cx - 9 + i * 4, cy - 5, cx - 9 + i * 4, cy + 16) end
  gfx.drawLine(cx - 11, cy + 6, cx + 11, cy - 5)
  gfx.drawLine(cx - 11, cy - 5, cx + 11, cy + 6)
  gfx.drawLine(cx, cy - 12, cx, cy - 6)
  -- deco dial on top
  gfx.setColor(gfx.kColorWhite)
  gfx.fillEllipseInRect(cx - 14, cy - 22, 28, 20, 270, 90)
  gfx.setColor(gfx.kColorBlack)
  for i = -2, 2 do
    local a = rad(i * 30)
    gfx.drawLine(cx, cy - 12, cx + sin(a) * 12, cy - 12 - cos(a) * 9)
  end
  gfx.setLineWidth(2)
  gfx.drawLine(cx, cy - 12, cx + 7, cy - 18)
  gfx.setLineWidth(1)
end

local E = Machine.define({
  id = "elevator",
  number = 6,
  title = "ELEVATOR OPERATOR",
  tagline = "Don't slam them into floors.",
  description = "Run the brass cage of the Ninefold Hotel. The crank is the car switch: lever out to drive, STOP to brake.",
  howto = "Crank is a lever: clockwise UP, back DOWN, middle STOP (brake). Ease the lever down to a creep before the floor, STOP level with the sill, A opens the gate. Jolts and bad stops cost tips.",
  controls = { { "CRANK", "car switch lever" }, { "A", "open / close gate" } },
  modes = { "tutorial", "standard", "endless" },
  medals = { standard = { 1100, 2000, 2800 }, endless = { 1500, 4000, 7000 } },
  scoreLabel = "FARES",
  unlockCost = 0,
  achievements = {
    { id = "first", name = "GOING UP", desc = "Deliver your first passenger." },
    { id = "hairline", name = "HAIRLINE", desc = "Five perfect stops in a row." },
    { id = "gloves", name = "KID GLOVES", desc = "Give a grandmother a full tip." },
    { id = "ghost", name = "THE THIRTEENTH", desc = "Take the night guest to 13." },
    { id = "rush", name = "RUSH HOUR", desc = "Deliver 16 in one Standard shift." },
  },
  challenges = {
    { id = "worn", name = "WORN SHOES", desc = "The brake is worn: stops take longer.", mode = "standard", difficulty = 2,
      mods = { wornBrake = true }, goal = 1400, reward = 2, cost = 2 },
    { id = "velvet", name = "VELVET GLOVES", desc = "Only grandmothers, and they hate jolts.", mode = "standard", difficulty = 2,
      mods = { grans = true }, goal = 1800, reward = 3, cost = 2 },
    { id = "night", name = "GRAVEYARD SHIFT", desc = "Endless, after midnight, hard.", mode = "endless", difficulty = 3,
      mods = { night = true }, goal = 1500, reward = 3, cost = 3 },
  },
  records = {
    { "delivered", "Passengers carried" },
    { "perfect", "Perfect stops" },
    { "ghosts", "Night guests" },
    { "bestShift", "Best shift (fares)" },
  },
  drawIcon = drawIcon,
})

------------------------------------------------------------------------
-- setup
------------------------------------------------------------------------
function E:enter(params)
  self.t = 0
  local tut = self.mode == "tutorial"
  if tut then
    self.labels = LABELS4
  elseif self.mode == "endless" then
    self.labels = LABELS14
  else
    self.labels = LABELS10
  end
  self.floors = #self.labels
  self.topH = (self.floors - 1) * FLOOR_M
  self.labelW = {}
  for i = 1, self.floors do self.labelW[i] = UI.width(self.labels[i]) end
  self.ghostW = UI.width("13")
  local d = self.difficulty
  self.brakeScale = self:mod("wornBrake") and 0.6 or 1
  self.spawnBase = ({ 10, 8, 6.5 })[d] or 10
  self.patScale = ({ 1.2, 1.0, 0.85 })[d] or 1.2
  -- the tall hotel of the endless night: longer trips, more forgiving guests
  if self.mode == "endless" then self.patScale = self.patScale * 1.35 end
  -- car state (metres, m/s)
  self.y = 0
  self.v = 0
  self.uEff = 0
  self.brakeGrip = 1
  self.s, self.sv = 0, 0
  self.af = 0
  self.aReal = 0
  self.lever = 0
  self.leverVis = 0
  self.gate, self.gateTarget = 0, 0
  self.load = 0
  self.power = 0
  self.camH = 0
  self.lastBand = 0
  self.stopJudged = false
  self.stopErr = 0
  self.xferT = 0
  self.levelWarned = false
  self.buzzed = false
  self.joltCD = 0
  self.teaSpill = 0
  self.sheave = 0
  -- run state
  self.score = 0
  self.delivered = 0
  self.perfects = 0
  self.perfectRun = 0
  self.stormed = 0
  self.tips = 0
  self.ghostsCarried = 0
  self.spawnT = tut and 9999 or 3
  self.night = self:mod("night") and 1 or 0
  self.bubbleCycle = 0
  self.cycleIdx = 1
  self.endT = 0
  -- pools
  self.pax = {}
  for i = 1, MAXP do
    self.pax[i] = { active = false, kind = 1, state = "wait", fl = 0, dest = 0, x = 0, tx = 0,
      patience = 0, patMax = 1, mood = 1, kg = 0, slots = 1, slot = 0, changed = false,
      stumble = 0, bubbleT = 0, order = 0 }
  end
  self.carSlot = {}
  for k = 1, CAP_SLOTS do self.carSlot[k] = 0 end
  self.qCount = {}
  self.carCall = {}
  for f = 0, self.floors - 1 do self.qCount[f] = 0 self.carCall[f] = false end
  self.fx = {}
  for i = 1, MAXFX do self.fx[i] = { life = 0, x = 0, h = 0, vx = 0, vy = 0 } end
  self.msgs = {}
  for i = 1, MSGN do self.msgs[i] = { t = 0, s = "", x = 0, h = 0 } end
  self.hum = Audio.Hum.new(Audio.SAW)
  self.squeal = Audio.Hum.new(Audio.NOISE)
  if tut then self:setupCoach() end
end

function E:exit()
  self.hum:stop()
  self.squeal:stop()
end

function E:setupCoach()
  local s = self
  self.coach = UI.Coach.new({
    { text = "The crank is the car switch. Turn it CLOCKWISE a little: the lever tips to UP and the car climbs.",
      check = function() return s.v > 0.4 end },
    { text = "Turn it back to the middle. At STOP the brake grabs the car. Bring it to rest.",
      check = function() return s:stopped() end, hold = 0.4 },
    { text = "A small lever is a slow creep. Stop at floor 2, level with the sill (see the LEVEL window).",
      check = function() return s:stopped() and s:nearestFloor() == 2 and abs(s:levelErr()) <= GOOD_PX end, hold = 0.4 },
    { text = "Press A to open the gate. Mrs. Pell steps in.",
      check = function() return s:riderCount() > 0 end },
    { text = "A closes the gate. She wants the Lobby (L): turn COUNTER-clockwise to go DOWN.",
      check = function() return s.gate <= 0 and s.v < -0.3 end },
    { text = "She hates jolts! Ease the lever back early, creep in, STOP level at L and open the gate.",
      check = function() return s.delivered > 0 end },
  }, { y = 20, h = 46, x = 4, w = 392 })
  -- the lesson's passenger waits on floor 2 with endless patience
  local p = self:spawnPassenger(GRAN, 2, 0)
  if p then p.patience, p.patMax = 9999, 9999 end
end

------------------------------------------------------------------------
-- queries
------------------------------------------------------------------------
function E:carH() return self.y + self.s end
function E:nearestFloor()
  return U.clamp(floor(self:carH() / FLOOR_M + 0.5), 0, self.floors - 1)
end
-- signed levelling error in pixels (+ = car above sill)
function E:levelErr()
  local f = self:nearestFloor()
  return (self:carH() - f * FLOOR_M) * PXM
end
function E:stopped()
  return abs(self.lever) <= NEUTRAL and self.v == 0 and self.brakeGrip > 0.8
end
function E:riderCount()
  local n = 0
  for i = 1, MAXP do
    local p = self.pax[i]
    if p.active and (p.state == "ride" or p.state == "board") then n = n + 1 end
  end
  return n
end

------------------------------------------------------------------------
-- passengers
------------------------------------------------------------------------
function E:spawnPassenger(kind, origin, dest)
  for i = 1, MAXP do
    local p = self.pax[i]
    if not p.active then
      p.active = true
      p.kind = kind
      p.state = "arrive"
      p.fl = origin
      p.dest = dest
      p.x = -10
      p.tx = 96
      p.patMax = KIND_PATIENCE[kind] * self.patScale
      p.patience = p.patMax
      p.mood = 1
      p.kg = KIND_KG[kind]
      p.slots = KIND_SLOTS[kind]
      p.slot = 0
      p.changed = false
      p.stumble = 0
      p.bubbleT = 0
      p.order = 0
      return p
    end
  end
  return nil
end

function E:waitingCount()
  local n = 0
  for i = 1, MAXP do
    local p = self.pax[i]
    if p.active and (p.state == "wait" or p.state == "arrive") then n = n + 1 end
  end
  return n
end

function E:spawnTick(dt)
  self.spawnT = self.spawnT - dt
  if self.spawnT > 0 then return end
  local rng = self.rng
  local rate = self.spawnBase
  if self.mode == "endless" then rate = max(3.2, rate + 2 - self.t / 60) end
  self.spawnT = rate * rng:between(0.6, 1.4)
  if self:waitingCount() >= 10 then return end
  local n = self.floors
  -- ghost after midnight on the 14-storey building
  if self.night > 0.6 and n >= 14 and rng:chance(0.2) then
    for i = 1, MAXP do
      local p = self.pax[i]
      if p.active and p.kind == GHOST then return end
    end
    self:spawnPassenger(GHOST, rng:range(1, n - 3), n - 1)
    return
  end
  local kind = self:mod("grans") and GRAN or rng:weighted(KIND_WEIGHT)
  local origin, dest
  local phase = self.t / SHIFT
  if self.mode == "endless" then phase = (self.t / 90) % 3 / 3 end
  if phase < 0.33 and rng:chance(0.6) then
    origin, dest = 0, rng:range(1, n - 1)
  elseif phase > 0.66 and rng:chance(0.6) then
    origin, dest = rng:range(1, n - 1), 0
  else
    origin = rng:range(0, n - 1)
    dest = rng:range(0, n - 2)
    if dest >= origin then dest = dest + 1 end
  end
  -- don't overfill one landing
  if self.qCount[origin] >= 4 then return end
  self:spawnPassenger(kind, origin, dest)
end

function E:say(str, x, h)
  local best, bt = self.msgs[1], 99
  for i = 1, MSGN do
    local m = self.msgs[i]
    if m.t <= 0 then best = m break end
    if m.t < bt then best, bt = m, m.t end
  end
  best.s, best.x, best.h, best.t = str, x, h, 1.6
end

function E:puff(x, h, n, spread)
  for _ = 1, n do
    for i = 1, MAXFX do
      local f = self.fx[i]
      if f.life <= 0 then
        f.life = 0.4 + self.rng:float() * 0.4
        f.x, f.h = x + self.rng:between(-spread, spread), h
        f.vx = self.rng:between(-30, 30)
        f.vy = self.rng:between(0.2, 1.2)
        break
      end
    end
  end
end

function E:findSlots(n)
  for k = 1, CAP_SLOTS - n + 1 do
    local ok = true
    for j = k, k + n - 1 do if self.carSlot[j] ~= 0 then ok = false end end
    if ok then return k end
  end
  return 0
end

function E:slotX(p)
  return CAR_X + 9 + (p.slot - 1) * 9 + (p.slots - 1) * 4
end

-- one boarding / alighting step while the gate is open
function E:transferStep()
  local fl = self:nearestFloor()
  local err = abs(self:levelErr())
  local pax = self.pax
  -- anyone walking right now blocks the doorway
  for i = 1, MAXP do
    local p = pax[i]
    if p.active and ((p.state == "board" and p.x < SHAFT_X0 + 10) or (p.state == "alight" and p.x > 96)) then return end
  end
  local wants, full = false, false
  -- alight first
  for i = 1, MAXP do
    local p = pax[i]
    if p.active and p.state == "ride" and (p.dest == fl or p.mood <= 0) then
      wants = true
      if err <= BOARD_PX then
        self:alight(p, fl, err)
        return
      end
    end
  end
  for i = 1, MAXP do
    local p = pax[i]
    if p.active and p.state == "wait" and p.fl == fl then
      wants = true
      if err <= BOARD_PX then
        local k = self:findSlots(p.slots)
        if k == 0 or self.load + p.kg > CAP_KG then
          full = true
        else
          self:board(p, k, err)
          return
        end
      end
    end
  end
  if full then
    if not self.fullWarned then
      self.fullWarned = true
      self:say("CAR FULL!", 60, fl * FLOOR_M + 2.4)
      Audio.sfx.denied()
    end
    return
  end
  if wants and not self.levelWarned then
    self.levelWarned = true
    self:say("LEVEL IT!", 60, fl * FLOOR_M + 2.4)
    Audio.sfx.denied()
  end
end

function E:judgeStop(err)
  if self.stopJudged then return end
  self.stopJudged = true
  local h = self:carH() + 2.9
  if err <= PERFECT_PX then
    self.perfects = self.perfects + 1
    self.perfectRun = self.perfectRun + 1
    self:statAdd("perfect", 1)
    self:say("PERFECT", CAR_X + 36, h)
    Audio.sfx.bell(1568, 0.25)
    if self.perfectRun >= 5 then self:award("hairline") end
  elseif err <= GOOD_PX then
    self.perfectRun = 0
    self:say("LEVEL", CAR_X + 36, h)
  else
    self.perfectRun = 0
    self:say("MIND THE STEP!", CAR_X + 36, h)
  end
end

function E:board(p, k, err)
  self:judgeStop(err)
  p.state = "board"
  p.slot = k
  for j = k, k + p.slots - 1 do self.carSlot[j] = self:paxIndex(p) end
  p.tx = self:slotX(p)
  p.bubbleT = 2.5
  self.load = self.load + p.kg
  if err > GOOD_PX then
    p.mood = p.mood - 0.2
    p.stumble = 0.6
    Audio.sfx.thud(0.3)
  end
  -- waiting time eats into their mood a little
  p.mood = U.clamp(p.mood - (1 - p.patience / p.patMax) * 0.25, 0.05, 1)
  Audio.play(Audio.SQUARE, 660 + p.kind * 80, 0.12, 0.05)
  self:say(BOARD_LINE[p.kind], 60, p.fl * FLOOR_M + 2.6)
end

function E:paxIndex(p)
  for i = 1, MAXP do if self.pax[i] == p then return i end end
  return 0
end

function E:freeSlots(p)
  for j = 1, CAP_SLOTS do
    if self.carSlot[j] == self:paxIndex(p) then self.carSlot[j] = 0 end
  end
  p.slot = 0
end

-- riders shuffle along to close gaps (so a trolley can fit)
function E:compactSlots()
  local cs = self.carSlot
  for k = 1, CAP_SLOTS do cs[k] = 0 end
  local nextK = 1
  for k = 1, CAP_SLOTS do
    for i = 1, MAXP do
      local p = self.pax[i]
      if p.active and (p.state == "ride" or p.state == "board") and p.slot == k then
        if p.state == "ride" then p.slot = nextK end
        for j = p.slot, p.slot + p.slots - 1 do cs[j] = i end
        nextK = p.slot + p.slots
        p.tx = self:slotX(p)
      end
    end
  end
end

function E:alight(p, fl, err)
  self:judgeStop(err)
  self.load = max(0, self.load - p.kg)
  self:freeSlots(p)
  self:compactSlots()
  p.state = "alight"
  p.fl = fl
  p.tx = -14
  p.bubbleT = 0
  if p.mood <= 0 and p.dest ~= fl then
    -- storms out at the wrong floor
    self:strike(p, "I'LL WALK!")
    return
  end
  if err > GOOD_PX then
    p.mood = p.mood - 0.2
    p.stumble = 0.6
    Audio.sfx.thud(0.3)
  end
  local gain
  if p.kind == GHOST then
    gain = 250
    self.ghostsCarried = self.ghostsCarried + 1
    self:statAdd("ghosts", 1)
    self:award("ghost")
    self:say("...THANK YOU.", 60, fl * FLOOR_M + 2.6)
    Audio.sfx.bell(415, 0.4)
  else
    local lv = err <= PERFECT_PX and 50 or (err <= GOOD_PX and 20 or -20)
    local tip = floor(U.clamp(p.mood, 0, 1) ^ 1.5 * 80)
    local quick = floor(U.clamp(p.patience / p.patMax, 0, 1) * 30)
    gain = 60 + lv + tip + quick
    self.tips = self.tips + tip
    if p.kind == GRAN and p.mood >= 0.95 then self:award("gloves") end
    self:say(U.cached("elv_gain", "+%d", gain), 60, fl * FLOOR_M + 2.6)
  end
  self.delivered = self.delivered + 1
  if self.mode ~= "tutorial" then self.score = self.score + gain end
  self:statAdd("delivered", 1)
  self:award("first")
  if self.mode == "standard" and self.delivered >= 16 then self:award("rush") end
  Audio.sfx.coin()
end

function E:strike(p, line)
  if p.kind == GHOST then return end
  self.stormed = self.stormed + 1
  p.state = "leave"
  p.tx = -14
  p.mood = 0
  self.perfectRun = 0
  self:say(line, 60, p.fl * FLOOR_M + 2.6)
  Audio.sfx.denied()
  if self.mode ~= "tutorial" then self.score = max(0, self.score - 100) end
  self:shake(1.5)
  if self.mode == "endless" and self.stormed >= 3 then self:endRun(false) end
end

function E:updatePassengers(dt, moving)
  local pax = self.pax
  local qc = self.qCount
  for f = 0, self.floors - 1 do qc[f] = 0 self.carCall[f] = false end
  local aJ = abs(self.af)
  local disc = max(0, aJ - COMFORT_A) * 0.18
  local jolt = false
  if aJ > 2.8 and self.joltCD <= 0 then jolt = true self.joltCD = 1.2 end
  local ghostOn = false
  self.cycleIdx = floor(self.bubbleCycle) % max(1, self:riderCount()) + 1
  local riderN = 0
  for i = 1, MAXP do
    local p = pax[i]
    if p.active then
      local st = p.state
      if p.stumble > 0 then p.stumble = p.stumble - dt end
      if p.bubbleT > 0 then p.bubbleT = p.bubbleT - dt end
      if st == "arrive" or st == "wait" then
        p.order = qc[p.fl]
        qc[p.fl] = qc[p.fl] + 1
        p.tx = 98 - p.order * 16
        p.x = U.approach(p.x, p.tx, 36 * dt)
        if st == "arrive" and p.x >= p.tx then p.state = "wait" end
        if self.mode ~= "tutorial" then
          p.patience = p.patience - dt
          if p.patience <= 0 then self:strike(p, "I'LL TAKE THE STAIRS!") end
        end
      elseif st == "board" then
        p.x = U.approach(p.x, p.tx, 60 * dt)
        if p.x >= p.tx then p.state = "ride" end
      elseif st == "ride" then
        p.x = U.approach(p.x, p.tx, 30 * dt)
        riderN = riderN + 1
        p.order = riderN
        self.carCall[p.dest] = true
        if p.kind == GHOST then ghostOn = true end
        if self.mode ~= "tutorial" then
          p.mood = p.mood - dt * 0.004 * KIND_IMPAT[p.kind]
        end
        local sens = KIND_SENS[p.kind]
        if sens > 0 then
          p.mood = p.mood - disc * sens * dt
          if jolt then
            p.mood = p.mood - 0.1 * sens
            p.stumble = 0.5
          end
        end
        -- the child changes its mind once the car moves
        if p.kind == CHILD and not p.changed and moving and self.rng:chance(dt * 0.25) then
          p.changed = true
          local nd = self.rng:range(0, self.floors - 2)
          if nd >= p.dest then nd = nd + 1 end
          p.dest = nd
          p.bubbleT = 2.5
          self:say("NO, THIS ONE!", CAR_X + 36, self:carH() + 2.8)
        end
        if p.mood < 0 then p.mood = 0 end
      elseif st == "alight" or st == "leave" then
        p.x = U.approach(p.x, p.tx, (st == "leave" and 50 or 60) * dt)
        if p.x <= p.tx then p.active = false end
      end
    end
  end
  self.ghostAboard = ghostOn
  if jolt and riderN > 0 then
    Audio.sfx.clack(0.4)
    for i = 1, MAXP do
      local p = pax[i]
      if p.active and p.state == "ride" and KIND_SENS[p.kind] >= 0.5 then
        self:say(JOLT_LINE[p.kind], CAR_X + 36, self:carH() + 2.8)
        break
      end
    end
  end
end

------------------------------------------------------------------------
-- physics
------------------------------------------------------------------------
function E:physicsStep(dt)
  local lev = self.lever
  local gateShut = self.gate <= 0 and self.gateTarget == 0
  local powered = abs(lev) > NEUTRAL and gateShut
  local u = 0
  if powered then
    local f = (abs(lev) - NEUTRAL) / (LEVER_MAX - NEUTRAL)
    u = (f ^ 1.35) * (lev > 0 and 1 or -1)
  end
  self.uEff = U.damp(self.uEff, u, 3.2, dt)
  self.brakeGrip = U.approach(self.brakeGrip, powered and 0 or 1, dt / (powered and 0.08 or 0.14))
  local mass = CAR_KG + CW_KG + ROT_KG + self.load
  local fg = (CW_KG - CAR_KG - self.load) * GRAV
  local fm = 0
  if powered then fm = U.clamp(KMOTOR * (self.uEff * VMAX - self.v), -FMOTOR, FMOTOR) end
  self.power = abs(fm) / FMOTOR
  local fb = FBRAKE * self.brakeScale * self.brakeGrip
  local net = fm + fg
  local v = self.v
  local v0 = v
  if v ~= 0 then
    local nv = v + (net - (v > 0 and fb or -fb)) / mass * dt
    if (nv > 0) ~= (v > 0) and fb >= abs(net) then nv = 0 end
    v = nv
  elseif abs(net) > fb then
    v = (net - (net > 0 and fb or -fb)) / mass * dt
  end
  if v ~= 0 and abs(v) < 0.002 and fb > abs(net) then v = 0 end
  local a = (v - v0) / dt
  self.y = self.y + v * dt
  -- overtravel buffers in the pit and under the machine room
  local lo, hi = -0.25, self.topH + 0.25
  if self.y < lo or self.y > hi then
    local impact = abs(v)
    self.y = U.clamp(self.y, lo, hi)
    a = -v / dt * 0.25
    v = 0
    if impact > 0.6 then self:slam(impact) end
  end
  self.v = v
  self.aReal = a
  -- rope stretch: static sag under load plus a bounce excited by acceleration
  local w = 8.8
  local seq = -self.load * 0.0002
  local sa = -w * w * (self.s - seq) - 2 * 0.18 * w * self.sv - a * 0.6
  self.sv = self.sv + sa * dt
  self.s = self.s + self.sv * dt
  if self.s > 0.08 then self.s = 0.08 end
  if self.s < -0.2 then self.s = -0.2 end
  return a
end

function E:slam(impact)
  Audio.sfx.thud(1)
  Audio.sfx.clank(0.6)
  self:shake(4 + impact * 2)
  self.sv = self.sv - impact * 0.2
  self:puff(CAR_X + 36, self:carH(), 8, 30)
  for i = 1, MAXP do
    local p = self.pax[i]
    if p.active and p.state == "ride" and p.kind ~= GHOST then
      p.mood = p.mood - 0.35
      p.stumble = 0.8
    end
  end
  if self:riderCount() > 0 then self:say("YOU MANIAC!", CAR_X + 36, self:carH() + 2.8) end
end

------------------------------------------------------------------------
-- input
------------------------------------------------------------------------
function E:cranked(change)
  if self.finished then return end
  local before = self.lever
  self.lever = U.clamp(self.lever + change, -LEVER_MAX, LEVER_MAX)
  -- detent notches every 11 degrees, a firmer click at STOP
  if floor(before / 11) ~= floor(self.lever / 11) then Audio.sfx.tick(1400, 0.06) end
  if (abs(before) > NEUTRAL) ~= (abs(self.lever) > NEUTRAL) then
    Audio.sfx.click(0.3)
    if abs(self.lever) > NEUTRAL and self.gateTarget == 1 and not self.buzzed then
      self.buzzed = true
      Audio.sfx.denied()
      self:say("CLOSE THE GATE", CAR_X + 36, self:carH() + 2.8)
    end
  end
  if abs(self.lever) <= NEUTRAL then self.buzzed = false end
end

function E:rattle()
  for i = 0, 4 do
    Audio.play(Audio.NOISE, 2400 + i * 300, 0.18, 0.02, 0.001, 0.03, 0, 0.02, i * 0.06)
  end
  Audio.play(Audio.SQUARE, 220, 0.08, 0.05, 0.001, 0.05, 0, 0.02, 0.3)
end

function E:buttonDown(b)
  if self.finished then return end
  if b == Input.A then
    if self.gateTarget == 0 then
      if self:stopped() then
        self.gateTarget = 1
        self.stopJudged = false
        self.levelWarned = false
        self.fullWarned = false
        self.xferT = 0.15
        self:rattle()
      else
        Audio.sfx.denied()
        self:say("STOP FIRST", CAR_X + 36, self:carH() + 2.8)
      end
    else
      -- can't slam the gate on someone in the doorway
      for i = 1, MAXP do
        local p = self.pax[i]
        if p.active and (p.state == "board" or (p.state == "alight" and p.x > 90)) then
          Audio.sfx.denied()
          return
        end
      end
      self.gateTarget = 0
      self:rattle()
    end
  end
end

------------------------------------------------------------------------
-- update
------------------------------------------------------------------------
function E:endRun(timeUp)
  if self.finished then return end
  self.hum:stop()
  self.squeal:stop()
  local rec = Save.machine(self.def.id).stats
  if self.mode == "standard" and self.score > (rec.bestShift or 0) then
    rec.bestShift = self.score
    Save.markDirty()
  end
  local ok = self.delivered > 0
  if ok then Audio.sfx.success() else Audio.sfx.fail() end
  local title
  if self.mode == "endless" then title = "THREE WALKED OUT"
  elseif self.delivered == 0 then title = "SACKED"
  elseif self.stormed == 0 then title = "SMOOTH OPERATOR"
  else title = "SHIFT OVER" end
  self:finish({ success = ok, score = self.score, title = title, delay = 1.6,
    lines = {
      "Delivered: " .. self.delivered,
      "Perfect stops: " .. self.perfects,
      "Tips: " .. self.tips,
      "Walked out: " .. self.stormed,
    } })
end

function E:update(dt)
  self.t = self.t + dt
  if self.finished then
    self.endT = self.endT + dt
    return
  end
  if self.mode == "endless" and not self:mod("night") then self.night = U.clamp((self.t - 90) / 60, 0, 1) end
  -- lever eases toward the crank position (visual only)
  self.leverVis = U.damp(self.leverVis, self.lever, 25, dt)
  local vPrev = self.v
  local a = 0
  for _ = 1, 2 do a = self:physicsStep(dt / 2) end
  local af0 = self.af
  self.af = U.damp(self.af, self.aReal, 8, dt)
  if self.joltCD > 0 then self.joltCD = self.joltCD - dt end
  -- stop thunk
  if vPrev ~= 0 and self.v == 0 then
    Audio.sfx.thunk(0.15 + min(0.6, abs(vPrev) * 0.4))
    if abs(vPrev) > 0.8 then self:shake(abs(vPrev)) end
  end
  -- floor passing ding
  local band = floor((self:carH() + FLOOR_M * 0.5) / FLOOR_M)
  if band ~= self.lastBand then
    self.lastBand = band
    Audio.play(Audio.SINE, 1760, 0.06, 0.05, 0.001, 0.12, 0, 0.1)
  end
  -- sounds
  local av = abs(self.v)
  self.hum:set(38 + av * 26 + self.power * 10, (abs(self.lever) > NEUTRAL and self.gateTarget == 0) and (0.04 + self.power * 0.1) or (av > 0.05 and 0.025 or 0))
  local squeal = (self.brakeGrip > 0.3 and av > 0.15) and min(0.12, av * 0.05) or 0
  self.squeal:set(1800, squeal)
  if squeal > 0.05 and self.rng:chance(0.5) then
    self:puff(CAR_X + 2, self:carH() + 0.5, 1, 1)
  end
  self.sheave = self.sheave + self.v * dt * PXM * 3
  -- tea in the cup: filtered acceleration tilts it and slops it over
  if abs(self.af) > COMFORT_A then self.teaSpill = min(1, self.teaSpill + (abs(self.af) - COMFORT_A) * dt * 1.5) end
  self.teaSpill = max(0, self.teaSpill - dt * 0.15)
  -- gate
  local gPrev = self.gate
  self.gate = U.approach(self.gate, self.gateTarget, dt * 3.4)
  if self.gate >= 1 then
    if gPrev < 1 then
      local err = abs(self:levelErr())
      if err > BOARD_PX and err < FH * 0.35 then self:say("NOT LEVEL", CAR_X + 36, self:carH() + 2.8) end
    end
    self.xferT = self.xferT - dt
    if self.xferT <= 0 then
      self.xferT = 0.35
      self:transferStep()
    end
  end
  self.bubbleCycle = self.bubbleCycle + dt * 0.7
  self:updatePassengers(dt, av > 0.3)
  if self.mode ~= "tutorial" then self:spawnTick(dt) end
  -- camera follows the car
  self.camH = U.damp(self.camH, self:carH(), 5, dt)
  -- fx
  for i = 1, MAXFX do
    local f = self.fx[i]
    if f.life > 0 then
      f.life = f.life - dt
      f.x = f.x + f.vx * dt
      f.h = f.h + f.vy * dt
      f.vy = f.vy - 2 * dt
    end
  end
  for i = 1, MSGN do
    local m = self.msgs[i]
    if m.t > 0 then m.t = m.t - dt m.h = m.h + dt * 0.25 end
  end
  if self.mode == "standard" and self.t >= SHIFT then self:endRun(true) end
end

------------------------------------------------------------------------
-- drawing
------------------------------------------------------------------------
local function floorImage(night)
  return Art.cached(night and "elv_floor_n" or "elv_floor_d", 262, FH, function(w, h)
    -- exterior wall
    gfx.setPattern(Art.pat.bricks)
    gfx.fillRect(0, 0, 14, h)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(14, 0, 14, h)
    -- landing wallpaper
    gfx.setPattern(night and Art.pat.gray25 or Art.pat.gray6)
    gfx.fillRect(15, 0, 97, h - 6)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(15, h - 22, 97, 16)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(15, h - 22, 112, h - 22)
    gfx.drawLine(15, h - 20, 112, h - 20)
    -- deco sconce
    gfx.fillTriangle(66, 14, 78, 14, 72, 22)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(72, 12, 3)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawCircleAtPoint(72, 12, 3)
    gfx.drawLine(72, 22, 72, 26)
    -- doorway frame at the shaft with a stepped deco lintel
    gfx.fillRect(104, 0, 8, h - 6)
    gfx.fillRect(98, 0, 14, 4)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawLine(106, 6, 106, h - 8)
    gfx.setColor(gfx.kColorBlack)
    -- right rooms: window onto the night harbour
    gfx.setPattern(Art.pat.grain)
    gfx.fillRect(216, 0, 46, h - 6)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(226, 12, 26, 30)
    gfx.setColor(gfx.kColorWhite)
    if night then
      gfx.drawPixel(231, 18) gfx.drawPixel(244, 16) gfx.drawPixel(238, 24)
      gfx.fillCircleAtPoint(246, 22, 2)
    else
      gfx.setPattern(Art.pat.gray50)
      gfx.fillRect(228, 14, 22, 26)
      gfx.setColor(gfx.kColorWhite)
    end
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(239, 12, 239, 42)
    gfx.drawLine(226, 27, 252, 27)
    gfx.drawRect(224, 10, 30, 34)
    -- floor slabs
    gfx.fillRect(0, h - 6, 114, 6)
    gfx.fillRect(214, h - 6, 48, 6)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawLine(15, h - 4, 110, h - 4)
    gfx.setColor(gfx.kColorBlack)
  end)
end

local function carImage()
  return Art.cached("elv_car", CAR_W + 4, CAR_H + 10, function(w, h)
    local x0, y0 = 2, 10
    -- back wall: pale panelling with a brass dado rail
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(x0, y0, CAR_W, CAR_H)
    gfx.setPattern(Art.pat.gray12)
    gfx.fillRect(x0, y0 + 6, CAR_W, 12)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(x0, y0 + 18, x0 + CAR_W, y0 + 18)
    gfx.drawLine(x0, y0 + CAR_H - 18, x0 + CAR_W, y0 + CAR_H - 18)
    -- deco crown: a fan above the roof
    gfx.fillEllipseInRect(x0 + CAR_W / 2 - 16, 0, 32, 20, 270, 90)
    gfx.setColor(gfx.kColorWhite)
    for i = -3, 3 do
      local a = rad(i * 24)
      gfx.drawLine(x0 + CAR_W / 2, 10, x0 + CAR_W / 2 + sin(a) * 14, 10 - cos(a) * 9)
    end
    gfx.setColor(gfx.kColorBlack)
    -- roof and floor plates
    gfx.fillRect(x0 - 2, y0, CAR_W + 4, 5)
    gfx.fillRect(x0 - 2, y0 + CAR_H - 4, CAR_W + 4, 5)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawLine(x0, y0 + 2, x0 + CAR_W, y0 + 2)
    gfx.setColor(gfx.kColorBlack)
    -- corner posts
    gfx.fillRect(x0 - 2, y0, 4, CAR_H)
    gfx.fillRect(x0 + CAR_W - 2, y0, 4, CAR_H)
    -- ceiling lamp
    gfx.drawLine(x0 + CAR_W / 2, y0 + 5, x0 + CAR_W / 2, y0 + 9)
    gfx.fillEllipseInRect(x0 + CAR_W / 2 - 4, y0 + 8, 8, 5)
    -- operator's switch box on the back wall
    gfx.fillRect(x0 + CAR_W - 13, y0 + 22, 8, 10)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawRect(x0 + CAR_W - 12, y0 + 23, 6, 8)
    gfx.setColor(gfx.kColorBlack)
  end)
end

local function dialImage(labels, n)
  return Art.cached("elv_dial" .. n, 128, 70, function(w, h)
    local cx, cy, r = 64, 66, DIAL_R
    gfx.setColor(gfx.kColorBlack)
    gfx.fillEllipseInRect(cx - r - 4, cy - r - 4, (r + 4) * 2, (r + 4) * 2, 270, 90)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawArc(cx, cy, r + 1, 270, 90)
    gfx.drawArc(cx, cy, r - 18, 270, 90)
    -- sunburst
    for i = 0, 12 do
      local a = rad(-90 + i * 15)
      gfx.drawLine(cx + sin(a) * 10, cy - cos(a) * 10, cx + sin(a) * (r - 22), cy - cos(a) * (r - 22))
    end
    gfx.fillCircleAtPoint(cx, cy, 8)
    -- floor labels
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    for i = 1, n do
      local a = rad(-78 + 156 * (i - 1) / (n - 1))
      if n <= 10 or (i % 2 == 1 and i ~= n - 1) or i == n then
        local lx, ly = cx + sin(a) * (r - 9), cy - cos(a) * (r - 9)
        UI.font:drawTextAligned(labels[i], lx, ly - 7, kTextAlignment.center)
      end
    end
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
  end)
end

local function leverPlate()
  return Art.cached("elv_lever", 138, 96, function(w, h)
    local cx, cy, r = 69, 90, 66
    gfx.setColor(gfx.kColorBlack)
    gfx.fillEllipseInRect(cx - r, cy - r, r * 2, r * 2, 270, 90)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawArc(cx, cy, r - 3, 272, 88)
    -- neutral band notch
    local nb = NEUTRAL * 0.7
    gfx.fillEllipseInRect(cx - r + 5, cy - r + 5, (r - 5) * 2, (r - 5) * 2, 360 - nb, nb)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(cx, cy, r - 20)
    gfx.setColor(gfx.kColorWhite)
    -- speed steps
    for i = 1, 5 do
      local f = NEUTRAL + (LEVER_MAX - NEUTRAL) * i / 5
      for s = -1, 1, 2 do
        local a = rad(s * f * 0.7)
        gfx.drawLine(cx + sin(a) * (r - 12), cy - cos(a) * (r - 12), cx + sin(a) * (r - 4), cy - cos(a) * (r - 4))
      end
    end
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    UI.bold:drawText("UP", cx + 22, cy - 42)
    UI.bold:drawText("DN", cx - 44, cy - 42)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    gfx.setColor(gfx.kColorBlack)
  end)
end

-- screen y of a world height (metres)
function E:sy(h) return CAM_Y - (h - self.camH) * PXM end

local function bubble(x, y, str, w, inverted)
  local bw = w + 8
  local bx = floor(x - bw / 2)
  local bh = UI.lineH + 1
  if bx < 16 then bx = 16 end
  gfx.setColor(inverted and gfx.kColorBlack or gfx.kColorWhite)
  gfx.fillRoundRect(bx, y - bh, bw, bh, 4)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRoundRect(bx, y - bh, bw, bh, 4)
  gfx.fillTriangle(x - 2, y - 1, x + 3, y - 1, x, y + 3)
  if inverted then UI.textW(str, bx + 4, y - bh + 1) else UI.text(str, bx + 4, y - bh + 1) end
end

-- figure with feet at (x, fy)
local function drawFigure(kind, x, fy, t, stumble, mood)
  x, fy = floor(x), floor(fy)
  local lean = stumble > 0 and floor(sin(stumble * 25) * 2) or 0
  gfx.setColor(gfx.kColorBlack)
  if kind == GHOST then
    local bob = floor(sin(t * 3 + x) * 2)
    gfx.setDitherPattern(0.5, gfx.kDitherTypeBayer4x4)
    gfx.fillEllipseInRect(x - 6, fy - 26 + bob, 12, 12)
    gfx.fillRect(x - 6, fy - 20 + bob, 12, 14)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawEllipseInRect(x - 6, fy - 26 + bob, 12, 12, 270, 90)
    gfx.fillRect(x - 3, fy - 21 + bob, 2, 2)
    gfx.fillRect(x + 1, fy - 21 + bob, 2, 2)
    for i = 0, 2 do gfx.drawLine(x - 6 + i * 4, fy - 6 + bob, x - 4 + i * 4, fy - 3 + bob) end
    return
  end
  if kind == CHILD then
    gfx.drawLine(x - 1, fy, x - 1, fy - 4)
    gfx.drawLine(x + 1, fy, x + 1, fy - 4)
    gfx.fillRect(x - 3 + lean, fy - 11, 6, 7)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(x + lean, fy - 14, 3)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawCircleAtPoint(x + lean, fy - 14, 3)
    gfx.fillRect(x - 3 + lean, fy - 18, 6, 2)
    -- balloon
    gfx.drawLine(x + 3 + lean, fy - 10, x + 6, fy - 22)
    gfx.drawCircleAtPoint(x + 6, fy - 25, 3)
    return
  end
  -- legs
  gfx.drawLine(x - 2, fy, x - 2, fy - 6)
  gfx.drawLine(x + 1, fy, x + 1, fy - 6)
  local bx = x + lean
  if kind == GRAN then
    gfx.setPattern(Art.pat.gray50)
    gfx.fillRect(bx - 4, fy - 16, 8, 12)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(bx - 4, fy - 16, 8, 12)
    gfx.drawLine(bx + 6, fy, bx + 5, fy - 12)
  elseif kind == DIVER then
    gfx.fillRect(bx - 5, fy - 16, 10, 11)
  else
    gfx.fillRect(bx - 4, fy - 16, 8, 10)
  end
  -- head
  local hy = fy - 20
  if kind == DIVER then
    gfx.fillCircleAtPoint(bx, hy - 1, 6)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(bx + 1, hy - 1, 3)
    gfx.setColor(gfx.kColorBlack)
  else
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(bx, hy, 3)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawCircleAtPoint(bx, hy, 3)
  end
  if kind == SUIT then
    gfx.fillRect(bx - 3, hy - 6, 7, 3)
    gfx.drawLine(bx - 5, hy - 3, bx + 5, hy - 3)
    gfx.fillRect(bx + 5, fy - 9, 5, 4)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawLine(bx, fy - 15, bx, fy - 10)
    gfx.setColor(gfx.kColorBlack)
  elseif kind == GRAN then
    gfx.fillCircleAtPoint(bx - 3, hy - 3, 2)
  elseif kind == BELL then
    gfx.fillRect(bx - 2, hy - 6, 5, 3)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawPixel(bx - 1, fy - 13) gfx.drawPixel(bx - 1, fy - 10)
    gfx.setColor(gfx.kColorBlack)
    -- trolley with luggage
    gfx.drawRect(bx + 5, fy - 5, 12, 3)
    gfx.fillRect(bx + 6, fy - 13, 10, 8)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawRect(bx + 8, fy - 11, 6, 4)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(bx + 8, fy - 17, 7, 4)
    gfx.fillCircleAtPoint(bx + 7, fy - 1, 1)
    gfx.fillCircleAtPoint(bx + 15, fy - 1, 1)
  end
  if mood and mood < 0.35 then
    -- steam of anger
    local ph = floor(t * 6) % 2
    gfx.drawLine(bx + 4, hy - 5 - ph, bx + 6, hy - 8 - ph)
    gfx.drawLine(bx - 4, hy - 5 - ph, bx - 6, hy - 8 - ph)
  end
end

function E:labelFor(f)
  if f == self.floors - 1 and self.ghostAboard and self.floors >= 14 then return "13", self.ghostW end
  return self.labels[f + 1], self.labelW[f + 1]
end

function E:drawBuilding()
  local camH = self.camH
  -- shaft
  gfx.setPattern(Art.pat.gray75)
  gfx.fillRect(SHAFT_X0, 18, SHAFT_X1 - SHAFT_X0, 204)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(SHAFT_X0 - 2, 18, 2, 204)
  gfx.fillRect(SHAFT_X1, 18, 2, 204)
  -- guide rails
  gfx.setColor(gfx.kColorWhite)
  gfx.drawLine(SHAFT_X0 + 3, 18, SHAFT_X0 + 3, 222)
  gfx.drawLine(CW_X - 3, 18, CW_X - 3, 222)
  gfx.setColor(gfx.kColorBlack)
  local img = floorImage(self.night > 0.5)
  local f0 = floor(camH / FLOOR_M) - 3
  local n = self.floors
  for f = f0, f0 + 6 do
    local sill = floor(self:sy(f * FLOOR_M))
    local top = sill - FH
    if sill > 18 and top < 222 then
      if f >= 0 and f < n then
        img:draw(0, top + 6)
        -- floor plate and call lamp
        local lab, lw = self:labelFor(f)
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(18, top + 10, 26, 18)
        UI.textW(lab, 31, top + 11, "center")
        local calls = self.qCount[f] or 0
        gfx.setColor(gfx.kColorWhite)
        gfx.fillCircleAtPoint(31, top + 36, 4)
        gfx.setColor(gfx.kColorBlack)
        gfx.drawCircleAtPoint(31, top + 36, 4)
        if calls > 0 then
          if (self.t * 3) % 2 < 1.5 then gfx.fillCircleAtPoint(31, top + 36, 2) end
        end
      elseif f < 0 then
        -- the pit
        gfx.setPattern(Art.pat.bricks)
        gfx.fillRect(0, top + 6, 114, FH)
        gfx.fillRect(216, top + 6, 46, FH)
        gfx.setColor(gfx.kColorBlack)
        if f == -1 then
          -- buffer springs
          for i = 0, 3 do
            gfx.drawLine(140, top + 20 + i * 5, 170, top + 22 + i * 5)
          end
          gfx.fillRect(138, top + 40, 36, 30)
        end
      else
        -- machine room with the hoist sheave
        gfx.setPattern(Art.pat.hlines2)
        gfx.fillRect(0, top + 6, 262, FH)
        if f == n then
          gfx.setColor(gfx.kColorWhite)
          gfx.fillRect(20, top + 14, 222, FH - 14)
          gfx.setColor(gfx.kColorBlack)
          gfx.drawRect(20, top + 14, 222, FH - 14)
          local scx, scy = 178, sill - 6
          gfx.fillCircleAtPoint(scx, scy, 20)
          gfx.setColor(gfx.kColorWhite)
          gfx.drawCircleAtPoint(scx, scy, 16)
          Art.spokes(scx, scy, 16, 6, self.sheave)
          gfx.setColor(gfx.kColorBlack)
          gfx.fillRect(60, sill - 26, 60, 20)
          gfx.setColor(gfx.kColorWhite)
          UI.textW("HOIST", 90, sill - 25, "center")
          gfx.setColor(gfx.kColorBlack)
          gfx.drawLine(120, sill - 16, 158, sill - 10)
        end
        gfx.setColor(gfx.kColorBlack)
      end
    end
  end
  -- counterweight (moves opposite to the car)
  local cwH = self.topH - self.y + 1.0
  local cy = floor(self:sy(cwH))
  gfx.setColor(gfx.kColorWhite)
  gfx.drawLine(CW_X + 7, 18, CW_X + 7, cy - 40)
  gfx.setPattern(Art.pat.hatch)
  gfx.fillRect(CW_X, cy - 40, 13, 40)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(CW_X, cy - 40, 13, 40)
end

function E:drawCar()
  local sill = floor(self:sy(self:carH()))
  local top = sill - CAR_H + 4
  -- ropes
  gfx.setColor(gfx.kColorWhite)
  local rx = CAR_X + CAR_W / 2
  gfx.drawLine(rx - 3, 18, rx - 3, top - 8)
  gfx.drawLine(rx, 18, rx, top - 8)
  gfx.drawLine(rx + 3, 18, rx + 3, top - 8)
  gfx.setColor(gfx.kColorBlack)
  carImage():draw(CAR_X - 2, top - 10)
  -- operator (you) at the switch
  local ox = CAR_X + CAR_W - 10
  drawFigure(SUIT, ox, sill - 1, self.t, 0, 1)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(ox - 3, sill - 23, 7, 2)
  gfx.setColor(gfx.kColorBlack)
  -- riders
  local t = self.t
  for i = 1, MAXP do
    local p = self.pax[i]
    if p.active and (p.state == "ride" or ((p.state == "board" or p.state == "alight") and p.x > SHAFT_X0)) then
      drawFigure(p.kind, p.x, sill - 1, t, p.stumble, p.mood)
    end
  end
  -- scissor gate across the front, folding to the right
  local g = self.gate
  local gw = floor((CAR_W - 6) * (1 - g * 0.85))
  if gw > 2 then
    local gx1 = CAR_X + CAR_W - 3
    local gx0 = gx1 - gw
    local n = 5
    local step = gw / n
    gfx.setColor(gfx.kColorBlack)
    for k = 0, n do
      local x = floor(gx0 + k * step)
      gfx.drawLine(x, top + 6, x, sill - 1)
    end
    for k = 0, n - 1 do
      local xa, xb = floor(gx0 + k * step), floor(gx0 + (k + 1) * step)
      gfx.drawLine(xa, top + 8, xb, sill - 3)
      gfx.drawLine(xb, top + 8, xa, sill - 3)
    end
    gfx.setLineWidth(2)
    gfx.drawLine(gx0, top + 6, gx0, sill - 1)
    gfx.setLineWidth(1)
  end
  -- riders' destination bubbles
  for i = 1, MAXP do
    local p = self.pax[i]
    if p.active and p.state == "ride" and (p.bubbleT > 0 or p.mood <= 0 or p.order == self.cycleIdx) then
      local lab, lw = self:labelFor(p.dest)
      if p.mood <= 0 then lab, lw = "!!", 8 end
      bubble(floor(p.x), top + 20 - (p.slot % 2) * 4, lab, lw, p.mood < 0.35)
    end
  end
  -- brake sparks & dust
  for i = 1, MAXFX do
    local f = self.fx[i]
    if f.life > 0 then
      local py = self:sy(f.h)
      gfx.fillRect(floor(f.x), floor(py), 2, 2)
    end
  end
end

function E:drawLanding()
  -- waiting and walking passengers on landings
  local t = self.t
  for i = 1, MAXP do
    local p = self.pax[i]
    if p.active and p.state ~= "ride" and not ((p.state == "board" or p.state == "alight") and p.x > SHAFT_X0) then
      local sill = self:sy(p.fl * FLOOR_M)
      if sill > 30 and sill < 240 + 30 then
        drawFigure(p.kind, p.x, sill - 1, t, p.stumble, p.state == "wait" and (p.patience / p.patMax) or 1)
        if p.state == "wait" then
          local lab, lw = self:labelFor(p.dest)
          if p.kind == GHOST then lab, lw = "13", self.ghostW end
          local by = floor(sill - 30 - (p.order % 2) * 12)
          local frac = p.patience / p.patMax
          local jig = (frac < 0.3 and (t * 10) % 2 < 1) and 1 or 0
          bubble(floor(p.x) + jig, by, lab, lw, frac < 0.3)
          -- patience bar
          if p.kind ~= GHOST and self.mode ~= "tutorial" then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(floor(p.x) - 5, by + 5, floor(11 * U.clamp(frac, 0, 1)), 2)
          end
        end
      end
    end
  end
end

function E:drawLoupe()
  -- magnified levelling window next to the car sill
  local sill = floor(self:sy(self:carH()))
  local cy = U.clamp(sill, 60, 196)
  local x, y, w, h = 218, cy - 18, 42, 36
  local err = self:levelErr()
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x, y, w, h)
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(2)
  gfx.drawRect(x, y, w, h)
  gfx.setLineWidth(1)
  local mid = y + h // 2 + 2
  -- tolerance marks (x3 magnification)
  gfx.drawLine(x + 3, mid - PERFECT_PX * 3, x + 8, mid - PERFECT_PX * 3)
  gfx.drawLine(x + 3, mid + PERFECT_PX * 3, x + 8, mid + PERFECT_PX * 3)
  gfx.setPattern(Art.pat.gray50)
  gfx.fillRect(x + 3, mid - 15, 5, 15 - GOOD_PX * 3 + 3)
  gfx.fillRect(x + 3, mid + GOOD_PX * 3 - 2, 5, 15 - GOOD_PX * 3 + 3)
  gfx.setColor(gfx.kColorBlack)
  -- landing sill (fixed) on the left, car sill (moving) on the right
  gfx.fillRect(x + 10, mid, 14, 4)
  local off = floor(U.clamp(-err * 3, -16, 14))
  gfx.fillRect(x + 24, mid + off, 15, 3)
  gfx.drawLine(x + 24, mid + off, x + 24, mid + off - 6)
  -- caption tab: turns black when the car is level
  local lv = abs(err) <= PERFECT_PX
  local tw = 50
  if lv then gfx.fillRect(x - 4, y - 16, tw, 16) else
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(x - 4, y - 16, tw, 16)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(x - 4, y - 16, tw, 16)
  end
  if lv then UI.textW("LEVEL", x + w // 2, y - 16, "center") else UI.text("LEVEL", x + w // 2, y - 16, "center") end
end

function E:drawPanel()
  local x0 = PANEL_X
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x0, 18, 138, 204)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(x0, 18, 3, 204)
  -- floor indicator dial
  local n = self.floors
  dialImage(self.labels, n):draw(DIAL_CX - 64, DIAL_CY - 66)
  local cx, cy = DIAL_CX, DIAL_CY
  -- hall calls (outer ticks) and car calls (inner lamps)
  for f = 0, n - 1 do
    local a = rad(-78 + 156 * f / (n - 1))
    local s, c = sin(a), cos(a)
    if (self.qCount[f] or 0) > 0 then
      gfx.setColor(gfx.kColorBlack)
      gfx.fillCircleAtPoint(cx + s * (DIAL_R + 7), cy - c * (DIAL_R + 7), 3)
    end
    if self.carCall[f] then
      gfx.setColor(gfx.kColorWhite)
      gfx.fillCircleAtPoint(cx + s * (DIAL_R - 24), cy - c * (DIAL_R - 24), 3)
    end
  end
  local frac = U.clamp(self:carH() / self.topH, -0.02, 1.02)
  local a = rad(-78 + 156 * frac)
  gfx.setColor(gfx.kColorWhite)
  gfx.setLineWidth(3)
  gfx.drawLine(cx, cy, cx + sin(a) * (DIAL_R - 20), cy - cos(a) * (DIAL_R - 20))
  gfx.setLineWidth(1)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(cx, cy, 4)
  -- readouts: load and teacup
  gfx.fillRect(x0 + 3, 90, 135, 2)
  UI.text("LOAD", x0 + 8, 94)
  local lf = U.clamp(self.load / CAP_KG, 0, 1)
  gfx.drawRect(x0 + 8, 112, 64, 8)
  gfx.fillRect(x0 + 10, 114, floor(60 * lf), 4)
  -- teacup: tilts with the felt acceleration
  local tx, ty = x0 + 104, 110
  local tilt = U.clamp(self.af / 3, -1, 1)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(tx - 20, ty + 10, 40, 2)
  gfx.drawEllipseInRect(tx - 12, ty - 8, 24, 20, 90, 270)
  gfx.drawLine(tx - 12, ty + 2, tx + 12, ty + 2)
  gfx.drawCircleAtPoint(tx + 14, ty + 4, 3)
  local lvl = floor(3 + self.teaSpill * 5)
  gfx.drawLine(tx - 10, ty + lvl - floor(tilt * 5), tx + 10, ty + lvl + floor(tilt * 5))
  if abs(self.af) > COMFORT_A and (self.t * 12) % 2 < 1 then
    local sx = tilt > 0 and tx + 12 or tx - 13
    gfx.fillRect(sx, ty + 2, 2, 2)
    gfx.fillRect(sx + (tilt > 0 and 2 or -2), ty + 6, 2, 2)
  end
  -- the car switch lever
  gfx.fillRect(x0 + 3, 124, 135, 2)
  leverPlate():draw(LEV_CX - 69, LEV_CY - 90)
  local la = rad(self.leverVis * 0.7)
  local hx, hy = LEV_CX + sin(la) * 66, LEV_CY - cos(la) * 66
  gfx.setColor(gfx.kColorWhite)
  gfx.setLineWidth(7)
  gfx.drawLine(LEV_CX, LEV_CY, hx, hy)
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(3)
  gfx.drawLine(LEV_CX, LEV_CY, hx, hy)
  gfx.setLineWidth(1)
  gfx.fillCircleAtPoint(hx, hy, 8)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(hx - 2, hy - 2, 2)
  gfx.fillCircleAtPoint(LEV_CX, LEV_CY, 9)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawCircleAtPoint(LEV_CX, LEV_CY, 9)
  gfx.fillCircleAtPoint(LEV_CX, LEV_CY, 3)
  local st = "STOP"
  if self.lever > NEUTRAL then st = "UP" elseif self.lever < -NEUTRAL then st = "DOWN" end
  UI.text(st, x0 + 8, 128, "left", UI.bold)
  if self.gateTarget == 1 then UI.text("GATE", x0 + 130, 128, "right", UI.bold) end
end

function E:drawMessages()
  for i = 1, MSGN do
    local m = self.msgs[i]
    if m.t > 0 then
      local y = floor(self:sy(m.h))
      if y > 22 and y < 214 then
        local w = UI.width(m.s, UI.bold)
        local x = U.clamp(m.x, 20 + w / 2, 250 - w / 2)
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(floor(x - w / 2 - 3), y - 1, w + 6, UI.boldH + 1)
        UI.textW(m.s, x, y, "center", UI.bold)
      end
    end
  end
end

function E:draw()
  gfx.clear(gfx.kColorWhite)
  self:drawBuilding()
  self:drawLanding()
  self:drawCar()
  self:drawLoupe()
  self:drawMessages()
  self:drawPanel()
  local right
  if self.mode == "standard" then
    local left = max(0, floor(SHIFT - self.t))
    right = fmt3("elv_hdr", "%d  %d:%02d", self.score, left // 60, left % 60)
  elseif self.mode == "endless" then
    right = fmt2("elv_hdr", "%d  OUT %d/3", self.score, self.stormed)
  else
    right = "LESSON"
  end
  UI.header(6, "ELEVATOR OPERATOR", right)
  UI.hints(HINTS)
end

------------------------------------------------------------------------
-- suspend / resume
------------------------------------------------------------------------
local PAX_FIELDS <const> = { "kind", "state", "fl", "dest", "x", "patience", "patMax", "mood", "kg", "slots", "slot", "changed" }

function E:serialize()
  local pax = {}
  for i = 1, MAXP do
    local p = self.pax[i]
    if p.active and p.state ~= "leave" and p.state ~= "alight" then
      local q = {}
      for _, k in ipairs(PAX_FIELDS) do q[k] = p[k] end
      if q.state == "board" then q.state = "ride" end
      if q.state == "arrive" then q.state = "wait" end
      pax[#pax + 1] = q
    end
  end
  return {
    t = self.t, y = self.y, v = self.v, lever = self.lever, uEff = self.uEff,
    score = self.score, delivered = self.delivered, perfects = self.perfects,
    perfectRun = self.perfectRun, stormed = self.stormed, tips = self.tips,
    spawnT = self.spawnT, night = self.night, ghosts = self.ghostsCarried,
    rng = self.rng:state(), pax = pax,
  }
end

function E:deserialize(t)
  self.t, self.y, self.v = t.t or 0, t.y or 0, t.v or 0
  self.lever, self.uEff = t.lever or 0, t.uEff or 0
  self.leverVis = self.lever
  self.score, self.delivered = t.score or 0, t.delivered or 0
  self.perfects, self.perfectRun = t.perfects or 0, t.perfectRun or 0
  self.stormed, self.tips = t.stormed or 0, t.tips or 0
  self.spawnT, self.night = t.spawnT or 3, t.night or 0
  self.ghostsCarried = t.ghosts or 0
  if t.rng then self.rng:setState(t.rng) end
  self.camH = self.y
  self.gate, self.gateTarget = 0, 0
  self.brakeGrip = abs(self.lever) <= NEUTRAL and 1 or 0
  for i = 1, MAXP do self.pax[i].active = false end
  for k = 1, CAP_SLOTS do self.carSlot[k] = 0 end
  self.load = 0
  local list = t.pax or {}
  for j = 1, math.min(#list, MAXP) do
    local q = list[j]
    local p = self.pax[j]
    for _, k in ipairs(PAX_FIELDS) do if q[k] ~= nil then p[k] = q[k] end end
    p.active = true
    p.stumble, p.bubbleT, p.order = 0, 0, 0
    p.tx = p.x
    if p.state == "ride" then
      local k = self:findSlots(p.slots)
      if k == 0 then
        p.active = false
      else
        p.slot = k
        for s = k, k + p.slots - 1 do self.carSlot[s] = j end
        p.x = self:slotX(p)
        p.tx = p.x
        self.load = self.load + p.kg
      end
    end
  end
end
