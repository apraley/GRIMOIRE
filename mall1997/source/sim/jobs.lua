-- Player employment: applications and interviews, weekly shift schedules,
-- clocking in (each shift is a minigame), pay, strikes, promotions.

Jobs = {}

Jobs.KIND = {
  music = "record", video = "video", food = "food", arcade = "arcade", cinema = "cinema",
  photo = "photo", books = "books", department = "department", sec = "security",
  restaurant = "food", clothing = "department", shoes = "department", toys = "department",
  games = "department", gifts = "department", sporting = "department", electronics = "department",
  jewelry = "department", weird = "department", services = "department", salon = "department",
}
Jobs.RANKS = { "clerk", "shift lead", "assistant manager", "manager" }
Jobs.SEC_TITLES = { "loss prevention intern", "loss prevention", "senior loss prevention", "night supervisor" }

Jobs.INTERVIEW = {
  { q = "Why do you want to work here?",
    a = { { "I love this store. Like, genuinely.", 12 }, { "I need money for a Discman.", 6 },
      { "My mom said I have to get a job.", 2 }, { "Employee discount, obviously.", 4 } } },
  { q = "A customer is yelling about a return with no receipt. What do you do?",
    a = { { "Stay calm and get a manager.", 12 }, { "Give them store credit, whatever.", 6 },
      { "Yell back.", -8 }, { "Pretend the register is broken.", 1 } } },
  { q = "Can you work weekends?",
    a = { { "Every weekend. I have no life.", 12 }, { "Most of them.", 8 }, { "Not during football season.", 2 },
      { "Define 'weekend'.", 0 } } },
  { q = "Where do you see yourself in five years?",
    a = { { "Managing this place.", 10 }, { "College, hopefully.", 8 }, { "2002? Flying cars.", 4 },
      { "Honestly? Right here, on this stool.", 3 } } },
  { q = "What's your greatest weakness?",
    a = { { "I care too much.", 5 }, { "Mornings.", 6 }, { "I've never had a job, but I learn fast.", 10 },
      { "Pretzels.", 3 } } },
}

function Jobs.kindFor(storeId)
  if storeId == "sec" then return "security" end
  local s = W.stores[storeId]
  return Jobs.KIND[s.type] or "department"
end

function Jobs.title()
  local j = W.p.job
  if not j then return "unemployed" end
  if j.store == "sec" then return Jobs.SEC_TITLES[j.rank] end
  return Jobs.RANKS[j.rank]
end

function Jobs.placeName()
  local j = W.p.job
  if not j then return "" end
  if j.store == "sec" then return "Mall Security" end
  return W.stores[j.store].name
end

-- can the player apply to this store (or "sec")?
function Jobs.canApply(storeId)
  local p = W.p
  if p.job then return false, "You already work at " .. Jobs.placeName() .. "." end
  local day = Clock.day(W.t)
  if (p.firedFrom or {})[tostring(storeId)] then return false, "\"You've got some nerve coming back here.\"" end
  if storeId == "sec" then
    if (p.record or 0) > 0 then return false, "\"With your record? Kid, come on.\"" end
    if day < 14 then return false, "\"Come back when I know your face better.\"" end
    if Social.playerRep() < 45 then return false, "\"We need people the kids actually respect. Work on that.\"" end
    return true
  end
  local s = W.stores[storeId]
  if not s or not s.open then return false, "It's closed." end
  if Security.banned(s) then return false, "\"You're banned. Why would we hire you?\"" end
  return true
end

-- decide after an interview; returns hired, text
function Jobs.decide(storeId, interviewPts)
  local p = W.p
  local mgr
  if storeId == "sec" then
    for _, id in ipairs(W.mall.security) do if W.npcs[id].title == "chief" then mgr = W.npcs[id] end end
  else
    local s = W.stores[storeId]
    mgr = s.mgr and W.npcs[s.mgr]
  end
  local score = 25 + interviewPts
  if mgr then score = score + mgr.p.f / 4 + mgr.p.t / 3 - mgr.p.an / 3 end
  score = score + Social.playerRep() / 5 - (p.record or 0) * 12
  if storeId ~= "sec" then
    local s = W.stores[storeId]
    if s.hiring then score = score + 25 else score = score - 5 end
    for _, r in ipairs(W.rumors) do
      if r.about == -1 and (r.kind == "shoplift" or r.kind == "caught") and mgr and r.known[mgr.id] then score = score - 25 end
    end
  end
  if p.flags.tips and storeId ~= "sec" then score = score + 3 end
  local hired = score >= 55
  if mgr then mgr.p.met = true; Memory.add(mgr, "interview", hired and "hired " .. p.name or "turned down " .. p.name, -1) end
  if hired then Jobs.hire(storeId) end
  return hired, math.floor(score)
