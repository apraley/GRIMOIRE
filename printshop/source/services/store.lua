-- Persistence. One JSON document in the Playdate datastore holds the whole
-- shop. Writes are debounced: services call Store.markDirty() and the store
-- flushes at most every AUTOSAVE_MS, plus immediately on lifecycle events
-- (terminate, sleep, lock) and after important transactions.
--
-- Load path:  read -> (missing? seed) -> (corrupt? backup + seed)
--             -> (older schema? backup + migrate) -> repair -> ready
-- A document from a *newer* app version is backed up, loaded best-effort
-- and opened READ-ONLY: saving it would downgrade the file.

Store = {
	FILE = "printshop",
	LIVE_FILE = "printshop-live",
	AUTOSAVE_MS = 4000,
	data = nil,
	dirty = false,
	sinceSave = 0,
	loadReport = {},
	readOnly = false,   -- set when the save came from a newer app version
	beforeSave = nil,   -- hook: flush live state (provider) into data
}

function Store.load()
	Store.readOnly = false
	local report = { seeded = false, migratedFrom = nil, backup = nil, newer = false }
	local raw = nil
	local ok, err = pcall(function() raw = playdate.datastore.read(Store.FILE) end)
	if not ok then
		print("PRINT SHOP: datastore read failed: " .. tostring(err))
		raw = nil
	end

	local data
	if raw == nil then
		data = Seed.build(Clock.now())
		report.seeded = true
	elseif type(raw) ~= "table" or (raw.schema == nil and raw.version == nil and raw.meta == nil) then
		-- Unrecognizable: keep a copy for forensic recovery, start fresh.
		report.backup = Store.FILE .. "-corrupt"
		pcall(playdate.datastore.write, type(raw) == "table" and raw or { value = tostring(raw) }, report.backup)
		data = Seed.build(Clock.now())
		report.seeded = true
	else
		local v = Schema.versionOf(raw)
		if v > Schema.CURRENT then
			report.newer = true
			Store.readOnly = true
			report.backup = Store.FILE .. "-v" .. v
			pcall(playdate.datastore.write, raw, report.backup)
			data = raw
		elseif v < Schema.CURRENT then
			report.backup = Store.FILE .. "-v" .. v
			pcall(playdate.datastore.write, raw, report.backup)
			local from
			data, from = Schema.migrate(raw)
			report.migratedFrom = from
		else
			data = raw
		end
	end

	Store.data = Schema.repair(data)
	Store.loadLive()
	if Memo then Memo.bump() end
	if Store.data.meta.createdAt == 0 then Store.data.meta.createdAt = Clock.now() end
	Store.loadReport = report
	Store.dirty = report.seeded or report.migratedFrom ~= nil
	return Store.data, report
end

function Store.markDirty()
	Store.dirty = true
	if Memo then Memo.bump() end
end

function Store.save(force)
	if Store.data == nil then return false end
	if Store.readOnly then return false end
	if not Store.dirty and not force then return true end
	if Store.beforeSave then Store.beforeSave() end
	local d = Store.data
	d.meta.savedAt = Clock.now()
	d.meta.saves = d.meta.saves + 1
	d.schema = Schema.CURRENT
	local ok, err = pcall(playdate.datastore.write, d, Store.FILE)
	if not ok then
		print("PRINT SHOP: save failed: " .. tostring(err))
		return false
	end
	Store.dirty = false
	Store.sinceSave = 0
	return true
end

-- Live printer state (provider progress, temps) changes constantly during a
-- print. Rewriting the whole shop document for it would stall the frame, so
-- it goes to a tiny side file instead. The main save still carries a copy;
-- on load, whichever copy is newer wins.
function Store.saveLive()
	if Store.data == nil or Store.readOnly then return false end
	if Store.beforeSave then Store.beforeSave() end
	local doc = { savedAt = Clock.now(), providerState = Store.data.providerState }
	local ok, err = pcall(playdate.datastore.write, doc, Store.LIVE_FILE)
	if not ok then print("PRINT SHOP: live save failed: " .. tostring(err)) end
	return ok
end

function Store.loadLive()
	local live
	pcall(function() live = playdate.datastore.read(Store.LIVE_FILE) end)
	if type(live) ~= "table" or type(live.providerState) ~= "table" then return end
	if U.int(live.savedAt, 0) > U.int(Store.data.meta.savedAt, 0) then
		Store.data.providerState = live.providerState
	end
end

function Store.update(dtMs)
	if not Store.dirty or Store.readOnly then return end
	Store.sinceSave = Store.sinceSave + dtMs
	if Store.sinceSave >= Store.AUTOSAVE_MS then
		Store.save()
	end
end

-- Hands out unique string ids like "j42".
function Store.newId(prefix)
	local m = Store.data.meta
	local id = prefix .. m.nextId
	m.nextId = m.nextId + 1
	return id
end

-- Erase everything and start from fresh seed data (Settings > RESET).
function Store.reset(emptyShop)
	Store.readOnly = false
	pcall(playdate.datastore.delete, Store.FILE)
	pcall(playdate.datastore.delete, Store.LIVE_FILE)
	if emptyShop then
		Store.data = Schema.repair(Seed.empty(Clock.now()))
	else
		Store.data = Schema.repair(Seed.build(Clock.now()))
	end
	Store.dirty = true
	if Memo then Memo.bump() end
	Store.save(true)
end

-- Convenience accessors ---------------------------------------------------

function Store.settings() return Store.data.settings end

function Store.activePrinter()
	local d = Store.data
	return (U.findById(d.printers, d.settings.activePrinterId)) or d.printers[1]
end

function Store.printer(id)
	return (U.findById(Store.data.printers, id))
end

function Store.spool(id)
	return (U.findById(Store.data.spools, id))
end

function Store.job(id)
	return (U.findById(Store.data.jobs, id))
end
