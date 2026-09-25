-- Procedural 1-bit pixel art. Everything is drawn with rects, lines,
-- triangles and dither patterns, so it scales with data (spool fill,
-- print progress, state) instead of being baked into image files.

local gfx <const> = playdate.graphics
local floor <const> = math.floor
local sin <const> = math.sin

Sprites = {
	partCache = {},
	partCacheCount = 0,
}

local BLACK <const> = gfx.kColorBlack
local WHITE <const> = gfx.kColorWhite

local function rect(c, x, y, w, h) gfx.setColor(c) gfx.fillRect(x, y, w, h) end
local function box(c, x, y, w, h) gfx.setColor(c) gfx.drawRect(x, y, w, h) end
local function line(c, x1, y1, x2, y2) gfx.setColor(c) gfx.drawLine(x1, y1, x2, y2) end
local function pat(name, x, y, w, h) Draw.pattern(name) gfx.fillRect(x, y, w, h) gfx.setColor(BLACK) end

---------------------------------------------------------------------------
-- filament colours as dither patterns

Sprites.COLOR_PATTERN = {
	BLACK = "black", WHITE = "white", GRAY = "gray50", SILVER = "light25", RED = "dark75",
	ORANGE = "diag", YELLOW = "light25", GREEN = "checker", BLUE = "hlines", PURPLE = "vlines",
	PINK = "light12", BROWN = "brick", CLEAR = "dots", GOLD = "water", OLIVE = "gray50", NAVY = "dark88",
}
local FALLBACK = { "gray50", "diag", "checker", "hlines", "vlines", "dark75", "light25", "brick" }

