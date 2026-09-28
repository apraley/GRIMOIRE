-- BOOKSTORE: shelve books alphabetically by author, help customers find titles.
-- Crank slides the insertion cursor along the shelf; A inserts.

local gfx = playdate.graphics

local SHIFT_FRAMES = 30 * 110

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

local TITLE_T = { "The {w} of {n}", "{n}'s Last Summer", "Chicken Broth for the {x} Soul", "Zen and the Art of {x}",
  "Men Are From {p}", "{w}: A Memoir", "The Celestine {w}", "Who Moved My {x}?", "A Brief History of {x}",
  "The {w} Diaries", "Midnight in the {x}", "{n} and the {w}", "Seven Habits of {x}", "The Bridges of {c}",
  "Into Thin {x}", "Waiting to {w}", "The {x} Whisperer", "Snow Falling on {n}" }
local WORDS = { "Horizon", "Shadow", "Legacy", "Pressure", "Secret", "Promise", "Silence", "Harvest", "Exhale", "Velocity" }
local THINGS = { "Teen", "Mall", "Cheese", "Dial-Up", "Minivan", "Beanie Baby", "Carpool", "Pager", "Horse", "Golf", "Tupperware" }
local PLANETS = { "Mars", "Venus", "Pluto", "Ohio", "Jupiter" }
local ASK = { "Do you have {t}? My book club meets tonight.", "Looking for {t}. Oprah said so.",
  "Um, {t}? It's for a friend.", "Do you carry {t}? The cover was blue. Or green." }
local GOOD = { "Shelved. The spines align. Beautiful.", "Perfect spot.", "Alphabetical bliss." }
local BAD = { "Wrong spot. A coworker sighs and fixes it.", "Nope. That's not how the alphabet works.",
  "A regular gasps. You fix it." }

local function key(s) return (string.lower(s):gsub("[^a-z]", "")) end

local function makeBook(st)
  local r = st.r
  local custs = st.ctx.customers or {}
  local last
  if #custs > 0 and r:chance(0.2) then last = r:pick(custs).last end
  last = last or r:pick(Names.last)
  local ini = string.char(64 + r:i(1, 26))
  local title = U.fmt(r:pick(TITLE_T), { w = r:pick(WORDS), n = r:pick(Names.teenFirst), x = r:pick(THINGS),
    p = r:pick(PLANETS), c = r:pick(Names.cities or { "Omaha" }) })
  return { last = last, ini = ini, title = title, k = key(last), pat = r:pick({ "white", "gray", "light", "dots", "diag", "hstripe", "dark" }), h = r:i(0, 16) }
end

local function sortShelf(t) table.sort(t, function(a, b) return a.k < b.k end) end

local function validGap(shelf, b, g)
  local left, right = shelf[g], shelf[g + 1]
  if left and left.k > b.k then return false end
  if right and right.k < b.k then return false end
  return true
end

local function correctGap(shelf, b)
  for g = 0, #shelf do if validGap(shelf, b, g) then return g end end
  return #shelf
end

local function nextTask(st)
  local r = st.r
  st.n = st.n + 1
  st.task = {}
  local t = st.task
  if st.n % 4 == 0 and #st.shelf > 4 then
    t.kind = "find"
    t.book = r:pick(st.shelf)
    t.ask = U.fmt(r:pick(ASK), { t = '"' .. t.book.title .. '"' })
    if r:chance(0.5) then t.ask = t.ask .. " By " .. t.book.last .. "?" end
    t.name = r:pick(Names.adultFirst)
    t.time = math.floor(30 * (24 - 8 * st.d))
    t.max = t.time
    t.misses = 0
    st.cur = math.floor(st.cur) + 0.5
  else
    t.kind = "shelve"
    t.book = makeBook(st)
  end
end

local function new(ctx)
  local r = ctx.rng
  local d = ctx.difficulty or 0
  local st = { r = r, ctx = ctx, d = d, t = 0, storeName = (ctx.store and ctx.store.name) or "Bookstore",
    clockStart = 13 * 60, clockSpan = 240, shelf = {}, cur = 5, n = 0,
    total = 14 + math.floor(d * 4 + 0.5), points = 0, tips = 0, right = 0, sayT = 0, over = false, found = 0 }
  for i = 1, 10 do st.shelf[i] = makeBook(st) end
  sortShelf(st.shelf)
  nextTask(st)
  return st
end

local function say(st, s, pts, good)
  st.say = s
  st.sayT = 35
  st.points = st.points + pts
  if good then Sfx.ok() else Sfx.bad() end
end

