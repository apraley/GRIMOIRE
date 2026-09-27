-- CRANKING IT :: No.XI CLOCKMAKER
--
-- The crank is a test instrument and a winding key.
--
--   BENCH: the crank turns the mainspring barrel by hand (2 crank turns =
--   1 barrel turn). Motion is propagated through the gear train you built,
--   mesh by mesh, at the true tooth ratios (driven = -driver * d / q).
--   Gears mesh only when their centre distance equals r1 + r2 (pitch
--   radius is proportional to tooth count, same module everywhere), so a
--   pair must add up to the gap's tooth sum. Too big BINDS (the whole train
--   upstream locks and the crank meets a hard stop), too small SLIPS (the
--   rest of the train stands still). A broken tooth transmits nothing while
--   it passes through the mesh, so the train downstream stutters once per
--   revolution of the damaged gear. A full barrel turn with a complete
--   train is a TEST: the measured hand ratio is compared with the ticket.
--
--   WIND: the crank winds the mainspring through a click (ratchet): it only
--   turns clockwise, each click tooth ticks, torque rises steeply near the
--   spring's limit (the key gets heavier: less wind per degree) and the
--   click pitch climbs. Past the limit the spring SNAPS.
--
-- Puzzles are generated solution-first: tooth counts per stage are drawn
-- from real clockmaking ratios, arbors are laid out so every stage's
-- centre distance equals the sum of its pitch radii, then distractors
-- (same-sum wrong-ratio pairs, near misses) are scattered into the tray.

local gfx <const> = playdate.graphics
local floor <const> = math.floor
local abs <const> = math.abs
local sin <const>, cos <const>, rad <const>, deg <const> = math.sin, math.cos, math.rad, math.deg
local sqrt <const> = math.sqrt
local atan <const> = math.atan

local K <const> = 1.0                  -- px of pitch radius per tooth
local PX0 <const>, PY0 <const>, PX1 <const>, PY1 <const> = 10, 26, 262, 214 -- plate
local TEST_GEAR <const> = 0.5          -- barrel degrees per crank degree
local ESC_TEETH <const> = 15
local ESC_R <const> = 11
local PINIONS <const> = { 6, 7, 8, 8, 9, 10, 10, 12, 12, 14, 15, 16 }
local RATIOS <const> = { 2, 2.5, 3, 3, 4, 4, 5, 6, 1.5 }
local STANDARD_CLOCKS <const> = 4
local MAX_TRAY <const> = 12

local NUMS = {}
for i = 0, 120 do NUMS[i] = tostring(i) end

local CLOCK_NAMES <const> = {
  "CARRIAGE CLOCK", "SHIP'S CHRONOMETER", "LONG-CASE, STAIRS", "TIDE CLOCK",
  "STATION REGULATOR", "KEEPER'S ALARM", "LIGHTHOUSE TIMER", "SOCIETY MASTER",
  "BRACKET CLOCK", "MANTEL CLOCK", "TURRET MOVEMENT", "POCKET WATCH",
}
local NOTES <const> = {
  assembly = { "A movement in pieces.", "Parts in a biscuit tin.", "Build the going train." },
  stutter = { "Stops for a moment, then goes on.", "It hesitates, now and then.", "It limps." },
  slow = { "It loses time.", "Always late. Always.", "Runs slow since winter." },
  fast = { "It gains time.", "Runs ahead of the tide.", "Too eager by half." },
  stopped = { "Won't go at all.", "Dead. Stopped.", "Nothing moves inside." },
}
local KIND_TITLE <const> = {
  assembly = "ASSEMBLY", stutter = "REPAIR", slow = "REPAIR", fast = "REPAIR", stopped = "REPAIR",
}

local PAT_BRASS <const> = { 0xff, 0xff, 0xdf, 0xff, 0xff, 0xff, 0xfd, 0xff }
local PAT_PLATE <const> = { 0x77, 0xdd, 0x77, 0xdd, 0x77, 0xdd, 0x77, 0xdd }

local Clock = Machine.define({
  id = "clockmaker",
  number = 11,
  title = "CLOCKMAKER",
  tagline = "Every tooth accounted for.",
  description = "Build gear trains that keep true time, find the broken tooth, then wind the mainspring - but never past its limit.",
  howto = "LEFT/RIGHT picks a slot, UP/DOWN a gear from the tray, A fits it, B takes it out. Meshing teeth must add up to the gap. Crank a full barrel turn to test the ratio, then wind clockwise and stop in the FULL band. A sets it going.",
  controls = { { "CRANK", "turn train / wind" }, { "DPAD", "slot & tray" }, { "A", "fit gear / start" }, { "B", "remove gear" } },
  modes = { "tutorial", "standard", "endless" },
  medals = { standard = { 2000, 4000, 5600 }, endless = { 3000, 7000, 12000 } },
  scoreLabel = "POINTS",
  unlockCost = 10,
  achievements = {
    { id = "first", name = "FIRST TICK", desc = "Finish your first clock." },
    { id = "true", name = "RIGHT FIRST TIME", desc = "Pass a 3-stage test first try." },
    { id = "full", name = "HAIR'S BREADTH", desc = "Wind a spring to 97% or more." },
    { id = "doctor", name = "CLOCK DOCTOR", desc = "Cure a stutter." },
    { id = "day", name = "A FULL DAY", desc = "All four clocks, no snapped spring." },
  },
  challenges = {
    { id = "byeye", name = "BY EYE", desc = "No tooth counts, no fit marks. Judge by sight.", mode = "standard", difficulty = 2, goal = 3500, reward = 3, cost = 2 },
    { id = "rusty", name = "RUSTED KEY", desc = "The crank sticks and lurches.", mode = "standard", difficulty = 1, mods = { rusty = true }, goal = 3500, reward = 2, cost = 2 },
    { id = "eve", name = "CHRISTMAS EVE", desc = "Endless. Impatient customers.", mode = "endless", difficulty = 3, goal = 6000, reward = 3, cost = 3 },
  },
  records = {
    { "clocks", "Clocks finished" },
    { "fixes", "Faults repaired" },
    { "snaps", "Springs snapped" },
    { "bestwind", "Best wind", function(v) return v > 0 and (floor(v) .. "%") or "-" end },
  },
  drawIcon = function(cx, cy)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(cx - 22, cy - 22, 44, 44)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(cx, cy, 20)
    gfx.setColor(gfx.kColorBlack)
    -- great wheel and its pinion, meshing
    Art.gear(cx - 5, cy + 4, 13, 16, 6, true)
    Art.gear(cx + 11, cy - 9, 6, 8, 22, true)
    -- crossings cut out of the wheel
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(cx - 5, cy + 4, 8)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    gfx.drawLine(cx - 11, cy - 2, cx + 1, cy + 10)
    gfx.drawLine(cx - 11, cy + 10, cx + 1, cy - 2)
    gfx.setLineWidth(1)
    gfx.fillCircleAtPoint(cx - 5, cy + 4, 3)
    -- the hand on the pinion arbor
    gfx.fillRect(cx - 4, cy - 17, 15, 2)
    gfx.fillRect(cx + 9, cy - 17, 2, 8)
    gfx.fillCircleAtPoint(cx - 5, cy - 16, 2)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(cx + 11, cy - 9, 1)
    gfx.setColor(gfx.kColorBlack)
  end,
})

------------------------------------------------------------------------
-- slot bookkeeping
--   arbor 1 = barrel (great wheel with B teeth), arbors 2..n+1
--   slot s odd  -> pinion of arbor (s+3)/2
--   slot s even -> wheel  of arbor s/2 + 1
--   mesh i (1..n): driver = barrel (i==1) or wheel slot 2i-2,
--                  driven = pinion slot 2i-1 on arbor i+1
------------------------------------------------------------------------
local function slotArbor(s) if s % 2 == 1 then return (s + 3) // 2 end return s // 2 + 1 end
local function slotIsWheel(s) return s % 2 == 0 end
local function drvSlot(i) if i == 1 then return 0 end return 2 * i - 2 end
local function pinSlot(i) return 2 * i - 1 end

local function ratioText(v)
  if abs(v - floor(v + 0.5)) < 0.01 then return "x" .. floor(v + 0.5) end
  return string.format("x%.1f", v)
end

