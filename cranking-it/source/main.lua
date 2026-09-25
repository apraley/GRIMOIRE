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
-- the left half of the system menu shows a card for the current context
local function buildMenuImage()
  local img = gfx.image.new(400, 240, gfx.kColorWhite)
  gfx.pushContext(img)
  gfx.setPattern(Art.pat.gray12)
  gfx.fillRect(0, 0, 200, 240)
  UI.panel(8, 8, 184, 224, "paper")
  if Scene.current == PlayScene and PlayScene.def then
    local def = PlayScene.def
    UI.text("No." .. U.roman(def.number), 100, 18, "center")
    UI.textLines(def.title, 20, 36, 160, 2, UI.bold)
    local y = 76
    for i = 1, math.min(5, #def.controls) do
      local c = def.controls[i]
      UI.glyph(c[1], 20, y)
      UI.textLines(c[2], 56, y, 128, 1)
      y = y + 22
    end
    local best = Save.machine(def.id).best[PlayScene.params.mode or "standard"]
    if best then UI.text("best " .. U.commas(best), 100, 200, "center") end
  else
    UI.text("CRANKING IT", 100, 20, "center", UI.bold)
    Art.gearIcon(100, 70, 22, 0)
    UI.text(Save.data.gears .. " gears", 100, 100, "center", UI.bold)
    local got, all = Achievements.total()
    UI.text(got .. "/" .. all .. " achievements", 100, 124, "center")
    UI.text(U.commas(math.floor(Save.data.totals.crankDegrees / 360)) .. " turns", 100, 146, "center")
  end
  gfx.popContext()
  return img
end

function pd.gameWillPause()
  Save.flush()
  local ok, img = pcall(buildMenuImage)
  if ok then pd.setMenuImage(img) end
end
