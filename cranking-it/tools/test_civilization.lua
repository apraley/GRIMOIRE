-- HAND-CRANKED CIVILIZATION proofs (sectored Wheel of History):
--   1. The tutorial can be completed with real inputs, lesson by lesson
--      (generations, lingering in FIELDS, starving FIELDS -> famine, rushed
--      turns -> unrest, backward friction, an event lock, ARTS -> a HAND).
--   2. Deliberate DWELL strategies produce measurably different
--      civilizations: FORGE-lingering reaches the Industrial age sooner,
--      SWORD-lingering conquers more, starving FIELDS brings famine; a
--      balanced dweller reaches year 5000; careless fast spinning collapses.
--   3. Endless: civilizations fall and new ones rise from the ruins.
--   4. serialize() round-trips through JSON mid-history.
--   5. Screenshots of the tutorial, each era, an event, a dark age and the
--      chronicle.
-- Run: MOCK_DATA_DIR=/tmp/ci-civ lua5.4 tools/test_civilization.lua
local H = dofile("tools/harness.lua")
H.shotDir = "shots/civilization"
H.boot({ wipe = true })
H.run(2)

local fails = 0
local function check(cond, msg)
  if not cond then fails = fails + 1 print("FAIL: " .. msg) end
end

-- seconds to linger in each season of a sector: FIELDS FORGE SWORD TEMPLE ARTS SAILS
local PROFILES = {
  balanced = { 0.25, 0.25, 0.25, 0.25, 0.25, 0.25 },
  forge = { 0.2, 1.0, 0.2, 0.2, 0.2, 0.2 },
  sword = { 0.2, 0.2, 1.0, 0.2, 0.2, 0.2 },
  starve = { 0.03, 0.3, 0.3, 0.3, 0.3, 0.3 },
  fields = { 1.0, 0.05, 0.05, 0.05, 0.05, 0.05 },
  nofields = { 0.03, 0.6, 0.6, 0.6, 0.6, 0.6 },
  arts = { 0.1, 0.1, 0.1, 0.1, 1.0, 0.1 },
}
-- crank degrees this frame so the current season lasts prof[sector] seconds
local function dwellDeg(m, prof)
  local sector = (m.hiSeason % 12) // 2 + 1
  return 1 / prof[sector]
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
while t.coach.i < 3 and g < 3000 do H.frame(dwellDeg(t, PROFILES.fields)) g = g + 1 end
check(t.coach.i >= 3, "lesson 2: lingering in FIELDS feeds it (focus " .. t.focus[1] .. ")")
H.shot("t-01-fields")
g = 0
while t.coach.i < 4 and g < 6000 do H.frame(dwellDeg(t, PROFILES.nofields)) g = g + 1 end
check(t.coach.i >= 4, "lesson 3: starving FIELDS brings famine")
H.shot("t-02-famine")
g = 0
while t.Un < 30 and g < 400 do H.frame(32) g = g + 1 end
H.shot("t-03-rushed")
H.run(30, 32)
check(t.coach.i >= 5, "lesson 4: rushed turns breed unrest (" .. t.Un .. ")")
g = 0
while t.coach.i < 6 and g < 600 do H.frame(-10) g = g + 1 end
check(t.coach.i >= 6, "lesson 5: backward friction cools unrest")
H.run(40)
check(t.event ~= nil, "lesson 6 forces an event that locks the wheel")
local y0 = t.year
H.crank(20, 20)
check(t.year == y0, "the locked wheel does not advance history")
H.shot("t-04-event")
H.press("down")
H.press("a")
H.run(40)
check(t.coach.i >= 7, "lesson 6: decided the event")
g = 0
while t.handsEarned < 1 and g < 4000 do H.frame(dwellDeg(t, PROFILES.arts)) g = g + 1 end
check(t.handsEarned >= 1, "lingering in ARTS earns a HAND")
H.shot("t-05-arts")
H.press("b")
H.run(120)
check(Scene.current == ResultsScene, "tutorial reaches results")
check(Save.machine("civilization").tutorialDone, "tutorialDone recorded")
H.run(60)

