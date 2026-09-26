-- PRINT SHOP for Playdate.
--
-- Layers (imported in dependency order):
--   lib/         pure helpers: util, clock, rng, events
--   data/        font, seed data, calibration procedures, Captain phrases
--   models/      record shapes + normalizers, schema versions + migrations
--   services/    persistence and domain logic shared by every tool
--   providers/   printer adapters behind the PrinterProvider interface
--   components/  drawing, text, input, widgets, sprites
--   screens/     the UI

import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/timer"
import "CoreLibs/keyboard"

import "lib/util"
import "lib/clock"
import "lib/rng"
import "lib/events"
import "lib/memo"

import "data/font5x9"
import "models/enums"
import "models/job"
import "models/spool"
import "models/printer"
import "models/history"
import "models/calibration"
import "models/maintenance"
import "models/schema"
import "data/seed"
import "data/calibration_defs"
import "data/phrases"

import "services/store"
import "services/filament"
import "services/queue"
import "services/stats"
import "services/maint_service"
import "services/cal_service"

-- Aggregates drawn every frame are memoized until the data changes.
for _, name in ipairs({ "combo", "combos", "overall", "forSpool", "causes", "projects", "weekly", "suggestions", "metersPrinted", "filamentCost" }) do
	Memo.wrap(Stats, name, "Stats." .. name)
end
for _, name in ipairs({ "list", "dueSoon" }) do Memo.wrap(MaintService, name, "Maint." .. name) end
for _, name in ipairs({ "lowSpools", "totals", "daysUntilEmpty", "weeklyUsage" }) do Memo.wrap(Filament, name, "Filament." .. name) end
for _, name in ipairs({ "backlog", "counts" }) do Memo.wrap(Queue, name, "Queue." .. name) end

import "providers/provider"
import "providers/demo_provider"
import "providers/bridge_provider"
import "providers/bambu_provider"

import "services/printing"
import "services/captain"

import "components/draw"
import "components/text"
import "components/input"
import "components/sfx"
import "components/screens_mgr"
import "components/list"
import "components/widgets"
import "components/form"
import "components/sprites"

import "screens/common"
import "screens/home"
import "screens/watch"
import "screens/failure"
import "screens/queue"
import "screens/job_edit"
import "screens/rolodex"
import "screens/spool_edit"
import "screens/calibration"
import "screens/calib_run"
import "screens/maint"
import "screens/captain"
import "screens/stats"
import "screens/settings"

local gfx <const> = playdate.graphics

App = {
	VERSION = "1.0.0",
	persistMs = 0,
	menu = {},
}

function App.init()
	playdate.display.setRefreshRate(30)
	gfx.setBackgroundColor(gfx.kColorWhite)
	Input.init()
	Text.init()

	Store.load()
	Store.beforeSave = function() Printing.persist() end
	Draw.setTheme(Store.settings().theme)

	Captain.init()
	App.subscribe()
	App.healJobs()
	Printing.init()
	App.dailyChores(true)

	App.installMenu()
	Screens.push(HomeScreen.new())

	local r = Store.loadReport
	if r.migratedFrom then
		Toast.show("DATA UPGRADED FROM V" .. r.migratedFrom, "check")
	elseif r.newer then
		Toast.show("NEWER SAVE: READ-ONLY. UPDATE PRINT SHOP", "warn")
	elseif r.backup and r.seeded then
		Toast.show("SAVE WAS DAMAGED; BACKED UP", "warn")
	end
	Store.save()
end

-- Jobs without temperatures (seed data, imports, old saves) get the
-- recommended profile so every queue row shows real settings.
function App.healJobs()
	for _, j in ipairs(Store.data.jobs) do
		if Job.isActive(j) and j.status ~= "PRINTING" and j.status ~= "PAUSED" and j.nozzleTemp == 0 then
			Queue.applyProfile(j)
			Store.markDirty()
		end
	end
end

