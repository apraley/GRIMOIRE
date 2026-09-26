-- Exploration: walk the mall in real time. One game minute passes per
-- second. Doors, escalators, NPCs, objects; chases (security, Mom); the HUD
-- and the crank-driven pager ticker.

Explore = {}
local T = MallGen.TILE
local FPM = 30                -- frames per game minute
Explore.FPM = FPM

local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

local ex = { overlay = false }
Explore.scene = ex

function Explore.start()
  ex.frames = 0
  ex.camx, ex.camy = 0, 0
  ex.walk = 0
  ex.bubbles = {}
  ex.fade = 0
  ex.chase = nil
  ex.pagerY = -60
  ex.pagerIdx = 0
  ex.pagerCrank = Input.crankStepper(25)
  ex.lastArea = nil
  Scene.reset(ex)
  Explore.arrive(W.p.area, true)
end

-- ------------------------------------------------------------------ helpers
local function tileAt(a, px, py) return Areas.get(a, px // T, py // T) end
local function walkableAt(a, px, py) return Areas.WALKABLE[tileAt(a, px, py)] == true end

local function canStand(a, x, y)
  return walkableAt(a, x - 5, y - 2) and walkableAt(a, x + 5, y - 2) and walkableAt(a, x - 5, y) and walkableAt(a, x + 5, y)
end

function Explore.area() return MapView.area end

-- how far into the current world minute the display is (0..1)
function Explore.sub() return (ex.frames % FPM) / FPM end

function Explore.npcPos(n)
  local a, x, y, moving, dir = NPCAI.pos(n, Explore.sub())
  return x or 0, y or 0, moving, dir
end

function Explore.bubble(n, txt, frames)
  ex.bubbles[#ex.bubbles + 1] = { n = n, txt = txt, t = frames or 75 }
end

-- ------------------------------------------------------------------ travel
function Explore.go(to, px, py, quiet)
  local p = W.p
  local from = p.area
  ex.lastArea = from
  p.area = to
  p.x, p.y = px, py
  ex.fade = 10
  -- companion comes along
  local c = p.companion and W.npcs[p.companion]
  if c then c.loc = to; c.route = nil; c.x, c.y = px - 14, py; c.dest = to end
  if ex.chase then
    ex.chase.hops = (ex.chase.hops or 0) + 1
    ex.chase.delay = 45
  end
  Explore.arrive(to, quiet)
end

-- things that happen when entering an area
function Explore.arrive(to, quiet)
  local p = W.p
  MapView.prepare(to)
  local a = MapView.area
  if not canStand(a, p.x, p.y) then
    -- nudge onto walkable ground
    for r = 1, 6 do
      local done = false
      for _, d in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
        local nx, ny = p.x + d[1] * r * 8, p.y + d[2] * r * 8
        if canStand(a, nx, ny) then p.x, p.y = nx, ny; done = true break end
      end
      if done then break end
    end
  end
  if quiet then return end
  local firsts = { v1 = "svc", v2 = "svc", ab = "ab", roof = "roof", tun = "tun", shel = "shel", off = "off", lock = "lock" }
  local lk = firsts[to]
  if lk and Lore.discover(lk) then
    local title, txt = Lore.noteText(lk)
    Say({ title:upper(), txt }, {})
  end
  -- staff-only spaces
  if (to == "v1" or to == "v2" or to:match("^b%d") or to == "dock" or to == "maint") and not Explore.staffOK(to) then
    local n = Security.trespass(to)
    if n then
      Explore.bubble(n, "HEY!", 60)
      Say("\"Employees only, kid. Out.\"", { npc = n, name = n.first, mood = "angry", after = function()
        if (p.trespass or 0) >= 3 then
          p.mallBan = Clock.day(W.t) + 1
          p.trespass = 0
          Timeline.add("crime", p.name .. " got escorted out of the mall for wandering the service halls.", 2)
          Say("Security walks you out to the parking lot. \"See you tomorrow. Maybe.\"", { after = function()
            Explore.go("lot", 20 * T, 4 * T, true)
          end })
        elseif ex.lastArea then
          local pa, _, _, px, py = Areas.portal(to)
          if pa then Explore.go(pa, px * T + 8, py * T + 12, true) end
        end
      end })
    end
  end
  -- banned from the mall: security at the doors
  if to == "c1" and ex.lastArea == "lot" and Security.mallBanned() then
    Say("A guard at the entrance recognizes you. \"You're banned, remember? Beat it.\"", { after = function()
      Explore.go("lot", 20 * T, 4 * T, true)
    end })
  end
end

function Explore.staffOK(to)
  local p = W.p
  if not p.job then return false end
  if to == "maint" or to == "dock" then return p.job.store == "sec" or p.job.rank >= 3 end
  local num = to:match("^b(%d+)")
  if num then return p.job.store == tonumber(num) end
  return true
end

-- ------------------------------------------------------------------ doors
function Explore.useDoor(d)
  local p = W.p
  local to = d.to
  local here = p.area
  if d.lock and not p.keys[d.lock] then
    if d.lock == "shelter" and p.keys.pry then
      p.keys.shelter = true
      Say("You wedge the pry bar into the rusted door. It gives with a groan that echoes down the tunnel.")
    else
      Toast.show("Locked.")
      Explore.pushBack()
      return
    end
  end
  local tnum = to:match("^s(%d+)$")
  if tnum then
    local s = W.stores[tonumber(tnum)]
    local employee = p.job and p.job.store == s.id
    if not s.open then Toast.show("Vacant."); Explore.pushBack() return end
    if not Stores.isOpenAt(s, W.t) and not employee then
      local o = Stores.hours(s, Clock.day(W.t))
      Toast.show(o and ("CLOSED. Opens " .. Clock.hhmm(o)) or "CLOSED today.")
      Explore.pushBack()
      return
    end
    if Security.banned(s) then
      local staff = Stores.presentStaff(s)[1]
      if staff then Explore.bubble(staff, "NOPE.", 60) end
      Toast.show("You're banned from " .. s.name .. ".")
      Explore.pushBack()
      return
    end
  end
  -- mall closed at night
  if here == "lot" and to == "c1" then
    local info = Clock.info(Clock.day(W.t))
    local m = Clock.minute(W.t)
    if info.closed or m < info.walkersOpen or m >= info.close + 10 then
      Toast.show("The mall doors are locked.")
      Explore.pushBack()
      return
    end
  end
  -- walking out of a store with unpaid goods
  local hnum = here:match("^s(%d+)$")
  if hnum and p.hot and #p.hot > 0 and not to:match("^b") then
    local s = W.stores[tonumber(hnum)]
    local c = Security.exitCheck(s)
    if c then
      Explore.confront(s, c, d)
      return
    else
      Security.getaway(s)
      Toast.show("You walk out. Heart pounding.")
    end
  end
  Explore.go(to, d.tx * T + 8, d.ty * T + 12)
end

function Explore.pushBack()
  local p = W.p
  local d = DIRS[p.dir]
  p.x, p.y = p.x - d[1] * 10, p.y - d[2] * 10
end

-- ------------------------------------------------------------------ crime
function Explore.confront(s, c, d)
  local p = W.p
  local n = c.staff or (c.witness)
  local opener = ({
    alarm = "BEEEEP. The alarm gate screams. Everyone turns to look.",
    staff = "\"Hey. Hold up. I need to see your bag.\"",
    guard = "A security guard steps in front of you. \"Bag. Now.\"",
    tattle = "A customer points at you. \"That kid put something in their backpack!\"",
  })[c.how]
  Choose("BUSTED?", { "Hand it over", "Run for it", "\"I was gonna pay...\"" }, function(i)
    if i == 1 then
      local out = Security.caughtPlayer(s, "comply")
      Explore.consequences(out, n)
    elseif i == 2 then
      Explore.startChase(s, n, d)
    else
      local r = U.rng(W.seed, "lie", math.floor(W.t))
      local total = 0
      for _, it in ipairs(p.hot) do total = total + it.v end
      if c.how ~= "alarm" and r:chance(0.25 + p.conf / 250) and p.money >= total then
        p.money = p.money - total
        s.npcSales = (s.npcSales or 0) + total
        for _, it in ipairs(p.hot) do it.from = "bought"; it.tagged = nil; Econ.give(it) end
        p.hot = {}; p.heat = nil
        s.suspicion = 100
        Say({ "\"...Right. The register's over there.\"", "You pay " .. U.money(total) .. ". They watch you the whole time." },
          { npc = n, name = n and n.first })
      else
        local out = Security.caughtPlayer(s, "comply")
        Explore.consequences(out, n)
      end
    end
  end, { prompt = opener, npc = n, y = 90 })
end

function Explore.consequences(out, n)
  local lines = {}
  for _, l in ipairs(out.lines) do lines[#lines + 1] = l end
  if out.storeBan > 0 then lines[#lines + 1] = "Banned from the store for " .. out.storeBan .. " days." end
  if out.mallBan > 0 then lines[#lines + 1] = "Banned from the mall for " .. out.mallBan .. " days." end
  if out.parents then lines[#lines + 1] = "Your mom is on her way. You are grounded." end
  Say(lines, { npc = n, name = n and n.first, mood = "angry", after = function()
    if out.mallBan > 0 or out.parents then
      Day.endDay(out.parents and "parents" or "banned")
    end
  end })
end

function Explore.startChase(s, n, d)
  local p = W.p
  local guard
  local list = NPCAI.inArea(p.area)
  for _, g in ipairs(W.mall.security) do
    local gn = W.npcs[g]
    if gn.status == "active" and gn.loc and gn.loc ~= "home" then guard = gn break end
  end
  local chaser = n or guard
  if not chaser then chaser = W.npcs[W.mall.security[1]] end
  ex.chase = { n = chaser, x = p.x, y = p.y + 20, store = s.id, hops = 0, delay = 20, t = 0 }
  chaser.held = true
  Toast.show("RUN!", 60)
  Explore.go(d.to, d.tx * T + 8, d.ty * T + 12, true)
end

-- ------------------------------------------------------------------ interaction
local function frontPoint()
  local p = W.p
  local d = DIRS[p.dir]
  return p.x + d[1] * 14, p.y - 6 + d[2] * 14
end

function Explore.findNPC()
  local p = W.p
  local fx, fy = frontPoint()
  local best, bd = nil, 26
  for _, n in ipairs(NPCAI.inArea(p.area)) do
    if n.id ~= p.companion or true then
      local x, y = Explore.npcPos(n)
      local d = U.dist(fx, fy, x, y - 8)
      if d < bd then best, bd = n, d end
    end
  end
  return best
end

function Explore.findObj()
  local p = W.p
  local a = MapView.area
  local fx, fy = frontPoint()
  local tx, ty = fx // T, fy // T
  for _, o in ipairs(a.objs) do
    if o.kind ~= "sign" and o.kind ~= "camera" and o.kind ~= "gate" and o.kind ~= "car" and o.kind ~= "planter" then
      if tx >= o.x and tx < o.x + o.w and ty >= o.y and ty < o.y + o.h then return o end
    end
  end
  -- objects behind a counter tile: look one tile further
  local d = DIRS[p.dir]
  tx, ty = (fx + d[1] * T) // T, (fy + d[2] * T) // T
  for _, o in ipairs(a.objs) do
    if o.kind == "counter" or o.kind == "stall" or o.kind == "booth" or o.kind == "concession" then
      if tx >= o.x and tx < o.x + o.w and ty >= o.y and ty < o.y + o.h then return o end
    end
  end
end

function Explore.interact()
  local n = Explore.findNPC()
  if n then Dialog.open(n) return end
  local o = Explore.findObj()
  if o then Interact.object(o) return end
end

-- ------------------------------------------------------------------ update
function ex:update()
  local p = W.p
  -- world clock
  self.frames = self.frames + 1
  if self.frames % FPM == 0 then
    WorldSim.tick(1)
    Explore.minute()
    if Scene.top() ~= self then return end
  end
  -- movement
  local dx, dy = 0, 0
  if In.lh then dx = -1 elseif In.rh then dx = 1 end
  if In.uh then dy = -1 elseif In.dh then dy = 1 end
  local a = MapView.prepare(p.area)
  if dx ~= 0 or dy ~= 0 then
    if dx ~= 0 then p.dir = dx < 0 and "left" or "right" else p.dir = dy < 0 and "up" or "down" end
    local sp = (p.energy < 15) and 2 or 3
    local nx, ny = p.x + dx * sp, p.y + dy * sp
    if canStand(a, nx, p.y) then p.x = nx end
    if canStand(a, p.x, ny) then p.y = ny end
    self.walk = self.walk + 1
    -- doors and escalators under our feet
    local tx, ty = p.x // T, (p.y - 2) // T
    local code = Areas.get(a, tx, ty)
    if code == Areas.DOOR then
      for _, d in ipairs(a.doors) do
        if d.x == tx and d.y == ty then Explore.useDoor(d) break end
      end
    elseif code == Areas.ESC then
      for _, o in ipairs(a.objs) do
        if o.kind == "escalator" and tx >= o.x and tx < o.x + o.w and ty >= o.y and ty < o.y + o.h then
          Explore.go(o.to, o.ax * T + 8, o.ay * T + 12)
          Sfx.blip(440, 0.1)
          break
        end
      end
    end
  else
    self.walk = 0
  end
  if In.a then Explore.interact() end
  if In.b then Menu.open() end
  -- crank: pager ticker
  local steps = self.pagerCrank(In.crank)
  if steps ~= 0 or (not In.docked and math.abs(In.crank) > 1) then
    self.pagerShow = 60
    if steps ~= 0 and #p.pager > 0 then
      self.pagerIdx = U.clamp(self.pagerIdx + steps, 0, #p.pager - 1)
      local m = p.pager[#p.pager - self.pagerIdx]
      if m then m.read = true end
      Sfx.tick()
    end
  end
  if self.pagerShow and self.pagerShow > 0 then
    self.pagerShow = self.pagerShow - 1
    self.pagerY = math.min(22, self.pagerY + 8)
  else
    self.pagerY = math.max(-60, self.pagerY - 8)
  end
  Explore.updateChase()
  -- camera
  local tw, th = a.w * T, a.h * T
  self.camx = U.clamp(p.x - 200, 0, math.max(0, tw - 400))
  -- the HUD covers the top 20px: let the camera show the top row fully when
  -- you're near it, and the bottom row (where exits are) when you're near that
  self.camy = U.clamp(p.y - 124, -22, math.max(-22, th - 240))
  if tw < 400 then self.camx = (tw - 400) // 2 end
  if th <= 216 then self.camy = (th - 220) // 2 - 20 end
  for i = #self.bubbles, 1, -1 do
    local b = self.bubbles[i]
    b.t = b.t - 1
    if b.t <= 0 then table.remove(self.bubbles, i) end
  end
  if self.fade > 0 then self.fade = self.fade - 1 end
  if Toast.t > 0 then Toast.t = Toast.t - 1 end
  if Pager.flash and Pager.flash > 0 then Pager.flash = Pager.flash - 1 end
end

-- once per game minute
function Explore.minute()
  local p = W.p
  local m = Clock.minute(W.t)
  local day = Clock.day(W.t)
  local info = Clock.info(day)
  -- closing time
  if (p.area == "c1" or p.area == "c2" or p.area == "fc" or p.area:match("^s%d")) and m >= info.close + 20 and
    not (p.area == "s" .. W.mall.cinema) and not ex.closingNag then
    ex.closingNag = true
    local g = W.npcs[W.mall.security[1]]
    Say("\"Mall's closed, folks. Let's go, let's go.\" A guard herds everyone toward the exits.",
      { npc = g, name = "SECURITY", after = function() Explore.go("lot", 20 * T, 4 * T, true) end })
  end
  if m < info.close then ex.closingNag = false end
  -- companion time
  if p.companion then
    local c = W.npcs[p.companion]
    if not c or W.t > (p.companionUntil or 0) then
      if c then
        c.held = nil
        Explore.bubble(c, "Gotta go. This was fun!", 90)
        Memory.add(c, "hungout", "hung out with " .. p.name, -1)
      end
      p.companion = nil
    else
      c.p.f = U.clamp(c.p.f + 0.15, -100, 100)
      c.p.last = day
      if c.p.a > 10 and NPCGen.romanceOK(c, { id = -1, age = p.age }) then c.p.a = U.clamp(c.p.a + 0.1, 0, 100) end
    end
  end
  -- invitations from friends: are they here?
  for _, inv in ipairs(p.invites) do
    if inv.day == day and not inv.met and m >= inv.s - 10 and m <= inv.e and inv.a == p.area then
      local n = W.npcs[inv.npc]
      if n and n.loc == p.area and not n.route then
        inv.met = true
        n.p.f = U.clamp(n.p.f + 6, -100, 100)
        Explore.bubble(n, "You came!", 90)
        p.companion = n.id; p.companionUntil = W.t + 60; n.held = true
        Memory.add(n, "showedup", p.name .. " showed up like they said", -1)
      end
    end
  end
  -- Mom
  local mom = PlayerSim.momChase()
  if mom and mom.loc == p.area and not ex.momSeen then
    ex.momSeen = true
    ex.mom = { n = mom, x = p.x + 160, y = p.y }
    local a = MapView.area
    local pa, x, y = Areas.portal(p.area)
    if x then ex.mom.x, ex.mom.y = x * T + 8, y * T + 8 end
  end
  -- a guard notices a nervous kid with a full backpack
  if p.hot and #p.hot > 0 and not ex.chase then
    for _, n in ipairs(NPCAI.inArea(p.area)) do
      if n.job == "sec" and not n.route then
        local x, y = Explore.npcPos(n)
        if U.dist(x, y, p.x, p.y) < 70 then
          local sid = p.heat and p.heat.store
          local s = sid and W.stores[sid]
          if s then
            Explore.confront(s, { how = "guard", staff = n, store = sid }, { to = p.area, tx = p.x // T, ty = p.y // T })
            return
          end
        end
      end
    end
  end
  -- security remembers the tape
  if (p.wanted or 0) > 0 and not ex.chase then
    for _, n in ipairs(NPCAI.inArea(p.area)) do
      if n.job == "sec" and not n.route then
        local x, y = Explore.npcPos(n)
        if U.dist(x, y, p.x, p.y) < 50 then
          p.wanted = p.wanted - 1
          local ev
          for _, e in ipairs(p.evidence) do if e.known and not e.served then ev = e end end
          local s = ev and W.stores[ev.store]
          if ev then ev.served = true end
          if s then
            Say({ "\"Hold on. We've got you on tape at " .. s.name .. ". Come with me.\"" }, { npc = n, name = n.first, mood = "angry",
              after = function() Explore.consequences(Security.caughtPlayer(s, "tape"), n) end })
            return
          end
        end
      end
    end
  end
  -- ambient chatter: people who know you say hi
  if ex.frames % (FPM * 3) == 0 then
    local list = NPCAI.inArea(p.area)
    local r = U.rng(W.t, "hi")
    for _ = 1, 2 do
      local n = list[r:i(1, math.max(1, #list))]
      if n and not n.route and n.p.met then
        local x, y = Explore.npcPos(n)
        if U.dist(x, y, p.x, p.y) < 120 then
          Explore.bubble(n, Talk.ambient(n), 80)
          break
        end
      end
    end
  end
  -- curfew + mall ban
  if p.mallBan and p.mallBan > day and (p.area ~= "lot") then
    -- banned mid-visit (just got banned): handled by consequences
  end
end

function Explore.updateChase()
  local p = W.p
  -- Mom walks straight at you
  if ex.mom then
    local m = ex.mom
    local d = U.dist(m.x, m.y, p.x, p.y)
    if d > 3 then
      m.x = m.x + (p.x - m.x) / d * 2.2
      m.y = m.y + (p.y - m.y) / d * 2.2
    end
    if d < 18 then
      ex.mom = nil
      ex.momSeen = false
      PlayerSim.momCaught()
      local mom = W.npcs[p.mom]
      Say({ "\"THERE you are. Do you know what time it is?\"", "She steers you toward the exit by the backpack strap. Everyone sees." },
        { npc = mom, name = "MOM", mood = "angry", after = function() Day.endDay("mom") end })
      return
    end
    if W.npcs[p.mom].loc ~= p.area and not W.npcs[p.mom].route then ex.mom = nil; ex.momSeen = false end
  end
  local c = ex.chase
  if not c then return end
  c.t = c.t + 1
  if c.delay > 0 then
    c.delay = c.delay - 1
    if c.delay == 0 then
      local pa, x, y = Areas.portal(p.area)
      c.x, c.y = p.x + (x and 0 or 0), p.y + 40
      if ex.lastArea then
        for _, d in ipairs(MapView.area.doors) do
          if d.to == ex.lastArea then c.x, c.y = d.x * T + 8, d.y * T + 8 break end
        end
      end
    end
    return
  end
  local d = U.dist(c.x, c.y, p.x, p.y)
  local sp = 2.6 + math.min(1, c.t / 300)
  if d > 2 then
    c.x = c.x + (p.x - c.x) / d * sp
    c.y = c.y + (p.y - c.y) / d * sp
  end
  local s = W.stores[c.store]
  if d < 14 then
    ex.chase = nil
    c.n.held = nil
    local out = Security.caughtPlayer(s, "caught")
    Explore.consequences(out, c.n)
  elseif c.hops >= 3 or p.area == "lot" or c.t > 30 * 40 then
    ex.chase = nil
    c.n.held = nil
    Security.getaway(s)
    s.suspicion = 100
    W.p.bans[tostring(s.id)] = Clock.day(W.t) + 60
    Rumors.add("shoplift", -1, W.p.name .. " ran out of " .. s.name .. " with security on their heels", 7, Stores.staff(s), { store = s.id })
    Toast.show("You lost them.", 90)
  end
end

-- ------------------------------------------------------------------ draw
local function drawBubble(x, y, txt)
  local w = math.min(160, Gfx.textW(txt) + 12)
  local lines = Gfx.wrap(txt, w - 10)
  local h = #lines * 16 + 6
  local bx = U.clamp(x - w // 2, 2, 398 - w)
  local by = y - h - 30
  Gfx.fill(bx, by, w, h, "white")
  Gfx.rect(bx, by, w, h)
  playdate.graphics.fillTriangle(x - 4, by + h - 1, x + 4, by + h - 1, x, by + h + 5)
  for i, l in ipairs(lines) do Gfx.text(l, bx + 6, by + 2 + (i - 1) * 16) end
end

function ex:draw(isTop)
  local gfx = playdate.graphics
  local p = W.p
  local a = MapView.prepare(p.area)
  Gfx.clear("black")
  local cx, cy = math.floor(self.camx), math.floor(self.camy)
  gfx.setDrawOffset(-cx, -cy)
  MapView.img:draw(0, 0)
  MapView.drawDynamic(a, cx, cy)
  -- entities sorted by y
  local ents = {}
  for _, n in ipairs(NPCAI.inArea(p.area)) do
    if n.id ~= p.companion then
      local x, y, moving, dir = Explore.npcPos(n)
      if not moving then
        -- idle fidget
        local ph = (Gfx.frame + n.id * 17) % 240
        if ph < 20 then x = x + ((n.id % 2 == 0) and 1 or -1) end
        dir = (U.dist(x, y, p.x, p.y) < 48) and ((math.abs(p.x - x) > math.abs(p.y - y)) and (p.x > x and "right" or "left") or (p.y > y and "down" or "up"))
          or n.idleDir or "down"
      end
      if x > cx - 20 and x < cx + 420 and y > cy - 10 and y < cy + 270 then
        ents[#ents + 1] = { y = y, x = x, lk = n.look, dir = dir or "down", fr = moving and ((Gfx.frame // 6 + n.id) % 2 + 1) or 0, n = n }
      end
    end
  end
  -- the anonymous crowd
  Crowd.each(p.area, cx, function(x, y, lk, dir, fr)
    if y > cy - 10 and y < cy + 270 then ents[#ents + 1] = { y = y, x = x, lk = lk, dir = dir, fr = fr } end
  end, Explore.sub())
  local comp = p.companion and W.npcs[p.companion]
  if comp then
    local d = DIRS[p.dir]
    local tx, ty = p.x - d[1] * 18 - (d[2] ~= 0 and 12 or 0), p.y - d[2] * 14
    comp.x = comp.x and U.lerp(comp.x, tx, 0.15) or tx
    comp.y = comp.y and U.lerp(comp.y, ty, 0.15) or ty
    ents[#ents + 1] = { y = comp.y, x = comp.x, lk = comp.look, dir = p.dir, fr = self.walk > 0 and ((Gfx.frame // 6) % 2 + 1) or 0, n = comp }
  end
  if ex.mom then ents[#ents + 1] = { y = ex.mom.y, x = ex.mom.x, lk = W.npcs[p.mom].look, dir = "down", fr = (Gfx.frame // 5) % 2 + 1, mom = true } end
  if ex.chase and ex.chase.delay == 0 then
    ents[#ents + 1] = { y = ex.chase.y, x = ex.chase.x, lk = ex.chase.n.look, dir = "down", fr = (Gfx.frame // 4) % 2 + 1, chaser = true }
  end
  local plk = p.look or { hair = 0, hc = 0, shirt = 2, pants = 1, skin = 0, acc = 0 }
  ents[#ents + 1] = { y = p.y, x = p.x, lk = plk, dir = p.dir, fr = self.walk > 0 and ((self.walk // 6) % 2 + 1) or 0, player = true }
  table.sort(ents, function(e1, e2) return e1.y < e2.y end)
  for _, e in ipairs(ents) do
    Sprites.draw(e.lk, e.x, e.y, e.dir, e.fr)
    if e.player and p.hot and #p.hot > 0 then
      -- sweat drop when carrying unpaid goods
      if (Gfx.frame // 8) % 2 == 0 then Gfx.circle(e.x + 8, e.y - 26, 2, true) end
    end
    if e.chaser or e.mom then Gfx.text("!", e.x - 2, e.y - 42, { bold = true }) end
  end
  -- dark places
  if a.kind == "tunnel" or a.kind == "shelter" or (a.kind == "roof" and Clock.minute(W.t) > 19 * 60 + 30) then
    local lx, ly = p.x, p.y - 12
    gfx.setPattern(Gfx.P.darker)
    gfx.fillRect(cx, cy, 400, ly - 70 - cy)
    gfx.fillRect(cx, ly + 70, 400, 240)
    gfx.fillRect(cx, ly - 70, lx - 90 - cx, 140)
    gfx.fillRect(lx + 90, ly - 70, 400, 140)
    gfx.setPattern(Gfx.P.dark)
    gfx.fillRect(lx - 90, ly - 70, 180, 14); gfx.fillRect(lx - 90, ly + 56, 180, 14)
    gfx.setColor(gfx.kColorBlack)
  end
  -- speech bubbles
  for _, b in ipairs(self.bubbles) do
    local x, y = Explore.npcPos(b.n)
    if b.n.id == p.companion then x, y = b.n.x, b.n.y end
    if b.n.loc == p.area or b.n.id == p.companion then drawBubble(x - cx, y - cy, b.txt) end
  end
  gfx.setDrawOffset(0, 0)
  if self.fade > 0 then
    gfx.setDitherPattern(self.fade / 10, gfx.image.kDitherTypeBayer4x4)
    gfx.fillRect(0, 0, 400, 240)
    gfx.setColor(gfx.kColorBlack)
  end
  Explore.hud(isTop)
end

function Explore.hud(isTop)
  local p = W.p
  local gfx = playdate.graphics
  Gfx.fill(0, 0, 400, 20, "black")
  local day = Clock.day(W.t)
  local dt = Clock.date(day)
  Gfx.text(Clock.DAYS[dt.wd + 1] .. " " .. Clock.MONTHS[dt.m] .. " " .. dt.d .. "  " .. Clock.hhmm(Clock.minute(W.t)), 6, 2, { white = true, bold = true })
  local an = Areas.name(p.area)
  while #an > 3 and Gfx.textW(an) > 128 do an = an:sub(1, #an - 1) end
  if an ~= Areas.name(p.area) then an = an .. "." end
  Gfx.text(an, 228, 2, { white = true, align = "center" })
  Gfx.text(U.money(p.money), 394, 2, { white = true, align = "right", bold = true })
  -- pager icon
  local unread = Pager.unread()
  if unread > 0 then
    local blink = (Pager.flash or 0) > 0 and (Gfx.frame // 4) % 2 == 0
    Gfx.fill(300, 3, 22, 14, blink and "black" or "white")
    Gfx.rect(300, 3, 22, 14, blink and "white" or "black")
    Gfx.text(tostring(unread), 311, 2, { align = "center", white = blink })
  end
  -- low needs
  if p.hunger > 70 then Gfx.box(4, 206, 90, 30, "light"); Gfx.text("HUNGRY", 49, 212, { align = "center", bold = true }) end
  if p.energy < 20 then Gfx.box(98, 206, 90, 30, "light"); Gfx.text("TIRED", 143, 212, { align = "center", bold = true }) end
  if p.hot and #p.hot > 0 then Gfx.box(4, 24, 120, 26, "dark"); Gfx.text("UNPAID ITEMS", 64, 29, { white = true, align = "center" }) end
  if ex.chase then Gfx.box(140, 24, 120, 26, "dark"); Gfx.text("RUN!", 200, 29, { white = true, align = "center", bold = true }) end
  -- context prompt
  if isTop then
    local n = Explore.findNPC()
    if n then Gfx.prompt("A: Talk to " .. n.first)
    else
      local o = Explore.findObj()
      if o then Gfx.prompt("A: " .. Interact.label(o)) end
    end
  end
  if Toast.t > 0 and Toast.msg then
    Gfx.box(60, 96, 280, 40, "dark")
    Gfx.text(Toast.msg, 200, 107, { white = true, align = "center" })
  end
  -- pager ticker (crank)
  local y = ex.pagerY
  if y > -58 then
    Gfx.fill(250, y, 146, 56, "black")
    Gfx.fill(254, y + 4, 138, 38, "light")
    Gfx.rect(254, y + 4, 138, 38)
    local m = p.pager[#p.pager - ex.pagerIdx]
    if m then
      Gfx.text(m.from .. " " .. Clock.hhmm(Clock.minute(m.t)), 258, y + 4, { bold = true })
      Gfx.text(m.txt:sub(1, 20), 258, y + 22)
    else
      Gfx.text("NO MESSAGES", 258, y + 12)
    end
    Gfx.text((ex.pagerIdx + 1) .. "/" .. math.max(1, #p.pager), 392, y + 42, { white = true, align = "right" })
  end
end
