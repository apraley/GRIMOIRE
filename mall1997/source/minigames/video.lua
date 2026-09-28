-- VIDEO STORE: find tapes, recommend tapes, reshelve returns.
-- D-pad left/right picks the genre section, crank scans the shelf, A pulls.

local gfx = playdate.graphics

local SHIFT_FRAMES = 30 * 115

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
    return (n.first or "Someone") .. " " .. string.sub(n.last or "X", 1, 1) .. "."
  end
  local pool = r:chance(0.5) and Names.adultFirst or Names.teenFirst
  return r:pick(pool) .. " " .. string.sub(r:pick(Names.last), 1, 1) .. "."
end

local FIND_ASK = {
  "Do you have {title}? It's {a} {genre}, I think.",
  "Looking for {title}. {genre}. My VCR is waiting.",
  "{title}? The {genre} one? Please say it's not all rented.",
}
local REC_ASK = {
  noR = { "Some {genre}, but nothing R-rated. It's for my kids.", "{genre} for my little brother. No R, Mom checks." },
  short = { "A {genre} movie under 100 minutes. I have a curfew.", "Short {genre}. Under 100 min. Work at 6am." },
  good = { "A {genre} flick that's actually good. 3 stars+.", "Best {genre} you've got. 3 stars or better." },
  isR = { "Something {genre} and rated R. I'm 17, I swear.", "Gimme an R-rated {genre}. Date night." },
}
local RETURN_ASK = {
  "Returning {title}. Be kind, rewind! (I didn't.)",
  "Dropping off {title}. Is it late? It's not late.",
  "{title}. The kids got peanut butter on it. Sorry.",
}
local WIN = { "Perfect! Popcorn time.", "Thanks! Can I get Milk Duds too?", "Yes! Last copy!" }
local MISS = { "That's... not it.", "No, the OTHER one.", "Hmm, not what I asked for." }
local LEAVE = { "Forget it, I'll go to the other video store.", "I'll just watch TV Guide channel." }

local function stars(q) return math.max(1, math.min(4, math.floor(q / 25) + 1)) end

local function sortShelf(t) table.sort(t, function(a, b) return a.title < b.title end) end

