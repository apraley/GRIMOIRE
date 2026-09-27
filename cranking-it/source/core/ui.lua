-- CRANKING IT :: core/ui
-- Shared UI components. Every machine has its own look, but these pieces
-- (header plate, control hints, gauges, dialog boxes, tutorial coach,
-- toasts, menus) keep the anthology feeling like one cabinet family.

UI = {}

local gfx <const> = playdate.graphics
local floor <const> = math.floor

function UI.init()
  UI.font = gfx.getSystemFont()
  UI.bold = gfx.getSystemFont("bold")
  UI.lineH = UI.font:getHeight()
  UI.boldH = UI.bold:getHeight()
end

------------------------------------------------------------------------
-- text
------------------------------------------------------------------------
-- draws text with the given alignment ("left" default, "center", "right")
function UI.text(str, x, y, align, font)
  font = font or UI.font
  if align == "center" then
    font:drawTextAligned(str, x, y, kTextAlignment.center)
  elseif align == "right" then
    font:drawTextAligned(str, x, y, kTextAlignment.right)
  else
    font:drawText(str, x, y)
  end
end

-- white text regardless of current color (for black panels)
function UI.textW(str, x, y, align, font)
  gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
  UI.text(str, x, y, align, font)
  gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function UI.width(str, font) return (font or UI.font):getTextWidth(str) end

