-- Scripted end-to-end flows through the real UI (strict mock). Each flow
-- drives scenes with button presses and checks the game returns to the
-- mall afterward. usage: lua5.4 tools/flows.lua

PD_TOOLS_DIR = (arg[0]:match("(.*/)") or "./")
PD_SOURCE_DIR = PD_TOOLS_DIR .. "../source/"
PD_DATA_DIR = "/tmp/pdmock_flows/"
os.execute("rm -rf " .. PD_DATA_DIR)
dofile(PD_TOOLS_DIR .. "pdmock.lua")
import "main"

local B = { left = 1, right = 2, up = 4, down = 8, b = 16, a = 32 }
local n = 0
local function frame(btn, crank)
  n = n + 1
  local ok, err = xpcall(function() PDMOCK_FRAME(btn or 0, crank or 0) end, debug.traceback)
  if not ok then print("ERROR (frame " .. n .. "):\n" .. err); os.exit(1) end
end
local function press(btn, times) for _ = 1, times or 1 do frame(btn); frame(0) end end
local r = RNG.new(99)
-- press A (and random stuff inside minigames) until we're back in the mall
local function untilExplore(max, randomize)
  for i = 1, max or 20000 do
    if Scene.top() == Explore.scene then return true end
    if randomize and r:chance(0.5) then
      frame(({ 1, 2, 4, 8, 32, 0 })[r:i(1, 6)], r:chance(0.3) and r:range(-30, 30) or 0)
    else
      if i % 2 == 0 then frame(B.a) else frame(0) end
    end
  end
  return Scene.top() == Explore.scene
