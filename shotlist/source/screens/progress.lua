-- PROGRESS: counts, % complete, remaining-time estimate, next-up queue and
-- per-scene coverage. LEFT/RIGHT toggles TODAY / ALL DAYS.

ProgressScreen = ListScreen:extend()

function ProgressScreen:init()
	ListScreen.init(self, "PROGRESS")
	self.allDays = false
	self.listTop = 112
	self.hints = { { "crank", "MOVE" }, { "A", "GO" }, { "left", "" }, { "right", "DAY/ALL" }, { "B", "BACK" } }
end

function ProgressScreen:scope()
	if self.allDays then return nil end
	return Model.currentDay()
end

function ProgressScreen:build()
	local p = Model.project()
	local rows = {}
	if p == nil then self.rows = rows; return end
	local cur = App.cursorShot()
	local cands = Model.nextCandidates(cur and cur.id)
	rows[#rows + 1] = { section = true, skip = true, label = "NEXT UP", h = 14 }
	for i = 1, math.min(5, #cands) do
		local c = cands[i]
		rows[#rows + 1] = { key = "n" .. c.shot.id, h = 18,
			draw = function(r, x, y, w, h, sel)
				Gfx.statusIcon(c.shot.status, x + 14, y + 5, sel)
				Gfx.pix(Model.code(c.shot), x + 27, y + 6, 1, { white = sel })
				Gfx.text(Model.describe(c.shot), x + 80, y + 1, { white = sel, maxW = 150 })
				Gfx.pix(Pixfont.fit(Model.nextReason(c), 140, 1), x + w - 8, y + 6, 1, { white = sel, align = "right" })
			end,
			onA = function() App.setCursor(c.shot); App.home() end }
	end
	if #cands == 0 then rows[#rows + 1] = { skip = true, label = "NOTHING LEFT TO SHOOT", icon = "check" } end
	rows[#rows + 1] = { section = true, skip = true, label = "SCENE COVERAGE", h = 14 }
	local day = self:scope()
	for _, d in ipairs(p.days) do
		if day == nil or d == day then
			for _, sc in ipairs(d.scenes) do
				local done, total, pu = 0, 0, 0
				for _, su in ipairs(sc.setups) do for _, s in ipairs(su.shots) do
					if s.status ~= "CUT" then total = total + 1 end
					if s.status == "GOT IT" then done = done + 1 end
					if s.status == "PICKUP" then pu = pu + 1 end
				end end
				rows[#rows + 1] = { key = sc.id, h = 18,
					draw = function(r, x, y, w, h, sel)
						Gfx.statusIcon(sc.status, x + 14, y + 5, sel)
						Gfx.pix("SC " .. sc.number, x + 27, y + 6, 1, { white = sel })
						Gfx.text(sc.desc, x + 72, y + 1, { white = sel, maxW = 150 })
						local bx = x + w - 120
						if sel then Gfx.fill(bx - 2, y + 3, 84, 12, true) end
						Gfx.bar(bx, y + 4, 80, 10, total > 0 and done / total or 1, total > 0 and pu / total or 0)
						Gfx.pix(done .. "/" .. total, x + w - 8, y + 6, 1, { white = sel, align = "right" })
					end,
					onA = function() App.push(BrowserScreen:new(sc.id)) end }
			end
		end
	end
	self.rows = rows
end

function ProgressScreen:onLeft() self.allDays = not self.allDays; self:build() end
function ProgressScreen:onRight() self.allDays = not self.allDays; self:build() end

function ProgressScreen:drawHeader()
	self.subtitle = self.allDays and "ALL DAYS" or ((Model.currentDay() or {}).label or "")
	ListScreen.drawHeader(self)
	local p = Model.project()
	if p == nil then return end
	local day = self:scope()
	local pr = Model.progress(p, day)
	-- counts column (matches the paper dashboard people already use)
	local y = 26
	local function stat(n, label, yy)
		Gfx.pix(tostring(n), 70, yy, 2, { align = "right" })
		Gfx.pix(label, 78, yy + 4, 1)
	end
	stat(pr.total, "SHOTS", y)
	stat(pr.done, "COMPLETE", y + 19)
	stat(pr.pickups, "PICKUPS", y + 38)
	stat(pr.remain, "REMAIN", y + 57)
	-- big percentage
	Gfx.pix(pr.pct .. "%", 250, y + 2, 6, { align = "center" })
	Gfx.bar(160, y + 48, 180, 12, pr.total > 0 and pr.done / pr.total or 0, pr.total > 0 and pr.pickups / pr.total or 0)
	local est = Model.estimate(p, day, Util.now())
	local line
	if est.method == "DONE" then line = "ALL SHOTS COMPLETE"
	elseif est.minutes then
		line = "EST " .. Util.fmtDur(est.minutes) .. " LEFT"
		if est.wrapAt and not self.allDays then line = line .. "  WRAP ~" .. Util.fmtClock(est.wrapAt, Model.db.settings.clock24) end
	end
	if line then Gfx.text(line, 250, y + 64, { bold = true, align = "center" }) end
	local basis = ({ PACE = string.format("%.1f", est.pace or 1) .. "X PLAN + " .. Util.fmtDur(est.change or 15) .. "/SETUP (" .. est.samples .. " SHOTS)",
		MEDIAN = "AVG " .. Util.fmtDur(est.median) .. "/SHOT", PLAN = "FROM PLAN (NO HISTORY YET)" })[est.method]
	if basis then Gfx.pix(basis, 250, y + 81, 1, { align = "center" }) end
end

return ProgressScreen
