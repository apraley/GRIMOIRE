-- The data model: indexing, the single mutation entry point (Model.apply) and
-- all production queries (navigation order, NEXT ranking, progress, estimates).
--
-- Every change to the database is an *op* (a small JSON-compatible table).
-- Ops are applied here, journaled by Store, and replayed after a crash, so
-- apply() must be deterministic: any timestamp or id is carried in the op.
--
--   { o="add",  p=parentId, c=collection, r=record, i=index? }
--   { o="set",  id=recordId, f=field, v=value }          (v absent = clear)
--   { o="del",  id=recordId }
--   { o="mv",   id=recordId, p=newParentId, c=collection, i=index? }
--   { o="batch", ops={...} }
-- Any op may carry `label` (shown in the undo toast) and `s` (journal seq).

Model = {}

Model.db = nil
Model.byId = {}
Model.parentOf = {}
Model.collOf = {}
Model.rev = 0 -- bumps on any structural change (add/del/mv)
local flatCache = {}

local PREFIX = { project = "p", day = "d", scene = "c", setup = "u", shot = "s", take = "t", note = "n",
	report = "r", pkg = "g" }

local function indexTree(rec, parent, coll)
	if rec.id then
		Model.byId[rec.id] = rec
		Model.parentOf[rec.id] = parent
		Model.collOf[rec.id] = coll
		local n = tonumber(tostring(rec.id):match("%d+$"))
		if n and Model.db and n >= Model.db.nextId then Model.db.nextId = n + 1 end
	end
	for _, c in ipairs(Schema.CHILDREN[rec.k] or {}) do
		local list = rec[c]
		if list then
			for _, child in ipairs(list) do indexTree(child, rec, c) end
		end
	end
end

local function unindexTree(rec)
	if rec.id then
		Model.byId[rec.id] = nil
		Model.parentOf[rec.id] = nil
		Model.collOf[rec.id] = nil
	end
	for _, c in ipairs(Schema.CHILDREN[rec.k] or {}) do
		for _, child in ipairs(rec[c] or {}) do unindexTree(child) end
	end
end

function Model.attach(db)
	Model.db = db
	Model.byId, Model.parentOf, Model.collOf = {}, {}, {}
	db.id, db.k = "root", "root"
	Model.byId.root = db
	Model.byId.settings = db.settings
	Model.byId.gear = db.gear
	for _, p in ipairs(db.projects) do indexTree(p, db, "projects") end
	for _, g in ipairs(db.gear.packages) do indexTree(g, db.gear, "packages") end
	Model.rev = Model.rev + 1
	flatCache = {}
end

-- Assign fresh ids to a record tree (before it is put into an add op).
function Model.assignIds(rec)
	if rec.id == nil then
		rec.id = (PREFIX[rec.k] or "x") .. Model.db.nextId
		Model.db.nextId = Model.db.nextId + 1
	end
	for _, c in ipairs(Schema.CHILDREN[rec.k] or {}) do
		for _, child in ipairs(rec[c] or {}) do
			child.k = child.k or Schema.COLLECTION_KIND[c]
			Model.assignIds(child)
		end
	end
	return rec
end

function Model.get(id) return Model.byId[id] end

local function indexIn(list, rec)
	for i = 1, #list do if list[i] == rec then return i end end
	return nil
end

---------------------------------------------------------------------------
-- Derived fields (recomputed inside apply, so replay reproduces them)
---------------------------------------------------------------------------

function Model.deriveSceneStatus(scene)
	local total, cut, got, shooting, pickup, upnext, todo = 0, 0, 0, 0, 0, 0, 0
	for _, setup in ipairs(scene.setups) do
		for _, shot in ipairs(setup.shots) do
			total = total + 1
			local s = shot.status
			if s == "CUT" then cut = cut + 1
			elseif s == "GOT IT" then got = got + 1
			elseif s == "SHOOTING" then shooting = shooting + 1
			elseif s == "PICKUP" then pickup = pickup + 1
			elseif s == "UP NEXT" then upnext = upnext + 1
			else todo = todo + 1 end
		end
	end
	local live = total - cut
	local st
	if total > 0 and live == 0 then st = "CUT"
	elseif live > 0 and got == live then st = "GOT IT"
	elseif shooting > 0 then st = "SHOOTING"
	elseif pickup > 0 and todo + upnext == 0 then st = "PICKUP"
	elseif upnext > 0 then st = "UP NEXT"
	elseif got + pickup > 0 then st = "SHOOTING"
	else st = "NOT SHOT" end
	scene.status = st
