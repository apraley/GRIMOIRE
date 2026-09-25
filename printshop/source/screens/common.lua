-- Helpers shared by screens.

local gfx <const> = playdate.graphics

Common = {}

-- Captain explains a feature in a dialog box with his portrait.
function Common.help(feature, onDone)
	local d
	d = Dialog.open(Captain.explain(feature), {
		speaker = "CAPTAIN",
		portrait = function(x, y) Sprites.captainPortrait(x, y, "neutral", d and not d:done()) end,
		onDone = onDone,
	})
	return d
end

-- The Captain says one line (table from Captain.advice etc.).
function Common.say(line, onDone)
	local d
	d = Dialog.open({ line.text }, {
		speaker = "CAPTAIN",
		portrait = function(x, y) Sprites.captainPortrait(x, y, line.mood, d and not d:done()) end,
		onDone = onDone,
	})
	return d
end

-- Printer state -> short label.
Common.STATE_LABEL = {
	IDLE = "IDLE", HEATING = "HEATING", PRINTING = "PRINTING", PAUSED = "PAUSED",
	ERROR = "ERROR", COMPLETE = "COMPLETE", OFFLINE = "OFFLINE",
}

-- Standard screen chrome: white page, title bar, hint strip.
function Common.page(title, right, hints, pattern)
	gfx.clear(gfx.kColorWhite)
	if pattern then Draw.fillPattern(pattern, 0, 15, 400, 212) end
	Draw.titleBar(title, right)
	if hints then Draw.hints(hints) end
end

-- Empty-state panel with a Captain line.
function Common.empty(x, y, w, h, title, body)
	Draw.window(x, y, w, h)
	Text.draw(title, x + w // 2, y + 12, { align = "center" })
	Text.drawWrapped(body, x + 14, y + 30, w - 28, (h - 40) // Text.LINE)
end

-- Picker for a spool: returns via callback(spool or nil).
function Common.pickSpool(title, filterMaterial, onPick, allowNone)
	local items = {}
	if allowNone then
		items[#items + 1] = { label = "(NO SPOOL)", action = function() onPick(nil) end }
	end
	for _, s in ipairs(Filament.list({ filter = "ALL", sort = "MATERIAL" })) do
		if filterMaterial == nil or s.material == filterMaterial then
			items[#items + 1] = {
				label = U.truncate(Spool.shortLabel(s), 26),
				right = U.fmtGrams(s.remainingGrams),
				hint = s.location .. "  " .. s.dryness .. (Spool.isLow(s, Store.settings().lowSpoolGrams) and "  LOW!" or ""),
				action = function() onPick(s) end,
			}
		end
	end
	if #items == 0 then
		items[1] = { label = "NO SPOOLS IN ROLODEX", disabled = true }
	end
	Menu.open({ title = title, items = items, maxRows = 10 })
end

-- Picks a failure cause.
function Common.pickCause(title, selected, onPick)
	local items = {}
	local sel = 1
	for i, c in ipairs(Enums.FAILURE_CAUSES) do
		if c.id == selected then sel = i end
		items[#items + 1] = { label = c.label, action = function() onPick(c.id) end }
	end
	Menu.open({ title = title, items = items, sel = sel, maxRows = 10 })
end

-- Dithered "gauge" for temperatures: label, now/target, bar vs max.
function Common.tempRow(label, now, target, x, y, w, maxT)
	local txt = string.format("%3d/%3d", U.roundInt(now), U.roundInt(target)) .. FontData.icon.deg .. "C"
	Text.draw(label, x, y)
	Text.draw(txt, x + w, y, { align = "right" })
	Draw.bar(x, y + 10, w, 5, (now or 0) / (maxT or 300), {})
	if target and target > 0 then
		local tx = x + math.floor(w * U.clamp(target / (maxT or 300), 0, 1))
		gfx.setColor(Draw.fgColor())
		gfx.drawLine(tx, y + 8, tx, y + 16)
		gfx.setColor(gfx.kColorBlack)
	end
end