end
local results = {}
local function flow(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  local back = untilExplore(30000, true)
  results[#results + 1] = (ok and back) and ("ok   " .. name) or ("FAIL " .. name .. " " .. tostring(err or "did not return to explore"))
  print(results[#results])
end

-- boot: title -> new mall -> name -> generation -> intro -> mall
press(0, 25)
press(B.a)          -- "New mall" (no save yet)
press(0, 3)
press(B.a)          -- pick a name
for _ = 1, 2000 do if Scene.top() == Explore.scene then break end frame(B.a); frame(0) end
assert(Scene.top() == Explore.scene, "did not reach the mall")
print("booted: " .. W.mall.name .. ", " .. #W.stores .. " stores, " .. #W.npcs .. " people")
local p = W.p

local function goStore(typ)
  local s = Stores.byType(typ)[1]
  local a = Areas.build(Areas.storeArea(s))
  p.area = a.id; p.x, p.y = a.w * 8, (a.h - 3) * 16; Explore.arrive(a.id, true)
  return s, a
end
local function objOf(a, kind) for _, o in ipairs(a.objs) do if o.kind == kind then return o end end end

flow("browse + buy album", function()
  local s, a = goStore("music")
  p.money = 5000
  Shop.browse(s, objOf(a, "rack"))
  frame(0, 45); frame(0, 45)
  press(B.a)      -- buy?
  press(B.a)      -- Yes
  untilExplore(200)
  assert(U.count(p.stats.albums) >= 1, "album not bought")
end)

flow("conceal + walk out", function()
  local s, a = goStore("clothing")
  Shop.browse(s, objOf(a, "rack"))
  press(B.down)   -- conceal prompt
  press(B.a)      -- slip it in
  press(B.b)
  untilExplore(50)
  assert(#p.hot >= 1, "nothing concealed")
  local d = a.doors[1]
  Explore.useDoor(d)
end)

flow("talk: every option", function()
  local n
  for _, x in ipairs(W.npcs) do if x.status == "active" and x.age < 19 and x.loc ~= "home" then n = x break end end
  n = n or W.npcs[p.friends[1]]
  n.p.f, n.p.t, n.p.a = 60, 60, 60
  Econ.give({ k = "gift", n = "mood ring", v = 900 })
  for _, id in ipairs({ "chat", "gossip", "music", "joke", "compliment", "about", "mall", "askout", "tell", "give", "borrow", "invite" }) do
    Dialog.card = setmetatable({ n = n, overlay = true }, { __index = { draw = function() end, update = function() end } })
    Scene.push(Dialog.card)
    Dialog.run(n, id)
    untilExplore(400)
    while Scene.top() ~= Explore.scene do Scene.pop() end
  end
end)

flow("job interview + shift", function()
  local s = goStore("music")
  local m = W.npcs[s.mgr]
  m.p.f, m.p.t = 80, 80
  s.hiring = true
  Dialog.interview(m, s.id)
  untilExplore(200)
  if not p.job then Jobs.hire(s.id) end
  local day = Clock.day(W.t)
  local mm = Clock.minute(W.t)
  p.job.shifts[#p.job.shifts + 1] = { day = day, s = mm, e = math.min(mm + 120, 23 * 60) }
  Play.clockIn()
  press(B.a) -- start
end)

flow("arcade cabinet + initials", function()
  local s = W.stores[W.mall.arcade]
  local a = Areas.build("s" .. s.id)
  p.area = a.id; Explore.arrive(a.id, true)
  p.tokens = 10
  local cab
  for _, o in ipairs(a.objs) do if o.kind == "cab" and W.arcade.machines[o.machine].game == "tower" then cab = o end end
  Play.cabinet(cab)
  press(B.a) -- Play
end)

flow("prize wheel + tokens", function()
  p.tokens = 10; p.money = p.money + 500
  Play.tokenMachine(); press(B.a)
  untilExplore(100)
  Play.prizeWheel()
  for _ = 1, 20 do frame(0, 40) end
end)

flow("movie", function()
  local shows = CinemaSim.shows(Clock.day(W.t))
  local sh = shows[#shows]
  Econ.give({ k = "ticket", n = "ticket", v = 0, show = Clock.minute(W.t), screen = sh.screen, movie = sh.movie, day = Clock.day(W.t) })
  Play.screenDoor({ screen = sh.screen })
end)

flow("menu tabs", function()
  Menu.open()
  for _ = 1, 9 do press(B.a); press(B.b); press(B.right) end
  press(B.b); press(B.b)
end)

flow("bench, fountain, payphone", function()
  p.area = "c1"; Explore.arrive("c1", true)
  local a = Areas.build("c1")
  Interact.object(objOf(a, "bench")); press(B.a)
  untilExplore(300)
  Interact.object(objOf(a, "fountain")); press(B.down); press(B.a)
  untilExplore(300)
  p.money = p.money + 100
  Interact.object(objOf(a, "phone")); press(B.a); press(B.down); press(B.down); press(B.a)
end)

flow("secret places", function()
  p.keys.tunnel = true
  Secret.combo()
  local code = W.mall.combo
  for i = 1, 4 do
    local d = tonumber(code:sub(i, i))
    for _ = 1, d do press(B.up) end
    if i < 4 then press(B.right) end
  end
  press(B.a)
  untilExplore(200)
  assert(p.area == "lock", "combo did not open the locked room")
  Secret.model(); press(B.a)
  untilExplore(100)
  Secret.ledger(); press(B.a)
end)

flow("band + gig", function()
  for i = 1, 3 do W.npcs[p.friends[i]].p.f = 80 end
  Play.bandSignup(); press(B.a); press(B.a)
  untilExplore(100)
  assert(p.band, "no band")
  p.band.practice = 3
  p.area = "fc"; Explore.arrive("fc", true)
  Play.gig(true)
end)

flow("save + load round trip", function()
  Save.write()
  local t = W.t
  assert(Save.read(), "load failed")
  assert(math.abs(W.t - t) < 1, "time mismatch")
  p = W.p
  Explore.start()
end)

flow("end day -> night -> sleep -> morning -> mall (x3)", function()
  for d = 1, 3 do
    Day.endDay("bus")
    for _ = 1, 3000 do
      frame(B.a); frame(0)
      if Scene.top() == Explore.scene then break end
    end
    assert(Scene.top() == Explore.scene, "day cycle stuck")
    print("   day cycle " .. d .. ": " .. Clock.stamp(W.t) .. " area " .. W.p.area)
    p = W.p
  end
end)

flow("walk through doors, escalators, staff doors", function()
  -- set a daytime clock so stores are open
  local day = Clock.day(W.t)
  if Clock.minute(W.t) > 18 * 60 or Clock.minute(W.t) < 11 * 60 then
    WorldSim.advance(day * 1440 + 1440 + 12 * 60, 5)
  end
  local a = Areas.build("c1")
  local tried = 0
  for _, d in ipairs(a.doors) do
    if d.store and d.fy and tried < 6 then
      local s = W.stores[d.store]
      if s.open and Stores.isOpenAt(s, W.t) and not d.staff then
        tried = tried + 1
        p.area = "c1"; p.x = d.fx * 16 + 8; p.y = d.fy * 16 + 14; Explore.arrive("c1", true)
        local dir = (d.fy > d.y) and B.up or (d.fy < d.y) and B.down or (d.fx > d.x) and B.left or B.right
        p.y = d.fy * 16 + (dir == B.up and 14 or dir == B.down and 2 or 12)
        for _ = 1, 30 do frame(dir); if p.area ~= "c1" then break end end
        assert(p.area == "s" .. s.id, "did not enter " .. s.name .. " (area " .. p.area .. ")")
        untilExplore(200)
        -- walk back out the front door
        for _ = 1, 80 do frame(B.down); if p.area ~= "s" .. s.id then break end end
        assert(p.area == "c1", "did not exit " .. s.name .. " (area " .. p.area .. ")")
        untilExplore(200)
      end
    end
  end
  assert(tried > 0, "no store doors tried")
  -- escalator up
  for _, o in ipairs(a.objs) do
    if o.kind == "escalator" then
      p.area = "c1"; p.x = (o.x - 1) * 16 + 8; p.y = (o.y + 2) * 16 + 8; Explore.arrive("c1", true)
      for _ = 1, 20 do frame(B.right); if p.area ~= "c1" then break end end
      assert(p.area == "c2", "escalator did not go up (area " .. p.area .. ")")
      break
    end
  end
  untilExplore(100)
  -- staff-only door without a job gets you shooed (or not, if nobody sees)
  local keep = p.job
  p.job = nil
  for _, d in ipairs(Areas.build("c2").doors) do
    if d.staff then
      p.area = "c2"; p.x = d.fx * 16 + 8; p.y = d.fy * 16 + 14; Explore.arrive("c2", true)
      local dir = (d.fy > d.y) and B.up or B.down
      for _ = 1, 30 do frame(dir); if p.area ~= "c2" then break end end
      assert(p.area == "v2" or Scene.top() ~= Explore.scene, "staff door did nothing")
      break
    end
  end
  untilExplore(300)
  p.job = keep
end)

flow("walk around for an hour", function()
  p.area = "c1"; p.x, p.y = W.mall.court0 * 16, 9 * 16; Explore.arrive("c1", true)
  for i = 1, 30 * 60 do
    local btn = ({ 1, 2, 4, 8 })[(i // 40) % 4 + 1]
    frame(btn)
    if Scene.top() ~= Explore.scene then untilExplore(500) end
  end
end)

local fails = 0
for _, l in ipairs(results) do if l:sub(1, 4) == "FAIL" then fails = fails + 1 end end
print(fails == 0 and "ALL FLOWS OK" or (fails .. " FLOW FAILURES"))
os.exit(fails == 0 and 0 or 1)
