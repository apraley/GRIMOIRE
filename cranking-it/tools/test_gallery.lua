-- Screenshots every cabinet in the gallery, every placard, and profiles
-- draw calls per frame for each machine.
local H = dofile("tools/harness.lua")
H.shotDir = "shots/gallery"
H.boot({ wipe = true })
Save.data.introSeen = true
for _, def in ipairs(Machines.list) do Save.machine(def.id).unlocked = true end
Scene.go(HubScene, {}, "cut")
H.run(5)
for i, def in ipairs(Machines.list) do
  HubScene.px = 470 + (i - 1) * 132
  HubScene.cam = HubScene.px - 200
  H.run(2)
  if i % 2 == 1 then H.shot(string.format("hub-%02d", i)) end
end
for i, def in ipairs(Machines.list) do
  Scene.go(LobbyScene, { id = def.id }, "cut")
  H.run(3)
  H.shot(string.format("lobby-%02d-%s", i, def.id))
end
print(string.format("%-14s %8s %8s", "machine", "calls", "ms(mock)"))
for _, def in ipairs(Machines.list) do
  H.goMachine(def.id, "standard")
  H.run(60, 10)
  local M = H.M
  M.render = true
  local calls, t0 = 0, os.clock()
  for _ = 1, 20 do H.frame(10) calls = calls + M.drawCalls end
  local ms = (os.clock() - t0) * 1000 / 20
  M.render = false
  print(string.format("%-14s %8d %8.1f", def.id, calls // 20, ms))
end
