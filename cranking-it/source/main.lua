-- CRANKING IT
-- An anthology of thirteen crank-powered machines in a strange museum.
-- Entry point: loads modules, owns playdate.update and system callbacks.

import "CoreLibs/graphics"

import "core/util"
import "core/crank"
import "core/input"
import "core/audio"
import "core/save"
import "core/art"
import "core/ui"
import "core/scene"
import "core/machine"
import "core/achievements"
import "core/challenge"
import "core/themes"
import "core/lore"

import "machines/safecracker"
import "machines/fishing"
import "machines/camera"
import "machines/microfiche"
import "machines/numbers"
import "machines/elevator"
import "machines/projectionist"
import "machines/lighthouse"
import "machines/winch"
import "machines/well"
import "machines/clockmaker"
import "machines/civilization"
import "machines/billion"

import "scenes/title"
import "scenes/hub"
import "scenes/lobby"
import "scenes/results"
import "scenes/exhibits"
import "scenes/curator"

local pd <const> = playdate
local gfx <const> = pd.graphics

pd.display.setRefreshRate(30)
UI.init()
Audio.init()
Save.load()
Audio.enabled = Save.data.settings.sound
Themes.apply()

Scene.go(TitleScene, {}, "cut")
pd.resetElapsedTime()

function pd.update()
  local dt = pd.getElapsedTime()
  pd.resetElapsedTime()
  if dt <= 0 or dt > 0.1 then dt = 1 / 30 end

  Input.poll(dt)
  if Input.crankChange ~= 0 then Scene.cranked(Input.crankChange, Input.crankAccel) end
  local order = Input.ORDER
  for i = 1, #order do
    local b = order[i]
    if (Input.pressed & b) ~= 0 then Scene.buttonDown(b) end
    if (Input.released & b) ~= 0 then Scene.buttonUp(b) end
  end

  Scene.update(dt)
  UI.updateToasts(dt)
  Save.data.totals.seconds = Save.data.totals.seconds + dt
  Save.update(dt)

  gfx.setDrawOffset(0, 0)
  Scene.draw()
  UI.drawToasts()
end

local function persist()
  if Scene.current == PlayScene then PlayScene:suspend() end
  Save.flush()
end

function pd.gameWillTerminate() persist() end
function pd.deviceWillSleep() persist() end
function pd.deviceWillLock() persist() end
function pd.gameWillPause() Save.flush() end
