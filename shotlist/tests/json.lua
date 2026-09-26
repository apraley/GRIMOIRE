-- Minimal JSON for the headless harness (stands in for the Playdate SDK's
-- built-in `json`). Arrays: tables whose keys are exactly 1..n.

local J = {}

local function isArray(t)
	local n = 0
	for k in pairs(t) do
		if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then return false end
		n = n + 1
	end
	for i = 1, n do if t[i] == nil then return false end end
	return true, n
end

local ESC = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function encStr(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		return ESC[c] or string.format("\\u%04x", c:byte())
	end) .. '"'
end

local encode
encode = function(v, pretty, indent)
	local t = type(v)
	if t == "nil" then return "null"
	elseif t == "boolean" then return tostring(v)
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then error("cannot encode non-finite number") end
		if math.type(v) == "integer" then return tostring(v) end
		if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format("%d", v) end
		return string.format("%.14g", v)
	elseif t == "string" then return encStr(v)
	elseif t == "table" then
		indent = indent or ""
		local ni = indent .. "  "
		local nl = pretty and "\n" or ""
		local sep = pretty and ": " or ":"
		local arr, n = isArray(v)
		if arr then
			if n == 0 then return "[]" end
			local parts = {}
			for i = 1, n do parts[i] = (pretty and ni or "") .. encode(v[i], pretty, ni) end
			return "[" .. nl .. table.concat(parts, "," .. nl) .. nl .. (pretty and indent or "") .. "]"
		end
		local keys = {}
		for k in pairs(v) do
			if type(k) ~= "string" then error("cannot encode non-string key " .. tostring(k)) end
			keys[#keys + 1] = k
		end
		table.sort(keys)
		local parts = {}
		for i, k in ipairs(keys) do
			parts[i] = (pretty and ni or "") .. encStr(k) .. sep .. encode(v[k], pretty, ni)
		end
		return "{" .. nl .. table.concat(parts, "," .. nl) .. nl .. (pretty and indent or "") .. "}"
	end
	error("cannot encode " .. t)
end

function J.encode(v) return encode(v, false) end
function J.encodePretty(v) return encode(v, true) end

local function decodeError(s, i, msg) error(string.format("json decode error at %d: %s", i, msg)) end

local decodeValue

local function skip(s, i)
	local _, e = s:find("^[ \t\r\n]*", i)
	return e + 1
end

local function decodeString(s, i)
	local out = {}
	local j = i + 1
	while true do
		local c = s:sub(j, j)
		if c == "" then decodeError(s, j, "unterminated string") end
		if c == '"' then return table.concat(out), j + 1 end
		if c == "\\" then
			local e = s:sub(j + 1, j + 1)
			local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
			if map[e] then out[#out + 1] = map[e]; j = j + 2
			elseif e == "u" then
				local hex = s:sub(j + 2, j + 5)
				out[#out + 1] = utf8.char(tonumber(hex, 16))
				j = j + 6
			else decodeError(s, j, "bad escape") end
		else
			out[#out + 1] = c
			j = j + 1
		end
	end
end

decodeValue = function(s, i)
	i = skip(s, i)
	local c = s:sub(i, i)
	if c == "{" then
		local obj = {}
		i = skip(s, i + 1)
		if s:sub(i, i) == "}" then return obj, i + 1 end
		while true do
			i = skip(s, i)
			if s:sub(i, i) ~= '"' then decodeError(s, i, "expected key") end
			local k
			k, i = decodeString(s, i)
			i = skip(s, i)
			if s:sub(i, i) ~= ":" then decodeError(s, i, "expected :") end
			local v
			v, i = decodeValue(s, i + 1)
			obj[k] = v
			i = skip(s, i)
			local d = s:sub(i, i)
			if d == "}" then return obj, i + 1 end
			if d ~= "," then decodeError(s, i, "expected , or }") end
			i = i + 1
		end
	elseif c == "[" then
		local arr = {}
		i = skip(s, i + 1)
		if s:sub(i, i) == "]" then return arr, i + 1 end
		while true do
			local v
			v, i = decodeValue(s, i)
			arr[#arr + 1] = v
			i = skip(s, i)
			local d = s:sub(i, i)
			if d == "]" then return arr, i + 1 end
			if d ~= "," then decodeError(s, i, "expected , or ]") end
			i = i + 1
		end
	elseif c == '"' then
		return decodeString(s, i)
	elseif s:sub(i, i + 3) == "true" then return true, i + 4
	elseif s:sub(i, i + 4) == "false" then return false, i + 5
	elseif s:sub(i, i + 3) == "null" then return nil, i + 4
	else
		local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
		if num == nil or num == "" then decodeError(s, i, "unexpected '" .. c .. "'") end
		local v = math.tointeger(tonumber(num)) or tonumber(num)
		return v, i + #num
	end
end

function J.decode(s)
	local v, i = decodeValue(s, 1)
	i = skip(s, i)
	if i <= #s then decodeError(s, i, "trailing garbage") end
	return v
end

return J
