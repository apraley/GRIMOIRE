-- Scripted proof of the SAILBOAT WINCH mechanics:
--   MOCK_DATA_DIR=/tmp/ci-winch lua5.4 tools/test_winch.lua
-- * the tutorial completes by doing what each lesson says
-- * trimming to the tell-tales beats bad trim (speed / VMG, via the crank)
-- * HIGH gear stalls under a close-hauled load, LOW gear hauls it
-- * a tack needs the old sheet cast off and the new one ground in
-- * a scripted sailor who trims and tacks well wins races; a lazy one doesn't
local H = dofile("tools/harness.lua")
H.shotDir = "shots/winch"
H.boot({ wipe = true })
H.run(2)

local abs = math.abs
local fails = 0
local function check(c, msg)
  print((c and "PASS  " or "FAIL  ") .. msg)
  if not c then fails = fails + 1 end
end

local function compass(dx, dy) return math.deg(math.atan(dx, -dy)) % 360 end

------------------------------------------------------------------------
-- Pilot: drives the real inputs (crank degrees + buttons) frame by frame
------------------------------------------------------------------------
local Pilot = {}
Pilot.__index = Pilot

function Pilot.new(opts)
  return setmetatable({ o = opts or {}, btn = nil, btnF = 0, gap = 0, steer = 0, turns = 0, shifts = 0, stalls = 0 }, Pilot)
end

function Pilot:button(name, frames)
  if self.btn or self.gap > 0 then return false end
  self.btn, self.btnF = name, frames or 1
  H.hold(name)
  if name == "a" then self.shifts = self.shifts + 1 end
  return true
end

function Pilot:setSteer(d)
  if d == self.steer then return end
  H.release("left") H.release("right")
  if d < 0 then H.hold("left") elseif d > 0 then H.hold("right") end
  self.steer = d
end

function Pilot:frame(crank)
  crank = crank or 0
  self.turns = self.turns + abs(crank) / 360
  H.frame(crank)
  if self.gap > 0 then self.gap = self.gap - 1 end
  if self.btn then
    self.btnF = self.btnF - 1
    if self.btnF <= 0 then H.release(self.btn) self.btn = nil self.gap = 2 end
  end
end

function Pilot:steerTo(m, want, dead)
  local d = U.angleDiff(m.b.hd, want)
  dead = dead or 4
  self:setSteer(d > dead and 1 or (d < -dead and -1 or 0))
end

local function desiredL(m, i, alpha)
  local A = abs(m.b.awa)
  if i == 2 then return U.clamp((A - alpha - 4) / 10.8, 0, 7.5) end
  return U.clamp((A - alpha - 10) / 9.6, 0, 10.5)
end

-- choose a line, cast off / select / shift gear; returns crank degrees
function Pilot:trim(m, alpha, only, mainIn)
  local b = m.b
  alpha = alpha or 18
  local win = 4 - b.lee
  if not self.o.noCast and only ~= 2 and b.L[win] < 8 and not b.run[win] and abs(b.twa) > 20 then
    if m.sel ~= win then self:button("b", 1) else self:button("b", 14) end
    return 0
  end
  local dM = mainIn and 0.6 or desiredL(m, 2, alpha)
  -- a good sailor eases the main when a gust lays the boat over
  if self.o.depower ~= false and b.heel > 30 and not mainIn then dM = math.max(dM, b.L[2] + 0.5) end
  local dJ = desiredL(m, b.lee, alpha)
  local eM, eJ = b.L[2] - dM, b.L[b.lee] - dJ
  local target
  if only then target = only
  elseif m.sel == 2 and abs(eM) > 0.15 then target = 2
  elseif m.sel == b.lee and abs(eJ) > 0.15 then target = b.lee
  else target = abs(eJ) > abs(eM) and b.lee or 2 end
  local e = target == 2 and eM or eJ
  if abs(e) < 0.15 then return 0 end
  if m.sel ~= target then self:button("b", 1) return 0 end
  if e > 0 then
    if m.gear == 1 and m.strain > 0.2 then self.stalls = self.stalls + 1 self:button("a", 1)
    elseif m.gear == 2 and e > 1.5 and b.T[target] < m.cap[1] * 0.45 then self:button("a", 1) end
    return self.o.crank or 28
  end
  return -18
