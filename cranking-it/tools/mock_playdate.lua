-- Headless mock of the Playdate Lua runtime, used for automated play-testing
-- and screenshots outside the Simulator. It implements only functions that
-- exist in the official SDK (checked against playdate-luacats by
-- tools/check_api.py) and rasterizes drawing into a 1-bit framebuffer so
-- screenshots approximate what the device shows.
--
-- Not shipped with the game.

local M = {}
local W, H = 400, 240

playdate = {}
playdate.isSimulator = true
playdate.argv = {}
local pd = playdate

pd.kButtonLeft, pd.kButtonRight, pd.kButtonUp, pd.kButtonDown = 1, 2, 4, 8
pd.kButtonB, pd.kButtonA = 16, 32

kTextAlignment = { left = 0, right = 1, center = 2 }

------------------------------------------------------------------------
-- time / input state driven by the harness
------------------------------------------------------------------------
M.frame = 0
M.ms = 0
M.crankPos = 0
M.crankChange = 0
M.crankDocked = false
M.buttonsCur, M.buttonsPressed, M.buttonsReleased = 0, 0, 0
M.epoch = 780000000 -- seconds since 2000-01-01
M.date = { year = 2026, month = 9, day = 25, weekday = 5, hour = 12, minute = 0, second = 0, millisecond = 0 }

function pd.getCurrentTimeMilliseconds() return M.ms end
local elapsedBase = 0
function pd.getElapsedTime() return (M.ms - elapsedBase) / 1000 end
function pd.resetElapsedTime() elapsedBase = M.ms end
function pd.getSecondsSinceEpoch() return M.epoch + M.ms // 1000, M.ms % 1000 end
function pd.getTime()
  local t = {}
  for k, v in pairs(M.date) do t[k] = v end
  return t
end
function pd.getCrankPosition() return M.crankPos end
function pd.getCrankChange() return M.crankChange, M.crankChange end
function pd.isCrankDocked() return M.crankDocked end
function pd.setCrankSoundsDisabled() end
function pd.getButtonState() return M.buttonsCur, M.buttonsPressed, M.buttonsReleased end
function pd.buttonIsPressed(b) return (M.buttonsCur & b) ~= 0 end
function pd.buttonJustPressed(b) return (M.buttonsPressed & b) ~= 0 end
function pd.buttonJustReleased(b) return (M.buttonsReleased & b) ~= 0 end
function pd.getReduceFlashing() return false end
function pd.setAutoLockDisabled() end
function pd.setMenuImage() end
function pd.stop() end
function pd.start() end
function pd.getFPS() return 30 end
function pd.drawFPS() end
function pd.getStats() return nil end

