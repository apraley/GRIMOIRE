-- CRANKING IT :: No.7 PROJECTIONIST
--
-- The crank IS the projector's drive shaft, geared directly to the film:
-- one turn = 8 frames, so two steady turns a second project 16 frames a
-- second, the silent standard. Every frame on the screen is a frame you
-- pulled through the gate yourself.
--   * Speed is the craft. Each reel asks for a speed (14-24 fps, sometimes
--     changing mid-reel). Too slow flickers and bores; too fast turns a
--     drama into a farce. The pianist watches the screen and follows YOUR
--     speed, and the projector's clatter is literally one click per frame.
--   * Rhythm is the danger. The feed sprocket lags behind the hand (the
--     reel has inertia); the difference is taken up by the Latham loop.
--     Steady cranking lets the loop restore itself; a jerk, a lurch or a
--     sudden stop tears it out or throws it wide - and the film JAMS. A
--     jammed frame sits in front of the arc lamp and burns while the
--     sprockets keep tearing at it: stop cranking at once, then open the
--     gate (B), re-thread (the arrows shown) and close it (A).
--   * Reels change over between two projectors. Cue dots flash in the
--     picture's corner 8 s and 1 s before the end: strike projector 2's
--     arc on the first (B), change over on the second (A). The new
--     projector starts from rest behind a clutch, so ease off the crank as
--     you change over and bring it back up smoothly.
-- This is the opposite of the FILM CAMERA: there the crank is still while
-- you work and only an exact AMOUNT of rotation matters; here it must never
-- stop, and only its steadiness matters.

local gfx <const> = playdate.graphics
local floor <const> = math.floor
local abs <const> = math.abs
local min <const>, max <const> = math.min, math.max
local sin <const>, cos <const>, rad <const> = math.sin, math.cos, math.rad

------------------------------------------------------------------------
-- constants
------------------------------------------------------------------------
local SX <const>, SY <const>, SW <const>, SH <const> = 18, 28, 184, 138   -- the screen (4:3)
local DEG_PER_FRAME <const> = 45          -- 8 frames per turn
local TAU <const> = 0.3                   -- feed reel lag (s)
local RESTORE <const> = 2.0               -- loop restoring rate (1/s)
local SEATS <const> = 14
local HATS_MAX <const> = 6
local BOOS_MAX <const> = 3

local K_TRAIN <const>, K_CHASE <const>, K_SEA <const>, K_ROMANCE <const>, K_COMEDY <const>, K_STRANGE <const> = 1, 2, 3, 4, 5, 6
local TITLES <const> = {
  { "THE 5.15 FROM", "GREY ROCK" }, { "ACROSS THE", "ROOFTOPS" }, { "THE GREY", "SEA" },
  { "ON THE PIER", "AT DUSK" }, { "THE WINDY", "PROMENADE" }, { "THE", "AUDIENCE" },
}
local BASE_FPS <const> = { 16, 20, 16, 14, 22, 16 }
local SPEEDS <const> = { 14, 16, 18, 20, 24 }
local NUMS = {}
for i = 0, 40 do NUMS[i] = tostring(i) end

