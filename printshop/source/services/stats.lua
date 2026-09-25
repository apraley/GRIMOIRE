-- Derived statistics over print history. Nothing here is stored: every
-- number is recomputed from Store.data.history so edits and migrations can
-- never leave stale aggregates behind.

Stats = {}

local function newAgg()
	return { prints = 0, successes = 0, failures = 0, cancels = 0, grams = 0, seconds = 0,
		causes = {}, nozzleSum = 0, nozzleN = 0, bedSum = 0, bedN = 0, lastAt = 0 }
end

local function addTo(a, h)
	a.prints = a.prints + 1
	a.grams = a.grams + h.grams
	a.seconds = a.seconds + h.durationSec
	a.lastAt = math.max(a.lastAt, h.endedAt)
	if h.outcome == "success" then
		a.successes = a.successes + 1
		if h.nozzleTemp > 0 then
			a.nozzleSum = a.nozzleSum + h.nozzleTemp
			a.nozzleN = a.nozzleN + 1
		end
		if h.bedTemp > 0 then
			a.bedSum = a.bedSum + h.bedTemp
			a.bedN = a.bedN + 1
		end
	elseif h.outcome == "failed" then
		a.failures = a.failures + 1
		a.causes[h.cause] = (a.causes[h.cause] or 0) + 1
	else
		a.cancels = a.cancels + 1
	end
end

local function finish(a)
	a.rate = (a.successes + a.failures) > 0 and a.successes / (a.successes + a.failures) or nil
	a.avgNozzle = a.nozzleN > 0 and U.roundInt(a.nozzleSum / a.nozzleN) or nil
	a.avgBed = a.bedN > 0 and U.roundInt(a.bedSum / a.bedN) or nil
	a.hours = a.seconds / 3600
	local top, topN = nil, 0
	for _, id in ipairs(Enums.CAUSE_IDS) do
		local n = a.causes[id] or 0
		if n > topN then top, topN = id, n end
	end
	a.topCause, a.topCauseCount = top, topN
	return a
end

local function each(filter, fn)
	for _, h in ipairs(Store.data.history) do
		if filter == nil or filter(h) then fn(h) end
	end
end

-- Stats for one material + manufacturer ("PETG / OVERTURE").
function Stats.combo(material, manufacturer)
	local a = newAgg()
	a.material, a.manufacturer = material, manufacturer
	each(function(h)
		return h.material == material and (manufacturer == nil or manufacturer == "ANY" or h.manufacturer == manufacturer)
	end, function(h) addTo(a, h) end)
	return finish(a)
end

