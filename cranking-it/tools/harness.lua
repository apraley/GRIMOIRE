-- Test harness: boots the game on the mock runtime and drives it frame by
-- frame with scripted crank and button input.
--
--   local H = dofile("tools/harness.lua")
--   H.boot({ wipe = true })
--   H.crank(20, 60)          -- 20 deg/frame for 60 frames
--   H.press("a")
--   H.shot("after-a")        -- writes shots/after-a.png
--
-- Run from the cranking-it directory.

local H = {}
local M = dofile("tools/mock_playdate.lua")
H.M = M
M.sourceDir = "source"
H.shotDir = os.getenv("SHOT_DIR") or "shots"

local BTN = { a = 32, b = 16, up = 4, down = 8, left = 1, right = 2 }
H.BTN = BTN
local held = 0
local prevHeld = 0
H.pendingCrank = 0

function H.boot(opts)
  opts = opts or {}
  if opts.wipe then M.wipeData() end
  if opts.docked ~= nil then M.crankDocked = opts.docked end
  math.randomseed(opts.seed or 1)
  import("main")
  M.endFrame()
end

-- advance one frame with crank delta (degrees)
function H.frame(crank)
  crank = crank or 0
  M.crankChange = crank
  M.crankPos = (M.crankPos + crank) % 360
  M.buttonsCur = held
  M.buttonsPressed = held & ~prevHeld
  M.buttonsReleased = prevHeld & ~held
  prevHeld = held
  M.beginFrame()
  playdate.update()
  M.endFrame()
end

function H.run(n, crank, opts)
  for _ = 1, n do
    local c = crank
    if type(crank) == "function" then c = crank() end
    H.frame(c or 0)
  end
end

function H.crank(degPerFrame, frames) H.run(frames or 1, degPerFrame) end

function H.hold(name) held = held | BTN[name] end
function H.release(name) held = held & ~BTN[name] end

function H.press(name, crank)
  H.hold(name)
  H.frame(crank)
  H.release(name)
  H.frame(crank)
end

function H.holdFor(name, frames, crank)
  H.hold(name)
  H.run(frames, crank)
  H.release(name)
  H.frame(0)
end

function H.shot(name)
  local was = M.render
  M.render = true
  H.frame(0)
  M.render = was
  os.execute("mkdir -p '" .. H.shotDir .. "'")
  local pbm = H.shotDir .. "/" .. name .. ".pbm"
  M.savePBM(pbm)
  os.execute("python3 tools/topng.py '" .. pbm .. "' >/dev/null 2>&1 && rm -f '" .. pbm .. "'")
end

-- average KB allocated per frame over n frames of the given input
function H.allocProbe(n, crank)
  collectgarbage("collect")
  collectgarbage("stop")
  local before = collectgarbage("count")
  H.run(n, crank)
  local after = collectgarbage("count")
  collectgarbage("restart")
  return (after - before) / n
end

function H.scene() return Scene.current end

function H.goMachine(id, mode, extra)
  local p = { id = id, mode = mode or "standard", difficulty = 1, seed = 12345 }
  if extra then for k, v in pairs(extra) do p[k] = v end end
  Scene.go(PlayScene, p, "cut")
  H.frame(0)
  return PlayScene.machine
end

-- simple deterministic pseudo-random input fuzzing
function H.fuzz(frames, seed)
  local r = U.rng(seed or 7)
  local names = { "a", "b", "up", "down", "left", "right" }
  local crank = 0
  for _ = 1, frames do
    if r:chance(0.08) then crank = r:between(-40, 40) end
    if r:chance(0.05) then crank = 0 end
    if r:chance(0.06) then
      local nm = names[r:range(1, #names)]
      if (held & BTN[nm]) ~= 0 then H.release(nm) else H.hold(nm) end
    end
    H.frame(crank)
  end
  held = 0
  H.frame(0)
end

function H.releaseAll() held = 0 end

return H