end

-- racing navigation: laylines upwind, gybe angles downwind, main in before a gybe
function Pilot:navigate(m)
  local b = m.b
  local mx, my = m:markPos()
  if not m.endless and m.mark > 3 then my = my - 40 end
  local brg = compass(mx - b.x, my - b.y)
  local rel = U.angleDiff(b.twd, brg)
  local side = b.tackSide
  local want
  if abs(rel) < 44 - (self.direct and 4 or 0) then
    self.direct = false
    want = b.twd - side * 42
  elseif abs(rel) > 150 + (self.direct and 5 or 0) then
    self.direct = false
    want = b.twd - side * 150
  else
    self.direct = true
    want = brg
  end
  -- gybe preparation: haul the main in, then turn
  local wantTwa = U.angleDiff(want, b.twd)
  local gybing = abs(wantTwa) > 90 and (wantTwa > 0 and 1 or -1) ~= side and abs(b.twa) > 100
  if gybing and b.L[2] > 1.2 and not self.o.crashGybe then
    want = b.hd
    return want, true
  end
  return want, gybing
end

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------
local function calm(m, tws)
  m.gustRate = 0
  for i = 1, #m.patches do m.patches[i].on = false end
  m.shiftAmp = 0
  m.tws0 = tws or m.tws0
  m.rival = nil
  m.mark = 1
end

local function sail(m, pilot, frames, want, alpha, only)
  local sum, n = 0, 0
  for f = 1, frames do
    pilot:steerTo(m, want)
    local c = pilot:trim(m, alpha, only)
    pilot:frame(c)
    if f > frames - 300 then sum = sum + m.b.v n = n + 1 end
  end
  pilot:setSteer(0)
  return sum / math.max(1, n)
end

------------------------------------------------------------------------
-- 1. tutorial, following the lesson texts
------------------------------------------------------------------------
do
  local m = H.goMachine("winch", "tutorial")
  local p = Pilot.new()
  local shotStep = {}
  local frames = 0
  while m.coach and not m.coach.done and frames < 6000 do
    local i = m.coach.i
    local b = m.b
    if not shotStep[i] and m.coach.t > 0.5 then
      shotStep[i] = true
      H.shot(string.format("tut-step%02d", i))
    end
    local c = 0
    if i == 1 or i == 2 then
      c = 26                                 -- crank clockwise, keep going until it stalls
    elseif i == 3 then
      if m.gear == 1 then p:button("a", 1) end
    elseif i == 4 then
      c = p:trim(m, 18, 2)
    elseif i == 5 then
      if m.sel ~= 3 then p:button("b", 1) end
    elseif i == 6 then
      c = p:trim(m, 18, b.lee)
    elseif i == 7 then
      p:steerTo(m, 42)                        -- LEFT, up to close hauled on port tack
      c = p:trim(m, 18)
    elseif i == 8 then
      p:setSteer(-1)                          -- hold LEFT through the wind
    elseif i == 9 then
      p:setSteer(0)
      if m.sel ~= 3 then p:button("b", 1) else p:button("b", 14) end
    else
      p:steerTo(m, 318)
      c = p:trim(m, 18, b.lee)
    end
    p:frame(c)
    frames = frames + 1
  end
  p:setSteer(0)
  check(m.coach.done, string.format("tutorial completed by following the lessons (%d frames = %.0fs, %d gear shifts)", frames, frames / 30, p.shifts))
  H.run(90)
  check(Scene.current == ResultsScene, "tutorial reaches the results card")
  H.shot("tut-results")
  check(Save.machine("winch").tutorialDone == true, "tutorial marked done")
end

