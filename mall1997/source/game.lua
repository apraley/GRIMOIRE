-- Frame loop and system menu.

local gfx = playdate.graphics

playdate.display.setRefreshRate(30)
Gfx.init()
Sfx.init()

local menu = playdate.getSystemMenu()
menu:addMenuItem("save", function()
  if W and W.p and #Scene.stack > 0 then Save.write() end
end)
menu:addMenuItem("title", function()
  if W and W.p then Save.write() end
  Title.start()
end)

function playdate.update()
  Input.read()
  Gfx.frame = Gfx.frame + 1
  Scene.update()
  gfx.setDrawOffset(0, 0)
  Scene.draw()
end

function playdate.gameWillTerminate()
  if W and W.p and W.t then Save.write() end
end

function playdate.deviceWillSleep()
  if W and W.p and W.t then Save.write() end
end

Title.start()