local menuItems = {}
M.menuItems = menuItems
local menu = {}
function menu:addMenuItem(title, cb)
  assert(type(title) == "string" and type(cb) == "function", "addMenuItem(title, callback)")
  assert(#menuItems < 3, "Playdate allows at most three custom menu items")
  local item = { title = title, cb = cb }
  function item:setTitle(t) self.title = t end
  function item:getTitle() return self.title end
  function item:setCallback(c) self.cb = c end
  menuItems[#menuItems + 1] = item
  return item
end
function menu:addCheckmarkMenuItem(title, v, cb) return menu:addMenuItem(title, cb or function() end) end
function menu:addOptionsMenuItem(title, opts, v, cb) return menu:addMenuItem(title, cb or function() end) end
function menu:removeAllMenuItems() for i = #menuItems, 1, -1 do menuItems[i] = nil end end
function menu:removeMenuItem(it)
  for i = #menuItems, 1, -1 do if menuItems[i] == it then table.remove(menuItems, i) end end
end
function menu:getMenuItems() return menuItems end
function pd.getSystemMenu() return menu end

------------------------------------------------------------------------
-- display
------------------------------------------------------------------------
pd.display = {}
M.refreshRate = 30
M.inverted = false
function pd.display.setRefreshRate(r) M.refreshRate = r end
function pd.display.getRefreshRate() return M.refreshRate end
function pd.display.setInverted(f) M.inverted = f and true or false end
function pd.display.getInverted() return M.inverted end
function pd.display.getWidth() return W end
function pd.display.getHeight() return H end
function pd.display.getSize() return W, H end
function pd.display.getRect() return 0, 0, W, H end
M.displayOffX, M.displayOffY = 0, 0
function pd.display.setOffset(x, y) M.displayOffX, M.displayOffY = x, y end
function pd.display.getOffset() return M.displayOffX, M.displayOffY end
function pd.display.setScale() end
function pd.display.getScale() return 1 end
function pd.display.setMosaic() end
function pd.display.flush() end

------------------------------------------------------------------------
-- json + datastore
------------------------------------------------------------------------
json = {}
local function encodeValue(v, out)
  local t = type(v)
  if t == "nil" then out[#out + 1] = "null"
  elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then error("json: cannot encode non-finite number") end
    if math.type(v) == "integer" then out[#out + 1] = tostring(v)
    else out[#out + 1] = string.format("%.14g", v) end
  elseif t == "string" then
    out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c)
      local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
      return map[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
  elseif t == "table" then
    local n = #v
    local isArray = n > 0 or next(v) == nil
    if isArray then
      for k in pairs(v) do
        if math.type(k) ~= "integer" or k < 1 or k > n then isArray = false break end
      end
    end
    if isArray then
      out[#out + 1] = "["
      for i = 1, n do
        if i > 1 then out[#out + 1] = "," end
        encodeValue(v[i], out)
      end
      out[#out + 1] = "]"
    else
      out[#out + 1] = "{"
      local first = true
      local keys = {}
      for k in pairs(v) do
        if type(k) ~= "string" then
          error("json: mixed/sparse table or non-string key '" .. tostring(k) .. "' is not portable to playdate.datastore")
        end
        keys[#keys + 1] = k
      end
      table.sort(keys)
      for _, k in ipairs(keys) do
        if not first then out[#out + 1] = "," end
        first = false
        encodeValue(k, out)
        out[#out + 1] = ":"
        encodeValue(v[k], out)
      end
      out[#out + 1] = "}"
    end
  else
    error("json: cannot encode " .. t)
  end
end
function json.encode(v) local out = {} encodeValue(v, out) return table.concat(out) end
json.encodePretty = json.encode

function json.decode(s)
  local pos = 1
  local function ws() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
  local parse
  local function str()
    local buf = {}
    pos = pos + 1
    while true do
      local c = s:sub(pos, pos)
      if c == '"' then pos = pos + 1 break end
      if c == "\\" then
        local e = s:sub(pos + 1, pos + 1)
        local map = { n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f" }
        if e == "u" then
          buf[#buf + 1] = utf8.char(tonumber(s:sub(pos + 2, pos + 5), 16))
          pos = pos + 6
        else
          buf[#buf + 1] = map[e]
          pos = pos + 2
        end
      else
        buf[#buf + 1] = c
        pos = pos + 1
      end
    end
    return table.concat(buf)
  end
  function parse()
    ws()
    local c = s:sub(pos, pos)
    if c == "{" then
      local t = {}
      pos = pos + 1 ws()
      if s:sub(pos, pos) == "}" then pos = pos + 1 return t end
      while true do
        ws()
        local k = str()
        ws() pos = pos + 1 -- :
        t[k] = parse()
        ws()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == "}" then return t end
      end
    elseif c == "[" then
      local t = {}
      pos = pos + 1 ws()
      if s:sub(pos, pos) == "]" then pos = pos + 1 return t end
      while true do
        t[#t + 1] = parse()
        ws()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == "]" then return t end
      end
    elseif c == '"' then return str()
    elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
    elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
    elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      pos = pos + #num
      return math.tointeger(tonumber(num)) or tonumber(num)
    end
  end
  return parse()
end

pd.datastore = {}
M.dataDir = os.getenv("MOCK_DATA_DIR") or "/tmp/cranking-it-mock-data"
os.execute("mkdir -p '" .. M.dataDir .. "'")
M.failWrites = false
function pd.datastore.write(t, name, pretty)
  name = name or "data"
  if M.failWrites then return end
  local s = json.encode(t)
  local f = assert(io.open(M.dataDir .. "/" .. name .. ".json", "w"))
  f:write(s)
  f:close()
end
function pd.datastore.read(name)
  name = name or "data"
  local f = io.open(M.dataDir .. "/" .. name .. ".json", "r")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  local ok, v = pcall(json.decode, s)
  if ok then return v end
  return nil
end
function pd.datastore.delete(name)
  return os.remove(M.dataDir .. "/" .. (name or "data") .. ".json") ~= nil
end
function M.wipeData() os.execute("rm -f '" .. M.dataDir .. "'/*.json") end

------------------------------------------------------------------------
-- sound (no-op objects with argument validation)
------------------------------------------------------------------------
pd.sound = {}
local S = pd.sound
S.kWaveSquare, S.kWaveTriangle, S.kWaveSine, S.kWaveNoise, S.kWaveSawtooth = 0, 1, 2, 3, 4
S.kWavePOPhase, S.kWavePODigital, S.kWavePOVosim = 5, 6, 7
S.kFilterLowPass, S.kFilterHighPass, S.kFilterBandPass = 0, 1, 2
S.kLFOSquare, S.kLFOTriangle, S.kLFOSine, S.kLFOSampleAndHold = 0, 1, 2, 3
function S.getCurrentTime() return M.ms / 1000 end
function S.resetTime() end
function S.getSampleRate() return 44100 end
function S.playingSources() return {} end
function S.addEffect() end
function S.removeEffect() end
function S.getHeadphoneState() return false end
function S.setOutputsActive() end

M.notes = 0
S.synth = {}
S.synth.__index = S.synth
function S.synth.new(wave)
  assert(wave == nil or type(wave) == "number", "synth.new(waveform)")
  return setmetatable({ playing = false, vol = 1 }, S.synth)
end
local function checkNum(v, name)
  if type(v) ~= "number" or v ~= v then error(name .. " must be a number, got " .. tostring(v), 3) end
end
function S.synth:playNote(pitch, vol, len, when)
  if type(pitch) ~= "string" then checkNum(pitch, "pitch") end
  if vol ~= nil then checkNum(vol, "volume") end
  if len ~= nil then checkNum(len, "length") end
  if when ~= nil then checkNum(when, "when") end
  M.notes = M.notes + 1
  self.playing = true
  return true
end
function S.synth:playMIDINote(n, vol, len, when) return self:playNote(440, vol, len, when) end
function S.synth:noteOff() self.playing = false end
function S.synth:stop() self.playing = false end
function S.synth:isPlaying() return self.playing end
function S.synth:setADSR(a, d, s, r) checkNum(a, "a") checkNum(d, "d") checkNum(s, "s") checkNum(r, "r") end
function S.synth:setAttack(v) checkNum(v, "attack") end
function S.synth:setDecay(v) checkNum(v, "decay") end
function S.synth:setSustain(v) checkNum(v, "sustain") end
function S.synth:setRelease(v) checkNum(v, "release") end
function S.synth:setVolume(l, r) checkNum(l, "volume") self.vol = l end
function S.synth:getVolume() return self.vol end
function S.synth:setWaveform(w) end
function S.synth:setLegato(f) end
function S.synth:setParameter() end
function S.synth:setFrequencyMod() end
function S.synth:setAmplitudeMod() end
function S.synth:setFinishCallback() end
function S.synth:setEnvelopeCurvature() end
function S.synth:clearEnvelope() end
function S.synth:copy() return S.synth.new() end

S.channel = {}
S.channel.__index = S.channel
function S.channel.new() return setmetatable({}, S.channel) end
function S.channel:addSource() return true end
function S.channel:removeSource() return true end
function S.channel:addEffect() end
function S.channel:removeEffect() end
function S.channel:setVolume() end
function S.channel:getVolume() return 1 end
function S.channel:setPan() end
function S.channel:remove() end

S.twopolefilter = {}
S.twopolefilter.__index = S.twopolefilter
function S.twopolefilter.new(t) return setmetatable({}, S.twopolefilter) end
function S.twopolefilter:setFrequency() end
function S.twopolefilter:setResonance() end
function S.twopolefilter:setMix() end
function S.twopolefilter:setType() end

S.lfo = {}
S.lfo.__index = S.lfo
function S.lfo.new() return setmetatable({}, S.lfo) end
function S.lfo:setRate() end
function S.lfo:setDepth() end
function S.lfo:setCenter() end
function S.lfo:setType() end

------------------------------------------------------------------------
-- graphics
------------------------------------------------------------------------
pd.graphics = {}
local g = pd.graphics
g.kColorBlack, g.kColorWhite, g.kColorClear, g.kColorXOR = 0, 1, 2, 3
g.kDrawModeCopy, g.kDrawModeWhiteTransparent, g.kDrawModeBlackTransparent = 0, 1, 2
g.kDrawModeFillWhite, g.kDrawModeFillBlack, g.kDrawModeXOR, g.kDrawModeNXOR, g.kDrawModeInverted = 3, 4, 5, 6, 7
g.kImageUnflipped, g.kImageFlippedX, g.kImageFlippedY, g.kImageFlippedXY = 0, 1, 2, 3
g.kLineCapStyleButt, g.kLineCapStyleSquare, g.kLineCapStyleRound = 0, 1, 2
g.kPolygonFillNonZero, g.kPolygonFillEvenOdd = 0, 1
g.kStrokeCentered, g.kStrokeInside, g.kStrokeOutside = 0, 1, 2
g.kDitherTypeNone, g.kDitherTypeDiagonalLine, g.kDitherTypeVerticalLine, g.kDitherTypeHorizontalLine = 0, 1, 2, 3
g.kDitherTypeScreen, g.kDitherTypeBayer2x2, g.kDitherTypeBayer4x4, g.kDitherTypeBayer8x8 = 4, 5, 6, 7
g.kDitherTypeFloydSteinberg, g.kDitherTypeBurkes, g.kDitherTypeAtkinson = 8, 9, 10
g.kWrapClip, g.kWrapCharacter, g.kWrapWord = 16777216, 16777217, 16777218

M.drawCalls = 0
M.render = os.getenv("MOCK_RENDER") == "1"

-- image objects -------------------------------------------------------
g.image = {}
local Image = g.image
Image.__index = Image
local function newBuffer(w, h, v)
  local p = {}
  for i = 1, w * h do p[i] = v end
  return p
end
function Image.new(w, h, bg)
  if type(w) == "string" then return nil, "mock cannot load image files" end
  assert(math.type(w) == "integer" or w == math.floor(w), "image.new width must be integral")
  w, h = math.floor(w), math.floor(h)
  assert(w > 0 and h > 0 and w <= 4096 and h <= 4096, "bad image size")
  local img = setmetatable({ w = w, h = h }, Image)
  bg = bg or g.kColorClear
  img.pix = newBuffer(w, h, bg == g.kColorBlack and 0 or 1)
  img.mask = newBuffer(w, h, bg == g.kColorClear and 0 or 1)
  return img
end
function Image:getSize() return self.w, self.h end
function Image:copy()
  local c = setmetatable({ w = self.w, h = self.h, pix = {}, mask = {} }, Image)
  for i = 1, #self.pix do c.pix[i] = self.pix[i] c.mask[i] = self.mask[i] end
  return c
end
function Image:clear(color)
  for i = 1, #self.pix do
    self.pix[i] = color == g.kColorBlack and 0 or 1
    self.mask[i] = color == g.kColorClear and 0 or 1
  end
end
function Image:sample(x, y)
  if x < 0 or y < 0 or x >= self.w or y >= self.h then return g.kColorClear end
  local i = y * self.w + x + 1
  if self.mask[i] == 0 then return g.kColorClear end
  return self.pix[i] == 0 and g.kColorBlack or g.kColorWhite
end
function Image:hasMask() return true end
function Image:addMask() end
function Image:removeMask() for i = 1, #self.mask do self.mask[i] = 1 end end
function Image:setInverted(f) if f then for i = 1, #self.pix do self.pix[i] = 1 - self.pix[i] end end end
function Image:invertedImage() local c = self:copy() c:setInverted(true) return c end
function Image:fadedImage(alpha) local c = self:copy() return c end
function Image:scaledImage(s, sy)
  sy = sy or s
  local nw, nh = math.max(1, math.floor(self.w * s)), math.max(1, math.floor(self.h * sy))
  local c = Image.new(nw, nh)
  for y = 0, nh - 1 do for x = 0, nw - 1 do
    local sx, syy = math.floor(x / s), math.floor(y / sy)
    local i = syy * self.w + sx + 1
    c.pix[y * nw + x + 1] = self.pix[i] c.mask[y * nw + x + 1] = self.mask[i]
  end end
  return c
end
function Image:rotatedImage(a) return self:copy() end
function Image:blurredImage() return self:copy() end
function Image:vcrPauseFilterImage() return self:copy() end

-- context --------------------------------------------------------------
local screen = Image.new(W, H, g.kColorWhite)
M.screen = screen
local ctx
local function newCtx(target)
  return {
    target = target, color = g.kColorBlack, pattern = nil, patMask = nil, dither = nil,
    lineWidth = 1, ox = 0, oy = 0, clip = nil, drawMode = g.kDrawModeCopy,
    font = nil, bg = g.kColorWhite, stroke = g.kStrokeCentered, tracking = 0,
  }
end
ctx = newCtx(screen)
local ctxStack = {}
function g.pushContext(img)
  ctxStack[#ctxStack + 1] = ctx
  local n = newCtx(img or ctx.target)
  if not img then
    for k, v in pairs(ctx) do n[k] = v end
  else
    n.font = ctx.font
  end
  ctx = n
end
function g.popContext()
  assert(#ctxStack > 0, "popContext without pushContext")
  ctx = table.remove(ctxStack)
end
function g.lockFocus(img) g.pushContext(img) end
function g.unlockFocus() g.popContext() end
function M.contextDepth() return #ctxStack end

local bayer8 = {
  { 0, 32, 8, 40, 2, 34, 10, 42 }, { 48, 16, 56, 24, 50, 18, 58, 26 },
  { 12, 44, 4, 36, 14, 46, 6, 38 }, { 60, 28, 52, 20, 62, 30, 54, 22 },
  { 3, 35, 11, 43, 1, 33, 9, 41 }, { 51, 19, 59, 27, 49, 17, 57, 25 },
  { 15, 47, 7, 39, 13, 45, 5, 37 }, { 63, 31, 55, 23, 61, 29, 53, 21 },
}

function g.setColor(c)
  if not (c == 0 or c == 1 or c == 2 or c == 3) then error("setColor: bad color " .. tostring(c), 2) end
  ctx.color = c ctx.pattern = nil ctx.dither = nil
end
function g.getColor() return ctx.color end
function g.setPattern(p, x, y)
  if getmetatable(p) == Image then ctx.pattern = { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff } ctx.dither = nil return end
  assert(type(p) == "table" and (#p == 8 or #p == 16), "setPattern expects 8 or 16 row values")
  for i = 1, #p do assert(type(p[i]) == "number", "pattern rows must be numbers") end
  ctx.pattern = p ctx.dither = nil
end
function g.setDitherPattern(alpha, dt)
  checkNum(alpha, "alpha")
  ctx.dither = alpha ctx.pattern = nil
end
function g.setLineWidth(w) checkNum(w, "lineWidth") ctx.lineWidth = w end
function g.getLineWidth() return ctx.lineWidth end
function g.setLineCapStyle() end
function g.setStrokeLocation(l) ctx.stroke = l end
function g.getStrokeLocation() return ctx.stroke end
function g.setPolygonFillRule() end
function g.setDrawOffset(x, y) checkNum(x, "x") checkNum(y, "y") ctx.ox, ctx.oy = x, y end
function g.getDrawOffset() return ctx.ox, ctx.oy end
function g.setClipRect(x, y, w, h)
  if type(x) == "table" then x, y, w, h = x.x, x.y, x.width, x.height end
  ctx.clip = { x + ctx.ox, y + ctx.oy, w, h }
end
function g.setScreenClipRect(x, y, w, h) ctx.clip = { x, y, w, h } end
function g.getClipRect() if ctx.clip then return table.unpack(ctx.clip) end return 0, 0, ctx.target.w, ctx.target.h end
function g.clearClipRect() ctx.clip = nil end
function g.setImageDrawMode(m) assert(type(m) == "number" or type(m) == "string", "setImageDrawMode") ctx.drawMode = m end
function g.getImageDrawMode() return ctx.drawMode end
function g.setBackgroundColor(c) ctx.bg = c end
function g.getBackgroundColor() return ctx.bg end
function g.setStencilImage() end
function g.setStencilPattern() end
function g.clearStencil() end
function g.clearStencilImage() end
function g.getDisplayImage() return screen:copy() end
function g.getWorkingImage() return screen:copy() end

-- raw pixel write with current color/pattern
local function plot(x, y, forceColor)
  x, y = math.floor(x), math.floor(y)
  local t = ctx.target
  if x < 0 or y < 0 or x >= t.w or y >= t.h then return end
  local c = ctx.clip
  if c and (x < c[1] or y < c[2] or x >= c[1] + c[3] or y >= c[2] + c[4]) then return end
  local color = forceColor or ctx.color
  if not forceColor then
    if ctx.pattern then
      local row = ctx.pattern[(y % 8) + 1]
      local bit = (row >> (7 - (x % 8))) & 1
      if #ctx.pattern == 16 then
        local mrow = ctx.pattern[(y % 8) + 9]
        if ((mrow >> (7 - (x % 8))) & 1) == 0 then return end
      end
      color = bit == 1 and g.kColorWhite or g.kColorBlack
    elseif ctx.dither then
      local th = (bayer8[(y % 8) + 1][(x % 8) + 1] + 0.5) / 64
      if ctx.color == g.kColorWhite then
        if th < ctx.dither then return end
        color = g.kColorWhite
      else
        if th >= ctx.dither then return end
        color = g.kColorBlack
      end
    end
  end
  local i = y * t.w + x + 1
  if color == g.kColorClear then t.mask[i] = 0 return end
  if color == g.kColorXOR then t.pix[i] = 1 - t.pix[i] t.mask[i] = 1 return end
  t.pix[i] = color == g.kColorBlack and 0 or 1
  t.mask[i] = 1
end
M.plot = plot

local function hspan(x0, x1, y)
  if x1 < x0 then x0, x1 = x1, x0 end
  x0, x1 = math.ceil(x0 - 0.0001), math.floor(x1)
  local t = ctx.target
  if y < 0 or y >= t.h then return end
  if x0 < 0 then x0 = 0 end
  if x1 >= t.w then x1 = t.w - 1 end
  for x = x0, x1 do plot(x, y) end
end

function g.clear(c)
  M.drawCalls = M.drawCalls + 1
  if not M.render and ctx.target == screen then return end
  local t = ctx.target
  c = c or ctx.bg
  for i = 1, t.w * t.h do
    if c == g.kColorClear then t.mask[i] = 0 else t.pix[i] = c == g.kColorBlack and 0 or 1 t.mask[i] = 1 end
  end
end

local function rectArgs(x, y, w, h)
  if type(x) == "table" then return x.x, x.y, x.width, x.height end
  return x, y, w, h
end

function g.fillRect(x, y, w, h)
  M.drawCalls = M.drawCalls + 1
  x, y, w, h = rectArgs(x, y, w, h)
  checkNum(x, "x") checkNum(y, "y") checkNum(w, "w") checkNum(h, "h")
  if not M.render and ctx.target == screen then return end
  x, y = math.floor(x + ctx.ox), math.floor(y + ctx.oy)
  w, h = math.floor(w), math.floor(h)
  if w < 0 then x = x + w w = -w end
  if h < 0 then y = y + h h = -h end
  local t = ctx.target
  local y0, y1 = math.max(0, y), math.min(t.h - 1, y + h - 1)
  local x0, x1 = math.max(0, x), math.min(t.w - 1, x + w - 1)
  for yy = y0, y1 do for xx = x0, x1 do plot(xx, yy) end end
end

function g.drawRect(x, y, w, h)
  M.drawCalls = M.drawCalls + 1
  x, y, w, h = rectArgs(x, y, w, h)
  checkNum(x, "x") checkNum(y, "y") checkNum(w, "w") checkNum(h, "h")
  if not M.render and ctx.target == screen then return end
  local lw = math.max(1, math.floor(ctx.lineWidth))
  local ox, oy = ctx.ox, ctx.oy
  ctx.ox, ctx.oy = 0, 0
  local fx, fy = x + ox, y + oy
  g.fillRect(fx, fy, w, lw)
  g.fillRect(fx, fy + h - lw, w, lw)
  g.fillRect(fx, fy, lw, h)
  g.fillRect(fx + w - lw, fy, lw, h)
  ctx.ox, ctx.oy = ox, oy
end

local function stamp(x, y, lw)
  if lw <= 1 then plot(x, y) return end
  local r = lw / 2
  for yy = math.floor(y - r + 0.5), math.floor(y + r - 0.5) do
    for xx = math.floor(x - r + 0.5), math.floor(x + r - 0.5) do plot(xx, yy) end
  end
end

function g.drawLine(x1, y1, x2, y2)
  M.drawCalls = M.drawCalls + 1
  if type(x1) == "table" then x1, y1, x2, y2 = x1.x, x1.y, x1.x2 or x1.x, x1.y2 or x1.y end
  checkNum(x1, "x1") checkNum(y1, "y1") checkNum(x2, "x2") checkNum(y2, "y2")
  if not M.render and ctx.target == screen then return end
  x1, y1, x2, y2 = x1 + ctx.ox, y1 + ctx.oy, x2 + ctx.ox, y2 + ctx.oy
  local lw = math.max(1, math.floor(ctx.lineWidth))
  local dx, dy = x2 - x1, y2 - y1
  local n = math.max(math.abs(dx), math.abs(dy))
  n = math.min(math.ceil(n), 2000)
  if n == 0 then stamp(x1, y1, lw) return end
  for i = 0, n do
    stamp(math.floor(x1 + dx * i / n + 0.5), math.floor(y1 + dy * i / n + 0.5), lw)
  end
end

function g.drawPixel(x, y)
  if type(x) == "table" then x, y = x.x, x.y end
  checkNum(x, "x") checkNum(y, "y")
  plot(x + ctx.ox, y + ctx.oy)
end

local function fillPoly(pts)
  -- pts: flat array x1,y1,x2,y2...
  local n = #pts // 2
  if n < 3 then return end
  local miny, maxy = math.huge, -math.huge
  for i = 1, n do
    local y = pts[i * 2]
    if y < miny then miny = y end
    if y > maxy then maxy = y end
  end
  local t = ctx.target
  miny = math.max(0, math.floor(miny))
  maxy = math.min(t.h - 1, math.ceil(maxy))
  local xs = {}
  for y = miny, maxy do
    local sy = y + 0.5
    local cnt = 0
    for i = 1, n do
      local ax, ay = pts[i * 2 - 1], pts[i * 2]
      local j = i % n + 1
      local bx, by = pts[j * 2 - 1], pts[j * 2]
      if (ay <= sy and by > sy) or (by <= sy and ay > sy) then
        cnt = cnt + 1
        xs[cnt] = ax + (sy - ay) / (by - ay) * (bx - ax)
      end
    end
    for k = cnt + 1, #xs do xs[k] = nil end
    table.sort(xs)
    for k = 1, cnt - 1, 2 do hspan(xs[k], xs[k + 1] - 0.5, y) end
  end
end

local function polyArgs(...)
  local a = { ... }
  if type(a[1]) == "table" then
    local p = a[1]
    local out = {}
    if p.getPointAt then
      for i = 1, p:count() do local q = p:getPointAt(i) out[#out + 1] = q.x out[#out + 1] = q.y end
    else
      for i = 1, #p do out[i] = p[i] end
    end
    return out
  end
  for i = 1, #a do checkNum(a[i], "polygon coord") end
  return a
end

function g.fillPolygon(...)
  M.drawCalls = M.drawCalls + 1
  local pts = polyArgs(...)
  if not M.render and ctx.target == screen then return end
  for i = 1, #pts, 2 do pts[i] = pts[i] + ctx.ox pts[i + 1] = pts[i + 1] + ctx.oy end
  fillPoly(pts)
end
function g.drawPolygon(...)
  M.drawCalls = M.drawCalls + 1
  local pts = polyArgs(...)
  if not M.render and ctx.target == screen then return end
  local n = #pts // 2
  for i = 1, n do
    local j = i % n + 1
    g.drawLine(pts[i * 2 - 1], pts[i * 2], pts[j * 2 - 1], pts[j * 2])
  end
end
function g.fillTriangle(x1, y1, x2, y2, x3, y3) g.fillPolygon(x1, y1, x2, y2, x3, y3) end
function g.drawTriangle(x1, y1, x2, y2, x3, y3) g.drawPolygon(x1, y1, x2, y2, x3, y3) end

local function ellipseFill(cx, cy, rx, ry, a0, a1)
  if rx <= 0 or ry <= 0 then return end
  local t = ctx.target
  for y = math.floor(cy - ry), math.ceil(cy + ry) do
    if y >= 0 and y < t.h then
      local dy = (y + 0.5 - cy) / ry
      if dy >= -1 and dy <= 1 then
        local span = rx * math.sqrt(1 - dy * dy)
        if a0 then
          for x = math.floor(cx - span), math.ceil(cx + span) do
            local ang = math.deg(math.atan(x + 0.5 - cx, -(y + 0.5 - cy))) % 360
            local s, e = a0 % 360, a1 % 360
            local inside = (s <= e) and (ang >= s and ang <= e) or (s > e and (ang >= s or ang <= e))
            if inside and ((x + 0.5 - cx) / rx) ^ 2 + dy * dy <= 1 then plot(x, y) end
          end
        else
          hspan(cx - span, cx + span - 0.5, y)
        end
      end
    end
  end
end

local function ellipseStroke(cx, cy, rx, ry, a0, a1)
  local lw = math.max(1, math.floor(ctx.lineWidth))
  local steps = math.max(16, math.floor((rx + ry) * 3))
  local s, e = 0, 360
  if a0 then s, e = a0, a1 if e < s then e = e + 360 end end
  for i = 0, steps do
    local a = math.rad(s + (e - s) * i / steps)
    stamp(math.floor(cx + math.sin(a) * rx), math.floor(cy - math.cos(a) * ry), lw)
  end
end

function g.fillCircleAtPoint(x, y, r)
  M.drawCalls = M.drawCalls + 1
  if type(x) == "table" then x, y, r = x.x, x.y, y end
  checkNum(x, "x") checkNum(y, "y") checkNum(r, "r")
  if not M.render and ctx.target == screen then return end
  ellipseFill(x + ctx.ox + 0.5, y + ctx.oy + 0.5, r, r)
end
function g.drawCircleAtPoint(x, y, r)
  M.drawCalls = M.drawCalls + 1
  if type(x) == "table" then x, y, r = x.x, x.y, y end
  checkNum(x, "x") checkNum(y, "y") checkNum(r, "r")
  if not M.render and ctx.target == screen then return end
  ellipseStroke(x + ctx.ox, y + ctx.oy, r, r)
end
function g.fillCircleInRect(x, y, w, h)
  x, y, w, h = rectArgs(x, y, w, h)
  ellipseFill(x + ctx.ox + w / 2, y + ctx.oy + h / 2, w / 2, h / 2)
end
function g.drawCircleInRect(x, y, w, h)
  x, y, w, h = rectArgs(x, y, w, h)
  ellipseStroke(x + ctx.ox + w / 2, y + ctx.oy + h / 2, w / 2, h / 2)
end
function g.fillEllipseInRect(x, y, w, h, a0, a1)
  M.drawCalls = M.drawCalls + 1
  if type(x) == "table" then x, y, w, h, a0, a1 = x.x, x.y, x.width, x.height, y, w end
  checkNum(x, "x") checkNum(y, "y") checkNum(w, "w") checkNum(h, "h")
  if not M.render and ctx.target == screen then return end
  ellipseFill(x + ctx.ox + w / 2, y + ctx.oy + h / 2, w / 2, h / 2, a0, a1)
end
function g.drawEllipseInRect(x, y, w, h, a0, a1)
  M.drawCalls = M.drawCalls + 1
  if type(x) == "table" then x, y, w, h, a0, a1 = x.x, x.y, x.width, x.height, y, w end
  checkNum(x, "x") checkNum(y, "y") checkNum(w, "w") checkNum(h, "h")
  if not M.render and ctx.target == screen then return end
  ellipseStroke(x + ctx.ox + w / 2, y + ctx.oy + h / 2, w / 2, h / 2, a0, a1)
end
function g.drawArc(x, y, r, a0, a1)
  M.drawCalls = M.drawCalls + 1
  if type(x) == "table" then x, y, r, a0, a1 = x.x, x.y, x.radius, x.startAngle, x.endAngle end
  checkNum(x, "x") checkNum(y, "y") checkNum(r, "r") checkNum(a0, "startAngle") checkNum(a1, "endAngle")
  if not M.render and ctx.target == screen then return end
  ellipseStroke(x + ctx.ox, y + ctx.oy, r, r, a0, a1)
end

function g.fillRoundRect(x, y, w, h, r)
  M.drawCalls = M.drawCalls + 1
  if type(x) == "table" then x, y, w, h, r = x.x, x.y, x.width, x.height, y end
  checkNum(x, "x") checkNum(y, "y") checkNum(w, "w") checkNum(h, "h") checkNum(r, "radius")
  if not M.render and ctx.target == screen then return end
  x, y = x + ctx.ox, y + ctx.oy
  r = math.min(r, w / 2, h / 2)
  for yy = math.floor(y), math.floor(y + h - 1) do
    local inset = 0
    local dy
    if yy < y + r then dy = y + r - yy - 0.5 elseif yy > y + h - r - 1 then dy = yy - (y + h - r - 1) - 0.5 end
    if dy and dy > 0 then inset = r - math.sqrt(math.max(0, r * r - dy * dy)) end
    hspan(x + inset, x + w - 1 - inset, yy)
  end
end
function g.drawRoundRect(x, y, w, h, r)
  M.drawCalls = M.drawCalls + 1
  if type(x) == "table" then x, y, w, h, r = x.x, x.y, x.width, x.height, y end
  checkNum(x, "x") checkNum(y, "y") checkNum(w, "w") checkNum(h, "h") checkNum(r, "radius")
  if not M.render and ctx.target == screen then return end
  local ox, oy = ctx.ox, ctx.oy
  r = math.min(r, w / 2, h / 2)
  g.drawLine(x + r, y, x + w - 1 - r, y)
  g.drawLine(x + r, y + h - 1, x + w - 1 - r, y + h - 1)
  g.drawLine(x, y + r, x, y + h - 1 - r)
  g.drawLine(x + w - 1, y + r, x + w - 1, y + h - 1 - r)
  local lw = math.max(1, math.floor(ctx.lineWidth))
  local function corner(cx, cy, s)
    for i = 0, 12 do
      local a = math.rad(s + 90 * i / 12)
      stamp(math.floor(cx + ox + math.sin(a) * r + 0.5), math.floor(cy + oy - math.cos(a) * r + 0.5), lw)
    end
  end
  corner(x + r, y + r, 270) corner(x + w - 1 - r, y + r, 0)
  corner(x + w - 1 - r, y + h - 1 - r, 90) corner(x + r, y + h - 1 - r, 180)
end

function g.drawSineWave(sx, sy, ex, ey, a0, a1, period, phase)
  local n = math.max(2, math.floor(math.abs(ex - sx) + math.abs(ey - sy)))
  local px, py
  for i = 0, n do
    local t = i / n
    local x = sx + (ex - sx) * t
    local amp = a0 + (a1 - a0) * t
    local y = sy + (ey - sy) * t + math.sin(((x - sx) / period) * 2 * math.pi + (phase or 0)) * amp
    if px then g.drawLine(px, py, x, y) end
    px, py = x, y
  end
end

-- image drawing -------------------------------------------------------
local function modeColor(v)
  local mode = ctx.drawMode
  if mode == g.kDrawModeCopy or mode == "copy" then return v end
  if mode == g.kDrawModeWhiteTransparent or mode == "whiteTransparent" then return v == 0 and 0 or nil end
  if mode == g.kDrawModeBlackTransparent or mode == "blackTransparent" then return v == 1 and 1 or nil end
  if mode == g.kDrawModeFillWhite or mode == "fillWhite" then return 1 end
  if mode == g.kDrawModeFillBlack or mode == "fillBlack" then return 0 end
  if mode == g.kDrawModeInverted or mode == "inverted" then return 1 - v end
  if mode == g.kDrawModeXOR or mode == "XOR" then return v == 1 and g.kColorXOR or nil end
  if mode == g.kDrawModeNXOR or mode == "NXOR" then return v == 0 and g.kColorXOR or nil end
  return v
end
local function colorOf(c) if c == 0 then return g.kColorBlack elseif c == 1 then return g.kColorWhite end return c end

local function blit(img, dx, dy, flip, sx0, sy0, sw, sh, sampler)
  M.drawCalls = M.drawCalls + 1
  if not M.render and ctx.target == screen then return end
  dx, dy = math.floor(dx + ctx.ox), math.floor(dy + ctx.oy)
  sx0, sy0 = sx0 or 0, sy0 or 0
  sw, sh = sw or img.w, sh or img.h
  local fx = flip == g.kImageFlippedX or flip == g.kImageFlippedXY or flip == "flipX" or flip == "flipXY"
  local fy = flip == g.kImageFlippedY or flip == g.kImageFlippedXY or flip == "flipY" or flip == "flipXY"
  local mode = ctx.drawMode
  for y = 0, sh - 1 do
    for x = 0, sw - 1 do
      local ix = fx and (sx0 + sw - 1 - x) or (sx0 + x)
      local iy = fy and (sy0 + sh - 1 - y) or (sy0 + y)
      local i = iy * img.w + ix + 1
      if img.mask[i] == 1 then
        local v = img.pix[i]
        local c
        if mode == g.kDrawModeCopy or mode == "copy" then c = v
        elseif mode == g.kDrawModeWhiteTransparent or mode == "whiteTransparent" then if v == 0 then c = 0 end
        elseif mode == g.kDrawModeBlackTransparent or mode == "blackTransparent" then if v == 1 then c = 1 end
        elseif mode == g.kDrawModeFillWhite or mode == "fillWhite" then c = 1
        elseif mode == g.kDrawModeFillBlack or mode == "fillBlack" then c = 0
        elseif mode == g.kDrawModeInverted or mode == "inverted" then c = 1 - v
        elseif mode == g.kDrawModeXOR or mode == "XOR" then if v == 1 then c = g.kColorXOR end
        elseif mode == g.kDrawModeNXOR or mode == "NXOR" then if v == 0 then c = g.kColorXOR end
        else c = v end
        if c ~= nil then
          if sampler and not sampler(dx + x, dy + y) then c = nil end
          if c ~= nil then plot(dx + x, dy + y, c == 0 and g.kColorBlack or (c == 1 and g.kColorWhite or c)) end
        end
      end
    end
  end
end

function Image:draw(x, y, flip, sr)
  if type(x) == "table" then x, y, flip, sr = x.x, x.y, y, flip end
  checkNum(x, "x") checkNum(y, "y")
  if sr then
    if type(sr) == "table" then blit(self, x, y, flip, sr.x, sr.y, sr.width, sr.height) return end
  end
  blit(self, x, y, flip)
end
function Image:drawIgnoringOffset(x, y, flip)
  local ox, oy = ctx.ox, ctx.oy
  ctx.ox, ctx.oy = 0, 0
  self:draw(x, y, flip)
  ctx.ox, ctx.oy = ox, oy
end
function Image:drawCentered(x, y, flip) self:draw(x - self.w // 2, y - self.h // 2, flip) end
function Image:drawAnchored(x, y, ax, ay, flip) self:draw(x - math.floor(self.w * ax), y - math.floor(self.h * ay), flip) end
function Image:drawFaded(x, y, alpha, dt, flip)
  blit(self, x, y, flip, nil, nil, nil, nil, function(px, py)
    return (bayer8[(py % 8) + 1][(px % 8) + 1] + 0.5) / 64 < alpha
  end)
end
function Image:drawTiled(x, y, w, h, flip)
  if type(x) == "table" then x, y, w, h, flip = x.x, x.y, x.width, x.height, y end
  for ty = 0, h - 1, self.h do for tx = 0, w - 1, self.w do self:draw(x + tx, y + ty, flip) end end
end
function Image:drawScaled(x, y, s, sy)
  M.drawCalls = M.drawCalls + 1
  sy = sy or s
  if not M.render and ctx.target == screen then return end
  local nw, nh = math.floor(self.w * s), math.floor(self.h * sy)
  x, y = math.floor(x + ctx.ox), math.floor(y + ctx.oy)
  for yy = 0, nh - 1 do for xx = 0, nw - 1 do
    local i = math.floor(yy / sy) * self.w + math.floor(xx / s) + 1
    if self.mask[i] == 1 then
      local c = modeColor(self.pix[i])
      if c then plot(x + xx, y + yy, colorOf(c)) end
    end
  end end
end
function Image:drawRotated(x, y, angle, s, sy)
  M.drawCalls = M.drawCalls + 1
  s = s or 1 sy = sy or s
  if not M.render and ctx.target == screen then return end
  local a = math.rad(angle)
  local ca, sa = math.cos(a), math.sin(a)
  local rad = math.ceil(math.sqrt(self.w * self.w * s * s + self.h * self.h * sy * sy) / 2) + 1
  local cx, cy = x + ctx.ox, y + ctx.oy
  for yy = -rad, rad do for xx = -rad, rad do
    local u = (ca * xx + sa * yy) / s + self.w / 2
    local v = (-sa * xx + ca * yy) / sy + self.h / 2
    local iu, iv = math.floor(u), math.floor(v)
    if iu >= 0 and iv >= 0 and iu < self.w and iv < self.h then
      local i = iv * self.w + iu + 1
      if self.mask[i] == 1 then
        local c = modeColor(self.pix[i])
        if c then plot(math.floor(cx + xx), math.floor(cy + yy), colorOf(c)) end
      end
    end
  end end
end
function Image:drawBlurred(x, y) self:draw(x, y) end
function Image:drawWithTransform(xf, x, y) self:draw(x, y) end
function Image:drawSampled() end

g.imagetable = {}
g.imagetable.__index = g.imagetable
function g.imagetable.new(n) return nil end

-- fonts --------------------------------------------------------------
-- A tiny built-in 5x7 glyph set so screenshots show legible text. Metrics
-- roughly approximate the Playdate system font (Asheville Sans 14).
local glyphs = {}
local function defglyph(chars, rows) for c in chars:gmatch(".") do glyphs[c] = rows end end
local G5 = {
  A = "01110 10001 10001 11111 10001 10001 10001", B = "11110 10001 11110 10001 10001 10001 11110",
  C = "01110 10001 10000 10000 10000 10001 01110", D = "11110 10001 10001 10001 10001 10001 11110",
  E = "11111 10000 11110 10000 10000 10000 11111", F = "11111 10000 11110 10000 10000 10000 10000",
  G = "01110 10001 10000 10111 10001 10001 01111", H = "10001 10001 11111 10001 10001 10001 10001",
  I = "01110 00100 00100 00100 00100 00100 01110", J = "00111 00010 00010 00010 00010 10010 01100",
  K = "10001 10010 11100 10010 10001 10001 10001", L = "10000 10000 10000 10000 10000 10000 11111",
  M = "10001 11011 10101 10101 10001 10001 10001", N = "10001 11001 10101 10011 10001 10001 10001",
  O = "01110 10001 10001 10001 10001 10001 01110", P = "11110 10001 10001 11110 10000 10000 10000",
  Q = "01110 10001 10001 10001 10101 10010 01101", R = "11110 10001 10001 11110 10010 10001 10001",
  S = "01111 10000 01110 00001 00001 10001 01110", T = "11111 00100 00100 00100 00100 00100 00100",
  U = "10001 10001 10001 10001 10001 10001 01110", V = "10001 10001 10001 10001 10001 01010 00100",
  W = "10001 10001 10001 10101 10101 11011 10001", X = "10001 01010 00100 00100 01010 10001 10001",
  Y = "10001 01010 00100 00100 00100 00100 00100", Z = "11111 00010 00100 01000 10000 10000 11111",
  ["0"] = "01110 10011 10101 10101 11001 10001 01110", ["1"] = "00100 01100 00100 00100 00100 00100 01110",
  ["2"] = "01110 10001 00001 00110 01000 10000 11111", ["3"] = "11110 00001 00110 00001 00001 10001 01110",
  ["4"] = "00010 00110 01010 10010 11111 00010 00010", ["5"] = "11111 10000 11110 00001 00001 10001 01110",
  ["6"] = "01110 10000 11110 10001 10001 10001 01110", ["7"] = "11111 00001 00010 00100 01000 01000 01000",
  ["8"] = "01110 10001 01110 10001 10001 10001 01110", ["9"] = "01110 10001 10001 01111 00001 00001 01110",
  ["."] = "00000 00000 00000 00000 00000 01100 01100", [","] = "00000 00000 00000 00000 01100 00100 01000",
  [":"] = "00000 01100 01100 00000 01100 01100 00000", ["!"] = "00100 00100 00100 00100 00100 00000 00100",
  ["?"] = "01110 10001 00001 00110 00100 00000 00100", ["-"] = "00000 00000 00000 11111 00000 00000 00000",
  ["+"] = "00000 00100 00100 11111 00100 00100 00000", ["/"] = "00001 00010 00010 00100 01000 01000 10000",
  ["'"] = "00100 00100 01000 00000 00000 00000 00000", ['"'] = "01010 01010 00000 00000 00000 00000 00000",
  ["("] = "00010 00100 01000 01000 01000 00100 00010", [")"] = "01000 00100 00010 00010 00010 00100 01000",
  ["%"] = "11001 11010 00010 00100 01000 01011 10011", ["#"] = "01010 11111 01010 01010 11111 01010 00000",
  ["="] = "00000 00000 11111 00000 11111 00000 00000", ["<"] = "00010 00100 01000 10000 01000 00100 00010",
  [">"] = "01000 00100 00010 00001 00010 00100 01000", ["*"] = "00000 10101 01110 11111 01110 10101 00000",
  ["_"] = "00000 00000 00000 00000 00000 00000 11111", ["["] = "01110 01000 01000 01000 01000 01000 01110",
  ["]"] = "01110 00010 00010 00010 00010 00010 01110", ["&"] = "01100 10010 10100 01000 10101 10010 01101",
  ["x"] = "00000 00000 10001 01010 00100 01010 10001",
}
for k, v in pairs(G5) do glyphs[k] = v end
local function glyphRows(ch)
  local gl = glyphs[ch] or glyphs[ch:upper()]
  if not gl then return nil end
  local rows = {}
  for r in gl:gmatch("%d+") do rows[#rows + 1] = r end
  return rows
end

g.font = {}
local Font = g.font
Font.__index = Font
Font.kVariantNormal, Font.kVariantBold, Font.kVariantItalic = "normal", "bold", "italic"
local function makeFont(bold)
  return setmetatable({ bold = bold, height = 16, tracking = 0, leading = 0 }, Font)
end
local sysNormal, sysBold, sysItalic = makeFont(false), makeFont(true), makeFont(false)
function Font.new(path) return makeFont(false) end
function Font.newFamily(t) return { [Font.kVariantNormal] = sysNormal, [Font.kVariantBold] = sysBold } end
local NARROW = {}
for c in ("il.,'!:|"):gmatch(".") do NARROW[c:byte()] = true end
local function charWB(font, b)
  if b == 32 then return 5 end
  if NARROW[b] then return 4 end
  if (b >= 65 and b <= 90) or (b >= 48 and b <= 57) then return font.bold and 10 or 9 end
  return font.bold and 9 or 8
end
local function charW(font, c) return charWB(font, c:byte()) end
function Font:getHeight() return self.height end
function Font:getLeading() return self.leading end
function Font:setLeading(l) self.leading = l end
function Font:getTracking() return self.tracking end
function Font:setTracking(t) self.tracking = t end
function Font:getTextWidth(text)
  if type(text) ~= "string" then error("getTextWidth expects string, got " .. type(text), 2) end
  local maxw, w = 0, 0
  local byte = string.byte
  for i = 1, #text do
    local b = byte(text, i)
    if b == 10 then
      if w > maxw then maxw = w end
      w = 0
    elseif b < 128 or b >= 192 then
      w = w + charWB(self, b) + self.tracking
    end
  end
  return math.max(maxw, w)
end
function Font:getGlyph() return Image.new(8, 16) end
local function drawGlyphs(font, text, x, y)
  local cx, cy = x, y
  if not M.render and ctx.target == screen then return end
  local color = ctx.color
  if ctx.drawMode == g.kDrawModeFillWhite or ctx.drawMode == "fillWhite" or ctx.drawMode == g.kDrawModeInverted then color = g.kColorWhite
  elseif ctx.drawMode == g.kDrawModeXOR or ctx.drawMode == g.kDrawModeNXOR then color = g.kColorXOR
  else color = g.kColorBlack end
  for c in text:gmatch(utf8.charpattern) do
    if c == "\n" then cx = x cy = cy + font.height + font.leading
    else
      local rows = glyphRows(c)
      local cw = charW(font, c)
      if rows then
        local lower = c:match("%l") ~= nil
        local oy = lower and 6 or 4
        local sh = lower and 1 or 1
        for r = 1, #rows do
          local row = rows[r]
          for k = 1, 5 do
            if row:sub(k, k) == "1" then
              local px = cx + (k - 1) + (cw > 8 and 1 or 0)
              local py
              if lower then py = cy + oy + math.floor((r - 1) * 0.72) else py = cy + oy + (r - 1) end
              plot(px + ctx.ox, py + ctx.oy, color)
              if font.bold then plot(px + 1 + ctx.ox, py + ctx.oy, color) end
            end
          end
        end
      end
      cx = cx + cw + font.tracking
    end
  end
  M.drawCalls = M.drawCalls + 1
  return cx - x, cy - y + font.height
end
function Font:drawText(text, x, y, a, b, c, d, e)
  if not (type(text) == "string") then error("font:drawText expects string, got " .. type(text), 2) end
  checkNum(x, "x") checkNum(y, "y")
  return drawGlyphs(self, text, x, y)
end
function Font:drawTextAligned(text, x, y, align)
  assert(type(text) == "string", "drawTextAligned expects string")
  local w = self:getTextWidth(text)
  if align == kTextAlignment.center then x = x - w / 2 elseif align == kTextAlignment.right then x = x - w end
  return drawGlyphs(self, text, math.floor(x), y)
end

function g.getSystemFont(variant)
  if variant == "bold" or variant == Font.kVariantBold then return sysBold end
  if variant == "italic" then return sysItalic end
  return sysNormal
end
function g.setFont(f, variant) ctx.font = f end
function g.getFont() return ctx.font or sysNormal end
function g.setFontFamily() end
function g.setFontTracking(t) ctx.tracking = t end
function g.getFontTracking() return ctx.tracking end
local function stripMarkup(text) return (text:gsub("%*%*", "\1"):gsub("__", "\2"):gsub("[%*_]", ""):gsub("\1", "*"):gsub("\2", "_")) end
function g.drawText(text, x, y, w, h)
  if not (type(text) == "string") then error("drawText expects string, got " .. type(text), 2) end
  if type(x) == "table" then x, y = x.x, x.y end
  checkNum(x, "x") checkNum(y, "y")
  return drawGlyphs(g.getFont(), stripMarkup(text), x, y)
end
function g.getTextSize(text, font)
  assert(type(text) == "string", "getTextSize expects string")
  font = font or g.getFont()
  local lines = 1
  for _ in text:gmatch("\n") do lines = lines + 1 end
  return font:getTextWidth(stripMarkup(text)), lines * font.height
end
function g.drawTextAligned(text, x, y, align)
  assert(type(text) == "string", "drawTextAligned expects string")
  return g.getFont():drawTextAligned(stripMarkup(text), x, y, align)
end
function g.drawTextInRect(text, x, y, w, h, lead, trunc, align, font)
  if type(x) == "table" then x, y, w, h, lead, trunc, align, font = x.x, x.y, x.width, x.height, y, w, h, lead end
  font = font or g.getFont()
  local line, cy = "", y
  for word in text:gmatch("%S+") do
    local t = line == "" and word or (line .. " " .. word)
    if font:getTextWidth(t) > w and line ~= "" then
      drawGlyphs(font, line, x, cy) cy = cy + font.height + (lead or 0) line = word
    else line = t end
  end
  if line ~= "" then drawGlyphs(font, line, x, cy) end
  return w, cy - y + font.height
end
function g.imageWithText(text, mw, mh)
  local f = g.getFont()
  local w, h = g.getTextSize(text)
  local img = Image.new(math.max(1, math.min(w, mw or w)), math.max(1, h))
  g.pushContext(img) g.drawText(text, 0, 0) g.popContext()
  return img
end

-- perlin ----------------------------------------------------------------
local perm = {}
do
  local seed = 1337
  for i = 0, 255 do perm[i] = i end
  for i = 255, 1, -1 do
    seed = (seed * 1103515245 + 12345) % 2147483648
    local j = seed % (i + 1)
    perm[i], perm[j] = perm[j], perm[i]
  end
  for i = 0, 255 do perm[i + 256] = perm[i] end
end
local function fade(t) return t * t * t * (t * (t * 6 - 15) + 10) end
local function grad(h, x, y, z)
  h = h % 16
  local u = h < 8 and x or y
  local v = h < 4 and y or ((h == 12 or h == 14) and x or z)
  return ((h % 2) == 0 and u or -u) + ((h % 4) < 2 and v or -v)
end
local function noise(x, y, z)
  local X, Y, Z = math.floor(x) % 256, math.floor(y) % 256, math.floor(z) % 256
  x, y, z = x - math.floor(x), y - math.floor(y), z - math.floor(z)
  local u, v, w = fade(x), fade(y), fade(z)
  local A, B = perm[X] + Y, perm[X + 1] + Y
  local AA, AB, BA, BB = perm[A] + Z, perm[A + 1] + Z, perm[B] + Z, perm[B + 1] + Z
  local function lerp(t, a, b) return a + t * (b - a) end
  return lerp(w, lerp(v, lerp(u, grad(perm[AA], x, y, z), grad(perm[BA], x - 1, y, z)),
    lerp(u, grad(perm[AB], x, y - 1, z), grad(perm[BB], x - 1, y - 1, z))),
    lerp(v, lerp(u, grad(perm[AA + 1], x, y, z - 1), grad(perm[BA + 1], x - 1, y, z - 1)),
      lerp(u, grad(perm[AB + 1], x, y - 1, z - 1), grad(perm[BB + 1], x - 1, y - 1, z - 1))))
end
function g.perlin(x, y, z, rep, oct, pers)
  checkNum(x, "x") checkNum(y, "y") checkNum(z, "z")
  oct = oct or 1 pers = pers or 0.5
  local total, amp, freq, maxv = 0, 1, 1, 0
  for _ = 1, oct do
    total = total + noise(x * freq, y * freq, z * freq) * amp
    maxv = maxv + amp amp = amp * pers freq = freq * 2
  end
  return math.max(0, math.min(1, (total / maxv) * 0.5 + 0.5))
end
function g.perlinArray(count, x, dx, y, dy, z, dz, rep, oct, pers)
  local out = {}
  for i = 1, count do out[i] = g.perlin(x + dx * (i - 1), y + dy * (i - 1), z + dz * (i - 1), rep, oct, pers) end
  return out
end

------------------------------------------------------------------------
-- import
------------------------------------------------------------------------
M.sourceDir = "source"
local imported = {}
function import(path)
  if path:match("^CoreLibs/") then return end
  local p = path:gsub("%.lua$", "")
  if imported[p] then return end
  imported[p] = true
  local chunk, err = loadfile(M.sourceDir .. "/" .. p .. ".lua")
  if not chunk then error("import failed: " .. err, 2) end
  chunk()
end

------------------------------------------------------------------------
-- harness helpers
------------------------------------------------------------------------
function M.beginFrame()
  M.drawCalls = 0
  -- reset per-frame draw state the way the device does between updates
  ctx.ox, ctx.oy = 0, 0
end

function M.endFrame()
  if not (#ctxStack == 0) then error("graphics context stack not balanced at end of frame (" .. #ctxStack .. ")", 2) end
  M.frame = M.frame + 1
  M.ms = M.ms + math.floor(1000 / 30 + 0.5)
end

function M.savePBM(path)
  local f = assert(io.open(path, "wb"))
  f:write("P1\n" .. W .. " " .. H .. "\n")
  local inv = M.inverted
  local buf = {}
  for y = 0, H - 1 do
    local row = {}
    for x = 0, W - 1 do
      local v = screen.pix[y * W + x + 1]
      if inv then v = 1 - v end
      row[#row + 1] = v == 1 and "0" or "1"
    end
    buf[#buf + 1] = table.concat(row, " ")
  end
  f:write(table.concat(buf, "\n"))
  f:close()
end

-- fraction of black pixels (used by tests to detect blank screens)
function M.inkRatio()
  local black = 0
  for i = 1, W * H do if screen.pix[i] == 0 then black = black + 1 end end
  return black / (W * H)
end

return M
