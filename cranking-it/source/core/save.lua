-- CRANKING IT :: core/save
-- Persistent progress via playdate.datastore.
--
-- Reliability: the save is written alternately to two slots ("save_a",
-- "save_b"). Each slot stores {seq, sum, payload} where payload is the
-- JSON-encoded save and sum is its FNV hash. On load, both slots are read
-- and the newest slot whose checksum verifies wins, so a crash or power
-- loss mid-write can only ever lose the most recent change.

Save = {}

local SLOTS <const> = { "save_a", "save_b" }
local VERSION <const> = 3

Save.DEFAULTS = {
  version = VERSION,
  gears = 0,          -- spendable
  gearsEarned = 0,    -- lifetime
  firstRun = true,
  introSeen = false,
  machines = {},      -- [id] = machine record (see Save.machine)
  meta = {},          -- meta achievements [id] = true
  exhibits = {},      -- [id] = true
  lore = {},          -- [id] = true (lore fragments read/unlocked)
  themes = { current = "woodcut", owned = { woodcut = true } },
  daily = { lastKey = "", streak = 0, bestStreak = 0, played = {}, completed = 0 },
  settings = { sound = true, reduceShake = false },
  totals = { plays = 0, seconds = 0, crankDegrees = 0 },
  suspend = false,    -- or {id=, params=, state=}
  hubX = 0,
}

local MACHINE_DEFAULTS = {
  unlocked = false,
  tutorialDone = false,
  plays = 0,
  best = {},          -- [mode] = score
  medals = {},        -- [mode] = 0..3
  stats = {},         -- free-form counters defined by each machine
  achievements = {},  -- [achId] = true
  challenges = {},    -- [challengeId] = {owned=bool, best=score, done=bool}
}

Save.data = nil
Save.dirty = false
Save.seq = 0
Save.lastError = nil

local function encode(t)
  local ok, s = pcall(json.encode, t)
  if ok then return s end
  Save.lastError = s
  return nil
end

local function readSlot(name)
  local ok, t = pcall(playdate.datastore.read, name)
  if not ok or type(t) ~= "table" then return nil end
  if type(t.payload) ~= "string" or type(t.seq) ~= "number" then return nil end
  if U.hash(t.payload) ~= t.sum then return nil end
  local ok2, data = pcall(json.decode, t.payload)
  if not ok2 or type(data) ~= "table" then return nil end
  return data, t.seq
end

function Save.load()
  local best, bestSeq = nil, -1
  for _, name in ipairs(SLOTS) do
    local d, seq = readSlot(name)
    if d and seq > bestSeq then best, bestSeq = d, seq end
  end
  if best then
    Save.data = best
    Save.seq = bestSeq
  else
    Save.data = U.deepcopy(Save.DEFAULTS)
    Save.seq = 0
  end
  Save.migrate()
  return Save.data
end

function Save.migrate()
  local d = Save.data
  U.mergeDefaults(d, Save.DEFAULTS)
  if type(d.machines) ~= "table" then d.machines = {} end
  for id, m in pairs(d.machines) do
    if type(m) ~= "table" then d.machines[id] = {} m = d.machines[id] end
    U.mergeDefaults(m, MACHINE_DEFAULTS)
  end
  d.version = VERSION
end

function Save.machine(id)
  local m = Save.data.machines[id]
  if not m then
    m = U.deepcopy(MACHINE_DEFAULTS)
    Save.data.machines[id] = m
  end
  return m
end

function Save.markDirty() Save.dirty = true end

-- Write now. Returns true on success.
function Save.flush()
  if not Save.data then return false end
  local payload = encode(Save.data)
  if not payload then
    print("SAVE ERROR: " .. tostring(Save.lastError))
    return false
  end
  Save.seq = Save.seq + 1
  local slot = SLOTS[(Save.seq % 2) + 1]
  local ok, err = pcall(playdate.datastore.write, { seq = Save.seq, sum = U.hash(payload), payload = payload }, slot)
  if not ok then
    Save.lastError = err
    print("SAVE ERROR: " .. tostring(err))
    return false
  end
  Save.dirty = false
  return true
end

-- Debounced autosave: call every frame; writes at most every few seconds.
local sinceWrite = 0
function Save.update(dt)
  sinceWrite = sinceWrite + dt
  if Save.dirty and sinceWrite > 3 then
    sinceWrite = 0
    Save.flush()
  end
end

function Save.wipe()
  for _, name in ipairs(SLOTS) do playdate.datastore.delete(name) end
  Save.data = U.deepcopy(Save.DEFAULTS)
  Save.seq = 0
  Save.migrate()
  Save.flush()
end

------------------------------------------------------------------------
-- Gears (currency)
------------------------------------------------------------------------
function Save.addGears(n, reason)
  if n <= 0 then return end
  Save.data.gears = Save.data.gears + n
  Save.data.gearsEarned = Save.data.gearsEarned + n
  Save.markDirty()
end

function Save.spendGears(n)
  if Save.data.gears < n then return false end
  Save.data.gears = Save.data.gears - n
  Save.markDirty()
  Save.flush()
  return true
end

-- stats helpers --------------------------------------------------------
function Save.statAdd(id, key, delta)
  local s = Save.machine(id).stats
  s[key] = (s[key] or 0) + (delta or 1)
  Save.markDirty()
  return s[key]
end

function Save.statMax(id, key, v)
  local s = Save.machine(id).stats
  if s[key] == nil or v > s[key] then s[key] = v Save.markDirty() return true end
  return false
end

function Save.stat(id, key) return Save.machine(id).stats[key] or 0 end
