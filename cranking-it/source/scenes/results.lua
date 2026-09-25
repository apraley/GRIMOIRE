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

function ResultsScene:draw()
  local def, sum, r = self.def, self.sum, self.r
  gfx.clear(gfx.kColorWhite)
  gfx.setPattern(Art.pat.gray12)
  gfx.fillRect(0, 0, 400, 240)
  UI.header(def.number, def.title, sum.params.daily and "DAILY" or (sum.params.challengeId and "CHALLENGE" or (sum.params.mode or ""):upper()))

  -- card
  UI.panel(10, 24, 290, 192, "paper")
  UI.text(def.scoreLabel, 26, 34)
  UI.text(U.commas(floor(self.shown)), 26, 50, "left", UI.bold)
  if sum.newBest and self.t > 1.2 then
    gfx.fillRoundRect(150, 34, 90, 20, 4)
    UI.textW("NEW BEST", 195, 35, "center", UI.bold)
  end
  if sum.goal then UI.text("goal " .. U.commas(sum.goal), 150, 56) end
  -- result lines
  local y = 78
  local lines = r.lines or {}
  for i = 1, math.min(#lines, 5) do
    UI.text(lines[i], 26, y)
    y = y + 18
  end
  -- medals
  if sum.params.mode ~= "tutorial" and not sum.params.daily and not sum.params.challengeId then
    local md = def.medals[sum.params.mode]
    if md then
      for i = 1, 3 do
        local mx = 40 + (i - 1) * 90
        local got = sum.medal >= i
        local fresh = got and i > sum.medalBefore
        if got then
          local a = fresh and self.t * 90 or 0
          Art.gear(mx, 190, 10, 8, a, true)
        else
          gfx.drawCircleAtPoint(mx, 190, 9)
        end
        UI.text(LobbyScene.MEDAL_NAMES[i] .. " " .. U.commas(md[i]), mx + 14, 182)
      end
    end
  elseif sum.streak then
    UI.text("daily streak: " .. sum.streak, 26, 182, "left", UI.bold)
  end
  if self.stamped then UI.stamp(self.stampText, 200, 120, self.t - 0.35) end

  -- gear box
  UI.panel(306, 24, 88, 192, "plain")
  UI.text("GEARS", 350, 30, "center", UI.bold)
  UI.text("+" .. self.dropped, 350, 48, "center", UI.bold)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawLine(314, 188, 386, 188)
  gfx.drawLine(314, 150, 314, 188)
  gfx.drawLine(386, 150, 386, 188)
  for _, d in ipairs(self.gearDrops) do Art.gear(d.x, floor(d.y), 8, 8, d.a, true) end
  UI.text("total " .. Save.data.gears, 350, 194, "center")
  -- achievements
  local ach = sum.achievements
  if #ach > 0 and self.t > 1.0 then
    UI.popup(24, 128, 260, 20 + #ach * 16, "ink")
    for i = 1, math.min(3, #ach) do UI.textW("* " .. ach[i].name, 34, 132 + (i - 1) * 16) end
  end
  UI.hints(ResultsScene.HINTS)
end

ResultsScene.HINTS = { { "A", "AGAIN" }, { "B", "PLACARD" } }
