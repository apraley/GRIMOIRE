-- Rendering helpers shared by every scene: SNES-style double-border boxes,
-- 1-bit "neon" dither patterns, safe text drawing, small icons.

Gfx = {}
local gfx = playdate.graphics

Gfx.W, Gfx.H = 400, 240

-- 8x8 patterns (rows as bytes). Used for shading, neon, floors.
Gfx.P = {
  black = { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
  white = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF },
  gray = { 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55 },
  light = { 0xFF, 0xDD, 0xFF, 0x77, 0xFF, 0xDD, 0xFF, 0x77 },
  lighter = { 0xFF, 0xFF, 0xFF, 0xF7, 0xFF, 0xFF, 0xFF, 0x7F },
  dark = { 0x00, 0x22, 0x00, 0x88, 0x00, 0x22, 0x00, 0x88 },
  darker = { 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x80 },
  hstripe = { 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00 },
  vstripe = { 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA },
  diag = { 0x77, 0xBB, 0xDD, 0xEE, 0x77, 0xBB, 0xDD, 0xEE },
  diag2 = { 0xEE, 0xDD, 0xBB, 0x77, 0xEE, 0xDD, 0xBB, 0x77 },
  check = { 0xF0, 0xF0, 0xF0, 0xF0, 0x0F, 0x0F, 0x0F, 0x0F },
  plaid = { 0x99, 0x99, 0xFF, 0x99, 0x99, 0x99, 0xFF, 0x99 },
  dots = { 0xFF, 0xDD, 0xFF, 0xFF, 0xFF, 0x77, 0xFF, 0xFF },
  brick = { 0x00, 0xEF, 0xEF, 0xEF, 0x00, 0xFE, 0xFE, 0xFE },
  tile = { 0x80, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF },
  carpet = { 0xDF, 0xFF, 0x7F, 0xFF, 0xFD, 0xFF, 0xF7, 0xFF },
  wave = { 0xFF, 0xE7, 0xDB, 0x3C, 0xFF, 0xE7, 0xDB, 0x3C },
  grate = { 0x00, 0x7E, 0x7E, 0x7E, 0x00, 0xE7, 0xE7, 0xE7 },
  asphalt = { 0xBF, 0xFF, 0xEF, 0xFB, 0xFF, 0x7F, 0xFD, 0xFF },
}
-- animated neon: cycling patterns give a buzzing, flickering glow
Gfx.NEON = {
  { 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55 },
  { 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA },
  { 0x88, 0x22, 0x88, 0x22, 0x88, 0x22, 0x88, 0x22 },
  { 0xCC, 0x33, 0xCC, 0x33, 0xCC, 0x33, 0xCC, 0x33 },
}

Gfx.frame = 0

function Gfx.color(c) gfx.setColor(c == "white" and gfx.kColorWhite or gfx.kColorBlack) end
function Gfx.pat(name) gfx.setPattern(Gfx.P[name] or name) end

function Gfx.clear(c)
  gfx.clear(c == "black" and gfx.kColorBlack or gfx.kColorWhite)
end

function Gfx.fill(x, y, w, h, c)
  if c == nil or c == "black" then gfx.setColor(gfx.kColorBlack)
  elseif c == "white" then gfx.setColor(gfx.kColorWhite)
  else gfx.setPattern(Gfx.P[c] or c) end
  gfx.fillRect(x, y, w, h)
  gfx.setColor(gfx.kColorBlack)
end

function Gfx.rect(x, y, w, h, c)
  gfx.setColor(c == "white" and gfx.kColorWhite or gfx.kColorBlack)
  gfx.drawRect(x, y, w, h)
  gfx.setColor(gfx.kColorBlack)
end

function Gfx.line(x1, y1, x2, y2, c)
  gfx.setColor(c == "white" and gfx.kColorWhite or gfx.kColorBlack)
  gfx.drawLine(x1, y1, x2, y2)
  gfx.setColor(gfx.kColorBlack)
end

-- Playdate text treats * and _ as bold/italic markers; double them to draw
-- literally.
local function esc(s)
  s = tostring(s)
  return (s:gsub("%*", "**"):gsub("_", "__"))
end
Gfx.esc = esc

Gfx.font = nil
Gfx.bold = nil
function Gfx.init()
  Gfx.font = gfx.getSystemFont()
  Gfx.bold = gfx.getSystemFont(gfx.font.kVariantBold)
  gfx.setFont(Gfx.font)
end

function Gfx.lineH() return 18 end
function Gfx.textW(s, bold)
  local f = bold and Gfx.bold or Gfx.font
  if not f then return #tostring(s) * 7 end
  return f:getTextWidth(esc(s))
end

-- draw text; opts: white=true, bold=true, align="center"/"right"
function Gfx.text(s, x, y, opts)
  opts = opts or {}
  local f = opts.bold and Gfx.bold or Gfx.font
  if f then gfx.setFont(f) end
  if opts.white then gfx.setImageDrawMode(gfx.kDrawModeFillWhite) end
  local str = esc(s)
  if opts.align == "center" then
    gfx.drawTextAligned(str, x, y, kTextAlignment.center)
  elseif opts.align == "right" then
    gfx.drawTextAligned(str, x, y, kTextAlignment.right)
  else
    gfx.drawText(str, x, y)
  end
  if opts.white then gfx.setImageDrawMode(gfx.kDrawModeCopy) end
  if Gfx.font then gfx.setFont(Gfx.font) end
end