-- piano accompaniment: {frequency, beats}; the pianist follows the screen
local function tune(list)
  local t = {}
  for i = 1, #list, 2 do
    local n = list[i]
    t[#t + 1] = { n == "-" and 0 or Audio.note(n), list[i + 1] }
  end
  return t
end
local TUNES = {
  [K_TRAIN] = { tune({ "C3", 0.5, "G3", 0.5, "E4", 0.5, "G3", 0.5, "C3", 0.5, "G3", 0.5, "F4", 0.5, "G3", 0.5,
    "B2", 0.5, "G3", 0.5, "D4", 0.5, "G3", 0.5, "C3", 0.5, "G3", 0.5, "E4", 1 }), 132 },
  [K_CHASE] = { tune({ "A4", 0.5, "A4", 0.5, "C5", 0.5, "A4", 0.5, "E5", 0.5, "D5", 0.5, "C5", 0.5, "B4", 0.5,
    "A4", 0.5, "G#4", 0.5, "A4", 0.5, "B4", 0.5, "C5", 0.5, "B4", 0.5, "A4", 1 }), 168 },
  [K_SEA] = { tune({ "D4", 1.5, "F4", 0.5, "A4", 1, "G4", 1, "F4", 1.5, "E4", 0.5, "D4", 2, "A3", 1, "C4", 1,
    "D4", 2 }), 84 },
  [K_ROMANCE] = { tune({ "E4", 1, "G4", 1, "C5", 1, "B4", 2, "A4", 1, "G4", 1, "E4", 1, "F4", 1, "D4", 2, "-", 1,
    "E4", 1, "G4", 1, "D5", 1, "C5", 3 }), 110 },
  [K_COMEDY] = { tune({ "C5", 0.5, "E5", 0.5, "G5", 0.5, "E5", 0.5, "F5", 0.5, "D5", 0.5, "B4", 0.5, "G4", 0.5,
    "C5", 0.5, "-", 0.5, "G4", 0.5, "C5", 0.5 }), 176 },
  [K_STRANGE] = { tune({ "E4", 2, "F4", 2, "E4", 2, "-", 1, "B3", 3, "C4", 2, "-", 2 }), 60 },
}

-- tiny integer hash for film grain (deterministic per frame)
local function hh(n)
  n = floor(n) % 65536
  return (n * 2654 + 7919 + (n * n) % 3571) % 10007
end

------------------------------------------------------------------------
-- definition
------------------------------------------------------------------------
local Proj = Machine.define({
  id = "projectionist",
  number = 7,
  title = "PROJECTIONIST",
  tagline = "Two turns a second. Always.",
  description = "Hand-crank the picture house projector: keep the frame rate the film asks for, never jerk the loop, and change reels on the cues.",
  howto = "Crank steadily: 2 turns/s = 16 fps. Match the speed dial's band. Jerks shrink the loop and jam the film: stop, B opens the gate, press the arrows, A closes. Cue dots: B strikes the other arc, A changes over.",
  controls = { { "CRANK", "drive the film" }, { "B", "strike arc / open gate" }, { "A", "change over / close gate" }, { "DPAD", "re-thread" } },
  modes = { "tutorial", "standard", "endless" },
  medals = { standard = { 1200, 1900, 2450 }, endless = { 3000, 6500, 11000 } },
  scoreLabel = "APPLAUSE",
  unlockCost = 6,
  achievements = {
    { id = "first", name = "FIRST NIGHT", desc = "Project a whole programme." },
    { id = "clean", name = "STEADY HANDS", desc = "A programme without a jam." },
    { id = "seamless", name = "SEAMLESS", desc = "Make a perfect changeover." },
    { id = "full", name = "FULL HOUSE", desc = "Finish with every seat taken." },
    { id = "watching", name = "THEY ARE WATCHING", desc = "Project 'The Audience' to the end." },
  },
  challenges = {
    { id = "hot", name = "NITRATE", desc = "Jammed film burns twice as fast.", mode = "standard", difficulty = 2, goal = 1800, reward = 3, cost = 2 },
    { id = "rusty", name = "WORN BEARINGS", desc = "The drive sticks and lurches.", mode = "standard", difficulty = 1, mods = { rusty = true }, goal = 1300, reward = 3, cost = 3 },
    { id = "double", name = "DOUBLE FEATURE", desc = "Endless, harder films.", mode = "endless", difficulty = 3, goal = 5000, reward = 3, cost = 3 },
  },
  records = {
    { "programmes", "Programmes shown" },
    { "changeovers", "Changeovers" },
    { "perfect", "Perfect changeovers" },
    { "jams", "Jams" },
  },
  drawIcon = function(cx, cy)
    gfx.setColor(gfx.kColorBlack)
    -- two reels
    gfx.fillCircleAtPoint(cx - 9, cy - 13, 9)
    gfx.fillCircleAtPoint(cx + 9, cy - 13, 9)
    gfx.setColor(gfx.kColorWhite)
    for i = 0, 2 do
      local a = rad(i * 120 + 20)
      gfx.drawLine(cx - 9, cy - 13, cx - 9 + sin(a) * 7, cy - 13 - cos(a) * 7)
      gfx.drawLine(cx + 9, cy - 13, cx + 9 + sin(a + 1) * 7, cy - 13 - cos(a + 1) * 7)
    end
    gfx.fillCircleAtPoint(cx - 9, cy - 13, 2)
    gfx.fillCircleAtPoint(cx + 9, cy - 13, 2)
    gfx.setColor(gfx.kColorBlack)
    -- body and lens
    gfx.fillRect(cx - 12, cy - 3, 22, 16)
    gfx.fillRect(cx - 21, cy + 1, 10, 7)
    -- beam
    gfx.drawLine(cx - 21, cy + 2, cx - 24, cy - 4)
    gfx.drawLine(cx - 21, cy + 6, cx - 24, cy + 12)
    gfx.drawLine(cx - 22, cy + 4, cx - 24, cy + 4)
    -- crank
    gfx.drawCircleAtPoint(cx + 16, cy + 8, 5)
    gfx.drawLine(cx + 16, cy + 8, cx + 20, cy + 16)
    gfx.fillCircleAtPoint(cx + 20, cy + 17, 2)
    -- legs
    gfx.drawLine(cx - 6, cy + 13, cx - 10, cy + 22)
    gfx.drawLine(cx + 4, cy + 13, cx + 8, cy + 22)
  end,
})

Proj.HINTS = { { "CRANK", "DRIVE" }, { "B", "ARC/GATE" }, { "A", "CHANGE/CLOSE" }, { "DPAD", "THREAD" } }

------------------------------------------------------------------------
-- programme generation
------------------------------------------------------------------------
-- a reel: kind, length in frames, speed segments, a few picture params
function Proj:makeReel(kind, idx, n)
  local r = self.rng
  local reel = { kind = kind, sf = {}, sfps = {}, p1 = r:float(), p2 = r:float(), p3 = r:range(1, 1000) }
  local secs = r:between(34, 42)
  if self.mode == "tutorial" then secs = 999 end
  local base = BASE_FPS[kind]
  if self.prog > 1 then base = min(24, base + 2 * (self.prog - 1) // 1) end
  local changes = 0
  if self.mode ~= "tutorial" then
    if self.difficulty >= 3 then changes = r:range(1, 2)
    elseif self.difficulty == 2 then changes = 1
    else changes = (idx > 1 and r:chance(0.6)) and 1 or 0 end
    if self.prog > 1 then changes = min(2, changes + 1) end
  end
  local f, fps = 0, base
  reel.sf[1], reel.sfps[1] = 0, base
  local segSecs = secs / (changes + 1)
  for c = 1, changes do
    f = f + floor(segSecs * fps)
    local nf
    for _ = 1, 8 do
      nf = SPEEDS[r:range(1, #SPEEDS)]
      if nf ~= fps then break end
    end
    fps = nf
    reel.sf[c + 1], reel.sfps[c + 1] = f, fps
  end
  reel.R = f + floor(segSecs * fps)
  reel.endFps = fps
  reel.title1, reel.title2 = TITLES[kind][1], TITLES[kind][2]
  reel.label = "REEL " .. idx .. "/" .. n
  return reel
end

function Proj:makeProgramme()
  local kinds = { K_TRAIN, K_CHASE, K_SEA, K_ROMANCE, K_COMEDY }
  self.rng:shuffle(kinds)
  local n = 3
  local list = { kinds[1], kinds[2], kinds[3] }
  if self.mode == "tutorial" then list = { K_TRAIN, K_SEA } n = 2 end
  if self.mode == "standard" and self.rng:chance(0.35) then list[3] = K_STRANGE end
  if self.mode == "endless" and self.prog == 2 then list[3] = K_STRANGE end
  self.reels = {}
  for i = 1, n do self.reels[i] = self:makeReel(list[i], i, n) end
end

function Proj:targetFps(f)
  local reel = self.reel
  local fps = reel.sfps[1]
  for i = 2, #reel.sf do if f >= reel.sf[i] then fps = reel.sfps[i] end end
  return fps
end

-- frames until the next speed change (or nil)
function Proj:nextChange(f)
  local reel = self.reel
  for i = 2, #reel.sf do if reel.sf[i] > f then return reel.sf[i] - f, reel.sfps[i] end end
  return nil
end

function Proj:cues()
  local reel = self.reel
  return reel.R - 8 * reel.endFps, reel.R - reel.endFps
end

function Proj:hasNext() return self.reelIdx < #self.reels end

function Proj:loadReel(i)
  self.reelIdx = i
  self.reel = self.reels[i]
  self.f = 0
  self.cue1Seen, self.cue2Seen = false, false
  self.titleT = 0
  local tn = TUNES[self.reel.kind]
  self.piano = Audio.MusicBox.new(tn[1], tn[2], Audio.TRIANGLE, 0.1)
  self.piano:start()
  self.hdr = self.mode == "endless" and ("SHOW " .. self.prog .. "  " .. self.reel.label) or self.reel.label
end

------------------------------------------------------------------------
-- lifecycle
------------------------------------------------------------------------
function Proj:enter(params)
  self.tut = self.mode == "tutorial"
  self.t = 0
  self.prog = 1
  self.score = 0
  self.scoreAcc = 0
  local d = self.difficulty
  self.K = self.tut and 2.0 or ({ 1.9, 2.2, 2.6 })[d]
  self.tol = ({ 0.12, 0.10, 0.08 })[d]
  self.cueDur = ({ 10, 7, 5 })[d]
  self.burnRate = self.params.challengeId == "hot" and 2 or 1
  if self.params.challengeId == "double" then self.K = self.K * 1.1 end
  self.tracker = Crank.Tracker.new()
  self.pend = 0
  self.vH, self.vF, self.fps = 0, 0, 0
  self.loop = 0.5
  self.state = "run"
  self.proj = 1
  self.heat = { 1, 0 }
  self.struck = { true, false }
  self.oldOff = 0
  self.mood = 0.72
  self.grace = 6
  self.present, self.patience, self.lowT, self.leaveT, self.hat, self.seatX, self.seatY = {}, {}, {}, {}, {}, {}, {}
  for i = 1, SEATS do
    self.present[i] = true
    self.patience[i] = self.tut and 0 or self.rng:between(0.12, 0.46)
    self.lowT[i] = 0
    self.leaveT[i] = 0
    self.hat[i] = self.rng:range(0, 4)
    local back = i <= 7
    self.seatX[i] = back and (30 + (i - 1) * 27) or (18 + (i - 8) * 29)
    self.seatY[i] = back and 180 or 208
  end
  self.booX, self.booY, self.booT = {}, {}, {}
  for i = 1, BOOS_MAX do self.booX[i], self.booY[i], self.booT[i] = 0, 0, 0 end
  self.hatX, self.hatY, self.hatVX, self.hatVY, self.hatA, self.hatOn = {}, {}, {}, {}, {}, {}
  for i = 1, HATS_MAX do self.hatX[i], self.hatY[i], self.hatVX[i], self.hatVY[i], self.hatA[i], self.hatOn[i] = 0, 0, 0, 0, 0, false end
  self.burn, self.burnX, self.burnY = 0, 0, 0
  self.seq = { 1, 2, 3, 4 }
  self.seqI = 1
  self.jams = 0
  self.progJams = 0
  self.perfects = 0
  self.msg, self.msgT = nil, 0
  self.blackT = 0
  self.laughT, self.booCool = 0, 0
  self.doorT = 0
  self.qNow = 0
  self.applause = 0
  self.interT = 0
  self.hum = Audio.Hum.new(Audio.NOISE)
  self.lastRating = ""
  self.changed = false
  self.post = 0
  self:makeProgramme()
  self:loadReel(1)
  if self.tut then self:setupCoach() end
end

function Proj:exit()
  self.hum:stop()
  if self.piano then self.piano:stop() end
end

------------------------------------------------------------------------
-- tutorial
------------------------------------------------------------------------
function Proj:setupCoach()
  local s = self
  self.coach = UI.Coach.new({
    { text = "Crank steadily: 2 turns a second projects 16 frames a second.",
      check = function() return s.state == "run" and abs(s.fps - 16) <= 2.5 end, hold = 2 },
    { text = "The LOOP gauge in the booth shows the slack. Keep cranking evenly.",
      check = function() return s.state == "run" and s.loop > 0.3 and s.loop < 0.7 and s.fps > 12 end, hold = 4 },
    { text = "Now JERK the crank - spin it fast, suddenly - to see a jam.",
      check = function() return s.state ~= "run" end },
    { text = "STOP cranking! The stuck frame is burning.",
      check = function() return s.state ~= "jam" end },
    { text = "B opens the gate. Press the arrows shown, then A to close it.",
      check = function() return s.state == "run" end },
    { text = "The film now asks for 20 fps. Speed up GENTLY to the dial's band.",
      enter = function() s:tutSpeed(20) end,
      check = function() return s.state == "run" and abs(s.fps - 20) <= 2.5 end, hold = 2 },
    { text = "A dot will flash top-right of the picture. Then press B: it lights projector 2.",
      enter = function() s:tutEnd() end,
      check = function() return s.struck[3 - s.proj] end },
    { text = "On the SECOND dot, press A to change over. Ease off the crank as you do.",
      check = function() return s.reelIdx == 2 end },
    { text = "Projector 2 started from rest. Bring it up to 16 fps smoothly.",
      check = function() return s.reelIdx == 2 and s.state == "run" and abs(s.fps - 16) <= 2.5 end, hold = 2 },
  }, { y = 176, h = 46, anchor = "bottom" })
end

function Proj:tutSpeed(fps)
  local reel = self.reel
  local n = #reel.sf + 1
  reel.sf[n], reel.sfps[n] = floor(self.f), fps
  reel.endFps = fps
end

function Proj:tutEnd()
  local reel = self.reel
  reel.R = floor(self.f) + 11 * reel.endFps
end

------------------------------------------------------------------------
-- mechanics
------------------------------------------------------------------------
function Proj:cranked(change)
  self.tracker:feed(change)
  self.pend = self.pend + change
end

function Proj:jam()
  self.state = "jam"
  self.burn = 0
  self.burnX = SX + 30 + self.rng:range(0, SW - 60)
  self.burnY = SY + 25 + self.rng:range(0, SH - 50)
  self.jams = self.jams + 1
  self.progJams = self.progJams + 1
  self:statAdd("jams", 1)
  self.mood = max(0, self.mood - 0.1)
  Audio.play(Audio.SAW, 900, 0.3, 0.25, 0.001, 0.2, 0.3, 0.1)
  Audio.sfx.snap(0.5)
  self:shake(4)
  self.msg, self.msgT = "JAMMED! STOP CRANKING", 2.5
  -- somebody throws a hat
  for i = 1, HATS_MAX do
    if not self.hatOn[i] then
      local seat = self.rng:range(1, SEATS)
      if self.present[seat] then
        self.hatOn[i] = true
        self.hatX[i], self.hatY[i] = self.seatX[seat], self.seatY[seat] - 16
        self.hatVX[i], self.hatVY[i] = self.rng:between(-40, 40), self.rng:between(-150, -110)
        self.hatA[i] = 0
      end
      break
    end
  end
end

function Proj:changeover()
  local reel = self.reel
  local fpsT = reel.endFps
  local _, cue2 = self:cues()
  local err = self.f - cue2
  local rating, pts, dm
  if self.state == "runout" then rating, pts, dm = "RUNOUT", 0, -0.02
  elseif err < -3 * fpsT then rating, pts, dm = "CUT SHORT", 0, -0.07
  elseif err < -0.6 * fpsT then rating, pts, dm = "EARLY", 50, -0.02
  elseif err <= 0.6 * fpsT then rating, pts, dm = "PERFECT", 150, 0.07
  else rating, pts, dm = "LATE", 40, -0.01 end
  local newP = 3 - self.proj
  if self.heat[newP] < 0.5 then
    rating = rating == "PERFECT" and "DARK SCREEN" or rating
    pts = 0
    dm = dm - 0.04
  end
  self.lastRating = rating
  self.score = self.score + pts
  self.mood = U.clamp(self.mood + dm, 0, 1)
  if rating == "PERFECT" then
    self.perfects = self.perfects + 1
    self:statAdd("perfect", 1)
    self:award("seamless")
    self.blackT = 1 / 30
  else
    self.blackT = 5 / 30
  end
  self:statAdd("changeovers", 1)
  self.msg, self.msgT = rating, 1.6
  Audio.sfx.thunk(0.5)
  Audio.sfx.click(0.4)
  -- the crank now drives the other machine, which starts from rest
  self.proj = newP
  self.oldOff = 1.2
  self.vF = 0
  self.loop = 0.5
  self.state = "run"
  self:loadReel(self.reelIdx + 1)
end

function Proj:endProgramme()
  self.state = "over"
  self.post = 0
  local present = self:presentCount()
  local bonus = floor(self.mood * present * 15)
  self.score = self.score + bonus
  self.applause = 1.5 + self.mood * 2
  self:statAdd("programmes", 1)
  self:award("first")
  if self.progJams == 0 then self:award("clean") end
  if present == SEATS then self:award("full") end
  if self.reel.kind == K_STRANGE then self:award("watching") end
  if self.piano then self.piano:stop() end
end

function Proj:presentCount()
  local n = 0
  for i = 1, SEATS do if self.present[i] then n = n + 1 end end
  return n
end

function Proj:buttonDown(b)
  local st = self.state
  if b == Input.B then
    if st == "stopped" or st == "jam" then
      if st == "jam" then return end
      self.state = "thread"
      self.msgT = 0
      self.seqI = 1
      for i = 1, 4 do self.seq[i] = self.rng:range(1, 4) end
      Audio.sfx.clank(0.3)
    elseif st == "run" or st == "runout" then
      local o = 3 - self.proj
      if not self.struck[o] and self:hasNext() then
        self.struck[o] = true
        self.heat[o] = 0.05
        Audio.sfx.snap(0.35)
        Audio.play(Audio.NOISE, 7000, 0.15, 0.4, 0.01, 0.3, 0.2, 0.2)
        self.msg, self.msgT = "ARC STRUCK", 1
      end
    end
  elseif b == Input.A then
    if st == "closing" then
      self.state = "run"
      self.loop = 0.5
      self.vF = self.vH
      self.f = self.f + 12 -- the burnt frames are spliced out
      self.burn = 0
      Audio.sfx.clank(0.5)
      self.msg, self.msgT = "RUNNING", 1
    elseif (st == "run" or st == "runout") and self:hasNext() then
      self:changeover()
    end
  elseif st == "thread" then
    local d = self.seq[self.seqI]
    local want = d == 1 and Input.UP or (d == 2 and Input.LEFT or (d == 3 and Input.DOWN or Input.RIGHT))
    if b == want then
      self.seqI = self.seqI + 1
      Audio.play(Audio.SQUARE, 700 + self.seqI * 120, 0.15, 0.03)
      if self.seqI > 4 then self.state = "closing" Audio.sfx.click(0.4) end
    elseif b == Input.UP or b == Input.DOWN or b == Input.LEFT or b == Input.RIGHT then
      self.seqI = 1
      Audio.sfx.denied()
    end
  end
end

function Proj:update(dt)
  self.t = self.t + dt
  self.tracker:update(dt)
  local c = self.pend
  self.pend = 0
  local raw = c / dt
  self.vH = U.damp(self.vH, raw, 14, dt)
  self.fps = max(0, self.vH / DEG_PER_FRAME)
  if self.msgT > 0 then self.msgT = self.msgT - dt end
  if self.blackT > 0 then self.blackT = self.blackT - dt end
  if self.grace > 0 then self.grace = self.grace - dt end
  local st = self.state
  local reel = self.reel
  local target = self:targetFps(self.f)
  self.target = target

  -- arc lamps: the struck one heats up, the old one goes out after a change
  local o = 3 - self.proj
  if self.struck[o] then self.heat[o] = min(1, self.heat[o] + dt / 3) end
  if self.oldOff > 0 then
    self.oldOff = self.oldOff - dt
    if self.oldOff <= 0 then self.heat[o] = 0 self.struck[o] = false end
  end
  self.heat[self.proj] = min(1, self.heat[self.proj] + dt / 3)
  self.struck[self.proj] = true

  local projecting = false
  if st == "run" or st == "runout" then
    -- the feed reel lags the hand; the loop takes up the difference
    self.vF = U.damp(self.vF, self.vH, 1 / TAU, dt)
    self.loop = self.loop + (self.K * (self.vF - self.vH) / 720 + RESTORE * (0.5 - self.loop)) * dt
    if self.loop <= 0.02 or self.loop >= 0.98 then
      self:jam()
    else
      local before = self.f
      self.f = max(0, self.f + c / DEG_PER_FRAME)
      -- one clack of the claw per frame pulled down
      local n = floor(self.f) - floor(before)
      if n > 0 then
        local fr = floor(self.f)
        Audio.play(Audio.NOISE, 2600, 0.1, 0.005, 0.001, 0.008, 0, 0.005)
        Audio.play(Audio.SQUARE, fr % 2 == 0 and 140 or 180, 0.1, 0.01, 0.001, 0.015, 0, 0.005)
      end
      local cue1, cue2 = self:cues()
      if self:hasNext() then
        if self.f >= cue1 then self.cue1Seen = true end
        if self.f >= cue2 then self.cue2Seen = true end
      end
      if self.f >= reel.R then
        if self:hasNext() then
          if st ~= "runout" then
            self.state = "runout"
            self.msg, self.msgT = "RUNOUT! CHANGE OVER (A)", 2
            Audio.sfx.whoosh(0.3)
          end
        else
          self:endProgramme()
        end
      end
      projecting = self.state == "run"
    end
  elseif st == "jam" then
    -- the frame is stuck in front of the arc; the sprockets tear at it
    if self.tracker.idle > 0.25 then
      self.state = "stopped"
      Audio.sfx.thunk(0.4)
      self.msg, self.msgT = "B: OPEN THE GATE", 2
    else
      local rate = (0.22 + min(2, abs(self.vH) / 720) * 0.7) * self.burnRate
      self.burn = self.burn + rate * dt
      if math.random() < 0.6 then Audio.play(Audio.NOISE, 900 + math.random() * 2000, 0.08, 0.01) end
      if self.burn >= 1 then
        self.burn = 1
        self.state = "stopped"
        self.mood = max(0, self.mood - 0.3)
        Audio.sfx.splash(0.4)
        self:shake(6)
        self.msg, self.msgT = "FILM FIRE! B: OPEN GATE", 2.5
      end
    end
  end

  -- how the audience experiences this second
  local q = 0
  if projecting then
    local ratio = self.fps / max(1, target)
    local e = abs(ratio - 1)
    q = e <= self.tol and 1 or max(0, 1 - (e - self.tol) / 0.3)
    q = q * self.heat[self.proj]
    if self.blackT > 0 then q = 0 end
    if ratio > 1.3 then self.laughT = 0.4 end
  end
  self.qNow = q
  if self.laughT > 0 then self.laughT = self.laughT - dt end

  local present = self:presentCount()
  if st ~= "over" and st ~= "intermission" then
    local dm
    if projecting then dm = (q - 0.6) * (q < 0.6 and 0.06 or 0.1)
    elseif st == "runout" then dm = -0.06
    else dm = -0.03 end
    if self.grace > 0 and dm < 0 then dm = 0 end
    self.mood = U.clamp(self.mood + dm * dt, 0, 1)
    self.scoreAcc = self.scoreAcc + q * present / SEATS * 20 * dt
    if self.scoreAcc >= 1 then
      local whole = floor(self.scoreAcc)
      self.score = self.score + whole
      self.scoreAcc = self.scoreAcc - whole
    end
    -- boos when it goes badly
    self.booCool = self.booCool - dt
    if (not projecting or q < 0.3) and self.grace <= 0 and self.mood < 0.5 and self.booCool <= 0 then
      self.booCool = 1.2
      for i = 1, BOOS_MAX do
        if self.booT[i] <= 0 then
          local seat = self.rng:range(1, SEATS)
          if self.present[seat] then
            self.booX[i], self.booY[i], self.booT[i] = U.clamp(self.seatX[seat], 22, 196), self.seatY[seat] - 30, 1.2
            Audio.play(Audio.SAW, 130, 0.12, 0.35, 0.05, 0.25, 0.4, 0.1)
          end
          break
        end
      end
    end
  end
  for i = 1, BOOS_MAX do if self.booT[i] > 0 then self.booT[i] = self.booT[i] - dt end end
  if self.laughT > 0 and math.random() < dt * 6 then
    Audio.play(Audio.SQUARE, 500 + math.random() * 300, 0.06, 0.05)
  end

  -- people leave when the house mood falls below their patience,
  -- one at a time: there is only one aisle
  if self.doorT > 0 then self.doorT = self.doorT - dt end
  for i = 1, SEATS do
    if self.present[i] then
      if self.leaveT[i] > 0 then
        self.leaveT[i] = self.leaveT[i] + dt
        if self.leaveT[i] > 1.5 then
          self.present[i] = false
          Audio.sfx.thud(0.25)
        end
      elseif self.mood < self.patience[i] then
        self.lowT[i] = self.lowT[i] + dt
        if self.lowT[i] > 3 and self.doorT <= 0 then
          self.leaveT[i] = 0.01
          self.doorT = 3
        end
      else
        self.lowT[i] = 0
      end
    end
  end
  if present == 0 and st ~= "over" then
    self:finishRun(false)
    return
  end

  -- hats in flight
  for i = 1, HATS_MAX do
    if self.hatOn[i] then
      self.hatVY[i] = self.hatVY[i] + 260 * dt
      self.hatX[i] = self.hatX[i] + self.hatVX[i] * dt
      self.hatY[i] = self.hatY[i] + self.hatVY[i] * dt
      self.hatA[i] = self.hatA[i] + dt * 8
      if self.hatY[i] > 240 then self.hatOn[i] = false end
    end
  end

  -- sounds: arc hiss, the pianist following the picture
  self.hum:set(5000, (st == "run" or st == "runout") and 0.02 * self.heat[self.proj] or 0)
  if self.piano then
    local rate = 0
    if projecting then rate = U.clamp(self.fps / max(1, target), 0, 1.6) end
    self.piano:update(dt, rate)
  end

  if st == "over" then
    self.post = self.post + dt
    if self.applause > 0 then
      self.applause = self.applause - dt
      if math.random() < 0.7 then
        Audio.play(Audio.NOISE, 1500 + math.random() * 3000, 0.06 + self.mood * 0.08, 0.02, 0.001, 0.02, 0, 0.01)
      end
    end
    if self.post > 3 then
      if self.mode == "endless" then
        self:intermission()
      elseif self.mode == "standard" then
        self:finishRun(true)
      end
    end
  elseif st == "intermission" then
    self.interT = self.interT - dt
    if self.interT <= 0 then
      self.state = "run"
      self.vF = 0
      self.loop = 0.5
      self.grace = 4
      self:loadReel(1)
    end
  end
end

function Proj:intermission()
  self.state = "intermission"
  self.interT = 4
  self.prog = self.prog + 1
  self.progJams = 0
  -- word of mouth: a good show fills the empty seats
  for i = 1, SEATS do
    if not self.present[i] and self.rng:chance(0.3 + 0.6 * self.mood) then
      self.present[i] = true
      self.leaveT[i], self.lowT[i] = 0, 0
      self.patience[i] = self.rng:between(0.12, 0.46)
      self.hat[i] = self.rng:range(0, 4)
    end
  end
  self.mood = max(self.mood, 0.62)
  self.tol = max(0.06, self.tol - 0.01)
  self:makeProgramme()
end

function Proj:finishRun(ok)
  if self.piano then self.piano:stop() end
  self.hum:stop()
  local present = self:presentCount()
  if self.mode == "endless" then
    self:finish({ success = self.prog > 1, score = self.score, title = "EMPTY HOUSE",
      lines = { "Programmes shown: " .. (self.prog - 1), "Jams: " .. self.jams .. "   Perfect changes: " .. self.perfects } })
  elseif ok then
    self:finish({ success = true, score = self.score,
      title = self.mood > 0.8 and "STANDING OVATION" or (self.mood > 0.5 and "APPLAUSE" or "POLITE COUGHS"),
      lines = { "Audience: " .. present .. "/" .. SEATS .. " stayed", "Jams: " .. self.jams .. "   Perfect changes: " .. self.perfects } })
  else
    self:finish({ success = false, score = self.score, title = "EMPTY HOUSE",
      lines = { "Everybody walked out.", "Jams: " .. self.jams } })
  end
end

------------------------------------------------------------------------
-- drawing: the films
------------------------------------------------------------------------
local function fig(x, y, s, hat, leg)
  -- a little silent-film person standing on (x, y), height ~ 22*s
  gfx.fillCircleAtPoint(x, y - 19 * s, 3 * s)
  gfx.fillRect(x - 3 * s, y - 16 * s, 6 * s, 9 * s)
  gfx.drawLine(x - s, y - 7 * s, x - s - leg * 3 * s, y)
  gfx.drawLine(x + s, y - 7 * s, x + s + leg * 3 * s, y)
  if hat == 1 then gfx.fillRect(x - 3 * s, y - 25 * s, 6 * s, 4 * s) gfx.fillRect(x - 5 * s, y - 22 * s, 10 * s, 1.5 * s)
  elseif hat == 2 then gfx.fillTriangle(x - 5 * s, y - 20 * s, x + 5 * s, y - 20 * s, x, y - 27 * s) end
end

local function drawTrain(f, R, reel)
  local W, H = SW, SH
  local vpx, vpy = SX + W * (0.55 + reel.p1 * 0.1), SY + H * 0.42
  -- canopy and platform
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(SX, SY, W, 12)
  gfx.setPattern(Art.pat.hatchD)
  gfx.fillTriangle(SX, SY + 12, SX + W, SY + 12, vpx, vpy - 10)
  gfx.setColor(gfx.kColorBlack)
  for k = 0, 3 do
    local x = SX + 10 + k * 22
    gfx.fillRect(x, SY + 12, 3, 40 + k * 14)
  end
  gfx.setPattern(Art.pat.gray25)
  gfx.fillTriangle(SX, SY + H, SX + W * 0.45, SY + H, vpx - 4, vpy)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawLine(SX + W * 0.45, SY + H, vpx - 4, vpy)
  gfx.drawLine(SX + W * 0.62, SY + H, vpx, vpy)
  gfx.drawLine(SX + W * 0.92, SY + H, vpx + 3, vpy)
  for k = 1, 6 do
    local t = (k / 6) ^ 2
    local y = vpy + (SY + H - vpy) * t
    gfx.drawLine(vpx - 1 + (SX + W * 0.6 - vpx) * t, y, vpx + 3 + (SX + W * 0.95 - vpx) * t, y)
  end
  -- the train arrives
  local a = U.smoothstep(min(1, f / 360))
  local size = 8 + 110 * a * a
  local cx = vpx + 2 + (SX + W * 0.74 - vpx) * a
  local cy = vpy + (SY + H * 0.64 - vpy) * a
  -- steam
  gfx.setPattern(Art.pat.gray50)
  for k = 0, 2 do
    local ph = (f * 0.04 + k * 0.33) % 1
    gfx.fillCircleAtPoint(cx - size * 0.1 - ph * 30, cy - size * 0.6 - ph * 40, size * 0.12 + ph * 12)
  end
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(cx - size * 0.4, cy - size * 0.5, size * 0.8, size)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(cx, cy - size * 0.05, size * 0.28)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(cx, cy - size * 0.05, size * 0.1)
  gfx.fillRect(cx - size * 0.06, cy - size * 0.75, size * 0.12, size * 0.25)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(cx - size * 0.28, cy + size * 0.36, size * 0.05 + 1)
  gfx.fillCircleAtPoint(cx + size * 0.28, cy + size * 0.36, size * 0.05 + 1)
  gfx.setColor(gfx.kColorBlack)
  -- people on the platform step back as it looms
  local back = a > 0.7 and (a - 0.7) * 40 or 0
  local leg = (f // 4) % 2
  for k = 0, 2 do
    local x = SX + 18 + k * 20 - back * (k + 1) * 0.4
    local y = SY + H - 30 + k * 8
    fig(x, y, 1 + k * 0.15, k % 3, a >= 1 and leg or 0)
  end
  -- passengers alight
  if f > 380 then
    local wx = SX + W * 0.5 - ((f - 380) * 0.4) % 60
    fig(wx, SY + H - 12, 1.2, 1, leg)
  end
end

local function drawChase(f, R, reel)
  local W, H = SW, SH
  -- night sky and moon
  gfx.setPattern(Art.pat.gray75)
  gfx.fillRect(SX, SY, W, H)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(SX + W - 34, SY + 26, 14)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(SX + W - 28, SY + 22, 11)
  -- rooftops scroll by
  local scroll = f * 2.4
  local seg = 48
  local first = floor(scroll / seg)
  local runY1, runY2
  for k = first, first + 5 do
    local x = SX + k * seg - scroll
    local h = 36 + hh(k + reel.p3) % 40
    local gap = (hh(k * 3 + reel.p3) % 3 == 0) and 14 or 2
    local top = SY + H - h
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(x, top, seg - gap, h)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawLine(x, top, x + seg - gap, top)
    for wy = top + 10, SY + H - 8, 14 do
      if hh(k + wy) % 3 == 0 then gfx.fillRect(x + 8, wy, 5, 6) end
      if hh(k * 7 + wy) % 4 == 0 then gfx.fillRect(x + 26, wy, 5, 6) end
    end
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(x + 30, top - 10, 7, 10)
    -- the runners' roofs
    if x <= SX + 110 and x + seg > SX + 110 then runY1 = top end
    if x <= SX + 64 and x + seg > SX + 64 then runY2 = top end
  end
  runY1, runY2 = runY1 or SY + H - 40, runY2 or SY + H - 40
  local leg = (f // 3) % 2
  local j1 = abs(sin(f * 0.13)) * 10
  gfx.setColor(gfx.kColorWhite)
  fig(SX + 110, runY1 - j1, 1.1, 0, leg)
  gfx.fillRect(SX + 113, runY1 - j1 - 16, 7, 7) -- the swag bag
  fig(SX + 64, runY2 - abs(sin(f * 0.13 + 1)) * 10, 1.15, 2, 1 - leg)
  gfx.setColor(gfx.kColorBlack)
end

local function drawSea(f, R, reel)
  local W, H = SW, SH
  gfx.setPattern(Art.pat.hatch)
  gfx.fillRect(SX, SY, W, 18)
  gfx.setColor(gfx.kColorBlack)
  -- rain as the storm grows
  local storm = U.clamp(f / max(1, R) * 1.4, 0, 1)
  if storm > 0.3 then
    for k = 0, 9 do
      local x = SX + (hh(k * 13 + f) % W)
      local y = SY + (hh(k * 7 + f * 3) % H)
      gfx.drawLine(x, y, x - 3, y + 8)
    end
  end
  -- lighthouse on a rock, flashing
  gfx.fillRect(SX + 16, SY + 54, 6, 22)
  gfx.fillCircleAtPoint(SX + 19, SY + 80, 10)
  if (f // 6) % 8 == 0 then
    gfx.setColor(gfx.kColorBlack)
    gfx.setDitherPattern(0.5, gfx.kDitherTypeBayer4x4)
    gfx.fillTriangle(SX + 19, SY + 56, SX + W, SY + 40, SX + W, SY + 66)
    gfx.setColor(gfx.kColorBlack)
  end
  -- the ship rolls
  local roll = sin(f * 0.07) * (4 + storm * 8)
  local sx, sy = SX + W * 0.55 + sin(f * 0.01) * 20, SY + 76 + sin(f * 0.09) * 3
  Art.poly[1], Art.poly[2] = sx - 34, sy - roll
  Art.poly[3], Art.poly[4] = sx + 34, sy + roll
  Art.poly[5], Art.poly[6] = sx + 26, sy + 12 + roll
  Art.poly[7], Art.poly[8] = sx - 28, sy + 12 - roll
  Art.polyFill(8)
  gfx.fillRect(sx - 6, sy - 22 - roll * 0.1, 8, 20)
  gfx.drawLine(sx - 20, sy - roll * 0.6, sx - 18, sy - 34)
  gfx.drawLine(sx + 18, sy + roll * 0.6, sx + 16, sy - 30)
  gfx.setPattern(Art.pat.gray50)
  gfx.fillCircleAtPoint(sx - 10 - (f % 40), sy - 30 - (f % 40) * 0.4, 5 + (f % 40) * 0.2)
  -- waves: rows of crests
  for row = 0, 4 do
    local y = SY + 84 + row * 11
    local amp = 2 + row + storm * 4
    gfx.setColor(gfx.kColorBlack)
    gfx.setPattern(row % 2 == 0 and Art.pat.gray50 or Art.pat.gray75)
    gfx.fillRect(SX, y + 2, W, 12)
    gfx.setColor(gfx.kColorWhite)
    local px, py = SX, y + sin(f * 0.15 + row) * amp
    for x = SX + 8, SX + W, 8 do
      local ny = y + sin(f * 0.15 + row + (x - SX) * 0.08) * amp
      gfx.drawLine(px, py, x, ny)
      px, py = x, ny
    end
  end
  gfx.setColor(gfx.kColorBlack)
end

local function drawRomance(f, R, reel)
  local W, H = SW, SH
  local p = f / max(1, R)
  -- dusk sky, rising moon
  gfx.setPattern(Art.pat.gray12)
  gfx.fillRect(SX, SY, W, 70)
  gfx.setColor(gfx.kColorWhite)
  local my = SY + 70 - min(1, f / 500) * 48
  gfx.fillCircleAtPoint(SX + W * 0.7, my, 13)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawCircleAtPoint(SX + W * 0.7, my, 13)
  -- sea and pier
  gfx.setPattern(Art.pat.waves)
  gfx.fillRect(SX, SY + 70, W, 40)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(SX, SY + 104, W, 5)
  for x = SX + 4, SX + W, 16 do gfx.fillRect(x, SY + 109, 3, 29) end
  gfx.drawLine(SX, SY + 94, SX + W, SY + 94)
  for x = SX + 8, SX + W, 12 do gfx.drawLine(x, SY + 94, x, SY + 104) end
  gfx.fillRect(SX + 30, SY + 60, 2, 44)
  gfx.fillCircleAtPoint(SX + 31, SY + 58, 4)
  -- they walk toward each other and meet
  local meet = U.smoothstep(min(1, f / 520))
  local leg = meet < 1 and (f // 4) % 2 or 0
  local x1 = SX + 14 + (W / 2 - 22) * meet
  local x2 = SX + W - 14 - (W / 2 - 22) * meet
  fig(x1, SY + 104, 1.3, 1, leg)
  -- the lady, with a parasol
  gfx.fillCircleAtPoint(x2, SY + 104 - 25, 3.5)
  gfx.fillTriangle(x2, SY + 104 - 21, x2 - 7, SY + 104, x2 + 7, SY + 104)
  gfx.drawLine(x2 + 4, SY + 104 - 16, x2 + 8, SY + 104 - 34)
  gfx.fillEllipseInRect(x2 - 2, SY + 104 - 40, 20, 8, 270, 90)
  if meet >= 1 then
    -- a heart rises between them
    local hy = SY + 60 - min(30, (f - 520) * 0.2)
    local hx = SX + W / 2
    gfx.fillCircleAtPoint(hx - 4, hy, 5)
    gfx.fillCircleAtPoint(hx + 4, hy, 5)
    gfx.fillTriangle(hx - 9, hy + 1, hx + 9, hy + 1, hx, hy + 12)
  end
end

local function drawComedy(f, R, reel)
  local W, H = SW, SH
  gfx.setColor(gfx.kColorBlack)
  -- promenade railings and sea
  gfx.setPattern(Art.pat.hlines2)
  gfx.fillRect(SX, SY + 50, W, 36)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(SX, SY + 86, W, 3)
  for x = SX + 6 - (f * 1.5) % 14, SX + W, 14 do gfx.fillRect(x, SY + 70, 2, 16) end
  gfx.drawLine(SX, SY + 70, SX + W, SY + 70)
  -- the wind
  for k = 0, 4 do
    local x = SX + (hh(k * 31) + f * 6) % (W + 40) - 20
    local y = SY + 12 + k * 9
    gfx.drawLine(x, y, x + 16, y)
  end
  -- the hat bounces along, its owner in pursuit
  local run = (f * 1.8) % (W + 80)
  local hx = SX + run - 20
  local hy = SY + 120 - abs(sin(f * 0.2)) * 22
  gfx.fillRect(hx - 5, hy - 6, 10, 6)
  gfx.fillRect(hx - 8, hy, 16, 2)
  local leg = (f // 3) % 2
  fig(hx - 44, SY + 128, 1.4, 0, leg)
  gfx.drawLine(hx - 44, SY + 128 - 30, hx - 34, SY + 128 - 36) -- reaching arm
  -- a lady's umbrella turns inside out
  local ux = SX + W - 40
  fig(ux, SY + 128, 1.3, 0, 0)
  if (f // 60) % 2 == 0 then
    gfx.fillEllipseInRect(ux - 14, SY + 128 - 46, 28, 12, 270, 90)
  else
    gfx.drawLine(ux, SY + 128 - 30, ux - 12, SY + 128 - 50)
    gfx.drawLine(ux, SY + 128 - 30, ux + 12, SY + 128 - 50)
    gfx.drawLine(ux - 12, SY + 128 - 50, ux + 12, SY + 128 - 50)
  end
  gfx.drawLine(ux, SY + 128 - 16, ux, SY + 128 - 34)
end

local function drawStrange(f, R, reel)
  local W, H = SW, SH
  local p = f / max(1, R)
  gfx.setPattern(Art.pat.gray50)
  gfx.fillRect(SX, SY, W, H)
  -- the booth window at the back, its beam pointing at us
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(SX + W / 2 - 8, SY + 10, 16, 10)
  if p > 0.4 then
    gfx.setColor(gfx.kColorWhite)
    gfx.setDitherPattern(0.75, gfx.kDitherTypeBayer4x4)
    gfx.fillTriangle(SX + W / 2, SY + 15, SX + 10, SY + H, SX + W - 10, SY + H)
  end
  -- rows of heads, facing us; eyes open one by one
  local seen = floor(p * 22)
  local n = 0
  for row = 0, 2 do
    local y = SY + 50 + row * 30
    local r = 7 + row * 2
    for k = 0, 6 - row % 2 do
      local x = SX + 16 + k * 26 + (row % 2) * 13
      gfx.setColor(gfx.kColorBlack)
      gfx.fillCircleAtPoint(x, y, r)
      gfx.fillRoundRect(x - r - 4, y + r - 2, 2 * r + 8, 16, 4)
      n = n + 1
      if n <= seen then
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(x - r * 0.45, y - 1, 2, 2)
        gfx.fillRect(x + r * 0.3, y - 1, 2, 2)
      end
    end
  end
  gfx.setColor(gfx.kColorBlack)
end

local DRAWERS <const> = { drawTrain, drawChase, drawSea, drawRomance, drawComedy, drawStrange }

------------------------------------------------------------------------
-- drawing: the auditorium
------------------------------------------------------------------------
function Proj:drawTitleCard(l1, l2, small)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(SX, SY, SW, SH)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawRect(SX + 8, SY + 8, SW - 16, SH - 16)
  gfx.drawRect(SX + 11, SY + 11, SW - 22, SH - 22)
  gfx.fillRect(SX + 8, SY + 8, 6, 6) gfx.fillRect(SX + SW - 14, SY + 8, 6, 6)
  gfx.fillRect(SX + 8, SY + SH - 14, 6, 6) gfx.fillRect(SX + SW - 14, SY + SH - 14, 6, 6)
  if small then UI.textW(small, SX + SW / 2, SY + 24, "center") end
  UI.textW(l1, SX + SW / 2, SY + 52, "center", UI.bold)
  if l2 then UI.textW(l2, SX + SW / 2, SY + 72, "center", UI.bold) end
  gfx.drawLine(SX + SW / 2 - 30, SY + 100, SX + SW / 2 + 30, SY + 100)
  gfx.setColor(gfx.kColorBlack)
end

function Proj:drawScreen()
  local st = self.state
  gfx.setClipRect(SX, SY, SW, SH)
  local reel = self.reel
  local f = self.f
  local fr = floor(f)
  if st == "intermission" or (st == "over" and self.post > 1) then
    self:drawTitleCard(st == "over" and "THE END" or "INTERMISSION", nil, st == "over" and "FIN" or nil)
  elseif st == "stopped" or st == "thread" or st == "closing" or self.blackT > 0 then
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(SX, SY, SW, SH)
  elseif st == "runout" then
    -- clear leader flapping through: white, scratched, flickering
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(SX, SY, SW, SH)
    gfx.setColor(gfx.kColorBlack)
    for k = 0, 5 do
      local x = SX + hh(fr * 5 + k) % SW
      gfx.drawLine(x, SY, x + (k % 3) - 1, SY + SH)
    end
    if fr % 2 == 0 then
      gfx.setDitherPattern(0.3, gfx.kDitherTypeBayer4x4)
      gfx.fillRect(SX, SY, SW, SH)
    end
    gfx.setColor(gfx.kColorBlack)
  else
    -- gate weave: the picture shivers a pixel
    local weave = (hh(fr) % 3) - 1
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(SX, SY, SW, SH)
    gfx.setColor(gfx.kColorBlack)
    gfx.setDrawOffset(0, weave)
    if fr < 44 then
      self:drawTitleCard(reel.title1, reel.title2, reel.label)
    elseif st ~= "over" and fr >= reel.R - 2 * reel.endFps and not self:hasNext() then
      self:drawTitleCard("THE END", nil, nil)
    else
      DRAWERS[reel.kind](f, reel.R, reel)
      -- the romance's intertitle
      if reel.kind == K_ROMANCE and fr >= 530 and fr < 575 then self:drawTitleCard("AT LAST.", nil, nil) end
      if reel.kind == K_STRANGE and f / reel.R > 0.8 then self:drawTitleCard("WE CAN SEE", "YOU TOO.", nil) end
    end
    gfx.setDrawOffset(0, 0)
    -- film grain: a long scratch, dust and hairs that change every frame
    gfx.setColor(gfx.kColorBlack)
    local sx = SX + hh(fr // 20 + 3) % SW
    gfx.drawLine(sx, SY, sx + 1, SY + SH)
    for k = 0, 2 do
      local h = hh(fr * 3 + k)
      local x, y = SX + h % SW, SY + (h // 7) % SH
      if k == 0 then gfx.drawLine(x, y, x + 4, y + 2) else gfx.fillRect(x, y, 2, 2) end
    end
    gfx.setColor(gfx.kColorWhite)
    local h2 = hh(fr * 11 + 5)
    gfx.fillRect(SX + h2 % SW, SY + (h2 // 3) % SH, 2, 1)
    -- cue dots: scratched circles in the top-right corner
    if self:hasNext() then
      local cue1, cue2 = self:cues()
      if (f >= cue1 and f < cue1 + self.cueDur) or (f >= cue2 and f < cue2 + self.cueDur) then
        gfx.setColor(gfx.kColorWhite)
        gfx.fillCircleAtPoint(SX + SW - 20, SY + 18, 9)
        gfx.setColor(gfx.kColorBlack)
        gfx.fillCircleAtPoint(SX + SW - 20, SY + 18, 7)
      end
    end
    -- a stuck frame burns: a white hole with a charred rim
    if st == "jam" or (self.burn > 0 and st ~= "run") then
      local r = self.burn * 70 + 3
      gfx.setColor(gfx.kColorBlack)
      gfx.fillCircleAtPoint(self.burnX, self.burnY, r + 4)
      gfx.setPattern(Art.pat.gray50)
      gfx.fillCircleAtPoint(self.burnX, self.burnY, r + 2)
      gfx.setColor(gfx.kColorWhite)
      gfx.fillCircleAtPoint(self.burnX, self.burnY, r)
    end
    -- too slow: the shutter's flicker shows; a cooling arc dims the image
    local shade = 0
    if st == "run" and self.fps < 12 and ((f * 2) % 1) < 0.5 then shade = 0.55 * (12 - self.fps) / 12 + 0.2 end
    shade = max(shade, (1 - self.heat[self.proj]) * 0.85)
    if shade > 0.05 then
      gfx.setColor(gfx.kColorBlack)
      gfx.setDitherPattern(shade, gfx.kDitherTypeBayer4x4)
      gfx.fillRect(SX, SY, SW, SH)
    end
  end
  gfx.clearClipRect()
  gfx.setColor(gfx.kColorBlack)
end

function Proj:drawHall()
  -- the picture house: dark hall, curtains, proscenium
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(0, 18, 222, 204)
  gfx.setPattern(Art.pat.vlines)
  gfx.fillRect(0, 18, 14, 162)
  gfx.fillRect(206, 18, 16, 162)
  gfx.setColor(gfx.kColorBlack)
  for x = 0, 212, 14 do gfx.fillCircleAtPoint(x + 7, 22, 7) end
  gfx.setColor(gfx.kColorWhite)
  gfx.drawRect(SX - 2, SY - 2, SW + 4, SH + 4)
  gfx.setColor(gfx.kColorBlack)
end

function Proj:drawAudience()
  gfx.setClipRect(0, 18, 222, 204)
  -- light spilling from the screen over the stalls
  gfx.setPattern(Art.pat.gray50)
  gfx.fillRect(14, 168, 192, 12)
  gfx.setPattern(Art.pat.gray75)
  gfx.fillRect(0, 180, 222, 14)
  gfx.setPattern(Art.pat.gray87)
  gfx.fillRect(0, 194, 222, 28)
  local t = self.t
  local laugh = self.laughT > 0
  local slump = self.mood < 0.35
  for i = 1, SEATS do
    if self.present[i] then
      local back = i <= 7
      local r = back and 8 or 10
      local x = self.seatX[i]
      local y = self.seatY[i]
      if self.leaveT[i] > 0 then
        -- walks out along the row, stooping
        x = x + (i % 2 == 0 and 1 or -1) * self.leaveT[i] * 90
        y = y + 4
      end
      if laugh then y = y - abs(sin(t * 18 + i)) * 3 end
      if slump then y = y + 3 end
      -- rim light from the screen
      gfx.setColor(gfx.kColorWhite)
      gfx.fillCircleAtPoint(x, y - r - 1, r)
      gfx.fillRoundRect(x - r - 4, y - 3, 2 * r + 8, 24, 5)
      gfx.setColor(gfx.kColorBlack)
      gfx.fillCircleAtPoint(x, y - r, r)
      gfx.fillRoundRect(x - r - 4, y - 2, 2 * r + 8, 24, 5)
      local hat = self.hat[i]
      if hat == 1 then
        gfx.fillCircleAtPoint(x, y - r - 5, r - 2)
        gfx.fillRect(x - r - 3, y - r - 3, 2 * r + 6, 2)
      elseif hat == 2 then
        gfx.fillRect(x - r + 2, y - 2 * r - 8, 2 * r - 4, 12)
        gfx.fillRect(x - r - 2, y - r - 4, 2 * r + 4, 2)
      elseif hat == 3 then
        gfx.fillEllipseInRect(x - r - 3, y - 2 * r - 2, 2 * r + 6, r)
        gfx.drawLine(x + r - 2, y - 2 * r, x + r + 6, y - 2 * r - 9)
        gfx.drawLine(x + r - 1, y - 2 * r, x + r + 8, y - 2 * r - 6)
      end
    end
  end
  -- boos
  for i = 1, BOOS_MAX do
    if self.booT[i] > 0 then
      local x, y = self.booX[i], self.booY[i] - (1.2 - self.booT[i]) * 12
      gfx.setColor(gfx.kColorWhite)
      gfx.fillRoundRect(x - 18, y - 2, 36, 18, 4)
      gfx.setColor(gfx.kColorBlack)
      gfx.drawRoundRect(x - 18, y - 2, 36, 18, 4)
      UI.text("BOO", x, y, "center", UI.bold)
    end
  end
  -- hats in flight
  for i = 1, HATS_MAX do
    if self.hatOn[i] then
      local x, y = self.hatX[i], self.hatY[i]
      local a = self.hatA[i]
      gfx.setColor(gfx.kColorWhite)
      gfx.fillCircleAtPoint(x, y, 6)
      gfx.setColor(gfx.kColorBlack)
      gfx.fillCircleAtPoint(x, y, 4)
      gfx.drawLine(x - cos(a) * 7, y - sin(a) * 7, x + cos(a) * 7, y + sin(a) * 7)
    end
  end
  gfx.clearClipRect()
  gfx.setColor(gfx.kColorBlack)
end

------------------------------------------------------------------------
-- drawing: the booth
------------------------------------------------------------------------
local function arcLamp(x, y, heat, struck)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawCircleAtPoint(x, y, 6)
  if heat > 0.05 then
    Art.setShade(1 - heat)
    gfx.fillCircleAtPoint(x, y, 5)
    gfx.setColor(gfx.kColorBlack)
    if heat > 0.9 then
      for k = 0, 7 do
        local a = k * 0.785
        gfx.drawLine(x + sin(a) * 8, y - cos(a) * 8, x + sin(a) * 11, y - cos(a) * 11)
      end
    end
  end
end

function Proj:drawBooth()
  local x0 = 224
  UI.panel(x0, 18, 176, 204, "plain")
  local reel = self.reel
  local R = reel.R
  local prog = U.clamp(self.f / max(1, R), 0, 1)
  -- which projector
  UI.text(self.proj == 1 and "PROJ. I" or "PROJ. II", x0 + 6, 21, "left", UI.bold)
  arcLamp(x0 + 98, 29, self.heat[self.proj], true)
  local o = 3 - self.proj
  UI.text(o == 1 and "I" or "II", x0 + 124, 21, "left", UI.bold)
  arcLamp(x0 + 154, 29, self.heat[o], self.struck[o])
  gfx.drawLine(x0 + 4, 40, x0 + 172, 40)

  -- the mechanism
  local fx, fy = 256, 66
  local rf = 8 + 20 * (1 - prog)
  local rt = 8 + 20 * prog
  local tx, ty = 256, 190
  local spin = self.f * 9
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(fx, fy, rf + 2)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(fx, fy, 6)
  for k = 0, 2 do
    local a = rad(-spin * 12 / rf + k * 120)
    gfx.drawLine(fx + sin(a) * 6, fy - cos(a) * 6, fx + sin(a) * (rf - 1), fy - cos(a) * (rf - 1))
  end
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(tx, ty, rt + 2)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(tx, ty, 6)
  for k = 0, 2 do
    local a = rad(-spin * 12 / rt + k * 120)
    gfx.drawLine(tx + sin(a) * 6, ty - cos(a) * 6, tx + sin(a) * (rt - 1), ty - cos(a) * (rt - 1))
  end
  gfx.setColor(gfx.kColorBlack)
  -- housing, lamp house, lens
  gfx.setPattern(Art.pat.gray25)
  gfx.fillRect(282, 92, 34, 64)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(282, 92, 34, 64)
  gfx.fillRect(300, 100, 22, 34)
  gfx.setColor(gfx.kColorWhite)
  for vy = 104, 128, 6 do gfx.drawLine(304, vy, 318, vy) end
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(268, 112, 16, 10)
  -- the film path with its two loops
  local s = self.loop
  gfx.setLineWidth(2)
  gfx.drawLine(fx + rf, fy, 288, 92)
  local bulge = 4 + s * 26
  local px, py = 288, 92
  for k = 1, 8 do
    local u = k / 8
    local nx = 288 - sin(u * 3.1416) * bulge
    local ny = 92 + u * 16
    gfx.drawLine(px, py, nx, ny)
    px, py = nx, ny
  end
  gfx.drawLine(288, 108, 288, 134)
  local bulge2 = 4 + s * 20
  px, py = 288, 134
  for k = 1, 8 do
    local u = k / 8
    local nx = 288 - sin(u * 3.1416) * bulge2
    local ny = 134 + u * 16
    gfx.drawLine(px, py, nx, ny)
    px, py = nx, ny
  end
  gfx.drawLine(288, 150, tx + rt, ty)
  gfx.setLineWidth(1)
  -- sprockets and gate
  for k = 0, 1 do
    local sy = k == 0 and 92 or 150
    gfx.fillCircleAtPoint(290, sy, 5)
    local a0 = rad(-self.f * 45)
    for tth = 0, 5 do
      local a = a0 + tth * 1.047
      gfx.drawLine(290 + sin(a) * 4, sy - cos(a) * 4, 290 + sin(a) * 7, sy - cos(a) * 7)
    end
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(290, sy, 1.5)
    gfx.setColor(gfx.kColorBlack)
  end
  local gateOpen = self.state == "thread" or self.state == "closing"
  gfx.fillRect(gateOpen and 292 or 285, 110, 6, 22)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(gateOpen and 293 or 286, 116, 4, 10)
  gfx.setColor(gfx.kColorBlack)
  if self.state == "jam" then
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(289, 121, 3 + self.burn * 5)
    gfx.setColor(gfx.kColorBlack)
  end
  -- the crank turns with yours
  local ca = Crank.position()
  local cx, cy = 312, 176
  gfx.drawCircleAtPoint(cx, cy, 4)
  gfx.setLineWidth(3)
  gfx.drawLine(cx, cy, cx + sin(rad(ca)) * 14, cy - cos(rad(ca)) * 14)
  gfx.setLineWidth(1)
  gfx.fillCircleAtPoint(cx + sin(rad(ca)) * 14, cy - cos(rad(ca)) * 14, 3)

  -- speed dial with the film's band
  local mx, my = 364, 72
  local tgt = self.target or 16
  UI.meter(mx, my, 27, self.fps / 32, -120, 120, 8)
  local a0 = -120 + 240 * U.clamp(tgt * (1 - self.tol) / 32, 0, 1)
  local a1 = -120 + 240 * U.clamp(tgt * (1 + self.tol) / 32, 0, 1)
  gfx.setLineWidth(5)
  gfx.drawArc(mx, my, 19, a0 < 0 and a0 + 360 or a0, a1 < 0 and a1 + 360 or a1)
  gfx.setLineWidth(1)
  gfx.setLineWidth(2)
  local na = rad(-120 + 240 * U.clamp(self.fps / 32, -0.05, 1.05))
  gfx.drawLine(mx, my, mx + sin(na) * 23, my - cos(na) * 23)
  gfx.setLineWidth(1)
  gfx.fillCircleAtPoint(mx, my, 3)
  UI.text(U.cached("proj_fps", "%d", floor(self.fps + 0.5)), mx, my + 8, "center", UI.bold)
  UI.text("FPS", mx, 102, "center")
  local dn, nf = self:nextChange(self.f)
  if dn and dn < 3 * tgt and floor(self.t * 3) % 2 == 0 then
    UI.text(nf > tgt and "FASTER" or "SLOWER", mx, 42, "center")
  end
  -- loop gauge: the slack between sprocket and gate
  local gx, gy, gw, gh = 336, 122, 12, 64
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(gx, gy, gw, gh)
  gfx.setPattern(Art.pat.hatch)
  gfx.fillRect(gx, gy, gw, gh * 0.15)
  gfx.fillRect(gx, gy + gh * 0.85, gw, gh * 0.15)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(gx, gy, gw, gh)
  local ly = gy + gh * (1 - s)
  gfx.fillRect(gx - 3, ly - 2, gw + 6, 4)
  UI.text("LOOP", gx + gw / 2, 190, "center")
  -- the house
  local hx = 370
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(hx, gy, gw, gh)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(hx, gy, gw, gh)
  local mh = floor((gh - 4) * self.mood)
  gfx.fillRect(hx + 2, gy + gh - 2 - mh, gw - 4, mh)
  UI.text("HOUSE", hx + gw / 2, 204, "center")
  -- reel footage left, with cue marks
  gfx.drawRect(x0 + 6, 208, 90, 6)
  gfx.fillRect(x0 + 8, 210, floor(86 * (1 - prog)), 2)

  -- re-threading instructions
  local st = self.state
  if st == "thread" or st == "closing" or st == "stopped" then
    UI.panel(x0 + 4, 92, 112, 66, "ink")
    if st == "stopped" then
      UI.textW("B: OPEN", x0 + 60, 99, "center", UI.bold)
      UI.textW("THE GATE", x0 + 60, 117, "center")
    elseif st == "thread" then
      UI.textW("THREAD", x0 + 60, 98, "center", UI.bold)
      for i = 1, 4 do
        local ax, ay = x0 + 21 + (i - 1) * 26, 136
        local d = self.seq[i]
        gfx.setColor(gfx.kColorWhite)
        if i < self.seqI then
          gfx.fillRect(ax - 8, ay - 8, 16, 16)
          gfx.setColor(gfx.kColorBlack)
        elseif i == self.seqI and floor(self.t * 4) % 2 == 0 then
          gfx.drawRect(ax - 10, ay - 10, 20, 20)
        end
        if d == 1 then gfx.fillTriangle(ax - 6, ay + 4, ax + 6, ay + 4, ax, ay - 6)
        elseif d == 2 then gfx.fillTriangle(ax + 4, ay - 6, ax + 4, ay + 6, ax - 6, ay)
        elseif d == 3 then gfx.fillTriangle(ax - 6, ay - 4, ax + 6, ay - 4, ax, ay + 6)
        else gfx.fillTriangle(ax - 4, ay - 6, ax - 4, ay + 6, ax + 6, ay) end
        gfx.setColor(gfx.kColorBlack)
      end
    else
      UI.textW("A: CLOSE", x0 + 60, 99, "center", UI.bold)
      UI.textW("THE GATE", x0 + 60, 117, "center")
    end
  end
end

function Proj:draw()
  gfx.clear(gfx.kColorWhite)
  self:drawHall()
  self:drawScreen()
  self:drawAudience()
  self:drawBooth()
  UI.header(7, "PROJECTIONIST", self.tut and "LESSON" or self.hdr)
  if self.msgT > 0 and self.msg then
    local nl = #UI.wrap(self.msg, SW - 24, UI.bold)
    local h = 8 + nl * UI.boldH
    UI.panel(SX + 6, SY + SH - 4 - h, SW - 12, h, "ink")
    UI.textBlock(self.msg, SX + 12, SY + SH - h, SW - 24, UI.bold, 0, nil, true, "center")
  end
  if not self.tut then UI.hints(Proj.HINTS) end
end

------------------------------------------------------------------------
-- suspend / resume
------------------------------------------------------------------------
function Proj:serialize()
  local reels = {}
  for i = 1, #self.reels do
    local r = self.reels[i]
    reels[i] = { kind = r.kind, sf = r.sf, sfps = r.sfps, p1 = r.p1, p2 = r.p2, p3 = r.p3, R = r.R, endFps = r.endFps, idx = i }
  end
  local st = self.state
  if st == "jam" then st = "stopped" end
  return {
    rng = self.rng:state(), t = self.t, prog = self.prog, score = self.score, reels = reels, reelIdx = self.reelIdx,
    f = self.f, loop = self.loop, state = st, proj = self.proj, heat = self.heat, struck = self.struck,
    mood = self.mood, present = self.present, patience = self.patience, hat = self.hat,
    burn = self.burn, burnX = self.burnX, burnY = self.burnY, jams = self.jams, progJams = self.progJams,
    perfects = self.perfects, tol = self.tol, interT = self.interT, cue1 = self.cue1Seen, cue2 = self.cue2Seen,
  }
end

function Proj:deserialize(t)
  self.rng:setState(t.rng)
  self.t, self.prog, self.score = t.t or 0, t.prog, t.score
  local n = #t.reels
  self.reels = {}
  for i = 1, n do
    local r = t.reels[i]
    r.title1, r.title2 = TITLES[r.kind][1], TITLES[r.kind][2]
    r.label = "REEL " .. i .. "/" .. n
    self.reels[i] = r
  end
  self:loadReel(t.reelIdx)
  self.f = t.f
  self.loop = t.loop
  self.state = t.state
  if self.state == "over" then self.state = "run" end
  self.proj = t.proj
  self.heat, self.struck = t.heat, t.struck
  self.mood = t.mood
  self.present, self.patience, self.hat = t.present, t.patience, t.hat
  for i = 1, SEATS do self.lowT[i], self.leaveT[i] = 0, 0 end
  self.burn, self.burnX, self.burnY = t.burn or 0, t.burnX or 0, t.burnY or 0
  self.jams, self.progJams, self.perfects = t.jams or 0, t.progJams or 0, t.perfects or 0
  self.tol = t.tol or self.tol
  self.interT = t.interT or 0
  self.cue1Seen, self.cue2Seen = t.cue1, t.cue2
  self.vH, self.vF = 0, 0
  self.grace = 4
  if self.state == "thread" then self.state = "stopped" end
end
