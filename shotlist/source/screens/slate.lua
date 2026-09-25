-- SLATE: full-screen digital slate, readable across a room.
--   A = log take (slate advances)   CRANK / LEFT / RIGHT = shot
--   UP = invert   DOWN = MOS / SYNC   B = back

SlateScreen = Screen:extend()
SlateScreen.hideToast = true

function SlateScreen:init()
	self.stepper = Stepper.new(40)
	self.flashUntil = 0
	self.mos = false
end

function SlateScreen:enter()
	local s = App.cursorShot()
	if s then
		local su = Model.ctx(s.id).setup
		self.mos = su.audio == "MOS"
	end
end

function SlateScreen:move(d)
	local cur = App.cursorShot()
	if cur == nil then return end
	local n = Model.step(cur.id, d, "shot")
	if n then App.setCursor(n) end
end

function SlateScreen:event(ev)
	if ev == "A" then
		local t = App.addTake()
		if t then
			-- no toast here: nothing may cover the slate while it faces camera
			self.flashUntil = Util.nowMs() + 250
			self.msg = "LOGGED T" .. t.n
			self.msgUntil = Util.nowMs() + 2500
			self.animating = true
		end
	elseif ev == "B" then App.pop()
	elseif ev == "LEFT" then self:move(-1)
	elseif ev == "RIGHT" then self:move(1)
	elseif ev == "UP" then
		local s = Model.db.settings
		App.commit(Model.opSet(s, "slateInvert", not s.slateInvert))
	elseif ev == "DOWN" then self.mos = not self.mos
	elseif ev == "AL" then
		local shot = App.cursorShot()
		local t = shot and Model.lastTake(shot)
		if t then
			App.commit(Model.opCircle(t, Util.now()))
			App.toast((t.circle and "CIRCLED T" or "UNCIRCLED T") .. t.n, { icon = "ring" })
		end
	end
	return true
end

function SlateScreen:crank(change, accel)
	local n = self.stepper:feed(change)
	if n ~= 0 then self:move(n) end
end

function SlateScreen:update()
	if self.msg and Util.nowMs() > self.msgUntil then self.msg = nil; App.redraw() end
	if self.animating and Util.nowMs() > self.flashUntil then
		self.animating = false
		App.redraw()
	end
end

function SlateScreen:draw()
	local shot = App.cursorShot()
	local inv = Model.db.settings.slateInvert
	local flash = Util.nowMs() < self.flashUntil
	if flash then inv = not inv end
	-- white = draw white on black (inverted slate)
	local white = inv
	Gfx.fill(0, 0, Gfx.W, Gfx.H, not inv)
	if shot == nil then
		Gfx.pix("NO SHOT", 200, 110, 4, { align = "center", white = white })
		return
	end
	local ctx = Model.ctx(shot.id)
	local project = ctx.project
	local function line(x, y, w, h)
		Gfx.fill(x, y, w, h, white)
	end
	-- frame
	line(0, 26, Gfx.W, 3)
	line(0, 128, Gfx.W, 3)
	line(150, 29, 3, 99)
	line(250, 131, 3, 109)
	-- top strip: production + date
	Gfx.pix(Pixfont.fit(project.title, 250, 2), 8, 7, 2, { white = white })
	Gfx.pix(self.msg or Util.fmtDate(Util.now()), Gfx.W - 8, 10, 1, { white = white, align = "right" })
	-- SCENE
	Gfx.pix("SCENE", 10, 34, 2, { white = white })
	local sn = tostring(ctx.scene.number)
	Gfx.pix(sn, 75, 56, Pixfont.fitScale(sn, 136, 9, 4), { white = white, align = "center" })
	-- SHOT (setup letter + shot number)
	Gfx.pix("SHOT", 162, 34, 2, { white = white })
	local sh = ctx.setup.letter .. "-" .. shot.num
	Gfx.pix(sh, 275, 56, Pixfont.fitScale(sh, 236, 9, 4), { white = white, align = "center" })
	-- TAKE (next take to be shot)
	Gfx.pix("TAKE", 10, 137, 2, { white = white })
	local tk = tostring(Model.maxTakeN(shot) + 1)
	Gfx.pix(tk, 125, 158, Pixfont.fitScale(tk, 230, 10, 5), { white = white, align = "center" })
	-- info block
	local ix, iy = 262, 138
	local function info(label, value)
		if value == nil or value == "" then return end
		Gfx.pix(label, ix, iy, 1, { white = white })
		Gfx.pix(Pixfont.fit(value, 128 - Pixfont.width(label, 1) - 6, 1), ix + Pixfont.width(label, 1) + 6, iy, 1, { white = white })
		iy = iy + 12
	end
	info("DIR", project.director)
	info("DP", project.dp)
	info("CAM", ctx.setup.camera)
	info("LENS", Vocab.fmtLens(Model.lensOf(shot)))
	info("FPS", ctx.setup.fps)
	info("ROLL", ctx.day and ctx.day.label or "")
	iy = math.max(iy, 212)
	-- MOS / SYNC badge
	local badge = self.mos and "MOS" or "SYNC"
	local bw = Pixfont.width(badge, 2) + 12
	Gfx.fill(ix, 218, bw, 18, white)
	Gfx.pix(badge, ix + 6, 220, 2, { white = not white })
	if shot.status == "GOT IT" then
		Gfx.icon("check", Gfx.W - 16, 222, { white = white })
	end
end

return SlateScreen
