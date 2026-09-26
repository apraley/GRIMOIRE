-- Headless smoke test for job minigames and arcade cabinets.
-- usage: lua5.4 tools/test_games.lua [key]
-- Runs every registered minigame / arcade game with pseudo-random input
-- through the strict Playdate mock and checks they finish and report sanely.

PD_TOOLS_DIR = (arg[0]:match("(.*/)") or "./")
PD_SOURCE_DIR = PD_TOOLS_DIR .. "../source/"
dofile(PD_TOOLS_DIR .. "pdmock.lua")

import "core/util"
import "gen/names"
import "gen/content"
import "ui/gfx"
import "ui/input"
import "minigames/framework"

local function lsLua(dir)
  local p = io.popen('ls "' .. PD_SOURCE_DIR .. dir .. '" 2>/dev/null')
  local t = {}
  for f in p:lines() do if f:match("%.lua$") and f ~= "framework.lua" then t[#t + 1] = f end end
  p:close()
  return t
end
for _, f in ipairs(lsLua("minigames")) do import("minigames/" .. f:gsub("%.lua$", "")) end
for _, f in ipairs(lsLua("arcade")) do import("arcade/" .. f:gsub("%.lua$", "")) end

Gfx.init()
local only = arg[1]
local r = RNG.new(1234)
local music = Content.genMusic(RNG.new(7))
local movies = Content.genMovies(RNG.new(8))
local fails = 0

local BTN = { 1, 2, 4, 8, 16, 32 }
local function run(name, def, isArcade)
  for trial = 1, 3 do
    local rr = RNG.new(100 + trial)
    local ctx
    if isArcade then ctx = { rng = rr, credits = 1 }
    else
      ctx = { rng = rr, store = { id = 1, name = "Test Store", type = "music", pop = 50 }, difficulty = (trial - 1) / 2,
        role = "clerk", music = music, movies = movies, customers = {} }
    end
    local st = def.new(ctx)
    local frames = 0
    local ok, err = pcall(function()
      while frames < 30 * 60 * 6 do
        frames = frames + 1
        -- random buttons, biased to A and directions; crank sweeps
        local b = 0
        if rr:chance(0.3) then b = BTN[rr:i(1, 6)] end
        if rr:chance(0.02) then b = 16 end
        PDMOCK_INPUT.prev = PDMOCK_INPUT.cur
        PDMOCK_INPUT.cur = b
        PDMOCK_INPUT.crankChange = rr:chance(0.5) and rr:range(-20, 30) or 0
        Input.read()
        def.update(st)
        def.draw(st)
        if def.done(st) then break end
      end
    end)
    if not ok then
      print(("FAIL %s trial %d: %s"):format(name, trial, tostring(err))); fails = fails + 1
    elseif not def.done(st) then
      print(("FAIL %s trial %d: not done after %d frames"):format(name, trial, frames)); fails = fails + 1
    else
      if isArcade then
        local sc = def.score(st)
        local npc = def.npcScore(RNG.new(trial), 0.5)
        assert(math.type(sc) == "integer", name .. " score must be integer")
        assert(math.type(npc) == "integer", name .. " npcScore must be integer")
        print(("ok   %-16s trial %d frames %5d score %d npc(0.5) %d"):format(name, trial, frames, sc, npc))
      else
        local res = def.result(st)
        assert(type(res.score) == "number" and res.score >= 0 and res.score <= 100, name .. " bad score")
        assert(type(res.text) == "string", name .. " missing text")
        print(("ok   %-16s trial %d frames %5d score %3d tips %s  %s"):format(name, trial, frames, res.score, tostring(res.tips), res.text))
      end
    end
  end
end

for _, k in ipairs(Minigames.order) do if not only or only == k then run(k, Minigames.list[k], false) end end
local ak = U.keys(ArcadeGames.list)
for _, k in ipairs(ak) do if not only or only == k then run(k, ArcadeGames.list[k], true) end end
print(fails == 0 and "ALL GAMES OK" or (fails .. " FAILURES"))
os.exit(fails == 0 and 0 or 1)
