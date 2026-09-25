-- Scripted test for No.XIII ONE BILLION YEARS.
--   MOCK_DATA_DIR=/tmp/ci-billion lua5.4 tools/test_billion.lua
-- Proves: the tutorial can be completed by doing what it says; a fast
-- crank carries a standard world from barren rock to the red giant in a
-- reasonable number of frames (and witnesses nothing); a patient scripted
-- player who slows down near each milestone witnesses them (including the
-- city lights, which exist only in a narrow window); endless coalesces a new
-- world after the red giant. Screenshots land in shots/billion/.
local H = dofile("tools/harness.lua")
H.shotDir = "shots/billion"
H.boot({ wipe = true })
H.run(2)

local fails = 0
local function check(cond, msg)
  print((cond and "ok   " or "FAIL ") .. msg)
  if not cond then fails = fails + 1 end
end

local VLO, VHI, LMAX = 20, 720, 9
-- years per second produced by a steady crank of d degrees per frame
local function rateFor(d)
  local v = d * 30
  local u = 0
  if v > VLO then u = math.min(1, math.log(v / VLO) / math.log(VHI / VLO)) end
  return d * 10 ^ (u * LMAX) / 360 * 30
end
-- the crank (deg/frame) that yields at most the given years per second
local function crankFor(rate)
  local lo, hi = 0.05, 40
  if rateFor(lo) > rate then return lo end
  if rateFor(hi) <= rate then return hi end
  for _ = 1, 40 do
    local mid = (lo + hi) / 2
    if rateFor(mid) <= rate then lo = mid else hi = mid end
  end
  return lo
end

------------------------------------------------------------------------
-- tutorial
------------------------------------------------------------------------
local m = H.goMachine("billion", "tutorial")
H.run(20)
H.shot("t-lesson1")
-- 1: crank slowly; a season (a year) passes
for _ = 1, 400 do
  if m.coach.i > 1 then break end
  H.frame(1)
end
H.shot("t-slow")
check(m.coach.i >= 2, "tutorial step 1 (slow crank shows a year)")
H.run(40, 1)
-- 2: crank fast; continents drift
for _ = 1, 400 do
  if m.coach.i > 2 then break end
  H.frame(20)
end
H.shot("t-fast")
check(m.coach.i >= 3, "tutorial step 2 (fast crank drifts continents, shifts=" .. m.tutShifts .. ")")
H.run(35)
-- 3: backward
for _ = 1, 200 do
  if m.coach.i > 3 then break end
  H.frame(-6)
end
check(m.coach.i >= 4, "tutorial step 3 (backward rests)")
H.run(35)
H.shot("t-witness0")
-- 4: approach the mark fast, slow near NOW, watch it
local frames = 0
local shotTaken = false
while not m.coach.done and frames < 3000 do
  frames = frames + 1
  m:scanUpcoming()
  local e = m.focus
  local d = 3
  if e then
    local ds = m:deltaYears(e.em, e.ey)
    if e.st == 1 then d = crankFor(e.lim * 0.5)
      if not shotTaken and e.seen > 0.2 then H.shot("t-watching") shotTaken = true end
    else d = crankFor(math.max(ds / 3, e.lim * 0.5)) end
  end
  H.frame(d)
end
check(m.coach.done or Scene.current ~= PlayScene, "tutorial step 4 (witnessed by slowing) in " .. frames .. " frames")
H.run(120)
check(Save.machine("billion").tutorialDone == true, "tutorial recorded as done")

------------------------------------------------------------------------
-- standard, flat out: barren rock to the red giant, nothing witnessed
------------------------------------------------------------------------
m = H.goMachine("billion", "standard")
H.run(10)
local f = 0
local snaps = { 5, 60, 400, 1500, 2600, 4000, 5300, 5700 }
local si = 1
while Scene.current == PlayScene and not m.finished and f < 20000 do
  f = f + 1
  H.frame(18)
  if si <= #snaps and m.my >= snaps[si] then
    H.shot(string.format("fast-%04d", snaps[si]))
    si = si + 1
  end
end
check(m.finished ~= nil, "fast standard run reaches the red giant in " .. f .. " frames")
check(f < 3000, "fast run is reasonably short (" .. f .. " frames = " .. math.floor(f / 30) .. "s)")
check(m.witN == 0, "flying past witnesses nothing (witnessed " .. m.witN .. ")")
H.run(150)

