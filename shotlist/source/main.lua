-- SHOT LIST for Playdate.
-- Entry point: loads modules, restores data (crash-safe), wires callbacks.

import "CoreLibs/graphics"

import "core/util"
import "core/vocab"
import "core/schema"
import "core/model"
import "core/store"
import "core/templates"
import "core/report"
import "core/interchange"

import "ui/pixfont"
import "ui/gfx"
import "ui/input"
import "ui/app"

import "screens/list"
import "screens/overlays"
import "screens/live"
import "screens/details"
import "screens/slate"
import "screens/hub"
import "screens/browser"
import "screens/builder"
import "screens/progress"
import "screens/continuity"
import "screens/gear"
import "screens/report"
import "screens/project"

local function boot()
	playdate.display.setRefreshRate(30)
	-- a shot list sits open for hours between presses
	playdate.setAutoLockDisabled(true)
	Gfx.init()
	local ok, err = pcall(Store.load)
	if not ok then
		-- never start over silently: keep files, show the error, run on a fresh in-memory db
		print("load failed: " .. tostring(err))
		Store.lastError = "LOAD FAILED - FILES KEPT"
	end
	if Model.db then Input.holdMs = Model.db.settings.holdMs or 450 end
	App.setupSystemMenu()
	App.resetRoot()
end

function playdate.update()
	App.update()
end

-- Persist everything the moment the OS might take the app away.
local function saveNow()
	if Model.db then
		Store.flush()
	end
end
function playdate.gameWillTerminate() saveNow() end
function playdate.deviceWillSleep() saveNow() end
function playdate.deviceWillLock() saveNow() end
function playdate.gameWillPause()
	saveNow()
	local img = App.buildMenuImage()
	playdate.setMenuImage(img)
end

boot()
