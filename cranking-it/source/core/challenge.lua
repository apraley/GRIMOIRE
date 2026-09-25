-- CRANKING IT :: core/challenge
-- Challenge modifiers shared by every machine, per-machine challenge
-- definitions, and the DAILY MACHINE generated deterministically from the
-- calendar date (same machine, seed, modifier and goal for every player).

Challenge = {}

-- generic modifiers are implemented by PlayScene so they work on any machine
Challenge.MODS = {
  rusty = { name = "RUSTY CRANK", desc = "The crank sticks, then lurches." },
  fog   = { name = "SEA FOG", desc = "A white haze hangs over everything." },
  haste = { name = "HASTE", desc = "The machine runs a third faster." },
}
Challenge.MOD_ORDER = { "rusty", "fog", "haste" }

function Challenge.modNames(mods)
  local out = {}
  for _, k in ipairs(Challenge.MOD_ORDER) do
    if mods and mods[k] then out[#out + 1] = Challenge.MODS[k].name end
  end
  return table.concat(out, " + ")
end

------------------------------------------------------------------------
-- dates
------------------------------------------------------------------------
local MONTH_DAYS <const> = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
local function isLeap(y) return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0 end

-- inverse of U.dayNumber (days since 2000-01-01, n >= 0)
local function civilFromDays(n)
  local y = 2000
  while true do
    local len = isLeap(y) and 366 or 365
    if n >= len then n = n - len y = y + 1 else break end
  end
  local m = 1
  while true do
    local len = MONTH_DAYS[m] + ((m == 2 and isLeap(y)) and 1 or 0)
    if n >= len then n = n - len m = m + 1 else break end
  end
  return y, m, n + 1
end

function Challenge.dayOfKey(key)
  local y, m, d = tonumber(key:sub(1, 4)), tonumber(key:sub(5, 6)), tonumber(key:sub(7, 8))
  return U.dayNumber({ year = y, month = m, day = d })
end

function Challenge.keyForDay(n)
  local y, m, d = civilFromDays(n)
  return string.format("%04d%02d%02d", y, m, d)
end

------------------------------------------------------------------------
-- daily machine
------------------------------------------------------------------------
function Challenge.daily(t)
  t = t or playdate.getTime()
  local key = U.dateKey(t)
  local rng = U.rng("daily-machine-" .. key)
  -- a machine is never picked twice in a row: walk a date-seeded order
  local day = U.dayNumber(t)
  local n = #Machines.list
  local cycle = day // n
  local order = {}
  for i = 1, n do order[i] = i end
  U.rng("daily-cycle-" .. cycle):shuffle(order)
  local def = Machines.list[order[day % n + 1]]
  local mods = {}
  local r = rng:float()
  if r < 0.25 then mods.rusty = true elseif r < 0.45 then mods.fog = true elseif r < 0.6 then mods.haste = true end
  local difficulty = rng:range(1, 3)
  local mode = "standard"
  local medals = def.medals[mode] or { 1, 2, 3 }
  local goal = medals[math.min(3, difficulty)] or medals[2]
  if difficulty == 3 then goal = medals[2] end
  return {
    key = key, id = def.id, def = def, mode = mode, difficulty = difficulty,
    seed = rng:next(), mods = mods, goal = goal,
  }
end

function Challenge.dailyParams(d)
  return { id = d.id, mode = d.mode, difficulty = d.difficulty, seed = d.seed, mods = d.mods, daily = d.key, goal = d.goal }
end

function Challenge.challengeParams(def, c)
  return {
    id = def.id, mode = c.mode or "standard", difficulty = c.difficulty or 2,
    seed = U.hash(def.id .. c.id), mods = c.mods or {}, challengeId = c.id, goal = c.goal,
  }
end
