-- Persistence. One JSON document in the Playdate datastore holds the whole
-- shop. Writes are debounced: services call Store.markDirty() and the store
-- flushes at most every AUTOSAVE_MS, plus immediately on lifecycle events
-- (terminate, sleep, lock) and after important transactions.
--
-- Load path:  read -> (missing? seed) -> (corrupt? backup + seed)
--             -> (older schema? backup + migrate) -> repair -> ready
-- A document from a *newer* app version is backed up and loaded best-effort,
-- never silently downgraded.

Store = {
	FILE = "printshop",
	AUTOSAVE_MS = 4000,
	data = nil,
	dirty = false,
	sinceSave = 0,
	loadReport = {},
	beforeSave = nil,   -- hook: flush live state (provider) into data
}

function Store.load()
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

function Store.update(dtMs)
	if not Store.dirty then return end
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
	pcall(playdate.datastore.delete, Store.FILE)
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
	return U.findById(d.printers, d.settings.activePrinterId) or d.printers[1]
end

function Store.printer(id)
	return U.findById(Store.data.printers, id)
end

function Store.spool(id)
	return U.findById(Store.data.spools, id)
end

function Store.job(id)
	return U.findById(Store.data.jobs, id)
end
