-- Scripted proof for No.VI ELEVATOR OPERATOR.
--   MOCK_DATA_DIR=/tmp/ci-elevator lua5.4 tools/test_elevator.lua
-- 1. the tutorial completes by doing what each lesson says
-- 2. a skilled operator (feathered lever, creep-in, level stops) earns a
--    good Standard score with perfect stops and no walk-outs
-- 3. a careless operator (full lever, snap to STOP) jolts and mis-levels
--    passengers and scores far less; an idle one is sacked
-- 4. endless ends after three walk-outs
local H = dofile("tools/harness.lua")
H.shotDir = "shots/elevator"
H.boot({ wipe = true })
H.run(2)

local fails = 0
local function check(c, msg)
  print((c and "ok   " or "FAIL ") .. msg)
  if not c then fails = fails + 1 end
end

local FLOOR_M = 3.5
local NEUTRAL = 12

-- lever angle that asks the motor for velocity v (inverse of the lever curve)
local function leverFor(v)
  local u = math.min(1, math.abs(v) / 3.0)
  if u < 0.005 then return 0 end
  local L = NEUTRAL + 1 + 87 * u ^ (1 / 1.35)
  return v > 0 and L or -L
end

-- one frame of a controller that moves the lever toward `want`
-- no faster than `rate` degrees per frame
local function steer(m, want, rate)
  local d = want - m.lever
  if d > rate then d = rate elseif d < -rate then d = -rate end
  H.frame(d)
end

-- skilled: trapezoid profile with a gentle acceleration and a creep-in
local function driveSkilled(m, target, maxFrames)
  local goal = target * FLOOR_M
  local braking = false
  for _ = 1, maxFrames or 900 do
    local d = goal - m:carH()
    local ad = math.abs(d)
    -- a skilled operator knows how far the brake needs, for this load
    local fg = (1160 - 900 - m.load) * 9.81
    local fb = 9500 * m.brakeScale
    local decel = (m.v > 0 and (fb - fg) or (fb + fg)) / (2510 + m.load)
    decel = math.max(0.3, decel)
    if not braking and ad < 0.01 + math.abs(m.v) * 0.09 + m.v * m.v / (2 * decel) and math.abs(m.v) < 0.7 then
      braking = true
    end
    if braking then
      steer(m, 0, 30)
      if m:stopped() then
        if math.abs(m:levelErr()) <= 1.5 then return true end
        braking = false
      end
    else
      local vdes = math.min(2.9, math.sqrt(2 * 0.9 * math.max(0, ad - 0.1 - math.abs(m.v) * 0.4)) + 0.25)
      if ad < 0.2 then vdes = math.max(0.2, ad * 2) end
      vdes = vdes * (d > 0 and 1 or -1)
      -- speed feedback trims the load/counterweight imbalance
      local cmd = vdes + (vdes - m.v) * 0.4
      if cmd * (d > 0 and 1 or -1) < 0.16 then cmd = 0.16 * (d > 0 and 1 or -1) end
      steer(m, leverFor(cmd), 5)
    end
  end
  return m:stopped()
end

-- careless: full lever, snap to STOP when the floor comes up
local function driveCareless(m, target)
  local goal = target * FLOOR_M
  for _ = 1, 600 do
    local d = goal - m:carH()
    if math.abs(d) < 0.6 then
      H.frame(-m.lever)
      H.run(20)
      return true
    end
    H.frame((d > 0 and 100 or -100) - m.lever)
  end
  return false
end

local function openAndService(m)
  H.press("a")
  -- wait for the gate and the transfers
  for _ = 1, 120 do
    H.frame(0)
    local busy = false
    for i = 1, #m.pax do
      local p = m.pax[i]
      if p.active and (p.state == "board" or p.state == "alight") then busy = true end
    end
    if m.gate >= 1 and not busy and m.xferT < 0.05 then
      -- nothing left to do on this floor?
      local fl = m:nearestFloor()
      local pending = false
      for i = 1, #m.pax do
        local p = m.pax[i]
        if p.active and ((p.state == "wait" and p.fl == fl) or (p.state == "ride" and p.dest == fl)) then pending = true end
      end
      if not pending then break end
    end
  end
  H.press("a")
  -- someone still in the doorway? wait and close again
  for _ = 1, 10 do
    if m.gateTarget == 0 then break end
    H.run(8)
    H.press("a")
  end
  H.run(12)
