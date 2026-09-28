-- ONE HOUR PHOTO: crank film through the processor at a steady speed,
-- then stuff each print stack into the right customer envelope.

local gfx = playdate.graphics

local DEV_LEN = 30 * 52
local MATCH_LEN = 30 * 48
local CARD_LEN = 45
local SHIFT_FRAMES = DEV_LEN + MATCH_LEN + CARD_LEN * 2

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

local PRINTS = { "14 photos of the same dog", "someone's thumb, x24", "a very blurry Hanson concert",
  "Grandma at Olive Garden, 24 angles", "prom 1997. So much teal.", "sunset, sunset, sunset, sunset",
  "a cat inside a Pringles can", "the inside of a pocket", "a man holding a large fish",
  "Disney World, mostly the line", "a Beanie Baby collection, cataloged", "a car. Just a parked car.",
  "the Grand Canyon, finger included", "a birthday cake on fire (on purpose?)", "a guy's new Camaro, 22 shots",
  "a wedding, but only the buffet" }
local HAPPY = { "These came out great!", "Oh, Biscuit looks SO cute.", "Worth every penny of $8.99." }
local WRONG = { "{n} got 24 photos of a stranger's bachelor party.", "{n} opened the envelope and gasped.",
  "{n}: 'I don't own a ferret. Who is this?'" }

