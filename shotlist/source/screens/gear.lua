-- GEAR: named camera packages and preset lists (cameras, lenses, filters,
-- support, audio, lighting). Presets feed every picker in the app.

GearScreen = ListScreen:extend()

function GearScreen:init()
	ListScreen.init(self, "GEAR")
	self.hints = { { "crank", "MOVE" }, { "A", "OPEN" }, { "B", "BACK" } }
end

function GearScreen:build()
	local gear = Model.db.gear
	local rows = { { section = true, skip = true, label = "CAMERA PACKAGES", h = 14 } }
	for _, pkg in ipairs(gear.packages) do
		local parts = { pkg.camera }
		for _, l in ipairs(pkg.lenses or {}) do parts[#parts + 1] = l end
		for _, l in ipairs(pkg.filters or {}) do parts[#parts + 1] = l end
		rows[#rows + 1] = { key = pkg.id, label = pkg.name, bold = true, icon = "cam", value = table.concat(parts, " / "),
			valueW = 260, onA = function() App.push(PackageForm(pkg)) end }
	end
	rows[#rows + 1] = { key = "addpkg", label = "+ NEW PACKAGE", icon = "right", onA = function()
		local letters = { "A", "B", "C", "D", "E", "F" }
		local pkg = Schema.new("pkg", { name = (letters[#gear.packages + 1] or "X") .. " CAM" })
		App.commit(Model.opAdd(gear, "packages", pkg, nil, "NEW PACKAGE"))
		App.push(PackageForm(Model.get(pkg.id)))
	end }
	rows[#rows + 1] = { section = true, skip = true, label = "PRESET LISTS", h = 14 }
	for _, name in ipairs(Vocab.GEAR_LISTS) do
		rows[#rows + 1] = { key = name, label = Vocab.GEAR_LABEL[name], icon = "right", value = #(gear.lists[name] or {}) .. " ITEMS",
			onA = function() App.push(PresetListScreen:new(name)) end }
	end
	self.rows = rows
end

function PackageForm(pkg)
	local L = Model.db.gear.lists
	local spec = {
		{ f = "name", label = "NAME", t = "text" },
		{ f = "camera", label = "CAMERA", t = "enum", opts = function() return L.cameras end, custom = true },
		{ f = "lenses", label = "LENSES", t = "multi", opts = function() return L.lenses end },
		{ f = "filters", label = "FILTERS", t = "multi", opts = function() return L.filters end },
		{ f = "support", label = "SUPPORT", t = "enum", opts = function() return Util.concat({ "" }, L.support) end, custom = true },
		{ f = "audio", label = "AUDIO", t = "enum", opts = function() return Util.concat({ "" }, L.audio) end, custom = true },
		{ f = "lighting", label = "LIGHTING", t = "enum", opts = function() return Util.concat({ "" }, L.lighting) end, custom = true },
		{ t = "action", label = "DELETE PACKAGE", icon = "x", run = function()
			App.commit(Model.opDel(pkg, "DELETE " .. pkg.name))
			App.pop()
			App.toast("DELETED " .. pkg.name, { undo = true })
		end },
	}
	return FormScreen:new("PACKAGE", pkg, spec)
end

---------------------------------------------------------------------------
-- A single preset list. Lists are replaced whole (never mutated in place)
-- so undo and journal replay stay exact.
---------------------------------------------------------------------------
PresetListScreen = ListScreen:extend()

function PresetListScreen:init(name)
	ListScreen.init(self, Vocab.GEAR_LABEL[name])
	self.name = name
	self.hints = { { "A", "EDIT" }, { "left", "UP" }, { "right", "DOWN" }, { "B", "BACK" } }
end

function PresetListScreen:setList(list, label)
	local lists = Util.deepcopy(Model.db.gear.lists)
	lists[self.name] = list
	App.commit(Model.opSet(Model.db.gear, "lists", lists, label))
	self:build()
end

function PresetListScreen:build()
	local list = Model.db.gear.lists[self.name] or {}
	local rows = {}
	rows[#rows + 1] = { key = "add", label = "+ ADD", icon = "right", onA = function()
		App.keyboard("ADD " .. self.title, "", function(t)
			if t ~= "" then
				local l = Util.copy(list); l[#l + 1] = Util.upper(t)
				self:setList(l, "ADD " .. Util.upper(t))
			end
		end)
	end }
	for i, v in ipairs(list) do
		local function swap(d)
			local j = i + d
			if j < 1 or j > #list then return end
			local l = Util.copy(list)
			l[i], l[j] = l[j], l[i]
			self:setList(l, "REORDER")
			self.sel = self.sel + d
		end
		rows[#rows + 1] = { key = "i" .. i .. v, label = v,
			onLeft = function() swap(-1) end, onRight = function() swap(1) end,
			onA = function()
				App.push(PickerOverlay:new(v, { { label = "RENAME", value = "rename" }, { label = "DELETE", value = "delete", icon = "x" } },
					nil, function(it)
						if it.value == "delete" then
							local l = Util.copy(list); table.remove(l, i)
							self:setList(l, "DELETE " .. v)
						else
							App.keyboard("RENAME", v, function(t)
								if t ~= "" then local l = Util.copy(list); l[i] = Util.upper(t); self:setList(l, "RENAME " .. v) end
							end)
						end
					end, { w = 200 }))
			end }
	end
	self.rows = rows
end

return GearScreen