end

-- choose the next stop: nearest rider destination, else nearest waiting call
local function nextTarget(m)
  local here = m:nearestFloor()
  local best, bd = nil, 99
  -- rescue anyone about to give up, if there's room
  local free = 0
  for k = 1, #m.carSlot do if m.carSlot[k] == 0 then free = free + 1 end end
  if free >= 2 then
    local urgent, ut = nil, 0.4
    for i = 1, #m.pax do
      local p = m.pax[i]
      if p.active and p.state == "wait" and p.patience / p.patMax < ut and p.kind ~= 6 and m:findSlots(p.slots) > 0 then urgent, ut = p.fl, p.patience / p.patMax end
    end
    if urgent then return urgent end
  end
  for i = 1, #m.pax do
    local p = m.pax[i]
    if p.active and p.state == "ride" then
      local dd = math.abs(p.dest - here)
      if dd < bd then best, bd = p.dest, dd end
    end
  end
  if best then
    -- collective control: pick up waiting passengers on the way
    local dir = best > here and 1 or -1
    local free = 0
    for k = 1, #m.carSlot do if m.carSlot[k] == 0 then free = free + 1 end end
    if free >= 2 then
      local stop = best
      for i = 1, #m.pax do
        local p = m.pax[i]
        if p.active and p.state == "wait" and (p.fl - here) * dir >= 0 and (best - p.fl) * dir > 0
          and (p.fl ~= here or m:findSlots(p.slots) > 0) then
          if math.abs(p.fl - here) < math.abs(stop - here) then stop = p.fl end
        end
      end
      return stop
    end
    return best
  end
  local oldest = -1
  for i = 1, #m.pax do
    local p = m.pax[i]
    if p.active and p.state == "wait" then
      local urgency = (p.patMax - p.patience) - math.abs(p.fl - here) * 2
      if urgency > oldest then best, oldest = p.fl, urgency end
    end
  end
  return best
end

------------------------------------------------------------------------
-- 1. tutorial
------------------------------------------------------------------------
local m = H.goMachine("elevator", "tutorial")
H.run(20)
H.shot("t-lesson1")
-- lesson 1: crank clockwise a little
for _ = 1, 40 do steer(m, 45, 3) if m.v > 0.45 then break end end
H.run(5, 0)
-- lesson 2: back to the middle, the brake grabs
for _ = 1, 60 do steer(m, 0, 6) end
H.run(30)
check(m.coach.i >= 3, "tutorial lessons 1-2 (lever up, back to STOP)")
-- lesson 3: go to floor 2 and stop level
check(driveSkilled(m, 2), "tutorial: stopped at floor 2")
H.run(40)
H.shot("t-level")
print(string.format("     level error at floor 2: %.2f px", m:levelErr()))
check(m.coach.i >= 4, "tutorial lesson 3 (stop level at floor 2)")
-- lesson 4: open the gate, she boards
H.press("a")
H.run(90)
H.shot("t-boarded")
check(m:riderCount() == 1, "tutorial: Mrs. Pell boarded")
-- lesson 5: close the gate and go down
H.press("a")
H.run(30)
for _ = 1, 60 do
  steer(m, -55, 3)
  if m.v < -0.5 then break end
end
H.run(30, 0)
check(m.coach.i >= 6, "tutorial lesson 5 (gate closed, going down)")
-- lesson 6: ease into L and open the gate
check(driveSkilled(m, 0), "tutorial: stopped at L")
H.run(20)
H.press("a")
H.run(120)
H.shot("t-done")
check(m.delivered == 1, "tutorial: passenger delivered")
H.run(120)
check(Save.machine("elevator").tutorialDone == true, "tutorial recorded as done")