------------------------------------------------------------------------
-- standard, patient: slow down near every milestone
------------------------------------------------------------------------
m = H.goMachine("billion", "standard", { seed = 777 })
H.run(10)
f = 0
local civSeen, civShot, giantShot = false, false, false
local shots = {}
local wantShot = { rain = true, snow = true, impact = true, traps = true, minds = true, boil = true, bloom = true, comet = true, lastlife = true }
while Scene.current == PlayScene and not m.finished and f < 60000 do
  f = f + 1
  m:scanUpcoming()
  local e = m.focus
  local d = 30
  if e then
    local ds = e.st == 1 and 0 or m:deltaYears(e.em, e.ey)
    if e.st == 1 then
      d = crankFor(e.lim * 0.45)
    else
      -- arrive in about three seconds, never faster than the eye allows at the end
      d = crankFor(math.max(ds / 3, e.lim * 0.45))
    end
    if e.st == 1 and e.seen > 0.25 and wantShot[e.k] and not shots[e.k] then
      shots[e.k] = true
      H.shot("slow-" .. e.k)
    end
  end
  if m.cityN > 20 and not civShot then
    civShot = true
    H.shot("slow-citylights")
  end
  if m.aGiant and not shots.giant0 and m:deltaYears(m.aGiant.em, m.aGiant.ey) < -0.4e7 then
    shots.giant0 = true
    H.shot("slow-giant0")
  end
  if m.aGiant and not giantShot and m:deltaYears(m.aGiant.em, m.aGiant.ey) < -2.2e7 then
    giantShot = true
    H.shot("slow-giant")
  end
  H.frame(d)
  if m.aCiv then civSeen = true end
end
local cities
for _, e in ipairs(m.ev) do if e.k == "cities" then cities = e end end
check(m.finished ~= nil, "patient run finishes (" .. f .. " frames = " .. math.floor(f / 30) .. "s)")
check(cities and cities.w <= 1.3e4, "the civilization window is narrow (" .. math.floor(cities.w) .. " years)")
check(civSeen and civShot, "city lights were on while cranking slowly")
check(cities.wit, "the city lights were witnessed by slowing down")
check(m.witN >= m.scorable - 1, "patient player witnesses nearly all (" .. m.witN .. "/" .. m.scorable .. ", score " .. m.score .. ")")
H.run(150)
if Scene.current == ResultsScene then H.shot("slow-results") end
print("medal", Save.machine("billion").medals.standard, "best", Save.machine("billion").best.standard)

------------------------------------------------------------------------
-- difficulty 3: narrower windows, still witnessable with patience
------------------------------------------------------------------------
m = H.goMachine("billion", "standard", { seed = 4242, difficulty = 3 })
H.run(5)
f = 0
while Scene.current == PlayScene and not m.finished and f < 60000 do
  f = f + 1
  m:scanUpcoming()
  local e = m.focus
  local d = 30
  if e then
    local ds = e.st == 1 and 0 or m:deltaYears(e.em, e.ey)
    d = (e.st == 1) and crankFor(e.lim * 0.45) or crankFor(math.max(ds / 3, e.lim * 0.45))
  end
  H.frame(d)
end
local c3
for _, e in ipairs(m.ev) do if e.k == "cities" then c3 = e end end
check(m.finished ~= nil and c3.wit, "difficulty 3: city window " .. math.floor(c3.w) .. " yrs, witnessed " .. m.witN .. "/" .. m.scorable)
H.run(150)

------------------------------------------------------------------------
-- the rate is the instrument: the same milestone, too fast, is missed
------------------------------------------------------------------------
m = H.goMachine("billion", "standard", { seed = 777 })
H.run(5)
local target
for _, e in ipairs(m.ev) do if e.k == "cities" then target = e end end
-- run up to just before the cities quickly, then pass through at 4x the limit
f = 0
while m:deltaYears(target.em, target.ey) > 2e6 and f < 20000 do
  f = f + 1
  local ds = m:deltaYears(target.em, target.ey)
  H.frame(crankFor(math.max(ds / 3, 1e6)))
end
while target.st < 2 and f < 40000 do
  f = f + 1
  H.frame(crankFor(target.lim * 4))
end
check(target.st == 2 and not target.wit, "passing the city lights at 4x the limit does not witness them")

------------------------------------------------------------------------
-- backward cranking never reverses time
------------------------------------------------------------------------
local my0, ky0 = m.my, m.ky
H.crank(-15, 60)
check(m.my == my0 and m.ky == ky0, "backward crank: time does not move")

------------------------------------------------------------------------
-- endless: a new world coalesces after the end
------------------------------------------------------------------------
m = H.goMachine("billion", "endless", { seed = 99 })
f = 0
-- witness a few early milestones so the lamp does not gutter
while m.planet == 1 and not m.finished and f < 60000 do
  f = f + 1
  m:scanUpcoming()
  local e = m.focus
  local d = 30
  if e and m.planetWit < 4 then
    local ds = e.st == 1 and 0 or m:deltaYears(e.em, e.ey)
    d = (e.st == 1) and crankFor(e.lim * 0.45) or crankFor(math.max(ds / 3, e.lim * 0.45))
  end
  H.frame(d)
end
check(m.planet == 2 and not m.finished, "endless: world II coalesces from the debris (frame " .. f .. ")")
H.crank(4, 40)
H.shot("endless-world2")

print(fails == 0 and "OK test_billion" or ("FAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)
