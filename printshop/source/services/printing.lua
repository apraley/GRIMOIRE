-- Printing: the orchestrator. Owns the active provider, turns provider
-- events into shop changes, and implements the "finish a print" transaction
-- that ties every tool together:
--
--   finish(job, outcome)
--     -> filament consumed from the spool (+ ledger row)
--     -> spool success/failure counters
--     -> history record (failure cause lives here)
--     -> printer statistics (prints, hours, grams, streak)
--     -> maintenance hour odometer -> "maint.due" when a task crosses
--     -> job status / dates / attempts
--     -> "print.finished" event -> Benchy Captain inbox, toasts, project stats
--     -> immediate save
--
-- Failures reported by a printer are held in Store.data.pendingFailure until
-- the user logs a cause (screens/failure.lua), so statistics carry a real
-- cause rather than a guess.

Printing = {
	provider = nil,
}

local PROVIDER_CLASSES = {
	demo = function(printer) return DemoProvider.new(printer) end,
	bridge = function(printer) return LocalBridgeProvider.new(printer) end,
	bambu = function(printer) return BambuProvider.new(printer) end,
}

function Printing.makeProvider(printer)
	local make = PROVIDER_CLASSES[printer.provider] or PROVIDER_CLASSES.demo
	return make(printer)
end

-- Builds the provider for the active printer and restores its saved state,
-- fast-forwarding a demo print by the time the app was closed.
function Printing.init()
	local printer = Store.activePrinter()
	local p = Printing.makeProvider(printer)
	local saved = Store.data.providerState[printer.id .. ":" .. printer.provider]
	if saved == nil and printer.provider == "demo" then
		saved = Store.data.providerState.demo   -- seed data uses the short key
		Store.data.providerState.demo = nil
	end
	if saved then
		local away = 0
		if saved.savedAt and saved.savedAt > 0 then away = math.max(0, Clock.now() - saved.savedAt) end
		p:restore(saved, away)
	end
	Printing.provider = p
	-- Anything that happened while we were away (fast-forward) is handled now.
	Printing.drain()
	Printing.reconcile()
	Printing.persist()
	return p
end

-- Brings the queue and the provider back into agreement after a restart,
-- a printer switch or a change of connection:
--  * an ERROR plate with no failure waiting to be logged is cleared
--    (e.g. the failure was logged while another printer was active);
--  * a job the queue thinks is PRINTING/PAUSED, which the provider is not
--    running, goes back to QUEUED with a log line, so it can be restarted
--    or marked done by hand. OFFLINE bridges are left alone until they
--    report in.
function Printing.reconcile()
	local p = Printing.provider
	local printer = Store.activePrinter()
	local st = p:getStatus().state
	local pf = Store.data.pendingFailure
	if st == "ERROR" and (pf == nil or pf.printerId ~= printer.id) then
		p:acknowledge()
		st = p:getStatus().state
	end
	if st == "OFFLINE" then return end
	local running = nil
	if st == "PRINTING" or st == "HEATING" or st == "PAUSED" then
		running = Printing.jobForProvider(p:getCurrentJob())
	end
	for _, j in ipairs(Store.data.jobs) do
		if j.printerId == printer.id and (j.status == "PRINTING" or j.status == "PAUSED") and j ~= running then
			if not (pf and pf.jobId == j.id) then
				j.status = "QUEUED"
				Printing.log(j.name .. " NOT ON PRINTER; BACK IN QUEUE")
				Store.markDirty()
			end
		end
	end
end

function Printing.persist()
	if Printing.provider == nil or Store.data == nil then return end
	local printer = Store.activePrinter()
	Store.data.providerState[printer.id .. ":" .. printer.provider] = Printing.provider:serialize()
end

function Printing.switchPrinter(printerId)
	if Printing.provider then
		Printing.persist()
		Printing.provider:shutdown()
	end
	Store.data.settings.activePrinterId = printerId
	Store.markDirty()
	return Printing.init()
end

-- Rebuild after the provider kind of the active printer changed.
function Printing.reload()
	if Printing.provider then
		Printing.persist()
		Printing.provider:shutdown()
	end
	return Printing.init()
end

function Printing.update(dtMs)
	local p = Printing.provider
	if p == nil then return end
	p:update(dtMs)
	Printing.drain()
end

