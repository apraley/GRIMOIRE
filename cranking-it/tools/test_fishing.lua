-- Scripted play-through for No.II FISHING LINE.
--   MOCK_DATA_DIR=/tmp/ci-fishing lua5.4 tools/test_fishing.lua
-- Proves: the tutorial can be completed by following its instructions, a
-- skilled scripted angler earns a medal in standard mode, an idle player
-- goes home skunked, and a reckless one (drag locked, cranking flat out)
-- snaps the line.
local H = dofile("tools/harness.lua")
H.shotDir = "shots/fishing"
H.boot({ wipe = true })
H.run(2)

local fails = 0
local function check(c, msg) print((c and "ok   " or "FAIL ") .. msg) if not c then fails = fails + 1 end end
local function M() return PlayScene.machine end

local held = { up = false, down = false, a = false }
local function setHeld(name, on)
  if on and not held[name] then H.hold(name) held[name] = true
  elseif not on and held[name] then H.release(name) held[name] = false end
end

-- cast with a given flick strength; release the bail when the lure passes targetX
-- (an angler judges the flick for the distance and keeps the bail open
-- until the lure touches down)
local function cast(flick, targetX)
  local m = M()
  if targetX then flick = math.min(30, 5 + targetX * 0.62) end
  setHeld("a", true)
  for _ = 1, 10 do H.frame(-9) end
  for _ = 1, 3 do H.frame(flick) end
  H.frame(0)
  local n = 0
  while m.phase == "flight" and n < 150 do
    H.frame(0)
    n = n + 1
  end
  setHeld("a", false)
end

local function nearestFish(m)
  local best, bd = nil, 1e9
  for i = 1, m.nFish do
    local f = m.fish[i]
    if f.active then
      local d = math.abs(f.x - m.lx) + math.abs(f.y - m.ly)
      if d < bd then best, bd = f, d end
    end
  end
  return best
end

-- one frame of skilled fighting (reads the tension gauge and the fish)
local function fightFrame(m)
  local f = m.hooked
  local tr = m.T / m.S
  local c = 0
  local rising = f and (f.air or f.state == "rise")
  if rising then
    setHeld("up", false) setHeld("down", true)
    c = (tr > 0.25) and -14 or 0
  else
    setHeld("down", false)
    setHeld("up", m.ra < 0.9)
    if tr < 0.5 then c = 12 elseif tr < 0.7 then c = 5 else c = 0 end
  end
  -- drag: lighter against strong runners
  local want = (f and f.str > m.S * 0.75) and 3 or 4
  if m.drag < want then H.press("right") elseif m.drag > want then H.press("left") end
  H.frame(c)
end

-- lure behaviour for the nearest fish's taste
local jigPhase = 0
local function lureFrame(m)
  local f = nearestFish(m)
  -- strike when the tip dives
  if m.biteDip > 0.5 then H.frame(22) return end
  for i = 1, m.nFish do
    local g = m.fish[i]
    if g.active and (g.state == "nibble") then H.frame(0) return end
  end
  jigPhase = jigPhase + 1
  local likes = f and (({ perch = "jig", pike = "retrieve", eel = "bottom", cat = "still", trout = "fast", grey = "any" })[({ "perch", "pike", "eel", "cat", "trout", "grey" })[f.sp]]) or "jig"
  if likes == "jig" or likes == "any" then
    H.frame((jigPhase % 2 == 0) and 8 or -7)
  elseif likes == "retrieve" then
    H.frame(5)
  elseif likes == "bottom" then
    if m.onBottom then H.frame((jigPhase % 2 == 0) and 6 or -6) else H.frame(0) end
  elseif likes == "still" then
    H.frame(0)
  elseif likes == "fast" then
    if m.ly > 2.5 then H.frame(11) else H.frame(11) end
  end
end

