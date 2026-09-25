-- CALIBRATION WIZARD: procedure list, stored profiles, profile detail.

local gfx <const> = playdate.graphics

CalibScreen = {}
CalibScreen.__index = CalibScreen

CalibScreen.TABS = { "PROCEDURES", "PROFILES" }

function CalibScreen.new()
	local s = setmetatable({ tab = 1, list = ScrollList.new(6) }, CalibScreen)
	s:refresh()
	return s
end

function CalibScreen:refresh()
	if self.tab == 1 then
		self.rows = CalibDefs.list
	else
		self.rows = CalService.profiles(Store.activePrinter().id)
	end
	self.list:setCount(#self.rows)
end

function CalibScreen:resume() self:refresh() end

-- Choose what to calibrate: a spool (printer + material + maker) or a
-- material-wide profile.
function CalibScreen:pickTarget(proc)
	local printer = Store.activePrinter()
	local items = {}
	local seen = {}
	for _, s in ipairs(Filament.list({ filter = "ALL", sort = "MATERIAL" })) do
		local key = Calibration.key(printer.id, s.material, s.manufacturer)
		if not seen[key] then
			seen[key] = true
			local p = CalService.profile(key)
			items[#items + 1] = { label = s.material .. " / " .. s.manufacturer,
				right = p and (FontData.icon.star .. p.runs) or "NEW",
				hint = "From spool " .. Spool.shortLabel(s),
				action = function() Screens.push(CalibRunScreen.new(proc, key)) end }
		end
	end
	for _, m in ipairs(Enums.MATERIALS) do
		local key = Calibration.key(printer.id, m, "ANY")
		items[#items + 1] = { label = m .. " / ANY MAKER", right = CalService.profile(key) and FontData.icon.star or "",
			action = function() Screens.push(CalibRunScreen.new(proc, key)) end }
	end
	Menu.open({ title = "CALIBRATE WHAT?", items = items, maxRows = 10 })
end

function CalibScreen:update()
	-- Data changed underneath (a print finished, a menu action ran): refresh.
	if self.rev ~= Memo.rev and true then
		self.rev = Memo.rev
		self:refresh()
	end
	self.list:update()
	local h = Input.horizontal()
	if h ~= 0 then
		self.tab = U.wrap(self.tab + h, #CalibScreen.TABS)
		self.list:select(1)
		self:refresh()
		Sfx.play("move")
	end
	if Input.a() then
		local row = self.rows[self.list.sel]
		if row == nil then return end
		if self.tab == 1 then
			local proc = row
			Menu.open({ title = proc.title, items = {
				{ label = "START", action = function() self:pickTarget(proc) end },
				{ label = "WHAT IS THIS?", action = function()
					Dialog.open({ proc.blurb, proc.steps[1].text or "" }, { speaker = "CAPTAIN",
						portrait = function(x, y) Sprites.captainPortrait(x, y, "neutral", false) end })
				end },
				{ label = "ASK THE CAPTAIN", action = function() Common.help("calibrate") end },
			} })
		else
			Screens.push(ProfileScreen.new(row))
		end
	elseif Input.b() then
		Sfx.play("back")
		Screens.pop()
	end
end

function CalibScreen:draw()
	Common.page("CALIBRATION WIZARD", Store.activePrinter().name,
		FontData.icon.left .. FontData.icon.right .. ":TAB  A:OPEN  B:BACK", "gray50")
	local x = 6
	for i, name in ipairs(CalibScreen.TABS) do
		local w = Text.width(name) + 10
		gfx.setColor(gfx.kColorBlack)
		gfx.fillRect(x, 17, w, 13)
		if i ~= self.tab then
			gfx.setColor(gfx.kColorWhite)
			gfx.fillRect(x + 1, 18, w - 2, 11)
		end
		Text.draw(name, x + 5, 19, { color = i == self.tab and "white" or "black" })
		x = x + w + 3
	end
	Draw.window(4, 34, 392, 190)
	if self.tab == 1 then
		for i, row in self.list:visible() do
			local p = self.rows[i]
			local y = 44 + row * 25
			Text.draw(p.title, 26, y)
			Text.draw(p.blurb, 26, y + 11)
			local last = CalService.lastRun(p.id)
			Text.draw(last and U.fmtRelDays(last.at) or "NEVER", 386, y, { align = "right" })
			if i == self.list.sel then Draw.cursor(12, y + 1) end
		end
		-- Suggestions from failures, if any.
		local sug = U.find(Stats.suggestions(), function(s) return s.kind == "calib" end)
		if sug then
			Text.draw(FontData.icon.anchor .. " CAPTAIN SUGGESTS: " .. U.upper(Phrases.procedureNames[sug.target] or sug.target)
				.. " (" .. sug.material .. "/" .. U.truncate(sug.manufacturer, 8) .. ")", 200, 212, { align = "center" })
		end
	else
		if #self.rows == 0 then
			Text.drawWrapped("No profiles yet. Run any procedure and its results become a profile for that printer, material and maker.", 20, 50, 360, 6)
			return
		end
		for i, row in self.list:visible() do
			local p = self.rows[i]
			local y = 44 + row * 25
			Text.draw((p.recommended and FontData.icon.star .. " " or "  ") .. Calibration.label(p), 26, y)
			local n, total = Calibration.completeness(p)
			Draw.bar(26, y + 12, 120, 6, n / total)
			Text.draw(n .. "/" .. total .. " FIELDS", 152, y + 11)
			Text.draw(p.nozzleTemp > 0 and U.fmtTemp(p.nozzleTemp) or "--", 300, y, { align = "right" })
			Text.draw(p.updatedAt > 0 and U.fmtRelDays(p.updatedAt) or "", 386, y, { align = "right" })
			if i == self.list.sel then Draw.cursor(12, y + 1) end
		end
	end
	self.list:drawScrollbar(388, 40, 176)
end

---------------------------------------------------------------------------
-- Profile detail

ProfileScreen = {}
ProfileScreen.__index = ProfileScreen

function ProfileScreen.new(profile)
	return setmetatable({ p = profile }, ProfileScreen)
end

function ProfileScreen:update()
	if Input.a() then
		local p = self.p
		local items = {
			{ label = p.recommended and "STOP RECOMMENDING" or "RECOMMEND FOR NEW JOBS", action = function()
				CalService.setRecommended(p, not p.recommended)
				Toast.show(p.recommended and "RECOMMENDED" or "NOT RECOMMENDED", "star")
			end },
		}
		for _, proc in ipairs(CalibDefs.list) do
			items[#items + 1] = { label = "RUN " .. proc.short, action = function() Screens.push(CalibRunScreen.new(proc, p.key)) end }
		end
		items[#items + 1] = { label = "PRINT STATS", action = function()
			Common.say({ text = Captain.comboReport(p.material, p.manufacturer), mood = "neutral" })
		end }
		items[#items + 1] = { label = "DELETE PROFILE", action = function()
			Confirm("DELETE PROFILE?", function() CalService.delete(p) Screens.pop() end)
		end }
		Menu.open({ title = Calibration.label(p), items = items, maxRows = 10 })
	elseif Input.b() then
		Sfx.play("back")
		Screens.pop()
	end
end

function ProfileScreen:draw()
	local p = self.p
	Common.page("PROFILE", Calibration.label(p), "A:ACTIONS  B:BACK", "gray50")
	Draw.window(4, 20, 190, 204, { title = p.recommended and "RECOMMENDED" or "STORED" })
	local y = 32
	for _, f in ipairs(Calibration.FIELDS) do
		Draw.row(f[2], Calibration.fmtField(p, f), 14, y, 170)
		y = y + 12
	end
	y = y + 4
	Draw.row("RUNS", tostring(p.runs), 14, y, 170)
	Draw.row("UPDATED", p.updatedAt > 0 and U.fmtShortDate(p.updatedAt) or "--", 14, y + 12, 170)

	Draw.window(198, 20, 198, 204, { title = "HISTORY" })
	local runs = CalService.runsFor(p.key, 6)
	if #runs == 0 then
		Text.drawWrapped("No runs yet.", 210, 34, 176, 3)
	end
	y = 32
	for _, r in ipairs(runs) do
		local def = CalibDefs.byId[r.procedure]
		Text.draw(U.fmtShortDate(r.at) .. " " .. (def and def.short or r.procedure), 210, y)
		local parts = {}
		for k, v in pairs(r.results) do
			if type(v) == "number" then parts[#parts + 1] = string.format("%s %g", k, U.round(v, 2)) end
		end
		table.sort(parts)
		Text.draw(U.truncate(table.concat(parts, " "), 29), 210, y + 10)
		y = y + 25
	end
	-- Stats for this combo.
	local a = Stats.combo(p.material, p.manufacturer ~= "ANY" and p.manufacturer or nil)
	if a.prints > 0 then
		Text.draw(string.format("%d PRINTS %d FAILS", a.prints, a.failures), 210, 202)
	end
end
