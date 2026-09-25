-- Arcade simulation: persistent high score boards, NPC play sessions,
-- machine wear/breakdowns, records and rivalries.

ArcadeSim = {}

local function initials(n)
  if n == nil then return W.p.initials or (W.p.name:sub(1, 3):upper()) end
  return (n.first:sub(1, 1) .. n.last:sub(1, 1) .. (n.first:sub(-1))):upper()
end
ArcadeSim.initials = initials

function ArcadeSim.board(game) return W.arcade.scores[game] end

-- insert a score; returns rank (1-based) or nil
function ArcadeSim.submit(game, who, score)
  local b = W.arcade.scores[game]
  local e = { i = who == -1 and initials(nil) or initials(W.npcs[who]), s = score, who = who, d = Clock.day(W.t) }
  local rank
  for i = 1, #b do if score > b[i].s then rank = i break end end
  if not rank then if #b < 10 then rank = #b + 1 else return nil end end
  local prevTop = b[1]
  table.insert(b, rank, e)
  while #b > 10 do table.remove(b) end
  if rank == 1 and prevTop and prevTop.who ~= who then
    local g = ArcadeGames.list[game]
    local gname = g and g.name or game
    W.stats.records = W.stats.records + 1
    if who == -1 then
      Timeline.add("arcade", W.p.name .. " set the " .. gname .. " record: " .. score .. ".", 3)
      Rumors.add("record", -1, W.p.name .. " set a record on " .. gname, 6, ArcadeSim.witnesses())
      W.p.fame = W.p.fame + 5
    else
      local n = W.npcs[who]
      Timeline.add("arcade", NPCGen.name(n) .. " set a new " .. gname .. " record: " .. score .. ".", 2)
      Rumors.add("record", who, n.first .. " set a record on " .. gname, 4, { who })
      n.rep = U.clamp(n.rep + 5, 0, 100)
      for i, w in ipairs(n.wants) do if w.k == "arcade" then table.remove(n.wants, i) break end end
      if prevTop.who == -1 then
        Pager.send(e.i, "UR " .. gname .. " RECORD IS MINE NOW")
        Memory.add(n, "beat", "beat " .. W.p.name .. "'s record", -1)
        n.rival = game
      end
    end
  end
  return rank
end

