-- CALIBRATION service: profiles, recommendations and stored runs.

CalService = {}

function CalService.profile(key)
	return Store.data.calibrations[key]
end

function CalService.ensure(key, recommended)
	local p = Store.data.calibrations[key]
	if p == nil then
		p = Calibration.new(key, { recommended = recommended == true })
		Store.data.calibrations[p.key] = p
		Store.markDirty()
	end
	return p
end

-- Profiles for a printer, most recently updated first.
function CalService.profiles(printerId)
	local out = {}
	for _, p in pairs(Store.data.calibrations) do
		if printerId == nil or p.printerId == printerId then out[#out + 1] = p end
	end
	table.sort(out, function(a, b)
		if a.updatedAt == b.updatedAt then return a.key < b.key end
		return a.updatedAt > b.updatedAt
	end)
	return out
end

-- The settings a new job should use. Looks for the most specific profile
-- that is marked recommended: exact maker, then material-wide ("ANY"), then
-- material defaults. Returns { nozzle, bed, profile, level }.
function CalService.recommend(printerId, material, manufacturer)
	printerId = printerId or Store.activePrinter().id
	local info = Enums.materialInfo(material)
	local candidates = {}
	if manufacturer and manufacturer ~= "" then
		candidates[#candidates + 1] = { Calibration.key(printerId, material, manufacturer), "exact" }
	end
	candidates[#candidates + 1] = { Calibration.key(printerId, material, "ANY"), "material" }
	for _, c in ipairs(candidates) do
		local p = Store.data.calibrations[c[1]]
		if p and p.recommended and (p.nozzleTemp > 0 or p.bedTemp > 0) then
			return {
				nozzle = p.nozzleTemp > 0 and p.nozzleTemp or info.nozzle,
				bed = p.bedTemp > 0 and p.bedTemp or info.bed,
				flow = p.flowRatio,
				profile = p, level = c[2],
			}
		end
	end
	return { nozzle = info.nozzle, bed = info.bed, profile = nil, level = "default" }
end

function CalService.lastRun(procId, key)
	local runs = Store.data.calibRuns
	for i = #runs, 1, -1 do
		local r = runs[i]
		if r.procedure == procId and (key == nil or r.key == key) then return r end
	end
	return nil
end

function CalService.runsFor(key, limit)
	local out = {}
	local runs = Store.data.calibRuns
	for i = #runs, 1, -1 do
		if key == nil or runs[i].key == key then
			out[#out + 1] = runs[i]
			if limit and #out >= limit then break end
		end
	end
	return out
end

-- Stores a finished procedure. `fields` are the computed profile values.
-- When makeRecommended, the profile's temps flow into matching spools'
-- favourite temps and into queued (not yet started) jobs using this combo.
function CalService.save(procId, key, fields, notes, makeRecommended)
	local p = CalService.ensure(key, makeRecommended)
	for k, v in pairs(fields) do
		if v ~= nil then p[k] = v end
	end
	p.updatedAt = Clock.now()
	p.runs = p.runs + 1
	if makeRecommended ~= nil then p.recommended = makeRecommended end
	Calibration.normalize(p)

	local run = {
		id = Store.newId("r"), procedure = procId, key = p.key, at = Clock.now(),
		results = U.copy(fields), notes = notes or "",
	}
	local runs = Store.data.calibRuns
	runs[#runs + 1] = run
	while #runs > 120 do table.remove(runs, 1) end

	local touchedJobs = 0
	-- Only temperature results change spools and queued jobs.
	local temps = fields.nozzleTemp ~= nil or fields.bedTemp ~= nil
	if p.recommended and temps then
		for _, s in ipairs(Store.data.spools) do
			if s.material == p.material and (p.manufacturer == "ANY" or s.manufacturer == p.manufacturer) then
				if fields.nozzleTemp then s.favNozzle = fields.nozzleTemp end
				if fields.bedTemp then s.favBed = fields.bedTemp end
			end
		end
		for _, j in ipairs(Store.data.jobs) do
			if not j.archived and (j.status == "QUEUED" or j.status == "READY" or j.status == "IDEA" or j.status == "FAILED")
				and j.printerId == p.printerId and j.material == p.material then
				local s = j.spoolId and Store.spool(j.spoolId) or nil
				local maker = s and s.manufacturer or nil
				-- Jobs with hand-set temps (no profileKey) keep them.
				local manual = j.manualTemps
				if (p.manufacturer == "ANY" or maker == p.manufacturer) and not manual then
					local before = j.nozzleTemp .. "/" .. j.bedTemp .. "/" .. j.profileKey
					Queue.applyProfile(j, true)
					if j.nozzleTemp .. "/" .. j.bedTemp .. "/" .. j.profileKey ~= before then
						touchedJobs = touchedJobs + 1
					end
				end
			end
		end
	end
	Store.markDirty()
	Events.emit("calib.saved", { profile = p, run = run, procedure = procId, jobsUpdated = touchedJobs })
	return p, run, touchedJobs
end

function CalService.setRecommended(p, flag)
	p.recommended = flag
	Store.markDirty()
end

function CalService.delete(p)
	Store.data.calibrations[p.key] = nil
	Store.markDirty()
end

-- Context passed to procedure steps.
function CalService.context(key)
	local printerId, material, manufacturer = Calibration.splitKey(key)
	return {
		key = key,
		profile = Store.data.calibrations[key],
		printer = Store.printer(printerId),
		material = material,
		manufacturer = manufacturer,
		info = Enums.materialInfo(material),
	}
end
