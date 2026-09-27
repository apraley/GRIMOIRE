-- CRANKING IT :: No.I SAFECRACKER
--
-- The crank IS the dial. Behind it sits a simulated wheel pack:
--   * wheel 1 is fixed to the dial; wheel k+1 is picked up by a pin on
--     wheel k only after almost a full turn of slack, so reversing direction
--     leaves the deeper wheels where they were.
--   * each wheel has one gate. When every gate sits under the fence, the
--     fence drops; turning back the other way then draws the bolt.
--   * a gate passing under the fence makes a click whose pitch identifies
--     the wheel. Nearer the gate, the contact needle and ticks grow louder.
-- Combinations are generated per safe; the canonical procedure (right,
-- left, right...) is how the gates were machined, so listening for each
-- wheel's click in the right direction reveals the number.

local gfx <const> = playdate.graphics
local floor <const> = math.floor
local abs <const> = math.abs
local sin <const>, cos <const>, rad <const> = math.sin, math.cos, math.rad

local SAFE_NAMES <const> = {
  "HARROW & SONS No.4", "KETTERING IRON", "NINEFOLD MUTUAL", "BRASSBOUND & CO.",
  "SABLE FIDELITY", "PELLAM STRONGROOM", "GREY ROCK SAVINGS", "THE ORPHAN'S TRUST",
  "LAMPLIGHTER'S BOX", "MERIDIAN VAULT",
}
local LOOT <const> = {
  "bearer bonds, damp", "a pocket watch, still ticking", "the deeds to a lighthouse",
  "a jar of milk teeth", "somebody's diary", "a note: 'turn back'", "gold sovereigns",
  "a single brass gear", "photographs of this room", "a smaller safe", "a sealed letter to you",
  "sand, and a smell of the sea",
}
local STANDARD_SAFES <const> = 5
local NUMS = {}
for i = 0, 99 do NUMS[i] = tostring(i) end

local Safe = Machine.define({
  id = "safecracker",
  number = 1,
  title = "SAFECRACKER",
  tagline = "Listen to the wheels.",
  description = "Each wheel in the pack has one gate. Spin to gather them, reverse to set each. The clicks name the wheel.",
  howto = "Spin right to gather all wheels, stop on the deepest wheel's click. Reverse: after a turn the next wheel joins. When every gate lines up the fence drops - turn back to draw the bolt.",
  controls = { { "CRANK", "turn the dial" }, { "A", "pencil the number" }, { "B", "wipe notes" } },
  modes = { "tutorial", "standard", "endless" },
  medals = { standard = { 3000, 6000, 9000 }, endless = { 3000, 7000, 12000 } },
  scoreLabel = "POINTS",
  unlockCost = 0,
  achievements = {
    { id = "first", name = "FIRST CRACK", desc = "Open your first safe." },
    { id = "clean", name = "SURGEON", desc = "Open a safe with no wasted reversals." },
    { id = "five", name = "FIVE WHEELS", desc = "Open a five-wheel safe." },
    { id = "quick", name = "LIGHT FINGERS", desc = "Open a safe in under 25 seconds." },
    { id = "vault", name = "THE WHOLE VAULT", desc = "Open all five Standard safes." },
  },
  challenges = {
    { id = "deaf", name = "COTTON EARS", desc = "No contact needle. Trust the wheel lamps.", mode = "standard", difficulty = 2, goal = 3000, reward = 2, cost = 2 },
    { id = "rusty", name = "RUSTED DIAL", desc = "The dial sticks and jumps.", mode = "standard", difficulty = 1, mods = { rusty = true }, goal = 3000, reward = 3, cost = 2 },
    { id = "night", name = "NIGHT SHIFT", desc = "Endless, starting at five wheels.", mode = "endless", difficulty = 3, goal = 5000, reward = 3, cost = 3 },
  },
  records = {
    { "opened", "Safes opened" },
    { "fastest", "Fastest crack", function(v) return v > 0 and string.format("%.1fs", v / 10) or "-" end },
    { "wheels", "Wheels set" },
  },
  drawIcon = function(cx, cy)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(cx - 22, cy - 22, 44, 44)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(cx, cy, 17)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawCircleAtPoint(cx, cy, 11)
    for i = 0, 19 do
      local a = rad(i * 18)
      local r1 = (i % 5 == 0) and 12 or 14
      gfx.drawLine(cx + sin(a) * r1, cy - cos(a) * r1, cx + sin(a) * 16, cy - cos(a) * 16)
    end
    gfx.fillCircleAtPoint(cx, cy, 5)
    gfx.fillTriangle(cx - 3, cy - 22, cx + 3, cy - 22, cx, cy - 18)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(cx + 16, cy + 14, 4, 4)
    gfx.fillRect(cx - 20, cy + 14, 4, 4)
  end,
})

