-- CRANKING IT :: core/art
-- 1-bit pattern library and procedural "woodcut" drawing helpers.
-- Anything static is rendered once into a cached image.

Art = {}

local gfx <const> = playdate.graphics
local sin <const>, cos <const>, rad <const> = math.sin, math.cos, math.rad
local unpack <const> = table.unpack

-- 8x8 patterns: bit 1 = white, 0 = black
Art.pat = {
  white    = { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff },
  black    = { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
  gray6    = { 0xff, 0xff, 0xff, 0xef, 0xff, 0xff, 0xff, 0xfe },
  gray12   = { 0x77, 0xff, 0xdd, 0xff, 0x77, 0xff, 0xdd, 0xff },
  gray25   = { 0x77, 0xdd, 0x77, 0xdd, 0x77, 0xdd, 0x77, 0xdd },
  gray50   = { 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55 },
  gray75   = { 0x88, 0x22, 0x88, 0x22, 0x88, 0x22, 0x88, 0x22 },
  gray87   = { 0x88, 0x00, 0x22, 0x00, 0x88, 0x00, 0x22, 0x00 },
  hatch    = { 0x7f, 0xbf, 0xdf, 0xef, 0xf7, 0xfb, 0xfd, 0xfe },
  hatchR   = { 0xfe, 0xfd, 0xfb, 0xf7, 0xef, 0xdf, 0xbf, 0x7f },
  hatchD   = { 0x3f, 0x9f, 0xcf, 0xe7, 0xf3, 0xf9, 0xfc, 0x7e },
  cross    = { 0x7e, 0xbd, 0xdb, 0xe7, 0xe7, 0xdb, 0xbd, 0x7e },
  hlines   = { 0x00, 0xff, 0xff, 0xff, 0x00, 0xff, 0xff, 0xff },
  hlines2  = { 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff },
  vlines   = { 0x77, 0x77, 0x77, 0x77, 0x77, 0x77, 0x77, 0x77 },
  dots     = { 0xff, 0xdf, 0xff, 0xff, 0xff, 0xfd, 0xff, 0xff },
  wood     = { 0xff, 0x00, 0xff, 0xf7, 0xff, 0xff, 0x00, 0xff },
  grain    = { 0xff, 0xe1, 0xff, 0xff, 0x87, 0xff, 0xff, 0xff },
  bricks   = { 0x00, 0xef, 0xef, 0xef, 0x00, 0xfe, 0xfe, 0xfe },
  waves    = { 0xff, 0xe7, 0xdb, 0x3c, 0xff, 0xff, 0xff, 0xff },
  scales   = { 0xe7, 0xdb, 0xbd, 0x7e, 0x7e, 0xff, 0xff, 0xff },
  weave    = { 0x0f, 0x0f, 0x0f, 0x0f, 0xf0, 0xf0, 0xf0, 0xf0 },
  grid     = { 0x00, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f },
  stipple  = { 0xdf, 0xff, 0x7f, 0xfb, 0xff, 0xef, 0xfe, 0xff },
}

-- ordered grey ramp for dithering by value 0 (white) .. 1 (black)
Art.ramp = { "white", "gray6", "gray12", "gray25", "gray50", "gray75", "gray87", "black" }

function Art.setPat(name) gfx.setPattern(Art.pat[name]) end

-- set pattern by darkness 0..1
function Art.setShade(v)
  local i = math.floor(U.clamp(v, 0, 1) * (#Art.ramp - 1) + 0.5) + 1
  gfx.setPattern(Art.pat[Art.ramp[i]])
end

function Art.black() gfx.setColor(gfx.kColorBlack) end
function Art.white() gfx.setColor(gfx.kColorWhite) end

------------------------------------------------------------------------
-- image cache
------------------------------------------------------------------------
local cache = {}
function Art.cached(key, w, h, builder, bg)
  local img = cache[key]
  if img then return img end
  img = gfx.image.new(w, h, bg or gfx.kColorClear)
  gfx.pushContext(img)
  builder(w, h)
  gfx.popContext()
  cache[key] = img
  return img
end
function Art.uncache(key) cache[key] = nil end

------------------------------------------------------------------------
-- polygon scratch buffer (avoids allocating per draw)
------------------------------------------------------------------------
local poly = {}
local function polyFill(n) gfx.fillPolygon(unpack(poly, 1, n)) end
local function polyStroke(n) gfx.drawPolygon(unpack(poly, 1, n)) end
Art.poly = poly
Art.polyFill = polyFill
Art.polyStroke = polyStroke

-- regular gear outline. teeth >= 4
function Art.gear(cx, cy, r, teeth, angle, filled, hole)
  local n = 0
  local depth = math.max(2, r * 0.18)
  local step = 360 / teeth
  for i = 0, teeth - 1 do
    local a = angle + i * step
    local a1, a2, a3, a4 = rad(a - step * 0.25), rad(a - step * 0.12), rad(a + step * 0.12), rad(a + step * 0.25)
    local ro, ri = r, r - depth
    poly[n + 1], poly[n + 2] = cx + sin(a1) * ri, cy - cos(a1) * ri
    poly[n + 3], poly[n + 4] = cx + sin(a2) * ro, cy - cos(a2) * ro
    poly[n + 5], poly[n + 6] = cx + sin(a3) * ro, cy - cos(a3) * ro
    poly[n + 7], poly[n + 8] = cx + sin(a4) * ri, cy - cos(a4) * ri
    n = n + 8
  end
  if filled then
    polyFill(n)
    if hole ~= false then
      gfx.setColor(gfx.kColorWhite)
      gfx.fillCircleAtPoint(cx, cy, math.max(1, r * 0.28))
      gfx.setColor(gfx.kColorBlack)
    end
  else
    polyStroke(n)
    gfx.drawCircleAtPoint(cx, cy, math.max(1, r * 0.28))
  end
end

-- spokes for larger gears
function Art.spokes(cx, cy, r, count, angle)
  for i = 0, count - 1 do
    local a = rad(angle + i * 360 / count)
    gfx.drawLine(cx, cy, cx + sin(a) * r, cy - cos(a) * r)
  end
end

-- the currency icon
function Art.gearIcon(x, y, r, angle)
  gfx.setColor(gfx.kColorBlack)
  Art.gear(x, y, r, 8, angle or 0, true)
end

-- woodcut style frame: heavy outer rule, thin inner rule, notched corners
function Art.frame(x, y, w, h, inverted)
  local fg = inverted and gfx.kColorWhite or gfx.kColorBlack
  gfx.setColor(fg)
  gfx.setLineWidth(3)
  gfx.drawRect(x, y, w, h)
  gfx.setLineWidth(1)
  gfx.drawRect(x + 5, y + 5, w - 10, h - 10)
  -- corner blocks
  gfx.fillRect(x + 1, y + 1, 7, 7)
  gfx.fillRect(x + w - 8, y + 1, 7, 7)
  gfx.fillRect(x + 1, y + h - 8, 7, 7)
  gfx.fillRect(x + w - 8, y + h - 8, 7, 7)
  gfx.setColor(inverted and gfx.kColorBlack or gfx.kColorWhite)
  gfx.fillRect(x + 3, y + 3, 3, 3)
  gfx.fillRect(x + w - 6, y + 3, 3, 3)
  gfx.fillRect(x + 3, y + h - 6, 3, 3)
  gfx.fillRect(x + w - 6, y + h - 6, 3, 3)
  gfx.setColor(fg)
end

function Art.rivet(x, y)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(x, y, 2)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawPixel(x - 1, y - 1)
  gfx.setColor(gfx.kColorBlack)
end

-- panel of riveted sheet metal
function Art.plate(x, y, w, h, shade)
  if shade then Art.setPat(shade) else gfx.setColor(gfx.kColorWhite) end
  gfx.fillRect(x, y, w, h)
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(2)
  gfx.drawRect(x, y, w, h)
  gfx.setLineWidth(1)
  Art.rivet(x + 5, y + 5)
  Art.rivet(x + w - 6, y + 5)
  Art.rivet(x + 5, y + h - 6)
  Art.rivet(x + w - 6, y + h - 6)
end

-- rolling sea band from y downward; t in seconds
function Art.sea(x0, x1, y, t, amp, spacing)
  amp = amp or 2
  spacing = spacing or 14
  gfx.setColor(gfx.kColorBlack)
  for row = 0, 3 do
    local yy = y + row * 6
    local ph = t * (1.2 + row * 0.4) + row * 1.7
    local prevx, prevy = x0, yy + sin(ph) * amp
    for x = x0 + spacing // 2, x1, spacing // 2 do
      local ny = yy + sin(ph + x * 0.09) * amp
      if (x // spacing + row) % 3 ~= 0 then gfx.drawLine(prevx, prevy, x, ny) end
      prevx, prevy = x, ny
    end
  end
end

-- thick line helper
function Art.line(x1, y1, x2, y2, w)
  gfx.setLineWidth(w or 1)
  gfx.drawLine(x1, y1, x2, y2)
  gfx.setLineWidth(1)
end

-- draw text with a 1px white halo so it reads over busy art
function Art.haloText(font, text, x, y)
  gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
  font:drawText(text, x - 1, y) font:drawText(text, x + 1, y)
  font:drawText(text, x, y - 1) font:drawText(text, x, y + 1)
  gfx.setImageDrawMode(gfx.kDrawModeCopy)
  font:drawText(text, x, y)
end

-- simple hand-drawn crank glyph (used in prompts)
function Art.crankGlyph(cx, cy, r, angle)
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(2)
  gfx.drawCircleAtPoint(cx, cy, r)
  local a = rad(angle)
  local hx, hy = cx + sin(a) * r, cy - cos(a) * r
  gfx.drawLine(cx, cy, hx, hy)
  gfx.setLineWidth(1)
  gfx.fillCircleAtPoint(hx, hy, math.max(2, r * 0.35))
  gfx.fillCircleAtPoint(cx, cy, 2)
end
