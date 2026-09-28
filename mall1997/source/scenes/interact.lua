-- What happens when you press A on a thing in the world.

Interact = {}

local LABELS = {
  counter = "Counter", rack = "Browse", stall = "Order", booth = "Box office", concession = "Snacks",
  screen = "Theater door", cab = "Arcade machine", tokens = "Token machine", prize = "Prize counter",
  chair = "Salon chair", lab = "Photo lab", phone = "Pay phone", directory = "Mall directory",
  fountain = "Fountain", bench = "Sit", kiosk = "Kiosk", table = "Table", stage = "Stage", bus = "Bus stop",
  monitors = "Monitors", desk = "Desk", timeclock = "Time clock", crates = "Stock boxes", reception = "Front desk",
  leasing = "Leasing board", workbench = "Workbench", ladder = "Ladder", hatch = "Hatch", locker = "Lockers",
  lockdoor = "Steel door", model = "Model", ledger = "Ledger", dumpster = "Dumpster", truck = "Truck",
  listen = "Listening station", dropbox = "Return slot", fitting = "Fitting room", holding = "Holding room",
  skylight = "Skylight", view = "View", hvac = "Air handler", supplies = "Supplies", bunks = "Bunks",
  blueprints = "Blueprints", calendar = "Calendar", graffiti = "Chalk marks", sleepingbag = "Sleeping bag",
  oldcounter = "Old counter", papered = "Papered window", escalator = "Escalator", atrium = "Railing",
  pipes = "Pipes", poster = "Poster", lamp = "Lamp post",
}

function Interact.label(o)
  if o.kind == "cab" then
    local m = W.arcade.machines[o.machine]
    if m then
      if m.game then return (ArcadeGames.list[m.game] and ArcadeGames.list[m.game].name) or "Arcade game" end
      return m.flavor
    end
  end
  if o.kind == "kiosk" then return U.cap(o.what) .. " kiosk" end
  if o.kind == "stall" or o.kind == "counter" then
    local s = W.stores[o.store]
    return s and s.name or "Counter"
  end
  if o.lore then return LABELS[o.kind] or "Look" end
  return LABELS[o.kind] or "Look"
end

local function storeOf(o) return o.store and W.stores[o.store] end

local function lore(key)
  local fresh = Lore.discover(key)
  local title, txt = Lore.noteText(key)
  Say({ title:upper(), txt })
  return fresh
end

