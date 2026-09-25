-- Save-file schema: versioning, migrations and whole-document repair.
--
-- Schema history
--   v1  First release. Top-level `version` key. Spools used `remaining` and a
--       single `temp`. Failures lived in their own `failures` list; history
--       rows had `ok = true/false`. Maintenance tasks stored
--       `interval = { kind = "hours"|"days", value = n }` and `last`.
--       Archived jobs used a pseudo-status "ARCHIVED". Calibrations were keyed
--       by material only with short field names.
--   v2  `schema` key; spools gain dryness/location; remaining -> remainingGrams,
--       temp -> favNozzle.
--   v3  Failures folded into history (`outcome`, `cause`); `failures` removed.
--   v4  Maintenance gets independent hour/day intervals; `archived` flag on
--       jobs; calibration profiles keyed printer|material|manufacturer.
--   v5  Non-temperature calibration fields use nil (not 0) for "not
--       calibrated"; jobs carry `manualTemps`.
--
-- To add v5: bump Schema.CURRENT, append Schema.migrations[5], and extend
-- Schema.repair() for any new sections. Migrations must be idempotent-safe on
-- partially-migrated data because a crash mid-save can leave odd shapes.

Schema = {
	CURRENT = 5,
	migrations = {},
}

Schema.migrations[2] = function(d)
	d.schema = 2
	d.version = nil
	for _, s in ipairs(U.asList(d.spools)) do
		if s.remainingGrams == nil and s.remaining ~= nil then
			s.remainingGrams = s.remaining
		end
		s.remaining = nil
		if s.favNozzle == nil and s.temp ~= nil then
			s.favNozzle = s.temp
		end
		s.temp = nil
		s.dryness = s.dryness or "OK"
		s.location = s.location or "SHELF"
	end
	return d
end

