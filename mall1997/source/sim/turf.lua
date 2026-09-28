-- The new kid's campaign. Five kids run the mall, each on their own turf,
-- each with a crew. You earn respect on a turf by being somebody there:
-- making friends, winning at the arcade, spreading dirt on whoever runs it.
-- With enough respect you can call them out; win the face-off and the turf
-- is yours. Hold all five and you run the mall. Nobody stays on top without
-- showing up, though: turf you ignore gets taken back.

Turf = {}

-- order is the suggested path; power is how tough the kid who runs it is
Turf.ZONES = {
  { key = "lot", name = "the Parking Lot", short = "PARKING LOT", spot = "lot", need = 50, pow = 1,
    cliques = { "skaters", "mall rats" } },
  { key = "arcade", name = "the Arcade", short = "ARCADE", spot = "arcade", need = 55, pow = 2,
    cliques = { "nerds", "mall rats", "band kids" } },
  { key = "c2", name = "the Upper Level", short = "UPPER LEVEL", spot = "c2", need = 60, pow = 2,
    cliques = { "alt kids", "goths", "band kids" } },
  { key = "fc", name = "the Food Court", short = "FOOD COURT", spot = "fc", need = 65, pow = 3,
    cliques = { "jocks", "preps" } },
  { key = "c1", name = "Center Court", short = "CENTER COURT", spot = "fountain", need = 70, pow = 4, final = true,
    cliques = { "preps", "jocks" } },
}
Turf.BY = {}
for _, z in ipairs(Turf.ZONES) do Turf.BY[z.key] = z end

local MOVES = { "roast", "flex", "crew" }
Turf.MOVES = MOVES

-- harmless, deeply embarrassing, and exactly what a crew member would leak
local DIRT = {
  "still sleeps with a Lion King nightlight", "cried at the end of Air Bud. In the theater. Loudly",
  "failed the driver's test three times, once in the parking lot", "has a Tamagotchi named Mr. Snuggles and has never let it die",
  "was in the church handbell choir until March", "does the frosted tips at home with lemon juice",
  "got dumped over the phone by a seventh grader", "has a signed photo of Steve Urkel above their bed",
  "wears their older cousin's hand-me-down Hypercolor shirts", "still has a Care Bears sleeping bag",
  "asked the mall Santa for a pony last year. As a joke. Supposedly",
  "called the Psychic Friends Network and ran up a $90 phone bill",
}

local function day() return Clock.day(W.t) end

function Turf.zone(key) return W.turf and W.turf.z[key] end

-- which turf an area belongs to (stores count toward their concourse)
function Turf.zoneOf(area)
  if not area or not W.turf then return nil end
  if area == "lot" or area == "fc" or area == "c1" or area == "c2" then return area end
  if area == "s" .. W.mall.arcade then return "arcade" end
  local id = tonumber(area:match("^s(%d+)$") or "")
  local s = id and W.stores[id]
  if s then
    if s.row == "fc" then return "fc" end
    return s.floor == 2 and "c2" or "c1"
  end
  return nil
end

function Turf.areaOf(key)
  if key == "arcade" then return "s" .. W.mall.arcade end
  return key
end

function Turf.held()
  local n = 0
  if not W.turf then return 0 end
  for _, z in ipairs(Turf.ZONES) do if W.turf.z[z.key].owner == "you" then n = n + 1 end end
  return n
end

-- ------------------------------------------------------------------ setup
local function score(n)
  return n.rep + n.tr.social * 30 + n.tr.temper * 10 + (U.hash(W.seed, "boss", n.id) % 10)
end