local function buildShelves(ctx, r)
  local byG, secs = {}, {}
  for _, m in ipairs(ctx.movies or {}) do
    if m.vhs then
      byG[m.genre] = byG[m.genre] or {}
      table.insert(byG[m.genre], m)
    end
  end
  for _, g in ipairs(Names.movieGenres) do
    if byG[g] and #byG[g] > 0 then sortShelf(byG[g]); secs[#secs + 1] = g end
  end
  if #secs == 0 then
    for i = 1, 4 do
      local g = Names.movieGenres[i]
      byG[g] = {}
      for k = 1, 6 do
        byG[g][k] = { title = g .. " tape " .. k, genre = g, rating = r:pick(Names.ratings), mins = r:i(84, 150), quality = r:i(10, 95), year = 1990 }
      end
      sortShelf(byG[g]); secs[#secs + 1] = g
    end
  end
  return byG, secs
end

local function fits(m, req)
  local ok = 0
  if m.genre == req.genre then ok = ok + 50 end
  local c = req.con
  if (c == "noR" and m.rating ~= "R") or (c == "short" and m.mins < 100) or
     (c == "good" and stars(m.quality) >= 3) or (c == "isR" and m.rating == "R") then
    ok = ok + 50
  end
  return ok
end

local function makeReq(st)
  local r = st.r
  local req = { name = customerName(st.ctx, r), patience = st.patience, maxPatience = st.patience, tries = 0 }
  local roll = r:f()
  local g = r:pick(st.secs)
  local shelf = st.byG[g]
  if roll < 0.4 and #shelf > 0 then
    req.kind = "find"
    req.movie = r:pick(shelf)
    req.ask = U.fmt(r:pick(FIND_ASK), { title = '"' .. req.movie.title .. '"', genre = g,
      a = (g:match("^[aeiou]") and "an" or "a") })
  elseif roll < 0.72 then
    req.kind = "rec"
    req.genre = g
    local cons = { "noR", "short", "good", "isR" }
    r:shuffle(cons)
    req.con = cons[1]
    for _, c in ipairs(cons) do
      local any = false
      for _, m in ipairs(shelf) do if fits(m, { genre = g, con = c }) == 100 then any = true break end end
      if any then req.con = c break end
    end
    req.ask = U.fmt(r:pick(REC_ASK[req.con]), { genre = g })
  else
    req.kind = "return"
    local m = r:pick(shelf)
    if m then
      U.removeValue(shelf, m)
    else
      m = { title = "Mystery Tape", genre = g, rating = "PG", mins = 90, quality = 50, year = 1993 }
    end
    req.movie = m
    req.ask = U.fmt(r:pick(RETURN_ASK), { title = '"' .. m.title .. '"' })
  end
  return req
end

local function new(ctx)
  local r = ctx.rng
  local d = ctx.difficulty or 0
  local st = { r = r, ctx = ctx, t = 0, storeName = (ctx.store and ctx.store.name) or "Video Store",
    clockStart = 18 * 60, clockSpan = 180, sec = 1, cur = 1, points = 0, tips = 0, served = 0,
    n = 1, total = 8 + math.floor(d * 2 + 0.5), patience = math.floor(30 * (28 - 12 * d)),
    sayT = 0, over = false, arrive = 0 }
  st.byG, st.secs = buildShelves(ctx, r)
  st.req = makeReq(st)
  return st
end

local function finish(st, pts, line, good)
  st.points = st.points + pts
  st.say = line
  st.sayT = 45
  if good then
    st.served = st.served + 1
    st.tips = st.tips + st.r:i(0, 50) + math.floor(st.req.patience / st.req.maxPatience * 50)
    Sfx.ok()
  else
    Sfx.bad()
  end
end

local function update(st)
  st.t = st.t + 1
  if st.t >= SHIFT_FRAMES then st.over = true end
  if st.over then return end
  if (st.missT or 0) > 0 then st.missT = st.missT - 1 end
  local shelf = st.byG[st.secs[st.sec]]
  if In.left then st.sec = st.sec - 1; if st.sec < 1 then st.sec = #st.secs end; st.cur = 1 end
  if In.right then st.sec = st.sec + 1; if st.sec > #st.secs then st.sec = 1 end; st.cur = 1 end
  shelf = st.byG[st.secs[st.sec]]
  local n = math.max(1, #shelf)
  local before = math.floor(st.cur)
  st.cur = U.clamp(st.cur + (In.crank or 0) / 30, 1, n + 0.99)
  if In.up then st.cur = U.clamp(math.floor(st.cur) - 1, 1, n) end
  if In.down then st.cur = U.clamp(math.floor(st.cur) + 1, 1, n) end
  if math.floor(st.cur) ~= before then Sfx.tick() end

  if st.sayT > 0 then
    st.sayT = st.sayT - 1
    if st.sayT == 0 then
      if st.n >= st.total then st.over = true return end
      st.n = st.n + 1
      st.req = makeReq(st)
      st.arrive = 0
    end
    return
  end
  if st.arrive < 25 then st.arrive = st.arrive + 1 return end
  local req = st.req
  req.patience = req.patience - 1
  if req.patience <= 0 then
    finish(st, req.kind == "return" and 20 or 0, st.r:pick(LEAVE), false)
    if req.kind == "return" then st.say = "They left the tape on the counter. Sticky." end
    return
  end
  if not In.a then return end
  local idx = math.floor(st.cur)
  local tape = shelf[idx]
  if req.kind == "find" then
    if tape == req.movie then
      finish(st, math.max(40, 100 - req.tries * 20), st.r:pick(WIN), true)
    else
      req.tries = req.tries + 1
      st.say = st.r:pick(MISS)
      st.sayT = 0
      st.missT = 30
      req.patience = req.patience - 60
      Sfx.bad()
    end
  elseif req.kind == "rec" then
    if tape then
      local s = fits(tape, req)
      if s == 100 then finish(st, 100, st.r:pick(WIN), true)
      elseif s == 50 then finish(st, 50, "Close. I guess. Fine.", true)
      else finish(st, 0, "Why would I want THIS?", false) end
    end
  else
    local m = req.movie
    local g = st.secs[st.sec]
    if g == m.genre then
      local pos = 1
      while shelf[pos] and shelf[pos].title < m.title do pos = pos + 1 end
      local bonus = (math.abs(pos - idx) <= 1) and 30 or 0
      table.insert(shelf, pos, m)
      finish(st, 70 + bonus, bonus > 0 and "Reshelved. Alphabetical, even." or "Reshelved. Close enough.", true)
    else
      finish(st, 0, "Wrong aisle. Someone finds it in 2003.", false)
    end
  end
end

local function draw(st)
  Gfx.clear()
  Gfx.fill(0, 28, 400, 212, "carpet")
  header(st, "CUST " .. st.n .. "/" .. st.total)
  local req = st.req
  Gfx.box(4, 30, 392, 58, "light")
  Gfx.text(req.name .. ":", 14, 36, { bold = true })
  local line = (st.sayT > 0 and st.say) or ((st.missT or 0) > 0 and st.say) or req.ask
  Gfx.para(line, 14, 52, 370, { maxLines = 2, lh = 16 })
  if st.sayT <= 0 then Gfx.meter(300, 38, 84, 8, req.patience / req.maxPatience) end

  -- section sign (neon!)
  local g = st.secs[st.sec]
  Gfx.neon(100, 90, 200, 20, st.sec)
  Gfx.fill(130, 92, 140, 16, "black")
  Gfx.btext(string.upper(g), 200, 92, { align = "center", bold = true })
  Gfx.tri(108, 97, "left", false)
  Gfx.tri(286, 97, "right", false)
  if req.kind == "return" then
    Gfx.fill(4, 90, 90, 20, "white"); Gfx.rect(4, 90, 90, 20)
    Gfx.text("TAPE: " .. string.upper(req.movie.genre), 8, 92)
  end

  -- shelf of spines
  local shelf = st.byG[g]
  local idx = math.floor(st.cur)
  Gfx.fill(0, 112, 400, 64, "dark")
  Gfx.fill(0, 170, 400, 6, "black")
  local first = math.max(1, idx - 7)
  for k = 0, 15 do
    local i = first + k
    local m = shelf[i]
    if not m then break end
    local x = 8 + k * 24
    local sel = (i == idx)
    local y = sel and 114 or 120
    Gfx.fill(x, y, 22, 50, sel and "white" or ((i % 3 == 0) and "gray" or "white"))
    Gfx.rect(x, y, 22, 50)
    Gfx.fill(x + 3, y + 4, 16, 10, "black")
    Gfx.text(string.sub(m.title, 1, 1), x + 11, y + 26, { align = "center", bold = sel })
    if m.rating == "R" then Gfx.fill(x + 4, y + 42, 14, 4, "black") end
    if sel then Gfx.rect(x - 2, y - 2, 26, 54) end
  end
  if #shelf == 0 then Gfx.btext("(section empty)", 200, 130, { align = "center" }) end

  -- info card
  Gfx.box(4, 176, 392, 42, "dark")
  local m = shelf[idx]
  if m then
    Gfx.btext(fit(m.title, 370, true), 14, 180, { bold = true })
    Gfx.btext(string.format("%s  %d min  %s  %s", m.rating, m.mins, string.rep("*", stars(m.quality)), tostring(m.year or "")), 14, 197)
  end
  local p = req.kind == "return" and "<> section  CRANK spot  (A) Shelve" or "<> section  CRANK scan  (A) Pull tape"
  Gfx.prompt(p, nil, 220)
end

local function done(st) return st.over end

local function result(st)
  local score = U.clamp(math.floor(st.points / st.total + 0.5), 0, 100)
  return { score = score, tips = st.tips,
    text = string.format("Helped %d of %d renters. %s", st.served, st.total,
      score >= 70 and "The VCRs of this town thank you." or (score >= 40 and "Late fees were collected." or "Someone rented the wrong Air Bud.")) }
end

Minigames.register("video", {
  title = "Video Store Shift",
  help = { "Find tapes, recommend tapes, reshelve returns.", "LEFT/RIGHT: genre section.",
    "CRANK: scan along the shelf.", "(A) pull the tape / shelve a return.", "Mind the ratings and runtimes!" },
  new = new, update = update, draw = draw, done = done, result = result,
})
