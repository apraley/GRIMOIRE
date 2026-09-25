-- CRANKING IT :: core/themes
-- Visual themes for the museum, bought from the Curator with gears.

Themes = {}

Themes.LIST = {
  { id = "woodcut", name = "WOODCUT", cost = 0, desc = "Oak panels and lamp oil. The museum as it was built." },
  { id = "ledger", name = "LEDGER", cost = 4, desc = "Walls papered with the Keeper's graph-ruled accounts." },
  { id = "night", name = "NIGHT SHIFT", cost = 6, desc = "The lamps invert. Everything glows like a negative." },
  { id = "tide", name = "HIGH TIDE", cost = 8, desc = "The sea has come in. The floor is under a hand of water." },
}

function Themes.get(id)
  for _, t in ipairs(Themes.LIST) do if t.id == id then return t end end
  return Themes.LIST[1]
end

function Themes.current() return Save.data.themes.current end

function Themes.owned(id) return Save.data.themes.owned[id] == true end

function Themes.apply()
  playdate.display.setInverted(Themes.current() == "night")
end

function Themes.select(id)
  Save.data.themes.current = id
  Save.markDirty()
  Themes.apply()
end

function Themes.buy(id)
  local t = Themes.get(id)
  if Themes.owned(id) then return true end
  if not Save.spendGears(t.cost) then return false end
  Save.data.themes.owned[id] = true
  Save.markDirty()
  return true
end

-- wall pattern for the hub
function Themes.wallPattern()
  local c = Themes.current()
  if c == "ledger" then return "grid" end
  return "wood"
end