------------------------------------------------------------------------
-- 2. trim matters: speed / VMG with good vs bad trim (through the crank)
------------------------------------------------------------------------
local function trimRun(label, twa, mode)
  local m = H.goMachine("winch", "standard", { seed = 7 })
  calm(m, 12)
  local b = m.b
  b.hd = (-twa) % 360
  b.v = 3
  local p = Pilot.new()
  local sum, n = 0, 0
  for f = 1, 1200 do
    p:steerTo(m, (-twa) % 360, 2)
    local c = 0
    if mode == "good" then c = p:trim(m, 18)
    elseif mode == "tight" then c = p:trim(m, 400)   -- everything sheeted in hard
    elseif mode == "loose" then c = p:trim(m, -400) end -- everything eased, flogging
    p:frame(c)
    if f > 900 then sum = sum + b.v n = n + 1 end
  end
  p:setSteer(0)
  local v = sum / n
  local vmg = v * math.cos(math.rad(twa))
  return v, vmg, m
end

do
  local rows = {}
  for _, twa in ipairs({ 42, 90, 150 }) do
    local vg, mg, mgood = trimRun("good", twa, "good")
    if twa == 42 then H.shot("trim-good-closehauled") end
    local vt, mt = trimRun("tight", twa, "tight")
    if twa == 90 then H.shot("trim-tight-reach") end
    local vl, ml = trimRun("loose", twa, "loose")
    if twa == 90 then H.shot("trim-loose-reach") end
    print(string.format("  TWA %3d  good %.2f kn (VMG %5.2f)  over-trim %.2f (VMG %5.2f)  under-trim %.2f (VMG %5.2f)",
      twa, vg, mg, vt, mt, vl, ml))
    rows[twa] = { vg, vt, vl }
  end
  check(rows[42][1] > rows[42][3] * 1.3, "close-hauled: trimmed beats luffing sails")
  check(rows[90][1] > rows[90][2] * 1.15 and rows[90][1] > rows[90][3] * 1.15, "beam reach: trimmed beats over- and under-trimmed")
  check(rows[150][1] > rows[150][2] * 1.1, "broad reach: eased beats sheeted-in")
  -- pointing: the no-go zone
  local v30 = trimRun("good", 30, "good")
  local v42 = trimRun("good", 42, "good")
  print(string.format("  no-go: TWA 30 -> %.2f kn (VMG %.2f), TWA 42 -> %.2f kn (VMG %.2f)", v30, v30 * math.cos(math.rad(30)), v42, v42 * math.cos(math.rad(42))))
  check(v42 * math.cos(math.rad(42)) > v30 * math.cos(math.rad(30)) * 1.3, "pinching into the no-go zone kills VMG")
end

------------------------------------------------------------------------
-- 3. gearing: HIGH stalls under load, LOW hauls
------------------------------------------------------------------------
do
  local m = H.goMachine("winch", "standard", { seed = 3 })
  calm(m, 12)
  local b = m.b
  b.hd = 318
  b.v = 5.5
  local p = Pilot.new()
  -- get sailing trimmed, then ease the main 1.5 m
  sail(m, p, 450, 318, 18)
  if m.sel ~= 2 then
    for _ = 1, 3 do if m.sel ~= 2 then p:button("b", 1) for _ = 1, 4 do p:frame(0) end end end
  end
  if m.gear ~= 1 then p:button("a", 1) for _ = 1, 4 do p:frame(0) end end
  local L0 = b.L[2]
  for _ = 1, 12 do p:steerTo(m, 318) p:frame(-30) end
  local L1 = b.L[2]
  H.run(60)
  local load = b.T[2]
  local strainMax = 0
  for _ = 1, 60 do p:steerTo(m, 318) p:frame(30) strainMax = math.max(strainMax, m.strain) end
  local L2 = b.L[2]
  H.shot("gear-high-stalled")
  print(string.format("  main load %.0f, HIGH capacity %.0f, LOW capacity %.0f", load, m.cap[1], m.cap[2]))
  print(string.format("  eased %.2f -> %.2f m; 5 turns in HIGH hauled %.2f m (strain %.2f)", L0, L1, L1 - L2, strainMax))
  check(L1 - L2 < 0.5 * (L1 - L0) and strainMax > 0.5, "HIGH gear stalls before it can win back the eased sheet")
  p:button("a", 1) for _ = 1, 4 do p:frame(0) end
  local L3 = b.L[2]
  for _ = 1, 60 do p:steerTo(m, 318) p:frame(30) end
  local L4 = b.L[2]
  print(string.format("  5 turns in LOW hauled %.2f m (strain %.2f)", L3 - L4, m.strain))
  check(L4 <= L0 + 0.2, "LOW gear hauls it all back in against the same load")
  -- light load: HIGH gear flies when the sail is luffing
  p:setSteer(0)
