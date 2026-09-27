-- Calling someone out: a best-of-three face-off in front of whoever is
-- around. Each round you pick a move and so do they:
--   ROAST  dirt you've dug up on them (rumors, secrets their crew leaked)
--   FLEX   the best stuff in your bag, your fame, your hair
--   CREW   friends standing in the room with you, turf you already hold
-- Everyone has a weak spot (your move hits 1.5x) and a strong suit (0.6x).
-- Each move can be used twice.

Showdown = {}

local ROASTS = {
  "\"Nice jacket. Did your mom get it at Kids R Us?\"", "\"You peaked in the sixth grade and everybody knows it.\"",
  "\"I've seen better hair on a Troll doll.\"", "\"You're the reason they put instructions on shampoo.\"",
  "\"Is that your real laugh? Like, on purpose?\"",
}
local THEIR = {
  roast = { "\"Hey everybody, the new kid thinks they're somebody.\"", "\"Didn't your family move here because nobody liked you?\"",
    "\"Cute backpack. Is it from the Lost and Found?\"", "\"You smell like the bus.\"" },
  flex = { "%s flips open a brand new StarTAC.", "%s shows off a pair of Air Jordans, still in the box.",
    "%s peels a twenty off a fat roll of bills.", "%s mentions, again, the Jeep they get on their birthday." },
  crew = { "%s's crew closes ranks behind them.", "Half the room starts chanting %s's name.",
    "Somebody hands %s a Slurpee. Somebody else holds their jacket." },
}

local function bestItem()
  local best
  for _, it in ipairs(W.p.inv) do
    if it.k ~= "gear" and it.k ~= "key" and not it.due and (not best or (it.v or 0) > (best.v or 0)) then best = it end
  end
  return best
end

local function dirtLine(boss, rng)
  local p = W.p
  local list = {}
  for _, sc in ipairs(p.secrets or {}) do if sc.npc == boss.id then list[#list + 1] = "You tell everyone that " .. boss.first .. " " .. sc.txt .. "." end end
  for _, rm in ipairs(W.rumors) do
    if rm.about == boss.id and p.knownRumors[rm.id] then list[#list + 1] = "You bring up how " .. rm.txt .. "." end
  end
  if #list > 0 then return list[rng:i(1, #list)] end
  return ROASTS[rng:i(1, #ROASTS)]
end

local function flexLine()
  local it = bestItem()
  if it and (it.v or 0) >= 1500 then return "You casually pull " .. U.a(it.n) .. " out of your backpack." end
  if W.p.fame >= 10 then return "Someone in the crowd whispers, \"Isn't that the kid who...?\"" end
  return "You flex... your house key. Nobody is impressed."
end

local function crewLine(boss)
  local p = W.p
  if p.companion and W.npcs[p.companion] then return W.npcs[p.companion].first .. " steps up right next to you." end
  for _, n in ipairs(NPCAI.inArea(p.area)) do
    if n.id ~= boss.id and n.age < 20 and n.p.f >= 25 then return n.first .. " steps out of the crowd to stand with you." end
  end
  if Turf.held() > 0 then return "You mention, casually, which turfs are already yours." end
  return "You look around for backup. Nobody moves."
end

function Showdown.start(boss)
  local key = boss.turfBoss
  local zdef = Turf.BY[key]
  local z = Turf.zone(key)
  local rng = U.rng(W.seed, "showdown", boss.id, math.floor(W.t))
  local st = { you = 0, them = 0, round = 1, used = { roast = 0, flex = 0, crew = 0 } }
  local who = { npc = boss, name = boss.first }
  local function finish()
    WorldSim.advance(W.t + 8, 1)
    if st.you > st.them then
      local king = Turf.win(boss)
      local lines = { boss.first .. " opens their mouth, closes it, and walks off.", U.cap(zdef.name) .. " is yours now." }
      if #z.crew > 0 then lines[#lines + 1] = "A couple of " .. boss.first .. "'s crew nod at you on their way out. That's new." end
      if king then
        lines[#lines + 1] = "That was the last one."
        lines[#lines + 1] = "Three weeks ago nobody in " .. W.mall.city .. " knew your name. Now every turf in " .. W.mall.name .. " is yours."
        lines[#lines + 1] = "The new kid runs the mall. (Keep showing up, or somebody will take it back.)"
      end
      Sfx.ok()
      Say(lines, { npc = boss, name = boss.first, mood = "sad" })
    else
      Turf.lose(boss)
      Sfx.bad()
      Say({ "The crowd drifts off, still laughing.", "\"Run along, new kid.\"",
        "(Dig up more dirt, bring friends, or get better stuff, then try again in a couple of days.)" },
        { npc = boss, name = boss.first, mood = "happy" })
    end
  end
  local round
  local function resolve(move)
    st.used[move] = st.used[move] + 1
    local mine, theirs, bm, mult = Turf.round(boss, move, rng)
    local lines = {}
    if move == "roast" then lines[#lines + 1] = dirtLine(boss, rng)
    elseif move == "flex" then lines[#lines + 1] = flexLine()
    else lines[#lines + 1] = crewLine(boss) end
    if mult > 1 then lines[#lines + 1] = boss.first .. " has nothing for that. You can see it land."
    elseif mult < 1 then lines[#lines + 1] = boss.first .. " was ready for that one." end
    local tl = THEIR[bm][rng:i(1, #THEIR[bm])]
    lines[#lines + 1] = tl:find("%%s") and string.format(tl, boss.first) or tl
    if mine > theirs then
      st.you = st.you + 1
      lines[#lines + 1] = "The crowd goes \"OHHHH.\" Point: you.  (" .. st.you .. "-" .. st.them .. ")"
    elseif mine < theirs then
      st.them = st.them + 1
      lines[#lines + 1] = "People laugh. Not with you. Point: " .. boss.first .. ".  (" .. st.you .. "-" .. st.them .. ")"
    else
      lines[#lines + 1] = "Nobody can tell who won that one.  (" .. st.you .. "-" .. st.them .. ")"
    end
    st.round = st.round + 1
    Say(lines, { npc = boss, name = boss.first, after = function()
      if st.you >= 2 or st.them >= 2 or st.round > 5 then finish() else round() end
    end })
  end
  round = function()
    local items = {}
    for i, m in ipairs(Turf.MOVES) do
      local label = U.cap(m) .. "  (" .. Turf.power(m, boss) .. ")"
      items[i] = { label = label, disabled = st.used[m] >= 2 }
    end
    Choose("ROUND " .. st.round .. ":  YOU " .. st.you .. " - " .. st.them .. " " .. boss.first:upper(), items, function(i)
      resolve(Turf.MOVES[i])
    end, { x = 40, w = 180, npc = boss, mood = "angry",
      prompt = "Roast: dirt on them. Flex: your stuff, your fame. Crew: who's got your back here. (Each move twice.)" })
  end
  Say({ "Word gets around fast. By the time you find " .. boss.first .. ", half of " .. zdef.name .. " is watching.",
    "\"You've got some nerve, new kid. Go on then.\"" }, { npc = boss, name = boss.first, mood = "angry", after = round })
end
