-- Input snapshot, read once per frame. Scenes receive `In`:
--   In.a In.b In.up In.down In.left In.right   just pressed this frame
--   In.ah In.bh In.uh In.dh In.lh In.rh        currently held
--   In.ur In.dr In.lr In.rr                     pressed OR auto-repeat (menus)
--   In.crank                                    crank change in degrees
--   In.docked                                   crank docked?

Input = {}
In = {}
local held = { up = 0, down = 0, left = 0, right = 0 }

function Input.read()
  local pd = playdate
  In.a = pd.buttonJustPressed(pd.kButtonA)
  In.b = pd.buttonJustPressed(pd.kButtonB)
  In.up = pd.buttonJustPressed(pd.kButtonUp)
  In.down = pd.buttonJustPressed(pd.kButtonDown)
  In.left = pd.buttonJustPressed(pd.kButtonLeft)
  In.right = pd.buttonJustPressed(pd.kButtonRight)
  In.ah = pd.buttonIsPressed(pd.kButtonA)
  In.bh = pd.buttonIsPressed(pd.kButtonB)
  In.uh = pd.buttonIsPressed(pd.kButtonUp)
  In.dh = pd.buttonIsPressed(pd.kButtonDown)
  In.lh = pd.buttonIsPressed(pd.kButtonLeft)
  In.rh = pd.buttonIsPressed(pd.kButtonRight)
  In.crank = pd.getCrankChange() or 0
  In.docked = pd.isCrankDocked()
  -- auto-repeat for menus: first repeat after 10 frames, then every 3
  local function rep(name, h, jp)
    if h then held[name] = held[name] + 1 else held[name] = 0 end
    local n = held[name]
    return jp or (n > 10 and (n - 10) % 3 == 0)
  end
  In.ur = rep("up", In.uh, In.up)
  In.dr = rep("down", In.dh, In.down)
  In.lr = rep("left", In.lh, In.left)
  In.rr = rep("right", In.rh, In.right)
end

-- Crank accumulator: turns continuous crank motion into discrete steps.
-- local acc = Input.crankStepper(30) ; each frame: local steps = acc(In.crank)
function Input.crankStepper(degPerStep)
  local accum = 0
  return function(delta)
    accum = accum + (delta or 0)
    local steps = 0
    while accum >= degPerStep do accum = accum - degPerStep; steps = steps + 1 end
    while accum <= -degPerStep do accum = accum + degPerStep; steps = steps - 1 end
    return steps
  end
end

-- Clear all input (used right after a scene change so a held A doesn't
-- immediately re-trigger in the next scene)
function Input.clear()
  In.a, In.b, In.up, In.down, In.left, In.right = false, false, false, false, false, false
  In.ur, In.dr, In.lr, In.rr = false, false, false, false
  In.crank = 0
end
