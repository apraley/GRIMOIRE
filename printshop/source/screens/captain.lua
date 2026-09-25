-- THE BENCHY CAPTAIN's dock: his Benchy bobs on a dithered sea while he
-- talks. Topics on the right; his words type out in the box below.

local gfx <const> = playdate.graphics

CaptainScreen = {}
CaptainScreen.__index = CaptainScreen

CaptainScreen.TOPICS = {
	{ id = "news", label = "ANY NEWS?" },
	{ id = "advice", label = "ADVICE" },
	{ id = "shop", label = "SHOP REPORT" },
	{ id = "wisdom", label = "WISDOM" },
	{ id = "explain", label = "EXPLAIN..." },
	{ id = "bye", label = "FAREWELL" },
}

function CaptainScreen.new()
	local s = setmetatable({
		list = ScrollList.new(#CaptainScreen.TOPICS),
		mood = "happy",
		dialog = nil,
	}, CaptainScreen)
	s.list:setCount(#CaptainScreen.TOPICS)
	return s
end

function CaptainScreen:enter()
	local first
	if Captain.hasNews() then
		first = Captain.nextNews()
	else
		first = Captain.greeting()
	end
	self:say(first)
end

function CaptainScreen:say(line)
	self.mood = line.mood or "neutral"
	self.dialog = Dialog.new({ line.text }, { overlay = false, x = 6, y = 150, w = 388, h = 74,
		speaker = "CAPTAIN",
		portrait = function(x, y) Sprites.captainPortrait(x, y, self.mood, self.dialog and not self.dialog:done()) end })
	-- The dialog lives inside this screen; closing just clears it.
	self.dialog.close = function() self.dialog = nil end
end

function CaptainScreen:sayPages(pages, mood)
	self.mood = mood or "neutral"
	self.dialog = Dialog.new(pages, { overlay = false, x = 6, y = 150, w = 388, h = 74, speaker = "CAPTAIN",
		portrait = function(x, y) Sprites.captainPortrait(x, y, self.mood, self.dialog and not self.dialog:done()) end })
	self.dialog.close = function() self.dialog = nil end
end

function CaptainScreen:shopReport()
	local o = Stats.overall()
	local q = Queue.backlog()
	local t = Filament.totals()
	local due = MaintService.dueSoon(Store.activePrinter().id)
	local pages = {
		string.format("Logbook: %d prints, %d failed. Success rate %s. %s of plastic, %.0f metres.",
			o.prints, o.failures, o.rate and U.fmtPct(o.rate * 100) or "--", U.fmtGrams(o.grams), Stats.metersPrinted()),
		string.format("Hold: %d spools, %s of filament worth %s. %d running low.",
			t.spools, U.fmtGrams(t.grams), U.fmtMoney(t.value), t.low),
		string.format("Queue: %d jobs waiting, about %s of printing.", q.count, U.fmtDuration(q.minutes * 60)),
	}
	if #due > 0 then
		pages[#pages + 1] = "Chores: " .. due[1].task.name .. " is " .. string.lower(Maint.fmtNext(due[1].st)) .. "."
	end
	local combos = Stats.combos()
	if combos[1] then
		local c = combos[1]
		pages[#pages + 1] = Captain.comboReport(c.material, c.manufacturer)
	end
	self:sayPages(pages, "neutral")
end

function CaptainScreen:choose(id)
	if id == "news" then
		local n = Captain.nextNews()
		if n then self:say(n)
		else self:say({ text = "No news, matey. Calm seas. Ask me for advice if ye want me opinion.", mood = "neutral" }) end
	elseif id == "advice" then
		self:say(Captain.advice())
	elseif id == "shop" then
		self:shopReport()
	elseif id == "wisdom" then
		self:say(Captain.wisdom())
	elseif id == "explain" then
		local items = {}
		for _, f in ipairs({ "home", "watch", "queue", "rolodex", "calibrate", "maint", "stats", "settings", "captain" }) do
			items[#items + 1] = { label = U.upper(f == "home" and "workshop" or f), action = function()
				self:sayPages(Captain.explain(f), "neutral")
			end }
		end
		Menu.open({ title = "EXPLAIN", items = items, maxRows = 9 })
	elseif id == "bye" then
		Sfx.play("back")
		Screens.pop()
	end
end

function CaptainScreen:update(dtMs)
	if self.dialog then
		self.dialog:tick(dtMs)
		if Input.a() then self.dialog:advance()
		elseif Input.b() then
			if self.dialog:done() then self.dialog = nil else self.dialog.shown = self.dialog.total end
		end
		return
	end
	self.list:update()
	if Input.a() then
		self:choose(CaptainScreen.TOPICS[self.list.sel].id)
	elseif Input.b() then
		Sfx.play("back")
		Screens.pop()
	end
end

function CaptainScreen:draw()
	gfx.clear(gfx.kColorWhite)
	Draw.titleBar("THE BENCHY CAPTAIN", Captain.hasNews() and "NEWS!" or nil)
	-- Sky with a few dithered clouds.
	Draw.fillPattern("light12", 0, 15, 400, 80)
	gfx.setColor(gfx.kColorWhite)
	local drift = (Draw.t // 80) % 440
	gfx.fillEllipseInRect(420 - drift, 26, 60, 14)
	gfx.fillEllipseInRect(200 - drift // 2, 40, 44, 10)
	gfx.setColor(gfx.kColorBlack)
	-- Sea and the boat.
	Sprites.sea(0, 110, 400, 40, Draw.t)
	Sprites.benchy(60, 60, Draw.t, { talking = self.dialog ~= nil and not self.dialog:done(), mood = self.mood })
	-- A buoy with a flag counting the printer's streak.
	local streak = Store.activePrinter().stats.streak
	gfx.setColor(gfx.kColorBlack)
	gfx.fillCircleAtPoint(200, 120 + math.floor(math.sin(Draw.t / 500) * 2), 6)
	Text.draw(string.format("STREAK %+d", streak), 200, 98, { color = "black", align = "center" })

	-- Topic menu.
	Draw.window(272, 22, 122, 88, { title = "ASK" })
	for i, row in self.list:visible() do
		local y = 32 + row * 12
		Text.draw(CaptainScreen.TOPICS[i].label, 292, y)
		if i == self.list.sel and self.dialog == nil then Draw.cursor(280, y + 1) end
	end
	if self.dialog then
		self.dialog:drawBox()
	else
		Draw.window(6, 150, 388, 74, { title = "CAPTAIN" })
		Sprites.captainPortrait(14, 158, self.mood, false)
		Text.drawWrapped("What'll it be, shipwright? Crank or d-pad to pick a topic.", 66, 160, 316, 5)
	end
end
