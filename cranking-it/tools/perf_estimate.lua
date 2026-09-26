-- Estimates per-frame Lua cost of every machine (logic + draw-call dispatch,
-- rasterization disabled). Device estimate uses a rough 50x desktop factor.
local H = dofile("tools/harness.lua")
H.boot({ wipe = true })
-- skip all rasterization (the device does it in C); measure game Lua only
H.M.perfMode = true
local FACTOR = tonumber(arg[1] or "50")
local rows = {}
local function measure(id, mode, crankFn, frames)
  H.goMachine(id, mode)
  H.run(90, crankFn)
  collectgarbage("collect") -- don't bill this machine for earlier machines' garbage
  local worst, total = 0, 0
  for i = 1, frames do
    local c = crankFn()
    local t0 = os.clock()
    H.frame(c)
    local dt = os.clock() - t0
    total = total + dt
    if dt > worst then worst = dt end
  end
  return total / frames * 1000, worst * 1000
end
print(string.format("%-14s %9s %9s %11s %11s", "machine", "avg ms", "worst ms", "dev avg ms", "dev worst"))
for _, def in ipairs(Machines.list) do
  local phase = 0
  local steady = function() return 12 end
  local fast = function() return 40 end
  local a1, w1 = measure(def.id, "standard", steady, 240)
  local a2, w2 = measure(def.id, "standard", fast, 240)
  local avg, worst = math.max(a1, a2), math.max(w1, w2)
  print(string.format("%-14s %9.3f %9.3f %11.1f %11.1f%s", def.id, avg, worst, avg * FACTOR, worst * FACTOR,
    avg * FACTOR > 25 and "  <-- over budget risk" or ""))
end
