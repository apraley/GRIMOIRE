-- Deterministic pseudo-random numbers.
--
-- The Benchy Captain and the demo printer must be reproducible: the same shop
-- state on the same day produces the same remark. We avoid math.random (global
-- state) and keep every intermediate product below 2^31, so this is exact on
-- any Lua number configuration, including 32-bit integer builds.

Rng = {}
Rng.__index = Rng

function Rng.new(seed)
	local r = setmetatable({}, Rng)
	r:seed(seed or 1)
	return r
end

function Rng:seed(seed)
	seed = math.floor(math.abs(tonumber(seed) or 1)) % 65536
	self.a = seed
	self.b = (seed * 7 + 12345) % 65536
	if self.b == 0 then self.b = 1 end
	-- Warm up so nearby seeds diverge quickly.
	for _ = 1, 4 do self:next() end
end

-- Two 16-bit LCGs combined; period is long enough for dialogue and demo noise.
function Rng:next()
	self.a = (self.a * 25173 + 13849) % 65536
	self.b = (self.b * 22695 + 1) % 65536
	return ((self.a + self.b * 3) % 65536) / 65536
end

-- Integer in [lo, hi].
function Rng:int(lo, hi)
	if hi < lo then lo, hi = hi, lo end
	return lo + math.floor(self:next() * (hi - lo + 1))
end

function Rng:pick(list)
	if list == nil or #list == 0 then return nil end
	return list[self:int(1, #list)]
end

function Rng:chance(p)
	return self:next() < p
end

-- items: list of { weight = n, ... }
function Rng:weighted(items)
	local total = 0
	for _, it in ipairs(items) do total = total + math.max(0, it.weight or 0) end
	if total <= 0 then return items[1] end
	local roll = self:next() * total
	for _, it in ipairs(items) do
		roll = roll - math.max(0, it.weight or 0)
		if roll < 0 then return it end
	end
	return items[#items]
end
