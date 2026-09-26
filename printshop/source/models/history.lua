-- Print history record: one per finished attempt (success, failure or
-- cancel). Failures carry their cause here; failure statistics are derived
-- from these records rather than stored separately.
--
-- Consumption entries are stored alongside (Store.data.consumption) so the
-- Rolodex can graph usage for spools that were also adjusted manually.

History = {}

History.OUTCOMES = { "success", "failed", "cancelled" }

History.DEFAULTS = {
	jobId = "",
	jobName = "",
	project = "",
	printerId = "p1",
	spoolId = "",
	material = "PLA",
	manufacturer = "GENERIC",
	color = "",
	outcome = "success",
	cause = "",
	notes = "",
	startedAt = 0,
	endedAt = 0,
	durationSec = 0,
	grams = 0,
	progress = 1,
	layer = 0,
	nozzleTemp = 0,
	bedTemp = 0,
	profileKey = "",
}

function History.new(fields)
	local h = U.copy(fields or {})
	return History.normalize(h)
end

function History.normalize(h)
	U.defaults(h, History.DEFAULTS)
	h.id = U.str(h.id, nil)
	h.outcome = U.oneOf(h.outcome, History.OUTCOMES, "success")
	h.material = U.oneOf(h.material, Enums.MATERIALS, "OTHER")
	h.manufacturer = U.upper(U.str(h.manufacturer, "GENERIC"))
	if h.outcome == "failed" then
		h.cause = U.oneOf(h.cause, Enums.CAUSE_IDS, "unknown")
	else
		h.cause = ""
	end
	h.startedAt = U.int(h.startedAt, 0)
	h.endedAt = U.int(h.endedAt, 0)
	h.durationSec = math.max(0, U.int(h.durationSec, 0))
	h.grams = math.max(0, U.num(h.grams, 0))
	h.progress = U.clamp(U.num(h.progress, 1), 0, 1)
	h.layer = math.max(0, U.int(h.layer, 0))
	h.nozzleTemp = U.int(h.nozzleTemp, 0)
	h.bedTemp = U.int(h.bedTemp, 0)
	return h
end

Consumption = {}

Consumption.KINDS = { "print", "failed", "manual", "purge", "adjust" }

function Consumption.normalize(c)
	c.id = U.str(c.id, nil)
	c.spoolId = U.str(c.spoolId, "")
	c.at = U.int(c.at, 0)
	c.grams = U.num(c.grams, 0)
	c.kind = U.oneOf(c.kind, Consumption.KINDS, "manual")
	c.jobId = U.str(c.jobId, "")
	c.note = U.str(c.note, "")
	return c
end
