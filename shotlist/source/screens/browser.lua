-- SHOT LIST browser: DAYS > SCENES > SETUPS > SHOTS.
--   A open / go live on shot   RIGHT edit   LEFT status (shots)   B up a level
--   The last row of every level adds a new item there.

BrowserScreen = ListScreen:extend()

local LEVEL_CHILD = { project = "day", day = "scene", scene = "setup", setup = "shot" }
local LEVEL_COLL = { project = "days", day = "scenes", scene = "setups", setup = "shots" }
local LEVEL_TITLE = { project = "DAYS", day = "SCENES", scene = "SETUPS", setup = "SHOTS" }

function BrowserScreen:init(parentId, focusId)
	ListScreen.init(self, "")
	self.parentId = parentId
	self.focusId = focusId
	self.hints = { { "crank", "MOVE" }, { "A", "OPEN" }, { "right", "EDIT" }, { "left", "STATUS" }, { "B", "UP" } }
end

-- Open at the cursor shot's setup, focused on the shot.
function BrowserScreen.forCursor()
	local s = App.cursorShot()
	if s == nil then
		local p = Model.project()
		return BrowserScreen:new(p and p.id)
	end
	return BrowserScreen:new(Model.parentOf[s.id].id, s.id)
end

local function counts(rec)
	local done, total = 0, 0
	local function walk(r)
		if r.k == "shot" then
			if r.status ~= "CUT" then total = total + 1 end
			if r.status == "GOT IT" then done = done + 1 end
			return
		end
		for _, c in ipairs(Schema.CHILDREN[r.k] or {}) do
			if c ~= "notes" and c ~= "reports" and c ~= "takes" then
				for _, ch in ipairs(r[c] or {}) do walk(ch) end
			end
		end
	end
	walk(rec)
	return done, total
end

