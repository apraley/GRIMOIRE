-- CINEMA: tear tickets, scoop popcorn, keep the projector in focus.

local gfx = playdate.graphics

local PHASE_LEN = { 30 * 36, 30 * 30, 30 * 42 }
local CARD_LEN = 45
local SHIFT_FRAMES = PHASE_LEN[1] + PHASE_LEN[2] + PHASE_LEN[3] + CARD_LEN * 3

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

local function customerName(ctx, r)
  local c = ctx.customers
  if c and #c > 0 and r:chance(0.4) then
    local n = r:pick(c)
    return (n.first or "Someone"), (type(n.age) == "number" and n.age >= 10) and math.floor(n.age) or nil
  end
  return r:pick(Names.teenFirst), nil
end

local TIMES = { "1:30", "4:15", "7:00", "7:15", "9:40", "10:05" }
local PHASE_NAMES = { "TICKET TAKING", "CONCESSIONS", "PROJECTION BOOTH" }
local REFUSED = { "Aw, man. Can I at least see Air Bud?", "My older brother said it's FINE.",
  "I'll just sneak in through the exit.", "Ugh. You're worse than my mom." }
local ADMIT_BAD = { "(Your manager saw that. Sigh.)", "(That kid is 12. Everyone saw.)", "(Wrong movie. Chaos in theater 3.)" }
local POP_ASK = { "{s} popcorn. Extra butter. EXTRA.", "{s} popcorn, and do you have Sno-Caps?",
  "Uh, {s} popcorn? Is the butter real? Don't answer.", "{s} popcorn for my date. Make it look full.",
  "{s} popcorn. I'm smuggling in my own soda." }
local SIZES = { { "Small", 0.45 }, { "Medium", 0.65 }, { "Large", 0.85 } }

