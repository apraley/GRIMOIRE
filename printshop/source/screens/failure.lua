-- FAILURE LOG: record why a print failed.
--
-- Two entry points:
--   FailureScreen.new()            resolves Store.data.pendingFailure (a
--                                   failure reported by the printer)
--   FailureScreen.new({ job = j })  manual: mark a queue job failed
--
-- The cause, wasted grams (crank) and notes feed history, spool failure
-- counts, filament consumption and the Captain's advice.

local gfx <const> = playdate.graphics

FailureScreen = {}
FailureScreen.__index = FailureScreen

function FailureScreen.new(opts)
	opts = opts or {}
	local pf = Store.data.pendingFailure
	local job = opts.job or (pf and pf.jobId and Store.job(pf.jobId)) or nil
	local self = setmetatable({
		manual = opts.job ~= nil,
		job = job,
		pending = (opts.job == nil) and pf or nil,
		cause = (pf and opts.job == nil and pf.cause) or "unknown",
		notes = "",
		asCancel = false,
		list = ScrollList.new(#Enums.FAILURE_CAUSES, { crank = false }),
		gramTicker = CrankTicker.new(10),
	}, FailureScreen)
	local progress = self.pending and self.pending.progress or 0.5
	local est = job and job.estGrams or 0
	self.progress = progress
	self.grams = U.round(self.pending and self.pending.grams or est * progress, 0)
	self.maxGrams = math.max(1, est)
	for i, c in ipairs(Enums.FAILURE_CAUSES) do
		if c.id == self.cause then self.list.sel = i end
	end
	self.list:setCount(#Enums.FAILURE_CAUSES)
	self.cancelled = self.pending and self.pending.cancelled
	if self.cancelled then self.cause = "unknown" end
	return self
end

function FailureScreen:confirm()
	if self.pending then
		Printing.resolvePending({ cause = self.cause, notes = self.notes, grams = self.grams, asCancel = self.asCancel })
	elseif self.job then
		Printing.markFailed(self.job, self.cause, self.notes, self.grams, self.progress)
	end
	Sfx.play("fail")
	Screens.pop()
	-- The Captain weighs in right away.
	if Captain.hasNews() then Common.say(Captain.nextNews()) end
end

function FailureScreen:update()
	if self.job == nil then
		if Input.a() or Input.b() then
			-- Orphaned pending failure (job deleted): just clear it.
			Store.data.pendingFailure = nil
			Printing.acknowledge()
			Screens.pop()
		end
		return
	end
	if self.list:update() then
		self.cause = Enums.FAILURE_CAUSES[self.list.sel].id
	end
	local t = self.gramTicker:update()
	local h = Input.horizontal()
	if t ~= 0 or h ~= 0 then
		self.grams = U.clamp(self.grams + t + h, 0, self.maxGrams * 2)
		Sfx.play("tick")
	end
	if Input.a() then
		local items = {
			{ label = "LOG AS " .. (Enums.CAUSE_LABEL[self.cause] or "?"), action = function() self.asCancel = false self:confirm() end },
			{ label = "ADD NOTES", action = function()
				TextEntry.open("WHAT HAPPENED?", self.notes, function(txt) self.notes = txt end, 60)
			end },
		}
		if self.pending then
			items[#items + 1] = { label = "JUST CANCELLED (NO FAULT)", hint = "Counts filament, not a failure.",
				action = function() self.asCancel = true self:confirm() end }
		end
		items[#items + 1] = { label = "ASK THE CAPTAIN", action = function()
			local r = Enums.CAUSE_REMEDY[self.cause]
			local tips = {
				"Pick what ye saw. I'll count them up and suggest fixes later.",
			}
			if r and r.calib then tips[#tips + 1] = "For " .. string.lower(Enums.CAUSE_LABEL[self.cause]) .. ", the " .. Phrases.procedureNames[r.calib] .. " usually helps." end
			if r and r.maint then tips[#tips + 1] = "And check the " .. string.lower(Enums.MAINT_LABEL[r.maint] or r.maint) .. " log." end
			Dialog.open(tips, { speaker = "CAPTAIN", portrait = function(x, y) Sprites.captainPortrait(x, y, "worried", false) end })
		end }
		Menu.open({ title = "FAILURE", items = items })
	elseif Input.b() then
		if self.pending then
			Toast.show("FAILURE STILL NEEDS LOGGING", "warn")
		end
		Sfx.play("back")
		Screens.pop()
	end
end

function FailureScreen:draw()
	Common.page("FAILURE LOG", self.manual and "MANUAL" or "FROM PRINTER", "A:LOG  CRANK/" .. FontData.icon.left .. FontData.icon.right .. ":GRAMS  B:LATER", "diag")
	if self.job == nil then
		Common.empty(60, 60, 280, 100, "NO JOB FOUND", "The failed job was deleted. Press A to clear the error.")
		return
	end
	-- Left: what happened.
	Draw.window(6, 22, 188, 200, { title = "WHAT HAPPENED" })
	local x, y = 16, 32
	Text.draw(U.truncate(self.job.name, 28), x, y)
	y = y + 12
	if self.pending then
		Text.drawWrapped(self.pending.reason or "", x, y, 170, 2)
		y = y + 24
		Draw.row("LAYER", tostring(self.pending.layer or 0), x, y, 168)
		y = y + 11
		Draw.row("PROGRESS", U.fmtPct((self.pending.progress or 0) * 100), x, y, 168)
		y = y + 11
		if self.cancelled then
			Text.draw("(CANCELLED BY YOU)", x, y)
			y = y + 11
		end
	else
		Text.drawWrapped("Logging a print that failed off the record.", x, y, 170, 2)
		y = y + 26
	end
	local spool = self.job.spoolId and Store.spool(self.job.spoolId)
	Text.draw(U.truncate(spool and Spool.shortLabel(spool) or self.job.material, 28), x, y)
	y = y + 16
	Text.draw("WASTED FILAMENT", x, y)
	y = y + 12
	Text.draw(U.fmtGrams(self.grams), 100, y, { scale = 2, align = "center" })
	y = y + 22
	Draw.bar(x, y, 168, 7, self.grams / math.max(1, self.maxGrams * 2))
	y = y + 12
	if spool then
		Text.draw("COST " .. U.fmtMoney(Filament.cost(spool, self.grams)), x, y)
		y = y + 11
	end
	if self.notes ~= "" then
		Text.drawWrapped('"' .. self.notes .. '"', x, y, 168, 2)
	end

	-- Right: cause list.
	Draw.window(198, 22, 198, 200, { title = "CAUSE" })
	for i, row in self.list:visible() do
		local c = Enums.FAILURE_CAUSES[i]
		local yy = 33 + row * 14
		Text.draw(c.label, 222, yy)
		if i == self.list.sel then Draw.cursor(210, yy + 1) end
		if self.pending and self.pending.cause == c.id then
			Text.draw(FontData.icon.star, 380, yy)
		end
	end
	-- Past count for this cause on this material (cached per cause).
	local m = spool and spool.material or self.job.material
	if self.countCause ~= self.cause then
		self.countCause = self.cause
		self.causeCount = #Stats.recent(200, function(h) return h.outcome == "failed" and h.cause == self.cause and h.material == m end)
	end
	Text.draw(string.format("%d BEFORE ON %s", self.causeCount, m), 210, 206)
end
