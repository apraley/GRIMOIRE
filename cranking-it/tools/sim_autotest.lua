-- CRANKING IT :: simulator autotest (not shipped)
-- Appended to main.lua by .github/workflows/cranking-it-pdx.yml to build a
-- test .pdx that runs in Panic's real Playdate Simulator. It replaces the
-- button/crank/clock readers with a scripted driver, walks the title and
-- gallery, then opens every machine's placard and plays every mode with
-- steady cranking and random input. Errors are caught per step, logged and
-- the run moves on. The log goes to stdout and to the datastore file
-- "autotest", then the Simulator quits.

local pd <const> = playdate

local log = {}
local errors = 0
local function say(s)
  log[#log + 1] = s
  print("AUTOTEST " .. s)
end

-- scripted input -----------------------------------------------------------
local cur, prevHeld, crank = 0, 0, 0
pd.getButtonState = function()
  local pressed = cur & ~prevHeld
  local released = prevHeld & ~cur
  prevHeld = cur
  return cur, pressed, released
end
pd.getCrankChange = function() return crank, crank end
pd.isCrankDocked = function() return false end
pd.getElapsedTime = function() return 1 / 30 end

local BUTTONS <const> = { pd.kButtonA, pd.kButtonB, pd.kButtonUp, pd.kButtonDown, pd.kButtonLeft, pd.kButtonRight }

-- the script is a coroutine that yields once per game frame -------------------
local step = "boot"
local function frames(n, c)
  for _ = 1, n do crank = c or 0 coroutine.yield() end
  crank = 0
end
local function fuzz(n, seed)
  local r = U.rng(seed)
  local c = 0
  for _ = 1, n do
    if r:chance(0.08) then c = r:between(-40, 40) end
    if r:chance(0.05) then c = 0 end
    if r:chance(0.06) then cur = cur ~ BUTTONS[r:range(1, #BUTTONS)] end
    crank = c
    coroutine.yield()
  end
  cur, crank = 0, 0
  coroutine.yield()
end
local function tap(b)
  cur = b coroutine.yield()
  cur = 0 coroutine.yield()
end

local failedStep = nil
local function guarded(name, fn)
  step = name
  failedStep = nil
  fn()
  if failedStep == name then return false end
  return true
end

local script = coroutine.create(function()
  guarded("title", function()
    frames(20)
    frames(40, 40) -- crank the doors open
    frames(60)
    for _ = 1, 12 do tap(pd.kButtonA) frames(8) end
  end)
  guarded("gallery", function()
    frames(40, 30)
    frames(40, -30)
    fuzz(300, 3)
  end)
  for i, def in ipairs(Machines.list) do
    guarded(def.id .. "/placard", function()
      Scene.go(LobbyScene, { id = def.id }, "cut")
      frames(45)
      tap(pd.kButtonDown) frames(10)
      tap(pd.kButtonUp) frames(10)
    end)
    for _, mode in ipairs(def.modes) do
      local name = def.id .. "/" .. mode
      local ok = guarded(name, function()
        Scene.go(PlayScene, { id = def.id, mode = mode, difficulty = 1, seed = 1000 + i }, "cut")
        frames(60)
        frames(150, 20)   -- steady forward cranking
        frames(60, -15)   -- and back
        tap(pd.kButtonA) frames(30, 10)
        cur = pd.kButtonA frames(40, -25) frames(10, 50) cur = 0 frames(60, 8)
        fuzz(700, i * 17 + #mode)
        frames(90)        -- let a results card or transition play out
      end)
      if ok then say("ok   " .. name) end
    end
  end
  step = "done"
end)

-- run the game under the script, several game frames per simulator frame ----
local gameUpdate = pd.update
local finished = false
local tb = (debug and debug.traceback) or function(m) return m end

local function finish()
  finished = true
  say(string.format("finished: %d error(s)", errors))
  pd.datastore.write({ errors = errors, log = log }, "autotest")
  if pd.simulator and pd.simulator.exit then pd.simulator.exit() end
end

pd.display.setRefreshRate(50)
say("start: " .. #Machines.list .. " machines")

function pd.update()
  if finished then return end
  for _ = 1, 4 do
    local okS, errS = coroutine.resume(script)
    if not okS then
      errors = errors + 1
      say("SCRIPT ERROR " .. tostring(errS))
      finish()
      return
    end
    if coroutine.status(script) == "dead" then finish() return end
    local ok, err = xpcall(gameUpdate, tb)
    if not ok then
      errors = errors + 1
      say("ERROR in " .. step .. ": " .. tostring(err))
      failedStep = step
      -- abandon this step: recover to a clean scene and skip ahead
      cur, crank = 0, 0
      pcall(Scene.go, HubScene, {}, "cut")
      pd.graphics.setDrawOffset(0, 0)
      -- fast-forward the script to the next step
      local s = step
      while coroutine.status(script) ~= "dead" and step == s do
        local okR = coroutine.resume(script)
        if not okR then break end
      end
      if coroutine.status(script) == "dead" then finish() return end
    end
  end
end
