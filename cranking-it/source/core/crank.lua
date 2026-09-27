-- CRANKING IT :: core/crank
-- Crank utilities shared by every machine. None of these substitute the
-- crank for a d-pad: they turn raw degree deltas into physical quantities
-- (velocity, detent clicks, direction reversals, flywheel momentum).

Crank = {}

local abs <const> = math.abs

-- global modifiers (set by PlayScene for challenge mods like RUSTY)
Crank.scale = 1

function Crank.docked() return playdate.isCrankDocked() end
function Crank.position() return playdate.getCrankPosition() end

------------------------------------------------------------------------
-- Tracker: velocity (deg/s), total rotation, revolutions, reversals.
------------------------------------------------------------------------
local Tracker = U.class()
Crank.Tracker = Tracker

function Tracker:init(smoothing)
  self.total = 0        -- accumulated signed degrees
  self.vel = 0          -- smoothed deg/s
  self.rawVel = 0       -- last frame deg/s
  self.dir = 0          -- -1, 0, 1 current direction
  self.lastDir = 0      -- last non-zero direction
  self.reversed = false -- true on the frame direction flipped
  self.reversals = 0
  self.sinceReverse = 0 -- degrees travelled since last reversal
  self.idle = 0         -- seconds since last movement
  self.smoothing = smoothing or 10
  self.pending = 0
end

-- feed a raw change (degrees); call from cranked()
function Tracker:feed(change)
  self.pending = self.pending + change
end

-- integrate once per update with dt
function Tracker:update(dt)
  local change = self.pending
  self.pending = 0
  self.total = self.total + change
  self.rawVel = change / dt
  self.vel = U.damp(self.vel, self.rawVel, self.smoothing, dt)
  self.reversed = false
  if abs(change) > 0.05 then
    local d = change > 0 and 1 or -1
    if self.lastDir ~= 0 and d ~= self.lastDir then
      self.reversed = true
      self.reversals = self.reversals + 1
      self.sinceReverse = 0
    end
    self.dir = d
    self.lastDir = d
    self.sinceReverse = self.sinceReverse + abs(change)
    self.idle = 0
  else
    self.dir = 0
    self.idle = self.idle + dt
  end
  return change
end

function Tracker:revolutions() return self.total / 360 end

-- revolutions per second (smoothed)
function Tracker:rps() return self.vel / 360 end

------------------------------------------------------------------------
-- Detent: counts crossings of evenly spaced notches (ratchets, dials,
-- clicking spools). Returns the number of notches crossed this call,
-- signed by direction.
------------------------------------------------------------------------
local Detent = U.class()
Crank.Detent = Detent

function Detent:init(perRev, offset)
  self.step = 360 / perRev
  self.pos = offset or 0
end

function Detent:feed(change)
  local before = self.pos // self.step
  self.pos = self.pos + change
  local after = self.pos // self.step
  return after - before
end

function Detent:index() return self.pos // self.step end

------------------------------------------------------------------------
-- Flywheel: a rotating mass driven through a coupling. Useful when a
-- machine must keep turning after the hand lets go.
--   torque from the hand = stiffness * (handVel - wheelVel)
------------------------------------------------------------------------
local Flywheel = U.class()
Crank.Flywheel = Flywheel

function Flywheel:init(inertia, friction, coupling)
  self.inertia = inertia or 1
  self.friction = friction or 0.5 -- viscous, per second
  self.coupling = coupling or 8    -- how strongly the hand grips
  self.vel = 0                     -- deg/s
  self.angle = 0
  self.handVel = 0
  self.gripped = true
end

function Flywheel:hand(change, dt)
  self.handVel = change / dt
end

function Flywheel:update(dt, externalTorque)
  local torque = externalTorque or 0
  if self.gripped then
    torque = torque + (self.handVel - self.vel) * self.coupling
  end
  self.vel = self.vel + torque / self.inertia * dt
  self.vel = self.vel * math.exp(-self.friction * dt)
  self.angle = self.angle + self.vel * dt
  self.handVel = 0
  return self.vel
end

------------------------------------------------------------------------
-- Gesture helpers
------------------------------------------------------------------------
-- A "flick" detector: returns peak velocity of a short burst that ended.
local Flick = U.class()
Crank.Flick = Flick
function Flick:init(threshold)
  self.threshold = threshold or 400
  self.peak = 0
  self.active = false
end
function Flick:update(vel)
  local av = abs(vel)
  if av > self.threshold then
    self.active = true
    if av > self.peak then self.peak = av end
    return nil
  elseif self.active and av < self.threshold * 0.5 then
    local p = self.peak
    self.active = false
    self.peak = 0
    return p
  end
  return nil
end

-- Oscillation detector: counts small alternating back-and-forth motions
-- (jiggling a rope, rocking a lever).
local Jiggle = U.class()
Crank.Jiggle = Jiggle
function Jiggle:init(maxAmplitude)
  self.maxAmp = maxAmplitude or 40
  self.run = 0
  self.lastDir = 0
  self.energy = 0
end
function Jiggle:feed(change, dt)
  if abs(change) < 0.2 then
    self.energy = math.max(0, self.energy - dt * 0.8)
    return self.energy
  end
  local d = change > 0 and 1 or -1
  self.run = self.run + abs(change)
  if d ~= self.lastDir and self.lastDir ~= 0 then
    if self.run < self.maxAmp then
      self.energy = math.min(1, self.energy + 0.18)
    else
      self.energy = math.max(0, self.energy - 0.3)
    end
    self.run = 0
  end
  self.lastDir = d
  self.energy = math.max(0, self.energy - dt * 0.4)
  return self.energy
end
