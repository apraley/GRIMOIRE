-- The persistent world. Everything that must survive a save lives in the
-- global table W; derived data (area geometry, caches) lives elsewhere.

World = {}
W = nil

World.VERSION = 3
World.START_T = 15 * 60 + 30 -- 3:30 PM on day 0

function World.new(seed, playerName)
  W = {
    ver = World.VERSION, seed = seed, t = 7 * 60, lastDay = -1,
    stores = {}, slots = {}, npcs = {}, rumors = {}, timeline = {}, cams = {},
    trends = {}, events = {}, incidents = {}, nextRumor = 1,
    mall = {}, stats = { thefts = 0, caught = 0, closures = 0, openings = 0, breakups = 0, couples = 0,
      hires = 0, quits = 0, fires = 0, mgrChanges = 0, records = 0, bans = 0, feuds = 0 },
    _usedNames = {},
    p = {
      name = playerName or "Alex", age = 16, money = 2200, energy = 90, hunger = 25, conf = 45, rep = 20,
      inv = {}, pager = {}, job = nil, bans = {}, mallBan = 0, grounded = 0, curfewShift = 0,
      area = "lot", x = 20 * 16 + 8, y = 18 * 16, dir = "up", tokens = 0,
      knownRumors = {}, lore = {}, keys = {}, evidence = {}, record = 0,
      stats = { movies = {}, albums = {}, arcade = {}, stolen = 0, caught = 0, dates = 0, earned = 0,
        shifts = 0, talks = 0, days = 0, gigs = 0, itemsBought = 0 },
      flags = {}, band = nil, fame = 0, cliqueRep = {}, taste = nil, dayLog = {}, invites = {},
      atMall = false,
    },
  }
  local r = RNG.new(seed)
  W.mall.name = Content.mallName(r)
  W.mall.opened = 1972
  W.mall.city = r:pick({ "Millbrook", "Ashford", "Glen Haven", "Port Clement", "Wexley" })
  W.music = Content.genMusic(r)
  W.movies = Content.genMovies(r)
  W.arcade = Content.genArcade(r)
  MallGen.genLayout(W, r)
  MallGen.genStores(W, r)
  MallGen.genCameras(W, r)
  NPCGen.genPopulation(W, r)
  W.p.pager[#W.p.pager + 1] = { t = W.t, from = "MOM", txt = "HAVE FUN. HOME BY 9. LOVE MOM", read = false }
  W.p.inv[#W.p.inv + 1] = { k = "gear", n = "pager", v = 0 }
  W.p.inv[#W.p.inv + 1] = { k = "gear", n = "backpack", v = 0 }
  W.p.inv[#W.p.inv + 1] = { k = "gear", n = "house key", v = 0 }
  Timeline.add("mall", W.mall.name .. " has been open since " .. W.mall.opened .. ".", -1)
  Lore.seed(r)
  Trends.seed(r)
  W._usedNames = nil
  WorldSim.bootstrap()
  return W
end

-- ------------------------------------------------------------------ timeline
Timeline = {}
-- cat: mall, store, people, player, arcade, crime, music, movie, lore, job
function Timeline.add(cat, txt, importance, t)
  local e = { t = math.floor(t or W.t), cat = cat, txt = txt, imp = importance or 1 }
  W.timeline[#W.timeline + 1] = e
  if #W.timeline > 900 then table.remove(W.timeline, 1) end
  if W.p and W.p.dayLog and importance and importance >= 2 then
    W.p.dayLog[#W.p.dayLog + 1] = txt
  end
  return e
end

function Timeline.recent(n, filter)
  local out = {}
  for i = #W.timeline, 1, -1 do
    local e = W.timeline[i]
    if not filter or filter(e) then out[#out + 1] = e end
    if #out >= n then break end
  end
  return out
end

-- ------------------------------------------------------------------ pager
Pager = {}
function Pager.send(from, txt)
  local p = W.p
  p.pager[#p.pager + 1] = { t = math.floor(W.t), from = from, txt = txt, read = false }
  U.trim(p.pager, 40)
  Pager.flash = 60
  if Sfx then Sfx.blip(1500, 0.08) end
end
function Pager.unread()
  local n = 0
  for _, m in ipairs(W.p.pager) do if not m.read then n = n + 1 end end
  return n
end

-- ------------------------------------------------------------------ rumors
-- A rumor is a piece of social information moving through the population.
-- r.known is a set of npc ids who know it; r.about is an npc id (or -1 for
-- the player); kind drives how people react when they hear it.
Rumors = {}

function Rumors.add(kind, about, txt, heat, seeds, extra)
  local r = { id = W.nextRumor, kind = kind, about = about, txt = txt, heat = heat or 5,
    day = Clock.day(W.t), known = {}, n = 0 }
  W.nextRumor = W.nextRumor + 1
  if extra then for k, v in pairs(extra) do r[k] = v end end
  W.rumors[#W.rumors + 1] = r
  for _, id in ipairs(seeds or {}) do Rumors.learn(r, W.npcs[id]) end
  return r
end

function Rumors.knows(r, n) return r.known[n.id] == true end

function Rumors.learn(r, n)
  if not n or r.known[n.id] then return false end
  r.known[n.id] = true
  r.n = r.n + 1
  Social.onRumor(n, r)
  return true
end

-- Rumors cool off; cold rumors with nobody left talking are forgotten.
function Rumors.daily()
  local keep = {}
  for _, r in ipairs(W.rumors) do
    local age = Clock.day(W.t) - r.day
    if age > 2 and not r.lore then r.heat = r.heat - 0.5 end
    if r.heat > 0 or r.lore or (r.about == -1 and age < 60) then keep[#keep + 1] = r end
  end
  W.rumors = keep
end

function Rumors.about(id)
  local out = {}
  for _, r in ipairs(W.rumors) do if r.about == id then out[#out + 1] = r end end
  return out
end

-- a variant of a rumor that has been exaggerated in the retelling
local EXAGGERATE = {
  { "caught stealing", "arrested for stealing" }, { "broke up", "had a screaming breakup" },
  { "is dating", "is secretly engaged to" }, { "got fired", "got escorted out by security" },
  { "was banned", "was banned for life" }, { "set a record", "is some kind of arcade genius" },
  { "is closing", "is going bankrupt" }, { "had a fight", "threw a smoothie at" },
}
function Rumors.mutate(r, teller)
  for _, e in ipairs(EXAGGERATE) do
    local a, b = e[1], e[2]
    if r.txt:find(a, 1, true) and not r.mutated and not r.hasVariant then
      r.hasVariant = true
      local nr = Rumors.add(r.kind, r.about, r.txt:gsub(a, b), r.heat + 1, { teller.id },
        { mutated = true, parent = r.id, store = r.store, lore = r.lore })
      return nr
    end
  end
  return nil
end
