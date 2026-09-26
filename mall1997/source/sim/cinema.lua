-- Cinema: fictional 1990s releases, weekly bookings (new films open on
-- Fridays), daily showtimes derived from the bookings, attendance.

CinemaSim = {}

function CinemaSim.init()
  W.cinema = { screens = {}, week = -1, booked = {} }
  -- one enormous December event picture
  for _, m in ipairs(W.movies) do
    if m.opens and m.opens >= 108 and m.opens <= 116 then
      m.title = "The Unsinkable"; m.genre = "romance"; m.rating = "PG-13"; m.mins = 194
      m.quality = 88; m.buzz = 99; m.star = "Leo DiCapra"; m.tag = "Nothing on Earth could come between them."
      m.blockbuster = true
      break
    end
  end
  CinemaSim.book(Clock.day(W.t))
end

-- which films are "in theaters" on a day
local function playing(m, day)
  if not m.opens or m.opens > day then return false end
  local run = 21 + math.floor(m.quality / 3) + (m.blockbuster and 60 or 0)
  return day - m.opens < run
end

function CinemaSim.book(day)
  local cands = {}
  for _, m in ipairs(W.movies) do if playing(m, day) then cands[#cands + 1] = m end end
  table.sort(cands, function(a, b)
    local fa = a.buzz - (day - a.opens) * 1.2
    local fb = b.buzz - (day - b.opens) * 1.2
    if fa == fb then return a.id < b.id end
    return fa > fb
  end)
  local old = {}
  for _, id in ipairs(W.cinema.screens) do old[id] = true end
  local screens = {}
  for i = 1, math.min(6, #cands) do screens[#screens + 1] = cands[i].id end
  -- a big opener gets two screens
  if cands[1] and cands[1].buzz > 80 and #screens >= 6 then screens[6] = cands[1].id end
  W.cinema.screens = screens
  W.cinema.week = Clock.week(day * 1440)
  for _, id in ipairs(screens) do
    if not old[id] and W.movies[id].opens and W.movies[id].opens >= day - 7 and not W.cinema.booked[id] then
      W.cinema.booked[id] = true
      local m = W.movies[id]
      Timeline.add("movie", "Now playing at the Cineplex: " .. m.title .. " (" .. m.rating .. ", " .. m.genre .. ").",
        m.blockbuster and 3 or 1)
      if m.blockbuster then Trends.start("unsinkable") end
    end
  end
end

-- shows for a day: { screen, movie, t (minute), mins }
function CinemaSim.shows(day)
  local out = {}
  for i, id in ipairs(W.cinema.screens) do
    local m = W.movies[id]
    local t = 12 * 60 + (i - 1) * 15
    while t <= 22 * 60 + 30 do
      out[#out + 1] = { screen = i, movie = id, t = t, mins = m.mins }
      t = t + m.mins + 25
      t = t - (t % 5)
    end
  end
  table.sort(out, function(a, b) return a.t < b.t end)
  return out
end

function CinemaSim.nextShow(mod, n)
  local day = Clock.day(W.t)
  local best, bw
  for _, s in ipairs(CinemaSim.shows(day)) do
    if s.t >= mod and s.t < mod + 120 then
      local m = W.movies[s.movie]
      local w = m.buzz + m.quality / 2
      if n and n.age < 13 and m.rating == "R" then w = 0 end
      if n and n.age < 20 and (m.genre == "horror" or m.genre == "teen" or m.genre == "comedy" or m.genre == "action") then w = w + 30 end
      if n and n.age >= 30 and (m.genre == "drama" or m.genre == "romance" or m.genre == "thriller") then w = w + 30 end
      if not bw or w > bw then best, bw = s, w end
    end
  end
  return best
end

function CinemaSim.price(mod) return mod < 18 * 60 and 450 or 650 end

function CinemaSim.npcWatch(n, movieId)
  local m = movieId and W.movies[movieId]
  if not m then return end
  local price = CinemaSim.price(Clock.minute(W.t))
  if n.money < price then return end
  n.money = n.money - price
  m.seen = m.seen + 1
  m.gross = m.gross + price
  local cin = W.stores[W.mall.cinema]
  cin.npcSales = (cin.npcSales or 0) + price + 300
  Memory.add(n, "movie", "saw " .. m.title, movieId)
  for i, w in ipairs(n.wants) do if w.k == "movie" then table.remove(n.wants, i) break end end
end

-- average draw of what's playing (0..1), used by store economics
function CinemaSim.draw()
  if not W.cinema or #W.cinema.screens == 0 then return 0.5 end
  local s = 0
  for _, id in ipairs(W.cinema.screens) do s = s + W.movies[id].buzz end
  return s / (#W.cinema.screens * 100)
end

function CinemaSim.weekly(day)
  for _, m in ipairs(W.movies) do
    if m.opens and m.opens <= day then m.buzz = math.max(5, m.buzz - 4 + math.floor((m.quality - 50) / 25)) end
  end
  CinemaSim.book(day)
end

function CinemaSim.review(m)
  local q = m.quality
  if q > 85 then return "Two thumbs way up." elseif q > 70 then return "Surprisingly good." elseif q > 50 then return "It was fine. Popcorn was good."
  elseif q > 30 then return "You kind of want those two hours back." end
  return "Legendarily bad. You'll quote it for years."
end
