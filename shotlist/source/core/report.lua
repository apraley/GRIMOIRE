-- Wrap report: a pure function of the project state. The structured `data`
-- is stored in the project (so it survives later edits) and rendered to lines
-- for the on-device viewer and the exported .txt.

Report = {}

local function sortedCounts(map)
	local r = {}
	for k, v in pairs(map) do r[#r + 1] = { name = k, n = v } end
	table.sort(r, function(a, b)
		if a.n ~= b.n then return a.n > b.n end
		return a.name < b.name
	end)
	return r
end

-- day = nil for the whole project
function Report.build(project, day, now)
	local d = {
		title = project.title, client = project.client, scope = day and (day.label .. " " .. (day.date or "")) or "ALL DAYS",
		generatedAt = now, completed = {}, missing = {}, pickups = {}, cut = {}, circled = {}, technical = {},
		performance = {}, coverage = {}, cameras = {}, lenses = {}, continuity = {},
	}
	local cams, lenses = {}, {}
	local shotsWithTakes, totalTakes = 0, 0
	local firstT, lastT
	local sceneRows = {}
	for _, e in ipairs(Model.flat(project)) do
		if day == nil or e.day == day then
			local s, code = e.shot, Model.code(e.shot)
			local row = { code = code, desc = Model.describe(s), pri = s.priority, takes = #s.takes }
			if s.status == "GOT IT" then d.completed[#d.completed + 1] = row
			elseif s.status == "PICKUP" then d.pickups[#d.pickups + 1] = row
			elseif s.status == "CUT" then d.cut[#d.cut + 1] = row
			else row.status = s.status; d.missing[#d.missing + 1] = row end

			local sc = sceneRows[e.scene]
			if sc == nil then
				sc = { number = e.scene.number, desc = e.scene.desc, done = 0, total = 0, pickups = 0, status = e.scene.status }
				sceneRows[e.scene] = sc
				d.coverage[#d.coverage + 1] = sc
			end
			if s.status ~= "CUT" then sc.total = sc.total + 1 end
			if s.status == "GOT IT" then sc.done = sc.done + 1 end
			if s.status == "PICKUP" then sc.pickups = sc.pickups + 1 end

			if #s.takes > 0 then
				shotsWithTakes = shotsWithTakes + 1
				totalTakes = totalTakes + #s.takes
				local cam = e.setup.camera ~= "" and e.setup.camera or ("SETUP " .. e.setup.letter)
				cams[cam] = (cams[cam] or 0) + #s.takes
				local lens = Model.lensOf(s)
				if lens ~= "" then
					local key = Vocab.fmtLens(lens)
					lenses[key] = (lenses[key] or 0) + #s.takes
				end
			end
			for _, t in ipairs(s.takes) do
				if t.t then
					if firstT == nil or t.t < firstT then firstT = t.t end
					if lastT == nil or t.t > lastT then lastT = t.t end
				end
				if t.circle then d.circled[#d.circled + 1] = { code = code, n = t.n, rating = t.rating } end
				if t.rating == "TECH" or (t.tech and t.tech ~= "") then
					d.technical[#d.technical + 1] = { code = code, n = t.n, issue = (t.tech ~= "" and t.tech) or "UNSPECIFIED",
						note = t.note }
				end
				if t.perf and t.perf ~= "" then
					d.performance[#d.performance + 1] = { code = code, n = t.n, issue = t.perf }
				end
			end
		end
	end
	for _, sc in ipairs(d.coverage) do
		sc.pct = sc.total > 0 and math.floor(sc.done * 100 / sc.total + 0.5) or 100
	end
	for _, dd in ipairs(project.days) do
		if day == nil or dd == day then
			for _, sc in ipairs(dd.scenes) do
				for _, n in ipairs(sc.notes) do
					if n.flag and not n.resolved then
						d.continuity[#d.continuity + 1] = { scene = sc.number, tag = n.tag, text = n.text }
					end
				end
			end
		end
	end
	d.cameras = sortedCounts(cams)
	d.lenses = sortedCounts(lenses)
	d.totalTakes = totalTakes
	d.shotsWithTakes = shotsWithTakes
	d.avgTakes = shotsWithTakes > 0 and math.floor(totalTakes * 10 / shotsWithTakes + 0.5) / 10 or 0
	d.progress = Model.progress(project, day)
	d.firstTake, d.lastTake = firstT, lastT
	return d
end

local function fmtAvg(v)
	local s = string.format("%.1f", v or 0)
	return s
end

-- Render to plain uppercase ASCII lines (<= 44 chars where possible).
function Report.lines(d)
	local L = {}
	local function add(s) L[#L + 1] = Util.upper(Util.ascii(s or "")) end
	local function section(title, count)
		add("")
		add("== " .. title .. (count and (" (" .. count .. ")") or "") .. " ==")
	end
	add(d.title .. (d.client ~= "" and (" / " .. d.client) or ""))
	add("WRAP REPORT - " .. d.scope)
	if d.generatedAt then add("GENERATED " .. Util.fmtDate(d.generatedAt) .. " " .. Util.fmtClock(d.generatedAt)) end
	local p = d.progress
	section("SUMMARY")
	add(string.format("%d SHOTS  %d COMPLETE  %d PICKUPS  %d REMAIN", p.total, p.done, p.pickups, p.remain))
	add(string.format("%d%% COMPLETE   %d CUT", p.pct, p.cut))
	add(string.format("%d TAKES  %s AVG TAKES/SHOT  %d CIRCLED", d.totalTakes, fmtAvg(d.avgTakes), #d.circled))
	if d.firstTake and d.lastTake then
		add("FIRST TAKE " .. Util.fmtClock(d.firstTake) .. "  LAST TAKE " .. Util.fmtClock(d.lastTake) ..
			"  (" .. Util.fmtDur((d.lastTake - d.firstTake) / 60) .. ")")
	end

	section("SCENE COVERAGE")
	for _, sc in ipairs(d.coverage) do
		local bar = string.rep("#", math.floor(sc.pct / 10)) .. string.rep(".", 10 - math.floor(sc.pct / 10))
		add(string.format("SC %-4s %s %3d%% %d/%d%s", sc.number, bar, sc.pct, sc.done, sc.total,
			sc.pickups > 0 and (" +" .. sc.pickups .. "PU") or ""))
	end

	section("MISSING SHOTS", #d.missing)
	for _, r in ipairs(d.missing) do
		add(string.format("%-8s %s %s", r.code, Vocab.PRIORITY_LABEL[r.pri] or "?", r.desc))
	end
	section("PICKUPS", #d.pickups)
	for _, r in ipairs(d.pickups) do add(string.format("%-8s %s", r.code, r.desc)) end
	section("CIRCLED TAKES", #d.circled)
	for _, r in ipairs(d.circled) do
		add(string.format("%-8s T%-3d %s", r.code, r.n, r.rating or ""))
	end
	section("TECHNICAL PROBLEMS", #d.technical)
	for _, r in ipairs(d.technical) do
		add(string.format("%-8s T%-3d %s%s", r.code, r.n, r.issue, (r.note and r.note ~= "") and (" - " .. r.note) or ""))
	end
	if #d.performance > 0 then
		section("PERFORMANCE NOTES", #d.performance)
		for _, r in ipairs(d.performance) do add(string.format("%-8s T%-3d %s", r.code, r.n, r.issue)) end
	end
	if #d.continuity > 0 then
		section("OPEN CONTINUITY FLAGS", #d.continuity)
		for _, r in ipairs(d.continuity) do add("SC " .. r.scene .. " " .. r.tag .. ": " .. r.text) end
	end
	section("CAMERA USAGE (TAKES)")
	for _, r in ipairs(d.cameras) do add(string.format("%-18s %d", r.name, r.n)) end
	section("LENS USAGE (TAKES)")
	for _, r in ipairs(d.lenses) do add(string.format("%-18s %d", r.name, r.n)) end
	section("COMPLETED SHOTS", #d.completed)
	for _, r in ipairs(d.completed) do add(string.format("%-8s %2dT %s", r.code, r.takes, r.desc)) end
	if #d.cut > 0 then
		section("CUT", #d.cut)
		for _, r in ipairs(d.cut) do add(string.format("%-8s %s", r.code, r.desc)) end
	end
	add("")
	add("-- END OF REPORT --")
	return L
end

return Report
