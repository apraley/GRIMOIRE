-- Drawing primitives: text with the system font, pixel icons, JRPG-style
-- windows, bars and the hint footer. All screens draw through these so the
-- look stays consistent and 1-bit legible.

Gfx = {}

local gfx = playdate.graphics
Gfx.W, Gfx.H = 400, 240
local BLACK, WHITE = gfx.kColorBlack, gfx.kColorWhite

local ICONS = {
	star = { "...#...", "...#...", "..###..", "#######", ".#####.", "..###..", ".##.##.", ".#...#." },
	check = { "........", ".......#", "......##", "#....##.", "##..##..", ".####...", "..##....", "........" },
	x = { "#.....#", "##...##", ".##.##.", "..###..", ".##.##.", "##...##", "#.....#", "......." },
	warn = { "...##...", "...##...", "..#..#..", "..#..#..", ".#.##.#.", ".#....#.", "#..##..#", "########" },
	ring = { "..####..", ".#....#.", "#......#", "#......#", "#......#", "#......#", ".#....#.", "..####.." },
	todo = { "........", ".######.", ".#....#.", ".#....#.", ".#....#.", ".#....#.", ".######.", "........" },
	upnext = { "........", "##..##..", ".##..##.", "..##..##", ".##..##.", "##..##..", "........", "........" },
	rec = { "........", "..####..", ".######.", ".######.", ".######.", ".######.", "..####..", "........" },
	pickup = { ".####.#.", "#....##.", "#...###.", "#.......", "#......#", "#......#", ".######.", "........" },
	cut = { "#......#", ".#....#.", "..#..#..", "...##...", "..#..#..", ".##..##.", "#.#..#.#", ".#....#." },
	flag = { "#####...", "#######.", "#######.", "#####...", "#.......", "#.......", "#.......", "........" },
	disk = { "#######.", "#.###.#.", "#.###.#.", "#.....#.", "#.###.#.", "#.#.#.#.", "#######.", "........" },
	crank = { "....##..", "....##..", "....#...", "#####...", "#...#...", "#...#...", "#####...", "........" },
	up = { "...#....", "..###...", ".#####..", "#######.", "..###...", "..###...", "..###...", "........" },
	down = { "..###...", "..###...", "..###...", "#######.", ".#####..", "..###...", "...#....", "........" },
	left = { "...#....", "..##....", ".#######", "########", ".#######", "..##....", "...#....", "........" },
	right = { "....#...", "....##..", "#######.", "########", "#######.", "....##..", "....#...", "........" },
	cam = { "........", ".##.....", "#######.", "#.....##", "#..#..##", "#.....##", "#######.", "........" },
	clock = { "..###...", ".#.#.#..", "#..#..#.", "#..##.#.", "#.....#.", ".#...#..", "..###...", "........" },
	lock = { "..###...", ".#...#..", ".#...#..", "#######.", "###.###.", "###.###.", "#######.", "........" },
}

