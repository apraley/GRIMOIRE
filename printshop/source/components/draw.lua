-- Drawing primitives in the PRINT SHOP house style: double-line JRPG
-- windows, 8x8 dither patterns (the only "greys" we allow), a blinking
-- triangle cursor, bars and small icons. Everything is 1-bit.
--
-- Themes: "night" = black windows with white ink (16-bit console menus);
-- "day" = white windows with black ink. Screens ask Draw for fg/bg rather
-- than hard-coding colours so both themes work everywhere.

local gfx <const> = playdate.graphics

Draw = {
	theme = "night",
	blinkOn = true,
	t = 0,          -- ms since start, for animation
}

-- 8x8 patterns; bit set = white pixel.
Draw.P = {
	white   = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF },
	light12 = { 0xFF, 0xDD, 0xFF, 0x77, 0xFF, 0xDD, 0xFF, 0x77 },
	light25 = { 0x77, 0xFF, 0xDD, 0xFF, 0x77, 0xFF, 0xDD, 0xFF },
	gray50  = { 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55 },
	dark75  = { 0x88, 0x00, 0x22, 0x00, 0x88, 0x00, 0x22, 0x00 },
	dark88  = { 0x80, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00 },
	hlines  = { 0xFF, 0x00, 0xFF, 0xFF, 0xFF, 0x00, 0xFF, 0xFF },
	vlines  = { 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB },
	diag    = { 0x7F, 0xBF, 0xDF, 0xEF, 0xF7, 0xFB, 0xFD, 0xFE },
	brick   = { 0xFE, 0xFE, 0xFE, 0xAA, 0xEF, 0xEF, 0xEF, 0xAA },
	wood    = { 0xFF, 0xFF, 0xF7, 0x00, 0xFF, 0x7F, 0xFF, 0x00 },
	dots    = { 0xFF, 0xFF, 0xF7, 0xFF, 0xFF, 0xFF, 0x7F, 0xFF },
	checker = { 0xF0, 0xF0, 0xF0, 0xF0, 0x0F, 0x0F, 0x0F, 0x0F },
	water   = { 0xFF, 0xE7, 0x18, 0xFF, 0xFF, 0x7E, 0x81, 0xFF },
}

-- Fade ramp used for screen transitions (light -> dark).
Draw.RAMP = { "white", "light12", "light25", "gray50", "dark75", "dark88" }

function Draw.setTheme(theme)
	Draw.theme = theme == "day" and "day" or "night"
end

-- Solid colours for window fill and ink.
function Draw.bgColor() return Draw.theme == "night" and gfx.kColorBlack or gfx.kColorWhite end
function Draw.fgColor() return Draw.theme == "night" and gfx.kColorWhite or gfx.kColorBlack end
function Draw.fgInk() return Draw.theme == "night" and "white" or "black" end
function Draw.bgInk() return Draw.theme == "night" and "black" or "white" end

