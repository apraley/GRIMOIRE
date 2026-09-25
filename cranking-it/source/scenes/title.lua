-- CRANKING IT :: scenes/title
-- The museum doors. You crank them open.

TitleScene = {}

local gfx <const> = playdate.graphics
local sin <const>, cos <const> = math.sin, math.cos

local logoImg, subImg
local tune = nil

local function buildLogo()
  -- draw the logo small, then scale 2x for chunky woodcut letters
  local text = "CRANKING IT"
  local w = UI.width(text, UI.bold) + 4
  local small = gfx.image.new(w, UI.boldH + 2, gfx.kColorClear)
  gfx.pushContext(small)
  UI.text(text, 2, 1, "left", UI.bold)
  gfx.popContext()
  logoImg = Art.cached("title-logo", w * 2 + 8, (UI.boldH + 2) * 2 + 8, function(iw, ih)
    -- shadow
    gfx.setImageDrawMode(gfx.kDrawModeFillBlack)
    small:drawScaled(6, 6, 2)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    small:drawScaled(2, 2, 2)
    small:drawScaled(4, 2, 2)
    small:drawScaled(2, 4, 2)
    small:drawScaled(4, 4, 2)
    gfx.setImageDrawMode(gfx.kDrawModeFillBlack)
    small:drawScaled(3, 3, 2)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
  end)
end

function TitleScene:enter(params)
  self.t = 0
  self.open = 0      -- 0..1 door lift
  self.openVel = 0
  self.leaving = false
  self.gearAngle = 0
  if not logoImg then buildLogo() end
  self.suspend = Save.data.suspend
  if self.suspend and not Machines.get(self.suspend.id) then self.suspend = false end
  self.choice = 1
  if not tune then
    local n = Audio.note
    tune = Audio.MusicBox.new({
      { n("E4"), 1 }, { n("G4"), 1 }, { n("B4"), 1 }, { n("E5"), 2 }, { n("D5"), 1 },
      { n("B4"), 1 }, { n("C5"), 1 }, { n("A4"), 2 }, { 0, 1 },
      { n("A4"), 1 }, { n("C5"), 1 }, { n("E5"), 1 }, { n("G5"), 2 }, { n("F#5"), 1 },
      { n("D5"), 1 }, { n("B4"), 1 }, { n("E5"), 3 }, { 0, 2 },
    }, 84, Audio.TRIANGLE, 0.14)
  end
  tune:start()
end

function TitleScene:exit()
  tune:stop()
end

function TitleScene:go()
  if self.leaving then return end
  self.leaving = true
  Audio.sfx.clank(0.6)
  if self.suspend and self.choice == 2 then
    local s = self.suspend
    local p = U.copy(s.params)
    p.resumeState = s.state
    Scene.go(PlayScene, p, "iris", 0.9)
  else
    Scene.go(HubScene, {}, "iris", 0.9)
  end
end

function TitleScene:update(dt)
  self.t = self.t + dt
  tune:update(dt, 0.6 + self.open)
  -- the portcullis has weight: it sinks back if you stop cranking
  if not self.leaving then
    self.open = math.max(0, self.open - dt * 0.12 * (1 - self.open))
    if Crank.docked() and Input.justPressed(Input.A) then self:go() end
    if self.open >= 1 then self:go() end
  end
  self.gearAngle = self.gearAngle + dt * 10
end

function TitleScene:cranked(change)
  if self.leaving then return end
  if change > 0 then
    local before = self.open
    self.open = math.min(1, self.open + change / 900)
    self.gearAngle = self.gearAngle + change * 0.5
    -- ratchet clicks every 1/24 of the travel
    if math.floor(before * 24) ~= math.floor(self.open * 24) then Audio.sfx.tick(900 + self.open * 900, 0.2) end
  end
end

function TitleScene:buttonDown(b)
  if self.suspend and (b == Input.UP or b == Input.DOWN) then
    self.choice = 3 - self.choice
    Audio.sfx.menuMove()
  elseif b == Input.A and self.suspend and self.choice == 2 then
    self:go()
  end
end

