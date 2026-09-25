-- Boots the full app headlessly. Returns H (harness) with helpers.
local H = dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]+$") or ".") .. "/harness.lua")

function H.boot(tag, keepData)
	if not keepData then H.freshData(tag) end
	Sim.epoch = Sim.epoch ~= 0 and Sim.epoch or H.START_EPOCH
	Sim.menuItems = {}
	dofile(SOURCE_DIR .. "/main.lua")
	Sim.step(2)
end

-- Re-run boot on an existing data dir (simulates relaunch after crash).
function H.relaunch()
	Model.db = nil
	App.stack = {}
	App.toastMsg = nil
	Sim.menuItems = {}
	playdate.update = nil
	local ok, err = pcall(dofile, SOURCE_DIR .. "/main.lua")
	assert(ok, err)
	Sim.step(2)
end

function H.top() return App.top() end
function H.topName()
	local t = App.top()
	for _, n in ipairs({ "LiveScreen", "RateOverlay", "DetailsScreen", "SlateScreen", "HubScreen", "BrowserScreen",
		"BuilderScreen", "ProgressScreen", "ContinuityScreen", "GearScreen", "ReportScreen", "PickerOverlay",
		"ConfirmOverlay", "IssuePicker", "WelcomeScreen", "FormScreen", "MultiPickerOverlay",
		"PresetListScreen" }) do
		if getmetatable(t) == _G[n] then return n end
	end
	return "?"
end

H.shots = 0
H.frameDir = nil
function H.shoot(name)
	if H.frameDir == nil then return end
	App.draw()
	Sim.dumpFrame(H.frameDir .. "/" .. name .. ".json")
	H.shots = H.shots + 1
end

-- From LIVE: UP opens the hub; move to the item whose label starts with `label`; A.
-- Returns the number of presses used (for friction accounting).
function H.hub(label)
	App.home()
	local presses = 1
	Sim.tap("UP")
	assert(H.topName() == "HubScreen", "hub did not open: " .. H.topName())
	local items = App.top():items()
	local idx
	for i, it in ipairs(items) do if it[1]:sub(1, #label) == label then idx = i end end
	assert(idx, "no hub item " .. label)
	-- shortest path on the 2-column grid: LEFT/RIGHT jump a column of 7
	local cur = App.top().sel
	if math.abs(idx - cur) >= 4 and math.abs(idx - cur - (idx > cur and 7 or -7)) < math.abs(idx - cur) then
		local s = cur + (idx > cur and 7 or -7)
		if s >= 1 and s <= #items then Sim.tap(idx > cur and "RIGHT" or "LEFT"); presses = presses + 1 end
		cur = App.top().sel
	end
	while cur ~= idx do
		Sim.tap(idx > cur and "DOWN" or "UP")
		presses = presses + 1
		cur = App.top().sel
	end
	Sim.tap("A")
	return presses + 1
end

-- Select the row whose key or label matches in a ListScreen, then A.
function H.row(match)
	local t = App.top()
	for i, r in ipairs(t.rows) do
		if r.key == match or (r.label and r.label:sub(1, #match) == match) then
			-- walk there with the d-pad so presses are counted honestly
			local guard = 0
			while t.sel ~= i and guard < 100 do
				Sim.tap(i > t.sel and "DOWN" or "UP"); guard = guard + 1
			end
			Sim.tap("A")
			return true
		end
	end
	error("no row " .. match .. " in " .. H.topName())
end

return H
