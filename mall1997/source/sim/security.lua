-- Crime and security. Shoplifting is a systemic, risky path: concealment is
-- judged against the employees, customers and cameras that can actually see
-- you; evidence and witnesses decide what happens later. Consequences
-- escalate (warning -> detention + parents -> bans) and people talk.

Security = {}

local T = MallGen.TILE

function Security.guards(area)
  local out = {}
  for _, n in ipairs(NPCAI.inArea(area)) do if n.job == "sec" and not n.route then out[#out + 1] = n end end
  return out
end

function Security.banNPC(n, days, why)
  local day = Clock.day(W.t)
  n.bannedMall = day + days
  n.grounded = day + math.min(days, 5)
  W.stats.bans = W.stats.bans + 1
  Timeline.add("crime", NPCGen.name(n) .. " got banned from the mall for " .. days .. " days (" .. why .. ").", 1)
  for _, b in ipairs(n.plan or {}) do b.e = b.s end
end

-- ------------------------------------------------------------------ NPC theft
function Security.npcConsiderTheft(n, s)
  if n.tr.klepto < 0.25 then return false end
  local r = U.rng(W.seed, "theft", n.id, math.floor(W.t))
  if not r:chance(n.tr.klepto * 0.25) then return false end
  local staff = #Stores.presentStaff(s)
  local guards = #Security.guards(Areas.storeArea(s))
  local p = 0.12 + 0.13 * s.sec + 0.07 * staff + 0.25 * guards
  if s.suspectNPC and s.suspectNPC[n.id] then p = p + 0.2 end
  local items = Econ.rack(s, r:i(1, 3))
  local it = r:pick(items)
  if not it then return false end
  local day = Clock.day(W.t)
  if r:chance(math.min(0.85, p)) then
    W.stats.caught = W.stats.caught + 1
    s.bannedNPC = s.bannedNPC or {}
    s.bannedNPC[n.id] = day + 60
    n.rep = U.clamp(n.rep - 15, 0, 100)
    n.mood = U.clamp(n.mood - 20, 0, 100)
    n.tr.klepto = n.tr.klepto * 0.7
    Timeline.add("crime", "Security caught " .. NPCGen.name(n) .. " shoplifting a " .. it.n .. " at " .. s.name .. ".", 2)
    local seeds = { n.id }
    for _, e in ipairs(Stores.presentStaff(s)) do seeds[#seeds + 1] = e.id end
    Rumors.add("caught", n.id, n.first .. " " .. n.last .. " got caught stealing at " .. s.name, 7, seeds, { store = s.id })
    Memory.add(n, "caught", "got caught at " .. s.name)
    if n.parent and W.npcs[n.parent] then
      local par = W.npcs[n.parent]
      NPCGen.setRel(par, n, -10)
      n.grounded = day + 7
    end
    if n.job and type(n.job) == "number" and n.job == s.id then
      Security.fireNPC(n, s, "stealing")
    end
  else
    W.stats.thefts = W.stats.thefts + 1
    s.theftDay = (s.theftDay or 0) + it.v
    s.theftWeek = (s.theftWeek or 0) + 1
    s.theft = (s.theft or 0) + 1
    s.losses = (s.losses or 0) + it.v
    n.poss[#n.poss + 1] = { k = it.k, n = it.n, v = it.v, ref = it.ref, stolen = true }
    U.trim(n.poss, 12)
    W.mall.theftWeek = (W.mall.theftWeek or 0) + 1
    -- a customer may have noticed
    for _, o in ipairs(NPCAI.inArea(Areas.storeArea(s))) do
      if o ~= n and o.act ~= "work" and r:chance(0.15) then
        Rumors.add("shoplift", n.id, n.first .. " pocketed something at " .. s.name, 5, { o.id }, { store = s.id })
        break
      end
    end
    -- the store starts watching this person
    if r:chance(0.2) then s.suspectNPC = s.suspectNPC or {}; s.suspectNPC[n.id] = true end
  end
  return true
end

function Security.fireNPC(n, s, why)
  U.removeValue(s.emp, n.id)
  if s.mgr == n.id then s.mgr = nil end
  n.job, n.title = nil, nil
  W.stats.fires = W.stats.fires + 1
  Timeline.add("people", NPCGen.name(n) .. " got fired from " .. s.name .. " for " .. why .. ".", 2)
  Rumors.add("fired", n.id, n.first .. " got fired from " .. s.name, 6, { n.id }, { store = s.id })
end

-- weekly: the mall responds to theft waves by adding cameras / tightening up
function Security.weekly(day)
  local r = U.rng(W.seed, "secweek", day)
  local wave = W.mall.theftWeek or 0
  W.mall.theftHist = W.mall.theftHist or {}
  W.mall.theftHist[#W.mall.theftHist + 1] = wave
  U.trim(W.mall.theftHist, 12)
  if wave >= 5 then
    local worst, wv = nil, 0
    for _, s in ipairs(W.stores) do
      if s.open and (s.theft or 0) > wv then worst, wv = s, s.theft end
    end
    local added = 0
    for _, c in ipairs(W.cams) do if not c.on and added < 2 then c.on = true; added = added + 1 end end
    local x = r:i(MallGen.ANCHOR_W + 4, W.mall.w - MallGen.ANCHOR_W - 4)
    W.cams[#W.cams + 1] = { area = "c" .. r:i(1, 2), x = x, y = 5, r = 7, on = true, new = day }
    if worst and worst.sec < 3 then
      worst.sec = worst.sec + 1
      worst.theft = 0
      Areas.invalidate("s" .. worst.id)
      Timeline.add("crime", "After a rash of shoplifting, " .. worst.name .. " installed more security.", 2)
    else
      Timeline.add("crime", "Mall security installed new cameras after " .. wave .. " thefts this week.", 2)
    end
    Areas.invalidate("c1"); Areas.invalidate("c2")
  end
  W.mall.theftWeek = 0
  -- tapes get reviewed
  local keep = {}
  for _, ev in ipairs(W.p.evidence) do
    if not ev.reviewed then
      if r:chance(0.45) then
        ev.reviewed = true
        ev.known = true
        W.p.wanted = (W.p.wanted or 0) + 1
        local s = W.stores[ev.store]
        if s then Timeline.add("crime", "Security reviewed tape from " .. s.name .. ". Someone is in trouble.", 1) end
      end
      keep[#keep + 1] = ev
    elseif day - ev.day < 30 then keep[#keep + 1] = ev end
  end
  W.p.evidence = keep
end

-- ------------------------------------------------------------------ player
-- Can this NPC see tile position (px,py)? Cheap cone-free check with a
-- distance falloff; employees behind a counter are "facing the floor".
local function sees(n, px, py, r)
  local nx, ny = n.x, n.y
  local d = U.dist(nx, ny, px, py) / T
  if d > 9 then return 0 end
  local base = 0.9 - d * 0.08
  if n.act ~= "work" then base = base * 0.5 end
  return U.clamp(base, 0, 0.9)
end

-- Evaluate a concealment attempt right now; returns a risk report.
function Security.concealCheck(s, px, py)
  local r = U.rng(W.seed, "conceal", math.floor(W.t * 10))
  local area = Areas.storeArea(s)
  local rep = { store = s.id, seen = {}, cam = false, risk = 0, t = W.t }
  local skill = U.clamp(W.p.sneak or 0, 0, 30) / 100
  local heat = (s.suspicion or 0) / 100
  local total = 1
  for _, n in ipairs(NPCAI.inArea(area)) do
    if not n.route then
      local p = sees(n, px, py, r)
      if n.job == s.id then p = p * (0.5 + n.tr.honest * 0.6) + heat * 0.3
      elseif n.job == "sec" then p = p * 1.3
      else p = p * 0.35 end
      p = U.clamp(p - skill, 0, 0.95)
      total = total * (1 - p)
      if r:chance(p) then rep.seen[#rep.seen + 1] = n.id end
    end
  end
  -- cameras in the store
  local a = Areas.build(area)
  for _, o in ipairs(a.objs) do
    if o.cam then
      local d = U.dist(o.x * T, o.y * T, px, py) / T
      if d <= (o.r or 7) then
        local p = 0.35 + 0.1 * s.sec
        total = total * (1 - p)
        if r:chance(p) then rep.cam = true end
      end
    end
  end
  rep.risk = 1 - total
  return rep
end

-- remember what's in the bag that isn't paid for
function Security.conceal(s, it, rep)
  local p = W.p
  local copy = U.copy(it)
  copy.from = "stolen"; copy.store = s.id; copy.tagged = s.sec >= 3 and (U.hash(W.t, it.n) % 10 < 7)
  p.hot = p.hot or {}
  p.hot[#p.hot + 1] = copy
  p.heat = { store = s.id, seen = rep.seen, cam = rep.cam, t = W.t }
  s.suspicion = U.clamp((s.suspicion or 0) + (#rep.seen > 0 and 30 or 5), 0, 100)
  p.sneak = (p.sneak or 0) + 1
end

-- Player walks out the door of store s with unpaid goods. Returns nil if
-- they got away with it, or a confrontation descriptor.
function Security.exitCheck(s)
  local p = W.p
  if not p.hot or #p.hot == 0 then return nil end
  local r = U.rng(W.seed, "exit", math.floor(W.t * 10))
  local heat = p.heat or { seen = {} }
  local tagged = false
  for _, it in ipairs(p.hot) do if it.tagged then tagged = true end end
  if tagged then return { how = "alarm", store = s.id, staff = Stores.presentStaff(s)[1] } end
  for _, id in ipairs(heat.seen or {}) do
    local n = W.npcs[id]
    if n and n.job == s.id then
      -- low-wage apathy is real
      local cares = n.title == "manager" or n.tr.honest > 0.5 or r:chance(0.4)
      if cares then return { how = "staff", store = s.id, staff = n } end
    elseif n and n.job == "sec" then
      return { how = "guard", store = s.id, staff = n }
    elseif n then
      if n.tr.honest > 0.75 and r:chance(0.5) then
        return { how = "tattle", store = s.id, staff = Stores.presentStaff(s)[1], witness = n }
      end
    end
  end
  return nil
end

-- the player got away: goods move into the bag, word may get out
function Security.getaway(s)
  local p = W.p
  local heat = p.heat or { seen = {} }
  for _, it in ipairs(p.hot or {}) do
    it.tagged = nil
    Econ.give(it)
    p.stats.stolen = p.stats.stolen + 1
    s.theftDay = (s.theftDay or 0) + it.v
    s.theftWeek = (s.theftWeek or 0) + 1
    s.theft = (s.theft or 0) + 1
    W.stats.thefts = W.stats.thefts + 1
    W.mall.theftWeek = (W.mall.theftWeek or 0) + 1
  end
  if heat.cam then p.evidence[#p.evidence + 1] = { store = s.id, day = Clock.day(W.t) } end
  -- customers who saw you might talk
  local seeds = {}
  for _, id in ipairs(heat.seen or {}) do
    local n = W.npcs[id]
    if n and n.job ~= s.id then seeds[#seeds + 1] = id end
  end
  if #seeds > 0 then
    Rumors.add("shoplift", -1, p.name .. " pocketed something at " .. s.name, 6, seeds, { store = s.id })
  end
  Timeline.add("player", "You walked out of " .. s.name .. " with something you didn't pay for.", 1)
  p.hot = {}
  p.heat = nil
end

-- escalating consequences. how: "comply" | "caught" (after running) | "tape"
function Security.caughtPlayer(s, how)
  local p = W.p
  local day = Clock.day(W.t)
  p.record = (p.record or 0) + 1
  p.stats.caught = p.stats.caught + 1
  W.stats.caught = W.stats.caught + 1
  -- goods go back
  p.hot = {}; p.heat = nil
  local seeds = {}
  for _, n in ipairs(NPCAI.inArea(p.area)) do seeds[#seeds + 1] = n.id end
  for _, id in ipairs(Stores.staff(s)) do seeds[#seeds + 1] = id end
  local out = { lines = {}, parents = false, mallBan = 0, storeBan = 0 }
  local lvl = p.record
  if how == "caught" then lvl = lvl + 1 end
  if lvl <= 1 then
    out.storeBan = 14
    out.lines[#out.lines + 1] = "The manager takes the item back and writes your name on a clipboard."
    out.lines[#out.lines + 1] = "\"Don't come back for two weeks. I mean it.\""
  elseif lvl == 2 then
    out.storeBan = 60; out.mallBan = 3; out.parents = true
    out.lines[#out.lines + 1] = "Security walks you to the office. The chief calls your house."
    out.lines[#out.lines + 1] = "Your mom's voice on speakerphone is very, very calm."
  else
    out.storeBan = 365; out.mallBan = 30; out.parents = true
    out.lines[#out.lines + 1] = "They take a Polaroid of you for the wall behind the security desk."
    out.lines[#out.lines + 1] = "\"Thirty days. Next time it's the police.\""
  end
  p.bans[tostring(s.id)] = day + out.storeBan
  if out.mallBan > 0 then p.mallBan = day + out.mallBan end
  if out.parents then p.grounded = math.max(p.grounded or 0, day + 5) end
  s.suspicion = 100
  local kind = out.mallBan > 0 and "banned" or "caught"
  Rumors.add(kind, -1, p.name .. " got caught stealing at " .. s.name, 8, seeds, { store = s.id })
  Timeline.add("crime", p.name .. " got caught shoplifting at " .. s.name ..
    (out.mallBan > 0 and (" and was banned from the mall for " .. out.mallBan .. " days") or "") .. ".", 3)
  for _, id in ipairs(Stores.staff(s)) do
    local n = W.npcs[id]
    Memory.add(n, "caught", "caught " .. p.name .. " stealing", -1)
    n.p.t = n.p.t - 30; n.p.an = n.p.an + 20; n.p.met = true
    Social.clampP(n)
  end
  if p.job then
    if p.job.store == s.id or p.job.store == "sec" then Jobs.lose("fired for stealing")
    else p.job.perf = p.job.perf - 10 end
  end
  return out
end

-- trespassing in staff-only areas without a job there
function Security.trespass(area)
  local p = W.p
  if p.job then return nil end
  local watchers = {}
  for _, n in ipairs(NPCAI.inArea(area)) do
    if (n.job == "sec" or n.job == "maint" or type(n.job) == "number") and not n.route then watchers[#watchers + 1] = n end
  end
  if #watchers == 0 then return nil end
  local r = U.rng(W.seed, "tres", math.floor(W.t))
  local n = r:pick(watchers)
  if r:chance(0.55) then
    p.trespass = (p.trespass or 0) + 1
    return n
  end
end

function Security.banned(s)
  local b = W.p.bans[tostring(s.id)]
  return b and b > Clock.day(W.t)
end

function Security.mallBanned() return (W.p.mallBan or 0) > Clock.day(W.t) end
