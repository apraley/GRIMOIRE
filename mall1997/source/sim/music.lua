-- Music scene: weekly charts, new releases, band hype, local bands.

MusicSim = {}

function MusicSim.weekly(day)
  local M = W.music
  local r = U.rng(W.seed, "music", day)
  for _, a in ipairs(M.albums) do
    local b = M.bands[a.band]
    if a.releaseDay and not a.released and a.releaseDay <= day then
      a.released = true
      a.pop = U.clamp(b.pop + 10 + r:i(0, 15), 0, 100)
      b.hype = b.hype + 20
      Timeline.add("music", "New release: " .. a.title .. " by " .. b.name .. ".", b.pop > 50 and 2 or 1)
      -- fans want it
      for _, n in ipairs(W.npcs) do
        if n.status == "active" and n.taste == b.genre and r:chance(0.3) then
          n.wants[#n.wants + 1] = { k = "album", ref = a.id }
        end
      end
    end
    if not a.releaseDay or a.released then
      local trend = Trends.genreBoost(b.genre)
      local delta = (a.quality - 50) / 30 + b.hype / 15 + (trend - 1) * 8 + math.min(5, a.sold / 4) - 1.2
      a.pop = U.clamp(a.pop + delta + r:range(-2, 2), 1, 100)
      a.sold = math.floor(a.sold * 0.5)
    end
  end
  for _, b in ipairs(M.bands) do
    b.hype = math.floor(b.hype * 0.6)
    local best = 0
    for _, a in ipairs(M.albums) do if a.band == b.id and a.pop > best then best = a.pop end end
    b.pop = U.clamp(b.pop + (best - b.pop) * 0.3, 0, 100)
  end
  -- chart
  local list = {}
  for _, a in ipairs(M.albums) do if not a.releaseDay or a.released then list[#list + 1] = a end end
  table.sort(list, function(x, y) if x.pop == y.pop then return x.id < y.id end return x.pop > y.pop end)
  local prevTop = M.chart[1]
  M.chart = {}
  for i = 1, math.min(10, #list) do M.chart[i] = list[i].id end
  if M.chart[1] and M.chart[1] ~= prevTop then
    local a = M.albums[M.chart[1]]
    Timeline.add("music", Content.albumName(M, a) .. " is the #1 album at the mall's record stores.", 1)
  end
end

-- how an NPC reacts to a genre as a social signal (-1..1)
function MusicSim.opinion(n, genre)
  if not genre then return 0 end
  if n.taste == genre then return 1 end
  local close = {
    grunge = { "alt-rock", "metal", "indie" }, ["alt-rock"] = { "grunge", "indie", "emo" },
    ["ska-punk"] = { "swing", "emo" }, ["hip-hop"] = { "r&b" }, ["r&b"] = { "hip-hop", "pop" },
    pop = { "boy band", "r&b" }, ["boy band"] = { "pop" }, electronica = { "trip-hop" },
    ["trip-hop"] = { "electronica", "indie" }, emo = { "indie", "alt-rock" }, indie = { "emo", "riot grrrl", "alt-rock" },
    ["riot grrrl"] = { "indie", "grunge" }, metal = { "grunge" }, country = {}, swing = { "ska-punk" },
    ["jam band"] = { "indie" },
  }
  for _, g in ipairs(close[n.taste] or {}) do if g == genre then return 0.4 end end
  local hate = { goths = { pop = true, ["boy band"] = true, country = true }, skaters = { country = true, ["boy band"] = true },
    ["alt kids"] = { ["boy band"] = true, pop = true }, jocks = { emo = true, ["riot grrrl"] = true },
    preps = { metal = true, grunge = true } }
  if n.clique and hate[n.clique] and hate[n.clique][genre] then return -1 end
  return -0.2
end

-- NPC bands form among friends who want one
function MusicSim.formBands(day)
  local r = U.rng(W.seed, "bands", day)
  for _, n in ipairs(W.npcs) do
    if n.status == "active" and not n.band then
      for i, w in ipairs(n.wants) do
        if w.k == "band" and r:chance(0.05) then
          local mates = {}
          for _, id in ipairs(U.keys(n.rel)) do
            local rel = n.rel[id]
            local m = W.npcs[id]
            if m and rel.f > 25 and m.age < 25 and not m.band and m.status == "active" then mates[#mates + 1] = m end
          end
          if #mates >= 2 then
            local name = "The " .. r:pick(Names.bandA) .. " " .. r:pick(Names.bandB)
            local b = { id = #W.music.bands + 1, name = name, genre = n.taste, scene = "local scene", pop = 3,
              hype = 5, local_ = true, formed = Clock.date(day).y, members = { n.id, mates[1].id, mates[2].id } }
            W.music.bands[b.id] = b
            for _, id in ipairs(b.members) do W.npcs[id].band = b.id end
            table.remove(n.wants, i)
            Timeline.add("music", n.first .. ", " .. mates[1].first .. " and " .. mates[2].first ..
              " started " .. U.a(n.taste) .. " band called " .. name .. ".", 2)
            Rumors.add("band", n.id, n.first .. " started a band called " .. name, 4, b.members)
          end
          break
        end
      end
    end
  end
end
