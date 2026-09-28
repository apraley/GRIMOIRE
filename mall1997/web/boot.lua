-- Browser boot for THE MALL, 1997.
--
-- Runs the game's Lua source unchanged on Lua 5.4 (wasmoon) in the page,
-- using the same strict Playdate mock (tools/pdmock.lua) and 1-bit software
-- rasterizer (tools/pdraster.lua) the headless test tools use. This file only
-- supplies what a browser lacks:
--   * a read-only in-memory file system for the sources (WEB_FILES, filled
--     by the page before this runs),
--   * playdate.datastore backed by the page's storage (WEB.save/load/remove),
--   * the system menu (items are listed by the page's MENU button),
--   * synth notes played through Web Audio (WEB.beep),
--   * WebFrame(buttons, crank): one 30 fps frame, returning the display
--     packed 6 pixels per character (chr(48 + bits)), or "!" .. error.

local FILES = WEB_FILES
local function norm(p)
  p = tostring(p):gsub("^%./", "")
  while true do
    local q = p:gsub("[^/]+/%.%./", "", 1)
    if q == p then break end
    p = q
  end
  return p
end

-- ---------------------------------------------------------------- files
local function fileObj(s)
  local pos = 1
  local f = {}
  function f:lines()
    return function()
      if pos > #s then return nil end
      local e = s:find("\n", pos, true)
      local line
      if e then line = s:sub(pos, e - 1); pos = e + 1 else line = s:sub(pos); pos = #s + 1 end
      return (line:gsub("\r$", ""))
    end
  end
  function f:read(fmt)
    if fmt == "a" or fmt == "*a" then local r = s:sub(pos); pos = #s + 1; return r end
    return self:lines()()
  end
  function f:close() end
  return f
end

io.open = function(path, mode)
  mode = mode or "r"
  if mode:sub(1, 1) ~= "r" then return nil, "read-only file system" end
  local s = FILES[norm(path)]
  if not s then return nil, path .. ": No such file" end
  return fileObj(s)
end
loadfile = function(path)
  local s = FILES[norm(path)]
  if not s then return nil, "cannot open " .. tostring(path) end
  return load(s, "@" .. norm(path))
end
dofile = function(path)
  local chunk, err = loadfile(path)
  if not chunk then error(err, 2) end
  return chunk()
end
os.execute = function() return true end

-- ---------------------------------------------------------------- runtime
PD_TOOLS_DIR = "tools/"
PD_SOURCE_DIR = "source/"
PD_DATA_DIR = "data/"
dofile("tools/pdmock.lua")
dofile("tools/pdraster.lua")

local IMPL = PDMOCK_IMPL

IMPL["playdate.datastore.write"] = function(t, name)
  WEB.save(name or "data", json.encode(t))
end
IMPL["playdate.datastore.read"] = function(name)
  local s = WEB.load(name or "data")
  if type(s) ~= "string" or s == "" then return nil end
  local ok, v = pcall(json.decode, s)
  if ok then return v end
  return nil
end
IMPL["playdate.datastore.delete"] = function(name)
  WEB.remove(name or "data")
  return true
end

WEB_MENU = {}
IMPL["playdate.menu:addMenuItem"] = function(self, title, cb)
  WEB_MENU[#WEB_MENU + 1] = { title = title, cb = cb }
  return PDMOCK_NEW_INSTANCE("playdate.menu.item", {})
end

local volume = 0.15
IMPL["playdate.sound.synth:setVolume"] = function(self, v) volume = tonumber(v) or volume end
IMPL["playdate.sound.synth:playNote"] = function(self, freq, vel, len)
  WEB.beep(tonumber(freq) or 440, volume * (tonumber(vel) or 1), tonumber(len) or 0.05)
end

-- ---------------------------------------------------------------- frames
local lastErr
local function run(fn, ...)
  local ok, err = xpcall(fn, debug.traceback, ...)
  if not ok then lastErr = tostring(err) end
  return ok
end

local char, unpack, concat = string.char, table.unpack, table.concat
local codes = {}
local function packDisplay()
  local P = PDRASTER_DISPLAY.px
  local i = 1
  for k = 1, 16000 do
    codes[k] = 48 + P[i] * 32 + P[i + 1] * 16 + P[i + 2] * 8 + P[i + 3] * 4 + P[i + 4] * 2 + P[i + 5]
    i = i + 6
  end
  return char(unpack(codes, 1, 4000)) .. char(unpack(codes, 4001, 8000))
    .. char(unpack(codes, 8001, 12000)) .. char(unpack(codes, 12001, 16000))
end

function WebBoot()
  if not run(import, "main") then return "!" .. lastErr end
  return ""
end

function WebFrame(buttons, crank)
  if lastErr then return "!" .. lastErr end
  if not run(PDMOCK_FRAME, math.tointeger(buttons) or 0, tonumber(crank) or 0) then return "!" .. lastErr end
  return packDisplay()
end

function WebMenuItems()
  local t = {}
  for i, m in ipairs(WEB_MENU) do t[i] = m.title end
  return concat(t, "\n")
end

function WebMenuSelect(i)
  local m = WEB_MENU[math.tointeger(i) or 0]
  if m and m.cb then run(m.cb) end
end

-- where the player is right now, for tester notes and bug reports.
-- WebDebugInfo("short") is one line: "SAT AUG 30 4:12PM · Food Court · $18.50";
-- with no argument it is a fuller multi-line snapshot.
local function sceneLine()
  local top = Scene and Scene.top and Scene.top()
  if not top then return "no scene" end
  if Explore and top == Explore.scene then return "walking around" end
  if top.pages and top.pages[top.page] then return "dialog: " .. (top.pages[top.page][1] or "") end
  if top.items then
    local t = top.title or (top.opts and top.opts.prompt) or ""
    return "choosing: " .. t
  end
  if top.tab and top.rows then return "life menu" end
  return "other screen"
end

function WebDebugInfo(kind)
  local ok, out = pcall(function()
    if not W or not W.p then return kind == "short" and "title screen" or "title screen (no mall loaded yet)" end
    local p = W.p
    local where = p.atMall and Areas.name(p.area) or "not at the mall"
    if kind == "short" then
      return Clock.stamp(W.t) .. " \u{b7} " .. where .. " \u{b7} " .. U.money(p.money)
    end
    local lines = {
      "mall: " .. W.mall.name .. " (seed " .. tostring(W.seed) .. ")",
      "game time: " .. Clock.stamp(W.t) .. " (day " .. Clock.day(W.t) .. ")",
      "where: " .. where .. (p.atMall and (" [" .. p.area .. " x" .. math.floor(p.x) .. " y" .. math.floor(p.y) .. "]") or ""),
      "player: " .. p.name .. ", " .. U.money(p.money) .. ", " .. (p.tokens or 0) .. " tokens",
      "screen: " .. sceneLine(),
    }
    if Turf and W.turf then
      local label, v = Turf.standing()
      lines[#lines + 1] = "standing: " .. label .. " (" .. v .. "), turf held " .. Turf.held() .. "/" .. #Turf.ZONES
      local key = Turf.zoneOf(p.area)
      local z = key and Turf.zone(key)
      if z then lines[#lines + 1] = "turf here: " .. Turf.BY[key].short .. " owner " .. z.owner .. " respect " .. z.resp .. "/" .. Turf.BY[key].need end
    end
    if p.job then lines[#lines + 1] = "job: " .. Jobs.title() .. " at " .. Jobs.placeName() end
    return table.concat(lines, "\n")
  end)
  if ok then return out end
  return "(debug info unavailable: " .. tostring(out) .. ")"
end

-- the page is being hidden or closed: save like the device would on sleep
function WebSuspend()
  if playdate.gameWillTerminate then run(playdate.gameWillTerminate) end
end
