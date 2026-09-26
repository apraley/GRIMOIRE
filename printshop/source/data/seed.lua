-- Demo shop contents. Seed.build(now) returns a complete current-schema
-- document so every screen has something interesting on first launch:
-- a print in progress, a queue with every status, a rolodex with low, damp
-- and sealed spools, two months of history with failures, due maintenance
-- and a couple of calibration profiles.
--
-- Everything is derived deterministically from `now` so tests are stable.

Seed = {}

local DAY = 86400

local function spoolRows()
	-- id, maker, material, color, nominal, remaining, cost, boughtDaysAgo, openedDaysAgo, dryness, location, nozzle, bed, fav, notes
	return {
		{ "s1",  "BAMBU",     "PLA",  "BLACK",  1000, 612, 19.99, 70, 42, "OK",     "AMS LITE 1", 220, 60, true,  "PLA Basic. The reliable workhorse." },
		{ "s2",  "BAMBU",     "PLA",  "WHITE",  1000, 845, 21.99, 70, 20, "DRY",    "AMS LITE 2", 220, 60, false, "Matte. Hides layer lines." },
		{ "s3",  "POLYMAKER", "PLA",  "OLIVE",  1000, 118, 24.99, 120, 95, "OK",    "AMS LITE 3", 215, 55, false, "PolyTerra. Nearly done." },
		{ "s10", "OVERTURE",  "PLA",  "GOLD",   1000, 508, 22.99, 60, 30, "OK",     "AMS LITE 4", 225, 60, true,  "Silk. Print slow for shine." },
		{ "s4",  "OVERTURE",  "PETG", "BLACK",  1000, 431, 18.99, 90, 60, "DAMP",   "DRYBOX",     242, 75, false, "Loves to grab the nozzle." },
		{ "s5",  "ESUN",      "PETG", "CLEAR",  1000, 1000, 17.49, 14, 0, "SEALED", "SHELF A",      0,  0, false, "" },
		{ "s6",  "SUNLU",     "TPU",  "RED",    500,  262, 21.00, 110, 80, "WET",   "DRYBOX",     225, 45, false, "95A. Direct drive only." },
		{ "s7",  "PRUSAMENT", "ASA",  "GRAY",   850,  610, 29.99, 50, 25, "DRY",    "SHELF B",    255, 95, false, "Outdoor parts. Vent the room." },
		{ "s8",  "HATCHBOX",  "ABS",  "WHITE",  1000, 34,  22.99, 300, 240, "DAMP", "SHELF B",    245, 95, false, "Old roll. Warps on the A1 Mini." },
		{ "s9",  "ELEGOO",    "PLA",  "ORANGE", 1000, 1000, 15.99, 10, 0, "SEALED", "SHELF A",      0,  0, false, "Benchy orange, obviously." },
	}
end