------------------------------------------------------------------------
-- 2. skilled standard shift
------------------------------------------------------------------------
local function playShift(driver, label, seed, shots, extra)
  local p = { seed = seed }
  if extra then for k, v in pairs(extra) do p[k] = v end end
  local mm = H.goMachine("elevator", p.mode or "standard", p)
  local stops, maxErr, jolts = 0, 0, 0
  local shotN = 0
  while Scene.current == PlayScene and not mm.finished and mm.t < 900 do
    local target = nextTarget(mm)
    if not target then
      H.frame(-mm.lever)
    else
      if target ~= mm:nearestFloor() or math.abs(mm:levelErr()) > 1.5 or not mm:stopped() then
        driver(mm, target)
      end
      if mm.finished then break end
      if mm:stopped() then
        stops = stops + 1
        local e = math.abs(mm:levelErr())
        if e > maxErr then maxErr = e end
        if shots and shotN < 3 and stops % 4 == 2 then
          shotN = shotN + 1
          H.shot(label .. "-stop" .. shotN)
        end
        openAndService(mm)
      end
    end
  end
  local res = mm.finished
  H.run(80)
  print(string.format("     %s: score %d delivered %d perfect %d walked %d tips %d stops %d maxErr %.1fpx",
    label, res and res.score or -1, mm.delivered, mm.perfects, mm.stormed, mm.tips, stops, maxErr))
  return mm, res
end

local skilled, sres = playShift(driveSkilled, "skilled", 777, true)
check(sres ~= nil and sres.success, "skilled shift finishes successfully")
check(skilled.delivered >= 11, "skilled operator delivers >= 11 passengers")
check(skilled.perfects >= skilled.delivered * 0.4, "skilled operator stops mostly perfectly level")
check(skilled.stormed <= 3, "skilled operator loses at most three passengers")
check(sres.score >= 1100, "skilled operator earns at least brass (" .. sres.score .. ")")

------------------------------------------------------------------------
-- 3. careless and idle shifts
------------------------------------------------------------------------
local careless, cres = playShift(driveCareless, "careless", 777, false)
check(cres.score < sres.score * 0.6, "careless operator scores far less than skilled")
check(careless.perfects < skilled.perfects, "careless operator levels worse")

local idle = H.goMachine("elevator", "standard", { seed = 99 })
H.run(30 * 185)
check(idle.finished and idle.finished.success == false and idle.stormed >= 5, "idle operator is sacked (" .. idle.stormed .. " walked)")
H.run(80)

------------------------------------------------------------------------
-- 4. endless ends after three walk-outs; night guest appears
------------------------------------------------------------------------
local en = H.goMachine("elevator", "endless", { seed = 5 })
local frames = 0
while Scene.current == PlayScene and not en.finished and frames < 30 * 400 do
  H.frame(0)
  frames = frames + 1
end
check(en.finished ~= nil and en.stormed >= 3, "endless ends after three walk-outs")

local night = H.goMachine("elevator", "endless", { seed = 11, mods = { night = true }, difficulty = 3 })
local ghost = nil
for _ = 1, 30 * 80 do
  H.frame(0)
  for i = 1, #night.pax do if night.pax[i].active and night.pax[i].kind == 6 then ghost = night.pax[i] end end
  if ghost or night.finished then break end
end
check(ghost ~= nil, "a night guest appears on the graveyard shift")
if ghost and not night.finished then
  -- fetch the guest and take it to the top: the dial shows a thirteenth floor
  driveSkilled(night, ghost.fl)
  H.run(10)
  H.shot("night-ghost-waiting")
  H.press("a")
  for _ = 1, 150 do
    H.frame(0)
    if ghost.state == "ride" then break end
  end
  H.run(10)
  H.press("a")
  H.run(12)
  driveSkilled(night, night.floors - 1)
  H.run(10)
  H.shot("night-thirteen")
  H.press("a")
  H.run(90)
  check(night.ghostsCarried == 1 or (night.finished and night.ghostsCarried == 1), "the night guest reaches 13")
end
------------------------------------------------------------------------
-- 5. challenges are winnable by a skilled operator
------------------------------------------------------------------------
for _, ch in ipairs(Machines.get("elevator").challenges) do
  do
    local cm, cr = playShift(driveSkilled, "chal-" .. ch.id, 1234, false,
      { mode = ch.mode, difficulty = ch.difficulty, mods = ch.mods, challengeId = ch.id })
    check(cr and cr.score >= ch.goal * 0.8, "challenge " .. ch.id .. " is within reach (" .. (cr and cr.score or -1) .. " vs goal " .. ch.goal .. ")")
  end
end

print(fails == 0 and "OK elevator scripted" or ("FAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)
