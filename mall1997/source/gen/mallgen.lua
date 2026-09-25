-- Mall generation: floor plan slots, stores, cameras.
-- Geometry constants live here because both generation and the area
-- builder (world/areas.lua) need them.

MallGen = {}

MallGen.TILE = 16
MallGen.H = 18           -- concourse height in tiles
MallGen.TOP_DOOR = 4     -- row of top-row storefront doors
MallGen.BOT_DOOR = 13    -- row of bottom-row storefront doors
MallGen.ANCHOR_W = 12
MallGen.COURT_W = 18

-- store types, their weights for ordinary storefronts and base economics
MallGen.TYPES = {
  clothing = { w = 20, rent = 5200, ticket = 3200, conv = 0.14, staff = 3, demo = { "teens", "young adults", "adults" } },
  shoes = { w = 7, rent = 4200, ticket = 4800, conv = 0.12, staff = 2, demo = { "everyone", "teens" } },
  electronics = { w = 4, rent = 4600, ticket = 6400, conv = 0.07, staff = 2, demo = { "adults", "teens" } },
  music = { w = 3, rent = 3900, ticket = 1700, conv = 0.22, staff = 3, demo = { "teens", "young adults" } },
  video = { w = 2, rent = 3600, ticket = 900, conv = 0.30, staff = 3, demo = { "everyone", "families" } },
  books = { w = 3, rent = 3800, ticket = 1400, conv = 0.20, staff = 2, demo = { "adults", "seniors", "kids" } },
  toys = { w = 4, rent = 3900, ticket = 1900, conv = 0.18, staff = 2, demo = { "kids", "families" } },
  games = { w = 3, rent = 3900, ticket = 4200, conv = 0.10, staff = 2, demo = { "teens", "kids" } },
  jewelry = { w = 4, rent = 5000, ticket = 9000, conv = 0.04, staff = 2, demo = { "adults", "young adults" } },
  sporting = { w = 4, rent = 4400, ticket = 3500, conv = 0.10, staff = 2, demo = { "teens", "adults" } },
  gifts = { w = 6, rent = 3500, ticket = 1500, conv = 0.16, staff = 2, demo = { "teens", "everyone" } },
  photo = { w = 1, rent = 2800, ticket = 1100, conv = 0.25, staff = 2, demo = { "adults", "families" } },
  salon = { w = 3, rent = 3200, ticket = 2500, conv = 0.25, staff = 3, demo = { "adults", "teens" } },
  restaurant = { w = 3, rent = 5600, ticket = 1400, conv = 0.30, staff = 4, demo = { "families", "adults" } },
  services = { w = 5, rent = 2600, ticket = 1200, conv = 0.20, staff = 1, demo = { "adults", "seniors" } },
  weird = { w = 4, rent = 2200, ticket = 1100, conv = 0.09, staff = 1, demo = { "everyone" } },
  food = { w = 0, rent = 3000, ticket = 500, conv = 0.40, staff = 3, demo = { "everyone", "teens" } },
  department = { w = 0, rent = 16000, ticket = 4000, conv = 0.12, staff = 7, demo = { "everyone", "adults", "families" } },
  arcade = { w = 0, rent = 4800, ticket = 600, conv = 0.60, staff = 3, demo = { "teens", "kids" } },
  cinema = { w = 0, rent = 9000, ticket = 650, conv = 0.50, staff = 6, demo = { "everyone", "teens" } },
}
MallGen.TYPE_LABEL = {
  clothing = "Clothing", shoes = "Shoes", electronics = "Electronics", music = "Music", video = "Video",
  books = "Books", toys = "Toys", games = "Video Games", jewelry = "Jewelry", sporting = "Sporting Goods",
  gifts = "Gifts", photo = "Photo", salon = "Salon", restaurant = "Restaurant", services = "Services",
  weird = "Specialty", food = "Food", department = "Department Store", arcade = "Arcade", cinema = "Cinema",
}

