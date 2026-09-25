-- THE WORKSHOP (home screen).
--
-- Left: the shop itself: brick wall, window, a shelf of real spools from the
-- Rolodex, and the A1 Mini on the bench, animated by the live printer state.
-- Right: a status window with job, progress, layers, times, temps and
-- filament. Bottom: workshop stations.
--
-- Crank: when idle, walks between stations; when printing, scrubs a layer
-- preview of the part (released crank snaps back to live after a moment).

local gfx <const> = playdate.graphics

HomeScreen = {}
HomeScreen.__index = HomeScreen

HomeScreen.STATIONS = {
	{ id = "watch", label = "PRINT WATCH", icon = "watch" },
	{ id = "queue", label = "PRINT QUEUE", icon = "queue" },
	{ id = "rolodex", label = "FILAMENT ROLODEX", icon = "rolodex" },
	{ id = "calibrate", label = "CALIBRATION", icon = "calibrate" },
	{ id = "maint", label = "MAINTENANCE", icon = "maint" },
	{ id = "captain", label = "BENCHY CAPTAIN", icon = "captain" },
	{ id = "stats", label = "STATS OFFICE", icon = "stats" },
	{ id = "settings", label = "SETTINGS", icon = "settings" },
}

function HomeScreen.new()
	return setmetatable({
		sel = 1,
		ticker = CrankTicker.new(45),
		scrubTicker = CrankTicker.new(8),
		scrub = nil,          -- layer being previewed, nil = live
		scrubIdleMs = 0,
		tickerX = 0,
		introShown = false,
		ms = 0,
		slide = 0,            -- station bar slide animation
	}, HomeScreen)
end

function HomeScreen:open(id)
	local s
	if id == "watch" then s = WatchScreen.new()
	elseif id == "queue" then s = QueueScreen.new()
	elseif id == "rolodex" then s = RolodexScreen.new()
	elseif id == "calibrate" then s = CalibScreen.new()
	elseif id == "maint" then s = MaintScreen.new()
	elseif id == "captain" then s = CaptainScreen.new()
	elseif id == "stats" then s = StatsScreen.new()
	elseif id == "settings" then s = SettingsScreen.new()
	end
	if s then
		Sfx.play("ok")
		Screens.push(s)
	end
end

function HomeScreen:moveStation(d)
	local n = #HomeScreen.STATIONS
	self.sel = U.wrap(self.sel + d, n)
	self.slide = d * 6
	Sfx.play("move")
end

function HomeScreen:update(dtMs)
	self.ms = self.ms + dtMs
	if self.slide ~= 0 then self.slide = self.slide - U.sign(self.slide) end

	-- First launch: the Captain introduces himself.
	if not self.introShown and self.ms > 600 then
		self.introShown = true
		if not Store.data.captain.seenIntro then
			Store.data.captain.seenIntro = true
			Store.markDirty()
			Common.say({ text = "Ahoy! I'm the Benchy Captain, and this be yer PRINT SHOP. Let me show ye around.", mood = "happy" }, function()
				Common.help("home")
			end)
			return
		end
	end

	local snap = Printing.snapshot()
	local printing = snap.state == "PRINTING" or snap.state == "PAUSED" or snap.state == "HEATING"

	-- A pending failure takes priority: go log it.
	if snap.pending and Input.a() and self.sel == 1 then
		Screens.push(FailureScreen.new())
		return
	end

	local h = Input.horizontal()
	if h ~= 0 then self:moveStation(h) end

	if printing and snap.progress.totalLayers > 0 then
		local t = self.scrubTicker:update()
		if t ~= 0 then
			local total = snap.progress.totalLayers
			if self.scrub == nil then self.scrub = snap.progress.layer end
			self.scrub = U.clamp(self.scrub + t, 1, total)
			self.scrubIdleMs = 0
			Sfx.play("tick")
		elseif self.scrub then
			self.scrubIdleMs = self.scrubIdleMs + dtMs
			if self.scrubIdleMs > 1800 then self.scrub = nil end
		end
	else
		self.scrub = nil
		local t = self.ticker:update()
		if t ~= 0 then self:moveStation(t > 0 and 1 or -1) end
	end

	if Input.a() then
		self:open(HomeScreen.STATIONS[self.sel].id)
	elseif Input.b() then
		-- B on the workshop: the Captain pipes up.
		Common.say(Captain.advice())
	elseif Input.up() then
		self:open("watch")
	elseif Input.down() then
		self:open("queue")
	end
