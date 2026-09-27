-- CRANKING IT :: scenes/lobby
-- A machine's placard: description, modes, records, challenges, and the
-- dust-sheet unlock for covered cabinets. Also hosts the Daily Machine.

LobbyScene = {}

local gfx <const> = playdate.graphics
local floor <const> = math.floor

local MODE_NAMES <const> = { tutorial = "TUTORIAL", standard = "STANDARD", endless = "ENDLESS" }
local MEDAL_NAMES <const> = { "BRASS", "SILVER", "GOLD" }
LobbyScene.MEDAL_NAMES = MEDAL_NAMES

local bigIcons = {}
local function bigIcon(def)
  if bigIcons[def.id] then return bigIcons[def.id] end
  local small = HubScene.iconFor(def)
  local img = gfx.image.new(96, 96, gfx.kColorClear)
  gfx.pushContext(img)
  small:drawScaled(0, 0, 2)
  gfx.popContext()
  bigIcons[def.id] = img
  return img
end

function LobbyScene:enter(params)
  self.def = Machines.get(params.id)
  self.daily = params.daily
  self.t = 0
  self.page = "main"
  self.msg = nil
  self.msgT = 0
  self:buildMain()
end

function LobbyScene:buildMain()
  local def = self.def
  local rec = Save.machine(def.id)
  local items = {}
  if self.daily then
    local played = Save.data.daily.played[self.daily.key]
    items[#items + 1] = { label = "PLAY TODAY'S MACHINE", action = "daily", right = played and ("best " .. played) or nil }
  elseif not Machines.isUnlocked(def) then
    local can = Save.data.gears >= def.unlockCost
    items[#items + 1] = { label = "REMOVE DUST SHEET", right = def.unlockCost .. " gears", action = "unlock", disabled = not can }
  else
    for _, mode in ipairs(def.modes) do
      local right
      if mode == "tutorial" then
        right = rec.tutorialDone and "done" or "+1 gear"
      else
        local b = rec.best[mode]
        right = b and ("best " .. U.commas(b)) or "-"
      end
      items[#items + 1] = { label = MODE_NAMES[mode], action = "play", mode = mode, right = right }
    end
    if #def.challenges > 0 then
      local done = 0
      for _, c in ipairs(def.challenges) do if rec.challenges[c.id] and rec.challenges[c.id].done then done = done + 1 end end
      items[#items + 1] = { label = "CHALLENGES", action = "challenges", right = done .. "/" .. #def.challenges }
    end
    local got, all = Achievements.countFor(def)
    items[#items + 1] = { label = "RECORDS", action = "records", right = got .. "/" .. all .. " ach." }
  end
  items[#items + 1] = { label = "BACK TO GALLERY", action = "back" }
  -- default to STANDARD once the tutorial is done
  local idx = 1
  if not self.daily and rec.tutorialDone and #items > 1 and items[2].mode then idx = 2 end
  self.menu = UI.Menu.new(items, { rowH = 18, visible = 5, index = idx })
end

function LobbyScene:buildRecords()
  local def = self.def
  local rec = Save.machine(def.id)
  local items = {}
  items[#items + 1] = { label = "Plays", right = tostring(rec.plays) }
  for _, mode in ipairs(def.modes) do
    if mode ~= "tutorial" then
      local m = rec.medals[mode] or 0
      items[#items + 1] = { label = MODE_NAMES[mode] .. " best", right = U.commas(rec.best[mode] or 0) .. (m > 0 and ("  " .. MEDAL_NAMES[m]) or "") }
      local md = def.medals[mode]
      if md then items[#items + 1] = { label = "  medals at", right = md[1] .. " / " .. md[2] .. " / " .. md[3] } end
    end
  end
  for _, r in ipairs(def.records) do
    local v = rec.stats[r[1]] or 0
    local s = r[3] and r[3](v) or U.commas(v)
    items[#items + 1] = { label = r[2], right = s }
  end
  for _, a in ipairs(def.achievements) do
    local has = rec.achievements[a.id]
    items[#items + 1] = { label = (has and "* " or "o ") .. a.name, right = has and "" or "", desc = a.desc, ach = true }
  end
  self.menu = UI.Menu.new(items, { rowH = 18, visible = 9 })
end

function LobbyScene:eligibleForChallenges()
  local rec = Save.machine(self.def.id)
  return (rec.medals.standard or 0) >= 1
end

function LobbyScene:buildChallenges()
  local def = self.def
  local rec = Save.machine(def.id)
  local items = {}
  for _, c in ipairs(def.challenges) do
    local st = rec.challenges[c.id]
    local right
    if st and st.done then right = "* " .. U.commas(st.best or 0)
    elseif st and st.owned then right = "best " .. U.commas(st.best or 0)
    elseif not self:eligibleForChallenges() then right = "locked"
    else right = "permit " .. (c.cost or 2) end
    items[#items + 1] = { label = c.name, right = right, c = c }
  end
  self.menu = UI.Menu.new(items, { rowH = 20, visible = 5 })
end

function LobbyScene:say(msg)
  self.msg = msg
  self.msgT = 2.2
end

function LobbyScene:play(mode)
  local p = { id = self.def.id, mode = mode, difficulty = 1 }
  Scene.go(PlayScene, p, "iris", 0.8)
end

function LobbyScene:update(dt)
  self.t = self.t + dt
  if self.msgT > 0 then self.msgT = self.msgT - dt end
  local sel = self.menu:update(dt)
  if not sel then return end
  if self.page ~= "main" then
    if sel == "back" then self.page = "main" self:buildMain() Audio.sfx.back() return end
    if self.page == "challenges" and sel.c then self:challengeSelect(sel.c) end
    return
  end
  if sel == "back" or sel.action == "back" then
    Audio.sfx.back()
    Scene.go(HubScene, { id = self.daily and nil or self.def.id, station = self.daily and "daily" or nil }, "shutter")
    return
  end
  if sel.disabled then
    if sel.action == "unlock" then self:say("Not enough gears. Master other machines.") end
    return
  end
  if sel.action == "unlock" then
    if Save.spendGears(self.def.unlockCost) then
      Save.machine(self.def.id).unlocked = true
      Save.flush()
      Audio.sfx.clank(0.7)
      Audio.sfx.gear(0.2)
      Scene.shake(4)
      Achievements.checkMeta()
      self:say("The dust sheet slides off.")
      self:buildMain()
    end
  elseif sel.action == "play" then
    self:play(sel.mode)
  elseif sel.action == "daily" then
    Scene.go(PlayScene, Challenge.dailyParams(self.daily), "iris", 0.8)
  elseif sel.action == "records" then
    self.page = "records"
    self:buildRecords()
  elseif sel.action == "challenges" then
    self.page = "challenges"
    self:buildChallenges()
  end
end

function LobbyScene:challengeSelect(c)
  local rec = Save.machine(self.def.id)
  local st = rec.challenges[c.id]
  if st and st.owned then
    Scene.go(PlayScene, Challenge.challengeParams(self.def, c), "iris", 0.8)
    return
  end
  if not self:eligibleForChallenges() then
    Audio.sfx.denied()
    self:say("Earn a BRASS medal in STANDARD first.")
    return
  end
  if Save.spendGears(c.cost or 2) then
    rec.challenges[c.id] = { owned = true, best = 0, done = false }
    Save.flush()
    Audio.sfx.coin()
    self:say("Permit stamped. Good luck.")
    self:buildChallenges()
  else
    Audio.sfx.denied()
    self:say("A permit costs " .. (c.cost or 2) .. " gears.")
  end
end

function LobbyScene:cranked(change) self.menu:cranked(change) end

------------------------------------------------------------------------
function LobbyScene:draw()
  local def = self.def
  gfx.clear(gfx.kColorWhite)
  gfx.setPattern(Art.pat[Themes.wallPattern()])
  gfx.fillRect(0, 0, 400, 240)
  UI.header(def.number, def.title, self.daily and ("DAILY " .. self.daily.key:sub(5, 6) .. "/" .. self.daily.key:sub(7, 8)) or nil)

  -- icon plate
  UI.panel(8, 24, 116, 116, "paper")
  bigIcon(def):draw(18, 34)
  if not Machines.isUnlocked(def) and not self.daily then
    gfx.setPattern(Art.pat.gray50)
    gfx.fillRect(14, 30, 104, 104)
    gfx.setColor(gfx.kColorBlack)
  end
  -- medals row
  local rec = Save.machine(def.id)
  UI.panel(8, 144, 116, 68, "plain")
  local y = 148
  for _, mode in ipairs(def.modes) do
    if mode ~= "tutorial" then
      UI.text(mode == "standard" and "STD" or "END", 14, y)
      local m = rec.medals[mode] or 0
      for i = 1, 3 do
        local mx = 60 + (i - 1) * 20
        if i <= m then Art.gear(mx, y + 8, 7, 7, 0, true) else gfx.drawCircleAtPoint(mx, y + 8, 6) end
      end
      y = y + 20
    end
  end
  if rec.tutorialDone then UI.text("lesson done", 14, 192) end

  -- right panel
  UI.panel(130, 24, 262, 190, "paper")
  if self.page == "main" then
    UI.text(def.tagline or "", 140, 32, "left", UI.bold)
    if self.daily then
      local d = self.daily
      local lines = "Everyone gets this machine today. Difficulty " .. d.difficulty .. ". Goal: " .. U.commas(d.goal) .. " " .. def.scoreLabel:lower() .. "."
      local mods = Challenge.modNames(d.mods)
      if mods ~= "" then lines = lines .. " Modifier: " .. mods .. "." end
      lines = lines .. " Streak: " .. Save.data.daily.streak .. "."
      UI.textLines(lines, 140, 50, 244, 4)
    else
      UI.textLines(def.description or "", 140, 50, 244, 4)
    end
    gfx.drawLine(138, 118, 384, 118)
    self.menu:draw(136, 122, 250)
  elseif self.page == "records" then
    UI.text("RECORDS", 140, 30, "left", UI.bold)
    self.menu:draw(136, 50, 250)
    local it = self.menu.items[self.menu.index]
    if it and it.desc then
      UI.panel(130, 196, 262, 22, "ink")
      UI.textW(it.desc, 138, 198)
    end
  elseif self.page == "challenges" then
    UI.text("CHALLENGES", 140, 30, "left", UI.bold)
    self.menu:draw(136, 50, 250)
    local it = self.menu.items[self.menu.index]
    if it and it.c then
      local c = it.c
      local txt = c.desc .. "  Goal " .. U.commas(c.goal or 0) .. ". Reward " .. (c.reward or 2) .. " gears."
      local m = Challenge.modNames(c.mods)
      if m ~= "" then txt = txt .. " " .. m .. "." end
      UI.textBlock(txt, 140, 156, 244, UI.font, 0)
    end
  end
  if self.msgT > 0 and self.msg then
    UI.popup(60, 100, 280, 36, "ink")
    UI.textW(self.msg, 200, 110, "center")
  end
  UI.hints(LobbyScene.HINTS)
end

LobbyScene.HINTS = { { "DPAD", "CHOOSE" }, { "A", "SELECT" }, { "B", "BACK" } }
