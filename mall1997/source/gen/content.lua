-- Content generation: bands, albums, movies, arcade machines. Called once at
-- new-game time; everything produced here is stored in the world save so it
-- can change (popularity, charts, high scores) and never regenerates.

Content = {}

local function bandName(r)
  local roll = r:f()
  if roll < 0.12 then return r:pick(Names.bandSolo) end
  if roll < 0.35 then return "The " .. r:pick(Names.bandA) .. " " .. r:pick(Names.bandB) end
  if roll < 0.45 then return r:pick(Names.bandA) .. r:pick({ "", "!", " 99", " Inc.", " Jr." }) end
  return r:pick(Names.bandA) .. " " .. r:pick(Names.bandB)
end

local MOODS = { "moody", "angry", "happy", "chill", "weird", "danceable", "sad", "loud", "romantic" }
Content.MOODS = MOODS
local GENRE_MOOD = {
  grunge = { "moody", "loud", "angry" }, ["alt-rock"] = { "moody", "loud", "sad" },
  ["ska-punk"] = { "happy", "loud", "danceable" }, ["hip-hop"] = { "danceable", "angry", "chill" },
  ["r&b"] = { "romantic", "chill", "danceable" }, pop = { "happy", "danceable", "romantic" },
  electronica = { "danceable", "weird", "chill" }, country = { "sad", "happy", "romantic" },
  metal = { "angry", "loud" }, swing = { "happy", "danceable" }, ["trip-hop"] = { "chill", "moody", "weird" },
  emo = { "sad", "moody", "loud" }, ["riot grrrl"] = { "angry", "loud" }, indie = { "weird", "sad", "chill" },
  ["boy band"] = { "happy", "romantic" }, ["jam band"] = { "chill", "weird", "happy" },
}
Content.GENRE_MOOD = GENRE_MOOD

function Content.genMusic(r)
  local M = { bands = {}, albums = {}, chart = {} }
  local used = {}
  local nb = r:i(70, 90)
  for i = 1, nb do
    local name
    for _ = 1, 20 do
      name = bandName(r)
      if not used[name] then break end
    end
    used[name] = true
    local g = r:pick(Names.genres)
    local b = {
      id = i, name = name, genre = g, scene = r:pick(Names.scenes),
      pop = r:i(5, 70), hype = r:i(0, 30),
      local_ = r:chance(0.12), -- a band from this town
      formed = r:i(1984, 1996),
    }
    if b.local_ then b.scene = "local scene"; b.pop = r:i(2, 25) end
    M.bands[i] = b
    local na = r:i(1, 3)
    for k = 1, na do
      local title
      if r:chance(0.2) then title = "Self-Titled" elseif r:chance(0.5) then
        title = r:pick(Names.albumA) .. " " .. r:pick(Names.albumB)
      else title = r:pick(Names.albumA) end
      local a = {
        id = #M.albums + 1, band = i, title = title,
        year = math.min(1997, b.formed + k * r:i(1, 3)),
        mood = r:pick(GENRE_MOOD[g] or MOODS), quality = r:i(20, 95),
        pop = math.max(1, b.pop + r:i(-15, 15)), sold = 0,
      }
      if a.year > 1997 then a.year = 1997 end
      M.albums[a.id] = a
    end
  end
  -- a few albums are announced to be released during the game
  for i = 1, 14 do
    local b = M.bands[r:i(1, nb)]
    local a = {
      id = #M.albums + 1, band = b.id, title = r:pick(Names.albumA) .. " " .. r:pick(Names.albumB),
      year = 1998, mood = r:pick(GENRE_MOOD[b.genre] or MOODS), quality = r:i(30, 98),
      pop = b.pop, sold = 0, releaseDay = r:i(5, 300),
    }
    M.albums[a.id] = a
  end
  return M
end

function Content.albumName(M, a)
  return M.bands[a.band].name .. " - " .. a.title
end

-- ------------------------------------------------------------------ movies
local function movieTitle(r, g)
  local t = r:pick(Names.movieTemplates[g])
  return U.fmt(t, {
    n = r:pick(Names.teenFirst), w = r:pick(Names.movieWords), c = r:pick(Names.cities),
    k = r:pick({ "II", "III", "IV", "2", "3", "5" }),
  })
end

