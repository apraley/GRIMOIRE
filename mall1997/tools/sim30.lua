-- Headless world inspection: generate a mall, simulate N days (default 30)
-- with no player present, and print a report on every system.
-- usage: lua5.4 tools/sim30.lua [seed] [days]

PD_TOOLS_DIR = (arg[0]:match("(.*/)") or "./")
PD_SOURCE_DIR = PD_TOOLS_DIR .. "../source/"
HEADLESS = true
dofile(PD_TOOLS_DIR .. "pdmock.lua")
import "main"

local seed = tonumber(arg[1]) or 1997
local days = tonumber(arg[2]) or 30
local t0 = os.clock()
World.new(seed, "Alex")
local genT = os.clock() - t0
print(("== %s  seed %d  (generated in %.2fs)"):format(W.mall.name, seed, genT))
local nStores, nOpen = 0, 0
local types = {}
for _, s in ipairs(W.stores) do nStores = nStores + 1; types[s.type] = (types[s.type] or 0) + 1 end
local vac = 0
for _, sl in ipairs(W.slots) do if sl.kind == "store" and not sl.store then vac = vac + 1 end end
print(("stores %d (vacant slots %d), npcs %d, width %d tiles"):format(nStores, vac, #W.npcs, W.mall.w))
local tl = {}
for _, k in ipairs(U.keys(types)) do tl[#tl + 1] = k .. "=" .. types[k] end
print("types: " .. table.concat(tl, " "))
local roles = {}
for _, n in ipairs(W.npcs) do roles[n.role] = (roles[n.role] or 0) + 1 end
local rl = {}
for _, k in ipairs(U.keys(roles)) do rl[#rl + 1] = k .. "=" .. roles[k] end
print("roles: " .. table.concat(rl, " "))

SIM_HOOK = SIM_HOOK or function() end
local t1 = os.clock()
local target = W.t + days * 1440
local samples = {}
while W.t < target do
  WorldSim.tick(5)
  local m = Clock.minute(W.t)
  if m == 12 * 60 + 5 or m == 19 * 60 + 5 then
    local inMall = 0
    for a, list in pairs(NPCAI.byArea) do inMall = inMall + #list end
    samples[#samples + 1] = { day = Clock.day(W.t), m = m, n = inMall }
  end
  SIM_HOOK()
end
print(("simulated %d days in %.2fs"):format(days, os.clock() - t1))
REPORT = { samples = samples }

-- ------------------------------------------------------------------ report
local function hdr(s) print(""); print("### " .. s) end

hdr("FOOTFALL (NPCs physically in the mall at noon / 7pm)")
local line = {}
for i, s in ipairs(samples) do
  if i <= 60 then line[#line + 1] = s.n end
end
print(table.concat(line, " "))

hdr("NPC SCHEDULES (sample)")
local shown = 0
for _, n in ipairs(W.npcs) do
  if n.id % 47 == 3 and shown < 8 then
    shown = shown + 1
    local b = {}
    for _, bl in ipairs(n.plan or {}) do b[#b + 1] = Clock.hhmm(bl.s) .. "-" .. Clock.hhmm(bl.e) .. " " .. bl.act .. "@" .. bl.a end
    print(("#%d %s (%d, %s%s): %s"):format(n.id, NPCGen.name(n), n.age, n.role, n.job and (" @" .. tostring(n.job)) or "",
      #b > 0 and table.concat(b, "; ") or "(stays home)"))
  end
end

hdr("STORE ECONOMICS")
local cashes, open, troubled, sale = {}, 0, 0, 0
for _, s in ipairs(W.stores) do
  if s.open then
    open = open + 1
    cashes[#cashes + 1] = s.cash / 100
    if (s.trouble or 0) > 0 then troubled = troubled + 1 end
    if s.sale > 0 then sale = sale + 1 end
  end
end
table.sort(cashes)
local function pct(t, p) return t[math.max(1, math.floor(#t * p))] end
print(("open %d, troubled %d, on sale %d, cash p10 $%d p50 $%d p90 $%d"):format(open, troubled, sale,
  math.floor(pct(cashes, 0.1)), math.floor(pct(cashes, 0.5)), math.floor(pct(cashes, 0.9))))
local sample = {}
for _, s in ipairs(W.stores) do
  if s.id % 11 == 1 then
    print(("  %-26s %-11s pop %3d cash $%8d wk %s  staff %d%s"):format(s.name, s.type, math.floor(s.pop), math.floor(s.cash / 100),
      table.concat(U.map(s.hist, function(v) return tostring(math.floor(v / 100)) end), ","), #s.emp + (s.mgr and 1 or 0),
      s.open and "" or " CLOSED"))
  end
end

hdr("RELATIONSHIPS")
local couples, crushes, friends, enemies = 0, 0, 0, 0
for _, n in ipairs(W.npcs) do
  if n.partner and n.partner > n.id then couples = couples + 1 end
  if n.crush then crushes = crushes + 1 end
  for _, r in pairs(n.rel) do
    if r.f >= 40 then friends = friends + 1 elseif r.f <= -30 then enemies = enemies + 1 end
  end
end
print(("couples %d, crushes %d, friend-edges %d, enemy-edges %d"):format(couples, crushes, friends, enemies))

hdr("RUMORS")
table.sort(W.rumors, function(a, b) return a.n > b.n end)
print(("active rumors: %d"):format(#W.rumors))
for i = 1, math.min(10, #W.rumors) do
  local r = W.rumors[i]
  print(("  [%s] known by %3d heat %.1f: %s"):format(r.kind, r.n, r.heat, r.txt))
end

hdr("EMPLOYMENT")
local unemployedWant = 0
for _, n in ipairs(W.npcs) do
  if n.status == "active" and not n.job then
    for _, w in ipairs(n.wants) do if w.k == "job" then unemployedWant = unemployedWant + 1 break end end
  end
end
local hiring = 0
for _, s in ipairs(W.stores) do if s.open and s.hiring then hiring = hiring + 1 end end
print(("hires %d quits %d fires %d manager changes %d; job-seekers %d; stores hiring %d"):format(
  W.stats.hires, W.stats.quits, W.stats.fires, W.stats.mgrChanges, unemployedWant, hiring))

hdr("SECURITY")
print(("thefts %d caught %d bans %d cams %d"):format(W.stats.thefts, W.stats.caught, W.stats.bans, #W.cams))

hdr("ARCADE")
for _, g in ipairs(Content.ARCADE_GAMES) do
  local b = W.arcade.scores[g.key]
  print(("  %-16s top: %s %d  (%d entries)"):format(g.name, b[1] and b[1].i or "-", b[1] and b[1].s or 0, #b))
end

hdr("STATS")
local sl = {}
for _, k in ipairs(U.keys(W.stats)) do sl[#sl + 1] = k .. "=" .. W.stats[k] end
print(table.concat(sl, " "))

hdr("TRENDS")
print(table.concat(Trends.describe(), ", "))

hdr("TIMELINE (last 45)")
local tl2 = Timeline.recent(45)
for i = #tl2, 1, -1 do
  local e = tl2[i]
  print(("  %s %-6s %s"):format(Clock.shortDate(Clock.day(e.t)), e.cat, e.txt))
end
local cats = {}
for _, e in ipairs(W.timeline) do cats[e.cat] = (cats[e.cat] or 0) + 1 end
local cl = {}
for _, k in ipairs(U.keys(cats)) do cl[#cl + 1] = k .. "=" .. cats[k] end
print("timeline entries by category: " .. table.concat(cl, " "))

-- save round trip
local t2 = os.clock()
Save.write()
local f = io.open((PD_DATA_DIR or "/tmp/pdmock_data/") .. "mall1997.json")
local size = f:seek("end"); f:close()
local before = W
assert(Save.read(), "save read failed")
print(("save: %d KB, round trip %.2fs, npcs %d rel sample ok=%s"):format(size // 1024, os.clock() - t2, #W.npcs,
  tostring(W.npcs[5].rel ~= nil)))