end

------------------------------------------------------------------------
-- 4. tacking: needs a cast-off and furious grinding
------------------------------------------------------------------------
local function tackRun(mode)
  local m = H.goMachine("winch", "standard", { seed = 5 })
  calm(m, 12)
  local b = m.b
  b.hd = 318
  b.v = 5.5
  local p = Pilot.new({ noCast = mode == "nocast" })
  sail(m, p, 450, 318, 18)
  local v0 = b.v
  local turns0 = p.turns
  local shifts0 = p.shifts
  -- tack: steer to port-tack close hauled
  local f = 0
  local drawT = nil
  local minV = 99
  local shot = false
  while f < 450 do
    p:steerTo(m, 42, 3)
    local c = 0
    if mode ~= "none" and m.tacks > 0 then c = p:trim(m, 18) end
    p:frame(c)
    f = f + 1
    minV = math.min(minV, b.v)
    if m.tacks > 0 and not shot and m.strain > 0.3 then shot = true H.shot("tack-grinding-stall") end
    if m.tacks > 0 and not drawT and b.lee == 3 and b.stJ == 2 then drawT = f / 30 end
  end
  p:setSteer(0)
  return { v0 = v0, v = b.v, minV = minV, drawT = drawT, turns = p.turns - turns0, shifts = p.shifts - shifts0, st = b.stJ, backed = b.backed, stalls = p.stalls }
end

do
  local a = tackRun("grind")
  H.shot("tack-after-grind")
  local n = tackRun("none")
  H.shot("tack-no-grind")
  local c = tackRun("nocast")
  print(string.format("  grind:   %.2f kn before, min %.2f, %.2f kn 15s later; jib drawing after %.1fs; %.1f handle turns, %d gear shifts",
    a.v0, a.minV, a.v, a.drawT or -1, a.turns, a.shifts))
  print(string.format("  no crank: %.2f kn 15s later, jib state %s", n.v, n.st == 4 and "BACKED" or (n.st == 1 and "LUFF" or tostring(n.st))))
  print(string.format("  no cast-off: %.2f kn 15s later, jib state %s", c.v, c.st == 4 and "BACKED" or tostring(c.st)))
  check(a.drawT and a.drawT < 9, "grinding in the new sheet gets the jib drawing")
  check(a.turns > 5 and a.shifts >= 1, "a tack takes real grinding (>5 turns) and a gear change")
  check(a.v > n.v * 1.4, "tack with grinding is much faster than tacking and not grinding")
  check(c.st == 4 and a.v > c.v * 1.3, "not casting off leaves the jib backed and the boat slow")
end

------------------------------------------------------------------------
-- 5. the race: good sailor vs lazy sailor
------------------------------------------------------------------------
local function race(diff, opts, shots)
  local m = H.goMachine("winch", "standard", { difficulty = diff, seed = 1234 + diff })
  local p = Pilot.new(opts)
  local f = 0
  local shotAt = { [240] = "race-start", [1500] = "race-mid", [2700] = "race-late" }
  local lastMark, gybeShot = 1, false
  while not m.finished and f < 30 * 450 do
    local b = m.b
    local c = 0
    if opts.lazy then
      local want = p:navigate(m)
      p:steerTo(m, want)
    else
      local want, gybing = p:navigate(m)
      p:steerTo(m, want)
      c = p:trim(m, 18, nil, gybing)
      if gybing and shots and not gybeShot and b.L[2] < 1.3 then gybeShot = true H.shot("race-gybe-prep") end
    end
    p:frame(c)
    f = f + 1
    if shots and shotAt[f] then H.shot(shotAt[f]) end
    if shots and m.mark ~= lastMark then lastMark = m.mark H.shot("race-mark" .. (m.mark - 1)) end
  end
  p:setSteer(0)
  local res = m.finished
  local out = { t = m.raceT, won = m.rival and not m.rival.done, score = res and res.score or 0, title = res and res.title,
    tacks = m.tacks, gybes = m.gybes, crashes = m.crashes, knocks = m.knocks, turns = m.turns, mark = m.mark,
    rivalMark = m.rival and m.rival.mark, rivalT = m.rival and m.rival.finT }
  if shots then H.run(20) H.shot("race-finish") end
  H.run(120)
  if shots then H.shot("race-results") end
  return out
