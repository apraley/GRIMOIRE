-- A small 1-bit software rasterizer that replaces the mock's no-op drawing
-- calls, so tests/shots.lua can save real screenshots of every screen
-- without the Playdate Simulator. It follows the SDK's documented semantics
-- for colours, 8x8 patterns (bit set = white, optional alpha mask rows),
-- image contexts and the Copy / FillWhite draw modes that PRINT SHOP uses.
-- Pixel-exactness with the device is not the goal; layout review is.

local gfx = playdate.graphics
local floor = math.floor

Raster = {}

local W, H = 400, 240
local screen = { w = W, h = H, px = {} }
local target = screen
local stack = {}
local color = 0           -- 0 black, 1 white, 2 clear
local pattern = nil       -- { rows[8], mask[8] or nil }
local drawMode = 0        -- 0 copy, 1 fillWhite
local lineWidth = 1

local BLACK, WHITE, CLEAR = gfx.kColorBlack, gfx.kColorWhite, gfx.kColorClear

local function clearBuf(buf, v)
	local n = buf.w * buf.h
	for i = 1, n do buf.px[i] = v end
end
clearBuf(screen, 1)

local function band(a, b) return a & b end

-- Plot one pixel with the current colour/pattern into the target.
local function plot(x, y)
	x, y = floor(x), floor(y)
	if x < 0 or y < 0 or x >= target.w or y >= target.h then return end
	local v
	if pattern then
		local row = pattern[(y % 8) + 1]
		local bit = (row >> (7 - (x % 8))) & 1
		if pattern.mask then
			local m = (pattern.mask[(y % 8) + 1] >> (7 - (x % 8))) & 1
			if m == 0 then return end
		end
		v = bit
	else
		if color == 2 then v = nil
		elseif color == 3 then
			local cur = target.px[y * target.w + x + 1]
			v = (cur == 0) and 1 or 0
		else v = color end
	end
	target.px[y * target.w + x + 1] = v
end

local function hspan(x1, x2, y)
	if x2 < x1 then x1, x2 = x2, x1 end
	for x = floor(x1), floor(x2) do plot(x, y) end
end

local function toColor(c)
	if c == BLACK then return 0 elseif c == WHITE then return 1 elseif c == CLEAR then return 2 end
	return 3
end

local function set(name, fn) rawset(gfx, name, fn) end

set("setColor", function(c) color = toColor(c) pattern = nil end)
set("setPattern", function(p)
	pattern = { p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8] }
	if #p >= 16 then pattern.mask = { p[9], p[10], p[11], p[12], p[13], p[14], p[15], p[16] } end
end)
set("setDitherPattern", function(alpha)
	local lvl = floor((alpha or 0.5) * 4 + 0.5)
	local pats = { { 0xFF, 0xFF }, { 0xDD, 0x77 }, { 0xAA, 0x55 }, { 0x22, 0x88 }, { 0, 0 } }
	local p = pats[lvl + 1] or pats[3]
	pattern = { p[1], p[2], p[1], p[2], p[1], p[2], p[1], p[2] }
end)
set("setImageDrawMode", function(m) drawMode = (m == gfx.kDrawModeFillWhite) and 1 or 0 end)
set("setLineWidth", function(w) lineWidth = w or 1 end)
set("setBackgroundColor", function() end)
set("clear", function(c)
	clearBuf(target, c == BLACK and 0 or (c == CLEAR and nil or 1))
end)

set("fillRect", function(x, y, w, h)
	for yy = floor(y), floor(y + h - 1) do hspan(x, x + w - 1, yy) end
end)
set("drawRect", function(x, y, w, h)
	if w <= 0 or h <= 0 then return end
	hspan(x, x + w - 1, y)
	hspan(x, x + w - 1, y + h - 1)
	for yy = floor(y), floor(y + h - 1) do plot(x, yy) plot(x + w - 1, yy) end
end)
set("drawPixel", function(x, y) plot(x, y) end)

local function line(x1, y1, x2, y2)
	x1, y1, x2, y2 = floor(x1), floor(y1), floor(x2), floor(y2)
	local dx, dy = math.abs(x2 - x1), -math.abs(y2 - y1)
	local sx, sy = x1 < x2 and 1 or -1, y1 < y2 and 1 or -1
	local err = dx + dy
	local half = floor((lineWidth - 1) / 2)
	while true do
		if lineWidth <= 1 then plot(x1, y1)
		else
			for oy = -half, lineWidth - 1 - half do
				for ox = -half, lineWidth - 1 - half do plot(x1 + ox, y1 + oy) end
			end
		end
		if x1 == x2 and y1 == y2 then break end
		local e2 = 2 * err
		if e2 >= dy then err = err + dy x1 = x1 + sx end
		if e2 <= dx then err = err + dx y1 = y1 + sy end
	end
end
set("drawLine", line)

