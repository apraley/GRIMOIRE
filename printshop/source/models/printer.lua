-- Printer model. A printer record is the shop's knowledge of a machine; the
-- live connection to it is a provider (providers/*.lua) named by `provider`.

Printer = {}

Printer.DEFAULTS = {
	name = "A1 MINI",
	model = "BAMBU LAB A1 MINI",
	provider = "demo",
	nozzle = 0.4,
	bedX = 180, bedY = 180, bedZ = 180,
	serial = "",
	host = "",          -- bridge host, e.g. "192.168.1.50"
	port = 8787,
	firmware = "",
	stats = {},
}

Printer.STATS_DEFAULTS = {
	prints = 0,
	successes = 0,
	failures = 0,
	printSeconds = 0,
	grams = 0,
	lastPrintAt = 0,
	streak = 0,        -- consecutive successes (negative = consecutive failures)
}

function Printer.new(fields)
	local p = U.copy(fields or {})
	return Printer.normalize(p)
end

function Printer.normalize(p)
	U.defaults(p, Printer.DEFAULTS)
	p.id = U.str(p.id, nil)
	p.name = U.str(p.name, "PRINTER")
	p.provider = U.oneOf(p.provider, Enums.PROVIDERS, "demo")
	p.nozzle = U.num(p.nozzle, 0.4)
	p.port = U.int(p.port, 8787)
	p.host = U.str(p.host, "")
	p.serial = U.str(p.serial, "")
	if type(p.stats) ~= "table" then p.stats = {} end
	U.defaults(p.stats, Printer.STATS_DEFAULTS)
	for k in pairs(Printer.STATS_DEFAULTS) do
		p.stats[k] = U.num(p.stats[k], 0)
	end
	return p
end

function Printer.hours(p)
	return p.stats.printSeconds / 3600
end

function Printer.successRate(p)
	local n = p.stats.successes + p.stats.failures
	if n == 0 then return nil end
	return p.stats.successes / n
end

-- Short tag used in calibration keys: "p1" stays "p1"; keys are stable ids.
function Printer.key(p)
	return p.id
end
