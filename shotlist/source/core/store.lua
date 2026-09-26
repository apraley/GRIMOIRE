-- Persistence: crash-safe snapshot + journal, rolling backups, undo.
--
-- Files in the game's Data folder:
--   shotlist.json        current snapshot (playdate.datastore)
--   shotlist_new.json    snapshot being written (promoted by rename)
--   shotlist_prev.json   previous snapshot
--   journal.jsonl        one op per line, appended on every commit
--   session.json         tiny UI state (cursor), written when idle
--   backups/snapN.json   rolling snapshots (N = 1..SLOTS) + backups/index.json
--   export/...           files written by EXPORT (see docs/SCHEMA.md)
--
-- A commit appends the op to the journal *before* returning, so a crash can
-- lose at most the op being written. Full snapshots are written when the
-- user is idle; the journal is truncated only after the new snapshot has been
-- promoted. On load the newest readable snapshot is taken and every journal op
-- with a higher sequence number is replayed.

Store = {}

Store.FILE = "shotlist"
Store.NEW = "shotlist_new"
Store.PREV = "shotlist_prev"
Store.JOURNAL = "journal.jsonl"
Store.SESSION = "session"
Store.BACKUP_DIR = "backups"
Store.SLOTS = 8
Store.SNAPSHOT_EVERY = 15 * 60 -- seconds of wall time between automatic backups

Store.seq = 0
Store.dirty = false
Store.pending = 0
Store.firstPendingMs = 0
Store.sessionDirty = false
Store.undoStack = {}
Store.lastError = nil
Store.loadInfo = {}
Store.saving = 0 -- frames left to show the save indicator

local function exists(path) return playdate.file.exists(path) end

local function readSnapshot(name)
	if not exists(name .. ".json") then return nil end
	local ok, t = pcall(playdate.datastore.read, name)
	if not ok or type(t) ~= "table" then return nil, "unreadable" end
	local db, err = Schema.migrate(t)
	if db == nil then return nil, err end
	return db
end