-- wrap to pixel width using real font metrics; returns list of lines
function Gfx.wrap(s, width, bold)
  local lines = {}
  for para in (tostring(s) .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      local test = (#line > 0) and (line .. " " .. word) or word
      if Gfx.textW(test, bold) > width and #line > 0 then
        lines[#lines + 1] = line
        line = word
      else
        line = test
      end
    end
    lines[#lines + 1] = line
  end
  return lines
end

-- wrapped paragraph; returns height used
function Gfx.para(s, x, y, width, opts)
  local lines = Gfx.wrap(s, width, opts and opts.bold)
  local lh = (opts and opts.lh) or Gfx.lineH()
  local maxLines = opts and opts.maxLines
  for i, l in ipairs(lines) do
    if maxLines and i > maxLines then break end
    Gfx.text(l, x, y + (i - 1) * lh, opts)
  end
  return #lines * lh
end

-- JRPG double-border window. style "dark" (black fill, white borders) or
-- "light" (white fill, black borders).
function Gfx.box(x, y, w, h, style)
  style = style or "dark"
  if style == "dark" then
    Gfx.fill(x, y, w, h, "black")
    gfx.setColor(gfx.kColorWhite)
    gfx.drawRoundRect(x + 2, y + 2, w - 4, h - 4, 3)
    gfx.drawRect(x + 5, y + 5, w - 10, h - 10)
    gfx.setColor(gfx.kColorBlack)
  else
    Gfx.fill(x, y, w, h, "white")
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRoundRect(x + 1, y + 1, w - 2, h - 2, 3)
    gfx.drawRect(x + 4, y + 4, w - 8, h - 8)
  end
end

-- text inside a dark box is white; helper for that
function Gfx.btext(s, x, y, opts)
  opts = opts or {}
  opts.white = true
  Gfx.text(s, x, y, opts)
end

-- neon rectangle: animated dither, flickers now and then
function Gfx.neon(x, y, w, h, seed)
  local f = Gfx.frame
  local flick = ((f + (seed or 0) * 7) % 97) < 3
  if flick then Gfx.fill(x, y, w, h, "darker") return end
  gfx.setPattern(Gfx.NEON[1 + ((f // 4 + (seed or 0)) % #Gfx.NEON)])
  gfx.fillRect(x, y, w, h)
  gfx.setColor(gfx.kColorBlack)
end

-- menu list inside a box. items: list of strings; sel: index
function Gfx.menu(items, sel, x, y, w, style, top, visible)
  top = top or 1
  visible = visible or #items
  local lh = 20
  local h = math.min(#items, visible) * lh + 16
  Gfx.box(x, y, w, h, style)
  local dark = (style or "dark") == "dark"
  for i = top, math.min(#items, top + visible - 1) do
    local yy = y + 8 + (i - top) * lh
    local label = items[i]
    if i == sel then
      if dark then Gfx.fill(x + 8, yy, w - 16, lh - 2, "white") else Gfx.fill(x + 8, yy, w - 16, lh - 2, "black") end
      Gfx.text(label, x + 20, yy + 1, { white = not dark })
    else
      Gfx.text(label, x + 20, yy + 1, { white = dark })
    end
  end
  if top > 1 then Gfx.tri(x + w - 14, y + 8, "up", dark) end
  if top + visible - 1 < #items then Gfx.tri(x + w - 14, y + h - 14, "down", dark) end
  return h
end

function Gfx.tri(x, y, dir, white)
  gfx.setColor(white and gfx.kColorWhite or gfx.kColorBlack)
  if dir == "up" then gfx.fillTriangle(x, y + 6, x + 6, y + 6, x + 3, y)
  elseif dir == "down" then gfx.fillTriangle(x, y, x + 6, y, x + 3, y + 6)
  elseif dir == "right" then gfx.fillTriangle(x, y, x, y + 6, x + 5, y + 3)
  else gfx.fillTriangle(x + 5, y, x + 5, y + 6, x, y + 3) end
  gfx.setColor(gfx.kColorBlack)
end

-- horizontal meter
function Gfx.meter(x, y, w, h, v, label, white)
  v = U.clamp(v, 0, 1)
  Gfx.rect(x, y, w, h, white and "white" or "black")
  Gfx.fill(x + 1, y + 1, math.floor((w - 2) * v), h - 2, white and "white" or "black")
  if label then Gfx.text(label, x - Gfx.textW(label) - 4, y - 3, { white = white }) end
end

function Gfx.circle(x, y, r, fill, c)
  gfx.setColor(c == "white" and gfx.kColorWhite or gfx.kColorBlack)
  if fill then gfx.fillCircleAtPoint(x, y, r) else gfx.drawCircleAtPoint(x, y, r) end
  gfx.setColor(gfx.kColorBlack)
end

function Gfx.offset(x, y) gfx.setDrawOffset(x, y) end

-- a "prompt" pill at the bottom of the screen: e.g. "(A) Talk"
function Gfx.prompt(s, x, y)
  local w = Gfx.textW(s) + 16
  x = x or (200 - w // 2)
  y = y or 218
  Gfx.fill(x, y, w, 20, "white")
  Gfx.rect(x, y, w, 20)
  Gfx.rect(x + 2, y + 2, w - 4, 16)
  Gfx.text(s, x + 8, y + 2)
end

-- tiny sound helper (synth blips); safe no-op if audio unavailable
Sfx = {}
local synth
function Sfx.init()
  synth = playdate.sound.synth.new(playdate.sound.kWaveSquare)
  if synth then synth:setVolume(0.15) end
end
function Sfx.blip(freq, len)
  if synth then synth:playNote(freq or 660, 0.3, len or 0.05) end
end
function Sfx.ok() Sfx.blip(880, 0.06) end
function Sfx.bad() Sfx.blip(180, 0.15) end
function Sfx.tick() Sfx.blip(1200, 0.02) end
