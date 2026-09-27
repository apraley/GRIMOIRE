-- Scripted proof for No.VIII THE LIGHTHOUSE.
--   MOCK_DATA_DIR=/tmp/ci-lighthouse lua5.4 tools/test_lighthouse.lua
-- 1. the tutorial completes by doing what each lesson says
-- 2. a skilled keeper (small anticipating pushes, horn for strays) keeps the
--    period in band and brings ships home with few or no wrecks
-- 3. an erratic keeper and an idle one wreck ships
-- 4. endless ends after three wrecks
local H = dofile("tools/harness.lua")
H.shotDir = "shots/lighthouse"
H.boot({ wipe = true })
H.run(2)

local fails = 0
local function check(c, msg)
  print((c and "ok   " or "FAIL ") .. msg)
  if not c then fails = fails + 1 end
end
local GAIN = 0.0125
local fogShot = false

-- crank needed this frame to steer the lens toward speed `w`, counting the
-- push already leaning into the carriage (the keeper anticipates)
local function keeperCrank(m, w, maxPer)
  local err = w - (m.omega + m.drive)
  if math.abs(err) < w * 0.012 then return 0 end
  local c = err / GAIN * 0.25
  if c > maxPer then c = maxPer elseif c < -maxPer then c = -maxPer end
  return c
end

------------------------------------------------------------------------
-- 1. tutorial
------------------------------------------------------------------------
local m = H.goMachine("lighthouse", "tutorial")
H.run(20)
H.shot("t-start")
-- lesson 1: push it round
for _ = 1, 400 do
  H.frame(20)
  if m.coach.i >= 2 then break end
end
check(m.coach.i >= 2, "tutorial lesson 1 (spin the lens up)")
-- lesson 2: into the band, then let it coast
for _ = 1, 600 do
  local c = keeperCrank(m, m.omegaT, 12)
  if math.abs(m.omegaT - m.omega) < m.omegaT * 0.05 and math.abs(m.drive) < 0.3 then c = 0 end
  H.frame(c)
  if m.coach.i >= 3 then break end
end
H.shot("t-band")
check(m.coach.i >= 3, "tutorial lesson 2 (period in band, coasting)")
-- lesson 3: too fast
for _ = 1, 400 do
  H.frame(15)
  if m.coach.i >= 4 then break end
end
check(m.coach.i >= 4, "tutorial lesson 3 (push it too fast)")
-- lesson 4: counter-crank to brake back into the band
for _ = 1, 900 do
  local c = keeperCrank(m, m.omegaT, 15)
  if math.abs(m.omegaT - m.omega) < m.omegaT * 0.04 and math.abs(m.drive) < 0.3 then c = 0 end
  H.frame(c)
  if m.coach.i >= 5 then break end
end
check(m.coach.i >= 5, "tutorial lesson 4 (counter-crank to brake)")
-- lessons 5-6: hold the rhythm while the ship reads it and comes home
local shotShip = false
for _ = 1, 30 * 120 do
  H.frame(keeperCrank(m, m.omegaT, 8))
  if not shotShip and m:countState("home") > 0 then H.shot("t-ship-home") shotShip = true end
  if m.coach.i >= 7 then break end
end
check(m.home >= 1, "tutorial lessons 5-6 (ship identified the light and came home)")
H.run(40)
H.shot("t-lost-ship")
-- lesson 7: fog horn
H.press("b")
H.run(40)
H.shot("t-horn")
H.run(90)
check(Save.machine("lighthouse").tutorialDone == true, "tutorial recorded as done")

