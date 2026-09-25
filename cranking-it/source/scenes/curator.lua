-- CRANKING IT :: scenes/curator
-- The Keeper's desk: stories (lore bought with gears), visual themes,
-- museum statistics and settings.

CuratorScene = {}

local gfx <const> = playdate.graphics
local floor <const> = math.floor

function CuratorScene:enter()
  self.t = 0
  self.page = "main"
  self.dialog = nil
  self.msg, self.msgT = nil, 0
  self.confirmErase = 0
  self:buildMain()
end

function CuratorScene:buildMain()
  self.page = "main"
  self.menu = UI.Menu.new({
    { label = "HEAR A STORY", action = "stories" },
    { label = "CHANGE THE LAMPS", action = "themes" },
    { label = "MUSEUM LEDGER", action = "stats" },
    { label = "SETTINGS", action = "settings" },
    { label = "BACK TO GALLERY", action = "back" },
  }, { rowH = 22, visible = 5 })
end

function CuratorScene:buildStories()
  self.page = "stories"
  local items = {}
  for _, f in ipairs(Lore.FRAGMENTS) do
    local right
    if Lore.owned(f.id) then right = "heard"
    elseif Lore.available(f) then right = f.cost .. " gears"
    else right = "later" end
    items[#items + 1] = { label = Lore.owned(f.id) and f.title or (Lore.available(f) and f.title or "? ? ?"), right = right, f = f }
  end
  self.menu = UI.Menu.new(items, { rowH = 18, visible = 8 })
end

function CuratorScene:buildThemes()
  self.page = "themes"
  local items = {}
  for _, th in ipairs(Themes.LIST) do
    local right
    if Themes.current() == th.id then right = "lit"
    elseif Themes.owned(th.id) then right = "owned"
    else right = th.cost .. " gears" end
    items[#items + 1] = { label = th.name, right = right, th = th }
  end
  self.menu = UI.Menu.new(items, { rowH = 22, visible = 5 })
end

function CuratorScene:buildSettings()
  self.page = "settings"
  local s = Save.data.settings
  self.menu = UI.Menu.new({
    { label = "SOUND", right = s.sound and "on" or "off", action = "sound" },
    { label = "GENTLE SHAKE", right = s.reduceShake and "on" or "off", action = "shake" },
    { label = "ERASE ALL PROGRESS", right = self.confirmErase > 0 and "sure?" or "", action = "erase" },
  }, { rowH = 22, visible = 5, index = self.menu and self.menu.index or 1 })
end

function CuratorScene:say(m) self.msg, self.msgT = m, 2.4 end

function CuratorScene:update(dt)
  self.t = self.t + dt
  if self.msgT > 0 then self.msgT = self.msgT - dt end
  if self.dialog then
    self.dialog:update(dt)
    if Input.justPressed(Input.A) or Input.justPressed(Input.B) then
      if self.dialog:advance() then self.dialog = nil end
    end
    return
  end
  local sel = self.menu:update(dt)
  if not sel then return end
  if sel == "back" or sel.action == "back" then
    if self.page == "main" then
      Audio.sfx.back()
      Scene.go(HubScene, { station = "curator" }, "wipe")
    else
      Audio.sfx.back()
      self.confirmErase = 0
      self:buildMain()
    end
    return
  end
  if self.page == "main" then
    if sel.action == "stories" then self:buildStories()
    elseif sel.action == "themes" then self:buildThemes()
    elseif sel.action == "settings" then self:buildSettings()
    elseif sel.action == "stats" then self.page = "stats" self.menu = UI.Menu.new({}, {}) end
  elseif self.page == "stories" and sel.f then
    local f = sel.f
    if Lore.owned(f.id) or Lore.buy(f) then
      local pages = {}
      for i, p in ipairs(f.text) do pages[i] = p end
      self.dialog = UI.Dialog.new(pages, { speaker = "THE KEEPER", y = 140, h = 90 })
      self:buildStories()
    elseif not Lore.available(f) then
      self:say("Come back when you have earned " .. f.after .. " gears.")
    else
      self:say("A gear or two for an old man's story.")
    end
  elseif self.page == "themes" and sel.th then
    local th = sel.th
    if Themes.owned(th.id) or Themes.buy(th.id) then
      Themes.select(th.id)
      Audio.sfx.clank(0.4)
      self:buildThemes()
    else
      self:say("That lamp costs " .. th.cost .. " gears.")
    end
  elseif self.page == "settings" then
    local s = Save.data.settings
    if sel.action == "sound" then
      s.sound = not s.sound
      Audio.enabled = s.sound
      if not s.sound then Audio.stopAllHums() end
    elseif sel.action == "shake" then
      s.reduceShake = not s.reduceShake
    elseif sel.action == "erase" then
      self.confirmErase = self.confirmErase + 1
      if self.confirmErase >= 3 then
        Save.wipe()
        Audio.enabled = Save.data.settings.sound
        Themes.apply()
        self.confirmErase = 0
        self:say("The ledger is blank again.")
      elseif self.confirmErase == 2 then
        self:say("Press once more to erase everything.")
      end
    end
    Save.markDirty()
    self:buildSettings()
  end
end

function CuratorScene:cranked(change) if not self.dialog then self.menu:cranked(change) end end

local function statLines()
  local d = Save.data
  local got, all = Achievements.total()
  local unlocked = 0
  for _, def in ipairs(Machines.list) do if Machines.isUnlocked(def) then unlocked = unlocked + 1 end end
  local exh = 0
  for _, e in ipairs(Lore.EXHIBITS) do if Lore.exhibitOwned(e) then exh = exh + 1 end end
  return {
    { "Machines uncovered", unlocked .. " / " .. #Machines.list },
    { "Achievements", got .. " / " .. all },
    { "Exhibits restored", exh .. " / " .. #Lore.EXHIBITS },
    { "Gears earned", U.commas(d.gearsEarned) },
    { "Machines played", U.commas(d.totals.plays) },
    { "Crank turned", U.commas(floor(d.totals.crankDegrees / 360)) .. " turns" },
    { "Time in museum", U.timeStr(d.totals.seconds) },
    { "Daily streak (best)", d.daily.streak .. " (" .. d.daily.bestStreak .. ")" },
  }
end

function CuratorScene:draw()
  gfx.clear(gfx.kColorWhite)
  gfx.setPattern(Art.pat.wood)
  gfx.fillRect(0, 0, 400, 240)
  UI.header(nil, "THE KEEPER'S DESK", tostring(Save.data.gears) .. " gears")
  -- keeper portrait
  UI.panel(8, 24, 120, 150, "paper")
  local bob = math.sin(self.t * 1.2) * 1.5
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(68, 76 + bob, 26)
  gfx.fillRect(34, 100 + bob, 68, 66)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawCircleAtPoint(58, 74 + bob, 6)
  gfx.drawCircleAtPoint(78, 74 + bob, 6)
  gfx.drawLine(64, 74 + bob, 72, 74 + bob)
  gfx.fillTriangle(50, 86 + bob, 86, 86 + bob, 68, 128 + bob)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawLine(58, 96 + bob, 78, 96 + bob)
  -- lantern
  gfx.fillRect(96, 140, 16, 24)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(100, 146 + floor(self.t * 6) % 2, 8, 12)
  gfx.setColor(gfx.kColorBlack)

  UI.panel(134, 24, 258, 190, "paper")
  if self.page == "main" then
    UI.textBlock("\"Sit. The chair is warm, somebody was just in it. What will it be?\"", 146, 34, 236, UI.font, 0)
    self.menu:draw(140, 96, 246)
  elseif self.page == "stories" then
    UI.text("THE KEEPER'S STORIES", 146, 30, "left", UI.bold)
    self.menu:draw(140, 50, 246)
  elseif self.page == "themes" then
    UI.text("LAMPS & WALLPAPER", 146, 30, "left", UI.bold)
    self.menu:draw(140, 50, 246)
    local it = self.menu.items[self.menu.index]
    if it and it.th then UI.textBlock(it.th.desc, 146, 164, 236, UI.font, 0) end
  elseif self.page == "stats" then
    UI.text("MUSEUM LEDGER", 146, 30, "left", UI.bold)
    local y = 52
    for _, l in ipairs(statLines()) do
      UI.text(l[1], 146, y)
      UI.text(l[2], 382, y, "right", UI.bold)
      y = y + 19
    end
  elseif self.page == "settings" then
    UI.text("SETTINGS", 146, 30, "left", UI.bold)
    self.menu:draw(140, 52, 246)
  end
  if self.dialog then self.dialog:draw() end
  if self.msgT > 0 and self.msg then
    UI.popup(40, 180, 320, 30, "ink")
    UI.textW(self.msg, 200, 186, "center")
  end
  if not self.dialog then UI.hints(CuratorScene.HINTS) end
end

CuratorScene.HINTS = { { "DPAD", "CHOOSE" }, { "A", "SELECT" }, { "B", "BACK" } }
