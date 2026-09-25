-- Store simulation: hours, staff schedules, daily economics, weekly reviews,
-- closures, new tenants, manager turnover and neighbour relations.

Stores = {}

function Stores.hours(s, day)
  if not s.open then return nil end
  local info = Clock.info(day)
  if info.closed then return nil end
  if s.reno and s.reno > day then return nil end
  if s.closedSun and info.wd == 0 then return nil end
  local o = math.max(info.open, s.hoursO or info.open)
  local c = s.hoursC or info.close
  if s.type == "cinema" then o, c = s.hoursO, s.hoursC end
  if s.type == "weird" then
    -- "open when the owner feels like it"
    local r = U.rng(W.seed, "weird", s.id, day)
    if r:chance(0.15) then return nil end
    o = o + r:i(0, 2) * 30
  end
  return o, c
end

function Stores.isOpenAt(s, t)
  local o, c = Stores.hours(s, Clock.day(t))
  if not o then return false end
  local m = Clock.minute(t)
  return m >= o and m < c
end

function Stores.staff(s)
  local list = {}
  if s.mgr then list[#list + 1] = s.mgr end
  for _, e in ipairs(s.emp) do list[#list + 1] = e end
  return list
end

-- Which shift (minute range) does NPC n work on this day, if any?
function Stores.shiftOf(n, day)
  if n.status ~= "active" or not n.job then return nil end
  local info = Clock.info(day)
  if type(n.job) == "number" then
    local s = W.stores[n.job]
    local o, c = Stores.hours(s, day)
    if not o then return nil end
    local mid = (o + c) // 2
    if n.title == "manager" then
      if ((day + n.id) % 7) < 2 then return nil end
      if (day + n.id) % 2 == 0 then return { o - 30, math.min(c, o + 510) } end
      return { math.max(o, c - 510), c + 15 }
    end
    local works = ((day * 3 + n.id) % 7) < 4
    if info.holidaySeason then works = ((day * 3 + n.id) % 7) < 6 end
    if not works then return nil end
    if n.age < 18 and info.school then
      return { math.max(mid, 16 * 60), c + 15 }
    end
    if (day + n.id) % 2 == 0 then return { o - 15, mid + 30 } end
    return { mid, c + 15 }
  end
  local off = ((n.id * 5 + day) % 7) < 2
  if n.job == "sec" then
    if n.title == "chief" then
      if info.weekend then return nil end
      return { 9 * 60, 17 * 60 + 30 }
    end
    if off then return nil end
    local k = (n.id + day) % 3
    if k == 0 then return { 6 * 60 + 30, 15 * 60 } end
    if k == 1 then return { 14 * 60 + 30, 23 * 60 } end
    return { 21 * 60, 23 * 60 + 59 }
  elseif n.job == "maint" then
    if n.id == W.mall.janitor then
      if info.wd == 1 then return nil end
      return { 21 * 60 + 30, 23 * 60 + 59 }
    end
    if off then return nil end
    if n.id % 2 == 0 then return { 6 * 60, 14 * 60 + 30 } end
    return { 13 * 60 + 30, 22 * 60 }
  elseif n.job == "mgmt" then
    if info.weekend and not (info.wd == 6 and n.id == W.mall.gm and day % 2 == 0) then return nil end
    return { 8 * 60 + 30, 17 * 60 + 30 }
  end
  return nil
end

-- staff physically present in the store right now
function Stores.presentStaff(s)
  local a = Areas.storeArea(s)
  local out = {}
  for _, n in ipairs(NPCAI.inArea(a)) do
    if n.job == s.id and (n.act == "work") and not n.route then out[#out + 1] = n end
  end
  return out
end

-- ------------------------------------------------------------------ economy
function Stores.footfall(day)
  local info = Clock.info(day)
  if info.closed then return 0 end
  local base = 3600
  if info.wd == 6 then base = 8200 elseif info.wd == 0 then base = 5200 elseif info.wd == 5 then base = 5000 end
  if info.summer and not info.weekend then base = base * 1.25 end
  if info.holidaySeason then base = base * 1.7 end
  if info.holiday == "Black Friday" then base = 15000 end
  if info.holiday == "Christmas Eve" then base = base * 1.3 end
  if info.m == 1 and info.d > 2 then base = base * 0.72 end
  if info.m == 12 and info.d >= 26 then base = base * 1.35 end
  if info.holiday == "Halloween" or info.holiday == "Valentine's Day" then base = base * 1.15 end
  -- vacancies and neglect make the whole mall less appealing
  local vac = 0
  for _, sl in ipairs(W.slots) do if sl.kind == "store" and not sl.store then vac = vac + 1 end end
  base = base * (1 - math.min(0.35, vac * 0.012))
  base = base * (W.mall.appeal or 1)
  return base
end

local SEASON = {
  toys = { winter = 1.6, fall = 1.0, spring = 0.8, summer = 0.9 },
  jewelry = { winter = 1.5 },
  gifts = { winter = 1.6 },
  sporting = { spring = 1.2, summer = 1.2, winter = 0.9 },
  clothing = { fall = 1.2, winter = 1.2 },
  shoes = { fall = 1.3 },
  cinema = { summer = 1.3, winter = 1.2 },
  arcade = { summer = 1.4 },
  food = { summer = 1.1 },
}

function Stores.weight(s, day)
  local info = Clock.info(day)
  local w = s.pop + 5
  local sm = SEASON[s.type]
  if sm and sm[info.season] then w = w * sm[info.season] end
  if info.m == 8 or (info.m == 9 and info.d < 10) then
    if s.type == "clothing" or s.type == "shoes" or s.type == "books" then w = w * 1.4 end -- back to school
  end
  if s.sale > 0 then w = w * (1 + s.sale / 60) end
  w = w * Trends.storeBoost(s)
  if s.type == "department" then w = w * 4 end
  if s.type == "food" then w = w * 1.8 end
  if s.type == "cinema" then w = w * 2.5 end
  if s.stock < 25 then w = w * 0.7 end
  return w
end

-- Expected weekly revenue for a store at a given popularity, using average
-- footfall and the current mix of stores. Used to set rents so that an
-- average store roughly breaks even and weak ones slowly bleed.
function Stores.expectedWeekly(s, pop, totalW)
  local T = MallGen.TYPES[s.type]
  local saved = s.pop
  s.pop = pop
  local w = Stores.weight(s, Clock.day(W.t))
  s.pop = saved
  local visits = 4500 * 7 * 3 * w / totalW
  return visits * T.conv * T.ticket
end

function Stores.totalWeight()
  local tw = 0
  for _, x in ipairs(W.stores) do if x.open then tw = tw + Stores.weight(x, Clock.day(W.t)) end end
  return tw
end

function Stores.calibrateRent(s, totalW)
  totalW = totalW or Stores.totalWeight()
  local wk = Stores.expectedWeekly(s, 52, totalW)
  s.rent = math.floor(wk * 4.3 * (s.type == "department" and 0.2 or 0.25))
end

-- Close out one day's trading for every store.
function Stores.daily(day)
  local foot = Stores.footfall(day)
  local totalW = 0
  local ws = {}
  for _, s in ipairs(W.stores) do
    if s.open and Stores.hours(s, day) then
      local w = Stores.weight(s, day)
      ws[s.id] = w
      totalW = totalW + w
    end
  end
  local r = U.rng(W.seed, "econ", day)
  W.mall.lastFootfall = math.floor(foot)
  for _, s in ipairs(W.stores) do
    if s.open then
      local T = MallGen.TYPES[s.type]
      local visits, rev = 0, 0
      if ws[s.id] and totalW > 0 then
        visits = foot * 3 * ws[s.id] / totalW
        local conv = T.conv
        local ticket = T.ticket * (1 - s.sale / 100)
        local stockF = U.clamp(s.stock / 60, 0.3, 1.1)
        local staffF = 1
        local crew = #s.emp + (s.mgr and 1 or 0)
        if crew < math.max(1, T.staff - 1) then staffF = 0.75 end
        if s.type == "cinema" then ticket = 700 + CinemaSim.draw() * 250 end
        rev = visits * conv * ticket * stockF * staffF * r:range(0.8, 1.2)
      end
      rev = rev + (s.npcSales or 0)
      s.npcSales = 0
      local wages = 0
      for _, id in ipairs(Stores.staff(s)) do
        local n = W.npcs[id]
        if n and Stores.shiftOf(n, day) then wages = wages + (n.wage or 500) * 7 end
      end
      local rent = s.rent / 30 * 1.25 -- rent plus common-area charges
      local cogs = rev * (s.type == "cinema" and 0.55 or 0.5)
      s.cash = s.cash + rev - wages - rent - cogs - (s.theftDay or 0)
      s.theftDay = 0
      s.costWeek = (s.costWeek or 0) + wages + rent + cogs
      s.salesDay = math.floor(rev)
      s.salesWeek = (s.salesWeek or 0) + rev
      s.visitsDay = math.floor(visits)
      -- stock: what sells is reordered (paid for in COGS) unless the store
      -- is broke and suppliers put it on credit hold
      local sold = visits * T.conv * 0.15
      local reorder = s.cash > 0 and sold * 1.05 + 1 or sold * 0.35
      s.stock = U.clamp(s.stock - sold + reorder, 0, 100)
    end
  end
end

-- Weekly review: history, popularity drift, restocking, trouble, sales.
function Stores.weekly(day)
  local r = U.rng(W.seed, "weekly", day)
  local closingsThisWeek = 0
  for _, s in ipairs(W.stores) do
    if s.open then
      s.hist[#s.hist + 1] = math.floor(s.salesWeek)
      U.trim(s.hist, 12)
      s.profitWeek = math.floor(s.salesWeek - (s.costWeek or 0))
      s.costWeek = 0
      local weekCost = s.rent / 4.3
      -- a store in the black refreshes its displays
      if s.cash > 0 then s.stock = U.clamp(s.stock + r:i(5, 15), 0, 100) end
      -- popularity drifts toward a base with trends and noise
      local target = 22 + (s.q or 0.5) * 56 + (Trends.storeBoost(s) - 1) * 60 + (s.buzz or 0)
      if s.feud then target = target - 4 end
      if (s.theft or 0) > 4 then target = target - 3 end
      s.pop = U.clamp(s.pop + (target - s.pop) * 0.15 + r:range(-3, 3), 3, 100)
      s.buzz = (s.buzz or 0) * 0.6
      -- margins
      if s.cash < -weekCost * 1.5 and (s.profitWeek or 0) < 0 then s.trouble = (s.trouble or 0) + 1
      elseif s.cash > 0 then s.trouble = math.max(0, (s.trouble or 0) - 1) end
      if s.sale > 0 then
        s.saleWeeks = (s.saleWeeks or 0) + 1
        if s.saleWeeks > 2 and not s.closing then s.sale = 0; s.saleWeeks = 0 end
      elseif (s.trouble or 0) >= 1 and r:chance(0.5) then
        s.sale = r:pick({ 15, 20, 25, 30 })
        if s.pop > 30 then Timeline.add("store", s.name .. " put up a big " .. s.sale .. "% OFF banner.", 1) end
      end
      -- a struggling store gets a new manager, or closes
      if not s.closing and s.type ~= "department" and s.type ~= "cinema" and s.id ~= W.mall.arcade then
        s.patience = s.patience or (2 + U.hash(W.seed, s.id) % 7)
        if ((s.trouble or 0) >= s.patience or (s.cash < -60000 * 100)) and closingsThisWeek < 2 then
          closingsThisWeek = closingsThisWeek + 1
          Stores.announceClosing(s, day, r)
        elseif (s.trouble or 0) >= 3 and r:chance(0.15) and s.mgr and (s.mgrSince or -99) < day - 60 then
          Stores.replaceManager(s, "fired", r)
        end
      end
      if s.type == "department" and s.cash < 0 then s.cash = s.cash + 2000000 end -- corporate backing
      s.salesWeek = 0
    end
  end
  Stores.neighbors(day, r)
  Stores.leasing(day, r)
end

function Stores.announceClosing(s, day, r)
  s.closing = day + r:i(7, 24)
  s.sale = 50
  Timeline.add("store", s.name .. " announced it is closing. EVERYTHING MUST GO.", 3)
  local seeds = {}
  for _, id in ipairs(Stores.staff(s)) do seeds[#seeds + 1] = id end
  Rumors.add("closing", nil, s.name .. " is closing", 6, seeds, { store = s.id })
  if W.p.job and W.p.job.store == s.id then Pager.send(W.npcs[s.mgr] and W.npcs[s.mgr].first:upper() or "WORK", "STORE IS CLOSING. SORRY KID.") end
end

function Stores.close(s, day)
  s.open = false
  s.closedDay = day
  s.closing = nil
  W.stats.closures = W.stats.closures + 1
  Timeline.add("store", s.name .. " closed for good after " .. math.max(1, (day - s.opened) // 30) .. " months.", 3)
  for _, id in ipairs(Stores.staff(s)) do
    local n = W.npcs[id]
    if n then
      n.job, n.title = nil, nil
      n.mood = U.clamp(n.mood - 20, 0, 100)
      n.wants[#n.wants + 1] = { k = "job" }
      Memory.add(n, "lostjob", s.name .. " closed and I lost my job")
    end
  end
  s.emp = {}
  s.mgr = nil
  if s.slot then
    local sl = W.slots[s.slot]
    sl.store = nil
    sl.vacantSince = day
  end
  if W.p.job and W.p.job.store == s.id then Jobs.lose("closed") end
  Areas.invalidate()
end

function Stores.replaceManager(s, why, r)
  local old = s.mgr and W.npcs[s.mgr]
  local best, bs = nil, -1
  for _, id in ipairs(s.emp) do
    local e = W.npcs[id]
    local sc = e.age / 10 + e.tr.ambition * 5 + r:f()
    if e.age >= 19 and sc > bs then best, bs = e, sc end
  end
  -- the player is a candidate if they are an assistant manager there
  if W.p.job and W.p.job.store == s.id and W.p.job.rank >= 3 and W.p.job.perf > 60 then
    best = nil
  end
  if old then
    old.job, old.title = nil, nil
    old.mood = U.clamp(old.mood + (why == "quit" and 10 or -30), 0, 100)
    Memory.add(old, "lostjob", why == "fired" and ("got fired from " .. s.name) or ("quit " .. s.name))
    old.wants[#old.wants + 1] = { k = "job" }
    if why == "fired" then
      Rumors.add("fired", old.id, NPCGen.name(old) .. " got fired from " .. s.name, 6, s.emp, { store = s.id })
    end
  end
  W.stats.mgrChanges = W.stats.mgrChanges + 1
  s.mgrSince = Clock.day(W.t)
  s.q = U.clamp((s.q or 0.5) + r:range(-0.15, 0.25), 0.05, 1)
  s.trouble = math.max(0, (s.trouble or 0) - 1)
  if best then
    U.removeValue(s.emp, best.id)
    s.mgr = best.id; best.title = "manager"; best.wage = (best.wage or 500) + 400
    best.mood = U.clamp(best.mood + 20, 0, 100)
    Timeline.add("store", NPCGen.name(best) .. " is the new manager of " .. s.name ..
      (old and (" (" .. old.first .. " " .. (why == "fired" and "was fired" or "quit") .. ")") or "") .. ".", 2)
  elseif W.p.job and W.p.job.store == s.id and W.p.job.rank >= 3 then
    s.mgr = nil
    Jobs.promote(4)
    Timeline.add("store", W.p.name .. " is now the manager of " .. s.name .. ". At sixteen.", 3)
  else
    local n = NPCGen.new(W, r, "manager", r:i(24, 50))
    NPCGen.hire(W, n, s, "manager")
    NPCGen.assignWants(W, r, n)
    Timeline.add("store", s.name .. " brought in a new manager from out of town, " .. NPCGen.name(n) .. ".", 2)
  end
end

-- neighbours: complaints, feuds, joint promotions
function Stores.neighbors(day, r)
  for _, s in ipairs(W.stores) do
    if s.open then
      for _, nid in ipairs(s.nbr) do
        local o = W.stores[nid]
        if o and o.open and nid > s.id then
          local v = s.nrel[nid] or 0
          local d = r:range(-6, 6)
          if s.type == o.type then d = d - 4 end
          if s.type == "arcade" or o.type == "arcade" or s.type == "music" or o.type == "music" then d = d - 2 end
          if (s.theftWeek or 0) + (o.theftWeek or 0) > 1 then d = d - 3 end
          local ma, mb = s.mgr and W.npcs[s.mgr], o.mgr and W.npcs[o.mgr]
          if ma and mb and ma.rel[mb.id] then d = d + ma.rel[mb.id].f / 25 end
          v = U.clamp(v + d, -100, 100)
          s.nrel[nid] = v; o.nrel[s.id] = v
          if v < -45 and not s.feud and r:chance(0.4) then
            s.feud, o.feud = nid, s.id
            W.stats.feuds = W.stats.feuds + 1
            local why = r:pick({ "the shared trash corridor", "blasting music", "a blocked fire door",
              "who gets the holiday window display", "a customer who went next door", "a parking space" })
            Timeline.add("store", "The managers of " .. s.name .. " and " .. o.name .. " are feuding over " .. why .. ".", 2)
            Rumors.add("feud", nil, s.name .. " and " .. o.name .. " had a fight over " .. why, 5,
              { s.mgr, o.mgr }, { store = s.id })
            if ma and mb then NPCGen.setRel(ma, mb, -25); NPCGen.setRel(mb, ma, -25) end
            for _, a in ipairs(s.emp) do for _, b in ipairs(o.emp) do
              if r:chance(0.3) then NPCGen.setRel(W.npcs[a], W.npcs[b], -10) end end end
          elseif v > 45 and not s.coop and r:chance(0.3) then
            s.coop, o.coop = day, day
            s.buzz, o.buzz = (s.buzz or 0) + 6, (o.buzz or 0) + 6
            Timeline.add("store", s.name .. " and " .. o.name .. " are running a joint sidewalk sale.", 1)
            if ma and mb then NPCGen.setRel(ma, mb, 15); NPCGen.setRel(mb, ma, 15) end
          end
          if s.feud == nid and v > -10 then
            s.feud, o.feud = nil, nil
            Timeline.add("store", s.name .. " and " .. o.name .. " called a truce.", 1)
          end
        end
      end
      s.theftWeek = 0
    end
  end
end

-- vacant storefronts get new tenants, shaped by current trends
function Stores.leasing(day, r)
  for _, sl in ipairs(W.slots) do
    if sl.kind == "store" and not sl.store and not sl.abandoned then
      if sl.coming then
        if sl.coming.day <= day then Stores.openNew(sl, day, r) end
      elseif day - (sl.vacantSince or 0) >= 10 and r:chance(0.3) then
        local typ = Trends.pickNewType(r)
        sl.coming = { day = day + r:i(10, 24), type = typ }
        W.mall.nextOpening = sl.id
        Timeline.add("mall", "COMING SOON sign went up on a vacant storefront (" .. MallGen.TYPE_LABEL[typ] .. ").", 1)
      end
    end
  end
end

function Stores.openNew(sl, day, r)
  local typ = sl.coming.type
  W._usedNames = {}
  for _, s in ipairs(W.stores) do W._usedNames[s.name] = true end
  local s = MallGen.newStore(W, r, typ, sl)
  W._usedNames = nil
  local tn = Trends.tenantName(typ, r)
  if tn then s.name = tn end
  s.opened = day
  s.q = r:range(0.3, 0.95)
  s.pop = r:i(45, 75)
  s.buzz = 15
  s.cash = r:i(5000, 20000) * 100
  Stores.calibrateRent(s)
  sl.coming = nil
  sl.vacantSince = nil
  W.stats.openings = W.stats.openings + 1
  -- staff: unemployed locals first, then newcomers
  local mgr = Stores.findWorker(r, true) or NPCGen.new(W, r, "manager", r:i(24, 50))
  NPCGen.hire(W, mgr, s, "manager"); mgr.role = mgr.age < 20 and mgr.role or "manager"
  for _ = 1, math.max(1, MallGen.TYPES[typ].staff - 1) do
    local e = Stores.findWorker(r, false) or NPCGen.new(W, r, "employee", r:i(17, 35))
    NPCGen.hire(W, e, s, "clerk")
    if e.age >= 20 then e.role = "employee" end
  end
  for _, id in ipairs(Stores.staff(s)) do
    local n = W.npcs[id]
    if #n.wants == 0 then NPCGen.assignWants(W, r, n) end
    U.removeValue(n.wants, nil)
    for i = #n.wants, 1, -1 do if n.wants[i].k == "job" then table.remove(n.wants, i) end end
  end
  MallGen.linkNeighbors(W)
  Areas.invalidate()
  Timeline.add("store", "GRAND OPENING: " .. s.name .. " (" .. MallGen.TYPE_LABEL[typ] .. ") opened on the " ..
    (s.floor == 1 and "lower" or "upper") .. " level.", 3)
  Rumors.add("opening", nil, "a new " .. MallGen.TYPE_LABEL[typ]:lower() .. " store called " .. s.name .. " just opened", 4,
    { s.mgr }, { store = s.id })
  return s
end

-- an unemployed NPC who wants a job
function Stores.findWorker(r, manager)
  local cands = {}
  for _, n in ipairs(W.npcs) do
    if n.status == "active" and not n.job and n.age >= (manager and 22 or 16) and n.age < 66 and n.role ~= "family" then
      for _, w in ipairs(n.wants) do if w.k == "job" then cands[#cands + 1] = n break end end
    end
  end
  return r:pick(cands)
end

-- Staff churn and hiring (daily, cheap)
function Stores.staffing(day)
  local r = U.rng(W.seed, "staff", day)
  for _, s in ipairs(W.stores) do
    if s.open and s.closing and s.closing <= day then Stores.close(s, day) end
    if s.open and not s.closing then
      local T = MallGen.TYPES[s.type]
      -- quitting
      for i = #s.emp, 1, -1 do
        local n = W.npcs[s.emp[i]]
        local wantsQuit = false
        for _, w in ipairs(n.wants) do if w.k == "quit" then wantsQuit = true end end
        local p = 0
        if n.mood < 25 then p = 0.05 end
        if wantsQuit then p = p + 0.06 end
        if s.mgr and n.rel[s.mgr] and n.rel[s.mgr].f < -40 then p = p + 0.03 end
        if r:chance(p) then
          table.remove(s.emp, i)
          n.job, n.title = nil, nil
          n.mood = U.clamp(n.mood + 15, 0, 100)
          for k = #n.wants, 1, -1 do if n.wants[k].k == "quit" then table.remove(n.wants, k) end end
          W.stats.quits = W.stats.quits + 1
          local why = r:pick({ "without notice", "after a shouting match", "to go back to school", "for a job at the outlet mall",
            "because of the manager", "by leaving the keys on the counter" })
          Timeline.add("people", NPCGen.name(n) .. " quit " .. s.name .. " " .. why .. ".", 1)
          Memory.add(n, "quit", "quit " .. s.name)
          Rumors.add("quit", n.id, n.first .. " quit " .. s.name .. " " .. why, 4, { n.id }, { store = s.id })
        end
      end
      local m = s.mgr and W.npcs[s.mgr]
      if m and m.mood < 18 and r:chance(0.04) then Stores.replaceManager(s, "quit", r) end
      if not s.mgr then Stores.replaceManager(s, "vacant", r) end
      -- hiring
      local target = (s.type == "department") and 6 or math.max(1, T.staff - 1)
      if W.p.job and W.p.job.store == s.id then target = target - 1 end
      s.hiring = #s.emp < target
      if s.hiring and r:chance(0.25) then
        local n = Stores.findWorker(r, false)
        if n then
          NPCGen.hire(W, n, s, "clerk")
          if n.age >= 20 then n.role = "employee" end
          for k = #n.wants, 1, -1 do if n.wants[k].k == "job" then table.remove(n.wants, k) end end
          n.mood = U.clamp(n.mood + 15, 0, 100)
          W.stats.hires = W.stats.hires + 1
          Timeline.add("people", NPCGen.name(n) .. " got hired at " .. s.name .. ".", 1)
          Memory.add(n, "hired", "got hired at " .. s.name)
        end
      end
    end
  end
end

function Stores.byType(typ)
  local out = {}
  for _, s in ipairs(W.stores) do if s.open and s.type == typ then out[#out + 1] = s end end
  return out
end
