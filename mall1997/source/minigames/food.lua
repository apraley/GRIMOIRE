-- FOOD COURT: build trays to match order tickets. Crank pours the soda.

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
  if sub then Gfx.btext(sub, 240, 6, { align = "center" }) end
  Gfx.btext(clockStr(st), 388, 6, { align = "right" })
end

local function customerName(ctx, r)
  local c = ctx.customers
  if c and #c > 0 and r:chance(0.5) then
    local n = r:pick(c)
    return (n.first or "Someone")
  end
  return r:pick(r:chance(0.5) and Names.adultFirst or Names.teenFirst)
end

local CAT_KEYS = { { "pizza", "pizza" }, { "corn dog", "hotdog" }, { "frank", "hotdog" }, { "teriyaki", "asian" },
  { "wok", "asian" }, { "taco", "mexican" }, { "pretzel", "pretzel" }, { "whip", "drink" }, { "bun", "sweet" },
  { "cookie", "sweet" }, { "yogurt", "sweet" }, { "burger", "burger" }, { "gyro", "burger" }, { "hero", "pizza" } }
local CATS = { "pizza", "hotdog", "asian", "mexican", "pretzel", "drink", "sweet", "burger" }

local QUIPS = { "And make it snappy, the bus leaves at 4.", "Is the soda Surge? No? OK.",
  "Extra napkins. I'm wearing white jeans.", "My mom said I could get whatever.",
  "Can I pay in quarters? All of it?", "It's for my Tamagotchi's birthday.", "My lunch break is 11 minutes.",
  "Do you validate parking? No? OK.", "Heavy on the ice. Light on the attitude." }
local HAPPY = { "Awesome. You're the best.", "Sweet! Keep the change.", "Yesss. Food." }
local MEH = { "This isn't... quite it. Whatever.", "Close enough, I'm starving." }
local MAD = { "This is NOT what I ordered.", "Are you even listening?!", "I'm telling your manager. Gary." }

local function new(ctx)
  local r = ctx.rng
  local d = ctx.difficulty or 0
  local name = (ctx.store and ctx.store.name) or "Food Court"
  local cat
  local low = string.lower(name)
  for _, kv in ipairs(CAT_KEYS) do if low:find(kv[1], 1, true) then cat = kv[2] break end end
  cat = cat or r:pick(CATS)
  local mains = Names.foodItems[cat] or Names.foodItems.pizza
  local st = { r = r, ctx = ctx, t = 0, storeName = name, clockStart = 11 * 60 + 30, clockSpan = 150,
    d = d, over = false, n = 0, total = 7 + math.floor(d * 3 + 0.5), points = 0, tips = 0, perfect = 0,
    cx = 1, cy = 1, tray = {}, sodas = {}, napkins = 0, pour = nil, sayT = 0, spills = 0,
    tol = 0.07 - 0.035 * d, ticketLen = math.floor(30 * (32 - 12 * d)) }
  st.grid = {
    { { kind = "main", name = mains[1][1], price = mains[1][2] }, { kind = "main", name = mains[2][1], price = mains[2][2] },
      { kind = "main", name = mains[3][1], price = mains[3][2] } },
    { { kind = "soda", name = "soda cup" }, { kind = "napkins", name = "napkins" }, { kind = "serve", name = "SERVE" } },
  }
  st.mains = mains
  return st
end

