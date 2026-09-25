-- NPC AI: daily plans from role + schedule + wants, physical travel through
-- the area tree (legs with timed waypoints), and arrival behaviours.
--
-- Plan block: { s = start minute-of-day, e = end, a = area id, act = verb,
--               ref = optional reference, sk = spot kind }

NPCAI = {}
NPCAI.byArea = {}     -- area id -> list of npc (rebuilt every tick; not saved)

local SPEED = { walker = 55, security = 70, default = 85 }

local ACT_SPOT = { work = "work", shop = "shop", eat = "eat", hang = "hang", play = "play",
  patrol = "hang", monitor = "work", fix = "work", ["break"] = "break", stage = "stage",
  chief = "chief", wait = "wait", date = "hang", lap = "lap", inspect = "hang", santa = "hang", tourney = "play" }

local function active(n) return n.status == "active" end

-- ------------------------------------------------------------------ plans
local function block(plan, s, e, a, act, ref, sk)
  if e <= s then return end
  plan[#plan + 1] = { s = math.floor(s), e = math.floor(e), a = a, act = act, ref = ref, sk = sk }
end

-- pick a store the NPC would plausibly visit
local function pickStore(n, r, types)
  local best, bw = nil, 0
  for _ = 1, 8 do
    local s = W.stores[r:i(1, #W.stores)]
    if s.open and s.type ~= "cinema" and (not types or types[s.type]) then
      local w = s.pop + 10
      if s.demo == "teens" and n.age < 20 then w = w * 1.8 end
      if (s.demo == "adults" or s.demo == "seniors") and n.age >= 30 then w = w * 1.5 end
      if s.demo == "families" and n.role == "parent" then w = w * 1.6 end
      if s.sale > 0 then w = w * 1.4 end
      w = w * Trends.storeBoost(s) * (0.6 + r:f())
      if w > bw then best, bw = s, w end
    end
  end
  return best
end
NPCAI.pickStore = pickStore

local TEEN_SPOTS = { "arcade", "fc", "music", "clothing", "fountain", "games", "cinema", "shoes", "gifts", "c2", "lot" }
local CLIQUE_PREF = {
  skaters = { arcade = 3, lot = 3, music = 2, shoes = 2 }, preps = { clothing = 3, fc = 2, gifts = 2, shoes = 2 },
  ["alt kids"] = { music = 4, fc = 1, gifts = 2 }, ["band kids"] = { music = 3, fc = 2, games = 1 },
  jocks = { fc = 3, shoes = 3, arcade = 1 }, ["mall rats"] = { arcade = 3, fc = 3, fountain = 2 },
  goths = { music = 3, gifts = 3, fountain = 1 }, nerds = { arcade = 4, games = 4, fc = 1 },
}

local function typeStore(r, typ)
  local cands = {}
  for _, s in ipairs(W.stores) do if s.open and s.type == typ then cands[#cands + 1] = s end end
  return r:pick(cands)
end

local function spotArea(n, r, what)
  if what == "arcade" then
    local s = W.stores[W.mall.arcade]
    if s.open then return "s" .. s.id, "play", s.id end
    return "fc", "hang"
  elseif what == "fc" then return "fc", r:chance(0.5) and "eat" or "hang"
  elseif what == "fountain" then
    if Management.has("loitering") and r:chance(0.6) then return "fc", "eat" end
    return "c1", "hang"
  elseif what == "c2" then return "c2", "hang"
  elseif what == "lot" then return "lot", "hang"
  elseif what == "cinema" then return "s" .. W.mall.cinema, "hang"
  else
    local s = typeStore(r, what)
    if s then return Areas.storeArea(s), "shop", s.id end
    return "fc", "hang"
  end
end

-- the place a clique converges on today (deterministic per clique/day)
function NPCAI.cliqueSpot(clique, day)
  local r = U.rng(W.seed, "clique", clique, day)
  local prefs = CLIQUE_PREF[clique] or {}
  local list = {}
  for k, v in pairs(prefs) do list[#list + 1] = { k, v } end
  table.sort(list, function(a, b) return a[1] < b[1] end)
  local pick = r:weighted(list, function(e) return e[2] end)
  return pick and pick[1] or "fc", r:i(0, 90)
end

local function teenPlan(n, day, info, plan, r, from, to)
  if to - from < 30 then return end
  local t = from
  local meet, meetOffset = NPCAI.cliqueSpot(n.clique or "mall rats", day)
  local meetT = from + meetOffset
  local used = 0
  while t < to - 20 and used < 5 do
    used = used + 1
    local what
    if t <= meetT and meetT < t + 90 and r:chance(0.7) then what = meet
    else
      local prefs = CLIQUE_PREF[n.clique] or {}
      what = r:weighted(TEEN_SPOTS, function(k) return (prefs[k] or 1) end)
    end
    local dur = r:i(25, 80)
    local a, act, ref = spotArea(n, r, what)
    -- movie with friends in the evening
    if what == "cinema" or (t > 17 * 60 and r:chance(0.12) and n.money > 800) then
      local show = CinemaSim.nextShow(t + 10, n)
      if show and show.t + show.mins < to + 30 then
        block(plan, t, show.t - 5, "s" .. W.mall.cinema, "hang")
        block(plan, show.t - 5, show.t + show.mins, "scr" .. show.screen, "watch", show.movie)
        t = show.t + show.mins
        goto continue
      end
    end
    block(plan, t, math.min(to, t + dur), a, act, ref)
    t = t + dur
    ::continue::
  end
end

local function shopperPlan(n, day, info, plan, r, from, to)
  local t = from
  local stops = r:i(1, 3)
  for _ = 1, stops do
    if t >= to - 15 then break end
    local s = pickStore(n, r)
    if s then
      local dur = r:i(12, 40)
      block(plan, t, math.min(to, t + dur), Areas.storeArea(s), s.type == "food" and "eat" or "shop", s.id)
      t = t + dur + r:i(2, 8)
    end
  end
  if r:chance(0.45) and t < to - 20 then block(plan, t, t + r:i(15, 35), "fc", "eat") end
end

function NPCAI.planDay(n, day)
  local info = Clock.info(day)
  local plan = {}
  local r = U.rng(W.seed, "plan", n.id, day)
  n.plan = plan
  n.pi = 1
  if not active(n) then return end
  local open, close = info.open, info.close
  local role = n.role
  if info.closed and role ~= "security" and role ~= "maint" then return end

  -- work first
  local shift = Stores.shiftOf(n, day)
  if shift then
    local s = type(n.job) == "number" and W.stores[n.job]
    local area = s and Areas.storeArea(s) or (n.job == "sec" and "sec" or n.job == "maint" and "maint" or "mgmt")
    local act = "work"
    if n.job == "sec" then act = (n.title == "chief" or r:chance(0.3)) and "monitor" or "patrol" end
    if n.job == "maint" then act = "fix" end
    local ss, se = shift[1], shift[2]
    if se - ss >= 300 and n.job ~= "sec" then
      local mid = ss + (se - ss) // 2
      block(plan, ss, mid, area, act)
      if s and s.type ~= "food" then block(plan, mid, mid + 30, r:chance(0.6) and "fc" or ("b" .. s.id), "break")
      else block(plan, mid, mid + 30, r:chance(0.5) and "fc" or "v1", "break") end
      block(plan, mid + 30, se, area, act)
    elseif n.job == "sec" and act == "patrol" then
      -- patrol legs across public areas
      local t = ss
      local zones = { "c1", "c2", "fc", "c1", "c2", "lot", "sec" }
      local zi = r:i(1, #zones)
      while t < se do
        local dur = r:i(40, 80)
        local z = zones[(zi % #zones) + 1]; zi = zi + 1
        block(plan, t, math.min(se, t + dur), z, z == "sec" and "monitor" or "patrol")
        t = t + dur
      end
    elseif n.job == "maint" then
      local t = ss
      local jobs = { "maint", "c1", "fc", "v1", "c2", "dock", "v2", "maint" }
      if n.id == W.mall.janitor then jobs = { "c1", "fc", "c2", "v1", "tun", "c1", "lock", "maint" } end
      local ji = r:i(1, #jobs)
      while t < se do
        local dur = r:i(45, 120)
        local z = jobs[(ji % #jobs) + 1]; ji = ji + 1
        block(plan, t, math.min(se, t + dur), z, "fix")
        t = t + dur
      end
    else
      block(plan, ss, se, area, act)
    end
    -- teens hang around after work
    if n.age < 20 and se < 20 * 60 and r:chance(0.5) then
      teenPlan(n, day, info, plan, r, se + 5, math.min(close, se + r:i(40, 120)))
    elseif n.age >= 20 and r:chance(0.12) and se < close - 30 then
      shopperPlan(n, day, info, plan, r, se + 5, math.min(close, se + 60))
    end
    -- the night janitor gets coffee in the food court before his shift
    if n.id == W.mall.janitor and not info.closed then
      table.insert(plan, 1, { s = 20 * 60, e = 21 * 60 + 25, a = "fc", act = "hang" })
    end
  elseif role == "teen" or (n.age < 20 and role == "employee") then
    local go = info.school and 0.45 or 0.72
    if info.wd == 0 then go = go * 0.7 end
    if n.clique == "mall rats" then go = go + 0.2 end
    if n.clique == "skaters" and Management.has("noSkate") then go = go * 0.7 end
    if n.grounded and n.grounded > day then go = 0 end
    if r:chance(go) then
      local from = info.school and (15 * 60 + r:i(0, 120)) or (open + r:i(60, 240))
      local curfew = (info.school and 21 * 60 or 22 * 60) - r:i(0, 90)
      if Management.has("teenEscort") and n.age < 16 and (info.wd == 5 or info.wd == 6) then curfew = math.min(curfew, 18 * 60) end
      local to = math.min(close, curfew)
      if n.age >= 18 then to = close end
      teenPlan(n, day, info, plan, r, from, to)
    end
  elseif role == "walker" then
    if not info.weekend or r:chance(0.3) then
      block(plan, 7 * 60 + r:i(0, 30), 9 * 60 + r:i(0, 40), "c1", "lap")
      if r:chance(0.4) then block(plan, 9 * 60 + 45, 10 * 60 + 40, "c2", "lap") end
      if r:chance(0.5) then block(plan, 10 * 60 + 45, 11 * 60 + 40, "fc", "eat") end
      if r:chance(0.2) then shopperPlan(n, day, info, plan, r, 12 * 60, 14 * 60) end
    end
  elseif role == "shopper" or role == "parent" or role == "manager" or role == "employee" or role == "mgmt" then
    local p = info.weekend and 0.42 or 0.22
    if info.holidaySeason then p = p + 0.25 end
    if info.holiday == "Black Friday" then p = 0.9 end
    if role == "manager" or role == "employee" then p = p * 0.5 end
    if r:chance(p) then
      local from = open + r:i(0, math.max(10, close - open - 90))
      shopperPlan(n, day, info, plan, r, from, math.min(close, from + r:i(60, 180)))
    end
  end

  -- social overrides: invitations accepted for today
  if n.dateToday and n.dateToday.day == day then
    local d = n.dateToday
    local keep = {}
    for _, b in ipairs(plan) do if b.e <= d.s or b.s >= d.e then keep[#keep + 1] = b end end
    if d.show and d.a:match("^scr") then
      block(keep, d.s, d.s + 15, "s" .. W.mall.cinema, "date", d.with)
      block(keep, d.s + 15, d.e, d.a, "watch", d.show)
    else
      block(keep, d.s, d.e, d.a, "date", d.with)
    end
    n.plan = keep
  end
  -- band practice / gigs
  if n.gig and n.gig.day == day then
    block(n.plan, n.gig.s, n.gig.e, "fc", "stage")
  end
  table.sort(n.plan, function(a, b) return a.s < b.s end)
  -- drop overlaps
  local clean, last = {}, -1
  for _, b in ipairs(n.plan) do
    if b.s >= last then clean[#clean + 1] = b; last = b.e end
  end
  n.plan = clean
end

-- ------------------------------------------------------------------ travel
local function px(t) return t * MallGen.TILE + MallGen.TILE // 2 end

local function laneY(r) local lanes = { 6, 7, 10, 11 } return px(lanes[1 + (r:next() % 4)]) end

-- build list of legs from (fromArea, fx, fy) to (toArea, tx, ty) [px coords]
function NPCAI.route(fromA, fx, fy, toA, tx, ty, r)
  local ca, cb = Areas.chain(fromA), Areas.chain(toA)
  local inB = {}
  for i, a in ipairs(cb) do inB[a] = i end
  local lca, ia
  for i, a in ipairs(ca) do if inB[a] then lca, ia = a, i break end end
  if not lca then lca = "c1"; ia = #ca end
  local seq = {}
  for i = 1, ia do seq[#seq + 1] = ca[i] end
  for i = inB[lca] - 1, 1, -1 do seq[#seq + 1] = cb[i] end
  local legs = {}
  local ib = inB[lca]
  for k, a in ipairs(seq) do
    local sx, sy, ex, ey
    if k == 1 then sx, sy = fx, fy
    else
      local prev = seq[k - 1]
      if k <= ia then -- came up from child prev
        local _, _, _, ppx, ppy = Areas.portal(prev)
        sx, sy = px(ppx), px(ppy)
      else -- came down into a from parent prev
        local _, cx, cy = Areas.portal(a)
        sx, sy = px(cx), px(cy)
      end
    end
    if k == #seq then ex, ey = tx, ty
    else
      local nxt = seq[k + 1]
      if k < ia then -- going up: exit through own portal
        local _, cx, cy = Areas.portal(a)
        ex, ey = px(cx), px(cy)
      else -- going down into nxt: walk to nxt's door in a
        local _, _, _, ppx, ppy = Areas.portal(nxt)
        ex, ey = px(ppx), px(ppy)
      end
    end
    local pts
    if (a == "c1" or a == "c2" or a == "v1" or a == "v2") and math.abs(ex - sx) > 48 then
      local ly = (a == "v1" or a == "v2") and px(r:i(4, 7)) or laneY(r)
      pts = { sx, sy, sx, ly, ex, ly, ex, ey }
    else
      pts = { sx, sy, ex, ey }
    end
    if a == "home" then pts = { 0, 0, 0, 0 } end
    legs[#legs + 1] = { a = a, pts = pts }
  end
  return legs
end

local function legLength(pts)
  local d = 0
  for i = 1, #pts - 2, 2 do d = d + U.dist(pts[i], pts[i + 1], pts[i + 2], pts[i + 3]) end
  return d
end

function NPCAI.depart(n, toA, act, ref, sk)
  local r = U.rng(W.seed, "dep", n.id, math.floor(W.t))
  local tx, ty = 0, 0
  if toA ~= "home" and not toA:match("^scr") then
    local kind = sk or ACT_SPOT[act] or "hang"
    local sxx, syy = Areas.spot(toA, kind, r)
    -- spread workers across work spots by id
    if kind == "work" then
      local a = Areas.build(toA)
      local ws = {}
      for _, s in ipairs(a.spots) do if s.kind == "work" or s.kind == "stock" then ws[#ws + 1] = s end end
      if #ws > 0 then local s = ws[1 + (n.id % #ws)]; sxx, syy = s.x, s.y end
    end
    tx, ty = px(sxx) + r:i(-4, 4), px(syy) + r:i(-3, 3)
  end
  local fromA = n.loc or "home"
  if n.route then
    local a, x, y = NPCAI.pos(n)
    fromA, n.x, n.y = a, x, y
  end
  local legs = NPCAI.route(fromA, n.x or 0, n.y or 0, toA, tx, ty, r)
  local speed = SPEED[n.role] or SPEED.default
  if n.age < 20 then speed = speed + 10 end
  local t = W.t
  for _, l in ipairs(legs) do
    l.t0 = t
    local d = legLength(l.pts)
    if l.a == "home" then d = 0 end
    l.t1 = t + d / speed
    t = l.t1
  end
  n.route = legs
  n.leg = 1
  n.dest, n.destAct, n.destRef = toA, act, ref
  n.act = "walk"
  n.loc = legs[1].a
  n.tx, n.ty = tx, ty
end

-- position at current world time; returns area, x, y, moving, dir
function NPCAI.pos(n)
  local rt = n.route
  if not rt then return n.loc, n.x, n.y, false end
  local l = rt[n.leg]
  if not l then return n.loc, n.x, n.y, false end
  local t = W.t
  local frac = (l.t1 > l.t0) and U.clamp((t - l.t0) / (l.t1 - l.t0), 0, 1) or 1
  local pts = l.pts
  local total = legLength(pts)
  local want = total * frac
  for i = 1, #pts - 2, 2 do
    local seg = U.dist(pts[i], pts[i + 1], pts[i + 2], pts[i + 3])
    if want <= seg or i >= #pts - 3 then
      local f = seg > 0 and U.clamp(want / seg, 0, 1) or 1
      local x = U.lerp(pts[i], pts[i + 2], f)
      local y = U.lerp(pts[i + 1], pts[i + 3], f)
      local dx, dy = pts[i + 2] - pts[i], pts[i + 3] - pts[i + 1]
      local dir
      if math.abs(dx) > math.abs(dy) then dir = dx > 0 and "right" or "left" else dir = dy > 0 and "down" or "up" end
      return l.a, x, y, true, dir
    end
    want = want - seg
  end
  return l.a, pts[#pts - 1], pts[#pts], true
end

local function arrive(n)
  n.route = nil
  n.loc = n.dest
  n.x, n.y = n.tx, n.ty
  n.act = n.destAct
  n.arrivedAt = W.t
  Econ.onArrive(n, n.destAct, n.destRef)
end

-- ------------------------------------------------------------------ tick
function NPCAI.update(dt)
  local t = W.t
  local mod = Clock.minute(t)
  local day = Clock.day(t)
  local byArea = {}
  for _, n in ipairs(W.npcs) do
    if n.status == "active" then
      -- travel progress
      if n.route then
        while n.route and n.route[n.leg] and t >= n.route[n.leg].t1 do
          n.leg = n.leg + 1
          if not n.route[n.leg] then arrive(n) end
        end
        if n.route then n.loc = n.route[n.leg].a end
      end
      -- plan progress
      if not n.route and not n.held then
        local plan = n.plan
        local b = plan and plan[n.pi]
        while b and mod >= b.e do n.pi = n.pi + 1; b = plan[n.pi] end
        if b and mod >= b.s then
          if n.dest ~= b.a or n.loc ~= b.a then
            NPCAI.depart(n, b.a, b.act, b.ref, b.sk)
          elseif (b.act == "patrol" or b.act == "lap" or b.act == "fix" or b.act == "inspect")
            and t - (n.arrivedAt or 0) > 6 then
            -- keep moving within the zone
            NPCAI.depart(n, b.a, b.act, b.ref, b.act == "lap" and "lap" or "hang")
          end
        elseif (not b or mod < b.s) and n.loc ~= "home" and n.dest ~= "home" then
          -- nothing to do right now: go home (or wait if next block is soon)
          if not b or b.s - mod > 45 then NPCAI.depart(n, "home", "home") end
        end
      end
      local a = n.loc
      if a and a ~= "home" then
        local list = byArea[a]
        if not list then list = {}; byArea[a] = list end
        list[#list + 1] = n
      end
    end
  end
  NPCAI.byArea = byArea
end

-- place everyone at home and plan the day (used at dawn)
function NPCAI.newDay(day)
  for _, n in ipairs(W.npcs) do
    if n.status == "active" then
      if n.loc ~= "home" and not (n.job == "sec" or n.job == "maint") then
        n.route = nil; n.loc = "home"; n.dest = "home"
      end
      n.held = nil
      NPCAI.planDay(n, day)
    end
  end
end

function NPCAI.inArea(a) return NPCAI.byArea[a] or {} end

-- what an NPC is currently doing, for dialogue and the people list
function NPCAI.describe(n)
  local act = n.act or "home"
  local where = Areas.name(n.dest or n.loc or "home")
  if n.loc == "home" and not n.route then return "at home in " .. n.home end
  local verbs = { work = "working at ", shop = "shopping at ", eat = "eating at the ", hang = "hanging out at ",
    play = "playing games at ", watch = "watching a movie", walk = "walking to ", patrol = "patrolling ",
    monitor = "watching monitors in ", fix = "fixing something in ", ["break"] = "on break in ",
    lap = "walking laps on the ", date = "on a date at ", stage = "on stage at the ", home = "heading home" }
  local v = verbs[act] or (act .. " at ")
  if act == "watch" or act == "home" then return v end
  return v .. where
end
