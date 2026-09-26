-- Modal overlays: option picker, multi-select, confirm, take rating,
-- continuity flag card.

---------------------------------------------------------------------------
-- PickerOverlay: items = { {label=, value=, icon=}, ... }
---------------------------------------------------------------------------
PickerOverlay = Screen:extend()
PickerOverlay.overlay = true

function PickerOverlay:init(title, items, current, onPick, opts)
	self.title = Util.upper(title)
	self.items = items
	self.onPick = onPick
	self.opts = opts or {}
	self.sel = 1
	for i, it in ipairs(items) do
		if current ~= nil and it.value == current then self.sel = i end
	end
	self.stepper = Stepper.new()
	self.top = 1
end

function PickerOverlay:geometry()
	local rows = math.min(#self.items, self.opts.rows or 8)
	local rowH = 20
	local h = rows * rowH + 34
	local w = self.opts.w or 240
	return (Gfx.W - w) // 2, math.max(6, (Gfx.H - 18 - h) // 2), w, h, rows, rowH
end

function PickerOverlay:draw()
	local x, y, w, h, rows, rowH = self:geometry()
	Gfx.window(x, y, w, h, self.title)
	if self.sel < self.top then self.top = self.sel end
	if self.sel > self.top + rows - 1 then self.top = self.sel - rows + 1 end
	for i = self.top, math.min(#self.items, self.top + rows - 1) do
		local it = self.items[i]
		local ry = y + 14 + (i - self.top) * rowH
		local sel = i == self.sel
		if sel then
			Gfx.selbar(x + 8, ry, w - 16, rowH)
			Gfx.cursor(x + 11, ry + 6, true)
		end
		local tx = x + 22
		if it.icon then Gfx.icon(it.icon, tx, ry + 6, { white = sel }); tx = tx + 14 end
		if it.key then
			Gfx.icon(it.key, x + w - 24, ry + 6, { white = sel })
		end
		Gfx.text(it.label, tx, ry + 2, { bold = true, white = sel, maxW = w - (tx - x) - 30 })
	end
	if #self.items > rows then
		Gfx.pix(self.sel .. "/" .. #self.items, x + w - 14, y + h - 14, 1, { align = "right" })
	end
	Gfx.hints(self.opts.hints or { { "crank", "PICK" }, { "A", "SELECT" }, { "B", "CANCEL" } })
end

function PickerOverlay:event(ev)
	if ev == "UP" then self.sel = Util.wrap(self.sel - 1, #self.items)
	elseif ev == "DOWN" then self.sel = Util.wrap(self.sel + 1, #self.items)
	elseif ev == "A" or (ev == "RIGHT" and not self.opts.noRightPick) then
		local it = self.items[self.sel]
		App.pop()
		if it and self.onPick then self.onPick(it) end
	elseif ev == "B" or ev == "LEFT" then
		App.pop()
		if self.opts.onCancel then self.opts.onCancel() end
	end
	return true
end

function PickerOverlay:crank(change, accel)
	local n = self.stepper:feed(accel)
	if n ~= 0 then self.sel = Util.clamp(self.sel + n, 1, #self.items) end
end

---------------------------------------------------------------------------
-- MultiPickerOverlay: toggle items, "DONE" row returns the list.
---------------------------------------------------------------------------
MultiPickerOverlay = PickerOverlay:extend()
MultiPickerOverlay.overlay = true

function MultiPickerOverlay:init(title, options, selected, onDone)
	local chosen = {}
	for _, v in ipairs(selected or {}) do chosen[Util.upper(v)] = true end
	-- selected values missing from the options list stay available
	local all = Util.uniq(Util.concat(options, selected or {}))
	self.chosen = chosen
	self.values = all
	local items = { { label = "DONE", done = true, icon = "check" } }
	for _, v in ipairs(all) do items[#items + 1] = { label = v, value = v } end
	PickerOverlay.init(self, title, items, nil, nil, { hints = { { "crank", "MOVE" }, { "A", "TOGGLE" }, { "B", "DONE" } } })
	self.onDone = onDone
	self:refresh()
end

function MultiPickerOverlay:refresh()
	for _, it in ipairs(self.items) do
		if not it.done then it.icon = self.chosen[Util.upper(it.value)] and "check" or "todo" end
	end
end

function MultiPickerOverlay:finish()
	local out = {}
	for _, v in ipairs(self.values) do if self.chosen[Util.upper(v)] then out[#out + 1] = v end end
	App.pop()
	self.onDone(out)
end

function MultiPickerOverlay:event(ev)
	if ev == "UP" then self.sel = Util.wrap(self.sel - 1, #self.items)
	elseif ev == "DOWN" then self.sel = Util.wrap(self.sel + 1, #self.items)
	elseif ev == "A" or ev == "RIGHT" then
		local it = self.items[self.sel]
		if it.done then self:finish() else
			local k = Util.upper(it.value)
			self.chosen[k] = not self.chosen[k]
			self:refresh()
		end
	elseif ev == "B" then self:finish()
	end
	return true
end

---------------------------------------------------------------------------
-- ConfirmOverlay
---------------------------------------------------------------------------
ConfirmOverlay = Screen:extend()
ConfirmOverlay.overlay = true

function ConfirmOverlay:init(text, onYes, opts)
	self.text = Util.upper(text)
	self.onYes = onYes
	self.opts = opts or {}
end

function ConfirmOverlay:draw()
	local lines = Gfx.wrap(self.text, 260, 4, true)
	local h = #lines * (Gfx.lineH + 2) + 44
	local x, y, w = 60, (Gfx.H - 18 - h) // 2, 280
	Gfx.window(x, y, w, h, self.opts.title or "CONFIRM")
	for i, l in ipairs(lines) do Gfx.text(l, x + w // 2, y + 12 + (i - 1) * (Gfx.lineH + 2), { bold = true, align = "center" }) end
	Gfx.hints({ { "A", self.opts.yes or "YES" }, { "B", self.opts.no or "NO" } })
end

function ConfirmOverlay:event(ev)
	if ev == "A" then App.pop(); self.onYes()
	elseif ev == "B" then App.pop(); if self.opts.onNo then self.opts.onNo() end end
	return true
end

---------------------------------------------------------------------------
-- RateOverlay: shown right after TAKE +1.
--   UP great, RIGHT good, DOWN bad, LEFT technical (then issue picker)
--   A = another take, hold A = circle, B = leave unrated.
---------------------------------------------------------------------------
RateOverlay = Screen:extend()
RateOverlay.overlay = true
RateOverlay.noDim = true

function RateOverlay:init(takeId, onAnotherTake)
	self.takeId = takeId
	self.onAnotherTake = onAnotherTake
end

local DIR_RATING = { UP = "GREAT", RIGHT = "GOOD", DOWN = "BAD", LEFT = "TECH" }
local RATE_ROWS = { { "up", "GREAT", "star" }, { "right", "GOOD", "check" }, { "down", "BAD", "x" }, { "left", "TECH", "warn" } }

function RateOverlay:draw()
	local take = Model.get(self.takeId)
	if take == nil then return end
	local shot = Model.parentOf[take.id]
	local x, y, w, h = 236, 26, 160, 188
	Gfx.window(x, y, w, h, "RATE " .. Model.code(shot))
	Gfx.pix("T" .. take.n, x + 16, y + 14, 4)
	if take.circle then
		Gfx.icon("ring", x + w - 40, y + 20, { scale = 2 })
		Gfx.pix("CIRCLED", x + w - 14, y + 40, 1, { align = "right" })
	else
		Gfx.pix("HOLD A", x + w - 14, y + 16, 1, { align = "right" })
		Gfx.pix("=CIRCLE", x + w - 14, y + 26, 1, { align = "right" })
	end
	for i, r in ipairs(RATE_ROWS) do
		local ry = y + 52 + (i - 1) * 30
		local sel = take.rating == r[2]
		if sel then Gfx.selbar(x + 8, ry - 2, w - 16, 26) end
		-- the d-pad direction is the big glyph: that is what the thumb needs
		Gfx.icon(r[1], x + 16, ry + 4, { white = sel, scale = 2 })
		Gfx.icon(r[3], x + 42, ry + 7, { white = sel })
		Gfx.pix(r[2], x + 56, ry + 4, 2, { white = sel })
	end
	Gfx.hints({ { "A", "TAKE+1" }, { "!A", "CIRCLE" }, { "B", "SKIP" }, { "!B", "NEXT" } })
end

function RateOverlay:event(ev)
	local take = Model.get(self.takeId)
	if take == nil then App.pop(); return true end
	local rating = DIR_RATING[ev]
	if rating then
		App.commit(Model.opSet(take, "rating", rating, "T" .. take.n .. " " .. rating))
		if rating == "TECH" then
			App.replace(IssuePicker:new(take, "tech"))
		elseif rating == "BAD" and Model.db.settings.askPerf then
			App.replace(IssuePicker:new(take, "perf"))
		else
			App.pop()
			App.toast("T" .. take.n .. " " .. rating, { icon = Vocab.RATING_ICON[rating], undo = true })
		end
	elseif ev == "A" then
		App.pop()
		if self.onAnotherTake then self.onAnotherTake() end
	elseif ev == "AL" then
		-- the ring in the window is the feedback; no toast over the card
		App.commit(Model.opCircle(take, Util.now()))
	elseif ev == "B" then
		App.pop()
	end
	return true
end

---------------------------------------------------------------------------
-- IssuePicker: technical / performance issue for a take.
---------------------------------------------------------------------------
IssuePicker = PickerOverlay:extend()
IssuePicker.overlay = true

function IssuePicker:init(take, kind)
	local list = kind == "tech" and Vocab.TECH_ISSUE or Vocab.PERF_ISSUE
	local items = {}
	for _, v in ipairs(list) do items[#items + 1] = { label = v, value = v } end
	PickerOverlay.init(self, (kind == "tech" and "TECH ISSUE T" or "PERFORMANCE T") .. take.n, items, take[kind], function(it)
		App.commit(Model.opSet(take, kind, it.value, "T" .. take.n .. " " .. it.value))
		App.toast("T" .. take.n .. " " .. it.value, { icon = kind == "tech" and "warn" or "x", undo = true })
	end, { rows = 8, w = 220, hints = { { "crank", "PICK" }, { "A", "SAVE" }, { "B", "SKIP" } } })
end

return PickerOverlay
