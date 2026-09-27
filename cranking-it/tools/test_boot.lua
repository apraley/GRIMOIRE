-- Boots the game, walks the wrapper scenes and takes screenshots.
local H = dofile("tools/harness.lua")
H.boot({ wipe = true })
H.run(20)
H.shot("00-title")
H.crank(30, 40) -- crank the doors open
H.run(40)
H.shot("01-hub-intro")
for _ = 1, 12 do H.press("a") H.run(10) end
H.run(20)
H.shot("02-hub")
-- walk to first cabinet
H.crank(25, 30)
H.run(30)
H.shot("03-hub-cabinet")
print("scene is hub:", H.scene() == HubScene, "px", HubScene.px)
H.press("a")
H.run(30)
H.shot("04-lobby")
print("scene is lobby:", H.scene() == LobbyScene)
