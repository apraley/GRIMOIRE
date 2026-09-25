-- CRANKING IT :: scenes/hub
-- The Museum of Hand-Turned Things: a long gallery with a conveyor floor.
-- The crank drives the floor (with a little inertia); the d-pad walks.

HubScene = {}

local gfx <const> = playdate.graphics
local sin <const>, cos <const> = math.sin, math.cos
local floor <const> = math.floor

local FLOOR_Y <const> = 200
local CAB_START <const> = 470
local CAB_GAP <const> = 132

local stations = nil
local worldW = 0
local tune = nil
local iconCache = {}

-- cabinet icon rendered once per machine
local function iconFor(def)
  local img = iconCache[def.id]
  if img then return img end
  img = gfx.image.new(48, 48, gfx.kColorClear)
  gfx.pushContext(img)
  if def.drawIcon then def.drawIcon(24, 24, 0) end
  gfx.popContext()
  iconCache[def.id] = img
  return img
end
HubScene.iconFor = iconFor

local function buildStations()
  stations = {}
  stations[#stations + 1] = { kind = "door", x = 70, name = "THE STAIRS", sub = "back to the sea" }
  stations[#stations + 1] = { kind = "daily", x = 200, name = "DAILY MACHINE", sub = "a new machine each day" }
  stations[#stations + 1] = { kind = "curator", x = 330, name = "THE KEEPER", sub = "stories, themes, settings" }
  for i, def in ipairs(Machines.list) do
    stations[#stations + 1] = { kind = "machine", x = CAB_START + (i - 1) * CAB_GAP, def = def, name = "No." .. U.roman(def.number) .. " " .. def.title }
  end
  local last = CAB_START + (#Machines.list - 1) * CAB_GAP
  stations[#stations + 1] = { kind = "exhibits", x = last + 160, name = "EXHIBIT HALL", sub = "restored curiosities" }
  worldW = last + 260
end

function HubScene:enter(params)
  if not stations then buildStations() end
  self.t = 0
  self.px = params.x or Save.data.hubX or 0
  if self.px < 40 then self.px = 120 end
  if params.id then
    for _, s in ipairs(stations) do if s.def and s.def.id == params.id then self.px = s.x end end
  end
  if params.station then
    for _, s in ipairs(stations) do if s.kind == params.station then self.px = s.x end end
  end
  self.vx = 0
  self.floorVel = 0
  self.floorOff = 0
  self.facing = 1
  self.walk = 0
  self.cam = U.clamp(self.px - 200, 0, worldW - 400)
  self.near = nil
  self.dialog = nil
  self.daily = Challenge.daily()
  if not Save.data.introSeen then
    self.dialog = UI.Dialog.new({
      "Ah. A visitor. The tide does not bring many up the stairs any more.",
      "This is the Museum of Hand-Turned Things. Thirteen machines, and not one of them moves unless somebody turns it.",
      "The floor is one of them. Turn your crank and the gallery turns under your feet. The d-pad works too, if you must.",
      "Stand at a cabinet and press A. Master a machine and it pays you in GEARS.",
      "Gears lift the dust sheets off the other cabinets, restore the exhibits, and buy an old man's stories. The thirteenth machine has not been turned in a very long time.",
    }, { speaker = "THE KEEPER", y = 146 })
  end
  if not tune then
    local n = Audio.note
    tune = Audio.MusicBox.new({
      { n("D4"), 1 }, { n("A4"), 1 }, { n("F5"), 1 }, { n("E5"), 1 }, { n("D5"), 1 }, { n("A4"), 1 },
      { n("Bb4"), 1 }, { n("D5"), 1 }, { n("G5"), 1 }, { n("F5"), 2 }, { 0, 1 },
      { n("C4"), 1 }, { n("G4"), 1 }, { n("E5"), 1 }, { n("D5"), 1 }, { n("C5"), 1 }, { n("G4"), 1 },
      { n("A4"), 1 }, { n("C#5"), 1 }, { n("E5"), 1 }, { n("D5"), 3 },
    }, 76, Audio.TRIANGLE, 0.12)
  end
  tune:start()
  local menu = playdate.getSystemMenu()
  self.menuItem = menu:addCheckmarkMenuItem("sound", Save.data.settings.sound, function(v)
    Save.data.settings.sound = v
    Audio.enabled = v
    if not v then Audio.stopAllHums() end
    Save.markDirty()
  end)
end

function HubScene:exit()
  tune:stop()
  Save.data.hubX = floor(self.px)
  Save.markDirty()
  if self.menuItem then playdate.getSystemMenu():removeMenuItem(self.menuItem) self.menuItem = nil end
end

function HubScene:cranked(change)
  if self.dialog then return end
  -- the conveyor has inertia: the crank sets its target velocity
  self.floorVel = self.floorVel + change * 2.5
end

function HubScene:update(dt)
  self.t = self.t + dt
  tune:update(dt, 1)
  if self.dialog then
    self.dialog:update(dt)
    if Input.justPressed(Input.A) or Input.justPressed(Input.B) then
      if self.dialog:advance() then
        self.dialog = nil
        Save.data.introSeen = true
        Save.markDirty()
      end
    end
    return
  end
  -- walking
  local ax = Input.axisX()
  self.vx = U.approach(self.vx, ax * 120, 600 * dt)
  -- conveyor floor: velocity decays (friction), carries the visitor
  self.floorVel = self.floorVel * math.exp(-5 * dt)
  local move = (self.vx + self.floorVel) * dt
  self.px = U.clamp(self.px + move, 30, worldW - 30)
  self.floorOff = self.floorOff + self.floorVel * dt
  if math.abs(move) > 0.1 then
    self.walk = self.walk + math.abs(self.vx) * dt * 0.12
    self.facing = move > 0 and 1 or -1
  end
  local target = U.clamp(self.px - 200 + self.facing * 40, 0, worldW - 400)
  self.cam = U.damp(self.cam, target, 4, dt)

  -- nearest station
  self.near = nil
  for _, s in ipairs(stations) do
    if math.abs(s.x - self.px) < 34 then self.near = s end
  end
  if Input.justPressed(Input.A) and self.near then self:activate(self.near) end
end

function HubScene:activate(s)
  Audio.sfx.menuSelect()
  if s.kind == "machine" then
    Scene.go(LobbyScene, { id = s.def.id }, "shutter")
  elseif s.kind == "daily" then
    Scene.go(LobbyScene, { id = self.daily.id, daily = self.daily }, "shutter")
  elseif s.kind == "curator" then
    Scene.go(CuratorScene, {}, "wipe")
  elseif s.kind == "exhibits" then
    Scene.go(ExhibitScene, {}, "wipe")
  elseif s.kind == "door" then
    Scene.go(TitleScene, {}, "iris", 0.9)
  end
end

------------------------------------------------------------------------
-- drawing
------------------------------------------------------------------------
local function drawWindow(x, t)
  -- arched window showing the sea and a far lighthouse
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x - 30, 40, 60, 70)
  gfx.fillCircleAtPoint(x, 40, 30)
  gfx.setColor(gfx.kColorBlack)
  gfx.setPattern(Art.pat.gray12)
  gfx.fillRect(x - 28, 42, 56, 40)
  gfx.setColor(gfx.kColorBlack)
  -- sea line
  gfx.fillRect(x - 28, 84, 56, 26)
  gfx.setColor(gfx.kColorWhite)
  for i = 0, 3 do
    local wx = x - 26 + ((t * 8 + i * 17) % 52)
    gfx.drawLine(wx, 90 + i * 5, wx + 6, 90 + i * 5)
  end
  -- lighthouse
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(x + 12, 66, 4, 18)
  gfx.fillRect(x + 11, 63, 6, 3)
  local beam = sin(t * 1.5)
  if beam > 0.6 then
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(x + 14, 64, x - 28, 58)
  end
  -- mullions
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(3)
  gfx.drawLine(x, 12, x, 110)
  gfx.drawLine(x - 30, 70, x + 30, 70)
  gfx.drawArc(x, 40, 30, 270, 90)
  gfx.drawRect(x - 30, 40, 60, 70)
  gfx.setLineWidth(1)
end

local function drawLamp(x, t)
  local sw = sin(t * 1.1 + x * 0.01) * 4
  gfx.setColor(gfx.kColorBlack)
  gfx.drawLine(x, 0, x + sw, 22)
  gfx.fillTriangle(x + sw - 7, 30, x + sw + 7, 30, x + sw, 20)
  gfx.fillRect(x + sw - 3, 30, 6, 4)
end

local function drawCabinet(self, s, sx)
  local def = s.def
  local rec = Save.machine(def.id)
  local unlocked = Machines.isUnlocked(def)
  local x, y, w, h = sx - 34, FLOOR_Y - 132, 68, 132
  -- body
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x, y + 18, w, h - 18)
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(2)
  gfx.drawRect(x, y + 18, w, h - 18)
  gfx.setLineWidth(1)
  -- marquee
  gfx.fillRect(x - 4, y, w + 8, 20)
  UI.textW(U.roman(def.number), sx, y + 1, "center", UI.bold)
  -- screen / icon
  gfx.drawRect(x + 8, y + 26, w - 16, 56)
  iconFor(def):draw(sx - 24, y + 30)
  -- crank on the side
  local ca = (self.t * (s == self.near and 180 or 20) + def.number * 30) % 360
  Art.crankGlyph(x + w + 7, y + 60, 7, ca)
  -- base panel: medals
  gfx.setPattern(Art.pat.wood)
  gfx.fillRect(x + 6, y + 90, w - 12, 34)
  gfx.setColor(gfx.kColorBlack)
  local best = 0
  for _, v in pairs(rec.medals) do if v > best then best = v end end
  for i = 1, 3 do
    local mx = sx - 18 + (i - 1) * 18
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(mx, y + 107, 7)
    gfx.setColor(gfx.kColorBlack)
    if i <= best then Art.gear(mx, y + 107, 6, 6, 0, true) else gfx.drawCircleAtPoint(mx, y + 107, 6) end
  end
  if not unlocked then
    -- dust sheet with folds
    gfx.setColor(gfx.kColorWhite)
    gfx.fillPolygon(x - 6, y + 4, x + w + 6, y + 4, x + w + 10, FLOOR_Y, x - 10, FLOOR_Y)
    gfx.setPattern(Art.pat.gray12)
    gfx.fillPolygon(x - 6, y + 4, x + w + 6, y + 4, x + w + 10, FLOOR_Y, x - 10, FLOOR_Y)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawPolygon(x - 6, y + 4, x + w + 6, y + 4, x + w + 10, FLOOR_Y, x - 10, FLOOR_Y)
    for i = 1, 4 do
      local fx = x + i * 14 + sin(self.t + i) * 1
      gfx.drawLine(fx, y + 10, fx - 4 + i, FLOOR_Y - 2)
    end
    -- tag with price
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(sx - 20, y + 54, 40, 22)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(sx - 20, y + 54, 40, 22)
    Art.gear(sx - 10, y + 65, 6, 6, 0, true)
    UI.text(tostring(def.unlockCost), sx + 12, y + 57, "center", UI.bold)
  elseif rec.plays == 0 then
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(sx + 12, y + 20, 30, 14)
    UI.textW("NEW", sx + 27, y + 19, "center")
  end
end

local function drawDaily(self, s, sx)
  -- plinth with a slowly turning golden gear and a calendar card
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(sx - 22, FLOOR_Y - 60, 44, 60)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawRect(sx - 19, FLOOR_Y - 57, 38, 54)
  gfx.setColor(gfx.kColorBlack)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(sx, FLOOR_Y - 92, 26)
  gfx.setColor(gfx.kColorBlack)
  Art.gear(sx, FLOOR_Y - 92, 24, 14, self.t * 30, true)
  iconFor(self.daily.def):drawScaled(sx - 12, FLOOR_Y - 48, 0.5)
  local played = Save.data.daily.played[self.daily.key]
  UI.textW(played and "DONE" or "TODAY", sx, FLOOR_Y - 22, "center")
end

local function drawCurator(self, s, sx)
  -- the Keeper at a desk with a lantern
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(sx - 40, FLOOR_Y - 40, 80, 8)
  gfx.fillRect(sx - 36, FLOOR_Y - 32, 6, 32)
  gfx.fillRect(sx + 30, FLOOR_Y - 32, 6, 32)
  -- keeper figure behind desk
  local bob = sin(self.t * 1.3) * 1
  gfx.fillRect(sx - 8, FLOOR_Y - 70 + bob, 18, 30)
  gfx.fillCircleAtPoint(sx + 1, FLOOR_Y - 78 + bob, 8)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(sx - 2, FLOOR_Y - 80 + bob, 7, 3) -- spectacles glint
  gfx.setColor(gfx.kColorBlack)
  -- beard
  gfx.fillTriangle(sx - 5, FLOOR_Y - 74 + bob, sx + 7, FLOOR_Y - 74 + bob, sx + 1, FLOOR_Y - 60 + bob)
  -- ledger & lantern
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(sx - 30, FLOOR_Y - 46, 22, 6)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(sx - 30, FLOOR_Y - 46, 22, 6)
  gfx.fillRect(sx + 20, FLOOR_Y - 56, 10, 14)
  gfx.setColor(gfx.kColorWhite)
  local flick = 2 + floor(self.t * 8) % 2
  gfx.fillRect(sx + 23, FLOOR_Y - 53, 4, flick + 4)
  gfx.setColor(gfx.kColorBlack)
end

local function drawDoor(self, s, sx, label)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(sx - 28, FLOOR_Y - 110, 56, 110)
  gfx.fillCircleAtPoint(sx, FLOOR_Y - 110, 28)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawRect(sx - 22, FLOOR_Y - 100, 44, 100)
  if label then
    gfx.setPattern(Art.pat.gray50)
    gfx.fillRect(sx - 20, FLOOR_Y - 98, 40, 96)
  end
  gfx.setColor(gfx.kColorBlack)
end

local function drawVisitor(self, x)
  local y = FLOOR_Y
  local step = floor(self.walk * 4) % 4
  local f = self.facing
  gfx.setColor(gfx.kColorBlack)
  -- legs
  local l1 = (step == 1) and 3 or ((step == 3) and -3 or 0)
  gfx.setLineWidth(3)
  gfx.drawLine(x - 2, y - 12, x - 2 + l1, y - 1)
  gfx.drawLine(x + 2, y - 12, x + 2 - l1, y - 1)
  gfx.setLineWidth(1)
  -- coat
  gfx.fillPolygon(x - 7, y - 11, x + 7, y - 11, x + 5, y - 28, x - 5, y - 28)
  -- head + cap
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(x, y - 33, 5)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawCircleAtPoint(x, y - 33, 5)
  gfx.fillRect(x - 5, y - 39, 11, 3)
  gfx.fillRect(x + f * 2, y - 38, 6 * f, 2)
  gfx.drawPixel(x + f * 2, y - 33)
  -- lantern arm
  local lx = x + f * 9
  gfx.drawLine(x + f * 3, y - 24, lx, y - 18)
  gfx.fillRect(lx - 2, y - 18, 5, 7)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawPixel(lx, y - 15)
  gfx.setColor(gfx.kColorBlack)
end

function HubScene:draw()
  local cam = floor(self.cam)
  local t = self.t
  local theme = Themes.current()
  gfx.clear(gfx.kColorWhite)

  -- wall
  gfx.setPattern(Art.pat[Themes.wallPattern()])
  gfx.fillRect(0, 0, 400, FLOOR_Y)
  -- wainscot
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(0, FLOOR_Y - 46, 400, 46)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawLine(0, FLOOR_Y - 46, 400, FLOOR_Y - 46)
  gfx.drawLine(0, FLOOR_Y - 43, 400, FLOOR_Y - 43)
  local off = -(cam % 60)
  for x = off, 400, 60 do gfx.drawRect(x + 6, FLOOR_Y - 38, 48, 32) end

  -- windows (parallax 0.6)
  local wcam = cam * 0.6
  for wx = 140, worldW, 280 do
    local sx = wx - wcam
    if sx > -40 and sx < 440 then drawWindow(floor(sx), t) end
  end
  -- lamps
  for lx = 60, worldW, 132 do
    local sx = lx - cam + 66
    if sx > -20 and sx < 420 then drawLamp(floor(sx), t) end
  end

  -- stations
  for _, s in ipairs(stations) do
    local sx = floor(s.x - cam)
    if sx > -80 and sx < 480 then
      if s.kind == "machine" then drawCabinet(self, s, sx)
      elseif s.kind == "daily" then drawDaily(self, s, sx)
      elseif s.kind == "curator" then drawCurator(self, s, sx)
      elseif s.kind == "door" then drawDoor(self, s, sx)
      elseif s.kind == "exhibits" then drawDoor(self, s, sx, true)
      end
    end
  end

  -- conveyor floor
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(0, FLOOR_Y, 400, 40)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawLine(0, FLOOR_Y + 2, 400, FLOOR_Y + 2)
  local fo = floor((cam + self.floorOff) % 24)
  for x = -fo, 400, 24 do
    gfx.drawLine(x, FLOOR_Y + 4, x, FLOOR_Y + 14)
  end
  -- rollers
  local ro = (cam + self.floorOff) * 3
  for x = -((cam) % 48), 400, 48 do
    gfx.drawCircleAtPoint(x + 24, FLOOR_Y + 24, 7)
    local a = math.rad(ro)
    gfx.drawLine(x + 24, FLOOR_Y + 24, x + 24 + sin(a) * 6, FLOOR_Y + 24 - cos(a) * 6)
  end
  if theme == "tide" then
    gfx.setColor(gfx.kColorWhite)
    gfx.setDitherPattern(0.5, gfx.kDitherTypeBayer4x4)
    gfx.fillRect(0, FLOOR_Y - 10, 400, 14)
    gfx.setColor(gfx.kColorBlack)
    for x = 0, 400, 16 do
      local wy = FLOOR_Y - 10 + sin(t * 2 + x * 0.2) * 2
      gfx.drawLine(x, wy, x + 8, wy)
    end
  end

  drawVisitor(self, floor(self.px - cam))

  -- prompt bubble
  if self.near and not self.dialog then
    local s = self.near
    local sx = floor(s.x - cam)
    local name = s.name
    local sub = s.sub
    if s.kind == "machine" and not Machines.isUnlocked(s.def) then sub = "covered  -  " .. s.def.unlockCost .. " gears" end
    if s.kind == "machine" and Machines.isUnlocked(s.def) then sub = s.def.tagline end
    if s.kind == "daily" then sub = self.daily.def.title end
    local w = math.max(UI.width(name, UI.bold), sub and UI.width(sub) or 0) + 40
    local bx = U.clamp(sx - w / 2, 4, 396 - w)
    local by = 26 + floor(sin(t * 4) * 2)
    UI.popup(bx, by, w, sub and 40 or 24, "plain")
    UI.glyph("A", bx + 6, by + 4)
    UI.text(name, bx + 28, by + 4, "left", UI.bold)
    if sub then UI.text(sub, bx + 28, by + 20) end
  end

  -- gear counter
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRoundRect(318, 4, 78, 22, 5)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(332, 15, 9)
  gfx.setColor(gfx.kColorBlack)
  Art.gear(332, 15, 8, 8, t * 20, true)
  UI.textW(tostring(Save.data.gears), 388, 6, "right", UI.bold)

  if self.dialog then
    self.dialog:draw()
  else
    UI.hints(HubScene.HINTS)
  end
end

HubScene.HINTS = { { "CRANK", "CONVEYOR" }, { "DPAD", "WALK" }, { "A", "INSPECT" } }
