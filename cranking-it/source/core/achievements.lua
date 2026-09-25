-- CRANKING IT :: core/achievements
-- Per-machine achievements (declared in each machine's def) and museum-wide
-- meta achievements. Each unlock pays one gear.

Achievements = {}

local session = {}

local function findDef(machineId, achId)
  local def = Machines.get(machineId)
  if not def then return nil end
  for _, a in ipairs(def.achievements) do if a.id == achId then return a end end
  return nil
end

function Achievements.has(machineId, achId)
  return Save.machine(machineId).achievements[achId] == true
end

function Achievements.unlock(machineId, achId)
  local rec = Save.machine(machineId)
  if rec.achievements[achId] then return false end
  local a = findDef(machineId, achId)
  if not a then print("unknown achievement " .. machineId .. "/" .. achId) return false end
  rec.achievements[achId] = true
  Save.addGears(a.gears or 1)
  UI.toast(a.name, "+" .. (a.gears or 1) .. " gear  " .. a.desc:sub(1, 26), "star")
  Audio.sfx.achievement()
  session[#session + 1] = a
  Save.markDirty()
  return true
end

-- achievements unlocked since the last drain (shown on the results card)
function Achievements.drainSession()
  local out = session
  session = {}
  return out
end

function Achievements.countFor(def)
  local rec = Save.machine(def.id)
  local n = 0
  for _, a in ipairs(def.achievements) do if rec.achievements[a.id] then n = n + 1 end end
  return n, #def.achievements
end

function Achievements.total()
  local got, all = 0, 0
  for _, def in ipairs(Machines.list) do
    local g, a = Achievements.countFor(def)
    got, all = got + g, all + a
  end
  for _, m in ipairs(Achievements.META) do
    all = all + 1
    if Save.data.meta[m.id] then got = got + 1 end
  end
  return got, all
end

------------------------------------------------------------------------
-- meta achievements (museum-wide)
------------------------------------------------------------------------
local function countMachines(pred)
  local n = 0
  for _, def in ipairs(Machines.list) do if pred(def, Save.machine(def.id)) then n = n + 1 end end
  return n
end

Achievements.META = {
  { id = "visitor", name = "VISITOR", desc = "Play any machine.",
    test = function() return Save.data.totals.plays >= 1 end },
  { id = "apprentice", name = "APPRENTICE", desc = "Finish five tutorials.",
    test = function() return countMachines(function(_, r) return r.tutorialDone end) >= 5 end },
  { id = "journeyman", name = "JOURNEYMAN", desc = "Play all thirteen machines.",
    test = function() return countMachines(function(_, r) return r.plays > 0 end) >= 13 end },
  { id = "brass", name = "BRASS BAND", desc = "Earn a medal on six machines.",
    test = function()
      return countMachines(function(_, r)
        for _, v in pairs(r.medals) do if v > 0 then return true end end
        return false
      end) >= 6
    end },
  { id = "gold", name = "GOLDEN GEAR", desc = "Earn any gold medal.",
    test = function()
      return countMachines(function(_, r)
        for _, v in pairs(r.medals) do if v >= 3 then return true end end
        return false
      end) >= 1
    end },
  { id = "hoard", name = "HOARDER", desc = "Earn 100 gears in total.",
    test = function() return Save.data.gearsEarned >= 100 end },
  { id = "daily3", name = "REGULAR", desc = "Keep a 3-day daily streak.",
    test = function() return Save.data.daily.bestStreak >= 3 end },
  { id = "crank100k", name = "ARM OF IRON", desc = "Turn the crank 100,000 degrees.",
    test = function() return Save.data.totals.crankDegrees >= 100000 end },
  { id = "keeper", name = "KEEPER", desc = "Unlock every machine.",
    test = function() return countMachines(function(d) return Machines.isUnlocked(d) end) >= 13 end },
}

function Achievements.checkMeta()
  for _, m in ipairs(Achievements.META) do
    if not Save.data.meta[m.id] and m.test() then
      Save.data.meta[m.id] = true
      Save.addGears(1)
      UI.toast(m.name, "+1 gear  " .. m.desc, "star")
      Audio.sfx.achievement()
      session[#session + 1] = m
      Save.markDirty()
    end
  end
end
