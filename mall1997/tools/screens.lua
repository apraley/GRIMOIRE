-- Headless screenshots of THE MALL, 1997 through the strict Playdate mock +
-- the 1-bit software rasterizer (tools/pdraster.lua). Boots exactly like
-- tools/flows.lua, then visits scenes and writes 2x PNGs to docs/screens/.
-- usage: lua5.4 tools/screens.lua [outdir]

PD_TOOLS_DIR = (arg[0]:match("(.*/)") or "./")
PD_SOURCE_DIR = PD_TOOLS_DIR .. "../source/"
PD_DATA_DIR = "/tmp/pdmock_screens/"
os.execute("rm -rf " .. PD_DATA_DIR)
dofile(PD_TOOLS_DIR .. "pdmock.lua")
dofile(PD_TOOLS_DIR .. "pdraster.lua")
local OUT = arg[1] or (PD_TOOLS_DIR .. "../docs/screens/")
if OUT:sub(-1) ~= "/" then OUT = OUT .. "/" end
os.execute("mkdir -p '" .. OUT .. "'")
import "main"

local B = { left = 1, right = 2, up = 4, down = 8, b = 16, a = 32 }
local n = 0
local function frame(btn, crank)
  n = n + 1
  local ok, err = xpcall(function() PDMOCK_FRAME(btn or 0, crank or 0) end, debug.traceback)
  if not ok then error("frame " .. n .. ": " .. err, 0) end
end
local function press(btn, times) for _ = 1, times or 1 do frame(btn); frame(0) end end
local function idle(k) for _ = 1, k or 1 do frame(0) end end

