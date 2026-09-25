-- Save system: the whole persistent world W goes to playdate.datastore as
-- JSON. JSON objects only have string keys, so tables that use integer ids
-- as keys (relationships, rumor knowledge sets) are packed with "#<id>" keys
-- and restored on load. Arrays stay arrays.

Save = {}
Save.FILE = "mall1997"

local function isArray(t)
  local n = #t
  if n == 0 then return next(t) == nil end
  local c = 0
  for k in pairs(t) do
    if math.type(k) ~= "integer" or k < 1 or k > n then return false end
    c = c + 1
  end
  return c == n
end

-- fields that are rebuilt after loading (plans, in-flight routes)
local TRANSIENT = { plan = true, route = true, leg = true, pi = true, tx = true, ty = true,
  destAct = true, destRef = true, arrivedAt = true, _usedNames = true }

local function isSet(t)
  local c = 0
  for k, v in pairs(t) do
    if math.type(k) ~= "integer" or v ~= true then return false end
    c = c + 1
  end
  return c > 0
end

local function pack(v)
  if type(v) ~= "table" then
    if type(v) == "number" then
      if v ~= v or v == math.huge or v == -math.huge then return 0 end
      if math.type(v) == "float" then
        local r = math.floor(v * 100 + 0.5) / 100
        return math.tointeger(r) or r
      end
    end
    return v
  end
  if isArray(v) then
    local out = {}
    for i = 1, #v do out[i] = pack(v[i]) end
    return out
  end
  if isSet(v) then
    local ids = {}
    for k in pairs(v) do ids[#ids + 1] = k end
    table.sort(ids)
    return { __set = ids }
  end
  local out = {}
  for k, x in pairs(v) do
    if type(x) ~= "function" and not TRANSIENT[k] then
      if type(k) == "number" then out["#" .. tostring(k)] = pack(x) else out[k] = pack(x) end
    end
  end
  return out
end

local function unpack_(v)
  if type(v) == "number" then
    -- JSON has one number type; make ids integers again so "s" .. id is "s12"
    return math.tointeger(v) or v
  end
  if type(v) ~= "table" then return v end
  if v.__set then
    local out = {}
    for _, id in ipairs(v.__set) do out[id] = true end
    return out
  end
  local out = {}
  for k, x in pairs(v) do
    if type(k) == "string" and k:sub(1, 1) == "#" then
      out[math.tointeger(tonumber(k:sub(2))) or tonumber(k:sub(2))] = unpack_(x)
    else
      out[k] = unpack_(x)
    end
  end
  return out
end

Save.pack, Save.unpack = pack, unpack_

function Save.write()
  local data = pack(W)
  playdate.datastore.write(data, Save.FILE)
  W.savedAt = W.t
end

function Save.exists()
  local d = playdate.datastore.read(Save.FILE)
  return d ~= nil and d.ver ~= nil
end

function Save.read()
  local d = playdate.datastore.read(Save.FILE)
  if not d or d.ver ~= World.VERSION then return false end
  W = unpack_(d)
  Areas.invalidate()
  -- rebuild today's plans; people who were out and about start from home
  local day = Clock.day(W.t)
  for _, n in ipairs(W.npcs) do
    if n.status == "active" then
      if n.loc ~= "home" then n.loc = "home"; n.dest = "home" end
      NPCAI.planDay(n, day)
    end
  end
  NPCAI.update(0)
  return true
end

function Save.delete() playdate.datastore.delete(Save.FILE) end
