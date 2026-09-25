-- PRINTER MAINTENANCE LOG.
--
-- Tasks sorted by urgency with a due bar (the fuller, the sooner). The
-- header shows the printer's print-hour odometer, which every finished
-- print advances. A: log done / edit / history. Also: one-off events
-- (firmware notes, replacement parts) and custom tasks.

local gfx <const> = playdate.graphics

MaintScreen = {}
MaintScreen.__index = MaintScreen

function MaintScreen.new()
	local s = setmetatable({ list = ScrollList.new(8) }, MaintScreen)
	s:refresh()
	return s
end

function MaintScreen:refresh()
	self.printer = Store.activePrinter()
	self.rows = MaintService.list(self.printer.id)
	-- Extra rows at the end: new task, log event, full history.
	self.list:setCount(#self.rows + 3)
end

function MaintScreen:resume() self:refresh() end

function MaintScreen:logDone(t)
	Menu.open({ title = "LOG " .. U.truncate(t.name, 18), items = {
		{ label = "DONE, NO NOTE", action = function()
			MaintService.logDone(t, "")
			Sfx.play("done")
			Toast.show(t.name .. " LOGGED", "wrench")
			self:refresh()
		end },
		{ label = "DONE, ADD NOTE...", action = function()
			TextEntry.open("NOTE", "", function(txt)
				MaintService.logDone(t, txt)
				Sfx.play("done")
				Toast.show(t.name .. " LOGGED", "wrench")
				self:refresh()
			end, 60)
		end },
	} })
end

function MaintScreen:actions(e)
	local t = e.task
	local items = {
		{ label = "LOG AS DONE", action = function() self:logDone(t) end },
		{ label = "HOUR INTERVAL", right = t.intervalHours > 0 and U.fmtHours(t.intervalHours) or "OFF", action = function()
			Dial.open({ title = "EVERY N PRINT HOURS", label = "HOURS (0 = OFF)", value = t.intervalHours, min = 0,
				max = 2000, step = 5, unit = "h", onAccept = function(v)
					MaintService.update(t, { intervalHours = v })
					self:refresh()
				end })
		end },
		{ label = "DAY INTERVAL", right = t.intervalDays > 0 and (t.intervalDays .. "D") or "OFF", action = function()
			Dial.open({ title = "EVERY N DAYS", label = "DAYS (0 = OFF)", value = t.intervalDays, min = 0,
				max = 730, step = 1, unit = "d", onAccept = function(v)
					MaintService.update(t, { intervalDays = v })
					self:refresh()
				end })
		end },
		{ label = "HISTORY", action = function() Screens.push(MaintHistoryScreen.new(t)) end },
		{ label = "EDIT NOTES", action = function()
			TextEntry.open("NOTES", t.notes, function(txt) MaintService.update(t, { notes = txt }) end, 80)
		end },
		{ label = "RENAME", action = function()
			TextEntry.open("NAME", t.name, function(txt) if txt ~= "" then MaintService.update(t, { name = U.upper(txt) }) self:refresh() end end, 20)
		end },
		{ label = t.enabled and "DISABLE" or "ENABLE", action = function()
			MaintService.update(t, { enabled = not t.enabled })
			self:refresh()
		end },
		{ label = "DELETE TASK", action = function()
			Confirm("DELETE " .. U.truncate(t.name, 16) .. "?", function() MaintService.remove(t) self:refresh() end)
		end },
		{ label = "ASK THE CAPTAIN", action = function() Common.help("maint") end },
	}
	Menu.open({ title = U.truncate(t.name, 22), items = items, maxRows = 10 })
end

function MaintScreen:newTask()
	local items = {}
	for _, k in ipairs(Enums.MAINT_KINDS) do
		items[#items + 1] = { label = k.label, action = function()
			local t = MaintService.add({ kind = k.id, name = k.label, printerId = self.printer.id,
				intervalHours = k.id == "custom" and 0 or 100, intervalDays = 30 })
			Toast.show("ADDED " .. t.name, "check")
			self:refresh()
			if k.id == "custom" then
				TextEntry.open("TASK NAME", "", function(txt)
					if txt ~= "" then MaintService.update(t, { name = U.upper(txt) }) self:refresh() end
				end, 20)
			end
		end }
	end
	Menu.open({ title = "NEW RECURRING TASK", items = items, maxRows = 10 })
end

function MaintScreen:logEvent()
	local items = {}
	for _, k in ipairs(Enums.MAINT_KINDS) do
		items[#items + 1] = { label = k.label, action = function()
			TextEntry.open(k.label, "", function(txt)
				MaintService.logEvent(k.id, k.label, txt, self.printer.id)
				Toast.show("EVENT LOGGED", "wrench")
			end, 60)
		end }
	end
	Menu.open({ title = "LOG ONE-OFF EVENT", items = items, maxRows = 10 })
end

function MaintScreen:update()
	self.list:update()
	if Input.a() then
		local i = self.list.sel
		local n = #self.rows
		if i <= n then self:actions(self.rows[i])
		elseif i == n + 1 then self:newTask()
		elseif i == n + 2 then self:logEvent()
		else Screens.push(MaintHistoryScreen.new(nil)) end
	elseif Input.b() then
		Sfx.play("back")
		Screens.pop()
	end
end

function MaintScreen:draw()
	local hours = Printer.hours(self.printer)
	Common.page("MAINTENANCE LOG", self.printer.name, "A:ACTIONS  CRANK:SCROLL  B:BACK", "hlines")
	-- Odometer.
	Draw.window(4, 20, 392, 30)
	Text.draw("PRINT HOURS", 16, 30)
	local odo = string.format("%07.1f", hours)
	local ox = 110
	for i = 1, #odo do
		local ch = string.sub(odo, i, i)
		if ch ~= "." then
			gfx.setColor(Draw.fgColor())
			gfx.drawRect(ox - 2, 26, 12, 17)
		end
		Text.draw(ch, ox, 29, { scale = ch == "." and 1 or 2 })
		ox = ox + (ch == "." and 6 or 14)
	end
	local ps = self.printer.stats
	Text.draw(string.format("%d PRINTS  %s", ps.prints, U.fmtGrams(ps.grams)), 388, 30, { align = "right" })

	Draw.window(4, 54, 392, 170)
	for i, row in self.list:visible() do
		local y = 64 + row * 19
		local n = #self.rows
		if i <= n then
			local e = self.rows[i]
			local t, st = e.task, e.st
			local name = U.truncate(t.name, 18)
			Text.draw((st.due and FontData.icon.warn or (st.soon and "!" or " ")) .. " " .. name, 24, y)
			local barX = 160
			Draw.bar(barX, y + 1, 90, 8, math.min(1, st.frac), { pattern = st.due and nil or (st.soon and "gray50" or "light25") })
			if not t.enabled then Text.draw("OFF", barX + 45, y, { align = "center" }) end
			Text.draw(U.truncate(Maint.fmtNext(st), 20), 384, y, { align = "right" })
			Text.draw("LAST " .. (t.lastAt > 0 and U.fmtRelDays(t.lastAt) or "NEVER"), 36, y + 9)
		elseif i == n + 1 then
			Text.draw("+ NEW RECURRING TASK", 24, y + 4)
		elseif i == n + 2 then
			Text.draw("+ LOG ONE-OFF EVENT (FIRMWARE, PARTS)", 24, y + 4)
		else
			Text.draw("FULL HISTORY " .. FontData.icon.right, 24, y + 4)
		end
		if i == self.list.sel then Draw.cursor(12, y + 1) end
	end
	self.list:drawScrollbar(388, 60, 158)
end

---------------------------------------------------------------------------

MaintHistoryScreen = {}
MaintHistoryScreen.__index = MaintHistoryScreen

function MaintHistoryScreen.new(task)
	local s = setmetatable({ task = task, list = ScrollList.new(9) }, MaintHistoryScreen)
	s.rows = MaintService.logFor(task and task.id or nil)
	s.list:setCount(#s.rows)
	return s
end

function MaintHistoryScreen:update()
	self.list:update()
	if Input.a() then
		local e = self.rows[self.list.sel]
		if e and e.note ~= "" then
			Dialog.open({ e.note }, { speaker = U.fmtDate(e.at) })
		end
	elseif Input.b() then
		Sfx.play("back")
		Screens.pop()
	end
end

function MaintHistoryScreen:draw()
	Common.page("HISTORY", self.task and self.task.name or "ALL MAINTENANCE", "A:READ NOTE  B:BACK", "hlines")
	Draw.window(4, 20, 392, 204)
	if #self.rows == 0 then
		Text.drawWrapped("Nothing logged yet. Log a task as done and it appears here, with the print hours at the time.", 20, 36, 360, 5)
		return
	end
	for i, row in self.list:visible() do
		local e = self.rows[i]
		local y = 30 + row * 21
		Text.draw(U.fmtDate(e.at) .. "  " .. U.truncate(e.name, 22), 24, y)
		Text.draw(U.fmtHours(e.hoursAt), 384, y, { align = "right" })
		if e.note ~= "" then Text.draw(U.truncate(e.note, 58), 36, y + 10) end
		if i == self.list.sel then Draw.cursor(12, y + 1) end
	end
	self.list:drawScrollbar(388, 26, 192)
end
