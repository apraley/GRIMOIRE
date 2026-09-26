-- The deepest layer: the combination lock, the model, the ledger.

Secret = {}

-- 4-digit combination dial, turned with the crank
function Secret.combo()
  local p = W.p
  local sc = { digits = { 0, 0, 0, 0 }, pos = 1, crank = Input.crankStepper(36), shake = 0 }
  function sc:update()
    local st = self.crank(In.crank)
    if In.ur then st = st + 1 end
    if In.dr then st = st - 1 end
    if st ~= 0 then self.digits[self.pos] = (self.digits[self.pos] + st) % 10; Sfx.tick() end
    if In.left then self.pos = math.max(1, self.pos - 1) end
    if In.right then self.pos = math.min(4, self.pos + 1) end
    if self.shake > 0 then self.shake = self.shake - 1 end
    if In.a then
      local code = table.concat({ self.digits[1], self.digits[2], self.digits[3], self.digits[4] })
      if code == W.mall.combo then
        Sfx.ok()
        Scene.pop()
        p.keys.lock = true
        Say("CLICK. The bolt slides back. Behind the door, a light is already on.", { after = function()
          Explore.go("lock", 4 * 16 + 8, 6 * 16 + 12)
        end })
      else
        Sfx.bad()
        self.shake = 10
      end
    elseif In.b then Scene.pop() end
  end
  function sc:draw()
    Gfx.clear("black")
    Gfx.box(60, 30, 280, 180, "dark")
    Gfx.text("A STEEL DOOR. A 4-DIGIT DIAL.", 200, 42, { white = true, bold = true, align = "center" })
    local sx = (self.shake % 2 == 0) and 0 or 4
    for i = 1, 4 do
      local x = 100 + (i - 1) * 52 + sx
      Gfx.fill(x, 90, 40, 56, "white")
      Gfx.rect(x + 2, 92, 36, 52)
      Gfx.text(tostring(self.digits[i]), x + 20, 108, { bold = true, align = "center" })
      Gfx.text(tostring((self.digits[i] + 9) % 10), x + 20, 76, { white = true, align = "center" })
      Gfx.text(tostring((self.digits[i] + 1) % 10), x + 20, 150, { white = true, align = "center" })
      if i == self.pos then Gfx.tri(x + 16, 172, "up", true) end
    end
    Gfx.text("Crank: turn   <>: wheel   A: try   B: leave", 200, 188, { white = true, align = "center" })
  end
  Scene.push(sc)
end

-- the model of the mall, perfectly current
function Secret.model()
  Lore.discover("model")
  local sc = { t = 0 }
  function sc:update()
    self.t = self.t + 1
    if In.a or In.b then
      Scene.pop()
      local title, txt = Lore.noteText("model")
      Say({ txt, "The unlabeled storefront in the model has a tiny hand-painted sign: " .. Lore.prophecy() .. ".",
        "In the food court of the model, there is a figure sitting alone at a table. It has a little backpack." })
    end
  end
  function sc:draw()
    Secret.schematic("THE MODEL", true)
  end
  Scene.push(sc)
end

-- schematic of both floors. model=true: the uncanny version (lights flicker,
-- the next tenant already glows); otherwise the public directory map.
function Secret.schematic(title, model)
  do
    Gfx.clear("black")
    Gfx.text(title, 200, 4, { white = true, bold = true, align = "center" })
    local w = W.mall.w
    local sx = 392 / w
    for f = 1, 2 do
      local y0 = f == 1 and 150 or 40
      Gfx.fill(4, y0, 392, 70, "darker")
      Gfx.rect(4, y0, 392, 70, "white")
      for _, sl in ipairs(W.slots) do
        if (sl.floor == f or sl.row == "west" or sl.row == "east") and sl.kind ~= "gap" and sl.kind ~= "wall" then
          local x = 4 + sl.x * sx
          local ww = math.max(2, sl.w * sx - 1)
          local yy = (sl.row == "bot") and (y0 + 50) or y0 + 4
          local hh = (sl.row == "west" or sl.row == "east") and 62 or 16
          local s = sl.store and W.stores[sl.store]
          if s and s.open then
            if not model or (Gfx.frame // 20 + sl.id) % 17 ~= 0 then Gfx.fill(x, yy, ww, hh, "white") else Gfx.fill(x, yy, ww, hh, "light") end
          elseif sl.coming and model then
            Gfx.fill(x, yy, ww, hh, (Gfx.frame // 10) % 2 == 0 and "gray" or "dark")
          else
            Gfx.rect(x, yy, ww, hh, "white")
          end
        end
      end
      local lbl = f == 1 and "LOWER" or "UPPER"
      Gfx.fill(4, y0 - 17, Gfx.textW(lbl, true) + 8, 16, "black")
      Gfx.text(lbl, 8, y0 - 17, { white = true, bold = true })
    end
    if model then
      -- tiny figures: everyone currently in the mall
      local count = 0
      for _, list in pairs(NPCAI.byArea) do count = count + #list end
      Gfx.text(count .. " tiny figures", 200, 120, { white = true, align = "center" })
    else
      -- YOU ARE HERE
      local p = W.p
      local f, px
      if p.area == "c1" or p.area == "c2" then f = tonumber(p.area:sub(2)); px = p.x / 16
      else
        local num = p.area:match("^s(%d+)$")
        local s = num and W.stores[tonumber(num)]
        if s and s.x then f = s.floor; px = s.x + (s.w or 4) / 2 end
        if p.area == "fc" then f = 2; px = W.mall.court0 + 9 end
      end
      if f then
        local y0 = f == 1 and 150 or 40
        local x = 4 + px * sx
        if (Gfx.frame // 8) % 2 == 0 then Gfx.circle(x, y0 + 35, 5, true, "white") end
        Gfx.text("YOU ARE HERE", x, y0 + 38, { white = true, align = "center", bold = true })
      end
      Gfx.text("Food court + Cineplex: upstairs, center.  Exit: downstairs, center.", 200, 222, { white = true, align = "center" })
    end
  end
end

-- the janitor's ledger: the world's own memory, handwritten
function Secret.ledger()
  Lore.discover("ledger")
  local rows = {}
  for i = #W.timeline, 1, -1 do
    local e = W.timeline[i]
    if e.cat == "store" or e.cat == "mall" or e.imp >= 3 then rows[#rows + 1] = Clock.shortDate(Clock.day(e.t)) .. " " .. e.txt end
  end
  local tomorrow = Clock.day(W.t) + 1
  table.insert(rows, 1, Clock.shortDate(tomorrow) .. " (already written) " .. Secret.tomorrow())
  local labels = {}
  for i = 1, math.min(#rows, 60) do labels[i] = rows[i]:sub(1, 48) end
  Choose("THE LEDGER", labels, function(i) Say(rows[i]) end, { x = 4, w = 392, y = 28, visible = 9 })
end

-- the ledger's entry for tomorrow: the next scheduled thing it can know
function Secret.tomorrow()
  for _, sl in ipairs(W.slots) do
    if sl.coming then return "COMING SOON sign comes down. " .. MallGen.TYPE_LABEL[sl.coming.type] .. " opens " .. Clock.shortDate(sl.coming.day) .. "." end
  end
  for _, s in ipairs(W.stores) do
    if s.closing then return s.name .. " closes " .. Clock.shortDate(s.closing) .. "." end
  end
  return "The kid comes back. They always come back."
end
