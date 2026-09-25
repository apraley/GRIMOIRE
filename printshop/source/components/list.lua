-- Scrolling selection state shared by list screens. Handles d-pad (with
-- repeat) and crank detents, keeps the cursor visible, and wraps or clamps.

ScrollList = {}
ScrollList.__index = ScrollList

function ScrollList.new(rows, opts)
	opts = opts or {}
	return setmetatable({
		rows = rows or 8,
		sel = 1,
		scroll = 1,
		count = 0,
		wrap = opts.wrap ~= false,
		ticker = CrankTicker.new(opts.degPerRow or 24),
		crank = opts.crank ~= false,
	}, ScrollList)
end

function ScrollList:setCount(n)
	self.count = n
	if n == 0 then
		self.sel, self.scroll = 1, 1
		return
	end
	self.sel = U.clamp(self.sel, 1, n)
	self:reveal()
end

function ScrollList:reveal()
	if self.sel < self.scroll then self.scroll = self.sel end
	if self.sel > self.scroll + self.rows - 1 then self.scroll = self.sel - self.rows + 1 end
	self.scroll = U.clamp(self.scroll, 1, math.max(1, self.count - self.rows + 1))
end

function ScrollList:select(i)
	if self.count == 0 then return end
	self.sel = U.clamp(i, 1, self.count)
	self:reveal()
end

-- Moves by d; returns true if the selection changed.
function ScrollList:move(d)
	if self.count == 0 or d == 0 then return false end
	local before = self.sel
	local i = self.sel + d
	if self.wrap and math.abs(d) == 1 then
		i = U.wrap(i, self.count)
	else
		i = U.clamp(i, 1, self.count)
	end
	self.sel = i
	self:reveal()
	if self.sel ~= before then Sfx.play("move") end
	return self.sel ~= before
end

function ScrollList:update()
	local d = Input.vertical()
	if self.crank then d = d + self.ticker:update() end
	if d ~= 0 then return self:move(d > 0 and 1 or -1) end
	return false
end

-- Iterates visible rows: for i, rowIndexOnScreen in list:visible() do
function ScrollList:visible()
	local i = self.scroll - 1
	local last = math.min(self.count, self.scroll + self.rows - 1)
	return function()
		i = i + 1
		if i > last then return nil end
		return i, i - self.scroll
	end
end

-- Draws a scrollbar at x from y to y+h.
function ScrollList:drawScrollbar(x, y, h)
	if self.count <= self.rows then return end
	local gfx = playdate.graphics
	gfx.setColor(Draw.fgColor())
	gfx.drawLine(x + 1, y, x + 1, y + h)
	local th = math.max(6, math.floor(h * self.rows / self.count))
	local ty = y + math.floor((h - th) * (self.scroll - 1) / math.max(1, self.count - self.rows))
	gfx.fillRect(x, ty, 3, th)
	gfx.setColor(gfx.kColorBlack)
end
