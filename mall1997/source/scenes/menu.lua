-- Pause menu: your life at a glance. Tabs: ME, BAG, PAGER, PEOPLE, RUMORS,
-- NEWS (the world timeline), MALL (directory, charts, films, records),
-- LORE, SAVE. Crank or D-pad scrolls; LEFT/RIGHT switch tabs.

Menu = {}

local TABS = { "ME", "BAG", "PAGER", "PEOPLE", "RUMORS", "NEWS", "MALL", "LORE", "SAVE" }

local function fit(s, w)
  s = tostring(s)
  if Gfx.textW(s) <= w then return s end
  while #s > 1 and Gfx.textW(s .. "..") > w do s = s:sub(1, #s - 1) end
  return s .. ".."
end

local function bar(v) v = U.clamp(math.floor(v / 10 + 0.5), 0, 10) return string.rep("|", v) .. string.rep(".", 10 - v) end

-- each builder returns rows: { text = "...", act = fn? , hdr = bool }
local B = {}

B.ME = function()
  local p = W.p
  local day = Clock.day(W.t)
  local rows = {}
  local function add(t, h) rows[#rows + 1] = { text = t, hdr = h } end
  add(p.name .. ", " .. p.age .. ". " .. Clock.dateStr(day), true)
  add("Money " .. U.money(p.money) .. "   Tokens " .. p.tokens .. "   Tickets " .. (p.tickets or 0))
  add("Energy   " .. bar(p.energy) .. "   Hunger  " .. bar(p.hunger))
  add("Confid.  " .. bar(p.conf) .. "   Rep     " .. bar(p.rep or 20))
  if p.job then
    local sh = Jobs.shiftToday()
    add("Job: " .. Jobs.title() .. " at " .. Jobs.placeName() .. " (perf " .. math.floor(p.job.perf) .. ", " .. p.job.strikes .. " strikes)")
    local nxt
    for _, s in ipairs(p.job.shifts) do if s.day >= day and not s.done and not s.missed then nxt = s break end end
    if nxt then add("  Next shift: " .. Clock.DAYS[Clock.date(nxt.day).wd + 1] .. " " .. Clock.hhmm(nxt.s) .. "-" .. Clock.hhmm(nxt.e)) end
  else add("Job: none. (Managers hire. Look for NOW HIRING.)") end
  add("Curfew tonight: " .. Clock.hhmm(PlayerSim.curfew(day)))
  if (p.grounded or 0) > day then add("GROUNDED until " .. Clock.dateStr(p.grounded)) end
  if Security.mallBanned() then add("BANNED from the mall until " .. Clock.dateStr(p.mallBan)) end
  local bans = {}
  for k, v in pairs(p.bans) do if v > day and W.stores[tonumber(k)] then bans[#bans + 1] = W.stores[tonumber(k)].name end end
  if #bans > 0 then add("Banned at: " .. table.concat(bans, ", ")) end
  add("Taste: " .. (p.taste or "undeclared") .. "   Fame: " .. math.floor(p.fame))
  if p.partner and W.npcs[p.partner] then add("Going out with " .. NPCGen.name(W.npcs[p.partner])) end
  if p.band then add("Band: " .. p.band.name .. " (" .. p.band.practice .. " practices, " .. p.band.gigs .. " gigs)") end
  add("LIFE SO FAR", true)
  add("Days at the mall: " .. p.stats.days .. "   Conversations: " .. p.stats.talks)
  add("Movies seen: " .. U.count(p.stats.movies) .. "   Albums owned: " .. U.count(p.stats.albums))
  add("Shifts worked: " .. p.stats.shifts .. "   Earned: " .. U.money(p.stats.earned))
  add("Things stolen: " .. p.stats.stolen .. "   Times caught: " .. p.stats.caught)
  add("Dates: " .. p.stats.dates .. "   Gigs: " .. p.stats.gigs .. "   Mall secrets: " .. Lore.count() .. "/" .. Lore.total())
  local recs = 0
  for _, g in ipairs(Content.ARCADE_GAMES) do local b = W.arcade.scores[g.key]; if b[1] and b[1].who == -1 then recs = recs + 1 end end
  add("Arcade records held: " .. recs .. "/4" .. (p.flags.champ and "  (ARCADE CHAMPION)" or ""))
  local cr = p.cliqueRep or {}
  add("WHAT THE CLIQUES THINK", true)
  for _, c in ipairs(Names.cliques) do
    local v = cr[c] or 0
    add(U.cap(c) .. ": " .. (v > 30 and "love you" or v > 10 and "like you" or v > -10 and "shrug" or v > -30 and "don't like you" or "can't stand you"))
  end
  return rows
end

B.BAG = function()
  local p = W.p
  local rows = {}
  if #p.inv == 0 then rows[1] = { text = "Your backpack is empty. Except for gum wrappers." } end
  for _, it in ipairs(p.inv) do
    local label = Econ.itemLabel(it)
    if it.due then label = label .. " (due " .. Clock.shortDate(it.due) .. ")" end
    rows[#rows + 1] = { text = label, act = function() Menu.itemAction(it) end }
  end
  return rows
end

B.PAGER = function()
  local p = W.p
  local rows = {}
  for i = #p.pager, 1, -1 do
    local m = p.pager[i]
    rows[#rows + 1] = { text = (m.read and "  " or "* ") .. Clock.shortDate(Clock.day(m.t)) .. " " .. Clock.hhmm(Clock.minute(m.t)) .. "  " .. m.from .. ": " .. m.txt,
      act = function() m.read = true; Say(m.from .. ": " .. m.txt) end }
    m.read = true
  end
  if #rows == 0 then rows[1] = { text = "No messages." } end
  return rows
end

B.PEOPLE = function()
  local rows = {}
  local list = {}
  for _, n in ipairs(W.npcs) do if n.p.met and n.role ~= "family" then list[#list + 1] = n end end
  table.sort(list, function(a, b) return a.p.f > b.p.f end)
  for _, n in ipairs(list) do
    local tag = n.p.f > 50 and "close friend" or n.p.f > 20 and "friend" or n.p.f > -10 and "acquaintance" or "enemy"
    if W.p.partner == n.id then tag = "going out" end
    rows[#rows + 1] = { text = NPCGen.name(n) .. " - " .. Dialog.roleLine(n) .. " (" .. tag .. ")", act = function() Menu.person(n) end }
  end
  if #rows == 0 then rows[1] = { text = "You haven't met anyone yet." } end
  return rows
end

B.RUMORS = function()
  local rows = {}
  for _, rm in ipairs(W.rumors) do
    if W.p.knownRumors[rm.id] then
      rows[#rows + 1] = { text = (rm.lore and "[myth] " or "") .. rm.txt, act = function() Say(rm.txt .. ". (About " .. rm.n .. " people have heard this.)") end }
    end
  end
  for _, sc in ipairs(W.p.secrets or {}) do
    local n = W.npcs[sc.npc]
    rows[#rows + 1] = { text = "[secret] " .. n.first .. " " .. sc.txt, act = function() Say(NPCGen.name(n) .. " " .. sc.txt .. ".") end }
  end
  -- what people are saying about you
  local about = 0
  for _, rm in ipairs(W.rumors) do if rm.about == -1 then about = about + rm.n end end
  table.insert(rows, 1, { text = "People talking about you: ~" .. about, hdr = true })
  if #rows == 1 then rows[2] = { text = "Ask people for gossip. Sit on benches and listen." } end
  return rows
end

B.NEWS = function()
  local rows = {}
  for i = #W.timeline, 1, -1 do
    local e = W.timeline[i]
    rows[#rows + 1] = { text = Clock.shortDate(Clock.day(e.t)) .. "  " .. e.txt, act = function()
      Say(Clock.dateStr(Clock.day(e.t)) .. ", " .. Clock.hhmm(Clock.minute(e.t)) .. ". " .. e.txt) end, imp = e.imp }
    if #rows > 300 then break end
  end
  return rows
end

B.MALL = function()
  local rows = {}
  local function hdr(t) rows[#rows + 1] = { text = t, hdr = true } end
  hdr(W.mall.name .. " — opened " .. W.mall.opened .. " — " .. (W.mall.population or #W.npcs) .. " regulars")
  hdr("NOW PLAYING (CINEPLEX)")
  for i, id in ipairs(W.cinema.screens) do
    local m = W.movies[id]
    rows[#rows + 1] = { text = i .. ". " .. m.title .. " (" .. m.rating .. ", " .. m.genre .. ")" .. (W.p.stats.movies[id] and "  [seen]" or ""),
      act = function() Say(m.title .. ". Starring " .. m.star .. ". \"" .. m.tag .. "\"") end }
  end
  hdr("TOP 10 ALBUMS")
  for i, id in ipairs(W.music.chart) do
    local a = W.music.albums[id]
    rows[#rows + 1] = { text = i .. ". " .. Content.albumName(W.music, a) .. " (" .. W.music.bands[a.band].genre .. ")" }
  end
  hdr("ARCADE RECORDS")
  for _, g in ipairs(Content.ARCADE_GAMES) do
    local b = W.arcade.scores[g.key]
    rows[#rows + 1] = { text = g.name .. ": " .. (b[1] and (b[1].i .. " " .. b[1].s) or "-"), act = function() Play.scores(g.key) end }
  end
  hdr("TRENDS")
  for _, t in ipairs(Trends.describe()) do rows[#rows + 1] = { text = t } end
  hdr("DIRECTORY")
  local list = {}
  for _, s in ipairs(W.stores) do if s.open then list[#list + 1] = s end end
  table.sort(list, function(a, b) return a.name < b.name end)
  for _, s in ipairs(list) do
    local where = s.row == "fc" and "Food Court" or (s.floor == 1 and "Lower" or "Upper")
    local open = Stores.isOpenAt(s, W.t) and "open" or "closed"
    rows[#rows + 1] = { text = s.name .. " — " .. MallGen.TYPE_LABEL[s.type] .. ", " .. where .. " (" .. open .. ")" ..
      (s.hiring and " HIRING" or "") .. (s.closing and " CLOSING" or "") .. (s.sale > 0 and (" " .. s.sale .. "% off") or ""),
      act = function() Menu.store(s) end }
  end
  return rows
end

B.LORE = function()
  local rows = {}
  rows[1] = { text = "Mall secrets found: " .. Lore.count() .. " of " .. Lore.total(), hdr = true }
  for _, k in ipairs(U.keys(W.p.lore)) do
    local title, txt = Lore.noteText(k)
    rows[#rows + 1] = { text = title, act = function() Say({ title:upper(), txt }) end }
  end
  if Lore.count() == 0 then rows[2] = { text = "The mall has layers. Listen to the old-timers." } end
  return rows
end

B.SAVE = function()
  return {
    { text = "Save", act = function() Save.write(); Say("Saved.") end },
    { text = "Save and quit to title", act = function() Save.write(); Title.start() end },
    { text = "Controls: D-pad walk, A talk/use, B menu. Crank: pager, racks, dials." },
  }
end

local ms = { overlay = false }

function Menu.open(tab)
  local s = setmetatable({ tab = 1, sel = 1, top = 1, crank = Input.crankStepper(24) }, { __index = ms })
  if tab then for i, t in ipairs(TABS) do if t == tab then s.tab = i end end end
  s:rebuild()
  Scene.push(s)
end

function ms:rebuild()
  self.rows = B[TABS[self.tab]]()
  self.sel = U.clamp(self.sel, 1, math.max(1, #self.rows))
end

function ms:resume() self:rebuild() end

function ms:update()
  if In.left then self.tab = (self.tab - 2) % #TABS + 1; self.sel = 1; self.top = 1; self:rebuild(); Sfx.tick() end
  if In.right then self.tab = self.tab % #TABS + 1; self.sel = 1; self.top = 1; self:rebuild(); Sfx.tick() end
  local st = self.crank(In.crank)
  if In.ur then st = st - 1 end
  if In.dr then st = st + 1 end
  if st ~= 0 then self.sel = U.clamp(self.sel + st, 1, math.max(1, #self.rows)) end
  local vis = 9
  if self.sel < self.top then self.top = self.sel end
  if self.sel >= self.top + vis then self.top = self.sel - vis + 1 end
  if In.a then
    local r = self.rows[self.sel]
    if r and r.act then r.act() end
  elseif In.b then
    Scene.pop()
  end
end

function ms:draw()
  Gfx.clear("black")
  -- tabs
  local x = 2
  for i, t in ipairs(TABS) do
    local w = Gfx.textW(t, true) + 10
    if i == self.tab then Gfx.fill(x, 2, w, 18, "white"); Gfx.text(t, x + 5, 3, { bold = true })
    else Gfx.text(t, x + 5, 3, { white = true }) end
    x = x + w + 1
  end
  Gfx.box(0, 22, 400, 218, "light")
  local vis = 9
  for i = self.top, math.min(#self.rows, self.top + vis - 1) do
    local r = self.rows[i]
    local y = 30 + (i - self.top) * 22
    if i == self.sel then Gfx.fill(8, y - 1, 384, 21, "black") end
    local white = i == self.sel
    Gfx.text(fit(r.text, 370), 14, y + 1, { white = white, bold = r.hdr or (r.imp and r.imp >= 3) })
  end
  if self.top > 1 then Gfx.tri(386, 26, "up") end
  if self.top + vis - 1 < #self.rows then Gfx.tri(386, 230, "down") end
end

function Menu.itemAction(it)
  local p = W.p
  local opts, acts = { "Look" }, { function()
    local d = it.n .. ". " .. (it.v and it.v > 0 and ("Worth about " .. U.money(it.v) .. ". ") or "")
    if it.from == "stolen" then d = d .. "You didn't pay for this. You know that." end
    if it.borrowed then d = d .. "Borrowed from " .. W.npcs[it.borrowed].first .. "." end
    Say(d)
  end }
  if it.k == "food" then
    opts[#opts + 1] = "Eat"; acts[#acts + 1] = function()
      U.removeValue(p.inv, it); p.hunger = U.clamp(p.hunger - (it.food or 25), 0, 100); Say("Mm.")
    end
  end
  if it.k == "album" then
    opts[#opts + 1] = "Listen on your Walkman"; acts[#acts + 1] = function()
      p.conf = U.clamp(p.conf + 2, 0, 100); p.energy = U.clamp(p.energy + 3, 0, 100)
      Say("You put it on and walk slower, like you're in a music video.")
    end
  end
  if it.k ~= "gear" and it.k ~= "key" then
    opts[#opts + 1] = "Throw away"; acts[#acts + 1] = function() U.removeValue(p.inv, it); Say("Gone.") end
  end
  Choose(it.n:sub(1, 30), opts, function(i) acts[i]() end, {})
end

function Menu.person(n)
  local lines = {}
  lines[#lines + 1] = NPCGen.name(n) .. ", " .. n.age .. ". " .. Dialog.roleLine(n) .. ". Lives in " .. n.home .. "."
  lines[#lines + 1] = "Right now: " .. NPCAI.describe(n) .. "."
  local p = n.p
  lines[#lines + 1] = string.format("Friendship %d, trust %d%s%s.", math.floor(p.f), math.floor(p.t),
    Talk.romanceOK(n) and (", crush " .. math.floor(p.a)) or "", p.an > 20 and (", annoyed " .. math.floor(p.an)) or "")
  local rel = {}
  if n.partner and n.partner > 0 and W.npcs[n.partner] then rel[#rel + 1] = "going out with " .. W.npcs[n.partner].first end
  local friends = 0
  for _, r in pairs(n.rel) do if r.f > 40 then friends = friends + 1 end end
  rel[#rel + 1] = friends .. " close friends"
  if n.taste then rel[#rel + 1] = "into " .. n.taste end
  lines[#lines + 1] = U.cap(table.concat(rel, ", ")) .. "."
  for i = #n.mem, 1, -1 do
    local m = n.mem[i]
    if m.s == -1 then lines[#lines + 1] = "They remember: " .. m.txt .. " (" .. Clock.shortDate(m.d) .. ")." break end
  end
  Say(lines, { npc = n, name = n.first })
end

function Menu.store(s)
  local o, c = Stores.hours(s, Clock.day(W.t))
  local m = s.mgr and W.npcs[s.mgr]
  local lines = {
    s.name .. " — " .. MallGen.TYPE_LABEL[s.type] .. ". Owned by " .. s.company .. ".",
    (o and ("Hours today " .. Clock.hhmm(o) .. "-" .. Clock.hhmm(c) .. ". ") or "Closed today. ") .. "Crowd: " .. s.demo .. ".",
    "Manager: " .. (m and NPCGen.name(m) or "vacant") .. ". Staff: " .. #s.emp .. ". " .. s.flavor,
  }
  Say(lines)
end