function Sprites.colorPattern(color)
	color = U.upper(color or "")
	local p = Sprites.COLOR_PATTERN[color]
	if p then return p end
	return FALLBACK[U.hash(color) % #FALLBACK + 1]
end

local function fillColor(color, x, y, w, h)
	local p = Sprites.colorPattern(color)
	if p == "black" then rect(BLACK, x, y, w, h)
	elseif p == "white" then rect(WHITE, x, y, w, h)
	else pat(p, x, y, w, h) end
end

local function fillCircleColor(color, cx, cy, r)
	local p = Sprites.colorPattern(color)
	if p == "black" then gfx.setColor(BLACK)
	elseif p == "white" then gfx.setColor(WHITE)
	else Draw.pattern(p) end
	gfx.fillCircleAtPoint(cx, cy, r)
	gfx.setColor(BLACK)
end

---------------------------------------------------------------------------
-- spool

-- Side-on spool: flange circle, filament ring sized by frac, hub hole.
function Sprites.spool(cx, cy, r, frac, color, opts)
	opts = opts or {}
	frac = U.clamp(frac or 0, 0, 1)
	gfx.setColor(WHITE)
	gfx.fillCircleAtPoint(cx, cy, r)
	gfx.setColor(BLACK)
	gfx.drawCircleAtPoint(cx, cy, r)
	local hub = math.max(2, floor(r * 0.34))
	local fr = hub + floor((r - 2 - hub) * frac + 0.5)
	if fr > hub then
		fillCircleColor(color, cx, cy, fr)
		gfx.setColor(BLACK)
		gfx.drawCircleAtPoint(cx, cy, fr)
	end
	gfx.setColor(WHITE)
	gfx.fillCircleAtPoint(cx, cy, hub)
	gfx.setColor(BLACK)
	gfx.drawCircleAtPoint(cx, cy, hub)
	gfx.fillCircleAtPoint(cx, cy, math.max(1, hub // 2))
	if opts.spin then
		-- A spoke that turns while printing.
		local a = opts.spin
		gfx.drawLine(cx, cy, cx + floor(math.cos(a) * (r - 1)), cy + floor(math.sin(a) * (r - 1)))
	end
end

-- Spool seen edge-on (for shelves): a flanged rectangle.
function Sprites.spoolEdge(x, y, w, h, frac, color)
	rect(BLACK, x, y, 2, h)
	rect(BLACK, x + w - 2, y, 2, h)
	local inner = h - 4
	local fh = floor(inner * U.clamp(frac, 0, 1))
	local top = y + 2 + (inner - fh) // 2
	rect(WHITE, x + 2, y + 2, w - 4, inner)
	if fh > 0 then
		fillColor(color, x + 2, top, w - 4, fh)
		box(BLACK, x + 2, top, w - 4, fh)
	end
	line(BLACK, x + 2, y + h // 2, x + w - 3, y + h // 2)
end

---------------------------------------------------------------------------
-- printed part silhouettes. Each shape maps height z (0 bottom .. 1 top)
-- to a list of horizontal spans in -1..1.

local SHAPES = {}

SHAPES.cube = function(z) return { { -0.7, 0.7 } } end

SHAPES.box = function(z)
	if z < 0.12 then return { { -0.85, 0.85 } } end
	return { { -0.85, -0.7 }, { 0.7, 0.85 } }
end

SHAPES.vase = function(z)
	local w = 0.42 + 0.3 * sin(z * 3.6 + 0.4)
	if z < 0.06 then return { { -w, w } } end
	return { { -w, -w + 0.14 }, { w - 0.14, w } }
end

SHAPES.bracket = function(z)
	if z < 0.28 then return { { -0.9, 0.9 } } end
	if z < 0.36 then return { { -0.9, -0.3 } } end
	return { { -0.9, -0.55 } }
end

SHAPES.tower = function(z)
	local w = 0.55 - 0.3 * z
	if floor(z * 10) % 3 == 0 then w = w + 0.1 end
	return { { -w, w } }
end

SHAPES.gear = function(z)
	local tooth = floor(z * 14) % 2 == 0
	local w = tooth and 0.8 or 0.62
	return { { -w, -0.12 }, { 0.12, w } }
end

SHAPES.figure = function(z)
	if z < 0.1 then return { { -0.7, 0.7 } } end                -- base
	if z < 0.5 then return { { -0.45, 0.5 - z * 0.4 } } end      -- body
	if z < 0.62 then return { { -0.2, 0.15 } } end               -- neck
	if z < 0.85 then return { { -0.35, 0.45 } } end              -- head
	return { { -0.3, -0.15 }, { 0.15, 0.3 } }                    -- horns
end

SHAPES.benchy = function(z)
	if z < 0.34 then
		-- Hull: flares outward, bow on the right rises.
		local w = 0.6 + z
		return { { -w, math.min(0.98, w + z * 0.6) } }
	end
	if z < 0.74 then
		-- Cabin with a window.
		if z > 0.48 and z < 0.62 then return { { -0.55, -0.4 }, { -0.12, 0.2 } } end
		return { { -0.55, 0.2 } }
	end
	return { { -0.48, -0.26 } }                                   -- chimney
end

Sprites.SHAPES = SHAPES

-- Draws the part as printed up to `frac`, with the unprinted remainder as
-- a dotted ghost. `hot` highlights the current layer. Uses an image cache
-- keyed by (shape, size, printed rows) since this redraws every frame.
function Sprites.part(x, y, w, h, shape, frac, opts)
	opts = opts or {}
	local fn = SHAPES[shape] or SHAPES.cube
	frac = U.clamp(frac or 0, 0, 1)
	local printedRows = floor(h * frac + 0.5)
	local key = shape .. ":" .. w .. ":" .. h .. ":" .. printedRows .. ":" .. (opts.ghost == false and 0 or 1)
	local img = Sprites.partCache[key]
	if img == nil then
		if Sprites.partCacheCount > 120 then
			Sprites.partCache = {}
			Sprites.partCacheCount = 0
		end
		img = gfx.image.new(w, h, gfx.kColorClear)
		gfx.pushContext(img)
		local half = w / 2
		for row = 0, h - 1 do
			local z = (row + 0.5) / h
			local yy = h - 1 - row
			local spans = fn(z)
			for _, s in ipairs(spans) do
				local x1 = floor(half + s[1] * half)
				local x2 = floor(half + s[2] * half)
				if row < printedRows then
					gfx.setColor(BLACK)
					gfx.fillRect(x1, yy, math.max(1, x2 - x1), 1)
				elseif opts.ghost ~= false and (row % 2 == 0) then
					gfx.setColor(BLACK)
					gfx.drawPixel(x1, yy)
					gfx.drawPixel(math.max(x1, x2 - 1), yy)
					if row % 6 == 0 then
						for px = x1, x2 - 1, 3 do gfx.drawPixel(px, yy) end
					end
				end
			end
		end
		gfx.popContext()
		Sprites.partCache[key] = img
		Sprites.partCacheCount = Sprites.partCacheCount + 1
	end
	if opts.white then gfx.setImageDrawMode(gfx.kDrawModeFillWhite) end
	img:draw(x, y)
	if opts.white then gfx.setImageDrawMode(gfx.kDrawModeCopy) end
	-- Current layer highlight: a bright line with a dithered glow.
	if opts.hot and printedRows > 0 and printedRows < h then
		local yy = y + h - printedRows
		local spans = fn((printedRows - 0.5) / h)
		for _, s in ipairs(spans) do
			local x1 = x + floor(w / 2 + s[1] * w / 2)
			local x2 = x + floor(w / 2 + s[2] * w / 2)
			gfx.setColor(opts.white and BLACK or WHITE)
			gfx.drawLine(x1, yy, x2 - 1, yy)
		end
	end
	gfx.setColor(BLACK)
	return y + h - printedRows
end

-- Top of the printed region's span at a given progress (for nozzle placement).
function Sprites.partSpan(shape, frac)
	local fn = SHAPES[shape] or SHAPES.cube
	local spans = fn(U.clamp(frac, 0.001, 0.999))
	return spans[1][1], spans[#spans][2]
end

---------------------------------------------------------------------------
-- Bambu Lab A1 Mini (front view). 100 x 104 px. `st` is the printer state,
-- `t` the animation clock in ms, opts: progress (0..1), shape, color.

function Sprites.printer(x, y, st, t, opts)
	opts = opts or {}
	local progress = U.clamp(opts.progress or 0, 0, 1)
	local blink = (t // 300) % 2 == 0
	local shape = opts.shape or "cube"

	-- Base: white housing, dark kick plate, status screen on the front.
	rect(WHITE, x, y + 86, 100, 16)
	box(BLACK, x, y + 86, 100, 16)
	pat("dark75", x + 1, y + 97, 98, 4)
	line(BLACK, x + 1, y + 96, x + 98, y + 96)
	rect(BLACK, x + 70, y + 88, 24, 8)
	gfx.setColor(WHITE)
	if st == "PRINTING" then
		gfx.fillRect(x + 72, y + 91, math.max(1, floor(20 * progress)), 2)
	elseif st == "ERROR" then
		if blink then gfx.fillRect(x + 81, y + 89, 2, 3) gfx.drawPixel(x + 81, y + 94) gfx.drawPixel(x + 82, y + 94) end
	elseif st == "COMPLETE" then
		gfx.drawLine(x + 77, y + 91, x + 79, y + 93)
		gfx.drawLine(x + 79, y + 93, x + 86, y + 89)
	elseif st == "HEATING" then
		if blink then gfx.fillRect(x + 78, y + 90, 8, 4) end
	else
		gfx.drawLine(x + 75, y + 92, x + 89, y + 92)
	end
	rect(BLACK, x + 4, y + 102, 8, 3)
	rect(BLACK, x + 88, y + 102, 8, 3)

	-- Z tower on the left with a shaded side and lead screw.
	rect(WHITE, x + 2, y + 12, 16, 74)
	pat("gray50", x + 12, y + 13, 5, 72)
	box(BLACK, x + 2, y + 12, 16, 74)
	line(BLACK, x + 8, y + 14, x + 8, y + 84)

	-- Spool on top of the tower (spins while printing).
	local spin = st == "PRINTING" and (t / 900) or nil
	Sprites.spool(x + 10, y + 5, 9, opts.spoolFrac or 0.7, opts.color or "BLACK", { spin = spin })

	-- Bed: white textured plate on a black carriage; slides in Y (a small
	-- sideways wobble reads as motion in a front view).
	local bedY = y + 76
	local bedShift = st == "PRINTING" and floor(sin(t / 260) * 2) or 0
	local bx = x + 28 + bedShift
	rect(BLACK, bx + 4, bedY + 5, 56, 3)
	rect(WHITE, bx, bedY, 66, 5)
	box(BLACK, bx, bedY, 66, 5)
	gfx.setColor(BLACK)
	for k = bx + 3, bx + 62, 4 do gfx.drawPixel(k, bedY + 2) end
	line(BLACK, x + 60, bedY + 8, x + 60, y + 86)

	-- The part.
	local partH, partW = 28, 34
	local px = bx + 16
	local shown = progress
	if st == "COMPLETE" then shown = 1 end
	if st == "IDLE" or st == "OFFLINE" then shown = 0 end
	local partTop = bedY
	if shown > 0 and st ~= "ERROR" then
		partTop = Sprites.part(px, bedY - partH, partW, partH, shape, shown, { ghost = false })
	end
	if st == "ERROR" then
		-- Spaghetti: a deterministic tangle where the part used to be.
		local rng = Rng.new(77)
		gfx.setColor(BLACK)
		local lx, ly = px + 17, bedY - 1
		for _ = 1, 30 do
			local nx = U.clamp(lx + rng:int(-7, 7), px - 6, px + partW + 6)
			local ny = U.clamp(ly + rng:int(-5, 3), bedY - 20, bedY - 1)
			gfx.drawLine(lx, ly, nx, ny)
			lx, ly = nx, ny
		end
	end

	-- Gantry rides the layer height.
	local gy
	if st == "PRINTING" or st == "HEATING" then gy = partTop - 28
	elseif st == "PAUSED" then gy = partTop - 40
	else gy = y + 20 end
	gy = U.clamp(gy, y + 18, bedY - 28)
	rect(WHITE, x + 18, gy, 80, 6)
	box(BLACK, x + 18, gy, 80, 6)
	line(BLACK, x + 20, gy + 3, x + 95, gy + 3)

	-- Toolhead.
	local tx
	if st == "PRINTING" then
		local l, r = Sprites.partSpan(shape, progress)
		local cx = px + partW / 2
		local sweep = sin(t / 180) * 0.5 + 0.5
		tx = floor(cx + (l + (r - l) * sweep) * partW / 2) - 9
	elseif st == "COMPLETE" or st == "IDLE" or st == "OFFLINE" then
		tx = x + 78
	else
		tx = px + 8
	end
	tx = U.clamp(tx, x + 20, x + 78)
	local th = gy - 2
	rect(WHITE, tx, th, 18, 22)
	box(BLACK, tx, th, 18, 22)
	rect(BLACK, tx, th, 18, 4)
	gfx.setColor(BLACK)
	gfx.drawCircleAtPoint(tx + 9, th + 12, 4)
	local fa = (st == "PRINTING" or st == "HEATING") and (t / 60) or 0.8
	gfx.drawLine(tx + 9, th + 12, tx + 9 + floor(math.cos(fa) * 3 + 0.5), th + 12 + floor(sin(fa) * 3 + 0.5))
	gfx.fillTriangle(tx + 6, th + 22, tx + 12, th + 22, tx + 9, th + 26)
	-- Filament from the spool into the toolhead.
	gfx.drawLine(x + 18, y + 5, tx + 5, th)

	if st == "PRINTING" then
		if blink then gfx.drawPixel(tx + 9, th + 27) end
	elseif st == "HEATING" then
		local phase = t / 12
		gfx.setColor(BLACK)
		gfx.drawSineWave(bx + 2, bedY - 5, bx + 64, bedY - 5, 1, 1, 10, phase)
		gfx.drawSineWave(bx + 2, bedY - 11, bx + 64, bedY - 11, 1, 1, 12, phase + 4)
		if blink then gfx.fillCircleAtPoint(tx + 9, th + 28, 2) end
	elseif st == "PAUSED" then
		if blink then
			rect(BLACK, x + 42, y + 1, 6, 14)
			rect(BLACK, x + 52, y + 1, 6, 14)
		end
	elseif st == "ERROR" then
		if blink then
			gfx.setColor(BLACK)
			gfx.fillTriangle(x + 50, y - 4, x + 38, y + 16, x + 62, y + 16)
			gfx.setColor(WHITE)
			gfx.fillRect(x + 49, y + 3, 3, 7)
			gfx.fillRect(x + 49, y + 12, 3, 2)
		end
		gfx.setColor(BLACK)
		local s = (t // 90) % 20
		gfx.drawCircleAtPoint(tx + 14, th - 2 - s, 2 + s // 8)
		gfx.drawCircleAtPoint(tx + 4, th - 8 - (s + 10) % 20, 2)
	elseif st == "COMPLETE" then
		local k = (t // 200) % 4
		gfx.setColor(BLACK)
		local spots = { { px - 6, bedY - 18 }, { px + partW + 5, bedY - 24 }, { px + 12, bedY - partH - 6 }, { px + partW + 2, bedY - 6 } }
		for i, p in ipairs(spots) do
			if (i + k) % 2 == 0 then
				gfx.drawLine(p[1] - 3, p[2], p[1] + 3, p[2])
				gfx.drawLine(p[1], p[2] - 3, p[1], p[2] + 3)
			else
				gfx.drawPixel(p[1], p[2])
			end
		end
	elseif st == "IDLE" then
		local s = (t // 60) % 40
		local zx = tx + 16 + floor(sin(t / 400) * 2)
		if s < 30 then Text.draw("z", zx, th - 6 - s // 3, { color = "black" }) end
		if s > 10 then Text.draw("Z", zx + 6, th - 12 - (s - 10) // 3, { color = "black" }) end
	elseif st == "OFFLINE" then
		pat("light25", x, y, 100, 104)
		Text.draw("?", x + 44, y + 36, { color = "black", scale = 3 })
	end
	gfx.setColor(BLACK)
end

---------------------------------------------------------------------------
-- THE BENCHY CAPTAIN

-- Close-up portrait for dialog boxes, 44 x 44.
function Sprites.captainPortrait(x, y, mood, talking, t)
	t = t or Draw.t
	local ink = BLACK
	rect(WHITE, x, y, 44, 44)
	box(BLACK, x, y, 44, 44)
	-- Face.
	gfx.setColor(WHITE)
	gfx.fillCircleAtPoint(x + 22, y + 24, 13)
	gfx.setColor(ink)
	gfx.drawCircleAtPoint(x + 22, y + 24, 13)
	-- Beard: dithered, fills the lower face.
	Draw.pattern("gray50")
	gfx.fillEllipseInRect(x + 9, y + 25, 26, 17)
	gfx.setColor(ink)
	gfx.drawEllipseInRect(x + 9, y + 25, 26, 17)
	-- Hat: black crown, white band with an anchor dot, peak.
	rect(ink, x + 8, y + 4, 28, 10)
	rect(ink, x + 5, y + 13, 34, 3)
	rect(WHITE, x + 8, y + 9, 28, 2)
	gfx.setColor(WHITE)
	gfx.fillCircleAtPoint(x + 22, y + 7, 2)
	-- Eyes (blink every ~4s) and brows by mood.
	gfx.setColor(ink)
	local blinking = (t % 4000) < 140
	if blinking then
		gfx.drawLine(x + 16, y + 21, x + 19, y + 21)
		gfx.drawLine(x + 25, y + 21, x + 28, y + 21)
	else
		gfx.fillRect(x + 17, y + 20, 2, 3)
		gfx.fillRect(x + 26, y + 20, 2, 3)
	end
	if mood == "worried" then
		gfx.drawLine(x + 15, y + 18, x + 19, y + 17)
		gfx.drawLine(x + 25, y + 17, x + 29, y + 18)
	elseif mood == "stern" then
		gfx.drawLine(x + 15, y + 17, x + 19, y + 19)
		gfx.drawLine(x + 25, y + 19, x + 29, y + 17)
	else
		gfx.drawLine(x + 15, y + 18, x + 19, y + 18)
		gfx.drawLine(x + 25, y + 18, x + 29, y + 18)
	end
	-- Nose.
	gfx.setColor(WHITE)
	gfx.fillCircleAtPoint(x + 22, y + 26, 3)
	gfx.setColor(ink)
	gfx.drawCircleAtPoint(x + 22, y + 26, 3)
	-- Mouth: opens and closes while talking.
	local open = talking and ((t // 110) % 2 == 0)
	gfx.setColor(WHITE)
	if open then
		gfx.fillRect(x + 18, y + 31, 8, 5)
		gfx.setColor(ink)
		gfx.drawRect(x + 18, y + 31, 8, 5)
	elseif mood == "happy" then
		gfx.fillRect(x + 17, y + 31, 10, 3)
		gfx.setColor(ink)
		gfx.drawLine(x + 17, y + 31, x + 19, y + 33)
		gfx.drawLine(x + 19, y + 33, x + 25, y + 33)
		gfx.drawLine(x + 25, y + 33, x + 27, y + 31)
	elseif mood == "worried" then
		gfx.fillRect(x + 17, y + 31, 10, 3)
		gfx.setColor(ink)
		gfx.drawLine(x + 17, y + 33, x + 20, y + 31)
		gfx.drawLine(x + 20, y + 31, x + 24, y + 33)
		gfx.drawLine(x + 24, y + 33, x + 27, y + 31)
	else
		gfx.fillRect(x + 18, y + 31, 8, 3)
		gfx.setColor(ink)
		gfx.drawLine(x + 18, y + 32, x + 26, y + 32)
	end
	gfx.setColor(BLACK)
end

-- 3DBenchy hull + cabin + the Captain on deck. ~96 x 64, bobbing.
function Sprites.benchy(x, y, t, opts)
	opts = opts or {}
	local bob = floor(sin(t / 420) * 2 + 0.5)
	local tilt = floor(sin(t / 700) * 1.5 + 0.5)
	y = y + bob
	gfx.setColor(BLACK)
	-- Hull polygon (bow on the right).
	gfx.setColor(WHITE)
	gfx.fillPolygon(x + 2, y + 38 - tilt, x + 90, y + 32 + tilt, x + 80, y + 56, x + 12, y + 56)
	gfx.setColor(BLACK)
	gfx.drawPolygon(x + 2, y + 38 - tilt, x + 90, y + 32 + tilt, x + 80, y + 56, x + 12, y + 56)
	pat("hlines", x + 14, y + 46, 62, 8)
	-- Portholes.
	gfx.setColor(BLACK)
	gfx.drawCircleAtPoint(x + 30, y + 44, 2)
	gfx.drawCircleAtPoint(x + 44, y + 44, 2)
	gfx.drawCircleAtPoint(x + 58, y + 43, 2)
	-- Cabin.
	rect(WHITE, x + 12, y + 14, 34, 22)
	box(BLACK, x + 12, y + 14, 34, 22)
	rect(BLACK, x + 10, y + 12, 38, 3)
	rect(BLACK, x + 17, y + 19, 9, 8)
	rect(BLACK, x + 31, y + 19, 9, 8)
	gfx.setColor(WHITE)
	gfx.drawLine(x + 18, y + 20, x + 21, y + 20)
	gfx.drawLine(x + 32, y + 20, x + 35, y + 20)
	-- Chimney with smoke.
	rect(WHITE, x + 16, y + 2, 8, 10)
	box(BLACK, x + 16, y + 2, 8, 10)
	rect(BLACK, x + 15, y + 1, 10, 2)
	local s = (t // 120) % 16
	gfx.setColor(BLACK)
	gfx.drawCircleAtPoint(x + 20 - s // 3, y - 4 - s, 2 + s // 6)

	-- The Captain on the foredeck.
	local cx, cy = x + 64, y + 10
	gfx.setColor(WHITE)
	gfx.fillCircleAtPoint(cx, cy + 10, 7)
	gfx.setColor(BLACK)
	gfx.drawCircleAtPoint(cx, cy + 10, 7)
	Draw.pattern("gray50")
	gfx.fillEllipseInRect(cx - 7, cy + 11, 14, 10)
	gfx.setColor(BLACK)
	rect(BLACK, cx - 6, cy, 12, 5)
	rect(BLACK, cx - 8, cy + 4, 16, 2)
	gfx.fillRect(cx - 3, cy + 8, 2, 2)
	gfx.fillRect(cx + 2, cy + 8, 2, 2)
	-- Coat.
	rect(BLACK, cx - 6, cy + 18, 12, 12)
	gfx.setColor(WHITE)
	gfx.drawLine(cx, cy + 19, cx, cy + 29)
	gfx.fillRect(cx - 3, cy + 21, 1, 1)
	gfx.fillRect(cx - 3, cy + 25, 1, 1)
	-- Waving arm when talking or celebrating.
	gfx.setColor(BLACK)
	if opts.talking or opts.mood == "happy" then
		local wave = (t // 200) % 2
		gfx.drawLine(cx + 6, cy + 20, cx + 12, cy + 12 - wave * 3)
		gfx.drawLine(cx + 7, cy + 20, cx + 13, cy + 12 - wave * 3)
	else
		gfx.drawLine(cx + 6, cy + 20, cx + 10, cy + 28)
	end
	-- Flag on the bow.
	gfx.drawLine(x + 86, y + 32 + tilt, x + 86, y + 18)
	local f = (t // 250) % 2
	gfx.fillTriangle(x + 86, y + 18, x + 96, y + 21 + f, x + 86, y + 24)
end

-- Rolling sea strip.
function Sprites.sea(x, y, w, h, t)
	gfx.setColor(WHITE)
	gfx.fillRect(x, y, w, h)
	gfx.setColor(BLACK)
	local phase = t / 300
	gfx.drawSineWave(x, y + 3, x + w, y + 3, 2, 2, 28, phase * 8)
	gfx.drawSineWave(x, y + 10, x + w, y + 10, 2, 2, 36, -phase * 6)
	pat("water", x, y + 14, w, h - 14)
	gfx.setColor(BLACK)
end

---------------------------------------------------------------------------
-- workshop station icons, 28 x 28

local ICONS = {}

ICONS.watch = function(x, y)
	box(BLACK, x + 2, y + 3, 24, 18)
	rect(BLACK, x + 10, y + 21, 8, 3)
	rect(BLACK, x + 6, y + 24, 16, 2)
	gfx.setColor(BLACK)
	gfx.drawLine(x + 5, y + 16, x + 10, y + 11)
	gfx.drawLine(x + 10, y + 11, x + 14, y + 14)
	gfx.drawLine(x + 14, y + 14, x + 22, y + 6)
end

ICONS.queue = function(x, y)
	box(BLACK, x + 4, y + 3, 20, 23)
	rect(BLACK, x + 10, y + 1, 8, 4)
	for i = 0, 3 do
		rect(BLACK, x + 7, y + 8 + i * 4, 2, 2)
		gfx.drawLine(x + 11, y + 9 + i * 4, x + 20, y + 9 + i * 4)
	end
end

ICONS.rolodex = function(x, y)
	gfx.setColor(BLACK)
	gfx.drawCircleAtPoint(x + 8, y + 22, 3)
	gfx.drawCircleAtPoint(x + 20, y + 22, 3)
	gfx.drawLine(x + 8, y + 22, x + 20, y + 22)
	rect(WHITE, x + 3, y + 4, 22, 14)
	box(BLACK, x + 3, y + 4, 22, 14)
	box(BLACK, x + 5, y + 2, 18, 3)
	gfx.drawLine(x + 6, y + 9, x + 20, y + 9)
	gfx.drawLine(x + 6, y + 13, x + 16, y + 13)
end

ICONS.calibrate = function(x, y)
	gfx.setColor(BLACK)
	gfx.drawCircleAtPoint(x + 14, y + 15, 11)
	for i = 0, 7 do
		local a = i * math.pi / 4
		gfx.drawLine(x + 14 + floor(math.cos(a) * 8), y + 15 + floor(math.sin(a) * 8),
			x + 14 + floor(math.cos(a) * 11), y + 15 + floor(math.sin(a) * 11))
	end
	gfx.fillCircleAtPoint(x + 14, y + 15, 3)
	gfx.drawLine(x + 14, y + 15, x + 20, y + 8)
end

ICONS.maint = function(x, y)
	gfx.setColor(BLACK)
	gfx.setLineWidth(3)
	gfx.drawLine(x + 7, y + 22, x + 19, y + 9)
	gfx.setLineWidth(1)
	gfx.fillCircleAtPoint(x + 21, y + 7, 5)
	gfx.setColor(WHITE)
	gfx.fillRect(x + 20, y + 2, 3, 5)
	gfx.setColor(BLACK)
	gfx.fillCircleAtPoint(x + 6, y + 23, 3)
end

ICONS.captain = function(x, y)
	gfx.setColor(BLACK)
	gfx.drawCircleAtPoint(x + 14, y + 14, 10)
	gfx.drawCircleAtPoint(x + 14, y + 14, 4)
	for i = 0, 7 do
		local a = i * math.pi / 4
		gfx.drawLine(x + 14 + floor(math.cos(a) * 4), y + 14 + floor(math.sin(a) * 4),
			x + 14 + floor(math.cos(a) * 13), y + 14 + floor(math.sin(a) * 13))
	end
end

ICONS.stats = function(x, y)
	rect(BLACK, x + 4, y + 16, 4, 9)
	rect(BLACK, x + 10, y + 9, 4, 16)
	rect(BLACK, x + 16, y + 13, 4, 12)
	rect(BLACK, x + 22, y + 4, 4, 21)
	gfx.drawLine(x + 2, y + 25, x + 27, y + 25)
end

ICONS.settings = function(x, y)
	gfx.setColor(BLACK)
	for i = 0, 5 do
		local a = i * math.pi / 3
		gfx.fillCircleAtPoint(x + 14 + floor(math.cos(a) * 9), y + 14 + floor(math.sin(a) * 9), 3)
	end
	gfx.fillCircleAtPoint(x + 14, y + 14, 8)
	gfx.setColor(WHITE)
	gfx.fillCircleAtPoint(x + 14, y + 14, 3)
	gfx.setColor(BLACK)
end

function Sprites.icon(name, x, y, inverted)
	local fn = ICONS[name]
	if fn == nil then return end
	if inverted then
		rect(BLACK, x - 2, y - 2, 32, 32)
		rect(WHITE, x, y, 28, 28)
	end
	fn(x, y)
	gfx.setColor(BLACK)
end

---------------------------------------------------------------------------
-- calibration test pieces

-- Temperature / retraction tower: floors stacked top to bottom as `labels`.
function Sprites.tower(x, y, w, labels, sel, floorH)
	floorH = floorH or 14
	local n = #labels
	for i = 1, n do
		local fy = y + (i - 1) * floorH
		local selected = i == sel
		rect(selected and BLACK or WHITE, x, fy, w, floorH - 2)
		box(BLACK, x, fy, w, floorH - 2)
		-- Bridge notch and overhang on each floor.
		rect(selected and WHITE or BLACK, x + w // 2 - 6, fy + floorH - 6, 12, 4)
		if not selected then pat("light25", x + 2, fy + 2, w // 3, floorH - 6) end
		Text.draw(labels[i], x + w + 8, fy + (floorH - 11) // 2 + 1, { color = "black" })
	end
	-- Base plate.
	rect(BLACK, x - 6, y + n * floorH - 1, w + 12, 3)
end

-- Flow test: blocks in a grid, labels underneath.
function Sprites.flowGrid(x, y, labels, sel, cols)
	cols = cols or 5
	local bw, bh = 44, 30
	for i, lab in ipairs(labels) do
		local c = (i - 1) % cols
		local r = (i - 1) // cols
		local bx = x + c * (bw + 6)
		local by = y + r * (bh + 16)
		local selected = i == sel
		rect(WHITE, bx, by, bw, bh)
		-- Surface texture: rougher toward the extremes.
		local rough = math.abs(i - (#labels + 1) / 2) / (#labels / 2)
		if rough > 0.66 then pat("gray50", bx + 2, by + 2, bw - 4, bh - 4)
		elseif rough > 0.33 then pat("light25", bx + 2, by + 2, bw - 4, bh - 4)
		else pat("light12", bx + 2, by + 2, bw - 4, bh - 4) end
		box(BLACK, bx, by, bw, bh)
		if selected then
			gfx.setColor(BLACK)
			gfx.drawRect(bx - 3, by - 3, bw + 6, bh + 6)
			gfx.drawRect(bx - 2, by - 2, bw + 4, bh + 4)
		end
		Text.draw(lab, bx + bw // 2, by + bh + 3, { color = "black", align = "center" })
	end
end
