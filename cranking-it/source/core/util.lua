-- CRANKING IT :: core/util
-- Small math/table helpers, a deterministic RNG, and a tiny class helper.
--
-- Playdate's Lua may run with 32-bit numbers, so every bit-twiddling
-- routine here masks to 32 bits and only relies on logical shifts. The same
-- seed produces the same sequence on device, Simulator and desktop Lua.

U = {}

local floor <const> = math.floor
local sqrt <const> = math.sqrt
local abs <const> = math.abs

function U.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function U.lerp(a, b, t) return a + (b - a) * t end

function U.invLerp(a, b, v)
  if b == a then return 0 end
  return (v - a) / (b - a)
end

function U.remap(v, a, b, c, d) return c + (d - c) * U.clamp(U.invLerp(a, b, v), 0, 1) end

function U.sign(v)
  if v > 0 then return 1 elseif v < 0 then return -1 end
  return 0
end

-- move v toward target by at most step
function U.approach(v, target, step)
  if v < target then
    v = v + step
    if v > target then v = target end
  elseif v > target then
    v = v - step
    if v < target then v = target end
  end
  return v
end

-- frame-rate independent exponential smoothing
function U.damp(v, target, rate, dt) return target + (v - target) * math.exp(-rate * dt) end

function U.smoothstep(t)
  t = U.clamp(t, 0, 1)
  return t * t * (3 - 2 * t)
end

function U.wrap(v, lo, hi)
  local r = hi - lo
  return lo + (v - lo) % r
end

-- signed shortest difference b - a in degrees, range (-180, 180]
function U.angleDiff(a, b)
  local d = (b - a) % 360
  if d > 180 then d = d - 360 end
  return d
end

