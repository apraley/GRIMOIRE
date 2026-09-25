-- Economy: item catalogs (derived per store/week), NPC purchases, player
-- purchases, inventory helpers. Store cash and sales live on store tables.

Econ = {}
Memory = {}

-- ------------------------------------------------------------------ memory
function Memory.add(n, kind, txt, subj)
  n.mem = n.mem or {}
  n.mem[#n.mem + 1] = { d = Clock.day(W.t), k = kind, txt = txt, s = subj }
  U.trim(n.mem, 10)
end
function Memory.find(n, kind, subj)
  for i = #n.mem, 1, -1 do
    local m = n.mem[i]
    if m.k == kind and (subj == nil or m.s == subj) then return m end
  end
end

-- ------------------------------------------------------------------ catalog
local function albumItems(s, idx, r)
  local M = W.music
  local genres = {}
  for _, g in ipairs(Names.genres) do genres[#genres + 1] = g end
  local g1 = genres[((idx * 3 + s.id) % #genres) + 1]
  local g2 = genres[((idx * 3 + s.id + 5) % #genres) + 1]
  local items = {}
  local day = Clock.day(W.t)
  for _, a in ipairs(M.albums) do
    local b = M.bands[a.band]
    if (b.genre == g1 or b.genre == g2) and (not a.releaseDay or a.released) then
      local cd = r:chance(0.7)
      local price = cd and 1399 or 899
      if a.pop > 70 then price = price + 200 end
      if a.year <= 1993 then price = price - 400 end
      items[#items + 1] = { k = "album", ref = a.id, n = b.name .. " - " .. a.title, v = price,
        fmt = cd and "CD" or "cassette", genre = b.genre, mood = a.mood }
    end
  end
  table.sort(items, function(x, y) return x.n < y.n end)
  while #items > 18 do table.remove(items, r:i(1, #items)) end
  return items, g1 .. " / " .. g2
end

local function vhsItems(s, idx, r)
  local items = {}
  local g = Names.movieGenres[((idx + s.id) % #Names.movieGenres) + 1]
  for _, m in ipairs(W.movies) do
    if m.vhs and m.genre == g then
      items[#items + 1] = { k = "vhs", ref = m.id, n = m.title .. " (" .. m.year .. ")", v = 299, rent = true,
        genre = m.genre, rating = m.rating }
    end
  end
  table.sort(items, function(x, y) return x.n < y.n end)
  return items, g
end

local LISTS = {
  clothes = function() return Names.clothes end, toy = function() return Names.toyItems end,
  book = function() return Names.bookItems end, gift = function() return Names.giftItems end,
  jewelry = function() return Names.jewelryItems end, sport = function() return Names.sportItems end,
  electronic = function() return Names.electronicItems end, photo = function() return Names.photoItems end,
  weird = function() return Names.weirdItems end, service = function() return Names.serviceItems end,
}

function Econ.rack(s, idx)
  local week = Clock.week(W.t)
  local r = U.rng(W.seed, "rack", s.id, idx, week)
  local cat = Areas.RACK_CATS[s.type] or "gift"
  if s.type == "department" then cat = ({ "clothes", "jewelry", "electronic", "gift", "clothes", "toy" })[(idx % 6) + 1] end
  local items, label
  if cat == "album" then items, label = albumItems(s, idx, r)
  elseif cat == "vhs" then items, label = vhsItems(s, idx, r)
  elseif cat == "game" then
    items = {}
    for i, g in ipairs(Names.videoGames) do
      if (i + idx) % 2 == 0 then
        items[#items + 1] = { k = "game", n = g, v = r:chance(0.3) and 2999 or 5499 }
      end
    end
    label = "video games"
  elseif cat == "salon" then
    items = { { k = "service", n = "haircut", v = 1500, svc = "hair" }, { k = "service", n = "frosted tips", v = 3500, svc = "tips" },
      { k = "service", n = "perm", v = 4500, svc = "perm" }, { k = "service", n = "buzz cut", v = 900, svc = "buzz" } }
    label = "services"
  elseif cat == "food" then
    items = { { k = "food", n = "patty melt", v = 649, food = 45 }, { k = "food", n = "club sandwich", v = 599, food = 40 },
      { k = "food", n = "slice of pie", v = 299, food = 20 }, { k = "food", n = "coffee", v = 99, food = 5, energy = 15 } }
    label = "menu"
  else
    local src = (LISTS[cat] or LISTS.gift)()
    items = {}
    for _, e in ipairs(src) do
      if r:chance(0.7) then items[#items + 1] = { k = cat, n = e[1], v = e[2] } end
    end
    if #items == 0 then items[1] = { k = cat, n = src[1][1], v = src[1][2] } end
    label = cat
  end
  -- prices: sales and trends
  for _, it in ipairs(items) do
    it.v = math.floor(it.v * (1 - s.sale / 100) * Trends.itemPrice(it) + 0.5)
    it.key = it.k .. ":" .. (it.ref or it.n)
  end
  -- stock and sold-out
  local keep = {}
  local stockN = math.max(2, math.floor(#items * U.clamp(s.stock / 70, 0.2, 1)))
  for i, it in ipairs(items) do
    if i <= stockN and not (s.soldOut and s.soldOut[it.key]) then keep[#keep + 1] = it end
  end
  return keep, label
end

function Econ.foodMenu(s)
  local out = {}
  for _, e in ipairs(Names.foodItems[s.menu or "pizza"]) do
    out[#out + 1] = { k = "food", n = e[1], v = e[2], food = 30 + (e[2] // 20) }
  end
  return out
end

-- ------------------------------------------------------------------ NPC buying
local function wantMatch(n, it)
  for i, w in ipairs(n.wants) do
    if (w.k == "album" and it.k == "album" and it.ref == w.ref) or
      ((w.k == "item" or w.k == "clothes") and it.n == w.ref) then return i end
  end
end

function Econ.npcShop(n, s)
  if not s or not s.open then return end
  if not Stores.isOpenAt(s, W.t) then
    n.mood = U.clamp(n.mood - 1, 0, 100)
    return
  end
  if s.bannedNPC and s.bannedNPC[n.id] and s.bannedNPC[n.id] > Clock.day(W.t) then return end
  s.visits = (s.visits or 0) + 1
  if Security.npcConsiderTheft(n, s) then return end
  local r = U.rng(W.seed, "shop", n.id, math.floor(W.t))
  local T = MallGen.TYPES[s.type]
  local items = Econ.rack(s, r:i(1, 4))
  if #items == 0 then return end
  local it = r:pick(items)
  for _, x in ipairs(items) do if wantMatch(n, x) then it = x end end
  local wi = wantMatch(n, it)
  local p = math.min(0.9, T.conv * 2.5 + (wi and 0.6 or 0))
  if n.money >= it.v and r:chance(p) then
    n.money = n.money - it.v
    s.npcSales = (s.npcSales or 0) + it.v
    s.stock = math.max(0, s.stock - 0.3)
    n.poss[#n.poss + 1] = { k = it.k, n = it.n, v = it.v, ref = it.ref }
    U.trim(n.poss, 12)
    if it.k == "album" then
      local a = W.music.albums[it.ref]
      a.sold = a.sold + 1
    end
    if wi then
      table.remove(n.wants, wi)
      n.mood = U.clamp(n.mood + 10, 0, 100)
      Memory.add(n, "bought", "finally got " .. it.n)
    end
  end
end

function Econ.npcEat(n)
  local stalls = W.mall.foodStalls
  if not stalls or #stalls == 0 then return end
  local r = U.rng(W.seed, "eat", n.id, math.floor(W.t))
  local s = W.stores[r:pick(stalls)]
  if s and s.open and Stores.isOpenAt(s, W.t) then
    local price = r:i(250, 650)
    if n.money >= price then
      n.money = n.money - price
      s.npcSales = (s.npcSales or 0) + price
    end
  end
end

function Econ.onArrive(n, act, ref)
  if act == "shop" then Econ.npcShop(n, ref and W.stores[ref])
  elseif act == "eat" then Econ.npcEat(n)
  elseif act == "play" then ArcadeSim.npcPlay(n)
  elseif act == "tourney" then ArcadeSim.npcPlay(n); ArcadeSim.npcTourney(n)
  elseif act == "watch" then CinemaSim.npcWatch(n, ref)
  elseif act == "date" then Social.dateArrive(n, ref)
  elseif act == "fix" then Events.maintFix(n)
  end
end

-- NPC income: paydays and allowances
function Econ.daily(day)
  local info = Clock.info(day)
  for _, n in ipairs(W.npcs) do
    if n.status == "active" then
      local shift = Stores.shiftOf(n, day)
      if shift and n.job then
        n.money = n.money + math.floor((n.wage or 500) * (shift[2] - shift[1]) / 60 * 0.8)
      end
      if info.wd == 0 and n.age < 19 then n.money = n.money + 1000 end
      if n.age >= 22 and not n.job and info.wd == 5 then n.money = n.money + 5000 end
      if n.money > 60000 and n.age < 19 then n.money = 60000 end
    end
  end
end

-- ------------------------------------------------------------------ player
function Econ.give(item) -- add to player inventory
  item.d = Clock.day(W.t)
  W.p.inv[#W.p.inv + 1] = item
end

function Econ.buy(it, s)
  local p = W.p
  if p.money < it.v then return false, "You can't afford that." end
  p.money = p.money - it.v
  s.npcSales = (s.npcSales or 0) + it.v
  s.stock = math.max(0, s.stock - 0.5)
  p.stats.itemsBought = p.stats.itemsBought + 1
  local copy = U.copy(it)
  copy.from = "bought"
  copy.store = s.id
  if it.k == "album" then
    local a = W.music.albums[it.ref]
    a.sold = a.sold + 1
    p.stats.albums[it.ref] = true
    PlayerSim.updateTaste()
  end
  if it.k == "vhs" and it.rent then
    copy.due = Clock.day(W.t) + 2
    copy.n = copy.n .. " [RENTAL]"
    p.stats.movies["v" .. it.ref] = true
  end
  if it.k == "food" then
    p.hunger = U.clamp(p.hunger - (it.food or 30), 0, 100)
    p.energy = U.clamp(p.energy + (it.energy or 5), 0, 100)
    return true, "You eat the " .. it.n .. ". " .. (p.hunger < 20 and "Stuffed." or "Better.")
  end
  if it.k == "service" then
    return true, Econ.service(it)
  end
  Econ.give(copy)
  return true, "You bought " .. it.n .. " for " .. U.money(it.v) .. "."
end

function Econ.service(it)
  local p = W.p
  p.look = p.look or { hair = 0 }
  if it.svc == "hair" then p.look.hair = 2; p.conf = U.clamp(p.conf + 5, 0, 100); return "Fresh haircut. You feel lighter." end
  if it.svc == "tips" then p.look.hair = 1; p.look.hc = 2; p.conf = U.clamp(p.conf + 12, 0, 100); p.flags.tips = Clock.day(W.t); return "Frosted tips. It is 1997 and you are ready." end
  if it.svc == "perm" then p.look.hair = 4; p.conf = U.clamp(p.conf + 6, 0, 100); return "The perm is... a choice." end
  if it.svc == "buzz" then p.look.hair = 5; p.conf = U.clamp(p.conf + 3, 0, 100); return "Buzzed. Summer camp energy." end
  return "Done."
end

function Econ.countItem(pred)
  local c = 0
  for _, it in ipairs(W.p.inv) do if pred(it) then c = c + 1 end end
  return c
end

function Econ.removeItem(it) U.removeValue(W.p.inv, it) end

function Econ.itemLabel(it)
  local s = it.n
  if it.fmt then s = s .. " (" .. it.fmt .. ")" end
  if it.from == "stolen" then s = s .. " *" end
  if it.borrowed then s = s .. " (borrowed)" end
  return s
end
