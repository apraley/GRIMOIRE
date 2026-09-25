-- Runs one calibration procedure step by step (see data/calibration_defs.lua).
-- The crank does the heavy lifting: dials, towers and grids are all
-- crank-driven. Results land in a profile only when the user saves the
-- summary.

local gfx <const> = playdate.graphics

CalibRunScreen = {}
CalibRunScreen.__index = CalibRunScreen

function CalibRunScreen.new(proc, key)
	local s = setmetatable({
		proc = proc,
		key = key,
		ctx = CalService.context(key),
		step = 0,
		results = {},
		checks = { all = true },
		notes = "",
		ticker = CrankTicker.new(30),
	}, CalibRunScreen)
	s:gotoStep(1)
	return s
end

function CalibRunScreen:def()
	return self.proc.steps[self.step]
end

function CalibRunScreen:gotoStep(i)
	self.step = U.clamp(i, 1, #self.proc.steps)
	local st = self:def()
	self.dial = nil
	self.checked = nil
	self.pickIdx = nil
	self.typer = nil
	if st.type == "info" then
		self.typer = Dialog.new({ st.text }, { overlay = false, x = 16, y = 44, w = 368, h = 150, speed = 3 })
	elseif st.type == "dial" or st.type == "measure" then
		local v = st.default and st.default(self.ctx, self.results) or st.min
		if self.results[st.field] ~= nil then v = self.results[st.field] end
		self.dial = Dial.new({ title = st.title, label = st.label, value = v, min = st.min, max = st.max,
			step = st.step, fmt = st.fmt, unit = st.unit, labels = st.labels, hint = st.hint, target = st.target,
			degPerStep = st.type == "measure" and 6 or 12 })
	elseif st.type == "check" then
		self.checked = {}
		self.list = ScrollList.new(9, { crank = true })
		self.list:setCount(#st.items + 1)
	elseif st.type == "pick" then
		self.values = st.values(self.ctx)
		local def = self.results[st.field] or (st.default and st.default(self.ctx, self.results))
		self.pickIdx = 1
		local best = math.huge
		for idx, v in ipairs(self.values) do
			local dlt = math.abs(v - (def or 0))
			if dlt < best then best, self.pickIdx = dlt, idx end
		end
	elseif st.type == "summary" then
		self.computed = self.proc.compute(self.results, self.ctx, self.checks) or {}
	end
end

function CalibRunScreen:next()
	Sfx.play("ok")
	if self.step < #self.proc.steps then self:gotoStep(self.step + 1) end
end

function CalibRunScreen:back()
	Sfx.play("back")
	if self.step > 1 then
		self:gotoStep(self.step - 1)
	else
		Confirm("QUIT THIS PROCEDURE?", function() Screens.pop() end)
	end
end

function CalibRunScreen:save(recommend)
	local fields = self.computed or {}
	local p, _, touched = CalService.save(self.proc.id, self.key, fields, self.notes, recommend)
	Sfx.play("done")
	Toast.show("SAVED TO " .. Calibration.label(p), "star")
	if touched > 0 then Toast.show(touched .. " QUEUED JOBS UPDATED", "check") end
	Screens.pop()
end

function CalibRunScreen:update(dtMs)
	local st = self:def()
	if st.type == "info" then
		self.typer:tick(dtMs)
		if Input.a() then
			if self.typer:done() then
				if self.typer.page < #self.typer.pages then self.typer:advance() else self:next() end
			else
				self.typer.shown = self.typer.total
			end
		elseif Input.b() then self:back() end
	elseif st.type == "dial" or st.type == "measure" then
		self.dial:handle(dtMs)
		if Input.a() then
			self.results[st.field] = self.dial.value
			self:next()
		elseif Input.b() then self:back() end
	elseif st.type == "check" then
		self.list:update()
		if Input.a() then
			local i = self.list.sel
			if i <= #st.items then
				self.checked[i] = not self.checked[i]
				Sfx.play(self.checked[i] and "ok" or "back")
				if self.checked[i] then self.list:move(1) end
			else
				local all = true
				for k = 1, #st.items do if not self.checked[k] then all = false end end
				if all or st.optional then
					if not all then self.checks.all = false end
					self:next()
				else
					Confirm("SKIP UNCHECKED ITEMS?", function()
						self.checks.all = false
						self:next()
					end, nil, "SKIP", "GO BACK")
				end
			end
		elseif Input.b() then self:back() end
	elseif st.type == "pick" then
		local d = self.ticker:update() + Input.vertical() + Input.horizontal()
		if d ~= 0 then
			local before = self.pickIdx
			self.pickIdx = U.clamp(self.pickIdx + (d > 0 and 1 or -1), 1, #self.values)
			Sfx.play(before ~= self.pickIdx and "tick" or "error")
		end
		if Input.a() then
			self.results[st.field] = self.values[self.pickIdx]
			self:next()
		elseif Input.b() then self:back() end
	elseif st.type == "summary" then
		if Input.a() then
			Menu.open({ title = "SAVE RESULTS", items = {
				{ label = "SAVE + RECOMMEND", hint = "New jobs and spool favourites use it.", action = function() self:save(true) end },
				{ label = "SAVE ONLY", action = function() self:save(nil) end },
				{ label = "ADD A NOTE", action = function()
					TextEntry.open("NOTE", self.notes, function(t) self.notes = t end, 60)
				end },
				{ label = "DISCARD", action = function() Screens.pop() end },
			} })
		elseif Input.b() then self:back() end
	end
end

---------------------------------------------------------------------------

function CalibRunScreen:drawProgress()
	local n = #self.proc.steps
	local w = 380
	for i = 1, n do
		local x = 10 + math.floor((i - 1) * w / n)
		local sw = math.floor(w / n) - 4
		gfx.setColor(gfx.kColorBlack)
		if i < self.step then gfx.fillRect(x, 19, sw, 5)
		elseif i == self.step then
			Draw.fillPattern("gray50", x, 19, sw, 5)
			gfx.setColor(gfx.kColorBlack)
			gfx.drawRect(x, 19, sw, 5)
		else gfx.drawRect(x, 19, sw, 5) end
	end
end

function CalibRunScreen:fmtValue(st, v)
	local s = string.format(st.fmt or "%g", v)
	if st.unit == "C" then return s .. FontData.icon.deg .. "C" end
	return s .. (st.unit or "")
end

function CalibRunScreen:draw()
	local st = self:def()
	local ctxLabel = self.ctx.material .. "/" .. self.ctx.manufacturer
	local hints = "A:NEXT  B:BACK"
	if st.type == "dial" or st.type == "measure" then hints = "CRANK:ADJUST  A:ACCEPT  B:BACK"
	elseif st.type == "pick" then hints = "CRANK:CHOOSE  A:ACCEPT  B:BACK"
	elseif st.type == "check" then hints = "A:TICK  CRANK/" .. FontData.icon.up .. FontData.icon.down .. ":MOVE  B:BACK"
	elseif st.type == "summary" then hints = "A:SAVE  B:BACK" end
	Common.page(self.proc.title, ctxLabel, hints, "light25")
	self:drawProgress()
	local title = (st.title or "") .. "  " .. self.step .. "/" .. #self.proc.steps

	if st.type == "info" then
		Draw.window(8, 34, 384, 170, { title = title })
		self.typer:drawBox()
		Sprites.captainPortrait(338, 150, "neutral", not self.typer:done())
	elseif st.type == "dial" or st.type == "measure" then
		Draw.window(40, 38, 320, 170, { title = title })
		self.dial:drawBody(40, 50, 320, 150)
		local old = self.ctx.profile and self.ctx.profile[st.field]
		if old ~= nil and not (old == 0 and (st.field == "nozzleTemp" or st.field == "bedTemp")) then
			Text.draw("PROFILE NOW: " .. self:fmtValue(st, old), 200, 188, { align = "center" })
		end
	elseif st.type == "check" then
		Draw.window(8, 34, 384, 170, { title = title })
		for i, row in self.list:visible() do
			local y = 48 + row * 16
			if i <= #st.items then
				Draw.checkbox(30, y, self.checked[i])
				Text.draw(st.items[i], 44, y)
			else
				Text.draw(st.optional and "DONE" or "ALL DONE " .. FontData.icon.right, 44, y)
			end
			if i == self.list.sel then Draw.cursor(16, y) end
		end
	elseif st.type == "pick" then
		gfx.setColor(gfx.kColorWhite)
		gfx.fillRect(8, 34, 384, 170)
		gfx.setColor(gfx.kColorBlack)
		gfx.drawRect(8, 34, 384, 170)
		Text.draw(title, 16, 38, { color = "black" })
		local labels = U.map(self.values, function(v) return self:fmtValue(st, v) end)
		if st.style == "grid" then
			local cols = math.min(5, #labels)
			Sprites.flowGrid(200 - (cols * 50 - 6) // 2, 58, labels, self.pickIdx, cols)
		else
			-- Long towers (e.g. OTHER spans 180-300C) scroll in a window of
			-- at most 11 floors around the selection.
			local maxFloors = 11
			local first = 1
			if #labels > maxFloors then
				first = U.clamp(self.pickIdx - maxFloors // 2, 1, #labels - maxFloors + 1)
			end
			local shown = {}
			for i = first, math.min(#labels, first + maxFloors - 1) do shown[#shown + 1] = labels[i] end
			local floorH = math.max(12, math.min(16, 150 // #shown))
			local ty = 52
			Sprites.tower(210, ty, 60, shown, self.pickIdx - first + 1, floorH)
			Draw.cursor(192, ty + (self.pickIdx - first) * floorH + (floorH - 9) // 2, gfx.kColorBlack)
			if first > 1 then Text.draw(FontData.icon.up, 236, 42, { color = "black" }) end
			if first + #shown - 1 < #labels then
				Text.draw(FontData.icon.down, 196, ty + #shown * floorH - 10, { color = "black" })
			end
		end
		if st.style == "grid" then
			Text.draw(st.label .. ": " .. labels[self.pickIdx], 200, 160, { color = "black", align = "center", scale = 2 })
			if st.hint then Text.draw(st.hint, 200, 182, { color = "black", align = "center" }) end
		else
			-- Tower on the right half; the reading on the left.
			Text.draw(st.label, 20, 70, { color = "black" })
			Text.draw(labels[self.pickIdx], 20, 84, { color = "black", scale = 2 })
			if st.hint then Text.drawWrapped(st.hint, 20, 110, 100, 3, { color = "black" }) end
			Text.draw(FontData.icon.crank .. " TURN CRANK", 20, 186, { color = "black" })
		end
	elseif st.type == "summary" then
		Draw.window(8, 34, 384, 170, { title = "RESULTS  " .. title })
		local y = 50
		local any = false
		for _, f in ipairs(Calibration.FIELDS) do
			local v = self.computed[f[1]]
			if v ~= nil then
				any = true
				local old = self.ctx.profile and Calibration.fmtField(self.ctx.profile, f) or "--"
				local new = Calibration.fmtField({ [f[1]] = v }, f)
				Text.draw(f[2], 30, y)
				Text.draw(old, 220, y, { align = "right" })
				Text.draw(FontData.icon.right, 236, y)
				Text.draw(new, 360, y, { align = "right", scale = 1 })
				y = y + 14
			end
		end
		if not any then Text.draw("NOTHING TO SAVE.", 200, 60, { align = "center" }) end
		y = y + 6
		Text.drawWrapped("Saved to " .. self.key .. ". Recommended profiles feed new jobs and spool favourites.", 30, y, 340, 3)
		if self.notes ~= "" then Text.drawWrapped('"' .. self.notes .. '"', 30, 180, 340, 1) end
	end
end
