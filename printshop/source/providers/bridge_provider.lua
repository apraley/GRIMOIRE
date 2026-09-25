-- LocalBridgeProvider: talks HTTP+JSON to a companion service on your LAN
-- (see bridge/printshop_bridge.py and docs/BRIDGE.md for the schema).
--
-- Why a bridge: printers such as the Bambu Lab A1 Mini speak MQTT over TLS
-- with a self-signed certificate and a LAN access code. That is a job for a
-- small program on a computer or Raspberry Pi; the Playdate polls it with
-- the SDK's playdate.network.http API (SDK 2.7+). On older OS versions, or
-- when no host is configured, the provider reports OFFLINE with a reason and
-- the rest of PRINT SHOP keeps working from local data.
--
-- The provider derives complete/failed events itself from state
-- transitions, so a bridge only has to report current status.

LocalBridgeProvider = PrinterProvider.extend({})

LocalBridgeProvider.POLL_MS = 3000
LocalBridgeProvider.TIMEOUT_MS = 8000
LocalBridgeProvider.STATUS_PATH = "/api/v1/status"

function LocalBridgeProvider.new(printer)
	local p = setmetatable({}, LocalBridgeProvider)
	p:init(printer)
	return p
end

function LocalBridgeProvider:init(printer)
	PrinterProvider.init(self, printer)
	self.status = { state = "OFFLINE", online = false, message = "CONNECTING..." }
	self.temps = { nozzle = 0, nozzleTarget = 0, bed = 0, bedTarget = 0 }
	self.progress = { pct = 0, layer = 0, totalLayers = 0, elapsedSec = 0, remainingSec = 0 }
	self.job = nil
	self.spools = { mode = "unknown", active = nil, slots = {} }
	self.pollMs = LocalBridgeProvider.POLL_MS -- poll immediately
	self.inflight = nil
	self.lastState = nil
	self.failures = 0
	self.lastEventSeq = 0
end

function LocalBridgeProvider:kind() return "bridge" end
function LocalBridgeProvider:label() return "LOCAL BRIDGE" end

function LocalBridgeProvider:capabilities()
	return { live = true, control = self.status.online, start = false, ams = true, simulated = false }
end

function LocalBridgeProvider:networkAvailable()
	return playdate.network ~= nil and playdate.network.http ~= nil
end

function LocalBridgeProvider:host()
	return self.printer and self.printer.host or ""
end

---------------------------------------------------------------------------
-- HTTP plumbing: one request in flight, body accumulated from callbacks.