-- ---------------------------------------------------------------- setup
local function pickFilms(ctx, r)
  local now, pool = {}, {}
  for _, m in ipairs(ctx.movies or {}) do
    if m.opens and m.opens <= 0 then now[#now + 1] = m end
    pool[#pool + 1] = m
  end
  if #now < 3 then now = pool end
  local films = {}
  local tmp = {}
  for i = 1, #now do tmp[i] = now[i] end
  r:shuffle(tmp)
  for i = 1, math.min(3, #tmp) do films[i] = { title = tmp[i].title, rating = tmp[i].rating } end
  while #films < 3 do films[#films + 1] = { title = "Scream Night " .. (#films + 2), rating = "R" } end
  -- guarantee one R-rated film for the ID checks
  local anyR = false
  for _, f in ipairs(films) do if f.rating == "R" then anyR = true end end
  if not anyR then films[r:i(1, 3)].rating = "R" end
  for i, f in ipairs(films) do f.time = TIMES[i * 2 - r:i(0, 1)]; f.screen = i end
  return films
end

local function newPatron(st)
  local r = st.r
  if st.pn % 4 == 0 then st.seat = r:pick(st.films) end
  st.pn = st.pn + 1
  local f = st.seat
  local name, age = customerName(st.ctx, r)
  local p = { name = name, film = f.title, time = f.time, age = age or r:i(18, 60), valid = true }
  local roll = r:f()
  if roll < 0.2 then
    local other = r:pick(st.films)
    if other ~= f then p.film = other.title; p.time = other.time; p.valid = false; p.why = "wrong film" end
  elseif roll < 0.38 then
    local tm = r:pick(TIMES)
    if tm ~= f.time then p.time = tm; p.valid = false; p.why = "wrong showtime" end
  elseif roll < 0.6 and f.rating == "R" then
    p.age = r:i(11, 16); p.valid = false; p.why = "underage"
  end
  if f.rating == "R" and p.valid and p.age < 17 then p.valid = false; p.why = "underage" end
  st.patron = p
end

local function newPop(st)
  local r = st.r
  local s = r:pick(SIZES)
  st.pop = { name = customerName(st.ctx, r), size = s[1], line = s[2] + r:f() * 0.06 - 0.03, fill = 0,
    ask = U.fmt(r:pick(POP_ASK), { s = s[1] }), flow = 0 }
end

local function new(ctx)
  local r = ctx.rng
  local d = ctx.difficulty or 0
  local st = { r = r, ctx = ctx, d = d, t = 0, storeName = (ctx.store and ctx.store.name) or "Cinema",
    clockStart = 18 * 60 + 30, clockSpan = 240, phase = 1, pt = 0, card = CARD_LEN, over = false,
    tips = 0, sayT = 0,
    -- tickets
    pn = 0, tCorrect = 0, tTotal = 0,
    -- popcorn
    popScore = 0, popN = 0, spills = 0,
    -- booth
    focus = 0.3, fv = 0, sharp = 0, boothN = 0, cues = {}, cueHit = 0, cueMiss = 0,
    tol = 0.16 - 0.07 * d }
  st.films = pickFilms(ctx, r)
  newPatron(st)
  newPop(st)
  local L = PHASE_LEN[3]
  st.cues = { { at = math.floor(L * 0.35 + r:i(-60, 60)), hit = false }, { at = math.floor(L * 0.75 + r:i(-60, 60)), hit = false } }
  st.cueLen = math.floor(36 - 14 * d)
  return st
end

-- ---------------------------------------------------------------- update
local function sayLine(st, s, good)
  st.say = s
  st.sayT = 30
  if good then Sfx.ok() else Sfx.bad() end
end

local function updTickets(st)
  if st.sayT > 0 then
    st.sayT = st.sayT - 1
    if st.sayT == 0 then newPatron(st) end
    return
  end
  local p = st.patron
  if In.a or In.b then
    st.tTotal = st.tTotal + 1
    local admit = In.a
    if admit == p.valid then
      st.tCorrect = st.tCorrect + 1
      sayLine(st, admit and "*RIIIP* Enjoy the show!" or ("Refused: " .. p.why .. ". " .. st.r:pick(REFUSED)), true)
    else
      sayLine(st, admit and st.r:pick(ADMIT_BAD) or "That ticket was fine. They're mad now.", false)
    end
  end
end

local function updPop(st)
  if st.sayT > 0 then
    st.sayT = st.sayT - 1
    if st.sayT == 0 then newPop(st) end
    return
  end
  local p = st.pop
  local c = In.crank or 0
  p.flow = c > 0 and c or 0
  if c > 0 then p.fill = p.fill + c / 360 * 0.35 end
  if p.fill > 1.05 then
    st.spills = st.spills + 1
    p.fill = 0
    sayLine(st, "Popcorn avalanche! Grab the broom.", false)
    st.popN = st.popN + 1
    return
  end
  if In.a and p.fill > 0.05 then
    local err = math.abs(p.fill - p.line)
    local s = U.clamp(math.floor(100 - math.max(0, err - 0.04) * 400), 0, 100)
    st.popScore = st.popScore + s
    st.popN = st.popN + 1
    if s >= 80 then
      st.tips = st.tips + st.r:i(0, 40)
      sayLine(st, "Perfect scoop. Buttery.", true)
    elseif p.fill < p.line then
      sayLine(st, "That's a Small at best, pal.", false)
    else
      sayLine(st, "Uh, it's spilling on my shoes.", false)
    end
  end
end

local function updBooth(st)
  local r = st.r
  -- drift: the lens slowly wanders, sometimes jolts
  if r:chance(0.03) then st.fv = (r:f() - 0.5) * (0.012 + 0.012 * st.d) end
  st.focus = U.clamp(st.focus + st.fv + (In.crank or 0) / 360 * 0.4, -1, 1)
  st.boothN = st.boothN + 1
  if math.abs(st.focus) < st.tol then st.sharp = st.sharp + 1 end
  local cueOn = false
  for _, c in ipairs(st.cues) do
    if st.pt >= c.at and st.pt < c.at + st.cueLen and not c.hit then cueOn = true
      if In.a then c.hit = true; st.cueHit = st.cueHit + 1; sayLine(st, "Changeover! Seamless.", true) end
    end
  end
  st.cueOn = cueOn
  if In.a and not cueOn then st.cueMiss = st.cueMiss + 1; sayLine(st, "Too early! Half a second of blank.", false) end
  if st.sayT > 0 then st.sayT = st.sayT - 1 end
end

local function update(st)
  st.t = st.t + 1
  if st.over then return end
  if st.card > 0 then st.card = st.card - 1 return end
  st.pt = st.pt + 1
  if st.phase == 1 then updTickets(st) elseif st.phase == 2 then updPop(st) else updBooth(st) end
  if st.pt >= PHASE_LEN[st.phase] then
    st.phase = st.phase + 1
    st.pt = 0
    st.sayT = 0
    if st.phase > 3 then st.over = true else st.card = CARD_LEN end
  end
end

-- ---------------------------------------------------------------- draw
local function person(x, y, age, seed)
  local h = age < 17 and 48 + (age - 10) * 3 or 74
  local top = y - h
  Gfx.circle(x, top + 10, 10, true)
  Gfx.fill(x - 14, top + 22, 28, h - 22, (seed % 2 == 0) and "gray" or "diag")
  Gfx.rect(x - 14, top + 22, 28, h - 22)
  if seed % 3 == 0 then Gfx.fill(x - 12, top - 2, 24, 5, "black") end -- backwards cap
end

local function drawTickets(st)
  Gfx.fill(0, 28, 400, 212, "carpet")
  -- marquee board
  Gfx.box(4, 32, 196, 96, "dark")
  Gfx.btext("NOW SEATING", 102, 38, { align = "center", bold = true })
  local s = st.seat
  Gfx.btext(fit(s.title, 176), 102, 58, { align = "center" })
  Gfx.btext(s.time .. "  Screen " .. s.screen .. "  [" .. s.rating .. "]", 102, 78, { align = "center" })
  Gfx.btext("R = 17+ or with a parent", 102, 100, { align = "center" })
  -- patron
  local p = st.patron
  Gfx.fill(206, 32, 190, 96, "white")
  Gfx.rect(206, 32, 190, 96)
  person(240, 126, p.age, #p.name)
  Gfx.text(p.name, 270, 40, { bold = true })
  Gfx.text("looks about", 270, 60)
  Gfx.text(tostring(p.age), 270, 78, { bold = true })
  -- ticket stub
  Gfx.fill(40, 134, 320, 76, "white")
  Gfx.rect(40, 134, 320, 76)
  Gfx.rect(43, 137, 314, 70)
  for k = 0, 6 do Gfx.circle(300, 140 + k * 10, 2, true) end
  Gfx.text("ADMIT ONE", 56, 140, { bold = true })
  Gfx.text(fit(p.film, 236), 56, 160)
  Gfx.text("Showtime " .. p.time, 56, 180)
  Gfx.text("#" .. (4400 + st.pn * 7), 330, 180, { align = "center" })
  if st.sayT > 0 then
    sayBox(st.say, 20, 148, 360, 50)
  end
  Gfx.prompt("(A) Tear & admit   (B) Refuse", nil, 218)
end

local function drawPop(st)
  Gfx.fill(0, 28, 400, 212, "check")
  local p = st.pop
  Gfx.box(4, 32, 392, 50, "light")
  Gfx.text(p.name .. ":", 14, 38, { bold = true })
  Gfx.para(p.ask, 14, 54, 370, { maxLines = 2, lh = 15 })
  -- popcorn machine
  Gfx.box(20, 88, 150, 126, "dark")
  Gfx.btext("POPCORN", 95, 94, { align = "center", bold = true })
  for k = 0, 9 do
    local ph = (Gfx.frame + k * 7) % 20
    Gfx.circle(40 + (k * 13) % 110, 180 - (ph * 3 + k * 5) % 60, 3, true, "white")
  end
  -- bucket
  local x, y, w, h = 230, 96, 80, 110
  local fh = math.floor(math.min(p.fill, 1.05) * h)
  Gfx.fill(x, y, w, h, "white")
  if fh > 0 then Gfx.fill(x + 1, y + h - fh, w - 2, fh, "dots") end
  for k = 0, 3 do Gfx.fill(x + 6 + k * 20, y, 8, h, fh > 0 and "light" or "vstripe") end
  Gfx.rect(x, y, w, h)
  Gfx.rect(x + 1, y, w - 2, h)
  if fh > 0 then Gfx.fill(x + 1, y + h - fh, w - 2, math.min(fh, 6), "gray") end
  local ly = y + h - math.floor(p.line * h)
  for k = 0, 7 do Gfx.line(x - 14 + k * 14, ly, x - 6 + k * 14, ly) end
  Gfx.text(p.size, x + w + 6, ly - 8, { bold = true })
  if p.flow > 0 then for k = 0, 4 do Gfx.circle(x + 20 + k * 10, y - 6 - (Gfx.frame * 3 + k * 9) % 18, 3, false) end end
  if st.sayT > 0 then
    sayBox(st.say, 20, 120, 360, 50)
  end
  Gfx.prompt("CRANK scoop to the line   (A) Serve", nil, 218)
end

-- 16-value pattern: 8 bytes pattern + 8 bytes mask (transparent where 0)
local HAZE1 = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x88, 0x00, 0x22, 0x00, 0x88, 0x00, 0x22, 0x00 }
local HAZE2 = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55 }
local HAZE3 = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xEE, 0xBB, 0xEE, 0xBB, 0xEE, 0xBB, 0xEE, 0xBB }

local function scene(ox, oy, style, t)
  -- desert showdown: sun, mesa, a cowboy, a tumbleweed
  local function f(x, y, w, h) Gfx.fill(ox + x, oy + y, w, h, style) end
  gfx.setPattern(Gfx.P[style] or Gfx.P.black)
  gfx.fillTriangle(ox + 10, oy + 100, ox + 80, oy + 40, ox + 150, oy + 100)
  gfx.fillCircleAtPoint(ox + 190, oy + 32, 16)
  gfx.setColor(gfx.kColorBlack)
  f(0, 100, 240, 6)
  f(150, 60, 14, 40)
  gfx.setPattern(Gfx.P[style] or Gfx.P.black)
  gfx.fillCircleAtPoint(ox + 157, oy + 52, 8)
  gfx.setColor(gfx.kColorBlack)
  f(144, 44, 26, 3)
  local tx = (t // 2) % 260 - 20
  gfx.setPattern(Gfx.P[style] or Gfx.P.black)
  gfx.fillCircleAtPoint(ox + tx, oy + 94, 6)
  gfx.setColor(gfx.kColorBlack)
end

local function drawBooth(st)
  Gfx.fill(0, 28, 400, 212, "black")
  -- screen
  local sx, sy = 20, 40
  Gfx.fill(sx - 4, sy - 4, 248, 128, "gray")
  Gfx.fill(sx, sy, 240, 120, "white")
  gfx.setClipRect(sx, sy, 240, 120)
  local b = math.abs(st.focus)
  local o = math.floor(b * 10)
  if o > 0 then
    scene(sx - o, sy, "gray", st.pt)
    scene(sx + o, sy, "gray", st.pt)
  end
  scene(sx, sy, b < st.tol and "black" or "dark", st.pt)
  if b >= st.tol then
    local hz = b < 0.35 and HAZE1 or (b < 0.6 and HAZE2 or HAZE3)
    gfx.setPattern(hz)
    gfx.fillRect(sx, sy, 240, 120)
    gfx.setColor(gfx.kColorBlack)
  end
  if st.cueOn then
    Gfx.circle(sx + 222, sy + 16, 9, true)
    Gfx.circle(sx + 222, sy + 16, 11, false, "white")
  end
  gfx.clearClipRect()
  -- booth panel
  Gfx.box(270, 36, 126, 176, "dark")
  Gfx.btext("FOCUS", 333, 44, { align = "center", bold = true })
  -- focus gauge
  local gx, gy, gh = 300, 64, 110
  Gfx.rect(gx, gy, 20, gh, "white")
  local tolPx = math.floor(st.tol * gh / 2)
  Gfx.fill(gx + 1, gy + gh // 2 - tolPx, 18, tolPx * 2, "gray")
  local ny = gy + gh // 2 + math.floor(st.focus * gh / 2)
  ny = U.clamp(ny, gy, gy + gh - 3)
  Gfx.fill(gx - 6, ny - 1, 32, 3, "white")
  Gfx.btext(b < st.tol and "SHARP" or "BLURRY", 333, 180, { align = "center" })
  local sharpPct = st.boothN > 0 and math.floor(st.sharp * 100 / st.boothN) or 0
  Gfx.btext(sharpPct .. "% sharp", 333, 196, { align = "center" })
  -- reel progress
  Gfx.meter(20, 172, 240, 8, st.pt / PHASE_LEN[3], nil, true)
  Gfx.btext("REEL 2   cues: " .. st.cueHit .. "/" .. #st.cues, 20, 184)
  if st.sayT > 0 and st.say then Gfx.btext(fit(st.say, 245), 20, 200) end
  if not (st.sayT > 0) then Gfx.prompt("CRANK focus  (A) at cue dot", 20, 218) end
end

local function draw(st)
  Gfx.clear()
  local ph = math.min(st.phase, 3)
  header(st, PHASE_NAMES[ph])
  if st.card > 0 then
    Gfx.fill(0, 28, 400, 212, "dark")
    Gfx.box(60, 80, 280, 80, "dark")
    Gfx.btext("PART " .. ph .. " OF 3", 200, 94, { align = "center", bold = true })
    Gfx.btext(PHASE_NAMES[ph], 200, 118, { align = "center" })
    return
  end
  if ph == 1 then drawTickets(st) elseif ph == 2 then drawPop(st) else drawBooth(st) end
end

local function done(st) return st.over end

local function phaseScores(st)
  local a = st.tTotal > 0 and (st.tCorrect / st.tTotal) * math.min(1, st.tTotal / 8) or 0
  local b = st.popN > 0 and (st.popScore / st.popN / 100) * math.min(1, st.popN / 5) or 0
  local sharpF = st.boothN > 0 and st.sharp / st.boothN or 0
  local c = 0.65 * sharpF + 0.35 * (st.cueHit / #st.cues) - 0.05 * math.min(st.cueMiss, 4)
  return U.clamp(a, 0, 1), U.clamp(b, 0, 1), U.clamp(c, 0, 1)
end

local function result(st)
  local a, b, c = phaseScores(st)
  local score = U.clamp(math.floor((a + b + c) / 3 * 100 + 0.5), 0, 100)
  local txt = string.format("Tickets %d/%d right, %d popcorn %s, film %d%% in focus.", st.tCorrect, st.tTotal,
    st.popN, U.plural(st.popN, "order"), st.boothN > 0 and math.floor(st.sharp * 100 / st.boothN) or 0)
  return { score = score, tips = st.tips, text = txt }
end

Minigames.register("cinema", {
  title = "Cinema Shift",
  help = { "1) Tickets: (A) admit, (B) refuse wrong", "   film, wrong time, or under 17 for R.",
    "2) Popcorn: CRANK to the line, (A) serve.", "3) Booth: CRANK to keep focus sharp,",
    "   (A) when the cue dot appears." },
  new = new, update = update, draw = draw, done = done, result = result,
})
