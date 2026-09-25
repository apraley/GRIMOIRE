-- CRANKING IT :: No.X THE WELL
--
-- The crank IS the windlass handle, and gravity drives it, not you.
--   * The drum carries rope; the bucket (plus its water, plus the weight of
--     the hanging rope) pulls the drum round in the lowering direction.
--   * Your hand is a stiff spring on the handle. Holding still means your
--     grip supplies the whole load; cranking counter-clockwise lets it down,
--     clockwise hauls it up. When the force your hand must supply exceeds
--     your grip (grip weakens as you tire), the handle slips out of your
--     hand and the drum free-spins: the bucket plummets. Crank hard
--     clockwise to catch it by friction, or drop the pawl (A) into the
--     ratchet - a violent catch wears the pawl.
--   * The bucket hangs on a rope that can go slack: it floats on the unseen
--     water, you hear the splash late (sound comes back up the shaft), and
--     only small alternating jiggles tip it to fill. Slamming into the water
--     cracks it; a cracked bucket leaks.
--   * Hauling: a full bucket is heavy, and water sloshes with the bucket's
--     acceleration (a driven, damped oscillator): jerky hauling spills it.
-- Standard: seven nights, a water quota each night before the candle dies.
-- The well is a little deeper every night, and what comes up in the bucket
-- gets stranger. Endless: every bucket the water is further down.

local gfx <const> = playdate.graphics
local floor <const> = math.floor
local abs <const> = math.abs
local sqrt <const> = math.sqrt
local sin <const>, cos <const>, rad <const> = math.sin, math.cos, math.rad
local min <const>, max <const> = math.min, math.max
local clamp <const> = U.clamp

------------------------------------------------------------------------
-- physical constants (metres, seconds, kilograms-force)
------------------------------------------------------------------------
local G <const> = 9.8
local CIRC <const> = 1.2        -- metres of rope per turn of the handle
local ROPE_KG <const> = 0.12    -- per metre of hanging rope
local BUCKET_KG <const> = 2.5
local CAP <const> = 10          -- litres (= kg) the bucket holds
local BUCKET_H <const> = 0.35   -- rope end (bail) to the bucket's bottom
local MD <const> = 3.0          -- drum + handle, as an equivalent rope mass
local KP <const>, KD <const> = 110, 12    -- the hand: spring and damping
local KR <const>, CR <const> = 280, 9     -- the rope: stiff, one-sided
local GRIP0 <const> = 30        -- a fresh grip, kgf
local SUB <const> = 6           -- physics substeps per frame
local NIGHTS <const> = 7
local TEETH <const> = 12        -- ratchet teeth per turn

-- screen layout
local PXM <const> = 10          -- shaft pixels per metre
local SX <const> = 150          -- the shaft panel starts here
local SH_L <const>, SH_R <const> = 246, 306   -- inner walls
local RX <const> = 276          -- rope x in the shaft
local AX <const>, AY <const> = 64, 62         -- windlass axle in the inset

local NIGHT_DEPTH <const> = { 12, 15, 19, 23, 27, 32, 38 }
local NIGHT_QUOTA <const> = { 16, 18, 24, 26, 27, 32, 34 }

local STORY <const> = {
  [0] = "The pump froze in the night. The Keeper says the old well in the yard still works. \"Twelve metres,\" he says. \"Mind the handle. It bites.\"",
  "Good water, cold enough to hurt the teeth. The rope has old chalk marks on it. Someone measured this well before me.",
  "The chalk was wrong tonight. The water was lower. I measured twice. The Keeper says wells do that. He did not look at me when he said it.",
  "Something scraped along the bucket as it came up. Rats, the Keeper says. Rats do not live forty feet down, in the water.",
  "There was a child's shoe in the bucket. It was dry. There are no children in this house. There never have been.",
  "The photograph was of me, at the windlass, taken from below, with a flash. I did not see a flash. I heard someone breathe out.",
  "Carved inside the bucket, from underneath: THANK YOU FOR THE LIGHT. Tonight I will tie the lantern on again. It is only polite.",
}
local ENDING <const> = "At dawn the rope came up wet to the last knot, and warm. The Keeper has covered the well with a millstone. Some nights I still hear the windlass turning. Slowly. From the inside."

-- things that come up in the bucket: text, points; three tiers of strange
local FINDS <const> = {
  { { "Just water. Very cold.", 0 }, { "A copper coin, green with age.", 30 }, { "A pale fish. It has no eyes.", 20 },
    { "A brass ring. It fits you.", 60 }, { "A snail shell, perfectly white.", 10 } },
  { { "The water is warm.", 0 }, { "A button from a coat like yours.", 15 }, { "A tooth. Probably human.", 15 },
    { "A folded note: 'deeper'.", 0 }, { "Seven coins, all the same year.", 80 } },
  { { "Hair, wound round the handle.", 0 }, { "Your own writing: 'keep turning'.", 0 }, { "A lantern. Still lit.", 40 },
    { "Nothing. The bucket is warm inside.", 0 }, { "A key to this house.", 50 } },
}
local NIGHT_FIND <const> = {
  [3] = { "Scratches on the bucket, from below.", 0 },
  [4] = { "A child's shoe. It is dry.", 0 },
  [5] = { "A photograph of you, taken from below.", 0 },
  [6] = { "Carved inside: THANK YOU FOR THE LIGHT", 0 },
}
local WALL_WORDS <const> = { [5] = "LOWER", [6] = "THANK YOU", [7] = "FOR THE LIGHT" }

local HINTS <const> = { { "CRANK", "LOWER / HAUL" }, { "A", "PAWL" }, { "B", "LET GO" } }
local HINTS_READ <const> = { { "A", "CONTINUE" } }
local ROMAN = {}
for i = 1, 12 do ROMAN[i] = U.roman(i) end
local DEPTHS = {}
for i = 0, 300 do DEPTHS[i] = tostring(i) end

local Well = Machine.define({
  id = "well",
  number = 10,
  title = "THE WELL",
  tagline = "Mind the handle. It bites.",
  description = "Let the bucket down against its own weight, jiggle it full, haul it up without spilling. The well is deeper every night.",
  howto = "Crank counter-clockwise to lower, clockwise to haul. Hold still and your grip holds - until it slips. A drops the pawl so you can rest. Listen for the echo. Jiggle to fill. Haul smoothly.",
  controls = { { "CRANK", "ccw lower, cw haul, jiggle" }, { "A", "pawl down / up" }, { "B", "hold: let go of handle" } },
  modes = { "tutorial", "standard", "endless" },
  medals = { standard = { 700, 3000, 7000 }, endless = { 600, 2000, 4500 } },
  scoreLabel = "POINTS",
  unlockCost = 9,
  achievements = {
    { id = "first", name = "FIRST WATER", desc = "Haul up your first bucket of water." },
    { id = "brim", name = "BRIMMING", desc = "Deliver a bucket over 9.5 litres." },
    { id = "catch", name = "QUICK HANDS", desc = "Catch the handle mid-fall." },
    { id = "seven", name = "SEVEN NIGHTS", desc = "Draw water for all seven nights." },
    { id = "deep", name = "THE BOTTOM OF IT", desc = "Draw water from 60 metres down." },
  },
  challenges = {
    { id = "nopawl", name = "NO PAWL", desc = "The pawl is broken. Grip alone.", mode = "standard", difficulty = 2, goal = 1500, reward = 3, cost = 2 },
    { id = "leaky", name = "LEAKY BUCKET", desc = "The only bucket leaks. Be quick.", mode = "standard", difficulty = 2, goal = 1500, reward = 2, cost = 2 },
    { id = "lastlight", name = "LAST LIGHT", desc = "Endless. The lantern is failing.", mode = "endless", difficulty = 3, goal = 1200, reward = 3, cost = 3 },
  },
  records = {
    { "litres", "Water drawn", function(v) return v .. " L" end },
    { "deepest", "Deepest water", function(v) return v > 0 and (v .. " m") or "-" end },
    { "nights", "Nights survived" },
    { "slips", "Grip slips" },
  },
  drawIcon = function(cx, cy)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(cx - 22, cy - 22, 44, 44)
    gfx.setColor(gfx.kColorWhite)
    -- roof and posts
    gfx.fillTriangle(cx - 18, cy - 10, cx + 18, cy - 10, cx, cy - 20)
    gfx.fillRect(cx - 15, cy - 10, 3, 18)
    gfx.fillRect(cx + 12, cy - 10, 3, 18)
    -- drum and handle
    gfx.fillRect(cx - 12, cy - 6, 24, 5)
    gfx.drawLine(cx + 15, cy - 4, cx + 19, cy - 4)
    gfx.drawLine(cx + 19, cy - 4, cx + 19, cy + 1)
    -- rope down into the mouth
    gfx.drawLine(cx, cy - 1, cx, cy + 12)
    -- well head ring
    gfx.fillRect(cx - 17, cy + 8, 34, 7)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(cx - 17, cy + 11, cx + 17, cy + 11)
    for x = -13, 13, 8 do gfx.drawLine(cx + x, cy + 8, cx + x, cy + 11) end
    for x = -9, 13, 8 do gfx.drawLine(cx + x, cy + 11, cx + x, cy + 15) end
    gfx.fillRect(cx - 11, cy + 8, 22, 3)
    -- two eyes in the dark
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(cx - 6, cy + 18, 2, 2)
    gfx.fillRect(cx + 3, cy + 18, 2, 2)
  end,
})

------------------------------------------------------------------------
-- small helpers
------------------------------------------------------------------------
-- integer hash for procedural wall features (no allocation)
local function ihash(a, b)
  local h = (a * 374761393 + b * 668265263) & 0x7fffffff
  h = ((h ~ (h >> 13)) * 1274126177) & 0x7fffffff
  return h ~ (h >> 16)
