-- THE MALL, 1997
-- A persistent mall life simulation for Playdate.
--
-- Architecture (each layer only depends on the ones above it):
--   core/      util (RNG, helpers), clock (calendar), save (datastore)
--   gen/       content generation: names, music/movies/arcade, mall, NPCs
--   world/     world state container, timeline, rumors, pager; area geometry
--   sim/       simulation systems: npcai, stores, economy, social, security,
--              jobs, cinema, arcade, music, trends, events, lore, player,
--              worldsim (tick orchestration)
--   minigames/ job minigames      arcade/  arcade cabinet games
--   ui/        gfx helpers, input, sprites/portraits, map renderer
--   scenes/    title, morning, explore, dialog, shop, menu, etc.

import "CoreLibs/graphics"

import "core/util"
import "core/clock"
import "gen/names"
import "gen/content"
import "gen/mallgen"
import "gen/npcgen"
import "world/world"
import "world/areas"
import "sim/npcai"
import "sim/stores"
import "sim/economy"
import "sim/cinema"
import "sim/arcade"
import "sim/music"
import "sim/trends"
import "sim/social"
import "sim/security"
import "sim/jobs"
import "sim/player"
import "sim/events"
import "sim/management"
import "sim/romance"
import "sim/lore"
import "sim/talk"
import "sim/worldsim"
import "core/save"

import "ui/gfx"
import "ui/input"
import "minigames/framework"
import "minigames/record"
import "minigames/video"
import "minigames/food"
import "minigames/arcade"
import "minigames/cinema"
import "minigames/photo"
import "minigames/books"
import "minigames/department"
import "minigames/security"
import "arcade/serpent"
import "arcade/orbital"
import "arcade/tower"
import "arcade/racer"

import "ui/sprites"
import "ui/mapview"
import "ui/crowd"
import "scenes/scene"
import "scenes/title"
import "scenes/explore"
import "scenes/dialog"
import "scenes/shop"
import "scenes/interact"
import "scenes/menu"
import "scenes/play"
import "scenes/day"
import "scenes/secret"
import "game"
