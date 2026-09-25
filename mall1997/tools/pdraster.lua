-- 1-bit software rasterizer for the headless Playdate mock.
--
-- Load AFTER tools/pdmock.lua:
--   dofile(PD_TOOLS_DIR .. "pdmock.lua"); dofile(PD_TOOLS_DIR .. "pdraster.lua")
--
-- Replaces the no-op playdate.graphics implementations with a real renderer
-- (400x240 framebuffer, images with masks, contexts, patterns, dithering,
-- primitives, bitmap text). It only swaps implementations inside pdmock's
-- PDMOCK_IMPL table, so the strict API surface (only documented functions
-- exist) and PDMOCK_CALLS counting keep working.
--
-- PDRASTER_SAVE(path_png [, scale]) writes the display as a PNG (default 2x).
--
-- Pixel convention everywhere: 1 = white, 0 = black. Buffers are flat Lua
-- arrays indexed y * w + x + 1. Images may carry a mask array (1 = opaque).
--
-- Known approximations: see the report / comments marked APPROX.

assert(PDMOCK_IMPL, "pdraster.lua: load tools/pdmock.lua first (needs PDMOCK_IMPL)")
local IMPL = PDMOCK_IMPL
local newInstance = PDMOCK_NEW_INSTANCE
local Text = dofile((PD_TOOLS_DIR or "./") .. "pdtext.lua")
PDMOCK_TEXT = Text -- pdmock's text-metric overrides now use the bitmap font
local floor, ceil, sqrt, min, max, abs = math.floor, math.ceil, math.sqrt, math.min, math.max, math.abs
local tmove = table.move

local gfx = playdate.graphics
local BLACK, WHITE, CLEAR, XOR = 0, 1, 2, 3

local function def(name, fn)
  if IMPL[name] == nil then error("pdraster: " .. name .. " is not a documented Playdate API") end
  IMPL[name] = fn
end

local function toint(v) return floor((v or 0) + 0.0) end

-- ------------------------------------------------------------------ buffers
local function newBuffer(w, h, bg)
  w, h = max(0, toint(w)), max(0, toint(h))
  local px, mask = {}, false  -- false (not nil): pdmock instances error on missing keys
  local n = w * h
  local v = (bg == WHITE) and 1 or 0
  for i = 1, n do px[i] = v end
  if bg == nil or bg == CLEAR then
    mask = {}
    for i = 1, n do mask[i] = 0 end
  end
  return newInstance("playdate.graphics.image", { w = w, h = h, px = px, mask = mask })
end

local display = newBuffer(400, 240, WHITE)
PDRASTER_DISPLAY = display

local function ensureMask(t)
  if not t.mask and t ~= display then
    local m = {}
    for i = 1, t.w * t.h do m[i] = 1 end
    t.mask = m
  end
  return t.mask
end

-- ------------------------------------------------------------------ state
local function defaultState(target, font)
  return {
    target = target, color = BLACK, pat = nil, phx = 0, phy = 0,
    offx = 0, offy = 0, clip = nil, mode = 0, lw = 1, font = font, bg = WHITE,
  }
end
local S = defaultState(display, nil)
local stack = {}

local function copyState(s)
  local c = {}
  for k, v in pairs(s) do c[k] = v end
  return c
end

-- per-primitive prepared values (target, clip bounds, offset)
local T, PX, MK, TW
local CX0, CY0, CX1, CY1, OX, OY
local SRC, PAT, PHX, PHY

local function prep()
  T = S.target; PX = T.px; MK = T.mask; TW = T.w
  CX0, CY0, CX1, CY1 = 0, 0, T.w - 1, T.h - 1
  local c = S.clip
  if c then
    if c[1] > CX0 then CX0 = c[1] end
    if c[2] > CY0 then CY0 = c[2] end
    if c[3] < CX1 then CX1 = c[3] end
    if c[4] < CY1 then CY1 = c[4] end
  end
  local sc = (T == display) and S.screenClip
  if sc then
    if sc[1] > CX0 then CX0 = sc[1] end
    if sc[2] > CY0 then CY0 = sc[2] end
    if sc[3] < CX1 then CX1 = sc[3] end
    if sc[4] < CY1 then CY1 = sc[4] end
  end
  OX, OY = S.offx, S.offy
  SRC, PAT, PHX, PHY = S.color, S.pat, S.phx, S.phy
  if SRC == CLEAR and not MK and T ~= display then MK = ensureMask(T) end
end

-- horizontal span in TARGET coordinates using the current color/pattern
local function hspan(y, xa, xb)
  if y < CY0 or y > CY1 then return end
  if xa < CX0 then xa = CX0 end
  if xb > CX1 then xb = CX1 end
  if xa > xb then return end
  local px, mk = PX, MK
  local base = y * TW + 1
  if PAT then
    local row = ((y + PHY) & 7) * 8 + 1
    local phx = PHX
    for x = xa, xb do
      local v = PAT[row + ((x + phx) & 7)]
      if v < 2 then
        local i = base + x
        px[i] = v
        if mk then mk[i] = 1 end
      end
    end
  elseif SRC == BLACK or SRC == WHITE then
    local v = SRC
    for i = base + xa, base + xb do px[i] = v end
    if mk then for i = base + xa, base + xb do mk[i] = 1 end end
  elseif SRC == CLEAR then
    if mk then for i = base + xa, base + xb do mk[i] = 0; px[i] = 0 end end
  else -- XOR
    for i = base + xa, base + xb do px[i] = 1 - px[i] end
  end
