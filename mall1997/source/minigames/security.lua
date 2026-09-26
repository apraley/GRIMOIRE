-- LOSS PREVENTION: watch four grainy CCTV feeds, flag shoplifters.
-- Crank cycles which feed is enlarged; A flags the enlarged feed.

local gfx = playdate.graphics

local SHIFT_FRAMES = 30 * 110
local FW, FH = 100, 70 -- feed coordinate space
local AISLES = { 12, 37, 63, 88 }
local SHELVES = { 25, 50, 75 }

local function clockStr(st)
  local mins = st.clockStart + math.floor(st.t / SHIFT_FRAMES * st.clockSpan)
  local h = (mins // 60) % 24
  local ap = h >= 12 and "PM" or "AM"
  local h12 = h % 12
  if h12 == 0 then h12 = 12 end
  return string.format("%d:%02d%s", h12, mins % 60, ap)
end

local function fit(s, w, bold)
  s = tostring(s)
  if Gfx.textW(s, bold) <= w then return s end
  while #s > 1 and Gfx.textW(s .. "..", bold) > w do s = s:sub(1, -2) end
  return s .. ".."
end

local function sayBox(s, x, y, w, h, light)
  Gfx.box(x, y, w, h, light and "light" or "dark")
  local lines = Gfx.wrap(s, w - 28)
  local n = math.min(#lines, 2)
  local y0 = y + (h - n * 16) // 2 - 1
  for i = 1, n do Gfx.text(lines[i], x + w // 2, y0 + (i - 1) * 16, { align = "center", white = not light }) end
end

local function header(st, sub)
  Gfx.box(0, 0, 400, 28, "dark")
  Gfx.btext(st.storeName, 12, 6, { bold = true })
  if sub then Gfx.btext(sub, 240, 6, { align = "center" }) end
  Gfx.btext(clockStr(st), 388, 6, { align = "right" })
end

local CAUGHT = { "Floor staff nabbed them. Discman in a Starter jacket.", "Caught! 6 Pogs slammers in one sock.",
  "Busted with a Tamagotchi in their Big Gulp.", "Got 'em. Lipstick in a hollowed-out Walkman." }
local FALSE = { "False alarm. That was a price-tag check.", "That was the district manager. Awkward.",
  "Nope. Just a guy scratching his back.", "Mrs. Dunn was just smelling a candle." }
local MISSED = { "Something just walked out of CAM {c}.", "Inventory will be short on CAM {c}'s aisle." }
local CAM_NAMES = { "ENTRANCE", "AISLE 2", "ELECTRONICS", "STOCKROOM" }

local function planRoute(sh, r)
  local ta = r:pick(AISLES)
  local ty = r:i(8, 60)
  sh.route = {}
  if math.abs(ta - sh.x) > 2 then
    sh.route[#sh.route + 1] = { sh.x, 66 }
    sh.route[#sh.route + 1] = { ta, 66 }
  end
  sh.route[#sh.route + 1] = { ta, ty }
end

local function new(ctx)
  local r = ctx.rng
  local d = ctx.difficulty or 0
  local st = { r = r, ctx = ctx, d = d, t = 0, storeName = (ctx.store and ctx.store.name) or "Mall Security",
    clockStart = 18 * 60 + 15, clockSpan = 240, feed = 1, acc = 0, feeds = {}, caught = 0, missed = 0,
    falses = 0, lock = 0, sayT = 0, over = false, tips = 0,
    nextEvent = 30 * r:i(4, 7), eventLen = math.floor(30 * (3.2 - 1.4 * d)),
    noise = RNG.new(r:i(1, 99999)) }
  for f = 1, 4 do
    local feed = { shoppers = {} }
    for k = 1, r:i(2, 3 + math.floor(d + 0.5)) do
      local sh = { x = r:pick(AISLES), y = r:i(8, 62), state = "walk", t = 0, speed = 0.35 + r:f() * 0.3, id = k }
      planRoute(sh, r)
      feed.shoppers[k] = sh
    end
    st.feeds[f] = feed
  end
  return st
end

local function nearestShelfDir(x)
  local best, dir = 999, 1
  for _, s in ipairs(SHELVES) do
    if math.abs(s - x) < best then best = math.abs(s - x); dir = (s > x) and 1 or -1 end
  end
  return dir
end

local function stepShopper(st, f, sh)
  local r = st.r
  if sh.state == "walk" then
    local wp = sh.route[1]
    if not wp then
      sh.state = "idle"; sh.t = r:i(20, 60)
      return
    end
    local dx, dy = wp[1] - sh.x, wp[2] - sh.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist <= sh.speed then
      sh.x, sh.y = wp[1], wp[2]
      table.remove(sh.route, 1)
    else
      sh.x = sh.x + dx / dist * sh.speed
      sh.y = sh.y + dy / dist * sh.speed
    end
  elseif sh.state == "idle" then
    sh.t = sh.t - 1
    if sh.t <= 0 then
      if r:chance(0.45) then
        sh.state = "browse"; sh.t = 0; sh.len = r:i(50, 90); sh.dir = nearestShelfDir(sh.x)
      else
        sh.state = "walk"; planRoute(sh, r)
      end
    end
  elseif sh.state == "browse" or sh.state == "conceal" then
    sh.t = sh.t + 1
    if sh.t >= sh.len then
      if sh.state == "conceal" then
        st.missed = st.missed + 1
        st.say = U.fmt(r:pick(MISSED), { c = f })
        st.sayT = 50
        Sfx.bad()
      end
      sh.state = "walk"; planRoute(sh, r)
    end
  end
end

local function update(st)
  st.t = st.t + 1
  if st.t >= SHIFT_FRAMES then st.over = true end
  if st.over then return end
  local r = st.r
  -- crank cycles the enlarged feed
  st.acc = st.acc + (In.crank or 0)
  while st.acc >= 90 do st.acc = st.acc - 90; st.feed = st.feed % 4 + 1; Sfx.tick() end
  while st.acc <= -90 do st.acc = st.acc + 90; st.feed = (st.feed + 2) % 4 + 1; Sfx.tick() end
  if In.right or In.down then st.feed = st.feed % 4 + 1 end
  if In.left or In.up then st.feed = (st.feed + 2) % 4 + 1 end

  for f = 1, 4 do for _, sh in ipairs(st.feeds[f].shoppers) do stepShopper(st, f, sh) end end

  -- schedule a shoplifting attempt
  st.nextEvent = st.nextEvent - 1
  if st.nextEvent <= 0 and st.t < SHIFT_FRAMES - st.eventLen then
    local f = r:i(1, 4)
    local cands = {}
    for _, sh in ipairs(st.feeds[f].shoppers) do if sh.state == "walk" or sh.state == "idle" then cands[#cands + 1] = sh end end
    local sh = r:pick(cands)
    if sh then
      sh.route = {}
      sh.state = "conceal"; sh.t = 0; sh.len = st.eventLen; sh.dir = nearestShelfDir(sh.x)
    end
    st.nextEvent = math.floor(30 * (r:i(6, 10) - 2.5 * st.d))
  end

  if st.sayT > 0 then st.sayT = st.sayT - 1 end
  if st.lock > 0 then st.lock = st.lock - 1 return end
  if In.a then
    local hit
    for _, sh in ipairs(st.feeds[st.feed].shoppers) do if sh.state == "conceal" and sh.t > 8 then hit = sh end end
    if hit then
      st.caught = st.caught + 1
      st.tips = st.tips + 25
      hit.state = "walk"; hit.route = { { hit.x, 66 }, { hit.x < 50 and 2 or 98, 66 } }
      st.say = r:pick(CAUGHT)
      Sfx.ok()
    else
      st.falses = st.falses + 1
      st.say = r:pick(FALSE)
      Sfx.bad()
    end
    st.sayT = 60
    st.lock = 75
  end
end

-- ---------------------------------------------------------------- draw
local HAZE = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x88, 0x00, 0x22, 0x00, 0x88, 0x00, 0x22, 0x00 }

local function drawFeed(st, f, x, y, s, big)
  local w, h = math.floor(FW * s), math.floor(FH * s)
  Gfx.fill(x, y, w, h, big and "light" or "lighter")
  for _, sx in ipairs(SHELVES) do
    Gfx.fill(x + math.floor((sx - 3) * s), y + math.floor(10 * s), math.floor(6 * s), math.floor(48 * s), "dark")
  end
  for _, sh in ipairs(st.feeds[f].shoppers) do
    local px, py = x + math.floor(sh.x * s), y + math.floor(sh.y * s)
    if big then
      local busy = sh.state == "browse" or sh.state == "conceal"
      local glance = (sh.state == "conceal" and (sh.t // 6) % 2 == 0) and 2 or 0
      Gfx.fill(px - 5, py - 4, 10, 14, "black")
      Gfx.circle(px + glance, py - 9, 5, true, "white")
      Gfx.circle(px + glance, py - 9, 5, false)
      if busy then
        local p = sh.t / sh.len
        local reach = (p < 0.35) and (p / 0.35) or ((p < 0.65) and 1 - (p - 0.35) / 0.3 or 0)
        local hx = px + sh.dir * math.floor(4 + 12 * reach)
        Gfx.line(px + sh.dir * 4, py, hx, py - 2)
        if p > 0.2 then
          if sh.state == "browse" then
            if p < 0.8 then Gfx.fill(hx - 2, py - 6, 5, 5, "white"); Gfx.rect(hx - 2, py - 6, 5, 5) end
          elseif p < 0.65 then
            Gfx.fill(hx - 2, py - 6, 5, 5, "white"); Gfx.rect(hx - 2, py - 6, 5, 5)
          else
            Gfx.fill(px - 1, py + 1, 3, 3, "white") -- the bulge in the jacket
          end
        end
      end
    else
      Gfx.circle(px, py, 2, true)
    end
  end
  if big then
    -- grain + rolling bar
    local n = st.noise
    gfx.setColor(gfx.kColorBlack)
    for _ = 1, 40 do gfx.drawPixel(x + n:i(0, w - 1), y + n:i(0, h - 1)) end
    gfx.setColor(gfx.kColorWhite)
    for _ = 1, 25 do gfx.drawPixel(x + n:i(0, w - 1), y + n:i(0, h - 1)) end
    gfx.setColor(gfx.kColorBlack)
    local by = y + (st.t * 2) % h
    gfx.setPattern(HAZE)
    gfx.fillRect(x, by, w, math.min(10, y + h - by))
    gfx.setColor(gfx.kColorBlack)
    Gfx.fill(x + 2, y + h - 18, 118, 16, "black")
    Gfx.btext("CAM " .. f .. " " .. clockStr(st), x + 5, y + h - 19)
    if (st.t // 15) % 2 == 0 then Gfx.circle(x + w - 12, y + 10, 4, true) end
    Gfx.text("REC", x + w - 42, y + 3, { bold = true })
    Gfx.fill(x + 2, y + 2, Gfx.textW(CAM_NAMES[f]) + 6, 16, "white")
    Gfx.text(CAM_NAMES[f], x + 5, y + 2)
  end
  Gfx.rect(x, y, w, h)
end

local function draw(st)
  Gfx.clear()
  Gfx.fill(0, 28, 400, 212, "black")
  header(st, "LOSS PREVENTION")
  -- 2x2 thumbnails
  for f = 1, 4 do
    local col, row = (f - 1) % 2, (f - 1) // 2
    local x, y = 6 + col * 84, 34 + row * 62
    drawFeed(st, f, x, y, 0.8, false)
    Gfx.fill(x, y + 44, 14, 12, "black")
    Gfx.btext(tostring(f), x + 3, y + 41)
    if f == st.feed then Gfx.rect(x - 3, y - 3, 86, 62, "white"); Gfx.rect(x - 2, y - 2, 84, 60, "white") end
  end
  -- enlarged feed
  drawFeed(st, st.feed, 178, 34, 2.16, true)
  -- status
  Gfx.box(4, 160, 170, 56, "dark")
  Gfx.btext("CAUGHT " .. st.caught .. "  MISSED " .. st.missed, 14, 168)
  Gfx.btext("FALSE ALARMS " .. st.falses, 14, 186)
  if st.lock > 0 then Gfx.btext("RADIOING FLOOR...", 14, 204 - 2) end
  if st.sayT > 0 and st.say then
    sayBox(st.say, 4, 180, 392, 42, true)
  else
    Gfx.prompt("CRANK switch camera  (A) Flag shoplifter", nil, 220)
  end
end

local function done(st) return st.over end

local function result(st)
  local events = st.caught + st.missed
  local base = events > 0 and st.caught / events or 0.5
  local score = U.clamp(math.floor(100 * base / (1 + 0.15 * st.falses) + 0.5), 0, 100)
  return { score = score, tips = st.tips,
    text = string.format("Caught %d of %d shoplifters, %d false %s.", st.caught, events, st.falses, U.plural(st.falses, "alarm")) }
end

Minigames.register("security", {
  title = "Loss Prevention Shift",
  help = { "Watch the cameras for shoplifters.", "CRANK cycles which feed is enlarged.",
    "(A) flags the big feed while someone", "is pocketing an item. False alarms", "hurt your score. Browsers are innocent!" },
  new = new, update = update, draw = draw, done = done, result = result,
})