end

do
  for diff = 1, 3 do
    local g = race(diff, {}, diff == 1)
    print(string.format("  diff %d good sailor: %s  %.1fs  score %d  won=%s  rival %s  tacks %d gybes %d crashes %d knocks %d turns %.0f",
      diff, tostring(g.title), g.t, g.score, tostring(g.won), g.rivalT and g.rivalT > 0 and string.format("%.1fs", g.rivalT) or "-", g.tacks, g.gybes, g.crashes, g.knocks, g.turns))
    if diff == 1 then
      check(g.title ~= nil and g.title ~= "DID NOT FINISH", "good sailor finishes the race")
      check(g.won, "good sailor beats the difficulty-1 rival")
      check(g.score >= Machines.get("winch").medals.standard[2], "good sailor earns at least silver")
    end
  end
  local l = race(1, { lazy = true })
  print(string.format("  lazy sailor (steers, never trims): %s %.1fs score %d marks %d", tostring(l.title), l.t, l.score, l.mark - 1))
  local nc = race(1, { noCast = true })
  print(string.format("  sailor who never casts off: %s %.1fs score %d marks %d", tostring(nc.title), nc.t, nc.score, nc.mark - 1))
  local g1 = race(1, {})
  check(l.score < g1.score * 0.5, "lazy sailor scores far less than a trimmer")
  check(nc.score < g1.score, "not casting off the old sheet costs the race")
end

------------------------------------------------------------------------
-- 6. endless patrol & gybes & shots
------------------------------------------------------------------------
do
  local m = H.goMachine("winch", "endless", { difficulty = 2, seed = 99 })
  local p = Pilot.new()
  local f = 0
  while not m.finished and f < 30 * 200 do
    local want, gybing = p:navigate(m)
    p:steerTo(m, want)
    p:frame(p:trim(m, 18, nil, gybing))
    f = f + 1
    if f == 900 then H.shot("endless-sailing") end
  end
  p:setSteer(0)
  print(string.format("  endless (diff 2): %d buoys in %.0fs, knockdowns %d, finished=%s", m.buoys, f / 30, m.strikes, tostring(m.finished ~= nil)))
  check(m.buoys >= 4, "endless: the scripted sailor collects buoys")
  H.run(160)
end

do
  -- crash gybe vs controlled gybe
  local function gybe(mainIn)
    local m = H.goMachine("winch", "standard", { seed = 11 })
    calm(m, 13)
    local b = m.b
    b.hd = 200
    b.v = 5
    local p = Pilot.new()
    sail(m, p, 300, 200, 18)
    local pen0 = m.penalty
    for f = 1, 240 do
      p:steerTo(m, (f < 90 and mainIn) and 200 or 160)
      p:frame(mainIn and p:trim(m, 18, 2, true) or 0)
    end
    p:setSteer(0)
    return m.crashes, m.penalty - pen0, m.gybes
  end
  local c1, p1, g1 = gybe(false)
  H.shot("gybe-crash")
  local c2, p2, g2 = gybe(true)
  print(string.format("  gybe with main eased: gybes %d crashes %d penalty %d; main hauled in: gybes %d crashes %d penalty %d", g1, c1, p1, g2, c2, p2))
  check(c1 >= 1 and c2 == 0, "crash gybe only when the main is left eased")
end

print(fails == 0 and "OK winch scripted" or ("FAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)