function Printing.drain()
	local p = Printing.provider
	for _, ev in ipairs(p:pollEvents()) do
		Printing.handle(ev)
	end
	Printing.adoptExternalJob()
end

function Printing.log(text)
	local log = Store.data.printLog
	log[#log + 1] = { at = Clock.now(), text = U.upper(text) }
	while #log > 40 do table.remove(log, 1) end
	Store.markDirty()
end

-- The queue job the provider is working on, by id or by name.
function Printing.jobForProvider(pjob)
	if pjob == nil then return nil end
	local j = pjob.jobId and Store.job(pjob.jobId) or nil
	if j then return j end
	local name = U.upper(pjob.name or "")
	if name == "" then return nil end
	-- Only this printer's jobs; prefer the one already printing, then the
	-- next in line, then anything else not finished.
	local printerId = Store.activePrinter().id
	local rank = { PRINTING = 1, PAUSED = 1, QUEUED = 2, READY = 2, FAILED = 3, IDEA = 3 }
	local best, bestRank = nil, 99
	for _, cand in ipairs(Store.data.jobs) do
		if not cand.archived and cand.status ~= "COMPLETE" and cand.printerId == printerId
			and (U.upper(cand.name) == name or cand.printerJobName == name) then
			local r = rank[cand.status] or 9
			if r < bestRank then best, bestRank = cand, r end
		end
	end
	return best
end

-- A live printer may be running something the queue never sent (started
-- from the printer or the slicer). Adopt it so history stays complete.
function Printing.adoptExternalJob()
	local p = Printing.provider
	local st = p:getStatus().state
	if st ~= "PRINTING" and st ~= "HEATING" and st ~= "PAUSED" then return end
	local pjob = p:getCurrentJob()
	if pjob == nil then return end
	local printer = Store.activePrinter()
	local j = Printing.jobForProvider(pjob)
	if j == nil then
		local full = U.upper(pjob.name or "PRINTER JOB")
		j = Queue.add({ name = U.truncate(full, 28), material = pjob.material or "OTHER",
			color = pjob.color or "", status = "PRINTING", printerId = printer.id, notes = "Started on the printer.",
			estGrams = pjob.grams or 0 })
		j.source = "printer"
		-- Matching key: the printer's own name for the job, untruncated.
		j.printerJobName = full
		j.startedAt = Clock.now()
		j.attempts = 1
		Printing.log("ADOPTED " .. j.name)
	end
	if j.status ~= "PRINTING" and j.status ~= "PAUSED" then
		j.status = st == "PAUSED" and "PAUSED" or "PRINTING"
		if j.startedAt == 0 then j.startedAt = Clock.now() end
		Store.markDirty()
	end
end

function Printing.handle(ev)
	if ev.type == "log" then
		Printing.log(ev.text)
	elseif ev.type == "state" then
		local j = Printing.currentJob()
		if j then
			if ev.to == "PAUSED" and j.status == "PRINTING" then j.status = "PAUSED" end
			if (ev.to == "PRINTING" or ev.to == "HEATING") and j.status == "PAUSED" then j.status = "PRINTING" end
			Store.markDirty()
		end
		Events.emit("printer.state", { from = ev.from, to = ev.to })
	elseif ev.type == "complete" then
		local j = Printing.jobForProvider({ jobId = ev.jobId, name = ev.name }) or Printing.currentJob()
		-- Never record the same attempt twice (e.g. it was marked done by hand).
		if j and j.status == "COMPLETE" and j.completedAt >= j.startedAt then j = nil end
		if j then
			Printing.finish(j, "success", {
				durationSec = ev.durationSec, grams = (ev.grams and ev.grams > 0) and ev.grams or nil,
				preConsumed = ev.preConsumed, nozzleTemp = ev.nozzle, bedTemp = ev.bed,
				layer = ev.layers, progress = 1,
			})
		end
	elseif ev.type == "failed" then
		local j = Printing.jobForProvider({ jobId = ev.jobId, name = ev.name }) or Printing.currentJob()
		-- Only one failure can wait for a cause; an older one (from another
		-- printer) is logged with what we know so it isn't lost.
		local old = Store.data.pendingFailure
		if old and old.jobId ~= (j and j.id) then
			local oj = old.jobId and Store.job(old.jobId)
			if oj then
				Printing.finish(oj, old.cancelled and "cancelled" or "failed", {
					cause = old.cause or "unknown", notes = "Auto-logged: another failure arrived.",
					grams = old.grams, preConsumed = old.preConsumed, progress = old.progress,
					layer = old.layer, durationSec = old.durationSec, nozzleTemp = old.nozzleTemp, bedTemp = old.bedTemp,
				})
			end
			Store.data.pendingFailure = nil
		end
		Store.data.pendingFailure = {
			jobId = j and j.id or nil, printerId = Store.activePrinter().id,
			reason = ev.reason or "FAILED", cause = ev.cause,
			cancelled = ev.cancelled == true, progress = ev.progress or 0, layer = ev.layer or 0,
			durationSec = ev.durationSec or 0,
			-- Bridges often can't report grams: nil means "estimate from progress".
			grams = (ev.grams and ev.grams > 0) and ev.grams or nil,
			preConsumed = ev.preConsumed or 0,
			nozzleTemp = ev.nozzle or 0, bedTemp = ev.bed or 0, at = Clock.now(),
		}
		if j then j.status = "FAILED" end
		Store.markDirty()
		Store.save(true)
		Events.emit("print.error", { job = j, pending = Store.data.pendingFailure })
	elseif ev.type == "online" then
		-- A bridge just reported in: now we can tell what's really printing.
		Printing.reconcile()
	elseif ev.type == "lost" then
		-- The printer went idle without us seeing how the job ended.
		local j = Printing.jobForProvider({ jobId = ev.jobId, name = ev.name }) or Printing.currentJob()
		if j and (j.status == "PRINTING" or j.status == "PAUSED") then
			j.status = "QUEUED"
			Printing.log(j.name .. " ENDED OFF THE RECORD")
			Store.markDirty()
			Events.emit("print.lost", { job = j })
		end
	elseif ev.type == "runout" then
		Store.data.runout = { jobId = ev.jobId, layer = ev.layer, progress = ev.progress, at = Clock.now() }
		Store.markDirty()
		Events.emit("print.runout", { runout = Store.data.runout })
	end
end

function Printing.currentJob()
	return Queue.current(Store.activePrinter().id)
end

function Printing.pendingFailure()
	return Store.data.pendingFailure
end

-- Combined view of the active printer for the screens.
function Printing.snapshot()
	local p = Printing.provider
	local status = p:getStatus()
	local pjob = p:getCurrentJob()
	local qjob = Printing.currentJob() or Printing.jobForProvider(pjob)
	local spool = nil
	local spoolId = (pjob and pjob.spoolId) or (qjob and qjob.spoolId)
	if spoolId then spool = Store.spool(spoolId) end
	return {
		state = status.state,
		online = status.online,
		message = status.message or "",
		temps = p:getTemperatures(),
		progress = p:getProgress(),
		pjob = pjob,
		job = qjob,
		spool = spool,
		printer = Store.activePrinter(),
		caps = p:capabilities(),
		runout = Store.data.runout,
		pending = Store.data.pendingFailure,
	}
end

---------------------------------------------------------------------------
-- commands

function Printing.canStart(j)
	if not Job.isStartable(j) then return false, "JOB NOT READY" end
	local pf = Store.data.pendingFailure
	if pf and (pf.printerId == nil or pf.printerId == Store.activePrinter().id) then
		return false, "LOG LAST FAILURE FIRST"
	end
	local p = Printing.provider
	if not p:capabilities().start then return false, "PRINTER CAN'T START JOBS" end
	local st = p:getStatus().state
	if st == "PRINTING" or st == "HEATING" or st == "PAUSED" then return false, "PRINTER BUSY" end
	if j.printerId ~= Store.activePrinter().id then return false, "JOB IS FOR ANOTHER PRINTER" end
	return true
end

function Printing.start(j)
	local ok, err = Printing.canStart(j)
	if not ok then return false, err end
	local p = Printing.provider
	if p:getStatus().state == "COMPLETE" then p:acknowledge() end
	Queue.applyProfile(j)
	j.attempts = j.attempts + 1
	local spec = {
		jobId = j.id, name = j.name, material = j.material, color = j.color, spoolId = j.spoolId,
		grams = j.estGrams, minutes = j.estMinutes, layers = j.layers, nozzle = j.nozzleTemp,
		bed = j.bedTemp, shape = j.shape, model = j.model, attempt = j.attempts, printerId = j.printerId,
	}
	ok, err = p:startJob(spec)
	if not ok then
		j.attempts = j.attempts - 1
		return false, err
	end
	j.status = "PRINTING"
	j.startedAt = Clock.now()
	j.completedAt = 0
	Store.markDirty()
	Printing.drain()
	Events.emit("print.started", { job = j })
	return true
end

-- Commands drain provider events right away so the queue reflects the new
-- state in the same frame.
local function command(fn)
	local ok, err = fn(Printing.provider)
	Printing.drain()
	return ok, err
end

function Printing.pause() return command(function(p) return p:pause() end) end

function Printing.resume()
	local ok, err = command(function(p) return p:resume() end)
	if ok and Store.data.runout then
		Store.data.runout = nil
		Store.markDirty()
	end
	return ok, err
end

function Printing.cancel() return command(function(p) return p:cancel() end) end

-- Runout recovery: the old spool is empty (consume what was left), load a
-- new one and remember how much of the job is already accounted for.
function Printing.swapSpool(newSpoolId)
	local p = Printing.provider
	local pjob = p:getCurrentJob()
	local j = Printing.currentJob()
	if pjob == nil or j == nil then return false, "NO JOB" end
	local old = pjob.spoolId and Store.spool(pjob.spoolId) or nil
	local already = 0
	if p.st then already = p.st.consumed or 0 end
	if old and old.remainingGrams > 0 and Store.settings().autoConsume then
		already = already + old.remainingGrams
		Filament.consume(old.id, old.remainingGrams, "print", j.id, j.name .. " (RUNOUT)")
	end
	if p.swapSpool then p:swapSpool(newSpoolId, already) end
	j.spoolId = newSpoolId
	local s = Store.spool(newSpoolId)
	if s then
		Printing.log("LOADED " .. Spool.shortLabel(s))
	end
	Store.markDirty()
	return true
end

-- Clear a finished/failed plate on the printer.
function Printing.acknowledge()
	Printing.provider:acknowledge()
	Store.data.runout = nil
	Store.markDirty()
end

-- The user logged the cause of a pending failure (or declared a cancel).
-- details: { cause, notes, grams, asCancel }
function Printing.resolvePending(details)
	local pf = Store.data.pendingFailure
	if pf == nil then return nil end
	local j = pf.jobId and Store.job(pf.jobId) or nil
	local rec = nil
	if j then
		rec = Printing.finish(j, details.asCancel and "cancelled" or "failed", {
			cause = details.cause or pf.cause or "unknown",
			notes = details.notes or "",
			grams = details.grams or pf.grams,
			preConsumed = pf.preConsumed,
			progress = pf.progress, layer = pf.layer, durationSec = pf.durationSec,
			nozzleTemp = pf.nozzleTemp, bedTemp = pf.bedTemp,
		})
	end
	Store.data.pendingFailure = nil
	Store.data.runout = nil
	if pf.printerId == nil or pf.printerId == Store.activePrinter().id then
		Printing.acknowledge()
	end
	Store.save(true)
	return rec
end

-- The transaction. outcome: "success" | "failed" | "cancelled".
-- d: { grams, preConsumed, durationSec, progress, layer, cause, notes,
--      nozzleTemp, bedTemp, manual }
function Printing.finish(j, outcome, d)
	d = d or {}
	local now = Clock.now()
	local printer = Store.printer(j.printerId) or Store.activePrinter()
	local spool = j.spoolId and Store.spool(j.spoolId) or nil
	local progress = d.progress or (outcome == "success" and 1 or 0.5)

	-- 1. Filament.
	local grams = d.grams
	if grams == nil then
		if outcome == "success" then grams = j.estGrams else grams = j.estGrams * progress end
	end
	grams = math.max(0, grams)
	local toConsume = math.max(0, grams - (d.preConsumed or 0))
	if spool and Store.settings().autoConsume and toConsume > 0 then
		Filament.consume(spool.id, toConsume, outcome == "success" and "print" or "failed", j.id, j.name)
	end

	-- 2. Spool counters.
	if spool then
		if outcome == "success" then
			spool.successCount = spool.successCount + 1
			if spool.favNozzle == 0 and (d.nozzleTemp or j.nozzleTemp) > 0 then
				spool.favNozzle = U.roundInt(d.nozzleTemp or j.nozzleTemp)
				spool.favBed = U.roundInt(d.bedTemp or j.bedTemp)
			end
		elseif outcome == "failed" then
			spool.failCount = spool.failCount + 1
		end
	end

	-- 3. History.
	local duration = d.durationSec
	if duration == nil or duration <= 0 then
		duration = math.floor(j.estMinutes * 60 * progress)
	end
	local h = History.new({
		id = Store.newId("h"), jobId = j.id, jobName = j.name, project = j.project,
		printerId = printer.id, spoolId = spool and spool.id or "",
		material = spool and spool.material or j.material,
		manufacturer = spool and spool.manufacturer or "GENERIC",
		color = spool and spool.color or j.color,
		outcome = outcome, cause = outcome == "failed" and (d.cause or "unknown") or "",
		notes = d.notes or "", startedAt = j.startedAt > 0 and j.startedAt or (now - duration),
		endedAt = now, durationSec = duration, grams = grams, progress = progress,
		layer = d.layer or 0,
		nozzleTemp = U.roundInt(d.nozzleTemp and d.nozzleTemp > 0 and d.nozzleTemp or j.nozzleTemp),
		bedTemp = U.roundInt(d.bedTemp and d.bedTemp > 0 and d.bedTemp or j.bedTemp),
		profileKey = j.profileKey,
	})
	local hist = Store.data.history
	hist[#hist + 1] = h
	while #hist > 500 do table.remove(hist, 1) end

	-- 4. Printer statistics + maintenance odometer.
	local hoursBefore = Printer.hours(printer)
	local ps = printer.stats
	ps.prints = ps.prints + 1
	ps.printSeconds = ps.printSeconds + duration
	ps.grams = ps.grams + grams
	ps.lastPrintAt = now
	if outcome == "success" then
		ps.successes = ps.successes + 1
		ps.streak = ps.streak >= 0 and ps.streak + 1 or 1
	elseif outcome == "failed" then
		ps.failures = ps.failures + 1
		ps.streak = ps.streak <= 0 and ps.streak - 1 or -1
	end

	-- 5. Job.
	if outcome == "success" then
		j.status = "COMPLETE"
		j.completedAt = now
	elseif outcome == "failed" then
		j.status = "FAILED"
	else
		j.status = "QUEUED"
	end
	j.lastHistoryId = h.id
	-- One attempt, one record: logging this job by hand settles any
	-- failure the printer reported for it.
	local pf = Store.data.pendingFailure
	if pf and pf.jobId == j.id then
		Store.data.pendingFailure = nil
		if pf.printerId == nil or pf.printerId == Store.activePrinter().id then
			Printing.provider:acknowledge()
		end
	end

	Printing.log(j.name .. (outcome == "success" and " LOGGED COMPLETE" or (outcome == "failed" and (" FAILED: " .. (Enums.CAUSE_LABEL[h.cause] or "?")) or " CANCELLED")))
	Store.markDirty()

	-- 6. Ripple out: maintenance crossings, then everyone else via events.
	local crossed = MaintService.checkCrossings(printer.id, hoursBefore, now)
	Events.emit("print.finished", { job = j, history = h, outcome = outcome, spool = spool,
		printer = printer, maintCrossed = crossed })
	Store.save(true)
	return h
end

-- Manual logging for prints done without a connected printer.
function Printing.markComplete(j, d)
	d = d or {}
	if d.durationSec == nil then d.durationSec = j.estMinutes * 60 end
	d.manual = true
	return Printing.finish(j, "success", d)
end

function Printing.markFailed(j, cause, notes, grams, progress)
	return Printing.finish(j, "failed", { cause = cause, notes = notes, grams = grams,
		progress = progress or 0.5, manual = true })
end

-- True when the queue must not offer manual MARK COMPLETE/FAILED: the job
-- is (or may still be) on a printer, active or not. Use RETURN TO QUEUE to
-- take a stuck job back by hand.
function Printing.isBusy(j)
	return j.status == "PRINTING" or j.status == "PAUSED"
end

-- True when j is the job physically on the active provider right now.
function Printing.isLive(j)
	local p = Printing.provider
	if not p:capabilities().live then return false end
	local st = p:getStatus().state
	if st ~= "PRINTING" and st ~= "HEATING" and st ~= "PAUSED" then return false end
	local running = Printing.jobForProvider(p:getCurrentJob())
	return running ~= nil and running.id == j.id
end
