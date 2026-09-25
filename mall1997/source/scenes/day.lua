-- The shape of a day: morning choice, going to the mall, leaving (bus, Mom,
-- getting kicked out), the night summary, sleep (the world keeps running),
-- and time skips with a progress card.

Day = {}
local T = MallGen.TILE

-- ------------------------------------------------------------------ skip
-- Advance the world to time t over several frames (coroutine), then call after.
function Day.skipTo(t, label, after)
  local sc = { overlay = false, label = label or "...", start = W.t, target = t }
  sc.co = coroutine.create(function() WorldSim.advance(t, 3, 4) end)
  function sc:update()
    if coroutine.status(self.co) ~= "dead" then
      local ok, err = coroutine.resume(self.co)
      if not ok then error(err) end
    end
    if coroutine.status(self.co) == "dead" then
      Scene.pop()
      if after then after() end
    end
  end
  function sc:draw()
    Gfx.clear("black")
    Gfx.box(80, 80, 240, 80, "dark")
    Gfx.text(self.label, 200, 96, { white = true, align = "center", bold = true })
    Gfx.text(Clock.hhmm(Clock.minute(W.t)), 200, 122, { white = true, align = "center" })
    local f = (self.target > self.start) and (W.t - self.start) / (self.target - self.start) or 1
    Gfx.meter(100, 146, 200, 6, f, nil, true)
  end
  Scene.push(sc)
end

-- ------------------------------------------------------------------ leaving
local REASONS = {
  bus = "You take the 6 bus home. Someone's Walkman leaks through their headphones the whole way.",
  mom = "Silent car ride home. The radio is off. That's how you know.",
  pickup = "Mom picks you up by the entrance. \"How was the mall?\" \"Fine.\"",
  banned = "Security walks you to the lot. You wait for the bus in the dark.",
  parents = "Mom drives you home from the security office. She doesn't say a word until the driveway.",
  closing = "The lights go off row by row as you walk to the bus.",
}

