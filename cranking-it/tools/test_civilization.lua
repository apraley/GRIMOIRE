-- HAND-CRANKED CIVILIZATION proofs:
--   1. The tutorial can be completed with real inputs, lesson by lesson.
--   2. Steady cranking (with sensible use of friction and hands) keeps a
--      civilization alive for thousands of years; frantic cranking raises
--      collapse risk measurably (collapse rate, peak unrest, risk samples).
--   3. Endless: civilizations fall and new ones rise from the ruins.
--   4. serialize() round-trips through JSON mid-history.
--   5. Screenshots of each era, an event, a dark age and the chronicle.
-- Run: MOCK_DATA_DIR=/tmp/ci-civ lua5.4 tools/test_civilization.lua
local H = dofile("tools/harness.lua")
H.shotDir = "shots/civilization"
H.boot({ wipe = true })
H.run(2)

local fails = 0
local function check(cond, msg)
  if not cond then fails = fails + 1 print("FAIL: " .. msg) end
end

------------------------------------------------------------------------
-- 1. tutorial
------------------------------------------------------------------------
local t = H.goMachine("civilization", "tutorial")
H.run(10)
H.shot("t-00-start")
local g = 0
while t.gen < 2 and g < 400 do H.frame(6) g = g + 1 end
H.run(30, 6)
check(t.coach.i >= 2, "lesson 1: two generations")
g = 0
while t.coach.i < 3 and g < 400 do H.frame(6) g = g + 1 end
check(t.coach.i >= 3, "lesson 2: steady pace in the band")
H.shot("t-01-steady")
g = 0
while t.Un < 30 and g < 400 do H.frame(32) g = g + 1 end
H.shot("t-02-rushed")
H.run(30, 32)
check(t.coach.i >= 4, "lesson 3: rushing breeds unrest (" .. t.Un .. ")")
g = 0
while t.coach.i < 5 and g < 600 do H.frame(-10) g = g + 1 end
check(t.coach.i >= 5, "lesson 4: backward friction cools unrest")
H.run(40)
check(t.event ~= nil, "lesson 5 forces an event that locks the wheel")
local y0 = t.year
H.crank(20, 20)
check(t.year == y0, "the locked wheel does not advance history")
H.shot("t-03-event")
H.press("down")
H.press("a")
H.run(40)
check(t.coach.i >= 6, "lesson 5: decided the event")
H.press("b")
H.run(40)
check(t.coach.i >= 7, "lesson 6: spent a hand")
g = 0
while not t.finished and g < 2000 do H.frame(6) g = g + 1 end
H.shot("t-04-bronze")
H.run(120)
check(Scene.current == ResultsScene, "tutorial reaches results")
check(Save.machine("civilization").tutorialDone, "tutorialDone recorded")
H.run(60)

