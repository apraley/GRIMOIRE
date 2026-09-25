-- Input: button edges with key repeat, crank deltas and crank "tickers".
--
-- We poll (playdate.buttonJustPressed etc.) once per frame instead of using
-- input-handler callbacks so every screen sees a consistent snapshot. While
-- the system keyboard is up, or for a few frames after it closes, input is
-- suppressed so the keyboard's own A/B presses don't leak into the screen.

Input = {
	blockFrames = 0,
	held = {},        -- button -> ms held
	fired = {},       -- button -> fired this frame (press or repeat)
	crank = 0,        -- degrees this frame (0 when docked)
	docked = false,
	REPEAT_DELAY = 320,
	REPEAT_RATE = 90,
}

local BUTTONS = {}

function Input.init()
	BUTTONS = {
		playdate.kButtonUp, playdate.kButtonDown, playdate.kButtonLeft,
		playdate.kButtonRight, playdate.kButtonA, playdate.kButtonB,
	}
end

function Input.block(frames)
	Input.blockFrames = math.max(Input.blockFrames, frames or 2)
end

function Input.update(dtMs)
	local blocked = Input.blockFrames > 0 or (playdate.keyboard and playdate.keyboard.isVisible())
	if Input.blockFrames > 0 then Input.blockFrames = Input.blockFrames - 1 end
	Input.fired = {}
	Input.docked = playdate.isCrankDocked()
	if blocked then
		Input.crank = 0
		Input.held = {}
		return
	end
	local change = playdate.getCrankChange()
	Input.crank = Input.docked and 0 or change
	for _, b in ipairs(BUTTONS) do
		if playdate.buttonJustPressed(b) then
			Input.held[b] = 0
			Input.fired[b] = true
		elseif playdate.buttonIsPressed(b) and Input.held[b] then
			local before = Input.held[b]
			local after = before + dtMs
			Input.held[b] = after
			-- Repeat only for the d-pad.
			if b ~= playdate.kButtonA and b ~= playdate.kButtonB and after >= Input.REPEAT_DELAY then
				local n1 = math.max(0, (before - Input.REPEAT_DELAY) // Input.REPEAT_RATE)
				local n2 = (after - Input.REPEAT_DELAY) // Input.REPEAT_RATE
				if before < Input.REPEAT_DELAY or n2 > n1 then Input.fired[b] = true end
			end
		else
			Input.held[b] = nil
		end
	end
end

function Input.pressed(b) return Input.fired[b] == true end
function Input.up() return Input.fired[playdate.kButtonUp] == true end
function Input.down() return Input.fired[playdate.kButtonDown] == true end
function Input.left() return Input.fired[playdate.kButtonLeft] == true end
function Input.right() return Input.fired[playdate.kButtonRight] == true end
function Input.a() return Input.fired[playdate.kButtonA] == true end
function Input.b() return Input.fired[playdate.kButtonB] == true end

-- Vertical d-pad as -1/0/+1.
function Input.vertical()
	if Input.up() then return -1 end
	if Input.down() then return 1 end
	return 0
end

function Input.horizontal()
	if Input.left() then return -1 end
	if Input.right() then return 1 end
	return 0
end

---------------------------------------------------------------------------
-- Crank tickers turn continuous degrees into discrete detents.

CrankTicker = {}
CrankTicker.__index = CrankTicker

function CrankTicker.new(degPerTick)
	return setmetatable({ deg = degPerTick or 30, acc = 0 }, CrankTicker)
end

-- Returns whole ticks (can be negative) for this frame's crank movement.
function CrankTicker:update(delta)
	delta = delta or Input.crank
	if delta == 0 then return 0 end
	self.acc = self.acc + delta
	local ticks = 0
	while self.acc >= self.deg do
		self.acc = self.acc - self.deg
		ticks = ticks + 1
	end
	while self.acc <= -self.deg do
		self.acc = self.acc + self.deg
		ticks = ticks - 1
	end
	return ticks
end

function CrankTicker:reset()
	self.acc = 0
end

