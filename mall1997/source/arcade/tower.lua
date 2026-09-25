-- BLOCK TOWER: a slab slides back and forth above the stack; A drops it.
-- Whatever hangs past the slab below is sliced off and tumbles away. Land
-- within a couple of pixels for a PERFECT (bonus, and a streak of three
-- widens the slab again). The slab speeds up as the tower rises; miss the
-- stack entirely and it's over.

local gfx = playdate.graphics
local W, H = 400, 240
local SH = 12          -- slab height
local GROUND = 228     -- screen y of the base platform's bottom at cam 0
local MINX, MAXX = 12, 388
local START_W = 150

-- ---------------------------------------------------------------- cabinet
local DIG = {
  [48] = "111101101101111", [49] = "010110010010111", [50] = "111001111100111",
  [51] = "111001111001111", [52] = "101101111001001", [53] = "111100111001111",
  [54] = "111100111101111", [55] = "111001001001001", [56] = "111101111101111",
  [57] = "111101111001111",
}
local function bigNum(n, x, y, s, align)
  local str = tostring(math.floor(n))
  local w = #str * 4 * s - s
  if align == "right" then x = x - w elseif align == "center" then x = x - w // 2 end
  gfx.setColor(gfx.kColorWhite)
  for i = 1, #str do
    local d = DIG[str:byte(i)]
    if d then
      local bx = x + (i - 1) * 4 * s
      for p = 0, 14 do
        if d:byte(p + 1) == 49 then gfx.fillRect(bx + (p % 3) * s, y + (p // 3) * s, s, s - 1) end
      end
    end
  end
  gfx.setColor(gfx.kColorBlack)
end

local function crt(t)
  gfx.setColor(gfx.kColorBlack)
  gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer4x4)
  gfx.fillRect(0, (t * 2) % (H + 40) - 20, W, 10)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawRoundRect(0, 0, W, H, 12)
  gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
  gfx.drawRoundRect(2, 2, W - 4, H - 4, 10)
  gfx.setColor(gfx.kColorBlack)
end

local function gameOverBox(st, score)
  local x, y, w, h = 110, 68, 180, 104
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(x, y, w, h)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawRect(x + 2, y + 2, w - 4, h - 4)
  gfx.drawRect(x + 5, y + 5, w - 10, h - 10)
  gfx.setColor(gfx.kColorBlack)
  Gfx.text("GAME OVER", 200, y + 12, { white = true, bold = true, align = "center" })
  bigNum(score, 200, y + 38, 5, "center")
  if (st.t // 10) % 2 == 0 then Gfx.text("PRESS A", 200, y + 76, { white = true, align = "center" }) end
end

-- ---------------------------------------------------------------- game
local function speedFor(floors) return math.min(7.5, 2 + floors * 0.13) end

local function newSlab(st)
  local top = st.stack[#st.stack]
  local w = top.w
  local fromLeft = (#st.stack % 2) == 0
  st.slab = { x = fromLeft and MINX or (MAXX - w), w = w, dir = fromLeft and 1 or -1 }
end

local function new(ctx)
  local st = {
    rng = ctx.rng, t = 0, phase = "ready", overT = 0, finished = false,
    stack = { { x = 200 - START_W // 2, w = START_W } },
    falling = {}, score = 0, streak = 0, cam = 0, msg = nil, msgT = 0,
    skyline = {},
  }
  local x = 0
  while x < W do
    local bw = ctx.rng:i(14, 34)
    st.skyline[#st.skyline + 1] = { x, bw, ctx.rng:i(20, 70) }
    x = x + bw + ctx.rng:i(0, 4)
  end
  newSlab(st)
  return st
end

local function floors(st) return #st.stack - 1 end

-- screen y of the top edge of stack level i (level 1 = base platform)
local function levelY(st, i) return GROUND - i * SH + st.cam end

local function drop(st)
  local s, top = st.slab, st.stack[#st.stack]
  local lvl = #st.stack + 1
  local left = math.max(s.x, top.x)
  local right = math.min(s.x + s.w, top.x + top.w)
  if right - left <= 0 then
    st.falling[#st.falling + 1] = { x = s.x, w = s.w, y = levelY(st, lvl) - st.cam, vy = 0, vx = s.dir }
    st.slab = nil
    st.phase = "over"
    st.overT = 0
    Sfx.bad()
    return
  end
  if math.abs(s.x - top.x) <= 2 then
    st.streak = st.streak + 1
    local w = top.w
    if st.streak >= 3 then w = math.min(START_W, w + 6) end
    st.stack[#st.stack + 1] = { x = top.x - (w - top.w) // 2, w = w, perfect = 10 }
    st.score = st.score + 10 + 15 * math.min(st.streak, 6)
    st.msg, st.msgT = "PERFECT x" .. st.streak, 30
    Sfx.blip(880 + 110 * math.min(st.streak, 8), 0.06)
  else
    st.streak = 0
    -- the overhang tumbles off
    local ov
    if s.x < left then ov = { x = s.x, w = left - s.x, vx = -1 }
    else ov = { x = right, w = (s.x + s.w) - right, vx = 1 } end
    ov.y, ov.vy = levelY(st, lvl) - st.cam, 0
    if ov.w > 0 then st.falling[#st.falling + 1] = ov end
    st.stack[#st.stack + 1] = { x = left, w = right - left }
    st.score = st.score + 10
    Sfx.blip(440, 0.04)
  end
  newSlab(st)
end

local function update(st)
  st.t = st.t + 1
  -- camera keeps the working level around y = 100
  local want = math.max(0, (#st.stack + 1) * SH - 128)
  st.cam = st.cam + (want - st.cam) * 0.15
  if st.msgT > 0 then st.msgT = st.msgT - 1 end
  for i = #st.falling, 1, -1 do
    local f = st.falling[i]
    f.vy = f.vy + 0.5
    f.y = f.y + f.vy     -- screen y at cam 0 (top edge)
    f.x = f.x + f.vx
    if f.y + st.cam > H + 20 then table.remove(st.falling, i) end
  end
  for i = 1, #st.stack do
    local b = st.stack[i]
    if b.perfect and b.perfect > 0 then b.perfect = b.perfect - 1 end
  end
  if st.phase == "over" then
    st.overT = st.overT + 1
    if st.overT >= 80 or (st.overT > 30 and In.a) then st.finished = true end
    return
  end
  if st.phase == "ready" then
    if st.t >= 30 then st.phase = "play" end
    return
  end
  local s = st.slab
  local v = speedFor(floors(st))
  s.x = s.x + s.dir * v
  if s.x <= MINX then s.x = MINX; s.dir = 1 end
  if s.x + s.w >= MAXX then s.x = MAXX - s.w; s.dir = -1 end
  if In.a then drop(st) end
end

local function drawSlab(x, y, w, style)
  x, y = math.floor(x), math.floor(y)
  if style == "solid" then
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(x, y, w, SH)
  else
    gfx.setColor(gfx.kColorWhite)
    gfx.setDitherPattern(style == "a" and 0.25 or 0.5, gfx.image.kDitherTypeBayer4x4)
    gfx.fillRect(x, y, w, SH)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawRect(x, y, w, SH)
  end
  gfx.setColor(gfx.kColorBlack)
  gfx.drawLine(x, y + SH - 1, x + w - 1, y + SH - 1)
  -- window lights
  if w > 12 then
    for wx = x + 4, x + w - 6, 8 do gfx.fillRect(wx, y + 4, 3, 3) end
  end
end

local function draw(st)
  gfx.clear(gfx.kColorBlack)
  local cam = st.cam
  -- stars appear as you climb
  gfx.setColor(gfx.kColorWhite)
  for i = 1, 24 do
    local sx = (i * 97) % 380 + 10
    local sy = (i * 53 + math.floor(cam * 0.3)) % 220 + 10
    if (st.t // 20 + i) % 7 ~= 0 and cam > 20 then gfx.fillRect(sx, sy, 1, 1) end
  end
  -- mall skyline (parallax), fading behind a dither
  local base = GROUND + math.floor(cam * 0.5)
  if base - 70 < H then
    gfx.setColor(gfx.kColorWhite)
    gfx.setDitherPattern(0.8, gfx.image.kDitherTypeBayer4x4)
    for i = 1, #st.skyline do
      local b = st.skyline[i]
      gfx.fillRect(b[1], base - b[3], b[2], b[3])
    end
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(0, base, W, 2)
  end

  -- stack (only visible levels)
  for i = #st.stack, 1, -1 do
    local y = levelY(st, i)
    if y > H then break end
    if y > -SH then
      local b = st.stack[i]
      local style = (i == 1) and "solid" or ((i % 2 == 0) and "a" or "b")
      if b.perfect and b.perfect > 0 and b.perfect % 4 < 2 then style = "solid" end
      drawSlab(b.x, y, b.w, style)
    end
  end
  -- falling pieces
  for i = 1, #st.falling do
    local f = st.falling[i]
    drawSlab(f.x, f.y + cam, f.w, "b")
  end
  -- the moving slab, with a drop guide
  if st.slab and st.phase ~= "over" then
    local y = levelY(st, #st.stack + 1)
    drawSlab(st.slab.x, y, st.slab.w, "solid")
    gfx.setColor(gfx.kColorWhite)
    gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
    gfx.drawLine(st.slab.x, y + SH, st.slab.x, y + SH + 6)
    gfx.drawLine(st.slab.x + st.slab.w - 1, y + SH, st.slab.x + st.slab.w - 1, y + SH + 6)
  end
  gfx.setColor(gfx.kColorBlack)

  -- HUD
  gfx.fillRect(0, 0, W, 30)
  Gfx.text("BLOCK TOWER", 14, 4, { white = true, bold = true })
  Gfx.text("FLOOR " .. floors(st), 14, 14 + 2, { white = true })
  bigNum(st.score, 386, 5, 4, "right")
  gfx.setColor(gfx.kColorWhite)
  gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
  gfx.drawLine(0, 30, W, 30)
  gfx.setColor(gfx.kColorBlack)
  if st.msgT > 0 and (st.msgT // 3) % 2 == 0 then
    Gfx.text(st.msg, 200, 40, { white = true, bold = true, align = "center" })
  end

  if st.phase == "ready" then
    Gfx.text(((st.t // 8) % 2 == 0) and "CREDIT 1  -  1UP" or "A TO DROP", 200, 40,
      { white = true, bold = true, align = "center" })
  elseif st.phase == "over" and st.overT >= 20 then
    gameOverBox(st, st.score)
  end
  crt(st.t)
end

local function done(st) return st.finished end
local function score(st) return math.floor(st.score) end

-- NPC run: every drop lands with a timing error that grows with slab speed
-- and shrinks with skill; the error is shaved off the slab width.
local function npcScore(rng, skill)
  skill = U.clamp(skill or 0.5, 0, 1)
  local focus = 0.75 + 1.0 * rng:f() ^ 4
  local w, fl, streak, sc = START_W, 0, 0, 0
  while fl < 2000 do
    local v = speedFor(fl)
    -- approx. normal error from the sum of three uniforms
    local g = (rng:f() + rng:f() + rng:f() - 1.5) * 2
    local e = math.abs(g) * v * (3.4 - 2.7 * skill) * (1 + fl / 120) / focus
    if e >= w then break end
    fl = fl + 1
    if e <= 2 then
      streak = streak + 1
      if streak >= 3 then w = math.min(START_W, w + 6) end
      sc = sc + 10 + 15 * math.min(streak, 6)
    else
      streak = 0
      w = w - e
      sc = sc + 10
    end
  end
  return math.floor(sc)
end

ArcadeGames.register("tower", {
  name = "BLOCK TOWER",
  new = new, update = update, draw = draw, done = done, score = score, npcScore = npcScore,
})