end

------------------------------------------------------------------------
-- lifecycle
------------------------------------------------------------------------
function Well:enter(params)
  local d = self.difficulty
  local cid = self.params.challengeId
  self.tut = self.mode == "tutorial"
  self.gripK = self.tut and 1.25 or (d == 1 and 1 or (d == 2 and 0.93 or 0.86))
  self.fatigueK = self.tut and 0.5 or (d == 1 and 1 or (d == 2 and 1.2 or 1.4))
  self.depthK = (d == 3) and 1.12 or 1
  self.noPawl = cid == "nopawl"
  self.leaky = cid == "leaky"
  self.lastLight = cid == "lastlight"

  self.anim = 0
  self.score = 0
  self.litres = 0
  self.night = 1
  self.nightsDone = 0
  self.nightLitres = 0
  self.spares = self.leaky and 1 or 3
  self.delivered = 0
  self.descent = 0
  self.depthRecord = 0
  self.oil = 150
  self.findsSeen = 0
  self.hdrKey, self.hdrStr = -1, ""
  self.msg, self.msgT = nil, 0
  self.cardT = 0
  self.cardA, self.cardB = "", ""
  self.cin = 0
  self.hint = nil

  -- particles: 1 drop, 2 splash, 3 grit
  self.MAXP = 40
  self.pk, self.px, self.py, self.pvx, self.pvy, self.pl = {}, {}, {}, {}, {}, {}
  for i = 1, self.MAXP do self.pk[i] = 0 self.px[i] = 0 self.py[i] = 0 self.pvx[i] = 0 self.pvy[i] = 0 self.pl[i] = 0 end
  self.pNext = 1
  -- scheduled sounds (echo/splash delayed by the depth of the shaft)
  self.sdT, self.sdK, self.sdV = { 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0 }

  self.tracker = Crank.Tracker.new()
  self.jiggle = Crank.Jiggle.new(55)
  self.clickDetent = Crank.Detent.new(TEETH)
  self.creakDetent = Crank.Detent.new(3)

  self.humDrone = Audio.Hum.new(Audio.SINE)
  self.humSpin = Audio.Hum.new(Audio.SAW)
  self.humWind = Audio.Hum.new(Audio.NOISE)

  self.pawlWear = 0
  self.pawlBroken = self.noPawl
  self.stamina = 1
  self.slips = 0

  if self.tut then
    self.state = "play"
    self:startNight(1)
    self:setupCoach()
  elseif self.mode == "endless" then
    self.state = "play"
    self:startDescent(0)
  else
    self.state = "read"
    self.readText = STORY[0]
    self.readTitle = "NIGHT I"
    self.readChars = 0
    self.pendingNight = 1
    self:startNight(1)
    self.state = "read"
  end
end

function Well:exit()
  self.humDrone:stop()
  self.humSpin:stop()
  self.humWind:stop()
end

-- a fresh bucket hanging at the lip
function Well:resetBucket()
  self.y, self.vy = 0.45, 0
  self.b, self.vb = 0.45, 0
  self.h = self.y
  self.gripped = true
  self.letgo = false
  self.slipAcc = 0
  self.fill = 0
  self.cracks = self.leaky and 0.35 or 0
  self.pawl = false
  self.q, self.qv = 0, 0
  self.descended = false
  self.wet = false
  self.inWater = false
  self.haulSpill = 0
  self.maxFill = 0
  self.fHand = 0
  self.effort = 0
  self.freeV = 0
  self.wasFree = false
  self.caughtFree = false
  self.dripT = 1
  self.echo = 0
  self.echoFlash = 0
  self.tug, self.tugT, self.tugF, self.tugTw, self.tugCool = "none", 0, 0, 0, 8
  self.pawlKnock = 0
  self.camY = nil
  self.lastVb = 0
  self.accB = 0
end

function Well:startNight(n)
  self.night = n
  self.nightLitres = 0
  local W
  if self.tut then
    W = 9
    self.quota = 5
    self.candle = 0
    self.lastW = 9
  else
    W = NIGHT_DEPTH[n] * self.depthK + self.rng:between(-0.8, 0.8)
    self.quota = NIGHT_QUOTA[n]
    local trips = math.ceil(self.quota / 8.5)
    self.candle = trips * (0.9 * W + 9) * 1.9 + 25
    self.candleMax = self.candle
    self.lastW = (n == 1) and 12 or NIGHT_DEPTH[n - 1] * self.depthK
  end
  self.W = W
  self.ropeLen = W + 7
  self.strange = n
  self.lampR0 = self.tut and 64 or (66 - n * 2.5)
  self.moonK = clamp(1.05 - n * 0.12, 0.2, 1)
  self:resetBucket()
end

