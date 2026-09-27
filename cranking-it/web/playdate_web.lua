-- CRANKING IT web player: the Playdate Lua API on top of runtime.js.
-- Drawing, sound, input, time and storage are forwarded to JavaScript
-- functions (R_* / A_* globals registered by runtime.js); the JSON codec
-- and Perlin noise are pure Lua (shared with tools/mock_playdate.lua).
-- Generated into the web bundle by web/build.py.

local R_newImage, R_free, R_imgW, R_imgH, R_copy, R_imgClear, R_sample = R_newImage, R_free, R_imgW, R_imgH, R_copy, R_imgClear, R_sample
local R_invert, R_removeMask, R_scaled, R_draw, R_drawFaded, R_drawScaled, R_drawRotated = R_invert, R_removeMask, R_scaled, R_draw, R_drawFaded, R_drawScaled, R_drawRotated
local R_push, R_pop = R_push, R_pop
local R_setColor, R_getColor, R_setPattern, R_setDither, R_setLW, R_getLW = R_setColor, R_getColor, R_setPattern, R_setDither, R_setLW, R_getLW
local R_setOffset, R_getOX, R_getOY, R_setClip, R_setScreenClip, R_clearClip, R_getClip = R_setOffset, R_getOX, R_getOY, R_setClip, R_setScreenClip, R_clearClip, R_getClip
local R_setMode, R_getMode, R_setBG, R_getBG = R_setMode, R_getMode, R_setBG, R_getBG
local R_clear, R_fillRect, R_drawRect, R_drawLine, R_drawPixel, R_fillPoly, R_drawPoly = R_clear, R_fillRect, R_drawRect, R_drawLine, R_drawPixel, R_fillPoly, R_drawPoly
local R_ellipseFill, R_ellipseStroke, R_fillRoundRect, R_drawRoundRect = R_ellipseFill, R_ellipseStroke, R_fillRoundRect, R_drawRoundRect
local R_fontH, R_textW, R_drawText = R_fontH, R_textW, R_drawText
local A_new, A_play, A_off, A_adsr, A_vol, A_legato, A_time, A_playing = A_new, A_play, A_off, A_adsr, A_vol, A_legato, A_time, A_playing

playdate = {}
local pd = playdate
pd.isSimulator = false
pd.argv = {}
pd.kButtonLeft, pd.kButtonRight, pd.kButtonUp, pd.kButtonDown = 1, 2, 4, 8
pd.kButtonB, pd.kButtonA = 16, 32
kTextAlignment = { left = 0, right = 1, center = 2 }