------------------------------------------------------------------------
-- 2. dwell strategies
------------------------------------------------------------------------
-- a sensible hand: follows its dwell profile, cranks backward (friction)
-- when unrest climbs and spends HANDS in a crisis. Events: random choices.
local function play(seed, prof, opts)
  opts = opts or {}
  local m = H.goMachine("civilization", opts.mode or "standard", { seed = seed, difficulty = 1 })
  local choices = U.rng(seed)
  local frames = 0
  local maxF = 30 * (opts.seconds or 1500)
  local out = { risk = 0, riskN = 0 }
  while not m.ending and not m.finished and frames < maxF do
    local d = opts.spin or dwellDeg(m, prof)
    if not opts.careless then
      if m.Un > 35 then d = -4 end
      if m.Un > 55 and m.hands > 0 then m:buttonDown(Input.B) end
    end
    m:cranked(d)
    m:update(1 / 30)
    frames = frames + 1
    if m.risk then out.risk = out.risk + m.risk out.riskN = out.riskN + 1 end
    if m.gen == 40 and not out.at40 then
      out.at40 = true
      out.conq40 = m.conquests
      out.pop40 = m:totalPop()
    end
    if m.event then
      m.eventT = 1
      m.eventSel = choices:range(1, #m.event.opts)
      if not m:optEnabled(m.event.opts[m.eventSel]) then m.eventSel = 1 end
      m:decide()
    end
  end
  out.m = m
  return out
end

local N = 5
local S = {}
for _, name in ipairs({ "balanced", "forge", "sword", "starve", "fast" }) do
  local r = { survived = 0, collapsed = 0, industrial = 0, indYears = 0, conq40 = 0, famine = 0, pop40 = 0, years = 0, risk = 0 }
  for seed = 1, N do
    local o
    if name == "fast" then o = play(seed * 131, nil, { spin = 36, careless = true })
    else o = play(seed * 131, PROFILES[name]) end
    local m = o.m
    if m.year >= 5000 and m.falls == 0 then r.survived = r.survived + 1 end
    if (m.collapses or 0) > 0 or m.falls > 0 then r.collapsed = r.collapsed + 1 end
    -- industrial year (5000 = never reached)
    r.indYears = r.indYears + (m.industrialYear or 5000)
    if m.industrialYear then r.industrial = r.industrial + 1 end
    r.conq40 = r.conq40 + (o.conq40 or m.conquests)
    r.pop40 = r.pop40 + (o.pop40 or 0)
    r.famine = r.famine + m.famineSeasons
    r.years = r.years + m.year
    r.risk = r.risk + (o.riskN > 0 and o.risk / o.riskN or 0)
  end
  S[name] = r
  print(string.format("%-9s 5000y %d/%d  collapsed %d/%d  industrial by %4.0f (%d/%d)  conquests@gen40 %4.1f  famine region-seasons %6.1f  pop@gen40 %6.0fK  mean years %5.0f  risk %.3f",
    name, r.survived, N, r.collapsed, N, r.indYears / N, r.industrial, N, r.conq40 / N, r.famine / N, r.pop40 / N, r.years / N, r.risk / N))
end
check(S.balanced.survived >= N - 1, "a balanced dweller reaches year 5000")
check(S.forge.indYears < S.balanced.indYears - 500, "FORGE-lingering reaches the Industrial age sooner")
check(S.sword.conq40 >= S.balanced.conq40 * 2 and S.sword.conq40 > S.balanced.conq40 + 1, "SWORD-lingering conquers more")
check(S.starve.famine > S.balanced.famine * 2, "starving FIELDS brings famine")
check(S.starve.pop40 < S.balanced.pop40 * 0.7, "starving FIELDS keeps the people few")
check(S.fast.collapsed >= N - 1, "careless fast spinning collapses")

------------------------------------------------------------------------
-- 3. endless: rise and fall
------------------------------------------------------------------------
local e = play(77, nil, { mode = "endless", spin = 12, careless = true, seconds = 1200 }).m
print(string.format("endless (careless 1 turn/s): year %.0f falls %d score %s", e.year, e.falls, tostring(e.finished and e.finished.score)))
check(e.falls >= 1, "endless: a careless hand sees civilizations fall")
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
local prof = { 0.3, 0.45, 0.2, 0.3, 0.3, 0.25 }
while not m.finished and frames < 30 * 600 do
  local d = dwellDeg(m, prof)
  if m.Un > 35 then d = -6 end
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
    H.run(20, 3)
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
    local popBefore, yearBefore, cBefore, fBefore = m:totalPop(), m.year, m.C, m.focus[2]
    Scene.go(PlayScene, p, "cut")
    H.frame(0)
    local m2 = PlayScene.machine
    check(math.abs(m2.year - yearBefore) < 1e-6, "resume restores the year")
    check(math.abs(m2:totalPop() - popBefore) < 1e-3, "resume restores population")
    check(math.abs(m2.C - cBefore) < 1e-6, "resume restores culture")
    check(math.abs(m2.focus[2] - fBefore) < 1e-6, "resume restores sector focus")
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
