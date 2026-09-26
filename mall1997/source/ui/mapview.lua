-- Area renderer. The static layer (tiles, storefronts, signs) is drawn once
-- into an image when an area is entered or invalidated; dynamic overlays
-- (neon flicker, water, escalator steps, closed grilles, decorations) are
-- drawn each frame for what's on screen.

MapView = {}
local gfx = playdate.graphics
local T = MallGen.TILE
local A = Areas

MapView.img = nil
MapView.areaId = nil
MapView.version = -1
Areas.version = Areas.version or 0
local oldInvalidate = Areas.invalidate
function Areas.invalidate(id)
  oldInvalidate(id)
  Areas.version = (Areas.version or 0) + 1
end

local function pat(name) gfx.setPattern(Gfx.P[name]) end
local function black() gfx.setColor(gfx.kColorBlack) end
local function white() gfx.setColor(gfx.kColorWhite) end

local function tile(a, code, x, y)
  local px, py = x * T, y * T
  if code == A.FLOOR then
    white(); gfx.fillRect(px, py, T, T)
    black(); gfx.drawPixel(px, py)
    if (x + y) % 3 == 0 then gfx.drawPixel(px + 8, py + 8) end
    if a.kind == "concourse" and (y == 8 or y == 9) then
      -- terrazzo runner down the middle of the concourse
      pat("lighter"); gfx.fillRect(px, py, T, T); black()
      if y == 8 then gfx.drawLine(px, py, px + T - 1, py) else gfx.drawLine(px, py + T - 1, px + T - 1, py + T - 1) end
      if x % 4 == 0 then gfx.drawRect(px + 5, py + 5, 6, 6) end
    end
  elseif code == A.TILE2 then
    if (x + y) % 2 == 0 then pat("lighter") else white() end
    gfx.fillRect(px, py, T, T)
    black(); gfx.drawLine(px, py, px + T - 1, py); gfx.drawLine(px, py, px, py + T - 1)
    white(); gfx.drawLine(px + 1, py + 1, px + T - 2, py + 1)
  elseif code == A.CARPET then
    pat("carpet"); gfx.fillRect(px, py, T, T)
  elseif code == A.WALL then
    pat("dark"); gfx.fillRect(px, py, T, T)
    black(); gfx.drawLine(px, py + T - 1, px + T - 1, py + T - 1)
  elseif code == A.FACADE then
    pat("brick"); gfx.fillRect(px, py, T, T)
  elseif code == A.WINDOW then
    white(); gfx.fillRect(px, py, T, T)
    pat("diag"); gfx.fillRect(px + 2, py + 2, T - 4, T - 4)
    black(); gfx.drawRect(px, py, T, T)
  elseif code == A.PAPERED then
    pat("lighter"); gfx.fillRect(px, py, T, T)
    black(); gfx.drawRect(px, py, T, T); gfx.drawLine(px + 3, py + 3, px + 12, py + 12)
  elseif code == A.PLANTER then
    pat("gray"); gfx.fillRect(px, py, T, T)
    black(); gfx.drawRect(px, py, T, T)
    gfx.fillCircleAtPoint(px + 5, py + 6, 4); gfx.fillCircleAtPoint(px + 11, py + 9, 4)
    white(); gfx.drawPixel(px + 4, py + 5); gfx.drawPixel(px + 10, py + 8)
  elseif code == A.BENCH then
    white(); gfx.fillRect(px, py, T, T)
    black(); gfx.fillRect(px + 1, py + 4, T - 2, 3); gfx.fillRect(px + 1, py + 9, T - 2, 3)
    gfx.fillRect(px + 2, py + 12, 2, 3); gfx.fillRect(px + T - 4, py + 12, 2, 3)
  elseif code == A.FOUNTAIN then
    pat("wave"); gfx.fillRect(px, py, T, T)
  elseif code == A.ESC then
    white(); gfx.fillRect(px, py, T, T)
    black(); for i = 0, 3 do gfx.drawLine(px, py + i * 4, px + T - 1, py + i * 4) end
    gfx.drawLine(px, py, px, py + T - 1); gfx.drawLine(px + T - 1, py, px + T - 1, py + T - 1)
  elseif code == A.VOID then
    pat("darker"); gfx.fillRect(px, py, T, T)
  elseif code == A.COUNTER then
    pat("light"); gfx.fillRect(px, py, T, 6)
    black(); gfx.fillRect(px, py + 6, T, T - 6); gfx.drawLine(px, py, px + T - 1, py)
    white(); gfx.drawLine(px, py + 8, px + T - 1, py + 8)
  elseif code == A.RACK then
    white(); gfx.fillRect(px, py, T, T)
    black(); gfx.drawLine(px, py + 3, px + T - 1, py + 3)
    for i = 1, T - 2, 3 do gfx.fillRect(px + i, py + 4, 2, 9) end
  elseif code == A.SHELF then
    black(); gfx.fillRect(px, py, T, T)
    white(); for i = 1, T - 2, 3 do gfx.fillRect(px + i, py + 2 + (i % 4), 2, 10 - (i % 4)) end
  elseif code == A.TABLE then
    white(); gfx.fillRect(px, py, T, T)
    black(); gfx.drawRoundRect(px + 1, py + 2, T - 2, T - 5, 3)
    pat("gray"); gfx.fillRect(px + 2, py + 12, T - 4, 2); black()
  elseif code == A.DOOR then
    pat("gray"); gfx.fillRect(px, py, T, T)
    black(); gfx.drawRect(px, py, T, T)
  elseif code == A.LOCKDOOR then
    black(); gfx.fillRect(px, py, T, T)
    white(); gfx.drawRect(px + 2, py + 2, T - 4, T - 2); gfx.fillRect(px + 6, py + 7, 4, 4)
  elseif code == A.ASPHALT then
    pat("asphalt"); gfx.fillRect(px, py, T, T)
    if y % 5 == 4 then white(); gfx.fillRect(px, py + 14, T, 2) end
  elseif code == A.CAR then
    pat("asphalt"); gfx.fillRect(px, py, T, T)
  elseif code == A.DARK then
    black(); gfx.fillRect(px, py, T, T)
  elseif code == A.CAB then
    -- upright cabinet: marquee, screen, control panel, white trim
    white(); gfx.fillRect(px, py - 14, T, T + 14)
    black(); gfx.fillRect(px + 1, py - 13, T - 2, T + 12)
    white(); gfx.fillRect(px + 3, py - 4, T - 6, 8)
    black(); gfx.fillRect(px + 5, py - 2, T - 10, 4)
    white(); gfx.fillRect(px + 2, py + 7, T - 4, 3)
    black(); gfx.drawPixel(px + 5, py + 8); gfx.drawPixel(px + 10, py + 8)
  elseif code == A.STAGE then
    pat("hstripe"); gfx.fillRect(px, py, T, T)
  elseif code == A.CRATE then
    white(); gfx.fillRect(px, py, T, T)
    black(); gfx.drawRect(px + 1, py + 1, T - 2, T - 2); gfx.drawLine(px + 1, py + 1, px + T - 2, py + T - 2)
    gfx.drawLine(px + T - 2, py + 1, px + 1, py + T - 2)
  elseif code == A.PIPE then
    pat("gray"); gfx.fillRect(px, py + 4, T, 8); black(); gfx.drawRect(px, py + 4, T, 8)
  elseif code == A.HVAC then
    pat("light"); gfx.fillRect(px, py, T, T); black(); gfx.drawRect(px, py, T, T)
    gfx.drawCircleAtPoint(px + 8, py + 8, 5)
  elseif code == A.SKY then
    pat("lighter"); gfx.fillRect(px, py, T, T); black(); gfx.drawRect(px, py, T, T)
    gfx.drawLine(px, py + 8, px + T, py + 8); gfx.drawLine(px + 8, py, px + 8, py + T)
  elseif code == A.KIOSK then
    white(); gfx.fillRect(px, py, T, T)
    black(); gfx.drawRect(px, py, T, T)
    pat("vstripe"); gfx.fillRect(px + 1, py + 1, T - 2, 5); black()
  elseif code == A.DESK then
    pat("gray"); gfx.fillRect(px, py + 2, T, T - 4); black(); gfx.drawRect(px, py + 2, T, T - 4)
  elseif code == A.DUST then
    white(); gfx.fillRect(px, py, T, T)
    black(); gfx.drawPixel(px + (x * 7) % 16, py + (y * 5) % 16); gfx.drawPixel(px + (x * 3) % 16, py + (y * 11) % 16)
    gfx.drawPixel(px + (x * 13) % 16, py + (y * 3) % 16)
  elseif code == A.LOUD then
    -- arcade / cinema carpet: dark with stars and squiggles
    black(); gfx.fillRect(px, py, T, T)
    white()
    local h = (x * 7 + y * 13) % 16
    gfx.drawPixel(px + h, py + (h * 3) % 16)
    if (x + y) % 3 == 0 then gfx.drawLine(px + 3, py + 10, px + 6, py + 7); gfx.drawLine(px + 6, py + 7, px + 9, py + 10) end
    if (x * 5 + y) % 7 == 0 then gfx.fillRect(px + 11, py + 3, 2, 2) end
    black()
  elseif code == A.GRATE then
    pat("grate"); gfx.fillRect(px, py, T, T)
  else
    white(); gfx.fillRect(px, py, T, T)
  end
  black()
