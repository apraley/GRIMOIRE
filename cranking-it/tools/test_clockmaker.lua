-- CLOCKMAKER proofs:
--   1. 200 seeds x levels x kinds: the generated solution meshes (tooth sums
--      match the centre distances), hits the goal ratio, fits the plate,
--      the tray holds every part needed, and every diagnosis fault is
--      detectable by turning the train (stutter / wrong ratio / bind or slip)
--      and disappears once the right gear is fitted.
--   2. The tutorial can be completed with real inputs.
--   3. A skilled scripted clockmaker wins Standard; an idle one scores 0.
--   4. Overwinding snaps the spring; endless ends after three complaints.
-- Run: MOCK_DATA_DIR=/tmp/ci-clock lua5.4 tools/test_clockmaker.lua
local H = dofile("tools/harness.lua")
H.shotDir = "shots/clockmaker"
H.boot({ wipe = true })
H.run(2)

local fails = 0
local function check(cond, msg)
  if not cond then fails = fails + 1 print("FAIL: " .. msg) end
end

local Clock = Machines.get("clockmaker").class
local K = 1.0
local PX0, PY0, PX1, PY1 = 10, 26, 262, 214

------------------------------------------------------------------------
-- 1. generation
------------------------------------------------------------------------
local m = H.goMachine("clockmaker", "standard")
local kinds = { "assembly", "stutter", "slow", "fast", "stopped" }
local counts = { puzzles = 0, detect = 0 }
local function driveTurn(mm)
  mm:resetTest()
  local jam = 0
  for _ = 1, 120 do
    local j = mm:drive(3, true)
    if j > 0 then jam = j break end
  end
  return jam
end

local function multisetHas(pool, need)
  local cnt = {}
  for _, t in ipairs(pool) do cnt[t] = (cnt[t] or 0) + 1 end
  for _, t in ipairs(need) do
    if not cnt[t] or cnt[t] == 0 then return false end
    cnt[t] = cnt[t] - 1
  end
  return true
end

