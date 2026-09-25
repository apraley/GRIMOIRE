-- Small, dependency-free helpers shared by core and UI.
-- Everything here must run both on device and under the headless test harness.

Util = {}

function Util.clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function Util.wrap(i, n)
	if n <= 0 then return 1 end
	return ((i - 1) % n) + 1
end

function Util.trim(s)
	if s == nil then return "" end
	return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Util.isBlank(s)
	return s == nil or Util.trim(s) == ""
end

function Util.upper(s)
	if s == nil then return "" end
	return string.upper(tostring(s))
end

function Util.int(v, default)
	local n = tonumber(v)
	if n == nil then return default end
	return math.floor(n + 0.0)
end

function Util.pad2(n)
	return string.format("%02d", math.floor(n or 0))
end

function Util.indexOf(list, value)
	if list == nil then return nil end
	for i = 1, #list do
		if list[i] == value then return i end
	end
	return nil
end

function Util.copy(t)
	if type(t) ~= "table" then return t end
	local r = {}
	for k, v in pairs(t) do r[k] = v end
	return r
end

function Util.deepcopy(t)
	if type(t) ~= "table" then return t end
	local r = {}
	for k, v in pairs(t) do r[k] = Util.deepcopy(v) end
	return r
end

function Util.concat(a, b)
	local r = {}
	for i = 1, #(a or {}) do r[#r + 1] = a[i] end
	for i = 1, #(b or {}) do r[#r + 1] = b[i] end
	return r
end

-- Order-preserving unique merge of string lists (case-insensitive), dropping blanks.
function Util.uniq(list)
	local seen, r = {}, {}
	for i = 1, #list do
		local v = list[i]
		if v ~= nil and not Util.isBlank(v) then
			local key = Util.upper(v)
			if not seen[key] then
				seen[key] = true
				r[#r + 1] = v
			end
		end
	end
	return r
end

function Util.median(list)
	local n = #list
	if n == 0 then return nil end
	local s = {}
	for i = 1, n do s[i] = list[i] end
	table.sort(s)
	if n % 2 == 1 then return s[(n + 1) // 2] end
	return (s[n // 2] + s[n // 2 + 1]) / 2
end

function Util.mean(list)
	if #list == 0 then return nil end
	local t = 0
	for i = 1, #list do t = t + list[i] end
	return t / #list
end

function Util.split(s, sep)
	local r = {}
	if s == nil or s == "" then return r end
	for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do
		r[#r + 1] = part
	end
	return r
end

-- "a, b ,c" -> {"a","b","c"}
function Util.splitList(s)
	local r = {}
	for _, part in ipairs(Util.split(s or "", ",")) do
		local t = Util.trim(part)
		if t ~= "" then r[#r + 1] = t end
	end
	return r
end

function Util.joinList(list, sep)
	if type(list) ~= "table" then return list or "" end
	return table.concat(list, sep or ", ")
end

---------------------------------------------------------------------------
-- Time. All stored timestamps are Playdate epoch seconds (since 2000-01-01
-- UTC). Local wall-clock conversion uses the OS so the device timezone applies.
---------------------------------------------------------------------------

Util.clock = nil -- optional override used by the test harness

function Util.now()
	if Util.clock then return Util.clock() end
	local s = playdate.getSecondsSinceEpoch()
	return s
end

function Util.nowMs()
	return playdate.getCurrentTimeMilliseconds()
end

function Util.localTime(epoch)
	if epoch == nil then return playdate.getTime() end
	return playdate.timeFromEpoch(math.floor(epoch), 0)
end

function Util.fmtClock(epoch, use24)
	local t = Util.localTime(epoch)
	if use24 == false then
		local h = t.hour % 12
		if h == 0 then h = 12 end
		return string.format("%d:%02d%s", h, t.minute, t.hour < 12 and "A" or "P")
	end
	return string.format("%02d:%02d", t.hour, t.minute)
end

function Util.fmtDate(epoch)
	local t = Util.localTime(epoch)
	return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

function Util.fmtStamp(epoch)
	local t = Util.localTime(epoch)
	return string.format("%04d%02d%02d-%02d%02d", t.year, t.month, t.day, t.hour, t.minute)
end

-- minutes -> "1H05" / "45M"
function Util.fmtDur(minutes)
	if minutes == nil then return "--" end
	minutes = math.floor(minutes + 0.5)
	if minutes < 60 then return minutes .. "M" end
	return string.format("%dH%02d", minutes // 60, minutes % 60)
end

-- "07:30" <-> minutes since midnight
function Util.parseHM(s)
	local h, m = tostring(s or ""):match("^(%d+):(%d+)$")
	if not h then return nil end
	return tonumber(h) * 60 + tonumber(m)
end

function Util.fmtHM(mins)
	mins = math.floor(mins) % (24 * 60)
	return string.format("%02d:%02d", mins // 60, mins % 60)
end

-- "2026-09-25" +/- days, using the OS calendar via epoch conversion.
function Util.shiftDate(s, days)
	local y, mo, d = tostring(s or ""):match("^(%d+)-(%d+)-(%d+)$")
	local base
	if y then
		base = playdate.epochFromTime({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
			hour = 12, minute = 0, second = 0, millisecond = 0 })
	else
		base = Util.now()
	end
	return Util.fmtDate(base + days * 86400)
end

-- Short slug for filenames: "Northwind: First Light" -> "NORTHWIND-FIRST-LIGHT"
function Util.slug(s)
	local r = Util.upper(s):gsub("[^%w]+", "-"):gsub("^-+", ""):gsub("-+$", "")
	if r == "" then r = "PROJECT" end
	return r:sub(1, 24)
end

-- Keep only printable ASCII; the on-device keyboard and system font are ASCII-centric.
function Util.ascii(s)
	if s == nil then return "" end
	return (tostring(s):gsub("\226\128\148", "-"):gsub("\226\128\147", "-"):gsub("[^\32-\126]", ""))
end

return Util
