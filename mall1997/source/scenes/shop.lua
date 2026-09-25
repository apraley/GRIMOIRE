-- Store UI: counters, crank-browsing racks (records, tapes, clothes...),
-- buying, concealing, food stalls, the cinema box office, kiosks.

Shop = {}

local function clerk(s)
  local staff = Stores.presentStaff(s)
  for _, n in ipairs(staff) do if n.title ~= "manager" then return n end end
  return staff[1]
end

local function manager(s)
  local m = s.mgr and W.npcs[s.mgr]
  if m and m.loc == Areas.storeArea(s) and not m.route then return m end
end

function Shop.buy(it, s, after)
  local n = clerk(s)
  local ok, msg = Econ.buy(it, s)
  if ok then Sfx.ok() else Sfx.bad() end
  Say(msg, { npc = n, name = n and n.first, after = after })
end

-- ------------------------------------------------------------------ counter
function Shop.counter(s)
  local p = W.p
  local n = clerk(s)
  local opts, acts = {}, {}
  local function add(label, fn) opts[#opts + 1] = label; acts[#acts + 1] = fn end
  if n then add("Talk to " .. n.first, function() Dialog.open(n) end) end
  local m = manager(s)
  if p.job and p.job.store == s.id then
    add("Clock in", function() Play.clockIn() end)
  else
    add("Ask about a job", function()
      if not m then Say("\"The manager's not in right now. Try later.\"", { npc = n, name = n and n.first }) return end
      if s.hiring then Dialog.card = nil; Dialog.interview(m, s.id)
      else Say("\"We're not hiring right now. Check back.\"", { npc = m, name = m.first }) end
    end)
  end
  if s.type == "video" then
    for _, it in ipairs(p.inv) do
      if it.due and it.store == s.id then
        add("Return " .. it.n:sub(1, 22), function() Say(PlayerSim.returnRental(it)) end)
      end
    end
  end
  if s.type == "photo" then
    add("Buy a disposable camera", function()
      Shop.buy({ k = "photo", n = "disposable camera", v = 999 }, s)
    end)
  end
  if s.type == "restaurant" then
    add("Order food", function() Shop.menuBuy(s, Econ.rack(s, 1)) end)
  end
  add("Look around", function()
    local lines = { s.name .. " — " .. MallGen.TYPE_LABEL[s.type] .. ". " .. s.flavor }
    if s.sale > 0 then lines[#lines + 1] = "A sign says " .. s.sale .. "% OFF EVERYTHING." end
    if s.closing then lines[#lines + 1] = "STORE CLOSING. EVERYTHING MUST GO." end
    if s.hiring then lines[#lines + 1] = "There's a NOW HIRING card taped to the register." end
    if s.feud then lines[#lines + 1] = "Someone has taped a passive-aggressive note to the wall about " .. W.stores[s.feud].name .. "." end
    Say(lines)
  end)
  Choose(s.name:upper(), opts, function(i) acts[i]() end, {})
end

function Shop.menuBuy(s, items)
  local labels = {}
  for i, it in ipairs(items) do labels[i] = it.n .. "  " .. U.money(it.v) end
  Choose("MENU", labels, function(i) Shop.buy(items[i], s) end, {})
end

-- ------------------------------------------------------------------ browse
-- Crank flips through the rack; each item is a big card (sleeve, tape box,
-- garment). A buys, DOWN tries to slip it into your backpack.
local browse = {}

function Shop.browse(s, o)
  local items, label = Econ.rack(s, o.idx or 1)
  if #items == 0 then Say("This rack is picked clean.") return end
  local sc = setmetatable({ s = s, items = items, label = label or "", idx = 1, flip = 0, crank = Input.crankStepper(40),
    obj = o }, { __index = browse })
  Scene.push(sc)
end

function browse:update()
  local steps = self.crank(In.crank)
  if In.lr then steps = steps - 1 end
  if In.rr then steps = steps + 1 end
  if steps ~= 0 then
    local before = self.idx
    self.idx = U.clamp(self.idx + steps, 1, #self.items)
    if self.idx ~= before then self.flip = 8 * U.sign(steps); Sfx.tick() end
  end
  if self.flip ~= 0 then self.flip = self.flip - U.sign(self.flip) end
  local it = self.items[self.idx]
  if In.a then
    Confirm("Buy " .. it.n .. " for " .. U.money(it.v) .. "?", function()
      Shop.buy(it, self.s, function()
        if it.k ~= "vhs" then table.remove(self.items, self.idx) end
        if #self.items == 0 then Scene.pop() else self.idx = U.clamp(self.idx, 1, #self.items) end
      end)
    end)
  elseif In.down then
    self:conceal(it)
  elseif In.b then
    Scene.pop()
  end
end

function browse:conceal(it)
  local p = W.p
  local rep = Security.concealCheck(self.s, p.x, p.y)
  local risk = math.floor(rep.risk * 100)
  local watchers = #rep.seen
  local warn = risk < 20 and "Nobody seems to be looking." or risk < 50 and "A clerk is kind of nearby." or "Feels like everyone can see you."
  Choose(nil, { "Slip it in the backpack", "Put it back" }, function(i)
    if i == 1 then
      Security.conceal(self.s, it, rep)
      table.remove(self.items, self.idx)
      Toast.show("It's in the bag. Now walk out.", 60)
      if #self.items == 0 then Scene.pop() else self.idx = U.clamp(self.idx, 1, #self.items) end
      if watchers > 0 then
        local n = W.npcs[rep.seen[1]]
        if n then Explore.bubble(n, n.job == self.s.id and "..." or "!?", 60) end
      end
    else
      W.p.conf = U.clamp(W.p.conf + 1, 0, 100)
    end
  end, { prompt = "Your heart is pounding. " .. warn .. " (risk ~" .. risk .. "%)", y = 90 })
end

local function sleeve(it, x, y, size)
  local gfx = playdate.graphics
  local h = U.hash(it.n)
  Gfx.fill(x, y, size, size, "white")
  if it.k == "album" then
    -- procedural cover art: pattern + shape from the name hash
    local pats = { "gray", "diag", "check", "dots", "hstripe", "wave", "brick", "dark" }
    Gfx.fill(x, y, size, size, pats[(h % #pats) + 1])
    gfx.setColor(gfx.kColorWhite)
    local shape = (h >> 4) % 4
    local cx, cy = x + size // 2, y + size // 2
    if shape == 0 then gfx.fillCircleAtPoint(cx, cy, size // 4)
    elseif shape == 1 then gfx.fillRect(cx - size // 4, cy - size // 4, size // 2, size // 2)
    elseif shape == 2 then gfx.fillTriangle(cx, cy - size // 3, cx - size // 3, cy + size // 4, cx + size // 3, cy + size // 4)
    else for i = 0, 4 do gfx.fillRect(x + 8, y + 12 + i * (size // 6), size - 16, 4) end end
    gfx.setColor(gfx.kColorBlack)
    local band = it.n:match("^(.-) %- ") or it.n
    while #band > 1 and Gfx.textW(band, true) > size - 8 do band = band:sub(1, #band - 1) end
    Gfx.fill(x, y + size - 22, size, 22, "black")
    Gfx.text(band, x + 4, y + size - 20, { white = true, bold = true })
  elseif it.k == "vhs" then
    Gfx.fill(x + size // 6, y, size * 2 // 3, size, "black")
    Gfx.fill(x + size // 6 + 6, y + 10, size * 2 // 3 - 12, size // 2, (h % 2 == 0) and "gray" or "diag")
    Gfx.text((it.rating or "PG"), x + size // 2, y + size - 22, { white = true, align = "center", bold = true })
  else
    -- garments and goods: a hanger silhouette or a box
    if it.k == "clothes" then
      gfx.drawLine(x + size // 2, y + 6, x + size // 2, y + 14)
      gfx.drawLine(x + size // 2, y + 14, x + 12, y + 26); gfx.drawLine(x + size // 2, y + 14, x + size - 12, y + 26)
      Gfx.fill(x + 16, y + 26, size - 32, size - 36, ({ "plaid", "hstripe", "gray", "dots", "diag" })[(h % 5) + 1])
      Gfx.rect(x + 16, y + 26, size - 32, size - 36)
    else
      Gfx.fill(x + 14, y + 20, size - 28, size - 34, ({ "gray", "light", "dots", "check" })[(h % 4) + 1])
      Gfx.rect(x + 14, y + 20, size - 28, size - 34)
      Gfx.rect(x + 18, y + 24, size - 36, size - 42)
    end
  end
  Gfx.rect(x, y, size, size)
end

function browse:draw()
  local it = self.items[self.idx]
  Gfx.clear()
  Gfx.fill(0, 0, 400, 240, "lighter")
  Gfx.box(0, 0, 400, 30, "dark")
  Gfx.text(self.s.name .. " — " .. self.label, 12, 7, { white = true, bold = true })
  Gfx.text(self.idx .. "/" .. #self.items, 388, 7, { white = true, align = "right" })
  -- neighbors (flipping stack)
  for d = -2, 2 do
    local j = self.idx + d
    if d ~= 0 and self.items[j] then
      local size = 70 - math.abs(d) * 12
      local x = 200 + d * 80 - size // 2 + self.flip * 3
      sleeve(self.items[j], x, 60 + math.abs(d) * 10, size)
    end
  end
  local size = 110
  local x = 200 - size // 2 + self.flip * 4
  Gfx.fill(x + 4, 44, size, size, "gray")
  sleeve(it, x, 40, size)
  Gfx.box(0, 158, 400, 82, "dark")
  Gfx.text(it.n, 14, 166, { white = true, bold = true })
  local detail = U.money(it.v)
  if it.fmt then detail = detail .. "  " .. it.fmt end
  if it.genre then detail = detail .. "  " .. it.genre end
  if it.mood then detail = detail .. ", " .. it.mood end
  if it.rent then detail = detail .. "  (2-night rental)" end
  if W.p.stats.albums[it.ref or -1] and it.k == "album" then detail = detail .. "  [you own this]" end
  Gfx.text(detail, 14, 188, { white = true })
  Gfx.text("Crank: flip   A: buy   DOWN: pocket it   B: back", 14, 212, { white = true })
end

-- ------------------------------------------------------------------ food court
function Shop.stall(s)
  if not Stores.isOpenAt(s, W.t) then Toast.show(s.name .. " is closed.") return end
  local p = W.p
  local opts, acts = {}, {}
  if p.job and p.job.store == s.id then opts[#opts + 1] = "Clock in"; acts[#acts + 1] = function() Play.clockIn() end end
  for _, it in ipairs(Econ.foodMenu(s)) do
    opts[#opts + 1] = it.n .. "  " .. U.money(it.v)
    acts[#acts + 1] = function() Shop.buy(it, s) end
  end
  local c = clerk(s)
  if c then opts[#opts + 1] = "Talk to " .. c.first; acts[#acts + 1] = function() Dialog.open(c) end end
  if not (p.job and p.job.store == s.id) and s.hiring then
    opts[#opts + 1] = "Ask about a job"
    acts[#acts + 1] = function()
      local m = manager(s) or c
      if m then Dialog.interview(m, s.id) else Say("\"Manager's on break.\"") end
    end
  end
  Choose(s.name:upper(), opts, function(i) acts[i]() end, {})
end

-- ------------------------------------------------------------------ cinema
function Shop.boxOffice(s)
  local p = W.p
  local m = Clock.minute(W.t)
  local shows = CinemaSim.shows(Clock.day(W.t))
  local opts, acts = {}, {}
  if p.job and p.job.store == s.id then opts[#opts + 1] = "Clock in"; acts[#acts + 1] = function() Play.clockIn() end end
  for _, sh in ipairs(shows) do
    if sh.t >= m - 10 and sh.t <= m + 180 and #opts < 8 then
      local mv = W.movies[sh.movie]
      local price = CinemaSim.price(sh.t)
      opts[#opts + 1] = Clock.hhmm(sh.t) .. " " .. mv.title:sub(1, 22) .. " (" .. mv.rating .. ")"
      acts[#acts + 1] = function()
        Say({ mv.title .. " — " .. mv.genre .. ", " .. mv.mins .. " min. Starring " .. mv.star .. ".", "\"" .. mv.tag .. "\"" }, {
          after = function()
            Confirm("Buy a ticket for " .. U.money(price) .. "?", function()
              if p.money < price then Say("You're short.") return end
              if mv.rating == "R" and p.age < 17 then
                local c = clerk(s)
                if c and c.tr.honest > 0.5 then Say("\"Nice try. You need to be seventeen.\"", { npc = c, name = c.first }) return end
              end
              p.money = p.money - price
              s.npcSales = (s.npcSales or 0) + price
              Econ.give({ k = "ticket", n = "ticket: " .. mv.title, v = 0, show = sh.t, screen = sh.screen, movie = mv.id, day = Clock.day(W.t) })
              Say("Theater " .. sh.screen .. ", " .. Clock.hhmm(sh.t) .. ". Enjoy the show.")
            end)
          end })
      end
    end
  end
  if #opts == 0 then opts[1] = "Nothing else showing today"; acts[1] = function() end end
  Choose("NOW PLAYING", opts, function(i) acts[i]() end, { w = 380, x = 10 })
end

function Shop.concession(s)
  local items = { { k = "food", n = "large popcorn", v = 450, food = 35 }, { k = "food", n = "soda", v = 275, food = 5, energy = 8 },
    { k = "food", n = "box of chocolate drops", v = 225, food = 10 }, { k = "food", n = "nachos", v = 375, food = 30 } }
  Shop.menuBuy(s, items)
end

-- ------------------------------------------------------------------ kiosks
local KIOSK = {
  sunglasses = { { "wraparound sunglasses", 1299 }, { "clip-on shades", 699 } },
  pager = { { "glow pager case", 699 }, { "pager holster", 899 } },
  earrings = { { "ear piercing", 1500 }, { "hoop earrings", 899 } },
  calendar = { { "1998 cat calendar", 999 }, { "Magic Eye calendar", 1199 } },
  ["pretzel cart"] = { { "pretzel", 199 }, { "lemonade", 175 } },
  hat = { { "bucket hat", 1499 }, { "novelty jester hat", 1899 } },
  cellphone = { { "cellular sign-up (free phone!)", 0 } },
  perfume = { { "free perfume sample", 0 } },
}
function Shop.kiosk(o)
  local list = KIOSK[o.what] or KIOSK.sunglasses
  local labels, items = {}, {}
  for i, e in ipairs(list) do
    local it = { k = (o.what == "pretzel cart") and "food" or "gift", n = e[1], v = e[2], food = 25 }
    items[i] = it
    labels[i] = e[1] .. "  " .. (e[2] > 0 and U.money(e[2]) or "FREE")
  end
  Choose(o.what:upper() .. " KIOSK", labels, function(i)
    local it = items[i]
    if it.n:find("cellular") then Say("The kiosk guy talks for ten minutes about \"minutes\". You leave with a brochure and a headache.") return end
    if it.n:find("perfume") then Say("You smell like a department store for the rest of the day.") W.p.conf = U.clamp(W.p.conf + 2, 0, 100) return end
    if W.p.money < it.v then Say("You can't afford it.") return end
    W.p.money = W.p.money - it.v
    if it.k == "food" then
      W.p.hunger = U.clamp(W.p.hunger - 25, 0, 100)
      Say("Warm, salty, perfect.")
    elseif it.n == "ear piercing" then
      W.p.conf = U.clamp(W.p.conf + 6, 0, 100)
      W.p.flags.pierced = Clock.day(W.t)
      Say("The piercing gun goes CLACK. You are a new person.")
    else
      Econ.give({ k = "gift", n = it.n, v = it.v, from = "bought" })
      Say("You bought " .. it.n .. ".")
    end
  end, {})
end
