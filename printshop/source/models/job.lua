-- Print job model (a row in the PRINT QUEUE).

Job = {}

Job.DEFAULTS = {
	name = "UNTITLED",
	model = "",
	printerId = "p1",
	spoolId = nil,
	material = "PLA",
	color = "BLACK",
	estMinutes = 60,
	estGrams = 20,
	priority = 2,
	status = "IDEA",
	notes = "",
	project = "",
	shape = "cube",
	layers = 100,
	nozzleTemp = 0,     -- 0 = use recommended profile at print time
	bedTemp = 0,
	profileKey = "",
	manualTemps = false, -- temps set by hand in the editor; profiles leave them
	attempts = 0,
	archived = false,
	createdAt = 0,
	startedAt = 0,
	completedAt = 0,
	source = "queue",   -- "queue" or "printer" (discovered on a live printer)
}

function Job.new(fields)
	local j = U.copy(fields or {})
	U.defaults(j, Job.DEFAULTS)
	return Job.normalize(j)
end

-- Repairs a job loaded from disk: types, enums and ranges.
function Job.normalize(j)
	U.defaults(j, Job.DEFAULTS)
	j.id = U.str(j.id, nil)
	j.name = U.str(j.name, "UNTITLED")
	j.model = U.str(j.model, "")
	j.material = U.oneOf(j.material, Enums.MATERIALS, "OTHER")
	j.color = U.str(j.color, "BLACK")
	j.status = U.oneOf(j.status, Enums.JOB_STATUS, "IDEA")
	j.estMinutes = U.clamp(U.int(j.estMinutes, 60), 1, 60 * 24 * 7)
	j.estGrams = U.clamp(U.num(j.estGrams, 20), 0, 5000)
	j.priority = U.clamp(U.int(j.priority, 2), 1, #Enums.PRIORITY)
	j.layers = U.clamp(U.int(j.layers, 100), 1, 5000)
	j.attempts = math.max(0, U.int(j.attempts, 0))
	j.shape = U.oneOf(j.shape, Enums.SHAPES, "cube")
	j.archived = j.archived == true
	j.manualTemps = j.manualTemps == true
	j.createdAt = U.int(j.createdAt, 0)
	j.startedAt = U.int(j.startedAt, 0)
	j.completedAt = U.int(j.completedAt, 0)
	j.nozzleTemp = U.int(j.nozzleTemp, 0)
	j.bedTemp = U.int(j.bedTemp, 0)
	j.notes = U.str(j.notes, "")
	j.project = U.str(j.project, "")
	j.profileKey = U.str(j.profileKey, "")
	return j
end

function Job.isActive(j)
	return not j.archived and Enums.JOB_ACTIVE[j.status] == true
end

function Job.isStartable(j)
	return not j.archived and Enums.JOB_STARTABLE[j.status] == true
end

function Job.priorityLabel(j)
	return Enums.PRIORITY[j.priority] or "NORMAL"
end

-- Short status tag for list rows.
Job.STATUS_TAG = {
	IDEA = "IDEA", READY = "RDY", QUEUED = "QUE", PRINTING = "PRN",
	PAUSED = "PAU", FAILED = "ERR", COMPLETE = "DON",
}