local function candidates(used, cliques)
  local out = {}
  local friends = {}
  for _, id in ipairs(W.p.friends or {}) do friends[id] = true end
  for _, n in ipairs(W.npcs) do
    if n.status == "active" and n.age >= 15 and n.age <= 18 and not n.job and not used[n.id] and not friends[n.id]
      and n.role ~= "family" and (not cliques or U.contains(cliques, n.clique)) then
      out[#out + 1] = n
    end
  end
  table.sort(out, function(a, b) local sa, sb = score(a), score(b) if sa ~= sb then return sa > sb end return a.id < b.id end)
  return out
end

-- make n the kid who runs zone z (used at setup and when a boss moves away)
local function crown(zdef, n, r)
  local z = W.turf.z[zdef.key]
  z.boss = n.id
  n.turfBoss = zdef.key
  n.crew = nil
  n.rep = math.max(n.rep, 55 + zdef.pow * 8)
  if not n.turfDirt then n.turfDirt = DIRT[r:i(1, #DIRT)] end
  z.dirt = false
  -- a crew: kids who already like them, then clique-mates
  z.crew = {}
  local pool = {}
  for _, o in ipairs(W.npcs) do
    if o.status == "active" and o.age < 19 and o.id ~= n.id and not o.turfBoss and not o.crew and o.role ~= "family"
      and not U.contains(W.p.friends or {}, o.id) then
      local rel = n.rel[o.id]
      local w = (rel and rel.f or 0) + (o.clique == n.clique and 40 or 0)
      if w > 25 then pool[#pool + 1] = { o = o, w = w + (U.hash(W.seed, "crew", o.id) % 20) } end
    end
  end
  table.sort(pool, function(a, b) if a.w ~= b.w then return a.w > b.w end return a.o.id < b.o.id end)
  for i = 1, math.min(4, #pool) do
    local o = pool[i].o
    o.crew = zdef.key
    z.crew[#z.crew + 1] = o.id
    NPCGen.setRel(o, n, 20, nil); NPCGen.setRel(n, o, 20, nil)
  end
end

function Turf.setup()
  local r = U.rng(W.seed, "turf")
  W.turf = { z = {}, v = 1 }
  local used = {}
  for _, zdef in ipairs(Turf.ZONES) do
    W.turf.z[zdef.key] = { resp = 0, owner = "them", hold = 0, visit = -99, cool = -1, crew = {} }
    local list = candidates(used, zdef.cliques)
    if #list == 0 then list = candidates(used, nil) end
    local n = list[1]
    if n then
      used[n.id] = true
      crown(zdef, n, r)
      local z = W.turf.z[zdef.key]
      -- everyone has a weak spot and a strong suit
      local w = r:i(1, 3)
      z.weak = MOVES[w]
      z.strong = MOVES[(w % 3) + 1]
    else
      W.turf.z[zdef.key].owner = "you"
      W.turf.z[zdef.key].hold = 60
    end
  end
end

-- worlds from before the campaign get one the first time they load
function Turf.ensure()
  if not W.turf then Turf.setup() end
end

-- ------------------------------------------------------------------ respect
function Turf.need(zdef)
  return zdef.need
end

-- add respect on turf `key` (or hold, if it's already yours)
function Turf.gain(key, amt, why)
  local z = Turf.zone(key)
  if not z or amt == 0 then return end
  local zdef = Turf.BY[key]
  if z.owner == "you" then
    z.hold = U.clamp(z.hold + amt, 0, 100)
    return
  end
  local before = z.resp
  z.resp = U.clamp(z.resp + amt, 0, 100)
  if amt > 0 and Toast then Toast.show("+" .. amt .. " RESPECT: " .. zdef.short, 60) end
  local need = Turf.need(zdef)
  if before < need and z.resp >= need then
    local boss = W.npcs[z.boss]
    local c = W.p.cousin and W.npcs[W.p.cousin]
    if boss then
      Pager.send(c and c.first:upper() or "???", "PPL IN " .. zdef.short .. " KNOW WHO U ARE NOW. GO CALL OUT " .. boss.first:upper())
    end
  end
end

-- a conversation just happened with n (friendship moved by df)
function Turf.onTalk(n, id, df, out)
  if not W.turf or n.age >= 20 then return end
  local key = Turf.zoneOf(W.p.area)
  local z = key and Turf.zone(key)
  if not z then return end
  local d = day()
  -- crews leak their boss's secrets to people they like
  if id == "gossip" and n.crew and n.p.f >= 20 then
    local cz = Turf.zone(n.crew)
    local boss = cz and W.npcs[cz.boss]
    if boss and cz.owner == "them" and not cz.dirt and boss.turfDirt then
      cz.dirt = true
      W.p.secrets = W.p.secrets or {}
      W.p.secrets[#W.p.secrets + 1] = { npc = boss.id, txt = boss.turfDirt, turf = true }
      out.lines[#out.lines + 1] = "...Okay, you didn't hear this from me. " .. boss.first .. " " .. boss.turfDirt .. "."
      out.lines[#out.lines + 1] = "(That's the kind of thing that wins a face-off.)"
    end
  end
  if df <= 0 then return end
  if (n.p.turfDay or -1) == d then return end
  n.p.turfDay = d
  local amt = 2
  if n.crew == key then amt = n.p.f >= 40 and 5 or 3 end
  if n.turfBoss then amt = 0 end
  Turf.gain(key, amt, "talk")
end

-- the player passed a rumor or secret along to n
function Turf.onTell(n, entry)
  if not W.turf or n.age >= 20 then return end
  local key = Turf.zoneOf(W.p.area)
  local z = key and Turf.zone(key)
  if not z or z.owner ~= "them" then return end
  local about = entry.rumor and entry.rumor.about or (entry.secret and entry.secret.npc)
  if about ~= z.boss or n.id == z.boss then return end
  local boss = W.npcs[z.boss]
  boss.rep = U.clamp(boss.rep - 3, 0, 100)
  Turf.gain(key, entry.secret and 8 or 5, "dirt")
end

-- ------------------------------------------------------------------ moves
-- how strong each face-off move is for the player right now (1..~15)
function Turf.power(move, boss)
  local p = W.p
  if move == "roast" then
    local v = 2 + p.conf / 25
    local rumors = 0
    for _, rm in ipairs(W.rumors) do if rm.about == boss.id and p.knownRumors[rm.id] then rumors = rumors + 1 end end
    v = v + math.min(3, rumors) * 1.5
    for _, sc in ipairs(p.secrets or {}) do if sc.npc == boss.id then v = v + 5 end end
    return math.floor(math.min(16, v))
  elseif move == "flex" then
    local vals = {}
    for _, it in ipairs(p.inv) do if it.k ~= "gear" and it.k ~= "key" and not it.due then vals[#vals + 1] = it.v or 0 end end
    table.sort(vals, function(a, b) return a > b end)
    local sum = (vals[1] or 0) + (vals[2] or 0) + (vals[3] or 0)
    local v = 1 + math.min(7, sum / 2000) + math.min(4, p.fame / 8) + (p.flags.tips and 1 or 0) + math.min(2, p.money / 10000)
      + (p.rep or 20) / 25
    return math.floor(math.min(16, v))
  else
    -- people here who like you, and how much respect you've built on this turf
    local z = Turf.zone(boss.turfBoss)
    local v = 1 + (z and z.resp or 0) / 20
    for _, n in ipairs(NPCAI.inArea(p.area)) do
      if n.id ~= boss.id and n.age < 20 and n.p.f >= 25 and n.id ~= p.companion then v = v + 1.5 end
    end
    if p.companion and W.npcs[p.companion] then v = v + 3 end
    v = v + Turf.held()
    return math.floor(math.min(16, v))
  end
end

function Turf.bossPower(key)
  return 3 + Turf.BY[key].pow * 2
end

-- one face-off round: returns your score, theirs, their move, and the
-- multiplier your move got (1.5 on their weak spot, 0.6 on their strong suit)
function Turf.round(boss, move, rng)
  local z = Turf.zone(boss.turfBoss)
  local mult = (move == z.weak) and 1.5 or (move == z.strong) and 0.6 or 1
  local mine = Turf.power(move, boss) * mult + rng:i(0, 4)
  local theirs = Turf.bossPower(boss.turfBoss) + rng:i(0, 5)
  return mine, theirs, MOVES[rng:i(1, 3)], mult
end

-- can the player call out n right now? returns ok, reason
function Turf.canCallOut(n)
  local key = n.turfBoss
  local z = key and Turf.zone(key)
  if not z or z.boss ~= n.id or z.owner ~= "them" then return false end
  local zdef = Turf.BY[key]
  if zdef.final and Turf.held() < 3 then
    return false, "\"Center Court? You don't even run three turfs. Come back when you're somebody.\" (Take 3 other turfs first.)"
  end
  if z.cool > day() then return false, "\"Didn't I just embarrass you? Come back in a couple days.\"" end
  if z.resp < Turf.need(zdef) then
    return false, "\"Who even are you?\" (Respect in " .. zdef.name .. ": " .. z.resp .. "/" .. Turf.need(zdef) .. ")"
  end
  if Turf.zoneOf(W.p.area) ~= key then return false, "\"Not here. Come find me in " .. zdef.name .. ".\"" end
  return true
end

-- ------------------------------------------------------------------ results
function Turf.win(n)
  local p = W.p
  local key = n.turfBoss
  local z = Turf.zone(key)
  local zdef = Turf.BY[key]
  z.owner = "you"
  z.hold = 70
  z.visit = day()
  z.won = (z.won or 0) + 1
  n.p.fe = n.p.fe + 25; n.p.f = n.p.f - 10; n.p.met = true
  n.mood = U.clamp(n.mood - 20, 0, 100)
  n.rep = U.clamp(n.rep - 15, 0, 100)
  Social.clampP(n)
  Memory.add(n, "lostturf", "lost " .. zdef.name .. " to " .. p.name, -1)
  local seeds = {}
  for _, id in ipairs(z.crew) do
    local c = W.npcs[id]
    if c and c.status == "active" then c.p.f = c.p.f + 12; c.p.t = c.p.t + 5; c.p.met = true; Social.clampP(c); seeds[#seeds + 1] = id end
  end
  for _, o in ipairs(NPCAI.inArea(p.area)) do seeds[#seeds + 1] = o.id end
  Rumors.add("turf", -1, p.name .. " took " .. zdef.name .. " from " .. NPCGen.name(n), 8, seeds)
  Timeline.add("player", p.name .. " called out " .. NPCGen.name(n) .. " and took " .. zdef.name .. ".", 3)
  p.fame = p.fame + 8
  p.conf = U.clamp(p.conf + 15, 0, 100)
  if Turf.held() == #Turf.ZONES and not p.flags.king then
    p.flags.king = day()
    Timeline.add("player", p.name .. " runs " .. W.mall.name .. " now. Every turf. Nobody saw it coming.", 3)
    p.fame = p.fame + 20
    return true
  end
end

function Turf.lose(n)
  local p = W.p
  local key = n.turfBoss
  local z = Turf.zone(key)
  local zdef = Turf.BY[key]
  z.resp = math.floor(z.resp * 0.6)
  z.cool = day() + 2
  p.conf = U.clamp(p.conf - 15, 0, 100)
  n.rep = U.clamp(n.rep + 5, 0, 100)
  local seeds = {}
  for _, id in ipairs(z.crew) do seeds[#seeds + 1] = id end
  for _, o in ipairs(NPCAI.inArea(p.area)) do seeds[#seeds + 1] = o.id end
  Rumors.add("turfloss", -1, n.first .. " humiliated " .. p.name .. " in " .. zdef.name, 7, seeds)
  Timeline.add("player", p.name .. " tried to call out " .. NPCGen.name(n) .. " in " .. zdef.name .. " and got destroyed.", 2)
end

-- ------------------------------------------------------------------ daily
local TAUNTS = {
  "NEW KID NEEDS 2 STAY OUT OF %s", "SAW UR OUTFIT. YIKES", "%s IS MINE. GO BACK WHERE U CAME FROM",
  "EVERYBODY IS LAUGHING AT U", "NICE TRY LAST NIGHT. NOT", "U R NOT WELCOME IN %s",
}
local DISSES = {
  "the new kid is a narc", "the new kid still wears light-up sneakers", "the new kid got kicked out of their old school",
  "the new kid's mom still cuts their hair", "the new kid tried to sit at their table and got told to move",
}

local function successor(zdef, old, r)
  local z = W.turf.z[zdef.key]
  local pick
  for _, id in ipairs(z.crew) do
    local c = W.npcs[id]
    if c and c.status == "active" and not c.job and (not pick or c.rep > pick.rep) then pick = c end
  end
  if not pick then
    local used = {}
    for _, zz in pairs(W.turf.z) do if zz.boss then used[zz.boss] = true end end
    pick = candidates(used, zdef.cliques)[1] or candidates(used, nil)[1]
  end
  if old then old.turfBoss = nil end
  for _, id in ipairs(z.crew) do local c = W.npcs[id]; if c then c.crew = nil end end
  if not pick then return end
  crown(zdef, pick, r)
  return pick
end

function Turf.daily(d)
  if not W.turf then return end
  local p = W.p
  local r = U.rng(W.seed, "turfday", d)
  local c = p.cousin and W.npcs[p.cousin]
  local pawn = Pawn.shop()
  if c and pawn and p.stats.stolen > 0 and not p.flags.pawnTip then
    p.flags.pawnTip = d
    Pager.send(c.first:upper(), pawn.name:upper():sub(1, 18) .. " BUYS ANYTHING. NO QUESTIONS")
  end
  local taunted = false
  for _, zdef in ipairs(Turf.ZONES) do
    local z = W.turf.z[zdef.key]
    local boss = z.boss and W.npcs[z.boss]
    -- the kid who ran it moved away or got a job and stopped showing up
    if not boss or boss.status ~= "active" then
      local nb = successor(zdef, boss, r)
      if nb and z.owner == "them" then
        z.resp = math.floor(z.resp * 0.7)
        Timeline.add("people", NPCGen.name(nb) .. " runs " .. zdef.name .. " now.", 2)
      end
      boss = nb
    end
    if z.owner == "them" then
      if z.resp > 0 and d - z.visit > 1 then z.resp = math.max(0, z.resp - 2) end
      if boss and not taunted and z.resp >= 20 and r:chance(0.22) then
        taunted = true
        local zone = zdef.short
        Pager.send(boss.first:upper(), string.format(r:pick(TAUNTS), zone))
        local seeds = { boss.id }
        for _, id in ipairs(z.crew) do seeds[#seeds + 1] = id end
        Rumors.add("diss", -1, boss.first .. " says " .. r:pick(DISSES):gsub("the new kid", p.name), 5, seeds)
        z.resp = math.max(0, z.resp - 3)
      end
    else
      if d - z.visit > 3 then z.hold = math.max(0, z.hold - 3) end
      if z.hold <= 25 and boss and boss.status == "active" then
        z.owner = "them"
        z.resp = 35
        z.cool = d + 1
        boss.turfBoss = zdef.key
        boss.rep = U.clamp(boss.rep + 10, 0, 100)
        Pager.send(boss.first:upper(), zdef.short .. " IS MINE AGAIN. MISS ME?")
        Timeline.add("people", NPCGen.name(boss) .. " took " .. zdef.name .. " back from " .. p.name .. ".", 2)
        if p.flags.king then p.flags.king = nil end
      end
    end
  end
end

-- the player walked into an area: remember the visit, say whose turf it is
function Turf.enter(area)
  local key = Turf.zoneOf(area)
  local z = key and Turf.zone(key)
  if not z then return nil end
  local zdef = Turf.BY[key]
  local first = z.visit ~= day()
  z.visit = day()
  if area ~= Turf.areaOf(key) or not first then return nil end
  local boss = W.npcs[z.boss]
  if z.owner == "you" then return "YOUR TURF: " .. zdef.short end
  if not boss then return nil end
  return boss.first:upper() .. "'S TURF  (respect " .. z.resp .. "/" .. Turf.need(zdef) .. ")"
end

-- getting caught costs you standing everywhere you hold
function Turf.onCaught()
  if not W.turf then return end
  for _, z in pairs(W.turf.z) do
    if z.owner == "you" then z.hold = math.max(0, z.hold - 15) else z.resp = math.max(0, z.resp - 5) end
  end
end

-- ------------------------------------------------------------------ standing
local RANKS = {
  { 0, "New Kid" }, { 28, "Some Kid" }, { 38, "Regular" }, { 48, "Known Face" },
  { 58, "Somebody" }, { 72, "Big Deal" }, { 86, "Mall Royalty" },
}

function Turf.standing()
  local p = W.p
  local held = Turf.held()
  if W.turf and held == #Turf.ZONES then return "Runs the Mall", 100 end
  local v = math.floor((p.rep or 20) * 0.6 + held * 12 + math.min(15, (p.fame or 0) / 2))
  local label = RANKS[1][2]
  for _, rk in ipairs(RANKS) do if v >= rk[1] then label = rk[2] end end
  return label, v
end

-- one line: what to do next
function Turf.goal()
  if not W.turf then return nil end
  local held = Turf.held()
  if held == #Turf.ZONES then return "You run the mall. Show up, or they'll take it back." end
  local best
  for _, zdef in ipairs(Turf.ZONES) do
    local z = W.turf.z[zdef.key]
    if z.owner == "them" and not (zdef.final and held < 3) then
      if not best or z.resp / zdef.need > W.turf.z[best.key].resp / best.need then best = zdef end
    end
  end
  if not best then return nil end
  local z = W.turf.z[best.key]
  local boss = W.npcs[z.boss]
  if z.resp >= best.need then return "Call out " .. boss.first .. " in " .. best.name .. "." end
  return "Earn respect in " .. best.name .. " (" .. z.resp .. "/" .. best.need .. "), then call out " .. boss.first .. "."
end
