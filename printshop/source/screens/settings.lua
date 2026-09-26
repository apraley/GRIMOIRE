-- SETTINGS: printers and providers, demo simulation, display, data.

SettingsScreen = {}
SettingsScreen.__index = SettingsScreen

SettingsScreen.SPEEDS = { 1, 10, 60, 300, 1200 }

function SettingsScreen.new()
	local s = setmetatable({}, SettingsScreen)
	s:buildForm()
	return s
end

function SettingsScreen:buildForm()
	local set = Store.data.settings
	local function printer() return Store.activePrinter() end
	local fields = {
		{ label = "PRINTER", kind = "enum",
			options = function() return U.map(Store.data.printers, function(p) return p.id end) end,
			optionLabel = function(id) local p = Store.printer(id) return p and p.name or id end,
			get = function() return set.activePrinterId end,
			set = function(v)
				Printing.switchPrinter(v)
				Toast.show("ACTIVE: " .. Store.activePrinter().name, "check")
			end },
		{ label = "CONNECTION", kind = "enum", options = Enums.PROVIDERS,
			optionLabel = function(v) return Enums.PROVIDER_LABEL[v] end,
			get = function() return printer().provider end,
			set = function(v)
				printer().provider = v
				Store.markDirty()
				Printing.reload()
				Toast.show("CONNECTED VIA " .. Enums.PROVIDER_LABEL[v], "check")
			end,
			hint = "DEMO SIM works offline. BRIDGE needs the companion app." },
		{ label = "BRIDGE HOST", kind = "text", maxLen = 40, get = function() return printer().host end,
			set = function(v) printer().host = v Store.markDirty() Printing.reload() end,
			hidden = function() return printer().provider == "demo" end,
			hint = "IP of the computer running bridge/printshop_bridge.py" },
		{ label = "BRIDGE PORT", kind = "number", min = 1, max = 65535, step = 1,
			get = function() return printer().port end,
			set = function(v) printer().port = v Store.markDirty() Printing.reload() end,
			hidden = function() return printer().provider == "demo" end },
		{ label = "PRINTER NAME", kind = "text", maxLen = 14, get = function() return printer().name end,
			set = function(v) if v ~= "" then printer().name = U.upper(v) Store.markDirty() end end },
		{ label = "PRINTER MODEL", kind = "text", maxLen = 24, get = function() return printer().model end,
			set = function(v) if v ~= "" then printer().model = U.upper(v) Store.markDirty() end end },
		{ label = "ADD PRINTER", kind = "action", run = function()
			TextEntry.open("NEW PRINTER NAME", "", function(name)
				if name == "" then return end
				local p = Printer.new({ id = Store.newId("p"), name = U.upper(name), model = U.upper(name), provider = "demo" })
				Store.data.printers[#Store.data.printers + 1] = p
				-- Copy the default maintenance plan onto the new machine.
				for _, t in ipairs(Store.data.maintenance.tasks) do
					if t.printerId == Store.data.printers[1].id then
						MaintService.add({ kind = t.kind, name = t.name, printerId = p.id,
							intervalHours = t.intervalHours, intervalDays = t.intervalDays, notes = t.notes })
					end
				end
				Store.markDirty()
				Toast.show("ADDED " .. p.name, "check")
				self.form:refresh()
			end, 14)
		end },
		{ label = "DEMO SPEED", kind = "enum", options = SettingsScreen.SPEEDS,
			optionLabel = function(v) return v .. "X" end,
			get = function() return set.demoSpeed end, set = function(v) set.demoSpeed = v Store.markDirty() App.syncMenu() end,
			hint = "How fast simulated prints run." },
		{ label = "DEMO MISHAPS", kind = "bool", get = function() return set.demoChaos end,
			set = function(v) set.demoChaos = v Store.markDirty() end,
			hint = "Damp spools, dirty beds and overdue chores can fail demo prints." },
		{ label = "AUTO FILAMENT", kind = "bool", get = function() return set.autoConsume end,
			set = function(v) set.autoConsume = v Store.markDirty() end,
			hint = "Finished and failed prints deduct grams from their spool." },
		{ label = "LOW SPOOL AT", kind = "number", min = 0, max = 1000, step = 10, unit = "g",
			get = function() return set.lowSpoolGrams end, set = function(v) set.lowSpoolGrams = v Store.markDirty() end },
		{ label = "THEME", kind = "enum", options = { "night", "day" }, optionLabel = function(v) return U.upper(v) end,
			get = function() return set.theme end,
			set = function(v) set.theme = v Draw.setTheme(v) Store.markDirty() end },
		{ label = "TEXT SPEED", kind = "enum", options = { 1, 2, 3 },
			optionLabel = function(v) return ({ "SLOW", "NORMAL", "FAST" })[v] end,
			get = function() return set.typeSpeed end, set = function(v) set.typeSpeed = v Store.markDirty() end },
		{ label = "SOUND", kind = "bool", get = function() return set.sound end,
			set = function(v) set.sound = v Store.markDirty() end },
		{ label = "SAVE NOW", kind = "action", run = function()
			App.saveAll()
			if Store.readOnly then
				Toast.show("READ-ONLY: SAVE IS FROM A NEWER VERSION", "warn")
			else
				Toast.show("SAVED (" .. Store.data.meta.saves .. " SAVES)", "check")
			end
		end },
		{ label = "RESET TO DEMO SHOP", kind = "action", run = function()
			Confirm("ERASE ALL DATA + LOAD DEMO?", function() App.resetData(false) end, nil, "ERASE", "CANCEL")
		end },
		{ label = "RESET TO EMPTY SHOP", kind = "action", run = function()
			Confirm("ERASE EVERYTHING?", function() App.resetData(true) end, nil, "ERASE", "CANCEL")
		end },
		{ label = "ABOUT", kind = "action", run = function()
			local r = Store.loadReport or {}
			Dialog.open({
				"PRINT SHOP " .. App.VERSION .. ". Save schema v" .. Schema.CURRENT .. ", " .. Store.data.meta.saves .. " saves.",
				r.migratedFrom and ("Migrated your data from schema v" .. r.migratedFrom .. ". A backup was kept.") or "Your data is on the current schema.",
				"The Benchy Captain is rule-based: no network, no AI service. Everything works offline.",
			}, { speaker = "ABOUT" })
		end },
		{ label = "ASK THE CAPTAIN", kind = "action", run = function() Common.help("settings") end },
	}
	self.form = Form.new(fields, { rows = 14, x = 6, y = 22, w = 388, labelW = 130 })
end

function SettingsScreen:update()
	if self.form:update() then return end
	if Input.b() then
		Sfx.play("back")
		Screens.pop()
	end
end

function SettingsScreen:draw()
	local p = Printing.provider
	local st = p:getStatus()
	Common.page("SETTINGS", U.truncate(st.state .. " " .. (st.message or ""), 30), self.form:hint() .. "   B:BACK")
	Draw.window(2, 17, 396, 208)
	self.form:draw()
end
