-- Screen stack. A screen is a table with optional methods:
--   enter(), leave(), resume()    lifecycle (resume = uncovered by a pop)
--   update(dtMs)                  input + logic (only the top screen)
--   draw()                        rendering
--   overlay = true                draw the screen beneath first (menus, dialogs)
-- Transitions between full screens play a short dither wipe.

Screens = {
	stack = {},
	fade = 0,      -- frames of transition remaining
	FADE_FRAMES = 5,
}

function Screens.top()
	return Screens.stack[#Screens.stack]
end

function Screens.depth()
	return #Screens.stack
end

function Screens.push(s)
	Screens.stack[#Screens.stack + 1] = s
	if not s.overlay then Screens.fade = Screens.FADE_FRAMES end
	if s.enter then s:enter() end
	return s
end

function Screens.pop()
	if #Screens.stack <= 1 then return nil end
	local s = table.remove(Screens.stack)
	if s.leave then s:leave() end
	if not s.overlay then Screens.fade = Screens.FADE_FRAMES end
	local top = Screens.top()
	if top and top.resume then top:resume() end
	return s
end

-- Pops until `s` is on top (or the root is reached).
function Screens.popTo(s)
	while #Screens.stack > 1 and Screens.top() ~= s do Screens.pop() end
end

function Screens.popToRoot()
	while #Screens.stack > 1 do Screens.pop() end
end

-- Removes a specific screen wherever it is (used by overlays closing
-- themselves after their callback pushed something new).
function Screens.remove(s)
	for i = #Screens.stack, 1, -1 do
		if Screens.stack[i] == s then
			table.remove(Screens.stack, i)
			if s.leave then s:leave() end
			if i > #Screens.stack then
				local top = Screens.top()
				if top and top.resume then top:resume() end
			end
			return true
		end
	end
	return false
end

function Screens.update(dtMs)
	local top = Screens.top()
	if top and top.update then top:update(dtMs) end
end

function Screens.draw()
	local n = #Screens.stack
	if n == 0 then return end
	local base = n
	while base > 1 and Screens.stack[base].overlay do base = base - 1 end
	for i = base, n do
		local s = Screens.stack[i]
		if s.draw then s:draw() end
	end
	if Screens.fade > 0 then
		Screens.drawFade(math.min(#Draw.RAMP, Screens.fade + 1))
		Screens.fade = Screens.fade - 1
	end
end

-- Draws black pixels where the ramp pattern is black, leaving the rest.
function Screens.drawFade(idx)
	local gfx = playdate.graphics
	local p = Draw.P[Draw.RAMP[idx]]
	-- Second 8 rows are an alpha mask: only the pattern's black pixels are
	-- opaque, so the underlying frame shows through the white ones.
	local mask = {}
	for i = 1, 8 do mask[i] = 0xFF - p[i] end
	local pat = { 0, 0, 0, 0, 0, 0, 0, 0 }
	for i = 1, 8 do pat[8 + i] = mask[i] end
	gfx.setPattern(pat)
	gfx.fillRect(0, 0, 400, 240)
	gfx.setColor(gfx.kColorBlack)
end
