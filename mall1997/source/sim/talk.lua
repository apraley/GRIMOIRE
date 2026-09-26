-- Conversation outcomes between the player and an NPC. Pure simulation: the
-- dialog scene shows the lines this returns. Every choice nudges the five
-- player-facing feelings (friendship, trust, attraction, fear, annoyance)
-- and significant moments are written into the NPC's memory.

Talk = {}

local function P(n) return n.p end
local function clampP(n) Social.clampP(n) end
local function day() return Clock.day(W.t) end

local function r(n) return U.rng(W.seed, "talk", n.id, math.floor(W.t), n.p.talks) end

-- diminishing returns: the 6th chat today is worth a lot less than the 1st
local function fatigue(n)
  local p = P(n)
  if p.last ~= day() then p.last = day(); p.talks = 0 end
  p.talks = p.talks + 1
  if p.talks > 5 then p.an = p.an + 2 end
  return math.max(0.2, 1 - (p.talks - 1) * 0.18)
end

local function romanceWithPlayer(n) return NPCGen.romanceOK(n, { id = -1, age = W.p.age }) end
Talk.romanceOK = romanceWithPlayer

-- how much they like you before you open your mouth
function Talk.affinity(n)
  local p = W.p
  local a = MusicSim.opinion(n, p.taste) * 3
  if n.clique and p.cliqueRep and p.cliqueRep[n.clique] then a = a + p.cliqueRep[n.clique] / 20 end
  a = a + (p.conf - 50) / 25 + (p.flags.tips and 1 or 0)
  return a
end

-- ------------------------------------------------------------------ lines
local GREET = {
  friend = { "Hey {p}!", "{p}! What's up?", "Oh hey, it's you.", "Sup." },
  stranger = { "Um, hi?", "Can I help you?", "Do I know you?", "...Hey." },
  enemy = { "What do YOU want.", "Ugh. Hi.", "Oh. It's you." },
  crush = { "Oh! Hi. Hi.", "Hey... {p}.", "Oh my God, hi." },
  worker = { "Welcome to {store}!", "Let me know if you need anything.", "Hi, can I help you find something?" },
}

