-- WRAP REPORT: live preview; A saves it into the project and writes the
-- export files; LEFT/RIGHT toggles TODAY / ALL DAYS; hold A lists saved reports.

ReportScreen = Screen:extend()

function ReportScreen:init(saved)
	self.saved = saved -- a stored report record to view, or nil for live preview
	self.allDays = false
	self.scroll = 0
	self.stepper = Stepper.new(14)
	self:refresh()
end

function ReportScreen:refresh()
	if self.saved then
		self.lines = self.saved.lines or {}
		return
	end
	local p = Model.project()
	if p == nil then self.lines = { "NO PROJECT" }; return end
	self.data = Report.build(p, (not self.allDays) and Model.currentDay(p) or nil, Util.now())
	self.lines = Report.lines(self.data)
end

function ReportScreen:enter() self:refresh() end

function ReportScreen:visible() return math.floor((Gfx.H - 26 - 20) / (Gfx.lineH + 1)) end

function ReportScreen:scrollBy(n)
	self.scroll = Util.clamp(self.scroll + n, 0, math.max(0, #self.lines - self:visible()))
	App.redraw()
end

function ReportScreen:save()
	local p = Model.project()
	local rec = Schema.new("report", { t = Util.now(), day = self.allDays and "" or (Model.currentDay(p) or {}).id or "",
		title = "WRAP " .. (self.allDays and "ALL DAYS" or ((Model.currentDay(p) or {}).label or "")), data = self.data,
		lines = self.lines })
	App.commit(Model.opAdd(p, "reports", rec, nil, "SAVE WRAP REPORT"))
	local files = Interchange.exportFiles(p, Util.now(), self.lines)
	Store.flush()
	Store.snapshot("WRAP")
	App.toast("SAVED + " .. #files .. " FILES IN /EXPORT", { icon = "disk", ms = 2500 })
end

function ReportScreen:event(ev)
	if ev == "UP" then self:scrollBy(-self:visible() + 1)
	elseif ev == "DOWN" then self:scrollBy(self:visible() - 1)
	elseif (ev == "LEFT" or ev == "RIGHT") and not self.saved then
		self.allDays = not self.allDays; self.scroll = 0; self:refresh()
	elseif ev == "A" and not self.saved then self:save()
	elseif ev == "AL" then
		local p = Model.project()
		local items = {}
		for i = #p.reports, 1, -1 do
			local r = p.reports[i]
			items[#items + 1] = { label = (r.t and (Util.fmtDate(r.t) .. " " .. Util.fmtClock(r.t)) or "") .. " " .. (r.title or ""), value = r }
		end
		if #items == 0 then App.toast("NO SAVED REPORTS YET"); return true end
		App.push(PickerOverlay:new("SAVED REPORTS", items, nil, function(it) App.push(ReportScreen:new(it.value)) end, { w = 320 }))
	elseif ev == "B" then App.pop()
	end
	return true
end

function ReportScreen:crank(change, accel)
	local n = self.stepper:feed(accel)
	if n ~= 0 then self:scrollBy(n) end
end

function ReportScreen:draw()
	Gfx.fill(0, 0, Gfx.W, 22)
	Gfx.pix(self.saved and "SAVED REPORT" or "WRAP REPORT", 8, 4, 2, { white = true })
	if not self.saved then
		Gfx.pix(self.allDays and "ALL DAYS" or "TODAY", Gfx.W - 8, 8, 1, { white = true, align = "right" })
	end
	local y = 26
	local lh = Gfx.lineH + 1
	for i = self.scroll + 1, math.min(#self.lines, self.scroll + self:visible()) do
		local l = self.lines[i]
		if l:sub(1, 3) == "== " then
			Gfx.fill(4, y + 1, Gfx.W - 16, lh - 1)
			Gfx.text((l:gsub("=", "")), 10, y + 1, { bold = true, white = true, maxW = Gfx.W - 30 })
		else
			Gfx.text(l, 8, y + 1, { maxW = Gfx.W - 22 })
		end
		y = y + lh
	end
	-- scrollbar
	local vis = self:visible()
	if #self.lines > vis then
		local th = Gfx.H - 46
		local bh = math.max(10, th * vis // #self.lines)
		local by = 26 + (th - bh) * self.scroll // math.max(1, #self.lines - vis)
		Gfx.fill(Gfx.W - 5, 26, 1, th)
		Gfx.fill(Gfx.W - 7, by, 5, bh)
	end
	if self.saved then
		Gfx.hints({ { "crank", "SCROLL" }, { "up", "" }, { "down", "PAGE" }, { "B", "BACK" } })
	else
		Gfx.hints({ { "crank", "SCROLL" }, { "A", "SAVE+EXPORT" }, { "right", "DAY/ALL" }, { "!A", "SAVED" }, { "B", "BACK" } })
	end
end

return ReportScreen
