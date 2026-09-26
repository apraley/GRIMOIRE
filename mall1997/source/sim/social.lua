-- Social simulation: NPC-NPC interactions when co-located, friendships,
-- feuds, crushes, dating and breakups, rumor spread, reactions to news
-- about the player, and NPCs reaching out to the player by pager.

Social = {}

local function rel(a, b)
  local r = a.rel[b.id]
  if not r then r = { f = 0, a = 0 }; a.rel[b.id] = r end
  return r
end
Social.rel = rel

local function compat(a, b)
  local c = 0
  if a.taste == b.taste then c = c + 2 end
  if a.clique and a.clique == b.clique then c = c + 2 end
  if math.abs(a.age - b.age) > 12 then c = c - 1 end
  if a.job and a.job == b.job then c = c + 1 end
  c = c + (a.tr.social + b.tr.social - 1)
  return c
end
Social.compat = compat

local EDGY = { skaters = true, ["mall rats"] = true, goths = true }

-- what someone thinks when they hear a rumor
function Social.onRumor(n, r)
  if r.about == -1 then
    local p = n.p
    local k = r.kind
    if k == "shoplift" or k == "caught" then
      p.t = p.t - 8
      if EDGY[n.clique or ""] then p.f = p.f + 3 else p.f = p.f - 4 end
      if n.job and type(n.job) == "number" then p.t = p.t - 5 end
    elseif k == "banned" then
      if EDGY[n.clique or ""] then p.f = p.f + 2 else p.f = p.f - 2 end
    elseif k == "record" then p.f = p.f + 3; p.a = p.a + (n.age < 19 and 1 or 0)
    elseif k == "gig" then p.f = p.f + 4; p.a = p.a + (n.age < 19 and 2 or 0)
    elseif k == "fired" then p.t = p.t - 3
    elseif k == "hero" then p.f = p.f + 5; p.t = p.t + 5
    elseif k == "mom" then p.f = p.f - 1; p.an = p.an + 1
    elseif k == "dating" then
      if n.crushP then p.a = p.a - 10; p.an = p.an + 5 end
    elseif k == "promoted" then p.t = p.t + 3
    elseif k == "blabbed" then p.t = p.t - 6
    elseif k == "fight" then p.fe = p.fe + 4
    end
    p.heard = true
    Social.clampP(n)
  elseif r.kind == "closing" and n.job == r.store then
    n.mood = U.clamp(n.mood - 10, 0, 100)
    n.wants[#n.wants + 1] = { k = "job" }
  elseif r.kind == "breakup" and r.about and n.crush == r.about then
    n.mood = U.clamp(n.mood + 5, 0, 100) -- secretly thrilled
  end
  Romance.onRumor(n, r)
end

function Social.clampP(n)
  local p = n.p
  p.f = U.clamp(p.f, -100, 100); p.t = U.clamp(p.t, -100, 100)
  p.a = U.clamp(p.a, 0, 100); p.fe = U.clamp(p.fe, 0, 100); p.an = U.clamp(p.an, 0, 100)
end

-- hottest rumor a knows that b doesn't
local function pickRumor(a, b)
  local best, bh
  for _, r in ipairs(W.rumors) do
    if r.known[a.id] and not r.known[b.id] and r.about ~= b.id then
      local h = r.heat + ((r.about == -1) and 1 or 0)
      if not bh or h > bh then best, bh = r, h end
    end
  end
  return best
end

local function startDating(a, b)
  a.partner, b.partner = b.id, a.id
  a.since, b.since = Clock.day(W.t), Clock.day(W.t)
  a.crush, b.crush = b.id, a.id
  rel(a, b).a = math.max(rel(a, b).a, 60); rel(b, a).a = math.max(rel(b, a).a, 60)
  a.mood = U.clamp(a.mood + 15, 0, 100); b.mood = U.clamp(b.mood + 15, 0, 100)
  W.stats.couples = W.stats.couples + 1
  Timeline.add("people", NPCGen.name(a) .. " and " .. NPCGen.name(b) .. " are going out.", 2)
  Rumors.add("dating", a.id, a.first .. " is dating " .. b.first .. " " .. b.last, 6, { a.id, b.id })
  Memory.add(a, "dating", "started going out with " .. b.first, b.id)
  Memory.add(b, "dating", "started going out with " .. a.first, a.id)
end

function Social.breakup(a, b, why)
  a.partner, b.partner = nil, nil
  if a.crush == b.id then a.crush = nil end
  if b.crush == a.id then b.crush = nil end
  rel(a, b).a = 10; rel(b, a).a = 10
  rel(a, b).f = rel(a, b).f - 20; rel(b, a).f = rel(b, a).f - 25
  a.mood = U.clamp(a.mood - 15, 0, 100); b.mood = U.clamp(b.mood - 25, 0, 100)
  W.stats.breakups = W.stats.breakups + 1
  Timeline.add("people", NPCGen.name(a) .. " and " .. NPCGen.name(b) .. " broke up" .. (why and (" " .. why) or "") .. ".", 2)
  Rumors.add("breakup", a.id, a.first .. " and " .. b.first .. " broke up" .. (why and (" " .. why) or ""), 7, { a.id, b.id })
  Memory.add(a, "breakup", "broke up with " .. b.first, b.id)
  Memory.add(b, "breakup", "got dumped by " .. a.first, a.id)
end

-- one conversation between two co-located NPCs
function Social.interact(a, b, r)
  local ra, rb = rel(a, b), rel(b, a)
  local c = compat(a, b)
  local busy = (a.act == "work" and b.act ~= "work") or (b.act == "work" and a.act ~= "work")
  if busy and r:chance(0.7) then return end
  -- argument?
  local tension = (ra.f < -20 and 0.25 or 0.03) * (a.tr.temper + 0.3)
  if r:chance(tension) then
    ra.f = ra.f - r:i(4, 12); rb.f = rb.f - r:i(4, 12)
    local day = Clock.day(W.t)
    local public = a.loc == "c1" or a.loc == "c2" or a.loc == "fc" or a.loc == "lot" or a.loc:match("^s")
    if ra.f < -50 and rb.f < -40 and public and a.act ~= "work" and b.act ~= "work"
      and (a.lastFight or -99) < day - 14 and (b.lastFight or -99) < day - 14 and r:chance(0.25) then
      a.lastFight, b.lastFight = day, day
      Social.fight(a, b, r)
    end
    return
  end
  local df = c + r:range(-1.5, 3)
  ra.f = U.clamp(ra.f + df, -100, 100); rb.f = U.clamp(rb.f + df, -100, 100)
  -- gossip
  if r:chance(0.25 + a.tr.gossip * 0.5) then
    local rm = pickRumor(a, b)
    if rm and r:chance(math.min(0.95, rm.heat / 8 + 0.2)) then
      Rumors.learn(rm, b)
      rm.heat = math.min(10, rm.heat + 0.2)
      if r:chance(0.06) then Rumors.mutate(rm, a) end
    end
  end
  -- romance
  if NPCGen.romanceOK(a, b) and not busy then
    if a.crush == b.id then
      rb.a = U.clamp(rb.a + (c > 1 and 3 or 1), 0, 100)
      ra.a = U.clamp(ra.a + 1, 0, 100)
      if not a.partner and not b.partner and ra.a >= 55 and rb.a >= 45 and r:chance(0.12) then
        startDating(a, b)
      end
    elseif a.partner and a.partner ~= b.id and ra.a > 35 and r:chance(0.02 * a.tr.romance) then
      -- a new crush while already going out with someone
      a.crush = b.id
      a.secrets[#a.secrets + 1] = { txt = "is into " .. b.first .. " even though they're going out with " ..
        (W.npcs[a.partner] and W.npcs[a.partner].first or "someone"), known = false, cheat = b.id }
    elseif not a.crush and r:chance(0.01 * (a.tr.romance + 0.2)) and c > 1 then
      a.crush = b.id; ra.a = U.clamp(ra.a + 20, 0, 100)
    end
  end
end

function Social.fight(a, b, r)
  local where = Areas.name(a.loc)
  Management.noteFight()
  Timeline.add("people", NPCGen.name(a) .. " and " .. NPCGen.name(b) .. " got into a shoving match at the " .. where .. ".", 2)
  Rumors.add("fight", a.id, a.first .. " and " .. b.first .. " had a fight at the " .. where, 6, { a.id, b.id })
  -- security response if a guard is around
  local guard
  for _, n in ipairs(NPCAI.inArea(a.loc)) do if n.job == "sec" then guard = n end end
  if guard or r:chance(0.4) then
    for _, x in ipairs({ a, b }) do
      if x.job then Memory.add(x, "writeup", "got written up for fighting")
      else Security.banNPC(x, 7, "fighting") end
    end
  end
end

-- runs every 10 game minutes
function Social.update()
  local r = U.rng(W.seed, "social", math.floor(W.t))
  -- sorted: string-key iteration order is randomized per Lua state, and the
  -- shared RNG must be consumed in a stable order for deterministic runs
  for _, area in ipairs(U.keys(NPCAI.byArea)) do
    local list = NPCAI.byArea[area]
    local n = #list
    if n >= 2 and area ~= "home" then
      local pairs_ = math.min(4, n // 2 + 1)
      for _ = 1, pairs_ do
        local a = list[r:i(1, n)]
        local b = list[r:i(1, n)]
        if a ~= b and not a.route and not b.route then
          -- people talk more to people they know
          local known = a.rel[b.id] ~= nil
          if known or r:chance(0.25 * a.tr.social) then Social.interact(a, b, r) end
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ daily
-- relationships fade without contact: weekly drift toward neutral, and
-- near-zero acquaintances are forgotten entirely (keeps rel tables small)
function Social.weekly()
  for _, n in ipairs(W.npcs) do
    if n.status == "active" then
      for id, rr in pairs(n.rel) do
        local keep = (n.partner == id) or (n.crush == id) or (n.parent == id) or (n.kid == id)
        rr.f = rr.f * 0.9
        if rr.a and not keep then rr.a = rr.a * 0.9 end
        if not keep and math.abs(rr.f) < 3 and (rr.a or 0) < 5 then n.rel[id] = nil end
      end
      -- the player fades too, a little
      local p = n.p
      if p.met then
        p.f = p.f * 0.97; p.an = p.an * 0.8; p.fe = p.fe * 0.85
      end
    end
  end
end

function Social.daily(day)
  local r = U.rng(W.seed, "socday", day)
  for _, n in ipairs(W.npcs) do
    if n.status == "active" then
      -- mood drifts home
      n.mood = U.clamp(n.mood + (55 - n.mood) * 0.08 + r:range(-3, 3), 0, 100)
      -- couples
      local p = n.partner and W.npcs[n.partner]
      if p and n.id < p.id then
        local ra, rb = rel(n, p), rel(p, n)
        local risk = 0.004
        if ra.f < 5 or rb.f < 5 then risk = risk + 0.06 end
        if n.crush ~= p.id or p.crush ~= n.id then risk = risk + 0.05 end
        if n.age < 19 then risk = risk + 0.006 end
        if r:chance(risk) then
          local why = r:pick({ nil, "at the food court", "over the phone", "by passing a note", "in front of the fountain",
            "over a mixtape", nil })
          if r:chance(0.5) then Social.breakup(n, p, why) else Social.breakup(p, n, why) end
        end
      end
      -- workers who hate their job start wanting out
      if n.job and type(n.job) == "number" and n.mood < 35 and r:chance(0.05) then
        local has = false
        for _, w in ipairs(n.wants) do if w.k == "quit" then has = true end end
        if not has then n.wants[#n.wants + 1] = { k = "quit" } end
      end
      -- wants refresh
      if #n.wants < 2 and r:chance(0.08) then
        local before = #n.wants
        NPCGen.assignWants(W, r, n)
        if #n.wants == 0 and before > 0 then n.wants = {} end
      end
      -- trend-chasers
      local hot = Trends.hotItem()
      if hot and n.age < 30 and r:chance(0.02) then n.wants[#n.wants + 1] = { k = "item", ref = hot } end
      -- people move away, rarely
      if n.role ~= "family" and not n.lore and r:chance(0.0008) and n.id ~= W.mall.gm then
        Social.moveAway(n, r)
      end
      if n.grounded and n.grounded <= day then n.grounded = nil end
      -- things they borrowed from the player
      if n.owes and n.owes.due <= day then
        local o = n.owes
        n.owes = nil
        if n.tr.honest > 0.35 then
          for i, it in ipairs(n.poss) do
            if it.n == o.n and it.fromPlayer then
              table.remove(n.poss, i)
              Econ.give({ k = it.k, n = it.n, v = it.v, ref = it.ref })
              Pager.send(n.first:upper(), "LEFT UR " .. o.n:upper():sub(1, 14) .. " AT UR HOUSE. THX")
              break
            end
          end
        else
          Pager.send(n.first:upper(), "SO I KINDA LOST UR " .. o.n:upper():sub(1, 14) .. ". SORRY")
          Memory.add(n, "lostyours", "lost " .. W.p.name .. "'s " .. o.n, -1)
        end
      end
    end
  end
  -- newcomers keep the population steady
  local active = 0
  for _, n in ipairs(W.npcs) do if n.status == "active" then active = active + 1 end end
  W.mall.population = active
  NPCGen.compactGone(day)
  if active < (W.mall.basePop or active) and r:chance(0.5) then
    local role = r:pick({ "teen", "shopper", "parent", "teen" })
    local n = NPCGen.new(W, r, role, role == "teen" and r:i(14, 18) or r:i(25, 55))
    NPCGen.assignWants(W, r, n)
    n.wants[#n.wants + 1] = { k = "job" }
    Timeline.add("people", NPCGen.name(n) .. " just moved to " .. W.mall.city .. " from " .. r:pick(Names.cities) .. ".", 1)
    NPCAI.planDay(n, day)
  end
  MusicSim.formBands(day)
  Social.pagePlayer(day, r)
end

function Social.moveAway(n, r)
  n.status = "gone"
  n.goneDay = Clock.day(W.t)
  n.loc = "home"; n.route = nil
  local where = r:pick({ "Phoenix", "Ohio", "live with their dad", "college", "Florida", "the Army", "Portland" })
  Timeline.add("people", NPCGen.name(n) .. " moved away (" .. where .. ").", n.p.met and 2 or 1)
  if n.partner == -1 then W.p.partner = nil; W.p.conf = U.clamp(W.p.conf - 10, 0, 100) end
  if n.partner and W.npcs[n.partner] then
    local p = W.npcs[n.partner]
    p.partner = nil; p.mood = U.clamp(p.mood - 20, 0, 100)
  end
  if n.job and type(n.job) == "number" then
    local s = W.stores[n.job]
    if s.mgr == n.id then s.mgr = nil else U.removeValue(s.emp, n.id) end
  elseif n.job == "sec" then U.removeValue(W.mall.security, n.id)
  end
  n.job = nil
  if n.p.f > 40 then Pager.send(n.first:upper(), "MOVING AWAY. WONT FORGET U. " .. where:upper()) end
end

-- friends page the player with plans; crushes page 143
function Social.pagePlayer(day, r)
  local info = Clock.info(day)
  for _, n in ipairs(W.npcs) do
    if n.status == "active" and n.p.met and n.age < 20 then
      local p = n.p
      if p.f >= 45 and r:chance(0.05) then
        local place = r:pick({ "ARCADE", "FOOD CT", "FOUNTAIN", "RECORD STORE" })
        local hour = info.school and r:i(16, 19) or r:i(12, 19)
        local area = ({ ARCADE = "s" .. W.mall.arcade, ["FOOD CT"] = "fc", FOUNTAIN = "c1",
          ["RECORD STORE"] = (Stores.byType("music")[1] and ("s" .. Stores.byType("music")[1].id) or "fc") })[place]
        Pager.send(n.first:upper(), "MEET @ " .. place .. " " .. (hour > 12 and hour - 12 or hour) .. "PM?")
        W.p.invites[#W.p.invites + 1] = { npc = n.id, day = day, s = hour * 60, e = hour * 60 + 60, a = area }
        n.dateToday = { day = day, s = hour * 60, e = hour * 60 + 60, a = area, with = -1 }
      elseif p.a >= 65 and NPCGen.romanceOK(n, { id = -1, age = W.p.age }) and r:chance(0.04) then
        Pager.send("???", "143")
      elseif p.f >= 60 and r:chance(0.02) then
        local what = r:pick({ "mixtape (" .. n.first .. "'s picks)", "friendship bracelet", "photo-booth strip of you two",
          "copy of " .. (n.taste or "their favorite") .. " CD", "folded note (do not read in public)" })
        Econ.give({ k = "gift", n = what, v = 0, from = "gift", giver = n.id })
        Pager.send(n.first:upper(), "LEFT SOMETHING IN UR BACKPACK :)")
        Memory.add(n, "gave", "gave " .. W.p.name .. " a " .. what, -1)
      elseif p.f >= 35 and r:chance(0.01) and #W.p.inv > 3 then
        local it = W.p.inv[r:i(1, #W.p.inv)]
        if it.k ~= "gear" then
          Pager.send(n.first:upper(), "CAN I BORROW UR " .. it.n:upper():sub(1, 18) .. "?")
          n.wantsBorrow = it.n
        end
      end
    end
  end
  U.trim(W.p.invites, 10)
end

-- two people meeting for a date / plan
function Social.dateArrive(n, withId)
  if withId == -1 then return end -- meeting the player; handled by the explore scene
  local o = withId and W.npcs[withId]
  if o and o.loc == n.loc then
    rel(n, o).f = rel(n, o).f + 4; rel(o, n).f = rel(o, n).f + 4
    if NPCGen.romanceOK(n, o) then rel(n, o).a = rel(n, o).a + 3; rel(o, n).a = rel(o, n).a + 3 end
  end
end

-- ------------------------------------------------------------------ player
-- NPC reputation of the player, 0..100
function Social.playerRep()
  local sum, cnt = 0, 0
  for _, n in ipairs(W.npcs) do
    if n.status == "active" and (n.p.met or n.p.heard) then
      sum = sum + n.p.f + n.p.t * 0.5
      cnt = cnt + 1
    end
  end
  if cnt == 0 then return 20 end
  local known = math.min(1, cnt / 120)
  return U.clamp(math.floor(20 + (sum / cnt) * 0.6 + known * 30), 0, 100)
end

function Social.cliqueRep()
  local sums, cnts = {}, {}
  for _, n in ipairs(W.npcs) do
    if n.status == "active" and n.clique and (n.p.met or n.p.heard) then
      sums[n.clique] = (sums[n.clique] or 0) + n.p.f
      cnts[n.clique] = (cnts[n.clique] or 0) + 1
    end
  end
  local out = {}
  for _, c in ipairs(Names.cliques) do
    out[c] = cnts[c] and math.floor(sums[c] / cnts[c]) or 0
  end
  return out
end
