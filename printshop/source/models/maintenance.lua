-- Maintenance task model. A task can be due by print-hours, by calendar days,
-- or both (whichever comes first). "Last performed" is stored both as a date
-- and as the printer's print-hour odometer at that moment.

Maint = {}

Maint.DEFAULTS = {
	kind = "custom",
	name = "CUSTOM TASK",
	printerId = "p1",
	intervalHours = 0,   -- 0 = no hour interval
	intervalDays = 0,    -- 0 = no calendar interval
	lastAt = 0,
	lastHours = 0,
	notes = "",
	enabled = true,
}

function Maint.new(fields)
	local t = U.copy(fields or {})
	return Maint.normalize(t)
end

function Maint.normalize(t)
	U.defaults(t, Maint.DEFAULTS)
	t.id = U.str(t.id, nil)
	local kinds = U.map(Enums.MAINT_KINDS, function(k) return k.id end)
	t.kind = U.oneOf(t.kind, kinds, "custom")
	t.name = U.str(t.name, Enums.MAINT_LABEL[t.kind] or "TASK")
	t.intervalHours = math.max(0, U.num(t.intervalHours, 0))
	t.intervalDays = math.max(0, U.int(t.intervalDays, 0))
	t.lastAt = U.int(t.lastAt, 0)
	t.lastHours = math.max(0, U.num(t.lastHours, 0))
	t.enabled = t.enabled ~= false
	t.notes = U.str(t.notes, "")
	return t
end

-- Computes due state against the printer's hour odometer and today's date.
-- Returns a table:
--   frac      0..1+ how far through the interval (max of hours/days)
--   due       frac >= 1
--   soon      frac >= 0.8
--   hoursLeft, daysLeft  (nil when that interval isn't used)
--   never     task has never been performed
function Maint.status(t, printerHours, now)
	local st = { frac = 0, due = false, soon = false, never = t.lastAt == 0 }
	if not t.enabled then return st end
	if t.intervalHours > 0 then
		local used = math.max(0, printerHours - t.lastHours)
		st.hoursLeft = t.intervalHours - used
		st.frac = math.max(st.frac, used / t.intervalHours)
	end
	if t.intervalDays > 0 then
		local days, calDays = 0, 0
		if t.lastAt > 0 then
			days = (now - t.lastAt) / U.DAY
			calDays = U.daysBetween(t.lastAt, now)
		end
		-- Labels count calendar days ("DUE TODAY" means today); urgency
		-- (frac) uses the exact elapsed time.
		st.daysLeft = t.intervalDays - calDays
		st.frac = math.max(st.frac, days / t.intervalDays)
	end
	if st.never and (t.intervalHours > 0 or t.intervalDays > 0) then
		st.frac = math.max(st.frac, 1)
	end
	st.due = st.frac >= 1
	st.soon = st.frac >= 0.8
	return st
end

function Maint.fmtNext(st)
	if st.never then return "NEVER DONE" end
	local parts = {}
	if st.hoursLeft ~= nil then
		if st.hoursLeft <= 0 then parts[#parts + 1] = "OVER " .. U.fmtHours(-st.hoursLeft)
		else parts[#parts + 1] = U.fmtHours(st.hoursLeft) .. " LEFT" end
	end
	if st.daysLeft ~= nil then
		if st.daysLeft <= 0 then parts[#parts + 1] = "DUE " .. (st.daysLeft == 0 and "TODAY" or (-st.daysLeft .. "D AGO"))
		else parts[#parts + 1] = st.daysLeft .. "D LEFT" end
	end
	if #parts == 0 then return "NO INTERVAL" end
	return table.concat(parts, " / ")
end

MaintLog = {}

function MaintLog.normalize(e)
	e.id = U.str(e.id, nil)
	e.taskId = U.str(e.taskId, "")
	e.at = U.int(e.at, 0)
	e.hoursAt = math.max(0, U.num(e.hoursAt, 0))
	e.note = U.str(e.note, "")
	e.kind = U.str(e.kind, "custom")
	e.name = U.str(e.name, "")
	return e
end
