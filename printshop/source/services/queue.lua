-- PRINT QUEUE service. Store.data.jobs *is* the queue: its array order is
-- the manual print order. Filters produce views over it; moving an item in a
-- view swaps it with its neighbour in that view so hidden jobs keep their
-- relative places.

Queue = {}

Queue.FILTERS = { "ACTIVE", "ALL", "DONE", "ARCHIVED" }

local FILTER_FNS = {
	ACTIVE = function(j) return Job.isActive(j) end,
	ALL = function(j) return not j.archived end,
	DONE = function(j) return not j.archived and j.status == "COMPLETE" end,
	ARCHIVED = function(j) return j.archived end,
}

function Queue.list(filter)
	return U.filter(Store.data.jobs, FILTER_FNS[filter or "ACTIVE"] or FILTER_FNS.ACTIVE)
end

-- Copies the recommended calibration temps into a job and remembers which
-- profile they came from. Explicit temps on the job win unless force=true.
function Queue.applyProfile(j, force)
	local spool = j.spoolId and Store.spool(j.spoolId) or nil
	local rec = CalService.recommend(j.printerId, j.material, spool and spool.manufacturer or nil)
	-- Manual temperatures (set in the editor) are left alone, and so is the
	-- job's profileKey, so history never credits a profile for them.
	if force then j.manualTemps = false end
	if force or j.nozzleTemp == 0 then
		j.nozzleTemp = rec.nozzle
		if force or j.bedTemp == 0 then j.bedTemp = rec.bed end
		j.profileKey = rec.profile and rec.profile.key or ""
	elseif j.bedTemp == 0 then
		j.bedTemp = rec.bed
	end
	return rec
end

function Queue.add(fields)
	local j = Job.new(fields)
	j.id = Store.newId("j")
	j.createdAt = Clock.now()
	if j.printerId == nil or Store.printer(j.printerId) == nil then
		j.printerId = Store.activePrinter().id
	end
	local spool = j.spoolId and Store.spool(j.spoolId) or nil
	if spool then
		j.material = spool.material
		j.color = spool.color
	end
	Queue.applyProfile(j)
	Store.data.jobs[#Store.data.jobs + 1] = j
	Store.markDirty()
	Events.emit("job.added", { job = j })
	return j
end

-- Inserts the copy right after the original.
function Queue.duplicate(j)
	local copy = U.deepcopy(j)
	copy.id = Store.newId("j")
	copy.name = U.truncate(j.name, 22) .. " +"
	copy.status = (j.status == "PRINTING" or j.status == "PAUSED" or j.status == "COMPLETE" or j.status == "FAILED") and "QUEUED" or j.status
	copy.createdAt = Clock.now()
	copy.startedAt, copy.completedAt, copy.attempts = 0, 0, 0
	copy.archived = false
	copy.source = "queue"
	local _, idx = U.findById(Store.data.jobs, j.id)
	table.insert(Store.data.jobs, (idx or #Store.data.jobs) + 1, copy)
	Store.markDirty()
	return copy
end

function Queue.archive(j, flag)
	if j.status == "PRINTING" or j.status == "PAUSED" then return false end
	j.archived = flag ~= false
	Store.markDirty()
	return true
end

function Queue.remove(j)
	if j.status == "PRINTING" or j.status == "PAUSED" then return false end
	local _, idx = U.findById(Store.data.jobs, j.id)
	if idx then table.remove(Store.data.jobs, idx) end
	Store.markDirty()
	return true
end

function Queue.setStatus(j, status)
	j.status = U.oneOf(status, Enums.JOB_STATUS, j.status)
	if status == "COMPLETE" and j.completedAt == 0 then j.completedAt = Clock.now() end
	Store.markDirty()
end

-- Moves job j by delta positions within `view` (a filtered list). Returns the
-- job's new index inside the view.
function Queue.move(j, delta, view)
	view = view or Store.data.jobs
	local _, vi = U.findById(view, j.id)
	if vi == nil then return nil end
	local ti = U.clamp(vi + delta, 1, #view)
	if ti == vi then return vi end
	local other = view[ti]
	local jobs = Store.data.jobs
	local _, a = U.findById(jobs, j.id)
	local _, b = U.findById(jobs, other.id)
	-- Move j to other's slot in the master list; everything between shifts.
	U.moveItem(jobs, a, b)
	-- Keep the view consistent for the caller (unless it *is* the list).
	if view ~= jobs then U.moveItem(view, vi, ti) end
	Store.markDirty()
	return ti
end

-- A failed or finished job goes back in line with the latest profile.
function Queue.retry(j)
	j.status = "QUEUED"
	j.completedAt = 0
	j.archived = false
	-- Re-profile unless the temperatures were set by hand.
	Queue.applyProfile(j, not j.manualTemps)
	Store.markDirty()
	Events.emit("job.retry", { job = j })
	return j
end

-- Stable sort of the active jobs by priority (high first); others untouched.
function Queue.sortByPriority()
	local active, rest = {}, {}
	for _, j in ipairs(Store.data.jobs) do
		if Job.isActive(j) then active[#active + 1] = j else rest[#rest + 1] = j end
	end
	U.stableSort(active, function(a, b) return a.priority > b.priority end)
	local out = {}
	for _, j in ipairs(active) do out[#out + 1] = j end
	for _, j in ipairs(rest) do out[#out + 1] = j end
	Store.data.jobs = out
	Store.markDirty()
end

-- Next job to print on a printer: first QUEUED in order, else first READY.
function Queue.nextFor(printerId)
	local ready = nil
	for _, j in ipairs(Store.data.jobs) do
		if not j.archived and j.printerId == printerId then
			if j.status == "QUEUED" then return j end
			if j.status == "READY" and ready == nil then ready = j end
		end
	end
	return ready
end

function Queue.current(printerId)
	for _, j in ipairs(Store.data.jobs) do
		if j.printerId == printerId and (j.status == "PRINTING" or j.status == "PAUSED") then
			return j
		end
	end
	return nil
end

function Queue.counts()
	local c = { total = 0 }
	for _, s in ipairs(Enums.JOB_STATUS) do c[s] = 0 end
	for _, j in ipairs(Store.data.jobs) do
		if not j.archived then
			c[j.status] = c[j.status] + 1
			c.total = c.total + 1
		end
	end
	return c
end

-- Remaining queued work in minutes and grams (QUEUED + READY).
function Queue.backlog()
	local mins, grams, n = 0, 0, 0
	for _, j in ipairs(Store.data.jobs) do
		if not j.archived and (j.status == "QUEUED" or j.status == "READY") then
			mins = mins + j.estMinutes
			grams = grams + j.estGrams
			n = n + 1
		end
	end
	return { minutes = mins, grams = grams, count = n }
end

function Queue.projects()
	local seen, out = {}, {}
	for _, j in ipairs(Store.data.jobs) do
		if j.project ~= "" and not seen[j.project] then
			seen[j.project] = true
			out[#out + 1] = j.project
		end
	end
	for _, h in ipairs(Store.data.history) do
		if h.project ~= "" and not seen[h.project] then
			seen[h.project] = true
			out[#out + 1] = h.project
		end
	end
	table.sort(out)
	return out
end

-- Warns when a job needs more filament than its spool holds.
function Queue.filamentShortfall(j)
	local s = j.spoolId and Store.spool(j.spoolId) or nil
	if s == nil then return nil end
	if s.remainingGrams < j.estGrams then
		return j.estGrams - s.remainingGrams
	end
	return nil
end