end

function Jobs.hire(storeId)
  local p = W.p
  local day = Clock.day(W.t)
  local wage = storeId == "sec" and 575 or W.stores[storeId].wage
  p.job = { store = storeId, rank = 1, wage = wage, perf = 55, strikes = 0, shifts = {}, since = day, worked = 0 }
  Jobs.schedule(day)
  local place = Jobs.placeName()
  Timeline.add("job", W.p.name .. " got a job at " .. place .. ".", 3)
  Rumors.add("hired", -1, W.p.name .. " works at " .. place .. " now", 4, W.p.friends)
  if storeId ~= "sec" then
    local s = W.stores[storeId]
    s.hiring = false
    for _, id in ipairs(Stores.staff(s)) do W.npcs[id].p.met = true end
  end
end

-- plan next 7 days of shifts
function Jobs.schedule(fromDay)
  local j = W.p.job
  if not j then return end
  local r = U.rng(W.seed, "pshift", fromDay)
  local keep = {}
  for _, sh in ipairs(j.shifts) do if sh.day < fromDay and not sh.done and not sh.missed then sh.missed = true end
    if sh.day >= fromDay - 7 then keep[#keep + 1] = sh end end
  j.shifts = keep
  local want = 3 + (j.rank >= 2 and 1 or 0) + (j.moreHours and 1 or 0)
  local days = {}
  for d = fromDay + 1, fromDay + 7 do
    local info = Clock.info(d)
    local ok = not info.closed
    if j.store ~= "sec" then ok = ok and Stores.hours(W.stores[j.store], d) ~= nil end
    if ok then days[#days + 1] = d end
  end
  r:shuffle(days)
  local picked = {}
  for i = 1, math.min(want, #days) do picked[#picked + 1] = days[i] end
  table.sort(picked)
  for _, d in ipairs(picked) do
    local info = Clock.info(d)
    local s, e
    if info.school then s, e = 16 * 60, 20 * 60
    elseif r:chance(0.5) then s, e = 11 * 60, 17 * 60
    else s, e = 14 * 60, 20 * 60 end
    if j.store ~= "sec" then
      local o, c = Stores.hours(W.stores[j.store], d)
      if o then s = math.max(s, o); e = math.min(e, c) end
    end
    j.shifts[#j.shifts + 1] = { day = d, s = s, e = e }
  end
  local txt = {}
  for _, sh in ipairs(j.shifts) do
    if sh.day > fromDay then
      txt[#txt + 1] = Clock.DAYS[Clock.date(sh.day).wd + 1] .. " " .. (sh.s // 60 > 12 and sh.s // 60 - 12 or sh.s // 60) ..
        "-" .. (sh.e // 60 > 12 and sh.e // 60 - 12 or sh.e // 60)
    end
  end
  Pager.send("WORK", "SHIFTS: " .. table.concat(txt, " "))
end

function Jobs.shiftToday()
  local j = W.p.job
  if not j then return nil end
  local day = Clock.day(W.t)
  for _, sh in ipairs(j.shifts) do if sh.day == day and not sh.done and not sh.missed then return sh end end
end

-- can clock in right now?
function Jobs.canClockIn()
  local sh = Jobs.shiftToday()
  if not sh then return nil, "You're not on the schedule today." end
  local m = Clock.minute(W.t)
  if m < sh.s - 30 then return nil, "Your shift starts at " .. Clock.hhmm(sh.s) .. "." end
  if m > sh.e - 30 then return nil, "Too late. Your shift is basically over." end
  return sh
end

function Jobs.context(sh)
  local j = W.p.job
  local r = U.rng(W.seed, "shiftctx", sh.day, sh.s)
  local store = j.store == "sec" and { id = 0, name = "Mall Security", type = "sec", pop = 50 } or W.stores[j.store]
  local customers = {}
  for _ = 1, 8 do
    local n = W.npcs[r:i(1, #W.npcs)]
    if n.status == "active" and n.role ~= "family" then customers[#customers + 1] = n end
  end
  local late = Clock.minute(W.t) > sh.s + 10
  sh.late = late
  sh.inAt = math.max(sh.s, Clock.minute(W.t))
  return {
    rng = r, store = store, difficulty = U.clamp(0.2 + j.rank * 0.12 + (Clock.info(sh.day).weekend and 0.15 or 0), 0, 1),
    role = ({ "clerk", "lead", "assistant", "manager" })[j.rank], music = W.music, movies = W.movies,
    customers = customers,
  }
end

function Jobs.finish(sh, res)
  local p = W.p
  local j = p.job
  if not j then return "" end
  sh.done = true
  local mins = sh.e - (sh.inAt or sh.s)
  local hours = math.max(1, mins / 60)
  local pay = math.floor(hours * j.wage + (res.tips or 0))
  p.money = p.money + pay
  p.stats.earned = p.stats.earned + pay
  p.stats.shifts = p.stats.shifts + 1
  j.worked = j.worked + 1
  j.perf = U.clamp(j.perf * 0.75 + res.score * 0.25 - (sh.late and 5 or 0), 0, 100)
  p.energy = U.clamp(p.energy - hours * 5, 0, 100)
  -- coworkers and boss notice
  local lines = { string.format("Shift over. %d hours, %s pay%s.", math.floor(hours + 0.5), U.money(pay),
    (res.tips or 0) > 0 and (" (incl. " .. U.money(res.tips) .. " tips)") or "") }
  if j.store ~= "sec" then
    local s = W.stores[j.store]
    for _, id in ipairs(Stores.staff(s)) do
      local n = W.npcs[id]
      n.p.f = n.p.f + (res.score > 60 and 2 or 0); n.p.t = n.p.t + (res.score - 50) / 12; n.p.met = true
      Social.clampP(n)
    end
    s.npcSales = (s.npcSales or 0) + res.score * 40
    s.pop = U.clamp(s.pop + (res.score - 60) / 40, 0, 100)
  end
  if sh.late then lines[#lines + 1] = "You were late. The boss noticed." end
  -- promotions
  if j.rank == 1 and j.worked >= 8 and j.perf >= 68 then
    Jobs.promote(2); lines[#lines + 1] = "You've been promoted to " .. Jobs.title() .. "!"
  elseif j.rank == 2 and j.worked >= 20 and j.perf >= 74 then
    Jobs.promote(3); lines[#lines + 1] = "You've been promoted to " .. Jobs.title() .. "!"
  end
  lines[#lines + 1] = res.text
  return table.concat(lines, "\n")
end

function Jobs.promote(rank)
  local j = W.p.job
  if not j then return end
  j.rank = rank
  j.wage = j.wage + 75 * (rank - 1)
  Timeline.add("job", W.p.name .. " was promoted to " .. Jobs.title() .. " at " .. Jobs.placeName() .. ".", 3)
  Rumors.add("promoted", -1, W.p.name .. " got promoted at " .. Jobs.placeName(), 4, W.p.friends)
  if rank == 4 and j.store ~= "sec" then
    local s = W.stores[j.store]
    s.playerManaged = true
    W.p.flags.manager = Clock.day(W.t)
  end
end

function Jobs.lose(why)
  local p = W.p
  if not p.job then return end
  local place = Jobs.placeName()
  p.firedFrom = p.firedFrom or {}
  if why ~= "quit" and why ~= "closed" then p.firedFrom[tostring(p.job.store)] = true end
  Timeline.add("job", W.p.name .. (why == "quit" and " quit " or " lost the job at ") .. place ..
    (why ~= "quit" and (" (" .. why .. ")") or "") .. ".", 3)
  if why ~= "quit" and why ~= "closed" then
    Rumors.add("fired", -1, W.p.name .. " got fired from " .. place, 6, W.p.friends)
    Pager.send("WORK", "DONT COME IN ANYMORE. PICK UP LAST CHECK FRI")
  end
  if p.job.store ~= "sec" then
    local s = W.stores[p.job.store]
    if s then s.playerManaged = nil end
  end
  p.job = nil
end

-- missed shifts turn into strikes
function Jobs.daily(day)
  local j = W.p.job
  if not j then return end
  for _, sh in ipairs(j.shifts) do
    if sh.day < day and not sh.done and not sh.missed then
      sh.missed = true
      j.strikes = j.strikes + 1
      j.perf = j.perf - 12
      if j.strikes >= 3 then
        Jobs.lose("no-call no-show")
        return
      else
        Pager.send("WORK", "WHERE WERE U " .. Clock.DAYS[Clock.date(sh.day).wd + 1] .. "? STRIKE " .. j.strikes)
      end
    end
  end
  if Clock.info(day).wd == 0 then Jobs.schedule(day) end
end