function ArcadeSim.witnesses()
  local out = {}
  for _, n in ipairs(NPCAI.inArea("s" .. W.mall.arcade)) do out[#out + 1] = n.id end
  return out
end

function ArcadeSim.skill(n, game)
  n.ask = n.ask or {}
  if not n.ask[game] then
    local base = n.age < 20 and 0.35 or 0.2
    if n.clique == "nerds" or n.clique == "mall rats" then base = base + 0.2 end
    n.ask[game] = U.clamp(base + (U.hash(n.id, game) % 100) / 400, 0, 1)
  end
  return n.ask[game]
end

function ArcadeSim.npcPlay(n)
  local s = W.stores[W.mall.arcade]
  if not s.open or not Stores.isOpenAt(s, W.t) then return end
  local r = U.rng(W.seed, "play", n.id, math.floor(W.t))
  local plays = r:i(1, 4)
  if n.money < plays * 25 then return end
  n.money = n.money - plays * 25
  s.npcSales = (s.npcSales or 0) + plays * 25
  local game = r:pick(Content.ARCADE_GAMES).key
  for _, w in ipairs(n.wants) do if w.k == "arcade" then game = w.ref end end
  local def = ArcadeGames.list[game]
  local m
  for _, mm in ipairs(W.arcade.machines) do if mm.game == game then m = mm end end
  if not def or (m and m.broken) then return end
  for _ = 1, plays do
    local sk = ArcadeSim.skill(n, game)
    local score = def.npcScore(r, sk)
    n.ask[game] = U.clamp(sk + 0.004, 0, 1)
    ArcadeSim.submit(game, n.id, score)
    if m then
      m.plays = m.plays + 1
      m.wear = m.wear + r:i(0, 2)
      if m.wear > 260 and not m.broken then
        m.broken = true
        Timeline.add("arcade", def.name .. " broke down. OUT OF ORDER sign taped to the screen.", 1)
      end
    end
  end
end

-- seed boards with history so the arcade has legends before you arrive
function ArcadeSim.seedBoards()
  for _, g in ipairs(Content.ARCADE_GAMES) do
    local def = ArcadeGames.list[g.key]
    if def then
      local r = U.rng(W.seed, "board", g.key)
      for _ = 1, 60 do
        local n = W.npcs[r:i(1, #W.npcs)]
        if n.age < 30 then
          local b = W.arcade.scores[g.key]
          b[#b + 1] = { i = initials(n), s = def.npcScore(r, math.min(1, ArcadeSim.skill(n, g.key) + 0.25)),
            who = n.id, d = -r:i(1, 900) }
        end
      end
      local b = W.arcade.scores[g.key]
      table.sort(b, function(x, y) return x.s > y.s end)
      while #b > 10 do table.remove(b) end
    end
  end
end

function ArcadeSim.daily()
  -- the arcade crew fixes machines if someone is working
  local r = U.rng(W.seed, "arcfix", Clock.day(W.t))
  for _, m in ipairs(W.arcade.machines) do
    if m.broken and r:chance(0.25) then
      m.broken = false; m.wear = r:i(0, 30)
    end
  end
end

function ArcadeSim.champion()
  local all = true
  for _, g in ipairs(Content.ARCADE_GAMES) do
    local b = W.arcade.scores[g.key]
    if not b[1] or b[1].who ~= -1 then all = false end
  end
  return all
end

-- ------------------------------------------------------------------ tournaments
-- First Saturday of each month, 2-5 PM. Serious kids show up; everyone's
-- best run on the tournament cabinet counts; the winner gets 500 tokens and
-- a month of bragging rights.
local FLAVOR_POOL = { "TIME CRISIS-ISH", "BIG BASS FISHING", "SUPER SPRINT 2", "MORTAL FIGHTER III", "ALIEN AIR HOCKEY",
  "WHACK-A-GATOR", "BOWLING ALLEY 2000", "POP-A-SHOT", "X-FILES PINBALL", "RIDGE RACER-ISH DX" }

function ArcadeSim.startTourney(day, r)
  local g = r:pick(Content.ARCADE_GAMES)
  W.mall.tourney = { day = day, game = g.key, s = 14 * 60, e = 17 * 60, scores = {}, done = false }
  Timeline.add("arcade", "Arcade tournament today, 2-5 PM: " .. g.name .. ". Winner gets 500 tokens.", 2)
  Rumors.add("tourney", nil, "there's a " .. g.name .. " tournament at the arcade on Saturday", 5, ArcadeSim.witnesses())
end

function ArcadeSim.tourneyOn()
  local tn = W.mall.tourney
  if not tn or tn.done or tn.day ~= Clock.day(W.t) then return nil end
  local m = Clock.minute(W.t)
  if m >= tn.s and m < tn.e then return tn end
end

function ArcadeSim.tourneyEntry(who, score)
  local tn = ArcadeSim.tourneyOn()
  if not tn then return end
  local k = tostring(who)
  if not tn.scores[k] or tn.scores[k] < score then tn.scores[k] = score end
end

-- competitors plan to be there
function ArcadeSim.tourneyPlans(day)
  local tn = W.mall.tourney
  if not tn or tn.day ~= day then return end
  local r = U.rng(W.seed, "tplan", day)
  for _, n in ipairs(W.npcs) do
    if n.status == "active" and n.age < 26 and not Stores.shiftOf(n, day) then
      local sk = ArcadeSim.skill(n, tn.game)
      local keen = false
      for _, w in ipairs(n.wants) do if w.k == "arcade" then keen = true end end
      if (keen or sk > 0.5) and r:chance(0.7) then
        local s = tn.s + r:i(0, 90)
        local keep = {}
        for _, b in ipairs(n.plan or {}) do if b.e <= s or b.s >= s + 60 then keep[#keep + 1] = b end end
        keep[#keep + 1] = { s = s, e = s + 60, a = "s" .. W.mall.arcade, act = "tourney" }
        table.sort(keep, function(x, y) return x.s < y.s end)
        n.plan = keep; n.pi = 1
      end
    end
  end
end

function ArcadeSim.npcTourney(n)
  local tn = ArcadeSim.tourneyOn()
  if not tn then return end
  local def = ArcadeGames.list[tn.game]
  local r = U.rng(W.seed, "tplay", n.id, tn.day)
  local sk = ArcadeSim.skill(n, tn.game)
  local best = 0
  for _ = 1, 3 do best = math.max(best, def.npcScore(r, math.min(1, sk + 0.05))) end
  ArcadeSim.tourneyEntry(n.id, best)
  ArcadeSim.submit(tn.game, n.id, best)
end

-- called every tick: settle the tournament at 5 PM
function ArcadeSim.update()
  local tn = W.mall.tourney
  if not tn or tn.done or Clock.day(W.t) < tn.day then return end
  if Clock.day(W.t) == tn.day and Clock.minute(W.t) < tn.e then return end
  tn.done = true
  local bestK, bestS, entrants = nil, -1, 0
  for _, k in ipairs(U.keys(tn.scores)) do
    entrants = entrants + 1
    if tn.scores[k] > bestS then bestK, bestS = k, tn.scores[k] end
  end
  local g = ArcadeGames.list[tn.game]
  if not bestK then Timeline.add("arcade", "Nobody showed up for the arcade tournament.", 1) return end
  local who = tonumber(bestK)
  tn.winner = who
  W.arcade.champs = W.arcade.champs or {}
  W.arcade.champs[#W.arcade.champs + 1] = { day = tn.day, game = tn.game, who = who, score = bestS }
  if who == -1 then
    W.p.tokens = W.p.tokens + 500
    W.p.fame = W.p.fame + 12
    Timeline.add("arcade", W.p.name .. " won the " .. g.name .. " tournament (" .. bestS .. ") against " .. (entrants - 1) .. " other players.", 3)
    Rumors.add("record", -1, W.p.name .. " won the arcade tournament", 8, ArcadeSim.witnesses())
    Pager.send("ARCADE", "U WON!! 500 TOKENS AT THE COUNTER")
  else
    local n = W.npcs[who]
    n.rep = U.clamp(n.rep + 10, 0, 100)
    n.mood = U.clamp(n.mood + 20, 0, 100)
    Timeline.add("arcade", NPCGen.name(n) .. " won the " .. g.name .. " tournament with " .. bestS .. " (" .. entrants .. " entrants).", 2)
    Rumors.add("record", n.id, n.first .. " won the arcade tournament", 6, ArcadeSim.witnesses())
    if tn.scores["-1"] then
      Pager.send(ArcadeSim.initials(n), "GG. BETTER LUCK NEXT MONTH")
      n.rival = true
    end
  end
end

-- monthly: the arcade swaps out its least-played novelty cabinet
function ArcadeSim.rotate(day, r)
  local worst, wp
  for _, m in ipairs(W.arcade.machines) do
    if m.flavor and (not wp or m.plays < wp) then worst, wp = m, m.plays end
  end
  if not worst then return end
  local used = {}
  for _, m in ipairs(W.arcade.machines) do if m.flavor then used[m.flavor] = true end end
  local cands = {}
  for _, f in ipairs(FLAVOR_POOL) do if not used[f] then cands[#cands + 1] = f end end
  local new = r:pick(cands)
  if not new then return end
  Timeline.add("arcade", "The arcade hauled out " .. worst.flavor .. " and wheeled in a new cabinet: " .. new .. ".", 1)
  worst.flavor = new; worst.plays = 0; worst.wear = 0; worst.broken = false
end

-- player vs NPC challenge: returns npc score
function ArcadeSim.challengeScore(n, game)
  local r = U.rng(W.seed, "chal", n.id, math.floor(W.t))
  return ArcadeGames.list[game].npcScore(r, math.min(1, ArcadeSim.skill(n, game) + 0.1))
end
