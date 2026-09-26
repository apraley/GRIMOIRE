-- DemoProvider: a fully simulated printer, so PRINT SHOP is useful (and
-- fun) with no hardware at all.
--
-- The simulation is driven by shop data, not dice alone: damp spools string,
-- uncalibrated materials and a dirty bed lose adhesion, overdue belts shift
-- layers, and a spool with less filament than the job needs runs out
-- mid-print. Outcomes are seeded from the job id and attempt number, so a
-- given attempt always plays out the same way.
--
-- Time runs at settings.demoSpeed x real time, and a print keeps "running"
-- while PRINT SHOP is closed: restore() fast-forwards by the time away.

DemoProvider = PrinterProvider.extend({})

local AMBIENT = 24

function DemoProvider.new(printer, state)
	local p = setmetatable({}, DemoProvider)
	p:init(printer)
	p.st = {
		state = "IDLE", nozzle = AMBIENT, bed = AMBIENT, nozzleTarget = 0, bedTarget = 0,
		elapsedSec = 0, totalSec = 0, totalLayers = 0, heatSec = 0, grams = 0, consumed = 0,
	}
	p.rng = Rng.new(1234)
	p.sampleMs = 0
	if state then p:restore(state, 0) end
	return p
end

function DemoProvider:kind() return "demo" end
function DemoProvider:label() return "DEMO SIM" end

function DemoProvider:capabilities()
	return { live = true, control = true, start = true, ams = true, simulated = true }
end

local function speed()
	return (Store.data and Store.settings().demoSpeed) or 60
end

---------------------------------------------------------------------------
-- interface

function DemoProvider:getStatus()
	local st = self.st
	return { state = st.state, online = true, message = st.message or "" }
end

function DemoProvider:getTemperatures()
	local st = self.st
	return { nozzle = st.nozzle, nozzleTarget = st.nozzleTarget, bed = st.bed, bedTarget = st.bedTarget }
end

function DemoProvider:getProgress()
	local st = self.st
	if st.totalSec <= 0 then
		return { pct = 0, layer = 0, totalLayers = 0, elapsedSec = 0, remainingSec = 0 }
	end
	local frac = U.clamp(st.elapsedSec / st.totalSec, 0, 1)
	local layer = math.min(st.totalLayers, math.floor(frac * st.totalLayers) + (frac > 0 and 1 or 0))
	if st.state == "COMPLETE" then layer = st.totalLayers end
	return {
		pct = frac * 100,
		layer = layer,
		totalLayers = st.totalLayers,
		elapsedSec = math.floor(st.elapsedSec + st.heatSec),
		remainingSec = math.max(0, math.floor(st.totalSec - st.elapsedSec)),
	}
end

function DemoProvider:getCurrentJob()
	local st = self.st
	if st.jobId == nil then return nil end
	return { jobId = st.jobId, name = st.jobName, material = st.material, color = st.color,
		spoolId = st.spoolId, grams = st.grams, shape = st.shape }
end

-- The A1 Mini's AMS lite has four slots; spools whose Rolodex location is
-- "AMS LITE n" are loaded in slot n.
-- Built from the Rolodex; cached until the shop data or loaded spool changes
-- (the workshop scene asks for it every frame). Treat the result as read-only.
function DemoProvider:getAMSOrSpoolState()
	local c = self.amsCache
	if c and c.rev == (Memo and Memo.rev) and c.spoolId == self.st.spoolId then return c.value end
	local value = self:buildAMSState()
	self.amsCache = { rev = Memo and Memo.rev, spoolId = self.st.spoolId, value = value }
	return value
end

function DemoProvider:buildAMSState()
	local slots = {}
	if Store.data then
		for _, s in ipairs(Store.data.spools) do
			local n = tonumber(string.match(s.location or "", "^AMS LITE (%d)$"))
			if n and n >= 1 and n <= 4 and not s.archived then
				slots[n] = { slot = n, material = s.material, color = s.color, pct = Spool.pct(s) * 100, spoolId = s.id }
			end
		end
	end
	local list = {}
	local active = nil
	for i = 1, 4 do
		local sl = slots[i] or { slot = i, material = "", color = "", pct = 0 }
		list[i] = sl
		if sl.spoolId and sl.spoolId == self.st.spoolId then active = i end
	end
	return { mode = "ams", active = active, slots = list }
end

