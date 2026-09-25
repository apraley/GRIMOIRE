-- CRANKING IT :: core/input
-- Polls buttons and crank once per frame and exposes held/pressed state plus
-- d-pad auto-repeat for menus. The scene manager routes the events.

Input = {}

local pd <const> = playdate
Input.A = pd.kButtonA
Input.B = pd.kButtonB
Input.UP = pd.kButtonUp
Input.DOWN = pd.kButtonDown
Input.LEFT = pd.kButtonLeft
Input.RIGHT = pd.kButtonRight

Input.ORDER = { pd.kButtonLeft, pd.kButtonRight, pd.kButtonUp, pd.kButtonDown, pd.kButtonB, pd.kButtonA }

Input.cur, Input.pressed, Input.released = 0, 0, 0
Input.crankChange, Input.crankAccel = 0, 0
Input.heldTime = {}
for _, b in ipairs(Input.ORDER) do Input.heldTime[b] = 0 end

local REPEAT_DELAY <const> = 0.32
local REPEAT_RATE <const> = 0.075
local repeatFire = {}

function Input.poll(dt)
  local cur, pressed, released = pd.getButtonState()
  Input.cur, Input.pressed, Input.released = cur, pressed, released
  Input.crankChange, Input.crankAccel = pd.getCrankChange()
  for _, b in ipairs(Input.ORDER) do
    repeatFire[b] = false
    if (cur & b) ~= 0 then
      local before = Input.heldTime[b]
      local after = before + dt
      Input.heldTime[b] = after
      if before >= REPEAT_DELAY then
        local n0 = (before - REPEAT_DELAY) // REPEAT_RATE
        local n1 = (after - REPEAT_DELAY) // REPEAT_RATE
        if n1 > n0 then repeatFire[b] = true end
      elseif after >= REPEAT_DELAY then
        repeatFire[b] = true
      end
    else
      Input.heldTime[b] = 0
    end
  end
end

function Input.held(b) return (Input.cur & b) ~= 0 end
function Input.justPressed(b) return (Input.pressed & b) ~= 0 end
function Input.justReleased(b) return (Input.released & b) ~= 0 end
function Input.holdTime(b) return Input.heldTime[b] or 0 end

-- true on first press and on auto-repeat ticks (menus, counters)
function Input.repeated(b)
  return (Input.pressed & b) ~= 0 or repeatFire[b]
end

-- horizontal / vertical axis from the d-pad (-1, 0, 1)
function Input.axisX()
  local x = 0
  if (Input.cur & pd.kButtonLeft) ~= 0 then x = x - 1 end
  if (Input.cur & pd.kButtonRight) ~= 0 then x = x + 1 end
  return x
end
function Input.axisY()
  local y = 0
  if (Input.cur & pd.kButtonUp) ~= 0 then y = y - 1 end
  if (Input.cur & pd.kButtonDown) ~= 0 then y = y + 1 end
  return y
end

Input.NAMES = {
  [pd.kButtonA] = "A", [pd.kButtonB] = "B", [pd.kButtonUp] = "UP",
  [pd.kButtonDown] = "DOWN", [pd.kButtonLeft] = "LEFT", [pd.kButtonRight] = "RIGHT",
}