-- Domain events -> toasts, sounds and prompts.
function App.subscribe()
	Events.on("print.finished", function(e)
		if e.outcome == "success" then
			Sfx.play("done")
			Toast.show(e.job.name .. " COMPLETE", "check")
		elseif e.outcome == "failed" then
			Toast.show(e.job.name .. " FAILED", "cross")
		end
		for _, c in ipairs(e.maintCrossed or {}) do
			Toast.show(c.task.name .. (c.st.due and " DUE" or " DUE SOON"), "wrench")
		end
	end)
	Events.on("print.error", function(e)
		-- A cancel from our own Watch screen is resolved right there.
		if e.pending and e.pending.cancelled then return end
		Sfx.play("fail")
		Toast.show("PRINT FAILED: LOG THE CAUSE", "warn")
		-- Jump straight to the failure log when the user is watching.
		local top = Screens.top()
		if top and (getmetatable(top) == HomeScreen or getmetatable(top) == WatchScreen) then
			Screens.push(FailureScreen.new())
		end
	end)
	Events.on("print.lost", function(e)
		Toast.show(e.job.name .. ": MARK IT DONE OR FAILED", "warn")
	end)
	Events.on("print.runout", function()
		Sfx.play("error")
		Toast.show("FILAMENT RUNOUT: SWAP SPOOL", "warn")
	end)
	Events.on("spool.low", function(e)
		Toast.show(Spool.shortLabel(e.spool) .. (e.empty and " EMPTY" or " LOW"), "spool")
	end)
	Events.on("calib.saved", function(e)
		if e.jobsUpdated and e.jobsUpdated > 0 then Sfx.play("ok") end
	end)
end

-- Once per day: filament absorbs moisture; the Captain notices.
function App.dailyChores(force)
	local day = Clock.now() // U.DAY
	local cap = Store.data.captain
	if force or cap.lastDay ~= day then
		cap.lastDay = day
		Filament.ageDryness(Clock.now())
		Store.markDirty()
	end
end

---------------------------------------------------------------------------
-- System menu (max three custom items)

App.SPEED_LABELS = { "1x", "10x", "60x", "300x", "1200x" }

function App.installMenu()
	local menu = playdate.getSystemMenu()
	menu:removeAllMenuItems()
	App.menu.home = menu:addMenuItem("workshop", function()
		Screens.popToRoot()
	end)
	App.menu.captain = menu:addMenuItem("captain", function()
		Screens.popToRoot()
		Screens.push(CaptainScreen.new())
	end)
	App.menu.speed = menu:addOptionsMenuItem("demo spd", App.SPEED_LABELS, App.speedLabel(), function(v)
		local n = tonumber(string.match(v or "", "^(%d+)x$"))
		if n then
			Store.settings().demoSpeed = n
			Store.markDirty()
		end
	end)
end

function App.speedLabel()
	local s = Store.settings().demoSpeed
	for _, l in ipairs(App.SPEED_LABELS) do
		if tonumber(string.match(l, "^(%d+)")) == s then return l end
	end
	return "60x"
end

function App.syncMenu()
	if App.menu.speed then App.menu.speed:setValue(App.speedLabel()) end
end

---------------------------------------------------------------------------
-- lifecycle

function App.saveAll()
	Printing.persist()
	Store.markDirty()
	Store.save(true)
end

function App.resetData(empty)
	if Printing.provider then Printing.provider:shutdown() end
	-- Drop the old provider first so its state isn't saved into the new shop.
	Printing.provider = nil
	Store.reset(empty)
	Events.reset()
	Captain.init()
	App.subscribe()
	App.healJobs()
	Draw.setTheme(Store.settings().theme)
	Printing.init()
	Screens.stack = {}
	Screens.push(HomeScreen.new())
	Toast.show(empty and "EMPTY SHOP READY" or "DEMO SHOP RESTORED", "check")
end

function App.update()
	local dt = Clock.tick()
	Input.update(dt)
	Draw.tick(dt)
	playdate.timer.updateTimers()

	-- The printer keeps working while the device sleeps or the system menu
	-- is open: hand the provider the full real time, not the clamped frame.
	Printing.update(dt + Clock.gapMs)
	-- Provider state is saved every 30s while something is happening.
	App.persistMs = App.persistMs + dt
	App.minuteMs = (App.minuteMs or 0) + dt
	if App.minuteMs > 60000 then
		App.minuteMs = 0
		Memo.bump()      -- time-based values ("due in N days") move on
	end
	if App.persistMs > 30000 then
		App.persistMs = 0
		local st = Printing.provider:getStatus().state
		if st == "PRINTING" or st == "HEATING" or st == "PAUSED" then Store.saveLive() end
		App.dailyChores(false)
	end
	Store.update(dt)
	Toast.update(dt)

	Screens.update(dt)
	Screens.draw()
	Toast.draw()
end

playdate.update = App.update

function playdate.gameWillTerminate() App.saveAll() end
function playdate.deviceWillSleep() App.saveAll() end
function playdate.deviceWillLock() App.saveAll() end
function playdate.gameWillPause() App.saveAll() end

App.init()