function U.dist(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  return sqrt(dx * dx + dy * dy)
end

function U.round(v) return floor(v + 0.5) end

-- integer that is safe to pass to string.format("%d")
function U.int(v) return floor(v + 0.0) // 1 end

function U.commas(n)
  n = floor(n)
  local s = tostring(abs(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  if n < 0 then out = "-" .. out end
  return out
end

function U.timeStr(sec)
  sec = math.max(0, floor(sec))
  return string.format("%d:%02d", sec // 60, sec % 60)
end

local ROMAN = { { 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" } }
function U.roman(n)
  local out = ""
  for _, p in ipairs(ROMAN) do
    while n >= p[1] do out = out .. p[2] n = n - p[1] end
  end
  return out
end

------------------------------------------------------------------------
-- tables
------------------------------------------------------------------------
function U.copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

function U.deepcopy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = U.deepcopy(v) end
  return c
end

-- fill missing keys of t from defaults (recursively for tables)
function U.mergeDefaults(t, defaults)
  for k, v in pairs(defaults) do
    if t[k] == nil then
      t[k] = U.deepcopy(v)
    elseif type(v) == "table" and type(t[k]) == "table" and next(v) ~= nil and #v == 0 then
      U.mergeDefaults(t[k], v)
    end
  end
  return t
end

function U.indexOf(t, v)
  for i = 1, #t do if t[i] == v then return i end end
  return nil
end

function U.clear(t) for k in pairs(t) do t[k] = nil end end

------------------------------------------------------------------------
-- hashing (FNV-1a, 32-bit)
------------------------------------------------------------------------
local MASK <const> = 0xffffffff
function U.hash(s)
  s = tostring(s)
  local h = 0x811c9dc5 -- 2166136261 (hex literal wraps safely on 32-bit Lua)
  for i = 1, #s do
    h = ((h ~ s:byte(i)) * 16777619) & MASK
  end
  return h & 0x7fffffff -- non-negative, identical on 32/64-bit Lua
end

------------------------------------------------------------------------
-- RNG: xorshift32. Deterministic on every Lua number configuration.
------------------------------------------------------------------------
local RNG = {}
RNG.__index = RNG

function U.rng(seed)
  local r = setmetatable({}, RNG)
  r:seed(seed or 1)
  return r
end

function RNG:seed(seed)
  if type(seed) ~= "number" then seed = U.hash(seed) end
  local s = floor(seed) & MASK
  if s == 0 then s = 0x9e3779b9 & MASK end
  self.s = s
  -- warm up
  for _ = 1, 4 do self:next() end
end

function RNG:next()
  local x = self.s
  x = (x ~ (x << 13)) & MASK
  x = (x ~ (x >> 17)) & MASK
  x = (x ~ (x << 5)) & MASK
  self.s = x
  return x >> 1 -- 31-bit non-negative, identical on 32/64-bit Lua
end

-- float in [0, 1)
function RNG:float()
  return ((self:next() >> 7) & 0xffffff) / 16777216
end

-- integer in [a, b]
function RNG:range(a, b)
  if b < a then a, b = b, a end
  return a + floor(self:float() * (b - a + 1))
end

function RNG:between(a, b) return a + (b - a) * self:float() end

function RNG:chance(p) return self:float() < p end

function RNG:pick(t) return t[self:range(1, #t)] end

function RNG:shuffle(t)
  for i = #t, 2, -1 do
    local j = self:range(1, i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

function RNG:gauss()
  local u = math.max(1e-6, self:float())
  local v = self:float()
  return sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v)
end

-- pick index by weights array
function RNG:weighted(weights)
  local total = 0
  for i = 1, #weights do total = total + weights[i] end
  local r = self:float() * total
  for i = 1, #weights do
    r = r - weights[i]
    if r < 0 then return i end
  end
  return #weights
end

function RNG:state() return self.s end
function RNG:setState(s) self.s = floor(s) & MASK if self.s == 0 then self.s = 1 end end

------------------------------------------------------------------------
-- class helper
------------------------------------------------------------------------
-- local Foo = U.class()            -- base class
-- local Bar = U.class(Foo)         -- subclass
-- function Bar:init(a) Foo.init(self) ... end
-- local b = Bar.new(1)
function U.class(parent)
  local C = {}
  C.__index = C
  if parent then setmetatable(C, { __index = parent }) end
  C.super = parent
  C.new = function(...)
    local o = setmetatable({}, C)
    if o.init then o:init(...) end
    return o
  end
  return C
end

------------------------------------------------------------------------
-- ring buffer of numbers (fixed size, no per-push allocation)
------------------------------------------------------------------------
local Ring = {}
Ring.__index = Ring
function U.ring(n, fill)
  local r = setmetatable({ n = n, i = 0, count = 0 }, Ring)
  for k = 1, n do r[k] = fill or 0 end
  return r
end
function Ring:push(v)
  self.i = self.i % self.n + 1
  self[self.i] = v
  if self.count < self.n then self.count = self.count + 1 end
end
-- k = 0 is newest, k = 1 previous...
function Ring:get(k)
  local idx = (self.i - 1 - k) % self.n + 1
  return self[idx]
end
function Ring:mean()
  if self.count == 0 then return 0 end
  local s = 0
  for k = 0, self.count - 1 do s = s + self:get(k) end
  return s / self.count
end

------------------------------------------------------------------------
-- string cache to avoid per-frame string allocation for HUD numbers
------------------------------------------------------------------------
local fmtCache = {}
-- U.cached("score", "%06d", 123) returns the same string object while the
-- value is unchanged.
function U.cached(key, fmt, v)
  local c = fmtCache[key]
  if c and c.v == v and c.fmt == fmt then return c.s end
  if not c then c = {} fmtCache[key] = c end
  c.v, c.fmt = v, fmt
  c.s = string.format(fmt, v)
  return c.s
end

-- date helpers -----------------------------------------------------------
function U.dateKey(t)
  t = t or playdate.getTime()
  return string.format("%04d%02d%02d", t.year, t.month, t.day)
end

-- days since 2000-01-01 for a date table (proleptic Gregorian)
function U.dayNumber(t)
  local y, m, d = t.year, t.month, t.day
  if m <= 2 then y = y - 1 m = m + 12 end
  return 365 * y + y // 4 - y // 100 + y // 400 + (153 * (m - 3) + 2) // 5 + d - 730426
end