------------------------------------------------------------------------
-- lock generation
------------------------------------------------------------------------
-- level 0.. increases wheels, numbers and tightens tolerance
function Safe:makeLock(level, rng)
  local L = level
  local lock = {}
  lock.wheels = U.clamp(3 + L // 2, 3, 5)
  lock.N = (L == 0) and 40 or ((L <= 2) and 60 or 100)
  lock.A = lock.N * 0.485                       -- half slack between wheels
  lock.tol = lock.N * math.max(0.008, 0.02 - 0.0025 * L)
  lock.noise = math.min(0.9, 0.12 * L)          -- false clicks per second
  lock.xray = (L == 0 and self.mode ~= "endless") or self.mode == "tutorial"
  lock.name = rng:pick(SAFE_NAMES)
  lock.loot = rng:pick(LOOT)
  -- combination: well separated numbers
  local combo = {}
  local n = lock.wheels
  for j = 1, n do
    local c
    for _ = 1, 40 do
      c = rng:range(3, lock.N - 3)
      local ok = true
      for i = 1, j - 1 do
        if abs(U.angleDiff(c * 360 / lock.N, combo[i] * 360 / lock.N)) < 54 then ok = false end
      end
      if ok then break end
    end
    combo[j] = c
  end
  lock.combo = combo
  -- machine the gates so the canonical procedure works:
  -- step j sets wheel k = n-j+1 turning direction s_j (+1 right, -1 left)
  lock.gate = {}
  for j = 1, n do
    local k = n - j + 1
    local s = (j % 2 == 1) and 1 or -1
    lock.gate[k] = (combo[j] - s * (k - 1) * lock.A) % lock.N
  end
  lock.openDir = (n % 2 == 1) and -1 or 1  -- opposite to the final step
  return lock
end

function Safe:startSafe()
  local level = self.safeIndex + (self.difficulty - 1) * 2
  if self.mode == "tutorial" then level = 0 end
  self.lock = self:makeLock(level, self.rng)
  local lock = self.lock
  self.dial = self.rng:range(0, lock.N - 1)
  self.w = { self.dial }
  self.rel = { 0 }
  for k = 2, lock.wheels do
    self.rel[k] = self.rng:between(-lock.A, lock.A)
    self.w[k] = (self.w[k - 1] + self.rel[k]) % lock.N
  end
  self.fenceDown = false
  self.bolt = 0
  self.opened = false
  self.openT = 0
  self.lamps = {}
  self.pickup = {}
  self.moving = {}
  for k = 1, lock.wheels do self.lamps[k] = 0 self.pickup[k] = 0 self.moving[k] = 0 end
  self.contact = 0
  self.safeT = 0
  self.reversals = 0
  self.lastDir = 0
  self.runUnits = 0
  self.marks = {}
  self.doorSwing = 0
  self.msg, self.msgT = nil, 0
  self.everAligned = {}
end

------------------------------------------------------------------------
-- lifecycle
------------------------------------------------------------------------
function Safe:enter(params)
  self.t = 0
  self.safeIndex = 0
  self.score = 0
  self.cracked = 0
  if self.mode == "endless" then
    self.timeLeft = 120
    if self.difficulty >= 3 then self.safeIndex = 4 end
  elseif self.mode == "tutorial" then
    self.timeLeft = 0
  else
    self.timeLeft = 300
  end
  self.tracker = Crank.Tracker.new()
  self.tickDetent = 0
  self.hum = Audio.Hum.new(Audio.SINE)
  self:startSafe()
  if self.mode == "tutorial" then self:setupCoach() end
end

function Safe:exit() self.hum:stop() end

function Safe:setupCoach()
  local s = self
  local n = self.lock.wheels
  self.coach = UI.Coach.new({
    { text = "Turn the crank. The dial turns with it. Numbers pass the arrow at the top.",
      check = function() return abs(s.tracker.total) > 300 end },
    { text = "Spin CLOCKWISE two whole turns. Watch the x-ray: the wheels are picked up one by one.",
      check = function() return s:allEngaged(1) end },
    { text = "Keep going clockwise, slowly. Lamp III and a LOW click mark wheel III's gate. Stop on it.",
      check = function() return s:aligned(n) and s.tracker.idle > 0.4 end, hold = 0.3 },
    { text = "Reverse: COUNTER-clockwise. After about a turn wheel II joins. Stop on its MIDDLE click.",
      check = function() return s:aligned(n) and s:aligned(n - 1) and s.tracker.idle > 0.4 end, hold = 0.3 },
    { text = "Clockwise again. Wheel I moves at once. Stop on the HIGH click and the fence drops.",
      check = function() return s.fenceDown end },
    { text = "Now turn COUNTER-clockwise to draw the bolt and open the door.",
      check = function() return s.opened end },
  }, { y = 190, h = 46, anchor = "bottom" })
end

------------------------------------------------------------------------
-- mechanics
------------------------------------------------------------------------
local function wrapDiff(a, b, N)
  local d = (b - a) % N
  if d > N / 2 then d = d - N end
  return d
end

function Safe:aligned(k)
  local lock = self.lock
  return abs(wrapDiff(self.w[k], lock.gate[k], lock.N)) <= lock.tol
end

function Safe:allAligned()
  for k = 1, self.lock.wheels do if not self:aligned(k) then return false end end
  return true
end

-- every wheel pushed in direction s (each lagging the previous by A)
function Safe:allEngaged(s)
  for k = 2, self.lock.wheels do
    if abs(self.rel[k] + s * self.lock.A) > 0.6 then return false end
  end
  return true
end

-- move the dial by du units, propagating through the wheel pack.
-- rel[k] is the unwrapped offset of wheel k from wheel k-1 and is limited
-- to [-A, A] by the pickup pins; any excess drags wheel k along.
function Safe:turn(du)
  local lock = self.lock
  local N = lock.N
  if du == 0 then return end
  local dir = du > 0 and 1 or -1

  if self.fenceDown then
    -- the fence sits in the gates: the dial now works the bolt
    if dir == lock.openDir then
      local before = self.bolt
      self.bolt = math.min(1, self.bolt + abs(du) / (N * 0.22))
      self.dial = (self.dial + du) % N
      if floor(before * 12) ~= floor(self.bolt * 12) then Audio.sfx.creak(0.25) end
      if self.bolt >= 1 and not self.opened then self:open() end
      return
    elseif self.bolt > 0 then
      self.bolt = math.max(0, self.bolt - abs(du) / (N * 0.22))
      self.dial = (self.dial + du) % N
      return
    else
      self.fenceDown = false
      Audio.sfx.click(0.3)
    end
  end

  local A = lock.A
  local rel = self.rel
  local steps = math.max(1, math.ceil(abs(du) / (A * 0.25)))
  local step = du / steps
  for _ = 1, steps do
    local move = step
    local deepest = 1
    local before = self.w[1]
    self.moving[1] = 0.25
    self.w[1] = (self.w[1] + move) % N
    self:gateCheck(1, before, before + move)
    for k = 2, lock.wheels do
      if move == 0 then break end
      local newRel = rel[k] - move
      local clamped = U.clamp(newRel, -A, A)
      local mk = clamped - newRel
      if mk ~= 0 and abs(rel[k]) < A - 1e-6 then
        -- the pin just caught the next wheel: a soft clunk you can feel
        Audio.sfx.thud(0.25)
        self.pickup[k] = 1
      end
      rel[k] = clamped
      if mk ~= 0 then
        self.moving[k] = 0.25
        local b = self.w[k]
        self.w[k] = (b + mk) % N
        self:gateCheck(k, b, b + mk)
        deepest = k
      end
      move = mk
    end
    self.deepest = deepest
  end
  self.dial = self.w[1]

  if self:allAligned() and not self.fenceDown then
    self.fenceDown = true
    Audio.sfx.thunk(0.8)
    self:shake(2)
    self.msg, self.msgT = "THE FENCE DROPS", 2
  end
end

-- click when wheel k's gate crosses under the fence
function Safe:gateCheck(k, before, after)
  local lock = self.lock
  local d0 = wrapDiff(lock.gate[k], before, lock.N)
  local d1 = wrapDiff(lock.gate[k], after, lock.N)
  local crossed = (d0 <= 0 and d1 > 0) or (d0 >= 0 and d1 < 0)
  if crossed and abs(d0 - d1) < lock.N / 2 then
    local n = lock.wheels
    -- deeper wheels are lower pitched
    local pitch = 1500 - (k - 1) * (900 / math.max(1, n - 1))
    Audio.play(Audio.SQUARE, pitch, 0.35, 0.03, 0.001, 0.04, 0, 0.02)
    Audio.sfx.click(0.25)
    self.lamps[k] = 1
    self:shake(0.8)
  end
end

function Safe:open()
  self.opened = true
  self.openT = 0
  Audio.sfx.clank(0.9)
  Audio.sfx.success()
  self:shake(5)
  local secs = self.safeT
  self.cracked = self.cracked + 1
  self:statAdd("opened", 1)
  self:statAdd("wheels", self.lock.wheels)
  local rec = Save.machine(self.def.id).stats
  local tenths = floor(secs * 10)
  if not rec.fastest or rec.fastest == 0 or tenths < rec.fastest then rec.fastest = tenths Save.markDirty() end
  self:award("first")
  if self.reversals <= self.lock.wheels then self:award("clean") end
  if self.lock.wheels >= 5 then self:award("five") end
  if secs < 25 then self:award("quick") end
  local gained = 1000 + (self.reversals <= self.lock.wheels and 300 or 0) + self.lock.wheels * 100
  self.lastGain = gained
  if self.mode ~= "tutorial" then self.score = self.score + gained end
  if self.mode == "endless" then self.timeLeft = self.timeLeft + 45 end
end

function Safe:nextSafe()
  self.safeIndex = self.safeIndex + 1
  if self.mode == "standard" and self.safeIndex >= STANDARD_SAFES then
    self:award("vault")
    self.score = self.score + floor(self.timeLeft) * 10
    self:finish({ success = true, score = self.score, title = "VAULT EMPTIED",
      lines = { "Safes opened: " .. self.cracked .. "/" .. STANDARD_SAFES, "Time bonus: " .. floor(self.timeLeft) * 10 } })
    return
  end
  self:startSafe()
end

function Safe:cranked(change)
  if self.opened then return end
  self.tracker:feed(change)
  local lock = self.lock
  local du = change * lock.N / 360
  if self.fenceDown and U.sign(du) == lock.openDir then du = du * 0.45 end -- the bolt is heavy
  -- ticks at each number
  local before = floor(self.dial)
  self:turn(du)
  -- direction reversal accounting
  local dir = U.sign(du)
  if dir ~= 0 then
    if dir ~= self.lastDir then
      if self.runUnits > lock.N * 0.05 then self.reversals = self.reversals + 1 end
      self.runUnits = 0
    end
    self.runUnits = self.runUnits + abs(du)
    self.lastDir = dir
  end
  if floor(self.dial) ~= before then
    local c = self.contact
    Audio.sfx.tick(900 + c * 900, 0.04 + c * 0.25)
  end
end

function Safe:buttonDown(b)
  if b == Input.A then
    if self.opened and self.openT > 1.2 then
      if self.mode == "tutorial" then return end
      self:nextSafe()
      return
    end
    local dirs = self.lastDir >= 0 and "R" or "L"
    local s = dirs .. " " .. floor(self.dial + 0.5) % self.lock.N
    if #self.marks >= 6 then table.remove(self.marks, 1) end
    self.marks[#self.marks + 1] = s
    Audio.sfx.tick(600, 0.2)
  elseif b == Input.B then
    self.marks = {}
    Audio.sfx.whoosh(0.1)
  end
end

function Safe:update(dt)
  self.t = self.t + dt
  self.tracker:update(dt)
  local lock = self.lock
  if self.msgT > 0 then self.msgT = self.msgT - dt end
  for k = 1, lock.wheels do
    self.lamps[k] = math.max(0, self.lamps[k] - dt * 2.2)
    self.pickup[k] = math.max(0, self.pickup[k] - dt * 3)
    self.moving[k] = math.max(0, self.moving[k] - dt)
  end

  -- contact needle: proximity of the deepest moving wheel's gate
  local k = self.deepest or 1
  local d = abs(wrapDiff(self.w[k], lock.gate[k], lock.N))
  local window = lock.N * 0.07
  local target = U.clamp(1 - d / window, 0, 1)
  if self.tracker.idle > 0.3 then target = target * 0.4 end
  self.contact = U.damp(self.contact, target, 12, dt)
  if self.difficulty >= 2 and self.params.challengeId == "deaf" then self.contact = 0 end

  -- false clicks (building noise) on harder safes
  if lock.noise > 0 and self.rng:chance(lock.noise * dt) then
    local fk = self.rng:range(1, lock.wheels)
    self.lamps[fk] = math.max(self.lamps[fk], 0.45)
    Audio.sfx.click(0.12)
  end
  -- stethoscope hum grows with contact
  self.hum:set(110 + self.contact * 60, self.contact * 0.15)

  if self.opened then
    self.openT = self.openT + dt
    self.doorSwing = U.damp(self.doorSwing, 1, 3, dt)
    if self.mode == "tutorial" then return end
    if self.openT > 3.5 then self:nextSafe() end
    return
  end

  if self.mode ~= "tutorial" then
    self.safeT = self.safeT + dt
    self.timeLeft = self.timeLeft - dt
    if self.timeLeft <= 0 then
      self.timeLeft = 0
      Audio.sfx.fail()
      self:finish({ success = self.cracked > 0, score = self.score,
        title = self.cracked > 0 and "ALARM - TIME UP" or "ALARM RAISED",
        lines = { "Safes opened: " .. self.cracked, "Last safe: " .. lock.name } })
    end
  else
    self.safeT = self.safeT + dt
  end
end

------------------------------------------------------------------------
-- drawing
------------------------------------------------------------------------
local DCX <const>, DCY <const>, DR <const> = 124, 124, 76
local RIVETS <const> = { 20, 38, 232, 38, 20, 220, 232, 220, 126, 38, 126, 220 }

function Safe:drawDoor()
  -- door plate
  gfx.setPattern(Art.pat.gray75)
  gfx.fillRect(0, 18, 256, 222)
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(3)
  gfx.drawRect(8, 26, 236, 206)
  gfx.setLineWidth(1)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawRect(14, 32, 224, 194)
  gfx.setColor(gfx.kColorBlack)
  for i = 1, #RIVETS, 2 do Art.rivet(RIVETS[i], RIVETS[i + 1]) end
  -- hinge side bars
  gfx.fillRect(0, 50, 8, 40)
  gfx.fillRect(0, 160, 8, 40)
end

function Safe:drawDial()
  local lock = self.lock
  local N = lock.N
  -- rim
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(DCX, DCY, DR + 6)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(DCX, DCY, DR)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawCircleAtPoint(DCX, DCY, DR - 26)
  local r = self.dial
  local step = 360 / N
  -- numbers increase counter-clockwise on the face; the face turns with the crank
  local labelEvery = (N <= 40) and 5 or 10
  local shake = self.contact > 0.6 and (self.t * 60 % 2 < 1 and 1 or 0) or 0
  for i = 0, N - 1 do
    local a = rad((r - i) * step)
    local s, c = sin(a), cos(a)
    local len = (i % labelEvery == 0) and 12 or ((i % 5 == 0) and 8 or 5)
    local x1, y1 = DCX + s * (DR - 2), DCY - c * (DR - 2)
    local x2, y2 = DCX + s * (DR - 2 - len), DCY - c * (DR - 2 - len)
    if i % labelEvery == 0 then gfx.setLineWidth(2) end
    gfx.drawLine(x1 + shake, y1, x2 + shake, y2)
    gfx.setLineWidth(1)
    if i % labelEvery == 0 then
      local lx, ly = DCX + s * (DR - 22), DCY - c * (DR - 22)
      UI.text(NUMS[i], lx, ly - 8, "center")
    end
  end
  -- knob with grip
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(DCX, DCY, 30)
  gfx.setColor(gfx.kColorWhite)
  for i = 0, 11 do
    local a = rad(r * step + i * 30)
    gfx.drawLine(DCX + sin(a) * 18, DCY - cos(a) * 18, DCX + sin(a) * 28, DCY - cos(a) * 28)
  end
  gfx.fillCircleAtPoint(DCX, DCY, 8)
  gfx.setColor(gfx.kColorBlack)
  -- index arrow
  gfx.fillTriangle(DCX - 7, DCY - DR - 12, DCX + 7, DCY - DR - 12, DCX, DCY - DR + 1)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawLine(DCX, DCY - DR - 10, DCX, DCY - DR - 3)
  gfx.setColor(gfx.kColorBlack)
end

function Safe:drawHandle()
  -- bolt handle: three spokes that turn as the bolt is drawn
  local hx, hy = 222, 196
  local a0 = self.bolt * 90 + (self.opened and 90 or 0)
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(4)
  for i = 0, 2 do
    local a = rad(a0 + i * 120)
    gfx.drawLine(hx, hy, hx + sin(a) * 18, hy - cos(a) * 18)
  end
  gfx.setLineWidth(1)
  for i = 0, 2 do
    local a = rad(a0 + i * 120)
    gfx.fillCircleAtPoint(hx + sin(a) * 18, hy - cos(a) * 18, 4)
  end
  gfx.fillCircleAtPoint(hx, hy, 6)
  -- bolt gauge
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(196, 40, 42, 10)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(196, 40, 42, 10)
  gfx.fillRect(198, 42, floor(38 * self.bolt), 6)
  UI.textW("BOLT", 196, 52)
end

function Safe:drawPanel()
  local lock = self.lock
  local x0 = 258
  UI.panel(x0, 20, 142, 198, "paper")
  UI.text(lock.name, x0 + 71, 26, "center")
  -- wheel lamps (deepest at top)
  UI.text("WHEELS", x0 + 10, 44, "left", UI.bold)
  local n = lock.wheels
  for k = n, 1, -1 do
    local row = n - k
    local y = 62 + row * 16
    UI.text(U.roman(k), x0 + 12, y - 2)
    local lit = self.lamps[k]
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(x0 + 36, y, 60, 11)
    if lit > 0 then
      Art.setShade(lit)
      gfx.fillRect(x0 + 38, y + 2, floor(56 * lit), 7)
    end
    gfx.setColor(gfx.kColorBlack)
    -- turning indicator: a little wheel that spins while this wheel moves
    local cx, cy = x0 + 112, y + 5
    gfx.drawCircleAtPoint(cx, cy, 6 + floor(self.pickup[k] * 3))
    if self.moving[k] > 0 then
      local a = rad(self.w[k] * 360 / lock.N)
      gfx.drawLine(cx, cy, cx + sin(a) * 6, cy - cos(a) * 6)
      gfx.fillCircleAtPoint(cx, cy, 2)
    end
  end
  -- contact needle
  local my = 62 + n * 16 + 30
  if not (self.params.challengeId == "deaf") then
    UI.meter(x0 + 71, my + 8, 26, self.contact, -70, 70, 10, 0.8)
    UI.text("CONTACT", x0 + 71, my + 14, "center")
  end
  -- notes
  local ny = my + 32
  gfx.drawLine(x0 + 8, ny - 2, x0 + 134, ny - 2)
  for i = 1, #self.marks do
    local col = (i - 1) % 3
    local row = (i - 1) // 3
    UI.text(self.marks[i], x0 + 10 + col * 44, ny + row * 16)
  end
end

function Safe:drawXray()
  local lock = self.lock
  if not lock.xray then return end
  -- side view of the wheel pack, each wheel as a disc with its gate notch
  local n = lock.wheels
  local x0, y0 = 22, 196
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x0 - 4, y0 - 20, 18 + n * 26, 38)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(x0 - 4, y0 - 20, 18 + n * 26, 38)
  -- fence bar
  gfx.fillRect(x0, y0 - 17, n * 26, 3)
  for k = 1, n do
    local cx = x0 + 10 + (k - 1) * 26
    gfx.drawCircleAtPoint(cx, y0 + 2, 11)
    local d = wrapDiff(self.w[k], lock.gate[k], lock.N)
    local a = rad(-d * 360 / lock.N)
    local gx, gy = cx + sin(a) * 11, y0 + 2 - cos(a) * 11
    if self:aligned(k) then gfx.fillCircleAtPoint(gx, gy, 4) else gfx.drawCircleAtPoint(gx, gy, 3) end
  end
  UI.text("X-RAY", x0 + n * 26 + 16, y0 - 8)
end

function Safe:drawOpen()
  -- door swings away revealing the interior and its contents
  local sw = self.doorSwing
  local w = floor(256 * (1 - sw * 0.8))
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(0, 18, 256, 222)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(40, 50, 180, 150)
  gfx.setColor(gfx.kColorBlack)
  gfx.setPattern(Art.pat.hlines)
  gfx.fillRect(40, 50, 180, 150)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(60, 120, 140, 50)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(60, 120, 140, 50)
  UI.textBlock(self.lock.loot, 66, 128, 128, UI.font, 0)
  -- the door edge-on
  gfx.setPattern(Art.pat.gray75)
  gfx.fillRect(0, 18, math.max(6, w // 4), 222)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(0, 18, math.max(6, w // 4), 222)
  if self.mode ~= "tutorial" then
    UI.panel(60, 60, 140, 40, "ink")
    UI.textW("+" .. self.lastGain, 130, 64, "center", UI.bold)
    UI.textW(self.openT > 1.2 and "A: next safe" or "OPEN", 130, 80, "center")
  end
end

function Safe:draw()
  gfx.clear(gfx.kColorWhite)
  if self.opened then
    self:drawOpen()
  else
    self:drawDoor()
    self:drawDial()
    self:drawHandle()
    self:drawXray()
  end
  self:drawPanel()
  local right
  if self.mode == "standard" then
    right = U.cached("safe_hdr", "SAFE %d/5  ", self.safeIndex + 1) .. U.timeStr(self.timeLeft)
  elseif self.mode == "endless" then
    right = U.cached("safe_hdr", "SAFES %d  ", self.cracked) .. U.timeStr(self.timeLeft)
  else
    right = "LESSON"
  end
  UI.header(1, "SAFECRACKER", right)
  if self.msgT > 0 and self.msg and not self.opened then
    UI.panel(40, 100, 170, 26, "ink")
    UI.textW(self.msg, 125, 104, "center", UI.bold)
  end
  if self.mode ~= "tutorial" then UI.hints(Safe.HINTS) end
end

Safe.HINTS = { { "CRANK", "DIAL" }, { "A", "PENCIL" }, { "B", "WIPE" } }

------------------------------------------------------------------------
-- suspend / resume
------------------------------------------------------------------------
function Safe:serialize()
  return {
    safeIndex = self.safeIndex, score = self.score, cracked = self.cracked,
    timeLeft = self.timeLeft, rng = self.rng:state(), dial = self.dial,
    w = self.w, rel = self.rel, marks = self.marks,
    reversals = self.reversals, safeT = self.safeT,
    pickup = nil,
    lock = { wheels = self.lock.wheels, N = self.lock.N, A = self.lock.A, tol = self.lock.tol,
      noise = self.lock.noise, xray = self.lock.xray, name = self.lock.name, loot = self.lock.loot,
      combo = self.lock.combo, gate = self.lock.gate, openDir = self.lock.openDir },
  }
end

function Safe:deserialize(t)
  self.safeIndex, self.score, self.cracked = t.safeIndex, t.score, t.cracked
  self.timeLeft = t.timeLeft
  self.rng:setState(t.rng)
  self:startSafe()
  self.lock = t.lock
  self.dial = t.dial
  self.w = t.w
  self.rel = t.rel
  self.marks = t.marks or {}
  self.reversals = t.reversals or 0
  self.safeT = t.safeT or 0
  self.lamps, self.pickup, self.moving = {}, {}, {}
  for k = 1, self.lock.wheels do self.lamps[k] = 0 self.pickup[k] = 0 self.moving[k] = 0 end
end
