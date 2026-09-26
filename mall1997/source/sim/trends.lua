-- Trends: fads that rise, peak and fade, pushing demand toward store types,
-- genres and items, and shaping which tenants move into empty storefronts.

Trends = {}

-- kind: store (boost a store type), genre (music genre), item (item name
-- substring gets pricier & wanted), tenant (new store names of that type)
Trends.DEFS = {
  plush = { name = "Plush Pal craze", store = { toys = 0.6, gifts = 0.2 }, item = "Plush Pal", tenant = { "toys", "Plush Pals Headquarters" } },
  swing = { name = "swing revival", genre = { swing = 0.8 }, store = { clothing = 0.1 }, tenant = { "clothing", "Zoot & Suit" } },
  vpet = { name = "virtual pets", store = { toys = 0.3, electronics = 0.2 }, item = "Pocket Critter" },
  cargo = { name = "cargo pants everything", store = { clothing = 0.2 }, item = "cargo pants" },
  pager = { name = "everyone needs a pager", store = { electronics = 0.3 }, item = "pager", tenant = { "electronics", "Beep Beep Paging" } },
  cellular = { name = "cell phones", store = { electronics = 0.5 }, tenant = { "electronics", "Cellular Connection" } },
  cyber = { name = "the Internet", store = { weird = 0.2, electronics = 0.2 }, tenant = { "weird", "Byte Me Cyber Cafe" } },
  coffee = { name = "fancy coffee", store = { restaurant = 0.4 }, tenant = { "restaurant", "Grounds for Celebration" } },
  karaoke = { name = "karaoke", store = { weird = 0.2 }, tenant = { "weird", "Karaoke Korner" } },
  teenpop = { name = "teen pop", genre = { ["boy band"] = 0.8, pop = 0.4 } },
  skadeath = { name = "ska is over", genre = { ["ska-punk"] = -0.6 } },
  pogs = { name = "Pogs are over", item = "Pogs", neg = true },
  unsinkable = { name = "Unsinkable mania", store = { cinema = 0.6, music = 0.2, books = 0.2 }, genre = { pop = 0.3 } },
  y2k = { name = "Y2K panic", store = { electronics = 0.2, books = 0.2 }, tenant = { "services", "Y2K Readiness Center" } },
  platform = { name = "platform sneakers", store = { shoes = 0.4 }, item = "platform" },
  tiedye = { name = "tie-dye revival", item = "tie-dye", store = { clothing = 0.1 } },
  bigbeat = { name = "big beat electronica", genre = { electronica = 0.6 } },
  grungefade = { name = "grunge fading", genre = { grunge = -0.5 } },
  gamestore = { name = "the new game consoles", store = { games = 0.5 }, tenant = { "games", "Console Kingdom" } },
}

-- schedule: day index -> trend key (plus seeded variation)
local SCHEDULE = {
  { 0, "plush" }, { 0, "swing" }, { 0, "cargo" }, { 0, "pager" }, { 20, "vpet" }, { 45, "bigbeat" },
  { 60, "grungefade" }, { 75, "platform" }, { 100, "gamestore" }, { 125, "teenpop" }, { 140, "cellular" },
  { 160, "skadeath" }, { 175, "cyber" }, { 190, "pogs" }, { 205, "coffee" }, { 240, "tiedye" },
  { 270, "karaoke" }, { 330, "y2k" },
}

function Trends.seed(r)
  W.trends = {}
  W.trendSchedule = {}
  for _, e in ipairs(SCHEDULE) do
    local d = e[1]
    if d > 0 then d = d + r:i(-10, 10) end
    W.trendSchedule[#W.trendSchedule + 1] = { d, e[2] }
  end
  for _, e in ipairs(W.trendSchedule) do
    if e[1] <= 0 then Trends.start(e[2], true) end
  end
  for _, t in ipairs(W.trends) do t.str = 0.5 + (U.hash(W.seed, t.key) % 40) / 100; t.phase = "peak" end
end

function Trends.active(key)
  for _, t in ipairs(W.trends) do if t.key == key then return t end end
end

function Trends.start(key, quiet)
  if Trends.active(key) or not Trends.DEFS[key] then return end
  local t = { key = key, str = 0.1, phase = "rising", day = Clock.day(W.t) }
  W.trends[#W.trends + 1] = t
  if not quiet then
    Timeline.add("mall", "New trend: " .. Trends.DEFS[key].name .. ".", 2)
  end
end

function Trends.weekly(day)
  for _, e in ipairs(W.trendSchedule) do
    if e[1] <= day and e[1] > day - 7 then Trends.start(e[2]) end
  end
  local keep = {}
  for _, t in ipairs(W.trends) do
    if t.phase == "rising" then
      t.str = t.str + 0.2
      if t.str >= 0.9 then t.phase = "peak"; t.peakDay = day end
    elseif t.phase == "peak" then
      if day - (t.peakDay or t.day) > 21 + (U.hash(t.key) % 30) then t.phase = "fading" end
    else
      t.str = t.str - 0.15
    end
    if t.str > 0 then keep[#keep + 1] = t
    else Timeline.add("mall", "Nobody cares about " .. Trends.DEFS[t.key].name .. " anymore.", 1) end
  end
  W.trends = keep
end

function Trends.storeBoost(s)
  local m = 1
  for _, t in ipairs(W.trends or {}) do
    local d = Trends.DEFS[t.key]
    if d.store and d.store[s.type] then m = m + d.store[s.type] * t.str end
  end
  return m
end

function Trends.genreBoost(g)
  local m = 1
  for _, t in ipairs(W.trends or {}) do
    local d = Trends.DEFS[t.key]
    if d.genre and d.genre[g] then m = m + d.genre[g] * t.str end
  end
  return math.max(0.2, m)
end

function Trends.itemPrice(it)
  local m = 1
  for _, t in ipairs(W.trends or {}) do
    local d = Trends.DEFS[t.key]
    if d.item and it.n and it.n:find(d.item, 1, true) then
      m = m + (d.neg and -0.5 or 0.3) * t.str
    end
  end
  return math.max(0.3, m)
end

function Trends.hotItem()
  for _, t in ipairs(W.trends or {}) do
    local d = Trends.DEFS[t.key]
    if d.item and not d.neg and t.str > 0.4 then return d.item end
  end
end

function Trends.pickNewType(r)
  local types = {}
  for k, v in pairs(MallGen.TYPES) do if v.w > 0 then types[#types + 1] = k end end
  table.sort(types)
  return r:weighted(types, function(k)
    return MallGen.TYPES[k].w * Trends.storeBoost({ type = k }) ^ 2
  end)
end

function Trends.tenantName(typ, r)
  for _, t in ipairs(W.trends or {}) do
    local d = Trends.DEFS[t.key]
    if d.tenant and d.tenant[1] == typ and t.str > 0.3 then
      for _, s in ipairs(W.stores) do if s.name == d.tenant[2] and s.open then return nil end end
      return d.tenant[2]
    end
  end
end

function Trends.describe()
  local out = {}
  for _, t in ipairs(W.trends or {}) do
    local d = Trends.DEFS[t.key]
    out[#out + 1] = d.name .. " (" .. t.phase .. ")"
  end
  return out
end
