-- NPC population generation. Several hundred persistent people, each with a
-- stable integer id (their index in W.npcs).

NPCGen = {}

local function newLook(r, age, role)
  local lk = {
    hair = r:i(0, 7), hc = r:i(0, 2), shirt = r:i(0, 5), pants = r:i(0, 2),
    skin = r:i(0, 2), acc = 0, build = r:i(0, 2),
  }
  if r:chance(0.18) then lk.acc = 1 end                     -- glasses
  if age < 20 and r:chance(0.25) then lk.acc = r:pick({ 2, 3, 4 }) end
  if age > 60 then lk.hc = 3; if r:chance(0.4) then lk.acc = 1 end end
  if role == "security" then lk.uniform = "sec" end
  if role == "maint" then lk.uniform = "maint" end
  return lk
end

local function traits(r)
  return {
    klepto = r:chance(0.07) and r:range(0.3, 0.9) or r:range(0, 0.08),
    social = r:range(0.1, 1), gossip = r:range(0, 1), honest = r:range(0.2, 1),
    ambition = r:range(0, 1), temper = r:range(0, 1), romance = r:range(0, 1),
  }
end

function NPCGen.new(W, r, role, age, opts)
  opts = opts or {}
  local sex = opts.sex or (r:chance(0.5) and "f" or "m")
  local first
  if age < 22 then first = r:pick(Names.teenFirst)
  elseif age < 62 then first = r:pick(Names.adultFirst)
  else first = r:pick(Names.oldFirst) end
  local id = #W.npcs + 1
  local n = {
    id = id, first = first, last = opts.last or r:pick(Names.last), age = age, sex = sex, role = role,
    home = r:pick(Names.neighborhoods), money = r:i(5, 60) * 100, mood = r:i(40, 80),
    rep = r:i(20, 60), mem = {}, poss = {}, rel = {}, wants = {}, secrets = {},
    tr = traits(r), look = newLook(r, age, role), loc = "home", x = 0, y = 0,
    p = { f = 0, t = 0, a = 0, fe = 0, an = 0, met = false, last = -99, talks = 0 },
    status = "active", seed = r:next(),
  }
  if age < 19 then n.school = r:pick(Names.schools); n.clique = r:pick(Names.cliques) end
  if age >= 26 and r:chance(0.6) then n.married = true end
  local tastes = n.clique and Names.cliqueTaste[n.clique] or Names.genres
  n.taste = r:pick(tastes)
  if age >= 30 then n.taste = r:pick({ "country", "pop", "r&b", "jam band", "swing", "alt-rock" }) end
  if age >= 25 then n.money = r:i(20, 300) * 100 end
  W.npcs[id] = n
  return n
end

function NPCGen.name(n) return n.first .. " " .. n.last end

local function setRel(a, b, f, at)
  a.rel[b.id] = a.rel[b.id] or { f = 0, a = 0 }
  a.rel[b.id].f = U.clamp(a.rel[b.id].f + f, -100, 100)
  if at then a.rel[b.id].a = U.clamp(a.rel[b.id].a + at, 0, 100) end
end
NPCGen.setRel = setRel
local function mutual(a, b, f) setRel(a, b, f); setRel(b, a, f) end

-- romance is only ever allowed between two adults or two minors of similar age
function NPCGen.romanceOK(a, b)
  if a.id == b.id then return false end
  if a.married or b.married then return false end
  if a.age < 18 or b.age < 18 then
    return a.age < 18 and b.age < 18 and math.abs(a.age - b.age) <= 2
  end
  return math.abs(a.age - b.age) <= 15
end

