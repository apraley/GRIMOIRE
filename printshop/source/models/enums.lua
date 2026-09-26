-- Shared vocabularies. Everything that is persisted as a string enum lives
-- here so normalizers, screens and the Captain agree on the spelling.

Enums = {}

Enums.JOB_STATUS = { "IDEA", "READY", "QUEUED", "PRINTING", "PAUSED", "FAILED", "COMPLETE" }

-- Statuses that are "on the bench": shown in the active queue, eligible to print.
Enums.JOB_ACTIVE = { IDEA = true, READY = true, QUEUED = true, PRINTING = true, PAUSED = true, FAILED = true }
Enums.JOB_STARTABLE = { READY = true, QUEUED = true, FAILED = true }

Enums.MATERIALS = { "PLA", "PETG", "TPU", "ABS", "ASA", "OTHER" }

-- Reference numbers per material. density g/cm3; temps are sane defaults used
-- when no calibration profile exists yet.
Enums.MATERIAL_INFO = {
	PLA  = { density = 1.24, nozzle = 215, bed = 60, nozzleMin = 190, nozzleMax = 235, bedMin = 45, bedMax = 70,  retract = 0.8, hygro = 1 },
	PETG = { density = 1.27, nozzle = 240, bed = 70, nozzleMin = 220, nozzleMax = 260, bedMin = 60, bedMax = 85,  retract = 1.2, hygro = 2 },
	TPU  = { density = 1.21, nozzle = 225, bed = 45, nozzleMin = 200, nozzleMax = 245, bedMin = 30, bedMax = 60,  retract = 0.4, hygro = 3 },
	ABS  = { density = 1.04, nozzle = 250, bed = 95, nozzleMin = 230, nozzleMax = 270, bedMin = 80, bedMax = 110, retract = 0.8, hygro = 2 },
	ASA  = { density = 1.07, nozzle = 255, bed = 95, nozzleMin = 235, nozzleMax = 275, bedMin = 80, bedMax = 110, retract = 0.8, hygro = 2 },
	OTHER= { density = 1.20, nozzle = 220, bed = 60, nozzleMin = 180, nozzleMax = 300, bedMin = 0,  bedMax = 110, retract = 0.8, hygro = 2 },
}

-- 1.75 mm filament cross-section in cm^2 (pi * 0.0875^2); grams per metre =
-- area * 100 cm * density.
Enums.FILAMENT_AREA_CM2 = 0.024053

function Enums.gramsPerMeter(material)
	local info = Enums.MATERIAL_INFO[material] or Enums.MATERIAL_INFO.OTHER
	return Enums.FILAMENT_AREA_CM2 * 100 * info.density
end

Enums.FAILURE_CAUSES = {
	{ id = "spaghetti",  label = "SPAGHETTI" },
	{ id = "adhesion",   label = "ADHESION" },
	{ id = "layershift", label = "LAYER SHIFT" },
	{ id = "stringing",  label = "STRINGING" },
	{ id = "underext",   label = "UNDER EXTRUSION" },
	{ id = "overext",    label = "OVER EXTRUSION" },
	{ id = "clog",       label = "CLOG" },
	{ id = "support",    label = "SUPPORT FAILURE" },
	{ id = "dimension",  label = "DIMENSIONAL ERROR" },
	{ id = "unknown",    label = "UNKNOWN" },
}

Enums.CAUSE_LABEL = {}
Enums.CAUSE_IDS = {}
for _, c in ipairs(Enums.FAILURE_CAUSES) do
	Enums.CAUSE_LABEL[c.id] = c.label
	Enums.CAUSE_IDS[#Enums.CAUSE_IDS + 1] = c.id
end

-- Which calibration procedure and maintenance task address each cause. The
-- Captain and the stats screen use this to turn failures into advice.
Enums.CAUSE_REMEDY = {
	spaghetti  = { calib = "firstlayer", maint = "bed_clean" },
	adhesion   = { calib = "firstlayer", maint = "bed_clean" },
	layershift = { calib = nil,          maint = "belts" },
	stringing  = { calib = "retraction", maint = nil, alt = "temptower" },  -- alt: second suggestion
	underext   = { calib = "flow",       maint = "extruder_clean" },
	overext    = { calib = "flow",       maint = nil },
	clog       = { calib = "temptower",  maint = "nozzle" },
	support    = { calib = "tolerance",  maint = nil },
	dimension  = { calib = "dimension",  maint = "belts" },
	unknown    = { calib = "bedlevel",   maint = nil },
}

Enums.DRYNESS = { "SEALED", "DRY", "OK", "DAMP", "WET" }

Enums.PRINTER_STATES = { "IDLE", "HEATING", "PRINTING", "PAUSED", "ERROR", "COMPLETE", "OFFLINE" }

Enums.PRIORITY = { "LOW", "NORMAL", "HIGH", "URGENT", "RUSH" }

Enums.COLORS = {
	"BLACK", "WHITE", "GRAY", "RED", "ORANGE", "YELLOW", "GREEN", "BLUE",
	"PURPLE", "PINK", "BROWN", "CLEAR", "GOLD", "SILVER", "OLIVE", "NAVY",
}

Enums.MANUFACTURERS = {
	"BAMBU", "OVERTURE", "POLYMAKER", "ESUN", "SUNLU", "PRUSAMENT",
	"ELEGOO", "HATCHBOX", "JAYO", "GENERIC",
}

-- Silhouettes the print visualizer knows how to grow layer by layer.
Enums.SHAPES = { "benchy", "cube", "vase", "bracket", "gear", "figure", "box", "tower" }

Enums.PROVIDERS = { "demo", "bridge", "bambu" }
Enums.PROVIDER_LABEL = { demo = "DEMO SIM", bridge = "LOCAL BRIDGE", bambu = "BAMBU (VIA BRIDGE)" }

Enums.MAINT_KINDS = {
	{ id = "nozzle",         label = "NOZZLE CHANGE" },
	{ id = "lube",           label = "LUBRICATION" },
	{ id = "bed_clean",      label = "BED CLEANING" },
	{ id = "belts",          label = "BELT INSPECTION" },
	{ id = "extruder_clean", label = "EXTRUDER CLEANING" },
	{ id = "firmware",       label = "FIRMWARE NOTES" },
	{ id = "parts",          label = "REPLACEMENT PART" },
	{ id = "custom",         label = "CUSTOM" },
}

Enums.MAINT_LABEL = {}
for _, k in ipairs(Enums.MAINT_KINDS) do Enums.MAINT_LABEL[k.id] = k.label end

function Enums.materialInfo(material)
	return Enums.MATERIAL_INFO[material] or Enums.MATERIAL_INFO.OTHER
end
