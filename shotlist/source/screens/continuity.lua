-- CONTINUITY: tagged notes per scene. Flagged notes pop up automatically
-- when LIVE arrives in that scene. RIGHT toggles the flag; LEFT resolves.

ContinuityScreen = ListScreen:extend()

function ContinuityScreen:init(scene)
	ListScreen.init(self, "CONTINUITY")
	self.sceneId = scene and scene.id or nil
	self.hints = { { "A", "OPEN" }, { "right", "FLAG" }, { "left", "RESOLVE" }, { "B", "BACK" } }
end

-- Tag picker -> note linked to the shot/last take -> keyboard for the text.
function ContinuityScreen.quickAdd(scene, shot, after)
	local items = {}
	for _, t in ipairs(Vocab.CONT_TAG) do items[#items + 1] = { label = t, value = t } end
	App.push(PickerOverlay:new("NEW NOTE - SC " .. scene.number, items, nil, function(it)
		local last = shot and Model.lastTake(shot)
		local note = Schema.new("note", { tag = it.value, flag = true, shot = shot and shot.id or "",
			take = last and last.n or 0, t = Util.now() })
		App.commit(Model.opAdd(scene, "notes", note, 1, "NOTE " .. it.value))
		local rec = Model.get(note.id)
		App.keyboard(it.value .. " NOTE", "", function(text)
			if rec and Model.get(rec.id) then App.commit(Model.opSet(rec, "text", Util.upper(text), "NOTE TEXT")) end
			if after then after() end
		end)
		App.toast("FLAGGED " .. it.value .. " NOTE", { icon = "flag" })
	end, { w = 220 }))
end

function ContinuityScreen:scenes()
	local p = Model.project()
	local r = {}
	if p == nil then return r end
	local only = self.sceneId and Model.get(self.sceneId)
	for _, d in ipairs(p.days) do for _, sc in ipairs(d.scenes) do
		if only == nil or sc == only then r[#r + 1] = sc end
	end end
	return r
end

function ContinuityScreen:build()
	local rows = {}
	local only = self.sceneId and Model.get(self.sceneId)
	self.subtitle = only and ("SC " .. only.number .. " " .. only.desc) or "ALL SCENES"
	if only then
		rows[#rows + 1] = { key = "add", label = "+ ADD NOTE (TAG, THEN TEXT)", icon = "flag", onA = function()
			local cur = App.cursorShot()
			local shot = cur and Model.ctx(cur.id).scene == only and cur or nil
			ContinuityScreen.quickAdd(only, shot, function() self:build() end)
		end }
		rows[#rows + 1] = { key = "all", label = "SHOW ALL SCENES", icon = "right", onA = function()
			self.sceneId = nil; self:build() end }
	end
	for _, sc in ipairs(self:scenes()) do
		if only == nil and #sc.notes > 0 then
			rows[#rows + 1] = { section = true, skip = true, label = "SC " .. sc.number .. " " .. sc.desc, h = 14 }
		end
		for _, n in ipairs(sc.notes) do
			rows[#rows + 1] = { key = n.id, h = 20,
				draw = function(r, x, y, w, h, sel)
					if n.flag and not n.resolved then Gfx.icon("flag", x + 14, y + 6, { white = sel })
					elseif n.resolved then Gfx.icon("check", x + 14, y + 6, { white = sel }) end
					Gfx.pix(n.tag, x + 27, y + 7, 1, { white = sel })
					local ref = ""
					local shot = Model.get(n.shot or "")
					if shot then ref = Model.code(shot) .. (n.take and n.take > 0 and (" T" .. n.take) or "") end
					Gfx.text(n.text ~= "" and n.text or "(NO TEXT)", x + 90, y + 2, { white = sel, maxW = w - 170 })
					Gfx.pix(ref, x + w - 8, y + 7, 1, { white = sel, align = "right" })
				end,
				onA = function() App.push(NoteForm(n)) end,
				onRight = function()
					App.commit(Model.opSet(n, "flag", not n.flag, n.flag and "UNFLAG" or "FLAG"))
					self:build()
				end,
				onLeft = function()
					App.commit(Model.opSet(n, "resolved", not n.resolved, n.resolved and "REOPEN NOTE" or "RESOLVE NOTE"))
					self:build()
				end,
			}
		end
	end
	if #rows == 0 then rows[#rows + 1] = { skip = true, label = "NO CONTINUITY NOTES YET" } end
	self.rows = rows
end

function NoteForm(note)
	local spec = {
		{ f = "tag", label = "TAG", t = "enum", opts = Vocab.CONT_TAG },
		{ f = "text", label = "NOTE", t = "text" },
		{ f = "flag", label = "FLAG (SHOW ON RETURN)", t = "bool" },
		{ f = "resolved", label = "RESOLVED", t = "bool" },
		{ t = "info", label = "SHOT", value = function()
			local s = Model.get(note.shot or "")
			return s and (Model.code(s) .. (note.take > 0 and (" T" .. note.take) or "")) or "-"
		end },
		{ t = "action", label = "DELETE NOTE", icon = "x", run = function()
			App.commit(Model.opDel(note, "DELETE NOTE"))
			App.pop()
			App.toast("DELETED NOTE", { undo = true })
		end },
	}
	return FormScreen:new("NOTE " .. note.tag, note, spec)
end

return ContinuityScreen