------------------------------------------------------------------------
-- 2. steady vs frantic
------------------------------------------------------------------------
local function play(seed, degPerFrame, wise, maxSeconds, mode)
  local m = H.goMachine("civilization", mode or "standard", { seed = seed, difficulty = 1 })
  local choices = U.rng(seed)
  local frames, peakU, riskSum, riskN = 0, 0, 0, 0
  local maxF = 30 * (maxSeconds or 900)
  while not m.ending and not m.finished and frames < maxF do
    local d = degPerFrame
    if wise and m.Un > 35 then d = -math.abs(degPerFrame) end
    if wise and m.Un > 55 and m.hands > 0 then m:buttonDown(Input.B) end
    m:cranked(d)
    m:update(1 / 30)
    frames = frames + 1
    if m.Un > peakU then peakU = m.Un end
    if m.risk then riskSum = riskSum + m.risk riskN = riskN + 1 end
    if m.event then
      m.eventT = 1
      m.eventSel = choices:range(1, #m.event.opts)
      if not m:optEnabled(m.event.opts[m.eventSel]) then m.eventSel = 1 end
      m:decide()
    end
  end
  return m, peakU, riskN > 0 and riskSum / riskN or 0, frames
end

local N = 10
local stats = {}
for _, cfg in ipairs({ { "steady 0.5rps", 6, true }, { "steady 1rps", 12, true }, { "frantic 3rps", 36, false } }) do
  local survived, collapsed, years, peakU, risk = 0, 0, 0, 0, 0
  for seed = 1, N do
    local m, pu, rk = play(seed * 131, cfg[2], cfg[3])
    if m.year >= 5000 and m.falls == 0 then survived = survived + 1 end
    if (m.collapses or 0) > 0 or m.falls > 0 then collapsed = collapsed + 1 end
    years = years + m.year
    peakU = peakU + pu
    risk = risk + rk
  end
  stats[cfg[1]] = { survived = survived, collapsed = collapsed }
  print(string.format("%-14s survived 5000y: %2d/%d  collapsed: %2d/%d  mean years %5.0f  mean peak unrest %4.0f  mean risk %.3f",
    cfg[1], survived, N, collapsed, N, years / N, peakU / N, risk / N))
end
check(stats["steady 0.5rps"].survived >= N - 1, "steady cranking survives thousands of years")
check(stats["steady 1rps"].survived >= N - 2, "bold but steady cranking survives")
check(stats["frantic 3rps"].collapsed >= N - 1, "frantic cranking collapses")
check(stats["frantic 3rps"].collapsed > stats["steady 0.5rps"].collapsed + 5, "frantic raises collapse rate measurably")

------------------------------------------------------------------------
-- 3. endless: rise and fall
------------------------------------------------------------------------
local e = play(77, 12, false, 1200, "endless")
print(string.format("endless (1rps, careless): year %.0f falls %d score %s", e.year, e.falls, tostring(e.finished and e.finished.score)))
check(e.falls >= 1, "endless: a careless hand sees civilizations fall")
check(e.year > 5000, "endless history runs past 5000 years")
H.run(200)

------------------------------------------------------------------------
-- 4. serialize round trip + 5. screenshots
------------------------------------------------------------------------
local m = H.goMachine("civilization", "standard", { seed = 2024 })
H.run(10)
local shots = { [2] = "era-2-bronze", [3] = "era-3-iron", [4] = "era-4-middle", [5] = "era-5-sail", [6] = "era-6-industrial" }
local choices = U.rng(5)
local lastEra = 1
local evShot = false
local frames = 0
local serialTested = false
local darkShot = false
while not m.finished and frames < 30 * 400 do
  local d = 9
  if m.Un > 35 then d = -9 end
  if m.event then
    if not evShot then H.shot("event") evShot = true end
    H.run(14)
    local n = choices:range(0, #m.event.opts - 1)
    for _ = 1, n do H.press("down") end
    H.press("a")
  else
    H.frame(d)
  end
  frames = frames + 1
  if m.year > 3300 and not darkShot and not m.event then
    darkShot = true
    m.Un, m.S = 100, 5
    m:checkCollapse()
    m.Un, m.S = 20, 40
    H.run(40, 6)
    if m.event then m.eventT = 1 m:decide() end
    H.run(40)
    H.shot("dark-age")
  end
  if m.era > lastEra then
    lastEra = m.era
    H.run(20, 9)
    if shots[m.era] then H.shot(shots[m.era]) end
  end
  if m.year > 2500 and not serialTested and not m.event then
    serialTested = true
    local st = m:serialize()
    local ok, enc = pcall(json.encode, st)
    check(ok, "serialize encodes")
    local dec = json.decode(enc)
    local p = U.copy(PlayScene.params)
    p.resumeState = dec
    local popBefore, yearBefore, cBefore = m:totalPop(), m.year, m.C
    Scene.go(PlayScene, p, "cut")
    H.frame(0)
    local m2 = PlayScene.machine
    check(math.abs(m2.year - yearBefore) < 1e-6, "resume restores the year")
    check(math.abs(m2:totalPop() - popBefore) < 1e-3, "resume restores population")
    check(math.abs(m2.C - cBefore) < 1e-6, "resume restores culture")
    m = m2
    H.run(10)
    H.shot("resumed")
    H.press("a")
    H.run(5)
    H.shot("chronicle")
    H.press("a")
  end
end
H.shot("late")
check(darkShot, "dark age pictured")
H.run(100)

print(fails == 0 and "OK civilization scripted" or ("FAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)
