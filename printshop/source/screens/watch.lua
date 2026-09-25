-- PRINT WATCH: the current print in detail.
--
-- Left: the part growing layer by layer on a little bed, with the nozzle
-- riding the current layer. Crank scrubs back through the layers.
-- Right: progress, layers, times (elapsed, remaining, ETA clock),
-- temperatures with a history graph, material and estimated filament used,
-- and the printer's event log. A opens printer controls.

local gfx <const> = playdate.graphics

WatchScreen = {}
WatchScreen.__index = WatchScreen

function WatchScreen.new()
	return setmetatable({
		scrub = nil,
		scrubTicker = CrankTicker.new(6),
		idleMs = 0,
		logScroll = 0,
	}, WatchScreen)
end

function WatchScreen:controls(snap)
	local items = {}
	local st = snap.state
	local caps = snap.caps
	if snap.pending then
		items[#items + 1] = { label = "LOG FAILURE CAUSE", action = function() Screens.push(FailureScreen.new()) end }
	end
	if snap.runout then
		items[#items + 1] = { label = "SWAP SPOOL + RESUME", action = function() self:swapSpool(snap) end,
			hint = "Pick the new spool; the old one is logged empty." }
	end
	if st == "PRINTING" or st == "HEATING" then
		items[#items + 1] = { label = "PAUSE", disabled = not caps.control, action = function()
			local ok, err = Printing.pause()
			if not ok then Toast.show(err, "warn") end
		end }
	end
	if st == "PAUSED" and not snap.runout then
		items[#items + 1] = { label = "RESUME", disabled = not caps.control, action = function()
			local ok, err = Printing.resume()
			if not ok then Toast.show(err, "warn") end
		end }
	end
	if st == "PRINTING" or st == "HEATING" or st == "PAUSED" then
		items[#items + 1] = { label = "CANCEL PRINT", disabled = not caps.control, action = function()
			Confirm("CANCEL THIS PRINT?", function()
				local ok, err = Printing.cancel()
				if not ok then Toast.show(err, "warn") end
			end)
		end }
	end
	if st == "COMPLETE" then
		items[#items + 1] = { label = "CLEAR THE PLATE", action = function()
			Printing.acknowledge()
			Toast.show("PLATE CLEARED", "check")
		end }
	end
	if (st == "IDLE" or st == "COMPLETE") and not snap.pending then
		local nxt = Queue.nextFor(snap.printer.id)
		if nxt then
			local ok, why = Printing.canStart(nxt)
			items[#items + 1] = { label = "START NEXT: " .. U.truncate(nxt.name, 18), disabled = not ok,
				hint = ok and (U.fmtDuration(nxt.estMinutes * 60) .. "  " .. U.fmtGrams(nxt.estGrams)) or why,
				action = function()
					local ok2, err = Printing.start(nxt)
					if ok2 then Toast.show("PRINTING " .. nxt.name, "play") else Toast.show(err, "warn") end
				end }
		end
	end
	items[#items + 1] = { label = "ASK THE CAPTAIN", action = function() Common.help("watch") end }
	Menu.open({ title = "PRINTER", items = items })
end

function WatchScreen:swapSpool(snap)
	local mat = snap.job and snap.job.material or nil
	Common.pickSpool("LOAD WHICH SPOOL?", mat, function(s)
		if s == nil then return end
		Printing.swapSpool(s.id)
		local ok, err = Printing.resume()
		if ok then Toast.show("RESUMED WITH " .. Spool.shortLabel(s), "play")
		else Toast.show(err, "warn") end
	end)
end

function WatchScreen:update(dtMs)
	local snap = Printing.snapshot()
	local total = snap.progress.totalLayers
	if total > 0 then
		local t = self.scrubTicker:update()
		if t ~= 0 then
			if self.scrub == nil then self.scrub = math.max(1, snap.progress.layer) end
			local maxL = snap.state == "COMPLETE" and total or math.max(1, snap.progress.layer)
			self.scrub = U.clamp(self.scrub + t, 1, maxL)
			self.idleMs = 0
			Sfx.play("tick")
		elseif self.scrub then
			self.idleMs = self.idleMs + dtMs
			if self.idleMs > 2500 then self.scrub = nil end
		end
	end
	local v = Input.vertical()
	if v ~= 0 then self.logScroll = U.clamp(self.logScroll + v, 0, math.max(0, #Store.data.printLog - 4)) end
	if Input.a() then
		self:controls(snap)
	elseif Input.b() then
		Sfx.play("back")
		Screens.pop()
	end
end

function WatchScreen:drawPart(snap, x, y, w, h)
	Draw.window(x, y, w, h, { title = "LAYER VIEW" })
	-- White stage inside the window regardless of theme.
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRect(x + 6, y + 8, w - 12, h - 30)
	local job = snap.job
	local shape = (job and job.shape) or (snap.pjob and snap.pjob.shape) or "cube"
	local p = snap.progress
	local total = p.totalLayers
	local frac = total > 0 and (p.layer / total) or 0
	if snap.state == "COMPLETE" then frac = 1 end
	if self.scrub and total > 0 then frac = self.scrub / total end
	local bw, bh = w - 40, h - 60
	local bx = x + 20
	local bedY = y + h - 34
	-- Bed.
	Draw.fillPattern("dark75", x + 10, bedY, w - 20, 4)
	gfx.setColor(gfx.kColorBlack)
	gfx.drawRect(x + 10, bedY, w - 20, 4)
	if total > 0 and snap.state ~= "IDLE" then
		local topY = Sprites.part(bx, bedY - bh, bw, bh, shape, frac, { hot = snap.state == "PRINTING" and not self.scrub })
		-- Nozzle rides the current layer while printing.
		if (snap.state == "PRINTING" or snap.state == "PAUSED") and not self.scrub then
			local l, r = Sprites.partSpan(shape, frac)
			local sweep = math.sin(Draw.t / 160) * 0.5 + 0.5
			local nx = bx + math.floor(bw / 2 + (l + (r - l) * sweep) * bw / 2)
			local ny = topY - (snap.state == "PAUSED" and 12 or 1)
			gfx.setColor(gfx.kColorBlack)
			gfx.fillRect(nx - 7, ny - 14, 14, 9)
			gfx.fillTriangle(nx - 4, ny - 5, nx + 4, ny - 5, nx, ny)
		end
		if snap.state == "ERROR" then
			Text.draw(FontData.icon.warn .. " FAILED", x + w // 2, y + 14, { align = "center", color = "black" })
		end
	else
		Text.draw("EMPTY PLATE", x + w // 2, y + h // 2 - 10, { align = "center", color = "black" })
	end
	-- Caption.
	local label
	if self.scrub then label = string.format("SCRUB L%d/%d", self.scrub, total)
	elseif total > 0 then label = string.format("LAYER %d/%d", p.layer, total)
	else label = "NO LAYERS" end
	Text.draw(label, x + w // 2, y + h - 18, { align = "center" })
end

function WatchScreen:drawInfo(snap, x, y, w)
	local p = snap.progress
	local job = snap.job
	local name = job and job.name or (snap.pjob and snap.pjob.name) or "NO PRINT"
	Draw.window(x, y, w, 112, { title = U.truncate(name, 24) })
	local ix, iw = x + 10, w - 20
	local ty = y + 10
	local st = Common.STATE_LABEL[snap.state] or snap.state
	Draw.tag(st, ix, ty, true)
	Text.draw(U.truncate(snap.message, 20), ix + iw, ty + 1, { align = "right" })
	ty = ty + 15
	Draw.bar(ix, ty, iw, 10, p.pct / 100, { marks = 4 })
	ty = ty + 14
	Text.draw(U.fmtPct(p.pct), ix, ty)
	Text.draw(string.format("L %d/%d", p.layer, p.totalLayers), ix + iw, ty, { align = "right" })
	ty = ty + 12
	Draw.row("ELAPSED", U.fmtDuration(p.elapsedSec), ix, ty, iw // 2 - 6)
	Draw.row("LEFT", U.fmtDuration(p.remainingSec), ix + iw // 2 + 6, ty, iw // 2 - 6)
	ty = ty + 11
	local eta = "--:--"
	if p.remainingSec > 0 and (snap.state == "PRINTING" or snap.state == "HEATING") then
		local speed = snap.caps.simulated and Store.settings().demoSpeed or 1
		eta = U.fmtClock(Clock.now() + p.remainingSec // speed)
	end
	Draw.row("ETA", eta .. (snap.caps.simulated and " (DEMO)" or ""), ix, ty, iw)
	ty = ty + 11
	-- Filament: estimate used so far, from job grams x progress.
	local grams = job and job.estGrams or (snap.pjob and snap.pjob.grams) or 0
	local used = grams * p.pct / 100
	local mat = job and job.material or (snap.pjob and snap.pjob.material) or "PLA"
	local meters = used / Enums.gramsPerMeter(mat)
	Draw.row("USED", string.format("%s/%s %.1fm", U.fmtGrams(used), U.fmtGrams(grams), meters), ix, ty, iw)
	ty = ty + 11
	local fil = snap.spool and Spool.shortLabel(snap.spool) or (mat .. " " .. (job and job.color or ""))
	local cost = snap.spool and ("  " .. U.fmtMoney(Filament.cost(snap.spool, used))) or ""
	Text.draw(U.truncate(fil .. cost, Text.fit(iw)), ix, ty)
end

function WatchScreen:drawTemps(snap, x, y, w)
	Draw.window(x, y, w, 50, { title = "TEMPS" })
	local t = snap.temps
	local ix, iw = x + 10, w - 20
	Common.tempRow("NOZ", t.nozzle, t.nozzleTarget, ix, y + 9, iw // 2 - 6, 300)
	Common.tempRow("BED", t.bed, t.bedTarget, ix + iw // 2 + 6, y + 9, iw // 2 - 6, 120)
	-- History graph under the gauges.
	local hist = Printing.provider.tempHistory
	if #hist > 1 then
		local noz, bed = {}, {}
		for i, s in ipairs(hist) do noz[i], bed[i] = s[1], s[2] end
		Draw.lineGraph(ix, y + 28, iw // 2 - 6, 14, noz, 0, 300)
		Draw.lineGraph(ix + iw // 2 + 6, y + 28, iw // 2 - 6, 14, bed, 0, 120)
	end
end

function WatchScreen:drawLog(x, y, w, h)
	Draw.window(x, y, w, h, { title = "EVENT LOG" })
	local log = Store.data.printLog
	local rows = (h - 12) // 11
	local last = #log - self.logScroll
	local first = math.max(1, last - rows + 1)
	local ty = y + 8
	if #log == 0 then
		Text.draw("NOTHING YET.", x + 10, ty)
		return
	end
	for i = first, last do
		local e = log[i]
		Text.draw(U.fmtClock(e.at) .. " " .. U.truncate(e.text, Text.fit(w - 60)), x + 10, ty)
		ty = ty + 11
	end
end

function WatchScreen:draw()
	local snap = Printing.snapshot()
	Common.page("PRINT WATCH", snap.printer.name, "A:CONTROLS  CRANK:SCRUB  " .. FontData.icon.up .. FontData.icon.down .. ":LOG  B:BACK", "light12")
	self:drawPart(snap, 4, 20, 150, 160)
	self:drawInfo(snap, 158, 20, 238)
	self:drawTemps(snap, 158, 134, 238)
	self:drawLog(4, 184, 392, 42)
	if snap.pending and Draw.blinkOn then
		Draw.window(110, 90, 180, 34, { invert = true })
		Text.draw(FontData.icon.warn .. " PRINT FAILED", 200, 96, { align = "center", color = Draw.bgInk() })
		Text.draw("A: LOG THE CAUSE", 200, 108, { align = "center", color = Draw.bgInk() })
	end
end