local function historyRows()
	-- daysAgo, jobName, project, spoolId, minutes, grams, outcome, cause, nozzle, bed, progress
	return {
		{ 74, "BENCHY #41",        "BENCHY FLEET",   "s1", 55,  15, "success", nil,         220, 60, 1 },
		{ 72, "HEADPHONE HOOK",    "DESK ORGANIZER", "s1", 95,  31, "success", nil,         220, 60, 1 },
		{ 70, "PLANTER POT",       "GARDEN",         "s4", 240, 96, "success", nil,         240, 75, 1 },
		{ 69, "PLANTER POT",       "GARDEN",         "s4", 240, 20, "failed",  "adhesion",  240, 70, 0.2 },
		{ 66, "CABLE CHAIN",       "TOOL WALL",      "s2", 130, 38, "success", nil,         220, 60, 1 },
		{ 64, "PHONE STAND",       "DESK ORGANIZER", "s1", 110, 36, "success", nil,         220, 60, 1 },
		{ 61, "TPU FEET x8",       "TOOL WALL",      "s6", 60,  9,  "failed",  "stringing", 230, 45, 0.6 },
		{ 60, "TPU FEET x8",       "TOOL WALL",      "s6", 60,  14, "success", nil,         225, 45, 1 },
		{ 58, "HOSE CLIP",         "GARDEN",         "s4", 45,  12, "success", nil,         242, 75, 1 },
		{ 55, "BENCHY #42",        "BENCHY FLEET",   "s3", 55,  15, "success", nil,         215, 55, 1 },
		{ 53, "SEED LABELS x20",   "GARDEN",         "s4", 70,  18, "success", nil,         245, 75, 1 },
		{ 52, "WALL ANCHOR",       "TOOL WALL",      "s7", 90,  24, "failed",  "layershift",255, 95, 0.45 },
		{ 50, "WALL ANCHOR",       "TOOL WALL",      "s7", 90,  26, "success", nil,         255, 95, 1 },
		{ 48, "DRAWER LABELS",     "DESK ORGANIZER", "s2", 40,  8,  "success", nil,         220, 60, 1 },
		{ 46, "GARDEN STAKE x6",   "GARDEN",         "s4", 150, 44, "failed",  "adhesion",  245, 70, 0.1 },
		{ 45, "GARDEN STAKE x6",   "GARDEN",         "s4", 150, 44, "success", nil,         242, 80, 1 },
		{ 43, "BENCHY #43",        "BENCHY FLEET",   "s10",55,  15, "success", nil,         225, 60, 1 },
		{ 41, "MONITOR RISER FOOT","DESK ORGANIZER", "s1", 200, 70, "failed",  "spaghetti", 220, 60, 0.35 },
		{ 40, "MONITOR RISER FOOT","DESK ORGANIZER", "s1", 200, 71, "success", nil,         220, 60, 1 },
		{ 37, "PLANT TAG",         "GARDEN",         "s3", 30,  5,  "failed",  "underext",  210, 55, 0.5 },
		{ 36, "PLANT TAG",         "GARDEN",         "s3", 30,  5,  "success", nil,         215, 55, 1 },
		{ 34, "DRIP TRAY",         "GARDEN",         "s4", 160, 58, "success", nil,         240, 75, 1 },
		{ 31, "BENCHY #44",        "BENCHY FLEET",   "s9", 55,  15, "success", nil,         215, 60, 1 },
		{ 29, "PEGBOARD HOOKS x6", "TOOL WALL",      "s7", 120, 40, "success", nil,         255, 95, 1 },
		{ 27, "PHONE CASE",        "",               "s6", 100, 21, "failed",  "stringing", 230, 45, 0.7 },
		{ 24, "SPOOL HOLDER",      "TOOL WALL",      "s2", 180, 62, "success", nil,         220, 60, 1 },
		{ 22, "BENCHY #45",        "BENCHY FLEET",   "s10",55,  15, "success", nil,         225, 60, 1 },
		{ 20, "BATTERY BOX",       "TOOL WALL",      "s4", 130, 46, "success", nil,         242, 75, 1 },
		{ 18, "GOLD PLAQUE",       "",               "s10",75,  22, "success", nil,         225, 60, 1 },
		{ 16, "SQUARE VASE",       "GARDEN",         "s4", 180, 60, "failed",  "stringing", 250, 75, 0.8 },
		{ 15, "SQUARE VASE",       "GARDEN",         "s4", 180, 62, "success", nil,         242, 75, 1 },
		{ 12, "BENCHY #46",        "BENCHY FLEET",   "s1", 55,  15, "success", nil,         220, 60, 1 },
		{ 10, "TOOTHBRUSH CUP",    "",               "s4", 120, 40, "success", nil,         245, 75, 1 },
		{ 8,  "DESK TIDY",         "DESK ORGANIZER", "s2", 210, 75, "success", nil,         220, 60, 1 },
		{ 6,  "ABS DUCT",          "TOOL WALL",      "s8", 90,  30, "failed",  "adhesion",  245, 95, 0.25 },
		{ 5,  "HOSE ADAPTER",      "GARDEN",         "s4", 80,  24, "success", nil,         240, 75, 1 },
		{ 3,  "BENCHY #47",        "BENCHY FLEET",   "s9", 55,  15, "success", nil,         215, 60, 1 },
		{ 2,  "KEY RACK",          "TOOL WALL",      "s1", 150, 48, "success", nil,         220, 60, 1 },
	}
end

