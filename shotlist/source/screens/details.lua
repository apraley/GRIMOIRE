-- DETAILS (B from LIVE): the shot's quick controls and its take log.
-- LEFT/RIGHT on a take cycles its rating; hold A circles; A opens the take.

DetailsScreen = ListScreen:extend()

local RATING_CYCLE = { "", "GREAT", "GOOD", "BAD", "TECH" }

function DetailsScreen:init(shotId)
	ListScreen.init(self, "DETAILS")
	self.shotId = shotId
	self.hints = { { "crank", "MOVE" }, { "A", "OPEN" }, { "left", "" }, { "right", "ADJUST" }, { "B", "BACK" } }
end

function DetailsScreen:drawHeader()
	local shot = Model.get(self.shotId)
	Gfx.fill(0, 0, Gfx.W, 40)
	if shot == nil then return end
	Gfx.pix(Model.code(shot), 8, 4, 3, { white = true })
	Gfx.text(Model.describe(shot), 8, 23, { white = true, bold = true, maxW = 250 })
	Gfx.pix(shot.status, Gfx.W - 8, 6, 1, { white = true, align = "right" })
	local best = Model.bestTake(shot)
	Gfx.pix(#shot.takes .. " TAKES" .. (best and ("  BEST " .. best.n) or ""), Gfx.W - 8, 26, 1, { white = true, align = "right" })
end

function DetailsScreen:build()
	local shot = Model.get(self.shotId)
	if shot == nil then self.rows = {}; return end
	local ctx = Model.ctx(shot.id)
	local rows = {}
	local function cycleStatus(d)
		local i = Util.indexOf(Vocab.STATUS, shot.status) or 1
		App.setStatus(shot, Vocab.STATUS[Util.wrap(i + d, #Vocab.STATUS)])
		self:build()
	end
	rows[#rows + 1] = { key = "status", label = "STATUS", value = shot.status, icon = Vocab.STATUS_ICON[shot.status],
		valueBold = true, dial = true,
		onA = function() LiveScreen.statusPicker({ shot = function() return shot end }) end,
		onLeft = function() cycleStatus(-1) end, onRight = function() cycleStatus(1) end }
	rows[#rows + 1] = { key = "addnote", label = "+ CONTINUITY NOTE", icon = "flag",
		value = "TAG, THEN TEXT",
		onA = function() ContinuityScreen.quickAdd(ctx.scene, shot, function() App.home() end) end }
	local function cyclePri(d)
		local p = Util.wrap((tonumber(shot.priority) or 2) + d, 3)
		App.commit(Model.opSet(shot, "priority", p, Model.code(shot) .. " PRI " .. Vocab.PRIORITY_LABEL[p]))
		self:build()
	end
	rows[#rows + 1] = { key = "pri", label = "PRIORITY", value = Vocab.PRIORITY_LONG[shot.priority] or "?", valueBold = true,
		dial = true, onLeft = function() cyclePri(-1) end, onRight = function() cyclePri(1) end, onA = function() cyclePri(1) end }
	rows[#rows + 1] = { key = "editshot", label = "EDIT SHOT", icon = "right",
		value = shot.size .. " " .. Vocab.fmtLens(Model.lensOf(shot)) .. " " .. shot.move,
		onA = function() App.push(ShotForm(shot)) end }
	rows[#rows + 1] = { key = "editsetup", label = "EDIT SETUP " .. Model.setupCode(ctx.setup), icon = "cam",
		value = ctx.setup.camera ~= "" and ctx.setup.camera or "", onA = function() App.push(SetupForm(ctx.setup)) end }
	local flagged = #Model.flaggedNotes(ctx.scene)
	rows[#rows + 1] = { key = "cont", label = "CONTINUITY SC " .. ctx.scene.number, icon = "flag",
		value = flagged > 0 and (flagged .. " FLAGGED") or (#ctx.scene.notes .. " NOTES"),
		onA = function() App.push(ContinuityScreen:new(ctx.scene)) end }
	rows[#rows + 1] = { key = "slate", label = "SLATE", icon = "right", onA = function()
		App.setCursor(shot); App.push(SlateScreen:new()) end }

	local takes = {}
	for _, t in ipairs(shot.takes) do takes[#takes + 1] = t end
	table.sort(takes, function(a, b) return a.n > b.n end)
	rows[#rows + 1] = { section = true, skip = true, label = "TAKES (" .. #takes .. ")  LEFT/RIGHT RATE  HOLD A CIRCLE", h = 16 }
	for _, t in ipairs(takes) do
		local function cycle(d)
			local i = Util.indexOf(RATING_CYCLE, t.rating or "") or 1
			local r = RATING_CYCLE[Util.wrap(i + d, #RATING_CYCLE)]
			App.commit(Model.opSet(t, "rating", r, "T" .. t.n .. " " .. (r == "" and "UNRATED" or r)))
			self:build()
		end
		rows[#rows + 1] = {
			key = t.id, take = t, h = 20,
			draw = function(r, x, y, w, h, sel)
				Gfx.pix("T" .. t.n, x + 16, y + 6, 2, { white = sel })
				if t.circle then Gfx.icon("ring", x + 52, y + 6, { white = sel }) end
				Gfx.ratingIcon(t.rating, x + 64, y + 6, sel)
				Gfx.text(t.rating ~= "" and t.rating or "-", x + 78, y + 2, { white = sel, bold = true })
				local issue = {}
				if t.tech ~= "" then issue[#issue + 1] = t.tech end
				if t.perf ~= "" then issue[#issue + 1] = t.perf end
				if t.note ~= "" then issue[#issue + 1] = t.note end
				Gfx.text(table.concat(issue, " / "), x + 140, y + 2, { white = sel, maxW = w - 190 })
				if t.t then Gfx.text(Util.fmtClock(t.t, Model.db.settings.clock24), x + w - 6, y + 2, { white = sel, align = "right" }) end
			end,
			onLeft = function() cycle(-1) end, onRight = function() cycle(1) end,
			onA = function() App.push(TakeForm(t)) end,
			onAL = function()
				App.commit(Model.opCircle(t, Util.now()))
				App.toast((t.circle and "CIRCLED T" or "UNCIRCLED T") .. t.n, { icon = "ring" })
				self:build()
			end,
		}
	end
	rows[#rows + 1] = { key = "addtake", label = "LOG TAKE " .. (Model.maxTakeN(shot) + 1), icon = "rec", onA = function()
		local t = App.addTake(shot)
		if t then
			self:build()
			App.push(RateOverlay:new(t.id))
		end
	end }
	self.rows = rows
end

-- The list starts below the taller header.
DetailsScreen.listTop = 44

---------------------------------------------------------------------------
-- Field specs for records (used from details, browser, builder)
---------------------------------------------------------------------------

local function priFmt(v) return Vocab.PRIORITY_LONG[tonumber(v)] or tostring(v) end

function Specs_lensOptions()
	local r = {}
	for _, l in ipairs(Vocab.LENS) do if l ~= "CUSTOM" then r[#r + 1] = l end end
	for _, l in ipairs(Model.db.gear.lists.lenses or {}) do r[#r + 1] = l end
	for _, pkg in ipairs(Model.db.gear.packages) do for _, l in ipairs(pkg.lenses or {}) do r[#r + 1] = l end end
	return Util.uniq(r)
end

function Specs_subjects()
	local p = Model.project()
	local r = Util.concat(p and p.cast or {}, Model.usedValues("subject", "shot"))
	return Util.uniq(r)
end

function Specs_cameraOptions()
	local r = {}
	for _, pkg in ipairs(Model.db.gear.packages) do r[#r + 1] = pkg.name end
	for _, c in ipairs(Model.db.gear.lists.cameras or {}) do r[#r + 1] = c end
	return Util.uniq(r)
end

local function lensFmt(v) return (v == nil or v == "") and "(SETUP)" or Vocab.fmtLens(v) end

function ShotForm(shot)
	local spec = {
		{ f = "desc", label = "DESCRIPTION", t = "text" },
		{ f = "size", label = "SIZE", t = "enum", opts = Vocab.SIZE },
		{ f = "move", label = "MOVEMENT", t = "enum", opts = Vocab.MOVE },
		{ f = "lens", label = "LENS", t = "enum", opts = function() return Util.concat({ "" }, Specs_lensOptions()) end,
			fmt = lensFmt, custom = true },
		{ f = "subject", label = "SUBJECT", t = "text", suggest = Specs_subjects },
		{ f = "priority", label = "PRIORITY", t = "enum", opts = Vocab.PRIORITY, fmt = priFmt },
		{ f = "est", label = "EST MINUTES", t = "num", min = 0, max = 240, step = 1 },
		{ f = "status", label = "STATUS", t = "enum", opts = Vocab.STATUS },
		{ f = "num", label = "SHOT NUMBER", t = "text" },
		{ f = "notes", label = "NOTES", t = "text" },
		{ t = "action", label = "DUPLICATE SHOT", icon = "right", run = function()
			local setup = Model.parentOf[shot.id]
			local copy = Schema.new("shot", { num = Model.nextNum(setup), desc = shot.desc, size = shot.size, move = shot.move,
				lens = shot.lens, subject = shot.subject, priority = shot.priority, est = shot.est, notes = shot.notes })
			local i = Util.indexOf(setup.shots, shot)
			App.commit(Model.opAdd(setup, "shots", copy, i and i + 1, "DUPLICATE " .. Model.code(shot)))
			App.toast("ADDED " .. Model.code(Model.get(copy.id)), { undo = true })
		end },
		{ t = "action", label = "DELETE SHOT", icon = "x", run = function()
			App.push(ConfirmOverlay:new("DELETE " .. Model.code(shot) .. " AND " .. #shot.takes .. " TAKES?", function()
				local flat = Model.flat()
				local i = Model.flatIndex(shot.id) or 1
				local code = Model.code(shot)
				App.commit(Model.opDel(shot, "DELETE " .. code))
				local after = Model.flat()
				if #after > 0 then App.setCursor(after[Util.clamp(i, 1, #after)].shot) end
				App.home()
				App.toast("DELETED " .. code, { undo = true })
			end))
		end },
	}
	local f = FormScreen:new("SHOT " .. Model.code(shot), shot, spec)
	f.subtitle = Model.describe(shot)
	return f
end

function SetupForm(setup)
	local ctx = Model.ctx(setup.id)
	local spec = {
		{ f = "camera", label = "CAMERA", t = "enum", opts = Specs_cameraOptions, custom = true },
		{ f = "lens", label = "LENS", t = "enum", opts = Specs_lensOptions, fmt = Vocab.fmtLens, custom = true },
		{ f = "fps", label = "FRAME RATE", t = "enum", opts = Vocab.FPS, custom = true },
		{ f = "res", label = "RESOLUTION", t = "enum", opts = Vocab.RES, custom = true },
		{ f = "wb", label = "WHITE BAL", t = "enum", opts = Vocab.WB, custom = true },
		{ f = "iso", label = "ISO", t = "enum", opts = Vocab.ISO, custom = true },
		{ f = "shutter", label = "SHUTTER", t = "enum", opts = Vocab.SHUTTER, fmt = Vocab.fmtShutter, custom = true },
		{ f = "nd", label = "ND / FILTER", t = "enum", opts = function()
			return Util.uniq(Util.concat(Vocab.ND, Model.db.gear.lists.filters or {})) end, custom = true },
		{ f = "support", label = "SUPPORT", t = "enum", opts = function()
			return Util.uniq(Util.concat(Vocab.SUPPORT, Model.db.gear.lists.support or {})) end, custom = true },
		{ f = "lighting", label = "LIGHTING", t = "text", suggest = function()
			return Util.uniq(Util.concat(Model.usedValues("lighting", "setup"), Model.db.gear.lists.lighting or {})) end },
		{ f = "audio", label = "AUDIO", t = "enum", opts = Vocab.AUDIO, custom = true },
		{ f = "letter", label = "SETUP LETTER", t = "text" },
		{ t = "action", label = "ADD SHOT TO " .. Model.setupCode(setup), icon = "right", run = function()
			App.push(BuilderScreen:new(setup.id)) end },
		{ t = "action", label = "NEW SETUP (COPY OF THIS)", icon = "right", run = function()
			local copy = Util.deepcopy(setup)
			copy.id = nil
			copy.shots = {}
			copy.letter = Model.nextLetter(ctx.scene)
			local i = Util.indexOf(ctx.scene.setups, setup)
			App.commit(Model.opAdd(ctx.scene, "setups", copy, i and i + 1, "NEW SETUP " .. copy.letter))
			App.replace(SetupForm(Model.get(copy.id)))
		end },
		{ t = "action", label = "DELETE SETUP", icon = "x", run = function()
			App.push(ConfirmOverlay:new("DELETE SETUP " .. Model.setupCode(setup) .. " AND ITS " .. #setup.shots .. " SHOTS?", function()
				App.commit(Model.opDel(setup, "DELETE SETUP " .. Model.setupCode(setup)))
				App.home()
				App.toast("DELETED SETUP", { undo = true })
			end))
		end },
	}
	local f = FormScreen:new("SETUP " .. Model.setupCode(setup), setup, spec)
	return f
end

function TakeForm(take)
	local shot = Model.parentOf[take.id]
	local spec = {
		{ f = "rating", label = "RATING", t = "enum", opts = RATING_CYCLE, fmt = function(v) return v == "" and "UNRATED" or v end },
		{ f = "circle", label = "CIRCLED", t = "bool" },
		{ f = "tech", label = "TECH ISSUE", t = "enum", opts = function() return Util.concat({ "" }, Vocab.TECH_ISSUE) end, custom = true },
		{ f = "perf", label = "PERFORMANCE", t = "enum", opts = function() return Util.concat({ "" }, Vocab.PERF_ISSUE) end, custom = true },
		{ f = "note", label = "NOTE", t = "text" },
		{ t = "info", label = "LOGGED", value = function() return take.t and (Util.fmtDate(take.t) .. " " .. Util.fmtClock(take.t)) or "" end },
		{ t = "action", label = "DELETE TAKE", icon = "x", run = function()
			App.commit(Model.opDel(take, "DELETE T" .. take.n .. " " .. Model.code(shot)))
			App.pop()
			App.toast("DELETED T" .. take.n, { undo = true })
		end },
	}
	return FormScreen:new("TAKE " .. take.n .. " " .. Model.code(shot), take, spec)
end

return DetailsScreen
