-- FILAMENT ROLODEX service: spool inventory, consumption ledger, filters,
-- sorting, low-spool warnings and cost math.

Filament = {}

Filament.SORTS = { "REMAINING", "MAKER", "MATERIAL", "COLOR", "RECENT", "COST/G", "FAILS" }
Filament.FILTERS = { "ALL", "PLA", "PETG", "TPU", "ABS", "ASA", "OTHER", "LOW", "FAVS", "EMPTY" }

local function threshold()
	return Store.settings().lowSpoolGrams
end

local SORT_FNS = {
	REMAINING = function(a, b) return a.remainingGrams < b.remainingGrams end,
	MAKER = function(a, b)
		if a.manufacturer == b.manufacturer then return a.material < b.material end
		return a.manufacturer < b.manufacturer
	end,
	MATERIAL = function(a, b)
		if a.material == b.material then return a.manufacturer < b.manufacturer end
		return a.material < b.material
	end,
	COLOR = function(a, b) return a.color < b.color end,
	RECENT = function(a, b)
		return math.max(a.openedAt, a.purchasedAt) > math.max(b.openedAt, b.purchasedAt)
	end,
	["COST/G"] = function(a, b) return Spool.costPerGram(a) < Spool.costPerGram(b) end,
	FAILS = function(a, b) return a.failCount > b.failCount end,
}

