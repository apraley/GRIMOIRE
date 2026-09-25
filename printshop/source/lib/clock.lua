-- Wall clock and frame timing.
--
-- All persisted dates are integer seconds since 2000-01-01 UTC, the value
-- returned by playdate.getSecondsSinceEpoch(). Clock.offset lets tests (and
-- the demo "time warp") shift "now" without touching the system clock.

Clock = {
	offset = 0,
	frameMs = 33,
	lastMs = nil,
	gapMs = 0,      -- real time lost to clamping this frame (sleep, lock, menu)
}

function Clock.now()
	local s = playdate.getSecondsSinceEpoch()
	return s + Clock.offset
end

function Clock.toLocal(epoch)
	return playdate.timeFromEpoch(epoch, 0)
end

-- Call once per frame; returns the elapsed milliseconds since the last call,
-- clamped so a long pause (system menu, sleep) doesn't produce a huge step.
function Clock.tick()
	local ms = playdate.getCurrentTimeMilliseconds()
	local dt = 33
	if Clock.lastMs ~= nil then
		dt = ms - Clock.lastMs
		if dt < 0 then dt = 33 end
		if dt > 250 then dt = 250 end
	end
	-- The game clock may stand still while the device sleeps or the system
	-- menu is open; the wall clock doesn't. Any wall time beyond this frame
	-- is reported as a gap (whole seconds, so ignore sub-2s jitter).
	Clock.gapMs = 0
	local wall = Clock.now()
	if Clock.lastWall ~= nil and wall - Clock.lastWall >= 2 then
		Clock.gapMs = math.max(0, (wall - Clock.lastWall) * 1000 - dt)
	end
	Clock.lastWall = wall
	Clock.lastMs = ms
	Clock.frameMs = dt
	return dt
end

-- Monotonic milliseconds for animation.
function Clock.ms()
	return playdate.getCurrentTimeMilliseconds()
end

-- Hour of day (local) for the Captain's greetings.
function Clock.hour()
	return Clock.toLocal(Clock.now()).hour
end