function Day.endDay(reason)
  local p = W.p
  p.atMall = false
  local day = Clock.day(W.t)
  local m = Clock.minute(W.t)
  -- late?
  local late = m > PlayerSim.curfew(day) + 5 and reason ~= "mom" and reason ~= "parents"
  if late then
    p.grounded = math.max(p.grounded or 0, day + 2)
    Timeline.add("player", p.name .. " got home late. Grounded.", 1)
  end
  if p.companion then
    local c = W.npcs[p.companion]
    if c then c.held = nil; Memory.add(c, "hungout", "hung out with " .. p.name, -1) end
    p.companion = nil
  end
  -- unpaid goods go home with you
  if p.hot and #p.hot > 0 then
    local s = W.stores[p.heat and p.heat.store or 0]
    if s then Security.getaway(s) end
  end
  local mom = W.npcs[p.mom]
  if mom then mom.hunting = nil; mom.route = nil; mom.loc = "home" end
  p.stats.days = p.stats.days + 1
  p.area = "home"
  local lines = { REASONS[reason] or REASONS.bus }
  if late then lines[#lines + 1] = "You're late. Grounded for two days." end
  Day.night(lines)
end

-- ------------------------------------------------------------------ night
function Day.night(lines)
  local p = W.p
  local day = Clock.day(W.t)
  local sc = { overlay = false, page = 0 }
  local summary = {}
  for _, l in ipairs(lines) do summary[#summary + 1] = l end
  -- what happened today
  local today = {}
  for i = #W.timeline, 1, -1 do
    local e = W.timeline[i]
    if Clock.day(e.t) < day then break end
    if e.imp >= 2 then today[#today + 1] = e.txt end
    if #today >= 6 then break end
  end
  sc.summary, sc.today = summary, today
  function sc:update()
    if In.a then
      Scene.pop()
      Day.sleep()
    end
  end
  function sc:draw()
    Gfx.clear("black")
    -- bedroom window: night sky + mall glow on the horizon
    for i = 0, 30 do
      local x, y = (i * 53) % 400, (i * 29) % 70
      Gfx.fill(x, y, 1, 1, "white")
    end
    Gfx.neon(0, 72, 400, 3, 2)
    Gfx.box(10, 80, 380, 156, "dark")
    Gfx.text(Clock.dateStr(day) .. " — NIGHT", 22, 88, { white = true, bold = true })
    local y = 110
    for _, l in ipairs(self.summary) do y = y + Gfx.para(l, 22, y, 356, { white = true, maxLines = 2 }) end
    if #self.today > 0 then
      Gfx.text("AROUND THE MALL TODAY:", 22, y + 2, { white = true, bold = true })
      y = y + 20
      for i, t in ipairs(self.today) do
        if y > 206 then break end
        Gfx.text("- " .. t:sub(1, 52), 22, y, { white = true })
        y = y + 16
      end
    end
    Gfx.text("A: sleep", 380, 218, { white = true, align = "right" })
  end
  Scene.push(sc)
end

function Day.sleep()
  local day = Clock.day(W.t)
  local target = (day + 1) * 1440 + 7 * 60
  W.p.energy = 100
  W.p.hunger = 30
  W.p.curfewShift = 0
  Day.skipTo(target, "Sleeping...", function()
    Save.write()
    Day.morning()
  end)
end

-- ------------------------------------------------------------------ morning
function Day.morning()
  local p = W.p
  local day = Clock.day(W.t)
  local info = Clock.info(day)
  local lines = {}
  local notes = {}
  if info.holiday then notes[#notes + 1] = info.holiday .. "." end
  if info.closed then notes[#notes + 1] = "The mall is closed today." end
  if info.school then notes[#notes + 1] = "School day." elseif info.summer then notes[#notes + 1] = "Summer vacation." else notes[#notes + 1] = "No school!" end
  if (p.grounded or 0) > day then notes[#notes + 1] = "You're grounded." end
  if Security.mallBanned() then notes[#notes + 1] = "You're banned from the mall until " .. Clock.shortDate(p.mallBan) .. "." end
  local sh = p.job and Jobs.shiftToday()
  if sh then notes[#notes + 1] = "You work " .. Clock.hhmm(sh.s) .. "-" .. Clock.hhmm(sh.e) .. "." end
  local unread = Pager.unread()
  if unread > 0 then notes[#notes + 1] = unread .. " new page" .. (unread > 1 and "s" or "") .. "." end
  local opts, acts = {}, {}
  local function add(l, f) opts[#opts + 1] = l; acts[#acts + 1] = f end
  local banned = Security.mallBanned() or info.closed
  local grounded = (p.grounded or 0) > day
  if not banned then
    if info.school then
      add(grounded and "Go after school (sneak)" or "Mall after school (3:30)", function() Day.go(15 * 60 + 30, grounded) end)
      add("Skip school, go at 10", function() Day.skip(grounded) end)
    else
      local o = info.open
      add((grounded and "Sneak out: " or "Go at ") .. Clock.hhmm(o), function() Day.go(o, grounded) end)
      add((grounded and "Sneak out: " or "Go at ") .. "1:00PM", function() Day.go(13 * 60, grounded) end)
      add((grounded and "Sneak out: " or "Go at ") .. "5:00PM", function() Day.go(17 * 60, grounded) end)
    end
  end
  add("Stay home", function() Day.stayHome() end)
  add("Pager", function() Menu.open("PAGER") end)
  local sc = { overlay = false, notes = notes }
  function sc:resume() end
  function sc:update()
    if not self.asked then
      self.asked = true
      Choose(nil, opts, function(i) acts[i]() end, { x = 200, y = 120, w = 196, cancel = function() self.asked = false end })
    end
  end
  function sc:draw()
    local dt = Clock.date(day)
    Gfx.clear()
    Gfx.fill(0, 0, 400, 240, "lighter")
    -- a wall calendar
    Gfx.box(14, 14, 170, 150, "light")
    Gfx.fill(20, 20, 158, 26, "black")
    Gfx.text(Clock.MONTH_NAMES[dt.m]:upper() .. " " .. dt.y, 99, 24, { white = true, bold = true, align = "center" })
    Gfx.text(tostring(dt.d), 99, 64, { bold = true, align = "center" })
    Gfx.text(Clock.DAY_NAMES[dt.wd + 1], 99, 90, { align = "center" })
    if Clock.info(day).holiday then Gfx.text(Clock.info(day).holiday, 99, 120, { align = "center", bold = true }) end
    Gfx.box(14, 168, 170, 64, "dark")
    local yy = 174
    for i = 1, #self.notes do
      if yy < 222 then Gfx.text(self.notes[i]:sub(1, 24), 22, yy, { white = true }); yy = yy + 16 end
    end
    Gfx.box(196, 14, 200, 100, "dark")
    Gfx.text(W.mall.name, 296, 22, { white = true, bold = true, align = "center" })
    Gfx.text(U.money(p.money) .. " in your pocket", 296, 44, { white = true, align = "center" })
    Gfx.text("Curfew " .. Clock.hhmm(PlayerSim.curfew(day)), 296, 64, { white = true, align = "center" })
    Gfx.text(p.job and (Jobs.title() .. " @ " .. Jobs.placeName()):sub(1, 26) or "Unemployed", 296, 84, { white = true, align = "center" })
  end
  Scene.reset(sc)
end

function Day.go(arrive, sneaking)
  local p = W.p
  local day = Clock.day(W.t)
  local t = day * 1440 + arrive
  if sneaking then p.sneaking = day end
  Day.skipTo(math.max(t, W.t), "Taking the bus...", function()
    p.atMall = true
    p.area = "lot"
    p.x, p.y = 4 * T + 8, 19 * T + 8
    p.dir = "up"
    p.curfewFlags = { day = day }
    if sneaking then
      local r = U.rng(W.seed, "sneak", day)
      if r:chance(0.35) then
        -- Mom will notice and come looking early
        p.curfewShift = -(PlayerSim.curfew(day) - arrive - 60)
      end
    end
    Explore.start()
  end)
end

function Day.skip(grounded)
  local p = W.p
  local day = Clock.day(W.t)
  local r = U.rng(W.seed, "skipschool", day)
  if r:chance(0.35) then
    p.grounded = math.max(p.grounded or 0, day + 4)
    Timeline.add("player", "The school called " .. p.name .. "'s house about an absence.", 2)
    Pager.send("MOM", "SCHOOL CALLED. WE WILL TALK TONIGHT")
  end
  Day.go(10 * 60, grounded)
end

function Day.stayHome()
  local p = W.p
  local r = U.rng(W.seed, "home", Clock.day(W.t))
  p.energy = 100
  p.conf = U.clamp(p.conf + 2, 0, 100)
  local what = r:pick({ "You watch MTV for six hours. A video you like plays four times.", "You tape songs off the radio, cursing every DJ who talks over the intro.",
    "You play video games until your thumbs hurt.", "You call a friend and stay on the phone so long your dad needs the line.",
    "You reorganize your tapes by mood. Then by color.", "You do homework. Allegedly." })
  -- a friend calls
  for _, id in ipairs(p.friends) do
    local n = W.npcs[id]
    if n and n.status == "active" and r:chance(0.3) then n.p.f = U.clamp(n.p.f + 3, -100, 100); what = what .. " " .. n.first .. " calls. You talk about nothing for an hour." break end
  end
  p.area = "home"
  p.stats.days = p.stats.days + 0
  Day.skipTo(Clock.day(W.t) * 1440 + 21 * 60, "Staying home...", function() Day.night({ what }) end)
end