local function update(st)
  st.t = st.t + 1
  if st.t >= SHIFT_FRAMES then st.over = true end
  if st.over then return end
  local t = st.task
  local n = #st.shelf
  local before = math.floor(st.cur)
  local maxc = n + 0.99
  local minc = (t.kind == "find") and 1 or 0
  st.cur = U.clamp(st.cur + (In.crank or 0) / 30, minc, maxc)
  if In.left then st.cur = U.clamp(math.floor(st.cur) - 1, minc, maxc) end
  if In.right then st.cur = U.clamp(math.floor(st.cur) + 1, minc, maxc) end
  if math.floor(st.cur) ~= before then Sfx.tick() end

  if st.sayT > 0 then
    st.sayT = st.sayT - 1
    if st.sayT == 0 then
      if st.n >= st.total then st.over = true return end
      nextTask(st)
    end
    return
  end
  if t.kind == "find" then
    t.time = t.time - 1
    if t.time <= 0 then say(st, t.name .. " is going to Crown Books instead.", 0, false) return end
    if In.a then
      local b = st.shelf[math.floor(st.cur)]
      if b == t.book then
        st.found = st.found + 1
        st.tips = st.tips + st.r:i(0, 50)
        say(st, "That's it! You're a lifesaver.", math.max(30, 100 - t.misses * 25), true)
      else
        t.misses = t.misses + 1
        t.time = t.time - 45
        st.say = "No, that's \"" .. (b and b.title or "?") .. "\"."
        st.missT = 30
        Sfx.bad()
      end
    end
  else
    if In.a then
      local g = math.floor(st.cur)
      local b = t.book
      local cg = correctGap(st.shelf, b)
      if validGap(st.shelf, b, g) then
        st.right = st.right + 1
        table.insert(st.shelf, g + 1, b)
        say(st, st.r:pick(GOOD), 100, true)
      else
        local dist = math.abs(g - cg)
        table.insert(st.shelf, cg + 1, b)
        say(st, st.r:pick(BAD), math.max(0, 70 - 20 * dist), false)
      end
      -- somebody buys a book so the shelf never overflows
      if #st.shelf > 22 then table.remove(st.shelf, st.r:i(1, #st.shelf)) end
    end
  end
  if (st.missT or 0) > 0 then st.missT = st.missT - 1 end
end

local function draw(st)
  Gfx.clear()
  Gfx.fill(0, 28, 400, 212, "carpet")
  header(st, "TASK " .. st.n .. "/" .. st.total)
  local t = st.task
  local b = t.book
  -- top card
  if t.kind == "shelve" then
    Gfx.box(4, 32, 392, 54, "light")
    Gfx.text("SHELVE:", 14, 38, { bold = true })
    Gfx.text(string.upper(b.last) .. ", " .. b.ini .. ".", 86, 38, { bold = true })
    Gfx.text(fit('"' .. b.title .. '"', 370), 14, 58)
  else
    Gfx.box(4, 32, 392, 54, "light")
    Gfx.text(t.name .. ":", 14, 38, { bold = true })
    local line = ((st.missT or 0) > 0 and st.say) or t.ask
    Gfx.para(line, 90, 38, 296, { maxLines = 2, lh = 16 })
    Gfx.meter(14, 62, 64, 8, t.time / t.max)
  end
  -- the shelf
  Gfx.fill(4, 92, 392, 100, "brick")
  Gfx.fill(4, 184, 392, 10, "black")
  local n = #st.shelf
  local c = math.floor(st.cur)
  local first = U.clamp(c - 6, 1, math.max(1, n - 12))
  local W = 28
  local cursorX
  for k = 0, 12 do
    local i = first + k
    local bk = st.shelf[i]
    if not bk then break end
    local x = 12 + k * W
    local h = 70 + bk.h
    local y = 184 - h
    local sel = (t.kind == "find" and i == c)
    Gfx.fill(x, y, W - 2, h, sel and "black" or bk.pat)
    Gfx.rect(x, y, W - 2, h)
    Gfx.fill(x + 2, y + 8, W - 6, 16, sel and "black" or "white")
    Gfx.text(string.sub(string.upper(bk.last), 1, 3), x + (W - 2) // 2, y + 8, { align = "center", white = sel })
    if t.kind == "shelve" and i == c then cursorX = x + W - 2 end
    if t.kind == "shelve" and c == 0 and k == 0 then cursorX = x - 2 end
  end
  if t.kind == "shelve" then
    cursorX = cursorX or (12 + math.min(n - first + 1, 13) * W - 2)
    Gfx.fill(cursorX - 1, 96, 4, 88, "black")
    Gfx.tri(cursorX - 2, 88, "down", false)
  end
  -- info strip
  Gfx.box(4, 194, 392, 26, "dark")
  if t.kind == "find" then
    local bk = st.shelf[c]
    if bk then Gfx.btext(fit(bk.last .. ": " .. bk.title, 370), 200, 199, { align = "center" }) end
  else
    local l, r = st.shelf[c], st.shelf[c + 1]
    Gfx.btext((l and l.last or "[start]") .. "  |  " .. (r and r.last or "[end]"), 200, 199, { align = "center" })
  end
  if st.sayT > 0 then
    sayBox(st.say, 30, 108, 340, 50)
  end
  Gfx.prompt(t.kind == "find" and "CRANK browse spines  (A) That one!" or "CRANK move gap  (A) Insert book", nil, 220)
end

local function done(st) return st.over end

local function result(st)
  local score = U.clamp(math.floor(st.points / st.total + 0.5), 0, 100)
  return { score = score, tips = st.tips,
    text = string.format("Shelved %d %s correctly, found %d for customers.", st.right, U.plural(st.right, "book"), st.found) }
end

Minigames.register("books", {
  title = "Bookstore Shift",
  help = { "Shelve by author LAST NAME, A to Z.", "CRANK slides the gap along the shelf,",
    "(A) inserts the book there.", "Customers ask for titles: CRANK through", "the spines and (A) on the right one." },
  new = new, update = update, draw = draw, done = done, result = result,
})