end

local function plot(x, y) hspan(y, x, x) end

-- ------------------------------------------------------------------ color / pattern state
def("playdate.graphics.setColor", function(c)
  S.color = c or BLACK; S.pat = nil
end)
def("playdate.graphics.getColor", function() return S.color end)
def("playdate.graphics.setBackgroundColor", function(c) S.bg = c end)
def("playdate.graphics.getBackgroundColor", function() return S.bg end)

-- pattern: 8 row bytes (bit 1 = white), optional 8 mask bytes (bit 0 = transparent)
local function buildPattern(rows, x, y)
  local p = {}
  for r = 0, 7 do
    local b = rows[r + 1] or 0
    local m = rows[r + 9]
    for c = 0, 7 do
      local bit = (b >> (7 - c)) & 1
      if m and ((m >> (7 - c)) & 1) == 0 then bit = 2 end
      p[r * 8 + c + 1] = bit
    end
  end
  S.pat = p
  S.phx, S.phy = toint(x or 0) & 7, toint(y or 0) & 7
end

def("playdate.graphics.setPattern", function(pattern, x, y)
  if type(pattern) == "table" and pattern.px then
    -- APPROX: image patterns use the image's top-left 8x8
    local rows = {}
    for r = 0, 7 do
      local b = 0
      for c = 0, 7 do
        local v = (r < pattern.h and c < pattern.w) and pattern.px[r * pattern.w + c + 1] or 1
        b = (b << 1) | v
      end
      rows[r + 1] = b
    end
    buildPattern(rows, x, y)
  elseif type(pattern) == "table" then
    buildPattern(pattern, x, y)
  end
end)