for seed = 1, 200 do
  for level = 0, 5 do
    local kind = kinds[(seed + level) % #kinds + 1]
    local rng = U.rng(seed * 97 + level)
    local ok, c = pcall(Clock.generate, level, kind, rng)
    check(ok, "generate seed " .. seed .. " level " .. level .. ": " .. tostring(c))
    if ok then
      counts.puzzles = counts.puzzles + 1
      local n = c.n
      local R = 1
      for i = 1, n do
        local d = (i == 1) and c.B or c.solT[2 * i - 2]
        local q = c.solT[2 * i - 1]
        check(d + q == c.S[i], "tooth sum stage " .. i)
        local dist = math.sqrt((c.ax[i + 1] - c.ax[i]) ^ 2 + (c.ay[i + 1] - c.ay[i]) ^ 2)
        check(math.abs(dist - c.S[i] * K) < 0.01, "centre distance = r1 + r2 (seed " .. seed .. ")")
        R = R * d / q
      end
      check(math.abs(R - c.R) < 1e-6, "solution ratio equals goal")
      for k = 1, n + 1 do
        check(c.ax[k] > PX0 and c.ax[k] < PX1 and c.ay[k] > PY0 and c.ay[k] < PY1, "arbor on the plate")
      end
      -- parts available
      if c.kind == "assembly" then
        local need = {}
        for s = 1, 2 * n - 1 do if c.slotT[s] == 0 then need[#need + 1] = c.solT[s] end end
        check(multisetHas(c.trayT, need), "tray holds the solution (seed " .. seed .. ")")
        check(#c.trayT <= 12, "tray fits the tin")
      else
        local need = {}
        for s = 1, 2 * n - 1 do
          if c.slotT[s] ~= c.solT[s] or c.slotB[s] >= 0 then need[#need + 1] = c.solT[s] end
        end
        check(#need >= 1, "diagnosis clock has a fault")
        check(multisetHas(c.trayT, need), "tray holds the replacement (" .. c.kind .. ", seed " .. seed .. ")")
        -- detectability: turn the faulty train one barrel turn
        m.c = c
        m.ns = 2 * n - 1
        for k = 1, 6 do m.ang[k] = 0 end
        for i = 1, 5 do m.slack[i] = 0 m.armed[i] = true end
        m:computeGeometry()
        local jam = driveTurn(m)
        local measured = m.testO / math.max(1, m.testB)
        local detected
        if c.kind == "stutter" then detected = m.testStutter > 0
        elseif c.kind == "slow" then detected = jam == 0 and measured < c.R * 0.99
        elseif c.kind == "fast" then detected = jam == 0 and measured > c.R * 1.01
        else detected = jam > 0 or m.testO == 0 end
        check(detected, "fault " .. c.kind .. " detectable by turning (seed " .. seed .. " level " .. level .. ")")
        if detected then counts.detect = counts.detect + 1 end
        -- repaired: fit the solution
        for s = 1, 2 * n - 1 do c.slotT[s] = c.solT[s] c.slotB[s] = -1 end
        m:changed()
        jam = driveTurn(m)
        measured = m.testO / math.max(1, m.testB)
        check(jam == 0 and m.testStutter == 0 and math.abs(measured - c.R) / c.R < 0.004,
          "repaired train runs true (" .. c.kind .. ", seed " .. seed .. ") measured " .. measured .. " want " .. c.R)
      end
    end
  end
end
print(string.format("generated %d puzzles, %d faults detected", counts.puzzles, counts.detect))

------------------------------------------------------------------------
-- helpers driving the real UI
------------------------------------------------------------------------
local function selectSlot(mm, s)
  local guard = 0
  while mm.sel ~= s and guard < 12 do H.press("right") guard = guard + 1 end
end
local function selectTray(mm, teeth)
  local guard = 0
  while guard < 14 do
    if mm.c.trayT[mm.tsel] == teeth and mm.c.trayB[mm.tsel] < 0 then return true end
    H.press("down")
    guard = guard + 1
  end
  return false
end
local function solveBench(mm)
  local c = mm.c
  for s = 1, mm.ns do
    if c.slotT[s] ~= c.solT[s] or c.slotB[s] >= 0 then
      selectSlot(mm, s)
      if selectTray(mm, c.solT[s]) then H.press("a") end
    end
  end
  -- test: one barrel turn = two crank turns
  local guard = 0
  while mm.phase == "bench" and guard < 200 do H.frame(10) guard = guard + 1 end
  H.run(45)
end
local function windTo(mm, frac)
  local guard = 0
  while mm.phase == "wind" and mm.wind / mm.limit < frac and guard < 900 do H.frame(8) guard = guard + 1 end
  H.run(12)
end

------------------------------------------------------------------------
-- 2. tutorial
------------------------------------------------------------------------
local t = H.goMachine("clockmaker", "tutorial")
H.run(10)
H.shot("t-00-start")
H.crank(10, 40)
H.run(40)
check(t.coach.i >= 2, "tutorial lesson 1 passes by cranking")
H.press("right")
H.run(40)
check(t.coach.i >= 3, "tutorial lesson 2: select wheel slot")
-- fit a WRONG pair first (24 + 16 = 40 meshes but ratio 3 x 1.5 = 4.5)
selectTray(t, 24) H.press("a")
H.run(40)
check(t.coach.i >= 4, "tutorial lesson 3: fit a wheel")
H.press("right")
selectTray(t, 16) H.press("a")
H.run(40)
check(t.coach.i >= 5, "tutorial lesson 4: pinion meshes")
H.shot("t-01-wrongpair")
local g = 0
while t.fails == 0 and g < 200 do H.frame(10) g = g + 1 end
check(t.fails == 1, "wrong ratio fails the test")
H.shot("t-02-failtest")
H.run(20)
-- correct it: wheel 32, pinion 8
H.press("left")
selectTray(t, 32) H.press("a")
H.press("right")
selectTray(t, 8) H.press("a")
H.run(10)
H.shot("t-03-fixed")
g = 0
while t.phase == "bench" and g < 200 do H.frame(10) g = g + 1 end
check(t.phase == "closing" or t.phase == "wind", "correct train passes the test")
H.run(80)
check(t.coach.i >= 6, "tutorial lesson 5: test passes (" .. t.coach.i .. " " .. t.phase .. ")")
H.crank(8, 30)
H.shot("t-04-winding")
windTo(t, 0.93)
H.run(60)
check(t.coach.i >= 7, "tutorial lesson 6: wound into the FULL band (" .. t.coach.i .. ")")
H.shot("t-05-wound")
H.press("a")
H.run(30)
H.shot("t-06-running")
H.run(120)
check(Scene.current == ResultsScene, "tutorial finishes with results")
check(Save.machine("clockmaker").tutorialDone, "tutorialDone recorded")
H.run(60)

------------------------------------------------------------------------
-- 3. skilled standard run
------------------------------------------------------------------------
for diff = 1, 3 do
  local mm = H.goMachine("clockmaker", "standard", { difficulty = diff, seed = 777 + diff })
  H.run(10)
  for i = 1, 4 do
    mm = PlayScene.machine
    if not mm or mm.finished then break end
    if i == 2 and diff == 1 then H.shot("s-diag-before") end
    solveBench(mm)
    print("  clock", i, mm.c.kind, "phase", mm.phase, "score", mm.score)
    if i == 2 and diff == 1 then H.shot("s-wind") end
    windTo(mm, 0.94)
    H.press("a")
    H.run(20)
    if i == 1 and diff == 1 then H.shot("s-running") end
    local g = 0
    while not (mm.phase == "card" and mm.cardT > 1) and g < 300 do H.frame(0) g = g + 1 end
    if i == 1 and diff == 1 then H.shot("s-card") end
    H.press("a")
    H.run(10)
  end
  H.run(60)
  local rec = Save.machine("clockmaker")
  print(string.format("skilled standard d%d: best %d  medal %d", diff, rec.best.standard or 0, rec.medals.standard or 0))
  check((rec.best.standard or 0) >= 5600, "skilled player earns gold on d" .. diff)
  H.run(60)
end

-- idle player: the day runs out
local idle = H.goMachine("clockmaker", "standard", { seed = 4242 })
H.shot("s-idle-start")
for _ = 1, 30 * 490 do H.frame(0) if idle.finished then break end end
check(idle.finished and idle.finished.score == 0 and idle.finished.success == false, "idle player scores nothing")
H.run(80)

------------------------------------------------------------------------
-- 4. overwinding + binding + endless complaints
------------------------------------------------------------------------
local o = H.goMachine("clockmaker", "standard", { seed = 99 })
H.run(10)
solveBench(o)
check(o.phase == "wind", "reached winding")
local g2 = 0
while o.phase == "wind" and g2 < 900 do H.frame(20) g2 = g2 + 1 end
check(o.phase == "snapped", "overwinding snaps the spring")
H.run(4)
H.shot("s-snapped")
H.run(90)
check(o.phase == "wind" and o.wind == 0, "a new spring is fitted")

-- deliberately bind a mesh
local b = H.goMachine("clockmaker", "standard", { seed = 5 })
H.run(10)
local c = b.c
-- put the largest tray gear into the first pinion slot: likely binds
local big = 1
for i = 1, #c.trayT do if c.trayT[i] > c.trayT[big] then big = i end end
selectSlot(b, 1)
b.tsel = big
H.press("a")
if b.mstat[1] == 2 then
  local a0 = b.ang[1]
  H.crank(10, 20)
  check(b.ang[1] == a0, "a bound mesh locks the barrel")
  H.shot("s-bind")
end

local e = H.goMachine("clockmaker", "endless", { difficulty = 3, seed = 31 })
for _ = 1, 30 * 600 do H.frame(0) if e.finished then break end end
check(e.finished and e.complaints >= 3, "endless ends after three customers leave")
H.run(80)

print(fails == 0 and "OK clockmaker scripted" or ("FAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)
