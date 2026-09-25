-- DEPARTMENT STORE: ring up clothes and count back exact change;
-- fold sweaters between customers with D-pad sequences.

local gfx = playdate.graphics

local SHIFT_FRAMES = 30 * 120

local function clockStr(st)
  local mins = st.clockStart + math.floor(st.t / SHIFT_FRAMES * st.clockSpan)
  local h = (mins // 60) % 24
  local ap = h >= 12 and "PM" or "AM"
  local h12 = h % 12
  if h12 == 0 then h12 = 12 end
  return string.format("%d:%02d%s", h12, mins % 60, ap)
end

local function header(st, sub)
  Gfx.box(0, 0, 400, 28, "dark")
  Gfx.btext(st.storeName, 12, 6, { bold = true })
  if sub then Gfx.btext(sub, 240, 6, { align = "center" }) end
  Gfx.btext(clockStr(st), 388, 6, { align = "right" })
end

local function customerName(ctx, r)
  local c = ctx.customers
  if c and #c > 0 and r:chance(0.5) then return (r:pick(c).first or "Someone") end
  return r:pick(r:chance(0.6) and Names.adultFirst or Names.teenFirst)
end

local DENOMS = { { 1000, "$10" }, { 500, "$5" }, { 100, "$1" }, { 25, "25c" }, { 10, "10c" }, { 5, "5c" }, { 1, "1c" } }
local QUIPS = { "Do you take Discover? No? Cash then.", "Is this on sale? It should be on sale.",
  "My daughter says this is 'da bomb'.", "Can I return this if it's not phat?", "I'll need a gift box. And a receipt.",
  "It's for a Hootie concert. Be honest.", "I want to look like I'm on Friends." }
local EXACT = { "Exact change. You're a wizard.", "Thank you, dear.", "Perfect. Have a nice day!" }
local SHORT = { "Excuse me, I think I'm owed more.", "Hmm, I count that differently." }
local OVER = { "(They pocket the extra. Your drawer is short.)", "(The drawer will be short at close. Gulp.)" }
local ARROWS = { "up", "down", "left", "right" }

local function newCustomer(st)
  local r = st.r
  local items, sub = {}, 0
  for _ = 1, r:i(1, st.d > 0.5 and 3 or 2) do
    local it = r:pick(Names.clothes)
    items[#items + 1] = it
    sub = sub + it[2]
  end
  local tax = math.floor(sub * 0.06 + 0.5)
  local total = sub + tax
  local step = r:pick({ 500, 1000, 2000, 2000, 5000 })
  local paid = ((total + step - 1) // step) * step
  if paid == total then paid = paid + step end
  st.cust = { kind = "reg", name = customerName(st.ctx, r), items = items, sub = sub, tax = tax, total = total,
    paid = paid, change = paid - total, quip = r:pick(QUIPS), time = math.floor(30 * (34 - 12 * st.d)) }
  st.cust.max = st.cust.time
  st.counts = { 0, 0, 0, 0, 0, 0, 0 }
  st.sel = 1
  st.acc = 0
end

local function newFold(st)
  local r = st.r
  local seq = {}
  for i = 1, 4 + math.floor(st.d * 2 + 0.5) do seq[i] = r:pick(ARROWS) end
  st.cust = { kind = "fold", seq = seq, pos = 1, miss = 0, time = math.floor(30 * (9 - 3 * st.d)) }
  st.cust.max = st.cust.time
end

local function new(ctx)
  local r = ctx.rng
  local d = ctx.difficulty or 0
  local st = { r = r, ctx = ctx, d = d, t = 0, storeName = (ctx.store and ctx.store.name) or "Department Store",
    clockStart = 12 * 60, clockSpan = 300, regs = 6 + math.floor(d * 2 + 0.5), step = 1, points = 0, tips = 0,
    exact = 0, folded = 0, sayT = 0, over = false, short = 0 }
  st.steps = st.regs * 2 - 1
  newCustomer(st)
  return st
end

local function given(st)
  local s = 0
  for i, dd in ipairs(DENOMS) do s = s + st.counts[i] * dd[1] end
  return s
end

local function say(st, s, pts, good)
  st.say = s
  st.sayT = 45
  st.points = st.points + pts
  if good then Sfx.ok() else Sfx.bad() end
end

local function update(st)
  st.t = st.t + 1
  if st.t >= SHIFT_FRAMES then st.over = true end
  if st.over then return end
  if st.sayT > 0 then
    st.sayT = st.sayT - 1
    if st.sayT == 0 then
      if st.step >= st.steps then st.over = true return end
      st.step = st.step + 1
      if st.step % 2 == 1 then newCustomer(st) else newFold(st) end
    end
    return
  end
  local c = st.cust
  c.time = c.time - 1
  if c.kind == "reg" then
    if c.time <= 0 then say(st, c.name .. " left. Their stuff is on the counter.", 0, false) return end
    if In.left then st.sel = st.sel - 1; if st.sel < 1 then st.sel = 8 end end
    if In.right then st.sel = st.sel + 1; if st.sel > 8 then st.sel = 1 end end
    if st.sel <= 7 then
      st.acc = st.acc + (In.crank or 0)
      while st.acc >= 45 do st.acc = st.acc - 45; st.counts[st.sel] = math.min(19, st.counts[st.sel] + 1); Sfx.tick() end
      while st.acc <= -45 do st.acc = st.acc + 45; st.counts[st.sel] = math.max(0, st.counts[st.sel] - 1); Sfx.tick() end
      if In.up then st.counts[st.sel] = math.min(19, st.counts[st.sel] + 1) end
      if In.down then st.counts[st.sel] = math.max(0, st.counts[st.sel] - 1) end
    end
    if In.b then st.counts = { 0, 0, 0, 0, 0, 0, 0 } end
    if In.a then
      if st.sel <= 7 then
        st.counts[st.sel] = math.min(19, st.counts[st.sel] + 1)
        Sfx.tick()
      else
        local diff = given(st) - c.change
        if diff == 0 then
          st.exact = st.exact + 1
          st.tips = st.tips + (st.r:chance(0.2) and 100 or 0)
          say(st, st.r:pick(EXACT), 100, true)
        elseif diff < 0 then
          say(st, st.r:pick(SHORT) .. " (" .. U.money(-diff) .. " short)", -diff <= 5 and 70 or (-diff < 100 and 40 or 10), false)
        else
          st.short = st.short + diff
          say(st, st.r:pick(OVER) .. " +" .. U.money(diff), diff <= 5 and 70 or (diff < 100 and 30 or 0), false)
        end
      end
    end
  else
    if c.time <= 0 then
      say(st, "Your manager refolds it. Loudly.", math.floor(40 * (c.pos - 1) / #c.seq), false)
      return
    end
    local pressed
    if In.up then pressed = "up" elseif In.down then pressed = "down" elseif In.left then pressed = "left" elseif In.right then pressed = "right" end
    if pressed then
      if pressed == c.seq[c.pos] then
        c.pos = c.pos + 1
        Sfx.tick()
        if c.pos > #c.seq then
          st.folded = st.folded + 1
          say(st, c.miss == 0 and "Crisp fold. Gap-level quality." or "Folded. Kinda lumpy.", math.max(20, 100 - 20 * c.miss), true)
        end
      else
        c.miss = c.miss + 1
        Sfx.bad()
      end
    end
  end
end

local function drawReg(st, c)
  -- receipt
  Gfx.fill(6, 34, 170, 180, "white")
  Gfx.rect(6, 34, 170, 180)
  Gfx.text(c.name, 14, 38, { bold = true })
  local y = 58
  for _, it in ipairs(c.items) do
    local nm = it[1]
    if #nm > 13 then nm = nm:sub(1, 12) .. "." end
    Gfx.text(nm, 14, y)
    Gfx.text(U.money(it[2]), 168, y, { align = "right" })
    y = y + 16
  end
  Gfx.text("tax", 14, y); Gfx.text(U.money(c.tax), 168, y, { align = "right" })
  Gfx.line(14, y + 18, 168, y + 18)
  y = y + 20
  Gfx.text("TOTAL", 14, y, { bold = true }); Gfx.text(U.money(c.total), 168, y, { align = "right", bold = true })
  Gfx.text("PAID", 14, y + 16); Gfx.text(U.money(c.paid), 168, y + 16, { align = "right" })
  Gfx.meter(14, 204, 154, 6, c.time / c.max)
  -- register display
  Gfx.box(184, 34, 212, 60, "dark")
  Gfx.btext("CHANGE DUE " .. U.money(c.change), 290, 42, { align = "center", bold = true })
  local g = given(st)
  Gfx.btext("COUNTED    " .. U.money(g), 290, 64, { align = "center" })
  -- drawer
  Gfx.fill(184, 98, 212, 118, "gray")
  Gfx.rect(184, 98, 212, 118)
  for i, dd in ipairs(DENOMS) do
    local col, row = (i - 1) % 4, (i - 1) // 4
    local x, yy = 188 + col * 52, 102 + row * 56
    local sel = (i == st.sel)
    Gfx.box(x, yy, 50, 52, sel and "dark" or "light")
    Gfx.text(dd[2], x + 25, yy + 8, { align = "center", bold = true, white = sel })
    Gfx.text("x" .. st.counts[i], x + 25, yy + 28, { align = "center", white = sel })
  end
  local sel = st.sel == 8
  Gfx.box(344, 158, 50, 52, sel and "dark" or "light")
  Gfx.text("GIVE", 369, 176, { align = "center", bold = true, white = sel })
  Gfx.prompt("<> pick  CRANK/(A) count  GIVE to finish", nil, 220)
end

local function drawFold(st, c)
  Gfx.box(6, 34, 388, 50, "light")
  Gfx.text("Between customers: fold this sweater!", 200, 40, { align = "center", bold = true })
  Gfx.meter(120, 62, 160, 8, c.time / c.max)
  -- sweater shrinks as you fold
  local p = (c.pos - 1) / #c.seq
  local w = math.floor(200 - 120 * p)
  local h = math.floor(90 - 40 * p)
  local x, y = 200 - w // 2, 96
  Gfx.fill(x, y, w, h, "plaid")
  Gfx.rect(x, y, w, h)
  if p < 0.5 then
    Gfx.fill(x - 30, y + 4, 30, 24, "plaid"); Gfx.rect(x - 30, y + 4, 30, 24)
    Gfx.fill(x + w, y + 4, 30, 24, "plaid"); Gfx.rect(x + w, y + 4, 30, 24)
  end
  Gfx.fill(200 - 14, y, 28, 8, "white"); Gfx.rect(200 - 14, y, 28, 8)
  -- the sequence
  local n = #c.seq
  local bx = 200 - n * 14
  for i, a in ipairs(c.seq) do
    local x2 = bx + (i - 1) * 28
    local doneA = i < c.pos
    Gfx.box(x2, 190, 26, 26, doneA and "light" or "dark")
    Gfx.tri(x2 + 10, 200, a, not doneA)
  end
  if c.miss > 0 then Gfx.text("fumbles: " .. c.miss, 390, 196, { align = "right" }) end
end

local function draw(st)
  Gfx.clear()
  Gfx.fill(0, 28, 400, 212, "carpet")
  local c = st.cust
  header(st, c.kind == "reg" and ("REGISTER " .. ((st.step + 1) // 2) .. "/" .. st.regs) or "FOLDING")
  if c.kind == "reg" then drawReg(st, c) else drawFold(st, c) end
  if st.sayT > 0 then
    Gfx.box(20, 120, 360, 50, "dark")
    Gfx.para(st.say, 32, 128, 336, { white = true, maxLines = 2, lh = 16 })
  end
end

local function done(st) return st.over end

local function result(st)
  local score = U.clamp(math.floor(st.points / st.steps + 0.5), 0, 100)
  local txt = string.format("%d/%d exact change, %d %s folded.", st.exact, st.regs, st.folded, U.plural(st.folded, "sweater"))
  if st.short > 0 then txt = txt .. " Drawer over-paid " .. U.money(st.short) .. "." end
  return { score = score, tips = st.tips, text = txt }
end

Minigames.register("department", {
  title = "Department Store Shift",
  help = { "Count back the CHANGE DUE exactly.", "LEFT/RIGHT picks a bill/coin,",
    "(A) or CRANK adds, UP/DOWN adjusts,", "(B) clears. Pick GIVE to hand it over.", "Between customers: match the arrows to fold." },
  new = new, update = update, draw = draw, done = done, result = result,
})
