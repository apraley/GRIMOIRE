-- HIGHWAY 97: top-down four-lane highway scrolling toward you. Steer with
-- the D-pad or the CRANK, dodge the Sunday drivers and the semis. Speed
-- keeps climbing; score is distance. One spare car: the first crash costs
-- a life and some speed, the second ends the run.

local gfx = playdate.graphics
local W, H = 400, 240
local LANES = 4
local LANE_W = 44
local ROAD_X = 200 - (LANES * LANE_W) // 2 -- 112
local ROAD_W = LANES * LANE_W
local CAR_W, CAR_H = 20, 32
local PY = 188 -- player car top
local V0, VMAX = 5, 14

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
local function laneX(l) return ROAD_X + (l - 1) * LANE_W + (LANE_W - CAR_W) // 2 end
local function rowGap(v) return math.max(130, 190 - (v - V0) * 7) end

local function new(ctx)
  local st = {
    rng = ctx.rng, t = 0, phase = "ready", overT = 0, finished = false,
    x = laneX(2), v = V0, dist = 0, nextRow = 120, cars = {}, props = {},
    lives = 2, inv = 0, crashT = 0, crashX = 0, crashY = 0, lastOpen = 2,
  }
  for i = 1, 6 do
    st.props[i] = { side = (i % 2 == 0) and 1 or -1, y = i * 42 - 20, kind = ctx.rng:i(1, 3) }
  end
  return st
end

local function score(st) return math.floor(st.dist / 25) end

