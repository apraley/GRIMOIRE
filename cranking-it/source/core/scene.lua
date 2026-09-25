-- CRANKING IT :: core/scene
-- Scene manager with mechanical transitions (shutter, iris, wipe), screen
-- shake and flash. A scene is any table with optional methods:
--   enter(params) exit() update(dt) draw() cranked(change, accel)
--   buttonDown(button) buttonUp(button)

Scene = {}

local gfx <const> = playdate.graphics
local floor <const> = math.floor

Scene.current = nil
local trans = nil      -- {style, t, dur, target, params, switched}
local shakeMag = 0
local flashFrames = 0
local irisImg = nil

local function callIf(s, name, ...)
  if s and s[name] then return s[name](s, ...) end
end

function Scene.go(target, params, style, dur)
  if trans and trans.target == target then return end
  style = style or "shutter"
  if style == "cut" or not Scene.current then
    callIf(Scene.current, "exit")
    Scene.current = target
    callIf(target, "enter", params or {})
    return
  end
  trans = { style = style, t = 0, dur = dur or 0.55, target = target, params = params or {}, switched = false }
  Audio.sfx.whoosh(0.15)
end

function Scene.transitioning() return trans ~= nil end

function Scene.shake(mag)
  if Save.data and Save.data.settings.reduceShake then mag = mag * 0.3 end
  shakeMag = math.max(shakeMag, mag)
end

function Scene.flash(frames)
  if playdate.getReduceFlashing() then return end
  flashFrames = math.max(flashFrames, frames or 2)
end

function Scene.update(dt)
  if trans then
    trans.t = trans.t + dt
    if not trans.switched and trans.t >= trans.dur / 2 then
      trans.switched = true
      callIf(Scene.current, "exit")
      Scene.current = trans.target
      callIf(Scene.current, "enter", trans.params)
    end
    if trans.t >= trans.dur then trans = nil end
    -- the outgoing scene is frozen; the incoming one animates while opening
    if trans and not trans.switched then return end
  end
  callIf(Scene.current, "update", dt)
end

-- cover amount 0..1 (1 = fully covered)
local function coverAmount()
  if not trans then return 0 end
  local p = trans.t / trans.dur
  if p < 0.5 then return U.smoothstep(p * 2) end
  return U.smoothstep((1 - p) * 2)
end

local function drawCover(style, c)
  if c <= 0 then return end
  gfx.setColor(gfx.kColorBlack)
  if style == "shutter" then
    local slats = 8
    local sh = 240 / slats
    for i = 0, slats - 1 do
      gfx.fillRect(0, i * sh, 400, math.ceil(sh * c))
    end
  elseif style == "iris" then
    if not irisImg then irisImg = gfx.image.new(400, 240, gfx.kColorClear) end
    local r = (1 - c) * 240
    gfx.pushContext(irisImg)
    gfx.clear(gfx.kColorBlack)
    if r > 0.5 then
      gfx.setColor(gfx.kColorClear)
      gfx.fillCircleAtPoint(200, 120, r)
    end
    gfx.popContext()
    irisImg:draw(0, 0)
  elseif style == "wipe" then
    local w = floor(420 * c)
    gfx.fillRect(0, 0, w, 240)
    -- ragged woodcut edge
    for y = 0, 240, 12 do
      gfx.fillTriangle(w, y, w + 10, y + 6, w, y + 12)
    end
  else
    gfx.setDitherPattern(1 - c, gfx.kDitherTypeBayer8x8)
    gfx.fillRect(0, 0, 400, 240)
  end
  gfx.setColor(gfx.kColorBlack)
end

function Scene.draw()
  callIf(Scene.current, "draw")
  if trans then drawCover(trans.style, coverAmount()) end
  if flashFrames > 0 then
    flashFrames = flashFrames - 1
    gfx.setColor(gfx.kColorXOR)
    gfx.fillRect(0, 0, 400, 240)
    gfx.setColor(gfx.kColorBlack)
  end
  -- shake via display offset (cheap, affects whole frame)
  if shakeMag > 0.3 then
    local ox = (math.random() * 2 - 1) * shakeMag
    local oy = (math.random() * 2 - 1) * shakeMag
    playdate.display.setOffset(floor(ox), floor(oy))
    shakeMag = shakeMag * 0.82
  elseif shakeMag > 0 then
    shakeMag = 0
    playdate.display.setOffset(0, 0)
  end
end

function Scene.cranked(change, accel)
  if trans then return end
  callIf(Scene.current, "cranked", change, accel)
end

function Scene.buttonDown(b)
  if trans then return end
  callIf(Scene.current, "buttonDown", b)
end

function Scene.buttonUp(b)
  if trans then return end
  callIf(Scene.current, "buttonUp", b)
end
