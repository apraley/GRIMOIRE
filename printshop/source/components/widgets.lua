-- Overlay widgets: Menu, Confirm, Dial (crank number picker), TextEntry
-- (system keyboard), Dialog (typewriter text with a portrait) and Toast.
-- Each overlay is a screen pushed on the stack with overlay = true, so the
-- screen underneath keeps drawing.

local gfx <const> = playdate.graphics

---------------------------------------------------------------------------
-- Toast: transient message drawn by the app on top of everything.

Toast = { queue = {}, current = nil, ms = 0 }

function Toast.show(text, icon)
	Toast.queue[#Toast.queue + 1] = { text = U.upper(text), icon = icon }
end

function Toast.update(dtMs)
	if Toast.current == nil and #Toast.queue > 0 then
		Toast.current = table.remove(Toast.queue, 1)
		Toast.ms = 0
	end
	if Toast.current then
		Toast.ms = Toast.ms + dtMs
		if Toast.ms > 2200 then Toast.current = nil end
	end
end

function Toast.draw()
	local t = Toast.current
	if t == nil then return end
	local text = (t.icon and (FontData.icon[t.icon] or "") .. " " or "") .. t.text
	text = U.truncate(text, 58)
	local w = Text.width(text) + 20
	-- Slide in from the top.
	local y = 18
	if Toast.ms < 150 then y = 18 - (150 - Toast.ms) // 6 end
	Draw.window(200 - w // 2, y, w, 21)
	Text.draw(text, 200, y + 6, { align = "center" })
end

---------------------------------------------------------------------------
-- Menu: a list of options in a window. items: { label, action, disabled,
-- hint, right }. Crank or d-pad to move, A picks, B cancels.

Menu = {}
Menu.__index = Menu

function Menu.open(opts)
	local m = setmetatable({
		overlay = true,
		title = opts.title,
		items = opts.items or {},
		sel = opts.sel or 1,
		x = opts.x, y = opts.y, w = opts.w,
		maxRows = opts.maxRows or 9,
		onCancel = opts.onCancel,
		ticker = CrankTicker.new(30),
		scroll = 1,
	}, Menu)
	-- First enabled item.
	if m.items[m.sel] and m.items[m.sel].disabled then
		for i, it in ipairs(m.items) do if not it.disabled then m.sel = i break end end
	end
	local longest = 8
	for _, it in ipairs(m.items) do
		local l = #it.label + (it.right and (#it.right + 2) or 0)
		if l > longest then longest = l end
	end
	if m.title and #m.title + 2 > longest then longest = #m.title + 2 end
	m.w = m.w or math.min(380, longest * Text.ADV + 30)
	local rows = math.min(#m.items, m.maxRows)
	m.h = rows * 13 + 16
	m.x = m.x or (200 - m.w // 2)
	m.y = m.y or math.max(18, 120 - m.h // 2)
	if m.y + m.h > 238 then m.y = 238 - m.h end
	Screens.push(m)
	Sfx.play("ok")
	return m
end

function Menu:move(d)
	local n = #self.items
	if n == 0 then return end
	local i = self.sel
	for _ = 1, n do
		i = U.wrap(i + d, n)
		if not self.items[i].disabled then break end
	end
	if i ~= self.sel then
		self.sel = i
		Sfx.play("move")
	end
end

function Menu:update()
	local d = Input.vertical() + self.ticker:update()
	if d ~= 0 then self:move(d > 0 and 1 or -1) end
	if Input.a() then
		local it = self.items[self.sel]
		if it and not it.disabled then
			Screens.remove(self)
			Sfx.play("ok")
			if it.action then it.action(it) end
		else
			Sfx.play("error")
		end
	elseif Input.b() then
		Screens.remove(self)
		Sfx.play("back")
		if self.onCancel then self.onCancel() end
	end
end

function Menu:draw()
	local rows = math.min(#self.items, self.maxRows)
	if self.sel < self.scroll then self.scroll = self.sel end
	if self.sel >= self.scroll + rows then self.scroll = self.sel - rows + 1 end
	Draw.window(self.x, self.y, self.w, self.h, { title = self.title })
	local y = self.y + 9
	for i = self.scroll, math.min(#self.items, self.scroll + rows - 1) do
		local it = self.items[i]
		local ink = Draw.fgInk()
		local label = it.label
		if it.disabled then
			Text.draw(label, self.x + 18, y, { color = ink })
			-- Strike-through dither marks disabled items.
			Draw.fillPattern(Draw.theme == "night" and "dark75" or "light25", self.x + 17, y, Text.width(label) + 2, 9)
		else
			Text.draw(label, self.x + 18, y, { color = ink })
		end
		if it.right then Text.draw(it.right, self.x + self.w - 10, y, { color = ink, align = "right" }) end
		if i == self.sel then Draw.cursor(self.x + 8, y + 1) end
		y = y + 13
	end
	if self.scroll > 1 then Text.draw(FontData.icon.up, self.x + self.w - 12, self.y + 4) end
	if self.scroll + rows - 1 < #self.items then
		Text.draw(FontData.icon.down, self.x + self.w - 12, self.y + self.h - 12)
	end
	local it = self.items[self.sel]
	if it and it.hint then
		local hw = math.min(390, Text.width(it.hint) + 16)
		local hy = self.y + self.h + 2
		if hy + 17 > 240 then hy = self.y - 19 end
		Draw.window(200 - hw // 2, hy, hw, 17)
		Text.draw(U.truncate(it.hint, 62), 200, hy + 4, { align = "center" })
	end
end

---------------------------------------------------------------------------
-- Confirm: yes/no question.

function Confirm(question, onYes, onNo, yesLabel, noLabel)
	return Menu.open({
		title = question,
		items = {
			{ label = yesLabel or "YES", action = function() if onYes then onYes() end end },
			{ label = noLabel or "NO", action = function() if onNo then onNo() end end },
		},
		sel = 2,
		onCancel = onNo,
	})
end

---------------------------------------------------------------------------
-- Dial: the crank-driven number picker.
--
--      NOZZLE TEMP
--         215 C
--    <-----O----->
--  TURN CRANK TO ADJUST
--      A: ACCEPT
--
-- opts: title, label, value, min, max, step, fmt, unit, onAccept(v),
-- onCancel(), labels (for integer scales), degPerStep, target (measure mode).

Dial = {}
Dial.__index = Dial

function Dial.new(opts)
	local d = setmetatable({
		title = opts.title or "ADJUST",
		label = opts.label or "",
		value = opts.value or opts.min or 0,
		min = opts.min or 0,
		max = opts.max or 100,
		step = opts.step or 1,
		fmt = opts.fmt or "%d",
		unit = opts.unit or "",
		labels = opts.labels,
		target = opts.target,
		onAccept = opts.onAccept,
		onCancel = opts.onCancel,
		hint = opts.hint,
		ticker = CrankTicker.new(opts.degPerStep or 12),
		spin = 0,        -- accumulated crank angle for the knob drawing
		bump = 0,        -- ms since last step (for the knob wobble)
		overlay = true,
	}, Dial)
	d.value = d:snap(d.value)
	return d
end

function Dial.open(opts)
	local d = Dial.new(opts)
	Screens.push(d)
	return d
end

function Dial:snap(v)
	local steps = U.roundInt((v - self.min) / self.step)
	return U.clamp(self.min + steps * self.step, self.min, self.max)
end

function Dial:nudge(n)
	local before = self.value
	self.value = self:snap(self.value + n * self.step)
	if self.value ~= before then
		self.bump = 0
		Sfx.play("tick")
	elseif n ~= 0 then
		Sfx.play("error")
	end
end

-- Returns true when the value changed. Used standalone by the wizard too.
function Dial:handle(dtMs)
	self.bump = self.bump + (dtMs or 33)
	self.spin = (self.spin + Input.crank) % 360
	local ticks = self.ticker:update()
	local before = self.value
	if ticks ~= 0 then self:nudge(ticks) end
	local h = Input.horizontal()
	if h ~= 0 then self:nudge(h) end
	local v = Input.vertical()
	if v ~= 0 then self:nudge(-v * 10) end
	return self.value ~= before
end

function Dial:update(dtMs)
	self:handle(dtMs)
	if Input.a() then
		Screens.remove(self)
		Sfx.play("ok")
		if self.onAccept then self.onAccept(self.value) end
	elseif Input.b() then
		Screens.remove(self)
		Sfx.play("back")
		if self.onCancel then self.onCancel() end
	end
end

function Dial:valueText()
	local s = string.format(self.fmt, self.value)
	if self.labels then
		local l = self.labels[U.roundInt(self.value - self.min) + 1]
		if l then s = s .. " " .. l end
	end
	if self.unit == "C" then return s .. FontData.icon.deg .. "C" end
	if self.unit ~= "" then return s .. " " .. self.unit end
	return s
end

-- Draws the dial body inside a box (x, y, w, h). Shared with the wizard.
function Dial:drawBody(x, y, w, h)
	local cx = x + w // 2
	Text.draw(self.label, cx, y + 6, { align = "center" })
	-- Big value, with a little bounce right after each detent.
	local lift = self.bump < 80 and 1 or 0
	Text.draw(self:valueText(), cx, y + 22 - lift, { align = "center", scale = 3 })
	-- Track with the "O" knob positioned by value.
	local ty = y + 58
	local tx1, tx2 = x + 24, x + w - 24
	local fg = Draw.fgColor()
	gfx.setColor(fg)
	gfx.drawLine(tx1, ty, tx2, ty)
	gfx.fillTriangle(tx1 - 6, ty, tx1, ty - 4, tx1, ty + 4)
	gfx.fillTriangle(tx2 + 6, ty, tx2, ty - 4, tx2, ty + 4)
	for i = 0, 10 do
		local mx = tx1 + math.floor((tx2 - tx1) * i / 10)
		gfx.drawLine(mx, ty - (i % 5 == 0 and 3 or 1), mx, ty + (i % 5 == 0 and 3 or 1))
	end
	local frac = (self.value - self.min) / math.max(1e-6, self.max - self.min)
	local kx = tx1 + math.floor((tx2 - tx1) * frac)
	gfx.setColor(Draw.bgColor())
	gfx.fillCircleAtPoint(kx, ty, 6)
	gfx.setColor(fg)
	gfx.drawCircleAtPoint(kx, ty, 6)
	-- Knob notch follows the physical crank angle.
	local a = math.rad(self.spin)
	gfx.drawLine(kx, ty, kx + math.floor(math.sin(a) * 5 + 0.5), ty - math.floor(math.cos(a) * 5 + 0.5))
	if self.target then
		local err = self.value - self.target
		local pct = err / self.target * 100
		Text.draw(string.format("TARGET %.2f  ERROR %+.2f (%+.1f%%)", self.target, err, pct), cx, ty + 12, { align = "center" })
	elseif self.hint then
		Text.draw(U.truncate(self.hint, Text.fit(w - 16)), cx, ty + 12, { align = "center" })
	end
	Text.draw(FontData.icon.crank .. " TURN CRANK TO ADJUST", cx, y + h - 24, { align = "center" })
	Text.draw("A: ACCEPT   B: CANCEL   " .. FontData.icon.up .. FontData.icon.down .. ": x10", cx, y + h - 12, { align = "center" })
	gfx.setColor(gfx.kColorBlack)
end

function Dial:draw()
	local w, h = 300, 132
	local x, y = 50, 54
	Draw.window(x, y, w, h, { title = self.title })
	self:drawBody(x, y + 4, w, h - 4)
	if Input.docked and Draw.blinkOn then
		Text.draw("(UNDOCK THE CRANK, OR USE THE D-PAD)", 200, y + h + 4, { align = "center", color = "black" })
	end
end

---------------------------------------------------------------------------
-- TextEntry: wraps the system keyboard (CoreLibs/keyboard).

TextEntry = { active = nil }

function TextEntry.open(title, initial, onDone, maxLen)
	local entry = {
		overlay = true, title = title, text = initial or "", onDone = onDone,
		maxLen = maxLen or 28, opened = false,
	}
	function entry.update() end
	function entry.draw()
		local w = 400 - (playdate.keyboard.width and playdate.keyboard.width() or 180)
		w = math.max(160, math.min(220, w or 220))
		Draw.window(4, 70, w - 8, 70, { title = entry.title })
		local shown = playdate.keyboard.text or entry.text
		local lines = Text.wrap(shown .. (Draw.blinkOn and "_" or " "), Text.fit(w - 30))
		for i = 1, math.min(3, #lines) do
			Text.draw(lines[i], 16, 84 + (i - 1) * 12)
		end
		Text.draw(#shown .. "/" .. entry.maxLen, w - 12, 126, { align = "right" })
	end
	TextEntry.active = entry
	Screens.push(entry)
	playdate.keyboard.keyboardWillHideCallback = function(ok)
		local text = playdate.keyboard.text or ""
		if #text > entry.maxLen then text = string.sub(text, 1, entry.maxLen) end
		Screens.remove(entry)
		TextEntry.active = nil
		Input.block(3)
		if ok and entry.onDone then entry.onDone(U.trim(text)) end
	end
	playdate.keyboard.textChangedCallback = function()
		local t = playdate.keyboard.text or ""
		if #t > entry.maxLen then playdate.keyboard.text = string.sub(t, 1, entry.maxLen) end
	end
	playdate.keyboard.show(entry.text)
	return entry
end

---------------------------------------------------------------------------
-- Dialog: JRPG text box with typewriter reveal and an optional portrait.
-- pages: list of strings. opts: speaker, portrait(x, y) draw fn, onDone,
-- choices (shown after the last page as a Menu).

Dialog = {}
Dialog.__index = Dialog

function Dialog.new(pages, opts)
	opts = opts or {}
	local d = setmetatable({
		overlay = opts.overlay ~= false,
		pages = pages,
		page = 1,
		shown = 0,
		speaker = opts.speaker,
		portrait = opts.portrait,
		onDone = opts.onDone,
		x = opts.x or 8, y = opts.y or 160, w = opts.w or 384, h = opts.h or 64,
		chars = 0,
		ms = 0,
		speed = opts.speed,
	}, Dialog)
	d:paginate()
	d:layout()
	return d
end

-- Splits pages that don't fit the box into several pages.
function Dialog:paginate()
	local w = self.w - (self:textX() - self.x) - 12
	local maxLines = math.max(1, (self.h - 14) // Text.LINE)
	local out = {}
	for _, page in ipairs(self.pages) do
		local lines = Text.wrap(page, Text.fit(w))
		for i = 1, #lines, maxLines do
			local chunk = {}
			for k = i, math.min(#lines, i + maxLines - 1) do chunk[#chunk + 1] = lines[k] end
			out[#out + 1] = table.concat(chunk, " ")
		end
	end
	if #out == 0 then out[1] = "" end
	self.pages = out
end

function Dialog.open(pages, opts)
	local d = Dialog.new(pages, opts)
	Screens.push(d)
	return d
end

function Dialog:textX()
	return self.x + (self.portrait and 60 or 12)
end

function Dialog:layout()
	local w = self.w - (self:textX() - self.x) - 12
	self.lines = Text.wrap(self.pages[self.page] or "", Text.fit(w))
	self.total = 0
	for _, l in ipairs(self.lines) do self.total = self.total + #l end
	self.shown = 0
	self.ms = 0
end

function Dialog:done()
	return self.shown >= self.total
end

-- Characters revealed per second based on settings.typeSpeed (1..3).
function Dialog:cps()
	local s = self.speed or (Store.data and Store.settings().typeSpeed) or 2
	return ({ 30, 60, 120 })[s] or 60
end

function Dialog:advance()
	if not self:done() then
		self.shown = self.total
		return
	end
	if self.page < #self.pages then
		self.page = self.page + 1
		self:layout()
		Sfx.play("move")
	else
		self:close()
	end
end

function Dialog:close()
	Screens.remove(self)
	if self.onDone then self.onDone() end
end

function Dialog:tick(dtMs)
	if not self:done() then
		self.ms = self.ms + dtMs
		local before = self.shown
		-- Cranking forward speeds the typewriter up.
		local boost = Input.crank > 0 and 3 or 1
		self.shown = math.min(self.total, math.floor(self.ms / 1000 * self:cps() * boost))
		if self.shown // 3 ~= before // 3 then Sfx.play("type") end
	end
end

function Dialog:update(dtMs)
	self:tick(dtMs)
	if Input.a() then self:advance()
	elseif Input.b() then
		if self:done() then self:close() else self.shown = self.total end
	end
end

function Dialog:drawBox()
	Draw.window(self.x, self.y, self.w, self.h, { title = self.speaker })
	if self.portrait then
		self.portrait(self.x + 8, self.y + 8)
	end
	local tx = self:textX()
	local remaining = self.shown
	local maxLines = (self.h - 14) // Text.LINE
	for i, line in ipairs(self.lines) do
		if i > maxLines then break end
		local y = self.y + 9 + (i - 1) * Text.LINE
		if remaining >= #line then
			Text.draw(line, tx, y)
		elseif remaining > 0 then
			Text.drawPartial(line, remaining, tx, y)
		end
		remaining = remaining - #line
		if remaining <= 0 then break end
	end
	if self:done() then
		Draw.moreArrow(self.x + self.w - 16, self.y + self.h - 10)
	end
end

function Dialog:draw()
	self:drawBox()
end
