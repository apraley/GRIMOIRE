-- ListScreen: the scrolling, crank-driven list most screens are built on.
-- FormScreen: field editor on top of ListScreen (crank/left/right dial values,
-- A opens a picker or the keyboard, B saves and goes back).

ListScreen = Screen:extend()

ListScreen.ROW_H = 20
ListScreen.TOP = 24

function ListScreen:init(title)
	self.title = title or ""
	self.rows = {}
	self.sel = 1
	self.scrollY = 0
	self.stepper = Stepper.new()
	self.hints = { { "crank", "MOVE" }, { "A", "OPEN" }, { "B", "BACK" }, { "!B", "NEXT" } }
end

-- Subclasses rebuild self.rows here; called on every enter().
function ListScreen:build() end

function ListScreen:enter()
	local keepId = self.rows[self.sel] and self.rows[self.sel].key
	self:build()
	if keepId then
		for i, r in ipairs(self.rows) do if r.key == keepId then self.sel = i end end
	end
	self:clampSel()
end

function ListScreen:clampSel()
	if #self.rows == 0 then self.sel = 1; return end
	self.sel = Util.clamp(self.sel, 1, #self.rows)
	if self.rows[self.sel].skip then self:move(1, true) end
end

function ListScreen:selectKey(key)
	for i, r in ipairs(self.rows) do
		if r.key == key then self.sel = i; return true end
	end
	return false
end

function ListScreen:current() return self.rows[self.sel] end

function ListScreen:move(d, noWrap)
	local n = #self.rows
	if n == 0 then return end
	local i = self.sel
	for _ = 1, n do
		i = i + (d > 0 and 1 or -1)
		if i > n then if noWrap then i = n; break end i = 1 end
		if i < 1 then if noWrap then i = 1; break end i = n end
		if not self.rows[i].skip then break end
	end
	if not self.rows[i].skip then self.sel = i end
	App.redraw()
end

function ListScreen:listBottom() return Gfx.H - 20 end

function ListScreen:rowH(r) return r.h or ListScreen.ROW_H end

function ListScreen:drawHeader()
	Gfx.fill(0, 0, Gfx.W, 21)
	Gfx.pix(self.title, 8, 4, 2, { white = true })
	if self.subtitle then
		Gfx.text(self.subtitle, Gfx.W - 8, 2, { white = true, align = "right", maxW = 400 - 16 - Pixfont.width(self.title, 2) - 16 })
	end
end

-- Default row renderer: optional icon, label, right-aligned value.
function ListScreen:drawRow(r, x, y, w, h, selected)
	local white = selected
	local tx = x + 14
	if r.section then
		Gfx.pix(r.label, x + 4, y + h - 10, 1)
		Gfx.hline(x + 4 + Pixfont.width(r.label, 1) + 6, y + h - 7, w - Pixfont.width(r.label, 1) - 16)
		return
	end
	if r.icon then Gfx.icon(r.icon, tx, y + (h - 8) // 2, { white = white }); tx = tx + 13 end
	local vw = 0
	if r.value and r.value ~= "" then
		local maxV = r.valueW or math.floor(w * 0.55)
		vw = Gfx.text(r.value, x + w - 8, y + (h - Gfx.lineH) // 2 + 1,
			{ white = white, align = "right", maxW = maxV, bold = r.valueBold })
		if r.dial and selected then
			Gfx.icon("left", x + w - 8 - vw - 12, y + (h - 8) // 2, { white = true })
		end
	end
	Gfx.text(r.label or "", tx, y + (h - Gfx.lineH) // 2 + 1,
		{ white = white, bold = r.bold, maxW = w - (tx - x) - vw - (r.dial and 26 or 14) })
end

function ListScreen:draw()
	self:drawHeader()
	local top, bottom = self.listTop or ListScreen.TOP, self:listBottom()
	-- compute positions
	local ys, y = {}, 0
	for i, r in ipairs(self.rows) do ys[i] = y; y = y + self:rowH(r) end
	local total = y
	local viewH = bottom - top
	local sel = self.rows[self.sel]
	if sel then
		local sy, sh = ys[self.sel], self:rowH(sel)
		if sy - self.scrollY < 0 then self.scrollY = sy end
		if sy + sh - self.scrollY > viewH then self.scrollY = sy + sh - viewH end
		-- keep the header row of a section visible when near the top
		if self.sel <= 2 then self.scrollY = 0 end
	end
	self.scrollY = Util.clamp(self.scrollY, 0, math.max(0, total - viewH))
	playdate.graphics.setClipRect(0, top, Gfx.W, viewH)
	for i, r in ipairs(self.rows) do
		local ry = top + ys[i] - self.scrollY
		local h = self:rowH(r)
		if ry + h >= top and ry <= bottom then
			local selected = (i == self.sel) and not r.skip
			if selected then
				Gfx.selbar(4, ry, Gfx.W - 8 - 6, h)
				Gfx.cursor(7, ry + (h - 8) // 2, true)
			end
			if r.draw then r.draw(r, 4, ry, Gfx.W - 14, h, selected) else self:drawRow(r, 4, ry, Gfx.W - 14, h, selected) end
		end
	end
	playdate.graphics.clearClipRect()
	-- scrollbar
	if total > viewH then
		local bh = math.max(12, math.floor(viewH * viewH / total))
		local by = top + math.floor((viewH - bh) * self.scrollY / (total - viewH))
		Gfx.fill(Gfx.W - 5, top, 1, viewH)
		Gfx.fill(Gfx.W - 7, by, 5, bh)
	end
	if #self.rows == 0 and self.emptyText then
		Gfx.text(self.emptyText, Gfx.W // 2, 110, { align = "center" })
	end
	Gfx.hints(self.hints)
end

function ListScreen:event(ev)
	local r = self.rows[self.sel]
	if ev == "UP" then self:move(-1)
	elseif ev == "DOWN" then self:move(1)
	elseif ev == "A" then if r and r.onA then r.onA(r, self) end
	elseif ev == "AL" then if r and r.onAL then r.onAL(r, self) elseif r and r.onA then r.onA(r, self) end
	elseif ev == "LEFT" then if r and r.onLeft then r.onLeft(r, self) elseif self.onLeft then self:onLeft() end
	elseif ev == "RIGHT" then if r and r.onRight then r.onRight(r, self) elseif self.onRight then self:onRight() end
	elseif ev == "B" then self:back()
	end
	App.redraw()
	return true
end

function ListScreen:back() App.pop() end

function ListScreen:crank(change, accel)
	local r = self.rows[self.sel]
	if r and r.onCrank then
		local st = self.dialStepper or Stepper.new(24)
		self.dialStepper = st
		local n = st:feed(change)
		if n ~= 0 then r.onCrank(r, self, n) end
		return
	end
	local n = self.stepper:feed(accel)
	if n ~= 0 then
		for _ = 1, math.abs(n) do self:move(n) end
	end
end

---------------------------------------------------------------------------
-- FormScreen
--
-- spec entries:
--   { f="field", label="LABEL", t="text"|"enum"|"num"|"bool"|"time"|"date"|"multi"|"list"|"info"|"action",
--     opts = {..} or function() -> list, fmt = function(v) -> string, custom = true (enum: TYPE... option),
--     suggest = function() -> list (text: left/right cycles suggestions), min/max/step (num),
--     run = function(screen) (action), value = function() (info), danger = true }
---------------------------------------------------------------------------

FormScreen = ListScreen:extend()

function FormScreen:init(title, rec, spec, opts)
	ListScreen.init(self, title)
	self.rec = rec
	self.spec = spec
	self.opts = opts or {}
	self.pending = {}
	self.pendingMs = 0
	self.hints = { { "crank", "VALUE" }, { "A", "EDIT" }, { "B", "DONE" }, { "up", "" }, { "down", "FIELD" } }
end

local function optsOf(sp)
	local o = sp.opts
	if type(o) == "function" then o = o() end
	return o or {}
end

function FormScreen:valueOf(sp)
	if self.pending[sp.f] ~= nil then return self.pending[sp.f] end
	return self.rec[sp.f]
end

function FormScreen:fmt(sp, v)
	if sp.fmt then return sp.fmt(v) end
	if sp.t == "bool" then return v and "ON" or "OFF" end
	if sp.t == "multi" or sp.t == "list" then return Util.joinList(v or {}, ", ") end
	if v == nil or v == "" then return "-" end
	return tostring(v)
end

-- Commit buffered dial changes as one op.
function FormScreen:flushPending()
	local fields, any = {}, false
	for f, v in pairs(self.pending) do
		if self.rec[f] ~= v then fields[f] = v; any = true end
	end
	self.pending = {}
	if any then
		App.commit(Model.opSetMany(self.rec, fields, "EDIT " .. self.title))
		if self.opts.onChange then self.opts.onChange(self.rec) end
	end
end

function FormScreen:setValue(sp, v, immediate)
	self.pending[sp.f] = v
	self.pendingMs = Util.nowMs()
	if immediate then self:flushPending() end
	self:build()
	App.redraw()
end

function FormScreen:dial(sp, d)
	local v = self:valueOf(sp)
	if sp.t == "enum" then
		local o = optsOf(sp)
		if #o == 0 then return end
		local i = Util.indexOf(o, v) or 0
		i = Util.wrap(i + d, #o)
		self:setValue(sp, o[i])
	elseif sp.t == "num" then
		local n = (tonumber(v) or sp.min or 0) + d * (sp.step or 1)
		self:setValue(sp, Util.clamp(n, sp.min or 0, sp.max or 9999))
	elseif sp.t == "bool" then
		self:setValue(sp, not v, true)
	elseif sp.t == "time" then
		local m = Util.parseHM(v) or 7 * 60
		self:setValue(sp, Util.fmtHM(m + d * (sp.step or 15)))
	elseif sp.t == "date" then
		self:setValue(sp, Util.shiftDate(v, d))
	elseif sp.t == "text" and sp.suggest then
		local o = sp.suggest()
		if #o == 0 then return end
		local i = Util.indexOf(o, v) or 0
		self:setValue(sp, o[Util.wrap(i + d, #o)])
	end
end

function FormScreen:activate(sp)
	if sp.t == "action" then
		self:flushPending()
		sp.run(self)
	elseif sp.t == "text" then
		self:flushPending()
		App.keyboard(sp.label, self.rec[sp.f] or "", function(text)
			if sp.upper ~= false then text = Util.upper(text) end
			self:setValue(sp, text, true)
		end)
	elseif sp.t == "list" then
		self:flushPending()
		App.keyboard(sp.label .. " (COMMA SEPARATED)", Util.joinList(self.rec[sp.f] or {}, ", "), function(text)
			self:setValue(sp, Util.splitList(Util.upper(text)), true)
		end)
	elseif sp.t == "enum" then
		self:flushPending()
		local o = optsOf(sp)
		local items = {}
		for _, v in ipairs(o) do items[#items + 1] = { label = self:fmt(sp, v), value = v } end
		if sp.custom then items[#items + 1] = { label = "TYPE CUSTOM...", custom = true } end
		App.push(PickerOverlay:new(sp.label, items, self:valueOf(sp), function(item)
			if item.custom then
				App.keyboard(sp.label, tostring(self.rec[sp.f] or ""), function(text)
					self:setValue(sp, Util.upper(text), true)
				end)
			else
				self:setValue(sp, item.value, true)
			end
		end))
	elseif sp.t == "multi" then
		self:flushPending()
		App.push(MultiPickerOverlay:new(sp.label, optsOf(sp), self.rec[sp.f] or {}, function(list)
			self:setValue(sp, list, true)
		end))
	elseif sp.t == "bool" then
		self:setValue(sp, not self:valueOf(sp), true)
	elseif sp.t == "num" or sp.t == "time" or sp.t == "date" then
		self:flushPending()
	end
end

function FormScreen:build()
	local rows = {}
	for _, sp in ipairs(self.spec) do
		if sp.t == "section" then
			rows[#rows + 1] = { section = true, skip = true, label = sp.label, h = 16 }
		else
			local r = { key = sp.f or sp.label, label = sp.label, sp = sp }
			if sp.t == "action" then
				r.label = sp.label
				r.icon = sp.icon or "right"
				r.value = sp.value and sp.value() or nil
			elseif sp.t == "info" then
				r.value = sp.value and sp.value() or ""
				r.skip = sp.selectable ~= true
			else
				r.value = self:fmt(sp, self:valueOf(sp))
				r.valueBold = true
				r.dial = (sp.t ~= "text" and sp.t ~= "list" and sp.t ~= "multi") or sp.suggest ~= nil
				r.valueW = 250
				if self.pending[sp.f] ~= nil and self.pending[sp.f] ~= self.rec[sp.f] then r.value = r.value .. "*" end
			end
			r.onA = function() self:activate(sp) end
			r.onLeft = function() self:dial(sp, -1) end
			r.onRight = function() self:dial(sp, 1) end
			if r.dial then r.onCrank = function(_, _, n) self:dial(sp, n) end end
			rows[#rows + 1] = r
		end
	end
	self.rows = rows
end

function FormScreen:event(ev)
	if ev == "UP" or ev == "DOWN" then self:flushPending() end
	return ListScreen.event(self, ev)
end

function FormScreen:update()
	if next(self.pending) and Util.nowMs() - self.pendingMs > 900 then
		self:flushPending()
		self:build()
		App.redraw()
	end
end

function FormScreen:back()
	self:flushPending()
	if self.opts.onDone then self.opts.onDone(self.rec) end
	App.pop()
end

function FormScreen:leave()
	self:flushPending()
end

return ListScreen
