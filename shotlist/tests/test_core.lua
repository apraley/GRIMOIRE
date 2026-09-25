-- Core model / persistence tests (no UI).
local H = dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]+$") or ".") .. "/harness.lua")
H.freshData("core")
Sim.epoch = H.START_EPOCH
H.loadCore()

local function newDbWithDemo()
	local db = Schema.newDb()
	Model.attach(db)
	local p = Templates.demoCommercial()
	Model.assignIds(p)
	db.projects[1] = p
	for _, pkg in ipairs(Templates.demoPackages()) do
		Model.assignIds(pkg)
		db.gear.packages[#db.gear.packages + 1] = pkg
	end
	db.settings.project = p.id
	Store.reset(db)
	return db, p
end

-- fresh install
H.eq(Store.load(), false, "fresh data folder has no database")

local db, p = newDbWithDemo()
local flat = Model.flat(p)
H.eq(#flat, 60, "demo has 60 shots")
H.eq(Model.code(flat[1].shot), "01A-01", "first code")
H.eq(Model.code(flat[60].shot), "08B-02", "last code")

-- every template builds and normalises
for _, name in ipairs(Vocab.TEMPLATE) do
	local t = Templates.build(name)
	H.check(t ~= nil and #t.days >= 1, "template " .. name .. " builds")
	local shots = 0
	for _, d in ipairs(t.days) do for _, sc in ipairs(d.scenes) do for _, su in ipairs(sc.setups) do
		shots = shots + #su.shots
		H.check(su.fps ~= "" and su.res ~= "" and su.wb ~= "", "template " .. name .. " setup has tech defaults")
	end end end
	H.check(shots >= 2, "template " .. name .. " seeds shots")
end

-- take / status / derived scene status
local s1 = flat[1].shot
local op, take = Model.opTake(s1, Util.now())
H.check(Store.commit(op) ~= nil, "commit take")
H.eq(#s1.takes, 1, "take added")
H.eq(s1.status, "SHOOTING", "shot moves to SHOOTING on first take")
H.eq(flat[1].scene.status, "SHOOTING", "scene derived SHOOTING")
H.check(flat[1].day.started ~= nil, "day start stamped")
H.eq(Model.get(take.id).n, 1, "take number 1")

-- rating via set, circle
local t1 = Model.get(take.id)
Store.commit(Model.opSet(t1, "rating", "GREAT", "RATE"))
Store.commit(Model.opCircle(t1, Util.now()))
H.eq(t1.circle, true, "circled")
H.eq(Model.bestTake(s1), t1, "best take is circled great")

-- undo
local label = Store.undo()
H.check(label ~= nil and label:find("CIRCLE"), "undo returns label")
H.eq(t1.circle, false, "undo uncircles")

-- GOT IT
Store.commit(Model.opStatus(s1, "GOT IT", Util.now()))
H.eq(s1.status, "GOT IT", "got it")
H.check(s1.doneAt ~= nil, "doneAt stamped")

-- NEXT ranking: from 01A-01, the next should be same-setup priority-2 over other-scene priority-1?
-- ranking is priority before locality, so a priority-1 shot anywhere today wins.
local c = Model.nextCandidates(s1.id)
H.check(#c > 0, "has next candidates")
H.eq(c[1].shot.priority, 1, "next candidate is priority A")
for i = 2, #c do
	H.check(c[i - 1].k3 <= c[i].k3 or c[i - 1].k1 < c[i].k1 or c[i - 1].k2 < c[i].k2, "candidates sorted by priority")
end
-- UP NEXT overrides everything
local low = flat[6].shot -- a priority-3 shot
Store.commit(Model.opStatus(low, "UP NEXT", Util.now()))
c = Model.nextCandidates(s1.id)
H.eq(c[1].shot, low, "UP NEXT shot is ranked first")
Store.commit(Model.opStatus(low, "NOT SHOT", Util.now()))

-- step by setup / scene
local sA = Model.step(flat[1].shot.id, 1, "setup")
H.eq(Model.code(sA), "01B-01", "step setup forward")
local sB = Model.step(flat[1].shot.id, 1, "scene")
H.eq(Model.code(sB), "02A-01", "step scene forward")
local sC = Model.step(sB.id, -1, "scene")
H.eq(Model.code(sC), "01A-01", "step scene back")
local sD = Model.step(flat[3].shot.id, -1, "setup")
H.eq(Model.code(sD), "01A-01", "step setup back goes to start of current setup")

-- flush then journal-only changes, then simulated crash + reload
H.check(Store.flush(), "flush ok")
local s2 = flat[2].shot
Store.commit((Model.opTake(s2, Util.now())))
Store.commit((Model.opTake(s2, Util.now())))
H.eq(#s2.takes, 2, "two takes on s2 before crash")
-- crash: throw away memory without flushing
Model.db = nil
H.eq(Store.load(), true, "reload after crash")
H.eq(Store.loadInfo.replayed, 2, "journal replayed 2 ops")
local s2b = Model.get(s2.id)
H.eq(#s2b.takes, 2, "takes survived crash via journal")
H.eq(Model.get(s1.id).status, "GOT IT", "earlier state survived")

-- torn journal line (power loss mid-append) is ignored, prior ops kept
Store.commit((Model.opTake(s2b, Util.now())))
Sim.failWritesAfter = 0
local ok = pcall(Store.commit, (Model.opTake(s2b, Util.now())))
Sim.failWritesAfter = nil
H.check(not ok, "simulated crash during journal write")
Model.db = nil
Store.load()
H.eq(#Model.get(s2.id).takes, 3, "torn line skipped, previous op kept")

-- crash during snapshot write: shotlist_new is partial -> ignored, journal still replays
Store.commit((Model.opTake(Model.get(s2.id), Util.now())))
Sim.failWritesAfter = 0
local okCall, flushed = pcall(Store.flush)
Sim.failWritesAfter = nil
H.check(okCall and flushed == false, "torn snapshot write reported as failed flush")
H.check(Store.dirty, "still dirty after failed flush (journal kept)")
Model.db = nil
Store.load()
H.eq(#Model.get(s2.id).takes, 4, "partial snapshot ignored; journal replayed")

-- corrupt main snapshot -> falls back to prev
Store.flush()
Store.commit((Model.opTake(Model.get(s2.id), Util.now())))
Store.flush()
local f = io.open(Sim.dataDir .. "/shotlist.json", "wb"); f:write("{\"schema\":1,\"proj"); f:close()
Model.db = nil
H.eq(Store.load(), true, "load survives corrupt main snapshot")
H.check(Store.loadInfo.source == "shotlist_prev", "fell back to previous snapshot (" .. tostring(Store.loadInfo.source) .. ")")

-- rolling backups
for i = 1, Store.SLOTS + 2 do
	Sim.advance(60)
	H.check(Store.snapshot("TEST " .. i), "snapshot " .. i)
end
local snaps = Store.listSnapshots()
H.eq(#snaps, Store.SLOTS, "backup ring keeps SLOTS entries")
H.eq(snaps[1].reason, "TEST " .. (Store.SLOTS + 2), "newest backup first")
-- restore an older one
local before = #Model.get(s2.id).takes
Store.commit((Model.opTake(Model.get(s2.id), Util.now())))
H.check(Store.restore(snaps[1]), "restore backup")
H.eq(#Model.get(s2.id).takes, before, "restore rolled back later take")
Model.db = nil
Store.load()
H.eq(#Model.get(s2.id).takes, before, "restored state persisted")

-- schema migration of a v0 database
local v0 = { projects = {}, nextId = 1 }
local m = Schema.migrate(v0)
H.check(m and m.schema == Schema.VERSION and m.gear and m.settings, "migrates v0 database")
local future = { schema = Schema.VERSION + 1, app = "shotlist", projects = {} }
local m2, err = Schema.migrate(future)
H.check(m2 == nil and err:find("newer"), "refuses newer schema")

-- report
p = Model.project()
local rep = Report.build(p, nil, Util.now())
H.eq(rep.progress.total, 60, "report total")
H.eq(rep.progress.done, 1, "report done")
H.check(rep.totalTakes >= 5, "report takes")
local lines = Report.lines(rep)
H.check(#lines > 20, "report renders lines")

-- interchange: export -> import nested round trip
local doc = Interchange.exportDoc(p, Util.now())
local text = json.encode(doc)
local back, warn = Interchange.importDoc(json.decode(text))
H.check(back ~= nil, "import nested export")
local n = 0
for _, d in ipairs(back.days) do for _, sc in ipairs(d.scenes) do for _, su in ipairs(sc.setups) do n = n + #su.shots end end end
H.eq(n, 60, "round trip keeps 60 shots")
-- flat rows (what a CSV/StudioBinder converter would produce)
local rows = Interchange.flatRows(p)
H.eq(#rows, 60, "flat rows")
local flatDoc = { format = "shotlist.shots", version = 1, project = { title = "CSV TEST" }, shots = {
	{ scene = "1", setup = "A", shot = "1", size = "Close Up", move = "Static", lens = "50mm", priority = "High", desc = "Hero" },
	{ scene = "1", setup = "A", size = "wide", move = "pan", priority = "low" },
	{ scene = "2", setup = "A", size = "Weird Size", move = "TRACKING", status = "done" },
} }
local fp, fw = Interchange.importDoc(flatDoc)
H.check(fp ~= nil, "flat import")
local su = fp.days[1].scenes[1].setups[1]
H.eq(su.shots[1].size, "CU", "alias Close Up -> CU")
H.eq(su.shots[1].move, "LOCKED", "alias Static -> LOCKED")
H.eq(su.shots[1].lens, "50", "lens mm stripped")
H.eq(su.shots[1].priority, 1, "High -> priority A")
H.eq(su.shots[2].num, "02", "blank shot number auto-numbered")
H.eq(fp.days[1].scenes[2].setups[1].shots[1].status, "GOT IT", "status alias done")
H.check(#fw >= 1, "custom vocab warns")
local csv = Interchange.toCSV(Interchange.FLAT_COLUMNS, rows)
H.check(csv:find("01A%-01") ~= nil, "csv contains code")
local written = Interchange.exportFiles(p, Util.now(), lines)
H.eq(#written, 4, "export writes 4 files")

-- estimate
local est = Model.estimate(p, nil, Util.now())
H.check(est.minutes and est.minutes > 0, "estimate minutes")

H.done("test_core")
