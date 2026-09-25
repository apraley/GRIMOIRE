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
