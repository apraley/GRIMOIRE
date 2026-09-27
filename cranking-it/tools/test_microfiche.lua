-- MICROFICHE scripted tests:
--   MOCK_DATA_DIR=/tmp/ci-fiche lua5.4 tools/test_microfiche.lua [seeds]
-- 1. Case solvability: for many seeds and every case kind, a "reader" that
--    only sees the generated page text follows the chain and must reach a
--    unique answer equal to the case's answer (and hit the planted key lines).
-- 2. The tutorial can be completed with crank/button input only.
-- 3. A scripted player wins Standard mode (3 cases) with input only.
-- 4. An idle player runs out of time and scores nothing.
local H = dofile("tools/harness.lua")
H.shotDir = "shots/microfiche"
H.boot({ wipe = true })
H.run(2)

local NSEEDS = tonumber(arg and arg[1] or "200")
local fails = 0
local function check(c, msg) if not c then fails = fails + 1 print("FAIL: " .. msg) end return c end
local abs, floor = math.abs, math.floor

local def = Machines.get("microfiche")
local F = def.class
local R = F.REELS

------------------------------------------------------------------------
-- 1. solvability
------------------------------------------------------------------------
local function newInstance(seed, mode)
  local m = F.new()
  m:_setup({ id = "microfiche", mode = mode or "standard", difficulty = 1, seed = seed })
  m:enter(m.params)
  m:exit()
  return m
end

local SURIDX, SHIPIDX = {}, {}
for i, s in ipairs(F.SURN) do SURIDX[s] = i - 1 end
for i, s in ipairs(F.SHIPS) do SHIPIDX[s] = i - 1 end
local MONIDX = {}
for i, s in ipairs(F.MON) do MONIDX[s] = i end