local ICON_RUNS = {}
for name, rows in pairs(ICONS) do
	local runs = {}
	for r, line in ipairs(rows) do
		local x = 1
		while x <= #line do
			if line:sub(x, x) == "#" then
				local s = x
				while x <= #line and line:sub(x, x) == "#" do x = x + 1 end
				runs[#runs + 1] = { r - 1, s - 1, x - s }
			else
				x = x + 1
			end
		end
	end
	ICON_RUNS[name] = runs
end

function Gfx.init()
	Gfx.font = gfx.getSystemFont("normal")
	Gfx.bold = gfx.getSystemFont("bold")
	Gfx.lineH = Gfx.font:getHeight()
	Gfx.hasDegree = Gfx.font:getGlyph("\194\176") ~= nil
end

function Gfx.setColor(white)
	gfx.setColor(white and WHITE or BLACK)
end

-- ASCII-safe text for the system font.
function Gfx.safe(s)
	s = tostring(s or "")
	if not Gfx.hasDegree then s = s:gsub("\194\176", "D") end
	return Util.ascii(s)
end

function Gfx.textW(s, bold)
	return (bold and Gfx.bold or Gfx.font):getTextWidth(Gfx.safe(s))
end

function Gfx.fit(s, maxW, bold)
	s = Gfx.safe(s)
	local f = bold and Gfx.bold or Gfx.font
	if f:getTextWidth(s) <= maxW then return s end
	while #s > 1 and f:getTextWidth(s .. "..") > maxW do s = s:sub(1, -2) end
	return s .. ".."
end

-- opts: bold, white, align ("left"|"center"|"right"), maxW
function Gfx.text(s, x, y, opts)
	opts = opts or {}
	local f = opts.bold and Gfx.bold or Gfx.font
	s = opts.maxW and Gfx.fit(s, opts.maxW, opts.bold) or Gfx.safe(s)
	local w = f:getTextWidth(s)
	if opts.align == "center" then x = x - w // 2 elseif opts.align == "right" then x = x - w end
	if opts.white then gfx.setImageDrawMode(gfx.kDrawModeFillWhite) end
	f:drawText(s, x, y)
	if opts.white then gfx.setImageDrawMode(gfx.kDrawModeCopy) end
	return w
end

-- Word-wrap into at most maxLines lines of width maxW. Returns lines.
function Gfx.wrap(s, maxW, maxLines, bold)
	s = Gfx.safe(s)
	local f = bold and Gfx.bold or Gfx.font
	local lines, cur = {}, ""
	for word in s:gmatch("%S+") do
		local try = cur == "" and word or (cur .. " " .. word)
		if f:getTextWidth(try) <= maxW then
			cur = try
		else
			if cur ~= "" then lines[#lines + 1] = cur end
			cur = word
		end
	end
	if cur ~= "" then lines[#lines + 1] = cur end
	if maxLines and #lines > maxLines then
		local keep = {}
		for i = 1, maxLines do keep[i] = lines[i] end
		keep[maxLines] = Gfx.fit(keep[maxLines] .. " " .. lines[maxLines + 1], maxW, bold)
		lines = keep
	end
	return lines
end

-- Pixel-font text. opts: white, align. Returns width.
function Gfx.pix(s, x, y, scale, opts)
	opts = opts or {}
	gfx.setColor(opts.white and WHITE or BLACK)
	local w = Pixfont.draw(s, x, y, scale, opts.align)
	gfx.setColor(BLACK)
	return w
end

function Gfx.icon(name, x, y, opts)
	local runs = ICON_RUNS[name]
	if runs == nil then return end
	local s = (opts and opts.scale) or 1
	gfx.setColor((opts and opts.white) and WHITE or BLACK)
	for _, r in ipairs(runs) do
		gfx.fillRect(x + r[2] * s, y + r[1] * s, r[3] * s, s)
	end
	gfx.setColor(BLACK)
end

function Gfx.fill(x, y, w, h, white)
	gfx.setColor(white and WHITE or BLACK)
	gfx.fillRect(x, y, w, h)
	gfx.setColor(BLACK)
end

function Gfx.rect(x, y, w, h, white)
	gfx.setColor(white and WHITE or BLACK)
	gfx.drawRect(x, y, w, h)
	gfx.setColor(BLACK)
end

function Gfx.hline(x, y, w, white)
	Gfx.fill(x, y, w, 1, white)
end

-- Dithered dim layer (used under modal windows).
function Gfx.dim(x, y, w, h)
	gfx.setColor(BLACK)
	gfx.setDitherPattern(0.5)
	gfx.fillRect(x or 0, y or 0, w or Gfx.W, h or Gfx.H)
	gfx.setColor(BLACK)
end

-- JRPG window: white body, 2px rounded black frame, inner hairline.
-- title (optional) sits in a black tab on the top edge.
function Gfx.window(x, y, w, h, title)
	gfx.setColor(WHITE)
	gfx.fillRoundRect(x, y, w, h, 4)
	gfx.setColor(BLACK)
	gfx.setLineWidth(2)
	gfx.drawRoundRect(x + 1, y + 1, w - 2, h - 2, 4)
	gfx.setLineWidth(1)
	gfx.drawRoundRect(x + 4, y + 4, w - 8, h - 8, 2)
	if title then
		local tw = Pixfont.width(title, 1) + 10
		Gfx.fill(x + 10, y - 3, tw, 11)
		Gfx.pix(title, x + 15, y - 1, 1, { white = true })
	end
end

-- Selection bar (inverted row).
function Gfx.selbar(x, y, w, h)
	gfx.setColor(BLACK)
	gfx.fillRoundRect(x, y, w, h, 3)
end

-- Cursor triangle ("hand") pointing right.
function Gfx.cursor(x, y, white)
	gfx.setColor(white and WHITE or BLACK)
	gfx.fillTriangle(x, y, x, y + 8, x + 5, y + 4)
	gfx.setColor(BLACK)
end

-- Progress bar: solid for done, dither for pickups (optional).
function Gfx.bar(x, y, w, h, frac, frac2)
	gfx.setColor(BLACK)
	gfx.drawRect(x, y, w, h)
	local fw = math.floor((w - 4) * Util.clamp(frac or 0, 0, 1))
	gfx.fillRect(x + 2, y + 2, fw, h - 4)
	if frac2 and frac2 > 0 then
		local pw = math.floor((w - 4) * Util.clamp(frac2, 0, 1))
		gfx.setDitherPattern(0.5)
		gfx.fillRect(x + 2 + fw, y + 2, pw, h - 4)
		gfx.setColor(BLACK)
	end
end

-- A small round button badge with a letter: "A", "B".
function Gfx.btn(letter, x, y, white)
	gfx.setColor(white and WHITE or BLACK)
	gfx.fillCircleAtPoint(x + 6, y + 6, 6)
	Gfx.pix(letter, x + 4, y + 3, 1, { white = not white })
	gfx.setColor(BLACK)
end

-- Footer hint bar. items: { {"A","TAKE"}, {"B","INFO"}, {"crank","SHOT"}, {"up","HUB"} }
-- Keys "A"/"B" draw badges, others draw icons; a key prefixed "!" means hold.
function Gfx.hints(items, y)
	y = y or (Gfx.H - 18)
	-- overlays may sit on LIVE's taller two-row footer: cover it entirely
	Gfx.fill(0, Gfx.coverFooter and (Gfx.H - 26) or y, Gfx.W, Gfx.H - y + (Gfx.coverFooter and 8 or 0))
	local x = 6
	for _, it in ipairs(items) do
		local key, label = it[1], it[2]
		local hold = key:sub(1, 1) == "!"
		if hold then key = key:sub(2) end
		if key == "A" or key == "B" then
			if hold then
				Gfx.pix("HOLD", x, y + 6, 1, { white = true }); x = x + 20
			end
			Gfx.btn(key, x, y + 3, true)
			x = x + 15
		else
			Gfx.icon(key, x, y + 5, { white = true })
			x = x + 10
		end
		local w = Gfx.pix(label, x, y + 6, 1, { white = true })
		x = x + w + 12
	end
end

-- Status glyph: icon for a shot status.
function Gfx.statusIcon(status, x, y, white)
	Gfx.icon(Vocab.STATUS_ICON[status] or "todo", x, y, { white = white })
end

-- Inverted pill with status text.
function Gfx.statusPill(status, x, y, align)
	local label = status
	local w = Pixfont.width(label, 1) + 18
	if align == "right" then x = x - w end
	gfx.setColor(BLACK)
	gfx.fillRoundRect(x, y, w, 13, 3)
	Gfx.statusIcon(status, x + 3, y + 3, true)
	Gfx.pix(label, x + 13, y + 3, 1, { white = true })
	return w
end

function Gfx.ratingIcon(rating, x, y, white)
	local name = Vocab.RATING_ICON[rating]
	if name then Gfx.icon(name, x, y, { white = white }) end
end

return Gfx
