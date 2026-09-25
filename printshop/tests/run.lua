-- PRINT SHOP headless test suite.
--   lua5.4 tests/run.lua            (from the printshop/ directory)
--
-- Boots the real source tree against the strict Playdate mock, then runs
-- domain tests (persistence, migration, the finish-print transaction,
-- providers, Captain) and UI tests that drive every screen with input.

TEST_DIR = "tests/"
SOURCE_DIR = "source/"

dofile(TEST_DIR .. "mock_playdate.lua")

local results = { pass = 0, fail = 0, failures = {} }

local function test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if ok then
		results.pass = results.pass + 1
		io.write(".")
	else
		results.fail = results.fail + 1
		results.failures[#results.failures + 1] = name .. "\n" .. tostring(err)
		io.write("F")
	end
	io.flush()
end

local function eq(a, b, msg)
	if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function ok(v, msg)
	if not v then error(msg or "assertion failed", 2) end
end
local function near(a, b, eps, msg)
	if math.abs(a - b) > (eps or 1e-6) then error((msg or "") .. " expected ~" .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local B = {
	A = playdate.kButtonA, B = playdate.kButtonB, UP = playdate.kButtonUp,
	DOWN = playdate.kButtonDown, LEFT = playdate.kButtonLeft, RIGHT = playdate.kButtonRight,
}

-- Runs n idle frames.
local function frames(n, dt)
	for _ = 1, n or 1 do MOCK.frame(nil, 0, dt) end
end
-- Presses a button for one frame, then lets it go for one frame.
local function press(b, n)
	for _ = 1, n or 1 do
		MOCK.frame({ b }, 0)
		MOCK.frame(nil, 0)
	end
end
local function crank(deg, n)
	for _ = 1, n or 1 do MOCK.frame(nil, deg) end
end

local function topName()
	local top = Screens.top()
	for name, cls in pairs(_G) do
		if type(cls) == "table" and getmetatable(top) == cls then return name end
	end
	if top and top.overlay then return "overlay" end
	return "?"
end

-- Fresh boot from an empty datastore (or given files).
local function boot(files, keepIntro)
	MOCK.files = files or {}
	MOCK.keyboardVisible = false
	Events.reset()
	Screens.stack = {}
	Toast.queue, Toast.current = {}, nil
	Store.data = nil
	Printing.provider = nil
	App.init()
	-- Skip the first-launch Captain tour unless a test wants it.
	if not keepIntro then Store.data.captain.seenIntro = true end
	frames(2)
end

---------------------------------------------------------------------------
-- boot (main.lua runs App.init on import)

import "main"
frames(3)

test("boot seeds a demo shop and shows the workshop", function()
	eq(topName(), "HomeScreen")
	ok(Store.loadReport.seeded, "seeded")
	eq(#Store.data.spools, 10)
	ok(#Store.data.jobs >= 12, "jobs")
	ok(#Store.data.history >= 30, "history")
	eq(Printing.snapshot().state, "PRINTING")
	ok(MOCK.files.printshop ~= nil, "saved on boot")
end)

test("seed stats reproduce the PETG / OVERTURE example", function()
	local a = Stats.combo("PETG", "OVERTURE")
	eq(a.prints, 12, "prints")
	eq(a.failures, 3, "failures")
	eq(a.topCause, "adhesion", "top cause")
	eq(a.avgNozzle, 242, "avg nozzle")
end)

test("util: wrap, template, durations, hash stability", function()
	local lines = Text.wrap("Arrr. Stringing off the port bow. I'd inspect yer temperature.", 20)
	for _, l in ipairs(lines) do ok(#l <= 20, "line too long: " .. l) end
	eq(U.template("{a}-{b}-{c}", { a = 1, b = "x" }), "1-x-{c}")
	eq(U.fmtDuration(3900), "1h05m")
	eq(U.fmtDuration(59), "59s")
	eq(U.hash("benchy"), U.hash("benchy"))
	ok(U.hash("benchy") ~= U.hash("benchY"), "hash differs")
	local r1, r2 = Rng.new(42), Rng.new(42)
	for _ = 1, 50 do eq(r1:next(), r2:next()) end
end)

test("font covers every printable ASCII char", function()
	for c = 32, 126 do
		local ch = string.char(c)
		ok(ch == " " or Text.glyphs[ch] ~= nil, "missing glyph " .. ch)
	end
	for name, ch in pairs(FontData.icon) do ok(Text.glyphs[ch], "icon " .. name) end
end)

---------------------------------------------------------------------------
-- persistence

test("save/load roundtrip through JSON keeps everything", function()
	App.saveAll()
	local before = {
		spools = #Store.data.spools, jobs = #Store.data.jobs, history = #Store.data.history,
		cal = 0, nextId = Store.data.meta.nextId,
	}
	for _ in pairs(Store.data.calibrations) do before.cal = before.cal + 1 end
	local files = { printshop = MOCK.files.printshop }
	boot(files)
	ok(not Store.loadReport.seeded, "not reseeded")
	eq(#Store.data.spools, before.spools)
	eq(#Store.data.jobs, before.jobs)
	eq(#Store.data.history, before.history)
	local cal = 0
	for k, p in pairs(Store.data.calibrations) do cal = cal + 1 eq(k, p.key) end
	eq(cal, before.cal)
	ok(Store.data.meta.nextId >= before.nextId, "nextId kept")
	eq(Printing.snapshot().state, "PRINTING", "demo print resumed")
end)

test("corrupt save is backed up and replaced", function()
	boot({ printshop = '"garbage"' })
	ok(Store.loadReport.seeded, "seeded")
	ok(MOCK.files["printshop-corrupt"] ~= nil, "backup written")
	eq(topName(), "HomeScreen")
end)

test("partial / damaged records are repaired", function()
	local doc = json.decode(MOCK.files.printshop)
	doc.spools[1].remainingGrams = "lots"
	doc.spools[2].material = "UNOBTAINIUM"
	doc.jobs[3].status = "EXPLODED"
	doc.jobs[4].spoolId = "s999"
	doc.jobs[5].id = doc.jobs[6].id          -- duplicate id
	doc.history[1].outcome = "failed"
	doc.history[1].cause = nil
	doc.settings = nil
	doc.maintenance.tasks[1].printerId = "p404"
	boot({ printshop = json.encode(doc) })
	local d = Store.data
	eq(type(d.spools[1].remainingGrams), "number")
	eq(d.spools[2].material, "OTHER")
	eq(d.jobs[3].status, "IDEA")
	eq(d.jobs[4].spoolId, nil)
	ok(d.jobs[5].id ~= d.jobs[6].id, "ids unique")
	eq(d.history[1].cause, "unknown")
	eq(d.settings.lowSpoolGrams, 150)
	eq(d.maintenance.tasks[1].printerId, "p1")
end)

test("v1 save migrates to current schema", function()
	local now = MOCK.nowSec
	local v1 = {
		version = 1,
		meta = { nextId = 20, createdAt = now - 100 * 86400 },
		printers = { { id = "p1", name = "A1 MINI", provider = "demo", stats = { prints = 3, printSeconds = 36000 } } },
		spools = {
			{ id = "s1", manufacturer = "BAMBU", material = "PLA", color = "RED", nominalGrams = 1000, remaining = 400, temp = 215, cost = 20 },
		},
		jobs = {
			{ id = "j1", name = "OLD BOAT", status = "ARCHIVED", spoolId = "s1", material = "PLA" },
			{ id = "j2", name = "NEW BOAT", status = "QUEUED", spoolId = "s1", material = "PLA" },
		},
		history = {
			{ id = "h1", jobId = "j1", name = "OLD BOAT", at = now - 5 * 86400, ok = true, grams = 15, spoolId = "s1", material = "PLA" },
			{ id = "h2", jobId = "j1", name = "OLD BOAT", at = now - 6 * 86400, ok = false, grams = 5, spoolId = "s1", material = "PLA" },
		},
		failures = {
			{ id = "f1", jobId = "j1", at = now - 6 * 86400, cause = "adhesion", spoolId = "s1" },
			{ id = "f2", jobId = "j9", at = now - 9 * 86400, cause = "clog", spoolId = "s1", grams = 3, material = "PLA" },
		},
		maintenance = {
			{ id = "m1", kind = "lube", name = "LUBE", interval = { kind = "hours", value = 50 }, last = now - 10 * 86400 },
			{ id = "m2", kind = "bed_clean", name = "BED", interval = { kind = "days", value = 7 }, last = now - 3 * 86400 },
		},
		calibrations = { PLA = { nozzle = 212, bed = 58, flow = 0.97 } },
	}
	boot({ printshop = json.encode(v1) })
	local d = Store.data
	eq(Store.loadReport.migratedFrom, 1)
	ok(MOCK.files["printshop-v1"] ~= nil, "v1 backup kept")
	eq(d.schema, Schema.CURRENT)
	local s = Store.spool("s1")
	eq(s.remainingGrams, 400)
	eq(s.favNozzle, 215)
	eq(s.location, "SHELF")
	local j1 = Store.job("j1")
	eq(j1.archived, true)
	eq(j1.status, "COMPLETE")
	eq(#d.history, 3, "orphan failure became a history row")
	local h2 = U.findById(d.history, "h2")
	eq(h2.outcome, "failed")
	eq(h2.cause, "adhesion")
	local lube = U.findById(d.maintenance.tasks, "m1")
	eq(lube.intervalHours, 50)
	eq(lube.lastAt, now - 10 * 86400)
	local bed = U.findById(d.maintenance.tasks, "m2")
	eq(bed.intervalDays, 7)
	local p = d.calibrations["p1|PLA|ANY"]
	ok(p, "calibration rekeyed")
	eq(p.nozzleTemp, 212)
	near(p.flowRatio, 0.97, 1e-9)
	-- New jobs pick up the migrated profile.
	local j = Queue.add({ name = "T", spoolId = "s1" })
	eq(j.nozzleTemp, 212)
	ok(d.meta.nextId > 20, "ids continue")
	-- The migrated doc survives another save/load.
	App.saveAll()
	boot({ printshop = MOCK.files.printshop })
	ok(Store.loadReport.migratedFrom == nil, "no second migration")
	eq(Store.spool("s1").favNozzle, 215)
end)

test("newer-schema save is backed up, not downgraded", function()
	local doc = json.decode(MOCK.files.printshop)
	doc.schema = 99
	boot({ printshop = json.encode(doc) })
	ok(Store.loadReport.newer, "flagged newer")
	ok(MOCK.files["printshop-v99"] ~= nil, "backup")
end)

test("empty shop: every screen renders its empty state", function()
	boot({})
	App.resetData(true)
	frames(2)
	eq(#Store.data.spools, 0)
	eq(#Store.data.jobs, 0)
	for _, st in ipairs(HomeScreen.STATIONS) do
		Screens.popToRoot()
		Screens.top():open(st.id)
		frames(3)
		-- Close any dialog the screen opened (Captain greeting etc.).
		for _ = 1, 6 do press(B.A) end
		frames(2)
	end
	Screens.popToRoot()
	eq(topName(), "HomeScreen")
	ok(#Captain.candidates() > 0, "captain still has something to say")
end)

---------------------------------------------------------------------------
-- the interconnected finish transaction

test("completing a queued print ripples through every tool", function()
	boot({})
	local j = Store.job("j5")                 -- SD CARD WALLET, READY, s10
	local s = Store.spool(j.spoolId)
	local p = Store.activePrinter()
	local before = {
		grams = s.remainingGrams, ok = s.successCount, prints = p.stats.prints,
		secs = p.stats.printSeconds, hist = #Store.data.history, ledger = #Store.data.consumption,
		inbox = #Store.data.captain.inbox,
	}
	local h = Printing.markComplete(j)
	eq(j.status, "COMPLETE")
	ok(j.completedAt > 0, "completed date")
	near(s.remainingGrams, before.grams - j.estGrams, 1e-6, "filament")
	eq(s.successCount, before.ok + 1, "spool usage")
	eq(#Store.data.history, before.hist + 1, "history")
	eq(h.outcome, "success")
	eq(#Store.data.consumption, before.ledger + 1, "ledger")
	eq(p.stats.prints, before.prints + 1, "printer stats")
	eq(p.stats.printSeconds, before.secs + j.estMinutes * 60, "hours")
	ok(#Store.data.captain.inbox > before.inbox, "captain notified")
	local proj = U.find(Stats.projects(), function(x) return x.name == "" end)
	eq(proj, nil)
end)

test("a failed print consumes filament and feeds failure stats", function()
	local j = Store.job("j3")                 -- HEX PEN CUP, s2
	local s = Store.spool(j.spoolId)
	local g, f = s.remainingGrams, s.failCount
	local combo = Stats.combo(s.material, s.manufacturer)
	Printing.markFailed(j, "stringing", "wisps", 20, 0.3)
	eq(j.status, "FAILED")
	near(s.remainingGrams, g - 20, 1e-6)
	eq(s.failCount, f + 1)
	local after = Stats.combo(s.material, s.manufacturer)
	eq(after.failures, combo.failures + 1)
	eq(Store.data.history[#Store.data.history].cause, "stringing")
	-- Retry puts it back in line with the profile.
	Queue.retry(j)
	eq(j.status, "QUEUED")
end)

test("print hours trigger maintenance crossings", function()
	local p = Store.activePrinter()
	local t = MaintService.add({ kind = "custom", name = "TEST TASK", intervalHours = 2, intervalDays = 0 })
	local crossed
	local fn = Events.on("maint.due", function(e) if e.task == t then crossed = e end end)
	local j = Queue.add({ name = "LONG ONE", spoolId = "s2", estMinutes = 150, estGrams = 30 })
	Printing.markComplete(j)
	Events.off("maint.due", fn)
	ok(crossed, "maintenance crossing emitted")
	ok(MaintService.status(t).due, "task due")
	MaintService.logDone(t, "done")
	ok(not MaintService.status(t).due, "reset after logging")
	ok(p.stats.printSeconds > 0)
end)

test("calibration becomes the recommended profile for queue entries", function()
	-- ESUN PETG has no profile yet: new jobs get PETG defaults.
	local j = Queue.add({ name = "CLEAR THING", spoolId = "s5" })
	eq(j.nozzleTemp, Enums.MATERIAL_INFO.PETG.nozzle)
	eq(j.profileKey, "")
	local key = Calibration.key("p1", "PETG", "ESUN")
	local p, run, touched = CalService.save("temptower", key, { nozzleTemp = 236, bedTemp = 72 }, "", true)
	ok(run.id, "run stored")
	ok(touched >= 1, "queued job updated")
	eq(j.nozzleTemp, 236, "existing queued job re-profiled")
	eq(j.profileKey, key)
	eq(Store.spool("s5").favNozzle, 236, "spool favourite updated")
	local j2 = Queue.add({ name = "ANOTHER", spoolId = "s5" })
	eq(j2.nozzleTemp, 236)
	eq(j2.bedTemp, 72)
	-- Not recommended -> ignored by new jobs.
	CalService.setRecommended(p, false)
	local j3 = Queue.add({ name = "THIRD", spoolId = "s5" })
	eq(j3.nozzleTemp, Enums.MATERIAL_INFO.PETG.nozzle)
	-- A calibration run silences the Captain's matching suggestion.
	local before = #U.filter(Stats.suggestions(), function(s) return s.kind == "calib" and s.key == "p1|PETG|OVERTURE" end)
	ok(before > 0, "PETG/OVERTURE adhesion suggestion exists")
	CalService.save("firstlayer", "p1|PETG|OVERTURE", { zOffset = -0.02, bedTemp = 80 }, "", true)
	local sug = U.filter(Stats.suggestions(), function(s) return s.kind == "calib" and s.key == "p1|PETG|OVERTURE" and s.target == "firstlayer" end)
	eq(#sug, 0, "first-layer suggestion cleared")
end)

test("every calibration procedure computes sane results", function()
	for _, proc in ipairs(CalibDefs.list) do
		local ctx = CalService.context("p1|PLA|BAMBU")
		local r = {}
		for _, st in ipairs(proc.steps) do
			if st.type == "dial" or st.type == "measure" then
				r[st.field] = st.default and st.default(ctx, r) or st.min
			elseif st.type == "pick" then
				local vals = st.values(ctx)
				ok(#vals > 1, proc.id .. " pick values")
				r[st.field] = vals[#vals // 2 + 1]
			end
		end
		local out = proc.compute(r, ctx, { all = true })
		ok(type(out) == "table", proc.id)
		for k, v in pairs(out) do
			local known = false
			for _, f in ipairs(Calibration.FIELDS) do if f[1] == k then known = true end end
			ok(known, proc.id .. " writes unknown field " .. k)
			ok(type(v) == "number" or type(v) == "boolean", proc.id .. "." .. k)
		end
	end
	local dim = CalibDefs.byId.dimension.compute({ x = 19.9, y = 19.9, z = 20.1 }, CalService.context("p1|PLA|ANY"))
	near(dim.xyScale, 100.5, 0.05)
	near(dim.zScale, 99.5, 0.05)
	local flow = CalibDefs.byId.flow.compute({ baseFlow = 1.0, pass1 = -5, pass2 = -2 }, CalService.context("p1|PLA|ANY"))
	near(flow.flowRatio, 0.93, 0.001)
end)

---------------------------------------------------------------------------
-- demo provider

local function runDemo(seconds)
	local steps = math.ceil(seconds / 10)
	for _ = 1, steps do
		MOCK.advance(10)
		MOCK.frame(nil, 0, 10000 / Store.settings().demoSpeed)
	end
end

test("demo print runs HEATING -> PRINTING -> COMPLETE and logs history", function()
	boot({})
	Store.settings().demoChaos = false
	-- Finish the seeded in-progress print first.
	runDemo(95 * 60)
	local snap = Printing.snapshot()
	eq(snap.state, "COMPLETE")
	eq(Store.job("j1").status, "COMPLETE", "seeded job completed")
	local hist = Store.data.history[#Store.data.history]
	eq(hist.jobId, "j1")
	Printing.acknowledge()
	eq(Printing.snapshot().state, "IDLE")
	-- Start a fresh job.
	local j = Store.job("j6")                -- BENCHY #48, s9 sealed
	local s = Store.spool(j.spoolId)
	local g = s.remainingGrams
	local okStart, err = Printing.start(j)
	ok(okStart, err)
	eq(Printing.snapshot().state, "HEATING")
	eq(j.status, "PRINTING")
	runDemo(5 * 60)
	eq(Printing.snapshot().state, "PRINTING")
	-- Pause / resume.
	ok(Printing.pause())
	eq(j.status, "PAUSED")
	ok(Printing.resume())
	eq(j.status, "PRINTING")
	runDemo(60 * 60)
	eq(Printing.snapshot().state, "COMPLETE")
	eq(j.status, "COMPLETE")
	near(s.remainingGrams, g - j.estGrams, 1e-6)
	eq(s.dryness, "DRY", "sealed spool opened by use")
	ok(#Store.data.printLog > 0)
end)

test("demo print fast-forwards while the app was closed", function()
	boot({})
	Store.settings().demoChaos = false
	App.saveAll()
	local files = { printshop = MOCK.files.printshop }
	MOCK.advance(3 * 3600)               -- three real hours away at 60x
	boot(files)
	eq(Store.job("j1").status, "COMPLETE", "finished while away")
	eq(Printing.snapshot().state, "COMPLETE")
end)

test("runout pauses the print; swapping spools resumes and splits usage", function()
	boot({})
	Store.settings().demoChaos = false
	runDemo(95 * 60)
	Printing.acknowledge()
	local j = Queue.add({ name = "BIG PLANTER", spoolId = "s3", estMinutes = 120, estGrams = 200, layers = 150 })
	j.status = "QUEUED"
	local low = Store.spool("s3")
	local lowGrams = low.remainingGrams
	ok(lowGrams < 200)
	ok(Printing.start(j))
	runDemo(130 * 60)
	local snap = Printing.snapshot()
	eq(snap.state, "PAUSED")
	ok(Store.data.runout, "runout flagged")
	local okR = Printing.resume()
	ok(not okR, "cannot resume on an empty spool")
	ok(Printing.swapSpool("s1"))
	near(low.remainingGrams, 0, 1e-6, "old spool emptied")
	local s1 = Store.spool("s1")
	local g1 = s1.remainingGrams
	ok(Printing.resume())
	eq(Store.data.runout, nil)
	runDemo(130 * 60)
	eq(Printing.snapshot().state, "COMPLETE")
	near(g1 - s1.remainingGrams, 200 - lowGrams, 0.01, "new spool pays the rest")
	eq(j.status, "COMPLETE")
end)

test("demo failures are driven by shop state and are deterministic", function()
	boot({})
	runDemo(95 * 60)
	Printing.acknowledge()
	Store.settings().demoChaos = true
	-- A WET TPU spool strings: find an attempt that fails.
	local j = Store.job("j7")                 -- TPU BUMPERS, FAILED, s6 WET
	Queue.retry(j)
	local failedWith = nil
	for attempt = 1, 12 do
		ok(Printing.start(j))
		runDemo(80 * 60)
		local pf = Store.data.pendingFailure
		if pf then
			failedWith = pf.cause
			local screen = FailureScreen.new()
			ok(screen.job == j, "failure screen bound to job")
			Printing.resolvePending({ cause = pf.cause or "unknown", notes = "", grams = pf.grams })
			break
		end
		Printing.acknowledge()
		Queue.retry(j)
	end
	ok(failedWith ~= nil, "a wet TPU spool eventually fails")
	-- Determinism: same seed, same plan.
	local a = DemoProvider.new(Store.activePrinter())
	local b = DemoProvider.new(Store.activePrinter())
	local spec = { jobId = "jX", name = "X", spoolId = "s6", material = "TPU", grams = 10, minutes = 30, layers = 50, attempt = 3, printerId = "p1" }
	a:startJob(spec)
	b:startJob(spec)
	eq(a.st.failAt, b.st.failAt)
	eq(a.st.failCause, b.st.failCause)
end)

test("printer-reported failure goes pending until a cause is logged", function()
	boot({})
	local p = Printing.provider
	local j = Store.job("j1")
	local s = Store.spool(j.spoolId)
	local g, fc = s.remainingGrams, s.failCount
	-- Force a failure on the seeded print.
	p.st.failAt = p.st.elapsedSec / p.st.totalSec + 0.01
	p.st.failCause = "spaghetti"
	p.st.failReason = "SPAGHETTI DETECTED"
	runDemo(10 * 60)
	local pf = Store.data.pendingFailure
	ok(pf, "pending failure")
	eq(pf.cause, "spaghetti")
	eq(j.status, "FAILED")
	eq(s.remainingGrams, g, "no consumption until logged")
	-- Workshop auto-opened the failure log.
	eq(topName(), "FailureScreen")
	local ok2, why = Printing.canStart(Store.job("j6"))
	ok(not ok2 and why == "LOG LAST FAILURE FIRST")
	-- Log it through the UI: A opens the menu, A picks "LOG AS ...".
	press(B.A)
	eq(topName(), "Menu")
	press(B.A)
	eq(Store.data.pendingFailure, nil)
	ok(s.remainingGrams < g, "filament consumed")
	eq(s.failCount, fc + 1)
	eq(Store.data.history[#Store.data.history].cause, "spaghetti")
	eq(Printing.snapshot().state, "IDLE")
	-- Close the Captain's reaction.
	for _ = 1, 4 do press(B.A) end
end)

test("cancel from the printer can be logged as a plain cancel", function()
	boot({})
	local j = Store.job("j1")
	local fails = Store.activePrinter().stats.failures
	ok(Printing.cancel())
	frames(2)
	ok(Store.data.pendingFailure and Store.data.pendingFailure.cancelled, "pending cancel")
	Printing.resolvePending({ asCancel = true })
	eq(Store.data.history[#Store.data.history].outcome, "cancelled")
	eq(Store.activePrinter().stats.failures, fails, "cancel is not a failure")
	eq(j.status, "QUEUED", "cancelled job returns to the queue")
	Screens.popToRoot()
end)

---------------------------------------------------------------------------
-- bridge + bambu adapters

test("bambu report maps onto the provider interface", function()
	local report = { print = {
		gcode_state = "RUNNING", mc_percent = 40, mc_remaining_time = 30, layer_num = 48, total_layer_num = 120,
		nozzle_temper = 219.5, nozzle_target_temper = 220, bed_temper = 59.8, bed_target_temper = 60,
		subtask_name = "cable_clip_v3.gcode.3mf", print_error = 0,
		ams = { tray_now = "1", ams = { { id = "0", tray = {
			{ id = "0", tray_type = "PLA", tray_color = "000000FF", remain = 61 },
			{ id = "1", tray_type = "PETG-CF", tray_color = "FFFFFFFF", remain = 80 },
		} } } },
	} }
	local doc = BambuProvider.mapReport(report)
	eq(doc.state, "PRINTING")
	eq(doc.progress.layer, 48)
	eq(doc.progress.remainingSec, 1800)
	eq(doc.progress.elapsedSec, 1200)
	eq(doc.job.name, "cable_clip_v3")
	eq(doc.spools.active, 2)
	eq(doc.spools.slots[2].material, "PETG")
	eq(BambuProvider.mapReport({ gcode_state = "FINISH" }).state, "COMPLETE")
	eq(BambuProvider.mapReport({ gcode_state = "FAILED", print_error = 50348044 }).message, "ERROR 0300400C")
	local cmd = BambuProvider.buildCommand("pause")
	eq(cmd.print.command, "pause")
end)

test("bridge provider derives complete/failed events from state changes", function()
	boot({})
	local printer = Store.activePrinter()
	local p = LocalBridgeProvider.new(printer)
	local function doc(state, pct)
		return { state = state, temps = { nozzle = 220, nozzleTarget = 220, bed = 60, bedTarget = 60 },
			progress = { pct = pct, layer = 10, totalLayers = 100, elapsedSec = 600, remainingSec = 60 },
			job = { name = "Cable Clips x12", material = "PLA", grams = 18 } }
	end
	p:ingest(doc("PRINTING", 50))
	p:ingest(doc("PRINTING", 90))
	p:ingest(doc("COMPLETE", 100))
	local evs = p:pollEvents()
	local types = {}
	for _, e in ipairs(evs) do types[#types + 1] = e.type end
	ok(U.indexOf(types, "complete"), "complete derived: " .. table.concat(types, ","))
	-- Without a host (or network) it reports OFFLINE with a reason.
	printer.host = ""
	local q = LocalBridgeProvider.new(printer)
	q:update(5000)
	eq(q:getStatus().state, "OFFLINE")
	ok(string.find(q:getStatus().message, "HOST"), q:getStatus().message)
	-- Switching the active printer to the bridge keeps the app usable.
	printer.provider = "bridge"
	Printing.reload()
	frames(5)
	eq(Printing.snapshot().state, "OFFLINE")
	printer.provider = "demo"
	Printing.reload()
end)

test("jobs started on a live printer are adopted into the queue", function()
	boot({})
	local printer = Store.activePrinter()
	printer.provider = "bridge"
	Printing.reload()
	local p = Printing.provider
	p:ingest({ state = "PRINTING", temps = {}, progress = { pct = 5, layer = 1, totalLayers = 50 },
		job = { name = "Mystery Part", material = "PETG", grams = 30 } })
	Printing.drain()
	local j = U.find(Store.data.jobs, function(x) return x.name == "MYSTERY PART" end)
	ok(j, "adopted")
	eq(j.status, "PRINTING")
	eq(j.source, "printer")
	p:ingest({ state = "COMPLETE", temps = {}, progress = { pct = 100, layer = 50, totalLayers = 50 },
		job = { name = "Mystery Part", material = "PETG", grams = 30 } })
	Printing.drain()
	eq(j.status, "COMPLETE")
	printer.provider = "demo"
	Printing.reload()
end)

---------------------------------------------------------------------------
-- Benchy Captain

test("captain lines are deterministic, varied and slot-complete", function()
	boot({})
	local seen = {}
	local n = 0
	for i = 1, 60 do
		local line = Captain.advice()
		ok(type(line.text) == "string" and #line.text > 10, "text")
		ok(not string.find(line.text, "{%w+}"), "unfilled slot in: " .. line.text)
		if not seen[line.text] then n = n + 1 seen[line.text] = true end
	end
	ok(n >= 25, "variety: " .. n)
	-- Same state + counter -> same line.
	local c = Store.data.captain.counter
	local a = Captain.compose("wisdom", {}, "neutral", Rng.new(99))
	local b = Captain.compose("wisdom", {}, "neutral", Rng.new(99))
	eq(a, b)
	-- Combination count is in the thousands.
	local bodies = 0
	for _, bank in pairs(Phrases.topics) do bodies = bodies + #bank end
	ok(bodies * #Phrases.openers * #Phrases.closers > 10000, "combinations")
	-- Every topic bank renders without leftover slots given the vars the rules supply.
	for _, cand in ipairs(Captain.candidates()) do
		for i = 1, 8 do
			local line = Captain.compose(cand.topic, cand.vars, cand.mood, Rng.new(i))
			ok(not string.find(line, "{%w+}"), cand.topic .. ": " .. line)
		end
	end
	ok(Store.data.captain.counter > c - 1)
end)

test("captain reacts to failures with cause-specific advice", function()
	boot({})
	Store.data.captain.inbox = {}
	local j = Store.job("j2")
	Printing.markFailed(j, "layershift", "", 5, 0.2)
	ok(Captain.hasNews())
	local news = Captain.nextNews()
	eq(news.topic, "fail_layershift")
	eq(news.mood, "worried")
	local mentions = 0
	for i = 1, 20 do
		local line = Captain.compose("fail_layershift", { job = j.name, layer = 3 }, "worried", Rng.new(i))
		if string.find(line, j.name, 1, true) then mentions = mentions + 1 end
	end
	ok(mentions > 0, "some layer-shift lines name the job")
	-- The combo report reads like the spec example.
	local rep = Captain.comboReport("PETG", "OVERTURE")
	ok(string.find(rep, "12 prints", 1, true) and string.find(rep, "3 failures", 1, true), rep)
	ok(string.find(rep, "adhesion", 1, true), rep)
end)

---------------------------------------------------------------------------
-- UI

test("first launch: the Captain gives the tour", function()
	boot({}, true)
	frames(25)
	eq(topName(), "Dialog")
	ok(Store.data.captain.seenIntro)
	local presses = 0
	while topName() ~= "HomeScreen" and presses < 20 do
		press(B.A)
		frames(3)
		presses = presses + 1
	end
	eq(topName(), "HomeScreen")
	ok(presses >= 4, "multi-page tour (" .. presses .. " presses)")
	-- Not repeated on the next launch.
	App.saveAll()
	boot({ printshop = MOCK.files.printshop }, true)
	frames(25)
	eq(topName(), "HomeScreen")
end)

test("navigate every station, open its menu, and come back", function()
	boot({})
	for i, st in ipairs(HomeScreen.STATIONS) do
		Screens.popToRoot()
		local home = Screens.top()
		home.sel = i
		press(B.A)
		ok(Screens.depth() >= 2, "opened " .. st.id)
		frames(10)
		-- Scroll around, open the A menu if any, cancel out.
		press(B.DOWN, 2)
		crank(30, 4)
		press(B.RIGHT)
		press(B.LEFT)
		press(B.A)
		frames(3)
		press(B.B)
		frames(2)
		Screens.popToRoot()
		eq(topName(), "HomeScreen")
	end
end)

test("queue: crank reorder moves the job and persists the order", function()
	boot({})
	Screens.push(QueueScreen.new())
	local q = Screens.top()
	q.list:select(3)                           -- second job
	local j = q:selectedJob()
	local _, before = U.findById(Store.data.jobs, j.id)
	q:startMove(j)
	crank(45)                                  -- one detent down
	frames(1)
	press(B.A)                                 -- drop
	local _, after = U.findById(Store.data.jobs, j.id)
	eq(after, before + 1, "moved down one slot")
	crank(-45, 1)
	eq(select(2, U.findById(Store.data.jobs, j.id)), after, "crank ignored when not moving")
	App.saveAll()
	boot({ printshop = MOCK.files.printshop })
	eq(select(2, U.findById(Store.data.jobs, j.id)), after, "order persisted")
end)

test("queue: add a job through the editor with the keyboard", function()
	boot({})
	Screens.push(QueueScreen.new())
	local count = #Store.data.jobs
	press(B.A)                                -- "+ NEW JOB"
	eq(topName(), "JobEditScreen")
	press(B.A)                                -- NAME -> keyboard
	ok(MOCK.keyboardVisible, "keyboard shown")
	playdate.keyboard.text = "Desk Hook"
	MOCK.keyboardVisible = false
	playdate.keyboard.keyboardWillHideCallback(true)
	frames(4)
	local ed = Screens.top()
	eq(ed.draft.name, "DESK HOOK")
	-- Jump to SAVE and press it.
	ed.form.list:select(#ed.form.fields)
	press(B.A)
	eq(#Store.data.jobs, count + 1)
	local j = Store.data.jobs[#Store.data.jobs]
	eq(j.name, "DESK HOOK")
	ok(j.nozzleTemp > 0, "profile applied")
end)

test("dial: crank adjusts the value in detents", function()
	boot({})
	local got
	Dial.open({ title = "NOZZLE", label = "NOZZLE TEMP", value = 215, min = 190, max = 240, step = 1, unit = "C",
		onAccept = function(v) got = v end })
	crank(12, 5)                 -- 5 detents
	press(B.UP)                  -- x10
	press(B.A)
	eq(got, 230)
end)

test("rolodex: flip, filter, weigh-in", function()
	boot({})
	Screens.push(RolodexScreen.new())
	local r = Screens.top()
	local first = r:current()
	crank(50)
	frames(5)
	ok(r:current() ~= first, "flipped")
	press(B.RIGHT)                -- PLA filter
	for _, s in ipairs(r.spools) do eq(s.material, "PLA") end
	local s = r:current()
	local ledger = #Store.data.consumption
	Filament.setRemaining(s, s.remainingGrams - 50, "test")
	eq(#Store.data.consumption, ledger + 1)
	-- LOW filter only shows low spools.
	r.filter = U.indexOf(Filament.FILTERS, "LOW")
	r:refresh()
	for _, sp in ipairs(r.spools) do ok(Spool.isLow(sp, 150)) end
	frames(3)
end)

test("calibration wizard end to end with the crank", function()
	boot({})
	local key = "p1|PLA|POLYMAKER"
	Screens.push(CalibRunScreen.new(CalibDefs.byId.temptower, key))
	local w = Screens.top()
	press(B.A)                                 -- finish typing
	press(B.A)                                 -- next
	eq(w:def().type, "pick")
	crank(30, 2)                               -- two floors cooler
	press(B.A)
	eq(w:def().type, "dial")
	crank(12, 3)                               -- +3C fine tune
	press(B.A)
	press(B.A)                                 -- bed temp as is
	eq(w:def().type, "summary")
	press(B.A)                                 -- save menu
	press(B.A)                                 -- SAVE + RECOMMEND
	local p = CalService.profile(key)
	ok(p, "profile saved")
	ok(p.nozzleTemp > 0 and p.recommended, "values")
	eq(CalService.lastRun("temptower", key).key, key)
end)

test("maintenance: log done via the UI resets the task", function()
	boot({})
	Screens.push(MaintScreen.new())
	local m = Screens.top()
	local e = m.rows[1]
	ok(e.st.soon, "most urgent first")
	press(B.A)                                 -- actions
	press(B.A)                                 -- LOG AS DONE
	press(B.A)                                 -- DONE, NO NOTE
	ok(not MaintService.status(e.task).soon, "reset")
	eq(MaintService.logFor(e.task.id, 1)[1].taskId, e.task.id)
end)

test("system menu items exist and work", function()
	boot({})
	local names = {}
	for _, it in ipairs(MOCK.menuItems) do names[#names + 1] = it.title end
	ok(#MOCK.menuItems <= 3, "at most three custom items")
	Screens.push(QueueScreen.new())
	for _, it in ipairs(MOCK.menuItems) do
		if it.title == "captain" then it.cb() end
	end
	eq(topName(), "CaptainScreen")
	for _, it in ipairs(MOCK.menuItems) do
		if it.title == "demo spd" then it.cb("600x") it.cb("300x") end
	end
	eq(Store.settings().demoSpeed, 300)
end)

test("fuzz: random input across screens never crashes", function()
	boot({})
	local rng = Rng.new(2024)
	local buttons = { B.A, B.B, B.UP, B.DOWN, B.LEFT, B.RIGHT }
	for i = 1, 4000 do
		local r = rng:next()
		if MOCK.keyboardVisible then
			playdate.keyboard.text = "FUZZ " .. i
			MOCK.keyboardVisible = false
			playdate.keyboard.keyboardWillHideCallback(rng:chance(0.7))
			frames(1)
		elseif r < 0.55 then
			-- Bias away from B so we get deep into screens.
			local b = rng:pick(buttons)
			if b == B.B and rng:chance(0.5) then b = B.A end
			press(b)
		elseif r < 0.8 then
			crank(rng:int(-60, 60))
		else
			MOCK.advance(rng:int(1, 600))
			frames(1, rng:int(10, 300))
		end
		if Screens.depth() > 12 then Screens.popToRoot() end
	end
	ok(Screens.depth() >= 1)
	App.saveAll()
	boot({ printshop = MOCK.files.printshop })
	ok(not Store.loadReport.seeded, "fuzzed data reloads")
end)

---------------------------------------------------------------------------

print("")
for _, f in ipairs(results.failures) do print("\nFAIL: " .. f) end
print(string.format("\n%d passed, %d failed", results.pass, results.fail))
os.exit(results.fail == 0 and 0 or 1)
