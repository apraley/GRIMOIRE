-- Ambient crowd: the anonymous shoppers behind the economy's footfall
-- number. The named NPCs are only part of who's in the mall; the other few
-- thousand visitors a day exist in the store math (Stores.footfall) but had
-- no bodies, so the concourses looked empty on a Friday afternoon.
--
-- Extras are pure presentation. Nothing is saved or simulated: each one is a
-- function of (seed, area, index, time). They pace along a strip of open floor,
-- stop to look in windows, and walk on. How many there are follows the day's
-- footfall and the hour, so Saturday afternoon and Black Friday are packed and
-- a January Tuesday morning is mall walkers and nobody else.

Crowd = {}

local T = 16
local CAP = { c1 = 44, c2 = 34, fc = 26, lot = 6 }
local SPEED = 62 -- px per game minute
local CYCLE = 9  -- minutes: walk to a new spot, then linger

-- share of the day's visitors present at a given minute of the day
local function hourCurve(mod, info)
  local h = mod / 60
  local c
  if info.weekend then
    if h < 11 then c = 0.25 elseif h < 13 then c = 0.7 elseif h < 17 then c = 1.0 elseif h < 19 then c = 0.8 else c = 0.45 end
  else
    if h < 11 then c = 0.15 elseif h < 12 then c = 0.3 elseif h < 14 then c = 0.55
    elseif h < 15 then c = 0.4 elseif h < 18 then c = 0.8 elseif h < 20 then c = 0.75 else c = 0.4 end
  end
  -- ramp at opening and closing
  local open, close = info.open or 600, info.close or 1260
  c = c * U.clamp((mod - open) / 30, 0, 1) * U.clamp((close - mod) / 20, 0, 1)
  return c
end

local memo = {}
function Crowd.count(area, t)
  local cap = CAP[area]
  if not cap or not W then return 0 end
  local day = Clock.day(t)
  local mod = Clock.minute(t) // 1
  if memo.day ~= day or memo.mod ~= mod or memo.w ~= W then
    local info = Clock.info(day)
    local foot = info.closed and 0 or Stores.footfall(day)
    memo = { day = day, mod = mod, w = W, share = (foot / 5000) * (info.closed and 0 or hourCurve(mod, info)) }
  end
  return math.floor(U.clamp(cap * memo.share, 0, cap * 2))
end

-- horizontal strips of open floor, long enough to stroll along
local stripCache = {}
local BLOCK = { [Areas.ESC] = true }
local function strips(area)
  local a = Areas.build(area)
  local s = stripCache[area]
  if s and s.a == a then return s end
  s = { list = {}, total = 0, a = a }
  for y = 1, a.h - 2 do
    local x = 0
    while x < a.w do
      while x < a.w and (not Areas.walkable(a, x, y) or BLOCK[a.t[y * a.w + x + 1]]) do x = x + 1 end
      local x0 = x
      while x < a.w and Areas.walkable(a, x, y) and not BLOCK[a.t[y * a.w + x + 1]] do x = x + 1 end
      if x - x0 >= 6 then
        s.list[#s.list + 1] = { y = y, x0 = x0 + 1, x1 = x - 2 }
        s.total = s.total + (x - x0)
      end
    end
  end
  stripCache[area] = s
  return s
end

function Crowd.invalidate() stripCache = {} end

-- a small fixed wardrobe per mall so the sprite cache stays bounded
local looks
local function lookOf(i)
  if not looks then
    looks = {}
    local r = U.rng(W.seed, "crowd-looks")
    for k = 1, 18 do
      looks[k] = { hair = r:i(0, 7), hc = r:i(0, 3), shirt = r:i(0, 5), pants = r:i(0, 2), skin = r:i(0, 2),
        acc = r:chance(0.2) and 1 or 0, build = r:i(0, 2) }
    end
  end
  return looks[1 + (i % #looks)]
end

-- per-extra, per-cycle plan (recomputed once every CYCLE minutes)
local plans = {}

local function stripFor(st, h)
  local pick = h % st.total
  for _, s in ipairs(st.list) do
    local len = s.x1 - s.x0 + 3
    if pick < len then return s end
    pick = pick - len
  end
  return st.list[#st.list]
end

-- the point this extra is standing at the start of cycle k
local function waypoint(area, i, k, strip)
  local h = U.hash(W.seed, "cw", area, i, k)
  local span = strip.x1 - strip.x0
  -- each extra keeps to a home stretch so a cycle's walk is short
  local home = U.hash(W.seed, "ch", area, i) % (span + 1)
  local x = strip.x0 + U.clamp(home + (h % 25) - 12, 0, span)
  return x * T + T // 2 + (h // 25) % 7 - 3
end

-- facing while lingering: toward a shop window if there is one
local function faceAt(a, y, x, i)
  local tx = math.floor(x / T)
  local up = a.t[(y - 1) * a.w + tx + 1]
  local dn = a.t[(y + 1) * a.w + tx + 1]
  if up == Areas.WINDOW or up == Areas.FACADE then return "up" end
  if dn == Areas.WINDOW or dn == Areas.FACADE then return "down" end
  return ({ "left", "right", "down" })[1 + i % 3]
end

local function plan(area, i, k, st)
  local key = area .. i
  local p = plans[key]
  if p and p.k == k then return p end
  local strip = stripFor(st, U.hash(W.seed, "cs", area, i))
  local y = strip.y * T + T // 2 + (i % 5) - 2
  local xa = waypoint(area, i, k, strip)
  local xb = waypoint(area, i, k + 1, strip)
  local walk = math.abs(xb - xa) / SPEED
  local start = (U.hash(W.seed, "cd", area, i, k) % 100) / 100 * math.max(0, CYCLE - walk)
  p = { k = k, xa = xa, xb = xb, y = y, walk = walk, start = start,
    faceA = faceAt(st.a, strip.y, xa, i), faceB = faceAt(st.a, strip.y, xb, i) }
  plans[key] = p
  return p
end

-- visible extras in [cx, cx+400): calls fn(x, y, look, dir, frame, index)
-- sub: fraction of the current minute the display is at (see NPCAI.pos)
function Crowd.each(area, cx, fn, sub)
  local n = Crowd.count(area, W.t)
  if n == 0 then return end
  local st = strips(area)
  if #st.list == 0 then return end
  local m = math.floor(W.t)
  local frac = (W.t - m) + (sub or 0)
  for i = 1, n do
    local phase = (i * 7919) % (CYCLE * 100) / 100
    -- a small local clock so it stays precise in single-precision floats;
    -- 5040 is a multiple of CYCLE
    local tt = (m % 5040) + frac + phase
    local kk = math.floor(tt / CYCLE)
    local p = plan(area, i, kk + (m // 5040) * (5040 // CYCLE), st)
    local u = tt - kk * CYCLE
    local x, dir, moving
    if u < p.start then x, dir, moving = p.xa, p.faceA, false
    elseif u < p.start + p.walk then
      local f = (u - p.start) / p.walk
      x = p.xa + (p.xb - p.xa) * f
      dir = p.xb >= p.xa and "right" or "left"
      moving = true
    else x, dir, moving = p.xb, p.faceB, false end
    if x > cx - 20 and x < cx + 420 then
      fn(x, p.y, lookOf(i), dir, moving and ((Gfx.frame // 6 + i) % 2 + 1) or 0, i)
    end
  end
end
