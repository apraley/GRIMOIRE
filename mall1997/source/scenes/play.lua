-- Hosts for timed play: job shifts (minigames), arcade cabinets with
-- initials entry, the prize wheel, movies, and Teen Night gigs.

Play = {}

-- ------------------------------------------------------------------ host
-- Runs a Minigames / ArcadeGames def full-screen, with intro and result.
local host = {}

local function runGame(def, ctx, onDone, intro)
  local sc = setmetatable({ def = def, ctx = ctx, onDone = onDone, intro = intro, phase = intro and "intro" or "play", t = 0 },
    { __index = host })
  Scene.push(sc)
  return sc
end

function host:update()
  self.t = self.t + 1
  if self.phase == "intro" then
    if In.a then self.phase = "play"; self.st = self.def.new(self.ctx); Input.clear() end
    if In.b and self.intro.cancel then Scene.pop(); self.intro.cancel() end
    return
  end
  if not self.st then self.st = self.def.new(self.ctx) end
  self.def.update(self.st)
  if self.def.done(self.st) then
    Scene.pop()
    self.onDone(self.st)
  end
end

function host:draw()
  if self.phase == "intro" then
    Gfx.clear("black")
    Gfx.box(20, 16, 360, 208, "dark")
    Gfx.text(self.intro.title, 200, 30, { white = true, bold = true, align = "center" })
    local y = 60
    for _, l in ipairs(self.intro.lines or {}) do
      y = y + Gfx.para(l, 40, y, 320, { white = true })
    end
    if (Gfx.frame // 15) % 2 == 0 then Gfx.text("A: START", 200, 196, { white = true, align = "center", bold = true }) end
    return
  end
  if self.st then self.def.draw(self.st) end
end

-- ------------------------------------------------------------------ shifts
function Play.clockIn()
  local sh, why = Jobs.canClockIn()
  if not sh then Say(why) return end
  local key = Jobs.kindFor(W.p.job.store)
  local def = Minigames.list[key] or Minigames.list.department
  local ctx = Jobs.context(sh)
  local lines = {}
  for _, h in ipairs(def.help or {}) do lines[#lines + 1] = h end
  table.insert(lines, 1, Jobs.title():upper() .. " at " .. Jobs.placeName() .. ". Shift " .. Clock.hhmm(sh.s) .. "-" .. Clock.hhmm(sh.e) .. ".")
  if sh.late then table.insert(lines, 2, "You're late.") end
  runGame(def, ctx, function(st)
    local res = def.result(st)
    -- the rest of the shift passes
    local endT = Clock.day(W.t) * 1440 + sh.e
    W.p.atMall = true
    Day.skipTo(endT, "Working...", function()
      local txt = Jobs.finish(sh, res)
      Say(txt)
    end)
  end, { title = def.title or "SHIFT", lines = lines, cancel = function() end })
end

-- ------------------------------------------------------------------ arcade
function Play.cabinet(o)
  local p = W.p
  local m = W.arcade.machines[o.machine]
  if not m then return end
  if m.broken then
    if p.job and p.job.store == W.mall.arcade then
      Confirm("OUT OF ORDER. Fix it?", function()
        m.broken = false; m.wear = 0
        p.job.perf = U.clamp(p.job.perf + 2, 0, 100)
        WorldSim.advance(W.t + 10, 2)
        Say("You jiggle the coin mech and reseat a cable. It lives.")
      end)
    else
      Say("OUT OF ORDER. Someone drew a sad face on the tape.")
    end
    return
  end
  if m.flavor then
    Choose(m.flavor, { "Play (1 token)", "Watch someone play" }, function(i)
      if i == 1 then
        if p.tokens < 1 then Say("No tokens. The token machine is by the counter.") return end
        p.tokens = p.tokens - 1
        m.plays = m.plays + 1
        local r = U.rng(W.seed, m.flavor, W.t)
        Say(r:pick({ "You play for two minutes. You lose. It was great.", "The claw grabs a plush bear... and drops it. Of course.",
          "You win 12 tickets!", "A small crowd gathers. You do not live up to their expectations." }))
        p.tickets = (p.tickets or 0) + r:i(0, 12)
        WorldSim.advance(W.t + 3, 1)
      else
        Say("You watch a kid in a Starter jacket play like his life depends on it.")
      end
    end, {})
    return
  end
  local def = ArcadeGames.list[m.game]
  Choose(def.name, { "Play (1 token)", "High scores" }, function(i)
    if i == 2 then Play.scores(m.game) return end
    if p.tokens < 1 then Say("No tokens. The token machine is by the counter.") return end
    p.tokens = p.tokens - 1
    m.plays = m.plays + 1
    m.wear = m.wear + 1
    local ctx = { rng = U.rng(W.seed, "cab", W.t, m.plays), credits = 1 }
    runGame(def, ctx, function(st)
      local score = def.score(st)
      WorldSim.advance(W.t + 4, 1)
      p.stats.arcade[m.game] = math.max(p.stats.arcade[m.game] or 0, score)
      p.tickets = (p.tickets or 0) + math.floor(score / 200)
      local board = ArcadeSim.board(m.game)
      local qualifies = #board < 10 or score > board[#board].s
      if qualifies and score > 0 then
        Play.initials(function()
          local rank = ArcadeSim.submit(m.game, -1, score)
          Say(rank == 1 and ("NEW RECORD! " .. score .. ". The whole arcade saw that.") or ("You placed #" .. rank .. " with " .. score .. "."))
        end)
      else
        Say("GAME OVER. " .. score .. " points." .. (board[1] and ("  Record: " .. board[1].i .. " " .. board[1].s) or ""))
      end
    end)
  end, {})
end

function Play.scores(game)
  local b = ArcadeSim.board(game)
  local lines = {}
  for i, e in ipairs(b) do lines[#lines + 1] = string.format("%2d. %s  %d", i, e.i, e.s) end
  if #lines == 0 then lines[1] = "No scores yet." end
  Choose(ArcadeGames.list[game].name .. " HIGH SCORES", lines, function() end, { visible = 10, x = 90, w = 220, y = 26 })
end

-- crank through letters for your initials
function Play.initials(cb)
  local p = W.p
  local init = p.initials or (p.name:sub(1, 3):upper() .. "AAA"):sub(1, 3)
  local sc = { letters = { init:byte(1), init:byte(2), init:byte(3) }, pos = 1, crank = Input.crankStepper(20) }
  function sc:update()
    local st = self.crank(In.crank)
    if In.ur then st = st + 1 end
    if In.dr then st = st - 1 end
    if st ~= 0 then
      local c = self.letters[self.pos] - 65 + st
      self.letters[self.pos] = 65 + (c % 26)
      Sfx.tick()
    end
    if In.left then self.pos = math.max(1, self.pos - 1) end
    if In.right then self.pos = math.min(3, self.pos + 1) end
    if In.a then
      if self.pos < 3 then self.pos = self.pos + 1
      else
        p.initials = string.char(self.letters[1], self.letters[2], self.letters[3])
        Scene.pop()
        cb()
      end
    end
  end
  function sc:draw()
    Gfx.clear("black")
    Gfx.text("ENTER YOUR INITIALS", 200, 40, { white = true, bold = true, align = "center" })
    for i = 1, 3 do
      local x = 140 + (i - 1) * 50
      if i == self.pos and (Gfx.frame // 8) % 2 == 0 then Gfx.fill(x - 4, 146, 40, 4, "white") end
      Gfx.box(x - 6, 90, 44, 52, "dark")
      Gfx.text(string.char(self.letters[i]), x + 16, 106, { white = true, bold = true, align = "center" })
    end
    Gfx.text("CRANK / UP DOWN: letter   A: next", 200, 190, { white = true, align = "center" })
  end
  Scene.push(sc)
end

function Play.tokenMachine()
  local p = W.p
  Choose("TOKENS", { "$1 = 4 tokens", "$5 = 22 tokens", "$10 = 50 tokens" }, function(i)
    local cost = ({ 100, 500, 1000 })[i]
    local n = ({ 4, 22, 50 })[i]
    if p.money < cost then Say("The machine spits your bill back out. So do you, emotionally.") return end
    p.money = p.money - cost
    p.tokens = p.tokens + n
    local s = W.stores[W.mall.arcade]
    s.npcSales = (s.npcSales or 0) + cost
    Say("Clink clink clink. " .. n .. " tokens. You have " .. p.tokens .. ".")
  end, {})
end

-- the prize wheel: spin with the crank
function Play.prizeWheel()
  local p = W.p
  if p.tokens < 5 then Say("The prize wheel costs 5 tokens a spin. You have " .. p.tokens .. ".") return end
  p.tokens = p.tokens - 5
  local prizes = { "slap bracelet", "plastic spider ring", "TRY AGAIN", "giant pencil", "25 tickets", "TRY AGAIN",
    "rubber snake", "glow stick", "TRY AGAIN", "Plush Pal (knockoff)", "50 tokens!!", "Chinese finger trap" }
  local sc = { angle = 0, vel = 0, spun = false, done = 0 }
  function sc:update()
    if not self.spun then
      self.vel = self.vel + math.abs(In.crank) * 0.05
      if In.a then self.vel = self.vel + 12 end
      if self.vel > 6 then self.spun = true end
    else
      self.vel = self.vel * 0.985
      if self.vel < 0.15 and self.done == 0 then
        self.done = 1
        local idx = math.floor(((360 - self.angle % 360) % 360) / 30) + 1
        local prize = prizes[idx]
        Scene.pop()
        if prize == "TRY AGAIN" then Say("TRY AGAIN. The wheel mocks you.")
        elseif prize == "50 tokens!!" then p.tokens = p.tokens + 50; Say("50 TOKENS! The wheel bell rings. Kids cheer.")
        elseif prize == "25 tickets" then p.tickets = (p.tickets or 0) + 25; Say("25 tickets.")
        else Econ.give({ k = "gift", n = prize, v = 150, from = "won" }); Say("You win: " .. prize .. "!") end
        return
      end
    end
    self.angle = self.angle + self.vel
  end
  function sc:draw()
    local gfx = playdate.graphics
    Gfx.clear("black")
    local cx, cy, r = 200, 125, 95
    Gfx.circle(cx, cy, r + 4, true, "white")
    for i = 0, 11 do
      local a0 = math.rad(self.angle + i * 30)
      local a1 = math.rad(self.angle + (i + 1) * 30)
      local pat = (i % 2 == 0) and Gfx.P.gray or Gfx.P.white
      gfx.setPattern(pat)
      gfx.fillPolygon(cx, cy, cx + math.cos(a0) * r, cy + math.sin(a0) * r, cx + math.cos(a1) * r, cy + math.sin(a1) * r)
      gfx.setColor(gfx.kColorBlack)
      gfx.drawLine(cx, cy, cx + math.cos(a0) * r, cy + math.sin(a0) * r)
    end
    Gfx.circle(cx, cy, 10, true, "black")
    gfx.setColor(gfx.kColorWhite)
    gfx.fillTriangle(cx - 8, 18, cx + 8, 18, cx, 34)
    gfx.setColor(gfx.kColorBlack)
    if not self.spun then Gfx.text("CRANK TO SPIN!", 200, 222, { white = true, align = "center", bold = true }) end
    Gfx.neon(0, 0, 400, 6, 3); Gfx.neon(0, 234, 400, 6, 5)
  end
  Scene.push(sc)
end

-- ------------------------------------------------------------------ movies
local SCENES = {
  action = { "An explosion. Another explosion. A man walks away from the explosions without looking.", "A helicopter does something helicopters can't do." },
  comedy = { "Somebody falls into a pool. The theater howls.", "A misunderstanding escalates for 40 minutes." },
  horror = { "The phone rings. Nobody in the theater breathes.", "Someone behind you screams louder than anyone on screen." },
  romance = { "Rain. A kiss. A swell of strings.", "Two people almost say what they mean, twice." },
  ["sci-fi"] = { "A spaceship the size of the mall blots out the sun.", "Someone says 'the fabric of space-time' with a straight face." },
  drama = { "A long speech in a courtroom. A man in front of you cries into his popcorn.", "Wide shots of wheat." },
  family = { "A dog does a thing. Everyone claps. You clap too, a little.", "A song you'll hear in your head for a week." },
  thriller = { "A briefcase. A double-cross. A triple-cross.", "The twist! You totally called it. (You did not call it.)" },
  teen = { "A makeover montage set to a song you own.", "Prom goes terribly wrong in a very specific way." },
  indie = { "Two guys talk in a convenience store for a long time.", "A black-and-white dream sequence. You get it. Mostly." },
}

function Play.watch(movieId, screen)
  local p = W.p
  local mv = W.movies[movieId]
  local comp = p.companion and W.npcs[p.companion]
  local r = U.rng(W.seed, "movie", movieId, W.t)
  local beats = SCENES[mv.genre] or SCENES.drama
  local sc = { t = 0, beat = 0, lines = { mv.title:upper(), r:pick(beats), beats[1] == beats[2] and "" or beats[(r:i(1, 2))],
    CinemaSim.review(mv) } }
  function sc:update()
    self.t = self.t + 1
    if In.a or self.t > 90 then
      self.t = 0
      self.beat = self.beat + 1
      if self.beat >= #self.lines then
        Scene.pop()
        local endT = W.t + mv.mins + 5
        Day.skipTo(endT, "Watching " .. mv.title .. "...", function()
          mv.seen = mv.seen + 1
          p.stats.movies[movieId] = true
          p.energy = U.clamp(p.energy - 5, 0, 100)
          local lines = { "You saw " .. mv.title .. ". " .. CinemaSim.review(mv) }
          if comp then
            comp.p.f = U.clamp(comp.p.f + 8, -100, 100)
            if Talk.romanceOK(comp) and comp.p.a > 20 then comp.p.a = U.clamp(comp.p.a + 10, 0, 100) end
            Memory.add(comp, "movie", "saw " .. mv.title .. " with " .. p.name, movieId)
            lines[#lines + 1] = comp.first .. " " .. (comp.p.a > 50 and "held your hand during the scary part." or "keeps quoting it on the way out.")
            if comp.p.a > 50 and Talk.romanceOK(comp) then
              Timeline.add("player", p.name .. " and " .. comp.first .. " went to see " .. mv.title .. " together.", 2)
            end
          end
          local seen = U.count(p.stats.movies)
          lines[#lines + 1] = "Movies seen: " .. seen .. "."
          Say(lines)
        end)
      end
    end
  end
  function sc:draw()
    local gfx = playdate.graphics
    Gfx.clear("black")
    -- the screen, glowing
    Gfx.fill(40, 20, 320, 140, "white")
    local k = (self.beat * 7 + Gfx.frame // 20) % 4
    Gfx.fill(50, 30, 300, 120, ({ "gray", "diag", "light", "dots" })[k + 1])
    Gfx.text(self.lines[self.beat + 1] or "", 200, 80, { align = "center", bold = self.beat == 0 })
    -- heads in the seats
    for i = 0, 9 do
      gfx.setColor(gfx.kColorBlack)
      gfx.fillCircleAtPoint(30 + i * 38, 200, 16)
    end
    Gfx.fill(0, 214, 400, 26, "black")
    if self.beat > 0 and self.lines[self.beat + 1] then
      Gfx.para(self.lines[self.beat + 1], 20, 166, 360, { white = true })
    end
  end
  Scene.push(sc)
end

function Play.screenDoor(o)
  local p = W.p
  local m = Clock.minute(W.t)
  local day = Clock.day(W.t)
  for _, it in ipairs(p.inv) do
    if it.k == "ticket" and it.screen == o.screen and it.day == day and m >= it.show - 20 and m <= it.show + 25 then
      U.removeValue(p.inv, it)
      Econ.give({ k = "stub", n = "ticket stub: " .. W.movies[it.movie].title, v = 0 })
      Play.watch(it.movie, o.screen)
      return
    end
  end
  -- theater hopping
  local shows = CinemaSim.shows(day)
  local cur
  for _, sh in ipairs(shows) do if sh.screen == o.screen and m >= sh.t - 5 and m <= sh.t + 30 then cur = sh end end
  if not cur then Say("Theater " .. o.screen .. ". Nothing starting right now.") return end
  local mv = W.movies[cur.movie]
  Confirm("No ticket for this one (" .. mv.title .. "). Sneak in?", function()
    local s = W.stores[W.mall.cinema]
    local staff = Stores.presentStaff(s)
    local r = U.rng(W.seed, "sneak", W.t)
    if #staff > 0 and r:chance(0.25 + 0.1 * #staff) then
      local n = staff[1]
      p.bans[tostring(s.id)] = day + 7
      Rumors.add("banned", -1, p.name .. " got kicked out of the Cineplex for sneaking in", 4, { n.id })
      Say("\"Ticket? No? Out. And don't come back this week.\"", { npc = n, name = n.first, mood = "angry",
        after = function() Explore.go("fc", 50 * 16, 8 * 16 + 12, true) end })
    else
      Play.watch(cur.movie, o.screen)
    end
  end)
end

-- ------------------------------------------------------------------ band
function Play.bandSignup()
  local p = W.p
  if not p.band then
    local friends = {}
    for _, id in ipairs(p.friends) do
      local n = W.npcs[id]
      if n and n.status == "active" and n.p.f >= 35 then friends[#friends + 1] = n end
    end
    for _, n in ipairs(W.npcs) do
      if #friends >= 3 then break end
      if n.status == "active" and n.p.f >= 50 and n.age < 21 and not U.contains(friends, n) then friends[#friends + 1] = n end
    end
    if #friends < 2 then Say("\"You need a band to sign up for Teen Night, hon. At least three people.\" (Make better friends.)") return end
    local r = U.rng(W.seed, "pband", Clock.day(W.t))
    local name = "The " .. r:pick(Names.bandA) .. " " .. r:pick(Names.bandB)
    Confirm("Start a band with " .. friends[1].first .. " and " .. friends[2].first .. "? Name: " .. name, function()
      p.band = { name = name, members = { friends[1].id, friends[2].id }, practice = 0, gigs = 0, formed = Clock.day(W.t) }
      local b = { id = #W.music.bands + 1, name = name, genre = p.taste or "indie", scene = "local scene", pop = 2, hype = 5,
        local_ = true, formed = Clock.date(Clock.day(W.t)).y, members = { friends[1].id, friends[2].id }, player = true }
      W.music.bands[b.id] = b
      p.band.id = b.id
      Timeline.add("music", p.name .. ", " .. friends[1].first .. " and " .. friends[2].first .. " started a band called " .. name .. ".", 3)
      Rumors.add("band", -1, p.name .. " started a band called " .. name, 5, { friends[1].id, friends[2].id })
      Say("You're a band now. Practice on the food court stage when it's quiet, then sign up for Teen Night.")
    end)
    return
  end
  local day = Clock.day(W.t)
  local nextFri = day + ((5 - Clock.date(day).wd) % 7)
  if (nextFri // 7) % 2 ~= 0 then nextFri = nextFri + 7 end
  if p.band.gig and p.band.gig >= day then Say(p.band.name .. " is booked for " .. Clock.dateStr(p.band.gig) .. ", 7 PM.") return end
  if p.band.practice < 3 then Say("\"Come back after you've practiced a few times. Last band that didn't, the fire marshal came.\"") return end
  p.band.gig = nextFri
  Say("Booked! " .. p.band.name .. " plays Teen Night on " .. Clock.dateStr(nextFri) .. " at 7 PM. Tell everyone.")
  Pager.send("MALL OFFICE", "TEEN NIGHT " .. Clock.shortDate(nextFri) .. " 7PM. DONT BE LATE")
end

function Play.stage()
  local p = W.p
  local day = Clock.day(W.t)
  local m = Clock.minute(W.t)
  if p.band and p.band.gig == day and m >= 18 * 60 + 45 and m <= 20 * 60 then
    Play.gig(true)
  elseif p.band then
    Confirm("Practice with " .. p.band.name .. " (45 min)?", function() Play.gig(false) end)
  else
    Say("An empty stage. TEEN NIGHT every other Friday. Sign-ups at the mall office.")
  end
end

-- rhythm: press A (or crank-strum) when the note hits the line
function Play.gig(real)
  local p = W.p
  local r = U.rng(W.seed, "gig", W.t)
  local notes = {}
  local t = 40
  for i = 1, real and 48 or 30 do t = t + r:i(10, 24); notes[i] = { t = t, lane = r:i(1, 3), hit = false } end
  local sc = { f = 0, notes = notes, score = 0, miss = 0, strum = Input.crankStepper(90) }
  function sc:update()
    self.f = self.f + 1
    local lane
    if In.left then lane = 1 elseif In.a or In.up then lane = 2 elseif In.right then lane = 3 end
    if self.strum(In.crank) ~= 0 then lane = 2 end
    if lane then
      local best
      for _, n in ipairs(self.notes) do
        if not n.hit and n.lane == lane and math.abs(n.t - self.f) < 7 then best = n break end
      end
      if best then best.hit = true; self.score = self.score + 1; Sfx.blip(300 + lane * 120, 0.05)
      else self.miss = self.miss + 1 end
    end
    if self.f > notes[#notes].t + 40 then
      Scene.pop()
      local pct = self.score / #self.notes
      local mins = real and 45 or 45
      Day.skipTo(W.t + mins, real and "Playing Teen Night..." or "Practicing...", function()
        if real then
          p.band.gigs = p.band.gigs + 1
          p.band.gig = nil
          p.stats.gigs = p.stats.gigs + 1
          local crowd = #NPCAI.inArea("fc")
          local good = pct > 0.6
          p.fame = p.fame + (good and 10 or 3)
          local b = W.music.bands[p.band.id]
          if b then b.pop = b.pop + (good and 6 or 1); b.hype = b.hype + 10 end
          local seeds = {}
          for _, n in ipairs(NPCAI.inArea("fc")) do seeds[#seeds + 1] = n.id end
          Rumors.add("gig", -1, p.band.name .. (good and " killed it at Teen Night" or " played Teen Night (it was loud)"), good and 8 or 4, seeds)
          Timeline.add("music", p.band.name .. " played Teen Night to " .. crowd .. " people." .. (good and " People are talking." or ""), 3)
          Say(good and { "The food court goes nuts. Someone throws a pretzel on stage. It is an honor.", "You played for " .. crowd .. " people." }
            or { "It was loud and mostly in time. A few people clapped. Your mom would be proud." })
        else
          p.band.practice = p.band.practice + 1
          Say(pct > 0.6 and "You're getting tighter. " .. (3 - math.min(3, p.band.practice)) .. " more practices before Teen Night." or
            "Rough. The pretzel guy asked you to stop.")
        end
      end)
    end
  end
  function sc:draw()
    Gfx.clear("black")
    Gfx.text(real and "TEEN NIGHT - LIVE" or "PRACTICE", 200, 6, { white = true, bold = true, align = "center" })
    for lane = 1, 3 do
      local x = 100 + (lane - 1) * 100
      Gfx.line(x, 30, x, 200, "white")
    end
    Gfx.fill(60, 196, 280, 3, "white")
    for _, n in ipairs(self.notes) do
      local y = 196 - (n.t - self.f) * 4
      if y > 26 and y < 230 and not n.hit then
        Gfx.circle(100 + (n.lane - 1) * 100, y, 8, true, "white")
      end
    end
    Gfx.text("LEFT / A (or crank strum) / RIGHT", 200, 212, { white = true, align = "center" })
    Gfx.text(self.score .. " hits", 390, 6, { white = true, align = "right" })
    Gfx.neon(0, 228, 400, 12, 1)
  end
  Scene.push(sc)
end
