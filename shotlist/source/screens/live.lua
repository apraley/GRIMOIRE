-- LIVE SHOOT: the home screen. Everything needed on set in one glance, and
-- every frequent action is one press:
--
--   A        TAKE +1 (then rate with the d-pad)     hold A  circle last take
--   B        shot details                            hold B  NEXT priority shot
--   RIGHT    GOT IT (+ jump to NEXT)                 LEFT    status picker
--   UP       menu (hub)                              DOWN    slate
--   CRANK    scrub shots; spin faster to jump by setup, faster still by scene

LiveScreen = Screen:extend()

local SCRUB_LEVELS = { "SHOT", "SETUP", "SCENE" }

function LiveScreen:init()
	self.acc = 0
	self.speed = 0
	self.level = 1
	self.slowFrames = 0
	self.scrubUntil = 0
	self.banner = nil
	self.settledScene = nil
	self.lastMoveMs = 0
	self.pendingFlagCheck = false
end

function LiveScreen:enter()
	local s = App.cursorShot()
	if s and self.settledScene == nil then self.settledScene = Model.ctx(s.id).scene end
end

function LiveScreen:shot() return App.cursorShot() end

function LiveScreen:showNext(c, idx, total)
	local mode = Model.db.settings.nextMode == "RUSH" and "RUSH " or ""
	self.banner = { text = mode .. "NEXT " .. idx .. "/" .. total .. ": " .. Model.nextReason(c), untilMs = Util.nowMs() + 4500 }
	self.pendingFlagCheck = true
	self.lastMoveMs = Util.nowMs() - 1000
	App.redraw()
end

---------------------------------------------------------------------------
-- actions
---------------------------------------------------------------------------
function LiveScreen:take()
	local shot = self:shot()
	if shot == nil then return end
	local t = App.addTake(shot)
	if t then
		App.push(RateOverlay:new(t.id, function() self:take() end))
	end
end