function Well:startDescent(k)
  self.descent = k
  local W = (15 + k * 5) * self.depthK + self.rng:between(-1.5, 1.5)
  self.lastW = (k == 0) and 12 or self.W
  self.W = W
  self.ropeLen = W + 8
  self.strange = min(7, 2 + k // 2)
  self.night = self.strange
  self.lampR0 = self.lastLight and 48 or (64 - self.strange * 2)
  self.moonK = clamp(0.9 - k * 0.08, 0.15, 1)
  -- the same bucket goes down again: its cracks, the pawl's wear and your
  -- tired hands carry over from descent to descent
  local keepWear, keepSt, keepCr = self.pawlWear, self.stamina, self.cracks
  self:resetBucket()
  self.pawlWear, self.stamina = keepWear or 0, keepSt or 1
  if k > 0 and keepCr then self.cracks = max(self.cracks, keepCr) end
end

function Well:setupCoach()
  local s = self
  self.coach = UI.Coach.new({
    { text = "Crank COUNTER-clockwise to lower the bucket into the dark. Its weight wants to run.",
      check = function() return s.b > 2.5 end },
    { text = "Now stop. Your hand holds the handle: the GRIP bar shows the strain. Hold still.",
      check = function() return s.gripped and s.tracker.idle > 1.2 and s.b > 2 and not s.inWater end },
    { text = "Lower on. Drops fall from the bucket: the echo comes quicker near water. Ease down gently.",
      check = function() return s.inWater end },
    { text = "It floats. Take up any SLACK, then JIGGLE: tiny quick back-and-forth cranks tip it to fill.",
      check = function() return s.fill > 0.85 end },
    { text = "Haul CLOCKWISE, smooth and steady. Jerky cranking sloshes the water out.",
      check = function() return s.b < s.W - 3 and s.fill > 0.3 end },
    { text = "Press A: the PAWL drops into the ratchet. Now let go of the crank and rest your grip.",
      check = function() return s.pawl and s.tracker.idle > 1.2 end, hold = 0.5 },
    { text = "The pawl clicks as you haul and stops a fall. Bring the bucket all the way up.",
      check = function() return s.delivered > 0 end },
    { text = "Press A to lift the pawl and lower again. Then HOLD B: you let go - the handle spins free!",
      check = function() return s.letgo and s.vy > 2.2 end },
    { text = "Release B and crank CLOCKWISE hard: friction catches the handle. Or tap A for the pawl.",
      check = function() return s.caughtFree end },
  }, { y = 176, h = 46, anchor = "bottom" })
end

------------------------------------------------------------------------
-- input
------------------------------------------------------------------------
function Well:cranked(change) self.cin = self.cin + change end

function Well:buttonDown(b)
  if self.state == "read" then
    if b == Input.A then
      if self.readChars < #self.readText then
        self.readChars = #self.readText
      else
        self:closeRead()
      end
    end
    return
  end
  if self.state ~= "play" then return end
  if b == Input.A then
    if self.pawlBroken then
      Audio.sfx.denied()
      self:say(self.noPawl and "THE PAWL IS BROKEN" or "THE PAWL HAS SNAPPED", 1.2)
      return
    end
    self.pawl = not self.pawl
    if self.pawl then
      Audio.sfx.clack(0.5)
      if self.vy > 0.25 then self:pawlCatch() end
    else
      Audio.sfx.click(0.4)
      Audio.play(Audio.TRIANGLE, 520, 0.2, 0.05)
    end
  end
end

function Well:closeRead()
  if self.readDone then
    self.state = "done"
    return
  end
  self.state = "play"
  Audio.sfx.menuSelect()
end

-- the pawl slams into a turning ratchet
function Well:pawlCatch()
  local v = self.vy
  self.vy = 0
  local wear = 0.05 + 0.045 * v * v
  if self.tut then wear = 0 end
  self.pawlWear = self.pawlWear + wear
  self.accB = self.accB + v * 12        -- the jolt reaches the water
  self:shake(min(8, 1 + v * 1.2))
  Audio.sfx.clank(min(1, 0.4 + v * 0.1))
  Audio.sfx.thud(min(1, 0.3 + v * 0.1))
  if self.wasFree and v > 1 then self:caught(v) end
  if self.pawlWear >= 1 or (v > 7 and not self.tut) then
    self.pawlBroken = true
    self.pawl = false
    Audio.sfx.snap(0.8)
    self:say("THE PAWL SNAPPED", 2)
    self:shake(6)
    for _ = 1, 6 do self:spawnP(3, self.b - 1, self.rng:between(-1, 1), -1, 1.2) end
  end
end

function Well:caught(v)
  self.caughtFree = true
  self.wasFree = false
  if v > 4 and not self.tut then self:award("catch") end
  self:say("CAUGHT IT", 0.9)
end

------------------------------------------------------------------------
-- particles & delayed sounds
------------------------------------------------------------------------
function Well:spawnP(kind, y, vx, vy, life)
  local i = self.pNext
  self.pNext = i % self.MAXP + 1
  self.pk[i], self.px[i], self.py[i], self.pvx[i], self.pvy[i], self.pl[i] = kind, 0, y, vx, vy, life
end

function Well:schedule(kind, delay, vol)
  for i = 1, #self.sdT do
    if self.sdK[i] == 0 then
      self.sdK[i], self.sdT[i], self.sdV[i] = kind, delay, vol
      return
    end
  end
end

function Well:updateScheduled(dt)
  for i = 1, #self.sdT do
    local k = self.sdK[i]
    if k ~= 0 then
      self.sdT[i] = self.sdT[i] - dt
      if self.sdT[i] <= 0 then
        self.sdK[i] = 0
        local v = self.sdV[i]
        if k == 1 then       -- the drop lands: plip, with a hollow echo
          Audio.play(Audio.SINE, 1250, 0.2 * v, 0.03, 0.001, 0.05, 0, 0.04)
          Audio.play(Audio.SINE, 830, 0.08 * v, 0.05, 0.001, 0.08, 0, 0.1, 0.09)
          self.echoFlash = 1
        elseif k == 2 then   -- splash reaches your ears
          Audio.sfx.splash(v)
          Audio.play(Audio.SINE, 70, v * 0.5, 0.2, 0.001, 0.3, 0, 0.1)
        elseif k == 3 then   -- whisper
          Audio.play(Audio.NOISE, 3200 + v * 900, 0.05, 0.9, 0.4, 0.5, 0.3, 0.4)
          Audio.play(Audio.NOISE, 2100 + v * 600, 0.04, 0.7, 0.3, 0.4, 0.2, 0.3, 0.5)
        elseif k == 4 then   -- heartbeat
          Audio.play(Audio.SINE, 48, 0.45, 0.08, 0.001, 0.12, 0, 0.05)
          Audio.play(Audio.SINE, 44, 0.35, 0.08, 0.001, 0.12, 0, 0.05, 0.22)
        end
      end
    end
  end
end

function Well:updateParticles(dt)
  for i = 1, self.MAXP do
    local k = self.pk[i]
    if k ~= 0 then
      local l = self.pl[i] - dt
      self.pl[i] = l
      if l <= 0 then
        self.pk[i] = 0
      else
        self.pvy[i] = self.pvy[i] + G * dt * (k == 2 and 0.8 or 1)
        self.px[i] = self.px[i] + self.pvx[i] * dt
        self.py[i] = self.py[i] + self.pvy[i] * dt
        if k ~= 2 and self.py[i] > self.W then self.pk[i] = 0 end
        if k == 2 and self.pvy[i] > 0 and self.py[i] > self.W then self.pk[i] = 0 end
      end
    end
  end
end

function Well:say(m, t) self.msg, self.msgT = m, t or 1.5 end

------------------------------------------------------------------------
-- simulation
------------------------------------------------------------------------
function Well:gripMax()
  return GRIP0 * self.gripK * (0.5 + 0.5 * self.stamina)
end

function Well:update(dt)
  self.anim = self.anim + dt
  local c = self.cin
  self.cin = 0
  self.tracker:feed(c)
  self.tracker:update(dt)
  if self.msgT > 0 then self.msgT = self.msgT - dt end
  if self.cardT > 0 then self.cardT = self.cardT - dt end
  self.echoFlash = max(0, self.echoFlash - dt * 2)
  self:updateScheduled(dt)
  self:updateParticles(dt)

  if self.state == "read" then
    self.readChars = min(#self.readText, self.readChars + dt * 38)
    if floor(self.readChars) % 4 == 0 and self.readChars < #self.readText then Audio.sfx.type() end
    self:quiet()
    return
  end
  if self.finished or self.state == "done" then
    self:quiet()
    if self.state == "done" and not self.finished then self:endRun(true) end
    return
  end

  if self.state == "deliver" or self.state == "lost" then
    self.stateT = self.stateT - dt
    self.stamina = min(1, self.stamina + dt * 0.15)
    if self.stateT <= 0 then self:afterPause() end
    self:ambience(dt)
    self:timers(dt)
    return
  end

  self:physics(dt, c)
  self:ambience(dt)
  self:timers(dt)
end

function Well:quiet()
  self.humSpin:set(0, 0)
  self.humDrone:set(0, 0)
  self.humWind:set(0, 0)
end

function Well:timers(dt)
  if self.tut or self.finished then return end
  if self.mode == "standard" then
    self.candle = self.candle - dt
    if self.candle <= 0 then
      self.candle = 0
      self:say("THE CANDLE IS OUT", 2)
      self:endRun(false, "candle")
    end
  else
    self.oil = self.oil - dt
    if self.oil <= 0 then
      self.oil = 0
      self:endRun(false, "oil")
    end
  end
end

function Well:physics(dt, c)
  local hs = dt / SUB
  local dh = -c / 360 * CIRC           -- hand movement in rope metres (down +)
  local vh = dh / dt
  self.letgo = Input.held(Input.B)
  self.jiggle:feed(c, dt)

  -- taking hold of the handle again
  if self.letgo then
    if self.gripped then
      self.gripped = false
      Audio.sfx.whoosh(0.2)
    end
  elseif not self.gripped then
    local rel = self.vy - vh
    if (abs(self.vy) < 0.35 and c ~= 0) or (c ~= 0 and abs(rel) < 0.7) then
      self.gripped = true
      self.h = self.y
      self.slipAcc = 0
      if self.wasFree and self.freeV > 1 then self:caught(self.freeV) end
      self.wasFree = false
      Audio.sfx.thunk(0.4)
    end
  end
  if not self.gripped and self.vy > 1.2 then
    self.wasFree = true
    self.freeV = max(self.freeV, self.vy)
  end
  if self.gripped then self.freeV = 0 end

  -- hand relaxes onto the pawl when you stop cranking
  if self.gripped and self.pawl and c == 0 and self.tracker.idle > 0.2 then self.h = self.y end

  local gmax = self:gripMax()
  local W = self.W
  local fHandPeak, fHandSum = 0, 0
  local waterF = self.fill * CAP
  local mB = BUCKET_KG + waterF
  local vb0 = self.vb
  local subFrac = 0
  local tugF = 0
  if self.tug == "pull" then tugF = self.tugF * (0.75 + 0.25 * sin(self.anim * 9)) end
  if self.tug == "warn" and self.tugTw > 0 then tugF = 2.5 end
  for _ = 1, SUB do
    if self.gripped then self.h = self.h + dh / SUB end
    local y, vy, b, vb = self.y, self.vy, self.b, self.vb
    local hanging = min(y, b)
    if hanging < 0 then hanging = 0 end
    local st = b - y
    local T = 0
    if st > 0 then T = max(0, KR * st + CR * (vb - vy)) end
    local fh = 0
    if self.gripped then
      fh = KP * (y - self.h) + KD * (vy - vh)
    elseif not self.letgo and c > 0 and vy > 0 then
      -- cranking hard against the spinning handle: friction brake
      fh = min(gmax * 0.9, 7 * (vy - vh))
    end
    local ff = (vy > 0.02 and 0.3 or (vy < -0.02 and -0.3 or 0)) + 0.1 * vy
    local mD = MD + ROPE_KG * y
    local aD = (ROPE_KG * hanging + T - fh - ff) * G / mD
    -- bucket: weight, rope, buoyancy, water drag, and whatever is down there
    local sub = clamp((b + BUCKET_H - W) / BUCKET_H, 0, 1)
    local buoy = sub * 13
    local mEff = mB + sub * 3
    local aB = (mB - T - buoy + tugF * (sub > 0 and 1 or 0.6)) * G / mEff
    vy = vy + aD * hs
    vb = vb + aB * hs
    -- quadratic water/air drag, integrated implicitly so it never overshoots
    vb = vb / (1 + (sub * 25 + 0.02) * abs(vb) * G / mEff * hs)
    if self.pawl and vy > 0 then
      if vy > 0.6 then self.vy = vy self:pawlCatch() vy = self.vy end
      vy = 0
    end
    y = y + vy * hs
    b = b + vb * hs
    -- the handle stalls when the bucket is up against the windlass
    if y < 0.4 then
      y = 0.4
      if vy < 0 then vy = 0 end
      if self.gripped and self.h < y - 0.08 then self.h = y - 0.08 end
    end
    if self.pawl and self.gripped and self.h > y + 0.08 then self.h = y + 0.08 end
    if y > self.ropeLen then
      y = self.ropeLen
      if vy > 3.5 and not self.tut then
        self.y, self.vy, self.b, self.vb = y, 0, b, vb
        self:loseBucket("THE KNOT TORE FREE")
        return
      end
      if vy > 0 then vy = 0 self:shake(3) Audio.sfx.thud(0.6) end
    end
    if b < 0.4 then b = 0.4 if vb < 0 then vb = 0 end end
    if b > W + 5 then b = W + 5 if vb > 0 then vb = 0 end end
    self.y, self.vy, self.b, self.vb = y, vy, b, vb
    subFrac = sub
    if self.gripped then
      fHandSum = fHandSum + fh
      if abs(fh) > fHandPeak then fHandPeak = abs(fh) end
    end
  end
  self.fHand = fHandSum / SUB
  self.effort = abs(self.fHand) / GRIP0

  -- grip: sustained overload makes the handle slip from your hand
  if self.gripped then
    local over = abs(self.fHand) / gmax
    if over > 1 then
      self.slipAcc = self.slipAcc + (over - 1) * dt * 5 + dt * 1.3
    else
      self.slipAcc = max(0, self.slipAcc - dt * 2)
    end
    if self.slipAcc >= 1 then self:slip() end
  end
  -- fatigue and recovery
  if self.effort > 0.28 then
    self.stamina = self.stamina - dt * (self.effort - 0.28) * 0.07 * self.fatigueK
  elseif self.effort < 0.15 then
    self.stamina = self.stamina + dt * 0.1
  end
  self.stamina = clamp(self.stamina, 0, 1)

  -- water: impact, floating, filling, leaking, sloshing
  local inW = subFrac > 0.02
  -- hanging just clear of the water, a jiggle still dips the lip in
  local nearW = not inW and (self.b + BUCKET_H > self.W - 0.2) and self.fill < 1
  if nearW and self.jiggle.energy > 0.3 then self.fill = min(1, self.fill + dt * self.jiggle.energy * 0.2) end
  if inW and not self.inWater then
    self:hitWater(vb0)
    if self.state ~= "play" then return end
  end
  self.inWater = inW
  if self.b > 2.5 then self.descended = true end
  if inW then
    self.wet = true
    local slack = self.y - self.b
    local e = self.jiggle.energy
    if slack < 0.8 and e > 0.05 then
      self.fill = self.fill + dt * e * (self.tut and 0.7 or 0.5)
    end
    if subFrac >= 1 then self.fill = self.fill + dt * 0.25 end
    self.fill = min(1, self.fill)
    self.maxFill = max(self.maxFill, self.fill)
    self.q, self.qv = self.q * 0.9, self.qv * 0.9
    self.haulSpill = 0
  else
    if self.cracks > 0 and self.fill > 0 then
      local leak = dt * self.cracks * 0.05
      self.fill = max(0, self.fill - leak)
      if self.rng:chance(dt * 6 * self.cracks) then self:spawnP(1, self.b + BUCKET_H, 0, 0.5, 3) end
    end
    -- slosh: a damped oscillator driven by the bucket's acceleration
    local acc = (self.vb - self.lastVb) / dt + self.accB
    self.accB = 0
    local w0 = 6
    self.qv = self.qv + (-w0 * w0 * self.q - 2 * 0.22 * w0 * self.qv - acc * 7) * dt
    self.q = self.q + self.qv * dt
    local thr = 1 + (1 - self.fill) * 3
    if self.fill > 0.05 and abs(self.q) > thr then
      local spill = min(self.fill, (abs(self.q) - thr) * dt * 1.4 + dt * 0.08)
      self.fill = self.fill - spill
      self.haulSpill = self.haulSpill + spill * CAP
      Audio.play(Audio.NOISE, 1800, 0.12, 0.08, 0.005, 0.08)
      for _ = 1, 2 do self:spawnP(1, self.b + 0.1, self.rng:between(-1.4, 1.4), self.rng:between(-1.5, 0.5), 3) end
    end
  end
  self.lastVb = self.vb

  -- sounds of the mechanism
  local turned = -dh
  if not self.gripped then turned = -self.vy * dt end
  if self.pawl and turned > 0 then
    if self.clickDetent:feed(turned / CIRC * 360) ~= 0 then Audio.sfx.tick(1150, 0.16) end
  else
    self.clickDetent:feed(turned / CIRC * 360)
  end
  if self.creakDetent:feed(turned / CIRC * 360) ~= 0 and abs(turned) > 0.001 then
    Audio.sfx.creak(0.05 + min(0.2, (BUCKET_KG + self.fill * CAP) * 0.012))
  end
  if not self.gripped and abs(self.vy) > 0.5 then
    self.humSpin:set(90 + abs(self.vy) * 60, min(0.22, abs(self.vy) * 0.035))
    if self.rng:chance(dt * abs(self.vy) * 2) then Audio.sfx.tick(700, 0.1) end
  else
    self.humSpin:set(0, 0)
  end

  -- the echo sounder: a drop falls from the wet bucket, its plip comes back
  self.dripT = self.dripT - dt
  if self.dripT <= 0 then
    self.dripT = 1.5
    if not self.inWater and self.b < self.W - 0.5 then
      local dist = self.W - (self.b + BUCKET_H)
      self.echo = dist / 22 + dist * dist / 2400
      self:schedule(1, self.echo, clamp(1.2 - dist / 60, 0.3, 1))
      self:spawnP(1, self.b + BUCKET_H, 0, 0, 4)
      Audio.play(Audio.SINE, 2400, 0.04, 0.01, 0.001, 0.02, 0, 0.01)
    end
  end

  -- things below
  self:updateTug(dt)

  -- delivery at the top
  if self.descended and self.b <= 0.5 and self.y <= 0.5 then self:deliver() end
end

function Well:slip()
  self.gripped = false
  self.slipAcc = 0
  self.slips = self.slips + 1
  if not self.tut then self:statAdd("slips", 1) end
  self:say("GRIP SLIPS!", 1.4)
  self:shake(4)
  Audio.sfx.snap(0.4)
  Audio.sfx.whoosh(0.35)
  self.stamina = max(0, self.stamina - 0.08)
end

function Well:hitWater(v)
  local depth = self.W
  local delay = depth / 45
  local vol = clamp(0.25 + v * 0.1, 0.2, 1)
  self:schedule(2, delay, vol)
  for _ = 1, min(10, 3 + floor(v * 2)) do
    self:spawnP(2, self.W - 0.05, self.rng:between(-2, 2), -self.rng:between(1, 2.5 + v), 1.2)
  end
  if v > 4.2 and not self.tut then
    local dmg = (v - 4.2) * 0.3
    self.cracks = self.cracks + dmg
    self:shake(3)
    if self.cracks >= 1 then
      self:loseBucket("BUCKET SHATTERED")
      return
    end
    self:say("THE BUCKET CRACKED", 1.6)
    Audio.play(Audio.NOISE, 3500, 0.3, 0.05, 0.001, 0.06, 0, 0.02, delay)
  end
end

function Well:updateTug(dt)
  if self.tut then return end
  local n = self.strange
  if self.tug == "none" then
    self.tugCool = self.tugCool - dt
    local deep = self.b > self.W * 0.45
    if n >= 3 and deep and self.tugCool <= 0 and self.rng:chance(dt * min(0.09, 0.02 * (n - 2))) then
      self.tug = "warn"
      self.tugT = self.rng:between(1.2, 2.2)
      self.tugTw = 0
      self.tugNext = 0.3
      self:say("A TOUCH ON THE ROPE", 1.6)
    end
  elseif self.tug == "warn" then
    self.tugT = self.tugT - dt
    self.tugTw = max(0, self.tugTw - dt)
    self.tugNext = self.tugNext - dt
    if self.tugNext <= 0 then
      self.tugNext = self.rng:between(0.3, 0.6)
      self.tugTw = 0.12
      Audio.sfx.thud(0.35)
      Audio.play(Audio.NOISE, 5000, 0.08, 0.1, 0.001, 0.05, 0, 0.02)
      self:shake(1)
    end
    if self.tugT <= 0 then
      self.tug = "pull"
      self.tugT = self.rng:between(1.2, 2.4)
      self.tugF = (7 + n * 2.2) * (self.difficulty == 3 and 1.2 or 1)
      Audio.play(Audio.SAW, 55, 0.3, self.tugT, 0.05, 0.2, 0.8, 0.3)
      self:say("IT PULLS! HOLD ON", 1.6)
      self:shake(3)
    end
  elseif self.tug == "pull" then
    self.tugT = self.tugT - dt
    if self.rng:chance(dt * 4) then self:shake(1.5) end
    if self.tugT <= 0 then
      self.tug = "none"
      self.tugCool = self.rng:between(14, 24)
      Audio.play(Audio.NOISE, 900, 0.1, 0.4, 0.1, 0.3)
    end
  end
end

function Well:deliver()
  self.cardP = 0
  local litres = self.fill * CAP
  local slam = self.vb < -1.8 or self.vy < -1.8
  self.y, self.vy, self.b, self.vb = 0.45, 0, 0.45, 0
  self.h = self.y
  if slam then
    litres = litres * 0.6
    self:shake(5)
    Audio.sfx.clank(0.8)
    if not self.tut then self.cracks = self.cracks + 0.2 end
    self:say("SLAMMED THE LIP", 1.4)
  end
  self.descended = false
  self.fill = 0
  self.state = "deliver"
  self.stateT = litres >= 0.5 and 2.4 or 0.8
  Audio.sfx.thunk(0.5)
  if litres < 0.5 then
    self:say("EMPTY", 1)
    return
  end
  Audio.play(Audio.NOISE, 700, 0.25, 0.9, 0.05, 0.6, 0.3, 0.4)
  self.delivered = self.delivered + 1
  local L10 = floor(litres * 10)
  self.litres = self.litres + litres
  self.nightLitres = self.nightLitres + litres
  local pts
  if self.mode == "endless" then pts = floor(litres * self.W) else pts = floor(litres * 10) end
  local clean = self.haulSpill < 0.3 and litres >= 8
  if clean then pts = pts + 25 end
  -- what else came up
  local find = nil
  if not self.tut then
    local nf = NIGHT_FIND[self.night]
    if self.mode == "standard" and nf and self.nightLitres >= self.quota and self.foundNight ~= self.night then
      find = nf
      self.foundNight = self.night
    elseif self.rng:chance(0.4) then
      local tier = self.strange <= 2 and 1 or (self.strange <= 4 and 2 or 3)
      find = FINDS[tier][self.rng:range(1, #FINDS[tier])]
    end
  end
  if find then pts = pts + find[2] end
  if not self.tut then
    self.score = self.score + pts
    self:statAdd("litres", floor(litres + 0.5))
    self:award("first")
    if litres >= 9.5 then self:award("brim") end
    if litres >= 3 then self:statMax("deepest", floor(self.W)) end
    if self.mode == "endless" and litres >= 3 then
      self.depthRecord = max(self.depthRecord, floor(self.W))
      if self.W >= 60 then self:award("deep") end
      self.oil = self.oil + 40
    end
  end
  self.cardA = U.cached("well_l", "%.1f L", L10 / 10)
  self.cardB = find and find[1] or (clean and "Not a drop spilled." or "Water.")
  self.cardP = pts
  self.cardT = self.stateT
  self.cracks = self.leaky and max(0.35, self.cracks) or self.cracks
end

function Well:afterPause()
  if self.state == "lost" then
    if self.spares <= 0 then self:endRun(false, "buckets") return end
    self.state = "play"
    self:resetBucket()
    return
  end
  self.state = "play"
  if self.tut then return end
  if self.mode == "endless" then
    if self.cardP and self.cardP > 0 then
      self:startDescent(self.descent + 1)
      self:say("DEEPER", 1.6)
    end
    self.cardP = 0
    return
  end
  if self.nightLitres >= self.quota then
    self.nightsDone = self.night
    self.score = self.score + 150 * self.night + floor(self.candle)
    self:statMax("nights", self.night)
    Audio.sfx.bell(440, 0.3)
    if self.night >= NIGHTS then
      self:award("seven")
      self.score = self.score + 1000
      self.state = "read"
      self.readText = ENDING
      self.readTitle = "DAWN"
      self.readChars = 0
      self.readDone = true
      return
    end
    self.state = "read"
    self.readText = STORY[self.night]
    self.readTitle = "NIGHT " .. ROMAN[self.night + 1]
    self.readChars = 0
    self:startNight(self.night + 1)
    self.state = "read"
  end
end

function Well:loseBucket(why)
  self.spares = self.spares - 1
  self.state = "lost"
  self.stateT = 2.6
  self.gripped = true
  self.pawl = false
  self:say(why, 2.4)
  self:shake(6)
  self:flash(2)
  Audio.sfx.snap(0.7)
  Audio.sfx.fail()
  if self.mode == "standard" then self.candle = max(1, self.candle - 12) end
  if self.tut then self.spares = 3 end
end

function Well:endRun(ok, why)
  if self.finished then return end
  local lines
  local title
  local success
  if self.mode == "endless" then
    title = (why == "oil") and "THE LAMP WENT OUT" or "THE WELL KEPT IT"
    success = self.delivered > 0
    lines = {
      string.format("Water drawn: %.1f L", self.litres),
      "Deepest water: " .. self.depthRecord .. " m",
      "Buckets hauled: " .. self.delivered,
    }
  else
    success = self.nightsDone >= 1
    if ok then
      title = "SEVEN NIGHTS"
    elseif why == "candle" then
      title = "THE CANDLE WENT OUT"
    else
      title = "THE WELL KEPT IT"
    end
    lines = {
      "Nights survived: " .. self.nightsDone .. "/7",
      string.format("Water drawn: %.1f L", self.litres),
      "Grip slips: " .. self.slips,
    }
    if not ok then lines[#lines + 1] = "I did not stay to see what was on the rope." end
  end
  if success then Audio.sfx.success() else Audio.sfx.fail() end
  self:quiet()
  self:finish({ success = success, score = self.score, title = title, lines = lines, delay = 1.8 })
end

function Well:ambience(dt)
  local depth = self.b
  local n = self.strange
  -- wind over the mouth, the drone of the deep
  self.humWind:set(420, clamp(0.05 - depth * 0.004, 0, 0.05))
  self.humDrone:set(62 - n * 2 + sin(self.anim * 0.3) * 2, clamp(depth / 60, 0, 0.14) + n * 0.006)
  self.ambT = (self.ambT or 3) - dt
  if self.ambT <= 0 then
    self.ambT = self.rng:between(4, 9)
    if n >= 3 and not self.tut and depth > 6 then
      if self.rng:chance(0.5) then self:schedule(3, 0.1, self.rng:float()) end
      if n >= 4 and self.rng:chance(0.4) then
        for k = 0, 5 do Audio.play(Audio.NOISE, 6000, 0.05, 0.02, 0.001, 0.02, 0, 0.01, k * 0.07) end
      end
      if n >= 5 and depth > self.W * 0.5 then self:schedule(4, 0.2, 1) self:schedule(4, 1.2, 1) end
    end
  end
end

------------------------------------------------------------------------
-- drawing: the windlass close-up (left)
------------------------------------------------------------------------
local insetBg = nil
local function buildInsetBg()
  if insetBg then return insetBg end
  insetBg = Art.cached("well_inset", 148, 94, function()
    -- night sky with stars
    gfx.setPattern(Art.pat.gray87)
    gfx.fillRect(0, 0, 148, 94)
    gfx.setColor(gfx.kColorWhite)
    local r = U.rng(1010)
    for _ = 1, 22 do gfx.drawPixel(r:range(2, 146), r:range(2, 60)) end
    -- the near post of the windlass frame, woodcut grain
    gfx.fillRect(AX - 9, 6, 18, 88)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(AX - 9, 6, 18, 88)
    for yy = 10, 90, 6 do gfx.drawLine(AX - 6, yy, AX - 6 + (yy % 12 == 4 and 8 or 4), yy + 2) end
    gfx.drawLine(AX + 4, 12, AX + 4, 90)
    -- the stone well head in the foreground
    gfx.setPattern(Art.pat.bricks)
    gfx.fillRect(0, 80, 148, 14)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(0, 80, 148, 80)
    gfx.drawLine(0, 79, 148, 79)
  end, gfx.kColorBlack)
  return insetBg
end

function Well:drawInset()
  gfx.setClipRect(0, 18, 149, 94)
  buildInsetBg():draw(0, 18)
  -- moon with its nightly phase
  local mx, my = 124, 36
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(mx, my, 9)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(mx - 4 - (1 - self.moonK) * 12, my - 1, 9)
  local ang = -self.y / CIRC * 360
  local ay = AY
  -- rope leaving the drum, with scrolling marks (knots every 5 m, chalk mark)
  local onDrum = clamp((self.ropeLen - self.y) / self.ropeLen, 0, 1)
  local drumR = 14 + floor(onDrum * 6)
  local rx = AX + drumR
  local slack = self.y - self.b
  gfx.setColor(gfx.kColorWhite)
  gfx.setLineWidth(2)
  if slack > 0.3 then
    local px, py = rx, ay
    for i = 1, 8 do
      local yy = ay + i * 6
      local xx = rx + sin(i * 1.3 + self.anim * 2) * min(4, slack * 2)
      gfx.drawLine(px, py, xx, yy)
      px, py = xx, yy
    end
  else
    gfx.drawLine(rx, ay, rx, 112)
  end
  gfx.setLineWidth(1)
  for p = 0, 50, 2 do
    local len = self.y - p / 10          -- rope coordinate measured from the bucket
    local k = len % 5
    if len > 0.2 and (k < 0.2) then gfx.setColor(gfx.kColorBlack) gfx.fillRect(rx - 2, ay + p, 4, 2) gfx.setColor(gfx.kColorWhite) end
    if abs(len - self.lastW) < 0.15 and not self.tut then
      gfx.setColor(gfx.kColorWhite) gfx.fillRect(rx - 3, ay + p - 1, 6, 3)
    end
  end
  -- ratchet wheel turning with the drum
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(AX, ay, 26)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawCircleAtPoint(AX, ay, 20)
  gfx.setLineWidth(3)
  for i = 0, TEETH - 1 do
    -- saw teeth: a steep face and a sloping back
    local a = rad(ang + i * 360 / TEETH)
    local a2 = rad(ang + i * 360 / TEETH + 20)
    local x1, y1 = AX + sin(a) * 25, ay - cos(a) * 25
    gfx.drawLine(AX + sin(a) * 20, ay - cos(a) * 20, x1, y1)
    gfx.drawLine(x1, y1, AX + sin(a2) * 20, ay - cos(a2) * 20)
  end
  gfx.setLineWidth(1)
  gfx.drawCircleAtPoint(AX, ay, drumR)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(AX, ay, 6)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(AX, ay, 3)
  -- the pawl on its pivot
  local px, py = AX + 30, ay - 30
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(px, py, 4)
  gfx.setLineWidth(4)
  if self.pawlBroken then
    gfx.drawLine(px, py, px + 2, py + 12)
  elseif self.pawl then
    gfx.drawLine(px, py, AX + 17, ay - 17)
  else
    gfx.drawLine(px, py, px - 10, py - 6)
  end
  gfx.setLineWidth(1)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(px, py, 2)
  -- crank arm and handle
  local ca = rad(ang)
  local hx, hy = AX + sin(ca) * 34, ay - cos(ca) * 34
  gfx.setColor(gfx.kColorWhite)
  gfx.setLineWidth(5)
  gfx.drawLine(AX, ay, hx, hy)
  gfx.setLineWidth(3)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawLine(AX, ay, hx, hy)
  gfx.setLineWidth(1)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(hx, hy, 6)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawCircleAtPoint(hx, hy, 6)
  -- your hand
  if self.gripped then
    local shake = (self.slipAcc > 0.3) and ((floor(self.anim * 30) % 2) * 2 - 1) or 0
    gfx.setColor(gfx.kColorWhite)
    gfx.setLineWidth(9)
    gfx.drawLine(hx + shake, hy, -20, 140)
    gfx.setLineWidth(5)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(hx + shake, hy, -20, 140)
    gfx.setLineWidth(1)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRoundRect(hx - 7 + shake, hy - 6, 14, 12, 4)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRoundRect(hx - 7 + shake, hy - 6, 14, 12, 4)
    gfx.drawLine(hx - 3 + shake, hy - 5, hx - 3 + shake, hy + 5)
    gfx.drawLine(hx + 1 + shake, hy - 5, hx + 1 + shake, hy + 5)
  else
    -- the hand flung back, open; the handle a blur
    local fx, fy = 22, 96
    gfx.setColor(gfx.kColorWhite)
    gfx.setLineWidth(9)
    gfx.drawLine(fx, fy, -20, 140)
    gfx.setLineWidth(1)
    gfx.fillCircleAtPoint(fx, fy, 6)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawCircleAtPoint(fx, fy, 6)
    for i = -2, 2 do gfx.drawLine(fx + i * 3, fy - 6, fx + i * 4, fy - 11) end
    if abs(self.vy) > 0.8 then
      gfx.setColor(gfx.kColorWhite)
      gfx.drawArc(AX, ay, 34, ang - 90, ang)
      gfx.drawArc(AX, ay, 31, ang - 60, ang)
    end
  end
  gfx.clearClipRect()
  gfx.setColor(gfx.kColorBlack)
end

function Well:drawGauges()
  local y0 = 112
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(0, y0, 149, 110)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(147, 18, 3, 204)
  gfx.drawLine(0, y0, 148, y0)
  -- GRIP: your effort vs the slip line (which creeps left as you tire)
  UI.text("GRIP", 4, y0 + 3)
  local gx, gw = 46, 96
  local lim = self:gripMax() / 40
  local ef = abs(self.fHand) / 40
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(gx, y0 + 5, gw, 11)
  gfx.setPattern(Art.pat.hatch)
  gfx.fillRect(gx + floor(gw * min(1, lim)), y0 + 5, gw - floor(gw * min(1, lim)), 11)
  gfx.setColor(gfx.kColorBlack)
  if self.gripped then gfx.fillRect(gx + 2, y0 + 7, floor((gw - 4) * min(1, ef)), 7) end
  gfx.drawRect(gx, y0 + 5, gw, 11)
  gfx.fillRect(gx + floor(gw * min(1, lim)) - 1, y0 + 3, 2, 15)
  if not self.gripped then UI.text("LET GO", gx + gw / 2, y0 + 3, "center", UI.bold) end
  -- LOAD
  local load = BUCKET_KG + self.fill * CAP + ROPE_KG * min(self.y, self.b)
  if self.inWater then load = ROPE_KG * self.y + max(0, (BUCKET_KG + self.fill * CAP) - 13 * clamp((self.b + BUCKET_H - self.W) / BUCKET_H, 0, 1)) end
  UI.text("LOAD", 4, y0 + 19)
  if self.inWater and self.y - self.b > 0.8 then
    if floor(self.anim * 3) % 2 == 0 then UI.text("SLACK!", 144, y0 + 19, "right", UI.bold) end
  else
    UI.text(U.cached("well_load", "%d kg", floor(load + 0.5)), 144, y0 + 19, "right")
  end
  -- the bucket and its water
  local bx, by = 6, y0 + 36
  gfx.setColor(gfx.kColorBlack)
  gfx.drawLine(bx, by, bx + 3, by + 16)
  gfx.drawLine(bx + 18, by, bx + 15, by + 16)
  gfx.drawLine(bx + 3, by + 16, bx + 15, by + 16)
  local fh = floor(15 * self.fill)
  if fh > 0 then
    gfx.setPattern(Art.pat.gray50)
    gfx.fillRect(bx + 3, by + 16 - fh, 13, fh)
    gfx.setColor(gfx.kColorBlack)
  end
  if self.cracks > 0 then gfx.drawLine(bx + 5, by + 5, bx + 8, by + 9) gfx.drawLine(bx + 8, by + 9, bx + 6, by + 13) end
  gfx.drawArc(bx + 9, by + 2, 8, -80, 80)
  UI.text(U.cached("well_fill", "%.1f L", floor(self.fill * CAP * 10) / 10), 30, y0 + 37)
  if self.cracks > 0 then UI.text("LEAKS", 144, y0 + 37, "right") end
  -- PAWL
  UI.text("PAWL", 4, y0 + 55)
  local ps = self.pawlBroken and "BROKEN" or (self.pawl and "DOWN" or "UP")
  UI.text(ps, 60, y0 + 55, "left", UI.bold)
  if not self.pawlBroken then
    for i = 0, 3 do
      local wx = 122 + i * 6
      if self.pawlWear > i * 0.25 then gfx.fillRect(wx, y0 + 60, 4, 6) else gfx.drawRect(wx, y0 + 60, 4, 6) end
    end
  end
  if self.tut then return end
  gfx.drawLine(0, y0 + 74, 148, y0 + 74)
  -- ECHO: how long the drop takes to answer
  UI.text("ECHO", 4, y0 + 77)
  local ew = floor(min(1, self.echo / 2) * 90)
  gfx.drawRect(46, y0 + 81, 96, 8)
  if self.echoFlash > 0 then gfx.fillRect(48, y0 + 83, ew, 4) else
    gfx.setPattern(Art.pat.gray50) gfx.fillRect(48, y0 + 83, ew, 4) gfx.setColor(gfx.kColorBlack) end
  -- candle (standard) or lamp oil (endless); spare buckets
  local frac
  if self.mode == "standard" then frac = self.candle / max(1, self.candleMax or 1) else frac = min(1, self.oil / 150) end
  local ch = floor(18 * clamp(frac, 0, 1))
  local cx, cy = 10, y0 + 108
  gfx.fillRect(cx - 3, cy - ch, 6, ch)
  gfx.drawLine(cx, cy - ch - 1, cx, cy - ch - 3)
  if ch > 0 then
    local fl = floor(self.anim * 8) % 2
    gfx.fillTriangle(cx - 2, cy - ch - 3, cx + 2, cy - ch - 3, cx + fl - 0, cy - ch - 9)
  end
  gfx.drawLine(cx - 6, cy, cx + 6, cy)
  local tl = self.mode == "standard" and self.candle or self.oil
  UI.text(U.timeStr(tl), 20, y0 + 93)
  for i = 1, 3 do
    local sx = 88 + (i - 1) * 19
    local by = y0 + 96
    gfx.drawArc(sx + 7, by + 2, 6, -80, 80)
    if i <= self.spares then
      gfx.fillRect(sx, by + 1, 15, 3)
      gfx.fillRect(sx + 2, by + 4, 11, 8)
      gfx.setColor(gfx.kColorWhite) gfx.drawLine(sx + 3, by + 8, sx + 11, by + 8) gfx.setColor(gfx.kColorBlack)
    else
      gfx.drawLine(sx, by + 1, sx + 14, by + 1)
      gfx.drawLine(sx, by + 1, sx + 2, by + 12)
      gfx.drawLine(sx + 14, by + 1, sx + 12, by + 12)
      gfx.drawLine(sx + 2, by + 12, sx + 12, by + 12)
      gfx.drawLine(sx + 1, by + 12, sx + 13, by + 1)
    end
  end
end

------------------------------------------------------------------------
-- drawing: the shaft (right)
------------------------------------------------------------------------
local ZK <const> = { 0.5, 0.68, 0.82, 0.93, 1.0 }
local ZA <const> = { 0, 0.1, 0.25, 0.47, 0.72 }

local function darkRect(x0, x1, y, h, a)
  if x1 <= x0 or a <= 0.02 then return end
  gfx.setColor(gfx.kColorBlack)
  if a < 0.98 then gfx.setDitherPattern(a, gfx.kDitherTypeBayer4x4) end
  gfx.fillRect(x0, y, x1 - x0, h)
end

function Well:sy(yw) return self.anchor + (yw - self.camY) * PXM end

-- stone of the shaft, stratum by stratum
function Well:drawWalls(top, bot)
  local m0 = floor((top - self.anchor) / PXM + self.camY) - 1
  local m1 = floor((bot - self.anchor) / PXM + self.camY) + 1
  if m0 < 0 then m0 = 0 end
  local n = self.strange
  local seed = self.tut and 3 or (self.night * 17 + self.descent * 5)
  for m = m0, m1 do
    local y0 = floor(self:sy(m))
    local h = PXM
    local hs = ihash(m, 7)
    -- strata: masonry, rock, carved stone, roots, bone
    local pat
    if m < 7 then pat = Art.pat.bricks
    elseif m < 15 then pat = (m % 3 == 0) and Art.pat.gray12 or Art.pat.stipple
    elseif m < 24 then pat = Art.pat.gray25
    elseif m < 32 then pat = Art.pat.hatch
    else pat = Art.pat.scales end
    gfx.setPattern(pat)
    local jl = (hs % 5)
    local jr = ((hs >> 4) % 5)
    gfx.fillRect(SX, y0, SH_L - SX - jl, h)
    gfx.fillRect(SH_R + jr, y0, 400 - SH_R - jr, h)
    -- stone courses and a lit rim along the inner face
    gfx.setColor(gfx.kColorBlack)
    if m >= 7 and m % 2 == 0 then
      gfx.drawLine(SX, y0, SH_L - jl, y0)
      gfx.drawLine(SH_R + jr, y0, 400, y0)
    end
    gfx.fillRect(SH_L - jl - 3, y0, 3, h)
    gfx.fillRect(SH_R + jr + 1, y0, 3, h)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawLine(SH_L - jl, y0, SH_L - jl, y0 + h)
    gfx.drawLine(SH_R + jr, y0, SH_R + jr, y0 + h)
    -- features
    local f = ihash(m, seed) % 100
    if m >= 7 and m < 15 and f < 30 then
      gfx.setColor(gfx.kColorBlack)
      local cx = SH_L - 22 + (hs % 12)
      gfx.drawLine(cx, y0, cx + 6, y0 + 5)
      gfx.drawLine(cx + 6, y0 + 5, cx + 2, y0 + 10)
    end
    if m >= 15 and n >= 3 and f < 40 then
      -- carved spiral glyphs
      local cx = (f % 2 == 0) and (SH_L - 12 - (hs % 8)) or (SH_R + 12 + (hs % 8))
      gfx.setColor(gfx.kColorWhite)
      gfx.fillCircleAtPoint(cx, y0 + 5, 5)
      gfx.setColor(gfx.kColorBlack)
      gfx.drawCircleAtPoint(cx, y0 + 5, 5)
      gfx.drawCircleAtPoint(cx, y0 + 5, 2)
    end
    if m >= 24 and n >= 4 and f > 55 then
      -- roots hanging into the shaft
      gfx.setColor(gfx.kColorBlack)
      local x = (f % 2 == 0) and SH_L or SH_R
      local d = (f % 2 == 0) and 1 or -1
      gfx.drawLine(x, y0, x + d * 8, y0 + 6)
      gfx.drawLine(x + d * 8, y0 + 6, x + d * 11, y0 + 14)
      gfx.drawLine(x + d * 4, y0 + 3, x + d * 3, y0 + 11)
    end
    if m >= 30 and n >= 5 and f < 25 then
      -- a bone set in the wall
      local bx = SH_L - 20 - (hs % 8)
      gfx.setColor(gfx.kColorWhite)
      gfx.fillRect(bx, y0 + 4, 12, 3)
      gfx.fillCircleAtPoint(bx, y0 + 5, 2)
      gfx.fillCircleAtPoint(bx + 12, y0 + 5, 2)
    end
    if n >= 2 and f > 90 and m > 4 then
      -- scratches: four parallel strokes
      gfx.setColor(gfx.kColorWhite)
      local sx = SH_R + 5 + (hs % 10)
      for k = 0, 3 do gfx.drawLine(sx + k * 3, y0 + 1, sx + k * 3 + 2, y0 + 8) end
    end
  end
  gfx.setColor(gfx.kColorBlack)
end

function Well:drawShaft()
  local n = self.strange
  gfx.setClipRect(SX, 18, 250, 204)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(SX, 18, 250, 204)
  -- camera: the bucket stays in view; the mouth pins the top
  self.anchor = self.tut and 92 or 112
  local camMin = (self.anchor - 48) / PXM
  local target = max(camMin, self.b)
  if not self.camY then self.camY = target end
  self.camY = U.damp(self.camY, target, 8, 1 / 30)
  local gy = floor(self:sy(0))
  -- sky, windlass frame and well head above ground
  if gy > 18 then
    gfx.setPattern(Art.pat.gray87)
    gfx.fillRect(SX, 18, 250, gy - 18)
    gfx.setColor(gfx.kColorWhite)
    for i = 0, 9 do gfx.drawPixel(SX + 7 + (i * 53) % 240, 20 + (i * 17) % max(4, gy - 24)) end
      gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(RX - 58, gy - 44, 6, 44)
    gfx.fillRect(RX + 52, gy - 44, 6, 44)
    gfx.fillTriangle(RX - 68, gy - 42, RX + 68, gy - 42, RX, gy - 62)
    gfx.setPattern(Art.pat.wood)
    gfx.fillTriangle(RX - 60, gy - 45, RX + 60, gy - 45, RX, gy - 59)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(RX - 52, gy - 33, 104, 7)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(RX - 52, gy - 33, 104, 7)
    for x = RX - 48, RX + 48, 6 do gfx.drawLine(x, gy - 33, x + 3, gy - 27) end
    -- the handle on the near side turning with the drum
    local a = rad(-self.y / CIRC * 360)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawLine(RX + 58, gy - 30, RX + 58 + sin(a) * 8, gy - 30 - cos(a) * 8)
    -- ground and the stone ring
    gfx.setPattern(Art.pat.gray75)
    gfx.fillRect(SX, gy - 2, 250, 6)
    gfx.setPattern(Art.pat.bricks)
    gfx.fillRect(RX - 62, gy - 12, 124, 12)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(RX - 62, gy - 12, 124, 12)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(SH_L, gy - 12, SH_R - SH_L, 14)
  end
  local top = max(18, gy)
  -- walls, and the dark interior air
  self:drawWalls(top, 222)
  -- words scratched near the water on late nights
  local word = WALL_WORDS[self.night]
  if word and not self.tut and self.mode == "standard" then
    local wy = floor(self:sy(self.W - 3.5))
    if wy > top - 20 and wy < 230 then UI.textW(word, SH_L - 4, wy, "right") end
  end
  -- water
  local wsy = floor(self:sy(self.W))
  if wsy < 222 then
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(SH_L, wsy, SH_R - SH_L, 222 - wsy)
    gfx.setColor(gfx.kColorWhite)
    for k = 0, 5 do
      local yy = wsy + 2 + k * 5
      if yy < 222 then
        local off = floor((self.anim * (8 + k * 3) + k * 17) % 24)
        for x = SH_L + off - 24, SH_R, 24 do gfx.drawLine(max(SH_L, x), yy, min(SH_R, x + 10 - k), yy) end
      end
    end
    gfx.drawLine(SH_L, wsy, SH_R, wsy)
    -- on the last night there is a light under the water
    if n >= 7 and not self.tut then
      local gl = floor(3 + 2 * sin(self.anim * 1.7))
      gfx.fillCircleAtPoint(RX + 18, wsy + 14, gl)
    end
  end
  -- rope
  local bot = self:sy(self.b + BUCKET_H)
  local bail = bot - 22
  gfx.setColor(gfx.kColorWhite)
  local ropeTop = (gy > 18) and (gy - 30) or 18
  local slack = self.y - self.b
  if slack > 0.15 then
    local amp = min(8, slack * 3)
    local sy0 = max(ropeTop, bail - 40)
    gfx.drawLine(RX, ropeTop, RX, sy0)
    local px, py = RX, sy0
    for i = 1, 10 do
      local yy = sy0 + (bail - sy0) * i / 10
      local xx = RX + sin(i * 1.4 + self.anim) * amp * (i / 10)
      gfx.drawLine(px, py, xx, yy)
      px, py = xx, yy
    end
  else
    local tw = (self.tug ~= "none" and (floor(self.anim * 30) % 2 == 0)) and 1 or 0
    gfx.drawLine(RX + tw, ropeTop, RX, bail)
  end
  -- the bucket (tilting while it floats and fills), with its lantern
  self:drawBucket(RX, bot)
  -- particles
  for i = 1, self.MAXP do
    local k = self.pk[i]
    if k ~= 0 then
      local x = RX + floor(self.px[i] * PXM)
      local y = floor(self:sy(self.py[i]))
      gfx.setColor(gfx.kColorWhite)
      if k == 3 then gfx.setColor(gfx.kColorWhite) gfx.fillRect(x, y, 2, 2) else gfx.fillRect(x, y, 1, 2) end
    end
  end
  -- darkness: the lantern and the moon are the only light
  local lampY = bot - 10
  local R = self.lampR0 + sin(self.anim * 13) * 1.2 + sin(self.anim * 5.3) * 1.5
  if self.lastLight then R = R - 6 * (0.5 + 0.5 * sin(self.anim * 0.7)) end
  local band = 4
  for yb = top, 221, band do
    local yw = (yb + band / 2 - self.anchor) / PXM + self.camY
    local moonDark = 1 - clamp(1 - yw / (4.5 * self.moonK + 0.5), 0, 1) * self.moonK
    if moonDark > 0.02 then
      local dy = yb + band / 2 - lampY
      local prevW = 0
      -- inner zones out to the lantern radius, mirrored about the rope
      for k = 1, 5 do
        local r = ZK[k] * R
        local w2 = r * r - dy * dy
        local w = w2 > 0 and sqrt(w2) or 0
        if w > prevW then
          local a = min(ZA[k], moonDark)
          if k == 1 then
            darkRect(RX - w, RX + w, yb, band, a)
          else
            darkRect(RX - w, RX - prevW, yb, band, a)
            darkRect(RX + prevW, RX + w, yb, band, a)
          end
          prevW = w
        end
      end
      local a = min(1, moonDark)
      darkRect(SX, RX - prevW, yb, band, a)
      darkRect(RX + prevW, 400, yb, band, a)
    end
  end
  gfx.setColor(gfx.kColorBlack)
  -- eyes in the dark that watch the lantern (later nights)
  if n >= 4 and not self.tut then
    local m0 = floor((top - self.anchor) / PXM + self.camY)
    for m = m0, m0 + 22 do
      local hsh = ihash(m, 91 + self.night)
      if hsh % 100 < (n - 3) * 5 then
        local ex = (hsh % 2 == 0) and (SX + 8 + (hsh >> 3) % 80) or (SH_R + 8 + (hsh >> 3) % 64)
        local ey = floor(self:sy(m)) + (hsh >> 9) % 8
        local ddx, ddy = ex - RX, ey - lampY
        if ddx * ddx + ddy * ddy > (R + 8) * (R + 8) and ey > top then
          local blink = floor(self.anim * 0.8 + (hsh % 13)) % 11 == 0
          gfx.setColor(gfx.kColorWhite)
          if blink then
            gfx.drawLine(ex, ey + 1, ex + 2, ey + 1)
            gfx.drawLine(ex + 6, ey + 1, ex + 8, ey + 1)
          else
            gfx.fillRect(ex, ey, 3, 3)
            gfx.fillRect(ex + 6, ey, 3, 3)
            gfx.setColor(gfx.kColorBlack)
            local lx = ddx > 0 and 0 or 2
            local ly = ddy > 0 and 0 or 2
            gfx.drawPixel(ex + lx, ey + ly)
            gfx.drawPixel(ex + 6 + lx, ey + ly)
          end
        end
      end
    end
  end
  -- echo ring at the edge of the light when the drop answers
  if self.echoFlash > 0 and not self.inWater then
    gfx.setColor(gfx.kColorWhite)
    local rr = floor(R * 0.8 + (1 - self.echoFlash) * 14)
    gfx.setDitherPattern(1 - self.echoFlash * 0.7, gfx.kDitherTypeBayer4x4)
    gfx.drawEllipseInRect(RX - rr, lampY + R * 0.6, rr * 2, 8)
  end
  -- depth rule on the right edge
  gfx.setColor(gfx.kColorWhite)
  local m0 = floor((top - self.anchor) / PXM + self.camY)
  for m = max(0, m0), m0 + 22 do
    local yy = floor(self:sy(m))
    if yy >= top and yy < 222 then
      local long = m % 5 == 0
      gfx.drawLine(long and 390 or 395, yy, 399, yy)
      if long and m > 0 and yy > top + 4 and yy < 214 then UI.textW(DEPTHS[min(300, m)], 386, yy - 7, "right") end
    end
  end
  gfx.clearClipRect()
  gfx.setColor(gfx.kColorBlack)
end

function Well:drawBucket(x, bot)
  -- tilt while floating & jiggled
  local tilt = 0
  if self.inWater then tilt = sin(self.anim * 14) * self.jiggle.energy * 0.5 + (1 - self.fill) * 0.15 end
  tilt = tilt + clamp(self.q * 0.05, -0.25, 0.25)
  local c, s = cos(tilt), sin(tilt)
  local poly = self.bpoly
  if not poly then
    poly = {}
    for i = 1, 8 do poly[i] = 0 end
    self.bpoly = poly
  end
  -- corners relative to the bottom centre
  local pts = self.bpts
  if not pts then
    pts = { -9, -18, 9, -18, 7, 0, -7, 0 }
    self.bpts = pts
  end
  for i = 1, 7, 2 do
    local px, py = pts[i], pts[i + 1]
    poly[i] = x + px * c - py * s
    poly[i + 1] = bot + px * s + py * c
  end
  gfx.setPattern(Art.pat.vlines)
  gfx.fillPolygon(poly[1], poly[2], poly[3], poly[4], poly[5], poly[6], poly[7], poly[8])
  gfx.setColor(gfx.kColorBlack)
  gfx.drawLine(poly[1], poly[2], poly[3], poly[4])
  gfx.drawLine(poly[3], poly[4], poly[5], poly[6])
  gfx.drawLine(poly[5], poly[6], poly[7], poly[8])
  gfx.drawLine(poly[7], poly[8], poly[1], poly[2])
  -- hoops
  local hx1, hy1 = x - 9 * c + 5 * s, bot - 9 * s - 5 * c
  local hx2, hy2 = x + 9 * c + 5 * s, bot + 9 * s - 5 * c
  gfx.setLineWidth(2)
  gfx.drawLine(hx1, hy1, hx2, hy2)
  gfx.drawLine(x - 9 * c + 13 * s, bot - 9 * s - 13 * c, x + 9 * c + 13 * s, bot + 9 * s - 13 * c)
  gfx.setLineWidth(1)
  -- bail
  gfx.setColor(gfx.kColorWhite)
  local tx, ty = x + 22 * s, bot - 22 * c
  gfx.drawLine(poly[1], poly[2], tx, ty)
  gfx.drawLine(poly[3], poly[4], tx, ty)
  -- cracks
  if self.cracks > 0 then
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(x - 2, bot - 14, x + 1, bot - 9)
    gfx.drawLine(x + 1, bot - 9, x - 1, bot - 4)
  end
  -- the lantern tied to the bail
  local lx, ly = poly[3] + 5, poly[4] - 2
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(lx, ly, 5, 7)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(lx, ly, 5, 7)
  gfx.fillRect(lx + 2, ly + 2, 1, 3)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawLine(lx + 2, ly - 2, tx, ty)
  gfx.setColor(gfx.kColorBlack)
end

------------------------------------------------------------------------
-- drawing: frame
------------------------------------------------------------------------
function Well:drawRead()
  gfx.clear(gfx.kColorBlack)
  -- the well at night, small, centred
  local cx, cy = 200, 78
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(300, 44, 10)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(296 - (1 - self.moonK) * 12, 43, 10)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillTriangle(cx - 34, cy - 20, cx + 34, cy - 20, cx, cy - 36)
  gfx.fillRect(cx - 28, cy - 20, 4, 30)
  gfx.fillRect(cx + 24, cy - 20, 4, 30)
  gfx.fillRect(cx - 22, cy - 12, 44, 4)
  gfx.drawLine(cx, cy - 8, cx, cy + 6)
  gfx.setPattern(Art.pat.bricks)
  gfx.fillRect(cx - 36, cy + 6, 72, 12)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawRect(cx - 36, cy + 6, 72, 12)
  UI.textW(self.readTitle, 200, 104, "center", UI.bold)
  UI.textBlock(self.readText, 40, 126, 320, UI.font, 2, floor(self.readChars), true)
  if self.readChars >= #self.readText and (self.anim * 2) % 2 < 1.4 then
    UI.textW("A: continue", 200, 204, "center")
  end
end

function Well:headerText()
  if self.tut then return "LESSON" end
  if self.mode == "standard" then
    local key = self.night * 1000 + floor(self.nightLitres)
    if key ~= self.hdrKey then
      self.hdrKey = key
      self.hdrStr = string.format("NIGHT %s  %d/%dL", ROMAN[self.night], floor(self.nightLitres), self.quota)
    end
  else
    local key = floor(self.W) * 100000 + self.score
    if key ~= self.hdrKey then
      self.hdrKey = key
      self.hdrStr = string.format("WATER %dm  %s PTS", floor(self.W), U.commas(self.score))
    end
  end
  return self.hdrStr
end

function Well:draw()
  if self.state == "read" or self.state == "done" then
    self:drawRead()
    UI.header(10, "THE WELL", nil)
    UI.hints(HINTS_READ)
    return
  end
  gfx.clear(gfx.kColorBlack)
  self:drawShaft()
  self:drawInset()
  self:drawGauges()
  if self.cardT > 0 and self.cardP then
    UI.popup(160, 42, 230, 64, "paper")
    UI.text(self.cardA, 174, 51, "left", UI.bold)
    if self.cardP > 0 and not self.tut then UI.text(U.cached("well_pts", "+%d", self.cardP), 376, 51, "right", UI.bold) end
    UI.textLines(self.cardB, 174, 70, 206, 2, UI.font, 0)
  end
  if self.msgT > 0 and self.msg then
    local w = UI.width(self.msg, UI.bold) + 20
    local x = (w > 244) and (200 - w / 2) or clamp(RX - w / 2, SX + 2, 398 - w)
    UI.panel(x, 24, w, 22, "ink")
    UI.textW(self.msg, x + w / 2, 27, "center", UI.bold)
  end
  UI.header(10, "THE WELL", self:headerText())
  UI.hints(HINTS)
end

------------------------------------------------------------------------
-- suspend / resume
------------------------------------------------------------------------
function Well:serialize()
  if self.state == "done" then return nil end
  return {
    night = self.night, nightsDone = self.nightsDone, nightLitres = self.nightLitres,
    litres = self.litres, score = self.score, spares = self.spares, delivered = self.delivered,
    descent = self.descent, depthRecord = self.depthRecord, oil = self.oil,
    candle = self.candle or 0, W = self.W, ropeLen = self.ropeLen, lastW = self.lastW,
    pawlWear = self.pawlWear, pawlBroken = self.pawlBroken, stamina = self.stamina, slips = self.slips,
    y = self.y, vy = self.vy, b = self.b, vb = self.vb, fill = self.fill, cracks = self.cracks,
    pawl = self.pawl, state = (self.state == "play" or self.state == "read") and self.state or "play",
    readText = self.readText or "", readTitle = self.readTitle or "", readDone = self.readDone == true,
    foundNight = self.foundNight or 0, rng = self.rng:state(),
  }
end

function Well:deserialize(t)
  if self.mode == "endless" then
    self:startDescent(t.descent or 0)
  else
    self:startNight(t.night or 1)
  end
  self.nightsDone = t.nightsDone or 0
  self.nightLitres = t.nightLitres or 0
  self.litres = t.litres or 0
  self.score = t.score or 0
  self.spares = t.spares or 3
  self.delivered = t.delivered or 0
  self.depthRecord = t.depthRecord or 0
  self.oil = t.oil or 150
  if self.mode == "standard" and t.candle then self.candle = t.candle end
  self.W = t.W or self.W
  self.ropeLen = t.ropeLen or self.ropeLen
  self.lastW = t.lastW or self.lastW
  self.pawlWear = t.pawlWear or 0
  self.pawlBroken = t.pawlBroken == true
  self.stamina = t.stamina or 1
  self.slips = t.slips or 0
  self.y, self.vy = t.y or 0.45, t.vy or 0
  self.b, self.vb = t.b or 0.45, t.vb or 0
  self.h = self.y
  self.fill = t.fill or 0
  self.cracks = t.cracks or 0
  self.pawl = t.pawl == true
  self.descended = self.b > 2.5
  self.state = t.state or "play"
  self.readText = t.readText or ""
  self.readTitle = t.readTitle or ""
  self.readDone = t.readDone == true
  self.readChars = #self.readText
  self.foundNight = t.foundNight or 0
  if t.rng then self.rng:setState(t.rng) end
  self.camY = nil
end
