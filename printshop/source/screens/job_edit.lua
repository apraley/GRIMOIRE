-- Job editor (add or edit a queue entry). Choosing a spool fills material
-- and colour and applies the recommended calibration profile.

JobEditScreen = {}
JobEditScreen.__index = JobEditScreen

function JobEditScreen.new(job)
	local isNew = job == nil
	-- Edit a working copy; commit on SAVE.
	local draft
	if isNew then
		local printer = Store.activePrinter()
		local s = Filament.list({ filter = "ALL", sort = "REMAINING" })
		local spool = s[#s]
		draft = Job.new({ name = "NEW JOB", printerId = printer.id, status = "READY",
			spoolId = spool and spool.id or nil, material = spool and spool.material or "PLA",
			color = spool and spool.color or "WHITE" })
		Queue.applyProfile(draft)
	else
		draft = U.deepcopy(job)
	end
	local self = setmetatable({ job = job, draft = draft, isNew = isNew }, JobEditScreen)
	self:buildForm()
	return self
end

function JobEditScreen:buildForm()
	local d = self.draft
	local fields = {
		{ label = "NAME", kind = "text", maxLen = 28, get = function() return d.name end,
			set = function(v) if v ~= "" then d.name = U.upper(v) end end },
		{ label = "MODEL FILE", kind = "text", maxLen = 40, get = function() return d.model end,
			set = function(v) d.model = v end },
		{ label = "SPOOL", kind = "custom",
			value = function()
				local s = d.spoolId and Store.spool(d.spoolId)
				return s and Spool.shortLabel(s) or "(NONE)"
			end,
			run = function()
				Common.pickSpool("SPOOL", nil, function(s)
					d.spoolId = s and s.id or nil
					if s then
						d.material, d.color = s.material, s.color
						Queue.applyProfile(d, true)
						Toast.show("PROFILE " .. d.nozzleTemp .. "/" .. d.bedTemp .. "C APPLIED", "star")
					end
					self.form:refresh()
				end, true)
			end,
			hint = "A: PICK FROM ROLODEX (APPLIES PROFILE)" },
		{ label = "MATERIAL", kind = "enum", options = Enums.MATERIALS, get = function() return d.material end,
			set = function(v) d.material = v Queue.applyProfile(d, true) end },
		{ label = "COLOR", kind = "enum", options = Enums.COLORS, get = function() return d.color end,
			set = function(v) d.color = v end },
		{ label = "PRINTER", kind = "enum",
			options = function() return U.map(Store.data.printers, function(p) return p.id end) end,
			optionLabel = function(id) local p = Store.printer(id) return p and p.name or id end,
			get = function() return d.printerId end, set = function(v) d.printerId = v Queue.applyProfile(d, true) end },
		{ label = "EST TIME", kind = "number", min = 5, max = 60 * 48, step = 5, get = function() return d.estMinutes end,
			set = function(v) d.estMinutes = v end, fmt = function(v) return U.fmtDuration(v * 60) end,
			dialFmt = "%d", unit = "min" },
		{ label = "EST GRAMS", kind = "number", min = 1, max = 2000, step = 1, get = function() return d.estGrams end,
			set = function(v) d.estGrams = v end, fmt = function(v)
				local s = d.spoolId and Store.spool(d.spoolId)
				return U.fmtGrams(v) .. (s and ("  " .. U.fmtMoney(Filament.cost(s, v))) or "")
			end, dialFmt = "%d", unit = "g" },
		{ label = "PRIORITY", kind = "enum", options = { 1, 2, 3, 4, 5 },
			optionLabel = function(v) return Enums.PRIORITY[v] end,
			get = function() return d.priority end, set = function(v) d.priority = v end },
		{ label = "STATUS", kind = "enum",
			options = { "IDEA", "READY", "QUEUED", "FAILED", "COMPLETE" },
			get = function() return d.status end, set = function(v) d.status = v end,
			hidden = function() return d.status == "PRINTING" or d.status == "PAUSED" end },
		{ label = "PROJECT", kind = "custom", value = function() return d.project ~= "" and d.project or "(NONE)" end,
			run = function() self:pickProject() end },
		{ label = "SHAPE", kind = "enum", options = Enums.SHAPES, get = function() return d.shape end,
			set = function(v) d.shape = v end, optionLabel = function(v) return U.upper(v) end,
			hint = "Silhouette for the layer visualizer" },
		{ label = "LAYERS", kind = "number", min = 1, max = 3000, step = 5, get = function() return d.layers end,
			set = function(v) d.layers = v end },
		{ label = "NOZZLE", kind = "number", min = 0, max = 300, step = 1, unit = "C", get = function() return d.nozzleTemp end,
			set = function(v) d.nozzleTemp = v d.profileKey = "" end, hint = "Crank to override the profile" },
		{ label = "BED", kind = "number", min = 0, max = 120, step = 1, unit = "C", get = function() return d.bedTemp end,
			set = function(v) d.bedTemp = v d.profileKey = "" end },
		{ label = "USE PROFILE", kind = "action", value = function()
				local s = d.spoolId and Store.spool(d.spoolId)
				local rec = CalService.recommend(d.printerId, d.material, s and s.manufacturer or nil)
				return string.format("%d/%d", rec.nozzle, rec.bed) .. FontData.icon.deg .. "C " .. U.upper(rec.level)
			end,
			run = function()
				local rec = Queue.applyProfile(d, true)
				Toast.show("APPLIED " .. U.upper(rec.level) .. " PROFILE", "star")
				self.form:refresh()
			end },
		{ label = "NOTES", kind = "text", maxLen = 80, get = function() return d.notes end, set = function(v) d.notes = v end },
		{ label = "SAVE", kind = "action", value = function() return "" end, run = function() self:save() end },
	}
	self.form = Form.new(fields, { rows = 14, x = 6, y = 22, w = 388, labelW = 118 })
end

function JobEditScreen:pickProject()
	local d = self.draft
	local items = {
		{ label = "(NONE)", action = function() d.project = "" end },
		{ label = "+ NEW PROJECT...", action = function()
			TextEntry.open("PROJECT", "", function(t) d.project = U.upper(t) end, 20)
		end },
	}
	for _, p in ipairs(Queue.projects()) do
		items[#items + 1] = { label = p, action = function() d.project = p end }
	end
	Menu.open({ title = "PROJECT", items = items, maxRows = 10 })
end

function JobEditScreen:save()
	local d = self.draft
	if self.isNew then
		local fields = U.copy(d)
		fields.id = nil
		local j = Queue.add(fields)
		-- Keep manual temperature overrides from the form.
		j.nozzleTemp, j.bedTemp, j.profileKey = d.nozzleTemp, d.bedTemp, d.profileKey
		Toast.show("ADDED " .. j.name, "check")
	else
		-- The draft already carries profile temps (or manual overrides).
		local id = self.job.id
		for k, v in pairs(d) do self.job[k] = v end
		self.job.id = id
		self.job.spoolId = d.spoolId    -- may be nil, which pairs() skips
		Job.normalize(self.job)
		Toast.show("SAVED", "check")
	end
	Store.markDirty()
	Sfx.play("ok")
	Screens.pop()
end

function JobEditScreen:update()
	if self.form:update() then return end
	if Input.b() then
		Confirm("DISCARD CHANGES?", function() Screens.pop() end, nil, "DISCARD", "KEEP EDITING")
	end
end

function JobEditScreen:draw()
	Common.page(self.isNew and "NEW JOB" or "EDIT JOB", nil, self.form:hint() .. "   B:CANCEL")
	Draw.window(2, 17, 396, 208)
	self.form:draw()
end