function LiveScreen:gotIt()
	local shot = self:shot()
	if shot == nil then return end
	if shot.status == "GOT IT" then
		App.toast(Model.code(shot) .. " ALREADY GOT IT", { icon = "check" })
		return
	end
	self.undoCursor = shot.id
	App.setStatus(shot, "GOT IT")
	if Model.db.settings.autoNext then
		local cands = Model.nextCandidates(shot.id)
		if #cands > 0 then
			App.setCursor(cands[1].shot)
			App.nextState = { at = Util.nowMs(), shotId = cands[1].shot.id, idx = 1, fromId = shot.id }
			self:showNext(cands[1], 1, #cands)
		end
	end
end

function LiveScreen:onUndo()
	if self.undoCursor and Model.get(self.undoCursor) then
		App.setCursor(Model.get(self.undoCursor))
		self.banner = nil
	end
	self.undoCursor = nil
end

function LiveScreen:circleLast()
	local shot = self:shot()
	local t = shot and Model.lastTake(shot)
	if t == nil then App.toast("NO TAKES YET"); return end
	App.commit(Model.opCircle(t, Util.now()))
	App.toast((t.circle and "CIRCLED T" or "UNCIRCLED T") .. t.n, { icon = "ring", undo = true })
end

function LiveScreen:statusPicker()
	local shot = self:shot()
	if shot == nil then return end
	local items = {}
	for _, s in ipairs(Vocab.STATUS) do items[#items + 1] = { label = s, value = s, icon = Vocab.STATUS_ICON[s] } end
	App.push(PickerOverlay:new("STATUS " .. Model.code(shot), items, shot.status, function(it)
		if it.value ~= shot.status then App.setStatus(shot, it.value) end
	end, { w = 200 }))
end

function LiveScreen:event(ev)
	local shot = self:shot()
	if shot == nil then
		if ev == "A" then App.push(BuilderScreen:new()) elseif ev == "UP" then App.push(HubScreen:new()) end
		return true
	end
	if ev == "A" then self:take()
	elseif ev == "AL" then self:circleLast()
	elseif ev == "B" then App.push(DetailsScreen:new(shot.id))
	elseif ev == "RIGHT" then self:gotIt()
	elseif ev == "LEFT" then self:statusPicker()
	elseif ev == "UP" then App.push(HubScreen:new())
	elseif ev == "DOWN" then App.push(SlateScreen:new())
	end
	return true
end

---------------------------------------------------------------------------
-- crank scrubbing with speed levels
---------------------------------------------------------------------------
function LiveScreen:crank(change, accel)
	local sp = math.abs(change)
	self.speed = self.speed * 0.55 + sp * 0.45
	local want = 1
	if self.speed > 26 then want = 3 elseif self.speed > 13 then want = 2 end
	if want > self.level then
		self.level = want
		self.acc = 0
	end
	self.slowFrames = 0
	local deg = ({ Input.degPerStep() + 4, 50, 70 })[self.level]
	self.acc = self.acc + change
	local steps = 0
	while self.acc >= deg do self.acc = self.acc - deg; steps = steps + 1 end
	while self.acc <= -deg do self.acc = self.acc + deg; steps = steps - 1 end
	if steps ~= 0 then
		local cur = self:shot()
		if cur then
			local nxt = Model.step(cur.id, steps, ({ "shot", "setup", "scene" })[self.level])
			if nxt and nxt ~= cur then
				App.setCursor(nxt)
				self.lastMoveMs = Util.nowMs()
				self.pendingFlagCheck = true
				self.banner = nil
				self.flags = nil
			end
		end
	end
	self.scrubUntil = Util.nowMs() + 900
	App.redraw()
end

function LiveScreen:update()
	if Input.crankChange == 0 then
		self.slowFrames = self.slowFrames + 1
		self.speed = self.speed * 0.6
		if self.slowFrames > 8 and self.level > 1 then self.level = 1; self.acc = 0 end
	end
	if self.banner and Util.nowMs() > self.banner.untilMs then self.banner = nil; App.redraw() end
	if self.flags and Util.nowMs() > self.flags.untilMs then self.flags = nil; App.redraw() end
	if self.scrubUntil > 0 and Util.nowMs() > self.scrubUntil then self.scrubUntil = 0; App.redraw() end
	-- when the cursor settles in a different scene, surface flagged continuity
	if self.pendingFlagCheck and Util.nowMs() - self.lastMoveMs > 600 and App.top() == self then
		self.pendingFlagCheck = false
		local shot = self:shot()
		local scene = shot and Model.ctx(shot.id).scene
		if scene and scene ~= self.settledScene then
			self.settledScene = scene
			local notes = Model.flaggedNotes(scene)
			-- non-modal on purpose: a modal card would swallow the next A press
			-- and a take the operator believes was logged would be lost
			if #notes > 0 then self.flags = { scene = scene, notes = notes, untilMs = Util.nowMs() + 9000 } end
		end
	end
	self.animating = Input.isDown("A") or Input.isDown("B")
end

---------------------------------------------------------------------------
-- drawing
---------------------------------------------------------------------------
local function drawHeader(ctx, project)
	Gfx.fill(0, 0, Gfx.W, 22)
	local s = Model.db.settings
	Gfx.pix(Util.fmtClock(nil, s.clock24), 6, 4, 2, { white = true })
	local x = 80
	if ctx.scene then
		x = x + Gfx.pix("SC " .. ctx.scene.number, x, 4, 2, { white = true }) + 14
		x = x + Gfx.pix("SETUP " .. ctx.setup.letter, x, 4, 2, { white = true }) + 10
	end
	local pr = Model.progress(project, ctx.day)
	local right = Gfx.W - 6
	local ptxt = pr.done .. "/" .. pr.total
	Gfx.pix(ptxt, right, 8, 1, { white = true, align = "right" })
	right = right - Pixfont.width(ptxt, 1) - 8
	if ctx.scene and #Model.flaggedNotes(ctx.scene) > 0 then
		Gfx.icon("flag", right - 8, 7, { white = true })
		right = right - 14
	end
	if ctx.day and x < right - 40 then
		Gfx.pix(ctx.day.label, right, 8, 1, { white = true, align = "right" })
	end
end

local function drawTakes(shot, x, y, w, h)
	Gfx.window(x, y, w, h)
	Gfx.pix("TAKES", x + 12, y + 10, 1)
	Gfx.pix(tostring(#shot.takes), x + 12, y + 22, 5)
	local best = Model.bestTake(shot)
	Gfx.pix("BEST", x + 70, y + 10, 1)
	if best then
		local bw = Gfx.pix(tostring(best.n), x + 70, y + 22, 5)
		if best.circle then Gfx.icon("ring", x + 74 + bw, y + 22) end
		Gfx.ratingIcon(best.rating, x + 74 + bw, y + 40)
	else
		Gfx.pix("-", x + 70, y + 22, 4)
	end
	-- last takes, newest first
	local ty = y + 64
	Gfx.hline(x + 8, ty - 4, w - 16)
	local list = {}
	for _, t in ipairs(shot.takes) do list[#list + 1] = t end
	table.sort(list, function(a, b) return a.n > b.n end)
	local maxRows = math.floor((h - 72) / 17)
	for i = 1, math.min(#list, maxRows) do
		local t = list[i]
		local ry = ty + (i - 1) * 17
		Gfx.pix("T" .. t.n, x + 12, ry + 4, 1)
		if t.circle then Gfx.icon("ring", x + 34, ry + 3) end
		Gfx.ratingIcon(t.rating, x + 46, ry + 3)
		local tag = (t.tech ~= "" and t.tech) or (t.perf ~= "" and t.perf) or (t.rating ~= "" and t.rating) or "UNRATED"
		Gfx.pix(Pixfont.fit(tag, w - 70, 1), x + 58, ry + 4, 1)
	end
	if #list == 0 then Gfx.pix("A = LOG TAKE", x + 12, ty + 4, 1) end
end

local function drawScrub(self, cur, x, y, w, h)
	Gfx.window(x, y, w, h)
	local label = SCRUB_LEVELS[self.level]
	Gfx.fill(x + 8, y + 8, w - 16, 16)
	Gfx.pix("BY " .. label, x + w // 2, y + 13, 1, { white = true, align = "center" })
	local list = Model.flat()
	local i = Model.flatIndex(cur.id) or 1
	local rowH = 22
	local mid = y + 30 + 3 * rowH
	for d = -3, 3 do
		local e = list[i + d]
		if e then
			local ry = mid + d * rowH - rowH // 2
			local sel = d == 0
			if sel then Gfx.selbar(x + 8, ry, w - 16, rowH) end
			Gfx.statusIcon(e.shot.status, x + 12, ry + 7, sel)
			Gfx.pix(Model.code(e.shot), x + 24, ry + 5, 2, { white = sel })
		end
	end
end

-- Flagged continuity for the scene just entered (auto-hides; B > CONTINUITY for all).
function LiveScreen:drawFlags(x, y, w, h)
	Gfx.window(x, y, w, h, "CONTINUITY SC " .. self.flags.scene.number)
	local ry = y + 14
	for _, note in ipairs(self.flags.notes) do
		if ry > y + h - 40 then
			Gfx.pix("+ MORE: B > CONTINUITY", x + 12, y + h - 16, 1)
			break
		end
		Gfx.icon("flag", x + 12, ry + 2)
		Gfx.pix(note.tag, x + 24, ry + 3, 1)
		local s = Model.get(note.shot or "")
		if s then Gfx.pix(Model.code(s), x + w - 12, ry + 3, 1, { align = "right" }) end
		local lines = Gfx.wrap(note.text ~= "" and note.text or "-", w - 24, 3, true)
		for j, l in ipairs(lines) do Gfx.text(l, x + 12, ry + 12 + (j - 1) * 14, { bold = true }) end
		ry = ry + 16 + #lines * 14
	end
end

function LiveScreen:draw()
	local project = Model.project()
	local shot = self:shot()
	if project == nil or shot == nil then
		Gfx.fill(0, 0, Gfx.W, 22)
		Gfx.pix("SHOT LIST", 8, 4, 2, { white = true })
		Gfx.window(40, 60, 320, 100, "NO SHOTS")
		Gfx.text("THIS PROJECT HAS NO SHOTS YET.", 200, 84, { align = "center", bold = true })
		Gfx.text("A: OPEN SHOT BUILDER", 200, 108, { align = "center" })
		Gfx.text("UP: MENU", 200, 128, { align = "center" })
		Gfx.hints({ { "A", "BUILDER" }, { "up", "MENU" } })
		return
	end
	local ctx = Model.ctx(shot.id)
	drawHeader(ctx, project)

	local lx = 10
	local y = 28
	-- status + priority pills
	local pw = Gfx.statusPill(shot.status, lx, y)
	local pri = "PRI " .. (Vocab.PRIORITY_LABEL[shot.priority] or "?")
	local ppx = lx + pw + 6
	if shot.priority == 1 then
		playdate.graphics.fillRoundRect(ppx, y, Pixfont.width(pri, 1) + 10, 13, 3)
		Gfx.pix(pri, ppx + 5, y + 3, 1, { white = true })
	else
		playdate.graphics.drawRoundRect(ppx, y, Pixfont.width(pri, 1) + 10, 13, 3)
		Gfx.pix(pri, ppx + 5, y + 3, 1)
	end
	local est = tonumber(shot.est) or 0
	if est > 0 then Gfx.pix(est .. " MIN", ppx + Pixfont.width(pri, 1) + 18, y + 3, 1) end

	-- shot code, big
	y = 48
	Gfx.cursor(lx, y + 13)
	local code = Model.code(shot)
	local sc = Pixfont.fitScale(code, 250, 5, 3)
	Gfx.pix(code, lx + 10, y, sc)

	-- description (pixel font, up to two lines; system font if longer)
	y = 90
	local desc = Util.upper(Gfx.safe(Model.describe(shot)))
	local maxW = 256
	local lines = {}
	local cur = ""
	for word in desc:gmatch("%S+") do
		local try = cur == "" and word or (cur .. " " .. word)
		if Pixfont.width(try, 2) <= maxW then cur = try else lines[#lines + 1] = cur; cur = word end
	end
	if cur ~= "" then lines[#lines + 1] = cur end
	if #lines <= 2 then
		for i, l in ipairs(lines) do Gfx.pix(l, lx, y + (i - 1) * 18, 2) end
	else
		for i, l in ipairs(Gfx.wrap(desc, maxW, 2, true)) do Gfx.text(l, lx, y + (i - 1) * 17, { bold = true }) end
	end

	-- lens + movement
	y = 130
	local lens = Vocab.fmtLens(Model.lensOf(shot))
	local lw = 0
	if lens ~= "" then lw = Gfx.pix(lens, lx, y, 2) + 14 end
	Gfx.pix(shot.move, lx + lw, y, 2)
	Gfx.pix(shot.size, lx + 256, y, 2, { align = "right" })

	-- secondary info (system font)
	y = 150
	local su = ctx.setup
	local info1 = {}
	if shot.subject ~= "" then info1[#info1 + 1] = shot.subject end
	if su.camera ~= "" then info1[#info1 + 1] = su.camera end
	if su.support ~= "" then info1[#info1 + 1] = su.support end
	Gfx.text(table.concat(info1, "  /  "), lx, y, { maxW = 258 })
	local info2 = { su.fps, su.res, "ISO " .. su.iso, su.wb, Vocab.fmtShutter(su.shutter) }
	if su.nd ~= "" then info2[#info2 + 1] = su.nd end
	Gfx.text(table.concat(info2, " "), lx, y + 18, { maxW = 258 })
	if shot.notes ~= "" then
		Gfx.text("NOTE: " .. shot.notes, lx, y + 36, { maxW = 258, bold = true })
	elseif su.lighting ~= "" then
		Gfx.text(su.lighting, lx, y + 36, { maxW = 258 })
	end

	-- right panel: takes, or the scrub strip while cranking
	if self.scrubUntil > 0 then drawScrub(self, shot, 272, 26, 124, 178)
	elseif self.flags and self.flags.scene == ctx.scene then self:drawFlags(270, 26, 126, 188)
	else drawTakes(shot, 272, 26, 124, 178) end

	-- NEXT banner
	if self.banner then
		Gfx.fill(0, 22, Gfx.W, 16)
		Gfx.icon("right", 6, 26, { white = true })
		Gfx.pix(self.banner.text, 18, 27, 1, { white = true })
	end

	-- two-row hint footer
	Gfx.fill(0, Gfx.H - 26, Gfx.W, 26)
	local function hint(key, label, x, yy)
		if key == "A" or key == "B" then
			Gfx.btn(key, x, yy - 3, true); x = x + 15
		elseif key == "!A" or key == "!B" then
			Gfx.pix("HOLD", x, yy, 1, { white = true }); x = x + 22
			Gfx.btn(key:sub(2), x, yy - 3, true); x = x + 15
		else
			Gfx.icon(key, x, yy - 1, { white = true }); x = x + 11
		end
		return x + Gfx.pix(label, x, yy, 1, { white = true }) + 10
	end
	local hx = 6
	local r1 = Gfx.H - 22
	hx = hint("crank", "SHOT", hx, r1)
	hx = hint("A", "TAKE", hx, r1)
	hx = hint("B", "DETAILS", hx, r1)
	hint("!B", "NEXT", hx, r1)
	hx = 6
	local r2 = Gfx.H - 10
	hx = hint("right", "GOT IT", hx, r2)
	hx = hint("left", "STATUS", hx, r2)
	hx = hint("up", "MENU", hx, r2)
	hx = hint("down", "SLATE", hx, r2)
	hint("!A", "CIRCLE", hx, r2)
end

return LiveScreen