local function spawnRow(st)
  local r = st.rng
  -- keep a lane open near the last open lane so every row is passable
  local open = U.clamp(st.lastOpen + r:i(-1, 1), 1, LANES)
  st.lastOpen = open
  local busy = math.min(0.85, 0.35 + (st.v - V0) * 0.06)
  local n = 1
  if r:chance(busy) then n = 2 end
  if st.v > 10 and r:chance(0.25) then n = 3 end
  local lanes = {}
  for l = 1, LANES do if l ~= open then lanes[#lanes + 1] = l end end
  r:shuffle(lanes)
  for i = 1, n do
    local l = lanes[i]
    local truck = r:chance(0.2)
    local h = truck and 50 or CAR_H
    st.cars[#st.cars + 1] = {
      lane = l, x = laneX(l), y = -h - r:i(0, 30), h = h, truck = truck,
      sp = r:range(0.35, 0.6), -- fraction of our speed they drive at
    }
  end
end

local function crash(st, c)
  st.lives = st.lives - 1
  st.crashT = 24
  st.crashX, st.crashY = st.x + CAR_W // 2, PY + 10
  Sfx.bad()
  if st.lives <= 0 then
    st.phase = "over"
    st.overT = 0
    return
  end
  st.inv = 75
  st.v = math.max(V0, st.v * 0.65)
  -- clear the immediate neighbourhood so the restart is fair
  for i = #st.cars, 1, -1 do
    if st.cars[i].y > PY - 120 then table.remove(st.cars, i) end
  end
end

local function update(st)
  st.t = st.t + 1
  if st.crashT > 0 then st.crashT = st.crashT - 1 end
  if st.phase == "over" then
    st.overT = st.overT + 1
    if st.overT >= 80 or (st.overT > 30 and In.a) then st.finished = true end
    return
  end

  -- steering works during the countdown too
  local steer = 3 + st.v * 0.3
  if In.lh then st.x = st.x - steer end
  if In.rh then st.x = st.x + steer end
  st.x = st.x + (In.crank or 0) * 0.5
  st.x = U.clamp(st.x, ROAD_X + 2, ROAD_X + ROAD_W - CAR_W - 2)

  if st.phase == "ready" then
    if st.t >= 40 or In.a then st.phase = "play" end
    return
  end

  st.v = math.min(VMAX, st.v + 0.0027)
  if st.inv > 0 then st.inv = st.inv - 1 end
  st.dist = st.dist + st.v

  st.nextRow = st.nextRow - st.v
  if st.nextRow <= 0 then
    spawnRow(st)
    st.nextRow = rowGap(st.v) + st.rng:i(0, 30)
  end

  for p = 1, #st.props do
    local pr = st.props[p]
    pr.y = pr.y + st.v
    if pr.y > H + 30 then pr.y = pr.y - 6 * 42; pr.kind = st.rng:i(1, 3) end
  end

  local px1, px2 = st.x + 3, st.x + CAR_W - 3
  local py1, py2 = PY + 3, PY + CAR_H - 3
  for i = #st.cars, 1, -1 do
    local c = st.cars[i]
    c.y = c.y + st.v * (1 - c.sp)
    if c.y > H + 10 then
      table.remove(st.cars, i)
      Sfx.tick()
    elseif st.inv == 0 and c.x + CAR_W > px1 and c.x < px2 and c.y + c.h > py1 and c.y < py2 then
      crash(st, c)
      return
    end
  end
end

local function drawCar(x, y, h, style)
  x, y = math.floor(x), math.floor(y)
  gfx.setColor(gfx.kColorWhite)
  if style == "truck" then
    -- cab + dithered trailer
    gfx.fillRoundRect(x, y + h - 14, CAR_W, 14, 3)
    gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
    gfx.fillRect(x, y, CAR_W, h - 16)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawRect(x, y, CAR_W, h - 16)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(x + 3, y + h - 6, CAR_W - 6, 3) -- windshield (facing down)
  else
    gfx.fillRoundRect(x, y, CAR_W, h, 4)
    gfx.setColor(gfx.kColorBlack)
    if style == "player" then
      gfx.fillRect(x + 3, y + 7, CAR_W - 6, 5)   -- windshield
      gfx.fillRect(x + 4, y + h - 9, CAR_W - 8, 4) -- rear window
      gfx.fillRect(x + CAR_W // 2 - 1, y + 13, 2, h - 23) -- racing stripe
    else
      gfx.fillRect(x + 3, y + h - 12, CAR_W - 6, 5)
      gfx.fillRect(x + 4, y + 5, CAR_W - 8, 4)
    end
    -- wheels
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(x - 2, y + 5, 2, 6); gfx.fillRect(x + CAR_W, y + 5, 2, 6)
    gfx.fillRect(x - 2, y + h - 11, 2, 6); gfx.fillRect(x + CAR_W, y + h - 11, 2, 6)
  end
  gfx.setColor(gfx.kColorBlack)
end

local function drawProp(pr)
  local x = pr.side < 0 and 60 or 332
  local y = math.floor(pr.y)
  gfx.setColor(gfx.kColorWhite)
  if pr.kind == 1 then -- palm tree
    gfx.fillRect(x + 3, y, 3, 18)
    gfx.fillCircleAtPoint(x + 4, y, 7)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(x + 4, y, 3)
  elseif pr.kind == 2 then -- billboard
    gfx.fillRect(x - 6, y - 8, 24, 12)
    gfx.fillRect(x + 4, y + 4, 2, 10)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(x - 3, y - 5, 18, 2)
  else -- lamp post
    gfx.fillRect(x + 4, y - 10, 2, 22)
    gfx.fillRect(pr.side < 0 and (x + 4) or (x - 4), y - 10, 10, 2)
  end
  gfx.setColor(gfx.kColorBlack)
end

local function draw(st)
  gfx.clear(gfx.kColorBlack)
  -- verges
  gfx.setColor(gfx.kColorWhite)
  gfx.setDitherPattern(0.85, gfx.image.kDitherTypeBayer4x4)
  gfx.fillRect(0, 0, ROAD_X - 8, H)
  gfx.fillRect(ROAD_X + ROAD_W + 8, 0, W - ROAD_X - ROAD_W - 8, H)
  -- road edges (solid) and rumble strips
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(ROAD_X - 3, 0, 2, H)
  gfx.fillRect(ROAD_X + ROAD_W + 1, 0, 2, H)
  local off = math.floor(st.dist) % 40
  for y = -40 + off, H, 20 do
    gfx.fillRect(ROAD_X - 8, y, 4, 10)
    gfx.fillRect(ROAD_X + ROAD_W + 4, y, 4, 10)
  end
  -- dashed lane lines
  for l = 1, LANES - 1 do
    local lx = ROAD_X + l * LANE_W - 1
    for y = -40 + off, H, 40 do gfx.fillRect(lx, y, 2, 20) end
  end
  for p = 1, #st.props do drawProp(st.props[p]) end

  for i = 1, #st.cars do
    local c = st.cars[i]
    drawCar(c.x, c.y, c.h, c.truck and "truck" or "car")
  end
  local showMe = st.phase ~= "over" and (st.inv == 0 or (st.t // 3) % 2 == 0)
  if showMe then drawCar(st.x, PY, CAR_H, "player") end
  -- crash burst
  if st.crashT > 0 then
    gfx.setColor(gfx.kColorWhite)
    local r = 26 - st.crashT
    gfx.drawCircleAtPoint(st.crashX, st.crashY, r)
    gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
    gfx.fillCircleAtPoint(st.crashX, st.crashY, r // 2 + 2)
    gfx.setColor(gfx.kColorBlack)
  end

  -- HUD: left panel score, right panel speed + lives
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(6, 6, 96, 58)
  gfx.fillRect(W - 102, 6, 96, 58)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawRect(8, 8, 92, 54)
  gfx.drawRect(W - 100, 8, 92, 54)
  gfx.setColor(gfx.kColorBlack)
  Gfx.text("HIGHWAY 97", 54, 11, { white = true, bold = true, align = "center" })
  bigNum(score(st), 54, 32, 3, "center")
  local mph = math.floor(55 + (st.v - V0) * 6.5)
  if st.phase == "ready" then mph = 0 end
  bigNum(mph, W - 54, 14, 4, "center")
  Gfx.text("MPH", W - 54, 36, { white = true, align = "center" })
  for i = 1, 2 do
    local lx = W - 38 + (i - 1) * 12
    gfx.setColor(gfx.kColorWhite)
    if i <= st.lives then gfx.fillRect(lx, 50, 8, 8) else gfx.drawRect(lx, 50, 8, 8) end
  end
  gfx.setColor(gfx.kColorBlack)
  if mph >= 97 and mph <= 99 then
    Gfx.text("97!", 200, 40, { white = true, bold = true, align = "center" })
  end

  if st.phase == "ready" then
    gfx.fillRect(116, 100, 168, 40)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawRect(118, 102, 164, 36)
    gfx.setColor(gfx.kColorBlack)
    local s = ((st.t // 8) % 2 == 0) and "CREDIT 1  -  1UP" or "STEER: D-PAD / CRANK"
    Gfx.text(s, 200, 112, { white = true, bold = true, align = "center" })
  elseif st.phase == "over" and st.overT >= 20 then
    gameOverBox(st, score(st))
  end
  crt(st.t)
end

local function done(st) return st.finished end

-- NPC run: row by row of traffic at the in-game speed curve; each row has a
-- crash chance that climbs with speed and falls with skill. Two lives.
local function npcScore(rng, skill)
  skill = U.clamp(skill or 0.5, 0, 1)
  local focus = 0.75 + 1.0 * rng:f() ^ 4
  local v, dist, lives = V0, 0, 2
  while lives > 0 and dist < 2000000 do
    local gap = rowGap(v) + 15
    dist = dist + gap
    v = math.min(VMAX, v + 0.0027 * (gap / v))
    local risk = (0.022 + ((v - V0) / (VMAX - V0)) ^ 2 * 0.09) * (1.4 - 1.25 * skill) / focus
    if rng:chance(risk) then
      lives = lives - 1
      v = math.max(V0, v * 0.65)
    end
  end
  return math.floor(dist / 25)
end

ArcadeGames.register("racer", {
  name = "HIGHWAY 97",
  new = new, update = update, draw = draw, done = done, score = score, npcScore = npcScore,
})