function Interact.object(o)
  local p = W.p
  local k = o.kind
  local s = storeOf(o)
  if o.lore and k ~= "model" and k ~= "chair" then lore(o.lore) return end
  if k == "counter" then Shop.counter(s)
  elseif k == "rack" then Shop.browse(s, o)
  elseif k == "stall" then Shop.stall(s)
  elseif k == "booth" then Shop.boxOffice(s)
  elseif k == "concession" then Shop.concession(s)
  elseif k == "screen" then Play.screenDoor(o)
  elseif k == "cab" then Play.cabinet(o)
  elseif k == "tokens" then Play.tokenMachine()
  elseif k == "prize" then Play.prizeWheel()
  elseif k == "chair" then
    if o.lore then
      lore(o.lore)
      if not p.keys.tunnel then
        p.keys.tunnel = true
        Econ.give({ k = "key", n = "brass key (MAINT-T)", v = 0 })
        Lore.discover("key")
        local title, txt = Lore.noteText("key")
        Say({ title:upper(), txt })
      end
      return
    end
    Shop.menuBuy(s, Econ.rack(s, 1))
  elseif k == "lab" then
    if p.job and p.job.store == s.id then Play.clockIn() else Say("The minilab hums and smells like vinegar.") end
  elseif k == "listen" then
    local items = Econ.rack(s, 1)
    local it = items[1]
    if it then Say("You put on the big headphones. " .. it.n .. " — " .. (it.mood or "loud") .. ". You kind of get it now.")
      W.p.conf = U.clamp(W.p.conf + 1, 0, 100)
    end
  elseif k == "dropbox" then
    local returned = false
    for _, it in ipairs(p.inv) do
      if it.due then Say(PlayerSim.returnRental(it)); returned = true break end
    end
    if not returned then Say("BE KIND, REWIND.") end
  elseif k == "fitting" then
    Say("You try on something in the tiny booth with the saloon doors. You look... fine. Honestly, good.")
    p.conf = U.clamp(p.conf + 2, 0, 100)
  elseif k == "phone" then Interact.payphone()
  elseif k == "directory" then Menu.open("MALL")
  elseif k == "fountain" then
    Choose("FOUNTAIN", { "Toss a penny", "Read the plaque", "Stare at the water" }, function(i)
      if i == 1 then
        if p.money < 1 then Say("You don't even have a penny.") return end
        p.money = p.money - 1
        p.conf = U.clamp(p.conf + 3, 0, 100)
        Say("Plink. You make a wish. You don't tell anyone what it was.")
      elseif i == 2 then lore("fountain")
      else
        WorldSim.advance(W.t + 10, 2)
        p.energy = U.clamp(p.energy + 5, 0, 100)
        Say("Ten minutes vanish. The water sounds like applause from very far away.")
      end
    end, {})
  elseif k == "bench" or k == "table" then Interact.sit(o)
  elseif k == "kiosk" then Shop.kiosk(o)
  elseif k == "stage" then Play.stage()
  elseif k == "bus" then
    Confirm("Take the bus home?", function() Day.endDay("bus") end)
  elseif k == "monitors" then
    if p.job and p.job.store == "sec" then Play.clockIn()
    else Say("Twelve tiny black-and-white screens. On one of them, a kid is picking his nose by the fountain. \"Hey. Out.\"") end
  elseif k == "desk" then Interact.desk(o)
  elseif k == "timeclock" then
    if p.job and s and p.job.store == s.id then Play.clockIn()
    else Say("A time clock and a rack of punch cards. None of them have your name.") end
  elseif k == "crates" then Say("Boxes of stock: " .. (s and MallGen.TYPE_LABEL[s.type]:lower() or "stuff") .. ", a broken display, and someone's lunch.")
  elseif k == "reception" then Interact.mallOffice()
  elseif k == "leasing" then
    local lines = { "LEASING BOARD: " }
    for _, sl in ipairs(W.slots) do
      if sl.kind == "store" and not sl.store and not sl.abandoned then
        lines[#lines + 1] = (sl.coming and ("Signed: " .. MallGen.TYPE_LABEL[sl.coming.type] .. " opening " .. Clock.shortDate(sl.coming.day))
          or "Available: unit " .. sl.id .. ", " .. (sl.floor == 1 and "lower" or "upper") .. " level")
      end
    end
    Say(#lines > 1 and table.concat(lines, "  ") or "LEASING BOARD: Fully leased! (for now)")
  elseif k == "workbench" then
    local maintHere = false
    for _, n in ipairs(NPCAI.inArea(p.area)) do if n.job == "maint" and not n.route then maintHere = true end end
    if p.keys.pry then Say("Wrenches, a coffee can of screws, a radio playing oldies.")
    elseif maintHere then Say("\"Hands off the tools, kid.\"")
    else
      Confirm("There's a pry bar on the bench. Take it?", function()
        p.keys.pry = true
        Econ.give({ k = "key", n = "pry bar", v = 0, from = "stolen" })
        Say("You slide the pry bar into your backpack. It does not fit. You carry it awkwardly.")
      end)
    end
  elseif k == "ladder" then
    local ok = p.keys.roof
    if not ok then
      for _, n in ipairs(NPCAI.inArea(p.area)) do if n.job == "maint" and n.p.f >= 40 then ok = true end end
    end
    if ok then Explore.go("roof", 10 * 16 + 8, 3 * 16) else Say("The ladder goes up to a hatch with a padlock. ROOF ACCESS - AUTHORIZED ONLY.") end
  elseif k == "hatch" then
    if p.keys.tunnel then Explore.go("tun", 3 * 16 + 8, 6 * 16 + 12)
    else Say("A steel hatch in the floor, stenciled T. Padlocked. Cold air comes up through the seam.") end
  elseif k == "locker" then Say("Lockers with names on tape. One says HOLLIS in very old marker.")
  elseif k == "lockdoor" then Secret.combo()
  elseif k == "model" then Secret.model()
  elseif k == "ledger" then Secret.ledger()
  elseif k == "dumpster" then Interact.dumpster()
  elseif k == "truck" then Say("A delivery truck idles. The driver is asleep with a newspaper over his face.")
  elseif k == "holding" then Say("The holding room. A bench, a box of tissues, and a poster about the consequences of shoplifting.")
  elseif k == "skylight" then Say("Through the skylight: the fountain, tiny, and all the people around it like pepper on a plate.")
  elseif k == "view" then
    Say(Clock.minute(W.t) > 18 * 60 and "The parking lot lights come on one row at a time. Beyond them, the whole town, and the interstate glowing like a zipper."
      or "Parking lot, then subdivisions, then the water tower, then nothing. You can see your school from here.")
    p.conf = U.clamp(p.conf + 3, 0, 100)
  elseif k == "escalator" or k == "atrium" then Say("Don't lean on the railing.")
  elseif k == "papered" then Say("Brown paper over the glass, sun-faded. You can just read 'COMING SOON' from the inside, backwards.")
  else
    Say(Interact.label(o) .. ".")
  end
end

function Interact.sit(o)
  local p = W.p
  local foods = {}
  for _, it in ipairs(p.inv) do if it.k == "food" then foods[#foods + 1] = it end end
  Choose("SIT", { "People-watch (15 min)", "Rest (30 min)" }, function(i)
    local mins = i == 1 and 15 or 30
    WorldSim.advance(W.t + mins, 1)
    p.energy = U.clamp(p.energy + mins / 3, 0, 100)
    if i == 1 then
      -- overhear something
      local heard
      for _, n in ipairs(NPCAI.inArea(p.area)) do
        for _, rm in ipairs(W.rumors) do
          if rm.known[n.id] and not p.knownRumors[rm.id] and rm.heat > 2 then heard = { n = n, rm = rm } break end
        end
        if heard then break end
      end
      if heard then
        p.knownRumors[heard.rm.id] = true
        Say({ "You watch people for a while.", "At the next table, " .. heard.n.first .. " is saying that " .. heard.rm.txt .. "." })
      else
        Say("You watch people for a while. A man argues with a pretzel. A toddler escapes. Nobody says anything interesting.")
      end
    else
      Say("You rest your feet. The mall hums.")
    end
  end, {})
end

function Interact.payphone()
  local p = W.p
  if p.money < 25 then Say("You need a quarter.") return end
  Choose("PAY PHONE", { "Call home", "Call a friend", "Hang up" }, function(i)
    if i == 3 then return end
    p.money = p.money - 25
    if i == 1 then
      local mom = W.npcs[p.mom]
      Choose(nil, { "Can I stay out a little later?", "Can you come get me?", "Just checking in" }, function(j)
        local day = Clock.day(W.t)
        if j == 1 then
          if (p.grounded or 0) > day then Say("\"You are GROUNDED. Nine o'clock means seven o'clock.\"", { npc = mom, name = "MOM" })
          elseif U.rng(W.seed, "curfew", day):chance(0.35 + p.record * -0.1) then
            p.curfewShift = 30
            p.curfewDay = day
            Say("\"...Fine. Thirty minutes. Not one minute more.\"", { npc = mom, name = "MOM" })
          else Say("\"No. Home by curfew. I love you. Goodbye.\"", { npc = mom, name = "MOM" }) end
        elseif j == 2 then
          Say("\"I'll be there in twenty minutes. Wait by the entrance.\"", { npc = mom, name = "MOM", after = function() Day.endDay("pickup") end })
        else
          Say("\"Oh! You never call. Are you eating? Did you eat?\"", { npc = mom, name = "MOM" })
        end
      end, { prompt = "Ring... ring... \"Hello?\"", npc = mom, y = 70 })
    else
      local friends, labels = {}, {}
      for _, n in ipairs(W.npcs) do
        if n.status == "active" and n.p.met and n.p.f >= 30 and n.age < 22 then
          friends[#friends + 1] = n; labels[#labels + 1] = NPCGen.name(n)
          if #friends >= 8 then break end
        end
      end
      if #friends == 0 then Say("You realize you don't have anyone's number memorized.") return end
      Choose("CALL", labels, function(j)
        local n = friends[j]
        local busy = n.loc ~= "home" or (Stores.shiftOf(n, Clock.day(W.t)) ~= nil)
        if n.loc == p.area then Say(n.first .. " is literally standing right there.") return end
        if not busy and n.p.f >= 40 and not n.grounded then
          n.dateToday = { day = Clock.day(W.t), s = Clock.minute(W.t) + 20, e = Clock.minute(W.t) + 110, a = p.area, with = -1 }
          p.invites[#p.invites + 1] = { npc = n.id, day = Clock.day(W.t), s = Clock.minute(W.t) + 15, e = Clock.minute(W.t) + 110, a = p.area }
          NPCAI.planDay(n, Clock.day(W.t))
          Say("\"The mall? Yeah, okay. Give me twenty minutes.\"", { npc = n, name = n.first })
        else
          Say(busy and "Their mom answers. \"They're out.\"" or "\"Ugh, I can't today. Sorry.\"", { npc = n, name = n.first })
        end
      end, {})
    end
  end, {})
end

function Interact.desk(o)
  local p = W.p
  if o.office == "sec" then
    Say("Incident reports. A stack of Polaroids of banned teenagers. One of them might be you." ..
      ((p.record or 0) > 0 and " It is." or ""))
    return
  end
  if o.office == "gm" then
    local lines = { "The general manager's desk. A memo: 'Foot traffic " .. (W.mall.lastFootfall or 0) .. "/day. Appeal index " ..
      string.format("%.2f", W.mall.appeal or 1) .. ".'" }
    if W.mall.outlet then lines[#lines + 1] = "A newspaper clipping about the outlet mall, circled in red." end
    local troubled = 0
    for _, s in ipairs(W.stores) do if s.open and (s.trouble or 0) > 1 then troubled = troubled + 1 end end
    lines[#lines + 1] = "A list titled AT RISK with " .. troubled .. " store names on it."
    Say(lines)
    return
  end
  local s = W.stores[o.store]
  if not s then Say("An empty desk.") return end
  local hist = s.hist
  local last = hist[#hist] or 0
  local prev = hist[#hist - 1] or last
  local trend = last > prev * 1.05 and "up" or (last < prev * 0.95 and "down" or "flat")
  local lines = { "Manager's desk. Weekly sales: " .. U.dollars(last) .. " (" .. trend .. ")." }
  if s.cash < 0 then lines[#lines + 1] = "A letter from corporate: 'Please call us regarding your account.'" end
  if s.theft and s.theft > 0 then lines[#lines + 1] = "A shrink report: " .. s.theft .. " items missing this month." end
  if s.hiring then lines[#lines + 1] = "A stack of applications. The top one has a coffee ring on it." end
  local m = s.mgr and W.npcs[s.mgr]
  if m and m.secrets[1] then lines[#lines + 1] = "A sticky note in " .. m.first .. "'s handwriting hints that they " .. m.secrets[1].txt .. "." end
  Say(lines)
end

function Interact.mallOffice()
  local p = W.p
  local opts = { "Ask about vacancies", "Lost and found", "Sign up for Teen Night", "Never mind" }
  Choose("MALL OFFICE", opts, function(i)
    if i == 1 then
      local coming = Lore.prophecy()
      Say("\"We've got units available. " .. (coming and ("Next up: a " .. coming .. ".") or "") .. " You're not looking to lease, are you?\"")
    elseif i == 2 then
      local r = U.rng(W.seed, "lost", Clock.day(W.t))
      local found = r:pick({ "a single rollerblade", "a retainer", "a Pocket Critter (dead)", "three car keys on a Garfield keyring",
        "a cassette labeled MIX FOR JENNY", "a baby's shoe", "a hardcover SAT prep book, never opened" })
      if not p.flags.lost or p.flags.lost ~= Clock.day(W.t) then
        p.flags.lost = Clock.day(W.t)
        Econ.give({ k = "gift", n = found, v = 100 })
        Say("\"Take something. Please. Nobody ever comes back for anything.\" You get " .. found .. ".")
      else
        Say("\"One per customer.\"")
      end
    elseif i == 3 then Play.bandSignup()
    end
  end, {})
end

function Interact.dumpster()
  local p = W.p
  local day = Clock.day(W.t)
  if p.flags.dump == day then Say("Just trash now.") return end
  p.flags.dump = day
  local r = U.rng(W.seed, "dump", day)
  local finds = { { "box of unsold Pogs", 200 }, { "working Walkman (scratched)", 1500 }, { "store mannequin arm", 0 },
    { "stack of expired coupons", 0 }, { "promo poster: The Unsinkable", 300 }, { "broken lava lamp", 0 } }
  local f = r:pick(finds)
  if r:chance(0.6) then
    Econ.give({ k = "gift", n = f[1], v = f[2], from = "found" })
    Say("You dig around. You find a " .. f[1] .. ". Score?")
  else
    Say("Cardboard, cardboard, a raccoon. You back away from the raccoon.")
  end
end
