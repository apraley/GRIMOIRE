-- Filament spool model (a card in the FILAMENT ROLODEX).

Spool = {}

Spool.DEFAULTS = {
	manufacturer = "GENERIC",
	material = "PLA",
	color = "BLACK",
	nominalGrams = 1000,
	remainingGrams = 1000,
	usedGrams = 0,
	cost = 20,
	purchasedAt = 0,
	openedAt = 0,
	notes = "",
	dryness = "SEALED",
	driedAt = 0,
	location = "SHELF",
	favNozzle = 0,     -- 0 = not set yet
	favBed = 0,
	successCount = 0,
	failCount = 0,
	favorite = false,
	archived = false,
}

function Spool.new(fields)
	local s = U.copy(fields or {})
	U.defaults(s, Spool.DEFAULTS)
	return Spool.normalize(s)
end

function Spool.normalize(s)
	U.defaults(s, Spool.DEFAULTS)
	s.id = U.str(s.id, nil)
	s.manufacturer = U.upper(U.str(s.manufacturer, "GENERIC"))
	s.material = U.oneOf(s.material, Enums.MATERIALS, "OTHER")
	s.color = U.str(s.color, "BLACK")
	s.nominalGrams = U.clamp(U.num(s.nominalGrams, 1000), 1, 10000)
	s.remainingGrams = U.clamp(U.num(s.remainingGrams, s.nominalGrams), 0, s.nominalGrams)
	s.usedGrams = math.max(0, U.num(s.usedGrams, 0))
	s.cost = math.max(0, U.num(s.cost, 0))
	s.purchasedAt = U.int(s.purchasedAt, 0)
	s.openedAt = U.int(s.openedAt, 0)
	s.driedAt = U.int(s.driedAt, 0)
	s.dryness = U.oneOf(s.dryness, Enums.DRYNESS, "OK")
	s.location = U.str(s.location, "SHELF")
	s.favNozzle = U.int(s.favNozzle, 0)
	s.favBed = U.int(s.favBed, 0)
	s.successCount = math.max(0, U.int(s.successCount, 0))
	s.failCount = math.max(0, U.int(s.failCount, 0))
	s.favorite = s.favorite == true
	s.archived = s.archived == true
	s.notes = U.str(s.notes, "")
	return s
end

function Spool.pct(s)
	if s.nominalGrams <= 0 then return 0 end
	return U.clamp(s.remainingGrams / s.nominalGrams, 0, 1)
end

function Spool.costPerGram(s)
	if s.nominalGrams <= 0 then return 0 end
	return s.cost / s.nominalGrams
end

function Spool.valueRemaining(s)
	return Spool.costPerGram(s) * s.remainingGrams
end

function Spool.isLow(s, threshold)
	return not s.archived and s.remainingGrams <= (threshold or 150)
end

function Spool.isEmpty(s)
	return s.remainingGrams <= 0.5
end

function Spool.metersRemaining(s)
	return s.remainingGrams / Enums.gramsPerMeter(s.material)
end

-- Short label that fits in list rows.
function Spool.shortLabel(s)
	return U.truncate(s.manufacturer, 9) .. " " .. s.material .. " " .. U.truncate(s.color, 7)
end

function Spool.successRate(s)
	local total = s.successCount + s.failCount
	if total == 0 then return nil end
	return s.successCount / total
end

-- Hygroscopic materials left open for a long time drift toward DAMP.
-- Returns the dryness the spool *should* show given time since drying/opening.
function Spool.agedDryness(s, now)
	if s.dryness == "SEALED" then return "SEALED" end
	local ref = math.max(s.driedAt or 0, s.openedAt or 0)
	if ref == 0 then return s.dryness end
	local days = (now - ref) // U.DAY
	local hygro = Enums.materialInfo(s.material).hygro
	local limit = ({ 60, 30, 10 })[hygro] or 30
	local order = { DRY = 1, OK = 2, DAMP = 3, WET = 4 }
	local current = order[s.dryness] or 2
	local aged = current
	if days > limit * 2 then aged = math.max(current, 4)
	elseif days > limit then aged = math.max(current, 3)
	elseif days > limit // 2 then aged = math.max(current, 2) end
	return ({ "DRY", "OK", "DAMP", "WET" })[aged]
end
