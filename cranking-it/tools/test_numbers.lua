-- NUMBERS STATION scripted tests:
--   MOCK_DATA_DIR=/tmp/ci-numbers lua5.4 tools/test_numbers.lua [seeds]
-- 1. Cipher solvability: for many seeds and every level, decode each
--    transmission using only what an operator can know (the indicator
--    group, tonight's date, the pad station found at the announced
--    frequency, the codebook) and check it equals the plaintext; each relay
--    must name the next station's frequency; the last names a listed place.
-- 2. The tutorial can be completed with crank/button input only.
-- 3. A scripted operator (a steady hand on the dial) wins Standard.
-- 4. An idle player is caught by the dawn.
local H = dofile("tools/harness.lua")
H.shotDir = "shots/numbers"
H.boot({ wipe = true })
H.run(2)

local NSEEDS = tonumber(arg and arg[1] or "200")
local fails = 0
local function check(c, msg) if not c then fails = fails + 1 print("FAIL: " .. msg) end return c end
local abs, floor = math.abs, math.floor

local def = Machines.get("numbers")
local N = def.class

------------------------------------------------------------------------
-- 1. ciphers
------------------------------------------------------------------------
local function newInstance(seed, mode, diff)
  local m = N.new()
  m:_setup({ id = "numbers", mode = mode or "standard", difficulty = diff or 1, seed = seed })
  m:enter(m.params)
  m:exit()
  return m
end