local wrapCache = {}
local wrapCacheCount = 0
-- returns an array of lines (cached per text/width/font)
function UI.wrap(str, width, font)
  font = font or UI.font
  local key = str .. "\0" .. width .. (font == UI.bold and "b" or "n")
  local lines = wrapCache[key]
  if lines then return lines end
  lines = {}
  for para in (str .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      local t = line == "" and word or (line .. " " .. word)
      if font:getTextWidth(t) > width and line ~= "" then
        lines[#lines + 1] = line
        line = word
      else
        line = t
      end
    end
    lines[#lines + 1] = line
  end
  wrapCacheCount = wrapCacheCount + 1
  if wrapCacheCount > 400 then wrapCache = {} wrapCacheCount = 0 end
  wrapCache[key] = lines
  return lines
end

-- draws at most maxLines wrapped lines
function UI.textLines(str, x, y, w, maxLines, font, gap)
  font = font or UI.font
  local lines = UI.wrap(str, w, font)
  local lh = font:getHeight() + (gap or 0)
  for i = 1, math.min(#lines, maxLines) do font:drawText(lines[i], x, y + (i - 1) * lh) end
  return math.min(#lines, maxLines) * lh
end

-- draws wrapped text, returns height used. maxChars reveals a typewriter prefix.
function UI.textBlock(str, x, y, w, font, gap, maxChars, white, align)
  font = font or UI.font
  local lines = UI.wrap(str, w, font)
  local lh = font:getHeight() + (gap or 2)
  local shown = 0
  if white then gfx.setImageDrawMode(gfx.kDrawModeFillWhite) end
  for i = 1, #lines do
    local line = lines[i]
    if maxChars then
      if shown >= maxChars then break end
      if shown + #line > maxChars then line = line:sub(1, maxChars - shown) end
      shown = shown + #lines[i] + 1
    end
    if align == "center" then
      font:drawTextAligned(line, x + w / 2, y + (i - 1) * lh, kTextAlignment.center)
    else
      font:drawText(line, x, y + (i - 1) * lh)
    end
  end
  if white then gfx.setImageDrawMode(gfx.kDrawModeCopy) end
  return #lines * lh
end

------------------------------------------------------------------------
-- panels
------------------------------------------------------------------------
-- style: "paper" (white w/ woodcut frame), "ink" (black w/ white rule),
-- "plain" (white w/ 2px border)
function UI.panel(x, y, w, h, style)
  style = style or "paper"
  if style == "ink" then
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(x, y, w, h)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawRect(x + 3, y + 3, w - 6, h - 6)
    gfx.setColor(gfx.kColorBlack)
  elseif style == "plain" then
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(x, y, w, h)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    gfx.drawRect(x, y, w, h)
    gfx.setLineWidth(1)
  else
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(x, y, w, h)
    Art.frame(x, y, w, h)
  end
end

-- drop shadow + panel (for pop-ups)
function UI.popup(x, y, w, h, style)
  gfx.setPattern(Art.pat.gray50)
  gfx.fillRect(x + 4, y + 4, w, h)
  UI.panel(x, y, w, h, style)
end

------------------------------------------------------------------------
-- machine chrome
------------------------------------------------------------------------
-- black header strip: "No.IX  TITLE" left, right text right. height 18
UI.HEADER_H = 18
function UI.header(number, title, right, inverted)
  gfx.setColor(inverted and gfx.kColorWhite or gfx.kColorBlack)
  gfx.fillRect(0, 0, 400, UI.HEADER_H)
  local draw = inverted and UI.text or UI.textW
  draw(number and ("No." .. U.roman(number) .. "  " .. title) or title, 6, 1, "left", UI.bold)
  if right then draw(right, 394, 1, "right", UI.bold) end
  gfx.setColor(gfx.kColorBlack)
end

-- small button glyph: rounded box with label. returns width
function UI.glyph(label, x, y, inverted)
  local w
  if label == "CRANK" then
    w = 16
    gfx.setColor(inverted and gfx.kColorWhite or gfx.kColorBlack)
    gfx.drawCircleAtPoint(x + 7, y + 8, 6)
    gfx.drawLine(x + 7, y + 8, x + 12, y + 3)
    gfx.fillCircleAtPoint(x + 12, y + 3, 2)
    return w
  elseif label == "DPAD" then
    w = 15
    gfx.setColor(inverted and gfx.kColorWhite or gfx.kColorBlack)
    gfx.fillRect(x + 5, y + 2, 5, 13)
    gfx.fillRect(x, y + 6, 15, 5)
    return w
  end
  w = UI.bold:getTextWidth(label) + 8
  gfx.setColor(inverted and gfx.kColorWhite or gfx.kColorBlack)
  gfx.fillRoundRect(x, y + 1, w, 15, 4)
  if inverted then UI.text(label, x + 4, y, "left", UI.bold) else UI.textW(label, x + 4, y, "left", UI.bold) end
  gfx.setColor(gfx.kColorBlack)
  return w
end

-- bottom control legend. list = { {"A","REEL"}, {"CRANK","WIND"}, ... }
UI.HINTS_H = 18
function UI.hints(list, inverted, y)
  y = y or (240 - UI.HINTS_H)
  gfx.setColor(inverted and gfx.kColorBlack or gfx.kColorWhite)
  gfx.fillRect(0, y, 400, UI.HINTS_H)
  gfx.setColor(inverted and gfx.kColorWhite or gfx.kColorBlack)
  gfx.drawLine(0, y, 400, y)
  local x = 6
  for i = 1, #list do
    local item = list[i]
    x = x + UI.glyph(item[1], x, y + 1, inverted) + 3
    if inverted then UI.textW(item[2], x, y + 1) else UI.text(item[2], x, y + 1) end
    x = x + UI.width(item[2]) + 12
  end
  gfx.setColor(gfx.kColorBlack)
end

------------------------------------------------------------------------
-- gauges
------------------------------------------------------------------------
-- horizontal bar. v 0..1. opts: lo/hi danger marks (0..1), label
function UI.gauge(x, y, w, h, v, lo, hi, label, pat)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x, y, w, h)
  gfx.setColor(gfx.kColorBlack)
  if lo then
    gfx.setPattern(Art.pat.hatch)
    gfx.fillRect(x, y, floor(w * lo), h)
  end
  if hi then
    gfx.setPattern(Art.pat.hatch)
    gfx.fillRect(x + floor(w * hi), y, w - floor(w * hi), h)
  end
  if pat then gfx.setPattern(Art.pat[pat]) else gfx.setColor(gfx.kColorBlack) end
  gfx.fillRect(x + 2, y + 2, floor((w - 4) * U.clamp(v, 0, 1)), h - 4)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(x, y, w, h)
  if label then UI.text(label, x, y - UI.lineH, "left") end
end

function UI.vgauge(x, y, w, h, v, lo, hi, pat)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x, y, w, h)
  if lo then gfx.setPattern(Art.pat.hatch) gfx.fillRect(x, y + h - floor(h * lo), w, floor(h * lo)) end
  if hi then gfx.setPattern(Art.pat.hatch) gfx.fillRect(x, y, w, h - floor(h * hi)) end
  if pat then gfx.setPattern(Art.pat[pat]) else gfx.setColor(gfx.kColorBlack) end
  local fh = floor((h - 4) * U.clamp(v, 0, 1))
  gfx.fillRect(x + 2, y + h - 2 - fh, w - 4, fh)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(x, y, w, h)
end

-- analog needle meter. v 0..1 maps to angles a0..a1 (degrees, 0 = up)
function UI.meter(cx, cy, r, v, a0, a1, ticks, redFrom)
  a0, a1 = a0 or -60, a1 or 60
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(cx, cy, r)
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(2)
  gfx.drawCircleAtPoint(cx, cy, r)
  gfx.setLineWidth(1)
  ticks = ticks or 10
  for i = 0, ticks do
    local a = math.rad(a0 + (a1 - a0) * i / ticks)
    local s, c = math.sin(a), math.cos(a)
    local inner = (i % 5 == 0) and r - 8 or r - 5
    if redFrom and i / ticks >= redFrom then
      gfx.setLineWidth(3)
    end
    gfx.drawLine(cx + s * inner, cy - c * inner, cx + s * (r - 2), cy - c * (r - 2))
    gfx.setLineWidth(1)
  end
  local a = math.rad(a0 + (a1 - a0) * U.clamp(v, -0.05, 1.05))
  gfx.setLineWidth(2)
  gfx.drawLine(cx, cy, cx + math.sin(a) * (r - 4), cy - math.cos(a) * (r - 4))
  gfx.setLineWidth(1)
  gfx.fillCircleAtPoint(cx, cy, 3)
end

------------------------------------------------------------------------
-- crank prompt / docked overlay
------------------------------------------------------------------------
function UI.crankPrompt(x, y, t, dir, r)
  r = r or 10
  local ang = (t * 360 * (dir or 1)) % 360
  Art.crankGlyph(x, y, r, ang)
  -- arrow arc
  gfx.setColor(gfx.kColorBlack)
  local d = dir or 1
  local ax = x + (r + 6) * (d > 0 and 1 or -1)
  gfx.fillTriangle(ax - 3, y - 2, ax + 3, y - 2, ax, y + 3)
end

function UI.dockedOverlay(t)
  gfx.setPattern(Art.pat.gray50)
  gfx.fillRect(0, 0, 400, 240)
  UI.popup(100, 70, 200, 100, "paper")
  UI.text("UNDOCK THE CRANK", 200, 88, "center", UI.bold)
  Art.crankGlyph(200, 135, 16, (t * 180) % 360)
  UI.text("this machine needs it", 200, 152, "center")
end

------------------------------------------------------------------------
-- toasts (achievements, gears)
------------------------------------------------------------------------
local toasts = {}
function UI.toast(title, sub, icon)
  toasts[#toasts + 1] = { title = title, sub = sub, icon = icon or "gear", t = 0 }
end

function UI.updateToasts(dt)
  local tt = toasts[1]
  if not tt then return end
  tt.t = tt.t + dt
  if tt.t > 3.2 then table.remove(toasts, 1) end
end

function UI.drawToasts()
  local tt = toasts[1]
  if not tt then return end
  local slide = 1
  if tt.t < 0.25 then slide = tt.t / 0.25 elseif tt.t > 2.9 then slide = (3.2 - tt.t) / 0.3 end
  slide = U.smoothstep(slide)
  local w, h = 250, 38
  local x = 200 - w / 2
  local y = floor(-h + (h + 4) * slide)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRoundRect(x, y, w, h, 6)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawRoundRect(x + 2, y + 2, w - 4, h - 4, 5)
  gfx.fillCircleAtPoint(x + 20, y + h / 2, 13)
  gfx.setColor(gfx.kColorBlack)
  if tt.icon == "star" then
    UI.text("*", x + 20, y + 10, "center", UI.bold)
  else
    Art.gear(x + 20, y + h / 2, 10, 8, tt.t * 120, true)
  end
  UI.textW(tt.title, x + 40, y + 3, "left", UI.bold)
  if tt.sub then UI.textW(tt.sub, x + 40, y + 19, "left") end
end

function UI.toastsBusy() return #toasts > 0 end

------------------------------------------------------------------------
-- Dialog: SNES-style typewriter box with speaker name tab
------------------------------------------------------------------------
local Dialog = U.class()
UI.Dialog = Dialog

-- pages: array of strings. opts: speaker, y, h, cps, sound
function Dialog:init(pages, opts)
  opts = opts or {}
  self.pages = pages
  self.page = 1
  self.chars = 0
  self.cps = opts.cps or 45
  self.speaker = opts.speaker
  self.y = opts.y or 150
  self.h = opts.h or 84
  self.done = false
  self.t = 0
  self.onDone = opts.onDone
end

function Dialog:update(dt)
  if self.done then return end
  self.t = self.t + dt
  local text = self.pages[self.page]
  if self.chars < #text then
    local before = floor(self.chars)
    self.chars = math.min(#text, self.chars + self.cps * dt)
    if floor(self.chars) ~= before and floor(self.chars) % 3 == 0 then Audio.sfx.type() end
  end
end

-- returns true when the whole dialog is finished
function Dialog:advance()
  if self.done then return true end
  local text = self.pages[self.page]
  if self.chars < #text then
    self.chars = #text
    return false
  end
  if self.page < #self.pages then
    self.page = self.page + 1
    self.chars = 0
    Audio.sfx.menuMove()
    return false
  end
  self.done = true
  if self.onDone then self.onDone() end
  return true
end

function Dialog:draw()
  if self.done then return end
  local x, y, w, h = 8, self.y, 384, self.h
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRoundRect(x, y, w, h, 6)
  gfx.setColor(gfx.kColorWhite)
  gfx.setLineWidth(2)
  gfx.drawRoundRect(x + 3, y + 3, w - 6, h - 6, 5)
  gfx.setLineWidth(1)
  if self.speaker then
    local sw = UI.width(self.speaker, UI.bold) + 16
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRoundRect(x + 12, y - 14, sw, 20, 4)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawRoundRect(x + 14, y - 12, sw - 4, 16, 3)
    UI.textW(self.speaker, x + 20, y - 12, "left", UI.bold)
  end
  UI.textBlock(self.pages[self.page], x + 14, y + 12, w - 28, UI.font, 2, floor(self.chars), true)
  local text = self.pages[self.page]
  if self.chars >= #text and (self.t * 2) % 2 < 1.3 then
    gfx.setColor(gfx.kColorWhite)
    local ax, ay = x + w - 18, y + h - 14
    gfx.fillTriangle(ax, ay, ax + 8, ay, ax + 4, ay + 5)
  end
  gfx.setColor(gfx.kColorBlack)
end

------------------------------------------------------------------------
-- Menu: vertical list with cursor. items = { {label=, sub=, disabled=} }
------------------------------------------------------------------------
local Menu = U.class()
UI.Menu = Menu

function Menu:init(items, opts)
  opts = opts or {}
  self.items = items
  self.index = opts.index or 1
  self.rowH = opts.rowH or 22
  self.visible = opts.visible or 6
  self.scroll = 0
  self.anim = 0
end

function Menu:setItems(items)
  self.items = items
  self.index = U.clamp(self.index, 1, math.max(1, #items))
end

-- returns selected item on A, "back" on B, nil otherwise
function Menu:update(dt)
  self.anim = self.anim + dt
  local n = #self.items
  if n == 0 then return nil end
  if Input.repeated(Input.DOWN) then self.index = self.index % n + 1 Audio.sfx.menuMove() end
  if Input.repeated(Input.UP) then self.index = (self.index - 2) % n + 1 Audio.sfx.menuMove() end
  if self.index > self.scroll + self.visible then self.scroll = self.index - self.visible end
  if self.index <= self.scroll then self.scroll = self.index - 1 end
  if Input.justPressed(Input.A) then
    local it = self.items[self.index]
    if it.disabled then Audio.sfx.denied() else Audio.sfx.menuSelect() end
    return it
  end
  if Input.justPressed(Input.B) then return "back" end
  return nil
end

-- crank scrolling for menus (one step per 30 degrees)
function Menu:cranked(change)
  self.crankAcc = (self.crankAcc or 0) + change
  local n = #self.items
  while self.crankAcc > 30 do self.crankAcc = self.crankAcc - 30 self.index = math.min(n, self.index + 1) Audio.sfx.menuMove() end
  while self.crankAcc < -30 do self.crankAcc = self.crankAcc + 30 self.index = math.max(1, self.index - 1) Audio.sfx.menuMove() end
end

function Menu:draw(x, y, w)
  local n = #self.items
  for row = 1, math.min(self.visible, n) do
    local i = row + self.scroll
    local it = self.items[i]
    if not it then break end
    local ry = y + (row - 1) * self.rowH
    local sel = i == self.index
    if sel then
      gfx.setColor(gfx.kColorBlack)
      gfx.fillRect(x, ry, w, self.rowH - 2)
      local bob = floor((self.anim * 4) % 2)
      gfx.setColor(gfx.kColorWhite)
      gfx.fillTriangle(x + 4 + bob, ry + 5, x + 4 + bob, ry + self.rowH - 7, x + 9 + bob, ry + (self.rowH - 2) / 2)
    end
    local draw = sel and UI.textW or UI.text
    local label = it.label
    draw(label, x + 14, ry + (self.rowH - 2 - UI.lineH) / 2, "left", sel and UI.bold or UI.font)
    if it.disabled and not sel then
      gfx.setColor(gfx.kColorBlack)
      gfx.setPattern(Art.pat.gray50)
      gfx.drawLine(x + 14, ry + self.rowH / 2, x + 14 + UI.width(label), ry + self.rowH / 2)
    end
    if it.right then draw(it.right, x + w - 6, ry + (self.rowH - 2 - UI.lineH) / 2, "right") end
  end
  gfx.setColor(gfx.kColorBlack)
  if self.scroll > 0 then gfx.fillTriangle(x + w - 12, y - 2, x + w - 4, y - 2, x + w - 8, y - 7) end
  if self.scroll + self.visible < n then
    local by = y + self.visible * self.rowH
    gfx.fillTriangle(x + w - 12, by, x + w - 4, by, x + w - 8, by + 5)
  end
end

------------------------------------------------------------------------
-- Coach: tutorial steps with completion checks
--   steps = { {text="Turn the crank", check=function(dt) return ... end}, ... }
------------------------------------------------------------------------
local Coach = U.class()
UI.Coach = Coach

function Coach:init(steps, opts)
  opts = opts or {}
  self.steps = steps
  self.i = 1
  self.state = "active" -- active | passed | done
  self.t = 0
  self.y = opts.y or 22
  self.h = opts.h or 46
  self.x = opts.x or 8
  self.w = opts.w or 384
  self.inverted = opts.inverted
  self.anchor = opts.anchor -- "bottom": grow upward from y + h
  self.done = false
  self.holdT = 0
end

function Coach:current() return self.steps[self.i] end

function Coach:update(dt)
  if self.done then return true end
  self.t = self.t + dt
  local s = self.steps[self.i]
  if self.state == "active" then
    if s.enter and not s.entered then s.entered = true s.enter() end
    local ok = s.check == nil and self.t > (s.time or 3) or (s.check and s.check(dt))
    if ok then
      self.holdT = self.holdT + dt
      if self.holdT >= (s.hold or 0) then
        self.state = "passed"
        self.t = 0
        Audio.sfx.coin()
      end
    else
      self.holdT = 0
    end
  elseif self.state == "passed" then
    if self.t > 0.9 then
      if self.i >= #self.steps then
        self.done = true
        self.state = "done"
        return true
      end
      self.i = self.i + 1
      self.state = "active"
      self.t = 0
      self.holdT = 0
    end
  end
  return false
end

function Coach:skip()
  if self.state == "active" then self.state = "passed" self.t = 0 end
end

function Coach:draw()
  if self.done then return end
  local s = self.steps[self.i]
  local x, y, w, h = self.x, self.y, self.w, self.h
  local ink = not self.inverted
  local label = U.cached("coach_step", "LESSON %d/", self.i) .. #self.steps
  local lx0 = x + 10 + UI.width(label, UI.bold) + 8
  local lines = UI.wrap(s.text, w - (lx0 - x) - 30, UI.font)
  local need = 10 + #lines * UI.lineH
  if need > h then
    if self.anchor == "bottom" then y = y + h - need end
    h = need
  end
  gfx.setColor(ink and gfx.kColorBlack or gfx.kColorWhite)
  gfx.fillRoundRect(x, y, w, h, 5)
  gfx.setColor(ink and gfx.kColorWhite or gfx.kColorBlack)
  gfx.drawRoundRect(x + 2, y + 2, w - 4, h - 4, 4)
  local tx = x + 10
  if ink then UI.textW(label, tx, y + 5, "left", UI.bold) else UI.text(label, tx, y + 5, "left", UI.bold) end
  local lx = tx + UI.width(label, UI.bold) + 8
  UI.textBlock(s.text, lx, y + 5, w - (lx - x) - 30, UI.font, 0, nil, ink)
  -- check box
  local bx, by = x + w - 24, y + 8
  gfx.setColor(ink and gfx.kColorWhite or gfx.kColorBlack)
  gfx.drawRect(bx, by, 14, 14)
  if self.state == "passed" then
    gfx.setLineWidth(3)
    gfx.drawLine(bx + 2, by + 7, bx + 6, by + 12)
    gfx.drawLine(bx + 6, by + 12, bx + 14, by - 2)
    gfx.setLineWidth(1)
  elseif s.hold and self.holdT > 0 then
    local f = U.clamp(self.holdT / s.hold, 0, 1)
    gfx.fillRect(bx + 2, by + 12 - floor(10 * f), 10, floor(10 * f))
  end
  gfx.setColor(gfx.kColorBlack)
end

------------------------------------------------------------------------
-- rubber stamp (results, events): renders text once into a cached image
------------------------------------------------------------------------
function UI.stampImage(text)
  return Art.cached("stamp:" .. text, UI.width(text, UI.bold) + 24, UI.boldH + 14, function(w, h)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(3)
    gfx.drawRoundRect(2, 2, w - 4, h - 4, 4)
    gfx.setLineWidth(1)
    gfx.drawRoundRect(5, 5, w - 10, h - 10, 3)
    UI.text(text, w / 2, 7, "center", UI.bold)
  end)
end

-- t: seconds since stamp started
function UI.stamp(text, x, y, t)
  local img = UI.stampImage(text)
  local s = t < 0.15 and (2.2 - 1.2 * (t / 0.15)) or 1
  local w, h = img:getSize()
  if s > 1.01 then
    img:drawScaled(floor(x - w * s / 2), floor(y - h * s / 2), s)
  else
    img:drawRotated(x, y, -6)
  end
end

------------------------------------------------------------------------
-- big numeral with a woodcut plate background
------------------------------------------------------------------------
function UI.counter(label, value, x, y, w)
  w = w or 90
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x, y, w, 34)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(x, y, w, 34)
  UI.text(label, x + 4, y + 1)
  UI.text(value, x + w - 5, y + 16, "right", UI.bold)
end