------------------------------------------------------------------------
-- 1. tutorial, following the coach's instructions
------------------------------------------------------------------------
do
  H.goMachine("fishing", "tutorial")
  local m = M()
  H.run(20)
  H.shot("tut-a-start")
  local guard = 0
  while not m.finished and guard < 9000 do
    guard = guard + 1
    local step = m.coach.i
    if os.getenv("VERBOSE") and guard % 60 == 0 then
      local f = m.fish[1]
      print(guard, "step", step, m.phase, string.format("T%.2f L%.1f drag%d ra%.2f slip%.1f pumps%d", m.T, m.L, m.drag, m.ra, m.slipAcc, m.pumps),
        f.active and f.state, f.active and string.format("%.1f,%.1f st%.2f", f.x, f.y, f.stamina))
    end
    if m.phase == "ready" then
      cast(26, 14)
      H.run(10)
    elseif m.phase == "water" then
      if step == 3 and guard % 200 == 0 then H.shot("tut-b-jig") end
      if m.biteDip > 0.5 then H.frame(22)
      else
        local f = m.fish[1]
        if f.active and (f.state == "nibble") then H.frame(0)
        else
          jigPhase = jigPhase + 1
          H.frame((jigPhase % 2 == 0) and 8 or -7)
        end
      end
    elseif m.phase == "fight" then
      if step == 6 then
        if m.drag > 2 then H.press("left") end
        H.frame(0)
        if guard % 50 == 0 then H.shot("tut-c-run") end
      elseif step == 7 then
        if m.drag < 3 then H.press("right") end
        -- pump: lift, then lower while reeling
        setHeld("down", false) setHeld("up", true)
        H.run(22, 0)
        setHeld("up", false) setHeld("down", true)
        H.run(22, 6)
        setHeld("down", false)
      else
        fightFrame(m)
      end
    else
      H.frame(0)
    end
  end
  setHeld("up", false) setHeld("down", false) setHeld("a", false)
  check(m.finished and m.finished.success, "tutorial completed by following the steps (frames " .. guard .. ")")
  H.run(90)
  check(Save.machine("fishing").tutorialDone == true, "tutorial recorded as done")
end

------------------------------------------------------------------------
-- 2. skilled standard trip
------------------------------------------------------------------------
do
  H.goMachine("fishing", "standard")
  local m = M()
  H.run(10)
  local guard, shots = 0, 0
  local fightShot = false
  local lastPh = ""
  while not m.finished and guard < 30 * 400 do
    guard = guard + 1
    if os.getenv("VERBOSE") and m.phase ~= lastPh then
      lastPh = m.phase
      local f = m.hooked or nearestFish(m)
      print(string.format("%5d t=%5.1f %-8s msg=%s lure=%.1f,%.1f", guard, m.t, m.phase, tostring(m.msg), m.lx, m.ly),
        f and ({ "perch", "pike", "eel", "cat", "trout", "grey" })[f.sp], f and string.format("%.1f,%.1f %s", f.x, f.y, f.state))
    end
    if m.phase == "ready" then
      local f = nearestFish(m)
      local target = f and math.max(6, f.x - 1.5) or 20
      cast(28, target)
    elseif m.phase == "water" then
      if m.phaseT > 25 then
        -- nothing interested: reel in and try elsewhere
        H.frame(12)
      else
        lureFrame(m)
      end
    elseif m.phase == "fight" then
      fightFrame(m)
      if not fightShot and m.phaseT > 2 then H.shot("std-fight") fightShot = true end
    else
      if m.phase == "landing" and shots < 2 and m.phaseT > 0.3 then H.shot("std-landed-" .. shots) shots = shots + 1 H.frame(0) end
      H.frame(0)
    end
  end
  setHeld("up", false) setHeld("down", false) setHeld("a", false)
  print(string.format("standard: score %d, caught %d, lost %d, snaps %d", m.score, m.caught, m.lost, m.snaps))
  check(m.finished ~= nil, "standard trip ends")
  check(m.caught >= 3, "skilled angler lands at least 3 fish")
  check(m.score >= Machines.get("fishing").medals.standard[1], "skilled angler earns at least brass (" .. m.score .. ")")
  H.run(150)
  H.shot("std-results")
end

------------------------------------------------------------------------
-- 3. idle player: goes home with nothing
------------------------------------------------------------------------
do
  H.goMachine("fishing", "standard", { seed = 777 })
  local m = M()
  H.run(30 * 250)
  check(m.finished and not m.finished.success and m.finished.score == 0, "idle player is skunked")
  H.run(150)
end

------------------------------------------------------------------------
-- 4. reckless player: drag locked, cranking flat out once hooked
------------------------------------------------------------------------
do
  H.goMachine("fishing", "endless", { seed = 4242 })
  local m = M()
  for _ = 1, 5 do H.press("right") end
  local guard = 0
  while m.snaps == 0 and not m.finished and guard < 30 * 300 do
    guard = guard + 1
    if m.phase == "ready" then
      local f = nearestFish(m)
      cast(28, f and math.max(6, f.x - 1.5) or 20)
    elseif m.phase == "water" then
      if m.phaseT > 25 then H.frame(12) else lureFrame(m) end
    elseif m.phase == "fight" then
      if m.phaseT < 0.1 then H.shot("reckless-fight") end
      H.frame(30)
    else
      H.frame(0)
    end
  end
  print("reckless: caught", m.caught, "lost", m.lost, "snaps", m.snaps, "frames", guard, "finished", m.finished ~= nil)
  check(m.snaps > 0, "reckless player snaps the line (drag " .. m.drag .. ")")
  H.shot("reckless-after")
end

print(fails == 0 and "OK fishing scripted" or ("FAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)