Schema.migrations[3] = function(d)
	d.schema = 3
	d.history = U.asList(d.history)
	for _, h in ipairs(d.history) do
		if h.outcome == nil then
			if h.ok == false then h.outcome = "failed" else h.outcome = "success" end
		end
		h.ok = nil
		if h.jobName == nil and h.name ~= nil then h.jobName = h.name end
		h.name = nil
		if h.endedAt == nil and h.at ~= nil then h.endedAt = h.at end
		h.at = nil
	end
	for _, f in ipairs(U.asList(d.failures)) do
		local match = nil
		for _, h in ipairs(d.history) do
			if h.jobId == f.jobId and h.endedAt == f.at then match = h break end
		end
		if match == nil then
			match = {
				id = f.id, jobId = f.jobId, jobName = f.jobName or "", spoolId = f.spoolId,
				endedAt = f.at, grams = f.grams or 0, material = f.material,
			}
			d.history[#d.history + 1] = match
		end
		match.outcome = "failed"
		match.cause = f.cause or "unknown"
		if f.notes then match.notes = f.notes end
	end
	d.failures = nil
	return d
end

Schema.migrations[4] = function(d)
	d.schema = 4
	local m = d.maintenance or {}
	-- v1 stored the task list directly; later shapes nest it under `tasks`.
	local tasks = U.asList(m.tasks or (m[1] ~= nil and m) or {})
	for _, t in ipairs(tasks) do
		if type(t.interval) == "table" then
			if t.interval.kind == "hours" then t.intervalHours = t.interval.value
			elseif t.interval.kind == "days" then t.intervalDays = t.interval.value end
		end
		t.interval = nil
		if t.lastAt == nil and t.last ~= nil then t.lastAt = t.last end
		t.last = nil
	end
	d.maintenance = { tasks = tasks, log = U.asList(m.log) }

	for _, j in ipairs(U.asList(d.jobs)) do
		if j.status == "ARCHIVED" then
			j.status = "COMPLETE"
			j.archived = true
		end
	end

	local old = d.calibrations or {}
	local new = {}
	for k, p in pairs(old) do
		if type(p) == "table" then
			local key = k
			if not string.find(k, "|", 1, true) then
				key = Calibration.key("p1", k, "ANY")
			end
			p.key = key
			if p.nozzleTemp == nil and p.nozzle ~= nil then p.nozzleTemp = p.nozzle end
			if p.bedTemp == nil and p.bed ~= nil then p.bedTemp = p.bed end
			if p.flowRatio == nil and p.flow ~= nil then p.flowRatio = p.flow end
			p.nozzle, p.bed, p.flow = nil, nil, nil
			new[key] = p
		end
	end
	d.calibrations = new
	return d
end

Schema.CAL_ZERO_FIELDS = { "flowRatio", "retractLength", "retractSpeed", "xyScale", "zScale", "tolerance", "zOffset" }

Schema.migrations[5] = function(d)
	d.schema = 5
	-- Zeros used to mean "not calibrated". Keep a zero only if some stored
	-- run actually produced it (a real 0.00 Z offset, say).
	local measured = {}
	for _, r in ipairs(U.asList(d.calibRuns)) do
		if type(r) == "table" and type(r.results) == "table" then
			for k, v in pairs(r.results) do
				if v == 0 then measured[tostring(r.key) .. "#" .. k] = true end
			end
		end
	end
	if type(d.calibrations) == "table" then
		for key, p in pairs(d.calibrations) do
			if type(p) == "table" then
				for _, f in ipairs(Schema.CAL_ZERO_FIELDS) do
					if p[f] == 0 and not measured[tostring(p.key or key) .. "#" .. f] then p[f] = nil end
				end
			end
		end
	end
	-- Hand-set temps: no profile and not the material default.
	for _, j in ipairs(U.asList(d.jobs)) do
		if type(j) == "table" and j.manualTemps == nil then
			local info = Enums.materialInfo(j.material)
			local n = tonumber(j.nozzleTemp) or 0
			j.manualTemps = (j.profileKey == nil or j.profileKey == "") and n > 0 and n ~= info.nozzle
		end
	end
	return d
end

-- Returns the schema version of a raw document (v1 used `version`).
function Schema.versionOf(d)
	if type(d) ~= "table" then return 0 end
	return U.int(d.schema or d.version, 1)
end

-- Migrates in place from whatever version d is at up to CURRENT.
-- Returns d, fromVersion, list of applied versions.
function Schema.migrate(d)
	local from = Schema.versionOf(d)
	local applied = {}
	local v = from
	while v < Schema.CURRENT do
		v = v + 1
		local step = Schema.migrations[v]
		if step then
			d = step(d) or d
			applied[#applied + 1] = v
		end
	end
	d.schema = math.max(Schema.versionOf(d), Schema.CURRENT)
	return d, from, applied
end

local function repairList(list, normalize, prefix, meta)
	local out = {}
	local seen = {}
	for _, item in ipairs(U.asList(list)) do
		if type(item) == "table" then
			normalize(item)
			if item.id == nil or seen[item.id] then
				item.id = prefix .. meta.nextId
				meta.nextId = meta.nextId + 1
			end
			seen[item.id] = true
			out[#out + 1] = item
		end
	end
	return out
end

-- Largest numeric suffix among ids, so new ids never collide after a load.
local function maxIdNumber(d)
	local maxN = 0
	local function scan(list)
		if type(list) ~= "table" then return end
		for _, item in pairs(list) do
			local n = type(item) == "table" and tonumber(string.match(tostring(item.id or ""), "(%d+)$")) or nil
			if n and n > maxN then maxN = n end
		end
	end
	scan(d.printers) scan(d.spools) scan(d.jobs) scan(d.history)
	scan(d.consumption) scan(d.calibRuns)
	if type(d.maintenance) == "table" then scan(d.maintenance.tasks) scan(d.maintenance.log) end
	return maxN
end

Schema.SETTINGS_DEFAULTS = {
	activePrinterId = "p1",
	demoSpeed = 60,
	theme = "night",
	sound = true,
	lowSpoolGrams = 150,
	typeSpeed = 2,
	autoConsume = true,
	demoChaos = true,
}

-- Makes any (migrated) document safe to use: every section present, every
-- record normalized, ids unique, cross references valid.
function Schema.repair(d)
	if type(d) ~= "table" then d = {} end
	d.meta = type(d.meta) == "table" and d.meta or {}
	d.meta.nextId = math.max(U.int(d.meta.nextId, 1), 1)
	d.meta.createdAt = U.int(d.meta.createdAt, 0)
	d.meta.saves = U.int(d.meta.saves, 0)
	-- Reserve ids above every existing one before repairs hand out new ids.
	d.meta.nextId = math.max(d.meta.nextId, maxIdNumber(d) + 1)

	d.settings = type(d.settings) == "table" and d.settings or {}
	U.defaults(d.settings, Schema.SETTINGS_DEFAULTS)
	d.settings.demoSpeed = U.clamp(U.int(d.settings.demoSpeed, 60), 1, 3600)
	d.settings.lowSpoolGrams = U.clamp(U.int(d.settings.lowSpoolGrams, 150), 0, 2000)
	d.settings.theme = U.oneOf(d.settings.theme, { "night", "day" }, "night")

	d.printers = repairList(d.printers, Printer.normalize, "p", d.meta)
	d.spools = repairList(d.spools, Spool.normalize, "s", d.meta)
	d.jobs = repairList(d.jobs, Job.normalize, "j", d.meta)
	d.history = repairList(d.history, History.normalize, "h", d.meta)
	d.consumption = repairList(d.consumption, Consumption.normalize, "c", d.meta)
	d.calibRuns = repairList(d.calibRuns, function(r)
		r.id = U.str(r.id, nil)
		r.procedure = U.str(r.procedure, "")
		r.key = U.str(r.key, "")
		r.at = U.int(r.at, 0)
		if type(r.results) ~= "table" then r.results = {} end
		r.notes = U.str(r.notes, "")
	end, "r", d.meta)

	local m = type(d.maintenance) == "table" and d.maintenance or {}
	d.maintenance = {
		tasks = repairList(m.tasks, Maint.normalize, "m", d.meta),
		log = repairList(m.log, MaintLog.normalize, "l", d.meta),
	}

	local cal = {}
	if type(d.calibrations) == "table" then
		for k, p in pairs(d.calibrations) do
			if type(p) == "table" then
				p.key = p.key or k
				Calibration.normalize(p)
				cal[p.key] = p
			end
		end
	end
	d.calibrations = cal

	d.captain = type(d.captain) == "table" and d.captain or {}
	U.defaults(d.captain, { counter = 0, seenIntro = false, lastTopics = {}, inbox = {}, lastDay = 0 })
	d.captain.lastTopics = U.asList(d.captain.lastTopics)
	d.captain.inbox = U.asList(d.captain.inbox)

	local log = {}
	for _, e in ipairs(U.asList(d.printLog)) do
		if type(e) == "table" then
			log[#log + 1] = { at = U.int(e.at, 0), text = U.upper(U.str(e.text, "")) }
		end
	end
	d.printLog = log
	d.providerState = type(d.providerState) == "table" and d.providerState or {}
	if type(d.pendingFailure) ~= "table" then d.pendingFailure = nil end
	if type(d.runout) ~= "table" then d.runout = nil end

	-- There must always be at least one printer to attach jobs to.
	if #d.printers == 0 then
		d.printers[1] = Printer.new({ id = "p1" })
	end
	if U.findById(d.printers, d.settings.activePrinterId) == nil then
		d.settings.activePrinterId = d.printers[1].id
	end

	-- Dangling references: a deleted spool/printer must not crash screens.
	for _, j in ipairs(d.jobs) do
		if j.spoolId ~= nil and U.findById(d.spools, j.spoolId) == nil then j.spoolId = nil end
		if U.findById(d.printers, j.printerId) == nil then j.printerId = d.printers[1].id end
	end
	for _, t in ipairs(d.maintenance.tasks) do
		if U.findById(d.printers, t.printerId) == nil then t.printerId = d.printers[1].id end
	end
	-- Only one job may be PRINTING/PAUSED per printer; extras fall back to QUEUED.
	local busy = {}
	for _, j in ipairs(d.jobs) do
		if j.status == "PRINTING" or j.status == "PAUSED" then
			if busy[j.printerId] then j.status = "QUEUED" else busy[j.printerId] = true end
		end
	end

	d.meta.nextId = math.max(d.meta.nextId, maxIdNumber(d) + 1)
	d.schema = Schema.CURRENT
	return d
end
