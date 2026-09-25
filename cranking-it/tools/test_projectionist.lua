-- Scripted tests for No.7 PROJECTIONIST:
--   1. the tutorial can be completed by doing what each lesson says
--   2. a skilled projectionist (steady crank at the film's speed, gentle
--      speed changes, arc on the first cue, changeover on the second while
--      easing off) scores well in standard mode
--   3. a jerky projectionist jams the film and empties the house
--   4. an idle projectionist empties the house
-- Run: MOCK_DATA_DIR=/tmp/ci-proj lua5.4 tools/test_projectionist.lua
local H = dofile("tools/harness.lua")
H.shotDir = "shots/projectionist"
H.boot({ wipe = true })
H.run(2)

local fails = 0
local function check(cond, msg)
  print((cond and "ok   " or "FAIL ") .. msg)
  if not cond then fails = fails + 1 end
end
local function M() return PlayScene.machine end
local function waitStep(n, crank)
  for _ = 1, 400 do
    if M().coach.i >= n or M().coach.done then return end
    H.frame(crank or 0)
  end
end

-- steady hand with a smooth ramp toward a speed (deg per frame)
local hand = 0
local function drive(targetFps, frames, rampPerFrame)
  local want = targetFps * 45 / 30
  for _ = 1, frames do
    local d = want - hand
    local step = rampPerFrame or 1.2
    if math.abs(d) < step then hand = want else hand = hand + (d > 0 and step or -step) end
    H.frame(hand)
  end
end

------------------------------------------------------------------------
-- 1. tutorial
------------------------------------------------------------------------
local m = H.goMachine("projectionist", "tutorial")
hand = 0
H.run(10)
H.shot("tut-0")
drive(16, 150)                          -- "Crank steadily: 2 turns a second"
waitStep(2, hand)
check(m.coach.i >= 2, "tutorial: steady 16 fps passes lesson 1")
drive(16, 200)                          -- "keep cranking evenly"
waitStep(3, hand)
check(m.coach.i >= 3, "tutorial: an even loop passes lesson 2")
H.shot("tut-1-steady")
for _ = 1, 8 do H.frame(80) end         -- "JERK the crank"
check(m.state ~= "run", "tutorial: a jerk jams the film (state " .. m.state .. ")")
H.shot("tut-2-jam")
hand = 0
H.run(30)                               -- "STOP cranking!"
waitStep(5)
check(m.coach.i >= 5 and m.state == "stopped", "tutorial: stopping stops the burn")
H.shot("tut-3-stopped")
H.press("b")                            -- "B opens the gate..."
H.run(5)
H.shot("tut-4-thread")
local names = { "up", "left", "down", "right" }
for i = 1, 4 do H.press(names[m.seq[i]]) end
H.press("a")
waitStep(6)
check(m.coach.i >= 6 and m.state == "run", "tutorial: re-threading passes lesson 5")
drive(20, 220, 0.6)                     -- "speed up GENTLY to 20"
waitStep(7, hand)
check(m.coach.i >= 7, "tutorial: 20 fps passes lesson 6")
for _ = 1, 600 do if m.cue1Seen then break end drive(20, 1) end
H.shot("tut-5-cue")
H.press("b", hand)                      -- "then press B"
waitStep(8, hand)
check(m.coach.i >= 8, "tutorial: striking the arc passes lesson 7")
local _, cue2 = m:cues()
while m.f < cue2 - 12 do drive(20, 1) end
drive(10, 10, 2)                        -- ease off...
H.press("a", hand)                      -- "...press A to change over"
check(m.reelIdx == 2 and m.state == "run", "tutorial: changeover without a jam (" .. m.lastRating .. ", loop " .. string.format("%.2f", m.loop) .. ")")
H.shot("tut-6-changed")
drive(16, 160, 0.6)
waitStep(99, hand)
check(m.coach.done, "tutorial: coach finished")
H.run(80)
check(Save.machine("projectionist").tutorialDone, "tutorial recorded as done")

