-- Form: a vertical list of editable fields, used by the job, spool, task
-- and settings editors.
--
-- field = {
--   label = "NAME",
--   kind  = "text" | "enum" | "number" | "bool" | "action" | "custom",
--   get   = function() return value end,
--   set   = function(v) end,
--   fmt   = function(v) return "shown" end,       -- optional display
--   options = { ... } or function() return {...} end,   -- enum values
--   optionLabel = function(v) return "LABEL" end,        -- enum display
--   min, max, step, dialFmt, unit, labels,               -- number
--   maxLen,                                              -- text
--   run = function() end,                                -- action / custom
--   hidden = function() return bool end,
--   hint = "shown at the bottom",
-- }
-- Left/right cycles enums and nudges numbers; the crank nudges numbers in
-- place; A opens the keyboard, an option menu, or the big crank Dial.

Form = {}
Form.__index = Form

function Form.new(fields, opts)
	opts = opts or {}
	local f = setmetatable({
		allFields = fields,
		fields = {},
		list = ScrollList.new(opts.rows or 12, { crank = false }),
		ticker = CrankTicker.new(15),
		x = opts.x or 8, y = opts.y or 20, w = opts.w or 384,
		labelW = opts.labelW or 120,
		onChange = opts.onChange,
		editing = false,
	}, Form)
	f:refresh()
	return f
end

function Form:refresh()
	self.fields = {}
	for _, fd in ipairs(self.allFields) do
		if not (fd.hidden and fd.hidden()) then self.fields[#self.fields + 1] = fd end
	end
	self.list:setCount(#self.fields)
end

function Form:current()
	return self.fields[self.list.sel]
end

local function options(fd)
	if type(fd.options) == "function" then return fd.options() end
	return fd.options or {}
end

function Form:display(fd)
	local v = fd.get and fd.get()
	if fd.fmt then return fd.fmt(v) end
	if fd.kind == "bool" then return v and "ON" or "OFF" end
	if fd.kind == "enum" and fd.optionLabel then return fd.optionLabel(v) end
	if fd.kind == "number" then
		local s = string.format(fd.dialFmt or "%d", v or 0)
		if fd.unit == "C" then return s .. FontData.icon.deg .. "C" end
		return s .. (fd.unit and fd.unit ~= "" and (" " .. fd.unit) or "")
	end
	if fd.kind == "action" or fd.kind == "custom" then return fd.value and fd.value() or "" end
	if v == nil or v == "" then return "--" end
	return tostring(v)
end

function Form:changed(fd)
	if self.onChange then self.onChange(fd) end
	self:refresh()
end

function Form:cycle(fd, d)
	local opts = options(fd)
	if #opts == 0 then return end
	local cur = fd.get()
	local i = U.indexOf(opts, cur) or 0
	i = U.wrap(i + d, #opts)
	fd.set(opts[i])
	Sfx.play("move")
	self:changed(fd)
end

function Form:nudge(fd, n)
	local v = fd.get() or fd.min or 0
	local step = fd.step or 1
	local nv = U.clamp(v + n * step, fd.min or -1e9, fd.max or 1e9)
	nv = U.round(nv, 4)
	if nv ~= v then
		fd.set(nv)
		Sfx.play("tick")
		self:changed(fd)
	end
end

function Form:activate(fd)
	if fd.kind == "text" then
		TextEntry.open(fd.label, fd.get() or "", function(text)
			fd.set(text)
			self:changed(fd)
		end, fd.maxLen)
	elseif fd.kind == "enum" then
		local items = {}
		local cur = fd.get()
		local sel = 1
		for i, o in ipairs(options(fd)) do
			if o == cur then sel = i end
			items[#items + 1] = { label = fd.optionLabel and fd.optionLabel(o) or tostring(o), action = function()
				fd.set(o)
				self:changed(fd)
			end }
		end
		Menu.open({ title = fd.label, items = items, sel = sel })
	elseif fd.kind == "number" then
		Dial.open({ title = fd.label, label = fd.dialLabel or fd.label, value = fd.get() or fd.min or 0,
			min = fd.min or 0, max = fd.max or 100, step = fd.step or 1, fmt = fd.dialFmt or "%d",
			unit = fd.unit or "", labels = fd.labels, hint = fd.hint,
			onAccept = function(v)
				fd.set(v)
				self:changed(fd)
			end })
	elseif fd.kind == "bool" then
		fd.set(not fd.get())
		Sfx.play("ok")
		self:changed(fd)
	elseif fd.kind == "action" or fd.kind == "custom" then
		if fd.run then fd.run() end
	end
end

-- Returns true if the form consumed A.
function Form:update()
	self.list:update()
	local fd = self:current()
	if fd == nil then return false end
	local h = Input.horizontal()
	if h ~= 0 then
		if fd.kind == "enum" then self:cycle(fd, h)
		elseif fd.kind == "number" then self:nudge(fd, h)
		elseif fd.kind == "bool" then fd.set(not fd.get()) Sfx.play("ok") self:changed(fd) end
	end
	-- Crank: numbers adjust in place, everything else scrolls the form.
	local t = self.ticker:update()
	if t ~= 0 then
		if fd.kind == "number" then self:nudge(fd, t)
		else self.list:move(t > 0 and 1 or -1) end
	end
	if Input.a() then
		self:activate(fd)
		return true
	end
	return false
end

function Form:draw()
	local rowH = 13
	local y0 = self.y
	for i, row in self.list:visible() do
		local fd = self.fields[i]
		local y = y0 + row * rowH
		local ink = Draw.fgInk()
		Text.draw(fd.label, self.x + 14, y, { color = ink })
		local val = U.truncate(self:display(fd), Text.fit(self.w - self.labelW - 24))
		local vx = self.x + self.labelW
		if fd.kind == "enum" or fd.kind == "number" or fd.kind == "bool" then
			if i == self.list.sel then
				Text.draw(FontData.icon.left, vx - 8, y, { color = ink })
				Text.draw(FontData.icon.right, vx + Text.width(val) + 3, y, { color = ink })
			end
		end
		Text.draw(val, vx, y, { color = ink })
		if i == self.list.sel then Draw.cursor(self.x + 4, y + 1) end
	end
	self.list:drawScrollbar(self.x + self.w - 6, y0, self.list.rows * rowH - 4)
end

function Form:hint()
	local fd = self:current()
	if fd == nil then return nil end
	if fd.hint then return fd.hint end
	if fd.kind == "text" then return "A: TYPE" end
	if fd.kind == "enum" then return FontData.icon.left .. FontData.icon.right .. ": CHANGE  A: LIST" end
	if fd.kind == "number" then return FontData.icon.left .. FontData.icon.right .. "/CRANK: ADJUST  A: DIAL" end
	if fd.kind == "bool" then return "A: TOGGLE" end
	return "A: SELECT"
end
