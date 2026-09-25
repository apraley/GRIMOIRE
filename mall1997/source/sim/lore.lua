-- The secret mall. Mundane mythology accumulates first (rumors that old
-- walkers and night staff pass around); physical places are discovered
-- later, and each discovery explains a little and complicates a little.

Lore = {}

Lore.MYTHS = {
  { key = "well", txt = "the fountain was built over the old Hollis farm well", heat = 4 },
  { key = "vents", txt = "a kid got lost in the air vents in 1989 and came out in the Sears-that-was", heat = 3 },
  { key = "shelter", txt = "there's a fallout shelter under the mall from before it was built", heat = 4 },
  { key = "store", txt = "that one storefront has said COMING SOON since 1991", heat = 3 },
  { key = "janitor", txt = "the night janitor talks to somebody after closing, but he's alone", heat = 5 },
  { key = "developer", txt = "the man who built the mall disappeared in 1979 owing everybody money", heat = 3 },
  { key = "roof", txt = "you can get on the roof from the maintenance room if you know who to ask", heat = 4 },
  { key = "ghost", txt = "somebody's been sleeping in the empty store; people call it the Mall Ghost", heat = 5 },
  { key = "model", txt = "the mall is exactly the same as a little model of it somewhere", heat = 2 },
}

Lore.NOTES = {
  svc = { "Service Corridors", "Behind the storefronts there's a second mall: cinderblock, fluorescent tubes, cardboard, and a smell like old fryer oil. Every store has a back door. Nobody decorates back here." },
  ab = { "The Vacant Storefront", "Formerly KINNEY KAMERA (closed Nov. 1991). The calendar is still on November. There's a sleeping bag, a flashlight, and a stack of library books due in 1996. Somebody lives here, sometimes. The 'Mall Ghost' is a person." },
  roof = { "The Roof", "Gravel, humming air handlers, and the skylight over center court: from up here the fountain looks like a coin. Someone left a lawn chair facing the parking lot, and a pile of 1980s magazines weighed down with a brick." },
  key = { "A Key Under the Chair", "Taped under the lawn chair on the roof: a brass key stamped MAINT-T. Somebody wanted it found, or wanted to find it again." },
  tun = { "Maintenance Tunnels", "Under the mall: pipe tunnels older than the building, stenciled 1962. The dust has footprints in it. Recent ones. One set, always the same boots." },
  graffiti = { "Tunnel Graffiti", "Chalk on the pipe: a number circled twice: {d4}. Underneath, in careful handwriting: 'for when I forget.'" },
  shel = { "Fallout Shelter", "A civil-defense shelter from 1962, from when this was farmland. Water drums, crackers, bunks. Yellow-and-black sign. The mall was built right over it and nobody filled it in." },
  supplies = { "Shelter Supplies", "Survival crackers dated 1963. Somebody has been swapping the water drums. The newest one says '97." },
  off = { "The Forgotten Office", "A sealed office from 1979. Wood paneling, a dead rubber plant, a desk calendar on June 1979. Letters from creditors. The developer's name is on everything: R. Hollis." },
  memo = { "Developer's Memo", "'Keep the model current. It is the only honest copy. Combination as agreed: first two digits are the year of the fountain plaque, the last is on the pipe.' The third digit is written in the margin: {d3}." },
  blueprint = { "Blueprints", "Original 1971 plans. The mall was supposed to have a second phase: a whole wing that was never built. On the plans, a small room under center court is labeled only: MODEL." },
  calendar79 = { "1979 Calendar", "June 1979. One date circled: the day the fountain was dedicated. A note: 'Plaque says '72. It was always '72. Don't let them change it.'" },
  calendar91 = { "1991 Calendar", "November 1991. The camera store's last month. Somebody has kept crossing off days on a new calendar taped next to it, up to last week." },
  sleepingbag = { "The Sleeping Bag", "Clean, rolled tight. A name written inside the collar in marker, faded past reading. A cassette Walkman with a mix tape labeled SUMMER 94." },
  oldcounter = { "Old Counter", "Under the counter: a box of unclaimed photos from 1991. Birthday parties. A prom. Someone's dog. Nobody ever came back for them." },
  fountain = { "The Fountain Plaque", "DEDICATED TO THE PEOPLE OF {city}, 19{d12}. Pennies all over the bottom, and one old key nobody can reach." },
  lock = { "The Locked Room", "It's a model. The whole mall at 1:100 scale, every storefront, every sign, perfectly current. Tiny figures stand in the food court." },
  model = { "The Model", "Stores that closed this year are dark. Stores that opened are there too. One storefront is labeled with a store that hasn't opened yet." },
  ledger = { "The Janitor's Ledger", "Twenty years of handwriting: every store that ever opened or closed here, every manager, every broken escalator. Tonight's entry is already written." },
  roofchair = { "The Lawn Chair", "It's facing the sunset side of the parking lot. It's where somebody sits on their break. There's a thermos." },
}

function Lore.seed(r)
  -- combination for the locked room: 4 digits
  local plaque = 72
  local d3, d4 = r:i(0, 9), r:i(0, 9)
  W.mall.combo = string.format("%02d%d%d", plaque, d3, d4)
  W.mall.comboParts = { d12 = string.format("%02d", plaque), d3 = tostring(d3), d4 = tostring(d4) }
  -- old-timers know the myths
  local elders = {}
  for _, n in ipairs(W.npcs) do
    if n.role == "walker" or n.role == "maint" or (n.role == "manager" and n.age > 45) then elders[#elders + 1] = n.id end
  end
  for _, m in ipairs(Lore.MYTHS) do
    local seeds = {}
    for _ = 1, 3 do seeds[#seeds + 1] = elders[r:i(1, #elders)] end
    Rumors.add("lore", nil, m.txt, m.heat, seeds, { lore = m.key })
  end
end

function Lore.noteText(key)
  local n = Lore.NOTES[key]
  if not n then return key, "" end
  local parts = W.mall.comboParts or {}
  local txt = n[2]:gsub("{(%w+)}", function(k) return parts[k] or (k == "city" and (W.mall.city or ""):upper()) or "?" end)
  return n[1], txt
end

function Lore.discover(key)
  local p = W.p
  if p.lore[key] then return false end
  p.lore[key] = Clock.day(W.t)
  local title = Lore.noteText(key)
  Timeline.add("lore", p.name .. " discovered: " .. title .. ".", 2)
  p.fame = p.fame + 1
  return true
end

function Lore.count()
  local c = 0
  for _ in pairs(W.p.lore) do c = c + 1 end
  return c
end

function Lore.total() return U.count(Lore.NOTES) end

-- the model shows the next store to open (from the leasing pipeline)
function Lore.prophecy()
  for _, sl in ipairs(W.slots) do
    if sl.coming then return MallGen.TYPE_LABEL[sl.coming.type] .. " store, " .. (sl.floor == 1 and "lower" or "upper") .. " level" end
  end
  return "a storefront with a hand-lettered sign that just says " .. (W.p.name or "YOU"):upper()
end
