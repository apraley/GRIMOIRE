-- THE BENCHY CAPTAIN: a deterministic, rule-based advisor.
--
-- 1. Services emit events; the Captain turns relevant ones into inbox items
--    (persisted, so news survives a restart).
-- 2. When asked, he delivers news first, then picks the most relevant topic
--    from the current shop state using weighted rules (failures -> advice,
--    due maintenance, low/damp spools, missing calibration, idle printer,
--    queue status, stats, wisdom).
-- 3. A line is OPENER + BODY + CLOSER from data/phrases.lua with slots filled
--    from real data. The choice is seeded by (topic, day, conversation
--    counter), so the same shop on the same day gives the same answers, and
--    asking again moves the conversation on.

Captain = {
	tickerText = nil,
	tickerAge = 99999,
}

local function cap() return Store.data.captain end

local function inbox(kind, data, mood, priority)
	local box = cap().inbox
	box[#box + 1] = { kind = kind, data = data, mood = mood or "neutral", priority = priority or 1, at = Clock.now() }
	-- Highest priority first, then newest.
	U.stableSort(box, function(a, b) return a.priority > b.priority end)
	while #box > 8 do table.remove(box) end
	Captain.tickerAge = 99999
	Store.markDirty()
end

function Captain.init()
	Events.on("print.finished", function(e)
		local j, h = e.job, e.history
		local data = {
			job = j.name, grams = U.fmtGrams(h.grams), material = h.material, maker = h.manufacturer,
			duration = U.fmtDuration(h.durationSec), layer = h.layer, pct = U.fmtPct(h.progress * 100),
			cause = h.cause, project = j.project, spool = e.spool and Spool.shortLabel(e.spool) or "",
			spoolLeft = e.spool and U.fmtGrams(e.spool.remainingGrams) or "", attempts = j.attempts,
		}
		if e.outcome == "success" then
			inbox("complete", data, "happy", 3)
		elseif e.outcome == "failed" then
			inbox("fail", data, "worried", 4)
		else
			inbox("cancelled", data, "neutral", 2)
		end
		for _, c in ipairs(e.maintCrossed or {}) do
			inbox(c.st.due and "maint_due" or "maint_soon", { task = c.task.name, when = Maint.fmtNext(c.st) }, "stern", 2)
		end
	end)
	Events.on("spool.low", function(e)
		local s = e.spool
		inbox(e.empty and "empty_spool" or "low_spool", { spool = Spool.shortLabel(s), grams = U.fmtGrams(s.remainingGrams),
			material = s.material }, "stern", 2)
	end)
	Events.on("spool.damp", function(e)
		local s = e.spools[1]
		if s then
			inbox("damp_spool", { spool = Spool.shortLabel(s), dryness = s.dryness, material = s.material }, "stern", 1)
		end
	end)
	Events.on("calib.saved", function(e)
		local p = e.profile
		inbox("calib_saved", { procedure = Phrases.procedureNames[e.procedure] or e.procedure,
			material = p.material, maker = p.manufacturer, jobs = e.jobsUpdated }, "happy", 1)
	end)
	Events.on("job.retry", function(e)
		inbox("retry", { job = e.job.name }, "neutral", 1)
	end)
	Events.on("maint.done", function(e)
		inbox("maint_done", { task = e.task.name }, "happy", 1)
	end)
end

function Captain.hasNews()
	return #cap().inbox > 0
end

---------------------------------------------------------------------------
-- line assembly

local function rngFor(topic, extra)
	local c = cap()
	local day = Clock.now() // U.DAY
	return Rng.new(U.hash(topic .. ":" .. day .. ":" .. c.counter .. ":" .. tostring(extra or "")))
end

-- Builds a full line for a topic bank. vars fill {slots}.
function Captain.compose(topic, vars, mood, rng)
	rng = rng or rngFor(topic)
	local bank = Phrases.topics[topic] or Phrases.topics.wisdom
	local body = U.template(rng:pick(bank), vars or {})
	local openers = Phrases.openers
	if mood and Phrases.moodOpeners[mood] and rng:chance(0.6) then
		openers = Phrases.moodOpeners[mood]
	end
	local opener = rng:chance(0.85) and rng:pick(openers) or ""
	local closer = rng:pick(Phrases.closers)
	local parts = {}
	if opener ~= "" then parts[#parts + 1] = opener end
	parts[#parts + 1] = body
	if closer ~= "" then parts[#parts + 1] = closer end
	return table.concat(parts, " ")
end

local function fmtCause(c)
	return string.lower(Enums.CAUSE_LABEL[c] or "mystery")
end

-- Converts an inbox item into { text, mood, topic }.
function Captain.renderNews(item)
	local d = U.copy(item.data or {})
	local topic = item.kind
	if topic == "fail" then
		topic = "fail_" .. (d.cause ~= "" and d.cause or "unknown")
		if Phrases.topics[topic] == nil then topic = "fail_unknown" end
		d.maker = d.maker or "?"
	elseif topic == "complete" then
		local streak = Store.activePrinter().stats.streak
		d.prints = Store.activePrinter().stats.prints
		d.streak = streak
		if (d.attempts or 1) > 1 then topic = "complete_after_fail"
		elseif streak >= 3 and streak % 3 == 0 then topic = "complete_streak" end
		if d.project == nil or d.project == "" then d.project = "shop" end
	end
	local rng = rngFor(topic, item.at)
	return { text = Captain.compose(topic, d, item.mood, rng), mood = item.mood, topic = topic }
end

-- Pops the most important news item, or nil.
function Captain.nextNews()
	local box = cap().inbox
	if #box == 0 then return nil end
	local item = table.remove(box, 1)
	Store.markDirty()
	return Captain.renderNews(item)
end

---------------------------------------------------------------------------
-- rules

-- Candidate topics with weights and slot values, from live shop state.
function Captain.candidates(now)
	now = now or Clock.now()
	local out = {}
	local function add(topic, weight, vars, mood)
		out[#out + 1] = { topic = topic, weight = weight, vars = vars or {}, mood = mood or "neutral" }
	end
	local printer = Store.activePrinter()

	-- Live print.
	if Printing.provider then
		local snap = Printing.snapshot()
		if (snap.state == "PRINTING" or snap.state == "HEATING") and snap.job then
			add("printing", 4, { job = snap.job.name, pct = U.fmtPct(snap.progress.pct), layer = snap.progress.layer,
				layers = snap.progress.totalLayers, remaining = U.fmtDuration(snap.progress.remainingSec) })
		end
	end

	-- Failures -> calibration / maintenance advice.
	for i, s in ipairs(Stats.suggestions(now)) do
		if i > 2 then break end
		local count = #Stats.recent(20, function(h) return h.outcome == "failed" and h.cause == s.cause end)
		if s.kind == "calib" then
			add("suggest_calib", 5 + s.weight, { count = count, cause = fmtCause(s.cause), material = s.material,
				maker = s.manufacturer, procedure = Phrases.procedureNames[s.target] or s.target }, "stern")
		else
			add("suggest_maint", 4 + s.weight, { cause = fmtCause(s.cause), task = s.taskName }, "stern")
		end
	end

	-- Maintenance.
	for i, e in ipairs(MaintService.dueSoon(printer.id, now)) do
		if i > 2 then break end
		add(e.st.due and "maint_due" or "maint_soon", e.st.due and 6 or 3,
			{ task = e.task.name, when = string.lower(Maint.fmtNext(e.st)) }, "stern")
	end

	-- Spools.
	local nextJob = Queue.nextFor(printer.id)
	for i, s in ipairs(Filament.lowSpools()) do
		if i > 2 then break end
		local days = Filament.daysUntilEmpty(s, now)
		add("low_spool", 3, { spool = Spool.shortLabel(s), grams = U.fmtGrams(s.remainingGrams),
			next = nextJob and nextJob.name or "Benchy",
			days = days and ("At this rate, empty in " .. days .. " days.") or "" }, "stern")
	end
	for _, s in ipairs(Store.data.spools) do
		if not s.archived and (s.dryness == "DAMP" or s.dryness == "WET") then
			add("damp_spool", s.dryness == "WET" and 4 or 2, { spool = Spool.shortLabel(s), dryness = string.lower(s.dryness),
				material = s.material }, "stern")
			break
		end
	end

	-- Queue.
	if nextJob then
		local shortfall = Queue.filamentShortfall(nextJob)
		local sp = nextJob.spoolId and Store.spool(nextJob.spoolId) or nil
		if shortfall and sp then
			add("shortfall", 6, { job = nextJob.name, need = U.fmtGrams(nextJob.estGrams),
				spool = Spool.shortLabel(sp), have = U.fmtGrams(sp.remainingGrams) }, "stern")
		end
		local rec = CalService.recommend(printer.id, nextJob.material, sp and sp.manufacturer or nil)
		if rec.level == "default" then
			add("no_profile", 3, { material = nextJob.material, maker = sp and sp.manufacturer or "ANY" })
		end
		local b = Queue.backlog()
		add("queue_status", 2, { n = b.count, next = nextJob.name, duration = U.fmtDuration(nextJob.estMinutes * 60),
			hours = U.fmtDuration(b.minutes * 60), grams = U.fmtGrams(b.grams),
			spool = sp and Spool.shortLabel(sp) or "any spool" })
	else
		add("queue_empty", 2)
	end

	-- Idle.
	local last = printer.stats.lastPrintAt
	if last > 0 and now - last > 3 * U.DAY then
		add("idle", 3, { days = (now - last) // U.DAY })
	end

	-- Stats and a favourite combo.
	local o = Stats.overall()
	if o.prints > 0 then
		add("stats", 1, { prints = o.prints, meters = U.roundInt(Stats.metersPrinted()),
			rate = o.rate and U.fmtPct(o.rate * 100) or "--", failures = o.failures, kg = U.fmtGrams(o.grams) })
		local combos = Stats.combos()
		local c = combos[1]
		if c and c.prints >= 3 then
			add("combo", 2, { material = c.material, maker = c.manufacturer, prints = c.prints, failures = c.failures,
				cause = c.topCause and fmtCause(c.topCause) or "none", temp = c.avgNozzle and U.fmtTemp(c.avgNozzle) or "--" })
		end
	end

	add("wisdom", 2)
	return out
end

-- Returns { text, mood, topic }. News first; otherwise a weighted pick among
-- candidates, avoiding the last few topics so conversation stays fresh.
function Captain.advice(now)
	local news = Captain.nextNews()
	local c = cap()
	c.counter = c.counter + 1
	Store.markDirty()
	if news then return news end
	local cands = Captain.candidates(now)
	local recent = {}
	for _, t in ipairs(c.lastTopics) do recent[t] = true end
	for _, cand in ipairs(cands) do
		if recent[cand.topic] then cand.weight = cand.weight * 0.25 end
	end
	local rng = rngFor("advice")
	local pick = rng:weighted(cands)
	c.lastTopics[#c.lastTopics + 1] = pick.topic
	while #c.lastTopics > 3 do table.remove(c.lastTopics, 1) end
	return { text = Captain.compose(pick.topic, pick.vars, pick.mood, rng), mood = pick.mood, topic = pick.topic }
end

-- Greeting by time of day.
function Captain.greeting()
	local h = Clock.hour()
	local topic = "greet_day"
	if h >= 5 and h < 11 then topic = "greet_morning"
	elseif h >= 18 and h < 23 then topic = "greet_evening"
	elseif h >= 23 or h < 5 then topic = "greet_night" end
	local s = Store.data.spools[1]
	return { text = Captain.compose(topic, { material = s and s.material or "PLA" }, "happy"), mood = "happy", topic = topic }
end

function Captain.wisdom()
	local c = cap()
	c.counter = c.counter + 1
	return { text = Captain.compose("wisdom", {}, "neutral", rngFor("wisdom")), mood = "neutral", topic = "wisdom" }
end

-- Pages of the feature tutorial.
function Captain.explain(feature)
	return Phrases.explain[feature] or Phrases.explain.captain
end

-- "PETG / OVERTURE: 12 prints, 3 failures..." for a combo.
function Captain.comboReport(material, maker)
	maker = maker or "ANY"
	local a = Stats.combo(material, maker)
	if a.prints == 0 then
		return "No prints logged for " .. material .. " / " .. maker .. " yet. Print something and I'll keep score."
	end
	return Captain.compose("combo", { material = material, maker = maker, prints = a.prints, failures = a.failures,
		cause = a.topCause and fmtCause(a.topCause) or "none", temp = a.avgNozzle and U.fmtTemp(a.avgNozzle) or "--" },
		"neutral", rngFor("combo", material .. maker))
end

-- One short line for the workshop's speech bubble; refreshed every ~20s or
-- when news arrives.
function Captain.ticker(dtMs)
	Captain.tickerAge = Captain.tickerAge + (dtMs or 0)
	if Captain.tickerText == nil or Captain.tickerAge > 20000 then
		Captain.tickerAge = 0
		local box = cap().inbox
		if #box > 0 then
			Captain.tickerText = "! NEWS: " .. ({
				complete = "A PRINT FINISHED", fail = "A PRINT FAILED", cancelled = "A PRINT WAS CANCELLED",
				maint_due = "MAINTENANCE DUE", maint_soon = "MAINTENANCE SOON", low_spool = "SPOOL RUNNING LOW",
				empty_spool = "SPOOL EMPTY", damp_spool = "DAMP SPOOL", calib_saved = "NEW CALIBRATION",
				retry = "RETRY QUEUED", maint_done = "CHORE LOGGED",
			})[box[1].kind] or "CAPTAIN HAS NEWS"
		else
			local rng = rngFor("ticker", Clock.now() // 20)
			Captain.tickerText = rng:pick(Phrases.topics.wisdom)
		end
	end
	return Captain.tickerText
end
