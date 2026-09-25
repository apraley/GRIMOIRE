-- Area geometry. Areas are *derived* from persistent world data (stores,
-- slots, the seed) and rebuilt on demand; nothing here is saved. Persistent
-- entities never live in an area object — areas only hold tiles, doors,
-- interactable objects and NPC "spots".
--
-- Area ids:
--   c1 c2        concourse floors          fc       food court
--   s<id>        store interior             b<id>    store back room
--   v1 v2        service corridors          dock mgmt sec maint roof lot
--   ab           abandoned storefront       tun shel off lock   (secret mall)
--   scr1..6      cinema screens (abstract)  home     off-site

Areas = {}
local T = MallGen.TILE

-- tile codes
Areas.FLOOR, Areas.WALL, Areas.FACADE, Areas.WINDOW, Areas.PLANTER = 0, 1, 2, 3, 4
Areas.BENCH, Areas.FOUNTAIN, Areas.ESC, Areas.VOID, Areas.COUNTER = 5, 6, 7, 8, 9
Areas.RACK, Areas.TABLE, Areas.DOOR, Areas.TILE2, Areas.CARPET = 10, 11, 12, 13, 14
Areas.ASPHALT, Areas.CAR, Areas.DARK, Areas.CAB, Areas.STAGE = 15, 16, 17, 18, 19
Areas.CRATE, Areas.PIPE, Areas.HVAC, Areas.SKY, Areas.KIOSK = 20, 21, 22, 23, 24
Areas.SHELF, Areas.DESK, Areas.DUST, Areas.PAPERED, Areas.GRATE = 25, 26, 27, 28, 29
Areas.LOCKDOOR = 30
Areas.LOUD = 31 -- arcade / cinema carpet

local WALKABLE = { [0] = true, [7] = true, [12] = true, [13] = true, [14] = true, [15] = true,
  [19] = true, [27] = true, [29] = true, [31] = true }
Areas.WALKABLE = WALKABLE

local cache = {}
function Areas.invalidate(id) if id then cache[id] = nil else cache = {} end end