function LocalBridgeProvider:request(method, path, body, onDone)
	if self.inflight then return false, "BUSY" end
	if not self:networkAvailable() then return false, "NO NETWORK API (NEEDS OS 2.7+)" end
	local host = self:host()
	if host == "" then return false, "SET BRIDGE HOST IN SETTINGS" end

	local port = self.printer.port or 8787
	local conn = playdate.network.http.new(host, port, false, "PRINT SHOP reads printer status from your local bridge.")
	if conn == nil then return false, "NETWORK ACCESS DENIED" end
	local req = { conn = conn, buf = {}, started = Clock.ms(), done = false, onDone = onDone }
	self.inflight = req

	local function finish(err)
		if req.done then return end
		req.done = true
		local text = table.concat(req.buf)
		local status = conn:getResponseStatus()
		pcall(conn.close, conn)
		if self.inflight == req then self.inflight = nil end
		if err == nil and (status == nil or status < 200 or status >= 300) then
			err = "HTTP " .. tostring(status)
		end
		local data = nil
		if err == nil then
			local ok, decoded = pcall(json.decode, text)
			if ok and type(decoded) == "table" then data = decoded else err = "BAD JSON" end
		end
		onDone(data, err)
	end

	conn:setConnectTimeout(4)
	conn:setRequestCallback(function()
		local n = conn:getBytesAvailable()
		if n and n > 0 then req.buf[#req.buf + 1] = conn:read(n) end
	end)
	conn:setRequestCompleteCallback(function()
		local n = conn:getBytesAvailable()
		if n and n > 0 then req.buf[#req.buf + 1] = conn:read(n) end
		finish(conn:getError())
	end)
	conn:setConnectionClosedCallback(function()
		finish(conn:getError())
	end)

	local ok, err
	if method == "GET" then
		ok, err = conn:get(path, { Accept = "application/json" })
	else
		ok, err = conn:post(path, { ["Content-Type"] = "application/json" }, body or "{}")
	end
	if not ok then
		self.inflight = nil
		pcall(conn.close, conn)
		return false, err or "REQUEST FAILED"
	end
	return true
end

---------------------------------------------------------------------------
-- polling

function LocalBridgeProvider:update(dtMs)
	if self.inflight then
		if Clock.ms() - self.inflight.started > LocalBridgeProvider.TIMEOUT_MS then
			local req = self.inflight
			self.inflight = nil
			req.done = true
			pcall(req.conn.close, req.conn)
			self:markOffline("TIMEOUT")
		end
		return
	end
	self.pollMs = self.pollMs + dtMs
	-- Back off while offline so we don't hammer the radio.
	local interval = LocalBridgeProvider.POLL_MS * math.min(8, 1 + self.failures)
	if self.pollMs < interval then return end
	self.pollMs = 0
	local ok, err = self:request("GET", self:statusPath(), nil, function(data, e)
		if e then self:markOffline(e) else self:ingest(data) end
	end)
	if not ok then self:markOffline(err) end
end

function LocalBridgeProvider:statusPath()
	return LocalBridgeProvider.STATUS_PATH
end

function LocalBridgeProvider:markOffline(reason)
	self.failures = self.failures + 1
	self.status = { state = "OFFLINE", online = false, message = U.upper(tostring(reason or "OFFLINE")) }
end

-- Applies a normalized status document (docs/BRIDGE.md, schema 1).
function LocalBridgeProvider:ingest(doc)
	local norm = self:normalize(doc)
	self.failures = 0
	self.status = { state = norm.state, online = true, message = norm.message or "" }
	self.temps = norm.temps
	self.progress = norm.progress
	self.job = norm.job
	self.spools = norm.spools
	self:sampleTemps()
	for _, ev in ipairs(norm.events or {}) do
		if (ev.seq or 0) > self.lastEventSeq and ev.type == "log" then
			self.lastEventSeq = ev.seq or self.lastEventSeq
			self:emit({ type = "log", text = U.upper(tostring(ev.text or "")) })
		end
	end
	self:deriveEvents(norm.state)
end

-- Translate state transitions into the provider event vocabulary.
function LocalBridgeProvider:deriveEvents(state)
	local prev = self.lastState
	self.lastState = state
	if prev == nil or prev == state then return end
	self:emit({ type = "state", from = prev, to = state })
	local j = self.job or {}
	local p = self.progress
	local wasActive = prev == "PRINTING" or prev == "PAUSED" or prev == "HEATING"
	if wasActive and state == "COMPLETE" then
		self:emit({ type = "complete", jobId = j.jobId, name = j.name, durationSec = p.elapsedSec,
			grams = j.grams, layers = p.totalLayers, nozzle = self.temps.nozzleTarget, bed = self.temps.bedTarget })
	elseif wasActive and state == "ERROR" then
		self:emit({ type = "failed", jobId = j.jobId, name = j.name, reason = self.status.message,
			progress = p.pct / 100, layer = p.layer, durationSec = p.elapsedSec,
			grams = (j.grams or 0) * p.pct / 100, nozzle = self.temps.nozzleTarget, bed = self.temps.bedTarget })
	end
end

local function numOr(v, d) return U.num(v, d) end

-- Bridge schema 1 -> provider tables. Subclasses override for other shapes.
function LocalBridgeProvider:normalize(doc)
	local t = doc.temps or {}
	local pr = doc.progress or {}
	local job = nil
	if type(doc.job) == "table" and doc.job.name then
		job = { jobId = doc.job.id, name = U.upper(tostring(doc.job.name)), material = doc.job.material or "OTHER",
			color = U.upper(doc.job.color or ""), grams = numOr(doc.job.grams, 0) }
	end
	local slots = {}
	local sp = doc.spools or {}
	for i, s in ipairs(sp.slots or {}) do
		slots[#slots + 1] = { slot = s.slot or i, material = s.material or "", color = s.color or "", pct = numOr(s.pct, 0) }
	end
	return {
		state = U.oneOf(doc.state, Enums.PRINTER_STATES, "OFFLINE"),
		message = doc.message and U.upper(tostring(doc.message)) or "",
		temps = { nozzle = numOr(t.nozzle, 0), nozzleTarget = numOr(t.nozzleTarget, 0),
			bed = numOr(t.bed, 0), bedTarget = numOr(t.bedTarget, 0) },
		progress = { pct = U.clamp(numOr(pr.pct, 0), 0, 100), layer = U.int(pr.layer, 0),
			totalLayers = U.int(pr.totalLayers, 0), elapsedSec = U.int(pr.elapsedSec, 0),
			remainingSec = U.int(pr.remainingSec, 0) },
		job = job,
		spools = { mode = sp.mode or "external", active = sp.active, slots = slots },
		events = doc.events,
	}
end

function LocalBridgeProvider:getStatus() return self.status end
function LocalBridgeProvider:getTemperatures() return self.temps end
function LocalBridgeProvider:getProgress() return self.progress end
function LocalBridgeProvider:getCurrentJob() return self.job end
function LocalBridgeProvider:getAMSOrSpoolState() return self.spools end

function LocalBridgeProvider:command(name, payload)
	if not self.status.online then return false, "BRIDGE OFFLINE" end
	local ok, err = self:request("POST", "/api/v1/" .. name, payload and json.encode(payload) or "{}", function(_, e)
		if e then self:emit({ type = "log", text = U.upper(name) .. " FAILED: " .. e })
		else self:emit({ type = "log", text = U.upper(name) .. " SENT" }) end
	end)
	return ok, err
end

function LocalBridgeProvider:pause() return self:command("pause") end
function LocalBridgeProvider:resume() return self:command("resume") end
function LocalBridgeProvider:cancel() return self:command("cancel") end

-- Starting jobs remotely needs the sliced file on the printer; bridges may
-- support it (schema: POST /api/v1/start {jobId,name,file}), most won't.
function LocalBridgeProvider:startJob(spec)
	if not self.status.online then return false, "BRIDGE OFFLINE" end
	return self:command("start", { jobId = spec.jobId, name = spec.name, file = spec.model })
end

function LocalBridgeProvider:acknowledge() end

function LocalBridgeProvider:shutdown()
	if self.inflight then
		pcall(self.inflight.conn.close, self.inflight.conn)
		self.inflight = nil
	end
end

function LocalBridgeProvider:serialize()
	return { lastState = self.lastState, lastEventSeq = self.lastEventSeq }
end

function LocalBridgeProvider:restore(state)
	-- lastState is not restored on purpose: a transition that happened while
	-- PRINT SHOP was closed is reported by the bridge's `events`, and
	-- re-deriving from a stale state could double-count a completion.
	self.lastEventSeq = U.int(state and state.lastEventSeq, 0)
end