function DemoProvider:startJob(spec)
	local st = self.st
	if st.state == "HEATING" or st.state == "PRINTING" or st.state == "PAUSED" then
		return false, "PRINTER BUSY"
	end
	if st.state == "ERROR" then
		return false, "CLEAR ERROR FIRST"
	end
	local minutes = math.max(1, spec.minutes or 60)
	st.state = "HEATING"
	st.jobId = spec.jobId
	st.jobName = spec.name
	st.spoolId = spec.spoolId
	st.material = spec.material
	st.color = spec.color
	st.shape = spec.shape
	st.grams = spec.grams or 0
	st.consumed = 0
	st.totalSec = minutes * 60
	st.totalLayers = math.max(1, spec.layers or 100)
	st.elapsedSec = 0
	st.heatSec = 0
	st.nozzleTarget = spec.nozzle or 215
	st.bedTarget = spec.bed or 60
	st.message = "HEATING"
	st.seed = U.hash((spec.jobId or "x") .. ":" .. tostring(spec.attempt or 1))
	st.startedAt = Clock.now()
	self:planOutcome(spec)
	self:emit({ type = "log", text = U.upper(spec.name or "JOB") .. " SENT TO PRINTER" })
	self:setState("HEATING")
	return true
end

function DemoProvider:pause()
	local st = self.st
	if st.state ~= "PRINTING" and st.state ~= "HEATING" then return false, "NOT PRINTING" end
	st.resumeTo = st.state
	st.message = "PAUSED BY USER"
	self:setState("PAUSED")
	self:emit({ type = "log", text = "PAUSED" })
	return true
end

function DemoProvider:resume()
	local st = self.st
	if st.state ~= "PAUSED" then return false, "NOT PAUSED" end
	-- After a runout the spool must be swapped (swapSpool) before resuming.
	if st.runout then return false, "LOAD FILAMENT FIRST" end
	if st.needsReplan then
		st.needsReplan = false
		self:replanRunout()
	end
	st.message = ""
	self:setState(st.resumeTo or "PRINTING")
	self:emit({ type = "log", text = "RESUMED" })
	return true
end

function DemoProvider:cancel()
	local st = self.st
	if st.state ~= "PRINTING" and st.state ~= "HEATING" and st.state ~= "PAUSED" then
		return false, "NOTHING TO CANCEL"
	end
	local prog = self:getProgress()
	local nozzle, bed = st.nozzleTarget, st.bedTarget
	st.message = "CANCELLED"
	st.nozzleTarget, st.bedTarget = 0, 0
	st.runout = false
	self:emit({ type = "failed", jobId = st.jobId, reason = "CANCELLED", cause = nil, cancelled = true,
		progress = prog.pct / 100, layer = prog.layer, durationSec = prog.elapsedSec,
		grams = st.grams * prog.pct / 100, preConsumed = st.consumed,
		nozzle = nozzle, bed = bed })
	self:setState("ERROR")
	st.cancelled = true
	return true
end

-- User cleared the plate / dismissed the error.
function DemoProvider:acknowledge()
	local st = self.st
	if st.state == "COMPLETE" or st.state == "ERROR" then
		st.jobId = nil
		st.jobName = nil
		st.message = ""
		st.cancelled = nil
		st.totalSec, st.elapsedSec, st.heatSec = 0, 0, 0
		self:setState("IDLE")
	end
end

-- Runout recovery: the spool on the printer was swapped.
function DemoProvider:swapSpool(spoolId, consumedSoFar)
	local st = self.st
	st.runout = false
	st.needsReplan = true
	st.spoolId = spoolId
	st.consumed = consumedSoFar or st.consumed
	local s = Store.spool(spoolId)
	if s then
		st.material = s.material
		st.color = s.color
	end
end

---------------------------------------------------------------------------
-- simulation

function DemoProvider:setState(s)
	local from = self.st.state
	self.st.state = s
	if from ~= s then self:emit({ type = "state", from = from, to = s }) end
end