local total, good = 0, 0
local keysSeen = { 0, 0, 0, 0 }
for seed = 1, NSEEDS do
  local m = newInstance(seed * 104729 + 7)
  for level = 0, 4 do
    local night = m:makeNight(seed * 17 + level, level, false)
    local S = night.stations
    for i, idx in ipairs(night.msgs) do
      total = total + 1
      local st = S[idx]
      local d = st.digits
      local key = d[1]
      keysSeen[key] = keysSeen[key] + 1
      local pad, dateKey
      local ok = true
      if key == 2 then
        -- the operator knows tonight's date; the indicator repeats it
        dateKey = { night.day // 10, night.day % 10, night.month // 10, night.month % 10 }
        for k = 1, 4 do if d[1 + k] ~= dateKey[k] then ok = false end end
      elseif key == 3 then
        local f = d[2] * 1000 + d[3] * 100 + d[4] * 10 + d[5]
        local found = 0
        for _, ps in ipairs(S) do
          if ps.kind == "pad" and ps.nominal == f then found = found + 1 pad = ps.digits end
        end
        ok = ok and found == 1 and f >= 3000 and f <= 9000
      end
      local text = N.decode(d, key, dateKey, pad, night.book)
      local want = st.msg.text
      if key == 4 then
        -- codebook words: digits of the frequency are separate code words
        local w = {}
        for word in want:gmatch("%S+") do
          if word:match("^%d+$") then for k = 1, #word do w[#w + 1] = word:sub(k, k) end else w[#w + 1] = word end
        end
        want = st.msg.final and night.place or table.concat(w, " ")
      end
      ok = ok and text == want
      -- every other key must NOT produce the plaintext (the key matters)
      for other = 1, 4 do
        if other ~= key then
          local t2 = N.decode(d, other, { night.day // 10, night.day % 10, night.month // 10, night.month % 10 }, pad, night.book)
          if t2 == want and want ~= "" then ok = false end
        end
      end
      -- relay: names the next station's frequency; final: a place among the options
      if not st.msg.final then
        local qsy = text and text:gsub(" ", ""):match("QSY(%d%d%d%d)")
        ok = ok and qsy ~= nil and tonumber(qsy) == S[night.msgs[i + 1]].nominal
      else
        local count = 0
        for _, o in ipairs(night.options) do if o == text then count = count + 1 end end
        ok = ok and count == 1 and night.options[night.answer] == text
      end
      -- a clear channel: no other station within 3 sigma of this one's dial spot
      for j, other in ipairs(S) do
        if j ~= idx then
          local sep = abs((other.nominal + other.calib) - (st.nominal + st.calib))
          if sep < 3.2 * math.max(st.sigma, other.sigma) then ok = false end
        end
      end
      if ok then good = good + 1
      else check(false, string.format("seed %d level %d msg %d key %d: got %s want %s", seed, level, i, key, tostring(text), want)) end
    end
  end
end
print(string.format("ciphers: %d/%d transmissions decode to their plaintext (keys plain/date/pad/book: %d/%d/%d/%d)",
  good, total, keysSeen[1], keysSeen[2], keysSeen[3], keysSeen[4]))
check(keysSeen[1] > 0 and keysSeen[2] > 0 and keysSeen[3] > 0 and keysSeen[4] > 0, "all four cipher kinds occur")

------------------------------------------------------------------------
-- operator: a closed loop on the dial, through the real crank/backlash
------------------------------------------------------------------------
local function M() return PlayScene.machine end
local KPD = 600 / 360

local function crankToward(st)
  local m = M()
  local want = m:stationFreq(st)
  local err = want - m.freq
  if abs(err) > 12 and m.fine then H.press("a") return end
  if abs(err) <= 12 and not m.fine then H.press("a") return end
  local deg
  if m.fine then
    deg = U.clamp(err / (KPD / 10), -25, 25)
    if abs(err) < 0.15 then deg = 0 end
  else
    deg = U.clamp(err / KPD, -45, 45)
  end
  H.frame(deg)
end

-- hold the station until `cond` is true (or timeout seconds)
local function holdStation(stIdx, cond, timeout)
  local m = M()
  local st = m.night.stations[stIdx]
  for _ = 1, floor(timeout * 30) do
    if cond() then return true end
    if m.finished or m.state ~= "night" then return cond() end
    crankToward(st)
  end
  return cond()
end

local function decodeCurrent()
  local m = M()
  local msg = m:currentMsg()
  if not m.pad then H.press("b") end
  for _ = 1, 4 do
    if m.keySel == msg.key then break end
    H.press("right")
  end
  H.press("a")
  local i = m.msgIdx
  for _ = 1, 300 do
    if m.decoded[i] then break end
    H.frame(0)
  end
  return m.decoded[i]
end

------------------------------------------------------------------------
-- 2. tutorial
------------------------------------------------------------------------
do
  local m = H.goMachine("numbers", "tutorial")
  H.run(10)
  local st1 = m.night.msgs[1]
  -- 1: sweep to the pencil mark (coarse)
  for _ = 1, 200 do
    if abs(m.freq - m.night.stations[st1].nominal) < 10 then break end
    H.frame(U.clamp((m.night.stations[st1].nominal - m.freq) / KPD, -40, 40))
  end
  H.run(40)
  H.press("a")                                  -- 2: FINE
  H.run(20)
  holdStation(st1, function() return m.coach.i >= 4 end, 20)   -- 3: peak and hold
  H.shot("tut-peak")
  -- 4: feel the play: small reversals
  for _ = 1, 4 do H.crank(-4, 12) H.crank(4, 12) end
  H.shot("tut-backlash")
  holdStation(st1, function() return m:recComplete(st1) end, 90) -- 5: copy
  H.shot("tut-copied")
  H.run(30)
  H.press("b")                                  -- 6: notepad, PLAIN, apply
  H.press("a")
  for _ = 1, 200 do if m.decoded[1] then break end H.frame(0) end
  H.run(10)
  H.shot("tut-decoded")
  H.press("b")
  holdStation(m.night.msgs[2], function() return m.coach.done end, 60)  -- 7: QSY
  H.run(60)
  check(Scene.current == ResultsScene, "tutorial finished (coach step " .. tostring(m.coach.i) .. ")")
  check(Save.machine("numbers").tutorialDone, "tutorial recorded as done")
  H.run(60)
end

------------------------------------------------------------------------
-- 3. scripted operator wins standard (difficulty 2: plain, date, pad)
------------------------------------------------------------------------
local function playNight(tag)
  local m = M()
  local night = m.night
  for i = 1, #night.msgs do
    local idx = night.msgs[i]
    local msg = night.stations[idx].msg
    check(holdStation(idx, function() return m:recComplete(idx) end, 120), tag .. " copied message " .. i)
    if i == 1 then H.shot(tag .. "-copy") end
    if msg.key == 3 then
      check(holdStation(msg.padStation, function() return m:recComplete(msg.padStation) end, 120), tag .. " copied the pad")
      H.shot(tag .. "-pad")
    end
    check(decodeCurrent(), tag .. " decoded message " .. i)
    if i == #night.msgs or i == 2 then H.shot(tag .. "-notepad-" .. i) end
    if not msg.final then H.press("b") end
  end
  check(m.state == "pick", tag .. " reached the final choice")
  for _ = 1, 4 do
    if m.pickSel == night.answer then break end
    H.press("down")
  end
  H.shot(tag .. "-pick")
  H.press("a")
  H.run(10)
  H.shot(tag .. "-done")
  return m.nightWon
end

do
  H.goMachine("numbers", "standard", { difficulty = 2, seed = 4711 })
  H.run(10)
  check(playNight("std"), "standard night won")
  H.run(30) H.press("a") H.run(90)
  check(Scene.current == ResultsScene, "standard reached results")
  local best = Save.machine("numbers").best.standard or 0
  print("standard score:", best, "medal", Save.machine("numbers").medals.standard)
  check(best >= def.medals.standard[2], "scripted operator earns at least silver (" .. best .. ")")
  H.shot("std-results")
  H.run(60)
end

-- difficulty 3 uses date, pad and codebook
do
  H.goMachine("numbers", "standard", { difficulty = 3, seed = 777 })
  H.run(10)
  check(playNight("hard"), "difficulty 3 night won")
  H.run(30) H.press("a") H.run(90)
end

------------------------------------------------------------------------
-- 4. idle player
------------------------------------------------------------------------
do
  local m = H.goMachine("numbers", "standard", { seed = 5 })
  H.run(30 * 400)
  check(m.finished and not m.finished.success and m.finished.score == 0, "idle player: dawn, nothing decoded")
  H.run(90)
end

print(fails == 0 and "OK numbers scripted" or ("FAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)
