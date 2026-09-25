-- Tiny publish/subscribe bus. Services announce domain events here
-- ("print.completed", "spool.low", ...) and other services react, which keeps
-- the six tools interconnected without them importing each other's internals.

Events = {
	handlers = {},
	history = {},   -- recent events, newest last (for debugging and tests)
}

function Events.on(name, fn)
	local list = Events.handlers[name]
	if list == nil then
		list = {}
		Events.handlers[name] = list
	end
	list[#list + 1] = fn
	return fn
end

function Events.off(name, fn)
	local list = Events.handlers[name]
	if list == nil then return end
	for i = #list, 1, -1 do
		if list[i] == fn then table.remove(list, i) end
	end
end

function Events.emit(name, payload)
	payload = payload or {}
	local h = Events.history
	h[#h + 1] = { name = name, payload = payload }
	if #h > 64 then table.remove(h, 1) end
	local list = Events.handlers[name]
	if list == nil then return end
	-- Copy so handlers can unsubscribe while we iterate.
	local snapshot = {}
	for i, fn in ipairs(list) do snapshot[i] = fn end
	for _, fn in ipairs(snapshot) do fn(payload) end
end

function Events.reset()
	Events.handlers = {}
	Events.history = {}
end