local FLAVOR = {
  weird = { "Open when the owner feels like it.", "Nobody has ever seen a customer buy anything.",
    "Has been 'going out of business' since 1993.", "Smells faintly of patchouli and ozone.",
    "The owner will tell you about the lizards whether you ask or not." },
  services = { "Keys cut while you wait.", "Mostly retirees and lost receipts." },
  default = { "Blasting the radio a little too loud.", "Big SALE banner, permanently.",
    "Staff look bored in a friendly way.", "Glossy posters of models in the window.",
    "Mirrored walls and a ficus nobody waters.", "Smells like new carpet.", "Always a line at the register." },
}

local function pickType(r, counts)
  local list = {}
  for k, v in pairs(MallGen.TYPES) do if v.w > 0 then list[#list + 1] = k end end
  table.sort(list)
  return r:weighted(list, function(k)
    local base = MallGen.TYPES[k].w
    -- soften repetition
    return base / (1 + (counts[k] or 0) * 0.35)
  end)
end

local function uniqueName(r, W, typ)
  local pool = Names.storeNames[typ] or Names.storeNames.weird
  local used = W._usedNames
  for _ = 1, 30 do
    local n = r:pick(pool)
    if not used[n] then used[n] = true; return n end
  end
  -- fall back to a surname-based name
  local n = r:pick(Names.last) .. "'s " .. (MallGen.TYPE_LABEL[typ] or "Shop")
  used[n] = true
  return n
end

function MallGen.newStore(W, r, typ, slot)
  local T = MallGen.TYPES[typ]
  local id = #W.stores + 1
  local s = {
    id = id, type = typ, name = uniqueName(r, W, typ), slot = slot and slot.id or nil,
    company = r:pick(Names.companies), mgr = nil, emp = {},
    cash = 0, rent = math.floor(T.rent * (slot and slot.w or 6) / 5.5) * 100,
    pop = 50, demo = r:pick(T.demo), sec = r:i(0, 2), q = r:f(),
    nbr = {}, nrel = {}, open = true, opened = -r:i(30, 3000),
    salesDay = 0, salesWeek = 0, hist = {}, stock = r:i(55, 95), sale = 0,
    banned = 0, suspicion = 0, theft = 0, losses = 0,
    wage = r:i(475, 550), flavor = r:pick(FLAVOR[typ] or FLAVOR.default),
    hoursO = nil, hoursC = nil, reno = 0, visits = 0,
  }
  s.pop = math.floor(22 + s.q * 56 + r:i(-6, 6))
  -- established stores have cash reflecting how well they've been run
  s.cash = math.floor(((s.q - 0.2) * 25000 + r:i(-2000, 6000)) * 100)
  if typ == "jewelry" or typ == "electronics" or typ == "department" then s.sec = s.sec + 1 end
  if typ == "weird" then
    s.hoursO = 12 * 60 + r:i(0, 3) * 30; s.hoursC = 18 * 60 + r:i(0, 4) * 30
    s.company = "the owner"
  end
  if typ == "food" then s.hoursO = 10 * 60 + 30 end
  if typ == "cinema" then s.hoursO = 11 * 60 + 30; s.hoursC = 23 * 60 + 45 end
  if typ == "salon" then s.closedSun = true end
  if slot then slot.store = id; s.floor = slot.floor; s.row = slot.row; s.x = slot.x; s.w = slot.w end
  W.stores[id] = s
  return s
end

-- Build the storefront slots for both floors.
function MallGen.genLayout(W, r)
  local L = r:i(78, 108)
  local AW, CW = MallGen.ANCHOR_W, MallGen.COURT_W
  local width = AW + L + CW + L + AW
  W.mall.w = width
  W.mall.court0 = AW + L
  W.mall.court1 = AW + L + CW - 1
  W.slots = {}
  local function addSlot(floor, row, x, w, kind)
    local s = { id = #W.slots + 1, floor = floor, row = row, x = x, w = w, kind = kind }
    W.slots[#W.slots + 1] = s
    return s
  end
  -- anchors at both ends span both floors
  addSlot(1, "west", 0, AW, "anchor")
  addSlot(1, "east", width - AW, AW, "anchor")
  -- optional interior anchors take a 12-wide chunk of floor 1 rows
  local extraAnchors = r:i(0, 3)
  local reserved = {}
  local candidates = { { 1, "top", AW + math.floor(L / 3) }, { 1, "top", W.mall.court1 + 1 + math.floor(L / 2) },
    { 1, "bot", AW + math.floor(L / 2) } }
  r:shuffle(candidates)
  for i = 1, extraAnchors do
    local c = candidates[i]
    reserved[#reserved + 1] = { floor = c[1], row = c[2], x0 = c[3], x1 = c[3] + 11 }
  end
  for floor = 1, 2 do
    for _, row in ipairs({ "top", "bot" }) do
      for side = 1, 2 do
        local x0 = side == 1 and AW or W.mall.court1 + 1
        local x1 = x0 + L - 1
        -- split the stretch around reserved anchor blocks
        local segs, cur = {}, x0
        local rs = {}
        for _, rv in ipairs(reserved) do
          if rv.floor == floor and rv.row == row and rv.x0 >= x0 and rv.x1 <= x1 then rs[#rs + 1] = rv end
        end
        table.sort(rs, function(a, b) return a.x0 < b.x0 end)
        for _, rv in ipairs(rs) do
          if rv.x0 > cur then segs[#segs + 1] = { cur, rv.x0 - 1 } end
          segs[#segs + 1] = { rv.x0, rv.x1, anchor = true }
          cur = rv.x1 + 1
        end
        if cur <= x1 then segs[#segs + 1] = { cur, x1 } end
        local sinceGap = 0
        for _, sg in ipairs(segs) do
          if sg.anchor then
            addSlot(floor, row, sg[1], 12, "anchor")
          elseif sg[2] - sg[1] + 1 < 4 then
            addSlot(floor, row, sg[1], sg[2] - sg[1] + 1, "wall")
          else
            local x = sg[1]
            while x <= sg[2] do
              local left = sg[2] - x + 1
              if sinceGap > 22 and left > 8 and r:chance(0.35) then
                addSlot(floor, row, x, 2, "gap")
                x = x + 2; sinceGap = 0
              else
                local w = r:i(4, 7)
                if left - w < 4 then w = left end
                addSlot(floor, row, x, w, "store")
                x = x + w; sinceGap = sinceGap + w
              end
            end
          end
        end
      end
    end
  end
end

function MallGen.genStores(W, r)
  local counts = {}
  local storeSlots = {}
  for _, sl in ipairs(W.slots) do
    if sl.kind == "store" then storeSlots[#storeSlots + 1] = sl end
  end
  -- anchors
  for _, sl in ipairs(W.slots) do
    if sl.kind == "anchor" then
      local s = MallGen.newStore(W, r, "department", sl)
      s.sec = 3; s.cash = r:i(150000, 400000) * 100
      s.company = s.name .. " Inc."
    end
  end
  -- the arcade: widest store slot on floor 2 near the court
  table.sort(storeSlots, function(a, b) return a.id < b.id end)
  local arcadeSlot, best = nil, 1e9
  for _, sl in ipairs(storeSlots) do
    if sl.floor == 2 and sl.w >= 6 then
      local d = math.abs(sl.x - W.mall.court0)
      if d < best then best, arcadeSlot = d, sl end
    end
  end
  arcadeSlot = arcadeSlot or storeSlots[1]
  local arcade = MallGen.newStore(W, r, "arcade", arcadeSlot)
  arcade.sec = 1
  W.mall.arcade = arcade.id
  -- guarantee the job-bearing store types exist
  local required = { "music", "video", "books", "photo", "games", "clothing", "salon", "services",
    "weird", "weird", "toys", "shoes", "jewelry", "sporting", "gifts", "electronics", "restaurant" }
  local free = {}
  for _, sl in ipairs(storeSlots) do if not sl.store then free[#free + 1] = sl end end
  r:shuffle(free)
  -- the abandoned storefront (secret) and a few ordinary vacancies
  local abandoned = table.remove(free)
  abandoned.abandoned = true
  W.mall.abandonedSlot = abandoned.id
  local vac = math.floor(#free * 0.04)
  for _ = 1, vac do local sl = table.remove(free); sl.vacantSince = -r:i(10, 200) end
  for _, typ in ipairs(required) do
    local sl = table.remove(free)
    if sl then MallGen.newStore(W, r, typ, sl); counts[typ] = (counts[typ] or 0) + 1 end
  end
  for _, sl in ipairs(free) do
    local typ = pickType(r, counts)
    counts[typ] = (counts[typ] or 0) + 1
    MallGen.newStore(W, r, typ, sl)
  end
  -- food court stalls and the cinema live in the food court wing
  local nfood = r:i(9, 12)
  W.mall.foodStalls = {}
  for i = 1, nfood do
    local s = MallGen.newStore(W, r, "food", nil)
    s.row = "fc"; s.floor = 2; s.stall = i; s.rent = 3000 * 100
    s.menu = ({ "pizza", "hotdog", "asian", "mexican", "pretzel", "drink", "sweet", "burger" })[(i - 1) % 8 + 1]
    W.mall.foodStalls[#W.mall.foodStalls + 1] = s.id
  end
  local cin = MallGen.newStore(W, r, "cinema", nil)
  cin.row = "fc"; cin.floor = 2; cin.rent = 9000 * 100; cin.sec = 1
  W.mall.cinema = cin.id
  MallGen.linkNeighbors(W)
end

-- neighbors: adjacent storefronts on the same floor/row, plus facing store
function MallGen.linkNeighbors(W)
  for _, s in ipairs(W.stores) do s.nbr = {} end
  local byRow = {}
  for _, sl in ipairs(W.slots) do
    if sl.store then
      local k = sl.floor .. sl.row
      byRow[k] = byRow[k] or {}
      byRow[k][#byRow[k] + 1] = sl
    end
  end
  for _, list in pairs(byRow) do
    table.sort(list, function(a, b) return a.x < b.x end)
    for i = 1, #list do
      local s = W.stores[list[i].store]
      if list[i - 1] then U.addUnique(s.nbr, list[i - 1].store) end
      if list[i + 1] then U.addUnique(s.nbr, list[i + 1].store) end
    end
  end
  for _, s in ipairs(W.stores) do
    for _, n in ipairs(s.nbr) do
      if s.nrel[n] == nil then s.nrel[n] = 0 end
    end
  end
  local fs = W.mall.foodStalls or {}
  for i = 1, #fs do
    local s = W.stores[fs[i]]
    if fs[i - 1] then U.addUnique(s.nbr, fs[i - 1]); s.nrel[fs[i - 1]] = s.nrel[fs[i - 1]] or 0 end
    if fs[i + 1] then U.addUnique(s.nbr, fs[i + 1]); s.nrel[fs[i + 1]] = s.nrel[fs[i + 1]] or 0 end
  end
end

-- security cameras: concourse zones + in-store cameras by security level
function MallGen.genCameras(W, r)
  W.cams = {}
  for floor = 1, 2 do
    local x = MallGen.ANCHOR_W + r:i(4, 10)
    while x < W.mall.w - MallGen.ANCHOR_W - 4 do
      W.cams[#W.cams + 1] = { area = "c" .. floor, x = x, y = 5, r = 7, on = r:chance(0.8) }
      x = x + r:i(16, 30)
    end
  end
  W.cams[#W.cams + 1] = { area = "fc", x = 20, y = 3, r = 10, on = true }
  W.cams[#W.cams + 1] = { area = "c1", x = W.mall.court0 + 9, y = 12, r = 8, on = true }
end
