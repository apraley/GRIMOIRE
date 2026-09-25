-- FILAMENT ROLODEX.
--
-- One big index card per spool; the crank flips through them like a real
-- rolodex (the card squashes and swaps at the half-turn). Left/right change
-- the filter tab, A opens the card's actions, B leaves.

local gfx <const> = playdate.graphics

RolodexScreen = {}
RolodexScreen.__index = RolodexScreen

function RolodexScreen.new()
	local s = setmetatable({
		filter = 1,
		sort = 1,
		idx = 1,
		flip = 0,          -- -1..1 card flip animation phase
		flipDir = 0,
		ticker = CrankTicker.new(50),
	}, RolodexScreen)
	s:refresh()
	return s
end

function RolodexScreen:refresh()
	local keep = self.spools and self.spools[self.idx]
	self.spools = Filament.list({ filter = Filament.FILTERS[self.filter], sort = Filament.SORTS[self.sort] })
	self.idx = 1
	if keep then
		local _, i = U.findById(self.spools, keep.id)
		if i then self.idx = i end
	end
	self.idx = U.clamp(self.idx, 1, math.max(1, #self.spools))
end

function RolodexScreen:resume()
	self:refresh()
end

function RolodexScreen:current()
	return self.spools[self.idx]
end

function RolodexScreen:flipBy(d)
	if #self.spools < 2 then
		Sfx.play("error")
		return
	end
	self.idx = U.wrap(self.idx + d, #self.spools)
	self.flip = 1
	self.flipDir = d
	Sfx.play("flip")
end

function RolodexScreen:actions(s)
	local items = {
		{ label = "EDIT CARD", hint = s.notes ~= "" and U.truncate(s.notes, 60) or nil,
			action = function() Screens.push(SpoolEditScreen.new(s)) end },
		{ label = "WEIGH-IN", hint = "Set true grams left (spool weight minus empty spool).", action = function()
			Dial.open({ title = "WEIGH-IN", label = "FILAMENT LEFT", value = U.roundInt(s.remainingGrams), min = 0,
				max = s.nominalGrams, step = 1, unit = "g", degPerStep = 6,
				onAccept = function(v)
					Filament.setRemaining(s, v, "Weigh-in")
					Toast.show(Spool.shortLabel(s) .. " " .. U.fmtGrams(v), "check")
				end })
		end },
		{ label = "LOG USAGE", hint = "Filament used outside the queue.", action = function()
			Dial.open({ title = "LOG USAGE", label = "GRAMS USED", value = 10, min = 1,
				max = math.max(1, U.roundInt(s.remainingGrams)), step = 1, unit = "g", degPerStep = 8,
				onAccept = function(v)
					Filament.consume(s.id, v, "manual", nil, "Manual log")
					Toast.show("LOGGED " .. U.fmtGrams(v), "check")
				end })
		end },
		{ label = "USAGE HISTORY", action = function() Screens.push(SpoolLedgerScreen.new(s)) end },
		{ label = "PRINT STATS", action = function()
			Common.say({ text = Captain.comboReport(s.material, s.manufacturer), mood = "neutral" })
		end },
	}
	if s.dryness == "SEALED" then
		items[#items + 1] = { label = "OPEN THE SEAL", action = function() Filament.open(s) Toast.show("OPENED", "check") end }
	else
		items[#items + 1] = { label = "MARK DRIED", hint = "Resets the moisture clock.", action = function()
			Filament.markDried(s)
			Toast.show("DRIED " .. Spool.shortLabel(s), "drop")
		end }
	end
	items[#items + 1] = { label = "MOVE TO...", action = function() self:pickLocation(s) end }
	items[#items + 1] = { label = s.favorite and "UNFAVORITE" or "FAVORITE", action = function()
		s.favorite = not s.favorite
		Store.markDirty()
	end }
	items[#items + 1] = { label = "RESTOCK (NEW SPOOL)", hint = "Adds a sealed twin of this spool.", action = function()
		local n = Filament.restock(s)
		Toast.show("ADDED " .. Spool.shortLabel(n), "check")
		self:refresh()
	end }
	items[#items + 1] = { label = s.archived and "UNARCHIVE" or "ARCHIVE (EMPTY)", action = function()
		Filament.archive(s, not s.archived)
		self:refresh()
	end }
	items[#items + 1] = { label = "+ NEW SPOOL", action = function() Screens.push(SpoolEditScreen.new(nil)) end }
	items[#items + 1] = { label = "SORT: " .. Filament.SORTS[self.sort], action = function()
		self.sort = U.wrap(self.sort + 1, #Filament.SORTS)
		self:refresh()
		Toast.show("SORT BY " .. Filament.SORTS[self.sort], "check")
	end }
	items[#items + 1] = { label = "ASK THE CAPTAIN", action = function() Common.help("rolodex") end }
	Menu.open({ title = U.truncate(Spool.shortLabel(s), 24), items = items, maxRows = 10 })
end

RolodexScreen.LOCATIONS = { "AMS LITE 1", "AMS LITE 2", "AMS LITE 3", "AMS LITE 4", "EXTERNAL", "DRYBOX", "SHELF A", "SHELF B", "DRAWER" }

function RolodexScreen:pickLocation(s)
	local items = {}
	for _, loc in ipairs(RolodexScreen.LOCATIONS) do
		items[#items + 1] = { label = loc, action = function()
			-- One spool per AMS slot: bump whoever is there to the shelf.
			if string.find(loc, "^AMS") then
				for _, o in ipairs(Store.data.spools) do
					if o ~= s and o.location == loc then o.location = "SHELF A" end
				end
			end
			s.location = loc
			Store.markDirty()
			Toast.show(Spool.shortLabel(s) .. " -> " .. loc, "check")
		end }
	end
	items[#items + 1] = { label = "OTHER...", action = function()
		TextEntry.open("LOCATION", s.location, function(t) if t ~= "" then s.location = U.upper(t) Store.markDirty() end end, 16)
	end }
	Menu.open({ title = "MOVE TO", items = items, maxRows = 10 })
end

function RolodexScreen:update()
	if self.flip > 0 then self.flip = math.max(0, self.flip - 0.25) end
	local t = self.ticker:update()
	if t ~= 0 then self:flipBy(t > 0 and 1 or -1) end
	local v = Input.vertical()
	if v ~= 0 then self:flipBy(v) end
	local h = Input.horizontal()
	if h ~= 0 then
		self.filter = U.wrap(self.filter + h, #Filament.FILTERS)
		self.spools = nil
		self:refresh()
		self.idx = 1
		Sfx.play("move")
	end
	if Input.a() then
		local s = self:current()
		if s then self:actions(s)
		else Screens.push(SpoolEditScreen.new(nil)) end
	elseif Input.b() then
		Sfx.play("back")
		Screens.pop()
	end
end

---------------------------------------------------------------------------

function RolodexScreen:drawTabs()
	local x = 4
	for i, name in ipairs(Filament.FILTERS) do
		local w = Text.width(name) + 6
		gfx.setColor(gfx.kColorBlack)
		if i == self.filter then
			gfx.fillRect(x, 17, w, 13)
			Text.draw(name, x + 3, 19, { color = "white" })
		else
			gfx.drawRect(x, 17, w, 13)
			Text.draw(name, x + 3, 19, { color = "black" })
		end
		x = x + w + 2
	end
end

-- The card itself (always black ink on white "paper").
function RolodexScreen:drawCard(s, x, y, w, h)
	local low = Store.settings().lowSpoolGrams
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRect(x, y, w, h)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawRect(x, y, w, h)
	gfx.drawRect(x + 1, y + 1, w - 2, h - 2)
	-- Rolodex slots at the bottom.
	gfx.fillRect(x + w // 2 - 40, y + h - 6, 14, 6)
	gfx.fillRect(x + w // 2 + 26, y + h - 6, 14, 6)
	-- Index tab with the material.
	gfx.fillRect(x + 12, y - 10, 50, 11)
	Text.draw(s.material, x + 37, y - 9, { color = "white", align = "center" })
	-- Header.
	Text.draw(U.truncate(s.manufacturer, 16), x + 12, y + 8, { color = "black", scale = 2 })
	Text.draw(s.color .. "  " .. s.id, x + 12, y + 28, { color = "black" })
	if s.favorite then Text.draw(FontData.icon.heart, x + w - 16, y + 8, { color = "black" }) end
	gfx.drawLine(x + 8, y + 40, x + w - 8, y + 40)

	-- Spool picture with fill, and grams.
	Sprites.spool(x + 42, y + 72, 27, Spool.pct(s), s.color)
	local gx = x + 86
	local gy = y + 44
	Text.draw(U.fmtGrams(s.remainingGrams), gx, gy, { color = "black", scale = 2 })
	Text.draw("OF " .. U.fmtGrams(s.nominalGrams) .. "  " .. U.fmtPct(Spool.pct(s) * 100), gx, gy + 20, { color = "black" })
	Draw.bar(gx, gy + 32, w - (gx - x) - 12, 7, Spool.pct(s), { color = gfx.kColorBlack })
	local days = Filament.daysUntilEmpty(s)
	Text.draw(string.format("%.0fM LEFT", Spool.metersRemaining(s)) .. (days and ("  EMPTY ~" .. days .. "D") or ""), gx, gy + 44, { color = "black" })
	if Spool.isLow(s, low) then
		if Draw.blinkOn then
			gfx.fillRect(x + w - 58, y + 28, 50, 11)
			Text.draw(FontData.icon.warn .. " LOW", x + w - 33, y + 29, { color = "white", align = "center" })
		end
	end

	-- Facts in two columns.
	local fy = y + 104
	local col = (w - 36) // 2
	local lx, rx = x + 12, x + 24 + col
	local function fact(label, value, cx, cy)
		Draw.row(label, value, cx, cy, col, "black")
	end
	fact("COST", U.fmtMoney(s.cost), lx, fy)
	fact("PER G", string.format("$%.3f", Spool.costPerGram(s)), rx, fy)
	fy = fy + 11
	fact("VALUE", U.fmtMoney(Spool.valueRemaining(s)), lx, fy)
	fact("MOISTURE", s.dryness, rx, fy)
	fy = fy + 11
	fact("WHERE", U.truncate(s.location, 10), lx, fy)
	fact("TEMPS", s.favNozzle > 0 and (s.favNozzle .. "/" .. s.favBed) or "--", rx, fy)
	fy = fy + 11
	local rate = Spool.successRate(s)
	fact("PRINTS", s.successCount .. " OK " .. s.failCount .. " X", lx, fy)
	fact("RATE", rate and U.fmtPct(rate * 100) or "--", rx, fy)
	fy = fy + 11
	fact("BOUGHT", U.fmtShortDate(s.purchasedAt), lx, fy)
	fact("OPENED", s.openedAt > 0 and U.fmtShortDate(s.openedAt) or "SEALED", rx, fy)
end

function RolodexScreen:draw()
	local total = Filament.totals()
	local right = #self.spools > 0 and string.format("%d/%d  SORT:%s", self.idx, #self.spools, Filament.SORTS[self.sort]) or nil
	Common.page("FILAMENT ROLODEX", right,
		"CRANK:FLIP  " .. FontData.icon.left .. FontData.icon.right .. ":FILTER  A:ACTIONS  B:BACK", "dots")
	self:drawTabs()
	local x, y, w, h = 40, 50, 320, 170
	-- Card stack behind: offset edges suggest more cards.
	local behind = math.min(4, math.max(0, #self.spools - 1))
	for i = behind, 1, -1 do
		gfx.setColor(gfx.kColorWhite)
		gfx.fillRect(x + i * 3, y - i * 2, w, 20)
		gfx.setColor(gfx.kColorBlack)
		gfx.drawRect(x + i * 3, y - i * 2, w, 20)
	end
	-- Rolodex drum with shelf totals on it.
	gfx.setColor(gfx.kColorBlack)
	gfx.fillRect(x - 30, 216, w + 60, 11)
	gfx.fillCircleAtPoint(x - 30, 221, 7)
	gfx.fillCircleAtPoint(x + w + 30, 221, 7)
	Text.draw(string.format("%d SPOOLS  %s  %s ON THE SHELF  %d LOW", total.spools, U.fmtGrams(total.grams),
		U.fmtMoney(total.value), total.low), 200, 217, { color = "white", align = "center" })
	local s = self:current()
	if s == nil then
		local msg = self.filter == 1 and "No spools yet. Press A to add yer first spool." or "No spools match this filter."
		gfx.setColor(gfx.kColorWhite)
		gfx.fillRect(x, y, w, h - 6)
		gfx.setColor(gfx.kColorBlack)
		gfx.drawRect(x, y, w, h - 6)
		Text.draw("EMPTY", x + w // 2, y + 30, { color = "black", align = "center", scale = 2 })
		Text.drawWrapped(msg, x + 20, y + 70, w - 40, 4, { color = "black" })
		return
	end
	if self.flip > 0 then
		-- Mid-flip: the card squashes vertically toward its top ring.
		local squash = math.abs(math.cos(self.flip * math.pi / 2))
		local ch = math.max(8, math.floor((h - 6) * (1 - squash * 0.85)))
		gfx.setColor(gfx.kColorWhite)
		gfx.fillRect(x, y, w, ch)
		gfx.setColor(gfx.kColorBlack)
		gfx.drawRect(x, y, w, ch)
		Draw.fillPattern("light25", x + 2, y + 2, w - 4, ch - 4)
	else
		self:drawCard(s, x, y, w, h - 6)
	end
end

---------------------------------------------------------------------------
-- Spool ledger: weekly usage chart + consumption rows.

SpoolLedgerScreen = {}
SpoolLedgerScreen.__index = SpoolLedgerScreen

function SpoolLedgerScreen.new(spool)
	local s = setmetatable({ spool = spool, list = ScrollList.new(9) }, SpoolLedgerScreen)
	s.rows = Filament.ledger(spool.id)
	s.list:setCount(#s.rows)
	return s
end

function SpoolLedgerScreen:update()
	self.list:update()
	if Input.b() or Input.a() then
		Sfx.play("back")
		Screens.pop()
	end
end

function SpoolLedgerScreen:draw()
	local s = self.spool
	Common.page("USAGE: " .. U.truncate(Spool.shortLabel(s), 26), nil, "CRANK/" .. FontData.icon.up .. FontData.icon.down .. ":SCROLL  B:BACK")
	Draw.window(4, 20, 180, 204, { title = "LAST 8 WEEKS" })
	local weeks = Filament.weeklyUsage(s.id, 8)
	Draw.barChart(16, 34, 156, 70, weeks)
	local total = U.sum(weeks)
	Draw.row("8 WK TOTAL", U.fmtGrams(total), 16, 112, 156)
	Draw.row("AVG / WEEK", U.fmtGrams(total / 8), 16, 123, 156)
	Draw.row("ALL TIME", U.fmtGrams(s.usedGrams), 16, 134, 156)
	Draw.row("SPENT", U.fmtMoney(Filament.cost(s, s.usedGrams)), 16, 145, 156)
	local st = Stats.forSpool(s.id)
	Draw.row("PRINT HOURS", U.fmtHours(st.hours), 16, 156, 156)
	Draw.row("AVG NOZZLE", st.avgNozzle and U.fmtTemp(st.avgNozzle) or "--", 16, 167, 156)
	Draw.row("TOP FAILURE", st.topCause and U.truncate(Enums.CAUSE_LABEL[st.topCause], 10) or "NONE", 16, 178, 156)
	local days = Filament.daysUntilEmpty(s)
	Draw.row("EMPTY IN", days and (days .. " DAYS") or "IDLE", 16, 189, 156)

	Draw.window(188, 20, 208, 204, { title = "LEDGER" })
	if #self.rows == 0 then
		Text.drawWrapped("No usage logged yet. Finished prints and weigh-ins show up here.", 200, 34, 184, 6)
		return
	end
	for i, row in self.list:visible() do
		local c = self.rows[i]
		local y = 32 + row * 20
		Text.draw(U.fmtShortDate(c.at) .. " " .. U.upper(c.kind), 208, y)
		Text.draw((c.grams >= 0 and "-" or "+") .. U.fmtGrams(math.abs(c.grams)), 388, y, { align = "right" })
		Text.draw(U.truncate(U.upper(c.note), 28), 208, y + 9)
		if i == self.list.sel then Draw.cursor(196, y + 1) end
	end
	self.list:drawScrollbar(390, 30, 188)
end
