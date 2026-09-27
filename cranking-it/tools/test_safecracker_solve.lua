-- Proves the wheel-pack mechanics: follow the canonical procedure using the
-- generated combination and check the tutorial completes and a standard
-- safe opens.
local H = dofile("tools/harness.lua")
H.shotDir = "shots/safecracker"
H.boot({ wipe = true })
H.run(2)

local function dialTo(m, target, dir, extraTurns)
  local N = m.lock.N
  -- rotate in dir until reading == target, after extraTurns full turns
  local total = extraTurns * N
  local cur = m.dial
  local dist = ((target - cur) * dir) % N
  total = total + dist
  local degs = total * 360 / N * dir
  local per = 6 * dir
  local n = math.floor(math.abs(degs) / 6)
  for _ = 1, n do H.frame(per) end
  local rem = degs - n * per
  H.frame(rem)
  H.run(45)
end

local function solve(m)
  local n = m.lock.wheels
  for j = 1, n do
    local s = (j % 2 == 1) and 1 or -1
    local turns = (j == 1) and n or (n - j)
    dialTo(m, m.lock.combo[j], s, turns)
  end
  -- open: turn in openDir
  for _ = 1, 60 do H.frame(m.lock.openDir * 10) end
  H.run(10)
end

local m = H.goMachine("safecracker", "tutorial")
H.run(10)
H.crank(10, 40) -- lesson 1
solve(m)
H.shot("solve-tutorial")
print("tutorial opened:", m.opened, "coach step", m.coach.i, "done", m.coach.done)
H.run(200)
print("scene after tutorial:", Scene.current == ResultsScene and "results" or "other", "tutorialDone", Save.machine("safecracker").tutorialDone)

local m2 = H.goMachine("safecracker", "standard")
local opened = 0
for i = 1, 5 do
  local mm = PlayScene.machine
  solve(mm)
  if mm.opened then opened = opened + 1 end
  H.shot("solve-std-" .. i)
  H.run(20)
  H.press("a")
  H.run(40)
end
print("standard opened", opened, "scene", Scene.current == ResultsScene and "results" or "other")
H.run(100)
H.shot("solve-results")
print("best", Save.machine("safecracker").best.standard, "medal", Save.machine("safecracker").medals.standard, "gears", Save.data.gears)