-- Every material/manufacturer pair that has history, most-printed first.
function Stats.combos()
	local map, out = {}, {}
	each(nil, function(h)
		local k = h.material .. "|" .. h.manufacturer
		local a = map[k]
		if a == nil then
			a = newAgg()
			a.material, a.manufacturer = h.material, h.manufacturer
			map[k] = a
			out[#out + 1] = a
		end
		addTo(a, h)
	end)
	for _, a in ipairs(out) do finish(a) end
	U.stableSort(out, function(x, y) return x.prints > y.prints end)
	return out
end

function Stats.overall(printerId)
	local a = newAgg()
	each(function(h) return printerId == nil or h.printerId == printerId end, function(h) addTo(a, h) end)
	return finish(a)
end

function Stats.forSpool(spoolId)
	local a = newAgg()
	each(function(h) return h.spoolId == spoolId end, function(h) addTo(a, h) end)
	return finish(a)
end

-- Failure causes, most frequent first. `sinceDays` limits the window.
function Stats.causes(sinceDays, now)
	now = now or Clock.now()
	local counts = {}
	each(function(h)
		return h.outcome == "failed" and (sinceDays == nil or now - h.endedAt <= sinceDays * U.DAY)
	end, function(h) counts[h.cause] = (counts[h.cause] or 0) + 1 end)
	local out = {}
	for _, id in ipairs(Enums.CAUSE_IDS) do
		if counts[id] then out[#out + 1] = { cause = id, count = counts[id] } end
	end
	U.stableSort(out, function(a, b) return a.count > b.count end)
	return out
end

function Stats.recent(n, filter)
	local out = {}
	local list = Store.data.history
	for i = #list, 1, -1 do
		local h = list[i]
		if filter == nil or filter(h) then
			out[#out + 1] = h
			if #out >= (n or 10) then break end
		end
	end
	return out
end

-- Project history: every named project across queue and history.
function Stats.projects()
	local map, out = {}, {}
	local function get(name)
		local p = map[name]
		if p == nil then
			p = newAgg()
			p.name = name
			p.open = 0
			p.done = 0
			map[name] = p
			out[#out + 1] = p
		end
		return p
	end
	each(function(h) return h.project ~= "" end, function(h) addTo(get(h.project), h) end)
	for _, j in ipairs(Store.data.jobs) do
		if j.project ~= "" then
			local p = get(j.project)
			if Job.isActive(j) then p.open = p.open + 1 end
			if j.status == "COMPLETE" then p.done = p.done + 1 end
		end
	end
	for _, p in ipairs(out) do finish(p) end
	U.stableSort(out, function(a, b) return a.lastAt > b.lastAt end)
	return out
end

-- Prints per week, oldest first (for the tiny bar charts).
function Stats.weekly(weeks, now)
	now = now or Clock.now()
	weeks = weeks or 8
	local ok, bad = {}, {}
	for i = 1, weeks do ok[i], bad[i] = 0, 0 end
	each(nil, function(h)
		local age = (now - h.endedAt) // (7 * U.DAY)
		if age >= 0 and age < weeks then
			local i = weeks - age
			if h.outcome == "success" then ok[i] = ok[i] + 1 else bad[i] = bad[i] + 1 end
		end
	end)
	return ok, bad
end

-- Turns recent failures into concrete suggestions. Each suggestion names a
-- calibration procedure or maintenance task and why. Suggestions already
-- addressed (a calibration run or maintenance log newer than the failure)
-- are dropped, so doing the work makes the Captain stop nagging.
function Stats.suggestions(now)
	now = now or Clock.now()
	local out = {}
	local seen = {}
	local recent = Stats.recent(25, function(h) return h.outcome == "failed" and now - h.endedAt <= 45 * U.DAY end)
	for _, h in ipairs(recent) do
		local remedy = Enums.CAUSE_REMEDY[h.cause]
		if remedy then
			local key = Calibration.key(h.printerId, h.material, h.manufacturer)
			if remedy.calib then
				local id = "calib:" .. remedy.calib .. ":" .. key
				local run = CalService.lastRun(remedy.calib, key)
				if not seen[id] and (run == nil or run.at < h.endedAt) then
					seen[id] = true
					out[#out + 1] = { kind = "calib", target = remedy.calib, key = key, cause = h.cause,
						material = h.material, manufacturer = h.manufacturer, at = h.endedAt, weight = 3 }
				end
			end
			if remedy.maint then
				local task = U.find(Store.data.maintenance.tasks, function(t)
					return t.kind == remedy.maint and t.printerId == h.printerId
				end)
				local id = "maint:" .. remedy.maint
				if task and not seen[id] and task.lastAt < h.endedAt then
					seen[id] = true
					out[#out + 1] = { kind = "maint", target = task.id, taskName = task.name, cause = h.cause,
						material = h.material, manufacturer = h.manufacturer, at = h.endedAt, weight = 2 }
				end
			end
		end
	end
	-- Repeated causes weigh more.
	for _, s in ipairs(out) do
		local n = 0
		for _, h in ipairs(recent) do if h.cause == s.cause then n = n + 1 end end
		s.weight = s.weight + n
	end
	U.stableSort(out, function(a, b) return a.weight > b.weight end)
	return out
end

-- Filament "odometer" in metres for bragging rights.
function Stats.metersPrinted()
	local m = 0
	each(nil, function(h) m = m + h.grams / Enums.gramsPerMeter(h.material) end)
	return m
end

-- Money spent on filament across history (spools that still exist).
function Stats.filamentCost()
	local spent = 0
	each(nil, function(h)
		local s = h.spoolId ~= "" and Store.spool(h.spoolId) or nil
		if s then spent = spent + Filament.cost(s, h.grams) end
	end)
	return spent
end
