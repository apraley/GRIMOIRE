-- CRANKING IT :: scenes/exhibits
-- The Exhibit Hall: a carousel of display cases you crank past.

ExhibitScene = {}

local gfx <const> = playdate.graphics
local floor <const> = math.floor
local sin <const> = math.sin

function ExhibitScene:enter()
  self.t = 0
  self.pos = 0       -- carousel position in exhibits (float)
  self.vel = 0
  self.index = 1
  self.msg, self.msgT = nil, 0
  self.reading = false
end

function ExhibitScene:cranked(change)
  if self.reading then return end
  self.vel = self.vel + change / 90
end

function ExhibitScene:update(dt)
  self.t = self.t + dt
  if self.msgT > 0 then self.msgT = self.msgT - dt end
  local n = #Lore.EXHIBITS
  if Input.repeated(Input.RIGHT) and not self.reading then self.vel = self.vel + 2.5 end
  if Input.repeated(Input.LEFT) and not self.reading then self.vel = self.vel - 2.5 end
  -- carousel with detents: spring toward nearest integer when slow
  self.pos = self.pos + self.vel * dt
  self.vel = self.vel * math.exp(-4 * dt)
  local nearest = floor(self.pos + 0.5)
  if math.abs(self.vel) < 1.2 then self.pos = U.damp(self.pos, nearest, 8, dt) end
  self.pos = U.clamp(self.pos, 0, n - 1)
  local idx = U.clamp(nearest, 0, n - 1) + 1
  if idx ~= self.index then self.index = idx Audio.sfx.tick(700, 0.2) end

  if Input.justPressed(Input.B) then
    if self.reading then self.reading = false Audio.sfx.back() else
      Audio.sfx.back()
      Scene.go(HubScene, { station = "exhibits" }, "wipe")
    end
  elseif Input.justPressed(Input.A) then
    local e = Lore.EXHIBITS[self.index]
    if Lore.exhibitOwned(e) then
      self.reading = not self.reading
      Audio.sfx.menuSelect()
    elseif not e.cond() then
      Audio.sfx.denied()
      self.msg, self.msgT = "Requires: " .. e.need, 2.5
    elseif Lore.restore(e) then
      Audio.sfx.clank(0.6)
      Audio.sfx.gear(0.15)
      self.msg, self.msgT = "Restored: " .. e.name, 2.5
      self.reading = true
    else
      Audio.sfx.denied()
      self.msg, self.msgT = "Restoration costs " .. e.cost .. " gears.", 2.5
    end
  end
end

local function drawCase(e, cx, t, owned, avail)
  -- pedestal
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(cx - 34, 150, 68, 60)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawRect(cx - 30, 154, 60, 52)
  -- glass case
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(cx - 40, 60, 80, 90)
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(2)
  gfx.drawRect(cx - 40, 60, 80, 90)
  gfx.setLineWidth(1)
  gfx.drawLine(cx - 32, 66, cx - 20, 80)
  gfx.drawLine(cx - 28, 66, cx - 18, 76)
  if owned then
    local def = e.machine and Machines.get(e.machine)
    if def then
      HubScene.iconFor(def):draw(cx - 24, 82 + floor(sin(t * 1.5) * 2))
    else
      -- the keeper's chair
      gfx.fillRect(cx - 14, 104, 28, 6)
      gfx.fillRect(cx - 14, 84, 5, 40)
      gfx.fillRect(cx + 9, 110, 4, 16)
      gfx.fillRect(cx - 14, 110, 4, 16)
      Art.crankGlyph(cx + 2, 98, 5, t * 40)
    end
  else
    gfx.setPattern(avail and Art.pat.gray25 or Art.pat.gray75)
    gfx.fillRect(cx - 36, 64, 72, 82)
    gfx.setColor(gfx.kColorBlack)
    UI.text("?", cx, 96, "center", UI.bold)
  end
end

function ExhibitScene:draw()
  gfx.clear(gfx.kColorWhite)
  gfx.setPattern(Art.pat.gray75)
  gfx.fillRect(0, 0, 400, 240)
  -- spotlight cone on the centre case
  gfx.setColor(gfx.kColorWhite)
  gfx.fillPolygon(180, 0, 220, 0, 290, 220, 110, 220)
  gfx.setPattern(Art.pat.gray12)
  gfx.fillPolygon(180, 0, 220, 0, 290, 220, 110, 220)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(0, 210, 400, 30)
  local n = #Lore.EXHIBITS
  for i = 1, n do
    local cx = floor(200 + (i - 1 - self.pos) * 130)
    if cx > -60 and cx < 460 then
      local e = Lore.EXHIBITS[i]
      drawCase(e, cx, self.t, Lore.exhibitOwned(e), e.cond())
    end
  end
  UI.header(nil, "EXHIBIT HALL", self.index .. "/" .. n)
  local e = Lore.EXHIBITS[self.index]
  local owned = Lore.exhibitOwned(e)
  UI.panel(40, 22, 320, 32, "plain")
  UI.text(owned and e.name or "UNRESTORED EXHIBIT", 200, 24, "center", UI.bold)
  UI.text(owned and "A: read placard" or (e.cond() and ("A: restore for " .. e.cost .. " gears") or e.need), 200, 38, "center")
  if self.reading and owned then
    UI.popup(24, 60, 352, 150, "paper")
    UI.text(e.name, 200, 70, "center", UI.bold)
    UI.textBlock(e.text, 38, 92, 324, UI.font, 2)
  end
  if self.msgT > 0 and self.msg then
    UI.popup(50, 170, 300, 30, "ink")
    UI.textW(self.msg, 200, 176, "center")
  end
  UI.hints(ExhibitScene.HINTS)
end

ExhibitScene.HINTS = { { "CRANK", "CAROUSEL" }, { "A", "RESTORE / READ" }, { "B", "BACK" } }
