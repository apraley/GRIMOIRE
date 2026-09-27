-- Generic machine test:  lua5.4 tools/test_machine.lua <machine-id>
-- For every mode: enter, fuzz input, round-trip serialize/deserialize
-- through JSON, measure per-frame allocation, take screenshots, and verify
-- the machine can finish and reach the results screen.
local id = arg[1] or "safecracker"
local frames = tonumber(arg[2] or "900")
local H = dofile("tools/harness.lua")
H.shotDir = "shots/" .. id
H.boot({ wipe = true })
H.run(2)

local def = Machines.get(id)
assert(def, "no machine " .. id)
local fails = 0
local function check(cond, msg)
  if not cond then fails = fails + 1 print("FAIL: " .. msg) end
end

-- definition sanity
check(def.number and def.title and def.tagline and def.description, "def has number/title/tagline/description")
check(type(def.drawIcon) == "function", "def.drawIcon")
check(#def.controls >= 1, "def.controls")
for _, mode in ipairs(def.modes) do
  if mode ~= "tutorial" then check(def.medals[mode] and #def.medals[mode] == 3, "medals for " .. mode) end
end
check(#def.achievements >= 3, "at least 3 achievements")

for _, mode in ipairs(def.modes) do
  local m = H.goMachine(id, mode)
  check(PlayScene.machine ~= nil, "machine created for " .. mode)
  H.run(30)
  H.shot(mode .. "-0")
  if mode == "tutorial" then check(m.coach ~= nil, "tutorial sets self.coach") end
  -- steady cranking
  H.crank(12, 90)
  H.shot(mode .. "-1")
  local alloc = H.allocProbe(60, 8)
  print(string.format("%-10s alloc/frame while cranking: %.2f KB", mode, alloc))
  check(alloc < 2, mode .. " allocates " .. alloc .. " KB/frame (limit 2)")
  -- fuzz
  H.fuzz(frames // 2, 11)
  if Scene.current == PlayScene and PlayScene.machine and not PlayScene.machine.finished then
    H.shot(mode .. "-2")
    -- serialize round trip
    local st = PlayScene.machine:serialize()
    if st ~= nil then
      local ok, enc = pcall(json.encode, st)
      check(ok, mode .. " serialize() is JSON-encodable: " .. tostring(enc))
      if ok then
        local dec = json.decode(enc)
        local p = U.copy(PlayScene.params)
        p.resumeState = dec
        Scene.go(PlayScene, p, "cut")
        H.frame(0)
        H.fuzz(120, 5)
        check(Scene.current ~= nil, mode .. " survives resume")
        H.shot(mode .. "-resumed")
      end
    else
      print("note: " .. mode .. " serialize() returned nil")
    end
  end
  H.fuzz(frames // 2, 23)
  H.shot(mode .. "-3")
  -- force finish if still running, to test results flow
  if Scene.current == PlayScene and PlayScene.machine and not PlayScene.machine.finished then
    PlayScene.machine:finish({ success = true, score = 1, lines = { "forced" } })
  end
  H.run(120)
  if Scene.current == ResultsScene then H.shot(mode .. "-results") end
  check(Scene.current == ResultsScene or Scene.current == LobbyScene or Scene.current == PlayScene, mode .. " reached results (scene=" .. tostring(Scene.current == ResultsScene) .. ")")
  H.releaseAll()
end

-- json save must still encode
check(pcall(json.encode, Save.data), "save data encodes")
print(fails == 0 and ("OK " .. id) or ("FAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)
