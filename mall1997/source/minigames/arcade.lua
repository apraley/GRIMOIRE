-- ARCADE ATTENDANT: make token change, fix broken cabinets.
-- Crank dials token counts and unscrews panel screws.

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
  if c and #c > 0 and r:chance(0.5) then return (r:pick(c).first or "Some kid") end
  return r:pick(Names.teenFirst)
end

local FAULTS = {
  { "Screen rolls like a slot machine.", "monitor chassis" },
  { "It keeps rejecting my tokens!", "coin mech" },
  { "No sound. Just vibes.", "speaker" },
  { "Player 2 button is stuck down.", "button switch" },
  { "Smells like burnt popcorn. Won't boot.", "power supply" },
  { "Joystick only goes left. Like, only.", "joystick harness" },
  { "Picture is all green. Everyone looks sick.", "RGB cable" },
  { "Won't save my high score! I got 90,000!", "battery backup" },
}
local PARTS = { "monitor chassis", "coin mech", "speaker", "button switch", "power supply", "joystick harness",
  "RGB cable", "battery backup" }
local BILL_ASK = { "Tokens for this, please.", "Can I get tokens? My mom's at Sears for 3 hours.",
  "All of it in tokens. ALL of it.", "Tokens please. I'm going for the Skee-Roll record.",
  "My allowance. Tokens. Go." }
local JAM = { "(The change machine ate a Canadian quarter again.)", "(Change machine: OUT OF ORDER since 1994.)",
  "(The change machine is making a whale noise.)", "" , "" }

