-- RECORD STORE: recommend albums from the bin to picky customers.
-- Crank flips through the bin, A recommends, B lets them browse alone.

local gfx = playdate.graphics

local SHIFT_FRAMES = 30 * 110

-- ------------------------------------------------------------ shared bits
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
  if sub then Gfx.btext(sub, 236, 6, { align = "center" }) end
  Gfx.btext(clockStr(st), 388, 6, { align = "right" })
end

local function customerName(ctx, r)
  local c = ctx.customers
  if c and #c > 0 and r:chance(0.6) then
    local n = r:pick(c)
    return (n.first or "Someone") .. " " .. string.sub(n.last or "X", 1, 1) .. ".", n.taste
  end
  return r:pick(Names.teenFirst) .. " " .. string.sub(r:pick(Names.last), 1, 1) .. ".", nil
end

-- ------------------------------------------------------------ content
local MOOD_ASK = {
  loud = { "Something LOUD for my brother's birthday.", "I need something that'll annoy my neighbors." },
  sad = { "Just got dumped at the Citrus Whip. Sad stuff.", "Something to cry to in my Camaro." },
  happy = { "Something happy. It's been a long week at Pizza Pronto.", "Upbeat stuff for my road trip to Myrtle Beach." },
  chill = { "Something chill for studying. Or not studying.", "Mellow stuff for my lava lamp." },
  angry = { "My dad took my pager. I need ANGRY music.", "Something mad. Really mad." },
  weird = { "Something weird. Like, weirder than Bjork.", "Something my mom will not understand." },
  danceable = { "Something to dance to at the roller rink.", "I need jams for the homecoming afterparty." },
  romantic = { "Mixtape for a girl in my chem class. Romantic.", "Something romantic. Don't laugh." },
  moody = { "Moody stuff. For staring out of windows.", "Something moody for my poetry journal." },
}
local LIKE_ASK = {
  "I'm into {mood} stuff like {band}.",
  "Got anything {mood}? I love {band}.",
  "My friend made me a tape with {band}. More like that, but {mood}?",
}
local GENRE_ASK = {
  "Where's your {genre}? Something {mood}.",
  "Any good {genre}? Like, {mood} {genre}.",
  "I only listen to {genre}. And it has to be {mood}.",
}
local GOOD = { "Whoa. Rad. Ringing it up.", "Sweet, I saw them on 120 Minutes!", "Totally buying this.", "This is so me." }
local OK = { "Eh... close enough. I'll take it.", "Not quite, but OK.", "Hmm. My cousin might like it." }
local BAD = { "Uh... my MOM listens to this.", "Dude. No.", "Is this a joke? Is this a hidden camera?", "I'll just go to Sam Goody." }
local SKIP = { "Fine, I'll just browse.", "Whatever. I'll look myself.", "OK, I'll dig around." }
local LEAVE = { "Forget it, I'll tape it off the radio.", "This is taking forever. Bye." }

local ART = { "gray", "diag", "check", "dots", "wave", "brick", "plaid", "vstripe", "hstripe", "dark", "grate", "diag2" }