end

---------------------------------------------------------------------------
-- drawing

function HomeScreen:drawScene(snap)
	local x, y, w, h = 0, 15, 206, 157
	local benchY = y + h - 14
	Draw.fillPattern("brick", x, y, w, h)

	-- Window (top right) with sky by time of day.
	local wx, wy, ww, wh = x + 134, y + 6, 64, 32
	gfx.setColor(gfx.kColorBlack)
	gfx.fillRect(wx - 2, wy - 2, ww + 4, wh + 4)
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRect(wx, wy, ww, wh)
	local hour = Clock.hour()
	if hour >= 19 or hour < 6 then
		Draw.fillPattern("dark88", wx, wy, ww, wh)
		gfx.setColor(gfx.kColorWhite)
		gfx.fillCircleAtPoint(wx + 46, wy + 10, 6)
		gfx.setColor(gfx.kColorBlack)
		gfx.fillCircleAtPoint(wx + 43, wy + 8, 5)
		gfx.setColor(gfx.kColorWhite)
		gfx.drawPixel(wx + 10, wy + 6)
		gfx.drawPixel(wx + 22, wy + 22)
		gfx.drawPixel(wx + 56, wy + 26)
	else
		gfx.setColor(gfx.kColorBlack)
		gfx.drawCircleAtPoint(wx + 46, wy + 11, 6)
		Draw.fillPattern("light12", wx, wy + 22, ww, wh - 22)
	end
	gfx.setColor(gfx.kColorBlack)
	gfx.drawLine(wx + ww // 2, wy, wx + ww // 2, wy + wh)
	gfx.drawLine(wx, wy + wh // 2, wx + ww, wy + wh // 2)

	-- Upper shelf: the AMS lite spools, straight from the Rolodex.
	local shelfY = y + 70
	local ams = Printing.provider:getAMSOrSpoolState()
	local shown = 0
	for _, slot in ipairs(ams.slots or {}) do
		if slot.spoolId and shown < 4 then
			local s = Store.spool(slot.spoolId)
			if s then
				local sx = x + 128 + shown * 19
				Sprites.spoolEdge(sx, shelfY - 22, 16, 22, Spool.pct(s), s.color)
				if ams.active == slot.slot and Draw.blinkOn then
					gfx.setColor(gfx.kColorBlack)
					gfx.fillTriangle(sx + 4, shelfY - 30, sx + 12, shelfY - 30, sx + 8, shelfY - 25)
				end
				shown = shown + 1
			end
		end
	end
	gfx.setColor(gfx.kColorBlack)
	gfx.fillRect(x + 122, shelfY, 84, 4)
	gfx.fillRect(x + 128, shelfY + 4, 3, 6)
	gfx.fillRect(x + 196, shelfY + 4, 3, 6)
	if shown == 0 then
		gfx.setColor(gfx.kColorWhite)
		gfx.fillRect(x + 134, shelfY - 12, 60, 11)
		Text.draw("NO AMS", x + 164, shelfY - 11, { color = "black", align = "center" })
	end

	-- Lower shelf: the Captain's Benchy, and a warning flag for low spools.
	local s2 = y + 112
	gfx.setColor(gfx.kColorBlack)
	gfx.fillRect(x + 122, s2, 84, 4)
	gfx.fillRect(x + 128, s2 + 4, 3, 6)
	gfx.fillRect(x + 196, s2 + 4, 3, 6)
	local bob = (Draw.t // 500) % 2
	local bx, by = x + 150, s2 - 1 - bob
	gfx.setColor(gfx.kColorWhite)
	gfx.fillPolygon(bx, by - 9, bx + 40, by - 11, bx + 34, by, bx + 5, by)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawPolygon(bx, by - 9, bx + 40, by - 11, bx + 34, by, bx + 5, by)
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRect(bx + 6, by - 19, 15, 9)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawRect(bx + 6, by - 19, 15, 9)
	gfx.fillRect(bx + 9, by - 16, 3, 3)
	gfx.fillRect(bx + 15, by - 16, 3, 3)
	gfx.fillRect(bx + 8, by - 25, 4, 6)
	-- The Captain himself: hat and beard on the foredeck.
	gfx.fillRect(bx + 25, by - 21, 8, 3)
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRect(bx + 26, by - 18, 6, 6)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawRect(bx + 26, by - 18, 6, 6)
	Draw.fillPattern("gray50", bx + 26, by - 14, 6, 3)
	if Captain.hasNews() and Draw.blinkOn then
		gfx.setColor(gfx.kColorWhite)
		gfx.fillRect(bx + 32, by - 36, 12, 13)
		gfx.setColor(gfx.kColorBlack)
		gfx.drawRect(bx + 32, by - 36, 12, 13)
		gfx.drawLine(bx + 33, by - 23, bx + 31, by - 20)
		Text.draw("!", bx + 35, by - 34, { color = "black" })
	end
	if #Filament.lowSpools() > 0 then
		gfx.setColor(gfx.kColorWhite)
		gfx.fillRect(x + 124, s2 - 12, 24, 11)
		Text.draw(Draw.blinkOn and FontData.icon.warn or " ", x + 126, s2 - 11, { color = "black" })
		Text.draw("LO", x + 134, s2 - 11, { color = "black" })
	end

	-- Bench.
	Draw.fillPattern("wood", x, benchY, w, 14)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawLine(x, benchY, x + w, benchY)

	-- The printer stands on the bench.
	local job = snap.job
	local pj = snap.pjob
	local spoolFrac = snap.spool and Spool.pct(snap.spool) or 0.6
	local color = (snap.spool and snap.spool.color) or (pj and pj.color) or "BLACK"
	local shape = (job and job.shape) or (pj and pj.shape) or "cube"
	local progress = snap.progress.pct / 100
	if self.scrub and snap.progress.totalLayers > 0 then
		progress = self.scrub / snap.progress.totalLayers
	end
	Sprites.printer(x + 10, benchY - 105, snap.state, Draw.t, {
		progress = progress, shape = shape, color = color, spoolFrac = spoolFrac,
	})
end

function HomeScreen:drawStatus(snap)
	local x, y, w, h = 208, 18, 190, 154
	Draw.window(x, y, w, h, { title = snap.printer.name })
	local ix, iw = x + 10, w - 20
	local ty = y + 9
	-- State line.
	local stTag = Common.STATE_LABEL[snap.state] or snap.state
	Draw.tag(stTag, ix, ty, snap.state == "PRINTING" or snap.state == "ERROR" or (snap.state == "COMPLETE" and Draw.blinkOn))
	local msg = snap.message ~= "" and snap.message or (snap.caps.simulated and "DEMO" or (snap.online and "LIVE" or "OFFLINE"))
	Text.draw(U.truncate(msg, 16), x + w - 10, ty + 1, { align = "right" })
	ty = ty + 15

	local job = snap.job
	local jobName = job and job.name or (snap.pjob and snap.pjob.name) or nil
	if jobName then
		Text.draw(U.truncate(jobName, Text.fit(iw)), ix, ty)
		ty = ty + 12
		local p = snap.progress
		local pct = p.pct
		local layer = p.layer
		if self.scrub then
			layer = self.scrub
			Text.draw("SCRUB", ix, ty + 4)
			Text.draw(string.format("L%d", layer), ix + iw, ty + 4, { align = "right" })
		else
			Text.draw(U.fmtPct(pct), ix, ty, { scale = 2 })
			Text.draw(string.format("L %d/%d", p.layer, p.totalLayers), ix + iw, ty + 5, { align = "right" })
		end
		ty = ty + 20
		Draw.bar(ix, ty, iw, 8, (self.scrub and p.totalLayers > 0) and (self.scrub / p.totalLayers) or pct / 100, { pattern = nil })
		ty = ty + 12
		Draw.row("ELAPSED", U.fmtDuration(p.elapsedSec), ix, ty, iw)
		ty = ty + 11
		Draw.row("REMAIN", U.fmtDuration(p.remainingSec), ix, ty, iw)
		ty = ty + 11
	else
		local nxt = Queue.nextFor(snap.printer.id)
		Text.draw("NO JOB ON THE PLATE", ix, ty)
		ty = ty + 12
		if nxt then
			Text.draw("NEXT: " .. U.truncate(nxt.name, Text.fit(iw) - 6), ix, ty)
			ty = ty + 11
			Draw.row("EST", U.fmtDuration(nxt.estMinutes * 60) .. " " .. U.fmtGrams(nxt.estGrams), ix, ty, iw)
		else
			Text.draw("QUEUE IS EMPTY", ix, ty)
		end
		ty = ty + 11
		local b = Queue.backlog()
		Draw.row("BACKLOG", b.count .. " JOBS " .. U.fmtDuration(b.minutes * 60), ix, ty, iw)
		ty = ty + 20
	end
	local t = snap.temps
	Draw.row("NOZZLE", string.format("%d/%d", U.roundInt(t.nozzle), U.roundInt(t.nozzleTarget)) .. FontData.icon.deg .. "C", ix, ty, iw)
	ty = ty + 11
	Draw.row("BED", string.format("%d/%d", U.roundInt(t.bed), U.roundInt(t.bedTarget)) .. FontData.icon.deg .. "C", ix, ty, iw)
	ty = ty + 11
	local fil = "--"
	if snap.spool then fil = Spool.shortLabel(snap.spool)
	elseif snap.pjob and snap.pjob.material then fil = snap.pjob.material .. " " .. (snap.pjob.color or "") end
	Text.draw(FontData.icon.spool .. " " .. U.truncate(fil, Text.fit(iw) - 2), ix, ty)
	ty = ty + 12

	-- Alerts: failure to log, runout, maintenance, low spools.
	local alert = nil
	if snap.pending then alert = FontData.icon.warn .. " LOG FAILURE: A ON WATCH"
	elseif snap.runout then alert = FontData.icon.warn .. " RUNOUT! SWAP SPOOL"
	else
		local due = MaintService.dueSoon(snap.printer.id)
		if #due > 0 then
			alert = FontData.icon.wrench .. " " .. U.truncate(due[1].task.name, 14) .. (due[1].st.due and " DUE" or " SOON")
		elseif #Filament.lowSpools() > 0 then
			alert = FontData.icon.spool .. " " .. #Filament.lowSpools() .. " SPOOL(S) LOW"
		end
	end
	if alert and ty < y + h - 12 then
		if Draw.blinkOn or snap.pending == nil then
			Text.draw(U.truncate(alert, Text.fit(iw)), ix, y + h - 16)
		end
	end
end

function HomeScreen:drawStations()
	local y = 175
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRect(0, 172, 400, 55)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawLine(0, 172, 400, 172)
	gfx.drawLine(0, 174, 400, 174)
	for i, st in ipairs(HomeScreen.STATIONS) do
		local ix = 10 + (i - 1) * 49
		local sel = i == self.sel
		local iy = y + 4 - (sel and 2 or 0)
		Sprites.icon(st.icon, ix, iy, sel)
		if st.id == "captain" and Captain.hasNews() and Draw.blinkOn then
			gfx.fillCircleAtPoint(ix + 26, iy + 2, 3)
		end
		if st.id == "watch" and Store.data.pendingFailure and Draw.blinkOn then
			Text.draw("!", ix + 24, iy - 1, { color = "black" })
		end
		if st.id == "maint" and #MaintService.dueSoon(Store.activePrinter().id) > 0 then
			gfx.fillCircleAtPoint(ix + 26, iy + 2, 2)
		end
	end
	local cx = 10 + (self.sel - 1) * 49 + 14 + self.slide
	local label = HomeScreen.STATIONS[self.sel].label
	local lw = Text.width(label)
	local lx = U.clamp(cx - lw // 2, 14, 396 - lw)
	Text.draw(label, lx, y + 38, { color = "black" })
	Draw.cursor(lx - 10, y + 39, gfx.kColorBlack)
end

function HomeScreen:drawTicker(dtMs)
	gfx.setColor(gfx.kColorBlack)
	gfx.fillRect(0, 227, 400, 13)
	local text = "CAPTAIN: " .. U.upper(Captain.ticker(dtMs))
	local w = Text.width(text)
	if w < 390 then
		Text.draw(text, 200, 229, { color = "white", align = "center" })
	else
		self.tickerX = (self.tickerX + 1) % (w + 80)
		Text.draw(text, 400 - self.tickerX, 229, { color = "white" })
	end
end

function HomeScreen:draw()
	gfx.clear(gfx.kColorWhite)
	local snap = Printing.snapshot()
	local clock = U.fmtClock(Clock.now())
	Draw.titleBar("PRINT SHOP", clock)
	Text.draw(U.upper(Enums.PROVIDER_LABEL[snap.printer.provider] or ""), 200, 2, { color = "white", align = "center" })
	self:drawScene(snap)
	self:drawStatus(snap)
	self:drawStations()
	self:drawTicker(Clock.frameMs)
end