end

local NEON_TYPES = { music = true, arcade = true, cinema = true, food = true, video = true, games = true, restaurant = true }
MapView.NEON_TYPES = NEON_TYPES

local function fitText(s, w, bold)
  if Gfx.textW(s, bold ~= false) <= w then return s end
  while #s > 1 and Gfx.textW(s .. ".", bold ~= false) > w do s = s:sub(1, #s - 1) end
  s = s:gsub("%s+$", "")
  return s .. "."
end

-- split a name over up to two lines for narrow signs
local function signLines(s, w)
  if Gfx.textW(s, true) <= w then return { s }, true end
  if Gfx.textW(s) <= w then return { s }, false end
  local words = {}
  for wd in s:gmatch("%S+") do words[#words + 1] = wd end
  if #words == 1 then return { fitText(s, w, false) }, false end
  local best, bi = 1e9, 1
  for i = 1, #words - 1 do
    local l1 = table.concat(words, " ", 1, i)
    local l2 = table.concat(words, " ", i + 1)
    local d = math.max(Gfx.textW(l1), Gfx.textW(l2))
    if d < best then best, bi = d, i end
  end
  return { fitText(table.concat(words, " ", 1, bi), w, false), fitText(table.concat(words, " ", bi + 1), w, false) }, false
end
MapView.signLines = signLines

-- little products in a shop window
local function windowDisplay(typ, px, py, w, seed)
  local r = U.rng(seed)
  for i = 0, (w // 20) - 1 do
    local x = px + 6 + i * 20 + r:i(0, 4)
    local y = py + 4
    if typ == "clothing" or typ == "department" or typ == "shoes" then
      black(); gfx.drawLine(x + 5, y, x + 5, y + 2); gfx.fillRect(x + 1, y + 3, 9, 8)
      white(); gfx.fillRect(x + 3, y + 5, 5, 4); black()
    elseif typ == "music" or typ == "video" or typ == "games" or typ == "books" then
      black(); gfx.drawRect(x, y + 1, 10, 10); gfx.fillRect(x + 2, y + 3, 6, 6)
    elseif typ == "jewelry" then
      black(); gfx.drawCircleAtPoint(x + 5, y + 6, 4); gfx.fillRect(x + 4, y + 1, 3, 2)
    elseif typ == "toys" or typ == "gifts" or typ == "weird" then
      black(); gfx.fillCircleAtPoint(x + 5, y + 7, 4); white(); gfx.drawPixel(x + 4, y + 6); gfx.drawPixel(x + 6, y + 6); black()
    elseif typ == "electronics" then
      black(); gfx.fillRect(x, y + 2, 11, 8); white(); gfx.fillRect(x + 2, y + 4, 7, 4); black()
    elseif typ == "sporting" then
      black(); gfx.drawCircleAtPoint(x + 5, y + 6, 4); gfx.drawLine(x + 1, y + 6, x + 9, y + 6)
    else
      black(); gfx.fillRect(x + 2, y + 2, 7, 9)
    end
  end
end

local function drawSign(a, o)
  local s = o.store and W.stores[o.store]
  local px, py = o.x * T, o.y * T
  local w = o.w * T
  if o.staffSign then
    black(); gfx.fillRect(px + 2, py + 4, w - 4, 12)
    Gfx.text("STAFF", px + w // 2, py + 3, { white = true, align = "center" })
    return
  end
  if o.text then
    black(); gfx.fillRect(px, py + 1, w, T - 2)
    Gfx.text(fitText(o.text, w - 4), px + w // 2, py, { white = true, align = "center", bold = true })
    return
  end
  if o.anchorEnd then
    local name = s and s.name or "COMING SOON"
    white(); gfx.fillRect(px + 8, py + 40, w - 16, 26)
    black(); gfx.drawRect(px + 8, py + 40, w - 16, 26); gfx.drawRect(px + 10, py + 42, w - 20, 22)
    Gfx.text(fitText(name, w - 24), px + w // 2, py + 44, { align = "center", bold = true })
    white(); gfx.fillRect(px + 8, py + 210, w - 16, 26)
    black(); gfx.drawRect(px + 8, py + 210, w - 16, 26)
    Gfx.text(fitText(name, w - 24), px + w // 2, py + 214, { align = "center", bold = true })
    return
  end
  local sl = o.slot and W.slots[o.slot]
  local label
  if s and s.open then label = s.name
  elseif sl and sl.abandoned then label = "COMING SOON"
  elseif sl and sl.coming then label = "COMING SOON"
  else label = "FOR LEASE" end
  if not o.top and a.id ~= "fc" then
    -- bottom-row roofs
    pat("dark"); gfx.fillRect(px, py + T * 2 + 8, w, T * 2 - 8); black()
  end
  local by = o.top and (py + T - 2) or (py + T + 4)
  if o.top == nil and a.id == "fc" then by = py + 2 end
  local lines, bold = signLines(label, w - 10)
  local sh = #lines == 1 and 20 or 34
  black(); gfx.fillRect(px + 2, by, w - 4, sh)
  white(); gfx.drawRect(px + 3, by + 1, w - 6, sh - 2)
  for i, l in ipairs(lines) do
    Gfx.text(l, px + w // 2, by + 2 + (i - 1) * 15, { white = true, align = "center", bold = bold })
  end
  o.signH = sh
  o.signY = by
  if o.top and s and s.open then windowDisplay(s.type, px + T, py + 4 * T, w - 2 * T, s.id) end
end

function MapView.render(a)
  local img = gfx.image.new(a.w * T, a.h * T, gfx.kColorWhite)
  gfx.pushContext(img)
  gfx.setDrawOffset(0, 0)
  for y = 0, a.h - 1 do
    for x = 0, a.w - 1 do
      tile(a, a.t[y * a.w + x + 1], x, y)
    end
  end
  -- objects with static art
  for _, o in ipairs(a.objs) do
    local px, py = o.x * T, o.y * T
    if o.kind == "sign" then drawSign(a, o)
    elseif o.kind == "car" then
      black(); gfx.fillRoundRect(px + 2, py + 2, o.w * T - 4, o.h * T - 4, 5)
      white(); gfx.fillRect(px + 6, py + 6, o.w * T - 12, 6); gfx.fillRect(px + 6, py + o.h * T - 12, o.w * T - 12, 5)
    elseif o.kind == "truck" then
      black(); gfx.fillRect(px, py, o.w * T, o.h * T)
      white(); gfx.drawRect(px + 3, py + 3, o.w * T - 6, o.h * T - 6)
      Gfx.text("FREIGHT", px + o.w * T // 2, py + 16, { white = true, align = "center" })
    elseif o.kind == "fountain" then
      black(); gfx.setLineWidth(3); gfx.drawRoundRect(px - 2, py - 2, o.w * T + 4, o.h * T + 4, 8); gfx.setLineWidth(1)
      white(); gfx.fillCircleAtPoint(px + o.w * T // 2, py + o.h * T // 2, 10)
      black(); gfx.drawCircleAtPoint(px + o.w * T // 2, py + o.h * T // 2, 10)
    elseif o.kind == "atrium" then
      black(); gfx.setLineWidth(2); gfx.drawRect(px - 1, py - 1, o.w * T + 2, o.h * T + 2); gfx.setLineWidth(1)
      for i = px, px + o.w * T, 6 do gfx.drawLine(i, py - 1, i, py + 3) end
    elseif o.kind == "stage" then
      black(); gfx.drawRect(px, py, o.w * T, o.h * T)
      Gfx.text("TEEN NIGHT", px + o.w * T // 2, py + 2, { align = "center", bold = true })
    elseif o.kind == "bus" then
      black(); gfx.fillRect(px, py - 8, 3, 24); gfx.fillRect(px - 8, py - 26, 34, 19)
      white(); gfx.drawRect(px - 7, py - 25, 32, 17); black()
      Gfx.text("BUS", px + 9, py - 25, { white = true, align = "center", bold = true })
    elseif o.kind == "phone" then
      black(); gfx.fillRect(px + 3, py + 1, 10, 14); white(); gfx.fillRect(px + 5, py + 3, 6, 4); black()
    elseif o.kind == "directory" then
      black(); gfx.fillRect(px, py - 4, o.w * T, T + 4)
      Gfx.text("MAP", px + o.w * T // 2, py - 2, { white = true, align = "center", bold = true })
    elseif o.kind == "model" then
      pat("light"); gfx.fillRect(px, py, o.w * T, o.h * T); black(); gfx.drawRect(px, py, o.w * T, o.h * T)
      for i = 0, 6 do gfx.fillRect(px + 4 + i * 15, py + 8, 10, 8); gfx.fillRect(px + 4 + i * 15, py + o.h * T - 16, 10, 8) end
    elseif o.kind == "poster" then
      black(); gfx.drawRect(px + 2, py, 12, 16); gfx.fillRect(px + 4, py + 2, 8, 6)
    elseif o.kind == "wallsign" then
      local s = W.stores[o.store]
      if s then
        local w = o.w * T
        local lines = signLines(s.name, w - 8)
        black(); gfx.fillRect(px - 4, py, w + 8, 16)
        white(); gfx.drawRect(px - 3, py + 1, w + 6, 14)
        Gfx.text(lines[1], px + w // 2, py - 1, { white = true, align = "center", bold = true })
      end
    elseif o.kind == "wallposter" then
      local r = U.rng(o.seed)
      white(); gfx.fillRect(px + 1, py + 1, 14, 14)
      black(); gfx.drawRect(px + 1, py + 1, 14, 14)
      gfx.setPattern(Gfx.P[r:pick({ "gray", "diag", "dots", "check" })]); gfx.fillRect(px + 3, py + 3, 10, 7); black()
      gfx.drawLine(px + 3, py + 12, px + 12, py + 12)
    elseif o.kind == "pipes" then
      pat("gray"); gfx.fillRect(px, py + 4, o.w * T, 6); black(); gfx.drawRect(px, py + 4, o.w * T, 6)
    end
  end
  -- stenciled labels over service doors and labelled doors
  if a.kind == "service" or a.kind == "back" or a.kind == "office" or a.kind == "maint" or a.kind == "dock"
    or a.kind == "tunnel" or a.kind == "shelter" then
    local done = {}
    for _, d in ipairs(a.doors) do
      local label = d.label
      if not label and d.store and W.stores[d.store] then label = W.stores[d.store].name:upper() end
      if label and label ~= "?" and not done[label .. d.y] then
        done[label .. d.y] = true
        local px, py = d.x * T + 8, d.y * T
        -- label sits on the wall side of the door
        local ty
        if d.y >= a.h // 2 then ty = py + T else ty = py - 14 end
        if ty < 0 then ty = py + T end
        if ty > a.h * T - 14 then ty = py - 14 end
        local lw = math.min(90, Gfx.textW(label) + 6)
        white(); gfx.fillRect(px - lw // 2, ty, lw, 14); black(); gfx.drawRect(px - lw // 2, ty, lw, 14)
        local l = label
        while #l > 2 and Gfx.textW(l) > lw - 6 do l = l:sub(1, #l - 1) end
        Gfx.text(l, px, ty - 2, { align = "center" })
      end
    end
  end
  -- cinema lobby: numbered theater doors
  if a.kind == "store" and a.store == W.mall.cinema then
    for _, o in ipairs(a.objs) do
      if o.kind == "screen" then
        local px, py = o.x * T, o.y * T
        white(); gfx.fillRect(px - 2, py + T + 1, 20, 14); black(); gfx.drawRect(px - 2, py + T + 1, 20, 14)
        Gfx.text(tostring(o.screen), px + 8, py + T - 1, { align = "center", bold = true })
      end
    end
  end
  gfx.popContext()
  return img
end

-- small LRU of rendered area images so hopping between the two concourse
-- floors (or a store and its floor) doesn't re-render every time
local rendered = {}   -- list of { id, version, img, area }
function MapView.prepare(areaId)
  if MapView.areaId == areaId and MapView.version == Areas.version and MapView.img then return MapView.area end
  local hit
  for i, e in ipairs(rendered) do
    if e.id == areaId and e.version == Areas.version then hit = table.remove(rendered, i) break end
  end
  if not hit then
    local a = Areas.build(areaId)
    hit = { id = areaId, version = Areas.version, img = MapView.render(a), area = a }
  end
  table.insert(rendered, 1, hit)
  while #rendered > 3 do table.remove(rendered) end
  MapView.img, MapView.areaId, MapView.version, MapView.area = hit.img, hit.id, hit.version, hit.area
  return MapView.area
end

-- dynamic overlays for the visible region
function MapView.drawDynamic(a, camx, camy)
  local x0, x1 = camx - T * 2, camx + 400 + T * 2
  local y0, y1 = camy - T * 2, camy + 240 + T * 2
  local f = Gfx.frame
  local day = Clock.day(W.t)
  for _, o in ipairs(a.objs) do
    local px, py = o.x * T, o.y * T
    local w, h = o.w * T, o.h * T
    if px + w >= x0 and px <= x1 and py + h >= y0 and py <= y1 then
      if o.kind == "sign" and o.store and not o.anchorEnd then
        local s = W.stores[o.store]
        if s and s.open then
          local open = Stores.isOpenAt(s, W.t)
          if NEON_TYPES[s.type] and open then
            local by = o.signY or (py + T)
            local sh = o.signH or 20
            -- buzzing neon frame
            gfx.setPattern(Gfx.NEON[1 + ((f // 3 + s.id) % #Gfx.NEON)])
            gfx.drawRect(px + 1, by - 1, w - 2, sh + 2); gfx.drawRect(px, by - 2, w, sh + 4)
            black()
            if ((f + s.id * 13) % 151) < 4 then Gfx.fill(px + 3, by + 1, w - 6, sh - 2, "darker") end
          end
          if not open and a.kind == "concourse" then
            -- security grille pulled down
            local gy = o.top and (py + 3 * T) or py
            gfx.setPattern(Gfx.P.vstripe)
            gfx.fillRect(px + 2, gy, w - 4, T * (o.top and 2 or 1))
            black()
          end
        end
      elseif o.kind == "fountain" then
        if W.mall.reno == "fountain" then
          Gfx.fill(px, py, w, h, "diag")
          Gfx.text("PARDON OUR DUST", px + w // 2, py + h // 2 - 8, { align = "center", bold = true })
        else
          gfx.setPattern(Gfx.P.wave, 0, (f // 4) % 8)
          gfx.fillRect(px + 2, py + 2, w - 4, h - 4)
          white(); gfx.fillCircleAtPoint(px + w // 2, py + h // 2, 10)
          black(); gfx.drawCircleAtPoint(px + w // 2, py + h // 2, 10)
          -- spray
          for i = 0, 5 do
            local ang = (i * 60 + f * 6) % 360
            local r = 6 + (f + i * 5) % 10
            gfx.drawPixel(px + w // 2 + math.floor(math.cos(math.rad(ang)) * r), py + h // 2 + math.floor(math.sin(math.rad(ang)) * r) - 4)
          end
        end
      elseif o.kind == "escalator" then
        local off = (f // 2) % 4
        white(); gfx.fillRect(px + 1, py, w - 2, h)
        black()
        for i = 0, h, 4 do
          local yy = py + ((i + (o.to == "c2" and -off or off)) % h)
          gfx.drawLine(px + 1, yy, px + w - 2, yy)
        end
        gfx.drawRect(px, py, w, h)
      elseif o.kind == "cab" then
        local m = W.arcade.machines[o.machine]
        if m and m.broken then
          Gfx.fill(px + 3, py - 4, w - 6, 8, "white")
          Gfx.line(px + 3, py - 4, px + w - 4, py + 3)
        else
          gfx.setPattern(Gfx.NEON[1 + ((f // 3 + o.machine) % #Gfx.NEON)])
          gfx.fillRect(px + 2, py - 12, w - 4, 5)
          -- attract-mode flicker on the screen
          if (f // 10 + o.machine) % 3 == 0 then Gfx.fill(px + 4, py - 3, w - 8, 6, "gray") end
          black()
        end
      elseif o.kind == "atrium" then
        gfx.setPattern(Gfx.P.wave, 0, (f // 6) % 8)
        gfx.fillRect(px + 16, py + 12, w - 32, h - 24)
        black()
      elseif o.kind == "camera" or (o.cam) then
        black(); gfx.fillCircleAtPoint(px + 8, py + 4, 4)
        if (f // 15) % 2 == 0 then white(); gfx.drawPixel(px + 8, py + 4); black() end
      end
    end
  end
  -- concourse cameras
  for _, c in ipairs(W.cams) do
    if c.area == a.id and c.on then
      local px, py = c.x * T, c.y * T
      if px >= x0 and px <= x1 then
        black(); gfx.fillRect(px + 4, py - 2, 8, 5); gfx.fillCircleAtPoint(px + 8, py + 4, 3)
        if (f // 15) % 2 == 0 then white(); gfx.drawPixel(px + 8, py + 4); black() end
      end
    end
  end
  -- seasonal decorations
  local decor = W.mall.decor
  if decor and (a.kind == "concourse" or a.id == "fc") then
    for x = (x0 // 64) * 64, x1, 64 do
      local yy = 5 * T + 4
      if decor == "xmas" then
        -- tinsel snowflakes
        local cx, cy = x + 32, yy + 4 + math.floor(math.sin((f + x) / 20) * 2)
        black(); gfx.drawLine(cx - 5, cy, cx + 5, cy); gfx.drawLine(cx, cy - 5, cx, cy + 5)
        gfx.drawLine(cx - 3, cy - 3, cx + 3, cy + 3); gfx.drawLine(cx - 3, cy + 3, cx + 3, cy - 3)
      elseif decor == "halloween" then
        black(); gfx.fillCircleAtPoint(x + 32, yy + 2, 4)
        white(); gfx.drawPixel(x + 30, yy + 1); gfx.drawPixel(x + 34, yy + 1); black()
        gfx.drawLine(x + 32, yy - 6, x + 32, yy - 2)
      elseif decor == "valentine" then
        black(); gfx.fillCircleAtPoint(x + 30, yy, 3); gfx.fillCircleAtPoint(x + 34, yy, 3)
        gfx.fillTriangle(x + 27, yy + 1, x + 37, yy + 1, x + 32, yy + 7)
      end
    end
    if decor == "xmas" and a.id == "c1" and W.mall.santa then
      local px = (W.mall.court0 + 12) * T
      if px > x0 and px < x1 then
        -- Santa's throne
        black(); gfx.fillRect(px, 5 * T + 2, 24, 18); white(); gfx.fillRect(px + 4, 5 * T + 4, 16, 6); black()
        Gfx.text("SANTA", px + 12, 4 * T - 4, { align = "center", bold = true })
      end
    end
  end
  if W.mall.reno == "carpet" and a.id == "c2" then
    Gfx.text("PARDON OUR DUST", 200 + camx, 5 * T + 2, { align = "center" })
  end
end
