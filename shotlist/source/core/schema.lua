-- Record shapes, defaults and schema migration.
--
-- The whole database is one JSON-compatible Lua table (no functions, no
-- metatables, string keys for objects, dense arrays for lists). See
-- docs/SCHEMA.md for the full field reference and interchange rules.

Schema = {}

Schema.VERSION = 1
Schema.APP = "shotlist"

-- Child collections per record kind, in hierarchy order.
Schema.CHILDREN = {
	project = { "days", "reports" },
	day = { "scenes" },
	scene = { "setups", "notes" },
	setup = { "shots" },
	shot = { "takes" },
	gear = { "packages" },
}

-- Which kind lives in which collection.
Schema.COLLECTION_KIND = {
	projects = "project", days = "day", reports = "report", scenes = "scene", notes = "note",
	setups = "setup", shots = "shot", takes = "take", packages = "pkg",
}

-- Field defaults. Missing fields are filled on load (forward compatibility),
-- unknown fields are preserved untouched (so newer companion tools can round-trip).
Schema.DEFAULTS = {
	project = { title = "UNTITLED", client = "", director = "", dp = "", producer = "", notes = "",
		template = "", cast = {}, locations = {} },
	day = { label = "DAY 1", date = "", location = "", call = "07:00", crewNotes = "", weather = "" },
	scene = { number = "1", desc = "", location = "", cast = "", status = "NOT SHOT" },
	setup = { letter = "A", camera = "", lens = "", fps = "23.976", res = "UHD 4K", wb = "5600K", iso = "800",
		shutter = "180", nd = "", support = "STICKS", lighting = "", audio = "" },
	shot = { num = "01", desc = "", size = "MS", move = "LOCKED", lens = "", subject = "", priority = 2, est = 10,
		status = "NOT SHOT", notes = "" },
	take = { n = 1, rating = "", circle = false, tech = "", perf = "", note = "" },
	note = { tag = "PROP", text = "", flag = false, shot = "", take = 0, resolved = false },
	report = { day = "", title = "WRAP REPORT" },
	pkg = { name = "A CAM", camera = "", lenses = {}, filters = {}, support = "", audio = "", lighting = "" },
}

Schema.GEAR_DEFAULT_LISTS = {
	cameras = { "SONY FX6", "SONY FX3", "SONY VENICE 2", "ARRI ALEXA MINI LF", "ARRI ALEXA 35", "RED KOMODO",
		"RED V-RAPTOR", "CANON C70", "CANON C300 III", "BMPCC 6K" },
	lenses = { "24-70", "70-200", "16-35", "SIGMA CINE PRIMES", "ZEISS CP.3", "COOKE S4", "LAOWA 24 PROBE",
		"100 MACRO" },
	filters = { "VND", "ND.3", "ND.6", "ND.9", "ND1.2", "BPM 1/8", "BPM 1/4", "POLA" },
	support = { "STICKS", "HI-HAT", "SLIDER", "DOLLY", "RONIN 2", "EASYRIG", "JIB" },
	audio = { "BOOM MKH-50", "LAV x2", "SOUND DEVICES 833", "TIMECODE BOX" },
	lighting = { "ARRI SKYPANEL", "APUTURE 600D", "ASTERA TUBES", "4X4 FRAME", "NEG FILL", "BOUNCE" },
}

function Schema.newDb()
	return {
		schema = Schema.VERSION,
		app = Schema.APP,
		seq = 0,
		nextId = 1,
		savedAt = 0,
		settings = Schema.newSettings(),
		gear = Schema.newGear(),
		projects = {},
	}
end

function Schema.newSettings()
	return {
		id = "settings", k = "settings",
		project = "",      -- active project id
		cursor = "",       -- shot shown in LIVE
		holdMs = 450,      -- long-press threshold
		crank = 2,         -- 1 slow, 2 normal, 3 fast
		clock24 = true,
		autoNext = true,   -- GOT IT jumps to next priority shot
		nextMode = "BALANCED", -- or "RUSH": strict priority, ignore setup locality
		askPerf = false,   -- ask for performance issue after a BAD rating
		circleGotIt = false, -- circling a take also marks the shot GOT IT
		slateInvert = false,
		lastSnapshot = 0,
		snapSlot = 0,
	}
end

function Schema.newGear()
	return { id = "gear", k = "gear", packages = {}, lists = Util.deepcopy(Schema.GEAR_DEFAULT_LISTS) }
end

-- Build a new record of `kind`, applying defaults then `fields`. Ids are
-- assigned by Model when the record enters the database.
function Schema.new(kind, fields)
	local r = { k = kind }
	local d = Schema.DEFAULTS[kind] or {}
	for key, v in pairs(d) do r[key] = Util.deepcopy(v) end
	for key, v in pairs(fields or {}) do r[key] = v end
	for _, c in ipairs(Schema.CHILDREN[kind] or {}) do
		if r[c] == nil then r[c] = {} end
	end
	return r
end

-- Fill defaults recursively. Returns number of records visited.
function Schema.normalize(rec)
	local count = 1
	local kind = rec.k
	local d = Schema.DEFAULTS[kind]
	if d then
		for key, v in pairs(d) do
			if rec[key] == nil then rec[key] = Util.deepcopy(v) end
		end
	end
	for _, c in ipairs(Schema.CHILDREN[kind] or {}) do
		if type(rec[c]) ~= "table" then rec[c] = {} end
		for _, child in ipairs(rec[c]) do
			if child.k == nil then child.k = Schema.COLLECTION_KIND[c] end
			count = count + Schema.normalize(child)
		end
	end
	return count
end

---------------------------------------------------------------------------
-- Migrations. MIGRATIONS[v] upgrades a database from version v to v+1.
-- Never edit a shipped migration; append a new one and bump VERSION.
---------------------------------------------------------------------------

Schema.MIGRATIONS = {
	-- [0] pre-release databases had no schema field and no gear block.
	[0] = function(db)
		db.gear = db.gear or Schema.newGear()
		db.settings = db.settings or Schema.newSettings()
	end,
}

function Schema.migrate(db)
	if type(db) ~= "table" then return nil, "not a table" end
	if db.app ~= nil and db.app ~= Schema.APP then return nil, "not a shotlist database" end
	local v = db.schema or 0
	if v > Schema.VERSION then
		return nil, "database is from a newer version (" .. tostring(v) .. ")"
	end
	while v < Schema.VERSION do
		local m = Schema.MIGRATIONS[v]
		if m == nil then return nil, "no migration from v" .. v end
		m(db)
		v = v + 1
		db.schema = v
	end
	db.app = Schema.APP
	db.seq = db.seq or 0
	db.nextId = db.nextId or 1
	db.projects = db.projects or {}
	db.gear = db.gear or Schema.newGear()
	db.gear.id, db.gear.k = "gear", "gear"
	db.gear.packages = db.gear.packages or {}
	db.gear.lists = db.gear.lists or Util.deepcopy(Schema.GEAR_DEFAULT_LISTS)
	for _, name in ipairs(Vocab.GEAR_LISTS) do
		if db.gear.lists[name] == nil then db.gear.lists[name] = {} end
	end
	local s = db.settings or {}
	local def = Schema.newSettings()
	for key, val in pairs(def) do
		if s[key] == nil then s[key] = val end
	end
	db.settings = s
	for _, p in ipairs(db.projects) do
		p.k = "project"
		Schema.normalize(p)
	end
	for _, pkg in ipairs(db.gear.packages) do
		pkg.k = "pkg"
		Schema.normalize(pkg)
	end
	return db
end

return Schema
