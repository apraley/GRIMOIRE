-- Chunky 1-bit character sprites and procedural portraits.
-- Sprites are built from small ASCII templates, colored per NPC "look"
-- (hair style/color, shirt pattern, pants, skin, accessories), and cached as
-- images the first time they're needed.

Sprites = {}
local gfx = playdate.graphics

local SW, SH = 16, 24
Sprites.W, Sprites.H = SW, SH

-- Template legend: O outline, S skin, H hair, T shirt, P pants, E eye,
-- W white, . transparent, B shoe (black)
local HEAD_DOWN = {
  ".....OOOOOO.....",
  "....OHHHHHHO....",
  "...OHHHHHHHHO...",
  "...OHHHHHHHHO...",
  "...OHSSSSSSHO...",
  "...OSSESSESSO...",
  "...OSSSSSSSSO...",
  "....OSSSSSSO....",
  ".....OOSSOO.....",
}
local HEAD_UP = {
  ".....OOOOOO.....",
  "....OHHHHHHO....",
  "...OHHHHHHHHO...",
  "...OHHHHHHHHO...",
  "...OHHHHHHHHO...",
  "...OHHHHHHHHO...",
  "...OHHHHHHHHO...",
  "....OHHHHHHO....",
  ".....OOSSOO.....",
}
local HEAD_SIDE = {
  ".....OOOOOO.....",
  "....OHHHHHHO....",
  "...OHHHHHHHHO...",
  "...OHHHHHHHSO...",
  "...OHHHHSSSSO...",
  "...OHHHSSSESO...",
  "...OHHHSSSSSO...",
  "....OHHSSSSO....",
  ".....OOSSOO.....",
}
local BODY_DOWN = {
  "...OOTTTTTTOO...",
  "..OTTTTTTTTTTO..",
  "..OTTTTTTTTTTO..",
  "..OSOTTTTTTOSO..",
  "..OSOTTTTTTOSO..",
  "...O.PPPPPP.O...",
  "....OPPPPPPO....",
}
local BODY_SIDE = {
  ".....OTTTTO.....",
  "....OTTTTTTO....",
  "....OTTTTTTO....",
  "....OTSSTTTO....",
  "....OTSSTTTO....",
  ".....OPPPPO.....",
  ".....OPPPPO.....",
}
local LEGS = {
  down = {
    { "....OPPOOPPO....", "....OPPOOPPO....", "....OPPOOPPO....", "....OBBOOBBO....", "....OOOOOOOO...." },
    { "....OPPOOPPO....", "....OPPO.OPO....", "....OBBO.OPO....", "....OOOO.OBO....", ".........OOO...." },
    { "....OPPOOPPO....", "....OPO.OPPO....", "....OPO.OBBO....", "....OBO.OOOO....", "....OOO........." },
  },
  side = {
    { ".....OPPPPO.....", ".....OPPPPO.....", ".....OPPPPO.....", ".....OBBBBO.....", ".....OOOOOO....." },
    { ".....OPPOPPO....", "....OPPO.OPPO...", "...OPPO...OPPO..", "...OBBO...OBBO..", "...OOO.....OOO.." },
    { ".....OPPPPO.....", "......OPPO......", "......OPPO......", "......OBBO......", "......OOOO......" },
  },
}

-- hair style overlays: rows of the head that become hair (H) or skin (S)
-- style 0 short, 1 spiky, 2 long, 3 ponytail, 4 curtains, 5 buzz, 6 bun, 7 big
local function hairRow(style, dir, y, row)
  if dir == "up" then
    if style == 5 and y >= 3 then return (row:gsub("H", "S")) end
    return row
  end
  if style == 5 and y >= 2 then return (row:gsub("H", "S")) end
  if style == 1 and y == 0 then return ".....O.OO.O....." end
  if (style == 2 or style == 7) and y >= 4 and y <= 7 then
    return row:gsub("^(...)O", "%1H"):gsub("O(...)$", "H%1")
  end
  if style == 4 and y == 4 then return row:gsub("SSSSSS", "HSSSSH") end
  if style == 7 and y == 0 then return "....OOOOOOOO...." end
  return row
end

