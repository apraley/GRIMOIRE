-- Pixel text renderer for the 5x9 font in data/font5x9.lua.
--
-- Glyphs are rendered once into small images at startup. Whole strings are
-- composed into cached images (one draw call per string per frame), which
-- keeps text cheap even on busy screens. The cache has two generations of
-- CACHE_MAX entries each, so memory stays bounded; typewriter text bypasses
-- it by drawing the in-progress line glyph by glyph.

local gfx <const> = playdate.graphics

Text = {
	glyphs = {},
	cache = {},
	cacheCount = 0,
	oldCache = {},       -- previous generation (see Text.image)
	CACHE_MAX = 260,
	ADV = 6,
	H = 9,
	LINE = 11,
}

local function buildGlyph(rowsText)
	local rows = {}
	for r in string.gmatch(rowsText, "%S+") do rows[#rows + 1] = r end
	local img = gfx.image.new(5, 9, gfx.kColorClear)
	gfx.pushContext(img)
	gfx.setColor(gfx.kColorBlack)
	for y, row in ipairs(rows) do
		for x = 1, #row do
			if string.sub(row, x, x) == "#" then
				gfx.fillRect(x - 1, y - 1, 1, 1)
			end
		end
	end
	gfx.popContext()
	return img
end

function Text.init()
	for line in string.gmatch(FontData.source, "[^\n]+") do
		local ch = string.sub(line, 1, 1)
		local rest = string.sub(line, 3)
		Text.glyphs[ch] = buildGlyph(rest)
	end
	for _, entry in ipairs(FontData.iconSource) do
		Text.glyphs[string.char(entry[2])] = buildGlyph(entry[3])
	end
end

function Text.width(s)
	local n = #s
	if n == 0 then return 0 end
	return n * Text.ADV - 1
end

-- Composes a string into a transparent image with black ink.
local function render(s)
	local w = math.max(1, Text.width(s))
	local img = gfx.image.new(w, Text.H, gfx.kColorClear)
	gfx.pushContext(img)
	local x = 0
	local glyphs = Text.glyphs
	for i = 1, #s do
		local g = glyphs[string.sub(s, i, i)]
		if g == nil and string.sub(s, i, i) ~= " " then g = glyphs["?"] end
		if g then g:draw(x, 0) end
		x = x + Text.ADV
	end
	gfx.popContext()
	return img
end

function Text.image(s)
	local img = Text.cache[s]
	if img == nil then
		-- Two generations: when the young cache fills it becomes the old one,
		-- so strings still on screen survive the rollover instead of all being
		-- re-rendered in the same frame.
		img = Text.oldCache[s]
		if img == nil then img = render(s) end
		if Text.cacheCount >= Text.CACHE_MAX then
			Text.oldCache = Text.cache
			Text.cache = {}
			Text.cacheCount = 0
		end
		Text.cache[s] = img
		Text.cacheCount = Text.cacheCount + 1
	end
	return img
end

-- Draw modes for ink colour: "black" copies, "white" fills ink white.
local function withInk(color, fn)
	if color == "white" then
		gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
		fn()
		gfx.setImageDrawMode(gfx.kDrawModeCopy)
	else
		fn()
	end
end

-- opts: color ("black"/"white"/"fg"/"bg"), align ("left"/"center"/"right"),
-- scale (1..4). Returns drawn width.
function Text.draw(s, x, y, opts)
	s = tostring(s or "")
	if s == "" then return 0 end
	local color, align, scale = "fg", "left", 1
	if opts then
		color = opts.color or color
		align = opts.align or align
		scale = opts.scale or scale
	end
	if color == "fg" then color = Draw.fgInk() elseif color == "bg" then color = Draw.bgInk() end
	local w = Text.width(s) * scale
	if align == "center" then x = x - w // 2 elseif align == "right" then x = x - w end
	local img = Text.image(s)
	-- Inlined ink switch: this runs dozens of times a frame, so no closure.
	local white = color == "white"
	if white then gfx.setImageDrawMode(gfx.kDrawModeFillWhite) end
	if scale == 1 then img:draw(x, y) else img:drawScaled(x, y, scale) end
	if white then gfx.setImageDrawMode(gfx.kDrawModeCopy) end
	return w
end

-- Draws the first n characters of s glyph by glyph (typewriter lines).
function Text.drawPartial(s, n, x, y, color)
	if color == nil or color == "fg" then color = Draw.fgInk() elseif color == "bg" then color = Draw.bgInk() end
	n = math.min(n, #s)
	if n >= #s then
		return Text.draw(s, x, y, { color = color })
	end
	withInk(color, function()
		local glyphs = Text.glyphs
		for i = 1, n do
			local g = glyphs[string.sub(s, i, i)]
			if g then g:draw(x + (i - 1) * Text.ADV, y) end
		end
	end)
end

-- Word-wraps to at most maxChars per line. Honors "\n".
function Text.wrap(s, maxChars)
	local lines = {}
	for para in string.gmatch(tostring(s) .. "\n", "(.-)\n") do
		local line = ""
		for word in string.gmatch(para, "%S+") do
			while #word > maxChars do
				if line ~= "" then lines[#lines + 1] = line line = "" end
				lines[#lines + 1] = string.sub(word, 1, maxChars)
				word = string.sub(word, maxChars + 1)
			end
			if line == "" then
				line = word
			elseif #line + 1 + #word <= maxChars then
				line = line .. " " .. word
			else
				lines[#lines + 1] = line
				line = word
			end
		end
		lines[#lines + 1] = line
	end
	-- Drop the trailing empty line produced by the final "\n".
	while #lines > 1 and lines[#lines] == "" do lines[#lines] = nil end
	return lines
end

-- Wrapping runs every frame for detail panels, so results are cached
-- (bounded; the returned lines are shared and must not be modified).
local wrapCache, wrapCount = {}, 0

local function cachedWrap(s, maxChars)
	s = tostring(s)
	local key = maxChars .. "|" .. s
	local lines = wrapCache[key]
	if lines == nil then
		if wrapCount >= 120 then wrapCache, wrapCount = {}, 0 end
		lines = Text.wrap(s, maxChars)
		wrapCache[key] = lines
		wrapCount = wrapCount + 1
	end
	return lines
end

-- Draws wrapped text inside width w; returns number of lines drawn.
function Text.drawWrapped(s, x, y, w, maxLines, opts)
	local lines = cachedWrap(s, math.max(1, (w + 1) // Text.ADV))
	local n = math.min(#lines, maxLines or #lines)
	for i = 1, n do
		local line = lines[i]
		if i == n and n < #lines then line = U.truncate(line .. "...", (w + 1) // Text.ADV) end
		Text.draw(line, x, y + (i - 1) * Text.LINE, opts)
	end
	return n
end

-- Max characters that fit in a pixel width.
function Text.fit(w)
	return math.max(1, (w + 1) // Text.ADV)
end
