-- STATS OFFICE: derived statistics across every tool.
-- Pages: OVERVIEW / MATERIALS / CAUSES / PROJECTS / PRINTERS.

local gfx <const> = playdate.graphics

StatsScreen = {}
StatsScreen.__index = StatsScreen

StatsScreen.PAGES = { "OVERVIEW", "MATERIALS", "CAUSES", "PROJECTS", "PRINTERS" }

function StatsScreen.new()
	local s = setmetatable({ page = 1, list = ScrollList.new(8) }, StatsScreen)
	s:refresh()
	return s
end

function StatsScreen:refresh()
	local p = StatsScreen.PAGES[self.page]
	if p == "MATERIALS" then self.rows = Stats.combos()
	elseif p == "CAUSES" then self.rows = Stats.causes()
	elseif p == "PROJECTS" then self.rows = Stats.projects()
	elseif p == "PRINTERS" then self.rows = Store.data.printers
	else self.rows = {} end
	self.list:setCount(#self.rows)
end

function StatsScreen:update()
	self.list:update()
	local h = Input.horizontal()
	if h ~= 0 then
		self.page = U.wrap(self.page + h, #StatsScreen.PAGES)
		self.list:select(1)
		self:refresh()
		Sfx.play("move")
	end
	if Input.a() then
		local p = StatsScreen.PAGES[self.page]
		local row = self.rows[self.list.sel]
		if p == "MATERIALS" and row then
			Common.say({ text = Captain.comboReport(row.material, row.manufacturer), mood = "neutral" })
		elseif p == "CAUSES" and row then
			local r = Enums.CAUSE_REMEDY[row.cause]
			local text = string.format("%d %s failures. ", row.count, string.lower(Enums.CAUSE_LABEL[row.cause]))
			if r and r.calib then text = text .. "Try the " .. Phrases.procedureNames[r.calib] .. ". " end
			if r and r.maint then text = text .. "Check " .. string.lower(Enums.MAINT_LABEL[r.maint]) .. "." end
			Common.say({ text = text, mood = "stern" })
		elseif p == "OVERVIEW" then
			Common.help("stats")
		end
	elseif Input.b() then
		Sfx.play("back")
		Screens.pop()
	end
end

function StatsScreen:drawOverview()
	local o = Stats.overall()
	Draw.window(4, 34, 190, 190, { title = "ALL TIME" })
	local y = 46
	local function row(l, v) Draw.row(l, v, 14, y, 170) y = y + 12 end
	row("PRINTS", tostring(o.prints))
	row("SUCCESS", tostring(o.successes))
	row("FAILED", tostring(o.failures))
	row("CANCELLED", tostring(o.cancels))
	row("RATE", o.rate and U.fmtPct(o.rate * 100) or "--")
	row("HOURS", U.fmtHours(o.hours))
	row("PLASTIC", U.fmtGrams(o.grams))
	row("METRES", string.format("%.0f", Stats.metersPrinted()))
	row("COST", U.fmtMoney(Stats.filamentCost()))
	local streak = Store.activePrinter().stats.streak
	row("STREAK", string.format("%+d", streak))
	local t = Filament.totals()
	row("ON SHELF", U.fmtGrams(t.grams))
	row("SHELF VALUE", U.fmtMoney(t.value))

	Draw.window(198, 34, 198, 190, { title = "LAST 8 WEEKS" })
	local ok, bad = Stats.weekly(8)
	Draw.barChart(212, 50, 170, 90, ok, bad)
	Text.draw("SOLID = OK  DITHER = FAILED", 297, 146, { align = "center" })
	local causes = Stats.causes(60)
	Text.draw("TOP CAUSES (60D)", 212, 162)
	for i = 1, math.min(3, #causes) do
		Text.draw(string.format("%d  %s", causes[i].count, Enums.CAUSE_LABEL[causes[i].cause]), 212, 162 + i * 12)
	end
	if #causes == 0 then Text.draw("NONE. FAIR SEAS.", 212, 174) end
end

function StatsScreen:drawMaterials()
	Draw.window(4, 34, 392, 190)
	if #self.rows == 0 then
		Text.drawWrapped("No history yet. Finish or fail a print and it shows up here.", 20, 50, 360, 3)
		return
	end
	Text.draw("MATERIAL / MAKER      PRINTS FAIL  RATE  AVG NOZ  TOP CAUSE", 14, 42)
	for i, row in self.list:visible() do
		local a = self.rows[i]
		local y = 56 + row * 20
		Text.draw(U.padRight(a.material .. " / " .. U.truncate(a.manufacturer, 10), 21), 24, y)
		Text.draw(U.padLeft(tostring(a.prints), 6) .. U.padLeft(tostring(a.failures), 5), 150, y)
		Text.draw(a.rate and U.fmtPct(a.rate * 100) or "--", 226, y)
		Text.draw(a.avgNozzle and U.fmtTemp(a.avgNozzle) or "--", 262, y)
		Text.draw(a.topCause and U.truncate(Enums.CAUSE_LABEL[a.topCause], 10) or "-", 318, y)
		Draw.bar(24, y + 10, 120, 5, a.rate or 0)
		if i == self.list.sel then Draw.cursor(12, y + 1) end
	end
end

function StatsScreen:drawCauses()
	Draw.window(4, 34, 392, 190)
	if #self.rows == 0 then
		Text.drawWrapped("No failures logged. Either ye're very good, or very lucky.", 20, 50, 360, 3)
		return
	end
	local maxN = self.rows[1].count
	for i, row in self.list:visible() do
		local c = self.rows[i]
		local y = 46 + row * 20
		Text.draw(Enums.CAUSE_LABEL[c.cause], 24, y)
		Draw.bar(160, y, 190, 9, c.count / maxN, { pattern = "gray50" })
		Text.draw(tostring(c.count), 384, y, { align = "right" })
		if i == self.list.sel then Draw.cursor(12, y + 1) end
	end
end

function StatsScreen:drawProjects()
	Draw.window(4, 34, 392, 190)
	if #self.rows == 0 then
		Text.drawWrapped("No projects yet. Give a job a PROJECT in the queue editor to track it here.", 20, 50, 360, 3)
		return
	end
	for i, row in self.list:visible() do
		local p = self.rows[i]
		local y = 44 + row * 22
		Text.draw(U.truncate(p.name, 20), 24, y)
		Text.draw(string.format("%d OK %d X  %s  %s", p.successes, p.failures, U.fmtGrams(p.grams), U.fmtHours(p.hours)), 384, y, { align = "right" })
		Text.draw(string.format("%d OPEN  %d DONE  LAST %s", p.open, p.done, p.lastAt > 0 and U.fmtRelDays(p.lastAt) or "--"), 36, y + 10)
		if i == self.list.sel then Draw.cursor(12, y + 1) end
	end
end

function StatsScreen:drawPrinters()
	Draw.window(4, 34, 392, 190)
	for i, row in self.list:visible() do
		local p = self.rows[i]
		local y = 44 + row * 40
		local ps = p.stats
		Text.draw(p.name .. "  (" .. p.model .. ")", 24, y)
		Text.draw(string.format("%d PRINTS  %s  %s  RATE %s", ps.prints, U.fmtHours(Printer.hours(p)), U.fmtGrams(ps.grams),
			Printer.successRate(p) and U.fmtPct(Printer.successRate(p) * 100) or "--"), 36, y + 11)
		Text.draw("VIA " .. (Enums.PROVIDER_LABEL[p.provider] or p.provider) .. "  LAST " ..
			(ps.lastPrintAt > 0 and U.fmtRelDays(ps.lastPrintAt) or "NEVER"), 36, y + 22)
		if p.id == Store.data.settings.activePrinterId then Text.draw(FontData.icon.star, 384, y, { align = "right" }) end
		if i == self.list.sel then Draw.cursor(12, y + 1) end
	end
end

function StatsScreen:draw()
	Common.page("STATS OFFICE", nil, FontData.icon.left .. FontData.icon.right .. ":PAGE  A:ASK CAPTAIN  B:BACK", "checker")
	local x = 6
	for i, name in ipairs(StatsScreen.PAGES) do
		local w = Text.width(name) + 10
		gfx.setColor(gfx.kColorBlack)
		gfx.fillRect(x, 17, w, 13)
		if i ~= self.page then
			gfx.setColor(gfx.kColorWhite)
			gfx.fillRect(x + 1, 18, w - 2, 11)
		end
		Text.draw(name, x + 5, 19, { color = i == self.page and "white" or "black" })
		x = x + w + 3
	end
	local p = StatsScreen.PAGES[self.page]
	if p == "OVERVIEW" then self:drawOverview()
	elseif p == "MATERIALS" then self:drawMaterials()
	elseif p == "CAUSES" then self:drawCauses()
	elseif p == "PROJECTS" then self:drawProjects()
	else self:drawPrinters() end
end