------------------------------------------------------------------------
-- time and input
------------------------------------------------------------------------
local elapsedBase = 0
function pd.getCurrentTimeMilliseconds() return R_ms() end
function pd.getElapsedTime() return (R_ms() - elapsedBase) / 1000 end
function pd.resetElapsedTime() elapsedBase = R_ms() end
function pd.getSecondsSinceEpoch() return R_epoch(), R_ms() % 1000 end
function pd.getTime()
  local s = R_date()
  local f = {}
  for n in s:gmatch("[^,]+") do f[#f + 1] = math.tointeger(tonumber(n)) end
  return { year = f[1], month = f[2], day = f[3], weekday = f[4], hour = f[5], minute = f[6], second = f[7], millisecond = f[8] }
end
function pd.getCrankPosition() return R_crankPos() end
function pd.getCrankChange() local c = R_crankChange() return c, c end
function pd.isCrankDocked() return R_docked() end
function pd.setCrankSoundsDisabled() end
function pd.getButtonState() return math.tointeger(R_btn(0)), math.tointeger(R_btn(1)), math.tointeger(R_btn(2)) end
function pd.buttonIsPressed(b) return (R_btn(0) & b) ~= 0 end
function pd.buttonJustPressed(b) return (R_btn(1) & b) ~= 0 end
function pd.buttonJustReleased(b) return (R_btn(2) & b) ~= 0 end
function pd.getReduceFlashing() return false end
function pd.setAutoLockDisabled() end
function pd.stop() end
function pd.start() end
function pd.getFPS() return 30 end
function pd.drawFPS() end
function pd.getStats() return nil end

------------------------------------------------------------------------
-- system menu (shown by the player's MENU button)
------------------------------------------------------------------------
local menuItems = {}
local menu = {}
function menu:addMenuItem(title, cb)
  if #menuItems >= 3 then return nil, "Playdate allows at most three custom menu items" end
  local item = { title = title, cb = cb, kind = "action" }
  function item:setTitle(t) self.title = t end
  function item:getTitle() return self.title end
  function item:setCallback(c) self.cb = c end
  function item:setValue(v) self.value = v end
  function item:getValue() return self.value end
  menuItems[#menuItems + 1] = item
  return item
end
function menu:addCheckmarkMenuItem(title, v, cb)
  local item = menu:addMenuItem(title, cb or function() end)
  if item then item.kind = "check" item.value = v and true or false end
  return item
end
function menu:addOptionsMenuItem(title, opts, v, cb)
  local item = menu:addMenuItem(title, cb or function() end)
  if item then item.kind = "options" item.options = opts item.value = v end
  return item
end
function menu:removeAllMenuItems() for i = #menuItems, 1, -1 do menuItems[i] = nil end end
function menu:removeMenuItem(it)
  for i = #menuItems, 1, -1 do if menuItems[i] == it then table.remove(menuItems, i) end end
end
function menu:getMenuItems() return menuItems end
function pd.getSystemMenu() return menu end
function pd.setMenuImage(img) R_menuImage(img and img.id or -1) end

-- called from JavaScript
__callbacks = {
  menuList = function()
    local out = {}
    for i, it in ipairs(menuItems) do
      local v = ""
      if it.kind == "check" then v = it.value and "on" or "off" end
      out[#out + 1] = it.kind .. "\t" .. it.title .. "\t" .. v
    end
    return table.concat(out, "\n")
  end,
  menuActivate = function(i)
    local it = menuItems[i]
    if not it then return end
    if it.kind == "check" then it.value = not it.value it.cb(it.value) else it.cb() end
  end,
  pause = function() if pd.gameWillPause then pd.gameWillPause() end end,
  resume = function() if pd.gameWillResume then pd.gameWillResume() end end,
  terminate = function() if pd.gameWillTerminate then pd.gameWillTerminate() end end,
}

------------------------------------------------------------------------
-- display
------------------------------------------------------------------------
pd.display = {}
local inverted = false
function pd.display.setRefreshRate(r) R_setFPS(r) end
function pd.display.getRefreshRate() return 30 end
function pd.display.setInverted(f) inverted = f and true or false R_setInverted(inverted) end
function pd.display.getInverted() return inverted end
function pd.display.getWidth() return 400 end
function pd.display.getHeight() return 240 end
function pd.display.getSize() return 400, 240 end
function pd.display.getRect() return 0, 0, 400, 240 end
local dox, doy = 0, 0
function pd.display.setOffset(x, y) dox, doy = x, y R_setDisplayOffset(x, y) end
function pd.display.getOffset() return dox, doy end
function pd.display.setScale() end
function pd.display.getScale() return 1 end
function pd.display.setMosaic() end
function pd.display.flush() end

------------------------------------------------------------------------
-- json
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


------------------------------------------------------------------------
-- datastore (localStorage)
------------------------------------------------------------------------
pd.datastore = {}
function pd.datastore.write(t, name)
  local ok, s = pcall(json.encode, t)
  if ok then R_storeWrite(name or "data", s) else print("datastore.write: " .. tostring(s)) end
end
function pd.datastore.read(name)
  local s = R_storeRead(name or "data")
  if type(s) ~= "string" then return nil end
  local ok, v = pcall(json.decode, s)
  if ok then return v end
  return nil
end
function pd.datastore.delete(name) return R_storeDelete(name or "data") end

------------------------------------------------------------------------
-- sound
------------------------------------------------------------------------
pd.sound = {}
local S = pd.sound
S.kWaveSquare, S.kWaveTriangle, S.kWaveSine, S.kWaveNoise, S.kWaveSawtooth = 0, 1, 2, 3, 4
S.kWavePOPhase, S.kWavePODigital, S.kWavePOVosim = 5, 6, 7
S.kFilterLowPass, S.kFilterHighPass, S.kFilterBandPass = 0, 1, 2
S.kLFOSquare, S.kLFOTriangle, S.kLFOSine, S.kLFOSampleAndHold = 0, 1, 2, 3
function S.getCurrentTime() return A_time() end
function S.resetTime() end
function S.getSampleRate() return 44100 end
function S.playingSources() return {} end
function S.addEffect() end
function S.removeEffect() end
function S.getHeadphoneState() return false end
function S.setOutputsActive() end

local NOTE_OFF = { C = -9, D = -7, E = -5, F = -4, G = -2, A = 0, B = 2 }
local function toHz(p)
  if type(p) == "number" then return p end
  local l, acc, oct = tostring(p):match("^(%u)([#b]?)(%d)$")
  if not l then return 440 end
  local n = NOTE_OFF[l] + (acc == "#" and 1 or (acc == "b" and -1 or 0)) + (tonumber(oct) - 4) * 12
  return 440 * 2 ^ (n / 12)
end

S.synth = {}
S.synth.__index = S.synth
function S.synth.new(wave)
  if type(wave) ~= "number" then wave = 0 end
  return setmetatable({ id = A_new(wave), vol = 1 }, S.synth)
end
function S.synth:playNote(pitch, vol, len, when)
  local hz = toHz(pitch)
  if hz <= 0 then A_off(self.id) return true end
  A_play(self.id, hz, vol or 1, len or -1, when or -1)
  return true
end
function S.synth:playMIDINote(n, vol, len, when)
  return self:playNote(440 * 2 ^ ((n - 69) / 12), vol, len, when)
end
function S.synth:noteOff() A_off(self.id) end
function S.synth:stop() A_off(self.id) end
function S.synth:isPlaying() return A_playing(self.id) end
function S.synth:setADSR(a, d, s, r) self.a, self.d, self.s, self.r = a, d, s, r A_adsr(self.id, a, d, s, r) end
function S.synth:setAttack(v) self.a = v A_adsr(self.id, v, self.d or 0.08, self.s or 0, self.r or 0.05) end
function S.synth:setDecay(v) self.d = v A_adsr(self.id, self.a or 0.002, v, self.s or 0, self.r or 0.05) end
function S.synth:setSustain(v) self.s = v A_adsr(self.id, self.a or 0.002, self.d or 0.08, v, self.r or 0.05) end
function S.synth:setRelease(v) self.r = v A_adsr(self.id, self.a or 0.002, self.d or 0.08, self.s or 0, v) end
function S.synth:setVolume(l) self.vol = l A_vol(self.id, l) end
function S.synth:getVolume() return self.vol end
function S.synth:setWaveform() end
function S.synth:setLegato(f) A_legato(self.id, f and true or false) end
function S.synth:setParameter() end
function S.synth:setFrequencyMod() end
function S.synth:setAmplitudeMod() end
function S.synth:setFinishCallback() end
function S.synth:setEnvelopeCurvature() end
function S.synth:clearEnvelope() end
function S.synth:copy() return S.synth.new(0) end

local function stubClass(names)
  local C = {}
  C.__index = C
  C.new = function() return setmetatable({}, C) end
  for _, n in ipairs(names) do C[n] = function() return true end end
  return C
end
S.channel = stubClass({ "addSource", "removeSource", "addEffect", "removeEffect", "setVolume", "setPan", "remove" })
function S.channel:getVolume() return 1 end
S.twopolefilter = stubClass({ "setFrequency", "setResonance", "setMix", "setType" })
S.lfo = stubClass({ "setRate", "setDepth", "setCenter", "setType" })

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
g.kWrapClip, g.kWrapCharacter, g.kWrapWord = 16777216, 16777217, 16777218

local MODES = {
  copy = 0, whiteTransparent = 1, blackTransparent = 2, fillWhite = 3,
  fillBlack = 4, XOR = 5, NXOR = 6, inverted = 7,
}
local FLIPS = { flipX = 1, flipY = 2, flipXY = 3 }
local function flipOf(f)
  if f == nil then return 0 end
  if type(f) == "string" then return FLIPS[f] or 0 end
  return f
end
local function rectArgs(x, y, w, h)
  if type(x) == "table" then return x.x, x.y, x.width, x.height end
  return x, y, w, h
end

-- images ----------------------------------------------------------------
g.image = {}
g.image.kDitherTypeNone, g.image.kDitherTypeDiagonalLine, g.image.kDitherTypeVerticalLine, g.image.kDitherTypeHorizontalLine = 0, 1, 2, 3
g.image.kDitherTypeScreen, g.image.kDitherTypeBayer2x2, g.image.kDitherTypeBayer4x4, g.image.kDitherTypeBayer8x8 = 4, 5, 6, 7
g.image.kDitherTypeFloydSteinberg, g.image.kDitherTypeBurkes, g.image.kDitherTypeAtkinson = 8, 9, 10
local Image = g.image
Image.__index = Image
Image.__gc = function(self) if self.id and self.id > 0 then R_free(self.id) end end
local function wrap(id)
  return setmetatable({ id = id, w = math.tointeger(R_imgW(id)), h = math.tointeger(R_imgH(id)) }, Image)
end
function Image.new(w, h, bg)
  if type(w) == "string" then return nil, "no image files in the web player" end
  return wrap(R_newImage(math.floor(w), math.floor(h), bg or g.kColorClear))
end
function Image:getSize() return self.w, self.h end
function Image:copy() return wrap(R_copy(self.id)) end
function Image:clear(c) R_imgClear(self.id, c) end
function Image:sample(x, y) return R_sample(self.id, math.floor(x), math.floor(y)) end
function Image:hasMask() return true end
function Image:addMask() end
function Image:removeMask() R_removeMask(self.id) end
function Image:setInverted(f) if f then R_invert(self.id) end end
function Image:invertedImage() local c = self:copy() R_invert(c.id) return c end
function Image:fadedImage() return self:copy() end
function Image:scaledImage(s, sy) return wrap(R_scaled(self.id, s, sy or s)) end
function Image:rotatedImage() return self:copy() end
function Image:blurredImage() return self:copy() end
function Image:vcrPauseFilterImage() return self:copy() end
function Image:draw(x, y, flip, sr)
  if type(x) == "table" then x, y, flip, sr = x.x, x.y, y, flip end
  if type(sr) == "table" then
    R_draw(self.id, x, y, flipOf(flip), sr.x, sr.y, sr.width, sr.height)
  else
    R_draw(self.id, x, y, flipOf(flip))
  end
end
function Image:drawIgnoringOffset(x, y, flip)
  local ox, oy = R_getOX(), R_getOY()
  R_setOffset(0, 0)
  self:draw(x, y, flip)
  R_setOffset(ox, oy)
end
function Image:drawCentered(x, y, flip) self:draw(x - self.w // 2, y - self.h // 2, flip) end
function Image:drawAnchored(x, y, ax, ay, flip) self:draw(x - math.floor(self.w * ax), y - math.floor(self.h * ay), flip) end
function Image:drawFaded(x, y, alpha, dt, flip) R_drawFaded(self.id, x, y, alpha, flipOf(flip)) end
function Image:drawTiled(x, y, w, h, flip)
  if type(x) == "table" then x, y, w, h, flip = x.x, x.y, x.width, x.height, y end
  for ty = 0, h - 1, self.h do for tx = 0, w - 1, self.w do self:draw(x + tx, y + ty, flip) end end
end
function Image:drawScaled(x, y, s, sy) R_drawScaled(self.id, x, y, s, sy or s) end
function Image:drawRotated(x, y, angle, s, sy) s = s or 1 R_drawRotated(self.id, x, y, angle, s, sy or s) end
function Image:drawBlurred(x, y) self:draw(x, y) end
function Image:drawWithTransform(xf, x, y) self:draw(x, y) end
function Image:drawSampled() end

g.imagetable = {}
function g.imagetable.new() return nil end

local screenImage = setmetatable({ id = 0, w = 400, h = 240 }, Image)

-- context & state ---------------------------------------------------------
function g.pushContext(img) R_push(img and img.id or -1) end
function g.popContext() R_pop() end
function g.lockFocus(img) R_push(img and img.id or -1) end
function g.unlockFocus() R_pop() end
function g.setColor(c) R_setColor(c) end
function g.getColor() return math.tointeger(R_getColor()) end
function g.setPattern(p, x, y)
  if getmetatable(p) == Image then R_setPattern(255, 255, 255, 255, 255, 255, 255, 255) return end
  R_setPattern(table.unpack(p))
end
function g.setDitherPattern(alpha) R_setDither(alpha) end
function g.setLineWidth(w) R_setLW(w) end
function g.getLineWidth() return R_getLW() end
function g.setLineCapStyle() end
local strokeLoc = 0
function g.setStrokeLocation(l) strokeLoc = l end
function g.getStrokeLocation() return strokeLoc end
function g.setPolygonFillRule() end
function g.setDrawOffset(x, y) R_setOffset(x, y) end
function g.getDrawOffset() return R_getOX(), R_getOY() end
function g.setClipRect(x, y, w, h) x, y, w, h = rectArgs(x, y, w, h) R_setClip(x, y, w, h) end
function g.setScreenClipRect(x, y, w, h) x, y, w, h = rectArgs(x, y, w, h) R_setScreenClip(x, y, w, h) end
function g.getClipRect() return R_getClip(0), R_getClip(1), R_getClip(2), R_getClip(3) end
function g.clearClipRect() R_clearClip() end
function g.setImageDrawMode(m)
  if type(m) == "string" then m = MODES[m] or 0 end
  R_setMode(m)
end
function g.getImageDrawMode() return math.tointeger(R_getMode()) end
function g.setBackgroundColor(c) R_setBG(c) end
function g.getBackgroundColor() return math.tointeger(R_getBG()) end
function g.setStencilImage() end
function g.setStencilPattern() end
function g.clearStencil() end
function g.clearStencilImage() end
function g.getDisplayImage() return wrap(R_copy(0)) end
function g.getWorkingImage() return wrap(R_copy(0)) end

-- primitives -----------------------------------------------------------------
function g.clear(c) R_clear(c) end
function g.fillRect(x, y, w, h) x, y, w, h = rectArgs(x, y, w, h) R_fillRect(x, y, w, h) end
function g.drawRect(x, y, w, h) x, y, w, h = rectArgs(x, y, w, h) R_drawRect(x, y, w, h) end
function g.drawLine(x1, y1, x2, y2)
  if type(x1) == "table" then x1, y1, x2, y2 = x1.x, x1.y, x1.x2 or x1.x, x1.y2 or x1.y end
  R_drawLine(x1, y1, x2, y2)
end
function g.drawPixel(x, y) if type(x) == "table" then x, y = x.x, x.y end R_drawPixel(x, y) end
local function polyUnpack(first, ...)
  if type(first) == "table" then return table.unpack(first) end
  return first, ...
end
function g.fillPolygon(...) R_fillPoly(polyUnpack(...)) end
function g.drawPolygon(...) R_drawPoly(polyUnpack(...)) end
function g.fillTriangle(x1, y1, x2, y2, x3, y3) R_fillPoly(x1, y1, x2, y2, x3, y3) end
function g.drawTriangle(x1, y1, x2, y2, x3, y3) R_drawPoly(x1, y1, x2, y2, x3, y3) end
function g.fillCircleAtPoint(x, y, r)
  if type(x) == "table" then x, y, r = x.x, x.y, y end
  R_ellipseFill(x + 0.5, y + 0.5, r, r)
end
function g.drawCircleAtPoint(x, y, r)
  if type(x) == "table" then x, y, r = x.x, x.y, y end
  R_ellipseStroke(x, y, r, r)
end
function g.fillCircleInRect(x, y, w, h) x, y, w, h = rectArgs(x, y, w, h) R_ellipseFill(x + w / 2, y + h / 2, w / 2, h / 2) end
function g.drawCircleInRect(x, y, w, h) x, y, w, h = rectArgs(x, y, w, h) R_ellipseStroke(x + w / 2, y + h / 2, w / 2, h / 2) end
function g.fillEllipseInRect(x, y, w, h, a0, a1)
  if type(x) == "table" then x, y, w, h, a0, a1 = x.x, x.y, x.width, x.height, y, w end
  R_ellipseFill(x + w / 2, y + h / 2, w / 2, h / 2, a0, a1)
end
function g.drawEllipseInRect(x, y, w, h, a0, a1)
  if type(x) == "table" then x, y, w, h, a0, a1 = x.x, x.y, x.width, x.height, y, w end
  R_ellipseStroke(x + w / 2, y + h / 2, w / 2, h / 2, a0, a1)
end
function g.drawArc(x, y, r, a0, a1)
  if type(x) == "table" then x, y, r, a0, a1 = x.x, x.y, x.radius, x.startAngle, x.endAngle end
  R_ellipseStroke(x, y, r, r, a0, a1)
end
function g.fillRoundRect(x, y, w, h, r)
  if type(x) == "table" then x, y, w, h, r = x.x, x.y, x.width, x.height, y end
  R_fillRoundRect(x, y, w, h, r)
end
function g.drawRoundRect(x, y, w, h, r)
  if type(x) == "table" then x, y, w, h, r = x.x, x.y, x.width, x.height, y end
  R_drawRoundRect(x, y, w, h, r)
end
function g.drawSineWave(sx, sy, ex, ey, a0, a1, period, phase)
  local n = math.max(2, math.floor(math.abs(ex - sx) + math.abs(ey - sy)))
  local px, py
  for i = 0, n do
    local t = i / n
    local x = sx + (ex - sx) * t
    local amp = a0 + (a1 - a0) * t
    local y = sy + (ey - sy) * t + math.sin(((x - sx) / period) * 2 * math.pi + (phase or 0)) * amp
    if px then R_drawLine(px, py, x, y) end
    px, py = x, y
  end
end

-- fonts ----------------------------------------------------------------------
g.font = {}
local Font = g.font
Font.__index = Font
Font.kVariantNormal, Font.kVariantBold, Font.kVariantItalic = "normal", "bold", "italic"
local FONT_H = math.tointeger(R_fontH())
local function makeFont(fid) return setmetatable({ fid = fid, tracking = 0, leading = 0 }, Font) end
local sysNormal, sysBold = makeFont(0), makeFont(1)
local currentFont = nil
function Font.new() return makeFont(0) end
function Font.newFamily() return { [Font.kVariantNormal] = sysNormal, [Font.kVariantBold] = sysBold } end
function Font:getHeight() return FONT_H end
function Font:getLeading() return self.leading end
function Font:setLeading(l) self.leading = l end
function Font:getTracking() return self.tracking end
function Font:setTracking(t) self.tracking = t end
function Font:getTextWidth(text) return math.tointeger(R_textW(self.fid, text, self.tracking)) end
function Font:getGlyph() return Image.new(8, FONT_H) end
function Font:drawText(text, x, y)
  local w = R_drawText(self.fid, text, x, y, self.tracking, self.leading)
  return w, FONT_H
end
function Font:drawTextAligned(text, x, y, align)
  local w = R_textW(self.fid, text, self.tracking)
  if align == kTextAlignment.center then x = x - w / 2 elseif align == kTextAlignment.right then x = x - w end
  return self:drawText(text, math.floor(x), y)
end
function g.getSystemFont(variant)
  if variant == "bold" or variant == Font.kVariantBold then return sysBold end
  return sysNormal
end
function g.setFont(f) currentFont = f end
function g.getFont() return currentFont or sysNormal end
function g.setFontFamily() end
local fontTracking = 0
function g.setFontTracking(t) fontTracking = t end
function g.getFontTracking() return fontTracking end
local function stripMarkup(text)
  return (text:gsub("%*%*", "\1"):gsub("__", "\2"):gsub("[%*_]", ""):gsub("\1", "*"):gsub("\2", "_"))
end
function g.drawText(text, x, y)
  if type(x) == "table" then x, y = x.x, x.y end
  return g.getFont():drawText(stripMarkup(text), x, y)
end
function g.getTextSize(text, font)
  font = font or g.getFont()
  local lines = 1
  for _ in text:gmatch("\n") do lines = lines + 1 end
  return font:getTextWidth(stripMarkup(text)), lines * FONT_H
end
function g.drawTextAligned(text, x, y, align) return g.getFont():drawTextAligned(stripMarkup(text), x, y, align) end
function g.drawTextInRect(text, x, y, w, h, lead, trunc, align, font)
  if type(x) == "table" then x, y, w, h, lead, trunc, align, font = x.x, x.y, x.width, x.height, y, w, h, lead end
  font = font or g.getFont()
  local line, cy = "", y
  for word in text:gmatch("%S+") do
    local t = line == "" and word or (line .. " " .. word)
    if font:getTextWidth(t) > w and line ~= "" then
      font:drawText(line, x, cy) cy = cy + FONT_H + (lead or 0) line = word
    else line = t end
  end
  if line ~= "" then font:drawText(line, x, cy) end
  return w, cy - y + FONT_H
end
function g.imageWithText(text, mw, mh)
  local w, h = g.getTextSize(text)
  local img = Image.new(math.max(1, math.min(w, mw or w)), math.max(1, h))
  g.pushContext(img) g.drawText(text, 0, 0) g.popContext()
  return img
end

local function checkNum() end
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
-- import: sources are bundled by web/build.py
------------------------------------------------------------------------
local imported = {}
function import(path)
  if path:match("^CoreLibs/") then return end
  local p = path:gsub("%.lua$", "")
  if imported[p] then return end
  imported[p] = true
  local src = R_source(p)
  if not src then error("import: no source for " .. p, 2) end
  local chunk, err = load(src, "@" .. p .. ".lua")
  if not chunk then error("import failed: " .. err, 2) end
  chunk()
end

print = function(...)
  local t = {}
  for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
  R_print(table.concat(t, "\t"))
end
