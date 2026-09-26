-- ORBITAL DEFENSE: the moon base sits at screen center; the CRANK swings
-- the turret around it (D-pad left/right also rotate, for docked cranks),
-- A fires. Meteors, big meteors and spiralling UFOs close in from the
-- edges, faster and more often as time goes on. Three base hits and the
-- colony is dust.

local gfx = playdate.graphics
local W, H = 400, 240
local CX, CY = 200, 134
local BASE_R = 14
local SPAWN_D = 250

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
local KINDS = {
  rock = { r = 5, hp = 1, pts = 10, spd = 1.0 },
  big = { r = 9, hp = 2, pts = 25, spd = 0.7 },
  ufo = { r = 7, hp = 1, pts = 50, spd = 0.8 },
}

local function new(ctx)
  local st = {
    rng = ctx.rng, t = 0, phase = "ready", overT = 0, finished = false,
    ang = -90, cool = 0, shots = {}, foes = {}, parts = {},
    hits = 0, score = 0, play = 0, spawnT = 40, shake = 0, flash = 0, kills = 0,
    stars = {},
  }
  for i = 1, 36 do
    st.stars[i] = { ctx.rng:i(6, W - 6), ctx.rng:i(30, H - 6), ctx.rng:i(0, 60) }
  end
  return st
end