local function pickBin(ctx, r)
  local pool = {}
  local M = ctx.music or { albums = {}, bands = {} }
  for _, a in ipairs(M.albums or {}) do
    if not a.releaseDay and M.bands[a.band] then pool[#pool + 1] = a end
  end
  r:shuffle(pool)
  local bin = {}
  for i = 1, math.min(15, #pool) do
    local a = pool[i]
    local b = M.bands[a.band]
    bin[#bin + 1] = { band = b.name, title = a.title, genre = b.genre, mood = a.mood, year = a.year, id = a.id }
  end
  if #bin == 0 then
    for i = 1, 12 do
      local g = r:pick(Names.genres)
      local moods = Content.GENRE_MOOD[g] or Content.MOODS
      bin[i] = { band = r:pick(Names.bandA) .. " " .. r:pick(Names.bandB), title = r:pick(Names.albumA),
        genre = g, mood = r:pick(moods), year = r:i(1988, 1997), id = i }
    end
  end
  table.sort(bin, function(a, b) return a.band < b.band end)
  return bin
end

local function otherBand(ctx, r, genre, notName)
  local M = ctx.music
  if M and M.bands then
    local c = {}
    for _, b in ipairs(M.bands) do if b.genre == genre and b.name ~= notName then c[#c + 1] = b.name end end
    if #c > 0 then return r:pick(c) end
  end
  return notName
end

local function makeCustomer(st, ctx, r)
  local target = r:pick(st.bin)
  local name, taste = customerName(ctx, r)
  local c = { name = name, target = target, patience = st.patience, maxPatience = st.patience }
  local kind = r:i(1, 3)
  if kind == 1 then
    c.wantGenre, c.wantMood = target.genre, target.mood
    c.ask = U.fmt(r:pick(LIKE_ASK), { mood = target.mood, band = otherBand(ctx, r, target.genre, target.band) })
  elseif kind == 2 then
    c.wantGenre, c.wantMood = target.genre, target.mood
    c.ask = U.fmt(r:pick(GENRE_ASK), { mood = target.mood, genre = target.genre })
  else
    c.wantMood = target.mood
    c.ask = r:pick(MOOD_ASK[target.mood] or { "Something " .. target.mood .. ", please." })
  end
  if taste and r:chance(0.3) then c.ask = c.ask .. " (Secretly a " .. taste .. " fan.)" end
  return c
end

-- ------------------------------------------------------------ game
local function new(ctx)
  local r = ctx.rng
  local d = ctx.difficulty or 0
  local st = {
    r = r, ctx = ctx, t = 0, storeName = (ctx.store and ctx.store.name) or "Record Store",
    clockStart = 17 * 60, clockSpan = 240,
    bin = pickBin(ctx, r), pos = 1, n = 0, total = 7 + math.floor(d * 2 + 0.5),
    patience = math.floor(30 * (24 - 10 * d)), points = 0, tips = 0, sales = 0,
    say = nil, sayT = 0, over = false,
  }
  st.cust = makeCustomer(st, ctx, r)
  st.n = 1
  return st
end

local function nextCustomer(st)
  if st.n >= st.total then st.over = true return end
  st.n = st.n + 1
  st.cust = makeCustomer(st, st.ctx, st.r)
end

local function judge(st, alb)
  local c = st.cust
  local s = 0
  if c.wantGenre then
    if alb.genre == c.wantGenre then s = s + 60 end
    if alb.mood == c.wantMood then s = s + 40 end
  else
    if alb.mood == c.wantMood then s = 100
    elseif Content.GENRE_MOOD[alb.genre] and U.contains(Content.GENRE_MOOD[alb.genre], c.wantMood) then s = 40 end
  end
  return s
end

local function update(st)
  st.t = st.t + 1
  if st.t >= SHIFT_FRAMES then st.over = true end
  if st.over then return end
  -- crank flips the bin (one sleeve per 40 degrees)
  local nb = #st.bin
  st.pos = st.pos + (In.crank or 0) / 40
  if In.left then st.pos = math.floor(st.pos + 0.5) - 1 end
  if In.right then st.pos = math.floor(st.pos + 0.5) + 1 end
  if st.pos < 1 then st.pos = st.pos + nb end
  if st.pos >= nb + 1 then st.pos = st.pos - nb end
  if (In.crank or 0) ~= 0 then
    local cur = math.floor(st.pos + 0.5)
    if cur ~= st.lastIdx then Sfx.tick() st.lastIdx = cur end
  end

  if st.sayT > 0 then
    st.sayT = st.sayT - 1
    if st.sayT == 0 then nextCustomer(st) end
    return
  end
  local c = st.cust
  if (c.arrive or 0) < 30 then c.arrive = (c.arrive or 0) + 1 return end
  c.patience = c.patience - 1
  if c.patience <= 0 then
    st.say = st.r:pick(LEAVE)
    st.sayT = 45
    Sfx.bad()
    return
  end
  if In.a then
    local idx = math.floor(st.pos + 0.5)
    if idx > nb then idx = 1 end
    local alb = st.bin[idx]
    local s = judge(st, alb)
    st.points = st.points + s
    if s >= 90 then
      st.say = st.r:pick(GOOD)
      st.sales = st.sales + 1
      st.tips = st.tips + st.r:i(25, 100) + math.floor(c.patience / c.maxPatience * 50)
      Sfx.ok()
    elseif s >= 40 then
      st.say = st.r:pick(OK)
      st.sales = st.sales + 1
      Sfx.ok()
    else
      st.say = st.r:pick(BAD)
      Sfx.bad()
    end
    st.lastScore = s
    st.sayT = 50
  elseif In.b then
    st.points = st.points + 15
    st.say = st.r:pick(SKIP)
    st.sayT = 40
  end
end

-- sleeve art: pattern + a shape keyed on album id
local function sleeve(x, y, s, alb, skew)
  skew = skew or 0
  local pat = Gfx.P[ART[1 + alb.id % #ART]]
  gfx.setPattern(pat)
  gfx.fillPolygon(x + skew, y, x + s + skew, y, x + s, y + s, x, y + s)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawPolygon(x + skew, y, x + s + skew, y, x + s, y + s, x, y + s, x + skew, y)
  if skew == 0 then
    local kind = alb.id % 3
    local cx, cy = x + s // 2, y + s // 2
    if kind == 0 then
      Gfx.circle(cx, cy, s // 4, true, "white")
      Gfx.circle(cx, cy, s // 4, false)
      Gfx.circle(cx, cy, 3, true)
    elseif kind == 1 then
      gfx.setColor(gfx.kColorWhite)
      gfx.fillTriangle(cx - s // 4, cy + s // 5, cx + s // 4, cy + s // 5, cx, cy - s // 4)
      gfx.setColor(gfx.kColorBlack)
      gfx.drawTriangle(cx - s // 4, cy + s // 5, cx + s // 4, cy + s // 5, cx, cy - s // 4)
    else
      Gfx.fill(x + 8, cy - 8, s - 16, 16, "white")
      Gfx.rect(x + 8, cy - 8, s - 16, 16)
      Gfx.fill(x + 12, cy - 3, s - 24, 6, "black")
    end
  end
end

local function draw(st)
  Gfx.clear()
  Gfx.fill(0, 28, 400, 212, "carpet")
  header(st, "CUSTOMER " .. math.min(st.n, st.total) .. "/" .. st.total)
  local c = st.cust
  -- customer speech
  Gfx.box(4, 30, 392, 58, "light")
  Gfx.text(c.name .. ":", 14, 36, { bold = true })
  local line = st.sayT > 0 and st.say or c.ask
  Gfx.para(line, 14, 52, 360, { maxLines = 2, lh = 16 })
  if st.sayT <= 0 then
    Gfx.fill(300, 38, 84, 8, "white")
    Gfx.meter(300, 38, 84, 8, c.patience / c.maxPatience)
  end

  -- the bin: crate with sleeves
  local nb = #st.bin
  local idx = math.floor(st.pos + 0.5)
  if idx > nb then idx = 1 end
  local frac = st.pos - math.floor(st.pos)
  -- back sleeves (top edges peeking out of the crate)
  for k = 4, 1, -1 do
    local j = ((idx - 1 + k) % nb) + 1
    local yy = 104 - k * 5
    local xx = 30 + k * 6
    sleeve(xx, yy, 100, st.bin[j], 0)
  end
  -- current sleeve, tilting as you flip
  local skew = math.floor((frac - 0.5) * 40 + 0.5)
  if math.abs(frac - 0.5) < 0.12 then skew = 0 end
  sleeve(24, 110, 100, st.bin[idx], math.abs(frac - 0.5) < 0.12 and 0 or skew)
  -- crate front
  Gfx.fill(10, 176, 160, 50, "brick")
  Gfx.rect(10, 176, 160, 50)
  Gfx.fill(60, 192, 60, 16, "white")
  Gfx.rect(60, 192, 60, 16)
  Gfx.text(string.sub(st.bin[idx].band, 1, 1) .. "-" .. string.sub(st.bin[((idx + 3) % nb) + 1].band, 1, 1), 90, 192, { align = "center" })

  -- info card
  local a = st.bin[idx]
  Gfx.box(184, 94, 212, 118, "dark")
  Gfx.btext(fit(a.band, 186, true), 196, 102, { bold = true })
  Gfx.btext(fit('"' .. a.title .. '"', 186), 196, 120)
  Gfx.btext("Genre: " .. a.genre, 196, 142)
  Gfx.btext("Mood:  " .. a.mood, 196, 160)
  Gfx.btext(tostring(a.year) .. "   #" .. idx .. "/" .. nb, 196, 182)
  Gfx.prompt("CRANK flip  (A) Recommend  (B) Browse", nil, 218)
end

local function done(st) return st.over end

local function result(st)
  local score = U.clamp(math.floor(st.points / st.total + 0.5), 0, 100)
  return { score = score, tips = st.tips,
    text = string.format("Sold %d of %d customers a record. %s", st.sales, st.n,
      score >= 70 and "Your taste is legendary." or (score >= 40 and "Decent picks." or "Someone bought a polka CD by mistake.")) }
end

Minigames.register("record", {
  title = "Record Store Shift",
  help = { "Customers want something specific.", "CRANK flips through the bin.",
    "(A) recommend the sleeve on top.", "(B) let them browse alone.", "Match genre AND mood for tips." },
  new = new, update = update, draw = draw, done = done, result = result,
})
