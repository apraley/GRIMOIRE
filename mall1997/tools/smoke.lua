-- Full-game headless smoke test: boots main.lua through the strict Playdate
-- mock, starts a new game and plays it with a random-but-purposeful input
-- bot for a number of frames, exercising scenes, menus, dialogs, shops,
-- minigames and day transitions. Any Lua error or undocumented API call
-- fails the run.
-- usage: lua5.4 tools/smoke.lua [frames] [seed]

PD_TOOLS_DIR = (arg[0]:match("(.*/)") or "./")
PD_SOURCE_DIR = PD_TOOLS_DIR .. "../source/"
PD_DATA_DIR = "/tmp/pdmock_smoke/"
os.execute("rm -rf " .. PD_DATA_DIR)
dofile(PD_TOOLS_DIR .. "pdmock.lua")

local frames = tonumber(arg[1]) or 20000
local bseed = tonumber(arg[2]) or 7
import "main"

local B = { left = 1, right = 2, up = 4, down = 8, b = 16, a = 32 }
local r = RNG.new(bseed)
local function frame(btn, crank)
  local ok, err = xpcall(function() PDMOCK_FRAME(btn or 0, crank or 0) end, debug.traceback)
  if not ok then
    print("ERROR at frame " .. PD_FRAME .. ":\n" .. err)
    local names = {}
    for i, s in ipairs(Scene.stack) do names[#names + 1] = tostring(s.label or s.title or i) end
    print("scene depth " .. #Scene.stack)
    os.exit(1)
  end
end
PD_FRAME = 0
local held, holdN = 0, 0
local counts = {}
for i = 1, frames do
  PD_FRAME = i
  if holdN <= 0 then
    local roll = r:f()
    if roll < 0.45 then held = ({ B.left, B.right, B.up, B.down })[r:i(1, 4)]; holdN = r:i(5, 40)
    elseif roll < 0.8 then held = B.a; holdN = 1
    elseif roll < 0.9 then held = B.b; holdN = 1
    else held = 0; holdN = r:i(1, 10) end
  end
  holdN = holdN - 1
  -- press/release pattern so "just pressed" fires
  local btn = held
  if (held == B.a or held == B.b) and i % 2 == 0 then btn = 0 end
  local crank = r:chance(0.05) and r:range(-40, 40) or 0
  -- director: every so often teleport next to something interesting
  if i % 150 == 0 and Scene.top() == Explore.scene and W then
    local p = W.p
    local areas = { "c1", "c2", "fc", "v1", "maint", "roof", "tun", "shel", "off", "sec", "mgmt", "dock", "lot", "ab", "lock" }
    local a
    if r:chance(0.5) then
      local s = W.stores[r:i(1, #W.stores)]
      if s.open then a = Areas.storeArea(s) end
    end
    a = a or areas[r:i(1, #areas)]
    local ar = Areas.build(a)
    local targets = {}
    for _, o in ipairs(ar.objs) do if o.kind ~= "sign" then targets[#targets + 1] = { x = o.x, y = o.y + o.h } end end
    for _, n in ipairs(NPCAI.inArea(a)) do targets[#targets + 1] = { x = (n.x or 0) // 16, y = (n.y or 0) // 16 + 1 } end
    local t = targets[r:i(1, math.max(1, #targets))]
    if t then
      p.keys.roof = true; p.keys.tunnel = true; p.keys.pry = true
      p.area = a; p.x = t.x * 16 + 8; p.y = t.y * 16 + 14; p.dir = "up"
      Explore.arrive(a, true)
      counts["teleport:" .. (a:match("^s%d") and "store" or a)] = (counts["teleport:" .. (a:match("^s%d") and "store" or a)] or 0) + 1
    end
  end
  frame(btn, crank)
  local top = Scene.top()
  local key = top and (top.label or (top.def and top.def.key) or (top == Explore.scene and "explore") or (top.items and "choose") or (top.pages and "say") or "other") or "none"
  counts[key] = (counts[key] or 0) + 1
end
print(("ran %d frames. world time %s, player area %s, money %s"):format(frames, W and Clock.stamp(W.t) or "-", W and W.p.area or "-", W and U.money(W.p.money) or "-"))
local cl = {}
for k, v in pairs(counts) do cl[#cl + 1] = k .. "=" .. v end
table.sort(cl)
print("frames by scene: " .. table.concat(cl, " "))
local api = {}
for k, v in pairs(PDMOCK_CALLS) do api[#api + 1] = k end
table.sort(api)
print("distinct playdate APIs exercised: " .. #api)
print("SMOKE OK")