local function uniqueRolls(r, n)
  local out, used = {}, {}
  local base = tostring(r:i(1000, 9999))
  while #out < n do
    local s
    if #out > 0 and r:chance(0.6) then
      -- a lookalike: swap two digits of an existing roll number
      local src = r:pick(out)
      local i, j = r:i(1, 4), r:i(1, 4)
      local t = {}
      for k = 1, 4 do t[k] = src:sub(k, k) end
      t[i], t[j] = t[j], t[i]
      if i == j then t[i] = tostring((tonumber(t[i]) + 1) % 10) end
      s = table.concat(t)
    else
      s = tostring(r:i(1000, 9999))
      if r:chance(0.5) then s = base:sub(1, 2) .. s:sub(3, 4) end
    end
    if not used[s] and s:sub(1, 1) ~= "0" then used[s] = true; out[#out + 1] = s end
  end
  return out
end

local function new(ctx)
  local r = ctx.rng
  local d = ctx.difficulty or 0
  local n = 5 + math.floor(d * 2 + 0.5)
  local st = { r = r, ctx = ctx, d = d, t = 0, storeName = (ctx.store and ctx.store.name) or "One Hour Photo",
    clockStart = 10 * 60, clockSpan = 300, phase = 1, pt = 0, card = CARD_LEN, over = false, tips = 0,
    rolls = {}, cur = 1, prog = 0, spd = 0, rollLen = 1400, inBand = 0, fast = 0, slow = 0, frames = 0,
    bandLo = 7 + 1.5 * d, bandHi = 14 - 1.5 * d, strip = 0,
    sel = 1, env = 1, matched = 0, sayT = 0 }
  local nums = uniqueRolls(r, n)
  local prints = {}
  for i = 1, #PRINTS do prints[i] = PRINTS[i] end
  r:shuffle(prints)
  local custs = ctx.customers or {}
  for i = 1, n do
    local last
    if #custs > 0 and r:chance(0.5) then last = r:pick(custs).last end
    last = last or r:pick(Names.last)
    st.rolls[i] = { name = last, num = nums[i], print = prints[i], quality = 0, done = false, verdict = "stuck" }
  end
  return st
end

local function setupMatch(st)
  st.stacks = {}
  for i, rl in ipairs(st.rolls) do st.stacks[i] = rl end
  st.r:shuffle(st.stacks)
  st.envs = {}
  for i, rl in ipairs(st.rolls) do st.envs[i] = rl end
  st.r:shuffle(st.envs)
  st.env = 1
  st.sel = 1
end

local function finishRoll(st)
  local rl = st.rolls[st.cur]
  local f = math.max(1, st.frames)
  rl.quality = st.inBand / f
  rl.done = true
  if rl.quality >= 0.7 then rl.verdict = "crisp"
  elseif st.fast > st.slow then rl.verdict = "washed out"
  else rl.verdict = "too dark" end
  st.cur = st.cur + 1
  st.prog, st.inBand, st.fast, st.slow, st.frames = 0, 0, 0, 0, 0
  if rl.quality >= 0.7 then Sfx.ok() else Sfx.bad() end
end

local function updDev(st)
  local c = In.crank or 0
  st.spd = st.spd * 0.85 + c * 0.15
  if st.cur > #st.rolls then return end
  st.frames = st.frames + 1
  if c > 0 then st.prog = st.prog + c; st.strip = (st.strip + c / 4) % 40 end
  if st.spd >= st.bandLo and st.spd <= st.bandHi then st.inBand = st.inBand + 1
  elseif st.spd > st.bandHi then st.fast = st.fast + 1
  else st.slow = st.slow + 1 end
  if st.prog >= st.rollLen then finishRoll(st) end
end

local function updMatch(st)
  if st.sayT > 0 then st.sayT = st.sayT - 1 return end
  if st.env > #st.envs or #st.stacks == 0 then return end
  if In.up then st.sel = st.sel - 1; if st.sel < 1 then st.sel = #st.stacks end end
  if In.down then st.sel = st.sel + 1; if st.sel > #st.stacks then st.sel = 1 end end
  if In.a then
    local e = st.envs[st.env]
    local s = st.stacks[st.sel]
    if s == e then
      st.matched = st.matched + 1
      st.tips = st.tips + math.floor(25 + 50 * s.quality)
      st.say = e.name .. ": " .. (s.quality >= 0.7 and st.r:pick(HAPPY) or ("Why are these " .. s.verdict .. "?"))
      Sfx.ok()
    else
      st.say = U.fmt(st.r:pick(WRONG), { n = e.name })
      Sfx.bad()
    end
    st.sayT = 40
    table.remove(st.stacks, st.sel)
    st.env = st.env + 1
    if st.sel > #st.stacks then st.sel = math.max(1, #st.stacks) end
  end
end

local function update(st)
  st.t = st.t + 1
  if st.over then return end
  if st.card > 0 then st.card = st.card - 1 return end
  st.pt = st.pt + 1
  if st.phase == 1 then
    updDev(st)
    if st.pt >= DEV_LEN or st.cur > #st.rolls then
      if st.cur <= #st.rolls and st.frames > 0 then
        -- a partly developed roll counts, poorly
        local rl = st.rolls[st.cur]
        rl.quality = (st.inBand / st.frames) * (st.prog / st.rollLen)
        rl.verdict = "half developed"
      end
      st.phase, st.pt, st.card = 2, 0, CARD_LEN
      setupMatch(st)
    end
  else
    updMatch(st)
    if st.pt >= MATCH_LEN or (st.env > #st.envs and st.sayT == 0) then st.over = true end
  end
end

-- ---------------------------------------------------------------- draw
local function drawDev(st)
  Gfx.fill(0, 28, 400, 212, "dark")
  local rl = st.rolls[math.min(st.cur, #st.rolls)]
  Gfx.box(4, 32, 392, 40, "light")
  if st.cur <= #st.rolls then
    Gfx.text("Roll " .. st.cur .. "/" .. #st.rolls .. ": #" .. rl.num .. " (" .. rl.name .. ")", 14, 42, { bold = true })
  else
    Gfx.text("All rolls developed! Waiting on the dryer...", 14, 42, { bold = true })
  end
  -- processor machine
  Gfx.fill(10, 80, 220, 130, "white")
  Gfx.rect(10, 80, 220, 130)
  Gfx.rect(12, 82, 216, 126)
  Gfx.fill(20, 90, 200, 20, "black")
  Gfx.btext("KODAMATIC 2000", 120, 92, { align = "center", bold = true })
  -- film strip
  Gfx.fill(20, 130, 200, 34, "black")
  local off = math.floor(st.strip)
  for k = -1, 5 do
    local x = 20 + k * 40 + off
    if x > 14 and x < 216 then
      Gfx.fill(x + 4, 136, 28, 22, "gray")
      Gfx.fill(x + 1, 131, 4, 3, "white")
      Gfx.fill(x + 1, 160, 4, 3, "white")
    end
  end
  Gfx.circle(26, 147, 10, true, "white"); Gfx.circle(26, 147, 10, false)
  Gfx.circle(214, 147, 10, true, "white"); Gfx.circle(214, 147, 10, false)
  Gfx.meter(24, 186, 192, 10, st.prog / st.rollLen)
  -- speed gauge
  local cx, cy, R = 312, 170, 70
  Gfx.box(236, 80, 160, 130, "light")
  local function ang(v) return -90 + U.clamp(v, 0, 20) / 20 * 180 end
  gfx.setLineWidth(8)
  gfx.setPattern(Gfx.P.gray)
  gfx.drawArc(cx, cy, R - 12, ang(st.bandLo), ang(st.bandHi))
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(1)
  gfx.drawArc(cx, cy, R - 6, -90, 90)
  local a = math.rad(ang(st.spd) - 90)
  Gfx.line(cx, cy, cx + math.floor(math.cos(a) * (R - 12)), cy + math.floor(math.sin(a) * (R - 12)))
  Gfx.circle(cx, cy, 4, true)
  Gfx.text("DARK", 248, 176)
  Gfx.text("WASHED", 384, 176, { align = "right" })
  local inb = st.spd >= st.bandLo and st.spd <= st.bandHi
  Gfx.text(inb and "GOOD" or (st.spd > st.bandHi and "TOO FAST" or "TOO SLOW"), cx, 188, { align = "center", bold = true })
  Gfx.prompt("CRANK steadily - keep the needle in the band", nil, 218)
end

local function drawMatch(st)
  Gfx.fill(0, 28, 400, 212, "carpet")
  local e = st.envs[math.min(st.env, #st.envs)]
  -- envelope
  Gfx.fill(8, 36, 170, 120, "white")
  Gfx.rect(8, 36, 170, 120)
  gfx.drawLine(8, 36, 93, 80)
  gfx.drawLine(178, 36, 93, 80)
  if st.env <= #st.envs then
    Gfx.fill(20, 96, 146, 50, "white")
    Gfx.rect(20, 96, 146, 50)
    Gfx.text(string.upper(e.name), 93, 100, { align = "center", bold = true })
    Gfx.text("ROLL #" .. e.num, 93, 122, { align = "center" })
  end
  Gfx.text("Envelope " .. math.min(st.env, #st.envs) .. "/" .. #st.envs, 93, 160, { align = "center", bold = true })
  -- print stacks
  local y0 = 34
  for i, s in ipairs(st.stacks) do
    local y = y0 + (i - 1) * 30
    local sel = (i == st.sel)
    Gfx.box(186, y, 210, 29, sel and "dark" or "light")
    Gfx.text("#" .. s.num, 196, y + 6, { bold = true, white = sel })
    local desc = fit(s.print, 140, false)
    Gfx.text(desc, 246, y + 6, { white = sel })
  end
  if st.stacks[st.sel] then
    Gfx.box(8, 176, 170, 40, "dark")
    Gfx.btext("Prints: " .. st.stacks[st.sel].verdict, 18, 188)
  end
  if st.sayT > 0 then
    Gfx.box(10, 100, 380, 50, "dark")
    Gfx.para(st.say, 22, 108, 356, { white = true, maxLines = 2, lh = 16 })
  end
  Gfx.prompt("UP/DOWN pick stack  (A) Into envelope", nil, 218)
end

local function draw(st)
  Gfx.clear()
  header(st, st.phase == 1 and "DEVELOPING" or "PICKUP")
  if st.card > 0 then
    Gfx.fill(0, 28, 400, 212, "dark")
    Gfx.box(50, 80, 300, 80, "dark")
    Gfx.btext(st.phase == 1 and "PART 1: THE PROCESSOR" or "PART 2: CUSTOMER PICKUP", 200, 94, { align = "center", bold = true })
    Gfx.btext(st.phase == 1 and "Crank film at a steady pace." or "Match prints to envelopes.", 200, 118, { align = "center" })
    return
  end
  if st.phase == 1 then drawDev(st) else drawMatch(st) end
end

local function done(st) return st.over end

local function result(st)
  local q = 0
  for _, rl in ipairs(st.rolls) do q = q + rl.quality end
  q = q / #st.rolls
  local m = st.matched / #st.rolls
  local score = U.clamp(math.floor((0.5 * q + 0.5 * m) * 100 + 0.5), 0, 100)
  local crisp = 0
  for _, rl in ipairs(st.rolls) do if rl.verdict == "crisp" then crisp = crisp + 1 end end
  return { score = score, tips = st.tips,
    text = string.format("%d/%d rolls crisp, %d/%d envelopes right. %s", crisp, #st.rolls, st.matched, #st.rolls,
      m < 0.5 and "Somebody got the ferret photos." or "Nobody saw anything weird.") }
end

Minigames.register("photo", {
  title = "Photo Lab Shift",
  help = { "1) CRANK film through the processor.", "   Keep the needle in the gray band:",
    "   too fast = washed out, slow = dark.", "2) UP/DOWN pick a print stack,", "   (A) puts it in the envelope." },
  new = new, update = update, draw = draw, done = done, result = result,
})
