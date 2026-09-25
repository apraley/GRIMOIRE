-- Scripted tests for No.3 FILM CAMERA:
--   1. the tutorial can be completed by doing what each lesson says
--   2. a skilled photographer (reads the red window, meters, frames the
--      brief, rewinds gently) scores well in standard mode
--   3. careless play (no winding / blind winding) scores badly
-- Run: MOCK_DATA_DIR=/tmp/ci-camera lua5.4 tools/test_camera.lua
local H = dofile("tools/harness.lua")
H.shotDir = "shots/camera"
H.boot({ wipe = true })
H.run(2)

local fails = 0
local function check(cond, msg)
  print((cond and "ok   " or "FAIL ") .. msg)
  if not cond then fails = fails + 1 end
end

local function M() return PlayScene.machine end
-- is the lamp lit yet? (the viewfinder shows it; the bot asks the machine)
local function evBaseLit(m)
  local rec = { t0 = m.wt, te = 0, ox = 0, oy = 0, cdx = 0, cdy = 0, shake = 0, e = 0 }
  return m:quality(rec, 6, 5) > 0.5
end
local function waitStep(n) for _ = 1, 150 do if M().coach.i >= n or M().coach.done then return end H.frame(0) end end
local SUBJ = { FERRY = 1, GULL = 2, DOG = 3, COUPLE = 4, CYCLIST = 5, LIGHT = 6, SPIRE = 7, SAIL = 8 }

-- where is subject k now? (the player can see it in the viewfinder)
local function subjectCentre(m, k)
  if k == SUBJ.GULL then
    -- the gull nearest to the current view centre
    local best, bx, by = 1e9, 0, 0
    for i = 1, 3 do
      local g = m.W.gulls[i]
      local x = (g.x0 + g.v * m.wt) % 920 - 60
      local y = g.y0 + g.amp * math.sin(m.wt * g.w + g.ph)
      local d = math.abs(x - (m.ox + 84))
      if x > 20 and x < 780 and d < best then best, bx, by = d, x, y end
    end
    return bx, by
  end
  -- borrow the machine's own geometry through a fake record
  local rec = { t0 = m.wt, te = 0, ox = m.ox, oy = m.oy, cdx = 0, cdy = 0, shake = 0 }
  local f, d = m:subjEval(rec, k)
  -- recover the centre by scanning the frame offset that minimises d
  return nil, f, d
end

-- pan with the d-pad until the subject sits in the middle of the finder
local function aimAt(k, maxFrames)
  local m = M()
  for _ = 1, maxFrames or 300 do
    local tx, ty
    if k == SUBJ.GULL then
      tx, ty = subjectCentre(m, k)
    else
      -- search the world for the subject's box using the machine's eval
      local bestD, bx = 9, m.ox
      for ox = 0, 632, 8 do
        local rec = { t0 = m.wt, te = 0, ox = ox, oy = m.oy, cdx = 0, cdy = 0, shake = 0 }
        local f, d = m:subjEval(rec, k)
        if f > 0.5 and d < bestD then bestD, bx = d, ox end
      end
      tx = bx + 84
      local TY = { 109, 60, 138, 115, 131, 38, 71, 102 }
      ty = TY[k]
    end
    local wantOx = math.max(0, math.min(632, tx - 84))
    local wantOy = math.max(0, math.min(32, ty - 84))
    local dx, dy = wantOx - m.ox, wantOy - m.oy
    if math.abs(dx) < 2 and math.abs(dy) < 2 then H.releaseAll() H.frame(0) return true end
    H.releaseAll()
    if math.abs(dx) >= 2 then H.hold(dx > 0 and "right" or "left") end
    if math.abs(dy) >= 2 then H.hold(dy > 0 and "down" or "up") end
    H.frame(0)
    if math.abs(dx) < 30 then H.releaseAll() H.frame(0) end
  end
  H.releaseAll()
  H.frame(0)
  return false
end

-- choose shutter/aperture for the metered light (with a minimum shutter)
local function meter(minS)
  local m = M()
  local ev = m.evNow
  local bestA, bestS, bestE = m.aI, m.sI, 99
  for s = minS or 6, 10 do
    for a = 1, 7 do
      local e = math.abs(ev - (a + s + 1)) + (s == 8 and 0 or 0.05)
      if e < bestE then bestA, bestS, bestE = a, s, e end
    end
  end
  H.hold("b")
  H.frame(0)
  while m.sI < bestS do H.press("right") end
  while m.sI > bestS do H.press("left") end
  while m.aI < bestA do H.press("down") end
  while m.aI > bestA do H.press("up") end
  H.release("b")
  H.frame(0)
end

-- read the red window: wind until the next number is centred
local function windToNext()
  local m = M()
  local target = math.floor(m.filmPos + 0.5) + 1
  if #m.shots == 0 and m.filmPos < 0.5 then target = 1 end
  for _ = 1, 200 do
    local rem = (target - m.filmPos) * m:dpf()
    if rem <= 0.5 then break end
    H.frame(math.min(15, rem))
  end
  H.run(12) -- let the hand settle: the crank must be still for the shot
