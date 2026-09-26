-- Spool editor (new card or edit).

SpoolEditScreen = {}
SpoolEditScreen.__index = SpoolEditScreen

function SpoolEditScreen.new(spool)
	local isNew = spool == nil
	local d = isNew and Spool.new({ manufacturer = "BAMBU", material = "PLA", color = "BLACK", nominalGrams = 1000,
		remainingGrams = 1000, cost = 19.99, dryness = "SEALED", location = "SHELF A", purchasedAt = Clock.now() })
		or U.deepcopy(spool)
	local self = setmetatable({ spool = spool, draft = d, isNew = isNew, original = U.deepcopy(d) }, SpoolEditScreen)
	self:buildForm()
	return self
end

function SpoolEditScreen:buildForm()
	local d = self.draft
	local info = function() return Enums.materialInfo(d.material) end
	local makers = {}
	for _, m in ipairs(Enums.MANUFACTURERS) do makers[#makers + 1] = m end
	for _, s in ipairs(Store.data.spools) do
		if not U.indexOf(makers, s.manufacturer) then makers[#makers + 1] = s.manufacturer end
	end
	local fields = {
		{ label = "MAKER", kind = "enum", options = makers, get = function() return d.manufacturer end,
			set = function(v) d.manufacturer = v end, hint = FontData.icon.left .. FontData.icon.right .. ": CHANGE  A: LIST" },
		{ label = "MAKER (TYPE)", kind = "text", maxLen = 14, get = function() return d.manufacturer end,
			set = function(v) if v ~= "" then d.manufacturer = U.upper(v) end end },
		{ label = "MATERIAL", kind = "enum", options = Enums.MATERIALS, get = function() return d.material end,
			set = function(v) d.material = v end },
		{ label = "COLOR", kind = "enum", options = Enums.COLORS, get = function() return d.color end,
			set = function(v) d.color = v end },
		{ label = "COLOR (TYPE)", kind = "text", maxLen = 12, get = function() return d.color end,
			set = function(v) if v ~= "" then d.color = U.upper(v) end end },
		{ label = "NOMINAL", kind = "number", min = 100, max = 5000, step = 50, unit = "g",
			get = function() return d.nominalGrams end,
			set = function(v)
				-- A full spool stays full when the nominal weight is corrected.
				-- "Full" means full on the saved card, not in the draft: a
				-- dip below the remaining weight must not add filament on
				-- the way back up.
				local orig = self.original
				local wasFull = orig.remainingGrams >= orig.nominalGrams
				d.nominalGrams = v
				-- Otherwise the weight is only capped for display and on save,
				-- so a temporary dip doesn't lose grams either.
				if wasFull then d.remainingGrams = v end
			end },
		{ label = "REMAINING", kind = "number", min = 0, max = 5000, step = 5, unit = "g",
			get = function() return U.roundInt(math.min(d.remainingGrams, d.nominalGrams)) end,
			set = function(v) d.remainingGrams = math.min(v, d.nominalGrams) end },
		{ label = "COST", kind = "number", min = 0, max = 200, step = 0.5, dialFmt = "%.2f", unit = "$",
			get = function() return d.cost end, set = function(v) d.cost = v end,
			fmt = function(v) return U.fmtMoney(v) .. string.format("  $%.3f/G", v / math.max(1, d.nominalGrams)) end },
		{ label = "DRYNESS", kind = "enum", options = Enums.DRYNESS, get = function() return d.dryness end,
			set = function(v)
				d.dryness = v
				-- DRY or OK restarts the ageing clock; otherwise the daily
				-- chore would age the spool straight back from openedAt.
				if v == "DRY" or v == "OK" then d.driedAt = Clock.now() end
				if v ~= "SEALED" and d.openedAt == 0 then d.openedAt = Clock.now() end
			end },
		{ label = "LOCATION", kind = "enum", options = RolodexScreen.LOCATIONS, get = function() return d.location end,
			set = function(v) d.location = v end },
		{ label = "FAV NOZZLE", kind = "number", min = 0, max = 300, step = 1, unit = "C",
			get = function() return d.favNozzle > 0 and d.favNozzle or info().nozzle end, set = function(v) d.favNozzle = v end },
		{ label = "FAV BED", kind = "number", min = 0, max = 120, step = 1, unit = "C",
			get = function() return d.favBed > 0 and d.favBed or info().bed end, set = function(v) d.favBed = v end },
		{ label = "BOUGHT", kind = "number", min = 0, max = 3650, step = 1, unit = "days ago",
			get = function() return d.purchasedAt > 0 and math.max(0, (Clock.now() - d.purchasedAt) // U.DAY) or 0 end,
			set = function(v) d.purchasedAt = Clock.now() - v * U.DAY end,
			fmt = function(v) return U.fmtDate(Clock.now() - v * U.DAY) end },
		{ label = "NOTES", kind = "text", maxLen = 80, get = function() return d.notes end, set = function(v) d.notes = v end },
		{ label = "SAVE", kind = "action", run = function() self:save() end },
	}
	if not self.isNew then
		table.insert(fields, #fields, { label = "DELETE CARD", kind = "action", run = function() self:delete() end,
			hint = "Removes the card; history keeps its records." })
	end
	self.form = Form.new(fields, { rows = 14, x = 6, y = 22, w = 388, labelW = 118 })
end

function SpoolEditScreen:save()
	local d = self.draft
	if self.isNew then
		local fields = U.copy(d)
		fields.id = nil
		local s = Filament.add(fields)
		Toast.show("ADDED " .. Spool.shortLabel(s), "check")
	else
		-- Merge only the user's edits: prints may have consumed filament
		-- while the editor was open. A changed REMAINING is a weigh-in and
		-- goes through the ledger.
		local newRemaining = d.remainingGrams
		d.remainingGrams = self.original.remainingGrams
		U.mergeEdits(self.spool, self.original, d)
		-- Target weight: the user's weigh-in if they changed it, else what
		-- the spool holds now, capped by a possibly lowered nominal. Any
		-- change goes through the ledger before normalize could clamp it
		-- away silently.
		local target = self.spool.remainingGrams
		if newRemaining ~= self.original.remainingGrams then target = newRemaining end
		target = math.min(target, self.spool.nominalGrams)
		if math.abs(target - self.spool.remainingGrams) >= 0.5 then
			Filament.setRemaining(self.spool, target, "Edited card")
		end
		Spool.normalize(self.spool)
		Store.markDirty()
		Toast.show("SAVED", "check")
	end
	Sfx.play("ok")
	Screens.pop()
end

function SpoolEditScreen:delete()
	local s = self.spool
	local inUse = U.find(Store.data.jobs, function(j) return j.spoolId == s.id and (j.status == "PRINTING" or j.status == "PAUSED") end)
	if inUse then
		Toast.show("SPOOL IS PRINTING", "warn")
		return
	end
	Confirm("DELETE THIS CARD?", function()
		local _, i = U.findById(Store.data.spools, s.id)
		if i then table.remove(Store.data.spools, i) end
		for _, j in ipairs(Store.data.jobs) do
			if j.spoolId == s.id then j.spoolId = nil end
		end
		Store.markDirty()
		Toast.show("CARD DELETED", "cross")
		Screens.pop()
	end)
end

function SpoolEditScreen:update()
	if self.form:update() then return end
	if Input.b() then
		Confirm("DISCARD CHANGES?", function() Screens.pop() end, nil, "DISCARD", "KEEP EDITING")
	end
end

function SpoolEditScreen:draw()
	Common.page(self.isNew and "NEW SPOOL" or "EDIT SPOOL", nil, self.form:hint() .. "   B:CANCEL")
	Draw.window(2, 17, 396, 208)
	self.form:draw()
end
