-- Wrapper flow test: title, hub, curator, exhibits, unlocks, daily machine,
-- results, save reliability, suspend/resume.
--   MOCK_DATA_DIR=/tmp/ci-wrapper lua5.4 tools/test_wrapper.lua
local H = dofile("tools/harness.lua")
H.shotDir = "shots/wrapper"
H.boot({ wipe = true })
local fails = 0
local function check(c, msg) if not c then fails = fails + 1 print("FAIL: " .. msg) else print("ok   " .. msg) end end

H.run(10)
check(Scene.current == TitleScene, "boots to title")
H.crank(30, 40)
H.run(40)
check(Scene.current == HubScene, "cranking opens the doors")
check(HubScene.dialog ~= nil, "keeper intro on first visit")
for _ = 1, 12 do H.press("a") H.run(6) end
check(HubScene.dialog == nil and Save.data.introSeen, "intro dismissed and remembered")

-- walk left to the curator with the d-pad
local function walkTo(x)
  for _ = 1, 400 do
    if math.abs(HubScene.px - x) < 10 then break end
    if HubScene.px < x then H.hold("right") H.release("left") else H.hold("left") H.release("right") end
    H.frame(0)
  end
  H.releaseAll()
  H.run(20)
end
walkTo(330)
check(HubScene.near and HubScene.near.kind == "curator", "reached the Keeper's desk")
H.shot("hub-curator")
H.press("a")
H.run(30)
check(Scene.current == CuratorScene, "curator scene opens")
H.press("a") -- stories
H.run(5)
H.press("a") -- first story (costs 1 gear, we have 0)
H.run(5)
check(not Lore.owned("l1"), "cannot buy a story without gears")
Save.data.gears = 10
H.press("a")
H.run(10)
check(Lore.owned("l1") and Save.data.gears == 9, "story bought for 1 gear")
check(CuratorScene.dialog ~= nil, "story is told in a dialog")
H.shot("curator-story")
for _ = 1, 20 do if not CuratorScene.dialog then break end H.press("a") H.run(4) end
check(CuratorScene.dialog == nil, "story finished")
H.press("b") H.run(5)
-- themes
H.press("down") H.press("a") H.run(5)
H.press("down") H.press("a") H.run(5) -- LEDGER costs 4
check(Themes.current() == "ledger" and Save.data.gears == 5, "bought and lit the LEDGER theme (" .. Themes.current() .. ", " .. Save.data.gears .. ")")
H.press("b") H.run(5)
H.press("down") H.press("a") H.run(5) -- stats
H.shot("curator-stats")
H.press("b") H.run(5)
H.press("b") H.run(30)
check(Scene.current == HubScene, "back to hub from curator")

-- a covered cabinet: camera costs 3
local camX
for _, s in ipairs({}) do end
walkTo(470 + 2 * 132)
check(HubScene.near and HubScene.near.def and HubScene.near.def.id == "camera", "at the FILM CAMERA cabinet")
H.shot("hub-covered")
H.press("a") H.run(30)
check(Scene.current == LobbyScene, "lobby for covered cabinet")
H.shot("lobby-covered")
H.press("a") H.run(10)
check(Save.machine("camera").unlocked and Save.data.gears == 2, "dust sheet removed for 3 gears (" .. Save.data.gears .. ")")
H.shot("lobby-unlocked")
H.press("b") H.run(30)

-- daily machine
walkTo(200)
check(HubScene.near and HubScene.near.kind == "daily", "at the daily plinth")
H.press("a") H.run(30)
check(Scene.current == LobbyScene and LobbyScene.daily ~= nil, "daily lobby")
H.shot("lobby-daily")
local d = Challenge.daily()
local d2 = Challenge.daily()
check(d.id == d2.id and d.seed == d2.seed, "daily is deterministic")
-- different days give different machines on consecutive days
local t = playdate.getTime()
local seen = {}
local prev
local repeats = 0
for i = 0, 25 do
  local key = Challenge.keyForDay(U.dayNumber(t) + i)
  local dd = Challenge.daily({ year = tonumber(key:sub(1, 4)), month = tonumber(key:sub(5, 6)), day = tonumber(key:sub(7, 8)) })
  seen[dd.id] = true
  if dd.id == prev then repeats = repeats + 1 end
  prev = dd.id
end
local n = 0
for _ in pairs(seen) do n = n + 1 end
check(n == 13, "26 consecutive days cover all 13 machines (" .. n .. ")")
check(repeats <= 1, "daily machine rarely repeats on consecutive days")

-- save reliability: corrupt the newest slot, the other survives
Save.data.gears = 77
Save.flush()
Save.data.gears = 78
Save.flush()
local newest = (Save.seq % 2 == 0) and "save_a" or "save_b"
local f = io.open(H.M.dataDir .. "/" .. newest .. ".json", "w")
f:write('{"seq": 999, "sum": 1, "payload": "{\\"gears\\": 5000}"}')
f:close()
Save.load()
check(Save.data.gears == 77, "corrupt newest slot ignored, previous save recovered (" .. Save.data.gears .. ")")
-- a failing write never destroys the good slot
H.M.failWrites = true
Save.data.gears = 1
Save.flush()
H.M.failWrites = false
Save.load()
check(Save.data.gears == 77, "failed write keeps last good save")

-- suspend / resume
local m = H.goMachine("safecracker", "standard")
H.crank(15, 60)
local dialBefore = m.dial
local timeBefore = m.timeLeft
playdate.gameWillTerminate()
check(Save.data.suspend and Save.data.suspend.id == "safecracker", "suspend written on terminate")
Save.load()
Scene.go(TitleScene, {}, "cut")
H.run(5)
check(TitleScene.suspend ~= false and TitleScene.suspend ~= nil, "title offers resume")
H.press("down")
H.press("a")
H.run(40)
check(Scene.current == PlayScene and PlayScene.def.id == "safecracker", "resumed into the machine")
local m2 = PlayScene.machine
check(math.abs(m2.dial - dialBefore) < 0.01, "dial restored")
check(math.abs(m2.timeLeft - timeBefore) < 2, "timer restored")
H.shot("resumed")

-- achievements pay gears
local g0 = Save.data.gears
Achievements.unlock("safecracker", "first")
check(Save.data.gears == g0 + 1, "achievement pays a gear")
check(not Achievements.unlock("safecracker", "first"), "achievement only once")

-- exhibits
Scene.go(ExhibitScene, {}, "cut")
H.run(5)
H.press("a") H.run(5)
Save.machine("safecracker").medals.standard = 1
Save.data.gears = 10
H.press("a") H.run(10)
check(Save.data.exhibits.e_safe, "exhibit restored after a medal")
H.shot("exhibit-read")
check(pcall(json.encode, Save.data), "save encodes")

-- pause card builds in every context
Scene.go(HubScene, {}, "cut") H.run(3)
check(pcall(playdate.gameWillPause), "pause card in hub")
H.goMachine("safecracker", "standard")
check(pcall(playdate.gameWillPause), "pause card in machine")

print(fails == 0 and "WRAPPER OK" or ("WRAPPER FAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)
