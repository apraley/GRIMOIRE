-- Scripted play-through for No.X THE WELL.
--   MOCK_DATA_DIR=/tmp/ci-well lua5.4 tools/test_well.lua
-- Proves: the tutorial can be completed by following its steps, a skilled
-- scripted drawer of water gets through several nights in standard mode
-- (medal), an idle player lets the candle burn out, and a reckless one
-- (letting the handle run free every time) loses the buckets.
local H = dofile("tools/harness.lua")
H.shotDir = "shots/well"
H.boot({ wipe = true })
H.run(2)

local fails = 0
local function check(c, msg) print((c and "ok   " or "FAIL ") .. msg) if not c then fails = fails + 1 end end
local function M() return PlayScene.machine end
local V = os.getenv("VERBOSE")

local function skipRead(m)
  local n = 0
  while m.state == "read" and n < 40 do
    H.press("a")
    H.run(4)
    n = n + 1
  end
end

local function setPawl(m, on)
  if m.pawlBroken then return end
  if m.pawl ~= on then H.press("a") end
end

-- lower smoothly, listening to the echo; slow down near the water
local function lower(m, shotName)
  setPawl(m, false)
  local speed = 0
  local n = 0
  local shot = false
  while m.state == "play" and not m.inWater and n < 30 * 60 do
    n = n + 1
    local near = (m.echo > 0 and m.echo < 0.32) or (m.b > m.W - 4)
    local target = near and -4 or -16
    speed = speed + math.max(-1.5, math.min(1.5, target - speed))
    H.frame(speed)
    if shotName and not shot and m.b > 8 then H.shot(shotName) shot = true end
  end
end

local function fillUp(m)
  local n = 0
  -- take up any slack first
  while m.state == "play" and m.y - m.b > 0.4 and n < 300 do H.frame(6) n = n + 1 end
  n = 0
  while m.state == "play" and m.fill < 0.97 and n < 30 * 15 do
    n = n + 1
    if not m.inWater then H.frame(-3) end
    if V and n % 20 == 0 then print(string.format("   fill n=%d b=%.2f y=%.2f W=%.2f fill=%.2f e=%.2f inW=%s tug=%s", n, m.b, m.y, m.W, m.fill, m.jiggle.energy, tostring(m.inWater), m.tug)) end
    H.frame((n % 2 == 0) and 9 or -9)
  end
end

local function haul(m, shotName)
  setPawl(m, true)
  local speed = 0
  local n = 0
  local shot = false
  while m.state == "play" and n < 30 * 120 do
    n = n + 1
    if m.stamina < 0.3 or m.slipAcc > 0.4 then
      -- rest on the pawl
      speed = 0
      local r = 0
      while m.stamina < 0.85 and r < 30 * 15 do H.frame(0) r = r + 1 end
    end
    local target = (m.b < 3) and 5 or 11
    speed = speed + math.max(-0.6, math.min(0.6, target - speed))
    H.frame(speed)
    if shotName and not shot and m.b < m.W * 0.5 then H.shot(shotName) shot = true end
    if V and n % 30 == 0 then print(string.format("   haul b=%.1f fill=%.2f st=%.2f eff=%.2f tug=%s q=%.2f", m.b, m.fill, m.stamina, m.effort, m.tug, m.q)) end
    if m.state ~= "play" then break end
  end
  setPawl(m, false)
end

local function waitPlay(m)
  local n = 0
  while m.state ~= "play" and not m.finished and n < 30 * 20 do
    if m.state == "read" then skipRead(m) else H.frame(0) end
    n = n + 1
  end
end

