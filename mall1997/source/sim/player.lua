-- Player simulation: light needs, curfew and parents, allowance, rentals,
-- taste as a social signal, daily bookkeeping.

PlayerSim = {}

function PlayerSim.curfew(day)
  local info = Clock.info(day)
  local c = 21 * 60
  local tomorrow = Clock.info(day + 1)
  if not tomorrow.school then c = 22 * 60 end
  if (W.p.grounded or 0) > day then c = 19 * 60 end
  return c + (W.p.curfewShift or 0)
end

-- per game-minute while the player is at the mall
function PlayerSim.tick(dt)
  local p = W.p
  p.energy = U.clamp(p.energy - 0.07 * dt, 0, 100)
  p.hunger = U.clamp(p.hunger + 0.11 * dt, 0, 100)
  if p.hunger > 80 then p.conf = U.clamp(p.conf - 0.02 * dt, 0, 100) end
  p.conf = U.clamp(p.conf + (50 - p.conf) * 0.0008 * dt, 0, 100)
  PlayerSim.parents()
end

-- curfew pages and Mom coming to find you
function PlayerSim.parents()
  local p = W.p
  if not p.atMall then return end
  local day = Clock.day(W.t)
  local m = Clock.minute(W.t)
  local c = PlayerSim.curfew(day)
  p.curfewFlags = p.curfewFlags or {}
  local f = p.curfewFlags
  if f.day ~= day then p.curfewFlags = { day = day }; f = p.curfewFlags end
  if m >= c - 30 and not f.warn then f.warn = true; Pager.send("MOM", "HOME BY " .. Clock.hhmm(c) .. ". BUS IS AT THE LOT.") end
  if m >= c and not f.late then f.late = true; Pager.send("MOM", "911 911 WHERE ARE YOU") end
  if m >= c + 25 and not f.hunt then
    f.hunt = true
    local mom = W.npcs[p.mom]
    mom.status = "active"
    mom.loc = "home"; mom.x, mom.y = 0, 0; mom.route = nil
    mom.plan = {}
    mom.hunting = true
    NPCAI.depart(mom, p.area, "fetch", nil, "wait")
    Pager.send("MOM", "IM COMING IN THERE")
    Timeline.add("player", "Mom drove to the mall to find " .. p.name .. ".", 2)
  end
end

-- Mom re-targets the player's current area as she walks
function PlayerSim.momChase()
  local p = W.p
  local mom = W.npcs[p.mom]
  if not mom or not mom.hunting then return nil end
  if not mom.route and mom.loc ~= p.area then NPCAI.depart(mom, p.area, "fetch", nil, "wait") end
  if mom.route and mom.dest ~= p.area and (math.floor(W.t) % 3 == 0) then NPCAI.depart(mom, p.area, "fetch", nil, "wait") end
  return mom
end

function PlayerSim.momCaught()
  local p = W.p
  local mom = W.npcs[p.mom]
  mom.hunting = nil
  mom.route = nil; mom.loc = "home"; mom.status = "inactive"
  local day = Clock.day(W.t)
  p.grounded = math.max(p.grounded or 0, day + 3)
  local seeds = {}
  for _, n in ipairs(NPCAI.inArea(p.area)) do if n.age < 20 then seeds[#seeds + 1] = n.id end end
  if #seeds > 0 then
    Rumors.add("mom", -1, p.name .. "'s mom dragged them out of the " .. Areas.name(p.area) .. " by the backpack strap", 7, seeds)
  end
  Timeline.add("player", "Mom found " .. p.name .. " at the " .. Areas.name(p.area) .. ". Grounded for 3 days.", 3)
end

function PlayerSim.updateTaste()
  local counts = {}
  for _, it in ipairs(W.p.inv) do
    if it.k == "album" and W.music.albums[it.ref] then
      local g = W.music.bands[W.music.albums[it.ref].band].genre
      counts[g] = (counts[g] or 0) + 1
    end
  end
  local best, bc = nil, 0
  for _, g in ipairs(Names.genres) do if (counts[g] or 0) > bc then best, bc = g, counts[g] end end
  W.p.taste = best
end

-- once per day at dawn
function PlayerSim.daily(day)
  local p = W.p
  local info = Clock.info(day)
  if info.wd == 0 and (p.grounded or 0) <= day then
    p.money = p.money + 1000
    Pager.send("DAD", "$10 ALLOWANCE ON UR DRESSER")
  end
  -- rentals
  for _, it in ipairs(p.inv) do
    if it.due and it.due < day then
      p.money = p.money - 100
      it.lateFees = (it.lateFees or 0) + 100
      if (it.lateFees // 100) % 3 == 1 then Pager.send("VIDEO", "PLEASE RETURN " .. it.n:upper():sub(1, 16) .. " LATE FEES APPLY") end
    end
  end
  -- things you borrowed and haven't returned
  for _, it in ipairs(p.inv) do
    if it.borrowed and it.due and it.due < day then
      local n = W.npcs[it.borrowed]
      if n then
        n.p.t = n.p.t - 4; n.p.an = n.p.an + 3
        if (day - it.due) % 3 == 1 then Pager.send(n.first:upper(), "WHERE IS MY " .. it.n:upper():sub(1, 14) .. "???") end
        Social.clampP(n)
      end
    end
  end
  -- invitations you didn't show up for
  for _, inv in ipairs(p.invites) do
    if inv.day < day and not inv.met and not inv.judged then
      inv.judged = true
      local n = W.npcs[inv.npc]
      if n then
        n.p.f = n.p.f - 6; n.p.t = n.p.t - 4
        Memory.add(n, "stoodup", W.p.name .. " stood me up", -1)
        Social.clampP(n)
      end
    end
  end
  p.rep = Social.playerRep()
  p.cliqueRep = Social.cliqueRep()
  if p.fame > 0 then p.fame = p.fame - 0.2 end
  if ArcadeSim.champion() and not p.flags.champ then
    p.flags.champ = day
    Timeline.add("arcade", W.p.name .. " holds the record on every cabinet in the arcade. Arcade champion.", 3)
    p.fame = p.fame + 15
  end
  p.dayLog = {}
end

-- pay the video store back
function PlayerSim.returnRental(it)
  U.removeValue(W.p.inv, it)
  return it.lateFees and ("Returned. You paid " .. U.money(it.lateFees) .. " in late fees.") or "Returned on time. Be kind, rewind."
end