local BAYER2 = { 0, 2, 3, 1 }
local BAYER4 = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }
local BAYER8 = {}
for y = 0, 7 do
  for x = 0, 7 do
    -- recursive construction from the 4x4 matrix
    local v = 4 * BAYER4[(y % 4) * 4 + (x % 4) + 1] + BAYER2[(y // 4) * 2 + (x // 4) + 1]
    BAYER8[y * 8 + x + 1] = v
  end
end

-- Per Inside Playdate: with a black color, the dither is black pixels on a
-- transparent background, alpha 0 = transparent, 1 = opaque; with white the
-- alpha is inverted (1 = transparent, 0 = opaque). We follow the docs.
def("playdate.graphics.setDitherPattern", function(alpha, ditherType)
  alpha = alpha or 0.5
  local col = (S.color == WHITE) and 1 or 0
  local cover = (col == 1) and (1 - alpha) or alpha
  local dt = ditherType or 6
  local p = {}
  for y = 0, 7 do
    for x = 0, 7 do
      local th
      if dt == 5 then th = (BAYER2[(y % 2) * 2 + (x % 2) + 1] + 0.5) / 4
      elseif dt == 7 then th = (BAYER8[y * 8 + x + 1] + 0.5) / 64
      elseif dt == 3 then th = (({ 0, 4, 2, 6, 1, 5, 3, 7 })[y + 1] + 0.5) / 8   -- horizontal lines
      elseif dt == 2 then th = (({ 0, 4, 2, 6, 1, 5, 3, 7 })[x + 1] + 0.5) / 8   -- vertical lines
      elseif dt == 1 then th = (({ 0, 4, 2, 6, 1, 5, 3, 7 })[((x + y) % 8) + 1] + 0.5) / 8 -- diagonal
      else th = (BAYER4[(y % 4) * 4 + (x % 4) + 1] + 0.5) / 16 end               -- 4x4 (default/APPROX for others)
      p[y * 8 + x + 1] = (th < cover) and col or 2
    end
  end
  S.pat = p; S.phx, S.phy = 0, 0
end)

def("playdate.graphics.setDrawOffset", function(x, y) S.offx, S.offy = toint(x), toint(y) end)
def("playdate.graphics.getDrawOffset", function() return S.offx, S.offy end)

def("playdate.graphics.setClipRect", function(x, y, w, h)
  if type(x) == "table" then x, y, w, h = x.x, x.y, x.width, x.height end
  x, y = toint(x) + S.offx, toint(y) + S.offy
  S.clip = { x, y, x + toint(w) - 1, y + toint(h) - 1 }
end)
def("playdate.graphics.getClipRect", function()
  local c = S.clip
  if not c then return 0, 0, S.target.w, S.target.h end
  return c[1] - S.offx, c[2] - S.offy, c[3] - c[1] + 1, c[4] - c[2] + 1
end)
def("playdate.graphics.clearClipRect", function() S.clip = nil end)
def("playdate.graphics.setScreenClipRect", function(x, y, w, h)
  if type(x) == "table" then x, y, w, h = x.x, x.y, x.width, x.height end
  x, y = toint(x), toint(y)
  S.screenClip = { x, y, x + toint(w) - 1, y + toint(h) - 1 }
end)
def("playdate.graphics.getScreenClipRect", function()
  local c = S.screenClip
  if not c then return 0, 0, 400, 240 end
  return c[1], c[2], c[3] - c[1] + 1, c[4] - c[2] + 1
end)
def("playdate.graphics.setLineWidth", function(w) S.lw = max(1, toint(w or 1)) end)
def("playdate.graphics.getLineWidth", function() return S.lw end)

local MODE_NAMES = { copy = 0, whiteTransparent = 1, blackTransparent = 2, fillWhite = 3, fillBlack = 4,
  XOR = 5, NXOR = 6, inverted = 7 }
def("playdate.graphics.setImageDrawMode", function(m)
  if type(m) == "string" then m = MODE_NAMES[m] or 0 end
  S.mode = m or 0
end)
def("playdate.graphics.getImageDrawMode", function() return S.mode end)

-- ------------------------------------------------------------------ contexts
def("playdate.graphics.pushContext", function(img)
  stack[#stack + 1] = S
  -- APPROX: a pushed context starts from default drawing state (offset 0, no
  -- clip, black, copy mode), keeping the current font.
  S = defaultState(img or display, S.font)
end)
def("playdate.graphics.popContext", function()
  if #stack > 0 then S = table.remove(stack) end
end)
def("playdate.graphics.lockFocus", function(img) S.target = img or display end)
def("playdate.graphics.unlockFocus", function() S.target = display end)

-- ------------------------------------------------------------------ primitives
local function fillRectT(x0, y0, x1, y1) -- target coords, inclusive
  if y0 < CY0 then y0 = CY0 end
  if y1 > CY1 then y1 = CY1 end
  for y = y0, y1 do hspan(y, x0, x1) end
end

local function rectArgs(x, y, w, h)
  if type(x) == "table" then return x.x, x.y, x.width, x.height end
  return x, y, w, h
end

def("playdate.graphics.fillRect", function(x, y, w, h)
  x, y, w, h = rectArgs(x, y, w, h)
  prep()
  if w < 0 then x, w = x + w, -w end
  if h < 0 then y, h = y + h, -h end
  local x0, y0 = toint(x) + OX, toint(y) + OY
  local x1, y1 = toint(x + w) - 1 + OX, toint(y + h) - 1 + OY
  fillRectT(x0, y0, x1, y1)
end)

def("playdate.graphics.drawRect", function(x, y, w, h)
  x, y, w, h = rectArgs(x, y, w, h)
  prep()
  local lw = S.lw
  local x0, y0 = toint(x) + OX, toint(y) + OY
  local x1, y1 = toint(x + w) - 1 + OX, toint(y + h) - 1 + OY
  if x1 < x0 or y1 < y0 then return end
  -- APPROX: strokes are drawn inside the rect (Playdate default is centered)
  if x1 - x0 + 1 <= 2 * lw or y1 - y0 + 1 <= 2 * lw then fillRectT(x0, y0, x1, y1) return end
  fillRectT(x0, y0, x1, y0 + lw - 1)
  fillRectT(x0, y1 - lw + 1, x1, y1)
  fillRectT(x0, y0 + lw, x0 + lw - 1, y1 - lw)
  fillRectT(x1 - lw + 1, y0 + lw, x1, y1 - lw)
end)

def("playdate.graphics.drawPixel", function(x, y)
  if type(x) == "table" then x, y = x.x, x.y end
  prep()
  plot(toint(x) + OX, toint(y) + OY)
end)

local function lineT(x0, y0, x1, y1, lw)
  local dx, dy = abs(x1 - x0), -abs(y1 - y0)
  local sx = x0 < x1 and 1 or -1
  local sy = y0 < y1 and 1 or -1
  local err = dx + dy
  local horiz = dx >= -dy
  local h0 = (lw - 1) // 2
  while true do
    if lw <= 1 then plot(x0, y0)
    elseif horiz then for yy = y0 - h0, y0 - h0 + lw - 1 do plot(x0, yy) end
    else hspan(y0, x0 - h0, x0 - h0 + lw - 1) end
    if x0 == x1 and y0 == y1 then break end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x0 = x0 + sx end
    if e2 <= dx then err = err + dx; y0 = y0 + sy end
  end
end

def("playdate.graphics.drawLine", function(x1, y1, x2, y2)
  if type(x1) == "table" then x1, y1, x2, y2 = x1.x, x1.y, x1.x2, x1.y2 end
  prep()
  lineT(toint(x1) + OX, toint(y1) + OY, toint(x2) + OX, toint(y2) + OY, S.lw)
end)

-- ---- shapes via per-row spans (target coords)
-- ellipse inscribed in the (float) rect; returns span function row -> xa, xb
local function ellipseRows(x, y, w, h)
  local cx, cy, rx, ry = x + w / 2, y + h / 2, w / 2, h / 2
  return function(j)
    if rx <= 0 or ry <= 0 then return nil end
    local dy = (j + 0.5 - cy) / ry
    if dy < -1 or dy > 1 then return nil end
    local half = rx * sqrt(1 - dy * dy)
    local xa, xb = ceil(cx - half - 0.5), floor(cx + half - 0.5)
    if xa > xb then return nil end
    return xa, xb
  end, floor(y), ceil(y + h) - 1
end

local function roundRectRows(x, y, w, h, r)
  r = max(0, min(r or 0, w / 2, h / 2))
  return function(j)
    local ry = j - y
    if ry < 0 or ry >= h then return nil end
    local dy
    if ry < r then dy = r - (ry + 0.5)
    elseif ry >= h - r then dy = (ry + 0.5) - (h - r)
    else return x, x + w - 1 end
    local s2 = r * r - dy * dy
    if s2 < 0 then return nil end
    local s = sqrt(s2)
    local xa, xb = ceil(x + r - s - 0.5), floor(x + w - r + s - 0.5)
    if xa > xb then return nil end
    return xa, xb
  end, y, y + h - 1
end

local function fillRows(rows, j0, j1)
  for j = max(j0, CY0), min(j1, CY1) do
    local a, b = rows(j)
    if a then hspan(j, a, b) end
  end
end

-- outline of a (convex) row-span shape; inner = inset shape for thick lines.
-- emit(y, xa, xb) defaults to hspan.
local function strokeRows(rows, j0, j1, inner, emit)
  emit = emit or hspan
  local cache = {}
  local function get(j)
    local c = cache[j]
    if c == nil then
      local a, b = rows(j)
      c = a and { a, b } or false
      cache[j] = c
    end
    return c
  end
  for j = j0, j1 do
    local c = get(j)
    if c then
      local a, b = c[1], c[2]
      -- interior (not drawn) = (a, b) exclusive ∩ prev row ∩ next row ∩ inner row
      local ia, ib = a + 1, b - 1
      local p, n = get(j - 1), get(j + 1)
      if p then ia = max(ia, p[1]); ib = min(ib, p[2]) else ib = ia - 1 end
      if n then ia = max(ia, n[1]); ib = min(ib, n[2]) else ib = ia - 1 end
      if inner then
        local x0, x1 = inner(j)
        if x0 then ia = max(ia, x0); ib = min(ib, x1) else ib = ia - 1 end
      end
      if ia > ib then emit(j, a, b)
      else
        if ia > a then emit(j, a, ia - 1) end
        if ib < b then emit(j, ib + 1, b) end
      end
    end
  end
end

local function ellipseArgs(x, y, w, h)
  if type(x) == "table" then return x.x, x.y, x.width, x.height end
  return x, y, w, h
end

local function fillEllipse(x, y, w, h)
  prep()
  local rows, j0, j1 = ellipseRows(x + OX, y + OY, w, h)
  fillRows(rows, j0, j1)
end
local function strokeEllipse(x, y, w, h, emit)
  local lw = S.lw
  local X, Y = x + OX, y + OY
  local rows, j0, j1 = ellipseRows(X, Y, w, h)
  local inner = nil
  if lw > 1 then inner = (ellipseRows(X + lw, Y + lw, w - 2 * lw, h - 2 * lw)) end
  strokeRows(rows, j0, j1, inner, emit)
end

def("playdate.graphics.fillEllipseInRect", function(x, y, w, h)
  x, y, w, h = ellipseArgs(x, y, w, h)
  fillEllipse(x, y, w, h)
end)
def("playdate.graphics.drawEllipseInRect", function(x, y, w, h)
  x, y, w, h = ellipseArgs(x, y, w, h)
  prep(); strokeEllipse(x, y, w, h)
end)
def("playdate.graphics.fillCircleAtPoint", function(x, y, r)
  if type(x) == "table" then x, y, r = x.x, x.y, y end
  fillEllipse(x - r, y - r, 2 * r, 2 * r)
end)
def("playdate.graphics.drawCircleAtPoint", function(x, y, r)
  if type(x) == "table" then x, y, r = x.x, x.y, y end
  prep(); strokeEllipse(x - r, y - r, 2 * r, 2 * r)
end)
def("playdate.graphics.fillCircleInRect", function(x, y, w, h)
  x, y, w, h = ellipseArgs(x, y, w, h)
  local d = min(w, h)
  fillEllipse(x + (w - d) / 2, y + (h - d) / 2, d, d)
end)
def("playdate.graphics.drawCircleInRect", function(x, y, w, h)
  x, y, w, h = ellipseArgs(x, y, w, h)
  local d = min(w, h)
  prep(); strokeEllipse(x + (w - d) / 2, y + (h - d) / 2, d, d)
end)

def("playdate.graphics.fillRoundRect", function(x, y, w, h, r)
  if type(x) == "table" then x, y, w, h, r = x.x, x.y, x.width, x.height, y end
  prep()
  local rows, j0, j1 = roundRectRows(toint(x) + OX, toint(y) + OY, toint(w), toint(h), r)
  fillRows(rows, j0, j1)
end)
def("playdate.graphics.drawRoundRect", function(x, y, w, h, r)
  if type(x) == "table" then x, y, w, h, r = x.x, x.y, x.width, x.height, y end
  prep()
  local lw = S.lw
  local X, Y, W, H = toint(x) + OX, toint(y) + OY, toint(w), toint(h)
  local rows, j0, j1 = roundRectRows(X, Y, W, H, r)
  local inner = nil
  if lw > 1 then inner = (roundRectRows(X + lw, Y + lw, W - 2 * lw, H - 2 * lw, max(0, (r or 0) - lw))) end
  strokeRows(rows, j0, j1, inner)
end)

-- Playdate angles: 0 = up (north), increasing clockwise, degrees
def("playdate.graphics.drawArc", function(x, y, r, a0, a1)
  if type(x) == "table" then x, y, r, a0, a1 = x.x, x.y, x.r, x.startAngle, x.endAngle end
  prep()
  local span = a1 - a0
  local full = span >= 360 or span <= -360
  span = span % 360
  if span == 0 and not full then span = 360; full = true end
  a0 = a0 % 360
  local cx, cy = x + OX, y + OY
  local emit = function(j, xa, xb)
    for i = xa, xb do
      local ang = math.deg(math.atan(i + 0.5 - cx, -(j + 0.5 - cy))) % 360
      if full or (ang - a0) % 360 <= span then plot(i, j) end
    end
  end
  strokeEllipse(x - r, y - r, 2 * r, 2 * r, emit)
end)

-- polygons: flat coordinate list (or a table of numbers / points)
local function polyPoints(...)
  local a = { ... }
  if #a == 1 and type(a[1]) == "table" then
    local t = a[1]
    if type(t[1]) == "number" then a = t
    else
      a = {}
      for _, pt in ipairs(t) do a[#a + 1] = pt.x; a[#a + 1] = pt.y end
    end
  end
  local pts = {}
  for i = 1, #a - 1, 2 do pts[#pts + 1] = { a[i] + OX, a[i + 1] + OY } end
  return pts
end

local function fillPoly(pts)
  local n = #pts
  if n < 3 then return end
  local ymin, ymax = math.huge, -math.huge
  for _, p in ipairs(pts) do ymin = min(ymin, p[2]); ymax = max(ymax, p[2]) end
  for j = max(floor(ymin), CY0), min(ceil(ymax) - 1, CY1) do
    local yc = j + 0.5
    local xs = {}
    for i = 1, n do
      local p, q = pts[i], pts[i % n + 1]
      local y1, y2 = p[2], q[2]
      if (y1 <= yc and yc < y2) or (y2 <= yc and yc < y1) then
        xs[#xs + 1] = p[1] + (yc - y1) * (q[1] - p[1]) / (y2 - y1)
      end
    end
    table.sort(xs)
    for k = 1, #xs - 1, 2 do
      local xa, xb = ceil(xs[k] - 0.5), floor(xs[k + 1] - 0.5)
      if xa <= xb then hspan(j, xa, xb) end
    end
  end
end

def("playdate.graphics.fillPolygon", function(...)
  prep(); fillPoly(polyPoints(...))
end)
def("playdate.graphics.fillTriangle", function(x1, y1, x2, y2, x3, y3)
  prep(); fillPoly(polyPoints(x1, y1, x2, y2, x3, y3))
end)
local function strokePoly(pts, close)
  local lw = S.lw
  for i = 1, #pts - 1 do
    lineT(toint(pts[i][1]), toint(pts[i][2]), toint(pts[i + 1][1]), toint(pts[i + 1][2]), lw)
  end
  local f, l = pts[1], pts[#pts]
  if close and #pts > 2 and (f[1] ~= l[1] or f[2] ~= l[2]) then
    lineT(toint(l[1]), toint(l[2]), toint(f[1]), toint(f[2]), lw)
  end
end
def("playdate.graphics.drawPolygon", function(...)
  prep(); strokePoly(polyPoints(...), true)
end)
def("playdate.graphics.drawTriangle", function(x1, y1, x2, y2, x3, y3)
  prep(); strokePoly(polyPoints(x1, y1, x2, y2, x3, y3), true)
end)

def("playdate.graphics.clear", function(color)
  local t = S.target
  local c = color or S.bg
  if c == CLEAR then
    if t == display then c = WHITE
    else
      local m = ensureMask(t)
      for i = 1, t.w * t.h do m[i] = 0; t.px[i] = 0 end
      return
    end
  end
  local v = (c == WHITE) and 1 or 0
  local px = t.px
  for i = 1, t.w * t.h do px[i] = v end
  if t.mask then local m = t.mask; for i = 1, t.w * t.h do m[i] = 1 end end
end)

-- ------------------------------------------------------------------ images
-- draw-mode lookup: result for a source pixel of value s: 0/1 = write, 2 = skip, 3 = invert
local MODE = {
  [0] = { [0] = 0, [1] = 1 },   -- copy
  [1] = { [0] = 0, [1] = 2 },   -- white transparent
  [2] = { [0] = 2, [1] = 1 },   -- black transparent
  [3] = { [0] = 1, [1] = 1 },   -- fill white
  [4] = { [0] = 0, [1] = 0 },   -- fill black
  [5] = { [0] = 2, [1] = 3 },   -- XOR (white source pixels invert dest)
  [6] = { [0] = 3, [1] = 2 },   -- NXOR (black source pixels invert dest)
  [7] = { [0] = 1, [1] = 0 },   -- inverted
}

local FLIPS = { flipX = 1, flipY = 2, flipXY = 3 }

-- blit image `img` with its top-left at TARGET coords (tx, ty)
local function blit(img, tx, ty, flip, srect)
  if type(flip) == "string" then flip = FLIPS[flip] or 0 end
  flip = flip or 0
  local fx, fy = (flip & 1) ~= 0, (flip & 2) ~= 0
  local sw, sh = img.w, img.h
  local sx0, sy0, rw, rh = 0, 0, sw, sh
  if type(srect) == "table" then
    sx0, sy0 = toint(srect.x or srect[1] or 0), toint(srect.y or srect[2] or 0)
    rw, rh = toint(srect.width or srect[3] or sw), toint(srect.height or srect[4] or sh)
  end
  -- destination rect clipped
  local dx0, dy0 = max(tx, CX0), max(ty, CY0)
  local dx1, dy1 = min(tx + rw - 1, CX1), min(ty + rh - 1, CY1)
  if dx0 > dx1 or dy0 > dy1 then return end
  local spx, smk = img.px, img.mask
  local dpx, dmk = PX, MK
  local mode = S.mode
  if img == T then
    -- drawing an image into itself: snapshot the source
    spx = tmove(spx, 1, #spx, 1, {})
    if smk then smk = tmove(smk, 1, #smk, 1, {}) end
  end
  if mode == 0 and not fx and not smk then
    -- fast path: straight row copies
    local n = dx1 - dx0
    for y = dy0, dy1 do
      local sy = fy and (sy0 + rh - 1 - (y - ty)) or (sy0 + y - ty)
      if sy >= 0 and sy < sh then
        local sxa = sx0 + dx0 - tx
        local sb = sy * sw + 1
        local db = y * TW + 1 + dx0
        local a, b = sxa, sxa + n
        if a < 0 then db = db - a; a = 0 end
        if b > sw - 1 then b = sw - 1 end
        if a <= b then
          tmove(spx, sb + a, sb + b, db, dpx)
          if dmk then for i = db, db + (b - a) do dmk[i] = 1 end end
        end
      end
    end
    return
  end
  local M = MODE[mode] or MODE[0]
  local m0, m1 = M[0], M[1]
  for y = dy0, dy1 do
    local sy = fy and (sy0 + rh - 1 - (y - ty)) or (sy0 + y - ty)
    if sy >= 0 and sy < sh then
      local sb = sy * sw + 1
      local db = y * TW + 1
      for x = dx0, dx1 do
        local sx = fx and (sx0 + rw - 1 - (x - tx)) or (sx0 + x - tx)
        if sx >= 0 and sx < sw then
          local si = sb + sx
          if not smk or smk[si] == 1 then
            local r = (spx[si] == 1) and m1 or m0
            if r < 2 then
              dpx[db + x] = r
              if dmk then dmk[db + x] = 1 end
            elseif r == 3 then
              dpx[db + x] = 1 - dpx[db + x]
            end
          end
        end
      end
    end
  end
end

def("playdate.graphics.image.new", function(a, b, c)
  if type(a) == "number" then return newBuffer(a, b, c) end
  return nil -- no image files ship with the game
end)
def("playdate.graphics.image:getSize", function(self) return self.w, self.h end)
def("playdate.graphics.image:clear", function(self, color)
  local n = self.w * self.h
  if color == CLEAR then
    local m = ensureMask(self)
    for i = 1, n do m[i] = 0; self.px[i] = 0 end
  else
    local v = (color == WHITE) and 1 or 0
    for i = 1, n do self.px[i] = v end
    if self.mask then for i = 1, n do self.mask[i] = 1 end end
  end
end)
def("playdate.graphics.image:draw", function(self, x, y, flip, srect)
  if type(x) == "table" then x, y, flip, srect = x.x, x.y, y, flip end
  prep()
  blit(self, toint(x) + OX, toint(y) + OY, flip, srect)
end)
def("playdate.graphics.image:drawIgnoringOffset", function(self, x, y, flip)
  if type(x) == "table" then x, y, flip = x.x, x.y, y end
  prep()
  blit(self, toint(x), toint(y), flip)
end)
def("playdate.graphics.image:drawCentered", function(self, x, y, flip)
  prep()
  blit(self, toint(x - self.w / 2) + OX, toint(y - self.h / 2) + OY, flip)
end)
def("playdate.graphics.image:drawAnchored", function(self, x, y, ax, ay, flip)
  prep()
  blit(self, toint(x - self.w * (ax or 0)) + OX, toint(y - self.h * (ay or 0)) + OY, flip)
end)
def("playdate.graphics.image:drawScaled", function(self, x, y, sx, sy)
  sy = sy or sx
  local w, h = max(1, toint(self.w * sx)), max(1, toint(self.h * sy))
  local out = newBuffer(w, h, CLEAR)
  for yy = 0, h - 1 do
    for xx = 0, w - 1 do
      local si = floor(yy / sy) * self.w + floor(xx / sx) + 1
      out.px[yy * w + xx + 1] = self.px[si]
      out.mask[yy * w + xx + 1] = self.mask and self.mask[si] or 1
    end
  end
  prep()
  blit(out, toint(x) + OX, toint(y) + OY, 0)
end)
def("playdate.graphics.image:copy", function(self)
  local c = newBuffer(self.w, self.h, WHITE)
  tmove(self.px, 1, #self.px, 1, c.px)
  if self.mask then c.mask = tmove(self.mask, 1, #self.mask, 1, {}) end
  return c
end)
def("playdate.graphics.image:invertedImage", function(self)
  local c = gfx.image.new(self.w, self.h, WHITE)
  for i = 1, #self.px do c.px[i] = 1 - self.px[i] end
  if self.mask then c.mask = tmove(self.mask, 1, #self.mask, 1, {}) end
  return c
end)
def("playdate.graphics.image:hasMask", function(self) return self.mask ~= false end)
def("playdate.graphics.image:removeMask", function(self) self.mask = false end)
def("playdate.graphics.image:sample", function(self, x, y)
  x, y = toint(x), toint(y)
  if x < 0 or y < 0 or x >= self.w or y >= self.h then return CLEAR end
  local i = y * self.w + x + 1
  if self.mask and self.mask[i] == 0 then return CLEAR end
  return self.px[i]
end)
def("playdate.graphics.getDisplayImage", function() return display:copy() end)
def("playdate.graphics.getWorkingImage", function() return S.target:copy() end)

-- ------------------------------------------------------------------ text
local FONT_H = Text.height
local fontObjs = {}
local function fontFor(variant)
  local f = fontObjs[variant]
  if not f then
    f = newInstance("playdate.graphics.font", { variant = variant })
    fontObjs[variant] = f
  end
  return f
end
local VAR = { [0] = "normal", [1] = "bold", [2] = "italic" }
S.font = fontFor("normal")

def("playdate.graphics.getSystemFont", function(v)
  if type(v) == "string" then return fontFor(v) end
  return fontFor(VAR[v or 0] or "normal")
end)
def("playdate.graphics.setFont", function(f, variant)
  if f then S.font = f end
end)
def("playdate.graphics.getFont", function(v)
  if v ~= nil then return fontFor(type(v) == "string" and v or (VAR[v] or "normal")) end
  return S.font
end)
def("playdate.graphics.font:getHeight", function() return FONT_H end)
def("playdate.graphics.font:getLeading", function() return 0 end)
def("playdate.graphics.font:getTracking", function() return 0 end)
def("playdate.graphics.font:getTextWidth", function(self, s) return (Text.size(s, self.variant, false)) end)
def("playdate.graphics.getTextSize", function(s, family, leading)
  return Text.size(s, S.font and S.font.variant or "normal", true, leading)
end)

-- draw one glyph with its cell's top-left at target (tx, ty)
local function drawGlyph(g, tx, ty, m0)
  local rows, w = g.r, g.w
  local x0 = tx + g.x
  for r = 1, #rows do
    local bits = rows[r]
    if bits ~= 0 then
      local y = ty + r - 1
      if y >= CY0 and y <= CY1 then
        local base = y * TW + 1
        for c = 0, w - 1 do
          if (bits >> (w - 1 - c)) & 1 == 1 then
            local x = x0 + c
            if x >= CX0 and x <= CX1 then
              local i = base + x
              if m0 < 2 then
                PX[i] = m0
                if MK then MK[i] = 1 end
              elseif m0 == 3 then PX[i] = 1 - PX[i] end
            end
          end
        end
      end
    end
  end
end

-- align: 0 left, 1 right, 2 center (kTextAlignment)
local function drawTextImpl(s, x, y, base, markup, align, leading)
  prep()
  local m0 = (MODE[S.mode] or MODE[0])[0] -- glyphs are black-on-transparent
  local lines = Text.layout(s, base, markup)
  local maxw = 0
  local ty = toint(y) + OY
  for _, line in ipairs(lines) do
    local lw = Text.lineWidth(line)
    if lw > maxw then maxw = lw end
    local tx = toint(x) + OX
    if align == 1 then tx = tx - lw
    elseif align == 2 then tx = tx - lw // 2 end
    for _, gg in ipairs(line) do
      local g = Text.glyph(gg[2], gg[1])
      drawGlyph(g, tx, ty, m0)
      tx = tx + g.a
    end
    ty = ty + FONT_H + (leading or 0)
  end
  return maxw, #lines * FONT_H + (#lines - 1) * (leading or 0)
end

local function curVariant() return S.font and S.font.variant or "normal" end

def("playdate.graphics.drawText", function(s, x, y, family, leading)
  if type(x) == "table" then x, y = x.x, x.y end
  return drawTextImpl(s, x, y, curVariant(), true, 0, leading)
end)
def("playdate.graphics.drawTextAligned", function(s, x, y, align, leading)
  return drawTextImpl(s, x, y, curVariant(), true, align or 0, leading)
end)
def("playdate.graphics.font:drawText", function(self, s, x, y, leading)
  return drawTextImpl(s, x, y, self.variant, false, 0, leading)
end)
def("playdate.graphics.font:drawTextAligned", function(self, s, x, y, align, leading)
  return drawTextImpl(s, x, y, self.variant, false, align or 0, leading)
end)
-- APPROX: word-wraps on spaces, no truncator
def("playdate.graphics.drawTextInRect", function(s, x, y, w, h, leading, truncator, align)
  if type(x) == "table" then x, y, w, h, leading, truncator, align = x.x, x.y, x.width, x.height, y, w, h end
  local base = curVariant()
  local out = {}
  for para in (tostring(s) .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      local test = (#line > 0) and (line .. " " .. word) or word
      if Text.size(test, base, true) > w and #line > 0 then out[#out + 1] = line; line = word
      else line = test end
    end
    out[#out + 1] = line
  end
  local lh = FONT_H + (leading or 0)
  local n = max(0, min(#out, (h + (leading or 0)) // lh))
  local maxw = 0
  for i = 1, n do
    local ax = x
    if align == 1 then ax = x + w elseif align == 2 then ax = x + w // 2 end
    local ww = drawTextImpl(out[i], ax, y + (i - 1) * lh, base, true, align or 0)
    maxw = max(maxw, ww)
  end
  return maxw, n * lh, n < #out
end)

-- ------------------------------------------------------------------ PNG output
local crcTable = {}
for i = 0, 255 do
  local c = i
  for _ = 1, 8 do
    if c & 1 == 1 then c = 0xEDB88320 ~ (c >> 1) else c = c >> 1 end
  end
  crcTable[i] = c
end
local function crc32(s, crc)
  crc = (crc or 0) ~ 0xFFFFFFFF
  for i = 1, #s do crc = crcTable[(crc ~ s:byte(i)) & 0xFF] ~ (crc >> 8) end
  return crc ~ 0xFFFFFFFF
end
local function chunk(kind, data)
  return string.pack(">I4", #data) .. kind .. data .. string.pack(">I4", crc32(kind .. data))
end

-- palette: index 0 = black, index 1 = Playdate-ish off-white
function PDRASTER_PNG(img, scale)
  img = img or display
  scale = scale or 2
  local W, H = img.w * scale, img.h * scale
  local rowBytes = (W + 7) // 8
  local raw = {}
  local px = img.px
  for y = 0, img.h - 1 do
    local bytes = {}
    local acc, nb = 0, 0
    local base = y * img.w + 1
    for x = 0, img.w - 1 do
      local v = px[base + x]
      for _ = 1, scale do
        acc = (acc << 1) | v; nb = nb + 1
        if nb == 8 then bytes[#bytes + 1] = acc; acc, nb = 0, 0 end
      end
    end
    if nb > 0 then bytes[#bytes + 1] = acc << (8 - nb) end
    local row = "\0" .. string.char(table.unpack(bytes))
    for _ = 1, scale do raw[#raw + 1] = row end
  end
  local data = table.concat(raw)
  -- zlib stream with stored (uncompressed) deflate blocks
  local z = { "\x78\x01" }
  local pos, n = 1, #data
  while pos <= n do
    local len = min(65535, n - pos + 1)
    local final = (pos + len > n) and 1 or 0
    z[#z + 1] = string.char(final) .. string.pack("<I2<I2", len, len ~ 0xFFFF) .. data:sub(pos, pos + len - 1)
    pos = pos + len
  end
  local a, b = 1, 0
  for i = 1, n do a = (a + data:byte(i)) % 65521; b = (b + a) % 65521 end
  z[#z + 1] = string.pack(">I4", (b << 16) | a)
  assert(rowBytes > 0)
  return "\x89PNG\r\n\x1a\n"
    .. chunk("IHDR", string.pack(">I4>I4BBBBB", W, H, 1, 3, 0, 0, 0))
    .. chunk("PLTE", "\0\0\0\xB1\xAF\xA8")
    .. chunk("IDAT", table.concat(z))
    .. chunk("IEND", "")
end

function PDRASTER_SAVE(path, scale, img)
  local f = assert(io.open(path, "wb"))
  f:write(PDRASTER_PNG(img, scale))
  f:close()
end