end

local function sceneOfRec(rec)
	local r = rec
	while r and r.k ~= "scene" do r = Model.parentOf[r.id] end
	return r
end

local function touchDerived(rec)
	if rec == nil then return end
	if rec.k == "shot" or rec.k == "setup" or rec.k == "take" then
		local sc = sceneOfRec(rec)
		if sc then Model.deriveSceneStatus(sc) end
	elseif rec.k == "scene" then
		Model.deriveSceneStatus(rec)
	end
end

---------------------------------------------------------------------------
-- apply
---------------------------------------------------------------------------

local PROTECTED = { id = true, k = true }

local applyOp

local function applyAdd(op)
	local parent = Model.byId[op.p]
	if parent == nil then return nil, "add: no parent " .. tostring(op.p) end
	local list = parent[op.c]
	if type(list) ~= "table" then return nil, "add: no collection " .. tostring(op.c) end
	local rec = Util.deepcopy(op.r)
	if rec.id == nil then return nil, "add: record without id" end
	if Model.byId[rec.id] then return nil, "add: duplicate id " .. rec.id end
	Schema.normalize(rec)
	local i = op.i
	if i == nil or i > #list + 1 or i < 1 then i = #list + 1 end
	table.insert(list, i, rec)
	indexTree(rec, parent, op.c)
	Model.rev = Model.rev + 1
	touchDerived(rec)
	touchDerived(parent)
	return { o = "del", id = rec.id }
end

local function applySet(op)
	local rec = Model.byId[op.id]
	if rec == nil then return nil, "set: no record " .. tostring(op.id) end
	if PROTECTED[op.f] then return nil, "set: protected field " .. tostring(op.f) end
	for _, c in ipairs(Schema.CHILDREN[rec.k] or {}) do
		if c == op.f then return nil, "set: collection field " .. c end
	end
	local old = rec[op.f]
	rec[op.f] = Util.deepcopy(op.v)
	if op.f == "status" or op.f == "num" then touchDerived(rec) end
	return { o = "set", id = op.id, f = op.f, v = old }
end

local function applyDel(op)
	local rec = Model.byId[op.id]
	if rec == nil then return nil, "del: no record " .. tostring(op.id) end
	local parent = Model.parentOf[op.id]
	local coll = Model.collOf[op.id]
	if parent == nil or coll == nil then return nil, "del: record not in a collection" end
	local list = parent[coll]
	local i = indexIn(list, rec)
	table.remove(list, i)
	unindexTree(rec)
	Model.rev = Model.rev + 1
	touchDerived(parent)
	return { o = "add", p = parent.id, c = coll, r = rec, i = i }
end

local function applyMv(op)
	local rec = Model.byId[op.id]
	if rec == nil then return nil, "mv: no record" end
	local oldParent, oldColl = Model.parentOf[op.id], Model.collOf[op.id]
	local newParent = Model.byId[op.p]
	if newParent == nil or type(newParent[op.c]) ~= "table" then return nil, "mv: bad target" end
	local oldList = oldParent[oldColl]
	local oldI = indexIn(oldList, rec)
	table.remove(oldList, oldI)
	local list = newParent[op.c]
	local i = op.i
	if i == nil or i > #list + 1 or i < 1 then i = #list + 1 end
	table.insert(list, i, rec)
	Model.parentOf[op.id] = newParent
	Model.collOf[op.id] = op.c
	Model.rev = Model.rev + 1
	touchDerived(oldParent)
	touchDerived(newParent)
	return { o = "mv", id = op.id, p = oldParent.id, c = oldColl, i = oldI }
end

