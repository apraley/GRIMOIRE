-- PRINT QUEUE.
--
-- A list of jobs in print order with a detail panel. Left/right switch the
-- filter tab. A opens the job's action menu. MOVE lifts the job off the
-- list: turn the crank and it ratchets up or down one slot per detent
-- (with a click), A or B sets it down.

local gfx <const> = playdate.graphics

QueueScreen = {}
QueueScreen.__index = QueueScreen

local ROWS = 9

function QueueScreen.new()
	local s = setmetatable({
		filter = 1,
		list = ScrollList.new(ROWS),
		moving = nil,         -- job being reordered
		moveTicker = CrankTicker.new(40),
		lift = 0,
	}, QueueScreen)
	s:refresh()
	return s
end

function QueueScreen:filterName()
	return Queue.FILTERS[self.filter]
end

-- Row 1 is always "+ NEW JOB" (except in the archive view).
function QueueScreen:refresh()
	self.jobs = Queue.list(self:filterName())
	self.hasNew = self:filterName() ~= "ARCHIVED"
	self.list:setCount(#self.jobs + (self.hasNew and 1 or 0))
end

function QueueScreen:resume()
	self:refresh()
end

function QueueScreen:selectedJob()
	local i = self.list.sel - (self.hasNew and 1 or 0)
	return self.jobs[i], i
end

function QueueScreen:actions(j)
	local items = {}
	local live = Printing.isLive(j)
	local canStart, why = Printing.canStart(j)
	if Job.isStartable(j) then
		items[#items + 1] = { label = "PRINT NOW", disabled = not canStart, hint = canStart and "Send to " .. Store.activePrinter().name or why,
			action = function()
				local ok, err = Printing.start(j)
				if ok then
					Toast.show("PRINTING " .. j.name, "play")
					Screens.push(WatchScreen.new())
				else
					Toast.show(err, "warn")
				end
			end }
	end
	if live then
		items[#items + 1] = { label = "WATCH PRINT", action = function() Screens.push(WatchScreen.new()) end }
	end
	items[#items + 1] = { label = "EDIT", action = function() Screens.push(JobEditScreen.new(j)) end }
	if not j.archived and self:filterName() ~= "DONE" then
		items[#items + 1] = { label = "MOVE (CRANK)", action = function() self:startMove(j) end,
			hint = "Crank to slide it up or down the queue." }
	end
	if j.status == "IDEA" then
		items[#items + 1] = { label = "MARK READY", action = function() Queue.setStatus(j, "READY") self:refresh() end }
	end
	if j.status == "READY" or j.status == "IDEA" then
		items[#items + 1] = { label = "ADD TO QUEUE", action = function() Queue.setStatus(j, "QUEUED") self:refresh() end }
	end
	if j.status == "FAILED" or j.status == "COMPLETE" then
		items[#items + 1] = { label = "RETRY", hint = "Back in line with the latest profile.", action = function()
			Queue.retry(j)
			Toast.show("RETRY QUEUED", "check")
			self:refresh()
		end }
	end
	items[#items + 1] = { label = "DUPLICATE", action = function()
		local c = Queue.duplicate(j)
		Toast.show("COPIED " .. c.name, "check")
		self:refresh()
	end }
	if not live and j.status ~= "COMPLETE" and not j.archived then
		items[#items + 1] = { label = "MARK COMPLETE", hint = "Printed off the record: logs filament + history.",
			action = function()
				Confirm("LOG " .. U.truncate(j.name, 16) .. " DONE?", function()
					Printing.markComplete(j)
					Sfx.play("done")
					Toast.show("LOGGED " .. j.name, "check")
					self:refresh()
				end)
			end }
		items[#items + 1] = { label = "MARK FAILED...", action = function()
			Screens.push(FailureScreen.new({ job = j }))
		end }
	end
	if j.archived then
		items[#items + 1] = { label = "UNARCHIVE", action = function() Queue.archive(j, false) self:refresh() end }
		items[#items + 1] = { label = "DELETE FOREVER", action = function()
			Confirm("DELETE " .. U.truncate(j.name, 18) .. "?", function() Queue.remove(j) self:refresh() end)
		end }
	elseif not live then
		items[#items + 1] = { label = "ARCHIVE", action = function() Queue.archive(j, true) self:refresh() end }
	end
	if j.project ~= "" then
		items[#items + 1] = { label = "PROJECT: " .. U.truncate(j.project, 14), action = function()
			Screens.push(ProjectScreen.new(j.project))
		end }
	end
	items[#items + 1] = { label = "SORT QUEUE BY PRIORITY", action = function()
		Queue.sortByPriority()
		self:refresh()
		Toast.show("SORTED BY PRIORITY", "check")
	end }
	items[#items + 1] = { label = "ASK THE CAPTAIN", action = function() Common.help("queue") end }
	Menu.open({ title = U.truncate(j.name, 24), items = items, maxRows = 10 })
end

function QueueScreen:startMove(j)
	self.moving = j
	self.moveTicker:reset()
	self.lift = 0
	Sfx.play("ok")
end

function QueueScreen:updateMove(dtMs)
	self.lift = math.min(4, self.lift + 1)
	local d = self.moveTicker:update() + Input.vertical()
	if d ~= 0 then
		local step = d > 0 and 1 or -1
		local before = select(2, U.findById(self.jobs, self.moving.id))
		local after = Queue.move(self.moving, step, self.jobs)
		if after and after ~= before then
			Sfx.play("tick")
			self.list:select(after + (self.hasNew and 1 or 0))
		else
			Sfx.play("error")
		end
	end
	if Input.a() or Input.b() then
		self.moving = nil
		Sfx.play("ok")
		self:refresh()
	end
end

function QueueScreen:update(dtMs)
	if self.moving then
		self:updateMove(dtMs)
		return
	end
	self.list:update()
	local h = Input.horizontal()
	if h ~= 0 then
		self.filter = U.wrap(self.filter + h, #Queue.FILTERS)
		self.list:select(1)
		self:refresh()
		Sfx.play("move")
	end
	if Input.a() then
		local j = self:selectedJob()
		if self.hasNew and self.list.sel == 1 then
			Screens.push(JobEditScreen.new(nil))
		elseif j then
			self:actions(j)
		end
	elseif Input.b() then
		Sfx.play("back")
		Screens.pop()
	end
end

---------------------------------------------------------------------------

function QueueScreen:drawTabs()
	local x = 6
	for i, name in ipairs(Queue.FILTERS) do
		local w = Text.width(name) + 10
		if i == self.filter then
			gfx.setColor(gfx.kColorBlack)
			gfx.fillRect(x, 17, w, 13)
			Text.draw(name, x + 5, 19, { color = "white" })
		else
			gfx.setColor(gfx.kColorBlack)
			gfx.drawRect(x, 17, w, 13)
			Text.draw(name, x + 5, 19, { color = "black" })
		end
		x = x + w + 3
	end
	local c = Queue.counts()
	local b = Queue.backlog()
	Text.draw(string.format("%d QUEUED  %s  %s", c.QUEUED + c.READY, U.fmtDuration(b.minutes * 60), U.fmtGrams(b.grams)),
		396, 19, { align = "right", color = "black" })
end

function QueueScreen:drawRow(j, x, y, w, selected, lifted)
	local ink = Draw.fgInk()
	local fg = Draw.fgColor()
	if lifted then
		-- Lifted row: drop shadow and inverted body.
		gfx.setColor(gfx.kColorBlack)
		Draw.fillPattern("gray50", x + 3, y + 2, w, 12)
		gfx.setColor(fg)
		gfx.fillRect(x, y - self.lift, w, 12)
		ink = Draw.bgInk()
		y = y - self.lift
	end
	local tag = Job.STATUS_TAG[j.status] or "?"
	local solid = j.status == "PRINTING" or j.status == "FAILED"
	Draw.tag(tag, x + 12, y, solid, lifted and Draw.bgColor() or fg)
	Text.draw(U.truncate(j.name, 18), x + 44, y + 1, { color = ink })
	local right = U.fmtDuration(j.estMinutes * 60)
	Text.draw(right, x + w - 4, y + 1, { color = ink, align = "right" })
	-- Priority pips and warnings.
	local px = x + w - 4 - Text.width(right) - 30
	Draw.pips(px, y + 2, j.priority, 5, lifted and Draw.bgColor() or fg)
	if Queue.filamentShortfall(j) and Job.isActive(j) then
		Text.draw(FontData.icon.warn, px - 10, y + 1, { color = ink })
	end
	if selected and not lifted then Draw.cursor(x + 2, y + 2) end
end

function QueueScreen:drawDetail(j, x, y, w, h)
	Draw.window(x, y, w, h, { title = "JOB" })
	local ix, iw = x + 10, w - 20
	local ty = y + 9
	if j == nil then
		if self.hasNew then
			Text.drawWrapped("Add a new job. Pick a spool and the Captain's recommended profile fills in the temperatures.", ix, ty, iw, 10)
		end
		return
	end
	Text.drawWrapped(j.name, ix, ty, iw, 2)
	ty = ty + 24
	if j.model ~= "" then Text.draw(U.truncate(j.model, Text.fit(iw)), ix, ty) ty = ty + 11 end
	local spool = j.spoolId and Store.spool(j.spoolId)
	Text.draw(U.truncate(spool and Spool.shortLabel(spool) or (j.material .. " " .. j.color), Text.fit(iw)), ix, ty)
	ty = ty + 11
	Draw.row("STATUS", j.status, ix, ty, iw) ty = ty + 11
	Draw.row("PRIORITY", Job.priorityLabel(j), ix, ty, iw) ty = ty + 11
	Draw.row("EST", U.fmtDuration(j.estMinutes * 60) .. " " .. U.fmtGrams(j.estGrams), ix, ty, iw) ty = ty + 11
	if spool then
		Draw.row("COST", U.fmtMoney(Filament.cost(spool, j.estGrams)), ix, ty, iw) ty = ty + 11
	end
	Draw.row("TEMPS", string.format("%d/%d", j.nozzleTemp, j.bedTemp) .. FontData.icon.deg .. "C", ix, ty, iw) ty = ty + 11
	if j.profileKey ~= "" then
		local _, m, f = Calibration.splitKey(j.profileKey)
		Text.draw(FontData.icon.star .. " PROFILE " .. U.truncate((m or "") .. "/" .. (f or ""), 18), ix, ty)
		ty = ty + 11
	end
	if j.project ~= "" then Draw.row("PROJECT", U.truncate(j.project, 14), ix, ty, iw) ty = ty + 11 end
	Draw.row("ADDED", U.fmtShortDate(j.createdAt), ix, ty, iw) ty = ty + 11
	if j.completedAt > 0 then Draw.row("DONE", U.fmtShortDate(j.completedAt), ix, ty, iw) ty = ty + 11 end
	if j.attempts > 0 then Draw.row("ATTEMPTS", tostring(j.attempts), ix, ty, iw) ty = ty + 11 end
	local short = Queue.filamentShortfall(j)
	if short and ty < y + h - 12 then
		Text.draw(FontData.icon.warn .. " SHORT " .. U.fmtGrams(short), ix, ty)
		ty = ty + 11
	end
	if j.notes ~= "" and ty < y + h - 12 then
		Text.drawWrapped(j.notes, ix, ty, iw, (y + h - 6 - ty) // Text.LINE)
	end
end

function QueueScreen:draw()
	local hints = self.moving and "CRANK/" .. FontData.icon.up .. FontData.icon.down .. ": MOVE   A/B: DROP"
		or FontData.icon.left .. FontData.icon.right .. ":FILTER  A:ACTIONS  B:BACK"
	Common.page("PRINT QUEUE", nil, hints)
	self:drawTabs()
	local x, y, w = 4, 34, 232
	Draw.window(x, y, w, 190)
	if #self.jobs == 0 and not self.hasNew then
		Text.drawWrapped("Nothing archived. Finished jobs can be archived from their action menu.", x + 12, y + 14, w - 24, 6)
	end
	for i, row in self.list:visible() do
		local ry = y + 10 + row * 19
		if self.hasNew and i == 1 then
			Text.draw("+ NEW JOB", x + 48, ry + 1)
			if self.list.sel == 1 then Draw.cursor(x + 14, ry + 2) end
		else
			local j = self.jobs[i - (self.hasNew and 1 or 0)]
			if j then
				local lifted = self.moving ~= nil and self.moving.id == j.id
				self:drawRow(j, x + 4, ry, w - 14, i == self.list.sel, lifted)
			end
		end
	end
	if #self.jobs == 0 and self.hasNew then
		Text.drawWrapped("No jobs here yet. The Captain suggests a Benchy.", x + 12, y + 40, w - 24, 3)
	end
	self.list:drawScrollbar(x + w - 8, y + 8, 174)
	local j = self:selectedJob()
	self:drawDetail(j, 240, 34, 156, 190)
end