local function machineName(r)
  local pool = {}
  for _, g in ipairs(Content.ARCADE_GAMES or {}) do pool[#pool + 1] = g.name end
  for _, f in ipairs(Content.ARCADE_FLAVOR or {}) do pool[#pool + 1] = f end
  if #pool == 0 then pool = { "PINBALL" } end
  return r:pick(pool)
end

local function newTask(st)
  local r = st.r
  st.n = st.n + 1
  local task = { name = customerName(st.ctx, r) }
  if st.n % 2 == 1 then
    task.kind = "change"
    local bills = { 1, 5, 5, 10, 10, 20 }
    task.bill = r:pick(bills)
    task.need = task.bill * 4
    task.ask = r:pick(BILL_ASK)
    task.jam = r:pick(JAM)
    task.count = 0
    task.time = math.floor(30 * (20 - 7 * st.d))
  else
    task.kind = "repair"
    task.machine = machineName(r)
    local f = r:pick(FAULTS)
    task.symptom, task.part = f[1], f[2]
    local opts = { task.part }
    local others = {}
    for _, p in ipairs(PARTS) do if p ~= task.part then others[#others + 1] = p end end
    r:shuffle(others)
    opts[2], opts[3] = others[1], others[2]
    r:shuffle(opts)
    task.opts = opts
    task.sel = 1
    task.screw = 1
    task.turn = 0
    task.need = 360 + math.floor(180 * st.d)
    task.time = math.floor(30 * (40 - 10 * st.d))
  end
  task.max = task.time
  st.task = task
end

local function new(ctx)
  local r = ctx.rng
  local d = ctx.difficulty or 0
  local st = { r = r, ctx = ctx, d = d, t = 0, storeName = (ctx.store and ctx.store.name) or "Arcade",
    clockStart = 15 * 60, clockSpan = 240, n = 0, total = 8 + math.floor(d * 2 + 0.5),
    points = 0, tips = 0, fixed = 0, tokens = 0, sayT = 0, over = false, freebies = 0 }
  newTask(st)
  return st
end

local function say(st, line, pts, good)
  st.points = st.points + pts
  st.say = line
  st.sayT = 50
  if good then Sfx.ok() else Sfx.bad() end
end

local function update(st)
  st.t = st.t + 1
  if st.t >= SHIFT_FRAMES then st.over = true end
  if st.over then return end
  if st.sayT > 0 then
    st.sayT = st.sayT - 1
    if st.sayT == 0 then
      if st.n >= st.total then st.over = true return end
      newTask(st)
    end
    return
  end
  local task = st.task
  task.time = task.time - 1
  if task.time <= 0 then
    if task.kind == "change" then say(st, task.name .. " gave up and went to play pogs.", 0, false)
    else say(st, "The kid waiting for " .. task.machine .. " left crying.", 10, false) end
    return
  end
  local c = In.crank or 0
  if task.kind == "change" then
    local before = math.floor(task.count)
    task.count = U.clamp(task.count + c / 15, 0, 99)
    if In.up then task.count = math.floor(task.count) + 1 end
    if In.down then task.count = math.max(0, math.floor(task.count) - 1) end
    if In.right then task.count = math.min(99, math.floor(task.count) + 4) end
    if In.left then task.count = math.max(0, math.floor(task.count) - 4) end
    if math.floor(task.count) ~= before then Sfx.tick() end
    if In.a then
      local give = math.floor(task.count)
      local diff = give - task.need
      st.tokens = st.tokens + give
      if diff == 0 then
        st.tips = st.tips + (st.r:chance(0.3) and 25 or 0)
        say(st, "Sweet. " .. give .. " tokens. (Tips you a token.)", 100, true)
      elseif diff < 0 then
        say(st, "Hey! That's only " .. give .. ". I counted!", math.max(0, 100 + diff * 15), false)
      else
        st.freebies = st.freebies + diff
        say(st, "Score! " .. diff .. " free games. Don't tell.", math.max(0, 100 - diff * 20), false)
      end
    end
  else
    if task.screw <= 4 then
      if c < 0 then
        task.turn = task.turn - c
        if task.turn >= task.need then
          task.turn = 0
          task.screw = task.screw + 1
          Sfx.tick()
        end
      end
    else
      if In.up then task.sel = task.sel - 1; if task.sel < 1 then task.sel = 3 end end
      if In.down then task.sel = task.sel + 1; if task.sel > 3 then task.sel = 1 end end
      if In.a then
        local pick = task.opts[task.sel]
        if pick == task.part then
          st.fixed = st.fixed + 1
          st.tips = st.tips + st.r:i(0, 50)
          say(st, task.machine .. " is back! Kids cheer.", 60 + math.floor(40 * task.time / task.max), true)
        else
          say(st, "Replaced the " .. pick .. ". Still broken.", 20, false)
        end
      end
    end
  end
end

local function drawChange(st, task)
  Gfx.box(4, 32, 392, 56, "light")
  Gfx.text(task.name .. ":", 14, 38, { bold = true })
  Gfx.para(task.ask, 14, 54, 370, { maxLines = 2, lh = 15 })
  Gfx.meter(300, 40, 84, 8, task.time / task.max)
  -- the bill
  Gfx.fill(16, 100, 150, 66, "light")
  Gfx.rect(16, 100, 150, 66)
  Gfx.rect(20, 104, 142, 58)
  Gfx.circle(91, 133, 18, true, "white")
  Gfx.circle(91, 133, 18, false)
  Gfx.text("$" .. task.bill, 91, 125, { align = "center", bold = true })
  Gfx.text(tostring(task.bill), 26, 106, { bold = true })
  Gfx.text(tostring(task.bill), 156, 146, { bold = true, align = "right" })
  Gfx.text("4 tokens = $1", 91, 172, { align = "center" })
  -- token dial
  Gfx.box(190, 96, 200, 104, "dark")
  Gfx.btext("TOKENS TO HAND OVER", 290, 104, { align = "center" })
  local n = math.floor(task.count)
  Gfx.btext(string.format("%02d", n), 290, 128, { align = "center", bold = true })
  -- token stacks
  local stacks = n // 10
  for i = 0, math.min(stacks, 9) - 1 do
    Gfx.circle(208 + i * 18, 170, 7, true, "white")
    Gfx.circle(208 + i * 18, 170, 4, false)
  end
  for i = 0, (n % 10) - 1 do Gfx.circle(210 + i * 6, 186, 2, true, "white") end
  if task.jam ~= "" then Gfx.text(task.jam, 200, 202, { align = "center" }) end
end

local function drawRepair(st, task)
  Gfx.box(4, 32, 392, 56, "light")
  Gfx.text(task.machine .. " - kid reports:", 14, 38, { bold = true })
  Gfx.text('"' .. task.symptom .. '"', 14, 56)
  Gfx.meter(300, 40, 84, 8, task.time / task.max)
  -- cabinet panel
  local x, y, w, h = 20, 96, 160, 116
  if task.screw <= 4 then
    Gfx.fill(x, y, w, h, "grate")
    Gfx.rect(x, y, w, h)
    Gfx.box(x + 30, y + 40, 100, 36, "dark")
    Gfx.btext("SERVICE", x + 80, y + 50, { align = "center", bold = true })
    local pos = { { x + 12, y + 12 }, { x + w - 12, y + 12 }, { x + 12, y + h - 12 }, { x + w - 12, y + h - 12 } }
    for i, p in ipairs(pos) do
      if i >= task.screw then
        Gfx.circle(p[1], p[2], 8, true, "white")
        Gfx.circle(p[1], p[2], 8, false)
        local a = (i == task.screw) and math.rad(-task.turn) or 0.6
        local dx, dy = math.floor(math.cos(a) * 6), math.floor(math.sin(a) * 6)
        Gfx.line(p[1] - dx, p[2] - dy, p[1] + dx, p[2] + dy)
        if i == task.screw then Gfx.circle(p[1], p[2], 11, false) end
      else
        Gfx.circle(p[1], p[2], 3, true)
      end
    end
    Gfx.box(196, 100, 196, 90, "dark")
    Gfx.btext("Screw " .. task.screw .. " of 4", 294, 110, { align = "center", bold = true })
    Gfx.btext("Lefty-loosey:", 294, 132, { align = "center" })
    Gfx.btext("CRANK backwards", 294, 150, { align = "center" })
    Gfx.meter(216, 172, 156, 8, task.turn / task.need, nil, true)
  else
    Gfx.fill(x, y, w, h, "black")
    Gfx.fill(x + 10, y + 8, 60, 44, "gray")
    Gfx.rect(x + 10, y + 8, 60, 44, "white")
    Gfx.fill(x + 84, y + 12, 60, 20, "white")
    Gfx.fill(x + 84, y + 40, 30, 30, "diag")
    Gfx.circle(x + 130, y + 80, 14, true, "white")
    Gfx.circle(x + 130, y + 80, 6, true)
    Gfx.fill(x + 10, y + 70, 80, 8, "hstripe")
    Gfx.fill(x + 10, y + 90, 90, 14, "check")
    Gfx.text("Which part is bad?", 294, 94, { align = "center", bold = true })
    Gfx.menu(task.opts, task.sel, 196, 112, 196, "dark")
  end
end

local function draw(st)
  Gfx.clear()
  Gfx.fill(0, 28, 400, 212, "carpet")
  local task = st.task
  header(st, (task.kind == "change" and "CHANGE " or "REPAIR ") .. st.n .. "/" .. st.total)
  if task.kind == "change" then drawChange(st, task) else drawRepair(st, task) end
  if st.sayT > 0 then
    sayBox(st.say, 30, 110, 340, 50)
  end
  if task.kind == "change" then Gfx.prompt("CRANK/D-pad count  (A) Hand over", nil, 218)
  elseif task.screw <= 4 then Gfx.prompt("CRANK backwards to unscrew", nil, 218)
  else Gfx.prompt("UP/DOWN choose  (A) Replace part", nil, 218) end
end

local function done(st) return st.over end

local function result(st)
  local score = U.clamp(math.floor(st.points / st.total + 0.5), 0, 100)
  local txt = string.format("Handed out %d tokens, fixed %d %s.", st.tokens, st.fixed, U.plural(st.fixed, "cabinet"))
  if st.freebies > 0 then txt = txt .. " " .. st.freebies .. " " .. U.plural(st.freebies, "free game") .. " leaked." end
  return { score = score, tips = st.tips, text = txt }
end

Minigames.register("arcade", {
  title = "Arcade Attendant Shift",
  help = { "Token change: 4 tokens per dollar.", "CRANK dials the count, (A) hands over.",
    "Repairs: CRANK backwards to unscrew,", "then pick the bad part from the symptom." },
  new = new, update = update, draw = draw, done = done, result = result,
})
