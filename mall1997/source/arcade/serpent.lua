-- NEON SERPENT: arcade cabinet snake. D-pad steers, pellets grow you,
-- the neon bonus pellet flickers for a few seconds, walls and your own
-- tail kill. Speed ramps every few pellets.

local gfx = playdate.graphics
local W, H = 400, 240
local TILE = 10
local COLS, ROWS = 38, 20
local OX, OY = 10, 32 -- playfield occupies 10..390 x 32..232

-- ---------------------------------------------------------------- cabinet
-- 3x5 chunky digits; each "pixel" is s wide and s-1 tall so the gaps read
-- as CRT scanlines.
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

-- bezel + a slow rolling dim band, drawn last
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
local function key(x, y) return y * COLS + x end

local function freeCell(st)
  local r = st.rng
  for _ = 1, 60 do
    local x, y = r:i(0, COLS - 1), r:i(0, ROWS - 1)
    local k = key(x, y)
    if not st.occ[k] and not (st.pellet and st.pellet.k == k) and not (st.bonus and st.bonus.k == k) then
      return { x = x, y = y, k = k }
    end
  end
  for y = 0, ROWS - 1 do
    for x = 0, COLS - 1 do
      local k = key(x, y)
      if not st.occ[k] then return { x = x, y = y, k = k } end
    end
  end
  return nil
end

local function level(st) return st.eaten // 5 end