-- pixel color for a template char at (x,y) under a look; returns "b","w" or nil
local function patColor(p, x, y)
  if p == 0 then return "w" end               -- white
  if p == 1 then return "b" end               -- black
  if p == 2 then return (y % 2 == 0) and "b" or "w" end          -- stripes
  if p == 3 then return ((x // 2 + y // 2) % 2 == 0) and "b" or "w" end -- flannel check
  if p == 4 then return ((x + y) % 2 == 0) and "b" or "w" end    -- 50% dither
  if p == 5 then return (x % 3 == 0 and y % 3 == 0) and "b" or "w" end -- dots
  return "w"
end

local function color(ch, x, y, lk)
  if ch == "." then return nil end
  if ch == "O" or ch == "B" then return "b" end
  if ch == "W" then return "w" end
  if ch == "E" then return "b" end
  if ch == "S" then
    if lk.skin == 0 then return "w" end
    if lk.skin == 1 then return ((x + y) % 4 == 0) and "b" or "w" end
    return ((x + y) % 2 == 0) and "b" or "w"
  end
  if ch == "H" then
    local hc = lk.hc or 0
    if hc == 0 then return "b" end
    if hc == 1 then return ((x + y) % 2 == 0) and "b" or "w" end
    if hc == 2 then return ((x + y) % 4 == 0) and "b" or "w" end
    return (x % 3 == 0) and "b" or "w"
  end
  if ch == "T" then
    if lk.uniform == "sec" then return (x == 7 and y == 11) and "w" or "b" end
    if lk.uniform == "maint" then return ((x + y) % 2 == 0) and "b" or "w" end
    return patColor(lk.shirt or 0, x, y)
  end
  if ch == "P" then
    local p = lk.pants or 0
    if p == 0 then return "b" end
    if p == 1 then return ((x + y) % 2 == 0) and "b" or "w" end
    return "w"
  end
  return "b"
end

local cache = {}
local cacheN = 0

local function build(lk, dir, frame)
  local img = gfx.image.new(SW, SH, gfx.kColorClear)
  local rows = {}
  local side = dir == "left" or dir == "right"
  local head = dir == "up" and HEAD_UP or (side and HEAD_SIDE or HEAD_DOWN)
  for y = 1, #head do rows[#rows + 1] = hairRow(lk.hair or 0, dir, y - 1, head[y]) end
  local body = side and BODY_SIDE or BODY_DOWN
  for y = 1, #body do rows[#rows + 1] = body[y] end
  local legs = (side and LEGS.side or LEGS.down)[frame + 1]
  for y = 1, #legs do rows[#rows + 1] = legs[y] end
  -- accessories
  if lk.acc == 1 and dir ~= "up" then -- glasses
    local r = rows[6]
    rows[6] = side and r:gsub("SSSES", "SOOOO") or "...OSOOSOOOSO..."
  elseif lk.acc == 2 then -- cap
    rows[1] = "....OOOOOOOO...."
    rows[2] = dir == "down" and "...OOOOOOOOOOO.." or rows[2]
  elseif lk.acc == 3 and dir ~= "up" then -- headphones
    rows[5] = rows[5]:gsub("^(...)O", "%1B"):gsub("O(...)$", "B%1")
  elseif lk.acc == 4 then -- beanie
    rows[2] = "....OOOOOOOO...."; rows[3] = "...OOOOOOOOOO..."
  end
  gfx.pushContext(img)
  for y, row in ipairs(rows) do
    local x = 1
    local len = #row
    while x <= len do
      local c = color(row:sub(x, x), x - 1, y - 1, lk)
      if c then
        local x2 = x
        while x2 < len and color(row:sub(x2 + 1, x2 + 1), x2, y - 1, lk) == c do x2 = x2 + 1 end
        gfx.setColor(c == "b" and gfx.kColorBlack or gfx.kColorWhite)
        gfx.fillRect(x - 1, y - 1, x2 - x + 1, 1)
        x = x2 + 1
      else
        x = x + 1
      end
    end
  end
  gfx.popContext()
  return img
end

local function key(lk, dir, frame)
  return table.concat({ lk.hair or 0, lk.hc or 0, lk.shirt or 0, lk.pants or 0, lk.skin or 0, lk.acc or 0,
    lk.uniform or "", dir == "right" and "left" or dir, frame }, ",")
end

-- draw a character centered at feet position (x,y)
function Sprites.draw(lk, x, y, dir, frame)
  dir = dir or "down"
  frame = frame or 0
  local k = key(lk, dir, frame)
  local img = cache[k]
  if not img then
    if cacheN > 400 then cache = {}; cacheN = 0 end
    img = build(lk, dir == "right" and "left" or dir, frame)
    cache[k] = img
    cacheN = cacheN + 1
  end
  -- drop shadow
  gfx.setPattern(Gfx.P.gray)
  gfx.fillEllipseInRect(x - 6, y - 3, 12, 5)
  gfx.setColor(gfx.kColorBlack)
  img:draw(math.floor(x - SW / 2), math.floor(y - SH + 1), dir == "right" and gfx.kImageFlippedX or gfx.kImageUnflipped)
end

-- ------------------------------------------------------------------ portraits
local pcache = {}
local pcount = 0

local function skinPat(skin)
  if skin == 0 then return Gfx.P.white end
  if skin == 1 then return Gfx.P.lighter end
  return Gfx.P.light
end
local function hairPat(hc)
  if hc == 0 then return Gfx.P.black end
  if hc == 1 then return Gfx.P.dark end
  if hc == 2 then return Gfx.P.gray end
  return Gfx.P.lighter
end

-- mood: "happy" | "neutral" | "sad" | "angry" | "shy"
function Sprites.portrait(n, mood, x, y)
  mood = mood or "neutral"
  local lk = n.look or {}
  local k = tostring(n.id or "p") .. mood .. (lk.hair or 0) .. (lk.hc or 0) .. (lk.acc or 0)
  local img = pcache[k]
  if not img then
    if pcount > 40 then pcache = {}; pcount = 0 end
    img = gfx.image.new(48, 48, gfx.kColorWhite)
    local r = U.rng(n.id or 0, "face")
    gfx.pushContext(img)
    -- background: a little mall-y dither
    gfx.setPattern(Gfx.P.dots); gfx.fillRect(0, 0, 48, 48)
    -- shoulders / shirt
    gfx.setPattern(lk.uniform == "sec" and Gfx.P.black or (({ Gfx.P.white, Gfx.P.black, Gfx.P.hstripe, Gfx.P.plaid, Gfx.P.gray, Gfx.P.dots })[(lk.shirt or 0) + 1]))
    gfx.fillRoundRect(6, 38, 36, 14, 6)
    gfx.setColor(gfx.kColorBlack); gfx.drawRoundRect(6, 38, 36, 14, 6)
    -- back hair (long styles)
    local hs = lk.hair or 0
    gfx.setPattern(hairPat(lk.hc or 0))
    if hs == 2 or hs == 7 then gfx.fillRoundRect(9, 10, 30, 32, 8) end
    if hs == 3 then gfx.fillRect(34, 16, 6, 18) end
    -- face
    local fw = 22 + r:i(0, 4)
    local fx = 24 - fw // 2
    gfx.setPattern(skinPat(lk.skin or 0))
    gfx.fillEllipseInRect(fx, 11, fw, 27)
    gfx.setColor(gfx.kColorBlack); gfx.drawEllipseInRect(fx, 11, fw, 27)
    -- neck
    gfx.setPattern(skinPat(lk.skin or 0)); gfx.fillRect(20, 35, 8, 5)
    gfx.setColor(gfx.kColorBlack); gfx.drawLine(20, 35, 20, 39); gfx.drawLine(27, 35, 27, 39)
    -- hair top
    gfx.setPattern(hairPat(lk.hc or 0))
    if hs == 5 then gfx.fillRect(fx + 2, 10, fw - 4, 4)
    elseif hs == 1 then
      for i = 0, 4 do gfx.fillTriangle(fx + i * 5, 16, fx + i * 5 + 5, 16, fx + i * 5 + 2, 5) end
      gfx.fillRect(fx, 12, fw, 5)
    elseif hs == 6 then gfx.fillEllipseInRect(18, 2, 12, 10); gfx.fillEllipseInRect(fx, 9, fw, 10)
    elseif hs == 4 then gfx.fillEllipseInRect(fx - 1, 8, fw + 2, 12); gfx.fillRect(fx - 1, 14, 5, 10); gfx.fillRect(fx + fw - 4, 14, 5, 10)
    elseif hs == 7 then gfx.fillEllipseInRect(fx - 5, 3, fw + 10, 18)
    else gfx.fillEllipseInRect(fx - 1, 8, fw + 2, 12) end
    gfx.setColor(gfx.kColorBlack)
    -- eyes
    local ey = 21 + r:i(0, 2)
    local blink = mood == "shy"
    if blink then
      gfx.drawLine(17, ey + 1, 20, ey + 1); gfx.drawLine(27, ey + 1, 30, ey + 1)
    else
      gfx.fillRect(18, ey, 3, 3); gfx.fillRect(27, ey, 3, 3)
      gfx.setColor(gfx.kColorWhite); gfx.drawPixel(18, ey); gfx.drawPixel(27, ey); gfx.setColor(gfx.kColorBlack)
    end
    -- brows
    if mood == "angry" then gfx.drawLine(16, ey - 4, 21, ey - 2); gfx.drawLine(26, ey - 2, 31, ey - 4)
    elseif mood == "sad" then gfx.drawLine(16, ey - 2, 21, ey - 4); gfx.drawLine(26, ey - 4, 31, ey - 2)
    else gfx.drawLine(16, ey - 3, 21, ey - 3); gfx.drawLine(26, ey - 3, 31, ey - 3) end
    -- nose
    gfx.drawLine(24, ey + 3, 23, ey + 6); gfx.drawLine(23, ey + 6, 25, ey + 6)
    -- mouth
    local my = ey + 10
    if mood == "happy" then gfx.drawArc(24, my - 3, 5, 100, 260)
    elseif mood == "sad" or mood == "angry" then gfx.drawArc(24, my + 3, 4, 290, 70)
    elseif mood == "shy" then gfx.drawLine(22, my, 26, my)
    else gfx.drawLine(21, my, 27, my) end
    if mood == "shy" then gfx.setPattern(Gfx.P.gray); gfx.fillRect(14, ey + 5, 4, 2); gfx.fillRect(30, ey + 5, 4, 2); gfx.setColor(gfx.kColorBlack) end
    -- accessories
    if lk.acc == 1 then gfx.drawRect(15, ey - 2, 8, 7); gfx.drawRect(25, ey - 2, 8, 7); gfx.drawLine(23, ey, 25, ey) end
    if lk.acc == 2 then gfx.fillRect(fx - 2, 8, fw + 4, 6); gfx.fillRect(fx + fw - 4, 12, 10, 3) end
    if lk.acc == 3 then gfx.fillRect(fx - 4, 18, 5, 9); gfx.fillRect(fx + fw - 1, 18, 5, 9); gfx.drawArc(24, 20, fw // 2 + 3, 270, 90) end
    if lk.acc == 4 then gfx.fillRect(fx - 1, 6, fw + 2, 9) end
    if lk.uniform == "sec" then gfx.setColor(gfx.kColorWhite); gfx.fillRect(30, 42, 5, 5); gfx.setColor(gfx.kColorBlack) end
    if (n.age or 30) > 55 then gfx.drawLine(15, ey + 7, 17, ey + 9); gfx.drawLine(33, ey + 7, 31, ey + 9) end
    gfx.popContext()
    pcache[k] = img
    pcount = pcount + 1
  end
  -- double border frame
  Gfx.fill(x - 4, y - 4, 56, 56, "black")
  gfx.setColor(gfx.kColorWhite); gfx.drawRect(x - 2, y - 2, 52, 52); gfx.setColor(gfx.kColorBlack)
  img:draw(x, y)
end

function Sprites.moodOf(n)
  local p = n.p or {}
  if (p.an or 0) > 40 then return "angry" end
  if (p.a or 0) > 50 then return "shy" end
  if (n.mood or 50) < 30 then return "sad" end
  if (p.f or 0) > 30 or (n.mood or 50) > 70 then return "happy" end
  return "neutral"
end
