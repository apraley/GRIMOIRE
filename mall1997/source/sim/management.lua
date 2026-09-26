-- Mall management and store-to-store politics.
--
-- Neighbouring stores affect each other's business (spillover traffic,
-- noise, smells, competition). Bad relations become feuds with petty
-- incidents that management has to mediate; good relations become joint
-- promotions. The general manager reviews the mall weekly and changes
-- house rules in response to what's happening (fights, theft waves,
-- falling traffic), and those rules feed back into NPC behaviour.

Management = {}

-- how a neighbour of type b affects a store of type a (traffic multiplier delta)
local SPILL = {
  arcade = { books = -0.06, jewelry = -0.05, games = 0.08, music = 0.05, food = 0.04 },
  music = { jewelry = -0.03, books = -0.02, clothing = 0.03, games = 0.03 },
  food = { clothing = -0.02, arcade = 0.04, games = 0.02 },
  department = { clothing = 0.04, shoes = 0.04, jewelry = 0.04, gifts = 0.03 },
  cinema = { food = 0.06, arcade = 0.05, video = -0.04 },
  toys = { games = 0.03, books = 0.02 },
  weird = { jewelry = -0.02, weird = 0.02 },
}
-- pairs that get on each other's nerves (weekly relation drift)
local FRICTION = {
  arcade = { books = 5, jewelry = 4, services = 3 }, music = { books = 3, jewelry = 3, salon = 2 },
  food = { clothing = 2, jewelry = 2 }, restaurant = { salon = 2 }, weird = { jewelry = 2, department = 2 },
}
local SYNERGY = { clothing = { shoes = 3, jewelry = 2 }, shoes = { clothing = 3, sporting = 2 },
  books = { music = 1, gifts = 2 }, toys = { games = 3 }, gifts = { toys = 2, books = 2 } }

local function pairVal(t, a, b) return (t[a] and t[a][b] or 0) + (t[b] and t[b][a] or 0) end

-- traffic multiplier from a store's neighbours (called from Stores.weight)
function Management.neighborEffect(s)
  local m = 1
  for _, nid in ipairs(s.nbr or {}) do
    local o = W.stores[nid]
    if o and o.open then
      local sp = SPILL[o.type]
      if sp and sp[s.type] then m = m + sp[s.type] end
      -- a busy neighbour sends people past your window
      m = m + (o.pop - 50) * 0.0015
      if o.closing then m = m - 0.02 end
    end
  end
  if s.feud then m = m - 0.03 end
  if s.coop and s.coop > Clock.day(W.t) - 14 then m = m + 0.08 end
  return math.max(0.6, m)
end

function Management.drift(s, o, r)
  return -pairVal(FRICTION, s.type, o.type) + pairVal(SYNERGY, s.type, o.type)
end

local INCIDENTS = {
  "someone keeps parking a trash cart in front of {a}'s window",
  "{a} called mall management about {b}'s music. Again",
  "{b}'s staff were caught taking {a}'s break chairs",
  "a sign in {a}'s window now says 'PARDON THE NOISE FROM NEXT DOOR'",
  "{b} started a sale on the same day as {a}'s sale. On purpose, allegedly",
  "{a}'s manager left a note on {b}'s door that ended with 'regards'",
}

-- weekly: feuds generate incidents; management mediates or fines
function Management.feuds(day, r)
  local gm = W.npcs[W.mall.gm]
  for _, s in ipairs(W.stores) do
    if s.open and s.feud and s.feud > s.id then
      local o = W.stores[s.feud]
      if o and o.open then
        s.feudWeeks = (s.feudWeeks or 0) + 1
        if r:chance(0.45) then
          local a, b = s, o
          if r:chance(0.5) then a, b = o, s end
          local txt = U.fmt(r:pick(INCIDENTS), { a = a.name, b = b.name })
          Timeline.add("store", "Feud: " .. txt .. ".", 1)
          Rumors.add("feud", nil, txt, 4, { a.mgr, b.mgr }, { store = a.id })
          b.pop = U.clamp(b.pop - 2, 0, 100)
          for _, e in ipairs(a.emp) do for _, f in ipairs(b.emp) do
            if r:chance(0.25) then NPCGen.setRel(W.npcs[e], W.npcs[f], -6) end end end
        end
        -- management steps in
        if s.feudWeeks >= 3 and r:chance(0.35) then
          local fined = r:chance(0.5) and s or o
          fined.cash = fined.cash - 20000
          s.nrel[o.id] = (s.nrel[o.id] or 0) + 30; o.nrel[s.id] = s.nrel[o.id]
          Timeline.add("mall", (gm and gm.first or "The GM") .. " from mall management sat down with " .. s.name .. " and " .. o.name ..
            ". " .. fined.name .. " got a $200 fine for 'common area violations'.", 2)
          if gm then Memory.add(gm, "mediated", "mediated " .. s.name .. " vs " .. o.name) end
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ policies
Management.POLICIES = {
  teenEscort = { name = "Parental Escort Policy", txt = "Kids under 16 need a parent with them after 6 PM on Fridays and Saturdays." },
  noSkate = { name = "No Wheels", txt = "No skateboards, rollerblades or roller skates in the mall." },
  extraGuard = { name = "Extra Security", txt = "Mall security added a guard to the evening shift." },
  teenNightPaused = { name = "Teen Night Suspended", txt = "Teen Night is cancelled until further notice." },
  walkerHours = { name = "Mall Walkers Welcome", txt = "Doors open at 6:30 AM for mall walkers." },
  loitering = { name = "No Loitering", txt = "Security will move along groups hanging out by the fountain." },
}

