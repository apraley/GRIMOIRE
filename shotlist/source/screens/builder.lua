-- SHOT BUILDER: create shots from controlled vocabularies, no typing needed.
--   UP/DOWN field   CRANK or LEFT/RIGHT value   A: picker / keyboard / save
--   HOLD A: save and start the next shot (fields carry over, number +1)
--   B: done

BuilderScreen = Screen:extend()

local FIELDS = {
	{ f = "setup", label = "SETUP" },
	{ f = "size", label = "SIZE", opts = Vocab.SIZE },
	{ f = "move", label = "MOVE", opts = Vocab.MOVE },
	{ f = "lens", label = "LENS" },
	{ f = "subject", label = "SUBJECT" },
	{ f = "priority", label = "PRIORITY", opts = Vocab.PRIORITY },
	{ f = "est", label = "EST MIN" },
	{ f = "desc", label = "DESC" },
	{ f = "save", label = "SAVE" },
}

function BuilderScreen:init(setupId)
	local setup = setupId and Model.get(setupId)
	if setup == nil then
		local cur = App.cursorShot()
		setup = cur and Model.parentOf[cur.id]
	end
	if setup == nil then
		-- no shots anywhere yet: make sure a day/scene/setup exists
		setup = BuilderScreen.ensureSetup()
	end
	self.setupId = setup and setup.id
	self.sel = 2
	self.stepper = Stepper.new(22)
	self.moveStepper = Stepper.new()
	self.added = 0
	local last = setup and setup.shots[#setup.shots]
	self.draft = {
		size = last and last.size or "MS", move = last and last.move or "LOCKED",
		lens = "", subject = last and last.subject or "", priority = 2, est = last and last.est or 10, desc = "",
	}
	self.initial = Util.copy(self.draft)
end

function BuilderScreen.ensureSetup()
	local p = Model.project()
	if p == nil then return nil end
	local day = p.days[1]
	if day == nil then
		day = Schema.new("day", { label = "DAY 1", date = Util.fmtDate(Util.now()) })
		App.commit(Model.opAdd(p, "days", day, nil, "ADD DAY"))
		day = Model.get(day.id)
	end
	local scene = day.scenes[1]
	if scene == nil then
		scene = Schema.new("scene", { number = "01" })
		App.commit(Model.opAdd(day, "scenes", scene, nil, "ADD SCENE"))
		scene = Model.get(scene.id)
	end
	local setup = scene.setups[1]
	if setup == nil then
		setup = Schema.new("setup", { letter = "A" })
		App.commit(Model.opAdd(scene, "setups", setup, nil, "ADD SETUP"))
		setup = Model.get(setup.id)
	end
	return setup
end

function BuilderScreen:setup() return Model.get(self.setupId) end

-- All setups in the project in shooting order.
local function allSetups()
	local r = {}
	local p = Model.project()
	if p == nil then return r end
	for _, d in ipairs(p.days) do for _, sc in ipairs(d.scenes) do for _, su in ipairs(sc.setups) do r[#r + 1] = su end end end
	return r
end

function BuilderScreen:options(f)
	if f == "setup" then return allSetups()
	elseif f == "lens" then return Util.concat({ "" }, Specs_lensOptions())
	elseif f == "subject" then return Util.concat({ "" }, Specs_subjects())
	end
	for _, fd in ipairs(FIELDS) do if fd.f == f then return fd.opts end end
	return nil
end

function BuilderScreen:fmt(f)
	local d = self.draft
	if f == "setup" then
		local su = self:setup()
		return su and (Model.setupCode(su) .. "  " .. su.camera .. " " .. Vocab.fmtLens(su.lens)) or "-"
	elseif f == "lens" then
		if d.lens == "" then
			local su = self:setup()
			return "SETUP " .. (su and Vocab.fmtLens(su.lens) or "")
		end
		return Vocab.fmtLens(d.lens)
	elseif f == "priority" then return Vocab.PRIORITY_LONG[d.priority]
	elseif f == "est" then return d.est .. " MIN"
	elseif f == "subject" then return d.subject == "" and "-" or d.subject
	elseif f == "desc" then return d.desc == "" and ("(AUTO) " .. self:autoDesc()) or d.desc
	elseif f == "save" then return "ADD " .. self:previewCode()
	end
	return tostring(d[f] or "")
end

function BuilderScreen:autoDesc()
	local d = self.draft
	local parts = { d.size }
	if d.subject ~= "" then parts[#parts + 1] = d.subject end
	return table.concat(parts, " - ")
end

function BuilderScreen:previewCode()
	local su = self:setup()
	if su == nil then return "--" end
	return Model.setupCode(su) .. "-" .. Model.nextNum(su)
end

function BuilderScreen:dial(d)
	local fd = FIELDS[self.sel]
	local f = fd.f
	if f == "est" then
		self.draft.est = Util.clamp(self.draft.est + d * (self.draft.est >= 30 and 5 or 1), 0, 240)
	elseif f == "setup" then
		local list = allSetups()
		local i = Util.indexOf(list, self:setup()) or 1
		self.setupId = list[Util.wrap(i + d, #list)].id
	elseif f == "desc" or f == "save" then
		return
	else
		local o = self:options(f)
		local i = Util.indexOf(o, self.draft[f]) or 0
		self.draft[f] = o[Util.wrap(i + d, #o)]
	end
	App.redraw()
end

function BuilderScreen:save()
	local su = self:setup()
	if su == nil then return end
	local d = self.draft
	local shot = Schema.new("shot", { num = Model.nextNum(su), size = d.size, move = d.move, lens = d.lens,
		subject = d.subject, priority = d.priority, est = d.est, desc = d.desc })
	App.commit(Model.opAdd(su, "shots", shot, nil, "ADD SHOT"))
	local rec = Model.get(shot.id)
	self.added = self.added + 1
	self.lastAdded = rec and rec.id
	App.toast("ADDED " .. Model.code(rec), { icon = "check", undo = true })
	-- ready for the next one: keep the look, clear the words
	d.desc = ""
	self.initial = Util.copy(d)
end

function BuilderScreen:onUndo()
	self.added = math.max(0, self.added - 1)
end

function BuilderScreen:isDirty()
	for k, v in pairs(self.draft) do if self.initial[k] ~= v then return true end end
	return false
end

function BuilderScreen:event(ev)
	local fd = FIELDS[self.sel]
	if ev == "UP" then self.sel = Util.wrap(self.sel - 1, #FIELDS)
	elseif ev == "DOWN" then self.sel = Util.wrap(self.sel + 1, #FIELDS)
	elseif ev == "LEFT" then self:dial(-1)
	elseif ev == "RIGHT" then self:dial(1)
	elseif ev == "AL" then self:save()
	elseif ev == "A" then
		if fd.f == "save" then self:save()
		elseif fd.f == "desc" then
			App.keyboard("DESCRIPTION", self.draft.desc, function(t) self.draft.desc = Util.upper(t) end)
		elseif fd.f == "subject" then
			local items = {}
			for _, v in ipairs(Specs_subjects()) do items[#items + 1] = { label = v, value = v } end
			items[#items + 1] = { label = "TYPE NEW...", custom = true }
			App.push(PickerOverlay:new("SUBJECT", items, self.draft.subject, function(it)
				if it.custom then
					App.keyboard("SUBJECT", "", function(t) self.draft.subject = Util.upper(t) end)
				else self.draft.subject = it.value end
			end))
		elseif fd.f == "est" then
			self.draft.est = ({ [0] = 5, [5] = 10, [10] = 15, [15] = 20, [20] = 30, [30] = 45, [45] = 60 })[self.draft.est] or 5
		else
			local o = self:options(fd.f)
			local items = {}
			for _, v in ipairs(o) do
				local label
				if fd.f == "setup" then label = Model.setupCode(v) .. "  " .. v.camera .. " " .. Vocab.fmtLens(v.lens)
				elseif fd.f == "priority" then label = Vocab.PRIORITY_LONG[v]
				elseif fd.f == "lens" then label = v == "" and "USE SETUP LENS" or Vocab.fmtLens(v)
				else label = v end
				items[#items + 1] = { label = label, value = v }
			end
			if fd.f == "lens" then items[#items + 1] = { label = "TYPE CUSTOM...", custom = true } end
			local cur = fd.f == "setup" and self:setup() or self.draft[fd.f]
			App.push(PickerOverlay:new(fd.label, items, cur, function(it)
				if it.custom then
					App.keyboard("LENS", "", function(t) self.draft.lens = Util.upper(t):gsub("MM$", "") end)
				elseif fd.f == "setup" then self.setupId = it.value.id
				else self.draft[fd.f] = it.value end
			end, { w = 260 }))
		end
	elseif ev == "B" then
		if self:isDirty() then
			App.push(ConfirmOverlay:new("SAVE THIS SHOT BEFORE LEAVING?", function()
				self:save(); self:finish()
			end, { yes = "SAVE", no = "DISCARD", onNo = function() self:finish() end }))
		else
			self:finish()
		end
	end
	App.redraw()
	return true
end

function BuilderScreen:finish()
	if self.lastAdded and Model.get(self.lastAdded) and App.stack[1] == App.stack[#App.stack - 1] then
		App.setCursor(Model.get(self.lastAdded))
	end
	App.pop()
end

function BuilderScreen:crank(change, accel)
	local fd = FIELDS[self.sel]
	if fd.f == "desc" or fd.f == "save" then
		local n = self.moveStepper:feed(accel)
		if n ~= 0 then self.sel = Util.clamp(self.sel + n, 1, #FIELDS) end
		return
	end
	local n = self.stepper:feed(change)
	if n ~= 0 then self:dial(n) end
end

function BuilderScreen:draw()
	Gfx.fill(0, 0, Gfx.W, 22)
	Gfx.pix("SHOT BUILDER", 8, 4, 2, { white = true })
	if self.added > 0 then Gfx.pix(self.added .. " ADDED", Gfx.W - 8, 8, 1, { white = true, align = "right" }) end
	-- live preview card
	Gfx.window(4, 26, Gfx.W - 8, 44)
	Gfx.pix(self:previewCode(), 14, 36, 3)
	local d = self.draft
	local desc = d.desc ~= "" and d.desc or self:autoDesc()
	local lens = d.lens ~= "" and Vocab.fmtLens(d.lens) or Vocab.fmtLens((self:setup() or {}).lens)
	Gfx.text(desc, 140, 32, { bold = true, maxW = 250 })
	Gfx.text(lens .. " " .. d.move .. "  PRI " .. Vocab.PRIORITY_LABEL[d.priority] .. "  " .. d.est .. "M", 140, 49, { maxW = 250 })
	-- fields
	local y0, rowH = 74, 16
	for i, fd in ipairs(FIELDS) do
		local y = y0 + (i - 1) * rowH
		local sel = i == self.sel
		if sel then
			Gfx.selbar(4, y, Gfx.W - 8, rowH)
			Gfx.cursor(8, y + 4, true)
		end
		if fd.f == "save" then
			Gfx.icon("check", 20, y + 4, { white = sel })
			Gfx.pix(self:fmt("save") .. "   (HOLD A ANYWHERE)", 34, y + 5, 1, { white = sel })
		else
			Gfx.pix(fd.label, 20, y + 5, 1, { white = sel })
			local v = self:fmt(fd.f)
			if sel and fd.f ~= "desc" then
				Gfx.icon("left", 100, y + 4, { white = true })
				Gfx.icon("right", Gfx.W - 20, y + 4, { white = true })
			end
			Gfx.text(v, 114, y, { bold = true, white = sel, maxW = Gfx.W - 140 })
		end
	end
	Gfx.hints({ { "crank", "VALUE" }, { "A", "PICK" }, { "!A", "ADD" }, { "B", "DONE" } })
end

return BuilderScreen
