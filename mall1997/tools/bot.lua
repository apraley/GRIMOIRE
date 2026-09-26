-- Autopilot player for headless inspection runs. Uses the simulation APIs
-- directly (no UI) to live a plausible teenage life: go to the mall, talk
-- to people, shop, apply for jobs, work shifts, play the arcade, see movies
-- and, occasionally, shoplift. Loaded by tools/sim30.lua with --bot.

Bot = { log = {} }

local function say(s) Bot.log[#Bot.log + 1] = Clock.shortDate(Clock.day(W.t)) .. " " .. Clock.hhmm(Clock.minute(W.t)) .. " " .. s end

local function areaNPCs(a)
  local out = {}
  for _, n in ipairs(NPCAI.inArea(a)) do if not n.route then out[#out + 1] = n end end
  return out
end

local function visit(r)
  local p = W.p
  local choices = { "c1", "c2", "fc", "s" .. W.mall.arcade }
  local s = W.stores[r:i(1, #W.stores)]
  if s.open and s.type ~= "food" then choices[#choices + 1] = "s" .. s.id end
  p.area = r:pick(choices)
end

function Bot.day(day)
  local p = W.p
  local r = U.rng("bot", day)
  local info = Clock.info(day)
  if info.closed or Security.mallBanned() then
    WorldSim.advance(day * 1440 + 21 * 60, 5)
    return
  end
  local arrive = info.school and (15 * 60 + 30) or (11 * 60)
  WorldSim.advance(day * 1440 + arrive, 5)
  p.atMall = true
  local curfew = PlayerSim.curfew(day)
  while Clock.minute(W.t) < math.min(curfew - 10, info.close) do
    visit(r)
    local here = areaNPCs(p.area)
    -- work if scheduled
    local sh, why = Jobs.canClockIn()
    if sh then
      local def = Minigames.list[Jobs.kindFor(p.job.store)]
      local score = r:i(35, 95)
      Jobs.context(sh)
      local endT = day * 1440 + sh.e
      WorldSim.advance(endT, 5)
      Jobs.finish(sh, { score = score, tips = r:i(0, 300), text = "bot shift" })
      say("worked a shift at " .. Jobs.placeName() .. " (score " .. score .. ")")
    end
    -- talk to someone
    if #here > 0 then
      local n = r:pick(here)
      local opts = Talk.options(n)
      local o = opts[r:i(1, #opts)]
      if o.id == "job" and not p.job then
        local s = W.stores[n.job]
        if s and s.hiring then
          local hired = Jobs.decide(s.id, r:i(15, 40))
          say((hired and "got hired at " or "was turned down at ") .. s.name)
        end
      elseif o.id ~= "give" and o.id ~= "borrow" and o.id ~= "tell" and o.id ~= "quit" and o.id ~= "hours" and o.id ~= "insult" and o.id ~= "secjob" and o.id ~= "lend" then
        local out = Talk.act(n, o.id)
        if o.id == "askout" and W.p.partner == n.id then say("started going out with " .. n.first) end
      end
      if p.companion then local c = W.npcs[p.companion]; if c then c.held = nil end; p.companion = nil end
    end
    -- apply for jobs directly at hiring stores
    if not p.job and r:chance(0.3) then
      for _, s in ipairs(W.stores) do
        if s.open and s.hiring and Jobs.KIND[s.type] ~= "department" and r:chance(0.3) then
          local m = s.mgr and W.npcs[s.mgr]
          if m then
            m.p.met = true
            local hired = Jobs.decide(s.id, r:i(20, 42))
            say((hired and "got hired at " or "applied at ") .. s.name)
            break
          end
        end
      end
    end
    -- shop
    local sid = tonumber((p.area):match("^s(%d+)$"))
    local s = sid and W.stores[sid]
    if s and s.type ~= "arcade" and s.type ~= "cinema" and Stores.isOpenAt(s, W.t) then
      local items = Econ.rack(s, r:i(1, 3))
      local it = r:pick(items)
      if it then
        if r:chance(0.04) and (p.record or 0) < 2 then
          local rep = Security.concealCheck(s, 10 * 16, 8 * 16)
          Security.conceal(s, it, rep)
          local c = Security.exitCheck(s)
          if c then
            local out = Security.caughtPlayer(s, "comply")
            say("got caught shoplifting " .. it.n .. " at " .. s.name .. " (mall ban " .. out.mallBan .. ")")
            if out.mallBan > 0 then break end
          else
            Security.getaway(s)
            say("shoplifted " .. it.n .. " from " .. s.name)
          end
        elseif p.money > it.v + 500 and r:chance(0.4) then
          Econ.buy(it, s)
          say("bought " .. it.n)
        end
      end
    end
    -- arcade
    if p.area == "s" .. W.mall.arcade and r:chance(0.5) then
      local g = r:pick(Content.ARCADE_GAMES).key
      local sc = ArcadeGames.list[g].npcScore(r, 0.45 + math.min(0.4, p.stats.days * 0.01))
      local rank = ArcadeSim.submit(g, -1, sc)
      if rank == 1 then say("set the " .. g .. " record: " .. sc) end
    end
    -- food
    if p.hunger > 60 then p.hunger = 20; p.money = p.money - 350 end
    -- movie now and then
    if r:chance(0.06) and p.money > 700 then
      local show = CinemaSim.nextShow(Clock.minute(W.t), nil)
      if show and show.t + show.mins < curfew - 10 then
        WorldSim.advance(day * 1440 + show.t + show.mins, 5)
        p.money = p.money - CinemaSim.price(show.t)
        p.stats.movies[show.movie] = true
        say("saw " .. W.movies[show.movie].title)
      end
    end
    WorldSim.advance(W.t + r:i(15, 40), 5)
  end
  p.atMall = false
  p.stats.days = p.stats.days + 1
  p.area = "home"
end