function Management.has(key) return W.mall.policies and W.mall.policies[key] ~= nil end

local function enact(key, day)
  W.mall.policies = W.mall.policies or {}
  if W.mall.policies[key] then return end
  W.mall.policies[key] = day
  local P = Management.POLICIES[key]
  Timeline.add("mall", "New mall policy — " .. P.name .. ": " .. P.txt, 3)
  Rumors.add("policy", nil, "the mall office made a new rule: " .. P.txt:lower(), 6, W.mall.mgmt)
  if key == "extraGuard" then
    local r = U.rng(W.seed, "guard", day)
    local n = NPCGen.new(W, r, "security", r:i(22, 50))
    n.job = "sec"; n.title = "officer"; n.wage = 750
    W.mall.security[#W.mall.security + 1] = n.id
    NPCAI.planDay(n, day)
  end
end

local function repeal(key, why)
  if not Management.has(key) then return end
  W.mall.policies[key] = nil
  Timeline.add("mall", "Policy lifted: " .. Management.POLICIES[key].name .. " (" .. why .. ").", 2)
end

-- the GM's weekly review
function Management.review(day, r)
  W.mall.review = W.mall.review or { fights = 0 }
  local rv = W.mall.review
  local thefts = W.mall.theftHist and W.mall.theftHist[#W.mall.theftHist] or 0
  local fights = rv.fights or 0
  rv.fights = 0
  local foot = W.mall.lastFootfall or 4000
  rv.footHist = rv.footHist or {}
  rv.footHist[#rv.footHist + 1] = foot
  U.trim(rv.footHist, 6)
  if fights >= 3 and not Management.has("teenEscort") then enact("teenEscort", day)
  elseif Management.has("teenEscort") and fights == 0 and day - W.mall.policies.teenEscort > 28 then
    repeal("teenEscort", "quiet month, and the food court sales fell")
  end
  if fights >= 2 and not Management.has("loitering") and r:chance(0.5) then enact("loitering", day) end
  if thefts >= 14 and not Management.has("extraGuard") then enact("extraGuard", day) end
  if fights >= 4 and not Management.has("teenNightPaused") then enact("teenNightPaused", day)
  elseif Management.has("teenNightPaused") and day - W.mall.policies.teenNightPaused > 21 then
    repeal("teenNightPaused", "a petition with 212 signatures")
  end
  if r:chance(0.05) and not Management.has("noSkate") then enact("noSkate", day) end
  -- falling traffic: the GM tries promotions
  local fh = rv.footHist
  if #fh >= 3 and fh[#fh] < fh[#fh - 2] * 0.9 and r:chance(0.5) then
    local promo = r:pick({ "a 'Midnight Madness' sale night", "a car giveaway in center court", "a radio station live remote",
      "free carousel rides (there is no carousel)", "a Back-to-School fashion show" })
    W.mall.appeal = U.clamp((W.mall.appeal or 1) + 0.03, 0.6, 1.2)
    Timeline.add("mall", "Mall management announced " .. promo .. " to bring people back.", 2)
  end
end

function Management.weekly(day)
  local r = U.rng(W.seed, "mgmt", day)
  Management.feuds(day, r)
  Management.review(day, r)
end

function Management.noteFight() W.mall.review = W.mall.review or { fights = 0 }; W.mall.review.fights = (W.mall.review.fights or 0) + 1 end
