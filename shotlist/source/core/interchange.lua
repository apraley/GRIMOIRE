-- Import/export boundary for companion desktop/web tools.
--
-- The device never talks to the network. Exchange happens through files in
-- the game's Data folder (reachable over USB Data Disk mode or in the
-- Simulator):
--
--   export/<SLUG>-<STAMP>.json         shotlist.project v1 (nested, lossless)
--   export/<SLUG>-<STAMP>-shots.csv    one row per shot (flat, FLAT_COLUMNS)
--   export/<SLUG>-<STAMP>-takes.csv    one row per take
--   export/<SLUG>-<STAMP>-report.txt   wrap report (when generated)
--   import/*.json                      read by DATA > IMPORT
--
-- Import accepts two documents (see docs/SCHEMA.md):
--   { "format": "shotlist.project", "version": 1, "project": {...nested...} }
--   { "format": "shotlist.shots",   "version": 1, "project": {...header...}, "shots": [ flat rows ] }
-- The flat form is the target for CSV / StudioBinder / ShotDeck converters:
-- rows are grouped into day > scene > setup by their `day`, `scene` and
-- `setup` columns, in first-seen order.

Interchange = {}

Interchange.FORMAT_PROJECT = "shotlist.project"
Interchange.FORMAT_SHOTS = "shotlist.shots"
Interchange.VERSION = 1

Interchange.FLAT_COLUMNS = {
	"day", "date", "scene", "sceneDesc", "location", "cast", "setup", "camera", "setupLens", "fps", "res", "wb", "iso",
	"shutter", "nd", "support", "lighting", "audio", "shot", "code", "desc", "size", "move", "lens", "subject",
	"priority", "est", "status", "notes", "takes", "best", "circled",
}

Interchange.TAKE_COLUMNS = { "code", "take", "time", "rating", "circle", "tech", "perf", "note" }

local STRIP = { k = true }

local function exportRec(rec)
	local r = {}
	for key, v in pairs(rec) do
		if not STRIP[key] then
			if type(v) == "table" then r[key] = Util.deepcopy(v) else r[key] = v end
		end
	end
	return r
end

local function exportTree(rec)
	local r = exportRec(rec)
	for _, c in ipairs(Schema.CHILDREN[rec.k] or {}) do
		local list = {}
		for _, child in ipairs(rec[c] or {}) do
			local cr = exportTree(child)
			if child.k == "shot" then cr.code = Model.code(child) end
			list[#list + 1] = cr
		end
		r[c] = list
	end
	return r
end

function Interchange.exportDoc(project, now)
	return {
		format = Interchange.FORMAT_PROJECT,
		version = Interchange.VERSION,
		schema = Schema.VERSION,
		exportedAt = now and (Util.fmtDate(now) .. "T" .. Util.fmtClock(now)) or "",
		exportedAtEpoch2000 = now,
		project = exportTree(project),
		gear = { packages = exportTree(Model.db.gear).packages, lists = Util.deepcopy(Model.db.gear.lists) },
	}
end

function Interchange.flatRows(project)
	local rows = {}
	for _, e in ipairs(Model.flat(project)) do
		local s, su, sc, d = e.shot, e.setup, e.scene, e.day
		local best = Model.bestTake(s)
		local circled = {}
		for _, t in ipairs(s.takes) do if t.circle then circled[#circled + 1] = tostring(t.n) end end
		rows[#rows + 1] = {
			day = d.label, date = d.date, scene = sc.number, sceneDesc = sc.desc, location = sc.location, cast = sc.cast,
			setup = su.letter, camera = su.camera, setupLens = su.lens, fps = su.fps, res = su.res, wb = su.wb, iso = su.iso,
			shutter = su.shutter, nd = su.nd, support = su.support, lighting = su.lighting, audio = su.audio,
			shot = s.num, code = Model.code(s), desc = s.desc, size = s.size, move = s.move, lens = Model.lensOf(s),
			subject = s.subject, priority = Vocab.PRIORITY_LABEL[s.priority] or "", est = s.est, status = s.status,
			notes = s.notes, takes = #s.takes, best = best and best.n or "", circled = table.concat(circled, " "),
		}
	end
	return rows
end

local function csvCell(v)
	if v == nil then return "" end
	local s = tostring(v)
	if s:find('[,"\r\n]') then s = '"' .. s:gsub('"', '""') .. '"' end
	return s
end

function Interchange.toCSV(columns, rows)
	local out = { table.concat(columns, ",") }
	for _, r in ipairs(rows) do
		local cells = {}
		for i, c in ipairs(columns) do cells[i] = csvCell(r[c]) end
		out[#out + 1] = table.concat(cells, ",")
	end
	return table.concat(out, "\r\n") .. "\r\n"
end

function Interchange.takeRows(project)
	local rows = {}
	for _, e in ipairs(Model.flat(project)) do
		for _, t in ipairs(e.shot.takes) do
			rows[#rows + 1] = { code = Model.code(e.shot), take = t.n, time = t.t and Util.fmtClock(t.t) or "",
				rating = t.rating, circle = t.circle and "Y" or "", tech = t.tech, perf = t.perf, note = t.note }
		end
	end
	return rows
end

-- Writes the export set; returns list of written paths.
function Interchange.exportFiles(project, now, reportLines)
	local base = "export/" .. Util.slug(project.title) .. "-" .. Util.fmtStamp(now)
	local written = {}
	local function put(path, text)
		if Store.writeText(path, text) then written[#written + 1] = path end
	end
	put(base .. ".json", json.encodePretty(Interchange.exportDoc(project, now)))
	put(base .. "-shots.csv", Interchange.toCSV(Interchange.FLAT_COLUMNS, Interchange.flatRows(project)))
	put(base .. "-takes.csv", Interchange.toCSV(Interchange.TAKE_COLUMNS, Interchange.takeRows(project)))
	if reportLines then put(base .. "-report.txt", table.concat(reportLines, "\n") .. "\n") end
	return written
end

---------------------------------------------------------------------------
-- Import
---------------------------------------------------------------------------

local function str(v, default)
	if v == nil then return default or "" end
	if type(v) == "table" then return default or "" end
	return tostring(v)
end

local function prio(v)
	local u = Util.upper(str(v))
	if u == "A" or u == "1" or u == "HIGH" or u == "MUST" then return 1 end
	if u == "C" or u == "3" or u == "LOW" or u == "NICE" then return 3 end
	return 2
end

local function vocabOr(list, v, field, warn)
	local s = str(v)
	if s == "" then return nil end
	local n = Vocab.normalize(list, s)
	if n then return n end
	warn[#warn + 1] = field .. " '" .. s .. "' kept as custom value"
	return Util.upper(s)
end

local PROJECT_FIELDS = { "title", "client", "director", "dp", "producer", "notes", "template" }

local function importHeader(src, warn)
	local p = Schema.new("project", {})
	for _, f in ipairs(PROJECT_FIELDS) do
		if src[f] ~= nil then p[f] = str(src[f]) end
	end
	if type(src.cast) == "table" then p.cast = Util.deepcopy(src.cast) end
	if type(src.locations) == "table" then p.locations = Util.deepcopy(src.locations) end
	if p.title == "" then p.title = "IMPORTED" end
	return p
end

local function importShotFields(src, warn)
	local status = Vocab.normalize(Vocab.STATUS, str(src.status)) or "NOT SHOT"
	return Schema.new("shot", {
		num = str(src.num or src.shot, "01"), desc = str(src.desc), subject = str(src.subject),
		size = vocabOr(Vocab.SIZE, src.size, "size", warn) or "MS",
		move = vocabOr(Vocab.MOVE, src.move or src.movement, "move", warn) or "LOCKED",
		lens = str(src.lens):gsub("[mM][mM]$", ""), priority = prio(src.priority),
		est = Util.int(src.est, 10), status = status, notes = str(src.notes),
	})
end

-- Nested document (our own export, or a converter that builds the tree).
local function importNested(doc, warn)
	local src = doc.project
	local p = importHeader(src, warn)
	for _, sd in ipairs(src.days or {}) do
		local d = Schema.new("day", { label = str(sd.label, "DAY " .. (#p.days + 1)), date = str(sd.date),
			location = str(sd.location), call = str(sd.call, "07:00"), crewNotes = str(sd.crewNotes), weather = str(sd.weather) })
		for _, ss in ipairs(sd.scenes or {}) do
			local sc = Schema.new("scene", { number = str(ss.number, "1"), desc = str(ss.desc), location = str(ss.location),
				cast = str(ss.cast) })
			for _, sn in ipairs(ss.notes or {}) do
				sc.notes[#sc.notes + 1] = Schema.new("note", { tag = vocabOr(Vocab.CONT_TAG, sn.tag, "tag", warn) or "PROP",
					text = str(sn.text), flag = sn.flag == true, resolved = sn.resolved == true, t = sn.t })
			end
			for _, su in ipairs(ss.setups or {}) do
				local setup = Schema.new("setup", {})
				for key, _ in pairs(Schema.DEFAULTS.setup) do
					if su[key] ~= nil then setup[key] = str(su[key]) end
				end
				for _, sh in ipairs(su.shots or {}) do
					local shot = importShotFields(sh, warn)
					shot.startedAt, shot.doneAt = sh.startedAt, sh.doneAt
					for _, tk in ipairs(sh.takes or {}) do
						local r = Vocab.normalize(Vocab.RATING, str(tk.rating)) or ""
						shot.takes[#shot.takes + 1] = Schema.new("take", { n = Util.int(tk.n, #shot.takes + 1), t = tk.t,
							rating = r, circle = tk.circle == true, tech = str(tk.tech), perf = str(tk.perf), note = str(tk.note) })
					end
					setup.shots[#setup.shots + 1] = shot
				end
				sc.setups[#sc.setups + 1] = setup
			end
			d.scenes[#d.scenes + 1] = sc
		end
		p.days[#p.days + 1] = d
	end
	return p
end

-- Flat rows grouped by day > scene > setup, first-seen order.
local function importFlat(doc, warn)
	local p = importHeader(doc.project or {}, warn)
	local days, scenes, setups = {}, {}, {}
	for i, row in ipairs(doc.shots or {}) do
		local dayKey = Util.upper(str(row.day, "DAY 1"))
		local d = days[dayKey]
		if d == nil then
			d = Schema.new("day", { label = dayKey, date = str(row.date), location = str(row.location) })
			days[dayKey] = d
			p.days[#p.days + 1] = d
		end
		local sceneNum = Util.upper(str(row.scene, "1"))
		local sceneKey = dayKey .. "|" .. sceneNum
		local sc = scenes[sceneKey]
		if sc == nil then
			sc = Schema.new("scene", { number = sceneNum, desc = str(row.sceneDesc), location = str(row.location),
				cast = str(row.cast) })
			scenes[sceneKey] = sc
			d.scenes[#d.scenes + 1] = sc
		end
		local letter = Util.upper(str(row.setup, "A"))
		local setupKey = sceneKey .. "|" .. letter
		local su = setups[setupKey]
		if su == nil then
			su = Schema.new("setup", { letter = letter })
			for _, f in ipairs({ "camera", "fps", "res", "wb", "iso", "shutter", "nd", "support", "lighting", "audio" }) do
				if row[f] ~= nil and str(row[f]) ~= "" then su[f] = str(row[f]) end
			end
			if row.setupLens then su.lens = str(row.setupLens):gsub("[mM][mM]$", "") end
			setups[setupKey] = su
			sc.setups[#sc.setups + 1] = su
		end
		local shot = importShotFields(row, warn)
		if str(row.shot) == "" then shot.num = Util.pad2(#su.shots + 1) end
		su.shots[#su.shots + 1] = shot
		if i > 2000 then warn[#warn + 1] = "stopped at 2000 rows"; break end
	end
	return p
end

-- Returns project tree (no ids) and warnings, or nil, error.
function Interchange.importDoc(doc)
	if type(doc) ~= "table" then return nil, "not a JSON object" end
	local warn = {}
	if doc.format == Interchange.FORMAT_PROJECT and type(doc.project) == "table" then
		if (doc.version or 1) > Interchange.VERSION then return nil, "newer interchange version" end
		return importNested(doc, warn), warn
	elseif doc.format == Interchange.FORMAT_SHOTS and type(doc.shots) == "table" then
		if (doc.version or 1) > Interchange.VERSION then return nil, "newer interchange version" end
		return importFlat(doc, warn), warn
	end
	return nil, "unknown format (expected shotlist.project or shotlist.shots)"
end

function Interchange.listImports()
	local r = {}
	if not playdate.file.exists("import") then return r end
	for _, name in ipairs(playdate.file.listFiles("import") or {}) do
		if name:lower():match("%.json$") then r[#r + 1] = "import/" .. name end
	end
	table.sort(r)
	return r
end

function Interchange.readImport(path)
	local ok, doc = pcall(json.decodeFile, path)
	if not ok or type(doc) ~= "table" then return nil, "could not parse JSON" end
	return Interchange.importDoc(doc)
end

return Interchange