------------------------------------------------------------------------
-- 1. tutorial
------------------------------------------------------------------------
do
  H.goMachine("well", "tutorial")
  local m = M()
  H.run(20)
  H.shot("tut-a")
  local guard = 0
  while not m.finished and guard < 400 do
    guard = guard + 1
    local step = m.coach.i
    if V then print("step", step, m.state, string.format("b=%.1f y=%.1f fill=%.2f pawl=%s grip=%s vy=%.1f", m.b, m.y, m.fill, tostring(m.pawl), tostring(m.gripped), m.vy)) end
    if m.state ~= "play" then H.frame(0)
    elseif step == 1 then H.crank(-10, 30)
    elseif step == 2 then H.run(45)
    elseif step == 3 then lower(m) H.shot("tut-b-water")
    elseif step == 4 then fillUp(m) H.shot("tut-c-full")
    elseif step == 5 then
      local sp = 0
      for _ = 1, 50 do sp = math.min(9, sp + 0.5) H.frame(sp) end
    elseif step == 6 then setPawl(m, true) H.run(50)
    elseif step == 7 then haul(m) H.run(10)
    elseif step == 8 then
      waitPlay(m)
      setPawl(m, false)
      H.crank(-10, 20)
      H.hold("b")
      local n = 0
      while m.vy < 2.4 and n < 90 do H.frame(0) n = n + 1 end
      H.shot("tut-d-free")
      H.release("b")
      H.frame(0)
    elseif step == 9 then
      H.crank(24, 12)
      H.shot("tut-e-caught")
      H.run(10)
    end
  end
  check(m.finished and m.finished.success, "tutorial completed by following the steps (" .. guard .. " actions)")
  H.run(150)
  check(Save.machine("well").tutorialDone == true, "tutorial recorded as done")
end

------------------------------------------------------------------------
-- 2. skilled standard run
------------------------------------------------------------------------
do
  H.goMachine("well", "standard", { seed = 2024 })
  local m = M()
  H.run(5)
  H.shot("std-a-story")
  local guard = 0
  local shotNight = {}
  while not m.finished and guard < 200 do
    guard = guard + 1
    waitPlay(m)
    if m.finished then break end
    local nm = m.night
    local tag = (not shotNight[nm]) and ("std-n" .. nm) or nil
    shotNight[nm] = true
    lower(m, tag and (tag .. "-lower"))
    if m.state == "play" then fillUp(m) end
    if tag and m.state == "play" then H.shot(tag .. "-fill") end
    if m.state == "play" then haul(m, tag and (tag .. "-haul")) end
    if V then print(string.format("night %d  litres %.1f/%d  candle %.0f  score %d  spares %d  slips %d  pawlWear %.2f",
      m.night, m.nightLitres, m.quota, m.candle, m.score, m.spares, m.slips, m.pawlWear)) end
    if m.state == "deliver" and m.cardT > 1.5 and tag then H.shot(tag .. "-deliver") end
  end
  print(string.format("standard: nights %d, litres %.1f, score %d, slips %d", m.nightsDone, m.litres, m.score, m.slips))
  check(m.finished ~= nil, "standard run ends")
  check(m.nightsDone >= 4, "skilled player survives at least four nights")
  check(m.score >= Machines.get("well").medals.standard[1], "skilled player earns at least brass (" .. m.score .. ")")
  H.run(150)
  H.shot("std-results")
end

------------------------------------------------------------------------
-- 3. idle: reads the story, then does nothing; the candle burns out
------------------------------------------------------------------------
do
  H.goMachine("well", "standard", { seed = 55 })
  local m = M()
  skipRead(m)
  H.run(30 * 200)
  check(m.finished and not m.finished.success and m.finished.score == 0, "idle player lets the candle burn out")
  H.run(150)
end

------------------------------------------------------------------------
-- 4. reckless: lets the handle run free all the way down every time
------------------------------------------------------------------------
do
  H.goMachine("well", "standard", { seed = 66 })
  local m = M()
  skipRead(m)
  local guard = 0
  local shot = false
  while not m.finished and guard < 30 * 120 do
    guard = guard + 1
    if m.state == "play" then
      H.hold("b")
      H.frame(0)
      if not shot and m.vy > 5 then H.shot("reckless-fall") shot = true end
    else
      H.release("b")
      H.frame(0)
    end
  end
  H.release("b")
  H.frame(0)
  check(m.finished and not m.finished.success, "reckless player loses every bucket (" .. tostring(m.finished and m.finished.title) .. ")")
  H.run(150)
end

print(fails == 0 and "OK well scripted" or ("FAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)