local SECRETS = {
  employee = {
    "has been sneaking {store}'s damaged stock home", "is interviewing at another store",
    "can't stand {mgr}", "naps in the back room on doubles", "is two months behind on rent",
    "is saving up to move to Seattle", "takes long breaks on the roof stairs",
  },
  manager = {
    "knows {store} is on thin ice with corporate", "fudges the inventory counts",
    "is applying for a job at the new outlet mall", "cries in the stockroom sometimes",
  },
  teen = {
    "is failing algebra", "skipped school twice this week", "writes poetry in a composition book",
    "has a fake ID that says they're 23", "parents are getting divorced", "is terrified of escalators",
    "pocketed a keychain from {store} once", "still sleeps with a stuffed animal",
    "got into a summer program in New York and hasn't told anyone",
  },
  security = { "sleeps in the monitor room on night shift", "got let go from the police academy",
    "knows the roof hatch is never really locked" },
  maint = { "keeps a cot in the maintenance tunnels", "has keys to rooms that aren't on any plan",
    "says the fountain was built over something" },
  walker = { "was at the mall's grand opening in 1972", "knows why that one storefront was never rented",
    "sold the land this mall is built on" },
  adult = { "is secretly shopping for an engagement ring", "has maxed out three store credit cards",
    "is hiding a gift for their spouse at the service desk" },
}