------------------------------------------------------------------------
-- 2. skilled keeper
------------------------------------------------------------------------
local function keeperNight(style, seed, mode, extra)
  local p = { seed = seed }
  if extra then for k, v in pairs(extra) do p[k] = v end end
  local mm = H.goMachine("lighthouse", mode or "standard", p)
  local r = U.rng(seed + 1)
  local burst, burstT, dir = 0, 0, 1
  local frames = 0
  local shots = 0
  while Scene.current == PlayScene and not mm.finished and frames < 30 * 600 do
    frames = frames + 1
    local c = 0
    if style == "skilled" then
      c = keeperCrank(mm, mm.omegaT, 10)
      -- sound the horn for a stray closing on the headland
      for i = 1, #mm.ships do
        local s = mm.ships[i]
        if s.active and (s.state == "lost" or s.state == "misread") and mm.horns > 0 then
          local _, d = mm:nearestRock(s.x, s.y)
          if d < 30 then H.press("b") break end
        end
      end
    elseif style == "impatient" then
      -- glances at the gauge every few seconds and, if it reads slow,
      -- heaves on the crank for a turn and a half; never brakes
      burstT = burstT - 1
      if burstT <= 0 then
        burstT = r:range(90, 150)
        if mm:period() > mm.charT then burst = 18 end
      end
      if burst > 0 then c = 30 burst = burst - 1 end
    elseif style == "careless" then
      -- cranks by feel, in fits and starts, never reading the gauge
      burstT = burstT - 1
      if burstT <= 0 then
        burstT = r:range(30, 120)
        burst = r:range(6, 24)
        dir = r:chance(0.62) and 1 or -1
      end
      if burst > 0 then c = 30 * dir burst = burst - 1 end
    end
    H.frame(c)
    if style == "skilled" and not fogShot and mm.weather == "FOG BANK" and mm.fog[1].dens > 0.5 then
      fogShot = true
      H.shot("fogbank")
    end
    if shots < 2 and frames % 1500 == 900 then
      shots = shots + 1
      H.shot(style .. "-" .. shots)
    end
  end
  local res = mm.finished
  local band = mm.bandTotal > 0 and mm.bandT / mm.bandTotal or 0
  H.run(90)
  print(string.format("     %s: score %d home %d wrecks %d warned %d band %.0f%% ships %d horns %d",
    style, res and res.score or -1, mm.home, mm.wrecks, mm.warned, band * 100, mm.spawned, mm.horns))
  return mm, res, band
end

local sk, sres, sband = keeperNight("skilled", 42)
check(sres ~= nil and sres.success, "skilled keeper's night succeeds")
check(sband >= 0.85, "skilled keeper holds the band most of the night")
check(sk.home >= 6, "skilled keeper brings >= 6 ships home")
check(sk.wrecks <= 1, "skilled keeper loses at most one ship")
check(sres.score >= 700, "skilled keeper earns at least brass (" .. sres.score .. ")")

local sk2, sres2 = keeperNight("skilled", 7, "standard", { difficulty = 2 })
check(sres2.success and sk2.wrecks <= 2, "skilled keeper also copes at difficulty 2")

------------------------------------------------------------------------
-- 3. careless and idle keepers
------------------------------------------------------------------------
local ck, cres, cband = keeperNight("careless", 42)
check(ck.wrecks >= 3, "erratic keeper wrecks ships")
check(cres.score < sres.score * 0.5, "erratic keeper scores far less")

local pk, pres = keeperNight("impatient", 42)
check(pres.score < sres.score * 0.75 and pk.wrecks >= sk.wrecks, "impatient keeper (overshoots, never brakes) does clearly worse")

local ik, ires = keeperNight("idle", 42)
check(ik.wrecks >= 4 and ik.home == 0 and ires.success == false, "idle keeper: dark lens, ships wreck")

------------------------------------------------------------------------
-- 4. endless ends after three wrecks
------------------------------------------------------------------------
local ek, eres = keeperNight("idle", 5, "endless")
check(eres ~= nil and ek.wrecks >= 3, "endless ends after three wrecks")

------------------------------------------------------------------------
-- 5. challenges are winnable by a skilled keeper
------------------------------------------------------------------------
for _, ch in ipairs(Machines.get("lighthouse").challenges) do
  local cm, cr = keeperNight("skilled", 99, ch.mode, { difficulty = ch.difficulty, mods = ch.mods, challengeId = ch.id })
  check(cr and cr.score >= ch.goal, "challenge " .. ch.id .. " can be beaten (" .. (cr and cr.score or -1) .. " vs goal " .. ch.goal .. ")")
end

print(fails == 0 and "OK lighthouse scripted" or ("FAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)
