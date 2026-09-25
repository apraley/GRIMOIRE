-- CRANKING IT :: scenes/results
-- The results card: stamp, score count-up, medals, gears dropping into
-- the collection box, achievements.

ResultsScene = {}

local gfx <const> = playdate.graphics
local floor <const> = math.floor

function ResultsScene:enter(sum)
  self.sum = sum
  self.def = sum.def
  self.r = sum.result
  self.t = 0
  self.shown = 0
  self.gearDrops = {}
  self.dropped = 0
  self.stamped = false
  local mode = sum.params.mode
  if mode == "tutorial" then
    self.stampText = sum.result.success and "LESSON LEARNED" or "CLASS DISMISSED"
  elseif sum.params.daily then
    self.stampText = sum.dailyPassed and "DAILY CLEARED" or "NOT TODAY"
  elseif sum.params.challengeId then
    local met = sum.result.score >= (sum.goal or 0) and sum.result.success ~= false
    self.stampText = met and "CHALLENGE MET" or "SHORT OF GOAL"
  else
    self.stampText = sum.result.title or (sum.result.success and "WELL TURNED" or "MACHINE STOPPED")
  end
  if sum.result.success == false then Audio.sfx.fail() else Audio.sfx.success() end
  self.scoreImg = gfx.image.new(160, UI.boldH + 2, gfx.kColorClear)
  self.scoreDrawn = -1
  self.goalText = sum.goal and ("goal " .. U.commas(sum.goal)) or nil
  self.modeLabel = sum.params.daily and "DAILY" or (sum.params.challengeId and "CHALLENGE" or (sum.params.mode or ""):upper())
  local names = {}
  for i, a in ipairs(sum.achievements) do names[i] = a.name end
  self.achText = "* " .. table.concat(names, "  * ")
  self.medalText = {}
  local md = self.def.medals[sum.params.mode]
  if md then for i = 1, 3 do self.medalText[i] = U.commas(md[i]) end end
end

function ResultsScene:update(dt)
  self.t = self.t + dt
  local score = self.r.score
  if self.t > 0.6 and self.shown < score then
    local step = math.max(1, score / 40)
    local before = self.shown
    self.shown = math.min(score, self.shown + step)
    if floor(before / step) ~= floor(self.shown / step) then Audio.sfx.tick(1400, 0.1) end
  end
  if self.t > 0.35 and not self.stamped then
    self.stamped = true
    Audio.sfx.stamp()
    Scene.shake(3)
  end
  -- gears drop one by one
  local g = self.sum.gears
  if self.t > 1.4 and self.dropped < g then
    local want = floor((self.t - 1.4) / 0.35) + 1
    while self.dropped < math.min(g, want) do
      self.dropped = self.dropped + 1
      self.gearDrops[#self.gearDrops + 1] = { y = -20, vy = 0, x = 330 + (self.dropped % 3 - 1) * 12, landed = false, a = 0 }
    end
  end
  for _, d in ipairs(self.gearDrops) do
    if not d.landed then
      d.vy = d.vy + 900 * dt
      d.y = d.y + d.vy * dt
      d.a = d.a + 400 * dt
      if d.y >= 176 then
        d.y = 176
        if math.abs(d.vy) > 120 then d.vy = -d.vy * 0.35 Audio.sfx.tick(2200, 0.3) else d.landed = true Audio.sfx.coin() end
      end
    end
  end

  if self.t > 0.8 then
    if Input.justPressed(Input.A) then
      local p = U.copy(self.sum.params)
      p.resumeState = nil
      if not p.daily and not p.challengeId then p.seed = nil end
      if p.mode == "tutorial" then p.mode = "standard" end
      Scene.go(PlayScene, p, "iris", 0.8)
    elseif Input.justPressed(Input.B) then
      Audio.sfx.back()
      Scene.go(LobbyScene, { id = self.def.id, daily = self.sum.params.daily and Challenge.daily() or nil }, "shutter")
    end
  end
end

function ResultsScene:drawScore()
  local v = floor(self.shown)
  if v ~= self.scoreDrawn then
    self.scoreDrawn = v
    gfx.pushContext(self.scoreImg)
    gfx.clear(gfx.kColorClear)
    UI.text(U.commas(v), 0, 0, "left", UI.bold)
    gfx.popContext()
  end
  self.scoreImg:drawScaled(24, 44, 2)
end

function ResultsScene:draw()
  local def, sum, r = self.def, self.sum, self.r
  gfx.clear(gfx.kColorWhite)
  gfx.setPattern(Art.pat.gray12)
  gfx.fillRect(0, 0, 400, 240)
  UI.header(def.number, def.title, self.modeLabel)

  -- card
  UI.panel(10, 24, 290, 192, "paper")
  UI.text(def.scoreLabel, 24, 30)
  self:drawScore()
  if sum.goal then UI.text(self.goalText, 24, 80) end
  if sum.newBest and self.t > 1.2 then
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRoundRect(196, 84, 92, 18, 4)
    UI.textW("NEW BEST", 242, 84, "center", UI.bold)
  end
  -- result lines
  local y = sum.goal and 98 or 88
  local lines = r.lines or {}
  for i = 1, math.min(#lines, 4) do
    UI.text(lines[i], 24, y)
    y = y + 16
  end
  -- achievements ribbon
  local ach = sum.achievements
  if #ach > 0 and self.t > 1.0 then
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(16, 162, 278, 18)
    UI.textW(self.achText, 22, 163)
  end
  -- medals
  if sum.params.mode ~= "tutorial" and not sum.params.daily and not sum.params.challengeId then
    local md = def.medals[sum.params.mode]
    if md then
      for i = 1, 3 do
        local mx = 30 + (i - 1) * 92
        local got = sum.medal >= i
        local fresh = got and i > sum.medalBefore
        if got then
          Art.gear(mx, 198, 10, 8, fresh and self.t * 90 or 0, true)
        else
          gfx.setColor(gfx.kColorBlack)
          gfx.drawCircleAtPoint(mx, 198, 9)
        end
        UI.text(self.medalText[i], mx + 14, 190)
      end
    end
  elseif sum.streak then
    UI.text("daily streak: " .. sum.streak, 24, 190, "left", UI.bold)
  end
  if self.stamped then UI.stamp(self.stampText, 226, 54, self.t - 0.35) end

  -- gear box
  UI.panel(306, 24, 88, 192, "plain")
  UI.text("GEARS", 350, 30, "center", UI.bold)
  UI.text(U.cached("res_drop", "+%d", self.dropped), 350, 48, "center", UI.bold)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawLine(314, 188, 386, 188)
  gfx.drawLine(314, 150, 314, 188)
  gfx.drawLine(386, 150, 386, 188)
  for _, d in ipairs(self.gearDrops) do Art.gear(d.x, floor(d.y), 8, 8, d.a, true) end
  UI.text(U.cached("res_total", "total %d", Save.data.gears), 350, 194, "center")
  UI.hints(ResultsScene.HINTS)
end

ResultsScene.HINTS = { { "A", "AGAIN" }, { "B", "PLACARD" } }
