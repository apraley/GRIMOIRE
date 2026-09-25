-- Every machine, difficulty 3, under each challenge modifier and as a daily.
local H = dofile("tools/harness.lua")
H.boot({ wipe = true })
local fails = 0
for _, def in ipairs(Machines.list) do
  for _, mod in ipairs({ "rusty", "fog", "haste" }) do
    local ok, err = pcall(function()
      H.goMachine(def.id, "standard", { difficulty = 3, mods = { [mod] = true }, daily = "20260925", goal = 100 })
      H.fuzz(400, #def.id + #mod)
    end)
    if not ok then fails = fails + 1 print("FAIL " .. def.id .. " " .. mod .. ": " .. tostring(err)) end
  end
  for _, c in ipairs(def.challenges) do
    local ok, err = pcall(function()
      Scene.go(PlayScene, Challenge.challengeParams(def, c), "cut")
      H.frame(0)
      H.fuzz(300, 3)
    end)
    if not ok then fails = fails + 1 print("FAIL " .. def.id .. " challenge " .. c.id .. ": " .. tostring(err)) end
  end
end
print(fails == 0 and "MODS OK" or ("MODS FAILURES " .. fails))
os.exit(fails == 0 and 0 or 1)
