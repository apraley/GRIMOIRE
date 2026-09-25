-- Scene stack plus the two workhorse overlays: Say (message box with an
-- optional portrait) and Choose (JRPG choice list). Overlays draw the scene
-- beneath them first, so the mall keeps living behind dialogue.

Scene = { stack = {} }

function Scene.top() return Scene.stack[#Scene.stack] end
function Scene.push(s)
  Scene.stack[#Scene.stack + 1] = s
  if s.enter then s:enter() end
  Input.clear()
end
function Scene.pop()
  local s = table.remove(Scene.stack)
  if s and s.leave then s:leave() end
  local t = Scene.top()
  if t and t.resume then t:resume() end
  Input.clear()
  return s
end
function Scene.replace(s)
  local old = table.remove(Scene.stack)
  if old and old.leave then old:leave() end
  Scene.push(s)
end
function Scene.reset(s)
  Scene.stack = {}
  Scene.push(s)
end

function Scene.update()
  local s = Scene.top()
  if s and s.update then s:update() end
end

function Scene.draw()
  -- draw from the nearest opaque scene upward
  local start = #Scene.stack
  while start > 1 and Scene.stack[start].overlay do start = start - 1 end
  for i = start, #Scene.stack do
    local s = Scene.stack[i]
    if s.draw then s:draw(i == #Scene.stack) end
  end
end

-- ------------------------------------------------------------------ Say
-- Say(lines or string, { npc = n, mood = "happy", name = "…", after = fn })
function Say(text, opts)
  opts = opts or {}
  local pages = {}
  local list = type(text) == "table" and text or { text }
  local portrait = opts.npc ~= nil
  local width = portrait and 300 or 364
  for _, t in ipairs(list) do
    local lines = Gfx.wrap(t, width)
    for i = 1, #lines, 3 do
      pages[#pages + 1] = { lines[i], lines[i + 1], lines[i + 2] }
    end
  end
  local s = { overlay = true, page = 1, pages = pages, opts = opts, reveal = 0 }
  function s:update()
    self.reveal = self.reveal + 3
    if In.a or In.b then
      local total = 0
      for _, l in ipairs(self.pages[self.page]) do total = total + #l end
      if self.reveal < total then self.reveal = 999
      elseif self.page < #self.pages then self.page = self.page + 1; self.reveal = 0; Sfx.tick()
      else
        Scene.pop()
        if self.opts.after then self.opts.after() end
      end
    end
  end
  function s:draw()
    local y = 150
    Gfx.box(0, y, 400, 90, "dark")
    local x = 16
    if self.opts.npc then
      Sprites.portrait(self.opts.npc, self.opts.mood or Sprites.moodOf(self.opts.npc), 14, y + 20)
      x = 76
    end
    if self.opts.name then
      local nw = Gfx.textW(self.opts.name, true) + 16
      Gfx.box(x - 6, y - 20, nw, 24, "dark")
      Gfx.text(self.opts.name, x + 2, y - 15, { white = true, bold = true })
    end
    local budget = self.reveal
    for i, l in ipairs(self.pages[self.page]) do
      if l then
        local shown = l
        if budget < #l then shown = l:sub(1, math.max(0, budget)) end
        budget = budget - #l
        Gfx.text(shown, x, y + 12 + (i - 1) * 22, { white = true })
      end
    end
    if (Gfx.frame // 10) % 2 == 0 then Gfx.tri(380, y + 72, "down", true) end
  end
  Scene.push(s)
  return s
end

-- ------------------------------------------------------------------ Choose
-- Choose(title, items, callback(index, item), { cancel = fn, x=, w=, prompt = text, npc = n })
-- items: list of strings or { label = "...", disabled = bool }
function Choose(title, items, cb, opts)
  opts = opts or {}
  local s = { overlay = true, sel = 1, top = 1, items = items, title = title, opts = opts }
  s.crank = Input.crankStepper(30)
  local visible = opts.visible or 6
  function s:update()
    local n = #self.items
    local step = self.crank(In.crank)
    if In.ur then step = step - 1 end
    if In.dr then step = step + 1 end
    if step ~= 0 then
      self.sel = ((self.sel - 1 + step) % n) + 1
      Sfx.tick()
    end
    if self.sel < self.top then self.top = self.sel end
    if self.sel >= self.top + visible then self.top = self.sel - visible + 1 end
    if In.a then
      local it = self.items[self.sel]
      if type(it) == "table" and it.disabled then Sfx.bad(); return end
      Scene.pop()
      Sfx.ok()
      cb(self.sel, it)
    elseif In.b then
      Scene.pop()
      if self.opts.cancel then self.opts.cancel() end
    end
  end
  function s:draw()
    local labels = {}
    local maxw = Gfx.textW(self.title or "", true)
    for i, it in ipairs(self.items) do
      local l = type(it) == "table" and it.label or it
      if type(it) == "table" and it.disabled then l = l .. " (x)" end
      labels[i] = l
      maxw = math.max(maxw, Gfx.textW(l))
    end
    local w = self.opts.w or math.min(390, maxw + 48)
    local h = math.min(#labels, visible) * 20 + 16
    local x = self.opts.x or (400 - w - 6)
    local y = self.opts.y or math.max(4, 146 - h)
    if self.opts.prompt then
      Gfx.box(0, 150, 400, 90, "dark")
      local px = 16
      if self.opts.npc then Sprites.portrait(self.opts.npc, self.opts.mood or Sprites.moodOf(self.opts.npc), 14, 170); px = 76 end
      Gfx.para(self.opts.prompt, px, 162, 400 - px - 16, { white = true, maxLines = 3, lh = 22 })
    end
    if self.title then
      local tw = Gfx.textW(self.title, true) + 20
      Gfx.box(x, y - 22, tw, 24, "dark")
      Gfx.text(self.title, x + 10, y - 17, { white = true, bold = true })
    end
    Gfx.menu(labels, self.sel, x, y, w, "light", self.top, visible)
  end
  Scene.push(s)
  return s
end

-- simple yes/no
function Confirm(question, yes, no, opts)
  opts = opts or {}
  opts.prompt = question
  Choose(nil, { "Yes", "No" }, function(i) if i == 1 then yes() elseif no then no() end end,
    { prompt = question, npc = opts.npc, cancel = no, y = 96, w = 90 })
end

-- a timed toast in the explore HUD
Toast = { msg = nil, t = 0 }
function Toast.show(msg, frames) Toast.msg = msg; Toast.t = frames or 90 end