local produced, skipped = {}, {}
local function save(name)
  local path = OUT .. name .. ".png"
  PDRASTER_SAVE(path)
  produced[#produced + 1] = name
  print(string.format("saved %-22s (frame %d, scene depth %d)", name, n, #Scene.stack))
end
-- run a step; on error record it and carry on
local function step(name, fn)
  local t0 = os.clock()
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    skipped[#skipped + 1] = name .. ": " .. tostring(err)
    print("SKIP " .. name .. ": " .. tostring(err))
  else
    io.write(string.format("   (%.2fs)\n", os.clock() - t0))
  end
end

local function home(area, x, y)
  local p = W.p
  p.area = area
  local a = Areas.build(area)
  p.x = x or a.w * 8
  p.y = y or (a.h - 3) * 16
  Explore.start()
end

-- ------------------------------------------------------------------ boot
step("01_title", function()
  idle(25)
  save("01_title")
end)

step("02_intro", function()
  press(B.a)          -- "New mall"
  press(0, 3)
  press(B.a)          -- pick a name
  for _ = 1, 400 do
    local top = Scene.top()
    if top and top.pages and top.pages[1] and top.pages[1][1] and top.pages[1][1]:match("^Friday") then break end
    frame(0)
  end
  -- second page of the intro (name, money, pager...)
  press(B.a); press(B.a)
  idle(40)
  save("02_intro")
end)

step("03_parking_lot", function()
  for _ = 1, 2000 do if Scene.top() == Explore.scene then break end frame(B.a); frame(0) end
  assert(Scene.top() == Explore.scene, "did not reach the mall")
  print("booted: " .. W.mall.name .. ", " .. #W.stores .. " stores, " .. #W.npcs .. " people")
  idle(20)
  save("03_parking_lot")
end)

local p = W and W.p
step("04_concourse", function()
  p = W.p
  home("c1", (W.mall.court0 + 9) * 16, 12 * 16)
  idle(15)
  save("04_concourse")
end)

step("05_storefronts", function()
  home("c1", (MallGen.ANCHOR_W + 20) * 16, 12 * 16)
  idle(15)
  save("05_storefronts")
end)

step("06_food_court", function()
  local a = Areas.build("fc")
  home("fc", a.w * 8, 7 * 16)
  idle(15)
  save("06_food_court")
end)

local music
step("07_music_store", function()
  music = Stores.byType("music")[1]
  assert(music, "no music store")
  local id = Areas.storeArea(music)
  local a = Areas.build(id)
  home(id, a.w * 8, (a.h // 2) * 16 + 8)
  idle(15)
  save("07_music_store")
end)

step("08_arcade", function()
  local id = "s" .. W.mall.arcade
  local a = Areas.build(id)
  home(id, a.w * 8, (a.h - 3) * 16)
  idle(15)
  save("08_arcade")
end)

step("09_dialog", function()
  home("c1", (W.mall.court0 + 9) * 16, 12 * 16)
  idle(3)
  local who
  for _, x in ipairs(NPCAI.inArea(p.area)) do
    if x.status == "active" and not x.hunting and x.age < 19 then who = x break end
  end
  if not who then
    for _, x in ipairs(W.npcs) do if x.status == "active" and x.age < 19 and not x.hunting then who = x break end end
  end
  assert(who, "no NPC to talk to")
  Dialog.open(who)
  idle(40)
  save("09_dialog")
end)

step("10_browse", function()
  local id = Areas.storeArea(music)
  local a = Areas.build(id)
  home(id, a.w * 8, (a.h - 3) * 16)
  local rack
  for _, o in ipairs(a.objs) do if o.kind == "rack" then rack = o break end end
  assert(rack, "no rack in the music store")
  Shop.browse(music, rack)
  idle(12)
  save("10_browse")
end)

step("11_menu_me", function()
  home("c1", (W.mall.court0 + 9) * 16, 12 * 16)
  Menu.open()
  idle(5)
  save("11_menu_me")
end)

step("12_menu_mall", function()
  home("c1", (W.mall.court0 + 9) * 16, 12 * 16)
  Menu.open("MALL")
  idle(5)
  save("12_menu_mall")
end)

step("13_morning", function()
  Day.morning()
  idle(30)
  save("13_morning")
end)

step("14_night", function()
  Day.night({ "test line" })
  idle(30)
  save("14_night")
end)

step("15_minigame_record", function()
  p = W.p
  home("c1", (W.mall.court0 + 9) * 16, 12 * 16)
  Jobs.hire(music.id)
  local day = Clock.day(W.t)
  local mm = Clock.minute(W.t)
  p.job.shifts = { { day = day, s = mm, e = math.min(mm + 120, 23 * 60) } }
  Play.clockIn()
  idle(5)
  save("15a_minigame_intro")
  press(B.a) -- start
  idle(60)
  save("15_minigame_record")
end)

step("16_arcade_serpent", function()
  local id = "s" .. W.mall.arcade
  local a = Areas.build(id)
  home(id, a.w * 8, (a.h - 3) * 16)
  p.tokens = 5
  local cab
  for _, o in ipairs(a.objs) do
    if o.kind == "cab" and W.arcade.machines[o.machine] and W.arcade.machines[o.machine].game == "serpent" then cab = o end
  end
  assert(cab, "no serpent cabinet")
  W.arcade.machines[cab.machine].broken = false
  Play.cabinet(cab)
  idle(3)
  press(B.a)
  idle(60)
  save("16_arcade_serpent")
end)

step("17_model", function()
  home("c1", (W.mall.court0 + 9) * 16, 12 * 16)
  Secret.model()
  idle(10)
  save("17_model")
end)

step("18_tunnels", function()
  home("tun", 3 * 16 + 8, 6 * 16 + 12)
  idle(15)
  save("18_tunnels")
end)

step("19_service", function()
  home("v1", (W.mall.court0 + 12) * 16 + 8, 4 * 16 + 12)
  idle(15)
  save("19_service")
end)

step("20_cinema_lobby", function()
  local id = "s" .. W.mall.cinema
  local a = Areas.build(id)
  home(id, a.w * 8, (a.h - 3) * 16)
  idle(15)
  save("20_cinema_lobby")
end)

print(("%d screenshots in %s"):format(#produced, OUT))
if #skipped > 0 then
  print("skipped:")
  for _, s in ipairs(skipped) do print("  " .. s) end
end
os.exit(#skipped == 0 and 0 or 1)
