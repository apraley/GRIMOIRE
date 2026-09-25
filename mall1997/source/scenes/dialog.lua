-- NPC conversation UI: portrait, name/role card, relationship readout and
-- the choice menu. Outcomes come from sim/talk.lua.

Dialog = {}

local function roleLine(n)
  if n.job and type(n.job) == "number" then
    local s = W.stores[n.job]
    return (n.title == "manager" and "Manager, " or "") .. s.name
  end
  if n.job == "sec" then return n.title == "chief" and "Chief of Security" or "Mall Security" end
  if n.job == "maint" then return n.title == "night janitor" and "Night Janitor" or "Maintenance" end
  if n.job == "mgmt" then return U.cap(n.title or "mall office") end
  if n.age < 19 then return (n.clique and U.cap(n.clique) .. ", " or "") .. (n.school or "") end
  if n.role == "walker" then return "Mall walker" end
  return U.cap(n.role)
end
Dialog.roleLine = roleLine

local function hearts(v) -- -100..100 -> text meter
  local k = math.floor((v + 100) / 40)
  return string.rep("#", U.clamp(k, 0, 5)) .. string.rep(".", 5 - U.clamp(k, 0, 5))
end

-- the card at the top: name, role, what we know
local card = { overlay = true }
function card:draw()
  local n = self.n
  Gfx.box(0, 0, 400, 62, "dark")
  Gfx.text(NPCGen.name(n) .. "  (" .. n.age .. ")", 14, 8, { white = true, bold = true })
  Gfx.text(roleLine(n), 14, 30, { white = true })
  local p = n.p
  Gfx.text("FRIEND " .. hearts(p.f), 250, 8, { white = true })
  Gfx.text("TRUST  " .. hearts(p.t), 250, 22, { white = true })
  if Talk.romanceOK(n) then Gfx.text("CRUSH  " .. hearts(p.a * 2 - 100), 250, 36, { white = true }) end
  if p.an > 30 then Gfx.text("ANNOYED", 180, 44, { white = true, bold = true }) end
  if p.fe > 30 then Gfx.text("SCARED", 110, 44, { white = true, bold = true }) end
end
function card:update() end

function Dialog.open(n)
  if n.hunting then return end
  local c = setmetatable({ n = n, overlay = true }, { __index = card })
  Dialog.card = c
  Scene.push(c)
  local greet = Talk.greet(n)
  if n.act == "work" and type(n.job) == "number" then n.idleDir = "down" end
  Say(greet, { npc = n, name = n.first, after = function() Dialog.menu(n) end })
end

function Dialog.close()
  if Scene.top() == Dialog.card then Scene.pop() end
  Dialog.card = nil
end

function Dialog.menu(n)
  local opts = Talk.options(n)
  local labels = {}
  for i, o in ipairs(opts) do labels[i] = o.label end
  Choose(nil, labels, function(i)
    local id = opts[i].id
    Dialog.run(n, id)
  end, { cancel = Dialog.close, x = 236, y = 66, w = 160, visible = 7 })
end

local function respond(n, out, back)
  local lines = out.lines
  if #lines == 0 then lines = { "..." } end
  WorldSim.tick(1)
  Say(lines, { npc = n, name = n.first, mood = out.mood, after = function()
    if back ~= false then Dialog.menu(n) else Dialog.close() end
  end })
end

function Dialog.run(n, id)
  if id == "bye" then
    respond(n, Talk.act(n, "bye"), false)
  elseif id == "give" then
    local items = {}
    for _, it in ipairs(W.p.inv) do if it.k ~= "gear" then items[#items + 1] = it end end
    if #items == 0 then respond(n, { lines = { "You don't have anything to give." } }) return end
    local labels = {}
    for i, it in ipairs(items) do labels[i] = Econ.itemLabel(it) end
    Choose("GIVE", labels, function(i) respond(n, Talk.give(n, items[i])) end, { cancel = function() Dialog.menu(n) end })
  elseif id == "borrow" then
    local labels = {}
    for i, it in ipairs(n.poss) do labels[i] = it.n end
    Choose("BORROW", labels, function(i) respond(n, Talk.borrow(n, i)) end, { cancel = function() Dialog.menu(n) end })
  elseif id == "lend" then
    respond(n, Talk.lend(n))
  elseif id == "tell" then
    local entries, labels = {}, {}
    for _, rm in ipairs(W.rumors) do
      if W.p.knownRumors[rm.id] and rm.about ~= n.id then
        entries[#entries + 1] = { rumor = rm }; labels[#labels + 1] = rm.txt:sub(1, 40)
      end
    end
    for _, sc in ipairs(W.p.secrets or {}) do
      if sc.npc ~= n.id and not sc.told then
        entries[#entries + 1] = { secret = sc }; labels[#labels + 1] = "SECRET: " .. W.npcs[sc.npc].first .. " " .. sc.txt:sub(1, 26)
      end
    end
    if #entries == 0 then respond(n, { lines = { "You don't know any gossip. Ask around first." } }) return end
    Choose("TELL", labels, function(i)
      if entries[i].secret then entries[i].secret.told = true end
      respond(n, Talk.tell(n, entries[i]))
    end, { cancel = function() Dialog.menu(n) end, w = 390, x = 5 })
  elseif id == "job" then
    Dialog.interview(n, n.job)
  elseif id == "challenge" then
    Dialog.close()
    Play.challenge(n)
  elseif id == "secjob" then
    Dialog.interview(n, "sec")
  elseif id == "hours" then
    W.p.job.moreHours = not W.p.job.moreHours
    respond(n, { lines = { W.p.job.moreHours and "More hours? Sure, I'll put you down for extra next week." or "Fine. Fewer shifts starting next week." } })
  elseif id == "quit" then
    Confirm("Really quit " .. Jobs.placeName() .. "?", function()
      Jobs.lose("quit")
      n.p.t = n.p.t - 5
      respond(n, { lines = { "Well. Turn in your name tag on the way out." }, mood = "sad" }, false)
    end, function() Dialog.menu(n) end, { npc = n })
  else
    local out = Talk.act(n, id)
    respond(n, out, id ~= "insult" and not out.companion)
  end
end

-- three-question job interview
function Dialog.interview(n, storeId)
  local ok, why = Jobs.canApply(storeId)
  if not ok then respond(n, { lines = { why } }) return end
  local qs = {}
  local r = U.rng(W.seed, "iv", n.id, Clock.day(W.t))
  local pool = {}
  for i = 1, #Jobs.INTERVIEW do pool[i] = Jobs.INTERVIEW[i] end
  r:shuffle(pool)
  for i = 1, 3 do qs[i] = pool[i] end
  local pts = 0
  local function ask(i)
    if i > #qs then
      local hired, score = Jobs.decide(storeId, pts)
      if hired then
        Say({ "\"Okay. You're hired. Don't make me regret it.\"", "You start this week. Check your pager for shifts." },
          { npc = n, name = n.first, mood = "happy", after = Dialog.close })
      else
        Say({ "\"We'll keep your application on file.\"", "(They will not keep your application on file.)" },
          { npc = n, name = n.first, after = Dialog.close })
        W.p.conf = U.clamp(W.p.conf - 5, 0, 100)
      end
      return
    end
    local q = qs[i]
    local labels = {}
    for k, a in ipairs(q.a) do labels[k] = a[1] end
    Choose(nil, labels, function(k)
      pts = pts + q.a[k][2]
      ask(i + 1)
    end, { prompt = "\"" .. q.q .. "\"", npc = n, x = 6, w = 388, y = 42 })
  end
  ask(1)
end