local function new(ctx)
  local st = {
    rng = ctx.rng, t = 0, phase = "ready", overT = 0, finished = false,
    body = {}, hi = 0, ti = 1, occ = {}, len = 0,
    dx = 1, dy = 0, queue = {}, grow = 2, tick = 0, delay = 7,
    score = 0, eaten = 0, pellet = nil, bonus = nil, popT = 0, popX = 0, popY = 0,
  }
  for i = 0, 3 do
    local k = key(6 + i, ROWS // 2)
    st.hi = st.hi + 1
    st.body[st.hi] = k
    st.occ[k] = true
  end
  st.len = 4
  st.pellet = freeCell(st)
  return st
end

local function die(st)
  st.phase = "over"
  st.overT = 0
  Sfx.bad()
end

local function step(st)
  if #st.queue > 0 then
    local d = table.remove(st.queue, 1)
    st.dx, st.dy = d[1], d[2]
  end
  local hk = st.body[st.hi]
  local hx, hy = hk % COLS, hk // COLS
  local nx, ny = hx + st.dx, hy + st.dy
  if nx < 0 or ny < 0 or nx >= COLS or ny >= ROWS then die(st) return end
  local nk = key(nx, ny)
  -- tail moves out of the way unless we are growing
  if st.grow > 0 then
    st.grow = st.grow - 1
    st.len = st.len + 1
  else
    local tk = st.body[st.ti]
    st.body[st.ti] = nil
    st.ti = st.ti + 1
    st.occ[tk] = nil
  end
  if st.occ[nk] then die(st) return end
  st.hi = st.hi + 1
  st.body[st.hi] = nk
  st.occ[nk] = true

  if st.pellet and st.pellet.k == nk then
    st.eaten = st.eaten + 1
    st.score = st.score + 10 + 5 * level(st)
    st.grow = st.grow + 2
    st.delay = math.max(2, 7 - st.eaten // 6)
    st.popT, st.popX, st.popY = 12, nx, ny
    Sfx.blip(660 + 20 * (st.eaten % 12), 0.04)
    st.pellet = freeCell(st)
    if not st.bonus and st.eaten >= 3 and st.rng:chance(0.3) then
      local c = freeCell(st)
      if c then c.life = 150; st.bonus = c end
    end
    if not st.pellet then die(st) end -- filled the board (!)
  elseif st.bonus and st.bonus.k == nk then
    st.score = st.score + 50 + 10 * level(st)
    st.grow = st.grow + 4
    st.popT, st.popX, st.popY = 20, nx, ny
    st.bonus = nil
    Sfx.blip(1320, 0.1)
  end
end

local function pushDir(st, dx, dy)
  if #st.queue >= 2 then return end
  local last = st.queue[#st.queue]
  local lx, ly = st.dx, st.dy
  if last then lx, ly = last[1], last[2] end
  if (dx == lx and dy == ly) or (dx == -lx and dy == -ly) then return end
  st.queue[#st.queue + 1] = { dx, dy }
end

local function update(st)
  st.t = st.t + 1
  if st.phase == "over" then
    st.overT = st.overT + 1
    if st.overT >= 80 or (st.overT > 30 and In.a) then st.finished = true end
    return
  end
  if In.up then pushDir(st, 0, -1)
  elseif In.down then pushDir(st, 0, 1)
  elseif In.left then pushDir(st, -1, 0)
  elseif In.right then pushDir(st, 1, 0) end
  if st.phase == "ready" then
    if st.t >= 40 or In.a or #st.queue > 0 then st.phase = "play" end
    return
  end
  if st.popT > 0 then st.popT = st.popT - 1 end
  if st.bonus then
    st.bonus.life = st.bonus.life - 1
    if st.bonus.life <= 0 then st.bonus = nil end
  end
  st.tick = st.tick + 1
  if st.tick >= st.delay then
    st.tick = 0
    step(st)
  end
end

local NEON = {
  { 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55 },
  { 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA },
  { 0xFF, 0x99, 0xFF, 0x66, 0xFF, 0x99, 0xFF, 0x66 },
}

local function draw(st)
  gfx.clear(gfx.kColorBlack)
  -- HUD
  Gfx.text("NEON SERPENT", 14, 8, { white = true, bold = true })
  Gfx.text("LEN " .. st.len, 140, 8, { white = true })
  bigNum(st.score, 386, 6, 4, "right")
  -- playfield frame (dotted grid corners give a neon-tube feel)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawRect(OX - 3, OY - 3, COLS * TILE + 6, ROWS * TILE + 6)
  gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
  gfx.drawRect(OX - 1, OY - 1, COLS * TILE + 2, ROWS * TILE + 2)
  gfx.setColor(gfx.kColorWhite)

  -- pellet (pulsing dot)
  local p = st.pellet
  if p then
    local r = 2 + ((st.t // 6) % 2)
    gfx.fillCircleAtPoint(OX + p.x * TILE + 5, OY + p.y * TILE + 5, r)
  end
  -- neon bonus pellet: buzzing dither diamond, blinks when about to expire
  local b = st.bonus
  if b and (b.life > 40 or (st.t // 3) % 2 == 0) then
    local bx, by = OX + b.x * TILE, OY + b.y * TILE
    gfx.setPattern(NEON[1 + (st.t // 3) % #NEON])
    gfx.fillRect(bx - 1, by - 1, TILE + 2, TILE + 2)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawRect(bx - 3, by - 3, TILE + 6, TILE + 6)
  end

  -- snake body; flashes on death
  local dead = st.phase == "over"
  if not dead or (st.overT < 24 and (st.overT // 3) % 2 == 0) or st.overT >= 24 then
    for i = st.ti, st.hi do
      local k = st.body[i]
      local x, y = OX + (k % COLS) * TILE, OY + (k // COLS) * TILE
      if i == st.hi then
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(x, y, TILE, TILE)
        gfx.setColor(gfx.kColorBlack)
        -- eyes look the way we're heading
        local ex, ey = 5 + st.dx * 2, 5 + st.dy * 2
        if st.dx ~= 0 then
          gfx.fillRect(x + ex - 1, y + 2, 2, 2); gfx.fillRect(x + ex - 1, y + 6, 2, 2)
        else
          gfx.fillRect(x + 2, y + ey - 1, 2, 2); gfx.fillRect(x + 6, y + ey - 1, 2, 2)
        end
      else
        if (st.hi - i) % 4 == 3 then
          gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
        else
          gfx.setColor(gfx.kColorWhite)
        end
        gfx.fillRect(x + 1, y + 1, TILE - 2, TILE - 2)
      end
    end
  end
  gfx.setColor(gfx.kColorWhite)
  -- eat pop ring
  if st.popT > 0 then
    gfx.drawCircleAtPoint(OX + st.popX * TILE + 5, OY + st.popY * TILE + 5, 18 - st.popT)
  end
  gfx.setColor(gfx.kColorBlack)

  if st.phase == "ready" then
    gfx.fillRect(120, 100, 160, 40)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawRect(122, 102, 156, 36)
    gfx.setColor(gfx.kColorBlack)
    local s = ((st.t // 8) % 2 == 0) and "CREDIT 1  -  1UP" or "PLAYER 1 READY!"
    Gfx.text(s, 200, 112, { white = true, bold = true, align = "center" })
  elseif dead and st.overT >= 24 then
    gameOverBox(st, st.score)
  end
  crt(st.t)
end

local function done(st) return st.finished end
local function score(st) return math.floor(st.score) end

-- NPC run: pellet by pellet; each pellet risks a crash that grows with
-- speed and snake length and shrinks with skill.
local function npcScore(rng, skill)
  skill = U.clamp(skill or 0.5, 0, 1)
  local sc, eaten, bonusOn = 0, 0, false
  local focus = 0.75 + 0.5 * rng:f() -- good day / bad day
  while true do
    local lvl = eaten // 5
    local speed = math.max(2, 7 - eaten // 6)
    local risk = (0.055 + 0.008 * (7 - speed) + eaten * 0.003) * (1 - 0.85 * skill) / focus
    if rng:chance(risk) then break end
    eaten = eaten + 1
    sc = sc + 10 + 5 * ((eaten) // 5)
    if eaten >= 3 and rng:chance(0.3) then bonusOn = true end
    if bonusOn and rng:chance(0.35 + 0.5 * skill) then sc = sc + 50 + 10 * lvl; bonusOn = false
    elseif bonusOn and rng:chance(0.3) then bonusOn = false end
    if eaten > 700 then break end
  end
  return math.floor(sc)
end

ArcadeGames.register("serpent", {
  name = "NEON SERPENT",
  new = new, update = update, draw = draw, done = done, score = score, npcScore = npcScore,
})