local function jobRows()
	-- id, name, model, spoolId, status, minutes, grams, prio, project, shape, layers, createdDaysAgo, notes
	return {
		{ "j1",  "CABLE CLIPS x12",     "cable_clip_v3.3mf",   "s1",  "PRINTING", 95,  18, 2, "DESK ORGANIZER", "bracket", 120, 2,  "Stagger on plate for airflow." },
		{ "j2",  "PLAYDATE STAND",      "pd_stand_tilt.3mf",   "s2",  "QUEUED",   120, 40, 4, "DESK ORGANIZER", "bracket", 190, 4,  "15 deg tilt. Crank side open." },
		{ "j3",  "HEX PEN CUP",         "hex_cup.stl",         "s2",  "QUEUED",   180, 64, 2, "DESK ORGANIZER", "vase",    420, 6,  "Vase mode, 2 walls." },
		{ "j4",  "PLANTER DRIP TRAY",   "drip_tray_120.3mf",   "s4",  "QUEUED",   140, 55, 3, "GARDEN",         "box",     90,  5,  "PETG for water. Glue stick!" },
		{ "j5",  "SD CARD WALLET",      "sd_wallet.3mf",       "s10", "READY",    45,  12, 2, "",               "box",     60,  8,  "" },
		{ "j6",  "BENCHY #48",          "3DBenchy.3mf",        "s9",  "READY",    55,  15, 1, "BENCHY FLEET",   "benchy",  240, 3,  "The fleet grows." },
		{ "j7",  "TPU BUMPERS x4",      "bumper_round.stl",    "s6",  "FAILED",   70,  22, 2, "TOOL WALL",      "cube",    80,  9,  "Strung like a harp. Dry first." },
		{ "j8",  "CALIBRATION CUBE",    "xyz_20mm.stl",        "s3",  "READY",    20,  8,  3, "",               "cube",    100, 1,  "Check XY after belt tension." },
		{ "j9",  "GRIDFINITY 2x3 BINS", "gridfinity_2x3.3mf",  nil,   "IDEA",     200, 110,2, "TOOL WALL",      "box",     140, 12, "Need more white first." },
		{ "j10", "ARTICULATED DRAGON",  "dragon_flexi.3mf",    "s10", "IDEA",     360, 90, 1, "",               "figure",  300, 20, "Gift. Silk gold." },
		{ "j11", "ASA HOSE NOZZLE",     "hose_nozzle.3mf",     "s7",  "QUEUED",   95,  28, 2, "GARDEN",         "tower",   150, 7,  "Outdoor. Enclosure door closed." },
		{ "j12", "KEY RACK",            "key_rack.3mf",        "s1",  "COMPLETE", 150, 48, 2, "TOOL WALL",      "bracket", 110, 9,  "" },
		{ "j13", "BENCHY #47",          "3DBenchy.3mf",        "s9",  "COMPLETE", 55,  15, 1, "BENCHY FLEET",   "benchy",  240, 5,  "" },
		{ "j14", "HOSE ADAPTER",        "hose_adapter.3mf",    "s4",  "COMPLETE", 80,  24, 2, "GARDEN",         "tower",   160, 8,  "", true },
	}
end

local function maintRows()
	-- id, kind, name, hours, days, lastDaysAgo, lastHoursAgo, notes
	return {
		{ "m1", "bed_clean",      "BED CLEANING",       20,  14,  12, 18,  "Dish soap + hot water. No IPA on textured PEI." },
		{ "m2", "lube",           "LUBRICATION",        100, 90,  80, 70,  "Z lead screw + linear rails. Thin grease." },
		{ "m3", "belts",          "BELT INSPECTION",    150, 60,  35, 60,  "Check tension on X and Y." },
		{ "m4", "nozzle",         "NOZZLE CHANGE",      300, 0,   110, 180, "Hardened 0.4 for abrasives." },
		{ "m5", "extruder_clean", "EXTRUDER CLEANING",  200, 120, 60, 90,  "Clear dust from the gears." },
		{ "m6", "firmware",       "FIRMWARE CHECK",     0,   30,  33, 0,   "Running 01.04. Read release notes first." },
		{ "m7", "parts",          "PTFE TUBE",          500, 0,   150, 220, "Replace if feeding feels rough." },
		{ "m8", "custom",         "WIPE AMS ROLLERS",   0,   60,  20, 0,   "Dust builds on the feed rollers." },
	}
