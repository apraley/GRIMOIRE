-- CRANKING IT :: core/machine
-- Base class for the thirteen machines, the machine registry, the progress
-- bookkeeping (medals, gears, bests) and PlayScene, which hosts a running
-- machine with a fixed timestep, tutorials, challenge modifiers and
-- suspend/resume.
--
-- Every machine implements:
--   init() enter(params) exit() update(dt) draw()
--   cranked(change, acceleratedChange) buttonDown(button)
--   serialize() -> table|nil     deserialize(table)
-- and may implement buttonUp(button).

Machine = U.class()
Machines = { list = {}, byId = {} }

local gfx <const> = playdate.graphics
local STEP <const> = 1 / 30
local MAX_STEPS <const> = 3

------------------------------------------------------------------------
-- definition & registry
------------------------------------------------------------------------
-- def fields:
--   id, number, title, tagline, description, controls = {{glyph, text}},
--   modes = {"tutorial","standard","endless"}, medals = {standard={b,s,g}, endless={...}},
--   scoreLabel, unlockCost, achievements = {{id,name,desc}}, challenges = {...},
--   records = {{key,label,fmt}}, drawIcon(cx, cy, t) (48x48 cabinet art)
function Machine.define(def)
  local C = U.class(Machine)
  C.def = def
  def.class = C
  def.modes = def.modes or { "tutorial", "standard" }
  def.medals = def.medals or {}
  def.achievements = def.achievements or {}
  def.challenges = def.challenges or {}
  def.records = def.records or {}
  def.unlockCost = def.unlockCost or 0
  def.scoreLabel = def.scoreLabel or "SCORE"
  Machines.list[#Machines.list + 1] = def
  Machines.byId[def.id] = def
  table.sort(Machines.list, function(a, b) return a.number < b.number end)
  return C
end

function Machines.get(id) return Machines.byId[id] end

function Machines.isUnlocked(def)
  if def.unlockCost == 0 then return true end
  return Save.machine(def.id).unlocked
end

function Machines.hasMode(def, mode)
  return U.indexOf(def.modes, mode) ~= nil
end

------------------------------------------------------------------------
-- base behaviour (all no-ops so machines only override what they need)
------------------------------------------------------------------------
function Machine:init() end
function Machine:enter(params) end
function Machine:exit() end
function Machine:update(dt) end
function Machine:draw() end
function Machine:cranked(change, accel) end
function Machine:buttonDown(b) end
function Machine:buttonUp(b) end
function Machine:serialize() return nil end
function Machine:deserialize(t) end

-- called by PlayScene before enter()
function Machine:_setup(params)
  self.def = self.def or getmetatable(self).def
  self.params = params
  self.mode = params.mode or "standard"
  self.difficulty = params.difficulty or 1
  self.seed = params.seed or U.hash(tostring(playdate.getSecondsSinceEpoch()))
  self.rng = U.rng(self.seed)
  self.mods = params.mods or {}
  self.finished = nil
  self.coach = nil
end

function Machine:mod(name) return self.mods[name] == true end

-- End the run. result = {success=bool, score=int, title=str, lines={str}, delay=sec}
function Machine:finish(result)
  if self.finished then return end
  result.score = math.floor(result.score or 0)
  self.finished = result
end

function Machine:award(achId) Achievements.unlock(self.def.id, achId) end
function Machine:statAdd(key, d) return Save.statAdd(self.def.id, key, d) end
function Machine:statMax(key, v) return Save.statMax(self.def.id, key, v) end
function Machine:shake(m) Scene.shake(m or 3) end
function Machine:flash(f) Scene.flash(f or 2) end
function Machine:best(mode) return Save.machine(self.def.id).best[mode or self.mode] or 0 end

------------------------------------------------------------------------
-- Progress: record results, medals and gears
------------------------------------------------------------------------
Progress = {}

function Progress.medalFor(def, mode, score)
  local m = def.medals[mode]
  if not m then return 0 end
  local tier = 0
  for i = 1, 3 do if score >= m[i] then tier = i end end
  return tier
end

-- returns a summary table used by the Results scene
function Progress.record(def, params, result)
  local rec = Save.machine(def.id)
  local mode = params.mode or "standard"
  local sum = {
    def = def, params = params, result = result,
    gears = 0, newBest = false, medal = 0, medalBefore = 0,
    achievements = Achievements.drainSession(),
  }
  rec.plays = rec.plays + 1
  Save.data.totals.plays = Save.data.totals.plays + 1

  if mode == "tutorial" then
    if result.success and not rec.tutorialDone then
      rec.tutorialDone = true
      sum.gears = sum.gears + 1
      sum.tutorialFirst = true
    end
  elseif params.challengeId then
    local ch = rec.challenges[params.challengeId] or { owned = true, best = 0, done = false }
    rec.challenges[params.challengeId] = ch
    if result.score > (ch.best or 0) then ch.best = result.score sum.newBest = true end
    local cdef = nil
    for _, c in ipairs(def.challenges) do if c.id == params.challengeId then cdef = c end end
    if cdef and not ch.done and result.score >= (cdef.goal or 0) and result.success ~= false then
      ch.done = true
      sum.challengeDone = true
      sum.gears = sum.gears + (cdef.reward or 2)
    end
    sum.goal = cdef and cdef.goal
  elseif params.daily then
    local d = Save.data.daily
    local prev = d.played[params.daily]
    local passed = result.score >= (params.goal or 0) and result.success ~= false
    sum.goal = params.goal
    sum.dailyPassed = passed
    if not prev or result.score > prev then d.played[params.daily] = result.score sum.newBest = prev ~= nil end
    if passed and d.lastKey ~= params.daily then
      -- streak continues only from yesterday's key
      local yesterday = Challenge.keyForDay(Challenge.dayOfKey(params.daily) - 1)
      if d.lastKey == yesterday then d.streak = d.streak + 1 else d.streak = 1 end
      d.bestStreak = math.max(d.bestStreak, d.streak)
      d.lastKey = params.daily
      d.completed = d.completed + 1
      sum.gears = sum.gears + 1 + ((d.streak % 3 == 0) and 1 or 0)
      sum.streak = d.streak
    end
    -- trim old daily entries so the save stays small
    local count = 0
    for _ in pairs(d.played) do count = count + 1 end
    if count > 40 then
      local keys = {}
      for k in pairs(d.played) do keys[#keys + 1] = k end
      table.sort(keys)
      for i = 1, #keys - 30 do d.played[keys[i]] = nil end
    end
  else
    local best = rec.best[mode] or 0
    if result.score > best then
      rec.best[mode] = result.score
      sum.newBest = best > 0 or result.score > 0
    end
    local before = rec.medals[mode] or 0
    local now = Progress.medalFor(def, mode, result.score)
    sum.medalBefore = before
    sum.medal = now
    if now > before then
      rec.medals[mode] = now
      for tier = before + 1, now do sum.gears = sum.gears + (tier == 3 and 2 or 1) end
    end
  end
  if sum.gears > 0 then Save.addGears(sum.gears) end
  Achievements.checkMeta()
  local extra = Achievements.drainSession()
  for i = 1, #extra do sum.achievements[#sum.achievements + 1] = extra[i] end
  Save.data.suspend = false
  Save.markDirty()
  Save.flush()
  return sum
end

------------------------------------------------------------------------
-- PlayScene
------------------------------------------------------------------------
PlayScene = {}

local menuItems = {}

local function clearMenu()
  local menu = playdate.getSystemMenu()
  for i = #menuItems, 1, -1 do
    menu:removeMenuItem(menuItems[i])
    menuItems[i] = nil
  end
end

function PlayScene:enter(params)
  self.params = params
  self.def = Machines.get(params.id)
  self.machine = self.def.class.new()
  self.machine:_setup(params)
  self.acc = 0
  self.t = 0
  self.finishT = 0
  self.help = false
  self.docked = false
  self.rust = 0
  self.rustThreshold = 10
  self.crankTotal = 0
  self.machine:enter(params)
  if params.resumeState then
    local ok, err = pcall(self.machine.deserialize, self.machine, params.resumeState)
    if not ok then print("resume failed: " .. tostring(err)) end
  end
  Crank.scale = 1
  clearMenu()
  local menu = playdate.getSystemMenu()
  menuItems[#menuItems + 1] = menu:addMenuItem("how to play", function() self.help = true end)
  menuItems[#menuItems + 1] = menu:addMenuItem("restart", function()
    local p = U.copy(self.params)
    p.resumeState = nil
    Scene.go(PlayScene, p, "shutter")
  end)
  menuItems[#menuItems + 1] = menu:addMenuItem("leave machine", function()
    Save.data.suspend = false
    Save.markDirty()
    Scene.go(LobbyScene, { id = self.def.id }, "shutter")
  end)
  Save.data.suspend = false
end

function PlayScene:exit()
  clearMenu()
  if self.machine then self.machine:exit() end
  Audio.stopAllHums()
  Crank.scale = 1
end

-- write an in-progress snapshot so the machine resumes after a quit/sleep
function PlayScene:suspend()
  if not self.machine or self.machine.finished then return end
  local ok, state = pcall(self.machine.serialize, self.machine)
  if ok and type(state) == "table" then
    local p = U.copy(self.params)
    p.resumeState = nil
    Save.data.suspend = { id = self.def.id, params = p, state = state }
    Save.markDirty()
  end
end

function PlayScene:needsCrank()
  return self.def.needsCrank ~= false
end

function PlayScene:update(dt)
  self.t = self.t + dt
  local m = self.machine
  self.docked = self:needsCrank() and Crank.docked()
  if self.help or self.docked then
    Audio.stopAllHums()
    return
  end
  if m.finished then
    self.finishT = self.finishT + dt
    -- let the machine animate its ending
    m:update(STEP)
    if self.finishT > (m.finished.delay or 1.4) then
      Save.data.totals.crankDegrees = Save.data.totals.crankDegrees + math.floor(self.crankTotal)
      self.crankTotal = 0
      local sum = Progress.record(self.def, self.params, m.finished)
      Scene.go(ResultsScene, sum, "iris", 0.8)
    end
    return
  end
  local simDt = dt
  if self.params.mods and self.params.mods.haste then simDt = dt * 1.35 end
  self.acc = math.min(self.acc + simDt, STEP * MAX_STEPS)
  local steps = 0
  while self.acc >= STEP - 1e-6 and steps < MAX_STEPS do
    m:update(STEP)
    self.acc = self.acc - STEP
    steps = steps + 1
  end
  if m.coach then
    if m.coach:update(dt) and not m.finished then
      m:finish({ success = true, score = 0, title = "LESSON LEARNED",
        lines = { "You know how the " .. self.def.title .. " works.", "Standard mode awaits." }, delay = 0.6 })
    end
  end
end

function PlayScene:draw()
  local m = self.machine
  m:draw()
  if m.coach and not m.finished then m.coach:draw() end
  if self.params.mods and self.params.mods.fog then
    gfx.setColor(gfx.kColorWhite)
    gfx.setDitherPattern(0.45, gfx.kDitherTypeBayer4x4)
    gfx.fillRect(0, 0, 400, 240)
    gfx.setColor(gfx.kColorBlack)
  end
  if self.help then self:drawHelp() end
  if self.docked and not self.help then UI.dockedOverlay(self.t) end
end

function PlayScene:drawHelp()
  local def = self.def
  UI.popup(20, 16, 360, 208, "paper")
  UI.text(def.title, 200, 26, "center", UI.bold)
  local y = 48
  for i = 1, #def.controls do
    local c = def.controls[i]
    UI.glyph(c[1], 34, y)
    UI.text(c[2], 64, y)
    y = y + 20
  end
  if def.howto then UI.textBlock(def.howto, 34, y + 4, 330, UI.font, 0) end
  UI.text("press any button", 200, 202, "center")
end

function PlayScene:cranked(change, accel)
  if self.help or self.docked then return end
  self.crankTotal = self.crankTotal + math.abs(change)
  if self.params.mods and self.params.mods.rusty then
    -- rusty crank: small motions stick, then lurch free
    self.rust = self.rust + change
    if math.abs(self.rust) < self.rustThreshold then return end
    change = self.rust * 1.15
    accel = change
    self.rust = 0
    self.rustThreshold = 6 + math.random() * 14
    Audio.sfx.creak(0.12)
  end
  self.machine:cranked(change * Crank.scale, accel * Crank.scale)
end

function PlayScene:buttonDown(b)
  if self.help then self.help = false return end
  if self.docked then return end
  if self.machine.finished then return end
  self.machine:buttonDown(b)
end

function PlayScene:buttonUp(b)
  if self.help or self.docked or self.machine.finished then return end
  self.machine:buttonUp(b)
end
