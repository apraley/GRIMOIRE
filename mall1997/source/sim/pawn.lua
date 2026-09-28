-- Pawn shop: the one store in the mall that buys things from you. It pays a
-- fraction of retail, less for anything still warm from a shoplift, and
-- doesn't ask where it came from. What people sell ends up in its cases,
-- where anyone can buy it back. Mall security does walk through now and
-- then with a list of what's gone missing.

Pawn = {}

local NOSALE = { gear = true, key = true, food = true, service = true }

function Pawn.shop()
  for _, s in ipairs(W.stores) do if s.type == "pawn" and s.open then return s end end
end

local function stock()
  W.mall.pawnStock = W.mall.pawnStock or {}
  return W.mall.pawnStock
end

-- what the broker will pay, in cents; or nil and the reason
function Pawn.offer(it)
  if NOSALE[it.k] then return nil, "\"I don't buy that.\"" end
  if it.due then return nil, "\"That's a rental. It's got the video store's sticker right on it.\"" end
  if it.borrowed then return nil, "You borrowed that. Selling it would be a new low, even for you." end
  if (it.v or 0) < 200 then return nil, "\"I can't give you anything for that.\"" end
  local pct = 0.35
  local day = Clock.day(W.t)
  if it.from == "stolen" then pct = (day - (it.d or day) <= 1) and 0.2 or 0.3 end
  return math.max(100, math.floor(it.v * pct / 50) * 50), pct
end

function Pawn.sellable()
  local out = {}
  for _, it in ipairs(W.p.inv) do if Pawn.offer(it) then out[#out + 1] = it end end
  return out
end

-- the player sells `it` to pawn shop `s`; returns lines for the broker to say
function Pawn.sell(it, s)
  local p = W.p
  local cash, pct = Pawn.offer(it)
  if not cash then return { pct } end
  p.money = p.money + cash
  s.cash = s.cash - cash
  Econ.removeItem(it)
  local st = stock()
  W.mall.pawnNext = (W.mall.pawnNext or 0) + 1
  st[#st + 1] = { id = W.mall.pawnNext, k = it.k, n = it.n, ref = it.ref, fmt = it.fmt, v = math.floor(it.v * 0.7),
    shop = s.id, from = it.from, orig = it.store, d = Clock.day(W.t), byPlayer = true }
  while #st > 24 do table.remove(st, 1) end
  p.stats.pawned = (p.stats.pawned or 0) + 1
  local lines = { "He turns it over twice and counts out " .. U.money(cash) .. "." }
  if it.from == "stolen" then
    p.stats.fenced = (p.stats.fenced or 0) + 1
    if pct < 0.25 then lines[#lines + 1] = "\"Still warm, huh? That's why it's twenty cents on the dollar.\""
    else lines[#lines + 1] = "\"I don't know you, you don't know me.\"" end
    Timeline.add("player", p.name .. " sold " .. U.a(it.n) .. " to " .. s.name .. ".", 1)
  else
    lines[#lines + 1] = "\"Pleasure doing business.\""
  end
  return lines
end

-- rack entries: a few permanent fixtures plus whatever people sold this month
function Pawn.rack(s, r)
  local items = {}
  for _, e in ipairs(Names.pawnItems) do
    if r:chance(0.5) then items[#items + 1] = { k = "gift", n = e[1], v = e[2] } end
  end
  local st = stock()
  for i = #st, 1, -1 do
    local e = st[i]
    if e.shop == s.id and #items < 18 then
      items[#items + 1] = { k = e.k, n = e.n, ref = e.ref, fmt = e.fmt, v = e.v, pawnId = e.id }
    end
  end
  return items
end

-- bought back out of the case
function Pawn.bought(it)
  local st = stock()
  for i, e in ipairs(st) do if e.id == it.pawnId then table.remove(st, i) return end end
end

-- weekly: kleptos fence what they took, security checks the cases against
-- the week's theft reports, and old stock gets marked down and sold off
function Pawn.weekly(day, r)
  local s = Pawn.shop()
  if not s then return end
  local st = stock()
  for _, n in ipairs(W.npcs) do
    if n.status == "active" then
      for i, it in ipairs(n.poss) do
        if it.stolen and r:chance(0.3) then
          table.remove(n.poss, i)
          n.money = n.money + math.floor(it.v * 0.3)
          W.mall.pawnNext = (W.mall.pawnNext or 0) + 1
          st[#st + 1] = { id = W.mall.pawnNext, k = it.k, n = it.n, ref = it.ref, v = math.floor(it.v * 0.7),
            shop = s.id, from = "stolen", d = day }
          break
        end
      end
    end
  end
  for _, e in ipairs(st) do
    local o = e.orig and W.stores[e.orig]
    if e.byPlayer and e.from == "stolen" and not e.traced and o and o.open and o.sec >= 2 and day - e.d <= 21 and r:chance(0.2) then
      e.traced = true
      local p = W.p
      p.evidence[#p.evidence + 1] = { store = o.id, day = day, reviewed = true, known = true, pawn = true }
      p.wanted = (p.wanted or 0) + 1
      Timeline.add("crime", "Security matched " .. U.a(e.n) .. " in the case at " .. s.name .. " to a theft report from " ..
        o.name .. ". The pawn ticket has a name on it.", 2)
    end
  end
  local keep = {}
  for _, e in ipairs(st) do
    if day - e.d < 35 then
      if day - e.d > 14 then e.v = math.floor(e.v * 0.85) end
      keep[#keep + 1] = e
    end
  end
  W.mall.pawnStock = keep
end

-- every mall has one. Worlds made before the pawn shop existed get one the
-- first time they load; if the shop ever closes, a new one takes the next
-- vacant storefront.
function Pawn.ensure(day, now)
  if Pawn.shop() then return end
  for _, sl in ipairs(W.slots) do if sl.coming and sl.coming.type == "pawn" then return end end
  local slots = {}
  for _, sl in ipairs(W.slots) do
    if sl.kind == "store" and not sl.store and not sl.abandoned and not sl.coming then slots[#slots + 1] = sl end
  end
  if #slots == 0 then return end
  local r = U.rng(W.seed, "pawn", day)
  local sl = slots[r:i(1, #slots)]
  sl.coming = { day = day + (now and 0 or r:i(5, 12)), type = "pawn" }
  if now then
    local s = Stores.openNew(sl, day, r)
    s.q = 0.55
  else
    Timeline.add("mall", "COMING SOON: a pawn shop signed a lease on the " .. (sl.floor == 1 and "lower" or "upper") .. " level.", 1)
  end
end