local function newTicket(st)
  local r = st.r
  st.n = st.n + 1
  local tk = { name = customerName(st.ctx, r), want = {}, soda = 0, napkins = 0, time = st.ticketLen, max = st.ticketLen }
  local lines = r:i(1, st.d > 0.5 and 3 or 2)
  local used = 0
  for _ = 1, lines do
    local m = r:pick(st.mains)[1]
    local q = r:i(1, 2)
    if used + q <= 4 then tk.want[m] = (tk.want[m] or 0) + q; used = used + q end
  end
  if r:chance(0.65) then tk.soda = 1 end
  if st.d > 0.4 and r:chance(0.25) then tk.soda = 2 end
  if r:chance(0.3) then tk.napkins = 1 end
  tk.quip = r:pick(QUIPS)
  tk.lines = {}
  for _, it in ipairs(st.mains) do
    if tk.want[it[1]] then tk.lines[#tk.lines + 1] = tk.want[it[1]] .. "x " .. it[1] end
  end
  if tk.soda > 0 then tk.lines[#tk.lines + 1] = tk.soda .. "x large soda" end
  if tk.napkins > 0 then tk.lines[#tk.lines + 1] = "extra napkins" end
  st.tk = tk
  st.tray, st.sodas, st.napkins = {}, {}, 0
end

local function scoreTray(st)
  local tk = st.tk
  local s = 100
  local any = false
  for _, it in ipairs(st.mains) do
    local w, h = tk.want[it[1]] or 0, st.tray[it[1]] or 0
    if h > 0 then any = true end
    s = s - math.abs(w - h) * 25
  end
  -- sodas: best pours count toward what was ordered
  table.sort(st.sodas, function(a, b) return a > b end)
  for i = 1, tk.soda do
    local q = st.sodas[i]
    if q then s = s - math.floor((1 - q) * 30) else s = s - 30 end
  end
  if #st.sodas > tk.soda then s = s - (#st.sodas - tk.soda) * 10 end
  if #st.sodas > 0 then any = true end
  if tk.napkins > 0 and st.napkins == 0 then s = s - 10 end
  if not any then s = 0 end
  return U.clamp(s, 0, 100)
end

local function react(st, line, ok)
  st.say = line
  st.sayT = 45
  if ok then Sfx.ok() else Sfx.bad() end
end

local function update(st)
  st.t = st.t + 1
  if st.t >= SHIFT_FRAMES then st.over = true end
  if st.over then return end
  if st.sayT > 0 then
    st.sayT = st.sayT - 1
    if st.sayT == 0 then
      if st.n >= st.total then st.over = true return end
      newTicket(st)
    end
    return
  end
  if not st.tk then newTicket(st) end
  local tk = st.tk
  tk.time = tk.time - 1
  if tk.time <= 0 then
    react(st, tk.name .. " left for Hot Dog on a Stick.", false)
    st.pour = nil
    return
  end

  -- pouring a soda
  if st.pour then
    local p = st.pour
    local c = In.crank or 0
    p.flow = c > 0 and c or 0
    if c > 0 then p.fill = p.fill + c / 360 * 0.45 end
    if p.fill > 1.0 then
      st.spills = st.spills + 1
      p.fill = 0
      p.spillT = 30
      Sfx.bad()
    end
    if (p.spillT or 0) > 0 then p.spillT = p.spillT - 1 end
    if In.a and p.fill > 0.05 then
      local q = U.clamp(1 - (math.abs(p.fill - p.line) - st.tol) / 0.25, 0, 1)
      if math.abs(p.fill - p.line) <= st.tol then q = 1 end
      st.sodas[#st.sodas + 1] = q
      st.lastPour = q
      st.pour = nil
      if q >= 1 then Sfx.ok() else Sfx.tick() end
    elseif In.b then
      st.pour = nil
    end
    return
  end

  if In.left then st.cx = st.cx - 1; if st.cx < 1 then st.cx = 3 end end
  if In.right then st.cx = st.cx + 1; if st.cx > 3 then st.cx = 1 end end
  if In.up or In.down then st.cy = 3 - st.cy end
  if In.b then
    st.tray, st.sodas, st.napkins = {}, {}, 0
    Sfx.bad()
    return
  end
  if In.a then
    local cell = st.grid[st.cy][st.cx]
    if cell.kind == "main" then
      st.tray[cell.name] = (st.tray[cell.name] or 0) + 1
      Sfx.tick()
    elseif cell.kind == "soda" then
      st.pour = { fill = 0, line = 0.7 + st.r:f() * 0.15, flow = 0 }
    elseif cell.kind == "napkins" then
      st.napkins = st.napkins + 1
      Sfx.tick()
    else
      local s = scoreTray(st)
      st.points = st.points + s
      if s >= 100 then st.perfect = st.perfect + 1 end
      if s >= 75 then
        st.tips = st.tips + math.floor(tk.time / tk.max * 100) + st.r:i(0, 25)
        react(st, st.r:pick(HAPPY), true)
      elseif s >= 40 then
        react(st, st.r:pick(MEH), true)
      else
        react(st, st.r:pick(MAD), false)
      end
    end
  end
end

local function drawCup(st, x, y)
  local p = st.pour
  local w, h = 60, 90
  -- nozzle
  Gfx.fill(x - 10, y - 40, w + 20, 18, "black")
  Gfx.fill(x + w // 2 - 5, y - 22, 10, 8, "gray")
  if p.flow > 0 then Gfx.fill(x + w // 2 - 2, y - 14, 4, h + 12 - math.floor(p.fill * h), "gray") end
  -- cup body with fill
  local fh = math.floor(math.min(p.fill, 1) * h)
  Gfx.fill(x, y, w, h, "white")
  if fh > 0 then Gfx.fill(x + 1, y + h - fh, w - 2, fh, "dark") end
  Gfx.fill(x + 1, y + h - fh - 3, w - 2, 3, "dots")
  Gfx.rect(x, y, w, h)
  Gfx.rect(x - 1, y, w + 2, h)
  -- fill line
  local ly = y + h - math.floor(p.line * h)
  for k = 0, 6 do Gfx.line(x - 12 + k * 12, ly, x - 6 + k * 12, ly) end
  Gfx.text("FILL", x + w + 8, ly - 8, { bold = true })
  Gfx.fill(x + 16, y + 30, 28, 20, "white"); Gfx.rect(x + 16, y + 30, 28, 20)
  Gfx.text("L", x + 30, y + 32, { align = "center", bold = true })
  if (p.spillT or 0) > 0 then Gfx.text("SPLOOSH! New cup.", x + w // 2, y + h + 4, { align = "center", bold = true }) end
end

local function draw(st)
  Gfx.clear()
  Gfx.fill(0, 28, 400, 212, "tile")
  header(st, "ORDER " .. math.max(1, st.n) .. "/" .. st.total)
  local tk = st.tk
  -- ticket (paper slip)
  Gfx.fill(6, 34, 150, 176, "white")
  Gfx.rect(6, 34, 150, 176)
  Gfx.fill(6, 34, 150, 18, "black")
  if tk then
    Gfx.btext("TICKET: " .. tk.name, 12, 35)
    for i, l in ipairs(tk.lines) do Gfx.text(l, 12, 38 + i * 18) end
    Gfx.para('"' .. tk.quip .. '"', 12, 136, 136, { maxLines = 3, lh = 15 })
    Gfx.meter(12, 196, 138, 8, tk.time / tk.max)
  end

  if st.pour then
    Gfx.box(164, 34, 230, 182, "light")
    drawCup(st, 250, 96)
    Gfx.text("CRANK pour", 176, 190)
    Gfx.text("(A) done", 176, 44)
  else
    -- menu grid
    for gy = 1, 2 do
      for gx = 1, 3 do
        local cell = st.grid[gy][gx]
        local x, y = 164 + (gx - 1) * 78, 36 + (gy - 1) * 50
        local sel = (gx == st.cx and gy == st.cy)
        Gfx.box(x, y, 74, 46, sel and "dark" or "light")
        local lines = Gfx.wrap(cell.name, 60)
        for i, l in ipairs(lines) do
          if i <= 2 then Gfx.text(l, x + 37, y + 6 + (i - 1) * 15 + (#lines == 1 and 7 or 0), { align = "center", white = sel }) end
        end
      end
    end
    -- tray
    Gfx.fill(164, 140, 230, 72, "wave")
    Gfx.box(170, 144, 218, 64, "light")
    local items = {}
    for _, it in ipairs(st.mains) do
      if st.tray[it[1]] then items[#items + 1] = st.tray[it[1]] .. " " .. it[1] end
    end
    if #st.sodas > 0 then items[#items + 1] = #st.sodas .. " soda" end
    if st.napkins > 0 then items[#items + 1] = "napkins" end
    if #items == 0 then items[1] = "(empty tray)" end
    Gfx.para(U.join(items, ", "), 180, 150, 200, { maxLines = 3, lh = 16 })
  end
  if st.sayT > 0 then
    sayBox(st.say, 40, 90, 320, 50)
  end
  Gfx.prompt(st.pour and "CRANK pour to line  (A) Done  (B) Dump" or "D-pad pick  (A) Add  (B) Trash tray", nil, 218)
end

local function done(st) return st.over end

local function result(st)
  local score = U.clamp(math.floor(st.points / st.total + 0.5), 0, 100)
  local txt = string.format("%d/%d orders perfect, %d soda %s.", st.perfect, st.total, st.spills, U.plural(st.spills, "spill"))
  return { score = score, tips = st.tips, text = txt }
end

Minigames.register("food", {
  title = "Food Court Shift",
  help = { "Match each order ticket.", "D-pad moves, (A) adds to the tray.", "(B) trashes the tray.",
    "Soda: CRANK to pour up to the line.", "Overfill = spill. Serve fast for tips!" },
  new = new, update = update, draw = draw, done = done, result = result,
})
