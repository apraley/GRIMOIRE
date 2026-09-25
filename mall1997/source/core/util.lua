-- Core utilities: deterministic RNG, table helpers, text helpers.
-- Nothing in here touches the Playdate API, so the simulation layer can be
-- run headless under stock Lua 5.4 (see tools/).

U = {}

-- ------------------------------------------------------------------ RNG
-- xorshift32 so that generation is identical on device, simulator and the
-- headless harness (math.random differs between runtimes).
RNG = {}
RNG.__index = RNG

function RNG.new(seed)
  local s = math.tointeger(seed) or math.floor(seed)
  s = s & 0xFFFFFFFF
  if s == 0 then s = 0x9E3779B9 end
  local r = setmetatable({ s = s }, RNG)
  for _ = 1, 4 do r:next() end
  return r
end

function RNG:next()
  local x = self.s
  x = x ~ ((x << 13) & 0xFFFFFFFF)
  x = x ~ (x >> 17)
  x = x ~ ((x << 5) & 0xFFFFFFFF)
  self.s = x & 0xFFFFFFFF
  return self.s
end

-- float in [0,1)
function RNG:f() return self:next() / 4294967296.0 end
-- integer in [a,b]
function RNG:i(a, b) if b < a then return a end return a + (self:next() % (b - a + 1)) end
function RNG:chance(p) return self:f() < p end
function RNG:pick(t) if #t == 0 then return nil end return t[1 + (self:next() % #t)] end
function RNG:range(a, b) return a + (b - a) * self:f() end
function RNG:shuffle(t)
  for i = #t, 2, -1 do
    local j = 1 + (self:next() % i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end
-- weighted pick: list of {item, weight} or parallel weight fn
function RNG:weighted(list, wfn)
  local total = 0
  for i = 1, #list do total = total + math.max(0, wfn(list[i])) end
  if total <= 0 then return list[1] end
  local r = self:f() * total
  for i = 1, #list do
    r = r - math.max(0, wfn(list[i]))
    if r <= 0 then return list[i] end
  end
  return list[#list]
end

-- stable hash of any number of values -> 32-bit int (for derived content)
function U.hash(...)
  local h = 2166136261
  local args = { ... }
  for i = 1, #args do
    local s = tostring(args[i])
    for j = 1, #s do
      h = h ~ s:byte(j)
      h = (h * 16777619) & 0xFFFFFFFF
    end
    h = h ~ 0x5bd1e995
    h = (h * 16777619) & 0xFFFFFFFF
  end
  return h
end

-- a throwaway RNG derived from stable keys (used for content that is
-- re-derived rather than stored: rack contents, room furniture, etc.)
function U.rng(...) return RNG.new(U.hash(...)) end

-- ------------------------------------------------------------------ math
function U.clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
function U.lerp(a, b, t) return a + (b - a) * t end
function U.round(v) return math.floor(v + 0.5) end
function U.sign(v) if v < 0 then return -1 elseif v > 0 then return 1 end return 0 end
function U.dist(ax, ay, bx, by) local dx, dy = ax - bx, ay - by return math.sqrt(dx * dx + dy * dy) end

-- ------------------------------------------------------------------ tables
function U.count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function U.contains(t, v) for i = 1, #t do if t[i] == v then return true end end return false end
function U.removeValue(t, v)
  for i = #t, 1, -1 do if t[i] == v then table.remove(t, i) return true end end
  return false
end
function U.addUnique(t, v) if not U.contains(t, v) then t[#t + 1] = v end end
function U.copy(t) local r = {} for k, v in pairs(t) do r[k] = v end return r end
function U.keys(t)
  local r = {}
  for k in pairs(t) do r[#r + 1] = k end
  table.sort(r, function(a, b)
    if type(a) == "number" and type(b) == "number" then return a < b end
    return tostring(a) < tostring(b)
  end)
  return r
end
function U.filter(t, f) local r = {} for i = 1, #t do if f(t[i]) then r[#r + 1] = t[i] end end return r end
function U.map(t, f) local r = {} for i = 1, #t do r[i] = f(t[i]) end return r end
function U.sum(t, f) local s = 0 for i = 1, #t do s = s + (f and f(t[i]) or t[i]) end return s end
-- keep at most n newest entries (append order)
function U.trim(t, n) while #t > n do table.remove(t, 1) end end

-- ------------------------------------------------------------------ text
function U.money(cents)
  local neg = cents < 0
  cents = math.abs(math.floor(cents + 0.5))
  local s = string.format("$%d.%02d", cents // 100, cents % 100)
  if neg then s = "-" .. s end
  return s
end
function U.dollars(cents) return "$" .. tostring(math.floor(cents / 100 + 0.5)) end

function U.cap(s) return (s:gsub("^%l", string.upper)) end

-- "{name} likes {thing}" style templating
function U.fmt(template, vars)
  return (template:gsub("{(%w+)}", function(k)
    local v = vars[k]
    if v == nil then return "{" .. k .. "}" end
    return tostring(v)
  end))
end

-- word wrap by character budget (renderer uses real font metrics; this is
-- used by the headless tools and for pager lines)
function U.wrap(s, width)
  local lines, line = {}, ""
  for word in s:gmatch("%S+") do
    if #line + #word + 1 > width and #line > 0 then
      lines[#lines + 1] = line
      line = word
    else
      line = (#line > 0) and (line .. " " .. word) or word
    end
  end
  if #line > 0 then lines[#lines + 1] = line end
  return lines
end

function U.pad2(n) return string.format("%02d", n) end

function U.plural(n, one, many) if n == 1 then return one end return many or (one .. "s") end

function U.join(t, sep, lastSep)
  if #t == 0 then return "" end
  if #t == 1 then return t[1] end
  if not lastSep then return table.concat(t, sep) end
  return table.concat(t, sep, 1, #t - 1) .. lastSep .. t[#t]
end