local function addSecret(r, n, pool, vars)
  local t = r:pick(pool)
  n.secrets[#n.secrets + 1] = { txt = U.fmt(t, vars), known = false }
end

local function assignWants(W, r, n)
  n.wants = {}
  local M = W.music
  -- an album that fits their taste
  local cands = {}
  for _, a in ipairs(M.albums) do
    if M.bands[a.band].genre == n.taste and not a.releaseDay then cands[#cands + 1] = a.id end
  end
  if #cands > 0 and r:chance(0.6) then n.wants[#n.wants + 1] = { k = "album", ref = r:pick(cands) } end
  if n.role == "teen" and not n.job and r:chance(0.4) then n.wants[#n.wants + 1] = { k = "job" } end
  if n.age < 20 and r:chance(0.35) then n.wants[#n.wants + 1] = { k = "arcade", ref = r:pick(Content.ARCADE_GAMES).key } end
  if r:chance(0.3) then n.wants[#n.wants + 1] = { k = "movie" } end
  if n.age < 20 and r:chance(0.3) then n.wants[#n.wants + 1] = { k = "item", ref = r:pick(Names.toyItems)[1] } end
  if n.job and r:chance(0.25) then n.wants[#n.wants + 1] = { k = "raise" } end
  if n.age < 22 and r:chance(0.12) then n.wants[#n.wants + 1] = { k = "band" } end
  if r:chance(0.2) then n.wants[#n.wants + 1] = { k = "clothes", ref = r:pick(Names.clothes)[1] } end
end
NPCGen.assignWants = assignWants

local function hire(W, n, s, title)
  n.job = s.id; n.title = title
  n.wage = s.wage + (title == "manager" and 400 or 0)
  if title == "manager" then s.mgr = n.id else s.emp[#s.emp + 1] = n.id end
end
NPCGen.hire = hire

function NPCGen.genPopulation(W, r)
  W.npcs = {}
  local teens = {}
  -- teens first so some can be hired as clerks
  for _ = 1, r:i(95, 115) do
    local n = NPCGen.new(W, r, "teen", r:i(14, 19))
    teens[#teens + 1] = n
  end
  r:shuffle(teens)
  local teenPool = U.filter(teens, function(t) return t.age >= 16 end)
  local ti = 1
  -- staff every store
  for _, s in ipairs(W.stores) do
    local T = MallGen.TYPES[s.type]
    local mgrAge = r:i(23, 58)
    local m = NPCGen.new(W, r, "manager", mgrAge)
    hire(W, m, s, "manager")
    local staff = math.max(0, T.staff - 1 + r:i(-1, 1))
    if s.type == "department" then staff = r:i(5, 7) end
    if s.type == "cinema" then staff = 5 end
    for _ = 1, staff do
      local e
      local teenish = (s.type == "food" or s.type == "cinema" or s.type == "arcade" or s.type == "music"
        or s.type == "video" or s.type == "clothing") and r:chance(0.55)
      if teenish and teenPool[ti] then
        e = teenPool[ti]; ti = ti + 1
        e.role = "employee"
      else
        e = NPCGen.new(W, r, "employee", r:i(17, 45))
      end
      hire(W, e, s, "clerk")
    end
  end
  -- coworker relationships
  for _, s in ipairs(W.stores) do
    local crew = { s.mgr }
    for _, e in ipairs(s.emp) do crew[#crew + 1] = e end
    for i = 1, #crew do
      for j = i + 1, #crew do
        local a, b = W.npcs[crew[i]], W.npcs[crew[j]]
        local f = r:i(-10, 45)
        if r:chance(0.1) then f = r:i(-60, -25) end
        mutual(a, b, f)
      end
    end
  end
  -- mall operations staff
  W.mall.security = {}
  for i = 1, r:i(7, 9) do
    local n = NPCGen.new(W, r, "security", r:i(21, 62))
    n.job = "sec"; n.title = i == 1 and "chief" or "officer"; n.wage = 750
    W.mall.security[#W.mall.security + 1] = n.id
  end
  W.mall.maint = {}
  for i = 1, 5 do
    local n = NPCGen.new(W, r, "maint", r:i(26, 66))
    n.job = "maint"; n.title = i == 1 and "night janitor" or "maintenance"; n.wage = 700
    W.mall.maint[#W.mall.maint + 1] = n.id
    if i == 1 then W.mall.janitor = n.id; n.age = 64; n.look.hc = 3; n.lore = true end
  end
  local gm = NPCGen.new(W, r, "mgmt", r:i(40, 60))
  gm.job = "mgmt"; gm.title = "general manager"; gm.wage = 2400
  W.mall.gm = gm.id
  local agm = NPCGen.new(W, r, "mgmt", r:i(28, 45))
  agm.job = "mgmt"; agm.title = "marketing director"; agm.wage = 1600
  local leasing = NPCGen.new(W, r, "mgmt", r:i(30, 55))
  leasing.job = "mgmt"; leasing.title = "leasing agent"; leasing.wage = 1500
  W.mall.mgmt = { gm.id, agm.id, leasing.id }
  for _, a in ipairs(W.mall.security) do for _, b in ipairs(W.mall.security) do
    if a < b then mutual(W.npcs[a], W.npcs[b], r:i(0, 40)) end end end
  -- shoppers, parents, walkers
  for _ = 1, r:i(40, 50) do NPCGen.new(W, r, "shopper", r:i(22, 58)) end
  local parents = {}
  for _ = 1, r:i(28, 36) do parents[#parents + 1] = NPCGen.new(W, r, "parent", r:i(34, 52)) end
  for _ = 1, r:i(14, 18) do NPCGen.new(W, r, "walker", r:i(63, 84)) end
  -- families: parents linked to teens (shared surname and home)
  local allTeens = U.filter(W.npcs, function(n) return n.age < 19 end)
  r:shuffle(allTeens)
  for i, p in ipairs(parents) do
    local kid = allTeens[i]
    if kid then
      p.last = kid.last; p.home = kid.home; p.kid = kid.id; kid.parent = p.id
      mutual(p, kid, r:i(20, 70))
    end
  end
  -- walkers know each other
  local walkers = U.filter(W.npcs, function(n) return n.role == "walker" end)
  for i = 1, #walkers do for j = i + 1, #walkers do
    if r:chance(0.5) then mutual(walkers[i], walkers[j], r:i(10, 60)) end end end
  -- teen social graph by clique
  allTeens = U.filter(W.npcs, function(n) return n.age < 19 end)
  for i = 1, #allTeens do
    local a = allTeens[i]
    for j = i + 1, #allTeens do
      local b = allTeens[j]
      if a.clique == b.clique and r:chance(0.35) then mutual(a, b, r:i(15, 70))
      elseif a.school == b.school and r:chance(0.04) then mutual(a, b, r:i(-50, 30)) end
    end
  end
  -- crushes and couples
  for _, a in ipairs(W.npcs) do
    if r:chance(a.age < 19 and 0.35 or 0.12) then
      for _ = 1, 12 do
        local b = W.npcs[r:i(1, #W.npcs)]
        if NPCGen.romanceOK(a, b) and b.sex ~= a.sex or (NPCGen.romanceOK(a, b) and r:chance(0.1)) then
          a.crush = b.id; setRel(a, b, 10, r:i(40, 80)); break
        end
      end
    end
  end
  for _, a in ipairs(W.npcs) do
    local b = a.crush and W.npcs[a.crush]
    if b and not a.partner and not b.partner and r:chance(0.45) and NPCGen.romanceOK(a, b) then
      a.partner = b.id; b.partner = a.id; b.crush = a.id
      a.since = -r:i(5, 700); b.since = a.since
      setRel(b, a, 20, r:i(40, 80)); setRel(a, b, 20, 10)
    end
  end
  -- secrets and wants
  for _, n in ipairs(W.npcs) do
    local s = n.job and type(n.job) == "number" and W.stores[n.job]
    local vars = {
      store = s and s.name or W.stores[r:i(1, #W.stores)].name,
      mgr = s and s.mgr and W.npcs[s.mgr] and W.npcs[s.mgr].first or "the boss",
    }
    local pool = SECRETS[n.role] or SECRETS.adult
    if n.role == "employee" and n.age < 19 and r:chance(0.4) then pool = SECRETS.teen end
    local k = r:chance(0.7) and 1 or 2
    for _ = 1, k do addSecret(r, n, pool, vars) end
    if n.crush and r:chance(0.6) then
      n.secrets[#n.secrets + 1] = { txt = "has a crush on " .. NPCGen.name(W.npcs[n.crush]), known = false, crush = n.crush }
    end
    assignWants(W, r, n)
  end
  -- mall-lore secrets hang off specific people
  local jan = W.npcs[W.mall.janitor]
  jan.secrets = { { txt = "has been maintaining something under the mall for twenty years", known = false, lore = "model" } }
  -- the player's family and starting friends
  local fam = NPCGen.new(W, r, "family", r:i(38, 48), { sex = "f" })
  fam.first = r:pick({ "Linda", "Karen", "Debbie", "Donna", "Cheryl" })
  fam.title = "your mom"; fam.loc = "home"
  W.p.mom = fam.id
  local friends = U.filter(W.npcs, function(n) return n.age >= 15 and n.age <= 17 and n.role ~= "family" end)
  r:shuffle(friends)
  W.p.friends = {}
  for i = 1, 3 do
    local f = friends[i]
    f.p.f = r:i(35, 60); f.p.t = r:i(25, 50); f.p.met = true
    W.p.friends[#W.p.friends + 1] = f.id
    if i == 1 then f.p.f = 70; f.p.t = 60; f.best = true end
  end
  for i = 1, 3 do for j = i + 1, 3 do mutual(friends[i], friends[j], r:i(30, 60)) end end
  -- a handful of people who have heard of you
  for _ = 1, 12 do
    local n = W.npcs[r:i(1, #W.npcs)]
    if n.age < 20 then n.p.met = true; n.p.f = n.p.f + r:i(-10, 20) end
  end
end

-- People who moved away stay in W.npcs (ids are stable and the timeline,
-- rumors and high-score boards still name them), but after a month they
-- keep only who they were: their belongings, wants, secrets and ties to
-- everyone else are dropped so the save doesn't grow with every departure.
function NPCGen.compactGone(day)
  local newly = false
  for _, n in ipairs(W.npcs) do
    if n.status == "gone" and not n.compact then
      n.goneDay = n.goneDay or day
      if day - n.goneDay >= 30 then
        n.compact = true
        newly = true
        n.poss, n.wants, n.secrets, n.rel = {}, {}, {}, {}
        local keep = {}
        for i = math.max(1, #n.mem - 2), #n.mem do keep[#keep + 1] = n.mem[i] end
        n.mem = keep
        n.crush, n.partner, n.dateToday, n.gig = nil, nil, nil, nil
      end
    end
  end
  if not newly then return end
  for _, n in ipairs(W.npcs) do
    if n.status == "active" then
      for _, id in ipairs(U.keys(n.rel)) do
        local o = W.npcs[id]
        if o and o.compact then n.rel[id] = nil end
      end
    end
  end
end