-- food court width grows with the number of stalls (5 tiles each)
Areas.STALL = 5
function Areas.fcW() return math.max(52, 4 + #(W.mall.foodStalls or {}) * Areas.STALL + 14) end

-- ------------------------------------------------------------ grid helpers
local function grid(id, w, h, fill, name, kind)
  local a = { id = id, w = w, h = h, t = {}, doors = {}, objs = {}, spots = {}, name = name, kind = kind or id }
  for i = 1, w * h do a.t[i] = fill end
  return a
end
local function set(a, x, y, c)
  if x >= 0 and y >= 0 and x < a.w and y < a.h then a.t[y * a.w + x + 1] = c end
end
local function get(a, x, y)
  if x < 0 or y < 0 or x >= a.w or y >= a.h then return Areas.WALL end
  return a.t[y * a.w + x + 1]
end
Areas.get = get
Areas.set = set
local function rect(a, x, y, w, h, c) for j = y, y + h - 1 do for i = x, x + w - 1 do set(a, i, j, c) end end end
local function box(a, fillc, wallc)
  rect(a, 0, 0, a.w, a.h, fillc)
  rect(a, 0, 0, a.w, 1, wallc); rect(a, 0, a.h - 1, a.w, 1, wallc)
  rect(a, 0, 0, 1, a.h, wallc); rect(a, a.w - 1, 0, 1, a.h, wallc)
end
local function door(a, x, y, to, tx, ty, opts)
  set(a, x, y, Areas.DOOR)
  local d = { x = x, y = y, to = to, tx = tx, ty = ty }
  if opts then for k, v in pairs(opts) do d[k] = v end end
  a.doors[#a.doors + 1] = d
  return d
end
local function obj(a, kind, x, y, w, h, extra)
  local o = { kind = kind, x = x, y = y, w = w or 1, h = h or 1 }
  if extra then for k, v in pairs(extra) do o[k] = v end end
  a.objs[#a.objs + 1] = o
  return o
end
local function spot(a, kind, x, y) a.spots[#a.spots + 1] = { kind = kind, x = x, y = y } end

function Areas.walkable(a, tx, ty) return WALKABLE[get(a, tx, ty)] == true end

-- ------------------------------------------------------------ store doors
-- Returns concourse area id, door tile x,y and the corridor tile in front.
function Areas.storefront(s)
  local court0 = W.mall.court0
  if s.row == "fc" then
    local fw = Areas.fcW()
    if s.type == "cinema" then return "fc", fw - 1, 8, fw - 2, 8 end
    local x = 2 + (s.stall - 1) * Areas.STALL + 2
    return "fc", x, 4, x, 5
  end
  if s.row == "west" then return "c1", MallGen.ANCHOR_W - 1, 8, MallGen.ANCHOR_W, 8 end
  if s.row == "east" then return "c1", W.mall.w - MallGen.ANCHOR_W, 8, W.mall.w - MallGen.ANCHOR_W - 1, 8 end
  local dx = s.x + math.floor(s.w / 2) - 1
  local area = "c" .. s.floor
  if s.row == "top" then return area, dx, MallGen.TOP_DOOR, dx, MallGen.TOP_DOOR + 1 end
  return area, dx, MallGen.BOT_DOOR, dx, MallGen.BOT_DOOR - 1
end

function Areas.storeArea(s)
  if s.type == "food" then return "fc" end
  return "s" .. s.id
end

-- interior size for a store
local function interiorSize(s)
  if s.type == "department" or s.type == "cinema" or s.type == "arcade" then return 25, 15 end
  local w = U.clamp((s.w or 5) * 3 + 5, 17, 25)
  return w, 14
end
Areas.interiorSize = interiorSize

-- ------------------------------------------------------------ portals
-- For NPC routing: every area except c1 has a parent. portal(id) returns
-- parentId, (x,y) inside this area at the exit, (px,py) inside the parent.
function Areas.portal(id)
  local c0 = W.mall.court0
  if id == "c2" then return "c1", c0 + 4, 9, c0 + 4, 9 end
  if id == "fc" then return "c2", 26, 17, c0 + 8, 5 end
  if id == "lot" then return "c1", 20, 1, c0 + 8, 12 end
  if id == "home" then return "lot", 0, 0, 3, 18 end
  if id == "sec" then return "c1", 3, 8, c0 + 2, 12 end
  if id == "mgmt" then return "c2", 3, 8, c0 + 2, 12 end
  if id == "v1" or id == "v2" then
    local f = tonumber(id:sub(2))
    local gx = Areas.nearestGap(f, c0)
    return "c" .. f, gx, 9, gx, 5
  end
  if id == "dock" then return "v1", 1, 6, W.mall.w - 3, 6 end
  if id == "maint" then return "v1", 2, 6, c0 + 12, 3 end
  if id == "roof" then return "maint", 10, 2, 16, 2 end
  if id == "tun" then return "maint", 2, 6, 14, 8 end
  if id == "shel" then return "tun", 2, 6, 44, 3 end
  if id == "off" then return "tun", 2, 6, 24, 10 end
  if id == "lock" then return "shel", 2, 6, 17, 2 end
  if id == "ab" then
    local sl = W.slots[W.mall.abandonedSlot]
    return "v" .. sl.floor, 8, 12, sl.x + 1, sl.row == "top" and 3 or 8
  end
  if id:match("^scr") then
    local cin = W.stores[W.mall.cinema]
    local n = tonumber(id:sub(4))
    return "s" .. cin.id, 0, 0, 3 + (n - 1) * 3 + 1, 2
  end
  local kind, num = id:match("^([sb])(%d+)$")
  if kind == "s" then
    local s = W.stores[tonumber(num)]
    local w, h = interiorSize(s)
    local pa, _, _, fx, fy = Areas.storefront(s)
    return pa, math.floor(w / 2), h - 2, fx, fy
  elseif kind == "b" then
    local s = W.stores[tonumber(num)]
    local w = interiorSize(s)
    return "s" .. s.id, 5, 6, w - 3, 1
  end
  return nil
end

function Areas.nearestGap(floor, x)
  local best, bx = 1e9, x
  for _, sl in ipairs(W.slots) do
    if sl.kind == "gap" and sl.floor == floor and sl.row == "top" then
      local d = math.abs(sl.x - x)
      if d < best then best, bx = d, sl.x end
    end
  end
  return bx
end

-- ------------------------------------------------------------ concourse
local function buildConcourse(id, floor)
  local w, h = W.mall.w, MallGen.H
  local a = grid(id, w, h, Areas.WALL, floor == 1 and "Lower Level" or "Upper Level", "concourse")
  a.floor = floor
  rect(a, 0, 5, w, 8, Areas.FLOOR)
  local c0, c1 = W.mall.court0, W.mall.court1
  -- storefronts
  for _, sl in ipairs(W.slots) do
    local onFloor = sl.floor == floor or sl.row == "west" or sl.row == "east"
    if onFloor then
      if sl.row == "west" or sl.row == "east" then
        local x = sl.row == "west" and 0 or w - MallGen.ANCHOR_W
        rect(a, x, 0, MallGen.ANCHOR_W, h, Areas.FACADE)
        local dxx = sl.row == "west" and MallGen.ANCHOR_W - 1 or w - MallGen.ANCHOR_W
        local fx = sl.row == "west" and dxx + 1 or dxx - 1
        local s = W.stores[sl.store]
        for yy = 7, 10 do set(a, dxx, yy, Areas.WINDOW) end
        if s then
          local sw, sh = interiorSize(s)
          local tx = floor == 1 and math.floor(sw / 2) or 2
          local ty = floor == 1 and sh - 2 or 1
          door(a, dxx, 8, "s" .. s.id, tx, ty, { store = s.id, fx = fx, fy = 8 })
          door(a, dxx, 9, "s" .. s.id, tx, ty, { store = s.id, fx = fx, fy = 9 })
        end
        a.objs[#a.objs + 1] = { kind = "sign", x = x, y = 0, w = MallGen.ANCHOR_W, h = h, store = sl.store, slot = sl.id, anchorEnd = sl.row }
      else
        local top = sl.row == "top"
        local y0 = top and 0 or MallGen.BOT_DOOR
        local dy = top and MallGen.TOP_DOOR or MallGen.BOT_DOOR
        local fy = top and dy + 1 or dy - 1
        if sl.kind == "gap" then
          rect(a, sl.x, y0, 2, 5, Areas.FLOOR)
          local vy = top and 0 or h - 1
          door(a, sl.x, vy, "v" .. floor, sl.x, top and 8 or 3, { staff = true, fx = sl.x, fy = top and 1 or h - 2 })
          door(a, sl.x + 1, vy, "v" .. floor, sl.x + 1, top and 8 or 3, { staff = true, fx = sl.x + 1, fy = top and 1 or h - 2 })
          obj(a, "sign", sl.x, y0, 2, 5, { staffSign = true })
          obj(a, "phone", sl.x + 1, top and 2 or h - 3, 1, 1)
          set(a, sl.x + 1, top and 2 or h - 3, Areas.KIOSK)
        elseif sl.kind == "wall" then
          rect(a, sl.x, y0, sl.w, 5, Areas.FACADE)
        else
          rect(a, sl.x, y0, sl.w, 5, Areas.FACADE)
          for i = sl.x + 1, sl.x + sl.w - 2 do set(a, i, dy, Areas.WINDOW) end
          local s = sl.store and W.stores[sl.store]
          local dxx = sl.x + math.floor(sl.w / 2) - 1
          if s and s.open then
            local sw, sh = interiorSize(s)
            door(a, dxx, dy, "s" .. s.id, math.floor(sw / 2) - 1, sh - 2, { store = s.id, fx = dxx, fy = fy })
            door(a, dxx + 1, dy, "s" .. s.id, math.floor(sw / 2), sh - 2, { store = s.id, fx = dxx + 1, fy = fy })
          else
            for i = sl.x, sl.x + sl.w - 1 do set(a, i, dy, Areas.PAPERED) end
          end
          a.objs[#a.objs + 1] = { kind = "sign", x = sl.x, y = y0, w = sl.w, h = 5, store = sl.store, slot = sl.id, top = top }
        end
      end
    end
  end
  -- center court
  rect(a, c0, 0, c1 - c0 + 1, h, Areas.WALL)
  rect(a, c0, 5, c1 - c0 + 1, 8, Areas.TILE2)
  for _, ex in ipairs({ c0 + 2, c1 - 3 }) do
    rect(a, ex, 7, 2, 4, Areas.ESC)
    obj(a, "escalator", ex, 7, 2, 4, { to = floor == 1 and "c2" or "c1", ax = ex + (ex < c0 + 5 and 2 or -1), ay = 9 })
  end
  if floor == 1 then
    rect(a, c0 + 6, 7, 6, 4, Areas.FOUNTAIN)
    obj(a, "fountain", c0 + 6, 7, 6, 4)
    obj(a, "directory", c0 + 8, 4, 2, 1)
    set(a, c0 + 8, 4, Areas.KIOSK); set(a, c0 + 9, 4, Areas.KIOSK)
    obj(a, "phone", c0 + 4, 4, 1, 1)
    rect(a, c0 + 6, 13, 6, 5, Areas.TILE2)
    for i = c0 + 7, c0 + 10 do door(a, i, h - 1, "lot", 18 + (i - c0 - 7), 2, { fx = i, fy = h - 2 }) end
    door(a, c0 + 2, 13, "sec", 3, 8, { fx = c0 + 2, fy = 12, label = "SECURITY" })
    obj(a, "sign", c0, 13, 5, 1, { text = "SECURITY" })
    rect(a, c0 + 5, 12, 2, 1, Areas.BENCH); obj(a, "bench", c0 + 5, 12, 2, 1)
    rect(a, c0 + 11, 12, 2, 1, Areas.BENCH); obj(a, "bench", c0 + 11, 12, 2, 1)
    spot(a, "hang", c0 + 6, 6); spot(a, "hang", c0 + 11, 6); spot(a, "hang", c0 + 5, 11)
    spot(a, "hang", c0 + 12, 11); spot(a, "hang", c0 + 9, 11); spot(a, "hang", c0 + 8, 6)
  else
    rect(a, c0 + 6, 7, 6, 4, Areas.VOID)
    obj(a, "atrium", c0 + 6, 7, 6, 4)
    rect(a, c0 + 5, 0, 8, 5, Areas.TILE2)
    for i = c0 + 7, c0 + 10 do door(a, i, 0, "fc", 24 + (i - c0 - 7), 16, { fx = i, fy = 1 }) end
    obj(a, "sign", c0 + 5, 0, 8, 1, { text = "FOOD COURT" })
    door(a, c0 + 2, 13, "mgmt", 3, 8, { fx = c0 + 2, fy = 12, label = "MALL OFFICE" })
    obj(a, "sign", c0, 13, 5, 1, { text = "OFFICE" })
    obj(a, "phone", c1 - 2, 13, 1, 1)
    spot(a, "hang", c0 + 5, 6); spot(a, "hang", c0 + 12, 6); spot(a, "hang", c0 + 5, 11); spot(a, "hang", c0 + 12, 11)
  end
  -- corridor furniture: kiosks + planters + benches in the middle rows
  local r = U.rng(W.seed, "furniture", floor)
  local x = MallGen.ANCHOR_W + r:i(6, 12)
  local KIOSKS = { "sunglasses", "pager", "earrings", "calendar", "pretzel cart", "hat", "cellphone", "perfume" }
  while x < w - MallGen.ANCHOR_W - 6 do
    if x < c0 - 3 or x > c1 + 2 then
      local roll = r:f()
      if roll < 0.35 then
        rect(a, x, 8, 2, 2, Areas.KIOSK)
        obj(a, "kiosk", x, 8, 2, 2, { what = r:pick(KIOSKS) })
      elseif roll < 0.7 then
        rect(a, x, 8, 3, 2, Areas.PLANTER); obj(a, "planter", x, 8, 3, 2)
      else
        rect(a, x, 8, 2, 1, Areas.BENCH); obj(a, "bench", x, 8, 2, 1)
        rect(a, x, 9, 2, 1, Areas.BENCH); obj(a, "bench", x, 9, 2, 1)
        spot(a, "hang", x - 1, 8); spot(a, "hang", x + 2, 9)
      end
    end
    x = x + r:i(9, 16)
  end
  -- walker lap spots
  spot(a, "lap", MallGen.ANCHOR_W + 2, 6); spot(a, "lap", w - MallGen.ANCHOR_W - 3, 11)
  return a
end

-- ------------------------------------------------------------ store interiors
local RACK_CATS = {
  music = "album", video = "vhs", clothing = "clothes", shoes = "clothes", books = "book",
  toys = "toy", games = "game", jewelry = "jewelry", sporting = "sport", gifts = "gift",
  electronics = "electronic", photo = "photo", weird = "weird", services = "service",
  department = "clothes", salon = "salon", restaurant = "food",
}
Areas.RACK_CATS = RACK_CATS

local function buildStore(s)
  local w, h = interiorSize(s)
  local typ = s.type
  local fl = (typ == "arcade" or typ == "cinema") and Areas.LOUD or (typ == "restaurant" and Areas.TILE2 or Areas.CARPET)
  local a = grid("s" .. s.id, w, h, fl, s.name, "store")
  a.store = s.id
  box(a, fl, Areas.WALL)
  local r = U.rng(W.seed, "interior", s.id, s.type)
  local pa, fdx, fdy, fx, fy = Areas.storefront(s)
  local mid = math.floor(w / 2)
  if s.row == "west" or s.row == "east" then
    door(a, mid - 1, h - 1, "c1", fx, fy); door(a, mid, h - 1, "c1", fx, fy + 1)
    -- upstairs entrance for anchors
    local ex = s.row == "west" and MallGen.ANCHOR_W or W.mall.w - MallGen.ANCHOR_W - 1
    door(a, 1, 0, "c2", ex, 8, { label = "2F" })
    rect(a, 1, 1, 2, 2, Areas.ESC)
  elseif s.row == "fc" then
    door(a, mid - 1, h - 1, "fc", Areas.fcW() - 2, 8); door(a, mid, h - 1, "fc", Areas.fcW() - 2, 9)
  else
    door(a, mid - 1, h - 1, pa, fx, fy); door(a, mid, h - 1, pa, fx + 1, fy)
  end
  if s.type ~= "cinema" then
    door(a, w - 3, 0, "b" .. s.id, 5, 7, { staff = true, label = "EMPLOYEES" })
  end
  a.objs[#a.objs + 1] = { kind = "wallsign", x = math.floor(w / 2) - 3, y = 0, w = 6, h = 1, store = s.id }
  local pr = U.rng(W.seed, "posters", s.id)
  for _, px in ipairs({ 2, w - 6 }) do
    if pr:chance(0.7) then a.objs[#a.objs + 1] = { kind = "wallposter", x = px, y = 0, w = 1, h = 1, seed = pr:next() } end
  end
  local cat = RACK_CATS[typ]
  local function counter(x, y, cw)
    rect(a, x, y, cw, 1, Areas.COUNTER)
    obj(a, "counter", x, y, cw, 1, { store = s.id })
    spot(a, "work", x + 1, y - 1)
    spot(a, "queue", x + 1, y + 1)
  end
  if typ == "arcade" then
    counter(2, 3, 4)
    obj(a, "tokens", 7, 1, 1, 1); set(a, 7, 1, Areas.KIOSK)
    obj(a, "prize", 2, 1, 3, 1); rect(a, 2, 1, 3, 1, Areas.SHELF)
    local mi = 1
    for row = 0, 1 do
      for col = 0, 5 do
        local mx, my = 5 + col * 3, 6 + row * 4
        if mx < w - 2 and W.arcade.machines[mi] then
          set(a, mx, my, Areas.CAB)
          obj(a, "cab", mx, my, 1, 1, { machine = mi })
          spot(a, "play", mx, my + 1)
          mi = mi + 1
        end
      end
    end
    spot(a, "hang", 3, 10); spot(a, "hang", 20, 12); spot(a, "hang", 12, 12)
  elseif typ == "cinema" then
    for n = 1, 6 do
      local sx = 3 + (n - 1) * 3
      set(a, sx, 0, Areas.LOCKDOOR)
      obj(a, "screen", sx, 0, 1, 1, { screen = n })
    end
    rect(a, 2, 6, 5, 1, Areas.COUNTER); obj(a, "booth", 2, 6, 5, 1, { store = s.id }); spot(a, "work", 4, 5)
    rect(a, 15, 6, 7, 1, Areas.COUNTER); obj(a, "concession", 15, 6, 7, 1, { store = s.id }); spot(a, "work", 18, 5)
    spot(a, "work", 10, 2); spot(a, "queue", 4, 7); spot(a, "queue", 18, 7)
    spot(a, "hang", 10, 10); spot(a, "hang", 14, 11); spot(a, "hang", 7, 11)
    obj(a, "poster", 1, 3, 1, 1)
  elseif typ == "salon" then
    counter(2, 3, 4)
    for i = 0, 3 do
      local cx = 8 + i * 3
      if cx < w - 2 then set(a, cx, 5, Areas.DESK); obj(a, "chair", cx, 5, 1, 1, { store = s.id }); spot(a, "work", cx, 4) end
    end
    spot(a, "shop", 5, 9); spot(a, "shop", 9, 10)
  elseif typ == "restaurant" then
    counter(2, 3, 5)
    for ty = 6, 10, 4 do for tx = 3, w - 4, 5 do
      rect(a, tx, ty, 2, 1, Areas.TABLE); obj(a, "table", tx, ty, 2, 1, { store = s.id })
      spot(a, "eat", tx, ty + 1); spot(a, "eat", tx + 1, ty - 1)
    end end
  else
    counter(2, 3, 5)
    if typ == "photo" then obj(a, "lab", 2, 1, 2, 1, { store = s.id }); rect(a, 2, 1, 2, 1, Areas.DESK) end
    -- racks in rows
    local rows = { 6, 9 }
    if h >= 14 then rows = { 6, 9, 11 } end
    local ri = 0
    for _, ry in ipairs(rows) do
      local rx = 2
      while rx + 3 < w - 1 do
        local rw = r:i(3, 4)
        if rx + rw >= w - 1 then break end
        if not (ry >= h - 3 and rx <= mid + 1 and rx + rw >= mid - 1) then
          ri = ri + 1
          rect(a, rx, ry, rw, 1, Areas.RACK)
          obj(a, "rack", rx, ry, rw, 1, { store = s.id, cat = cat, idx = ri })
          spot(a, "shop", rx + 1, ry + 1)
          spot(a, "stock", rx + rw, ry)
        end
        rx = rx + rw + 2
      end
    end
    -- wall shelves along the top
    rect(a, 8, 1, math.min(8, w - 12), 1, Areas.SHELF)
    ri = ri + 1
    obj(a, "rack", 8, 1, math.min(8, w - 12), 1, { store = s.id, cat = cat, idx = ri, wall = true })
    if typ == "clothing" or typ == "department" then
      rect(a, w - 3, 3, 2, 2, Areas.DESK); obj(a, "fitting", w - 3, 3, 2, 2)
    end
    if typ == "music" then obj(a, "listen", w - 2, 6, 1, 1); set(a, w - 2, 6, Areas.KIOSK) end
    if typ == "video" then obj(a, "dropbox", w - 2, h - 3, 1, 1); set(a, w - 2, h - 3, Areas.KIOSK) end
  end
  -- security hardware
  if s.sec >= 1 then obj(a, "camera", w - 2, 1, 1, 1, { cam = true, r = 7 }) end
  if s.sec >= 2 then obj(a, "camera", 1, h - 2, 1, 1, { cam = true, r = 7 }) end
  if s.sec >= 3 then obj(a, "gate", mid - 2, h - 2, 1, 1); obj(a, "gate", mid + 1, h - 2, 1, 1) end
  spot(a, "wait", mid, h - 3)
  spot(a, "shop", mid - 3, h - 4); spot(a, "shop", mid + 3, h - 4)
  return a
end

local function buildBack(s)
  local sw = interiorSize(s)
  local a = grid("b" .. s.id, 12, 9, Areas.FLOOR, s.name .. " (back)", "back")
  a.store = s.id
  box(a, Areas.FLOOR, Areas.WALL)
  door(a, 5, 8, "s" .. s.id, sw - 3, 1, { label = "STORE" })
  local pa, _, _, fx = Areas.storefront(s)
  local vf = s.floor or 2
  local vy = (s.row == "bot") and 8 or 3
  if s.row == "fc" then vf = 2 end
  door(a, 11, 4, "v" .. vf, fx or 20, vy, { label = "SERVICE" })
  rect(a, 1, 1, 3, 2, Areas.CRATE); obj(a, "crates", 1, 1, 3, 2, { store = s.id })
  rect(a, 8, 1, 2, 1, Areas.DESK); obj(a, "desk", 8, 1, 2, 1, { store = s.id })
  obj(a, "timeclock", 6, 1, 1, 1, { store = s.id }); set(a, 6, 1, Areas.KIOSK)
  rect(a, 1, 6, 2, 1, Areas.CRATE)
  spot(a, "work", 4, 3); spot(a, "break", 8, 5); spot(a, "break", 3, 5)
  return a
end

-- ------------------------------------------------------------ food court
local function buildFoodCourt()
  local w, h = Areas.fcW(), 18
  local a = grid("fc", w, h, Areas.TILE2, "Food Court", "fc")
  box(a, Areas.TILE2, Areas.WALL)
  rect(a, 1, 0, w - 2, 3, Areas.FACADE)
  rect(a, 1, 3, w - 2, 1, Areas.FLOOR) -- kitchen strip behind counters
  local SW = Areas.STALL
  for i, sid in ipairs(W.mall.foodStalls) do
    local x = 2 + (i - 1) * SW
    rect(a, x, 4, SW - 1, 1, Areas.COUNTER)
    obj(a, "stall", x, 4, SW - 1, 1, { store = sid })
    obj(a, "sign", x, 0, SW - 1, 2, { store = sid, stallSign = true })
    spot(a, "work", x + 2, 3); spot(a, "queue", x + 2, 5)
  end
  local endx = 2 + #W.mall.foodStalls * SW
  if endx < w - 3 then rect(a, endx, 4, w - 3 - endx, 1, Areas.WALL) end
  local r = U.rng(W.seed, "fc")
  for ty = 7, 12, 3 do
    for tx = 12, w - 8, 5 do
      rect(a, tx, ty, 2, 1, Areas.TABLE)
      obj(a, "table", tx, ty, 2, 1)
      spot(a, "eat", tx, ty - 1); spot(a, "eat", tx + 1, ty + 1); spot(a, "hang", tx - 1, ty)
    end
  end
  rect(a, 1, 12, 8, 5, Areas.STAGE)
  obj(a, "stage", 1, 12, 8, 5)
  spot(a, "stage", 4, 14); spot(a, "stage", 6, 14); spot(a, "stage", 3, 15)
  for i = 24, 27 do door(a, i, h - 1, "c2", W.mall.court0 + 7 + (i - 24), 1) end
  door(a, w - 1, 8, "s" .. W.mall.cinema, 12, 12, { label = "CINEMA" })
  door(a, w - 1, 9, "s" .. W.mall.cinema, 12, 12, { label = "CINEMA" })
  obj(a, "sign", w - 9, 0, 6, 2, { text = "CINEPLEX 6", neon = true, cinema = true })
  obj(a, "phone", 10, 16, 1, 1)
  local cin = W.stores[W.mall.cinema]
  -- cinema's back room reachable from the fc kitchen strip
  door(a, w - 3, 3, "b" .. cin.id, 5, 5, { staff = true })
  return a
end

-- ------------------------------------------------------------ service
local function buildService(f)
  local w, h = W.mall.w, 12
  local a = grid("v" .. f, w, h, Areas.WALL, f == 1 and "Service Corridor B1" or "Service Corridor 2", "service")
  rect(a, 1, 3, w - 2, 6, Areas.FLOOR)
  for _, s in ipairs(W.stores) do
    if s.open and s.floor == f and s.row ~= "fc" and s.row ~= "west" and s.row ~= "east" then
      local _, _, _, fx = Areas.storefront(s)
      local y = s.row == "bot" and 9 or 2
      door(a, fx, y, "b" .. s.id, 10, 4, { staff = true, store = s.id, fx = fx, fy = s.row == "bot" and 8 or 3 })
    end
  end
  for _, sl in ipairs(W.slots) do
    if sl.kind == "gap" and sl.floor == f then
      local y = sl.row == "top" and 9 or 2
      local cy = sl.row == "top" and 1 or MallGen.H - 2
      door(a, sl.x, y, "c" .. f, sl.x, cy, { fx = sl.x, fy = sl.row == "top" and 8 or 3 })
    end
  end
  local c0 = W.mall.court0
  -- freight elevator between floors
  door(a, c0 + 8, 9, f == 1 and "v2" or "v1", c0 + 8, 8, { label = "FREIGHT" })
  if f == 1 then
    door(a, w - 2, 5, "dock", 1, 6, { label = "DOCK" }); door(a, w - 2, 6, "dock", 1, 6)
    door(a, c0 + 12, 2, "maint", 2, 6, { label = "MAINT." })
    door(a, c0 + 3, 9, "sec", 12, 8, { label = "SECURITY" })
  else
    door(a, c0 + 3, 9, "mgmt", 12, 8, { label = "OFFICES" })
  end
  local sl = W.slots[W.mall.abandonedSlot]
  if sl.floor == f then
    door(a, sl.x + 1, sl.row == "top" and 2 or 9, "ab", 8, 11, { label = "?", hidden = true })
  end
  for x = 6, w - 6, 23 do obj(a, "pipes", x, 1, 3, 1) end
  spot(a, "walk", 10, 5); spot(a, "walk", w - 10, 6); spot(a, "break", c0 + 5, 7); spot(a, "break", c0 + 14, 4)
  return a
end

-- ------------------------------------------------------------ special rooms
local function room(id, w, h, name, kind, floorc)
  local a = grid(id, w, h, floorc or Areas.FLOOR, name, kind)
  box(a, floorc or Areas.FLOOR, Areas.WALL)
  return a
end

local builders = {}
builders.sec = function()
  local a = room("sec", 16, 12, "Security Office", "office", Areas.CARPET)
  local c0 = W.mall.court0
  door(a, 3, 11, "c1", c0 + 2, 12, { label = "CONCOURSE" })
  door(a, 15, 8, "v1", c0 + 3, 8, { label = "SERVICE" })
  rect(a, 2, 1, 8, 1, Areas.KIOSK); obj(a, "monitors", 2, 1, 8, 1)
  spot(a, "work", 5, 2); spot(a, "work", 8, 2)
  rect(a, 11, 1, 4, 4, Areas.WALL); rect(a, 12, 2, 2, 2, Areas.FLOOR)
  obj(a, "holding", 11, 1, 4, 4); spot(a, "hold", 12, 2)
  rect(a, 3, 6, 3, 1, Areas.DESK); obj(a, "desk", 3, 6, 3, 1, { office = "sec" })
  spot(a, "chief", 4, 5); spot(a, "break", 9, 8)
  return a
end
builders.mgmt = function()
  local a = room("mgmt", 16, 12, "Mall Management", "office", Areas.CARPET)
  local c0 = W.mall.court0
  door(a, 3, 11, "c2", c0 + 2, 12, { label = "CONCOURSE" })
  door(a, 15, 8, "v2", c0 + 3, 8, { label = "SERVICE" })
  rect(a, 2, 3, 4, 1, Areas.COUNTER); obj(a, "reception", 2, 3, 4, 1); spot(a, "work", 3, 2)
  rect(a, 10, 2, 3, 1, Areas.DESK); obj(a, "desk", 10, 2, 3, 1, { office = "gm" }); spot(a, "chief", 11, 1)
  obj(a, "leasing", 7, 1, 2, 1); rect(a, 7, 1, 2, 1, Areas.SHELF)
  rect(a, 9, 6, 4, 2, Areas.TABLE); obj(a, "table", 9, 6, 4, 2); spot(a, "work", 8, 7); spot(a, "work", 13, 6)
  return a
end
builders.maint = function()
  local a = room("maint", 20, 12, "Maintenance", "maint", Areas.FLOOR)
  local c0 = W.mall.court0
  door(a, 1, 6, "v1", c0 + 12, 3, { label = "SERVICE" })
  rect(a, 3, 1, 6, 1, Areas.SHELF); obj(a, "workbench", 3, 1, 6, 1)
  rect(a, 12, 5, 3, 2, Areas.CRATE)
  obj(a, "ladder", 16, 1, 1, 1, { to = "roof", lock = "roof" }); set(a, 16, 1, Areas.GRATE)
  obj(a, "hatch", 14, 8, 1, 1, { to = "tun", lock = "tunnel" }); set(a, 14, 8, Areas.GRATE)
  obj(a, "locker", 18, 9, 1, 2); rect(a, 18, 9, 1, 2, Areas.SHELF)
  spot(a, "work", 5, 2); spot(a, "work", 10, 8); spot(a, "break", 7, 9)
  return a
end
builders.dock = function()
  local a = room("dock", 24, 12, "Loading Dock", "dock", Areas.ASPHALT)
  door(a, 0, 6, "v1", W.mall.w - 3, 6, { label = "SERVICE" })
  rect(a, 6, 1, 4, 3, Areas.CAR); obj(a, "truck", 6, 1, 4, 3)
  rect(a, 14, 1, 4, 3, Areas.CAR); obj(a, "truck", 14, 1, 4, 3)
  rect(a, 20, 8, 2, 2, Areas.CRATE); obj(a, "dumpster", 20, 8, 2, 2)
  door(a, 23, 10, "lot", 38, 20, { label = "LOT" })
  spot(a, "break", 4, 9); spot(a, "break", 12, 9); spot(a, "work", 10, 6)
  return a
end
builders.lot = function()
  local w, h = 40, 22
  local a = grid("lot", w, h, Areas.ASPHALT, "Parking Lot", "lot")
  rect(a, 0, 0, w, 2, Areas.FACADE)
  rect(a, 16, 0, 8, 2, Areas.WINDOW)
  local c0 = W.mall.court0
  for i = 18, 21 do door(a, i, 1, "c1", c0 + 7 + (i - 18), 16) end
  obj(a, "sign", 12, 0, 16, 2, { text = W.mall.name, neon = true })
  local r = U.rng(W.seed, "lot")
  for row = 5, 15, 5 do
    for col = 2, w - 4, 3 do
      if r:chance(0.55) and not (col >= 16 and col <= 23) then
        rect(a, col, row, 2, 2, Areas.CAR); obj(a, "car", col, row, 2, 2)
      end
    end
  end
  obj(a, "bus", 2, 18, 3, 2); rect(a, 2, 18, 3, 1, Areas.BENCH)
  obj(a, "lamp", 10, 10, 1, 1); obj(a, "lamp", 30, 10, 1, 1)
  door(a, w - 1, 20, "dock", 22, 10, { label = "DOCK" })
  spot(a, "hang", 5, 17); spot(a, "hang", 20, 4); spot(a, "hang", 25, 4)
  return a
end
builders.roof = function()
  local a = room("roof", 30, 16, "Roof", "roof", Areas.GRATE)
  door(a, 10, 1, "maint", 16, 2, { label = "LADDER" })
  for x = 3, 25, 7 do rect(a, x, 5, 3, 2, Areas.HVAC); obj(a, "hvac", x, 5, 3, 2) end
  rect(a, 11, 9, 8, 4, Areas.SKY); obj(a, "skylight", 11, 9, 8, 4)
  obj(a, "chair", 24, 12, 1, 1, { lore = "roofchair" }); set(a, 24, 12, Areas.DESK)
  obj(a, "view", 1, 14, 28, 1)
  spot(a, "hang", 22, 12); spot(a, "hang", 5, 13)
  return a
end
builders.tun = function()
  local a = grid("tun", 50, 14, Areas.WALL, "Maintenance Tunnels", "tunnel")
  rect(a, 1, 5, 48, 3, Areas.DUST)
  rect(a, 22, 7, 3, 4, Areas.DUST); rect(a, 42, 2, 4, 4, Areas.DUST)
  door(a, 2, 5, "maint", 14, 7, { label = "UP" })
  door(a, 44, 2, "shel", 3, 6, { label = "SHELTER", lock = "shelter" })
  door(a, 24, 10, "off", 3, 6, { label = "OFFICE" })
  for x = 4, 46, 6 do obj(a, "pipes", x, 4, 2, 1); set(a, x, 4, Areas.PIPE) end
  obj(a, "graffiti", 30, 8, 1, 1, { lore = "graffiti" })
  return a
end
builders.shel = function()
  local a = room("shel", 20, 12, "Fallout Shelter", "shelter", Areas.DUST)
  door(a, 1, 6, "tun", 44, 3, { label = "TUNNEL" })
  rect(a, 3, 1, 4, 2, Areas.CRATE); obj(a, "supplies", 3, 1, 4, 2, { lore = "supplies" })
  rect(a, 12, 8, 6, 1, Areas.SHELF); obj(a, "bunks", 12, 8, 6, 1)
  obj(a, "sign", 8, 0, 4, 1, { text = "FALLOUT SHELTER 1962" })
  obj(a, "lockdoor", 17, 1, 1, 1, { to = "lock" }); set(a, 17, 1, Areas.LOCKDOOR)
  return a
end
builders.off = function()
  local a = room("off", 14, 10, "Forgotten Office", "office", Areas.DUST)
  door(a, 1, 6, "tun", 24, 9, { label = "TUNNEL" })
  rect(a, 5, 2, 4, 1, Areas.DESK); obj(a, "desk", 5, 2, 4, 1, { lore = "memo" })
  obj(a, "blueprints", 11, 1, 2, 1, { lore = "blueprint" }); rect(a, 11, 1, 2, 1, Areas.SHELF)
  obj(a, "calendar", 2, 1, 1, 1, { lore = "calendar79" })
  return a
end
builders.lock = function()
  local a = room("lock", 16, 12, "The Locked Room", "lock", Areas.FLOOR)
  door(a, 2, 6, "shel", 16, 2, { label = "BACK" })
  rect(a, 5, 3, 7, 5, Areas.TABLE); obj(a, "model", 5, 3, 7, 5, { lore = "model" })
  obj(a, "ledger", 13, 1, 1, 1, { lore = "ledger" }); set(a, 13, 1, Areas.DESK)
  return a
end
builders.ab = function()
  local sl = W.slots[W.mall.abandonedSlot]
  local a = room("ab", 18, 13, "Vacant Storefront", "abandoned", Areas.DUST)
  door(a, 8, 12, "v" .. sl.floor, sl.x + 1, sl.row == "top" and 3 or 8, { label = "BACK" })
  rect(a, 2, 3, 4, 1, Areas.COUNTER); obj(a, "oldcounter", 2, 3, 4, 1, { lore = "oldcounter" })
  rect(a, 9, 5, 3, 1, Areas.RACK); rect(a, 9, 8, 3, 1, Areas.RACK)
  obj(a, "sleepingbag", 14, 9, 2, 1, { lore = "sleepingbag" })
  obj(a, "calendar", 15, 1, 1, 1, { lore = "calendar91" })
  obj(a, "papered", 1, 12, 7, 1)
  return a
end

function Areas.build(id)
  if cache[id] then return cache[id] end
  local a
  if id == "c1" then a = buildConcourse("c1", 1)
  elseif id == "c2" then a = buildConcourse("c2", 2)
  elseif id == "fc" then a = buildFoodCourt()
  elseif id == "v1" then a = buildService(1)
  elseif id == "v2" then a = buildService(2)
  elseif builders[id] then a = builders[id]()
  else
    local kind, num = id:match("^([sb])(%d+)$")
    if kind then
      local s = W.stores[tonumber(num)]
      if kind == "s" then a = buildStore(s) else a = buildBack(s) end
    end
  end
  assert(a, "unknown area " .. tostring(id))
  cache[id] = a
  return a
end

function Areas.name(id)
  if id == "home" then return "Home" end
  if id:match("^scr") then return "Screen " .. id:sub(4) end
  local kind, num = id:match("^([sb])(%d+)$")
  if kind then
    local s = W.stores[tonumber(num)]
    return kind == "s" and s.name or (s.name .. " stockroom")
  end
  local names = { c1 = "Lower Level", c2 = "Upper Level", fc = "Food Court", v1 = "Service Corridor",
    v2 = "Upper Service Corridor", dock = "Loading Dock", mgmt = "Mall Office", sec = "Security Office",
    maint = "Maintenance", roof = "Roof", lot = "Parking Lot", tun = "Tunnels", shel = "Fallout Shelter",
    off = "Forgotten Office", lock = "Locked Room", ab = "Vacant Storefront" }
  return names[id] or id
end

-- random spot of a kind in an area (tile coords); falls back to any walkable
function Areas.spot(id, kind, r)
  if id == "home" or id:match("^scr") then return 0, 0 end
  local a = Areas.build(id)
  local list = {}
  for _, s in ipairs(a.spots) do if s.kind == kind then list[#list + 1] = s end end
  if #list == 0 then
    for _, s in ipairs(a.spots) do if s.kind == "hang" or s.kind == "shop" or s.kind == "wait" then list[#list + 1] = s end end
  end
  if #list > 0 then
    local s = list[1 + (r:next() % #list)]
    return s.x, s.y
  end
  for _ = 1, 40 do
    local x, y = r:i(1, a.w - 2), r:i(1, a.h - 2)
    if Areas.walkable(a, x, y) then return x, y end
  end
  return 1, 1
end

-- parent chain for routing
function Areas.chain(id)
  local c = { id }
  local cur = id
  for _ = 1, 12 do
    if cur == "c1" then break end
    local p = Areas.portal(cur)
    if not p then break end
    c[#c + 1] = p
    cur = p
  end
  return c
end