-- Decides, deterministically, whether and how this attempt fails.
function DemoProvider:planOutcome(spec)
	local st = self.st
	local rng = Rng.new(st.seed)
	st.failAt, st.failCause, st.failReason = nil, nil, nil
	st.runout, st.runoutAt = false, nil

	local risks = {}
	local function risk(cause, p, reason)
		risks[#risks + 1] = { cause = cause, weight = p, reason = reason }
	end
	local chaos = Store.data == nil or Store.settings().demoChaos
	if chaos then
		risk("unknown", 0.02, "PRINT DETACHED")
		local s = spec.spoolId and Store.spool(spec.spoolId) or nil
		if s then
			if s.dryness == "WET" then risk("stringing", 0.30, "HEAVY STRINGING")
			elseif s.dryness == "DAMP" then risk("stringing", 0.12, "STRINGING") end
			local total = s.successCount + s.failCount
			if total >= 4 then risk("unknown", 0.10 * s.failCount / total, "NOZZLE BLOB") end
		end
		local rec = CalService.recommend(spec.printerId, spec.material, s and s.manufacturer or nil)
		if rec.level == "default" then risk("adhesion", 0.08, "CORNER LIFTED") end
		if spec.material == "ABS" or spec.material == "ASA" then
			risk("adhesion", 0.15, "WARPING: NO ENCLOSURE")
		end
		if spec.material == "TPU" then risk("underext", 0.06, "TPU BUCKLED IN EXTRUDER") end
		if Store.data then
			for _, e in ipairs(MaintService.list(spec.printerId)) do
				if e.st.due then
					local k = e.task.kind
					if k == "bed_clean" then risk("adhesion", 0.10, "LOST BED ADHESION") end
					if k == "belts" then risk("layershift", 0.08, "LAYER SHIFT DETECTED") end
					if k == "nozzle" then risk("clog", 0.06, "EXTRUDER CLICKING: CLOG?") end
					if k == "lube" then risk("layershift", 0.03, "Z BINDING") end
					if k == "extruder_clean" then risk("underext", 0.05, "UNDER EXTRUSION") end
				end
			end
		end
		-- Spaghetti is the classic: a small chance on tall prints.
		if (spec.layers or 0) > 200 then risk("spaghetti", 0.05, "SPAGHETTI DETECTED") end
	end

	local total = 0
	for _, r in ipairs(risks) do total = total + r.weight end
	total = math.min(total, 0.6)
	if #risks > 0 and rng:next() < total then
		local r = rng:weighted(risks)
		st.failCause = r.cause
		st.failReason = r.reason
		-- Adhesion problems strike early; the rest anywhere.
		if r.cause == "adhesion" then st.failAt = 0.03 + rng:next() * 0.2
		else st.failAt = 0.1 + rng:next() * 0.8 end
	end
	self:replanRunout()
end

function DemoProvider:replanRunout()
	local st = self.st
	st.runoutAt = nil
	local s = st.spoolId and Store.data and Store.spool(st.spoolId) or nil
	if s == nil or st.grams <= 0 then return end
	local frac = st.totalSec > 0 and st.elapsedSec / st.totalSec or 0
	local stillNeeded = st.grams * (1 - frac)
	if s.remainingGrams < stillNeeded then
		st.runoutAt = frac + (s.remainingGrams / st.grams)
	end
end

local function approach(v, target, rate, dt)
	if v < target then return math.min(target, v + rate * dt) end
	return math.max(target, v - rate * dt)
end

local function cool(v, dt)
	-- Newtonian cooling toward ambient.
	return AMBIENT + (v - AMBIENT) * math.exp(-dt / 240)
end

-- Advances the simulation by simSec simulated seconds. Handles large steps
-- (fast-forward after the app was closed) without per-second loops.
function DemoProvider:step(simSec)
	local st = self.st
	local guard = 0
	while simSec > 0 and guard < 8 do
		guard = guard + 1
		local s = st.state
		if s == "HEATING" then
			local nNeed = math.abs(st.nozzleTarget - st.nozzle) / 4
			local bNeed = math.abs(st.bedTarget - st.bed) / 1.2
			local need = math.max(nNeed, bNeed)
			local dt = math.min(simSec, need)
			st.nozzle = approach(st.nozzle, st.nozzleTarget, 4, dt)
			st.bed = approach(st.bed, st.bedTarget, 1.2, dt)
			st.heatSec = st.heatSec + dt
			simSec = simSec - dt
			if dt >= need then
				st.nozzle, st.bed = st.nozzleTarget, st.bedTarget
				st.message = ""
				self:emit({ type = "log", text = "NOZZLE " .. st.nozzleTarget .. "C / BED " .. st.bedTarget .. "C REACHED" })
				self:setState("PRINTING")
			end
		elseif s == "PRINTING" then
			local frac = st.elapsedSec / st.totalSec
			local stop = 1
			local reason = "complete"
			if st.failAt and st.failAt < stop then stop, reason = st.failAt, "fail" end
			if st.runoutAt and st.runoutAt < stop then stop, reason = st.runoutAt, "runout" end
			local need = math.max(0, (stop - frac) * st.totalSec)
			local dt = math.min(simSec, need)
			local layerBefore = self:getProgress().layer
			st.elapsedSec = st.elapsedSec + dt
			simSec = simSec - dt
			local layerAfter = self:getProgress().layer
			self:layerLogs(layerBefore, layerAfter)
			if dt >= need then
				self:hitMilestone(reason)
			end
		else
			-- IDLE, PAUSED, ERROR, COMPLETE: only temperatures move.
			if s == "PAUSED" and not st.runout then
				st.nozzle = approach(st.nozzle, st.nozzleTarget, 4, simSec)
				st.bed = approach(st.bed, st.bedTarget, 1.2, simSec)
			else
				st.nozzle = cool(st.nozzle, simSec)
				st.bed = cool(st.bed, simSec)
			end
			simSec = 0
		end
	end
end

local QUARTILES <const> = { 0.25, 0.5, 0.75 }

function DemoProvider:layerLogs(before, after)
	local st = self.st
	if before < 2 and after >= 2 then
		self:emit({ type = "log", text = "FIRST LAYER DOWN" })
	end
	local total = st.totalLayers
	if after == before then return end
	for _, q in ipairs(QUARTILES) do
		local L = math.floor(total * q)
		if before < L and after >= L then
			self:emit({ type = "log", text = string.format("LAYER %d/%d (%d%%)", L, total, math.floor(q * 100)) })
		end
	end
end

function DemoProvider:hitMilestone(reason)
	local st = self.st
	local prog = self:getProgress()
	if reason == "complete" then
		st.elapsedSec = st.totalSec
		st.message = "PRINT COMPLETE"
		st.nozzleTarget, st.bedTarget = 0, 0
		self:setState("COMPLETE")
		self:emit({ type = "complete", jobId = st.jobId, durationSec = math.floor(st.totalSec + st.heatSec),
			grams = st.grams, preConsumed = st.consumed, layers = st.totalLayers,
			nozzle = st.nozzle, bed = st.bed })
		self:emit({ type = "log", text = U.upper(st.jobName or "JOB") .. " COMPLETE" })
	elseif reason == "fail" then
		st.message = st.failReason or "PRINT FAILED"
		local nozzle, bed = st.nozzleTarget, st.bedTarget
		st.nozzleTarget, st.bedTarget = 0, 0
		self:setState("ERROR")
		self:emit({ type = "failed", jobId = st.jobId, reason = st.message, cause = st.failCause,
			progress = prog.pct / 100, layer = prog.layer, durationSec = prog.elapsedSec,
			grams = st.grams * prog.pct / 100, preConsumed = st.consumed, nozzle = nozzle, bed = bed })
		self:emit({ type = "log", text = "ERROR: " .. st.message })
		st.failAt = nil
	elseif reason == "runout" then
		st.runout = true
		st.runoutAt = nil
		st.resumeTo = "PRINTING"
		st.message = "FILAMENT RUNOUT"
		self:setState("PAUSED")
		self:emit({ type = "runout", jobId = st.jobId, layer = prog.layer, progress = prog.pct / 100 })
		self:emit({ type = "log", text = "FILAMENT RUNOUT AT LAYER " .. prog.layer })
	end
end

function DemoProvider:update(dtMs)
	local simSec = dtMs / 1000 * speed()
	self:step(simSec)
	-- Temperature jitter so the gauges feel alive.
	local st = self.st
	if st.state == "PRINTING" then
		st.nozzle = st.nozzleTarget + (self.rng:next() - 0.5) * 1.6
		st.bed = st.bedTarget + (self.rng:next() - 0.5) * 0.6
	end
	self.sampleMs = self.sampleMs + dtMs
	if self.sampleMs >= 500 then
		self.sampleMs = 0
		self:sampleTemps()
	end
end

function DemoProvider:serialize()
	local s = U.copy(self.st)
	s.savedAt = Clock.now()
	return s
end

-- Restores saved state, then fast-forwards by the real seconds spent away.
function DemoProvider:restore(state, awaySec)
	for k, v in pairs(state) do self.st[k] = v end
	local st = self.st
	st.state = U.oneOf(st.state, Enums.PRINTER_STATES, "IDLE")
	st.elapsedSec = U.num(st.elapsedSec, 0)
	st.totalSec = U.num(st.totalSec, 0)
	st.heatSec = U.num(st.heatSec, 0)
	st.totalLayers = U.int(st.totalLayers, 0)
	st.nozzle = U.num(st.nozzle, AMBIENT)
	st.bed = U.num(st.bed, AMBIENT)
	st.nozzleTarget = U.num(st.nozzleTarget, 0)
	st.bedTarget = U.num(st.bedTarget, 0)
	st.grams = U.num(st.grams, 0)
	st.consumed = U.num(st.consumed, 0)
	if (st.state == "PRINTING" or st.state == "HEATING" or st.state == "PAUSED") and st.totalSec <= 0 then
		st.state = "IDLE"
	end
	if st.state == "PRINTING" and st.runoutAt == nil and st.failAt == nil then
		self:replanRunout()
	end
	if awaySec and awaySec > 0 then
		self:step(math.min(awaySec, 7 * U.DAY) * speed())
	end
end
