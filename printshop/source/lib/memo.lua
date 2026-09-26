-- Revision-keyed memoization for derived data.
--
-- Screens redraw every frame, and several aggregates (stats over history,
-- due chores, low spools, backlog) would otherwise be recomputed 30 times a
-- second. Store.markDirty() bumps the revision, which invalidates
-- everything; so does the passage of a minute (App bumps it), which covers
-- time-based values like "due in N days".
--
-- Memoized functions return shared tables: callers must treat results as
-- read-only.

Memo = { rev = 0, cache = {}, hits = 0, misses = 0 }

function Memo.bump()
	Memo.rev = Memo.rev + 1
	Memo.cache = {}
end

local function keyOf(name, ...)
	local key = name
	for i = 1, select("#", ...) do
		local a = select(i, ...)
		if type(a) == "table" then a = a.id or tostring(a) end
		key = key .. "|" .. tostring(a)
	end
	return key
end

-- Replaces tbl[name] with a memoized version keyed by its arguments.
function Memo.wrap(tbl, name, label)
	local fn = tbl[name]
	label = label or name
	tbl[name] = function(...)
		local key = keyOf(label, ...)
		local e = Memo.cache[key]
		if e == nil then
			Memo.misses = Memo.misses + 1
			e = table.pack(fn(...))
			Memo.cache[key] = e
		else
			Memo.hits = Memo.hits + 1
		end
		return table.unpack(e, 1, e.n)
	end
end
