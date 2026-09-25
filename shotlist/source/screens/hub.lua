-- HUB (UP from LIVE): JRPG command window + production status.

HubScreen = Screen:extend()
HubScreen.hideToast = true

function HubScreen:init()
	-- right after an undoable action the cursor waits on UNDO: UP, A undoes
	self.sel = (App.toastMsg and App.toastMsg.undo) and 2 or 1
	self.stepper = Stepper.new()
end

function HubScreen:items()
	local undo = Store.undoLabel()
	return {
		{ "NEXT SHOT", function() App.goNext({ fresh = true }) end },
		{ "UNDO", function()
			local l = Store.undo()
			local live = App.home()
			if l and live and live.onUndo then live:onUndo() end
			App.toast(l and ("UNDONE: " .. l) or "NOTHING TO UNDO", { icon = "left" })
		end, disabled = undo == nil },
		{ "LIVE", function() App.home() end },
		{ "SLATE", function() App.home(); App.push(SlateScreen:new()) end },
		{ "SHOT LIST", function() App.replace(BrowserScreen.forCursor()) end },
		{ "NEW SHOT", function() App.replace(BuilderScreen:new()) end },
		{ "PROGRESS", function() App.replace(ProgressScreen:new()) end },
		{ "CONTINUITY", function()
			local s = App.cursorShot()
			App.replace(ContinuityScreen:new(s and Model.ctx(s.id).scene or nil))
		end },
		{ "GEAR", function() App.replace(GearScreen:new()) end },
		{ "REPORT", function() App.replace(ReportScreen:new()) end },
		{ "PROJECT", function() App.replace(ProjectForm()) end },
		{ "DATA", function() App.replace(DataForm()) end },
		{ "SETTINGS", function() App.replace(SettingsForm()) end },
	}
end

local COLS, ROWS = 2, 7

function HubScreen:draw()
	local project = Model.project()
	Gfx.fill(0, 0, Gfx.W, 22)
	Gfx.pix("SHOT LIST", 8, 4, 2, { white = true })
	Gfx.pix(Util.fmtClock(nil, Model.db.settings.clock24), Gfx.W - 8, 4, 2, { white = true, align = "right" })
	-- command window
	local x, y, w, h = 4, 28, 244, 190
	Gfx.window(x, y, w, h, "COMMAND")
	local items = self:items()
	local colW = (w - 16) // COLS
	for i, it in ipairs(items) do
		local col = (i - 1) // ROWS
		local row = (i - 1) % ROWS
		local ix, iy = x + 8 + col * colW, y + 12 + row * 25
		local sel = i == self.sel
		if sel then
			Gfx.selbar(ix, iy, colW - 4, 22)
			Gfx.cursor(ix + 3, iy + 7, true)
		end
		local label = it[1]
		if i == #items then label = Pixfont.fit(label, colW * 2 - 30, 1) end
		if Pixfont.width(label, 1) > colW - 22 and i ~= #items then
			Gfx.text(label, ix + 12, iy + 3, { bold = true, white = sel, maxW = colW - 18 })
		else
			Gfx.text(label, ix + 12, iy + 3, { bold = true, white = sel, maxW = (i == #items and colW * 2 or colW) - 18 })
		end
	end
	-- status window
	local sx, sw = 252, 144
	Gfx.window(sx, y, sw, h, "STATUS")
	if project then
		Gfx.text(project.title, sx + 10, y + 12, { bold = true, maxW = sw - 20 })
		local day = Model.currentDay(project)
		local pr = Model.progress(project, day)
		Gfx.pix((day and day.label or "") .. " " .. pr.pct .. "%", sx + 10, y + 34, 2)
		Gfx.bar(sx + 10, y + 52, sw - 20, 10, pr.total > 0 and pr.done / pr.total or 0, pr.total > 0 and pr.pickups / pr.total or 0)
		Gfx.text(pr.done .. " DONE  " .. pr.pickups .. " P/U", sx + 10, y + 66)
		Gfx.text(pr.remain .. " REMAIN  " .. pr.takes .. " TK", sx + 10, y + 84)
		local est = Model.estimate(project, day, Util.now())
		if est.minutes then
			Gfx.text("EST " .. Util.fmtDur(est.minutes) .. " LEFT", sx + 10, y + 106, { bold = true })
			if est.wrapAt then Gfx.text("WRAP ~" .. Util.fmtClock(est.wrapAt, Model.db.settings.clock24), sx + 10, y + 124) end
		end
		local cur = App.cursorShot()
		local c = cur and Model.nextCandidates(cur.id)[1]
		local undo = Store.undoLabel()
		if self.sel == 2 then
			Gfx.fill(sx + 8, y + 144, sw - 16, 38)
			Gfx.pix("UNDO:", sx + 12, y + 148, 1, { white = true })
			Gfx.text(undo or "NOTHING", sx + 12, y + 160, { white = true, bold = true, maxW = sw - 24 })
		elseif c then
			Gfx.pix("NEXT", sx + 10, y + 150, 1)
			Gfx.pix(Model.code(c.shot), sx + 10, y + 162, 2)
		end
	end
	Gfx.hints({ { "crank", "MOVE" }, { "A", "SELECT" }, { "B", "BACK" }, { "!B", "NEXT" } })
end

function HubScreen:move(d)
	local n = #self:items()
	self.sel = Util.wrap(self.sel + d, n)
end

function HubScreen:event(ev)
	local items = self:items()
	if ev == "UP" then self:move(-1)
	elseif ev == "DOWN" then self:move(1)
	elseif ev == "LEFT" or ev == "RIGHT" then
		local s = self.sel + (ev == "RIGHT" and ROWS or -ROWS)
		if s >= 1 and s <= #items then self.sel = s end
	elseif ev == "A" then
		local it = items[self.sel]
		if not it.disabled then it[2]() end
	elseif ev == "B" then App.pop()
	end
	return true
end

function HubScreen:crank(change, accel)
	local n = self.stepper:feed(accel)
	if n ~= 0 then self:move(n) end
end

return HubScreen