------------------------------------------------------------------------
-- 2. skilled standard programme
------------------------------------------------------------------------
local function skilled(mode, seed, shots)
  local mm = H.goMachine("projectionist", mode, { seed = seed })
  hand = 0
  local frames = 0
  local struckFor = 0
  while Scene.current == PlayScene and not mm.finished and frames < 30 * 400 do
    frames = frames + 1
    if mm.state == "run" or mm.state == "runout" then
      local tgt = mm.target or 16
      -- look ahead at the booth's speed warning
      local dn, nf = mm:nextChange(mm.f)
      if dn and dn < tgt * 0.8 then tgt = nf end
      if mm:hasNext() then
        local cue1, cue2 = mm:cues()
        if mm.f >= cue1 and struckFor ~= mm.reelIdx then
          H.press("b", hand) frames = frames + 2
          struckFor = mm.reelIdx
        end
        if mm.f >= cue2 - tgt * 0.25 and mm.f < cue2 + 4 then
          -- ease off into the changeover
          drive(tgt * 0.5, 6, 2.5)
          H.press("a", hand)
          frames = frames + 8
          if shots and mm.reelIdx == 2 then H.shot(shots .. "-changeover") end
        end
      end
      drive(tgt, 1, 0.9)
      if shots and frames == 400 then H.shot(shots .. "-running") end
      if shots and frames == 1500 then H.shot(shots .. "-reel2") end
    elseif mm.state == "stopped" then
      H.press("b")
    elseif mm.state == "thread" then
      local names = { "up", "left", "down", "right" }
      H.press(names[mm.seq[mm.seqI]])
    elseif mm.state == "closing" then
      H.press("a")
    else
      H.frame(0)
    end
  end
  return mm, frames
end

local sm, fr = skilled("standard", 12345, "std")
print(string.format("skilled standard: score %d jams %d perfect %d present %d frames %d", sm.score, sm.jams, sm.perfects, sm:presentCount(), fr))
check(sm.finished and sm.finished.success, "skilled programme completes")
check(sm.jams == 0, "skilled hand never jams")
check(sm.perfects >= 2, "skilled changeovers are perfect")
check(Achievements.has("projectionist", "seamless") and Achievements.has("projectionist", "first") and Achievements.has("projectionist", "clean"), "SEAMLESS, FIRST NIGHT, STEADY HANDS unlocked")
check(sm.score >= 2450, "skilled programme earns gold (" .. sm.score .. ")")
H.run(60)
H.shot("std-results")

for _, seed in ipairs({ 7, 99, 2024 }) do
  local mm = skilled("standard", seed)
  print(string.format("  seed %d: score %d jams %d perfect %d", seed, mm.score, mm.jams, mm.perfects))
  H.run(60)
end

------------------------------------------------------------------------
-- 3. jerky projectionist: lurches and stops, never repairs properly
------------------------------------------------------------------------
local jm = H.goMachine("projectionist", "standard", { seed = 555 })
local r = U.rng(3)
local frames = 0
while Scene.current == PlayScene and not jm.finished and frames < 30 * 240 do
  frames = frames + 1
  local c = (frames // 20) % 3 == 0 and r:between(40, 70) or r:between(0, 15)
  if jm.state == "stopped" and r:chance(0.02) then H.press("b") end
  if jm.state == "thread" then H.press(({ "up", "left", "down", "right" })[jm.seq[jm.seqI]]) end
  if jm.state == "closing" then H.press("a") end
  H.frame(c)
  if frames == 300 then H.shot("jerky-1") end
end
print(string.format("jerky: score %d jams %d present %d after %.0fs", jm.score, jm.jams, jm:presentCount(), frames / 30))
check(jm.jams >= 4, "jerky cranking jams repeatedly")
check(jm.score < 1200, "jerky projectionist scores below brass")
H.run(60)

------------------------------------------------------------------------
-- 4. idle: the house empties
------------------------------------------------------------------------
local im = H.goMachine("projectionist", "standard", { seed = 8 })
frames = 0
while Scene.current == PlayScene and not im.finished and frames < 30 * 240 do
  frames = frames + 1
  H.frame(0)
  if frames == 900 then H.shot("idle-1") end
end
print(string.format("idle: finished=%s after %.0fs, score %d", tostring(im.finished ~= nil), frames / 30, im.score))
check(im.finished and not im.finished.success, "idle projectionist: empty house")
check(frames / 30 > 45, "the house empties gradually, not instantly")
H.run(60)

------------------------------------------------------------------------
-- 5. endless: two programmes, then a resume mid-reel
------------------------------------------------------------------------
local em = skilled("endless", 31, nil)
print(string.format("endless (bot stops at 400s): prog %d score %d present %d", em.prog, em.score, em:presentCount()))
check(em.prog >= 2, "endless runs past the first programme")
local st = json.decode(json.encode(em:serialize()))
local p = U.copy(PlayScene.params)
p.resumeState = st
Scene.go(PlayScene, p, "cut")
H.frame(0)
check(PlayScene.machine.reelIdx == em.reelIdx and math.abs(PlayScene.machine.f - em.f) < 1e-6, "resume restores reel and frame")
H.shot("endless-resumed-script")

print(fails == 0 and "ALL PROJECTIONIST TESTS PASSED" or ("PROJECTIONIST FAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)
