-- Audio audit (the mock is silent, so check sound mechanically):
--  * every machine makes sound while its crank is turned
--  * volumes stay within 0..1 and pitches inside the audible band
--  * no more than 6 sustained "hum" voices at once
--  * every sustained voice is silenced when leaving the machine
local H = dofile("tools/harness.lua")
H.boot({ wipe = true })
H.M.perfMode = true
local M = H.M
local fails = 0
local function check(c, msg) if not c then fails = fails + 1 print("FAIL " .. msg) end end
print(string.format("%-14s %6s %6s %7s %8s %6s", "machine", "notes", "held", "maxVol", "Hz range", "after"))
for _, def in ipairs(Machines.list) do
  local worstHeld, notes = 0, 0
  for _, mode in ipairs(def.modes) do
    H.goMachine(def.id, mode)
    H.run(30)
    M.noteLog = { n = 0, maxVol = 0, minHz = math.huge, maxHz = 0 }
    for i = 1, 240 do
      local c = (i % 60 < 30) and 15 or -10
      if i % 45 == 0 then H.press("a") end
      H.frame(c)
      worstHeld = math.max(worstHeld, M.heldVoices())
    end
    H.fuzz(200, #def.id)
    notes = notes + M.noteLog.n
    local L = M.noteLog
    check(L.maxVol <= 1.0001, def.id .. "/" .. mode .. " volume " .. L.maxVol .. " > 1")
    if L.n > 0 then check(L.minHz >= 20 and L.maxHz <= 16000, string.format("%s/%s pitch out of band %.0f-%.0f Hz", def.id, mode, L.minHz, L.maxHz)) end
    if mode == "standard" then
      check(L.n > 0, def.id .. " makes no sound while cranked")
      print(string.format("%-14s %6d %6d %7.2f %4.0f-%-5.0f", def.id, L.n, worstHeld, L.maxVol, L.minHz == math.huge and 0 or L.minHz, L.maxHz))
    end
    -- leave the machine: every hum must stop
    Scene.go(LobbyScene, { id = def.id }, "cut")
    H.run(5)
    check(M.heldVoices() == 0, def.id .. "/" .. mode .. " leaves " .. M.heldVoices() .. " hums playing after exit")
  end
  check(worstHeld <= 6, def.id .. " holds " .. worstHeld .. " sustained voices at once (limit 6)")
end
print(fails == 0 and "AUDIO OK" or ("AUDIO FAILURES " .. fails))
os.exit(fails == 0 and 0 or 1)