end

function Seed.build(now)
	local d = {
		schema = Schema.CURRENT,
		meta = { createdAt = now, nextId = 100, saves = 0 },
		settings = U.deepcopy(Schema.SETTINGS_DEFAULTS),
		printers = {
			Printer.new({ id = "p1", name = "A1 MINI", model = "BAMBU LAB A1 MINI", provider = "demo",
				bedX = 180, bedY = 180, bedZ = 180, serial = "0309XXXXXXXXXXX", firmware = "01.04.00.00" }),
			Printer.new({ id = "p2", name = "ENDER 3", model = "CREALITY ENDER-3 V2", provider = "bridge",
				bedX = 220, bedY = 220, bedZ = 250, host = "", firmware = "MARLIN 2.1" }),
		},
		spools = {},
		jobs = {},
		history = {},
		consumption = {},
		calibrations = {},
		calibRuns = {},
		maintenance = { tasks = {}, log = {} },
		captain = { counter = 0, seenIntro = false, lastTopics = {}, inbox = {}, lastDay = 0 },
		printLog = {},
		providerState = {},
	}

	for _, r in ipairs(spoolRows()) do
		d.spools[#d.spools + 1] = Spool.new({
			id = r[1], manufacturer = r[2], material = r[3], color = r[4], nominalGrams = r[5],
			remainingGrams = r[6], cost = r[7], purchasedAt = now - r[8] * DAY,
			openedAt = r[9] > 0 and (now - r[9] * DAY) or 0, dryness = r[10], location = r[11],
			favNozzle = r[12], favBed = r[13], favorite = r[14], notes = r[15],
		})
	end
	local spoolById = {}
	for _, s in ipairs(d.spools) do spoolById[s.id] = s end

	-- History + consumption, and roll-ups onto spools and the printer.
	local p1 = d.printers[1]
	local hSeconds = 0
	local n = 0
	for _, r in ipairs(historyRows()) do
		n = n + 1
		local sp = spoolById[r[4]]
		local ended = now - r[1] * DAY + 3600 * ((n * 5) % 11)
		local dur = math.floor(r[5] * 60 * r[11])
		local h = History.new({
			id = "h" .. n, jobId = "", jobName = r[2], project = r[3], printerId = "p1",
			spoolId = sp.id, material = sp.material, manufacturer = sp.manufacturer, color = sp.color,
			outcome = r[7], cause = r[8] or "", startedAt = ended - dur, endedAt = ended,
			durationSec = dur, grams = r[6], progress = r[11],
			layer = math.floor(150 * r[11]), nozzleTemp = r[9], bedTemp = r[10],
		})
		d.history[#d.history + 1] = h
		d.consumption[#d.consumption + 1] = Consumption.normalize({
			id = "c" .. n, spoolId = sp.id, at = ended, grams = r[6],
			kind = r[7] == "success" and "print" or "failed", jobId = "", note = r[2],
		})
		sp.usedGrams = sp.usedGrams + r[6]
		if r[7] == "success" then
			sp.successCount = sp.successCount + 1
			p1.stats.successes = p1.stats.successes + 1
			p1.stats.streak = math.max(1, p1.stats.streak + 1)
		else
			sp.failCount = sp.failCount + 1
			p1.stats.failures = p1.stats.failures + 1
			p1.stats.streak = math.min(-1, p1.stats.streak - 1)
		end
		p1.stats.prints = p1.stats.prints + 1
		p1.stats.grams = p1.stats.grams + r[6]
		p1.stats.lastPrintAt = math.max(p1.stats.lastPrintAt, ended)
		hSeconds = hSeconds + dur
	end
	-- The A1 Mini had a life before PRINT SHOP: 150 hours on the odometer.
	p1.stats.printSeconds = hSeconds + 150 * 3600

	-- Link completed queue jobs to their history rows by name.
	for _, r in ipairs(jobRows()) do
		local sp = r[4] and spoolById[r[4]] or nil
		local j = Job.new({
			id = r[1], name = r[2], model = r[3], spoolId = r[4], printerId = "p1",
			material = sp and sp.material or "PLA", color = sp and sp.color or "WHITE",
			status = r[5], estMinutes = r[6], estGrams = r[7], priority = r[8], project = r[9],
			shape = r[10], layers = r[11], createdAt = now - r[12] * DAY, notes = r[13],
			archived = r[14] == true,
		})
		if j.status == "COMPLETE" or j.status == "FAILED" then
			for i = #d.history, 1, -1 do
				local h = d.history[i]
				if h.jobName == j.name then
					h.jobId = j.id
					if j.completedAt == 0 then j.completedAt = h.endedAt end
					j.attempts = j.attempts + 1
				end
			end
		end
		if j.status == "FAILED" then
			j.attempts = math.max(1, j.attempts)
			j.completedAt = 0
		end
		d.jobs[#d.jobs + 1] = j
	end

	-- The TPU bumpers failure (most recent TPU attempt) belongs to j7.
	local bumper = History.new({
		id = "h" .. (n + 1), jobId = "j7", jobName = "TPU BUMPERS x4", project = "TOOL WALL",
		printerId = "p1", spoolId = "s6", material = "TPU", manufacturer = "SUNLU", color = "RED",
		outcome = "failed", cause = "stringing", startedAt = now - DAY - 3000, endedAt = now - DAY,
		durationSec = 3000, grams = 11, progress = 0.55, layer = 44, nozzleTemp = 232, bedTemp = 45,
		notes = "Wisps everywhere. Spool was WET.",
	})
	d.history[#d.history + 1] = bumper
	d.consumption[#d.consumption + 1] = Consumption.normalize({ id = "c" .. (n + 1), spoolId = "s6",
		at = bumper.endedAt, grams = 11, kind = "failed", jobId = "j7", note = "TPU BUMPERS x4" })
	spoolById.s6.failCount = spoolById.s6.failCount + 1
	spoolById.s6.usedGrams = spoolById.s6.usedGrams + 11
	p1.stats.failures = p1.stats.failures + 1
	p1.stats.prints = p1.stats.prints + 1
	p1.stats.grams = p1.stats.grams + 11
	p1.stats.printSeconds = p1.stats.printSeconds + 3000
	p1.stats.streak = -1
	p1.stats.lastPrintAt = now - DAY
	-- Manual adjustment example: a purge line spool weigh-in.
	d.consumption[#d.consumption + 1] = Consumption.normalize({ id = "c" .. (n + 2), spoolId = "s1",
		at = now - 4 * DAY, grams = 6, kind = "purge", note = "AMS purge waste" })

	-- Maintenance, relative to the printer's hour odometer.
	local hoursNow = p1.stats.printSeconds / 3600
	for _, r in ipairs(maintRows()) do
		local t = Maint.new({
			id = r[1], kind = r[2], name = r[3], printerId = "p1",
			intervalHours = r[4], intervalDays = r[5],
			lastAt = now - r[6] * DAY, lastHours = math.max(0, hoursNow - r[7]), notes = r[8],
		})
		d.maintenance.tasks[#d.maintenance.tasks + 1] = t
		d.maintenance.log[#d.maintenance.log + 1] = MaintLog.normalize({
			id = "l" .. r[1], taskId = t.id, at = t.lastAt, hoursAt = t.lastHours,
			note = "Logged at setup.", kind = t.kind, name = t.name,
		})
	end
	d.maintenance.log[#d.maintenance.log + 1] = MaintLog.normalize({
		id = "l90", taskId = "m1", at = now - 30 * DAY, hoursAt = math.max(0, hoursNow - 45),
		note = "Fingerprints. Always fingerprints.", kind = "bed_clean", name = "BED CLEANING",
	})

	-- Calibration profiles.
	local function prof(key, fields)
		local p = Calibration.new(key, fields)
		d.calibrations[p.key] = p
	end
	prof("p1|PLA|BAMBU", { nozzleTemp = 220, bedTemp = 60, flowRatio = 0.98, retractLength = 0.8,
		retractSpeed = 30, xyScale = 100.2, zScale = 100, tolerance = 0.15, bedLeveled = true,
		updatedAt = now - 40 * DAY, runs = 4, notes = "Tuned on Basic Black." })
	prof("p1|PETG|OVERTURE", { nozzleTemp = 242, bedTemp = 75, flowRatio = 0.95, retractLength = 1.0,
		retractSpeed = 25, updatedAt = now - 50 * DAY, runs = 2 })
	prof("p1|PLA|ANY", { nozzleTemp = 215, bedTemp = 60, updatedAt = now - 90 * DAY, runs = 1 })
	d.calibRuns = {
		{ id = "r1", procedure = "temptower", key = "p1|PLA|BAMBU", at = now - 60 * DAY, results = { nozzleTemp = 220 }, notes = "Best bridging at 220." },
		{ id = "r2", procedure = "flow", key = "p1|PLA|BAMBU", at = now - 55 * DAY, results = { flowRatio = 0.98 }, notes = "" },
		{ id = "r3", procedure = "retraction", key = "p1|PLA|BAMBU", at = now - 45 * DAY, results = { retractLength = 0.8, retractSpeed = 30 }, notes = "" },
		{ id = "r4", procedure = "dimension", key = "p1|PLA|BAMBU", at = now - 40 * DAY, results = { xyScale = 100.2, zScale = 100 }, notes = "20mm cube read 19.96" },
		{ id = "r5", procedure = "temptower", key = "p1|PETG|OVERTURE", at = now - 52 * DAY, results = { nozzleTemp = 242 }, notes = "" },
		{ id = "r6", procedure = "flow", key = "p1|PETG|OVERTURE", at = now - 50 * DAY, results = { flowRatio = 0.95 }, notes = "" },
	}

	-- Printer event log shown on PRINT WATCH.
	d.printLog = {
		{ at = now - DAY, text = "TPU BUMPERS x4 FAILED: STRINGING" },
		{ at = now - 2 * DAY, text = "KEY RACK COMPLETE" },
		{ at = now - 2400, text = "CABLE CLIPS x12 STARTED" },
		{ at = now - 2280, text = "HEATBED 60C REACHED" },
		{ at = now - 2160, text = "FIRST LAYER OK" },
	}

	-- The demo printer is mid-way through j1 on first launch.
	d.providerState.demo = {
		state = "PRINTING", jobId = "j1", jobName = "CABLE CLIPS x12", spoolId = "s1",
		material = "PLA", color = "BLACK", totalLayers = 120, totalSec = 95 * 60,
		elapsedSec = 38 * 60, heatSec = 0, nozzle = 220, nozzleTarget = 220, bed = 60, bedTarget = 60,
		grams = 18, seed = 4242, savedAt = now, startedAt = now - 40 * 60,
	}
	local j1 = d.jobs[1]
	j1.startedAt = now - 40 * 60
	j1.nozzleTemp = 220
	j1.bedTemp = 60
	j1.profileKey = "p1|PLA|BAMBU"
	j1.attempts = 1

	return d
end

-- An empty shop: one printer, default maintenance plan, nothing else. Used
-- by Settings > RESET (EMPTY) and by tests of empty states.
function Seed.empty(now)
	local d = {
		schema = Schema.CURRENT,
		meta = { createdAt = now, nextId = 1, saves = 0 },
		settings = U.deepcopy(Schema.SETTINGS_DEFAULTS),
		printers = { Printer.new({ id = "p1", name = "A1 MINI", model = "BAMBU LAB A1 MINI", provider = "demo" }) },
		spools = {}, jobs = {}, history = {}, consumption = {}, calibrations = {}, calibRuns = {},
		maintenance = { tasks = {}, log = {} },
		captain = { counter = 0, seenIntro = false, lastTopics = {}, inbox = {}, lastDay = 0 },
		printLog = {}, providerState = {},
	}
	for i, r in ipairs(maintRows()) do
		d.maintenance.tasks[i] = Maint.new({ id = "m" .. i, kind = r[2], name = r[3], printerId = "p1",
			intervalHours = r[4], intervalDays = r[5], lastAt = 0, lastHours = 0, notes = r[8] })
	end
	d.meta.nextId = #d.maintenance.tasks + 1
	return d
end