end

local function shoot()
  local m = M()
  local n = #m.shots
  H.press("a")
  for _ = 1, 40 do if #m.shots > n then break end H.frame(0) end
  H.run(2)
end

local function rewind(degPerFrame)
  local m = M()
  H.hold("b")
  for _ = 1, 20 do if m.phase ~= "shoot" then break end H.frame(-20) end
  H.release("b")
  H.frame(0)
  for _ = 1, 2000 do
    if m.phase == "sheet" then break end
    H.frame(-(degPerFrame or 30))
  end
end

local function playRoll(m, shotName)
  local order = {}
  for i = 1, #m.brief do order[i] = m.brief[i] end
  windToNext()
  for bi, it in ipairs(order) do
    if it.r == 5 then
      -- the lighthouse must be lit: wait for dusk
      while m.phase == "shoot" and evBaseLit(m) == false do H.frame(0) end
    end
    local minS = (it.r == 4) and 7 or 6
    for attempt = 1, 2 do
      aimAt(it.s)
      meter(minS)
      aimAt(it.s, 60)
      meter(minS)
      aimAt(it.s, 20)
      shoot()
      if bi == 2 and shotName then H.shot(shotName) end
      local r = m.shots[#m.shots]
      local q = m:quality(r, it.s, it.r)
      print(string.format("  item %d subj %d req %d  q=%.2f e=%.2f", bi, it.s, it.r, q, r.e))
      windToNext()
      if q >= 0.6 then break end
      if #m.shots >= 11 then break end
    end
  end
  return order
end

------------------------------------------------------------------------
-- 1. tutorial, following the lesson text
------------------------------------------------------------------------
local m = H.goMachine("camera", "tutorial")
H.run(20)
H.shot("tut-1-find-ferry")
aimAt(SUBJ.FERRY)                      -- "D-pad aims. Find the FERRY."
H.run(20)
waitStep(2) check(m.coach.i >= 2, "tutorial: finding the ferry passes lesson 1")
windToNext()                           -- "Crank clockwise ... stop when 1 sits under the mark"
H.run(20)
H.shot("tut-2-wound")
waitStep(3) check(m.coach.i >= 3, "tutorial: winding to 1 passes lesson 2 (filmPos " .. string.format("%.2f", m.filmPos) .. ")")
aimAt(SUBJ.FERRY)
meter(8)                               -- "Hold B ... bring the needle to 0"
H.run(30)
waitStep(4) check(m.coach.i >= 4, "tutorial: metering passes lesson 3 (e " .. string.format("%.2f", m.eNow) .. ")")
aimAt(SUBJ.FERRY)
shoot()                                -- "Frame the whole ferry and press A"
H.run(30)
do local r = m.shots[#m.shots] print("  tutorial ferry shot: f", (m:subjEval(r, 1)), "e", r.e, "coach", m.coach.i, m.coach.state) end
waitStep(5) check(m.coach.i >= 5, "tutorial: ferry photograph passes lesson 4")
windToNext()                           -- "Wind to 2"
H.run(30)
waitStep(6) check(m.coach.i >= 6, "tutorial: winding to 2 passes lesson 5")
-- "Gulls are fast. Set 1/250, re-meter, shoot a gull."
local tries = 0
while m.coach.i == 6 and tries < 6 do
  tries = tries + 1
  aimAt(SUBJ.GULL, 200)
  meter(9)
  aimAt(SUBJ.GULL, 60)
  shoot()
  H.run(30)
  if m.coach.i == 6 then windToNext() end
end
H.shot("tut-3-gull")
waitStep(7) check(m.coach.i >= 7, "tutorial: sharp gull passes lesson 6 (tries " .. tries .. ")")
H.hold("b")
for _ = 1, 20 do H.frame(-20) end     -- "Hold B, crank backward a full turn"
H.release("b")
H.run(30)
waitStep(8) check(m.coach.i >= 8, "tutorial: rewind release passes lesson 7")
H.shot("tut-4-rewind")
for _ = 1, 400 do if m.phase == "sheet" then break end H.frame(-25) end
H.run(40)
waitStep(9) check(m.coach.i >= 9, "tutorial: rewinding passes lesson 8")
H.run(60)
H.shot("tut-5-sheet")
H.press("a")
H.press("a")
H.run(60)
check(m.coach.done, "tutorial: coach finished")
H.run(80)
check(Save.machine("camera").tutorialDone, "tutorial recorded as done")

------------------------------------------------------------------------
-- 2. skilled standard roll
------------------------------------------------------------------------
m = H.goMachine("camera", "standard")
H.run(10)
H.shot("std-0")
local order = playRoll(m, "std-shot")
H.shot("std-1-done")
rewind(28)
H.run(30)
H.shot("std-2-sheet-reveal")
H.run(90)
H.shot("std-3-sheet")
H.press("right")
H.run(5)
H.shot("std-4-loupe")
H.press("right")
H.run(5)
H.shot("std-5-loupe")
local D = m.devel
print("skilled roll: items " .. D.itemsTotal .. "/" .. D.maxItems .. " keepers " .. D.keepers .. " score " .. D.score)
check(D.itemsTotal >= D.maxItems * 0.7, "skilled player fulfils most of the brief")
check(D.score >= 400, "skilled player earns at least silver (" .. D.score .. ")")
H.press("a")
H.run(80)
H.shot("std-6-results")
check(Save.machine("camera").best.standard == D.score, "standard score recorded")

------------------------------------------------------------------------
-- 3. careless: winds to frame 1, then never again, mashes the shutter
------------------------------------------------------------------------
m = H.goMachine("camera", "standard", { seed = 777 })
H.run(10)
windToNext()
for i = 1, 12 do
  H.holdFor(i % 2 == 0 and "left" or "right", 15)
  shoot()
end
rewind(30)
H.run(120)
H.shot("careless-sheet")
D = m.devel
print("careless (winds once, then never): score " .. D.score .. " ruined " .. D.ruinedN)
check(D.score < 120, "never winding = double exposures, low score")
H.press("a")
H.run(80)

-- 4. careless: winds by feel (one turn per frame), ignores the window
m = H.goMachine("camera", "standard", { seed = 4242 })
H.run(10)
for i = 1, 12 do
  for _ = 1, 24 do H.frame(15) end   -- exactly one turn
  H.run(8)
  aimAt(order[(i - 1) % #order + 1].s)
  shoot()
end
rewind(30)
H.run(120)
H.shot("careless2-sheet")
D = m.devel
local ov = 0
for i = 1, #m.shots do if D.ov[i] >= 0.04 then ov = ov + 1 end end
print("careless (one turn per frame): score " .. D.score .. " overlapped " .. ov)
check(ov >= 6, "winding by feel overlaps half the roll or more")
check(D.score < 250, "winding by feel scores below brass")

-- 5. resume in the middle of a roll re-renders the thumbnails
m = H.goMachine("camera", "standard", { seed = 99 })
windToNext() aimAt(SUBJ.FERRY) meter(8) shoot() windToNext() shoot()
local st = json.decode(json.encode(m:serialize()))
local p = U.copy(PlayScene.params)
p.resumeState = st
Scene.go(PlayScene, p, "cut")
H.frame(0)
local m2 = PlayScene.machine
check(#m2.shots == 2 and m2.thumbs[2] ~= nil, "resume keeps the exposed frames")
check(math.abs(m2.filmPos - m.filmPos) < 1e-6, "resume keeps the film position")
rewind(30)
H.run(90)
H.shot("resume-sheet")
check(m2.phase == "sheet", "resumed roll develops")

------------------------------------------------------------------------
-- 6. the stranger, and a racing rewind
------------------------------------------------------------------------
m = H.goMachine("camera", "standard", { seed = 31337 })
windToNext()
local FIG_X, FIG_Y = { 382, 136, 606, 508 }, { 124, 70, 144, 124 }
local spot = m.W.figS[1]
while m.wt < m.W.figT[1] - 3 do H.frame(0) end
local want = math.max(0, math.min(632, FIG_X[spot] - 84))
for _ = 1, 400 do
  local d = want - m.ox
  if math.abs(d) < 2 then break end
  H.releaseAll() H.hold(d > 0 and "right" or "left") H.frame(0)
  if math.abs(d) < 30 then H.releaseAll() H.frame(0) end
end
H.releaseAll()
for _ = 1, 30 do H.press("down") end
while m.wt < m.W.figT[1] + 0.5 do H.frame(0) end
H.shot("stranger-finder")
meter(7)
shoot()
local fs = m:subjEval(m.shots[#m.shots], 9)
check(fs >= 0.6, "the stranger is on the negative (f " .. string.format("%.2f", fs) .. ")")
windToNext() aimAt(SUBJ.FERRY) meter(7) shoot() windToNext() aimAt(SUBJ.SPIRE) meter(7) shoot()
rewind(70)
local marked = 0
for i = 1, #m.shots do marked = marked + m.shots[i].st end
check(marked > 0, "racing the rewind sparks static marks (" .. marked .. ")")
H.run(120)
H.press("right")
H.run(4)
H.shot("stranger-loupe")
check(m.devel.stranger, "the contact sheet finds the stranger")
check(Achievements.has("camera", "stranger"), "THE STRANGER achievement unlocked")
check(Achievements.has("camera", "first"), "FIRST ROLL achievement unlocked")
H.press("a")
H.run(80)

------------------------------------------------------------------------
-- 7. endless: a good roll earns the next one
------------------------------------------------------------------------
m = H.goMachine("camera", "endless", { seed = 5150 })
playRoll(m)
rewind(30)
H.run(120)
H.shot("endless-sheet")
check(m.devel.pass, "endless: a skilled roll passes (" .. m.devel.itemsTotal .. "/" .. m.devel.maxItems .. ")")
H.press("a")
H.run(10)
check(m.roll == 2 and m.phase == "shoot" and #m.shots == 0, "endless: next roll loaded")
H.shot("endless-roll2")

print(fails == 0 and "ALL CAMERA TESTS PASSED" or ("CAMERA FAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)