local function drawDoorway(self)
  gfx.setDrawOffset(0, 22)
  -- stone arch
  gfx.setPattern(Art.pat.bricks)
  gfx.fillRect(110, 60, 180, 160)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(140, 90, 120, 130)
  gfx.fillCircleAtPoint(200, 92, 60)
  -- inside: warm light (white) revealed as door lifts
  local lift = math.floor(self.open * 128)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(146, 220 - lift, 108, lift)
  -- portcullis grid
  local top = 36 - lift
  gfx.setColor(gfx.kColorBlack)
  gfx.setClipRect(140, 30, 120, 190)
  gfx.setPattern(Art.pat.grain)
  gfx.fillRect(142, top + 60, 116, 130)
  gfx.setColor(gfx.kColorBlack)
  for x = 146, 256, 14 do gfx.fillRect(x, top + 60, 4, 132) end
  for y = top + 70, top + 188, 18 do gfx.fillRect(142, y, 116, 3) end
  for x = 146, 256, 14 do gfx.fillTriangle(x - 1, top + 190, x + 5, top + 190, x + 2, top + 198) end
  gfx.clearClipRect()
  -- keystone with gear
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(200, 44, 22)
  gfx.setColor(gfx.kColorBlack)
  Art.gear(200, 44, 20, 12, self.gearAngle, true)
  gfx.setColor(gfx.kColorBlack)
  gfx.setDrawOffset(0, 0)
end

function TitleScene:draw()
  gfx.clear(gfx.kColorWhite)
  -- night sky + moon
  gfx.setPattern(Art.pat.gray87)
  gfx.fillRect(0, 0, 400, 170)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(335, 40, 16)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(341, 36, 14)
  for i = 1, 20 do
    local x = (i * 97) % 400
    local y = (i * 53) % 120
    if (math.floor(self.t * 2 + i) % 7) ~= 0 then gfx.setColor(gfx.kColorWhite) gfx.drawPixel(x, y) end
  end
  -- sea
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(0, 170, 400, 70)
  gfx.setColor(gfx.kColorWhite)
  for row = 0, 5 do
    local yy = 176 + row * 10
    local ph = self.t * (1 + row * 0.3)
    for x = (row * 13) % 40, 400, 40 do
      local wx = x + sin(ph + x) * 6
      gfx.drawLine(wx, yy, wx + 14 + row * 2, yy)
    end
  end
  -- rock + stairs
  gfx.setColor(gfx.kColorBlack)
  gfx.fillPolygon(60, 240, 90, 150, 310, 150, 340, 240)
  gfx.setColor(gfx.kColorWhite)
  for i = 0, 5 do gfx.drawLine(170 - i * 6, 228 - i * 0, 230 + i * 6, 228 - i * 0) end
  for i = 0, 4 do
    local y = 222 - i * 1
    gfx.drawLine(160 + i * 2, 238 - i * 3, 240 - i * 2, 238 - i * 3)
  end
  drawDoorway(self)
  -- logo ribbon
  local lw, lh = logoImg:getSize()
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(0, 2, 400, lh + 2)
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(2)
  gfx.drawLine(0, 2, 400, 2)
  gfx.drawLine(0, lh + 4, 400, lh + 4)
  gfx.setLineWidth(1)
  logoImg:draw(200 - lw / 2 + 2, 3 + math.floor(sin(self.t * 1.3) * 1))
  Art.gear(26, lh / 2 + 3, 14, 10, -self.gearAngle, true)
  Art.gear(374, lh / 2 + 3, 14, 10, self.gearAngle, true)

  -- prompt
  local py = 196
  if self.suspend then
    UI.panel(110, 150, 180, 44, "plain")
    local items = { "ENTER MUSEUM", "RESUME " .. Machines.get(self.suspend.id).title }
    for i = 1, 2 do
      local y = 154 + (i - 1) * 18
      if i == self.choice then
        gfx.fillRect(114, y, 172, 17)
        UI.textW(items[i], 200, y, "center", UI.bold)
      else
        UI.text(items[i], 200, y, "center")
      end
    end
    UI.panel(90, 206, 220, 26, "ink")
    UI.textW(self.choice == 1 and "TURN THE CRANK TO ENTER" or "PRESS A TO RESUME", 200, 210, "center", UI.bold)
  else
    UI.panel(90, 206, 220, 26, "ink")
    if Crank.docked() then
      UI.textW("PRESS A TO ENTER", 200, 210, "center", UI.bold)
    else
      UI.textW("TURN THE CRANK TO ENTER", 200, 210, "center", UI.bold)
    end
  end
  -- crank progress on the right edge
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(372, 60, 12, 120)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(372, 60, 12, 120)
  gfx.fillRect(374, 178 - math.floor(116 * self.open), 8, math.floor(116 * self.open))
  Art.crankGlyph(378, 196, 8, (self.t * 200) % 360)
end