local function boom(st, x, y, n)
  local r = st.rng
  for _ = 1, n do
    if #st.parts >= 48 then break end
    local a = r:f() * math.pi * 2
    local v = r:range(0.8, 3.2)
    st.parts[#st.parts + 1] = { x = x, y = y, vx = math.cos(a) * v, vy = math.sin(a) * v, life = r:i(8, 20) }
  end
end

local function spawn(st)
  local r = st.rng
  local secs = st.play / 30
  local kind = "rock"
  local roll = r:f()
  if secs > 20 and roll < math.min(0.22, 0.08 + secs / 600) then kind = "ufo"
  elseif secs > 8 and roll < 0.45 then kind = "big" end
  local k = KINDS[kind]
  local f = {
    kind = kind, r = k.r, hp = k.hp, pts = k.pts,
    a = r:f() * 360, d = SPAWN_D,
    v = k.spd * (0.55 + secs * 0.012) * r:range(0.85, 1.2),
    spin = 0, wob = r:f() * 6,
  }
  if kind == "ufo" then f.spin = (r:chance(0.5) and 1 or -1) * r:range(0.6, 1.2) end
  st.foes[#st.foes + 1] = f
end

local function pos(f)
  local rad = math.rad(f.a)
  return CX + math.cos(rad) * f.d, CY + math.sin(rad) * f.d
end

local function update(st)
  st.t = st.t + 1
  if st.flash > 0 then st.flash = st.flash - 1 end
  if st.shake > 0 then st.shake = st.shake - 1 end
  -- particles keep drifting even after game over
  for i = #st.parts, 1, -1 do
    local p = st.parts[i]
    p.x, p.y, p.life = p.x + p.vx, p.y + p.vy, p.life - 1
    if p.life <= 0 then table.remove(st.parts, i) end
  end
  if st.phase == "over" then
    st.overT = st.overT + 1
    if st.overT >= 80 or (st.overT > 30 and In.a) then st.finished = true end
    return
  end

  -- aim: crank is 1:1 with the turret; D-pad as fallback
  st.ang = st.ang + (In.crank or 0)
  if In.lh then st.ang = st.ang - 5 end
  if In.rh then st.ang = st.ang + 5 end
  st.ang = st.ang % 360

  if st.phase == "ready" then
    if st.t >= 40 or In.a then st.phase = "play" end
    return
  end
  st.play = st.play + 1

  -- fire
  if st.cool > 0 then st.cool = st.cool - 1 end
  if In.a and st.cool == 0 and #st.shots < 5 then
    local rad = math.rad(st.ang)
    local cx, cy = math.cos(rad), math.sin(rad)
    st.shots[#st.shots + 1] = { x = CX + cx * 24, y = CY + cy * 24, vx = cx * 7, vy = cy * 7 }
    st.cool = 5
    Sfx.blip(1000, 0.02)
  end

  -- spawn
  st.spawnT = st.spawnT - 1
  if st.spawnT <= 0 then
    spawn(st)
    local secs = st.play / 30
    st.spawnT = math.max(12, math.floor(64 - secs * 0.9)) + st.rng:i(0, 16)
  end

  -- shots
  for i = #st.shots, 1, -1 do
    local s = st.shots[i]
    s.x, s.y = s.x + s.vx, s.y + s.vy
    local hit = false
    for j = #st.foes, 1, -1 do
      local f = st.foes[j]
      local fx, fy = pos(f)
      local dx, dy = fx - s.x, fy - s.y
      if dx * dx + dy * dy <= (f.r + 3) * (f.r + 3) then
        hit = true
        f.hp = f.hp - 1
        if f.hp <= 0 then
          st.score = st.score + f.pts
          st.kills = st.kills + 1
          boom(st, fx, fy, f.kind == "rock" and 6 or 10)
          table.remove(st.foes, j)
          Sfx.blip(f.kind == "ufo" and 1400 or 520, 0.05)
        else
          f.d = f.d + 6 -- knocked back
          boom(st, fx, fy, 3)
        end
        break
      end
    end
    if hit or s.x < -10 or s.x > W + 10 or s.y < -10 or s.y > H + 10 then table.remove(st.shots, i) end
  end

  -- foes close in
  for j = #st.foes, 1, -1 do
    local f = st.foes[j]
    f.d = f.d - f.v
    if f.kind == "ufo" then
      f.a = f.a + f.spin * (120 / math.max(40, f.d))
    else
      f.a = f.a + math.sin((st.t + f.wob * 10) / 20) * 0.15
    end
    if f.d <= BASE_R + f.r then
      local fx, fy = pos(f)
      boom(st, fx, fy, 14)
      table.remove(st.foes, j)
      st.hits = st.hits + 1
      st.shake, st.flash = 12, 4
      Sfx.bad()
      if st.hits >= 3 then
        st.phase = "over"
        st.overT = 0
        boom(st, CX, CY, 30)
        st.foes = {}
        return
      end
    end
  end
end

local function drawFoe(f, t)
  local x, y = pos(f)
  if x < -12 or x > W + 12 or y < -12 or y > H + 12 then return end
  if f.kind == "ufo" then
    gfx.setColor(gfx.kColorWhite)
    gfx.fillEllipseInRect(x - 9, y - 3, 18, 7)
    gfx.drawCircleAtPoint(x, y - 3, 4)
    gfx.setColor(gfx.kColorBlack)
    local k = (t // 4) % 3
    gfx.fillRect(x - 5 + k * 4, y - 1, 2, 2)
  else
    gfx.setColor(gfx.kColorWhite)
    if f.kind == "big" then
      if f.hp > 1 then gfx.fillCircleAtPoint(x, y, f.r)
      else
        gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
        gfx.fillCircleAtPoint(x, y, f.r)
        gfx.setColor(gfx.kColorWhite)
        gfx.drawCircleAtPoint(x, y, f.r)
      end
      gfx.setColor(gfx.kColorBlack)
      gfx.fillCircleAtPoint(x - 3, y - 2, 2)
      gfx.fillCircleAtPoint(x + 3, y + 3, 1)
    else
      gfx.fillCircleAtPoint(x, y, f.r)
      gfx.setColor(gfx.kColorBlack)
      gfx.fillRect(x - 1, y - 2, 2, 2)
    end
    -- short streak toward outer space
    gfx.setColor(gfx.kColorWhite)
    gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
    local rad = math.rad(f.a)
    gfx.drawLine(x + math.cos(rad) * (f.r + 2), y + math.sin(rad) * (f.r + 2),
      x + math.cos(rad) * (f.r + 10), y + math.sin(rad) * (f.r + 10))
  end
  gfx.setColor(gfx.kColorBlack)
end

local function draw(st)
  if st.flash > 0 and st.flash % 2 == 0 then gfx.clear(gfx.kColorWhite) else gfx.clear(gfx.kColorBlack) end
  local ox, oy = 0, 0
  if st.shake > 0 then ox, oy = st.rng:i(-3, 3), st.rng:i(-3, 3) end
  gfx.setDrawOffset(ox, oy)

  -- stars
  gfx.setColor(gfx.kColorWhite)
  for i = 1, #st.stars do
    local s = st.stars[i]
    if (st.t + s[3]) % 60 > 3 then gfx.fillRect(s[1], s[2], 1, 1) end
  end
  -- orbit guide ring
  gfx.setDitherPattern(0.75, gfx.image.kDitherTypeBayer4x4)
  gfx.drawCircleAtPoint(CX, CY, 40)

  -- moon base: cratered dome
  local alive = st.phase ~= "over"
  if alive then
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(CX, CY, BASE_R)
    gfx.setColor(gfx.kColorBlack)
    gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
    gfx.fillCircleAtPoint(CX + 3, CY + 3, BASE_R - 5)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawCircleAtPoint(CX, CY, BASE_R - 3)
    gfx.fillCircleAtPoint(CX, CY, 4)
    -- turret barrel
    local rad = math.rad(st.ang)
    local cx, cy = math.cos(rad), math.sin(rad)
    gfx.setColor(gfx.kColorWhite)
    gfx.setLineWidth(4)
    gfx.drawLine(CX + cx * 8, CY + cy * 8, CX + cx * 24, CY + cy * 24)
    gfx.setLineWidth(1)
    gfx.fillCircleAtPoint(CX + cx * 24, CY + cy * 24, 3)
    -- aim dots
    gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
    for d = 44, 110, 22 do gfx.fillRect(CX + cx * d - 1, CY + cy * d - 1, 2, 2) end
  else
    gfx.setColor(gfx.kColorWhite)
    gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer4x4)
    gfx.fillCircleAtPoint(CX, CY, BASE_R + 2)
  end

  -- foes, shots, particles
  for i = 1, #st.foes do drawFoe(st.foes[i], st.t) end
  gfx.setColor(gfx.kColorWhite)
  for i = 1, #st.shots do
    local s = st.shots[i]
    gfx.fillRect(s.x - 2, s.y - 2, 4, 4)
  end
  for i = 1, #st.parts do
    local p = st.parts[i]
    local sz = p.life > 10 and 2 or 1
    gfx.fillRect(p.x, p.y, sz, sz)
  end
  gfx.setDrawOffset(0, 0)

  -- HUD
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(0, 0, W, 28)
  gfx.setColor(gfx.kColorWhite)
  gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
  gfx.drawLine(0, 28, W, 28)
  Gfx.text("ORBITAL DEFENSE", 14, 6, { white = true, bold = true })
  -- shield pips
  for i = 1, 3 do
    local x = 160 + (i - 1) * 16
    gfx.setColor(gfx.kColorWhite)
    if i <= 3 - st.hits then gfx.fillRect(x, 9, 11, 10) else gfx.drawRect(x, 9, 11, 10) end
  end
  bigNum(st.score, 386, 5, 4, "right")
  gfx.setColor(gfx.kColorBlack)

  if st.phase == "ready" then
    gfx.fillRect(116, 170, 168, 40)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawRect(118, 172, 164, 36)
    gfx.setColor(gfx.kColorBlack)
    local s = ((st.t // 8) % 2 == 0) and "CREDIT 1  -  1UP" or "CRANK TO AIM - A FIRE"
    Gfx.text(s, 200, 182, { white = true, bold = true, align = "center" })
  elseif st.phase == "over" and st.overT >= 16 then
    gameOverBox(st, st.score)
  end
  crt(st.t)
end

local function done(st) return st.finished end
local function score(st) return math.floor(st.score) end

-- NPC run: second by second; foes arrive faster, each one either gets shot
-- (points by type) or slips through. Three leaks end the run.
local function npcScore(rng, skill)
  skill = U.clamp(skill or 0.5, 0, 1)
  local focus = 0.7 + 0.6 * rng:f() ^ 2
  local sc, hits, secs, acc = 0, 0, 0, 0
  while hits < 3 and secs < 3600 do
    secs = secs + 1
    local interval = math.max(12, 64 - secs * 0.9) + 8
    acc = acc + 30 / interval
    while acc >= 1 do
      acc = acc - 1
      local roll = rng:f()
      local pts = 10
      if secs > 20 and roll < math.min(0.22, 0.08 + secs / 600) then pts = 50
      elseif secs > 8 and roll < 0.45 then pts = 25 end
      local leak = (0.03 + secs * 0.0011) * (1.3 - 1.15 * skill) / focus
      if rng:chance(leak) then hits = hits + 1 else sc = sc + pts end
      if hits >= 3 then break end
    end
  end
  return math.floor(sc)
end

ArcadeGames.register("orbital", {
  name = "ORBITAL DEFENSE",
  new = new, update = update, draw = draw, done = done, score = score, npcScore = npcScore,
})