function BrowserScreen:build()
	local parent = Model.get(self.parentId)
	if parent == nil then self.rows = {}; return end
	local kind = parent.k
	local childKind = LEVEL_CHILD[kind]
	local coll = LEVEL_COLL[kind]
	self.title = LEVEL_TITLE[kind]
	if kind == "project" then self.subtitle = parent.title
	elseif kind == "day" then self.subtitle = parent.label .. " " .. parent.date
	elseif kind == "scene" then self.subtitle = "SC " .. parent.number .. " " .. parent.desc
	elseif kind == "setup" then self.subtitle = Model.setupCode(parent) .. " " .. parent.camera .. " " .. Vocab.fmtLens(parent.lens) end
	local rows = {}
	for _, rec in ipairs(parent[coll]) do
		local r = { key = rec.id, rec = rec }
		local done, total = counts(rec)
		if childKind == "day" then
			r.label = rec.label .. "  " .. rec.date
			r.value = done .. "/" .. total
			r.icon = done == total and total > 0 and "check" or "todo"
		elseif childKind == "scene" then
			r.label = "SC " .. rec.number .. "  " .. rec.desc
			r.value = (#Model.flaggedNotes(rec) > 0 and "! " or "") .. done .. "/" .. total
			r.icon = Vocab.STATUS_ICON[rec.status]
		elseif childKind == "setup" then
			r.label = Model.setupCode(rec) .. "  " .. rec.camera .. " " .. Vocab.fmtLens(rec.lens) .. " " .. rec.support
			r.value = done .. "/" .. total
			r.icon = done == total and total > 0 and "check" or "cam"
		elseif childKind == "shot" then
			r.draw = function(row, x, y, w, h, sel)
				Gfx.statusIcon(rec.status, x + 14, y + 6, sel)
				Gfx.pix(Model.code(rec), x + 27, y + 7, 1, { white = sel })
				Gfx.text(rec.size .. " " .. Model.describe(rec), x + 80, y + 2, { white = sel, maxW = w - 140 })
				local best = Model.bestTake(rec)
				local right = (Vocab.PRIORITY_LABEL[rec.priority] or "") .. " " .. #rec.takes .. "T"
				Gfx.pix(right, x + w - 8, y + 7, 1, { white = sel, align = "right" })
				if best and best.circle then Gfx.icon("ring", x + w - 8 - Pixfont.width(right, 1) - 12, y + 6, { white = sel }) end
			end
		end
		r.onA = function() self:open(rec) end
		r.onRight = function() self:edit(rec) end
		r.onLeft = function() self:status(rec) end
		rows[#rows + 1] = r
	end
	rows[#rows + 1] = { key = "add", label = "+ ADD " .. Util.upper(childKind), icon = "right", onA = function() self:add() end }
	self.rows = rows
	if self.focusId then
		self:selectKey(self.focusId)
		self.focusId = nil
	end
end

function BrowserScreen:open(rec)
	if rec.k == "shot" then
		App.setCursor(rec)
		App.home()
	else
		App.push(BrowserScreen:new(rec.id))
	end
end

function BrowserScreen:edit(rec)
	if rec.k == "shot" then App.push(ShotForm(rec))
	elseif rec.k == "setup" then App.push(SetupForm(rec))
	elseif rec.k == "scene" then App.push(SceneForm(rec))
	elseif rec.k == "day" then App.push(DayForm(rec)) end
end

function BrowserScreen:status(rec)
	if rec.k == "shot" then
		LiveScreen.statusPicker({ shot = function() return rec end })
	elseif rec.k == "scene" then
		App.push(PickerOverlay:new("SCENE " .. rec.number, {
			{ label = "CONTINUITY NOTES", value = "notes", icon = "flag" },
			{ label = "MARK REMAINING UP NEXT", value = "upnext", icon = "upnext" },
			{ label = "CUT REMAINING SHOTS", value = "cut", icon = "cut" },
		}, nil, function(it)
			if it.value == "notes" then App.push(ContinuityScreen:new(rec))
			elseif it.value == "cut" then
				App.commit(Model.opCutScene(rec))
				App.toast("CUT SC " .. rec.number, { undo = true })
			elseif it.value == "upnext" then
				local ops = {}
				for _, su in ipairs(rec.setups) do for _, s in ipairs(su.shots) do
					if s.status == "NOT SHOT" then ops[#ops + 1] = { o = "set", id = s.id, f = "status", v = "UP NEXT" } end
				end end
				App.commit({ o = "batch", ops = ops, label = "UP NEXT SC " .. rec.number })
				App.toast(#ops .. " SHOTS UP NEXT", { undo = true })
			end
			self:build()
		end, { w = 260 }))
	end
end

function BrowserScreen:add()
	local parent = Model.get(self.parentId)
	local kind = parent.k
	if kind == "setup" then
		App.push(BuilderScreen:new(parent.id))
		return
	end
	local rec
	if kind == "project" then
		local last = parent.days[#parent.days]
		rec = Schema.new("day", { label = "DAY " .. (#parent.days + 1),
			date = last and last.date ~= "" and Util.shiftDate(last.date, 1) or Util.fmtDate(Util.now()),
			location = last and last.location or "", call = last and last.call or "07:00" })
	elseif kind == "day" then
		rec = Schema.new("scene", { number = Model.nextSceneNumber(Model.project()), location = parent.location })
	elseif kind == "scene" then
		-- a new setup inherits the previous setup's camera settings
		local prev = parent.setups[#parent.setups]
		rec = prev and Util.deepcopy(prev) or Schema.new("setup", {})
		rec.id = nil
		rec.shots = {}
		rec.letter = Model.nextLetter(parent)
	end
	App.commit(Model.opAdd(parent, LEVEL_COLL[kind], rec, nil, "ADD " .. Util.upper(rec.k)))
	self.focusId = rec.id
	self:build()
	self:edit(Model.get(rec.id))
end

function BrowserScreen:back()
	local parent = Model.get(self.parentId)
	local up = parent and Model.parentOf[parent.id]
	if up and up.k ~= "root" and #App.stack >= 2 and not (App.stack[#App.stack - 1].parentId == up.id) then
		-- climb instead of popping, so B always walks up the hierarchy
		self.focusId = parent.id
		self.parentId = up.id
		self.sel = 1
		self:build()
		return
	end
	App.pop()
end

function SceneForm(scene)
	local spec = {
		{ f = "number", label = "SCENE NUMBER", t = "text" },
		{ f = "desc", label = "DESCRIPTION", t = "text" },
		{ f = "location", label = "LOCATION", t = "text", suggest = function()
			local p = Model.project()
			return Util.uniq(Util.concat(p and p.locations or {}, Model.usedValues("location", "scene"))) end },
		{ f = "cast", label = "CAST", t = "text", suggest = function()
			return Util.uniq(Util.concat(Model.project().cast or {}, Model.usedValues("cast", "scene"))) end },
		{ t = "info", label = "STATUS (FROM SHOTS)", value = function() return scene.status end },
		{ t = "action", label = "CONTINUITY NOTES", icon = "flag", run = function() App.push(ContinuityScreen:new(scene)) end },
		{ t = "action", label = "CUT REMAINING SHOTS", icon = "cut", run = function()
			App.push(ConfirmOverlay:new("CUT ALL UNFINISHED SHOTS IN SC " .. scene.number .. "?", function()
				App.commit(Model.opCutScene(scene)); App.toast("CUT SC " .. scene.number, { undo = true }) end))
		end },
		{ t = "action", label = "DELETE SCENE", icon = "x", run = function()
			App.push(ConfirmOverlay:new("DELETE SC " .. scene.number .. " WITH ALL SETUPS, SHOTS AND TAKES?", function()
				App.commit(Model.opDel(scene, "DELETE SC " .. scene.number)); App.home()
				App.toast("DELETED SC " .. scene.number, { undo = true })
			end))
		end },
	}
	return FormScreen:new("SCENE " .. scene.number, scene, spec)
end

function DayForm(day)
	local spec = {
		{ f = "label", label = "LABEL", t = "text" },
		{ f = "date", label = "DATE", t = "date" },
		{ f = "call", label = "CALL TIME", t = "time" },
		{ f = "location", label = "LOCATION", t = "text" },
		{ f = "weather", label = "WEATHER", t = "text" },
		{ f = "crewNotes", label = "CREW NOTES", t = "text" },
		{ t = "action", label = "SCENES", icon = "right", run = function() App.push(BrowserScreen:new(day.id)) end },
		{ t = "action", label = "DELETE DAY", icon = "x", run = function()
			App.push(ConfirmOverlay:new("DELETE " .. day.label .. " AND EVERYTHING IN IT?", function()
				App.commit(Model.opDel(day, "DELETE " .. day.label)); App.home()
				App.toast("DELETED " .. day.label, { undo = true })
			end))
		end },
	}
	return FormScreen:new(day.label, day, spec)
end

return BrowserScreen
