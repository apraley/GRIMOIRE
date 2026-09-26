-- Input: turns raw button state and crank deltas into events.
--
-- Events: "A", "B" (tap, fired on release), "AL", "BL" (long press, fired once
-- when the hold threshold passes, no tap follows), "UP", "DOWN", "LEFT",
-- "RIGHT" (fired on press, then auto-repeat while held).

Input = {}

local K = {
	A = playdate.kButtonA, B = playdate.kButtonB, UP = playdate.kButtonUp, DOWN = playdate.kButtonDown,
	LEFT = playdate.kButtonLeft, RIGHT = playdate.kButtonRight,
}
local DIRS = { "UP", "DOWN", "LEFT", "RIGHT" }

local REPEAT_DELAY, REPEAT_EVERY = 320, 75

local state = {
	A = { down = false, at = 0, long = false },
	B = { down = false, at = 0, long = false },
	UP = { down = false, at = 0, next = 0 }, DOWN = { down = false, at = 0, next = 0 },
	LEFT = { down = false, at = 0, next = 0 }, RIGHT = { down = false, at = 0, next = 0 },
}

Input.events = {}
Input.crankChange = 0
Input.crankAccel = 0
Input.lastInputMs = 0
Input.holdMs = 450
Input.suppress = false -- set while the system keyboard owns input

function Input.isDown(name) return state[name].down end

-- Progress (0..1) of the current A/B hold toward a long press, for feedback rings.
function Input.holdProgress(name)
	local s = state[name]
	if not s.down or s.long then return 0 end
	return Util.clamp((Util.nowMs() - s.at) / Input.holdMs, 0, 1)
end

-- Forget any press in progress (after a screen change eats the press).
function Input.reset()
	for _, s in pairs(state) do
		if s.down then s.long = true end
	end
end

function Input.update()
	local now = Util.nowMs()
	local cur, pressed, released = playdate.getButtonState()
	local ev = {}
	Input.events = ev
	local change, accel = playdate.getCrankChange()
	if Input.suppress or (playdate.keyboard.isVisible and playdate.keyboard.isVisible()) then
		Input.crankChange, Input.crankAccel = 0, 0
		for _, s in pairs(state) do s.down = false end
		return ev
	end
	Input.crankChange, Input.crankAccel = change or 0, accel or change or 0
	if change ~= 0 then Input.lastInputMs = now end

	for _, name in ipairs({ "A", "B" }) do
		local s, bit = state[name], K[name]
		local isDown = (cur & bit) ~= 0
		local justDown = (pressed & bit) ~= 0
		local justUp = (released & bit) ~= 0
		if justDown then
			s.down, s.at, s.long = true, now, false
			Input.lastInputMs = now
		end
		if s.down and not s.long and isDown and now - s.at >= Input.holdMs then
			s.long = true
			ev[#ev + 1] = name .. "L"
		end
		if justUp or (s.down and not isDown) then
			if s.down and not s.long then ev[#ev + 1] = name end
			s.down = false
			Input.lastInputMs = now
		end
	end
	for _, name in ipairs(DIRS) do
		local s, bit = state[name], K[name]
		local isDown = (cur & bit) ~= 0
		if (pressed & bit) ~= 0 then
			s.down, s.at, s.next = true, now, now + REPEAT_DELAY
			ev[#ev + 1] = name
			Input.lastInputMs = now
		elseif s.down and isDown and now >= s.next then
			s.next = now + REPEAT_EVERY
			ev[#ev + 1] = name
			Input.lastInputMs = now
		end
		if not isDown then s.down = false end
	end
	return ev
end

function Input.idleMs()
	return Util.nowMs() - Input.lastInputMs
end

---------------------------------------------------------------------------
-- Crank helpers
---------------------------------------------------------------------------

-- Degrees per list step for the crank sensitivity setting (1 slow .. 3 fast).
function Input.degPerStep()
	local c = Model.db and Model.db.settings.crank or 2
	return ({ 36, 26, 18 })[c] or 26
end

-- A stepper accumulates crank degrees and yields whole steps.
Stepper = {}
Stepper.__index = Stepper

function Stepper.new(deg)
	return setmetatable({ acc = 0, deg = deg }, Stepper)
end

function Stepper:feed(delta)
	local deg = self.deg or Input.degPerStep()
	self.acc = self.acc + delta
	local steps = 0
	while self.acc >= deg do self.acc = self.acc - deg; steps = steps + 1 end
	while self.acc <= -deg do self.acc = self.acc + deg; steps = steps - 1 end
	return steps
end

function Stepper:reset() self.acc = 0 end

return Input
