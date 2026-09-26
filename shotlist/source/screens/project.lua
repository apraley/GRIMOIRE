-- PROJECT, DATA, SETTINGS forms and the first-run WELCOME screen.

-- Create a project from a template (or the demo) and make it active.
function App.createProject(kind)
	local p
	if kind == "DEMO" then p = Templates.demoCommercial() else p = Templates.build(kind) end
	if p == nil then return end
	if Model.db == nil then
		local db = Schema.newDb()
		Store.reset(db)
	end
	if Model.db.projects[1] then Store.snapshot("PRE-NEW PROJECT") end
	local ops = {}
	Model.assignIds(p)
	ops[#ops + 1] = { o = "add", p = "root", c = "projects", r = p }
	if kind == "DEMO" and #Model.db.gear.packages == 0 then
		for _, pkg in ipairs(Templates.demoPackages()) do
			Model.assignIds(pkg)
			ops[#ops + 1] = { o = "add", p = "gear", c = "packages", r = pkg }
		end
	end
	ops[#ops + 1] = { o = "set", id = "settings", f = "project", v = p.id }
	App.commit({ o = "batch", ops = ops, label = "NEW PROJECT" })
	local flat = Model.flat(Model.get(p.id))
	Model.db.settings.cursor = flat[1] and flat[1].shot.id or ""
	Store.touchSession()
	Store.flush()
	App.resetRoot()
	App.toast("PROJECT READY: " .. p.title, { icon = "check" })
end

function App.templatePicker()
	local items = {}
	for _, t in ipairs(Vocab.TEMPLATE) do items[#items + 1] = { label = t, value = t } end
	items[#items + 1] = { label = "DEMO: 60-SHOT COMMERCIAL", value = "DEMO", icon = "star" }
	App.push(PickerOverlay:new("NEW PROJECT", items, nil, function(it) App.createProject(it.value) end, { w = 260, rows = 8 }))
end

function ProjectForm()
	local p = Model.project()
	local spec = {
		{ f = "title", label = "TITLE", t = "text" },
		{ f = "client", label = "CLIENT", t = "text" },
		{ f = "director", label = "DIRECTOR", t = "text" },
		{ f = "dp", label = "DP", t = "text" },
		{ f = "producer", label = "PRODUCER", t = "text" },
		{ f = "notes", label = "NOTES", t = "text", upper = false },
		{ f = "cast", label = "CAST / SUBJECTS", t = "list" },
		{ f = "locations", label = "LOCATIONS", t = "list" },
		{ t = "section", label = "SCHEDULE" },
		{ t = "action", label = "SHOOT DAYS", icon = "right", value = function() return #p.days .. " DAYS" end,
			run = function() App.push(BrowserScreen:new(p.id)) end },
		{ t = "section", label = "PROJECTS" },
		{ t = "action", label = "SWITCH PROJECT", icon = "right", value = function() return #Model.db.projects .. " TOTAL" end,
			run = function()
				local items = {}
				for _, pr in ipairs(Model.db.projects) do items[#items + 1] = { label = pr.title, value = pr } end
				App.push(PickerOverlay:new("PROJECTS", items, p, function(it)
					App.commit(Model.opSet(Model.db.settings, "project", it.value.id, "SWITCH PROJECT"))
					local flat = Model.flat(it.value)
					App.setCursor(flat[1] and flat[1].shot)
					App.home()
				end, { w = 300 }))
			end },
		{ t = "action", label = "NEW PROJECT FROM TEMPLATE", icon = "right", run = function() App.templatePicker() end },
		{ t = "action", label = "DELETE THIS PROJECT", icon = "x", run = function()
			App.push(ConfirmOverlay:new("DELETE " .. p.title .. "? A BACKUP IS TAKEN FIRST.", function()
				Store.snapshot("PRE-DELETE")
				App.commit(Model.opDel(p, "DELETE PROJECT"))
				local nxt = Model.db.projects[1]
				App.commit(Model.opSet(Model.db.settings, "project", nxt and nxt.id or ""))
				App.resetRoot()
			end))
		end },
	}
	return FormScreen:new("PROJECT", p, spec)
end

local function ago(t)
	if t == nil or t == 0 then return "NEVER" end
	local s = Util.now() - t
	if s < 60 then return math.floor(s) .. "S AGO" end
	if s < 3600 then return math.floor(s / 60) .. "M AGO" end
	return Util.fmtDate(t) .. " " .. Util.fmtClock(t)
end

function DataForm()
	local db = Model.db
	local spec = {
		{ t = "info", label = "SCHEMA VERSION", value = function() return "V" .. Schema.VERSION end },
		{ t = "info", label = "CHANGES LOGGED", value = function() return tostring(Store.seq) end },
		{ t = "info", label = "UNSAVED IN JOURNAL", value = function() return Store.pending .. " OPS (CRASH-SAFE)" end },
		{ t = "info", label = "LAST SNAPSHOT", value = function() return ago(db.savedAt) end },
		{ t = "info", label = "LAST BACKUP", value = function() return ago(db.settings.lastSnapshot) end },
		{ t = "info", label = "LOADED FROM", value = function()
			local li = Store.loadInfo
			return (li.source or "-") .. ((li.replayed or 0) > 0 and (" +" .. li.replayed .. " REPLAYED") or "")
		end },
		{ t = "action", label = "SAVE NOW", icon = "disk", run = function()
			App.toast(Store.flush() and "SAVED" or ("SAVE FAILED: " .. tostring(Store.lastError)), { icon = "disk" }) end },
		{ t = "action", label = "BACKUP NOW", icon = "disk", run = function()
			App.toast(Store.snapshot("MANUAL") and "BACKUP WRITTEN" or "BACKUP FAILED", { icon = "disk" }) end },
		{ t = "action", label = "RESTORE A BACKUP", icon = "right", run = function()
			local items = {}
			for _, e in ipairs(Store.listSnapshots()) do
				items[#items + 1] = { label = Util.fmtClock(e.t) .. " " .. e.reason .. " " .. (e.done or 0) .. "/" .. (e.shots or 0) ..
					" " .. (e.takes or 0) .. "TK", value = e }
			end
			if #items == 0 then App.toast("NO BACKUPS YET"); return end
			App.push(PickerOverlay:new("RESTORE BACKUP", items, nil, function(it)
				App.push(ConfirmOverlay:new("RESTORE BACKUP FROM " .. Util.fmtClock(it.value.t) .. "? CURRENT STATE IS BACKED UP FIRST.", function()
					local ok, err = Store.restore(it.value)
					App.home()
					App.toast(ok and "RESTORED" or ("RESTORE FAILED: " .. tostring(err)))
				end))
			end, { w = 320 }))
		end },
		{ t = "action", label = "EXPORT PROJECT (JSON+CSV)", icon = "right", run = function()
			local files = Interchange.exportFiles(Model.project(), Util.now(), nil)
			App.toast("WROTE " .. #files .. " FILES TO /EXPORT", { icon = "disk", ms = 2500 })
		end },
		{ t = "action", label = "IMPORT FROM /IMPORT", icon = "right", run = function()
			local files = Interchange.listImports()
			if #files == 0 then App.toast("PUT .JSON FILES IN DATA/IMPORT", { ms = 2500 }); return end
			local items = {}
			for _, f in ipairs(files) do items[#items + 1] = { label = f:gsub("^import/", ""), value = f } end
			App.push(PickerOverlay:new("IMPORT", items, nil, function(it)
				local proj, warn = Interchange.readImport(it.value)
				if proj == nil then App.toast("IMPORT FAILED: " .. tostring(warn), { ms = 3000 }); return end
				Store.snapshot("PRE-IMPORT")
				Model.assignIds(proj)
				App.commit({ o = "batch", label = "IMPORT " .. proj.title, ops = {
					{ o = "add", p = "root", c = "projects", r = proj },
					{ o = "set", id = "settings", f = "project", v = proj.id } } })
				local flat = Model.flat(Model.get(proj.id))
				App.setCursor(flat[1] and flat[1].shot)
				App.home()
				App.toast("IMPORTED " .. #flat .. " SHOTS" .. (#warn > 0 and (" (" .. #warn .. " WARNINGS)") or ""), { ms = 3000 })
			end, { w = 320 }))
		end },
		{ t = "action", label = "UNDO LAST CHANGE", icon = "left", value = function() return Store.undoLabel() or "-" end,
			run = function() local l = Store.undo(); App.toast(l and ("UNDONE: " .. l) or "NOTHING TO UNDO") end },
	}
	return FormScreen:new("DATA", db.settings, spec)
end

function SettingsForm()
	local spec = {
		{ f = "nextMode", label = "NEXT RANKING", t = "enum", opts = { "BALANCED", "RUSH" },
			fmt = function(v) return v == "RUSH" and "RUSH (PRIORITY ONLY)" or "BALANCED" end },
		{ f = "autoNext", label = "GOT IT JUMPS TO NEXT", t = "bool" },
		{ f = "circleGotIt", label = "CIRCLE ALSO MARKS GOT IT", t = "bool" },
		{ f = "askPerf", label = "ASK ISSUE AFTER BAD TAKE", t = "bool" },
		{ f = "holdMs", label = "HOLD TIME", t = "enum", opts = { 300, 450, 600, 800 }, fmt = function(v) return v .. " MS" end },
		{ f = "crank", label = "CRANK SPEED", t = "enum", opts = { 1, 2, 3 },
			fmt = function(v) return ({ "SLOW", "NORMAL", "FAST" })[v] or "?" end },
		{ f = "clock24", label = "24H CLOCK", t = "bool" },
		{ f = "slateInvert", label = "SLATE WHITE ON BLACK", t = "bool" },
	}
	return FormScreen:new("SETTINGS", Model.db.settings, spec, { onChange = function(s) Input.holdMs = s.holdMs end })
end

---------------------------------------------------------------------------
-- WELCOME (first run, or no projects)
---------------------------------------------------------------------------
WelcomeScreen = Screen:extend()

function WelcomeScreen:init()
	self.sel = 1
	self.items = {
		{ "LOAD 60-SHOT DEMO", function() App.createProject("DEMO") end },
		{ "NEW PROJECT FROM TEMPLATE", function() App.templatePicker() end },
	}
	self.noGlobalNext = true
end

function WelcomeScreen:draw()
	Gfx.fill(0, 0, Gfx.W, Gfx.H)
	Gfx.pix("SHOT LIST", 200, 30, 6, { align = "center", white = true })
	Gfx.pix("SHOT LOG - TAKES - SLATE - WRAP", 200, 82, 1, { align = "center", white = true })
	Gfx.window(40, 110, 320, 80)
	for i, it in ipairs(self.items) do
		local y = 124 + (i - 1) * 26
		if i == self.sel then
			Gfx.selbar(50, y, 300, 22)
			Gfx.cursor(54, y + 7, true)
		end
		Gfx.text(it[1], 66, y + 3, { bold = true, white = i == self.sel })
	end
	Gfx.hints({ { "up", "" }, { "down", "CHOOSE" }, { "A", "START" } })
end

function WelcomeScreen:event(ev)
	if ev == "UP" or ev == "DOWN" then self.sel = Util.wrap(self.sel + (ev == "UP" and -1 or 1), #self.items)
	elseif ev == "A" then self.items[self.sel][2]() end
	return true
end

function WelcomeScreen:crank(change)
	if math.abs(change) > 20 then self.sel = Util.wrap(self.sel + (change > 0 and 1 or -1), #self.items) end
end

return WelcomeScreen