local function pick(rng, t) return t[rng:i(1, #t)] end

function Talk.greet(n)
  local rng = r(n)
  local p = P(n)
  local vars = { p = W.p.name, store = n.job and type(n.job) == "number" and W.stores[n.job].name or "the store" }
  local pool
  if p.f < -25 or p.an > 50 then pool = GREET.enemy
  elseif p.a > 45 and romanceWithPlayer(n) then pool = GREET.crush
  elseif p.f > 25 then pool = GREET.friend
  elseif n.act == "work" and type(n.job) == "number" then pool = GREET.worker
  else pool = GREET.stranger end
  if not p.met then p.met = true end
  return U.fmt(pick(rng, pool), vars)
end

-- something topical they might say
local function smallTalk(n, rng)
  local lines = {}
  local m = n.mem[#n.mem]
  if m and m.d >= day() - 3 then
    if m.k == "breakup" then lines[#lines + 1] = "Honestly I'm still not over the " .. (m.txt:match("with (%a+)") or "whole") .. " thing."
    elseif m.k == "dating" then lines[#lines + 1] = "So... I'm kind of " .. m.txt .. ". It's new."
    elseif m.k == "hired" then lines[#lines + 1] = "I " .. m.txt .. "! Employee discount, baby."
    elseif m.k == "lostjob" then lines[#lines + 1] = "I " .. m.txt .. ". So that's great."
    elseif m.k == "movie" then lines[#lines + 1] = "I " .. m.txt .. ". " .. CinemaSim.review(W.movies[m.s] or { quality = 50 })
    elseif m.k == "bought" then lines[#lines + 1] = "I " .. m.txt .. "! Finally."
    elseif m.k == "caught" and m.s ~= -1 then lines[#lines + 1] = "Don't ask about the thing at the store. Seriously."
    end
  end
  local w = n.wants[1]
  if w then
    if w.k == "album" then
      local a = W.music.albums[w.ref]
      if a then lines[#lines + 1] = "I'm dying to get " .. a.title .. " by " .. W.music.bands[a.band].name .. "." end
    elseif w.k == "job" then lines[#lines + 1] = "I need a job so bad. Is anywhere hiring?"
    elseif w.k == "quit" then lines[#lines + 1] = "If I have to fold one more sweater I'm going to walk into the fountain."
    elseif w.k == "movie" then lines[#lines + 1] = "I want to see something at the Cineplex this week."
    elseif w.k == "item" then lines[#lines + 1] = "I NEED a " .. w.ref .. ". Everyone has one."
    elseif w.k == "arcade" then lines[#lines + 1] = "I'm gonna get the high score on " .. ((ArcadeGames.list[w.ref] or {}).name or "that game") .. " if it kills me."
    elseif w.k == "raise" then lines[#lines + 1] = "Five fifteen an hour. Five. Fifteen."
    elseif w.k == "band" then lines[#lines + 1] = "I want to start a band. I just need people who aren't lame."
    elseif w.k == "clothes" then lines[#lines + 1] = "I keep looking at this " .. w.ref .. ". It's so me."
    end
  end
  if n.act == "work" then lines[#lines + 1] = "My manager's watching, so, you know. Look busy with me." end
  if n.role == "walker" then lines[#lines + 1] = "Twelve laps this morning. The upper level is exactly half a mile." end
  if n.job == "sec" then lines[#lines + 1] = "Quiet day. Which is how I like it." end
  if n.job == "maint" then lines[#lines + 1] = "Somebody put a whole corn dog in the fountain again." end
  local tr = W.trends[1]
  if tr and n.age < 30 then lines[#lines + 1] = "Can you believe " .. Trends.DEFS[tr.key].name .. "? Everyone's obsessed." end
  -- memories about the player
  for i = #n.mem, 1, -1 do
    local mm = n.mem[i]
    if mm.s == -1 then
      if mm.k == "gift" then lines[#lines + 1] = "I still have the " .. (mm.txt:match("gave me (.+)") or "thing you gave me") .. ". Thanks again."
      elseif mm.k == "stoodup" then lines[#lines + 1] = "You totally stood me up, you know."
      elseif mm.k == "caught" then lines[#lines + 1] = "I saw what happened at the store. Not cool."
      elseif mm.k == "insult" then lines[#lines + 1] = "I haven't forgotten what you said."
      elseif mm.k == "hungout" then lines[#lines + 1] = "That was fun the other day."
      elseif mm.k == "borrowed" then lines[#lines + 1] = "When am I getting my " .. (mm.txt:match("lent .- (.+)") or "stuff") .. " back?"
      end
      break
    end
  end
  if #lines == 0 then lines[1] = pick(rng, { "Not much going on.", "The mall is so dead today.", "Did you see the new store?",
    "I've been here since noon. I have no life.", "Nothing. Just, like, existing." }) end
  return pick(rng, lines)
end

-- ------------------------------------------------------------------ options
function Talk.options(n)
  local p = P(n)
  local opts = { { id = "chat", label = "Chat" }, { id = "gossip", label = "Ask for gossip" },
    { id = "music", label = "Talk music" }, { id = "joke", label = "Tell a joke" }, { id = "compliment", label = "Compliment" },
    { id = "about", label = "Ask about them" }, { id = "mall", label = "Ask about the mall" } }
  if n.act ~= "work" and W.p.companion ~= n.id then opts[#opts + 1] = { id = "invite", label = "Hang out?" } end
  if romanceWithPlayer(n) and W.p.partner ~= n.id and p.f > 10 then opts[#opts + 1] = { id = "askout", label = "Ask out" } end
  if W.p.partner == n.id then opts[#opts + 1] = { id = "breakup", label = "Break up" } end
  opts[#opts + 1] = { id = "give", label = "Give something" }
  if #n.poss > 0 and p.f >= 20 then opts[#opts + 1] = { id = "borrow", label = "Borrow something" } end
  opts[#opts + 1] = { id = "tell", label = "Tell a rumor" }
  local s = type(n.job) == "number" and W.stores[n.job]
  if s and n.title == "manager" then
    if W.p.job and W.p.job.store == s.id then
      opts[#opts + 1] = { id = "hours", label = W.p.job.moreHours and "Fewer hours, please" or "More hours, please" }
      opts[#opts + 1] = { id = "quit", label = "Quit this job" }
    else
      opts[#opts + 1] = { id = "job", label = "Ask for a job" }
    end
  end
  if n.job == "sec" and n.title == "chief" and not W.p.job then opts[#opts + 1] = { id = "secjob", label = "Ask about security work" } end
  if n.wantsBorrow then opts[#opts + 1] = { id = "lend", label = "Lend " .. n.wantsBorrow } end
  if (n.rival or (n.ask and n.age < 25)) and n.act ~= "work" and n.loc == "s" .. W.mall.arcade then
    opts[#opts + 1] = { id = "challenge", label = "Challenge (10 tokens)" }
  end
  opts[#opts + 1] = { id = "insult", label = "Insult" }
  opts[#opts + 1] = { id = "bye", label = "Bye" }
  return opts
end

-- ------------------------------------------------------------------ actions
-- returns { lines = {...}, mood = "happy"|..., kind = "..." }
function Talk.act(n, id, arg)
  local p = P(n)
  local rng = r(n)
  local k = fatigue(n)
  local aff = Talk.affinity(n)
  local out = { lines = {} }
  local function say(s) out.lines[#out.lines + 1] = s end
  W.p.stats.talks = W.p.stats.talks + 1
  if id == "chat" then
    say(smallTalk(n, rng))
    p.f = p.f + (2 + aff * 0.5) * k; p.t = p.t + 1 * k
    W.p.conf = U.clamp(W.p.conf + 0.5, 0, 100)
  elseif id == "gossip" then
    if p.f < 0 and n.tr.gossip < 0.7 then say("Why would I tell YOU anything?"); p.an = p.an + 2
    else
      local best, bh
      for _, rm in ipairs(W.rumors) do
        if rm.known[n.id] and not W.p.knownRumors[rm.id] then
          local h = rm.heat + (rm.lore and 1.5 or 0) + (rm.about == -1 and 3 or 0)
          if not bh or h > bh then best, bh = rm, h end
        end
      end
      if best then
        W.p.knownRumors[best.id] = true
        if best.about == -1 then say("Okay so. People are saying " .. best.txt:gsub(W.p.name, "you") .. ". Just so you know.")
        elseif best.lore then say("This is going to sound dumb, but... " .. best.txt .. ".")
        else say(pick(rng, { "Did you hear? ", "Okay, don't tell anyone, but ", "So apparently " }) .. best.txt .. ".") end
        p.f = p.f + 1 * k
        out.rumor = best
      else
        say(pick(rng, { "I don't know anything you don't.", "Nothing. It's been so boring.", "My lips are sealed. Also I don't know anything." }))
      end
    end
  elseif id == "music" then
    local fav
    for _, a in ipairs(W.music.albums) do
      if W.music.bands[a.band].genre == n.taste and (not fav or a.pop > fav.pop) and (not a.releaseDay or a.released) then fav = a end
    end
    if fav then say("I've been playing " .. fav.title .. " by " .. W.music.bands[fav.band].name .. " nonstop.") end
    local op = MusicSim.opinion(n, W.p.taste)
    if not W.p.taste then say("What are you into? You don't even own any tapes, huh.")
    elseif op >= 1 then say("Wait, you like " .. W.p.taste .. " too? Okay. You're cool."); p.f = p.f + 5 * k; p.a = p.a + (romanceWithPlayer(n) and 2 or 0)
    elseif op > 0 then say(W.p.taste .. "? That's alright, I guess."); p.f = p.f + 2 * k
    elseif op < -0.5 then say("You listen to " .. W.p.taste .. "? Seriously? Gross."); p.f = p.f - 3; p.an = p.an + 3
    else say("I don't really get " .. W.p.taste .. ", but okay."); p.f = p.f + 0.5 end
  elseif id == "joke" then
    local ok = rng:chance(0.35 + W.p.conf / 250 + n.tr.social * 0.2 + aff * 0.03)
    if ok then
      say(pick(rng, { "HA! Okay, that was actually funny.", "*snort* Stop.", "Oh my God. You're so weird. I love it." }))
      p.f = p.f + 4 * k; W.p.conf = U.clamp(W.p.conf + 2, 0, 100)
      out.mood = "happy"
    else
      say(pick(rng, { "...", "I don't get it.", "Was that a joke?", "*polite smile*" }))
      p.an = p.an + 2; W.p.conf = U.clamp(W.p.conf - 2, 0, 100)
    end
  elseif id == "compliment" then
    if p.an > 35 then say("Whatever."); p.an = p.an + 2
    elseif romanceWithPlayer(n) then
      say(pick(rng, { "Oh! Um. Thanks.", "Stop it. ...No, keep going.", "You think so?" }))
      p.a = p.a + 3 * k + aff * 0.3; p.f = p.f + 1
      out.mood = "shy"
    else
      say(pick(rng, { "Aw, thanks!", "Well aren't you sweet.", "Thanks, kid." }))
      p.f = p.f + 2 * k
    end
  elseif id == "about" then
    local job = n.job and (type(n.job) == "number" and ("I work at " .. W.stores[n.job].name ..
      (n.title == "manager" and " — I'm the manager, God help me." or "."))) or
      (n.job == "sec" and "Mall security. Somebody's gotta do it.") or (n.job == "maint" and "I keep this place from falling apart.")
      or (n.job == "mgmt" and ("I'm the " .. (n.title or "manager") .. " for the whole mall.")) or
      (n.age < 19 and ("I go to " .. (n.school or "school") .. ".") or "Between jobs, you could say.")
    say(job .. " I live over in " .. n.home .. ".")
    if n.band and W.music.bands[n.band] then say("I'm in a band. " .. W.music.bands[n.band].name .. ". We play Teen Night sometimes.") end
    -- secrets need trust
    local sec
    for _, s in ipairs(n.secrets) do if not s.known then sec = s break end end
    if sec and p.t >= 45 and p.f >= 35 and rng:chance(0.5) then
      sec.known = true
      W.p.secrets = W.p.secrets or {}
      W.p.secrets[#W.p.secrets + 1] = { npc = n.id, txt = sec.txt, lore = sec.lore }
      say("...Can I tell you something? Don't spread it around. I " .. sec.txt:gsub("^is ", "am "):gsub("^has ", "have ") .. ".")
      Memory.add(n, "confided", "told " .. W.p.name .. " a secret", -1)
      p.t = p.t + 3
      out.secret = sec
      if sec.lore == "model" then W.p.keys.combo_hint = true end
    end
    p.f = p.f + 1 * k
  elseif id == "mall" then
    Talk.mallLore(n, rng, say, p)
  elseif id == "invite" then
    if n.act == "work" then say("I'm working. Maybe after?")
    elseif (p.f >= 25 or p.a >= 35) and n.mood > 25 and p.an < 40 then
      say(pick(rng, { "Sure, I've got time.", "Yeah, okay! Where to?", "I was literally about to leave, but okay." }))
      W.p.companion = n.id
      W.p.companionUntil = W.t + 60 + rng:i(0, 60)
      n.held = true
      n.route = nil
      out.mood = "happy"
      out.companion = true
    else
      say(pick(rng, { "I'm kind of busy.", "Maybe some other time.", "Ha. No." }))
      W.p.conf = U.clamp(W.p.conf - 3, 0, 100)
    end
  elseif id == "askout" then
    if n.partner then say("I'm going out with " .. (W.npcs[n.partner] and W.npcs[n.partner].first or "someone") .. ". Sorry.")
      p.a = p.a - 5; W.p.conf = U.clamp(W.p.conf - 5, 0, 100)
    elseif p.a >= 50 and p.f >= 25 then
      say(pick(rng, { "YES. I mean. Yeah. Cool.", "I thought you'd never ask.", "Okay. Yeah. Okay!" }))
      Talk.startDating(n)
      out.mood = "shy"
    else
      say(pick(rng, { "Oh. Um. I like you as a friend?", "That's... sweet. But no.", "Wait, are you serious?" }))
      p.a = p.a - 3; W.p.conf = U.clamp(W.p.conf - 8, 0, 100)
      out.mood = "sad"
    end
  elseif id == "breakup" then
    Talk.breakupPlayer(n, "you ended it")
    say(pick(rng, { "Wow. Okay. At the MALL?", "Fine. Whatever.", "...I'm going to go now." }))
    out.mood = "sad"
  elseif id == "insult" then
    say(pick(rng, { "Excuse me?!", "Wow. Okay.", "Say that again, I dare you." }))
    p.f = p.f - 10; p.an = p.an + 15; p.a = p.a - 5
    if W.p.rep > 60 then p.fe = p.fe + 5 end
    Memory.add(n, "insult", W.p.name .. " insulted me", -1)
    out.mood = "angry"
  elseif id == "bye" then
    say(pick(rng, { "Later.", "See ya.", "Bye!", "Okay, bye." }))
  end
  clampP(n)
  return out
end

function Talk.startDating(n)
  local p = W.p
  if p.partner and W.npcs[p.partner] then Talk.breakupPlayer(W.npcs[p.partner], "for someone else") end
  p.partner = n.id
  n.partner = -1
  n.crush = nil
  n.p.a = math.max(n.p.a, 60)
  p.stats.dates = p.stats.dates + 1
  p.conf = U.clamp(p.conf + 15, 0, 100)
  Timeline.add("player", n.first .. " " .. n.last .. " and " .. p.name .. " are going out.", 3)
  Rumors.add("dating", -1, p.name .. " is going out with " .. n.first .. " " .. n.last, 7, { n.id })
  Memory.add(n, "dating", "started going out with " .. p.name, -1)
end

function Talk.breakupPlayer(n, why)
  local p = W.p
  p.partner = nil
  n.partner = nil
  n.p.a = 10; n.p.f = n.p.f - 20; n.p.an = n.p.an + 20
  n.mood = U.clamp(n.mood - 25, 0, 100)
  p.conf = U.clamp(p.conf - 5, 0, 100)
  Timeline.add("player", p.name .. " and " .. n.first .. " broke up (" .. why .. ").", 3)
  Rumors.add("breakup", n.id, n.first .. " and " .. p.name .. " broke up", 7, { n.id })
  Memory.add(n, "breakup", "broke up with " .. p.name, -1)
  Social.clampP(n)
end

-- lore flows through people who've been here a long time
function Talk.mallLore(n, rng, say, p)
  local pl = W.p
  if n.id == W.mall.janitor then
    if p.t >= 55 and p.f >= 40 then
      say("You're a curious one. Most kids just throw pennies in the fountain.")
      if not pl.keys.tunnel then
        say("I leave a key where the view is best. Up top. Don't make me regret it.")
        pl.flags.janitorHint = true
      else
        local parts = W.mall.comboParts
        say("The old man who built this place wanted a record kept. The numbers are all around you, if you look. " ..
          "The fountain. The pipe. His desk. And I'll give you one: " .. parts.d3 .. ".")
        pl.keys.combo_hint = true
      end
      p.t = p.t + 2
    else
      say("I clean. I don't talk much.")
      p.f = p.f + 1
    end
    return
  end
  if n.job == "maint" then
    if p.f >= 40 and not pl.keys.roof then
      say("Roof's the best view in town. Here — spare key to the ladder hatch. You didn't get it from me.")
      pl.keys.roof = true
      Econ.give({ k = "key", n = "roof hatch key", v = 0 })
      Timeline.add("lore", pl.name .. " got a key to the roof from " .. n.first .. ".", 2)
      return
    end
    say("I could tell you stories about this place. The escalators alone.")
    p.f = p.f + 1
    return
  end
  -- elders pass on myths
  local myth
  for _, rm in ipairs(W.rumors) do
    if rm.lore and rm.known[n.id] and not pl.knownRumors[rm.id] then myth = rm break end
  end
  if myth then
    pl.knownRumors[myth.id] = true
    say((n.age > 60 and "Oh, when I was younger, people said " or "People say ") .. myth.txt .. ".")
  else
    local facts = { "This place opened in " .. W.mall.opened .. ". There was a marching band.",
      "Footfall's " .. (W.mall.lastFootfall or 0) .. " a day, if you believe the office.",
      "They say the outlet mall's going to kill us all eventually.",
      "The food court used to be a skating rink. Swear to God." }
    say(pick(rng, facts))
  end
  p.f = p.f + 1
end

-- give an inventory item to an NPC
function Talk.give(n, it)
  local p = P(n)
  local pl = W.p
  local out = { lines = {} }
  U.removeValue(pl.inv, it)
  if it.borrowed == n.id then
    out.lines[1] = "My " .. it.n .. "! Thanks for bringing it back."
    p.t = p.t + 8; p.f = p.f + 2
    return out
  end
  it.borrowed = nil
  n.poss[#n.poss + 1] = { k = it.k, n = it.n, v = it.v, ref = it.ref }
  U.trim(n.poss, 12)
  local wanted
  for i, w in ipairs(n.wants) do
    if (w.k == "album" and it.k == "album" and it.ref == w.ref) or ((w.k == "item" or w.k == "clothes") and it.n:find(w.ref, 1, true)) then
      wanted = i
    end
  end
  if wanted then
    table.remove(n.wants, wanted)
    out.lines[1] = "NO WAY. I've wanted this forever! You're the best."
    p.f = p.f + 15; p.t = p.t + 6
    if romanceWithPlayer(n) then p.a = p.a + 6 end
    n.mood = U.clamp(n.mood + 15, 0, 100)
    out.mood = "happy"
  else
    local v = (it.v or 0)
    out.lines[1] = v > 1500 and "Whoa, for me? That's a lot." or "Oh, cool. Thanks."
    p.f = p.f + math.min(8, 1 + v / 400)
    if romanceWithPlayer(n) then p.a = p.a + 2 end
    if it.from == "stolen" and n.tr.honest > 0.7 and U.hash(n.id, it.n) % 3 == 0 then
      out.lines[2] = "...Wait, is this the one from the store? Did you pay for this?"
      p.t = p.t - 8
    end
  end
  p.giftDay = Clock.day(W.t)
  Memory.add(n, "gift", pl.name .. " gave me " .. it.n, -1)
  Social.clampP(n)
  return out
end

-- borrow one of their things
function Talk.borrow(n, idx)
  local p = P(n)
  local it = n.poss[idx]
  if not it then return { lines = { "I don't have that anymore." } } end
  if p.f < 35 or p.t < 10 then
    p.an = p.an + 2
    return { lines = { "Uh, no. I don't lend my stuff out." } }
  end
  table.remove(n.poss, idx)
  local copy = U.copy(it)
  copy.borrowed = n.id
  copy.due = Clock.day(W.t) + 5
  Econ.give(copy)
  Memory.add(n, "borrowed", "lent " .. W.p.name .. " " .. it.n, -1)
  return { lines = { "Sure. But I want it back by next week. I mean it." } }
end

function Talk.lend(n)
  local pl = W.p
  local want = n.wantsBorrow
  n.wantsBorrow = nil
  for _, it in ipairs(pl.inv) do
    if it.n == want then
      U.removeValue(pl.inv, it)
      n.poss[#n.poss + 1] = { k = it.k, n = it.n, v = it.v, ref = it.ref, fromPlayer = true }
      n.p.f = n.p.f + 6; n.p.t = n.p.t + 4
      n.owes = { n = it.n, due = Clock.day(W.t) + 4 }
      Memory.add(n, "lent", "borrowed " .. it.n .. " from " .. pl.name, -1)
      Social.clampP(n)
      return { lines = { "You're a lifesaver. I'll give it back, promise." } }
    end
  end
  return { lines = { "Oh, you don't have it anymore? No worries." } }
end

-- pass a rumor (or secret) on
function Talk.tell(n, entry)
  local p = P(n)
  local out = { lines = {} }
  if entry.rumor then
    local rm = entry.rumor
    if rm.known[n.id] then out.lines[1] = "Yeah, I heard. Old news."; return out end
    Rumors.learn(rm, n)
    rm.heat = math.min(10, rm.heat + 1)
    out.lines[1] = "No WAY. Seriously?"
    p.f = p.f + 1
    local subj = rm.about and rm.about > 0 and W.npcs[rm.about]
    if subj and n.rel[subj.id] and n.rel[subj.id].f > 40 then
      out.lines[2] = "That's my friend you're talking about, though."
      p.t = p.t - 4
    end
  elseif entry.secret then
    local sec = entry.secret
    local subj = W.npcs[sec.npc]
    local rm = Rumors.add("secret", subj.id, subj.first .. " " .. sec.txt, 8, { n.id })
    rm.source = -1
    out.lines[1] = "Shut UP. " .. subj.first .. "? For real?"
    p.f = p.f + 2
    Timeline.add("people", "A secret about " .. NPCGen.name(subj) .. " is going around the mall.", 2)
    -- the subject may figure out who blabbed
    if U.hash(subj.id, W.t) % 3 == 0 then
      subj.p.t = subj.p.t - 30; subj.p.f = subj.p.f - 20; subj.p.an = subj.p.an + 25
      Memory.add(subj, "betrayed", W.p.name .. " told everyone my secret", -1)
      Rumors.add("blabbed", -1, W.p.name .. " can't keep a secret", 5, { subj.id })
      Social.clampP(subj)
    end
  end
  Social.clampP(n)
  return out
end

-- one-liners for speech bubbles in the concourse
function Talk.ambient(n)
  local p = P(n)
  local rng = U.rng(n.id, math.floor(W.t))
  if W.p.partner == n.id then return pick(rng, { "Hi you.", "There you are!", ":)" }) end
  if p.an > 45 then return pick(rng, { "Ugh.", "*glare*", "Oh great." }) end
  if p.f > 50 then return pick(rng, { "Hey " .. W.p.name .. "!", "Yo!", "Sup!" }) end
  for _, rm in ipairs(W.rumors) do
    if rm.about == -1 and rm.known[n.id] and rm.heat > 4 then
      if rm.kind == "record" then return "Arcade legend!" end
      if rm.kind == "caught" or rm.kind == "shoplift" or rm.kind == "banned" then return "Klepto..." end
      if rm.kind == "mom" then return "Did your mom find you? lol" end
      if rm.kind == "dating" then return "Ooooh, lovebirds." end
      if rm.kind == "gig" then return "Your band rules!" end
    end
  end
  if n.rival then
    local g = ArcadeGames.list[type(n.rival) == "string" and n.rival or "serpent"]
    return pick(rng, { "Nice score. For a baby.", "Still my record, " .. W.p.name .. ".", (g and g.name or "It") .. " is MINE." })
  end
  if n.job == "sec" then return "Keep it moving." end
  return pick(rng, { "Hey.", "Oh, hi.", "*nod*" })
end
