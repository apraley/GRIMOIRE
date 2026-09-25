-- Calibration profile model.
--
-- A profile is the best-known settings for one printer + material +
-- manufacturer combination, keyed "printerId|MATERIAL|MANUFACTURER". The
-- manufacturer part may be "ANY" for a material-wide fallback. Each guided
-- procedure writes some of these fields; new queue entries copy the
-- recommended profile's temperatures.

Calibration = {}

Calibration.FIELDS = {
	-- field, label, unit, format
	{ "nozzleTemp",   "NOZZLE",     "C",  "%d" },
	{ "bedTemp",      "BED",        "C",  "%d" },
	{ "flowRatio",    "FLOW",       "",   "%.2f" },
	{ "retractLength","RETRACT",    "mm", "%.1f" },
	{ "retractSpeed", "RETR SPD",   "mm/s", "%d" },
	{ "xyScale",      "XY SCALE",   "%",  "%.1f" },
	{ "zScale",       "Z SCALE",    "%",  "%.1f" },
	{ "tolerance",    "CLEARANCE",  "mm", "%.2f" },
	{ "zOffset",      "Z OFFSET",   "mm", "%.2f" },
	{ "bedLeveled",   "BED LEVEL",  "",   "%s" },
}

function Calibration.key(printerId, material, manufacturer)
	return (printerId or "p1") .. "|" .. (material or "OTHER") .. "|" .. U.upper(manufacturer or "ANY")
end

function Calibration.splitKey(key)
	local p, m, f = string.match(key or "", "^([^|]*)|([^|]*)|([^|]*)$")
	return p, m, f
end

function Calibration.new(key, fields)
	local p = U.copy(fields or {})
	p.key = key
	return Calibration.normalize(p)
end

function Calibration.normalize(p)
	local printerId, material, manufacturer = Calibration.splitKey(p.key)
	p.printerId = printerId or "p1"
	p.material = U.oneOf(material, Enums.MATERIALS, "OTHER")
	p.manufacturer = manufacturer or "ANY"
	p.key = Calibration.key(p.printerId, p.material, p.manufacturer)
	p.nozzleTemp = U.int(p.nozzleTemp, 0)
	p.bedTemp = U.int(p.bedTemp, 0)
	p.flowRatio = U.num(p.flowRatio, 0)
	p.retractLength = U.num(p.retractLength, 0)
	p.retractSpeed = U.int(p.retractSpeed, 0)
	p.xyScale = U.num(p.xyScale, 0)
	p.zScale = U.num(p.zScale, 0)
	p.tolerance = U.num(p.tolerance, 0)
	p.zOffset = U.num(p.zOffset, 0)
	if p.bedLeveled ~= true then p.bedLeveled = false end
	p.updatedAt = U.int(p.updatedAt, 0)
	p.runs = math.max(0, U.int(p.runs, 0))
	p.recommended = p.recommended ~= false
	p.notes = U.str(p.notes, "")
	return p
end

-- Value for display: "--" when a field hasn't been calibrated yet.
function Calibration.fmtField(p, fieldDef)
	local name, _, unit, fmt = fieldDef[1], fieldDef[2], fieldDef[3], fieldDef[4]
	local v = p[name]
	if name == "bedLeveled" then
		return v and "OK" or "--"
	end
	if v == nil or v == 0 then return "--" end
	local s = string.format(fmt, v)
	if unit == "C" then return s .. FontData.icon.deg .. "C" end
	return s .. unit
end

function Calibration.label(p)
	return p.material .. " / " .. p.manufacturer
end

-- Number of fields that have real values; used for "completeness" bars.
function Calibration.completeness(p)
	local n = 0
	for _, f in ipairs(Calibration.FIELDS) do
		local v = p[f[1]]
		if v == true or (type(v) == "number" and v ~= 0) then n = n + 1 end
	end
	return n, #Calibration.FIELDS
end