function Draw.tick(dtMs)
	Draw.t = Draw.t + dtMs
	Draw.blinkOn = (Draw.t // 400) % 2 == 0
end

function Draw.pattern(name)
	gfx.setPattern(Draw.P[name] or Draw.P.gray50)
end

function Draw.fillPattern(name, x, y, w, h)
	Draw.pattern(name)
	gfx.fillRect(x, y, w, h)
	gfx.setColor(gfx.kColorBlack)
end

function Draw.fill(color, x, y, w, h)
	gfx.setColor(color)
	gfx.fillRect(x, y, w, h)
end

function Draw.frame(color, x, y, w, h)
	gfx.setColor(color)
	gfx.drawRect(x, y, w, h)
end

-- Double-line bordered window. opts.title draws a tab; opts.fill = false
-- skips the background; opts.invert swaps colours for emphasis.
function Draw.window(x, y, w, h, opts)
	opts = opts or {}
	local bg, fg = Draw.bgColor(), Draw.fgColor()
	if opts.invert then bg, fg = fg, bg end
	if opts.fill ~= false then
		gfx.setColor(bg)
		gfx.fillRect(x, y, w, h)
	end
	-- Outer line with clipped corners, gap, inner line: the classic look.
	gfx.setColor(fg)
	gfx.drawLine(x + 2, y, x + w - 3, y)
	gfx.drawLine(x + 2, y + h - 1, x + w - 3, y + h - 1)
	gfx.drawLine(x, y + 2, x, y + h - 3)
	gfx.drawLine(x + w - 1, y + 2, x + w - 1, y + h - 3)
	gfx.drawPixel(x + 1, y + 1)
	gfx.drawPixel(x + w - 2, y + 1)
	gfx.drawPixel(x + 1, y + h - 2)
	gfx.drawPixel(x + w - 2, y + h - 2)
	gfx.drawRect(x + 3, y + 3, w - 6, h - 6)
	if opts.title then
		local tw = Text.width(opts.title) + 10
		gfx.setColor(bg)
		gfx.fillRect(x + 8, y, tw, 7)
		gfx.setColor(fg)
		gfx.drawRect(x + 8, y - 4, tw, 12)
		gfx.setColor(bg)
		gfx.fillRect(x + 9, y - 3, tw - 2, 10)
		Text.draw(opts.title, x + 13, y - 3, { color = opts.invert and Draw.bgInk() or Draw.fgInk() })
	end
	gfx.setColor(gfx.kColorBlack)
end

-- Blinking ▶ cursor, 5 wide x 7 tall, tip at (x+5, y+3).
function Draw.cursor(x, y, color, noBlink)
	if not noBlink and not Draw.blinkOn then return end
	gfx.setColor(color or Draw.fgColor())
	gfx.fillTriangle(x, y, x + 5, y + 3, x, y + 7)
	gfx.setColor(gfx.kColorBlack)
end

-- Small down-pointing triangle for "more text" prompts.
function Draw.moreArrow(x, y, color)
	if not Draw.blinkOn then return end
	gfx.setColor(color or Draw.fgColor())
	gfx.fillTriangle(x, y, x + 6, y, x + 3, y + 4)
	gfx.setColor(gfx.kColorBlack)
end

-- Progress bar: frame + dithered or solid fill. frac 0..1.
function Draw.bar(x, y, w, h, frac, opts)
	opts = opts or {}
	local fg = opts.color or Draw.fgColor()
	frac = U.clamp(frac or 0, 0, 1)
	gfx.setColor(fg)
	gfx.drawRect(x, y, w, h)
	local fw = math.floor((w - 4) * frac + 0.5)
	if fw > 0 then
		if opts.pattern then
			Draw.pattern(opts.pattern)
			gfx.fillRect(x + 2, y + 2, fw, h - 4)
		else
			gfx.setColor(fg)
			gfx.fillRect(x + 2, y + 2, fw, h - 4)
		end
	end
	if opts.marks then
		gfx.setColor(fg)
		for i = 1, opts.marks - 1 do
			local mx = x + math.floor(w * i / opts.marks)
			gfx.drawLine(mx, y + h, mx, y + h + 1)
		end
	end
	gfx.setColor(gfx.kColorBlack)
end

-- Segmented "pips" meter, e.g. priority. n filled of max.
function Draw.pips(x, y, n, max, color)
	gfx.setColor(color or Draw.fgColor())
	for i = 1, max do
		if i <= n then gfx.fillRect(x + (i - 1) * 5, y, 4, 6)
		else gfx.drawRect(x + (i - 1) * 5, y, 4, 6) end
	end
	gfx.setColor(gfx.kColorBlack)
end

-- Checkbox 7x7.
function Draw.checkbox(x, y, on, color)
	gfx.setColor(color or Draw.fgColor())
	gfx.drawRect(x, y, 7, 7)
	if on then gfx.fillRect(x + 2, y + 2, 3, 3) end
	gfx.setColor(gfx.kColorBlack)
end

-- Dotted leader line between a label and a value: one pattern-filled 1px
-- rect (a dot every 4px) instead of a drawPixel per dot.
local LEADER_WHITE = { 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88 }
local LEADER_BLACK = { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88, 0x88 }
function Draw.leader(x1, x2, y, color)
	if x2 <= x1 then return end
	-- Alpha-masked patterns: only the dots are drawn, the rest stays as is.
	gfx.setPattern((color or Draw.fgColor()) == gfx.kColorWhite and LEADER_WHITE or LEADER_BLACK)
	gfx.fillRect(x1, y, x2 - x1, 1)
	gfx.setColor(gfx.kColorBlack)
end

-- Label ........ value row inside a window.
function Draw.row(label, value, x, y, w, color)
	color = color or Draw.fgInk()
	Text.draw(label, x, y, { color = color })
	local vw = Text.width(value)
	Text.draw(value, x + w, y, { color = color, align = "right" })
	local lx1 = x + Text.width(label) + 3
	local lx2 = x + w - vw - 3
	if lx2 > lx1 then Draw.leader(lx1, lx2, y + 7, color == "white" and gfx.kColorWhite or gfx.kColorBlack) end
end

-- Screen title bar: black band with white title, optional right text.
function Draw.titleBar(title, right)
	gfx.setColor(gfx.kColorBlack)
	gfx.fillRect(0, 0, 400, 15)
	gfx.setColor(gfx.kColorWhite)
	gfx.drawLine(0, 13, 400, 13)
	Text.draw(title, 6, 2, { color = "white" })
	if right then Text.draw(right, 394, 2, { color = "white", align = "right" }) end
	gfx.setColor(gfx.kColorBlack)
end

-- Footer hint strip: "A:OPEN  B:BACK".
function Draw.hints(text)
	gfx.setColor(gfx.kColorBlack)
	gfx.fillRect(0, 227, 400, 13)
	Text.draw(text, 200, 229, { color = "white", align = "center" })
end

-- Full-screen backdrop pattern for screens.
function Draw.backdrop(name)
	gfx.clear(gfx.kColorWhite)
	if name then Draw.fillPattern(name, 0, 0, 400, 240) end
end

-- Tiny bar chart: values list, w x h box. Optional second series (drawn
-- hatched on top) for failures.
function Draw.barChart(x, y, w, h, values, values2, color)
	color = color or Draw.fgColor()
	local maxV = 1
	for i, v in ipairs(values) do
		local v2 = values2 and values2[i] or 0
		if v + v2 > maxV then maxV = v + v2 end
	end
	local n = #values
	if n == 0 then return end
	local bw = math.max(1, (w - (n - 1)) // n)
	gfx.setColor(color)
	gfx.drawLine(x, y + h, x + w, y + h)
	for i, v in ipairs(values) do
		local bx = x + (i - 1) * (bw + 1)
		local bh = math.floor((h - 1) * v / maxV + 0.5)
		gfx.setColor(color)
		if bh > 0 then gfx.fillRect(bx, y + h - bh, bw, bh) end
		local v2 = values2 and values2[i] or 0
		if v2 > 0 then
			local fh = math.max(1, math.floor((h - 1) * v2 / maxV + 0.5))
			Draw.pattern("gray50")
			gfx.fillRect(bx, y + h - bh - fh, bw, fh)
			gfx.setColor(color)
			gfx.drawRect(bx, y + h - bh - fh, bw, fh)
		end
	end
	gfx.setColor(gfx.kColorBlack)
end

-- Line graph of a numeric series inside a box.
function Draw.lineGraph(x, y, w, h, series, lo, hi, color)
	if #series < 2 then return end
	gfx.setColor(color or Draw.fgColor())
	local span = math.max(1, hi - lo)
	local step = w / (#series - 1)
	local px, py
	for i, v in ipairs(series) do
		local cx = x + math.floor((i - 1) * step)
		local cy = y + h - math.floor(U.clamp((v - lo) / span, 0, 1) * h)
		if px then gfx.drawLine(px, py, cx, cy) end
		px, py = cx, cy
	end
	gfx.setColor(gfx.kColorBlack)
end

-- Status tag box ("PRN", "RDY"...), inverted when `solid`.
function Draw.tag(text, x, y, solid, color)
	local w = Text.width(text) + 4
	local fg = color or Draw.fgColor()
	gfx.setColor(fg)
	if solid then
		gfx.fillRect(x, y, w, 11)
		local ink = (fg == gfx.kColorWhite) and "black" or "white"
		Text.draw(text, x + 2, y + 1, { color = ink })
	else
		gfx.drawRect(x, y, w, 11)
		Text.draw(text, x + 2, y + 1, { color = (fg == gfx.kColorWhite) and "white" or "black" })
	end
	gfx.setColor(gfx.kColorBlack)
	return w
end
