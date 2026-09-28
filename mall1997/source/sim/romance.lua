-- Romance: crushes that engineer "coincidences", couples going on dates,
-- anniversaries, cheating that leaks through the rumor mill, jealousy and
-- breakups, and what dating the player actually asks of you.

Romance = {}

local function rel(a, b) return Social.rel(a, b) end

-- after everyone has planned their day: people with crushes find reasons to
-- be wherever their crush is going to be
function Romance.coincidences(day)
  local r = U.rng(W.seed, "coinc", day)
  for _, n in ipairs(W.npcs) do
    if n.status == "active" and n.crush and n.crush > 0 and n.plan and #n.plan > 0 and r:chance(0.35) then
      local c = W.npcs[n.crush]
      if c and c.status == "active" and c.plan then
        for _, b in ipairs(c.plan) do
          if b.act ~= "work" and b.act ~= "watch" and (b.a == "fc" or b.a == "c1" or b.a == "c2" or b.a:match("^s%d")) then
            -- replace any overlapping block of ours
            local keep = {}
            for _, mb in ipairs(n.plan) do if mb.e <= b.s or mb.s >= b.e or mb.act == "work" then keep[#keep + 1] = mb end end
            local clash = false
            for _, mb in ipairs(keep) do if mb.act == "work" and not (mb.e <= b.s or mb.s >= b.e) then clash = true end end
            if not clash then
              keep[#keep + 1] = { s = b.s, e = b.e, a = b.a, act = b.act == "shop" and "hang" or b.act, ref = b.ref }
              table.sort(keep, function(x, y) return x.s < y.s end)
              n.plan = keep
              n.pi = 1
            end
            break
          end
        end
      end
    end
  end
end

local VENUES = { "movie", "fc", "movie", "restaurant", "arcade", "fountain" }

-- plan a date for a couple
local function planDate(a, b, day, r)
  local info = Clock.info(day)
  local venue = r:pick(VENUES)
  if a.age >= 25 then venue = r:pick({ "movie", "restaurant", "restaurant" }) end
  local s = info.school and r:i(17, 19) * 60 or r:i(13, 19) * 60
  local d = { day = day, s = s, e = s + 90, with = b.id }
  if venue == "movie" then
    local show = CinemaSim.nextShow(s, a)
    if show then d.a = "scr" .. show.screen; d.s = show.t - 15; d.e = show.t + show.mins; d.show = show.movie
    else venue = "fc" end
  end
  if venue == "restaurant" then
    local rs = Stores.byType("restaurant")
    if #rs > 0 then d.a = "s" .. r:pick(rs).id else venue = "fc" end
  end
  if venue == "arcade" then d.a = "s" .. W.mall.arcade end
  if venue == "fountain" then d.a = "c1" end
  if not d.a then d.a = "fc" end
  a.dateToday = d
  b.dateToday = { day = d.day, s = d.s, e = d.e, a = d.a, with = a.id, show = d.show }
end

function Romance.daily(day)
  local r = U.rng(W.seed, "romance", day)
  local info = Clock.info(day)
  for _, n in ipairs(W.npcs) do
    local p = n.partner and n.partner > 0 and W.npcs[n.partner]
    if n.status == "active" and p and p.status == "active" and n.id < p.id then
      n.since = n.since or day; p.since = p.since or n.since
      local months = (day - n.since) // 30
      if (day - n.since) > 0 and (day - n.since) % 30 == 0 and (months == 1 or months == 3 or months == 6 or months % 12 == 0) then
        local an, bn = n.first, p.first
        if an == bn then an, bn = NPCGen.name(n), NPCGen.name(p) end
        Timeline.add("people", an .. " and " .. bn .. " have been going out for " ..
          (months % 12 == 0 and (months // 12 .. (months == 12 and " year" or " years")) or (months .. (months == 1 and " month" or " months"))) .. ".", 1)
      end
      -- dates
      local chance = info.weekend and 0.35 or 0.12
      if info.holiday == "Valentine's Day" then chance = 0.95 end
      if not info.closed and r:chance(chance) and not Stores.shiftOf(n, day) and not Stores.shiftOf(p, day) then
        planDate(n, p, day, r)
      end
      -- wandering eyes get noticed
      if n.crush and n.crush ~= p.id and n.crush > 0 and r:chance(0.04) then
        local c = W.npcs[n.crush]
        if c and rel(n, c).a > 45 and NPCGen.romanceOK(n, c) then
          local witness
          for _, id in ipairs(U.keys(p.rel)) do
            local rr = p.rel[id]
            if rr.f > 30 and W.npcs[id] and W.npcs[id].status == "active" then witness = id break end
          end
          local where = r:pick({ "the food court", "the Cineplex", "the fountain", "the parking lot", "the arcade" })
          Rumors.add("cheat", n.id, n.first .. " was seen holding hands with " .. c.first .. " at " .. where, 8,
            { witness or c.id }, { partner = p.id, with = c.id })
        end
      end
    end
  end
end

-- jealousy: hearing that your partner was seen with someone else
function Romance.onRumor(n, rm)
  if rm.kind == "cheat" and rm.partner == n.id and n.partner == rm.about then
    local cheater = W.npcs[rm.about]
    local other = rm.with and W.npcs[rm.with]
    if cheater then
      Social.breakup(n, cheater, "after hearing what happened at the mall")
      if other then rel(n, other).f = rel(n, other).f - 40 end
      n.mood = U.clamp(n.mood - 20, 0, 100)
      -- and maybe the cheater ends up with the other person
      if other and not other.partner and U.hash(n.id, rm.id) % 2 == 0 then
        cheater.partner, other.partner = other.id, cheater.id
        cheater.crush, other.crush = other.id, cheater.id
        Timeline.add("people", cheater.first .. " and " .. other.first .. " are officially together now. Awkward.", 2)
      end
    end
  end
end

-- dating the player comes with expectations
function Romance.playerDaily(day)
  local pl = W.p
  local n = pl.partner and W.npcs[pl.partner]
  if not n then return end
  local p = n.p
  if n.status ~= "active" then pl.partner = nil return end
  local info = Clock.info(day)
  local since = day - (p.last or day)
  if since > 5 then
    p.a = p.a - 3
    if since % 3 == 0 then Pager.send(n.first:upper(), since > 9 and "R WE EVEN GOING OUT ANYMORE" or "U NEVER CALL ME BACK") end
  elseif U.hash(day, n.id) % 5 == 0 then
    Pager.send(n.first:upper(), U.hash(day) % 2 == 0 and "143" or "THINKING ABOUT U. MALL 2MRW?")
  end
  -- Valentine's Day is a test
  local yesterday = Clock.info(day - 1)
  if yesterday.holiday == "Valentine's Day" and (p.giftDay or -1) ~= day - 1 then
    p.a = p.a - 20; p.an = p.an + 20
    Pager.send(n.first:upper(), "U FORGOT. VALENTINES. WOW")
    Memory.add(n, "forgot", pl.name .. " forgot Valentine's Day", -1)
  end
  Social.clampP(n)
  if p.a < 25 then
    Talk.breakupPlayer(n, n.first .. " ended it")
    Pager.send(n.first:upper(), "I THINK WE SHOULD SEE OTHER PEOPLE")
  end
end
