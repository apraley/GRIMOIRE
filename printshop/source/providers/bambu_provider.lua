-- BambuProvider: Bambu Lab printers (primary target: A1 Mini).
--
-- STATUS OF DIRECT INTEGRATION: not implemented, deliberately.
-- Bambu printers in LAN mode publish a JSON report over MQTT on TLS port 8883
-- (topic device/<serial>/report, user "bblp", password = LAN access code)
-- and accept commands on device/<serial>/request. The certificate is
-- self-signed, and the Playdate SDK offers no way to pin or trust a custom
-- certificate on its TLS sockets, and there is no MQTT client in the SDK.
-- Rather than pretend, this adapter reads the *raw* Bambu report relayed by
-- the companion bridge (GET /api/v1/bambu/report) and maps Bambu's field
-- names onto the PrinterProvider interface. Commands are forwarded as Bambu
-- request payloads through the bridge (POST /api/v1/bambu/command).
--
-- The mapping (BambuProvider.mapReport) is pure and unit-tested, so it is
-- the part to extend as Bambu firmware adds fields.

BambuProvider = setmetatable({}, { __index = LocalBridgeProvider })
BambuProvider.__index = BambuProvider

function BambuProvider.new(printer)
	local p = setmetatable({}, BambuProvider)
	p:init(printer)
	return p
end

function BambuProvider:kind() return "bambu" end
function BambuProvider:label() return "BAMBU VIA BRIDGE" end

function BambuProvider:statusPath()
	return "/api/v1/bambu/report"
end

-- gcode_state values seen on current firmware.
BambuProvider.STATE_MAP = {
	IDLE = "IDLE",
	PREPARE = "HEATING",
	SLICING = "HEATING",
	RUNNING = "PRINTING",
	PAUSE = "PAUSED",
	FINISH = "COMPLETE",
	FAILED = "ERROR",
	INIT = "IDLE",
	OFFLINE = "OFFLINE",
}

-- Bambu tray_type strings -> our materials.
local function material(trayType)
	trayType = U.upper(trayType or "")
	for _, m in ipairs(Enums.MATERIALS) do
		if string.find(trayType, m, 1, true) == 1 then return m end
	end
	if trayType == "" then return "" end
	return "OTHER"
end

-- Converts a Bambu `print` report object into the bridge schema consumed
-- by LocalBridgeProvider:ingest. `doc` may be the full MQTT payload
-- ({ print = {...} }) or the inner object.
function BambuProvider.mapReport(doc)
	local r = doc.print or doc
	-- No gcode_state yet (bridge just restarted, MQTT not in) is "unknown",
	-- not IDLE: IDLE would look like the print vanished.
	if type(r) ~= "table" then r = {} end
	local state = BambuProvider.STATE_MAP[U.upper(tostring(r.gcode_state or ""))] or "OFFLINE"
	-- Heating shows up as RUNNING with stage "heating" on some firmware.
	local stg = tonumber(r.stg_cur)
	if state == "PRINTING" and (stg == 2 or stg == 7) then state = "HEATING" end
	local remainingMin = U.num(r.mc_remaining_time, 0)
	local pct = U.num(r.mc_percent, 0)
	local elapsed = 0
	if pct > 0 and pct < 100 and remainingMin > 0 then
		elapsed = math.floor(remainingMin * 60 * pct / (100 - pct))
	end
	local name = r.subtask_name or r.gcode_file or ""
	name = string.gsub(tostring(name), "%.gcode%.3mf$", "")
	name = string.gsub(name, "%.3mf$", "")
	name = string.gsub(name, "%.gcode$", "")

	local slots, active = {}, nil
	local ams = r.ams
	if type(ams) == "table" and type(ams.ams) == "table" then
		local unit = ams.ams[1]
		if type(unit) == "table" and type(unit.tray) == "table" then
			for i, tray in ipairs(unit.tray) do
				if type(tray) == "table" then
					slots[#slots + 1] = {
						slot = (tonumber(tray.id) or (i - 1)) + 1,
						material = material(tray.tray_type),
						color = tostring(tray.tray_color or ""),
						pct = U.clamp(U.num(tray.remain, 0), 0, 100),
					}
				end
			end
		end
		local now = tonumber(ams.tray_now)
		if now and now < 254 then active = now + 1 end
	end
	local mode = #slots > 0 and "ams" or "external"
	if mode == "external" and type(r.vt_tray) == "table" then
		slots[1] = { slot = 1, material = material(r.vt_tray.tray_type), color = r.vt_tray.tray_color or "", pct = 0 }
		active = 1
	end

	local message = ""
	local err = U.int(r.print_error, 0)
	if err ~= 0 then message = string.format("ERROR %08X", err) end
	if state == "ERROR" and message == "" then message = "PRINT FAILED" end

	local activeMat = active and slots[active] and slots[active].material or ""
	return {
		schema = 1,
		state = state,
		message = message,
		temps = {
			nozzle = U.num(r.nozzle_temper, 0), nozzleTarget = U.num(r.nozzle_target_temper, 0),
			bed = U.num(r.bed_temper, 0), bedTarget = U.num(r.bed_target_temper, 0),
		},
		progress = {
			pct = pct, layer = U.int(r.layer_num, 0), totalLayers = U.int(r.total_layer_num, 0),
			elapsedSec = elapsed, remainingSec = math.floor(remainingMin * 60),
		},
		job = name ~= "" and { name = name, material = activeMat ~= "" and activeMat or "OTHER", grams = 0 } or nil,
		spools = { mode = mode, active = active, slots = slots },
	}
end

function BambuProvider:normalize(doc)
	return LocalBridgeProvider.normalize(self, BambuProvider.mapReport(doc))
end

local seq = 0
local function request(command, extra)
	seq = seq + 1
	local p = { sequence_id = tostring(seq), command = command }
	for k, v in pairs(extra or {}) do p[k] = v end
	return { print = p }
end

function BambuProvider:bambuCommand(command)
	return self:post("/api/v1/bambu/command", json.encode(request(command)), U.upper(command))
end

function BambuProvider:pause() return self:bambuCommand("pause") end
function BambuProvider:resume() return self:bambuCommand("resume") end
function BambuProvider:cancel() return self:bambuCommand("stop") end

-- Starting a print on a Bambu requires the sliced .3mf on the printer's
-- storage (uploaded by Bambu Studio/Handy or FTPS). Start it on the printer;
-- PRINT SHOP will pick it up and match it to the queue by name.
function BambuProvider:startJob()
	return false, "START ON PRINTER; SHOP WILL FOLLOW"
end

BambuProvider.buildCommand = request