------------------------------------------------------------------------
-- generation (pure functions of rng, also used by the solver test)
------------------------------------------------------------------------
-- picks per-stage driver/driven tooth counts. returns drv, pin, R
local function pickStages(n, rng)
  local drv, pin = {}, {}
  local R = 1
  for i = 1, n do
    local d, q
    for _ = 1, 60 do
      local r = RATIOS[rng:range(1, #RATIOS)]
      q = PINIONS[rng:range(1, #PINIONS)]
      d = r * q
      local lo, hi = 20, 44
      if i == 1 then lo, hi = 28, 48 end
      if d == floor(d) and d >= lo and d <= hi and (i > 1 or r >= 2) then break end
      d = nil
    end
    if not d then return nil end
    drv[i], pin[i] = floor(d), q
    R = R * d / q
  end
  if R < 3 or R > 80 then return nil end
  return drv, pin, R
end

-- radius helpers for layout
local function arborMaxR(drv, pin, n, k)
  if k == 1 then return drv[1] * K end
  local r = pin[k - 1] * K
  if k <= n then r = math.max(r, drv[k] * K) else r = math.max(r, ESC_R + 3) end
  return r
end

-- positions every arbor so stage k's centre distance is (drv[k]+pin[k])*K.
local function layoutTrain(drv, pin, n, rng, y0, y1)
  local ax, ay = {}, {}
  for _ = 1, 40 do
    local rB = drv[1] * K
    ax[1] = PX0 + rB + 4 + rng:range(0, 10)
    ay[1] = rng:between(math.max(y0, PY0) + rB + 4, math.min(y1, PY1) - rB - 4)
    local ok = true
    for k = 2, n + 1 do
      local D = (drv[k - 1] + pin[k - 1]) * K
      local placed = false
      local rk = arborMaxR(drv, pin, n, k)
      for _ = 1, 50 do
        local th = rad(rng:between(-80, 80))
        local x = ax[k - 1] + cos(th) * D
        local y = ay[k - 1] + sin(th) * D
        local good = x - rk >= PX0 + 2 and x + rk <= PX1 - 2 and y - rk >= math.max(y0, PY0) + 2 and y + rk <= math.min(y1, PY1) - 2
        if good and k == n + 1 and y - ESC_R - 26 < PY0 + 2 then good = false end
        if good then
          for j = 1, k - 2 do
            local rj = arborMaxR(drv, pin, n, j)
            local dx, dy = x - ax[j], y - ay[j]
            if sqrt(dx * dx + dy * dy) < rj + rk + 4 then good = false break end
          end
        end
        if good and k >= 3 then
          -- the previous arbor's pinion must not sit under this wheel
          local rp = pin[k - 2] * K
          local rw = (k <= n) and drv[k] * K or (ESC_R + 3)
          local dx, dy = x - ax[k - 1], y - ay[k - 1]
          if sqrt(dx * dx + dy * dy) < rp + rw + 2 then good = false end
        end
        if good then ax[k], ay[k] = x, y placed = true break end
      end
      if not placed then ok = false break end
    end
    if ok then
      -- centre the train on the plate (translation keeps every constraint)
      local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
      for k = 1, n + 1 do
        local r = arborMaxR(drv, pin, n, k)
        minx = math.min(minx, ax[k] - r) maxx = math.max(maxx, ax[k] + r)
        local top = (k == n + 1) and (ESC_R + 26) or r
        miny = math.min(miny, ay[k] - top) maxy = math.max(maxy, ay[k] + r)
      end
      local ylo, yhi = math.max(y0, PY0), math.min(y1, PY1)
      local dx = (PX0 + PX1) / 2 - (minx + maxx) / 2
      local dy = (ylo + yhi) / 2 - (miny + maxy) / 2
      for k = 1, n + 1 do ax[k] = ax[k] + dx ay[k] = ay[k] + dy end
      return ax, ay
    end
  end
  return nil
end

-- a same-sum pair with a different ratio (for distractors and slow/fast faults)
-- sign: -1 lower ratio, 1 higher, 0 any
local function altPair(sum, w, p, sign, rng)
  local r0 = w / p
  local best = nil
  for _ = 1, 30 do
    local q = rng:range(6, 18)
    local d = sum - q
    local r = d / q
    if d >= 16 and d ~= w and abs(r - r0) > 0.25 and (sign == 0 or (sign < 0 and r < r0) or (sign > 0 and r > r0)) then
      best = q
      break
    end
  end
  if not best then return nil end
  return sum - best, best
end

-- builds a clock table. level 0.., kind "assembly"|"stutter"|"slow"|"fast"|"stopped"
function Clock.generate(level, kind, rng, opts)
  opts = opts or {}
  local n
  if opts.n then n = opts.n
  elseif level <= 0 then n = 2
  elseif level == 1 then n = rng:chance(0.5) and 2 or 3
  elseif level <= 3 then n = 3
  else n = rng:chance(0.45) and 4 or 3 end
  local drv, pin, R, ax, ay
  local y0, y1 = opts.y0 or PY0, opts.y1 or PY1
  for attempt = 1, 400 do
    local nn = n
    if attempt > 250 then nn = math.max(1, n - 1) end
    if opts.fixed then
      drv, pin, R = opts.fixed.drv, opts.fixed.pin, opts.fixed.R
      nn = #drv
    else
      drv, pin, R = pickStages(nn, rng)
    end
    if drv then
      ax, ay = layoutTrain(drv, pin, nn, rng, y0, y1)
      if ax then n = nn break end
    end
  end
  assert(ax, "clock layout failed")
  local c = { kind = kind, n = n, B = drv[1], R = R, ax = ax, ay = ay, S = {}, solT = {},
    slotT = {}, slotB = {}, trayT = {}, trayB = {}, level = level }
  for i = 1, n do c.S[i] = drv[i] + pin[i] end
  local ns = 2 * n - 1
  for s = 1, ns do
    if slotIsWheel(s) then c.solT[s] = drv[slotArbor(s)] else c.solT[s] = pin[slotArbor(s) - 1] end
    c.slotT[s] = 0
    c.slotB[s] = -1
  end
  c.name = CLOCK_NAMES[rng:range(1, #CLOCK_NAMES)]
  local tray = {}
  local function add(t) if t >= 6 and t <= 64 and #tray < MAX_TRAY then tray[#tray + 1] = t end end

  if kind == "slow" or kind == "fast" then
    if n < 2 then kind = "stutter" c.kind = kind end
  end
  if kind == "assembly" then
    for s = 1, ns do
      if opts.prefill and opts.prefill[s] then c.slotT[s] = c.solT[s] else add(c.solT[s]) end
    end
    local dis = opts.distractors or U.clamp(2 + level, 2, 6)
    local tries = 0
    while dis > 0 and tries < 40 do
      tries = tries + 1
      local roll = rng:float()
      if roll < 0.45 and n >= 2 then
        local i = rng:range(2, n)
        local w, p = altPair(c.S[i], drv[i], pin[i], 0, rng)
        if w and dis >= 2 then add(w) add(p) dis = dis - 2 end
      elseif roll < 0.8 then
        local s = rng:range(1, ns)
        local d = rng:chance(0.5) and 1 or -1
        if rng:chance(0.4) then d = d * 2 end
        add(c.solT[s] + d) dis = dis - 1
      else
        add(rng:range(8, 48)) dis = dis - 1
      end
    end
    for i = 1, #tray do c.trayT[i] = tray[i] c.trayB[i] = -1 end
  else
    for s = 1, ns do c.slotT[s] = c.solT[s] end
    if kind == "stutter" then
      local s = rng:range(1, ns)
      c.slotB[s] = rng:range(0, c.solT[s] - 1)
      c.fault = s
      add(c.solT[s])
      local s2 = rng:range(1, ns)
      add(c.solT[s2] + (rng:chance(0.5) and 1 or -1))
      if level >= 2 then add(rng:range(8, 40)) end
    elseif kind == "slow" or kind == "fast" then
      local i = rng:range(2, n)
      local w, p = altPair(c.S[i], drv[i], pin[i], kind == "slow" and -1 or 1, rng)
      if not w then
        kind = (kind == "slow") and "fast" or "slow"
        c.kind = kind
        w, p = altPair(c.S[i], drv[i], pin[i], kind == "slow" and -1 or 1, rng)
      end
      if not w then
        -- no alternative exists for this stage: fall back to a stutter
        c.kind = "stutter"
        local s = rng:range(1, ns)
        c.slotB[s] = rng:range(0, c.solT[s] - 1)
        c.fault = s
        add(c.solT[s])
      else
        c.slotT[2 * i - 2] = w
        c.slotT[2 * i - 1] = p
        c.fault = 2 * i - 2
        add(drv[i]) add(pin[i])
        local w2, p2 = altPair(c.S[i], drv[i], pin[i], 0, rng)
        if w2 and w2 ~= w and level >= 1 then add(w2) add(p2) end
        add(c.solT[rng:range(1, ns)] + 1)
      end
    else -- stopped: one gear of the wrong size
      local s = rng:range(1, ns)
      local d = rng:chance(0.55) and rng:range(1, 3) or -rng:range(1, 3)
      if c.solT[s] + d < 6 then d = rng:range(1, 3) end
      c.slotT[s] = c.solT[s] + d
      c.fault = s
      add(c.solT[s])
      add(c.solT[s] - d)
      if level >= 1 then add(c.solT[rng:range(1, ns)] + 2) end
    end
    for i = 1, #tray do c.trayT[i] = tray[i] c.trayB[i] = -1 end
  end
  table.sort(c.trayT)
  local notes = NOTES[c.kind]
  c.note = notes[rng:range(1, #notes)]
  return c
end

-- static mesh check on a clock table: 0 open, 1 ok, 2 bind, 3 slip
function Clock.meshStatus(c, i)
  local ds = drvSlot(i)
  local d = (ds == 0) and c.B or c.slotT[ds]
  local q = c.slotT[pinSlot(i)]
  if d == 0 or q == 0 then return 0 end
  local diff = d + q - c.S[i]
  if diff == 0 then return 1 elseif diff > 0 then return 2 end
  return 3
end

------------------------------------------------------------------------
-- lifecycle
------------------------------------------------------------------------
function Clock:enter(params)
  self.t = 0
  self.score = 0
  self.index = 0
  self.done = 0
  self.complaints = 0
  self.snapsRun = 0
  self.fixedRun = 0
  self.byEye = self.params.challengeId == "byeye"
  if self.mode == "standard" then
    self.timeLeft = ({ 480, 420, 360 })[self.difficulty] or 420
  else
    self.timeLeft = 0
  end
  self.ang = { 0, 0, 0, 0, 0, 0 }
  self.offW = { 0, 0, 0, 0, 0, 0 }
  self.offP = { 0, 0, 0, 0, 0, 0 }
  self.psi = { 0, 0, 0, 0, 0 }
  self.mstat = { 0, 0, 0, 0, 0 }
  self.slack = { 0, 0, 0, 0, 0 }
  self.armed = { true, true, true, true, true }
  self.spark = { 0, 0, 0, 0, 0 }
  self.bindFlash = { 0, 0, 0, 0, 0 }
  self.tracker = Crank.Tracker.new()
  self.strain = Audio.Hum.new(Audio.SAW)
  self.hdrSec, self.hdrIdx, self.hdr = -1, -1, ""
  self.msg, self.msgT, self.msg2 = nil, 0, nil
  self:startClock()
  if self.mode == "tutorial" then self:setupCoach() end
end

function Clock:exit() self.strain:stop() end

function Clock:levelFor(i)
  return i + (self.difficulty - 1) * 2
end

function Clock:kindFor(i, level)
  if self.mode == "standard" then
    return (i % 2 == 0) and "assembly" or ((level >= 3) and self.rng:pick({ "stutter", "slow", "fast", "stopped" }) or self.rng:pick({ "stutter", "stopped", "slow" }))
  end
  if i == 0 then return "assembly" end
  return self.rng:chance(0.5) and "assembly" or self.rng:pick({ "stutter", "slow", "fast", "stopped" })
end

function Clock:startClock()
  local rng = self.rng
  if self.mode == "tutorial" then
    self.c = Clock.generate(0, "assembly", rng, {
      fixed = { drv = { 36, 32 }, pin = { 12, 8 }, R = 12 }, y0 = 30, y1 = 158,
      prefill = { [1] = true }, distractors = 0 })
    local c = self.c
    c.trayT = { 8, 10, 16, 24, 32 }
    c.trayB = { -1, -1, -1, -1, -1 }
    c.name = "THE KEEPER'S ALARM"
    c.note = "Build it. Test it. Wind it."
  else
    local level = self:levelFor(self.index)
    self.c = Clock.generate(level, self:kindFor(self.index, level), rng)
  end
  local c = self.c
  self.ns = 2 * c.n - 1
  self.sel = 1
  -- first empty slot
  if self.mode ~= "tutorial" then
    for s = 1, self.ns do if c.slotT[s] == 0 then self.sel = s break end end
  end
  self.tsel = 1
  self.phase = "bench"
  self.clockT = 0
  self.fails = 0
  self.cardT = 0
  self.limit = (self.mode == "tutorial") and 2.6 or rng:between(2.8, 4.4)
  self.soft = rng:between(0.75, 0.86)  -- where the torque starts to climb
  self.wind = 0
  self.torque = 0
  self.needle = 0
  self.snapT = 0
  self.runT = 0
  self.gain = 0
  self.pawl = 0
  self.escPhase = 0
  self.anchor = 0
  self.windClick = 0
  self.barrelTick = 0
  self.escAcc = 0
  self.jamPush = 0
  self.patience = (self.mode == "endless") and (70 + 30 * c.n - (self.difficulty - 1) * 12 - math.min(40, self.index * 3)) or 0
  if self.params.challengeId == "eve" then self.patience = self.patience * 0.8 end
  for k = 1, 6 do self.ang[k] = 0 end
  for i = 1, 5 do self.slack[i] = 0 self.armed[i] = true self.spark[i] = 0 self.bindFlash[i] = 0 end
  self:computeGeometry()
  self:resetTest()
  self.goalStr = ratioText(c.R)
end

function Clock:computeGeometry()
  local c = self.c
  for i = 1, c.n do
    local dx, dy = c.ax[i + 1] - c.ax[i], c.ay[i + 1] - c.ay[i]
    self.psi[i] = deg(atan(dx, -dy))
  end
  self:refreshOffsets()
  self:refreshMesh()
end

-- tooth phase offsets so meshing teeth interleave. Each gear is nudged by
-- less than half a tooth so nothing visibly jumps when the train changes.
local function snapFrac(p) return p - floor(p + 0.5) end
function Clock:refreshOffsets()
  local c = self.c
  for i = 1, c.n do
    local ds = drvSlot(i)
    local d = (ds == 0) and c.B or c.slotT[ds]
    if d > 0 then
      local st = 360 / d
      local ph = (self.ang[i] + self.offW[i] - self.psi[i]) / st
      self.offW[i] = self.offW[i] - snapFrac(ph) * st
    end
    local q = c.slotT[pinSlot(i)]
    if q > 0 then
      local st = 360 / q
      local ph = (self.ang[i + 1] + self.offP[i + 1] - self.psi[i] - 180 - st * 0.5) / st
      self.offP[i + 1] = self.offP[i + 1] - snapFrac(ph) * st
    end
  end
end

function Clock:refreshMesh()
  for i = 1, self.c.n do self.mstat[i] = Clock.meshStatus(self.c, i) end
end

function Clock:resetTest()
  self.testB = 0
  self.testO = 0
  self.testStutter = 0
end

function Clock:setupCoach()
  local s = self
  self.coach = UI.Coach.new({
    { text = "Crank to turn the mainspring barrel. The pinion it drives turns 3x faster.",
      check = function() return s.testTravel and s.testTravel > 170 end },
    { text = "RIGHT picks the next slot: the empty WHEEL on arbor II.",
      check = function() return s.sel == 2 end },
    { text = "UP/DOWN browses the tray, A fits. Try a big wheel.",
      check = function() return s.c.slotT[2] > 0 end },
    { text = "Now the PINION on the hand arbor. Its teeth must touch: too big binds, too small slips.",
      check = function() return s.mstat[2] == 1 end, hold = 0.2 },
    { text = "The ticket wants x12. Crank one full barrel turn to test it. Wrong? Swap gears.",
      check = function() return s.phase == "wind" end },
    { text = "Wind CLOCKWISE. Clicks rise as it tightens. Stop in the FULL band.",
      check = function() return s.phase == "wind" and s.wind / s.limit >= 0.9 and s.tracker.idle > 0.3 end, hold = 0.3 },
    { text = "Press A to set it going.",
      check = function() return s.phase == "running" or s.phase == "card" end },
  }, { x = 4, w = 392, y = 172, h = 46, anchor = "bottom" })
end

------------------------------------------------------------------------
-- the train
------------------------------------------------------------------------
-- does the broken tooth of gear in slot s (world angle) sit in mesh i's contact?
function Clock:brokenInContact(i, s, isDriver)
  local c = self.c
  if s == 0 or c.slotB[s] < 0 then return false end
  local t = c.slotT[s]
  local step = 360 / t
  local arbor = slotArbor(s)
  local off = isDriver and self.offW[i] or self.offP[i + 1]
  local w = self.ang[arbor] + off + c.slotB[s] * step
  local contact = isDriver and self.psi[i] or (self.psi[i] + 180)
  return abs(U.angleDiff(w, contact)) < step * 0.5
end

-- turn the barrel by dB degrees through the train. returns jammed mesh or 0
function Clock:drive(dB, quiet)
  local c = self.c
  local n = c.n
  -- find how far the power reaches and whether it binds
  local reach = 1
  for i = 1, n do
    local st = self.mstat[i]
    if st == 2 then
      self.bindFlash[i] = 1
      return i
    elseif st ~= 1 then
      break
    end
    reach = i + 1
  end
  if dB == 0 then return 0 end
  -- substeps small enough that a broken tooth is never skipped over: the
  -- damaged gear may not advance more than ~1/3 of its pitch per substep
  local maxStep = 360
  local cum = 1
  for i = 1, reach - 1 do
    local ds, ps = drvSlot(i), pinSlot(i)
    local dT = (ds == 0) and c.B or c.slotT[ds]
    if ds > 0 and c.slotB[ds] >= 0 then maxStep = math.min(maxStep, 120 / dT / cum) end
    cum = cum * dT / c.slotT[ps]
    if c.slotB[ps] >= 0 then maxStep = math.min(maxStep, 120 / c.slotT[ps] / cum) end
  end
  local steps = math.min(64, math.max(1, math.ceil(abs(dB) / maxStep)))
  local step = dB / steps
  local outArbor = n + 1
  for _ = 1, steps do
    local d = step
    self.ang[1] = self.ang[1] + d
    for i = 1, reach - 1 do
      if d == 0 then break end
      local ds, ps = drvSlot(i), pinSlot(i)
      local dT = (ds == 0) and c.B or c.slotT[ds]
      local qT = c.slotT[ps]
      -- broken tooth: lose one driver pitch of motion
      local inContact = self:brokenInContact(i, ds, true) or self:brokenInContact(i, ps, false)
      if inContact then
        if self.armed[i] then
          self.armed[i] = false
          self.slack[i] = 360 / dT
          self.spark[i] = 1
          self.testStutter = self.testStutter + 1
          if not quiet then
            Audio.sfx.clack(0.5)
            self:shake(1.5)
          end
        end
      elseif self.slack[i] <= 0 then
        self.armed[i] = true
      end
      if self.slack[i] > 0 then
        local a = abs(d)
        if a <= self.slack[i] then
          self.slack[i] = self.slack[i] - a
          d = 0
        else
          d = d * (a - self.slack[i]) / a
          self.slack[i] = 0
        end
      end
      local dd = -d * dT / qT
      self.ang[i + 1] = self.ang[i + 1] + dd
      d = dd
    end
    if reach == outArbor then self.testO = self.testO + abs(d) end
  end
  if reach == outArbor then self.lastOutMove = true else self.lastOutMove = false end
  self.testB = self.testB + abs(dB)
  -- keep angles bounded
  for k = 1, n + 1 do
    local a = self.ang[k]
    if a > 36000 or a < -36000 then
      local w = a % 360
      self.ang[k] = w
    end
  end
  return 0
end

function Clock:complete()
  local c = self.c
  for s = 1, self.ns do if c.slotT[s] == 0 then return false end end
  return true
end

function Clock:connected()
  for i = 1, self.c.n do if self.mstat[i] ~= 1 then return false end end
  return true
end

function Clock:say(a, b, t)
  self.msg, self.msg2, self.msgT = a, b, t or 2.5
end

function Clock:evaluateTest()
  local c = self.c
  if not self:complete() then
    self:say("NOT FINISHED", "Empty slots in the train.")
    self:resetTest()
    return
  end
  if not self:connected() then
    self:say("NO DRIVE", "A mesh slips: teeth don't touch.")
    self:resetTest()
    return
  end
  local measured = self.testO / math.max(1, self.testB)
  local ok = abs(measured - c.R) / c.R < 0.004 and self.testStutter == 0
  if ok then
    self.phase = "closing"
    self.closeT = 0
    Audio.sfx.bell(1320, 0.4)
    Audio.sfx.gear()
    if self.fails == 0 and c.n >= 3 then self:award("true") end
    if c.kind ~= "assembly" then
      self.fixedRun = self.fixedRun + 1
      self:statAdd("fixes", 1)
      if c.kind == "stutter" then self:award("doctor") end
    end
    self:say("RATE TRUE", "Close the case and wind.", 2)
  else
    self.fails = self.fails + 1
    self.measured = measured
    Audio.sfx.denied()
    self:shake(2)
    if self.testStutter > 0 then
      self:say("IT STUTTERS", U.cached("clk_stut", "Hitched %d times. Broken tooth?", self.testStutter), 3.5)
    else
      self:say(U.cached("clk_meas2", "RUNS " .. "%s", ratioText(measured)), "The ticket wants " .. self.goalStr .. ".", 3.5)
    end
  end
  self:resetTest()
end

------------------------------------------------------------------------
-- input
------------------------------------------------------------------------
function Clock:cranked(change)
  self.tracker:feed(change)
  local ph = self.phase
  if ph == "bench" then
    local dB = change * TEST_GEAR
    local jam = self:drive(dB)
    self.testTravel = (self.testTravel or 0) + abs(dB)
    if jam > 0 then
      -- a hard stop: the crank pushes against a bound mesh
      self.jamPush = self.jamPush + abs(change)
      if self.jamPush > 25 or self.jamWas ~= true then
        if self.jamWas ~= true then
          Audio.sfx.thunk(0.7)
          self:shake(3)
          self:say("IT BINDS", "Too many teeth in that gap.", 2)
        else
          Audio.sfx.clank(0.3)
          self:shake(1.5)
        end
        self.jamPush = 0
      end
      self.jamWas = true
      self:resetTest()
    else
      self.jamWas = false
      -- the barrel's great wheel ticks past the click
      local before = self.barrelTick
      self.barrelTick = self.barrelTick + abs(dB)
      if floor(before / 30) ~= floor(self.barrelTick / 30) then Audio.sfx.tick(700, 0.06) end
      if self.lastOutMove then self:escapementAdvance(self.testLastO or 0) end
      if self.testB >= 360 then self:evaluateTest() end
    end
    self.testLastO = self.testO
  elseif ph == "wind" then
    if change > 0 then
      local x = self.wind / self.limit
      local resist = 1 - 0.65 * U.clamp(self.torque, 0, 1)
      if x > 1 then resist = 0.25 end
      local dw = change / 360 * resist
      local before = self.wind
      self.wind = self.wind + dw
      -- click teeth: 12 per turn of the arbor
      local clicks = floor(self.wind * 12) - floor(before * 12)
      if clicks > 0 then
        local tq = self:torqueAt(self.wind / self.limit)
        Audio.play(Audio.SQUARE, 420 + tq * 1500, 0.12 + 0.2 * tq, 0.012, 0.001, 0.02, 0, 0.01)
        Audio.sfx.click(0.12 + 0.25 * tq)
        if tq > 0.9 then Audio.sfx.creak(0.18) self:shake(0.8) end
        self.pawl = 1
        self.windClick = self.windClick + clicks
      end
      if self.wind / self.limit > 1 + self:slackLimit() then self:snapSpring() end
    elseif change < 0 then
      -- the click holds: the key ratchets back, the spring does not unwind
      local before = self.backRatchet or 0
      self.backRatchet = before + change
      if floor(before / 30) ~= floor(self.backRatchet / 30) then Audio.sfx.tick(1200, 0.05) end
    end
  end
end

function Clock:slackLimit()
  return ({ 0.05, 0.035, 0.022 })[self.difficulty] or 0.035
end

function Clock:torqueAt(x)
  local s = self.soft
  local climb = U.smoothstep((x - s) / (1 - s))
  return U.clamp(0.12 + 0.5 * x + 0.38 * climb, 0, 1.2)
end

function Clock:snapSpring()
  self.phase = "snapped"
  self.snapT = 0
  self.snapsRun = self.snapsRun + 1
  self:statAdd("snaps", 1)
  Audio.sfx.snap(1)
  Audio.sfx.thud(0.9)
  Audio.play(Audio.SAW, 90, 0.5, 0.4, 0.001, 0.4, 0, 0.2)
  self:shake(7)
  self:flash(2)
  if self.mode ~= "tutorial" then
    self.score = math.max(0, self.score - 250)
  end
  if self.mode == "endless" then self.complaints = self.complaints + 1 end
  self:say("SPRING SNAPPED", self.mode == "tutorial" and "Fitting a new one. Stop earlier." or "-250. Fitting a new one...", 2.5)
end

function Clock:buttonDown(b)
  local c = self.c
  if self.phase == "card" then
    if b == Input.A and self.cardT > 0.8 then self:nextClock() end
    return
  end
  if self.phase == "wind" then
    if b == Input.A then
      if self.wind / self.limit >= 0.25 then
        self:startRunning()
      else
        Audio.sfx.denied()
        self:say("NOT ENOUGH", "Wind it further first.", 1.5)
      end
    end
    return
  end
  if self.phase ~= "bench" then return end
  if b == Input.LEFT then
    self.sel = (self.sel - 2) % self.ns + 1
    Audio.sfx.menuMove()
  elseif b == Input.RIGHT then
    self.sel = self.sel % self.ns + 1
    Audio.sfx.menuMove()
  elseif b == Input.UP then
    local nt = #c.trayT
    if nt > 0 then self.tsel = (self.tsel - 2) % nt + 1 Audio.sfx.tick(1500, 0.1) end
  elseif b == Input.DOWN then
    local nt = #c.trayT
    if nt > 0 then self.tsel = self.tsel % nt + 1 Audio.sfx.tick(1500, 0.1) end
  elseif b == Input.A then
    self:fit()
  elseif b == Input.B then
    self:remove()
  end
end

function Clock:sortTray()
  local c = self.c
  -- insertion sort of parallel arrays (small)
  for i = 2, #c.trayT do
    local t, br = c.trayT[i], c.trayB[i]
    local j = i - 1
    while j >= 1 and c.trayT[j] > t do
      c.trayT[j + 1], c.trayB[j + 1] = c.trayT[j], c.trayB[j]
      j = j - 1
    end
    c.trayT[j + 1], c.trayB[j + 1] = t, br
  end
end

function Clock:changed()
  self:refreshOffsets()
  self:refreshMesh()
  self:resetTest()
  for i = 1, 5 do self.slack[i] = 0 self.armed[i] = true end
  self.jamWas = false
end

function Clock:fit()
  local c = self.c
  local nt = #c.trayT
  if nt == 0 then Audio.sfx.denied() return end
  self.tsel = U.clamp(self.tsel, 1, nt)
  local t, br = c.trayT[self.tsel], c.trayB[self.tsel]
  table.remove(c.trayT, self.tsel)
  table.remove(c.trayB, self.tsel)
  local s = self.sel
  if c.slotT[s] > 0 then
    if c.slotB[s] >= 0 then
      Audio.sfx.whoosh(0.2)
      self:say("INTO THE SCRAP TIN", "That one had a broken tooth.", 1.8)
    else
      c.trayT[#c.trayT + 1] = c.slotT[s]
      c.trayB[#c.trayB + 1] = -1
    end
  end
  c.slotT[s], c.slotB[s] = t, br
  self:sortTray()
  self.tsel = U.clamp(self.tsel, 1, math.max(1, #c.trayT))
  Audio.sfx.clack(0.4)
  Audio.sfx.tick(600, 0.2)
  self:changed()
  -- report the fit
  local i = slotIsWheel(s) and slotArbor(s) or (slotArbor(s) - 1)
  local st = self.mstat[i]
  if st == 2 then Audio.sfx.thunk(0.3) elseif st == 1 then Audio.sfx.tick(2200, 0.15) end
end

function Clock:remove()
  local c = self.c
  local s = self.sel
  if c.slotT[s] == 0 then Audio.sfx.denied() return end
  if c.slotB[s] >= 0 then
    Audio.sfx.whoosh(0.2)
    self:say("INTO THE SCRAP TIN", "That one had a broken tooth.", 1.8)
  elseif #c.trayT < MAX_TRAY then
    c.trayT[#c.trayT + 1] = c.slotT[s]
    c.trayB[#c.trayB + 1] = -1
    self:sortTray()
  end
  c.slotT[s], c.slotB[s] = 0, -1
  Audio.sfx.clack(0.25)
  self:changed()
end

------------------------------------------------------------------------
-- phases
------------------------------------------------------------------------
function Clock:startRunning()
  self.phase = "running"
  self.runT = 0
  local x = self.wind / self.limit
  self.windPct = floor(U.clamp(x, 0, 1.2) * 100 + 0.5)
  self:statMax("bestwind", math.min(100, self.windPct))
  if x >= 0.97 and x <= 1 + self:slackLimit() then self:award("full") end
  Audio.sfx.thunk(0.4)
end

function Clock:scoreClock()
  local c = self.c
  local x = self.wind / self.limit
  local base = 500 + 150 * c.n
  local timeBonus = math.max(0, 400 - floor(self.clockT * 2))
  local windBonus = floor(300 * U.clamp((x - 0.5) / 0.4, 0, 1))
  local pen = self.fails * 100
  local g = math.max(100, base + timeBonus + windBonus - pen)
  self.gainBase, self.gainTime, self.gainWind, self.gainPen = base, timeBonus, windBonus, pen
  return g
end

function Clock:finishClock()
  self.phase = "card"
  self.cardT = 0
  self.done = self.done + 1
  self:statAdd("clocks", 1)
  self:award("first")
  if self.mode ~= "tutorial" then
    self.gain = self:scoreClock()
    self.score = self.score + self.gain
  end
  Audio.sfx.success()
end

function Clock:nextClock()
  if self.mode == "tutorial" then return end
  self.index = self.index + 1
  if self.mode == "standard" and self.index >= STANDARD_CLOCKS then
    local bonus = floor(self.timeLeft) * 3
    self.score = self.score + bonus
    if self.snapsRun == 0 then self:award("day") end
    self:finish({ success = true, score = self.score, title = "SHOP CLOSED",
      lines = { "Clocks finished: " .. self.done .. "/" .. STANDARD_CLOCKS,
        "Time left bonus: " .. bonus, "Springs snapped: " .. self.snapsRun } })
    return
  end
  self:startClock()
end

function Clock:customerLeaves()
  self.complaints = self.complaints + 1
  Audio.sfx.fail()
  self:shake(3)
  if self.complaints >= 3 then
    self:finish({ success = self.done > 0, score = self.score, title = "SHOP SHUT",
      lines = { "Clocks finished: " .. self.done, "Three complaints.", "Faults repaired: " .. self.fixedRun } })
    return
  end
  self.index = self.index + 1
  self:startClock()
  self:say("CUSTOMER LEFT", "They took the clock elsewhere.", 2.5)
end

function Clock:escapementAdvance(prevO)
  -- the escapement ticks every half tooth of the escape wheel on the hand arbor
  local per = 360 / ESC_TEETH / 2
  local before = floor(prevO / per)
  local after = floor(self.testO / per)
  if after ~= before then
    self.escPhase = self.escPhase + 1
    if self.escPhase % 2 == 0 then Audio.play(Audio.SQUARE, 2400, 0.1, 0.008, 0.001, 0.012, 0, 0.01)
    else Audio.play(Audio.SQUARE, 1700, 0.1, 0.008, 0.001, 0.012, 0, 0.01) end
  end
end

function Clock:update(dt)
  self.t = self.t + dt
  self.tracker:update(dt)
  if self.msgT > 0 then self.msgT = self.msgT - dt end
  for i = 1, 5 do
    self.spark[i] = math.max(0, self.spark[i] - dt * 2.5)
    self.bindFlash[i] = math.max(0, self.bindFlash[i] - dt * 2)
  end
  self.pawl = math.max(0, self.pawl - dt * 6)
  local target = (self.escPhase % 2 == 0) and 1 or -1
  self.anchor = U.damp(self.anchor, target, 25, dt)
  local ph = self.phase
  local timed = self.mode ~= "tutorial" and not self.finished

  if ph == "bench" or ph == "wind" or ph == "closing" or ph == "snapped" then
    self.clockT = self.clockT + dt
    if timed and self.mode == "standard" then
      self.timeLeft = self.timeLeft - dt
      if self.timeLeft <= 0 then
        self.timeLeft = 0
        Audio.sfx.fail()
        self:finish({ success = self.done > 0, score = self.score, title = "SHOP CLOSED",
          lines = { "Clocks finished: " .. self.done .. "/" .. STANDARD_CLOCKS, "The day ran out.", "Springs snapped: " .. self.snapsRun } })
        return
      end
    elseif timed and self.mode == "endless" then
      self.patience = self.patience - dt
      if self.patience <= 0 then self:customerLeaves() return end
    end
  end

  -- strain hum: pushing a bound train or a spring near its limit
  local strain = 0
  if ph == "bench" and self.jamWas and self.tracker.idle < 0.15 then strain = 0.25 end
  if ph == "wind" then
    local x = self.wind / self.limit
    if x > 0.9 and self.tracker.idle < 0.15 then strain = U.clamp((x - 0.9) * 3, 0, 0.35) end
  end
  if strain > 0 then self.strain:set(55 + strain * 60, strain) else self.strain:set(0, 0) end

  if ph == "closing" then
    self.closeT = self.closeT + dt
    if self.closeT > 1.2 then
      self.phase = "wind"
      self.backRatchet = 0
      Audio.sfx.clank(0.4)
    end
  elseif ph == "wind" then
    local x = self.wind / self.limit
    self.torque = self:torqueAt(x)
    local jitter = (x > 0.95) and (sin(self.t * 70) * 0.02) or 0
    self.needle = U.damp(self.needle, self.torque + jitter, 10, dt)
  elseif ph == "snapped" then
    self.snapT = self.snapT + dt
    self.needle = U.damp(self.needle, 0, 6, dt)
    if self.snapT > 2.6 then
      self.phase = "wind"
      self.wind = 0
      self.torque = 0
      self.limit = self.rng:between(2.8, 4.4)
      if self.mode == "tutorial" then self.limit = 2.6 end
      self.soft = self.rng:between(0.75, 0.86)
      Audio.sfx.clank(0.4)
      if self.mode == "endless" and self.complaints >= 3 then
        self:finish({ success = self.done > 0, score = self.score, title = "SHOP SHUT",
          lines = { "Clocks finished: " .. self.done, "Three complaints.", "Faults repaired: " .. self.fixedRun } })
      end
    end
  elseif ph == "running" then
    self.runT = self.runT + dt
    -- the spring drives the train: the hand arbor at 24 deg/s -> escapement 2 ticks/s
    local c = self.c
    local prevO = self.testO
    local dB = 24 / c.R * dt
    if (c.n % 2) == 1 then dB = -dB end
    self:drive(dB, true)
    self:escapementAdvance(prevO)
    self.needle = U.damp(self.needle, self.torque * 0.95, 2, dt)
    if self.runT > 3.2 then self:finishClock() end
  elseif ph == "card" then
    self.cardT = self.cardT + dt
    if self.mode ~= "tutorial" and self.cardT > 6 then self:nextClock() end
    -- keep it ticking in the background
    local c = self.c
    local prevO = self.testO
    local dB = 24 / c.R * dt
    if (c.n % 2) == 1 then dB = -dB end
    self:drive(dB, true)
    self:escapementAdvance(prevO)
  end
end

------------------------------------------------------------------------
-- drawing
------------------------------------------------------------------------
local function drawBench()
  return Art.cached("clock_bench", 272, 204, function(w, h)
    -- workbench boards
    gfx.setPattern(Art.pat.wood)
    gfx.fillRect(0, 0, w, h)
    gfx.setColor(gfx.kColorBlack)
    for y = 0, h, 34 do gfx.drawLine(0, y, w, y) end
    -- the brass plate
    local x0, y0, x1, y1 = PX0 - 4, PY0 - 18 - 4, PX1 + 4, PY1 - 18 + 4
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRoundRect(x0 + 3, y0 + 3, x1 - x0, y1 - y0, 10)
    gfx.setPattern(PAT_PLATE)
    gfx.fillRoundRect(x0, y0, x1 - x0, y1 - y0, 10)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    gfx.drawRoundRect(x0, y0, x1 - x0, y1 - y0, 10)
    gfx.setLineWidth(1)
    gfx.drawRoundRect(x0 + 4, y0 + 4, x1 - x0 - 8, y1 - y0 - 8, 7)
    -- plate screws
    local sx = { x0 + 10, x1 - 10, x0 + 10, x1 - 10 }
    local sy = { y0 + 10, y0 + 10, y1 - 10, y1 - 10 }
    for i = 1, 4 do
      gfx.setColor(gfx.kColorWhite)
      gfx.fillCircleAtPoint(sx[i], sy[i], 4)
      gfx.setColor(gfx.kColorBlack)
      gfx.drawCircleAtPoint(sx[i], sy[i], 4)
      gfx.drawLine(sx[i] - 3, sy[i] + 2, sx[i] + 3, sy[i] - 2)
    end
  end)
end

-- Gears are pre-rendered once per tooth count and tooth phase: a gear turned
-- by one full tooth pitch looks identical, so a handful of phase images give
-- smooth rotation without building a many-vertex polygon every frame.
-- styles: 1 brass wheel, 2 black pinion, 3 escape wheel, 4 ratchet,
--         5 tray icon, 6 ghost outline
local gearImgs = {}
local function phasesFor(teeth) return U.clamp(math.ceil(360 / teeth / 4), 2, 12) end
local function gearImage(teeth, style, phase)
  local key = (teeth * 8 + style) * 16 + phase
  local img = gearImgs[key]
  if img then return img end
  local r
  if style == 3 then r = ESC_R elseif style == 4 then r = 6 elseif style == 5 then r = math.min(9, 4 + teeth * 0.1) else r = teeth * K end
  local vis = (style == 5) and math.min(teeth, 14) or teeth
  local size = math.ceil(r * 2) + 5
  local c = size / 2
  local ang = phase * (360 / vis) / phasesFor(vis)
  img = gfx.image.new(size, size, gfx.kColorClear)
  gfx.pushContext(img)
  if style == 1 then
    -- solid teeth, then the brass body painted over their roots so only
    -- short stubs remain (constant module, whatever the wheel's size)
    gfx.setColor(gfx.kColorBlack)
    Art.gear(c, c, r, vis, ang, true, false)
    gfx.setPattern(PAT_BRASS)
    gfx.fillCircleAtPoint(c, c, r - 4)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawCircleAtPoint(c, c, r - 4)
    if r > 14 then gfx.drawCircleAtPoint(c, c, r - 7) end
  elseif style == 2 or style == 4 or style == 5 then
    gfx.setColor(gfx.kColorBlack)
    Art.gear(c, c, r, vis, ang, true, false)
  elseif style == 3 then
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(c, c, r)
    gfx.setColor(gfx.kColorBlack)
    Art.gear(c, c, r, vis, ang, false)
  else
    gfx.setColor(gfx.kColorBlack)
    Art.gear(c, c, r, vis, ang, false)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawCircleAtPoint(c, c, r + 1)
  end
  gfx.popContext()
  gearImgs[key] = img
  return img
end

local function drawGearImg(x, y, teeth, ang, style)
  local vis = (style == 5) and math.min(teeth, 14) or teeth
  local ph = phasesFor(vis)
  local f = (ang / (360 / vis)) % 1
  local p = floor(f * ph + 0.5) % ph
  local img = gearImage(teeth, style, p)
  local w = img:getSize()
  img:draw(floor(x - w / 2 + 0.5), floor(y - w / 2 + 0.5))
end
Clock.gearImage = gearImage

-- brass wheel with crossings (spokes turn with the true arbor angle)
local function drawWheel(x, y, teeth, ang)
  local r = teeth * K
  drawGearImg(x, y, teeth, ang, 1)
  gfx.setColor(gfx.kColorBlack)
  if r > 14 then
    local ri = r - 7
    gfx.setLineWidth(3)
    for i = 0, 3 do
      local a = rad(ang + i * 90 + 45)
      local sa, ca = sin(a), cos(a)
      gfx.drawLine(x + sa * 4, y - ca * 4, x + sa * ri, y - ca * ri)
    end
    gfx.setLineWidth(1)
  end
  gfx.fillCircleAtPoint(x, y, 3)
end

local function drawPinion(x, y, teeth, ang)
  drawGearImg(x, y, teeth, ang, 2)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(x, y, 1.5)
  gfx.setColor(gfx.kColorBlack)
end

-- white notch where a tooth has broken off
local function drawBroken(x, y, teeth, ang, idx)
  local r = teeth * K
  local a = rad(ang + idx * 360 / teeth)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(x + sin(a) * (r - 1), y - cos(a) * (r - 1), math.max(2, r * 0.14))
  gfx.setColor(gfx.kColorBlack)
end

function Clock:drawBarrel()
  local c = self.c
  local x, y = c.ax[1], c.ay[1]
  local B = c.B
  local r = B * K
  local ang = self.ang[1] + self.offW[1]
  drawWheel(x, y, B, ang)
  -- the drum
  local dr = r * 0.62
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(x, y, dr)
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(2)
  gfx.drawCircleAtPoint(x, y, dr)
  gfx.setLineWidth(1)
  -- mainspring spiral: tighter coils as it is wound
  local wx = 0
  if self.phase == "wind" or self.phase == "running" or self.phase == "card" or self.phase == "closing" then
    wx = U.clamp(self.wind / self.limit, 0, 1.1)
  end
  local coils = 3 + wx * 3
  local r0, r1 = 3, dr - 2 - wx * (dr * 0.35)
  local segs = floor(coils * 10)
  local spin = self.ang[1] + (self.wind * 360)
  local px, py = x + sin(rad(spin)) * r0, y - cos(rad(spin)) * r0
  if self.phase ~= "snapped" then
    for s = 1, segs do
      local f = s / segs
      local a = rad(spin + f * coils * 360)
      local rr = r0 + (r1 - r0) * f
      local nx, ny = x + sin(a) * rr, y - cos(a) * rr
      gfx.drawLine(px, py, nx, ny)
      px, py = nx, ny
    end
  else
    -- a snapped spring: shards flung outward
    local k = self.snapT
    for s = 0, 7 do
      local a = rad(s * 45 + k * 40)
      local rr = 4 + math.min(dr - 4, k * 40)
      gfx.drawLine(x + sin(a) * 3, y - cos(a) * 3, x + sin(a + 0.5) * rr, y - cos(a + 0.5) * rr)
    end
  end
  -- winding arbor with its ratchet and click
  local ra = self.wind * 360
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(x, y, 6)
  gfx.setColor(gfx.kColorBlack)
  drawGearImg(x, y, 10, ra, 4)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x - 1, y - 1, 3, 3)
  gfx.setColor(gfx.kColorBlack)
  local pa = 1 - self.pawl * 0.6
  gfx.setLineWidth(2)
  gfx.drawLine(x + 13, y - 11, x + 5 + pa * 2, y - 5 - pa * 2)
  gfx.setLineWidth(1)
  gfx.fillCircleAtPoint(x + 13, y - 11, 2)
end

function Clock:drawTrain()
  local c = self.c
  local n = c.n
  -- pivot holes under every arbor
  for k = 1, n + 1 do
    local x, y = c.ax[k], c.ay[k]
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(x, y, 6)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawCircleAtPoint(x, y, 6)
    gfx.fillCircleAtPoint(x, y, 3)
  end
  -- wheels, last arbor first so each mesh with a pinion stays visible
  local out = n + 1
  local ea = self.ang[out] * (1) + self.offP[out]
  local ex, ey = c.ax[out], c.ay[out]
  drawGearImg(ex, ey, ESC_TEETH, ea, 3)
  gfx.setColor(gfx.kColorBlack)
  for k = n, 2, -1 do
    local s = 2 * k - 2
    local t = c.slotT[s]
    if t > 0 then
      local a = self.ang[k] + self.offW[k]
      drawWheel(c.ax[k], c.ay[k], t, a)
      if c.slotB[s] >= 0 then drawBroken(c.ax[k], c.ay[k], t, a, c.slotB[s]) end
    end
  end
  self:drawBarrel()
  for k = 2, n + 1 do
    local s = 2 * k - 3
    local t = c.slotT[s]
    if t > 0 then
      local a = self.ang[k] + self.offP[k]
      drawPinion(c.ax[k], c.ay[k], t, a)
      if c.slotB[s] >= 0 then drawBroken(c.ax[k], c.ay[k], t, a, c.slotB[s]) end
    end
  end
  -- escapement: anchor rocking over the escape wheel
  local px, py = ex, ey - ESC_R - 9
  local rock = self.anchor * 9
  local a1, a2 = rad(180 + 38 + rock), rad(180 - 38 + rock)
  gfx.setLineWidth(3)
  gfx.drawLine(px, py, px + sin(a1) * 12, py - cos(a1) * 12)
  gfx.drawLine(px, py, px + sin(a2) * 12, py - cos(a2) * 12)
  gfx.setLineWidth(2)
  local ca = rad(rock)
  gfx.drawLine(px, py, px + sin(ca) * 16, py - cos(ca) * 16)
  gfx.setLineWidth(1)
  gfx.fillCircleAtPoint(px, py, 3)
  -- the hand
  local ha = rad(self.ang[out] + 0)
  local hx, hy = ex + sin(ha) * 24, ey - cos(ha) * 24
  gfx.setLineWidth(2)
  gfx.drawLine(ex - sin(ha) * 6, ey + cos(ha) * 6, hx, hy)
  gfx.setLineWidth(1)
  gfx.fillCircleAtPoint(hx, hy, 2)
  gfx.fillCircleAtPoint(ex, ey, 3)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawPixel(ex, ey)
  gfx.setColor(gfx.kColorBlack)
end

-- contact point marker for mesh i
function Clock:drawMeshMarks()
  local c = self.c
  for i = 1, c.n do
    local st = self.mstat[i]
    local ds = drvSlot(i)
    local d = (ds == 0) and c.B or c.slotT[ds]
    local a = rad(self.psi[i])
    local cx, cy = c.ax[i] + sin(a) * d * K, c.ay[i] - cos(a) * d * K
    if self.spark[i] > 0 then
      local r = 3 + (1 - self.spark[i]) * 10
      gfx.setColor(gfx.kColorBlack)
      for s = 0, 5 do
        local sa = rad(s * 60 + self.t * 200)
        gfx.drawLine(cx + sin(sa) * r * 0.4, cy - cos(sa) * r * 0.4, cx + sin(sa) * r, cy - cos(sa) * r)
      end
    end
    local hide = self.byEye and self.bindFlash[i] <= 0
    if st == 2 and not hide then
      local blink = self.bindFlash[i] > 0 and (floor(self.t * 12) % 2 == 0)
      gfx.setColor(gfx.kColorWhite)
      gfx.fillCircleAtPoint(cx, cy, 6)
      gfx.setColor(gfx.kColorBlack)
      if blink then gfx.fillCircleAtPoint(cx, cy, 6) gfx.setColor(gfx.kColorWhite) end
      gfx.setLineWidth(2)
      gfx.drawLine(cx - 4, cy - 4, cx + 4, cy + 4)
      gfx.drawLine(cx - 4, cy + 4, cx + 4, cy - 4)
      gfx.setLineWidth(1)
      gfx.setColor(gfx.kColorBlack)
    elseif st == 3 and not self.byEye then
      gfx.setColor(gfx.kColorWhite)
      gfx.fillCircleAtPoint(cx, cy, 5)
      gfx.setColor(gfx.kColorBlack)
      gfx.drawCircleAtPoint(cx, cy, 5)
      gfx.drawLine(cx - 2, cy, cx + 2, cy)
    end
  end
end

function Clock:drawSelection()
  local c = self.c
  local s = self.sel
  local k = slotArbor(s)
  local x, y = c.ax[k], c.ay[k]
  local t = c.slotT[s]
  local nt = #c.trayT
  local ghost = (nt > 0) and c.trayT[U.clamp(self.tsel, 1, nt)] or 0
  local blink = floor(self.t * 4) % 2 == 0
  -- ghost of the tray gear at true size
  if ghost > 0 and ghost ~= t and blink then
    gfx.setColor(gfx.kColorBlack)
    drawGearImg(x, y, ghost, 0, 6)
  end
  -- slot marker: a bracket label next to the arbor
  local wheel = slotIsWheel(s)
  local r = (t > 0) and t * K or (wheel and 16 or 7)
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(2)
  gfx.drawCircleAtPoint(x, y, r + 4)
  gfx.setLineWidth(1)
  local label = wheel and "WHEEL" or "PINION"
  local lw = UI.width(label) + 8
  local lx = U.clamp(floor(x - lw / 2), 4, 268 - lw)
  local ly = floor(y + r + 6)
  if ly > 196 then ly = floor(y - r - 24) end
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRoundRect(lx, ly, lw, 17, 3)
  UI.textW(label, lx + 4, ly, "left")
end

function Clock:drawPanel()
  local c = self.c
  local x0 = 272
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x0, 18, 128, 204)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(x0, 18, 2, 204)
  -- job ticket: a paper tag
  UI.panel(x0 + 4, 21, 122, 84, "plain")
  UI.text(KIND_TITLE[c.kind], x0 + 10, 23, "left", UI.bold)
  gfx.fillCircleAtPoint(x0 + 116, 30, 3)
  UI.textLines(c.note, x0 + 10, 38, 110, 2, UI.font, -2)
  UI.text("WANTS", x0 + 10, 67)
  UI.text(self.goalStr, x0 + 118, 67, "right", UI.bold)
  local meas = self.testB > 5 and (self.testO / self.testB) or 0
  UI.text("TEST", x0 + 10, 83)
  if self.phase ~= "bench" then
    UI.text(self.goalStr, x0 + 118, 83, "right")
  elseif self.testB > 5 then
    UI.text(U.cached("clk_meas", "x%.1f", floor(meas * 10 + 0.5) / 10), x0 + 118, 83, "right")
  else
    UI.text("-", x0 + 118, 83, "right")
  end
  -- test progress bar (one barrel turn)
  gfx.drawRect(x0 + 50, 87, 28, 8)
  gfx.fillRect(x0 + 52, 89, floor(24 * U.clamp(self.testB / 360, 0, 1)), 4)
  if self.mode == "endless" then
    local maxP = 70 + 30 * c.n
    gfx.fillRect(x0 + 8, 100, floor(114 * U.clamp(self.patience / maxP, 0, 1)), 2)
  end

  if self.phase == "bench" then self:drawTray(x0) else self:drawWindPanel(x0) end
end

function Clock:drawTray(x0)
  local c = self.c
  UI.text("TRAY", x0 + 8, 107, "left", UI.bold)
  -- fit report for selected slot + tray gear
  local nt = #c.trayT
  local s = self.sel
  if nt > 0 and not self.byEye then
    local g = c.trayT[U.clamp(self.tsel, 1, nt)]
    local i = slotIsWheel(s) and slotArbor(s) or (slotArbor(s) - 1)
    local other
    if slotIsWheel(s) then other = c.slotT[pinSlot(i)] else local ds = drvSlot(i) other = (ds == 0) and c.B or c.slotT[ds] end
    local txt
    if other == 0 then txt = "no mate"
    else
      local diff = g + other - c.S[i]
      if diff == 0 then txt = "FITS" elseif diff > 0 then txt = U.cached("clk_fitb", "binds +%d", diff) else txt = U.cached("clk_fits", "gap %d", diff) end
    end
    UI.text(txt, x0 + 122, 107, "right")
  end
  for i = 1, math.min(nt, MAX_TRAY) do
    local col = (i - 1) % 5
    local row = (i - 1) // 5
    local cx = x0 + 16 + col * 24
    local cy = 138 + row * 28
    local tt = c.trayT[i]
    local sel = i == self.tsel
    if sel then
      gfx.setColor(gfx.kColorBlack)
      gfx.fillRoundRect(cx - 12, cy - 14, 24, 28, 3)
      gfx.setColor(gfx.kColorWhite)
    else
      gfx.setColor(gfx.kColorBlack)
    end
    if sel then gfx.setImageDrawMode(gfx.kDrawModeFillWhite) end
    drawGearImg(cx, cy - 5, tt, 0, 5)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    gfx.setColor(sel and gfx.kColorBlack or gfx.kColorWhite)
    gfx.fillCircleAtPoint(cx, cy - 5, 1.5)
    if not self.byEye then
      if sel then UI.textW(NUMS[tt], cx, cy - 2, "center") else UI.text(NUMS[tt], cx, cy - 2, "center") end
    end
    gfx.setColor(gfx.kColorBlack)
  end
  if nt == 0 then UI.text("empty", x0 + 64, 140, "center") end
end

function Clock:drawClockLine(x0)
  if self.mode == "endless" then
    UI.text("PATIENCE", x0 + 8, 204)
    gfx.drawRect(x0 + 80, 207, 40, 9)
    local maxP = 70 + 30 * self.c.n
    gfx.fillRect(x0 + 82, 209, floor(36 * U.clamp(self.patience / maxP, 0, 1)), 5)
  elseif self.mode == "standard" then
    UI.text("SCORE", x0 + 8, 204)
    UI.text(U.cached("clk_score", "%d", self.score), x0 + 122, 204, "right", UI.bold)
  end
end

function Clock:drawWindPanel(x0)
  UI.text("MAINSPRING", x0 + 66, 108, "center", UI.bold)
  local v = U.clamp(self.needle, 0, 1.05)
  UI.meter(x0 + 60, 156, 28, v, -75, 75, 10, 0.88)
  UI.text("FULL", x0 + 124, 128, "right")
  if self.phase == "wind" or self.phase == "closing" then
    if not self.byEye and self.difficulty < 3 then
      UI.text(U.cached("clk_windp", "%d%%", floor(U.clamp(self.wind / self.limit, 0, 1.2) * 100)), x0 + 66, 186, "center", UI.bold)
    end
  elseif self.phase == "running" or self.phase == "card" then
    UI.text("RUNNING", x0 + 66, 186, "center", UI.bold)
  elseif self.phase == "snapped" then
    UI.text("SNAPPED", x0 + 66, 186, "center", UI.bold)
  end
  self:drawClockLine(x0)
end

function Clock:drawCard()
  UI.popup(36, 48, 200, 132, "paper")
  if self.mode == "tutorial" then
    UI.text("IT RUNS", 136, 60, "center", UI.bold)
    UI.text("Tick. Tock.", 136, 84, "center")
    return
  end
  UI.text(self.c.name, 136, 58, "center", UI.bold)
  local y = 80
  UI.text("Work", 50, y) UI.text(U.cached("clk_c1", "%d", self.gainBase or 0), 222, y, "right")
  UI.text("Speed", 50, y + 16) UI.text(U.cached("clk_c2", "%d", self.gainTime or 0), 222, y + 16, "right")
  UI.text("Wound", 50, y + 32) UI.text(U.cached("clk_c3", "%d", self.gainWind or 0), 222, y + 32, "right")
  if (self.gainPen or 0) > 0 then UI.text("Failed tests", 50, y + 48) UI.text(U.cached("clk_c4", "-%d", self.gainPen), 222, y + 48, "right") end
  gfx.drawLine(50, y + 66, 222, y + 66)
  UI.text(U.cached("clk_c5", "+%d", self.gain), 222, y + 70, "right", UI.bold)
  if self.cardT > 0.8 then UI.text("A: next clock", 50, y + 70) end
end

function Clock:drawHeader()
  local sec = floor(self.timeLeft)
  if self.mode == "standard" then
    if sec ~= self.hdrSec or self.index ~= self.hdrIdx then
      self.hdrSec, self.hdrIdx = sec, self.index
      self.hdr = "CLOCK " .. math.min(STANDARD_CLOCKS, self.index + 1) .. "/" .. STANDARD_CLOCKS .. "  " .. U.timeStr(sec)
    end
  elseif self.mode == "endless" then
    local key = self.done * 10 + self.complaints
    if key ~= self.hdrIdx then
      self.hdrIdx = key
      local marks = ({ "", " X", " XX", " XXX" })[self.complaints + 1] or ""
      self.hdr = "CLOCKS " .. self.done .. marks
    end
  else
    self.hdr = "LESSON"
  end
  UI.header(11, "CLOCKMAKER", self.hdr)
end

function Clock:draw()
  gfx.clear(gfx.kColorWhite)
  drawBench():draw(0, 18)
  self:drawTrain()
  self:drawMeshMarks()
  if self.phase == "bench" then self:drawSelection() end
  -- clock name engraved on the plate
  if self.phase == "bench" or self.phase == "wind" then
    gfx.setColor(gfx.kColorWhite)
    local nw = UI.width(self.c.name) + 8
    gfx.fillRect(PX1 - nw - 2, PY1 - 14, nw, 16)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(PX1 - nw - 2, PY1 - 14, nw, 16)
    UI.text(self.c.name, PX1 - 6, PY1 - 14, "right")
  end
  self:drawPanel()
  if self.msgT > 0 and self.msg and self.phase ~= "card" then
    local w = 250
    UI.popup(10, 26, w, 40, "ink")
    UI.textW(self.msg, 10 + w / 2, 30, "center", UI.bold)
    if self.msg2 then UI.textW(self.msg2, 10 + w / 2, 46, "center") end
  end
  if self.phase == "card" then self:drawCard() end
  self:drawHeader()
  if self.phase == "wind" or self.phase == "snapped" then
    UI.hints(Clock.HINTS_WIND)
  elseif self.phase == "card" then
    UI.hints(Clock.HINTS_RUN)
  elseif self.phase == "running" then
    UI.hints(Clock.HINTS_LISTEN)
  else
    UI.hints(Clock.HINTS_BENCH)
  end
end

Clock.HINTS_BENCH = { { "CRANK", "TEST" }, { "DPAD", "SLOT/TRAY" }, { "A", "FIT" }, { "B", "REMOVE" } }
Clock.HINTS_WIND = { { "CRANK", "WIND CLOCKWISE" }, { "A", "SET IT GOING" } }
Clock.HINTS_RUN = { { "A", "NEXT CLOCK" } }
Clock.HINTS_LISTEN = { { "CRANK", "LISTEN: TICK, TOCK" } }

------------------------------------------------------------------------
-- suspend / resume
------------------------------------------------------------------------
function Clock:serialize()
  local c = self.c
  local phase = self.phase
  if phase ~= "bench" and phase ~= "wind" then phase = "next" end
  return {
    v = 1, index = self.index, score = self.score, done = self.done, complaints = self.complaints,
    snapsRun = self.snapsRun, fixedRun = self.fixedRun, timeLeft = self.timeLeft,
    rng = self.rng:state(), phase = phase, clockT = self.clockT, fails = self.fails,
    wind = self.wind, limit = self.limit, soft = self.soft, patience = self.patience,
    c = { kind = c.kind, n = c.n, B = c.B, R = c.R, ax = c.ax, ay = c.ay, S = c.S, solT = c.solT,
      slotT = c.slotT, slotB = c.slotB, trayT = c.trayT, trayB = c.trayB, level = c.level,
      name = c.name, note = c.note, fault = c.fault or 0 },
  }
end

function Clock:deserialize(t)
  if type(t) ~= "table" or t.v ~= 1 then return end
  self.index, self.score, self.done = t.index, t.score, t.done
  self.complaints, self.snapsRun, self.fixedRun = t.complaints or 0, t.snapsRun or 0, t.fixedRun or 0
  self.timeLeft = t.timeLeft or 0
  self.rng:setState(t.rng)
  if t.phase == "next" then
    if self.mode == "tutorial" then self:startClock() else self.index = self.index + 1 self:startClock() end
    if self.mode == "standard" and self.index >= STANDARD_CLOCKS then self.index = STANDARD_CLOCKS - 1 end
    return
  end
  self:startClock()
  local c = t.c
  local trayT, trayB = {}, {}
  for i = 1, #c.trayT do trayT[i] = c.trayT[i] trayB[i] = c.trayB[i] end
  self.c = { kind = c.kind, n = c.n, B = c.B, R = c.R, ax = c.ax, ay = c.ay, S = c.S, solT = c.solT,
    slotT = c.slotT, slotB = c.slotB, trayT = trayT, trayB = trayB, level = c.level,
    name = c.name, note = c.note, fault = c.fault }
  self.ns = 2 * self.c.n - 1
  self.sel = U.clamp(self.sel, 1, self.ns)
  self.tsel = 1
  self.goalStr = ratioText(self.c.R)
  for k = 1, 6 do self.ang[k] = 0 end
  self:computeGeometry()
  self:resetTest()
  self.phase = t.phase
  self.clockT, self.fails = t.clockT or 0, t.fails or 0
  self.wind, self.limit, self.soft = t.wind or 0, t.limit or 3.5, t.soft or 0.8
  self.patience = t.patience or self.patience
end