-- opts.filter: one of FILTERS (default "ALL"); opts.sort: one of SORTS.
-- Empty (archived) spools only appear under the EMPTY filter.
function Filament.list(opts)
	opts = opts or {}
	local filter = opts.filter or "ALL"
	local low = threshold()
	local out = {}
	for _, s in ipairs(Store.data.spools) do
		local keep
		if filter == "EMPTY" then
			keep = s.archived
		elseif s.archived then
			keep = false
		elseif filter == "ALL" then
			keep = true
		elseif filter == "LOW" then
			keep = Spool.isLow(s, low)
		elseif filter == "FAVS" then
			keep = s.favorite
		else
			keep = s.material == filter
		end
		if keep then out[#out + 1] = s end
	end
	local fn = SORT_FNS[opts.sort or "MAKER"] or SORT_FNS.MAKER
	U.stableSort(out, fn)
	return out
end

function Filament.lowSpools()
	local low = threshold()
	return U.filter(Store.data.spools, function(s) return Spool.isLow(s, low) end)
end

function Filament.add(fields)
	local s = Spool.new(fields)
	s.id = Store.newId("s")
	if s.purchasedAt == 0 then s.purchasedAt = Clock.now() end
	Store.data.spools[#Store.data.spools + 1] = s
	Store.markDirty()
	Events.emit("spool.added", { spool = s })
	return s
end

function Filament.update(s, fields)
	for k, v in pairs(fields) do s[k] = v end
	Spool.normalize(s)
	Store.markDirty()
	return s
end

-- Buy another of the same: a sealed clone with fresh counters.
function Filament.restock(s)
	return Filament.add({
		manufacturer = s.manufacturer, material = s.material, color = s.color,
		nominalGrams = s.nominalGrams, remainingGrams = s.nominalGrams, cost = s.cost,
		dryness = "SEALED", location = "SHELF", favNozzle = s.favNozzle, favBed = s.favBed,
		notes = "Restock of " .. s.id,
	})
end

local function logEntry(s, grams, kind, jobId, note)
	local c = Consumption.normalize({
		id = Store.newId("c"), spoolId = s.id, at = Clock.now(), grams = grams,
		kind = kind, jobId = jobId or "", note = note or "",
	})
	local list = Store.data.consumption
	list[#list + 1] = c
	-- Keep the ledger bounded; old rows are summarized in spool.usedGrams.
	while #list > 400 do table.remove(list, 1) end
	return c
end

-- Removes grams from a spool and records why. Returns the spool plus whether
-- this consumption pushed it under the low threshold (or emptied it).
function Filament.consume(spoolId, grams, kind, jobId, note)
	local s = Store.spool(spoolId)
	if s == nil or grams == nil or grams <= 0 then return nil, false end
	local low = threshold()
	local wasLow = Spool.isLow(s, low)
	local before = s.remainingGrams
	s.remainingGrams = math.max(0, s.remainingGrams - grams)
	s.usedGrams = s.usedGrams + (before - s.remainingGrams)
	if s.openedAt == 0 then
		s.openedAt = Clock.now()
		if s.dryness == "SEALED" then s.dryness = "DRY" end
	end
	logEntry(s, before - s.remainingGrams, kind or "manual", jobId, note)
	Store.markDirty()
	local crossed = not wasLow and Spool.isLow(s, low)
	if crossed or (before > 0 and s.remainingGrams <= 0) then
		Events.emit("spool.low", { spool = s, empty = s.remainingGrams <= 0 })
	end
	return s, crossed
end

-- Weigh-in: set the true remaining weight; the difference is logged.
function Filament.setRemaining(s, grams, note)
	grams = U.clamp(grams, 0, s.nominalGrams)
	local diff = s.remainingGrams - grams
	if math.abs(diff) < 0.5 then return s end
	if diff > 0 then
		Filament.consume(s.id, diff, "adjust", nil, note or "Weigh-in")
	else
		s.remainingGrams = grams
		logEntry(s, diff, "adjust", nil, note or "Weigh-in (gain)")
		Store.markDirty()
	end
	return s
end

function Filament.markDried(s)
	s.dryness = "DRY"
	s.driedAt = Clock.now()
	Store.markDirty()
	Events.emit("spool.dried", { spool = s })
end

function Filament.open(s)
	if s.openedAt == 0 then s.openedAt = Clock.now() end
	if s.dryness == "SEALED" then s.dryness = "DRY" end
	Store.markDirty()
end

function Filament.archive(s, flag)
	s.archived = flag ~= false
	Store.markDirty()
end

-- Applies time-based moisture drift to every opened spool. Called at startup
-- and once per day so the Rolodex reflects spools left out on the shelf.
function Filament.ageDryness(now)
	local changed = {}
	for _, s in ipairs(Store.data.spools) do
		if not s.archived then
			local aged = Spool.agedDryness(s, now)
			if aged ~= s.dryness then
				s.dryness = aged
				changed[#changed + 1] = s
			end
		end
	end
	if #changed > 0 then
		Store.markDirty()
		Events.emit("spool.damp", { spools = changed })
	end
	return changed
end

-- Consumption rows for one spool, newest first.
function Filament.ledger(spoolId, limit)
	local out = {}
	local list = Store.data.consumption
	for i = #list, 1, -1 do
		local c = list[i]
		if spoolId == nil or c.spoolId == spoolId then
			out[#out + 1] = c
			if limit and #out >= limit then break end
		end
	end
	return out
end

-- Grams used per week for the last `weeks` weeks (oldest first).
function Filament.weeklyUsage(spoolId, weeks, now)
	now = now or Clock.now()
	weeks = weeks or 8
	local buckets = {}
	for i = 1, weeks do buckets[i] = 0 end
	for _, c in ipairs(Store.data.consumption) do
		if (spoolId == nil or c.spoolId == spoolId) and c.grams > 0 then
			local age = (now - c.at) // (7 * U.DAY)
			if age >= 0 and age < weeks then
				local idx = weeks - age
				buckets[idx] = buckets[idx] + c.grams
			end
		end
	end
	return buckets
end

-- Estimated days until empty at the recent (30 day) burn rate; nil if idle.
function Filament.daysUntilEmpty(s, now)
	now = now or Clock.now()
	local used = 0
	for _, c in ipairs(Store.data.consumption) do
		if c.spoolId == s.id and c.grams > 0 and now - c.at <= 30 * U.DAY then
			used = used + c.grams
		end
	end
	if used <= 0 then return nil end
	return math.floor(s.remainingGrams / (used / 30))
end

function Filament.totals()
	local t = { spools = 0, grams = 0, value = 0, spent = 0, low = 0 }
	local lowT = threshold()
	for _, s in ipairs(Store.data.spools) do
		t.spent = t.spent + s.cost
		if not s.archived then
			t.spools = t.spools + 1
			t.grams = t.grams + s.remainingGrams
			t.value = t.value + Spool.valueRemaining(s)
			if Spool.isLow(s, lowT) then t.low = t.low + 1 end
		end
	end
	return t
end

-- Best spool for a job: same material (+color, +maker if given) with the most
-- filament left. Returns spool or nil.
function Filament.findMatch(material, color, manufacturer, minGrams)
	local best, bestScore = nil, -1
	for _, s in ipairs(Store.data.spools) do
		if not s.archived and s.material == material and s.remainingGrams >= (minGrams or 0) then
			local score = 1
			if color and s.color == color then score = score + 4 end
			if manufacturer and s.manufacturer == manufacturer then score = score + 2 end
			if s.dryness == "DAMP" or s.dryness == "WET" then score = score - 1 end
			score = score + s.remainingGrams / 10000
			if score > bestScore then best, bestScore = s, score end
		end
	end
	return best
end

-- Cost of printing `grams` from spool s.
function Filament.cost(s, grams)
	if s == nil then return 0 end
	return Spool.costPerGram(s) * (grams or 0)
end
