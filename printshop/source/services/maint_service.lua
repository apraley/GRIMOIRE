-- PRINTER MAINTENANCE LOG service.

MaintService = {}

local function printerHours(printerId)
	local p = Store.printer(printerId) or Store.activePrinter()
	return Printer.hours(p)
end

function MaintService.status(t, now)
	return Maint.status(t, printerHours(t.printerId), now or Clock.now())
end

-- Tasks for a printer with their status, most urgent first.
function MaintService.list(printerId, now)
	now = now or Clock.now()
	local out = {}
	for _, t in ipairs(Store.data.maintenance.tasks) do
		if printerId == nil or t.printerId == printerId then
			out[#out + 1] = { task = t, st = MaintService.status(t, now) }
		end
	end
	U.stableSort(out, function(a, b)
		if a.task.enabled ~= b.task.enabled then return a.task.enabled end
		return a.st.frac > b.st.frac
	end)
	return out
end

-- Only tasks that are due or due soon.
function MaintService.dueSoon(printerId, now)
	return U.filter(MaintService.list(printerId, now), function(e) return e.st.soon end)
end

function MaintService.logDone(t, note, now)
	now = now or Clock.now()
	local hours = printerHours(t.printerId)
	t.lastAt = now
	t.lastHours = hours
	local e = MaintLog.normalize({
		id = Store.newId("l"), taskId = t.id, at = now, hoursAt = hours,
		note = note or "", kind = t.kind, name = t.name,
	})
	local log = Store.data.maintenance.log
	log[#log + 1] = e
	while #log > 200 do table.remove(log, 1) end
	Store.markDirty()
	Events.emit("maint.done", { task = t, entry = e })
	return e
end

function MaintService.add(fields)
	local t = Maint.new(fields)
	t.id = Store.newId("m")
	t.printerId = t.printerId or Store.activePrinter().id
	if Store.printer(t.printerId) == nil then t.printerId = Store.activePrinter().id end
	-- A new task starts its clock now rather than being instantly overdue.
	if t.lastAt == 0 then
		t.lastAt = Clock.now()
		t.lastHours = printerHours(t.printerId)
	end
	local tasks = Store.data.maintenance.tasks
	tasks[#tasks + 1] = t
	Store.markDirty()
	return t
end

function MaintService.update(t, fields)
	for k, v in pairs(fields) do t[k] = v end
	Maint.normalize(t)
	Store.markDirty()
end

function MaintService.remove(t)
	local tasks = Store.data.maintenance.tasks
	local _, i = U.findById(tasks, t.id)
	if i then table.remove(tasks, i) end
	Store.markDirty()
end

function MaintService.logFor(taskId, limit)
	local out = {}
	local log = Store.data.maintenance.log
	for i = #log, 1, -1 do
		if taskId == nil or log[i].taskId == taskId then
			out[#out + 1] = log[i]
			if limit and #out >= limit then break end
		end
	end
	return out
end

-- Free-form event (firmware note, one-off repair) that isn't a recurring task.
function MaintService.logEvent(kind, name, note, printerId)
	local p = Store.printer(printerId) or Store.activePrinter()
	local e = MaintLog.normalize({
		id = Store.newId("l"), taskId = "", at = Clock.now(), hoursAt = Printer.hours(p),
		note = note or "", kind = kind or "custom", name = name or "EVENT",
	})
	local log = Store.data.maintenance.log
	log[#log + 1] = e
	while #log > 200 do table.remove(log, 1) end
	Store.markDirty()
	return e
end

-- Called after print hours are added. Returns tasks whose state worsened
-- (ok -> soon, or soon -> due) so the Captain and home banner can react.
function MaintService.checkCrossings(printerId, hoursBefore, now)
	now = now or Clock.now()
	local hoursAfter = printerHours(printerId)
	local crossed = {}
	for _, t in ipairs(Store.data.maintenance.tasks) do
		if t.printerId == printerId and t.enabled then
			local before = Maint.status(t, hoursBefore, now)
			local after = Maint.status(t, hoursAfter, now)
			if (after.due and not before.due) or (after.soon and not before.soon) then
				crossed[#crossed + 1] = { task = t, st = after }
			end
		end
	end
	for _, c in ipairs(crossed) do
		Events.emit("maint.due", { task = c.task, st = c.st })
	end
	return crossed
end