local TAGLINES = {
  action = { "This time, it's personal.", "One man. One bus. No brakes.", "Justice has a new address." },
  comedy = { "They're back. And they're still idiots.", "Some guys never grow up.", "A comedy of epic proportions." },
  horror = { "Don't look behind you.", "Somebody knows your secret.", "Sleep is for the weak." },
  romance = { "Love is always worth the wait.", "Two hearts. One city.", "Fate has other plans." },
  ["sci-fi"] = { "The future is now.", "We are not alone.", "Space is big. Trouble is bigger." },
  drama = { "Some journeys change everything.", "Based on a true story.", "Hope lasts." },
  family = { "Fun for the whole pack!", "The whole family will howl!", "Believe in magic." },
  thriller = { "Trust no one.", "Every move is being watched.", "The truth will cost you." },
  teen = { "High school is a jungle.", "Senior year just got complicated.", "Be yourself. Or don't." },
  indie = { "Winner, Audience Award.", "Nothing happens. Beautifully.", "A film about waiting." },
}

function Content.genMovies(r)
  local list = {}
  local used = {}
  -- older catalog (VHS shelf) + films that will open during the game
  for i = 1, 150 do
    local g = r:pick(Names.movieGenres)
    local title
    for _ = 1, 20 do
      title = movieTitle(r, g)
      if not used[title] then break end
    end
    used[title] = true
    local rating = r:pick(Names.ratings)
    if g == "family" then rating = r:pick({ "G", "PG" }) end
    if g == "horror" then rating = r:pick({ "R", "R", "PG-13" }) end
    local m = {
      id = i, title = title, genre = g, rating = rating,
      star = r:pick(Names.stars), mins = r:i(84, 156), quality = r:i(10, 95),
      buzz = r:i(10, 90), tag = r:pick(TAGLINES[g]), seen = 0, gross = 0,
    }
    if i <= 90 then m.year = r:i(1985, 1997); m.vhs = true
    else m.opens = (i - 90) * 5 + r:i(-2, 2) end -- theatrical release day index
    list[i] = m
  end
  -- make sure some films are in theaters on day 0
  for i = 91, 98 do list[i].opens = -r:i(0, 20) end
  return list
end

-- ------------------------------------------------------------------ arcade
Content.ARCADE_GAMES = {
  { key = "serpent", name = "NEON SERPENT", blurb = "Eat pellets. Grow. Don't bite yourself." },
  { key = "orbital", name = "ORBITAL DEFENSE", blurb = "Crank the turret. Save the moon base." },
  { key = "tower", name = "BLOCK TOWER", blurb = "Stack slabs to the sky. Timing is everything." },
  { key = "racer", name = "HIGHWAY 97", blurb = "Dodge traffic at 97 miles an hour." },
}
Content.ARCADE_FLAVOR = { "SKEE-ROLL", "CLAW MACHINE", "AIR HOCKEY", "PINBALL: WIZARD KING",
  "STREET BRAWLER II", "PHOTO STICKER BOOTH", "DANCE MAT (IMPORT)", "LIGHT GUN SAFARI" }

-- Seeded NPC high scores so the boards have history before you arrive.
function Content.genArcade(r)
  local A = { machines = {}, scores = {}, champions = {} }
  for i, g in ipairs(Content.ARCADE_GAMES) do
    A.machines[#A.machines + 1] = { id = i, game = g.key, broken = false, wear = r:i(0, 40), plays = 0 }
    A.scores[g.key] = {}
  end
  for i, f in ipairs(Content.ARCADE_FLAVOR) do
    A.machines[#A.machines + 1] = { id = #A.machines + 1, flavor = f, broken = r:chance(0.15), wear = r:i(0, 70), plays = 0 }
  end
  A.tokens = 0 -- tokens sold today
  return A
end

-- ------------------------------------------------------------------ mall
local PLACES = { "Briarwood", "Cedar Point", "Twin Oaks", "Millbrook", "Fox Hollow", "Lakeshore",
  "Heritage", "Crossroads", "Riverbend", "Stonegate", "Pine Ridge", "Meadowlark" }
local SUFFIX = { "Mall", "Galleria", "Centre", "Town Center", "Fashion Square", "Plaza Mall" }
function Content.mallName(r)
  return r:pick(PLACES) .. " " .. r:pick(SUFFIX)
end