local function fillPoly(pts)
	local minY, maxY = math.huge, -math.huge
	for i = 2, #pts, 2 do
		minY = math.min(minY, pts[i])
		maxY = math.max(maxY, pts[i])
	end
	local n = #pts // 2
	for y = floor(minY), floor(maxY) do
		local yc = y + 0.5
		local xs = {}
		for i = 1, n do
			local j = i % n + 1
			local ax, ay = pts[i * 2 - 1], pts[i * 2]
			local bx, by = pts[j * 2 - 1], pts[j * 2]
			if (ay <= yc and by > yc) or (by <= yc and ay > yc) then
				xs[#xs + 1] = ax + (yc - ay) * (bx - ax) / (by - ay)
			end
		end
		table.sort(xs)
		for k = 1, #xs - 1, 2 do hspan(math.ceil(xs[k] - 0.5), math.floor(xs[k + 1] - 0.5), y) end
	end
end
set("fillPolygon", function(...) fillPoly({ ... }) end)
set("drawPolygon", function(...)
	local p = { ... }
	local n = #p // 2
	for i = 1, n do
		local j = i % n + 1
		line(p[i * 2 - 1], p[i * 2], p[j * 2 - 1], p[j * 2])
	end
end)
set("fillTriangle", function(x1, y1, x2, y2, x3, y3)
	fillPoly({ x1, y1, x2, y2, x3, y3 })
	line(x1, y1, x2, y2) line(x2, y2, x3, y3) line(x3, y3, x1, y1)
end)

set("fillCircleAtPoint", function(cx, cy, r)
	for y = -r, r do
		local w = math.sqrt(math.max(0, r * r - y * y))
		hspan(cx - floor(w + 0.5), cx + floor(w + 0.5), cy + y)
	end
end)
set("drawCircleAtPoint", function(cx, cy, r)
	local steps = math.max(16, floor(r * 8))
	for i = 0, steps do
		local a = i / steps * 2 * math.pi
		plot(cx + floor(math.cos(a) * r + 0.5), cy + floor(math.sin(a) * r + 0.5))
	end
end)
set("fillEllipseInRect", function(x, y, w, h)
	local cx, cy, rx, ry = x + w / 2, y + h / 2, w / 2, h / 2
	for yy = floor(y), floor(y + h - 1) do
		local t = (yy + 0.5 - cy) / ry
		if math.abs(t) <= 1 then
			local hw = rx * math.sqrt(1 - t * t)
			hspan(floor(cx - hw + 0.5), floor(cx + hw - 0.5), yy)
		end
	end
end)
set("drawEllipseInRect", function(x, y, w, h)
	local cx, cy, rx, ry = x + w / 2, y + h / 2, w / 2 - 0.5, h / 2 - 0.5
	for i = 0, 120 do
		local a = i / 120 * 2 * math.pi
		plot(floor(cx + math.cos(a) * rx), floor(cy + math.sin(a) * ry))
	end
end)
set("drawSineWave", function(x1, y1, x2, y2, a1, a2, period, phase)
	for x = floor(x1), floor(x2) do
		local t = (x - x1) / math.max(1, x2 - x1)
		local a = a1 + (a2 - a1) * t
		local y = y1 + (y2 - y1) * t + math.sin(((x - x1) + (phase or 0)) / period * 2 * math.pi) * a
		plot(x, floor(y + 0.5))
	end
end)

-- images ------------------------------------------------------------------

local function newImage(w, h, bg)
	local img, methods = MOCK.object("playdate.graphics.image", { w = w, h = h, px = {} })
	local v = 1
	if bg == BLACK then v = 0 elseif bg == CLEAR then v = nil end
	if bg == nil then v = nil end
	clearBuf(img, v)
	methods.getSize = function(self) return self.w, self.h end
	local function blit(self, x, y, scale)
		scale = scale or 1
		x, y = floor(x), floor(y)
		local saveColor, savePattern = color, pattern
		pattern = nil
		for yy = 0, self.h - 1 do
			for xx = 0, self.w - 1 do
				local p = self.px[yy * self.w + xx + 1]
				if p ~= nil then
					if drawMode == 1 then color = 1 else color = p end
					for sy = 0, scale - 1 do
						for sx = 0, scale - 1 do plot(x + xx * scale + sx, y + yy * scale + sy) end
					end
				end
			end
		end
		color, pattern = saveColor, savePattern
	end
	methods.draw = function(self, x, y) blit(self, x, y, 1) end
	methods.drawScaled = function(self, x, y, s) blit(self, x, y, floor(s)) end
	return img
end
rawset(gfx.image, "new", function(w, h, bg)
	if type(w) == "string" then return nil end
	return newImage(floor(w), floor(h), bg)
end)
set("pushContext", function(img)
	stack[#stack + 1] = { target, color, pattern, drawMode }
	target = img or screen
end)
set("popContext", function()
	local s = table.remove(stack)
	target, color, pattern, drawMode = s[1], s[2], s[3], s[4]
end)

-- output ------------------------------------------------------------------

-- Writes the screen as a plain PBM (P1) file.
function Raster.save(path)
	local f = assert(io.open(path, "w"))
	f:write("P1\n400 240\n")
	local out = {}
	for y = 0, H - 1 do
		local row = {}
		for x = 0, W - 1 do
			row[#row + 1] = screen.px[y * W + x + 1] == 0 and "1" or "0"
		end
		out[#out + 1] = table.concat(row, " ")
	end
	f:write(table.concat(out, "\n"))
	f:close()
end

-- Glyph images were built before the rasterizer loaded: rebuild them.
function Raster.rebuildText()
	Text.glyphs = {}
	Text.cache = {}
	Text.cacheCount = 0
	Text.init()
	Sprites.partCache = {}
	Sprites.partCacheCount = 0
end