-- all Gazette issue indices falling in (y, m)
local function issuesIn(y, mo)
  local out = {}
  local first = F.issueAfter(F.dayNum(y, mo, 1) - 1)
  for i = first, first + 6 do
    local iy, im = F.dateOf(2 + 7 * i)
    if iy == y and im == mo then out[#out + 1] = i end
  end
  return out
end

-- find the item titled `title` in a Gazette frame; returns its text lines and key
local function findItem(m, fi, title)
  local t = m:frameText(R.GAZ, fi)
  if t.headline == title then return t.lines, t.hkey end
  for i = 1, #t.lines do
    if t.lines[i] == title then
      local body = {}
      for j = i + 1, math.min(#t.lines, i + 3) do body[#body + 1] = t.lines[j] end
      return body, t.keys[i]
    end
  end
  return nil
end

local function nightOf(lines)
  for _, l in ipairs(lines) do
    local d, mon = l:match("night of %u+ (%d+) (%u+)%.")
    if d then return tonumber(d), MONIDX[mon] end
  end
end

-- the log line for day number dn: returns initial, surname, key
local function readLog(m, dn)
  local y, mo, d = F.dateOf(dn)
  local t = m:frameText(R.LOG, dn // 7)
  local prefix = string.format("%2d ", d)
  local hits = 0
  local init, sur, key, idx
  for i, l in ipairs(t.lines) do
    if l:sub(1, 3) == prefix then
      hits = hits + 1
      init, sur = l:match("^%s*%d+ %u+ (%u)%.(%u+) ")
      key, idx = t.keys[i], i
    end
  end
  return hits == 1 and init or nil, sur, key, t, idx
end

-- parish people: { first, bornStr, occ, key }
local function people(m, sur)
  local t = m:frameText(R.PAR, SURIDX[sur])
  local out = {}
  local i = 1
  while i <= #t.lines do
    local first, born = t.lines[i]:match("^(%u+)  b%.(.+)$")
    if first then
      out[#out + 1] = { first = first, born = born, occ = t.lines[i + 1] or "", key = t.keys[i] }
      i = i + 2
    else
      i = i + 1
    end
  end
  return out, t
end

local function solveLost(m, c, four)
  local name, mo, y
  if four then
    name = c.q:match("^The %a+ (%u+) was lost off Grey Rock%.")
    local t = m:frameText(R.REG, SHIPIDX[name])
    for i, l in ipairs(t.lines) do
      if l == "FATE: lost off Grey Rock," then
        local mm, yy = t.lines[i + 1]:match("^  (%u+) (%d+), all hands%.")
        mo, y = MONIDX[mm], tonumber(yy)
        check(t.keys[i] == 1, "lost4: registry fate is the clip key")
      end
    end
  else
    local mm, yy
    name, mm, yy = c.q:match("^The %a+ (%u+) was lost off Grey Rock in (%u+) (%d+)%.")
    mo, y = MONIDX[mm], tonumber(yy)
  end
  if not (name and mo and y) then return nil, "could not read the question/registry" end
  local found = {}
  for _, fi in ipairs(issuesIn(y, mo)) do
    local body, key = findItem(m, fi, "LOSS OF THE " .. name)
    if body then found[#found + 1] = { body = body, key = key } end
  end
  if #found ~= 1 then return nil, "gazette reports found: " .. #found end
  local d = nightOf(found[1].body)
  check(found[1].key == (four and 2 or 1), "lost: gazette report is the clip key")
  local dn = F.dayNum(y, mo, d)
  local init, sur, key = readLog(m, dn)
  if not init then return nil, "log line not unique" end
  check(key == (four and 3 or 2), "lost: log line is the clip key")
  local ppl = people(m, sur)
  local cands = {}
  for _, p in ipairs(ppl) do
    local a, b = p.occ:match("Grey Rock keeper (%d+)%-(%d+)")
    if a and p.first:sub(1, 1) == init then
      local from = tonumber(a)
      local to = floor(from / 100) * 100 + tonumber(b)
      if y >= from and y <= to then cands[#cands + 1] = p.first .. " " .. sur end
    end
  end
  if #cands ~= 1 then return nil, "parish candidates: " .. #cands end
  -- the herring really is there: another person with the same initials
  local same = 0
  for _, p in ipairs(ppl) do if p.first:sub(1, 1) == init then same = same + 1 end end
  check(same >= 2, "lost: parish page has a same-initials herring")
  return cands[1]
end

local function solveGale(m, c)
  local y = tonumber(c.q:match("great gale of (%d+)"))
  local found = {}
  local first = F.issueAfter(F.dayNum(y, 1, 1) - 1)
  for fi = first, first + 53 do
    local iy = F.dateOf(2 + 7 * fi)
    if iy == y then
      local body, key = findItem(m, fi, "THE GREAT GALE")
      if body then found[#found + 1] = { body = body, key = key } end
    end
  end
  if #found ~= 1 then return nil, "gale reports: " .. #found end
  check(found[1].key == 1, "gale: gazette item is the clip key")
  local d, mo = nightOf(found[1].body)
  local dn = F.dayNum(y, mo, d)
  local init, sur, key, t, idx = readLog(m, dn)
  if not init then return nil, "gale log line" end
  check(key == 2, "gale: log line is the clip key")
  check(t.lines[idx + 1] and t.lines[idx + 1]:find("daughter born") ~= nil, "gale: log notes the birth")
  local want = d .. " " .. F.MON[mo] .. " " .. y
  local cands = {}
  for _, p in ipairs(people(m, sur)) do
    if p.born == want and p.occ:find("dau%. of " .. init) then cands[#cands + 1] = p.first .. " " .. sur end
  end
  if #cands ~= 1 then return nil, "gale parish candidates: " .. #cands end
  return cands[1]
end

local function solveWatch(m, c)
  local init, sur = c.q:match("^Capt%. (%u)%.(%u+) went down")
  local ship
  local ships = 0
  for _, p in ipairs(people(m, sur)) do
    local s = p.occ:match("drowned with the (%u+)")
    if s and p.first:sub(1, 1) == init then ship = s ships = ships + 1 check(p.key == 1, "watch: parish line is the clip key") end
  end
  if ships ~= 1 then return nil, "drowned captains: " .. ships end
  local t = m:frameText(R.REG, SHIPIDX[ship])
  local mo, y
  for i, l in ipairs(t.lines) do
    if l == "FATE: lost off Grey Rock," then
      local mm, yy = t.lines[i + 1]:match("^  (%u+) (%d+), all hands%.")
      mo, y = MONIDX[mm], tonumber(yy)
      check(t.keys[i] == 2, "watch: registry is the clip key")
    end
  end
  check(t.lines[3] == "master " .. init .. "." .. sur, "watch: registry names the master")
  if not mo then return nil, "watch: registry fate" end
  local found = {}
  for _, fi in ipairs(issuesIn(y, mo)) do
    local body, key = findItem(m, fi, "LOSS OF THE " .. ship)
    if body then found[#found + 1] = { body = body, key = key } end
  end
  if #found ~= 1 then return nil, "watch gazette reports: " .. #found end
  check(found[1].key == 3, "watch: gazette is the clip key")
  local d = nightOf(found[1].body)
  local ki, ks = readLog(m, F.dayNum(y, mo, d))
  if not ki then return nil, "watch log" end
  return ki .. "." .. ks
end

local function solveTutor(m, c)
  local name = c.q:match("^The (%u+) was lost in MAR 1884")
  local found = {}
  for _, fi in ipairs(issuesIn(1884, 3)) do
    local body = findItem(m, fi, "LOSS OF THE " .. name)
    if body then found[#found + 1] = body end
  end
  if #found ~= 1 then return nil, "tutor reports " .. #found end
  local d = nightOf(found[1])
  local ki, ks = readLog(m, F.dayNum(1884, 3, d))
  return ki and (ki .. "." .. ks)
end

local SOLVERS = {
  lost3 = function(m, c) return solveLost(m, c, false) end,
  lost4 = function(m, c) return solveLost(m, c, true) end,
  gale = solveGale, watch = solveWatch, tutor = solveTutor,
}

local solvedCount, total = 0, 0
local t0 = os.clock()
for seed = 1, NSEEDS do
  local m = newInstance(seed * 7919 + 13)
  for _, kind in ipairs({ "lost3", "lost4", "gale", "watch", "tutor" }) do
    local lvl = (seed % 4)
    local c = m:makeCase(kind, seed * 31 + #kind, lvl)
    m.case = c
    m:flushSlots()
    total = total + 1
    local ans, why = SOLVERS[kind](m, c)
    local ok = ans ~= nil and ans == c.options[c.answer]
    -- options: 4 distinct, the answer among them
    local distinct = true
    for i = 1, #c.options do for j = i + 1, #c.options do if c.options[i] == c.options[j] then distinct = false end end end
    ok = ok and #c.options == 4 and distinct
    if ok then solvedCount = solvedCount + 1
    else check(false, string.format("seed %d %s: %s (got %s, want %s, %d options)", seed, kind, tostring(why), tostring(ans), tostring(c.options[c.answer]), #c.options)) end
    -- every case needs 2 (tutorial) or 3-4 records
    check(c.records == (kind == "tutor" and 2 or ((kind == "lost4" or kind == "watch") and 4 or 3)), "record count for " .. kind)
  end
end
print(string.format("solvability: %d/%d cases deduced uniquely from page text (%.1fs)", solvedCount, total, os.clock() - t0))

-- determinism: the same seed/reel/frame always renders the same page
do
  local a = newInstance(4242)
  local b = newInstance(4242)
  local same = true
  for _, fi in ipairs({ 0, 5, 300, 1042 }) do
    for reel = 1, 4 do
      local f = math.min(fi, F.N_FRAMES[reel] - 1)
      local ta, tb = a:frameText(reel, f), b:frameText(reel, f)
      if ta.headline ~= tb.headline or #ta.lines ~= #tb.lines then same = false end
      for i = 1, #ta.lines do if ta.lines[i] ~= tb.lines[i] then same = false end end
    end
  end
  check(same, "archive frames are deterministic from the seed")
  -- alphabetical reels are really alphabetical
  local sorted = true
  for i = 2, #F.SHIPS do if F.SHIPS[i - 1] >= F.SHIPS[i] then sorted = false end end
  for i = 2, #F.SURN do if F.SURN[i - 1] >= F.SURN[i] then sorted = false end end
  check(sorted, "registry and parish reels are in alphabetical order")
end

------------------------------------------------------------------------
-- driving helpers: a physical controller over the inertial spool
------------------------------------------------------------------------
local function sign(v) return v > 0 and 1 or (v < 0 and -1 or 0) end
local function M() return PlayScene.machine end

local function setGear(g)
  local m = M()
  for _ = 1, 3 do
    if m.gear == g then return end
    H.press("a")
  end
end

-- drive the spool to frame `target` using only crank degrees
local function goTo(target)
  local m = M()
  for _ = 1, 4000 do
    local p, v = m.pos[m.reel], m.vel
    local e = target - p
    if abs(e) < 0.02 and abs(v) < 0.05 then H.run(4) return true end
    local wantHigh = abs(e) > 14
    if ((m.gear == 2) ~= wantHigh) and abs(v) < 1.5 and not m.mag and not m.stuckHigh then
      setGear(wantHigh and 2 or 1)
    else
      local hi = m.gear == 2
      local ratio = F.RATIOS[m.gear]
      local vmax = hi and 110 or 4.5
      local vd = U.clamp(e * (hi and 1.6 or 2.5), -vmax, vmax)
      local crank = 0
      if abs(e) < 0.45 and abs(v) < 2.5 then
        crank = 0 -- let the detent seat the frame
      elseif (abs(v) < 0.05 or sign(vd) == sign(v)) and abs(vd) > abs(v) then
        crank = vd / ratio / 30
      elseif sign(vd) ~= sign(v) or abs(v) > abs(vd) + 0.5 then
        local need = abs(v) - (sign(vd) == sign(v) and abs(vd) or 0)
        crank = -sign(v) * math.min(70, need / F.BRAKE + 1)
      end
      H.frame(crank)
    end
  end
  return false
end

local function toReel(r)
  local m = M()
  if m.mag then H.press("b") end
  for _ = 1, 6 do
    if m.reel == r then break end
    local d = ((r - m.reel) % 4 <= 2) and "right" or "left"
    H.press(d)
    H.run(30)
  end
  return m.reel == r
end

-- magnify, move the cursor to the line carrying `key`, clip it, step back
local function clipKey(key)
  local m = M()
  if not m.mag then H.press("b") end
  H.run(4)
  local s = m:getFrame(m.reel, m:curFrame())
  local row
  if s.hkey == key then row = 0 end
  for i = 1, s.n do if not row and s.keys[i] == key then row = i end end
  if not row then return false end
  for _ = 1, 20 do
    if m.cursor == row then break end
    H.press(m.cursor < row and "down" or "up")
  end
  H.run(6)
  H.press("a")
  H.run(4)
  return m.case.steps[key].done
end

local function frameFor(c, reel)
  if reel == R.GAZ then return c.issue
  elseif reel == R.LOG then return c.logFrame
  elseif reel == R.REG then return c.ship
  else return c.parishFrame end
end

local function accuse(idx)
  local m = M()
  if m.mag then H.press("b") end
  H.press("up")
  check(m.view == "file", "case file opens")
  H.press("a")
  check(m.view == "accuse", "accusation opens once the chain is complete")
  for _ = 1, 6 do
    if m.accSel == idx then break end
    H.press("down")
  end
  H.press("a")
end

------------------------------------------------------------------------
-- 2. tutorial
------------------------------------------------------------------------
do
  local m = H.goMachine("microfiche", "tutorial")
  H.run(10)
  H.crank(6, 90)                       -- 1: slow cranking, page by page
  H.run(20)
  H.press("a")                         -- 2: high gear
  H.crank(40, 25)
  H.shot("tut-highgear")
  H.run(10)                            -- 3: coast, then brake
  for _ = 1, 60 do if abs(m.vel) < 0.2 then break end H.frame(-40) end
  H.run(20)
  local c = m.case
  check(goTo(c.issue), "tutorial: reached the issue")   -- 4
  H.run(20)
  H.shot("tut-issue")
  check(clipKey(1), "tutorial: clipped the report")     -- 5
  H.shot("tut-clipped")
  H.press("b") H.run(10)
  H.press("right") H.run(40)                            -- 6
  check(m.reel == R.LOG, "tutorial: loaded the log reel")
  check(goTo(c.logFrame), "tutorial: reached the log week")
  H.press("b") H.run(40)                                -- 7 (read it)
  H.shot("tut-log")
  H.run(20)
  accuse(c.answer)                                      -- 8
  H.run(10)
  check(m.solved == 1, "tutorial: case solved")
  H.run(80)
  check(Scene.current == ResultsScene, "tutorial: finished with LESSON LEARNED (coach step " .. tostring(m.coach and m.coach.i) .. ")")
  check(Save.machine("microfiche").tutorialDone, "tutorial recorded as done")
  H.run(60)
end

------------------------------------------------------------------------
-- 3. scripted player wins standard
------------------------------------------------------------------------
do
  local m = H.goMachine("microfiche", "standard")
  H.run(10)
  local shots = 0
  for ci = 1, 3 do
    m = M()
    local c = m.case
    if m.view == "file" then
      if ci == 1 then H.shot("std-file") end
      H.press("b")
    end
    for k, st in ipairs(c.steps) do
      if not st.read then
        check(toReel(st.reel), "reel " .. st.reel)
        check(goTo(frameFor(c, st.reel)), "case " .. ci .. " step " .. k .. " reached frame")
        if shots < 2 then H.press("b") H.run(12) H.shot("std-mag-" .. ci .. "-" .. k) shots = shots + 1 end
        check(clipKey(k), "case " .. ci .. " step " .. k .. " clipped")
        H.press("b")
      end
    end
    -- the reading step (look at it, as a player would)
    local last = c.steps[#c.steps]
    toReel(last.reel)
    goTo(frameFor(c, last.reel))
    H.press("b") H.run(15)
    if ci == 1 then H.shot("std-read") end
    H.press("b")
    if ci == 1 then H.press("up") H.shot("std-file-ready") H.press("b") end
    if ci == 2 then H.press("up") H.press("a") H.shot("std-accuse") H.press("b") H.press("b") end
    accuse(c.answer)
    H.run(10)
    if ci == 1 then H.shot("std-solved") end
    check(m.caseState == "solved", "standard case " .. ci .. " solved (" .. c.kind .. ")")
    H.run(30)
    H.press("a")
    H.run(10)
  end
  H.run(90)
  check(Scene.current == ResultsScene, "standard reached results")
  local best = Save.machine("microfiche").best.standard or 0
  print("standard score:", best, "medal", Save.machine("microfiche").medals.standard)
  check(best >= def.medals.standard[2], "a skilled scripted player earns at least silver (" .. best .. ")")
  H.shot("std-results")
  H.run(60)
end

------------------------------------------------------------------------
-- allocation at speed (blur) and at rest on a cached, magnified page
------------------------------------------------------------------------
do
  local m = H.goMachine("microfiche", "standard", { seed = 31 })
  H.press("b")
  H.press("a")
  H.crank(40, 40)
  local fast = H.allocProbe(60, 40)
  print(string.format("alloc/frame spinning at %.0f fr/s: %.2f KB", abs(m.vel), fast))
  check(abs(m.vel) > 60, "HIGH gear reaches speed")
  check(fast < 2, "spinning at speed allocates < 2 KB/frame")
  for _ = 1, 200 do if abs(m.vel) < 0.1 then break end H.frame(-30) end
  H.run(40)
  H.press("b")
  H.run(20)
  local rest = H.allocProbe(60, 0)
  print(string.format("alloc/frame at rest, magnified: %.2f KB", rest))
  check(rest < 0.6, "a cached page at rest allocates (almost) nothing")
  H.run(10)
end

------------------------------------------------------------------------
-- 4. idle player
------------------------------------------------------------------------
do
  local m = H.goMachine("microfiche", "standard", { seed = 99 })
  H.press("b")
  H.run(30 * 60 * 9)
  check(m.finished and m.finished.score == 0 and not m.finished.success, "idle player: time runs out with nothing solved")
  H.run(90)
end

print(fails == 0 and "OK microfiche scripted" or ("FAILURES: " .. fails))
os.exit(fails == 0 and 0 or 1)
