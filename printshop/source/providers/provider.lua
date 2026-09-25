-- PrinterProvider: the adapter boundary between PRINT SHOP and a machine.
--
-- Every provider implements this interface. Screens and services only talk
-- to providers through it, so adding a new printer family means writing one
-- file here, not touching the UI.
--
--   getStatus()          -> { state, online, message }
--                           state is one of Enums.PRINTER_STATES
--   getTemperatures()    -> { nozzle, nozzleTarget, bed, bedTarget }
--   getProgress()        -> { pct 0..100, layer, totalLayers, elapsedSec, remainingSec }
--   getCurrentJob()      -> { jobId, name, material, color, spoolId, grams } | nil
--   getAMSOrSpoolState() -> { mode = "ams"|"external"|"unknown", active, slots = {
--                               { slot, material, color, pct, spoolId } } }
--   pause() / resume() / cancel()          -> ok, err
--   startJob(spec)       -> ok, err   spec = { jobId, name, material, color,
--                           spoolId, grams, minutes, layers, nozzle, bed, shape }
--   acknowledge()        clear a COMPLETE/ERROR screen back to IDLE
--   update(dtMs)         poll / simulate; called every frame
--   pollEvents()         drain queued events (see below)
--   serialize()/restore(state, awaySec)   persistence of provider state
--   capabilities()       -> { live, control, start, ams, simulated }
--
-- Events (tables with .type):
--   { type="state", from, to }            printer state changed
--   { type="log", text }                  human readable line for PRINT WATCH
--   { type="complete", jobId, durationSec, grams, layers, nozzle, bed }
--   { type="failed", jobId, reason, cause, progress, layer, durationSec, grams, nozzle, bed }
--   { type="runout", jobId, layer }       paused because the spool ran dry

PrinterProvider = {}
PrinterProvider.__index = PrinterProvider

function PrinterProvider.extend(child)
	child = child or {}
	child.__index = child
	return setmetatable(child, { __index = PrinterProvider })
end

function PrinterProvider.new(printer)
	local p = setmetatable({}, PrinterProvider)
	p:init(printer)
	return p
end

function PrinterProvider:init(printer)
	self.printer = printer
	self.events = {}
	self.tempHistory = {}   -- ring of {nozzle, bed} samples for graphs
end

function PrinterProvider:kind() return "none" end
function PrinterProvider:label() return "NO PROVIDER" end

function PrinterProvider:capabilities()
	return { live = false, control = false, start = false, ams = false, simulated = false }
end

function PrinterProvider:getStatus()
	return { state = "OFFLINE", online = false, message = "NOT CONNECTED" }
end

function PrinterProvider:getTemperatures()
	return { nozzle = 0, nozzleTarget = 0, bed = 0, bedTarget = 0 }
end

function PrinterProvider:getProgress()
	return { pct = 0, layer = 0, totalLayers = 0, elapsedSec = 0, remainingSec = 0 }
end

function PrinterProvider:getCurrentJob() return nil end

function PrinterProvider:getAMSOrSpoolState()
	return { mode = "unknown", active = nil, slots = {} }
end

function PrinterProvider:pause() return false, "NOT SUPPORTED" end
function PrinterProvider:resume() return false, "NOT SUPPORTED" end
function PrinterProvider:cancel() return false, "NOT SUPPORTED" end
function PrinterProvider:startJob() return false, "NOT SUPPORTED" end
function PrinterProvider:acknowledge() end
function PrinterProvider:update() end
function PrinterProvider:serialize() return {} end
function PrinterProvider:restore() end
function PrinterProvider:shutdown() end

function PrinterProvider:emit(ev)
	self.events[#self.events + 1] = ev
end

function PrinterProvider:pollEvents()
	local e = self.events
	self.events = {}
	return e
end

function PrinterProvider:sampleTemps()
	local t = self:getTemperatures()
	local h = self.tempHistory
	h[#h + 1] = { t.nozzle, t.bed }
	if #h > 48 then table.remove(h, 1) end
end