local function applyBatch(op)
	local inverses = {}
	for idx, sub in ipairs(op.ops or {}) do
		local inv, err = applyOp(sub)
		if inv == nil then
			-- roll back what was applied so a batch is all-or-nothing
			for j = #inverses, 1, -1 do applyOp(inverses[j]) end
			return nil, "batch[" .. idx .. "]: " .. tostring(err)
		end
		inverses[#inverses + 1] = inv
	end
	local rev = {}
	for j = #inverses, 1, -1 do rev[#rev + 1] = inverses[j] end
	return { o = "batch", ops = rev }
end

applyOp = function(op)
	if op.o == "add" then return applyAdd(op)
	elseif op.o == "set" then return applySet(op)
	elseif op.o == "del" then return applyDel(op)
	elseif op.o == "mv" then return applyMv(op)
	elseif op.o == "batch" then return applyBatch(op)
	end
	return nil, "unknown op " .. tostring(op.o)
end

-- Apply an op. Returns the inverse op (for undo) or nil, error.
function Model.apply(op)
	local inv, err = applyOp(op)
	if inv then inv.label = op.label end
	return inv, err
end

---------------------------------------------------------------------------
-- Op builders (pure: they read state and return ops; Store commits them)
---------------------------------------------------------------------------

function Model.opSet(rec, field, value, label)
	return { o = "set", id = rec.id, f = field, v = value, label = label }
end

function Model.opSetMany(rec, fields, label)
	local ops = {}
	for f, v in pairs(fields) do
		if rec[f] ~= v then ops[#ops + 1] = { o = "set", id = rec.id, f = f, v = v } end
	end
	table.sort(ops, function(a, b) return a.f < b.f end)
	return { o = "batch", ops = ops, label = label }
end

function Model.opAdd(parent, coll, rec, index, label)
	Model.assignIds(rec)
	return { o = "add", p = parent.id, c = coll, r = rec, i = index, label = label }
end

function Model.opDel(rec, label)
	return { o = "del", id = rec.id, label = label }
end

-- TAKE +1 : adds the take and moves the shot/day into "shooting".
function Model.opTake(shot, now)
	local ctx = Model.ctx(shot.id)
	local n = 0
	for _, t in ipairs(shot.takes) do if (t.n or 0) > n then n = t.n end end
	n = n + 1
	local take = Schema.new("take", { n = n, t = now })
	Model.assignIds(take)
	local ops = { { o = "add", p = shot.id, c = "takes", r = take } }
	local s = shot.status
	if s == "NOT SHOT" or s == "UP NEXT" or s == "PICKUP" then
		ops[#ops + 1] = { o = "set", id = shot.id, f = "status", v = "SHOOTING" }
	end
	if shot.startedAt == nil then ops[#ops + 1] = { o = "set", id = shot.id, f = "startedAt", v = now } end
	if ctx.day and ctx.day.started == nil then ops[#ops + 1] = { o = "set", id = ctx.day.id, f = "started", v = now } end
	return { o = "batch", ops = ops, label = "TAKE " .. n .. " " .. Model.code(shot) }, take
end

function Model.opStatus(shot, status, now)
	local ops = { { o = "set", id = shot.id, f = "status", v = status } }
	if status == "GOT IT" then
		ops[#ops + 1] = { o = "set", id = shot.id, f = "doneAt", v = now }
	end
	if status == "SHOOTING" and shot.startedAt == nil then
		ops[#ops + 1] = { o = "set", id = shot.id, f = "startedAt", v = now }
	end
	return { o = "batch", ops = ops, label = Model.code(shot) .. " " .. status }
end

function Model.opCircle(take, now)
	local shot = Model.parentOf[take.id]
	local on = not take.circle
	local ops = { { o = "set", id = take.id, f = "circle", v = on } }
	if on and Model.db.settings.circleGotIt and shot and shot.status ~= "GOT IT" then
		local st = Model.opStatus(shot, "GOT IT", now)
		for _, o in ipairs(st.ops) do ops[#ops + 1] = o end
	end
	return { o = "batch", ops = ops, label = (on and "CIRCLE T" or "UNCIRCLE T") .. take.n .. " " .. Model.code(shot) }
end

-- Scene CUT = cut every shot that is not already done.
function Model.opCutScene(scene)
	local ops = {}
	for _, setup in ipairs(scene.setups) do
		for _, shot in ipairs(setup.shots) do
			if shot.status ~= "GOT IT" and shot.status ~= "CUT" then
				ops[#ops + 1] = { o = "set", id = shot.id, f = "status", v = "CUT" }
			end
		end
	end
	return { o = "batch", ops = ops, label = "CUT SC " .. scene.number }
end

---------------------------------------------------------------------------
-- Context & naming
---------------------------------------------------------------------------

function Model.settings() return Model.db.settings end

function Model.project()
	local p = Model.byId[Model.db.settings.project]
	if p and p.k == "project" then return p end
	return Model.db.projects[1]
end

-- Ancestors of any record: { shot, setup, scene, day, project, take }
function Model.ctx(id)
	local r = Model.byId[id]
	local ctx = {}
	while r and r.k ~= "root" do
		ctx[r.k] = r
		r = Model.parentOf[r.id]
	end
	return ctx
end

function Model.code(shot)
	if shot == nil then return "--" end
	local setup = Model.parentOf[shot.id]
	local scene = setup and Model.parentOf[setup.id]
	local sn = scene and scene.number or "?"
	local sl = setup and setup.letter or "?"
	return tostring(sn) .. tostring(sl) .. "-" .. tostring(shot.num)
end

function Model.setupCode(setup)
	local scene = Model.parentOf[setup.id]
	return tostring(scene and scene.number or "?") .. tostring(setup.letter)
end

function Model.lensOf(shot)
	if shot.lens and shot.lens ~= "" then return shot.lens end
	local setup = Model.parentOf[shot.id]
	return setup and setup.lens or ""
end

-- Description for display; synthesised from size/subject when left blank.
function Model.describe(shot)
	if shot.desc and shot.desc ~= "" then return shot.desc end
	local parts = { shot.size }
	if shot.subject and shot.subject ~= "" then parts[#parts + 1] = shot.subject end
	return table.concat(parts, " - ")
end

function Model.maxTakeN(shot)
	local n = 0
	for _, t in ipairs(shot.takes) do if (t.n or 0) > n then n = t.n end end
	return n
end

function Model.lastTake(shot)
	local best, n = nil, -1
	for _, t in ipairs(shot.takes) do
		if (t.n or 0) > n then best, n = t, t.n end
	end
	return best
end

-- Best take: circled beats uncircled, then rating, then most recent.
function Model.bestTake(shot)
	local best, bestKey = nil, nil
	for _, t in ipairs(shot.takes) do
		local key = (t.circle and 100 or 0) + ((Vocab.RATING_SCORE[t.rating] or 1.5) * 10)
		if t.rating == "" or t.rating == nil then key = key - 5 end
		if bestKey == nil or key > bestKey or (key == bestKey and (t.n or 0) > (best.n or 0)) then
			best, bestKey = t, key
		end
	end
	if best and not best.circle and (best.rating == "" or best.rating == nil or best.rating == "BAD" or best.rating == "TECH") then
		return nil -- nothing worth calling "best" yet
	end
	return best
end

function Model.nextNum(setup)
	local m = 0
	for _, s in ipairs(setup.shots) do
		local n = tonumber(tostring(s.num):match("^%d+"))
		if n and n > m then m = n end
	end
	return Util.pad2(m + 1)
end

function Model.nextLetter(scene)
	local used = {}
	for _, s in ipairs(scene.setups) do used[Util.upper(s.letter)] = true end
	for c = string.byte("A"), string.byte("Z") do
		local l = string.char(c)
		if not used[l] and l ~= "I" and l ~= "O" then return l end -- I/O skipped (industry convention)
	end
	return "X"
end

function Model.nextSceneNumber(project)
	local m = 0
	for _, d in ipairs(project.days) do
		for _, sc in ipairs(d.scenes) do
			local n = tonumber(tostring(sc.number):match("^%d+"))
			if n and n > m then m = n end
		end
	end
	return Util.pad2(m + 1)
end

---------------------------------------------------------------------------
-- Flat shooting order: day > scene > setup > shot
---------------------------------------------------------------------------

function Model.flat(project)
	project = project or Model.project()
	if project == nil then return {} end
	local c = flatCache[project.id]
	if c and c.rev == Model.rev then return c.list end
	local list, pos = {}, {}
	for _, day in ipairs(project.days) do
		for _, scene in ipairs(day.scenes) do
			for _, setup in ipairs(scene.setups) do
				for _, shot in ipairs(setup.shots) do
					local e = { shot = shot, setup = setup, scene = scene, day = day, i = #list + 1 }
					list[#list + 1] = e
					pos[shot.id] = e.i
				end
			end
		end
	end
	flatCache[project.id] = { rev = Model.rev, list = list, pos = pos }
	return list
end

function Model.flatIndex(shotId, project)
	Model.flat(project)
	local c = flatCache[(project or Model.project()).id]
	return c and c.pos[shotId]
end

-- Step through the flat list by `delta` at granularity "shot" | "setup" | "scene".
function Model.step(shotId, delta, level)
	local list = Model.flat()
	if #list == 0 then return nil end
	local i = Model.flatIndex(shotId) or 1
	if level == nil or level == "shot" then
		return list[Util.clamp(i + delta, 1, #list)].shot
	end
	local key = level == "setup" and "setup" or "scene"
	local dir = delta > 0 and 1 or -1
	local count = math.abs(delta)
	for _ = 1, count do
		local cur = list[i][key]
		if dir > 0 then
			local j = i
			while j <= #list and list[j][key] == cur do j = j + 1 end
			if j > #list then break end
			i = j
		else
			-- go to the first shot of the previous group (or of this group if not at its start)
			local j = i
			while j > 1 and list[j - 1][key] == cur do j = j - 1 end
			if j == i then
				if j == 1 then break end
				local prev = list[j - 1][key]
				j = j - 1
				while j > 1 and list[j - 1][key] == prev do j = j - 1 end
			end
			i = j
		end
	end
	return list[i].shot
end

---------------------------------------------------------------------------
-- NEXT: the ranked list of what to shoot next.
--
-- Ranking (lexicographic):
--   1. shots the AD flagged UP NEXT
--   2. shots scheduled on the current day (then other days)
--   3. priority A > B > C
--   4. locality: same setup > same scene > elsewhere  (no relight/move)
--   5. unshot before pickups
--   6. schedule order, starting after the current shot
---------------------------------------------------------------------------

local OPEN = { ["NOT SHOT"] = true, ["UP NEXT"] = true, ["SHOOTING"] = true, ["PICKUP"] = true }

function Model.isOpen(shot) return OPEN[shot.status] == true end

function Model.nextCandidates(fromShotId, project)
	local list = Model.flat(project)
	local n = #list
	if n == 0 then return {} end
	local fromI = fromShotId and Model.flatIndex(fromShotId, project) or nil
	local from = fromI and list[fromI] or nil
	local cands = {}
	for _, e in ipairs(list) do
		local s = e.shot
		if OPEN[s.status] and s.id ~= fromShotId then
			local loc = 2
			if from then
				if e.setup == from.setup then loc = 0 elseif e.scene == from.scene then loc = 1 end
			end
			local dist = fromI and ((e.i - fromI) % n) or e.i
			local pri = tonumber(s.priority) or 2
			-- BALANCED (default): finish the setup we are lit for before moving
			-- (a C shot left behind costs a whole relight later), then go by
			-- priority. RUSH ("losing the light"): strict priority, no locality.
			local eff = pri
			if Model.db.settings.nextMode ~= "RUSH" and loc == 0 then eff = pri - 3 end
			cands[#cands + 1] = {
				shot = s, e = e,
				k1 = s.status == "UP NEXT" and 0 or 1,
				k2 = (from == nil or e.day == from.day) and 0 or 1,
				k3 = eff, pri = pri,
				k4 = loc,
				k5 = s.status == "PICKUP" and 1 or 0,
				k6 = dist,
			}
		end
	end
	table.sort(cands, function(a, b)
		if a.k1 ~= b.k1 then return a.k1 < b.k1 end
		if a.k2 ~= b.k2 then return a.k2 < b.k2 end
		if a.k3 ~= b.k3 then return a.k3 < b.k3 end
		if a.k4 ~= b.k4 then return a.k4 < b.k4 end
		if a.k5 ~= b.k5 then return a.k5 < b.k5 end
		return a.k6 < b.k6
	end)
	return cands
end

function Model.nextReason(c)
	local parts = {}
	if c.k1 == 0 then parts[#parts + 1] = "UP NEXT" end
	parts[#parts + 1] = "PRI " .. (Vocab.PRIORITY_LABEL[c.pri] or "?")
	if c.k4 == 0 then parts[#parts + 1] = "SAME SETUP"
	elseif c.k4 == 1 then parts[#parts + 1] = "SAME SCENE"
	else parts[#parts + 1] = "MOVE" end
	if c.k5 == 1 then parts[#parts + 1] = "PICKUP" end
	if c.k2 == 1 then parts[#parts + 1] = "OTHER DAY" end
	return table.concat(parts, " / ")
end

---------------------------------------------------------------------------
-- Progress & estimates
---------------------------------------------------------------------------

-- scope: nil = whole project, or a day record
function Model.progress(project, day)
	project = project or Model.project()
	local r = { total = 0, done = 0, pickups = 0, remain = 0, cut = 0, shooting = 0, takes = 0, circled = 0,
		estRemain = 0, estPlanned = 0 }
	if project == nil then return r end
	for _, e in ipairs(Model.flat(project)) do
		if day == nil or e.day == day then
			local s = e.shot
			r.takes = r.takes + #s.takes
			for _, t in ipairs(s.takes) do if t.circle then r.circled = r.circled + 1 end end
			if s.status == "CUT" then
				r.cut = r.cut + 1
			else
				r.total = r.total + 1
				r.estPlanned = r.estPlanned + (tonumber(s.est) or 0)
				if s.status == "GOT IT" then r.done = r.done + 1
				elseif s.status == "PICKUP" then r.pickups = r.pickups + 1; r.estRemain = r.estRemain + (tonumber(s.est) or 0)
				else
					r.remain = r.remain + 1
					r.estRemain = r.estRemain + (tonumber(s.est) or 0)
					if s.status == "SHOOTING" then r.shooting = r.shooting + 1 end
				end
			end
		end
	end
	r.pct = r.total > 0 and math.floor(r.done * 100 / r.total + 0.5) or 0
	return r
end

-- Remaining-time estimate from historical completion intervals.
--
-- Completion interval = time between consecutive GOT ITs on the same day
-- (the first measured from the day's first take); gaps over 90 min are
-- breaks and ignored. Intervals are split by whether the shot started a new
-- setup, which gives two learned rates:
--   pace   = mean(interval / planned minutes) for same-setup shots
--   change = mean extra minutes a new setup costs (relight / move)
-- Remaining = sum over open shots of planned*pace (or the mean same-setup
-- interval when unplanned) + change for every setup still to be started.
-- Until enough history exists the plan (or 10 min/shot, 15 min/setup) is used.
function Model.estimate(project, day, now)
	project = project or Model.project()
	local res = { minutes = nil, pace = nil, samples = 0, method = "NONE" }
	if project == nil then return res end
	local done, open = {}, {}
	for _, e in ipairs(Model.flat(project)) do
		if day == nil or e.day == day then
			local s = e.shot
			if s.status == "GOT IT" and s.doneAt then
				done[#done + 1] = { t = s.doneAt, est = tonumber(s.est), day = e.day, setup = e.setup,
					loc = Util.upper(e.scene.location) }
			elseif OPEN[s.status] then
				open[#open + 1] = e
			end
		end
	end
	table.sort(done, function(a, b) return a.t < b.t end)
	local sameIv, ratios, changeExtra = {}, {}, {}
	for i, d in ipairs(done) do
		local prev = (i > 1 and done[i - 1].day == d.day) and done[i - 1] or nil
		local prevT = prev and prev.t or d.day.started
		if prevT then
			local mins = (d.t - prevT) / 60
			if mins > 0 and mins <= 90 then
				local newSetup = prev == nil or prev.setup ~= d.setup
				if newSetup then
					changeExtra[#changeExtra + 1] = { mins = mins, est = d.est, move = prev ~= nil and prev.loc ~= d.loc }
				else
					sameIv[#sameIv + 1] = mins
					if d.est and d.est > 0 then ratios[#ratios + 1] = mins / d.est end
				end
			end
		end
	end
	local function recent(list, n)
		local r = {}
		for i = math.max(1, #list - n + 1), #list do r[#r + 1] = list[i] end
		return r
	end
	-- means, not medians: setup costs are skewed (a 7 min relight vs a 25 min
	-- company move) and the median hides exactly the time that runs a day long
	local pace = Util.mean(recent(ratios, 15))
	local sameMed = Util.mean(recent(sameIv, 15))
	-- relights (same location) and company moves are learned separately
	local relights, moves = {}, {}
	for _, c in ipairs(changeExtra) do
		local work = (c.est and c.est > 0 and pace) and c.est * pace or (sameMed or 10)
		local list = c.move and moves or relights
		list[#list + 1] = math.max(0, c.mins - work)
	end
	local changeMed = Util.mean(recent(relights, 8))
	local moveMed = Util.mean(recent(moves, 4))
	res.samples = #sameIv + #changeExtra
	res.remainCount = #open
	res.pace, res.median, res.change, res.move = pace, sameMed, changeMed, moveMed
	if #open == 0 then
		res.minutes, res.method = 0, "DONE"
		return res
	end
	-- the setup we are standing in needs no change
	local cur = Model.byId[Model.db.settings.cursor]
	local curSetup = cur and cur.k == "shot" and Model.parentOf[cur.id] or nil
	local seen = {}
	local lastLoc = nil
	if curSetup then
		seen[curSetup] = true
		local sc = Model.parentOf[curSetup.id]
		lastLoc = sc and Util.upper(sc.location)
	end
	local total = 0
	for _, e in ipairs(open) do
		local est = tonumber(e.shot.est)
		local work
		if est and est > 0 then work = est * (pace or 1) else work = sameMed or 10 end
		total = total + work
		if not seen[e.setup] then
			seen[e.setup] = true
			local loc = Util.upper(e.scene.location)
			if lastLoc ~= nil and loc ~= lastLoc then
				total = total + (moveMed or math.max(30, (changeMed or 12) * 2))
			else
				total = total + (changeMed or 12)
			end
			lastLoc = loc
		end
	end
	-- a meal break written in the day's crew notes ("LUNCH 12:30") that is
	-- still ahead of us will happen before wrap
	local d = day or Model.currentDay(project)
	local lunchAt = d and Util.parseHM((tostring(d.crewNotes or ""):upper():match("LUNCH%s+(%d%d?:%d%d)")) or "")
	if lunchAt and now then
		local t = Util.localTime(now)
		local nowMin = t.hour * 60 + t.minute
		if nowMin < lunchAt and nowMin + total > lunchAt then
			total = total + 45
			res.lunch = true
		end
	end
	res.minutes = total
	if pace and #ratios >= 3 then res.method = "PACE"
	elseif sameMed then res.method = "MEDIAN"
	else res.method = "PLAN" end
	if now then res.wrapAt = now + res.minutes * 60 end
	return res
end

function Model.flaggedNotes(scene)
	local r = {}
	if scene == nil then return r end
	for _, n in ipairs(scene.notes) do
		if n.flag and not n.resolved then r[#r + 1] = n end
	end
	return r
end

-- The day LIVE considers "today": the day of the cursor shot, else first day.
function Model.currentDay(project)
	project = project or Model.project()
	if project == nil then return nil end
	local cur = Model.byId[Model.db.settings.cursor]
	if cur and cur.k == "shot" then
		local ctx = Model.ctx(cur.id)
		if ctx.project == project then return ctx.day end
	end
	return project.days[1]
end

-- Suggestions for free-text fields: values already used in the project.
function Model.usedValues(field, kind, project)
	project = project or Model.project()
	local r = {}
	if project == nil then return r end
	local function visit(rec)
		if rec.k == kind and rec[field] and rec[field] ~= "" then r[#r + 1] = rec[field] end
		for _, c in ipairs(Schema.CHILDREN[rec.k] or {}) do
			for _, ch in ipairs(rec[c] or {}) do visit(ch) end
		end
	end
	visit(project)
	return Util.uniq(r)
end

return Model