local function readJournal()
	local ops = {}
	if not exists(Store.JOURNAL) then return ops end
	local f = playdate.file.open(Store.JOURNAL, playdate.file.kFileRead)
	if f == nil then return ops end
	while true do
		local line = f:readline()
		if line == nil then break end
		if #line > 1 then
			local ok, op = pcall(json.decode, line)
			if ok and type(op) == "table" and op.o then ops[#ops + 1] = op end
			-- a torn final line (crash mid-write) fails to decode and is skipped
		end
	end
	f:close()
	return ops
end

local function truncateJournal()
	local f = playdate.file.open(Store.JOURNAL, playdate.file.kFileWrite)
	if f then f:close() end
end

-- Returns true if a database was found (fresh installs return false).
function Store.load()
	local best, bestName
	for _, name in ipairs({ Store.FILE, Store.NEW, Store.PREV }) do
		local db = readSnapshot(name)
		if db and (best == nil or (db.seq or 0) > (best.seq or 0)) then best, bestName = db, name end
	end
	if best == nil then
		-- fall back to the newest rolling backup
		for _, snap in ipairs(Store.listSnapshots()) do
			local ok, t = pcall(json.decodeFile, snap.path)
			if ok and type(t) == "table" then
				local db = Schema.migrate(t)
				if db then best, bestName = db, snap.path; break end
			end
		end
	end
	if best == nil then Store.quarantine() end
	local ops = readJournal()
	if best == nil and #ops == 0 then
		Store.loadInfo = { source = "none" }
		return false
	end
	best = best or Schema.newDb()
	Model.attach(best)
	Store.seq = best.seq or 0
	local replayed, failed = 0, 0
	for _, op in ipairs(ops) do
		if (op.s or 0) > Store.seq then
			local inv = Model.apply(op)
			if inv then replayed = replayed + 1 else failed = failed + 1 end
			Store.seq = op.s
		end
	end
	Store.loadInfo = { source = bestName or "journal", replayed = replayed, failed = failed, seq = Store.seq }
	local sess = nil
	if exists(Store.SESSION .. ".json") then
		local ok, t = pcall(playdate.datastore.read, Store.SESSION)
		if ok and type(t) == "table" then sess = t end
	end
	if sess then
		if sess.cursor and Model.byId[sess.cursor] then best.settings.cursor = sess.cursor end
		if sess.project and Model.byId[sess.project] then best.settings.project = sess.project end
	end
	if replayed > 0 or bestName ~= Store.FILE then Store.flush() end
	return true
end

function Store.db() return Model.db end

-- Snapshot files exist but none could be read: move them aside (never delete)
-- so a fresh start cannot overwrite what might still be recoverable by hand.
function Store.quarantine()
	local names = { Store.FILE .. ".json", Store.NEW .. ".json", Store.PREV .. ".json" }
	local any = false
	for _, n in ipairs(names) do if exists(n) then any = true end end
	if not any then return false end
	local dir = "rescue-" .. tostring(math.floor(Util.now()))
	playdate.file.mkdir(dir)
	for _, n in ipairs(names) do
		if exists(n) then playdate.file.rename(n, dir .. "/" .. n) end
	end
	Store.loadInfo.quarantined = dir
	return true
end

-- Start over with a new database (first run / wipe).
function Store.reset(db)
	Model.attach(db)
	Store.seq = db.seq or 0
	Store.undoStack = {}
	Store.flush()
end

-- The single write path for production data.
function Store.commit(op)
	local inv, err = Model.apply(op)
	if inv == nil then
		Store.lastError = err
		print("commit failed: " .. tostring(err))
		return nil, err
	end
	Store.seq = Store.seq + 1
	op.s = Store.seq
	local okEnc, line = pcall(json.encode, op)
	if okEnc then
		local f = playdate.file.open(Store.JOURNAL, playdate.file.kFileAppend)
		if f then
			f:write(line .. "\n")
			f:close()
		else
			Store.lastError = "journal write failed"
		end
	end
	if op.label and op.noUndo ~= true then
		Store.undoStack[#Store.undoStack + 1] = inv
		if #Store.undoStack > 40 then table.remove(Store.undoStack, 1) end
	end
	if not Store.dirty then Store.firstPendingMs = Util.nowMs() end
	Store.dirty = true
	Store.pending = Store.pending + 1
	return inv
end

function Store.canUndo() return #Store.undoStack > 0 end

function Store.undoLabel()
	local inv = Store.undoStack[#Store.undoStack]
	return inv and inv.label or nil
end

function Store.undo()
	local inv = table.remove(Store.undoStack)
	if inv == nil then return nil end
	inv.noUndo = true
	local label = inv.label
	local r = Store.commit(inv)
	return r and label or nil
end

-- UI state that is not production data (cursor position): cheap separate file.
function Store.touchSession()
	Store.sessionDirty = true
end

function Store.flushSession()
	if not Store.sessionDirty or Model.db == nil then return end
	local s = Model.db.settings
	pcall(playdate.datastore.write, { cursor = s.cursor, project = s.project }, Store.SESSION)
	Store.sessionDirty = false
end

function Store.flush()
	if Model.db == nil then return false end
	local db = Model.db
	db.seq = Store.seq
	db.savedAt = Util.now()
	db.schema = Schema.VERSION
	local ok, err = pcall(playdate.datastore.write, db, Store.NEW)
	if not ok or not exists(Store.NEW .. ".json") then
		Store.lastError = "snapshot write failed: " .. tostring(err)
		return false
	end
	if exists(Store.FILE .. ".json") then
		if exists(Store.PREV .. ".json") then playdate.file.delete(Store.PREV .. ".json") end
		playdate.file.rename(Store.FILE .. ".json", Store.PREV .. ".json")
	end
	if not playdate.file.rename(Store.NEW .. ".json", Store.FILE .. ".json") then
		Store.lastError = "snapshot promote failed"
		return false -- journal kept; load() will still find shotlist_new
	end
	truncateJournal()
	Store.dirty = false
	Store.pending = 0
	Store.lastError = nil
	Store.saving = 12
	Store.flushSession()
	return true
end

-- Called every frame. idleMs = time since the last button/crank input.
function Store.tick(idleMs)
	if Store.saving > 0 then Store.saving = Store.saving - 1 end
	if Store.dirty then
		local age = Util.nowMs() - Store.firstPendingMs
		if idleMs > 1500 or Store.pending >= 40 or age > 45000 then
			Store.flush()
			local s = Model.db.settings
			if Util.now() - (s.lastSnapshot or 0) > Store.SNAPSHOT_EVERY then Store.snapshot("AUTO") end
		end
	elseif Store.sessionDirty and idleMs > 2500 then
		Store.flushSession()
	end
end

---------------------------------------------------------------------------
-- Rolling backups
---------------------------------------------------------------------------

local function readIndex()
	local path = Store.BACKUP_DIR .. "/index.json"
	if not exists(path) then return {} end
	local ok, t = pcall(json.decodeFile, path)
	if ok and type(t) == "table" and type(t.slots) == "table" then return t.slots end
	return {}
end

function Store.snapshot(reason)
	local db = Model.db
	if db == nil then return false end
	if Store.dirty then Store.flush() end
	local s = db.settings
	local slot = (s.snapSlot or 0) % Store.SLOTS + 1
	playdate.file.mkdir(Store.BACKUP_DIR)
	local path = Store.BACKUP_DIR .. "/snap" .. slot .. ".json"
	db.seq = Store.seq
	local ok = pcall(json.encodeToFile, path, false, db)
	if not ok then
		Store.lastError = "backup failed"
		return false
	end
	local index = readIndex()
	local p = Model.project()
	local pr = Model.progress(p)
	local entry = { slot = slot, path = path, t = Util.now(), reason = reason or "MANUAL", seq = Store.seq,
		project = p and p.title or "", shots = pr.total, done = pr.done, takes = pr.takes }
	local kept = { entry }
	for _, e in ipairs(index) do
		if e.slot ~= slot then kept[#kept + 1] = e end
	end
	pcall(json.encodeToFile, Store.BACKUP_DIR .. "/index.json", true, { slots = kept })
	s.snapSlot = slot
	s.lastSnapshot = Util.now()
	return true
end

-- Newest first.
function Store.listSnapshots()
	local list = {}
	for _, e in ipairs(readIndex()) do
		if exists(e.path) then list[#list + 1] = e end
	end
	table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
	return list
end

function Store.restore(entry)
	local ok, t = pcall(json.decodeFile, entry.path)
	if not ok or type(t) ~= "table" then return false, "unreadable backup" end
	local db, err = Schema.migrate(t)
	if db == nil then return false, err end
	Store.snapshot("PRE-RESTORE")
	local keepSlot, keepSnap = Model.db.settings.snapSlot, Model.db.settings.lastSnapshot
	-- the restored db continues the journal sequence so stale ops never replay
	db.seq = Store.seq
	db.settings.snapSlot, db.settings.lastSnapshot = keepSlot, keepSnap
	Model.attach(db)
	Store.undoStack = {}
	Store.flush()
	return true
end

-- Plain text file in the Data folder (exports). Returns ok.
function Store.writeText(path, text)
	local dir = path:match("^(.*)/[^/]+$")
	if dir then playdate.file.mkdir(dir) end
	local f = playdate.file.open(path, playdate.file.kFileWrite)
	if f == nil then return false end
	f:write(text)
	f:close()
	return true
end

return Store
