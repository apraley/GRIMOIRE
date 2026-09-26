-- Job minigame registry. Each job minigame file calls Minigames.register.
--
-- def = {
--   title = "Record Store Shift",
--   help = { "line", ... },            -- shown on the intro card
--   new = function(ctx) return st end, -- ctx fields below
--   update = function(st) end,         -- read global `In` (ui/input.lua)
--   draw = function(st) end,           -- draw the full 400x240 screen
--   done = function(st) return bool end,
--   result = function(st) return { score = 0..100, tips = cents, text = "..." } end,
-- }
--
-- ctx = {
--   rng = RNG,              -- deterministic RNG for this shift
--   store = store table,    -- W.stores[id] (name, type, pop, ...)
--   difficulty = 0..1,      -- rises with promotions / busy days
--   role = "clerk" | "lead" | "assistant" | "manager",
--   music = W.music,        -- { bands = {...}, albums = {...} }
--   movies = W.movies,      -- list of movies { title, genre, rating, mins, quality, year, opens }
--   customers = { npc, ... } -- a few real NPCs who may appear as customers
-- }

Minigames = { list = {}, order = {} }

function Minigames.register(key, def)
  def.key = key
  Minigames.list[key] = def
  Minigames.order[#Minigames.order + 1] = key
end

-- Arcade cabinet registry (fictional games on the arcade floor).
--
-- def = {
--   name = "NEON SERPENT",
--   new = function(ctx) return st end,  -- ctx = { rng = RNG, credits = 1 }
--   update = function(st) end,
--   draw = function(st) end,
--   done = function(st) return bool end,
--   score = function(st) return integer end,
--   npcScore = function(rng, skill) return integer end, -- simulate an NPC's run (skill 0..1)
-- }
ArcadeGames = { list = {} }
function ArcadeGames.register(key, def)
  def.key = key
  ArcadeGames.list[key] = def
end
