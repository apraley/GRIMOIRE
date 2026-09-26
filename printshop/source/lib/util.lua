-- General helpers shared by every layer. Pure Lua: no playdate.* calls here,
-- so these run unchanged under the headless test harness.
--
-- Numeric note: dates are stored as integer seconds since 2000-01-01 UTC (the
-- Playdate epoch). Keep date math in integers (use //) so values stay exact.

U = {}

function U.clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function U.round(v, places)
	local m = 10 ^ (places or 0)
	return math.floor(v * m + 0.5) / m
end

function U.roundInt(v)
	return math.floor(v + 0.5)
end

function U.sign(v)
	if v > 0 then return 1 elseif v < 0 then return -1 end
	return 0
end

-- Wraps i into 1..n.
function U.wrap(i, n)
	if n <= 0 then return 1 end
	return ((i - 1) % n) + 1
end

---------------------------------------------------------------------------
-- tables

function U.copy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = v end
	return out
end

function U.deepcopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = U.deepcopy(v) end
	return out
end

function U.find(list, pred)
	for i, v in ipairs(list) do
		if pred(v) then return v, i end
	end
	return nil
end

function U.findById(list, id)
	if id == nil then return nil end
	for i, v in ipairs(list) do
		if v.id == id then return v, i end
	end
	return nil
end

function U.filter(list, pred)
	local out = {}
	for _, v in ipairs(list) do
		if pred(v) then out[#out + 1] = v end
	end
	return out
end

function U.map(list, fn)
	local out = {}
	for i, v in ipairs(list) do out[i] = fn(v, i) end
	return out
end

function U.count(list, pred)
	local n = 0
	for _, v in ipairs(list) do
		if pred == nil or pred(v) then n = n + 1 end
	end
	return n
end

function U.sum(list, fn)
	local s = 0
	for _, v in ipairs(list) do s = s + (fn and fn(v) or v) end
	return s
end

function U.indexOf(list, value)
	for i, v in ipairs(list) do
		if v == value then return i end
	end
	return nil
end

function U.keys(t)
	local out = {}
	for k in pairs(t) do out[#out + 1] = k end
	table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
	return out
end

-- Stable insertion sort (table.sort is not stable, and queue order matters).
function U.stableSort(list, less)
	for i = 2, #list do
		local v = list[i]
		local j = i - 1
		while j >= 1 and less(v, list[j]) do
			list[j + 1] = list[j]
			j = j - 1
		end
		list[j + 1] = v
	end
	return list
end

-- Copies defaults into t for any missing key (recursing into sub-tables that
-- are plain records). Used by model normalizers to repair partial saves.
function U.defaults(t, defaults)
	for k, v in pairs(defaults) do
		if t[k] == nil then
			t[k] = U.deepcopy(v)
		end
	end
	return t
end

-- Ensures a value is a dense array. Save files that went through JSON can
-- come back with holes or as a keyed object; this rebuilds a clean list.
function U.asList(t)
	if type(t) ~= "table" then return {} end
	local out = {}
	local keys = {}
	for k in pairs(t) do
		if type(k) == "number" then keys[#keys + 1] = k end
	end
	table.sort(keys)
	for _, k in ipairs(keys) do
		out[#out + 1] = t[k]
	end
	if #out == 0 then
		-- Keyed object (e.g. {"1": ..., "10": ...}): keep values in key
		-- order, numerically when the keys are numbers.
		local sk = {}
		for k, v in pairs(t) do
			if type(k) == "string" and type(v) == "table" then sk[#sk + 1] = k end
		end
		table.sort(sk, function(a, b)
			local na, nb = tonumber(a), tonumber(b)
			if na and nb then return na < nb end
			if na or nb then return na ~= nil end
			return a < b
		end)
		for _, k in ipairs(sk) do out[#out + 1] = t[k] end
	end
	return out
end

-- Three-way merge for editors: copies into `target` only the keys whose
-- value in `draft` differs from `original` (the snapshot taken when the
-- editor opened). Fields that changed underneath the editor meanwhile (a
-- print finishing, filament being consumed) are preserved. Returns the
-- list of changed keys.
function U.mergeEdits(target, original, draft)
	local changed = {}
	local keys = {}
	for k in pairs(original) do keys[k] = true end
	for k in pairs(draft) do keys[k] = true end
	for k in pairs(keys) do
		if draft[k] ~= original[k] and type(draft[k]) ~= "table" then
			target[k] = draft[k]
			changed[#changed + 1] = k
		end
	end
	return changed
end

function U.moveItem(list, from, to)
	if from == to or from < 1 or from > #list then return from end
	to = U.clamp(to, 1, #list)
	local item = table.remove(list, from)
	table.insert(list, to, item)
	return to
end

function U.num(v, fallback)
	v = tonumber(v)
	if v == nil or v ~= v then return fallback end
	return v
end

function U.int(v, fallback)
	v = tonumber(v)
	if v == nil or v ~= v then return fallback end
	return math.floor(v)
end

function U.str(v, fallback)
	if v == nil then return fallback end
	return tostring(v)
end

function U.oneOf(v, allowed, fallback)
	for _, a in ipairs(allowed) do
		if a == v then return v end
	end
	return fallback
end

---------------------------------------------------------------------------
-- strings

function U.upper(s)
	return string.upper(s or "")
end

function U.trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function U.truncate(s, n)
	s = tostring(s or "")
	if #s <= n then return s end
	if n <= 1 then return string.sub(s, 1, n) end
	return string.sub(s, 1, n - 1) .. "~"
end

function U.padRight(s, n)
	s = tostring(s or "")
	if #s >= n then return string.sub(s, 1, n) end
	return s .. string.rep(" ", n - #s)
end

function U.padLeft(s, n)
	s = tostring(s or "")
	if #s >= n then return s end
	return string.rep(" ", n - #s) .. s
end

-- Replaces {key} slots with values from vars.
function U.template(s, vars)
	return (s:gsub("{(%w+)}", function(k)
		local v = vars[k]
		if v == nil then return "{" .. k .. "}" end
		return tostring(v)
	end))
end

-- Small non-cryptographic hash, 16-bit safe for 32-bit integer builds.
function U.hash(s)
	s = tostring(s)
	local h = 7
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 65521
	end
	return h
end

---------------------------------------------------------------------------
-- number formatting

function U.fmtGrams(g)
	g = U.num(g, 0)
	if g >= 1000 then
		return string.format("%.2fkg", g / 1000)
	end
	return string.format("%dg", U.roundInt(g))
end

function U.fmtMoney(v)
	return string.format("$%.2f", U.num(v, 0))
end

function U.fmtPct(v)
	return string.format("%d%%", U.roundInt(U.clamp(U.num(v, 0), 0, 100)))
end

-- seconds -> "2h05m" / "14m" / "45s"
function U.fmtDuration(sec)
	sec = math.max(0, U.int(sec, 0))
	local h = sec // 3600
	local m = (sec % 3600) // 60
	if h > 0 then
		return string.format("%dh%02dm", h, m)
	elseif m > 0 then
		return string.format("%dm", m)
	end
	return string.format("%ds", sec)
end

function U.fmtHours(hours)
	hours = U.num(hours, 0)
	if hours < 10 then
		return string.format("%.1fh", hours)
	end
	return string.format("%dh", U.roundInt(hours))
end

function U.fmtTemp(t)
	return string.format("%d", U.roundInt(U.num(t, 0))) .. FontData.icon.deg .. "C"
end

---------------------------------------------------------------------------
-- dates (seconds since 2000-01-01 UTC)

U.DAY = 86400

local MONTHS = { "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }

function U.fmtDate(epoch)
	if epoch == nil or epoch == 0 then return "--" end
	local t = Clock.toLocal(epoch)
	return string.format("%02d %s %02d", t.day, MONTHS[t.month] or "???", t.year % 100)
end

-- Date formatting allocates a time table per call and runs every frame on
-- several screens; results are cached per epoch (bounded).
local dateCache, dateCount = {}, 0

local function cachedDate(kind, epoch, fmt)
	local key = kind .. epoch
	local s = dateCache[key]
	if s == nil then
		if dateCount >= 200 then dateCache, dateCount = {}, 0 end
		s = fmt(Clock.toLocal(epoch))
		dateCache[key] = s
		dateCount = dateCount + 1
	end
	return s
end

local function shortDate(t) return string.format("%s %d", MONTHS[t.month] or "???", t.day) end
local function clockHM(t) return string.format("%02d:%02d", t.hour, t.minute) end

function U.fmtShortDate(epoch)
	if epoch == nil or epoch == 0 then return "--" end
	return cachedDate("d", epoch, shortDate)
end

function U.fmtClock(epoch)
	return cachedDate("c", epoch, clockHM)
end

-- "today", "3d ago", "in 5d"
-- Calendar day number of an epoch in local time (days since 1970-01-01 on
-- the proleptic Gregorian calendar). Differences between two day numbers
-- are calendar days, so 23:00 yesterday is "yesterday" at 08:00 today.
local function civilDay(t)
	local y, m, d = t.year, t.month, t.day
	if m <= 2 then y = y - 1 end
	local era = (y >= 0 and y or y - 399) // 400
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = (153 * mp + 2) // 5 + d - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return era * 146097 + doe - 719468
end

function U.dayNumber(epoch)
	return cachedDate("n", epoch, civilDay)
end

-- Calendar days from a to b (b later = positive).
function U.daysBetween(a, b)
	return U.dayNumber(b) - U.dayNumber(a)
end

function U.fmtRelDays(epoch, now)
	if epoch == nil or epoch == 0 then return "never" end
	now = now or Clock.now()
	local d = U.daysBetween(epoch, now)
	if d == 0 then return "today" end
	if d == 1 then return "yesterday" end
	if d > 0 then return d .. "d ago" end
	if d == -1 then return "tomorrow" end
	return "in " .. (-d) .. "d"
end

