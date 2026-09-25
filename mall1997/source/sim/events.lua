-- Calendar events and the slow aging of the mall: holidays, decorations,
-- Santa, Teen Night gigs, arcade tournaments, renovations, competition from
-- the new outlet mall, and the turn of the year.

Events = {}

function Events.seed(r)
  W.events = {
    { day = 4, kind = "school", done = false },
    { day = Clock.dayOf(1998, 1, 12), kind = "reno", what = "fountain", dur = 21 },
    { day = Clock.dayOf(1998, 3, 2), kind = "reno", what = "carpet", dur = 14 },
    { day = Clock.dayOf(1998, 4, 20), kind = "outlet" },
    { day = Clock.dayOf(1998, 5, 11), kind = "reno", what = "foodcourt", dur = 10 },
    { day = Clock.dayOf(1998, 6, 1), kind = "reno", what = "skylight", dur = 7 },
    { day = Clock.dayOf(1998, 8, 3), kind = "anchor_rumor" },
  }
  W.mall.appeal = 1.0
  W.mall.age = 25
end

local function santa()
  -- someone has to be Santa
  local cands = {}
  for _, n in ipairs(W.npcs) do
    if n.status == "active" and n.sex == "m" and n.age >= 55 and n.role ~= "family" then cands[#cands + 1] = n end
  end
  table.sort(cands, function(a, b) return a.id < b.id end)
  return cands[1 + (W.seed % math.max(1, #cands))]
end

function Events.daily(day)
  local info = Clock.info(day)
  local r = U.rng(W.seed, "events", day)
  -- decorations
  local decor
  if info.m == 10 and info.d >= 15 then decor = "halloween" end
  if (info.m == 11 and info.d >= 20) or info.m == 12 then decor = "xmas" end
  if info.m == 2 and info.d <= 14 then decor = "valentine" end
  if decor ~= W.mall.decor then
    W.mall.decor = decor
    if decor == "xmas" then Timeline.add("mall", "Maintenance hung the giant tinsel snowflakes over center court.", 1) end
    if decor == "halloween" then Timeline.add("mall", "Paper skeletons and orange lights went up all over the mall.", 1) end
  end
  -- Santa's workshop
  if info.holiday == "Black Friday" and not W.mall.santa then
    local s = santa()
    if s then
      W.mall.santa = s.id
      Timeline.add("mall", NPCGen.name(s) .. " is this year's mall Santa. Photos $6.99.", 2)
      Rumors.add("santa", s.id, NPCGen.name(s) .. " is playing Santa this year", 5, { s.id })
    end
  end
  if info.m == 12 and info.d == 25 then W.mall.santa = nil end
  if info.holiday == "Halloween" then
    Timeline.add("mall", "Trick-or-treating at the mall: a thousand tiny Power Rangers in the concourse.", 2)
  end
  if info.holiday == "Black Friday" then
    Timeline.add("mall", "Black Friday. Doors opened at 7 AM. Someone was trampled over a Giggle Me Gus.", 2)
  end
  if info.m == 1 and info.d == 1 then
    Timeline.add("mall", "Happy New Year. It is " .. info.y .. ".", 3)
    W.mall.age = W.mall.age + 1
    Pager.send("MOM", "HAPPY NEW YEAR " .. info.y .. " LOVE U")
  end
  -- slow aging: each month the mall looks a little more tired
  if info.d == 1 then
    W.mall.appeal = U.clamp((W.mall.appeal or 1) - 0.012, 0.6, 1.2)
  end
  -- Teen Night on alternate Fridays: a local band plays the food court stage
  if info.wd == 5 and (day // 7) % 2 == 0 and not Management.has("teenNightPaused") then
    Events.teenNight(day, r)
  end
  -- arcade tournament: first Saturday of the month
  if info.wd == 6 and info.d <= 7 then ArcadeSim.startTourney(day, r) end
  if info.d == 15 then ArcadeSim.rotate(day, r) end
  -- scheduled events
  for _, e in ipairs(W.events) do
    if not e.done and e.day <= day then
      e.done = true
      Events.run(e, day, r)
    end
    if e.kind == "reno" and e.done and not e.finished and e.day + e.dur <= day then
      e.finished = true
      W.mall.reno = nil
      W.mall.appeal = U.clamp((W.mall.appeal or 1) + 0.06, 0.6, 1.2)
      W.mall.renovated = W.mall.renovated or {}
      W.mall.renovated[e.what] = day
      Timeline.add("mall", "Renovation finished: " .. Events.renoName(e.what) .. ". It looks... newer.", 2)
      Areas.invalidate()
    end
  end
  -- holiday season hiring: stores staff up
  if info.m == 11 and info.d == 15 then
    Timeline.add("mall", "HOLIDAY HELP WANTED signs appeared in half the windows.", 1)
    for _, s in ipairs(W.stores) do if s.open then s.hiring = true end end
  end
end

function Events.renoName(w)
  return ({ fountain = "the center court fountain", carpet = "new carpet on the upper level",
    foodcourt = "the food court (new tables, same pizza)", skylight = "the skylights" })[w] or w
end

function Events.run(e, day, r)
  if e.kind == "school" then
    Timeline.add("mall", "School started. The mall is quieter on weekday mornings.", 1)
  elseif e.kind == "reno" then
    W.mall.reno = e.what
    Timeline.add("mall", "Renovation began: " .. Events.renoName(e.what) .. ". Plywood walls and a sign that says PARDON OUR DUST.", 2)
    Areas.invalidate()
  elseif e.kind == "outlet" then
    W.mall.appeal = U.clamp((W.mall.appeal or 1) - 0.08, 0.6, 1.2)
    W.mall.outlet = day
    Timeline.add("mall", "The new outlet mall opened out by the interstate. Everyone says they'll never go.", 3)
    Rumors.add("outlet", nil, "half the stores are thinking about moving to the outlet mall", 6, W.mall.mgmt)
  elseif e.kind == "anchor_rumor" then
    Rumors.add("anchor", nil, "one of the department stores might close", 7, W.mall.mgmt)
    Timeline.add("mall", "Leasing office lights on late. Nobody will say why.", 1)
  end
end

function Events.teenNight(day, r)
  -- local bands take turns; the player's band can sign up at the mall office
  local p = W.p
  if p.band and p.band.gig == day then return end
  local bands = {}
  for _, b in ipairs(W.music.bands) do if b.local_ and b.members then bands[#bands + 1] = b end end
  local b = r:pick(bands)
  if b then
    for _, id in ipairs(b.members) do
      local n = W.npcs[id]
      if n and n.status == "active" then n.gig = { day = day, s = 19 * 60, e = 20 * 60 + 30 } end
    end
    b.hype = b.hype + 5; b.pop = b.pop + 2
    Timeline.add("music", "Teen Night: " .. b.name .. " played the food court stage.", 1)
  end
end

-- maintenance crews fix things as they make their rounds
function Events.maintFix(n)
  if n.loc == ("s" .. W.mall.arcade) or n.loc == "fc" then
    for _, m in ipairs(W.arcade.machines) do
      if m.broken and U.hash(n.id, W.t) % 4 == 0 then m.broken = false; m.wear = 10 break end
    end
  end
end
