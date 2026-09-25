-- Simulated 60-shot commercial shoot day, driven only through the UI.
--
-- Plays a realistic day (06:00 call, setups, takes, ratings, tech issues,
-- circles, pickups, continuity notes, lunch, a crash, losing the light at
-- golden hour, wrap) and measures interaction cost for every workflow.
-- Fails if any hard UX requirement is broken (e.g. NEXT > 2 interactions).
--
-- usage: lua5.4 tests/sim_commercial.lua [FRAME_DIR]
local H = dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]+$") or ".") .. "/uiharness.lua")
H.frameDir = arg[1]
if H.frameDir then os.execute('mkdir -p "' .. H.frameDir .. '"') end
math.randomseed(42)

Sim.epoch = H.START_EPOCH + 5 * 60 -- 06:00
H.boot("sim")
assert(H.topName() == "WelcomeScreen")
Sim.tap("A") -- load demo
assert(H.topName() == "LiveScreen")
local function project() return Model.project() end
H.eq(#Model.flat(), 60, "demo has 60 shots")

local M = {                -- friction metrics
	takes = 0, takePresses = 0, ratePresses = 0,
	gotIts = 0, gotItPresses = 0, autoNextHits = 0,
	nextChecks = {}, pickups = 0, notes = 0, notePresses = 0,
	techIssues = 0, techPresses = 0, circles = 0,
	estimates = {}, maxPressesPerShot = 0, shotsDone = 0,
	cut = 0, screens = {},
}

local function clock() return Util.fmtClock(Util.now()) end
local function minutes(m) Sim.advance(m * 60) end
local function pressesSince(p) return Sim.presses - p end
local function cursor() return App.cursorShot() end

-- NEXT from an arbitrary screen: must land on LIVE at the top-ranked candidate
-- in <= 2 interactions.
local function checkNext(where)
	local expected = Model.nextCandidates(cursor() and cursor().id)[1]
	local p = Sim.presses
	Sim.hold("B", 600) -- the NEXT gesture
	local used = pressesSince(p)
	local ok = H.topName() == "LiveScreen" and expected ~= nil and cursor() == expected.shot
	M.nextChecks[#M.nextChecks + 1] = { where = where, presses = used, ok = ok }
	H.check(ok and used <= 2, "NEXT from " .. where .. " took " .. used .. " presses, landed on " .. H.topName())
end

-- Log one take with a rating chosen like a real script supervisor would.
local RATE_KEYS = { GREAT = "UP", GOOD = "RIGHT", BAD = "DOWN", TECH = "LEFT" }
M.setupVisits = 0
local function logTake(rating)
	local p = Sim.presses
	Sim.tap("A")
	assert(H.topName() == "RateOverlay", "rating overlay after A, got " .. H.topName())
	M.takePresses = M.takePresses + pressesSince(p)
	p = Sim.presses
	Sim.tap(RATE_KEYS[rating])
	if rating == "TECH" then
		assert(H.topName() == "IssuePicker")
		local n = math.random(0, 4)
		if n > 0 then Sim.crank(n * 30, 3) end
		Sim.tap("A")
		M.techIssues = M.techIssues + 1
		M.techPresses = M.techPresses + pressesSince(p)
	else
		M.ratePresses = M.ratePresses + pressesSince(p)
	end
	M.takes = M.takes + 1
end

local function takesFor(shot)
	-- product/insert shots take more takes; priority A gets more coverage
	local base = ({ 2, 3, 2 })[tonumber(shot.priority) or 2]
	if shot.size == "INSERT" or shot.size == "ECU" then base = base + 2 end
	return math.max(1, base + math.random(-1, 2))
end

local function randomRating(i, n)
	local r = math.random()
	if i == n then return r < 0.7 and "GREAT" or "GOOD" end
	if r < 0.12 then return "TECH" elseif r < 0.45 then return "BAD" elseif r < 0.8 then return "GOOD" end
	return "GREAT"
end

local lastSetup = nil
local crashed = false
local lunched = false
local rushed = false
local noteShots = { ["02A-02"] = "PROP", ["03A-02"] = "WARDROBE", ["05A-01"] = "POSITION", ["07A-02"] = "LIGHT" }

H.shoot("sim-00-start")
local guard = 0
while true do
	guard = guard + 1
	if guard > 200 then error("simulation did not converge") end
	local shot = cursor()
	if shot == nil or not Model.isOpen(shot) then
		-- nothing open under the cursor: ask for NEXT
		local c = Model.nextCandidates(shot and shot.id)
		if #c == 0 then break end
		Sim.hold("B", 600)
		shot = cursor()
	end
	local ctx = Model.ctx(shot.id)
	local code = Model.code(shot)
	local shotStart = Sim.presses

	-- company moves / relights cost real time
	if lastSetup ~= ctx.setup then
		minutes(lastSetup and (Model.ctx(lastSetup.id).scene == ctx.scene and 7 or 22) or 20)
		lastSetup = ctx.setup
		M.setupVisits = M.setupVisits + 1
	end
	-- lunch at 12:30
	if not lunched and Util.localTime().hour >= 12 and Util.localTime().minute >= 30 then
		lunched = true
		minutes(45)
		Sim.wait(3) -- idle: snapshot is written
		H.check(not Store.dirty, "idle after lunch flushed snapshot")
	end

	-- golden hour: at 18:30 the AD calls it. RUSH mode via the system menu.
	if not rushed and Util.localTime().hour >= 18 and Util.localTime().minute >= 30 then
		rushed = true
		local p = Sim.presses
		Sim.menu("GO", "RUSH")
		Sim.step(2)
		local top = Model.nextCandidates(nil)
		local cur = cursor()
		local best = 3
		for _, e in ipairs(Model.flat()) do
			if Model.isOpen(e.shot) and e.shot ~= cur then best = math.min(best, e.shot.priority) end
		end
		H.check(cur.priority <= best, "RUSH jumps to highest priority open shot (got pri " .. cur.priority .. ")")
		M.rushPresses = pressesSince(p) + 1 -- +1: selecting the RUSH option in the menu
		H.shoot("sim-10-rush")
		shot = cur
		ctx = Model.ctx(shot.id)
		code = Model.code(shot)
	end

	-- time pressure: after 19:10 the light is gone; remaining C shots are cut
	if Util.localTime().hour >= 19 and Util.localTime().minute >= 10 and shot.priority == 3 then
		Sim.tap("LEFT")
		assert(H.topName() == "PickerOverlay")
		local idx = Util.indexOf(Vocab.STATUS, "CUT")
		local cur = App.top().sel
		Sim.crank((idx - cur) * 30, 3)
		Sim.tap("A")
		H.eq(shot.status, "CUT", "cut via status picker " .. code)
		M.cut = M.cut + 1
		Sim.hold("B", 600) -- NEXT
	else
		local n = takesFor(shot)
		for i = 1, n do
			logTake(randomRating(i, n))
			minutes(math.random(1, 3))
			-- crash drill once mid-morning: power pulled between takes
			if not crashed and M.takes == 23 then
				crashed = true
				local before = M.takes
				local count = 0
				for _, e in ipairs(Model.flat()) do count = count + #e.shot.takes end
				H.relaunch()
				local after = 0
				for _, e in ipairs(Model.flat()) do after = after + #e.shot.takes end
				H.eq(after, count, "no takes lost across crash")
				M.replayed = Store.loadInfo.replayed
				H.eq(H.topName(), "LiveScreen", "relaunch resumes in LIVE")
				H.eq(cursor(), Model.get(shot.id), "relaunch resumes on the same shot")
				shot = cursor()
			end
		end
		-- circle the best take (hold A circles the last one when it was the keeper)
		local last = Model.lastTake(shot)
		if last.rating == "GREAT" then
			Sim.hold("A", 600)
			M.circles = M.circles + 1
		end
		-- continuity note on selected shots: B details, hold A on continuity row
		local tag = noteShots[code]
		if tag then
			local p = Sim.presses
			Sim.tap("B")
			H.row("addnote") -- DETAILS: "+ CONTINUITY NOTE" -> tag picker
			local i = Util.indexOf(Vocab.CONT_TAG, tag)
			Sim.crank((i - 1) * 30, 3)
			Sim.tap("A")
			Sim.type(tag .. " MATCH FOR " .. code)
			H.eq(H.topName(), "LiveScreen", "note returns straight to LIVE")
			M.notes = M.notes + 1
			M.notePresses = M.notePresses + pressesSince(p) + 1 -- +1 for keyboard confirm
			H.check(#Model.flaggedNotes(ctx.scene) > 0, "note flagged")
		end
		-- ~10% of shots need a pickup (e.g. focus on the only great take)
		if math.random() < 0.1 and shot.priority > 1 then
			Sim.menu("GO", "PICKUP")
			H.eq(shot.status, "PICKUP", "pickup via system menu")
			M.pickups = M.pickups + 1
			Sim.hold("B", 600)
		else
			local p = Sim.presses
			Sim.tap("RIGHT") -- GOT IT (+ auto NEXT)
			M.gotIts = M.gotIts + 1
			M.gotItPresses = M.gotItPresses + pressesSince(p)
			H.eq(shot.status, "GOT IT", "got it " .. code)
			if cursor() ~= shot then M.autoNextHits = M.autoNextHits + 1 end
		end
	end
	M.shotsDone = M.shotsDone + 1
	M.maxPressesPerShot = math.max(M.maxPressesPerShot, pressesSince(shotStart))
	-- estimate snapshot every 10 shots: predicted wrap vs. later truth
	if M.shotsDone % 10 == 0 then
		local est = Model.estimate(project(), nil, Util.now())
		if os.getenv("ESTDEBUG") then print("EST", Util.fmtClock(Util.now()), est.pace, est.median, est.change, est.samples, est.minutes) end
		M.estimates[#M.estimates + 1] = { at = Util.now(), wrapAt = est.wrapAt, method = est.method, pace = est.pace,
			left = Model.progress(project()).remain + Model.progress(project()).pickups }
		H.shoot(string.format("sim-%02d-live", M.shotsDone // 10))
	end
	-- NEXT from other screens, a few times during the day
	if M.shotsDone == 7 then
		Sim.tap("UP"); checkNext("HUB")
		H.hub("SHOT LIST"); Sim.tap("B"); checkNext("BROWSER (SCENES)")
		H.hub("NEW SHOT"); Sim.tap("DOWN"); checkNext("SHOT BUILDER")
		Sim.tap("DOWN"); checkNext("SLATE")
		Sim.tap("B"); Sim.tap("LEFT"); checkNext("STATUS PICKER")
		Sim.tap("A"); checkNext("RATE OVERLAY")
		Model.get(Model.lastTake(Model.flat()[1].shot).id) -- no-op
		H.hub("PROGRESS"); checkNext("PROGRESS")
		H.hub("REPORT"); checkNext("WRAP REPORT")
		H.hub("SETTINGS"); checkNext("SETTINGS FORM")
		H.hub("GEAR"); Sim.tap("A"); checkNext("GEAR PACKAGE FORM")
		Sim.tap("B"); H.row("editsetup"); Sim.tap("A"); checkNext("ENUM PICKER")
		-- system menu route: menu button + select = 2
		local p = Sim.presses
		Sim.menu("NEXT SHOT")
		M.nextChecks[#M.nextChecks + 1] = { where = "SYSTEM MENU", presses = pressesSince(p), ok = H.topName() == "LiveScreen" }
	end
end

-- The RATE overlay NEXT check logged an extra (unrated) take; count it.
M.takes = 0
for _, e in ipairs(Model.flat()) do M.takes = M.takes + #e.shot.takes end

-- Wrap
local wrapTime = Util.now()
local p = Sim.presses
H.hub("REPORT")
H.shoot("sim-90-report")
Sim.tap("A")
M.wrapPresses = pressesSince(p)
H.eq(#project().reports, 1, "wrap report stored")
local rep = project().reports[1]
H.eq(rep.data.progress.total + rep.data.progress.cut, 60, "report covers all 60 shots")
local files = playdate.file.listFiles("export")
H.check(#files >= 4, "export files written (" .. #files .. ")")
Sim.wait(3)
Model.db = nil
H.relaunch()
H.eq(#Model.project().reports, 1, "report survives relaunch")

-- estimate accuracy: compare each prediction with the actual wrap
local estErr = {}
for _, e in ipairs(M.estimates) do
	if e.wrapAt then estErr[#estErr + 1] = { at = Util.fmtClock(e.at), predicted = Util.fmtClock(e.wrapAt),
		err = math.floor((e.wrapAt - wrapTime) / 60), method = e.method, left = e.left } end
end

-------------------------------------------------------------------------------
-- Report
-------------------------------------------------------------------------------
local pr = Model.progress(Model.project())
local out = {}
local function w(s) out[#out + 1] = s end
w("SIMULATED DAY: FIRST LIGHT :30 (60 shots, 8 scenes, 20 setups)")
w(string.format("wrap at %s, %d shots GOT IT, %d pickups, %d cut, %d takes", Util.fmtClock(wrapTime), pr.done, pr.pickups, pr.cut, pr.takes))
w(string.format("total interactions: %d  (%.1f per shot)", Sim.presses, Sim.presses / 60))
w(string.format("log take: %.2f presses, rate: %.2f presses (tech issue incl. pick: %.2f)",
	M.takePresses / math.max(1, M.takes), M.ratePresses / math.max(1, M.takes - M.techIssues),
	M.techPresses / math.max(1, M.techIssues)))
w(string.format("GOT IT: %.2f presses; auto-NEXT moved the cursor %d/%d times", M.gotItPresses / math.max(1, M.gotIts), M.autoNextHits, M.gotIts))
w(string.format("continuity note (tag + typed text): %.1f presses", M.notePresses / math.max(1, M.notes)))
w(string.format("RUSH (losing the light) from LIVE: %d interactions", M.rushPresses or -1))
w(string.format("wrap report save+export: %d presses", M.wrapPresses))
w(string.format("max interactions spent on one shot: %d", M.maxPressesPerShot))
w(string.format("crash drill: %d journal ops replayed, takes intact", M.replayed or -1))
w(string.format("setup visits (relights incl. returns): %d for 20 setups", M.setupVisits))
w("NEXT reachability:")
for _, c in ipairs(M.nextChecks) do w(string.format("  %-20s %d  %s", c.where, c.presses, c.ok and "ok" or "FAIL")) end
w("remaining-time estimate vs actual wrap:")
for _, e in ipairs(estErr) do w(string.format("  at %s predicted %s (%+d min, %s, %d left)", e.at, e.predicted, e.err, e.method, e.left)) end
w("press mix:")
local keys = {}
for k in pairs(Sim.pressLog) do keys[#keys + 1] = k end
table.sort(keys)
for _, k in ipairs(keys) do w(string.format("  %-10s %d", k, Sim.pressLog[k])) end
print(table.concat(out, "\n"))
H.done("sim_commercial")
