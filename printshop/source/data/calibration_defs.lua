-- CALIBRATION WIZARD procedures.
--
-- PRINT SHOP never calibrates the printer by itself: each procedure is a
-- guided checklist around a test print you slice and run, with the crank used
-- to dial in what you observed. The computed values are stored on a profile
-- (printer + material + manufacturer) and become the recommended settings for
-- future queue entries.
--
-- Step types (see screens/calib_run.lua):
--   info     text page
--   check    checklist; every item must be ticked (or explicitly skipped)
--   dial     crank-adjusted number -> results[field]
--   pick     crank selects one candidate from a drawn test piece -> results[field]
--   measure  dial with a nominal target and live error readout -> results[field]
--   summary  shows computed profile changes; A saves
--
-- `default(ctx)` and `values(ctx)` receive ctx = { profile, material,
-- manufacturer, info (Enums.MATERIAL_INFO row), printer }.

CalibDefs = {}

local function prof(ctx, field, fallback)
	local v = ctx.profile and ctx.profile[field]
	if v == nil then return fallback end
	if v == 0 and (field == "nozzleTemp" or field == "bedTemp") then return fallback end
	-- Scales and flow can never be zero or negative: treat as unset.
	if v <= 0 and (field == "xyScale" or field == "zScale" or field == "flowRatio") then return fallback end
	return v
end

local function range(a, b, step)
	local out = {}
	local v = a
	while v <= b + step / 1000 do
		out[#out + 1] = U.round(v, 3)
		v = v + step
	end
	return out
end

CalibDefs.list = {
	{
		id = "bedlevel",
		title = "BED LEVELING",
		short = "BED LEVEL",
		blurb = "Checklist before trusting the auto-level mesh.",
		steps = {
			{ type = "info", title = "BEFORE WE BEGIN",
				text = "The A1 Mini levels itself with its nozzle load cell. This checklist makes sure the mesh it measures is a clean one. Heat the bed to your usual temperature first." },
			{ type = "check", title = "PREP THE BED", items = {
				"Plate seated on all four corners",
				"Plate cleaned with dish soap, dried",
				"No blobs stuck to the nozzle tip",
				"Nothing on the bed or under the plate",
				"Bed at printing temperature",
			} },
			{ type = "check", title = "RUN THE PRINTER", items = {
				"Printer: Calibration > Bed leveling",
				"Leveling finished without errors",
				"Mesh looks smooth (no single spikes)",
			} },
			{ type = "dial", title = "RATE THE MESH", field = "meshRating", label = "MESH QUALITY",
				min = 1, max = 5, step = 1, fmt = "%d", unit = "/5",
				labels = { "SPIKY", "LUMPY", "OKAY", "GOOD", "FLAT" },
				default = function() return 4 end,
				hint = "How flat did the mesh look?" },
			{ type = "summary" },
		},
		compute = function(r, ctx)
			return { bedLeveled = (r.meshRating or 0) >= 3 }
		end,
	},
	{
		id = "flow",
		title = "FLOW CALIBRATION",
		short = "FLOW",
		blurb = "Two-pass flow ratio test.",
		steps = {
			{ type = "info", title = "FLOW TEST",
				text = "Slice a flow-rate test (pass 1: blocks from -20 to +20 percent). Print it with your current flow ratio, then look for the block with the smoothest top surface and no gaps." },
			{ type = "dial", title = "CURRENT FLOW", field = "baseFlow", label = "FLOW RATIO",
				min = 0.80, max = 1.20, step = 0.01, fmt = "%.2f", unit = "",
				default = function(ctx) return prof(ctx, "flowRatio", 0.98) end,
				hint = "The ratio you printed pass 1 with." },
			{ type = "pick", title = "PASS 1: BEST BLOCK", field = "pass1", label = "MODIFIER",
				style = "grid", fmt = "%+d", unit = "%",
				values = function() return range(-20, 20, 5) end,
				default = function() return 0 end,
				hint = "Crank to the smoothest block." },
			{ type = "info", title = "PASS 2",
				text = "Now print pass 2 (fine blocks from -9 to 0) using the pass 1 result. Pick the smoothest again." },
			{ type = "pick", title = "PASS 2: BEST BLOCK", field = "pass2", label = "MODIFIER",
				style = "grid", fmt = "%+d", unit = "%",
				values = function() return range(-9, 0, 1) end,
				default = function() return -4 end,
				hint = "Crank to the smoothest block." },
			{ type = "summary" },
		},
		compute = function(r, ctx)
			local base = r.baseFlow or prof(ctx, "flowRatio", 0.98)
			local f1 = base * (100 + (r.pass1 or 0)) / 100
			local f2 = f1 * (100 + (r.pass2 or 0)) / 100
			return { flowRatio = U.round(U.clamp(f2, 0.7, 1.3), 2) }
		end,
	},
	{
		id = "temptower",
		title = "TEMPERATURE TOWER",
		short = "TEMP TOWER",
		blurb = "Find the nozzle temperature this spool likes.",
		steps = {
			{ type = "info", title = "TEMP TOWER",
				text = "Print a temperature tower spanning this material's range, hottest at the bottom. Look at bridges, overhangs and stringing on every floor." },
			{ type = "pick", title = "BEST FLOOR", field = "nozzleTemp", label = "NOZZLE",
				style = "tower", fmt = "%d", unit = "C",
				values = function(ctx)
					local out = {}
					for t = ctx.info.nozzleMax, ctx.info.nozzleMin, -5 do out[#out + 1] = t end
					return out
				end,
				default = function(ctx) return prof(ctx, "nozzleTemp", ctx.info.nozzle) end,
				hint = "Crank up and down the tower." },
			{ type = "dial", title = "FINE TUNE", field = "nozzleFine", label = "NOZZLE TEMP",
				min = 170, max = 300, step = 1, fmt = "%d", unit = "C",
				default = function(ctx, r) return r.nozzleTemp or ctx.info.nozzle end,
				hint = "Split the difference between floors." },
			{ type = "dial", title = "BED TEMP", field = "bedTemp", label = "BED TEMP",
				min = 0, max = 110, step = 5, fmt = "%d", unit = "C",
				default = function(ctx) return prof(ctx, "bedTemp", ctx.info.bed) end,
				hint = "Keep it unless the tower lifted." },
			{ type = "summary" },
		},
		compute = function(r, ctx)
			return { nozzleTemp = r.nozzleFine or r.nozzleTemp, bedTemp = r.bedTemp }
		end,
	},
	{
		id = "retraction",
		title = "RETRACTION TEST",
		short = "RETRACTION",
		blurb = "Tame stringing with retraction length and speed.",
		steps = {
			{ type = "info", title = "RETRACTION TOWER",
				text = "Print a retraction tower from 0.0 to 2.0 mm in 0.2 mm steps (direct drive). Dry the spool first: wet filament strings no matter what." },
			{ type = "check", title = "BEFORE PRINTING", items = {
				"Spool dried or known dry",
				"Nozzle temp set from calibration",
				"Two thin towers on the plate",
			} },
			{ type = "pick", title = "CLEANEST FLOOR", field = "retractLength", label = "LENGTH",
				style = "tower", fmt = "%.1f", unit = "mm",
				values = function() return range(0, 2.0, 0.2) end,
				default = function(ctx) return prof(ctx, "retractLength", ctx.info.retract) end,
				hint = "Lowest floor with no strings." },
			{ type = "dial", title = "RETRACT SPEED", field = "retractSpeed", label = "SPEED",
				min = 10, max = 70, step = 5, fmt = "%d", unit = "mm/s",
				default = function(ctx) return prof(ctx, "retractSpeed", 30) end,
				hint = "TPU likes slow. PLA does not care." },
			{ type = "summary" },
		},
		compute = function(r)
			return { retractLength = r.retractLength, retractSpeed = r.retractSpeed }
		end,
	},
	{
		id = "dimension",
		title = "DIMENSIONAL ACCURACY",
		short = "DIMENSIONS",
		blurb = "Measure a 20mm cube; compute XY and Z scale.",
		steps = {
			{ type = "info", title = "XYZ CUBE",
				text = "Print a 20 mm calibration cube with 3 walls. Let it cool, then measure each axis with calipers at mid height, away from the seam." },
			{ type = "measure", title = "MEASURE X", field = "x", label = "X", target = 20.0,
				min = 19.0, max = 21.0, step = 0.01, fmt = "%.2f", unit = "mm",
				default = function() return 20.0 end },
			{ type = "measure", title = "MEASURE Y", field = "y", label = "Y", target = 20.0,
				min = 19.0, max = 21.0, step = 0.01, fmt = "%.2f", unit = "mm",
				default = function(ctx, r) return r.x or 20.0 end },
			{ type = "measure", title = "MEASURE Z", field = "z", label = "Z", target = 20.0,
				min = 19.0, max = 21.0, step = 0.01, fmt = "%.2f", unit = "mm",
				default = function() return 20.0 end },
			{ type = "summary" },
		},
		compute = function(r, ctx)
			local xy = ((r.x or 20) + (r.y or 20)) / 2
			local oldXY = prof(ctx, "xyScale", 100)
			local oldZ = prof(ctx, "zScale", 100)
			return {
				xyScale = U.round(oldXY * 20 / xy, 1),
				zScale = U.round(oldZ * 20 / (r.z or 20), 1),
			}
		end,
	},
	{
		id = "firstlayer",
		title = "FIRST LAYER",
		short = "FIRST LAYER",
		blurb = "Squish check for adhesion problems.",
		steps = {
			{ type = "info", title = "FIRST LAYER PATCH",
				text = "Print a single-layer square in each bed corner and one in the middle. Run a fingernail across each: it should feel smooth, with lines fused together." },
			{ type = "check", title = "WHAT DO YOU SEE?", optional = true, items = {
				"Lines fused, no gaps",
				"No ridges or elephant ripples",
				"Same look in every corner",
				"Peels off in one piece",
			} },
			{ type = "dial", title = "Z OFFSET", field = "zOffset", label = "Z OFFSET",
				min = -0.20, max = 0.20, step = 0.01, fmt = "%+.2f", unit = "mm",
				default = function(ctx) return prof(ctx, "zOffset", 0) end,
				hint = "Gaps: go lower (-). Ridges: go higher (+)." },
			{ type = "dial", title = "BED TEMP", field = "bedTemp", label = "BED TEMP",
				min = 0, max = 110, step = 5, fmt = "%d", unit = "C",
				default = function(ctx) return prof(ctx, "bedTemp", ctx.info.bed) end,
				hint = "Corners lifting? A little warmer." },
			{ type = "summary" },
		},
		compute = function(r, ctx, checks)
			local fields = { zOffset = r.zOffset, bedTemp = r.bedTemp }
			if checks and checks.all then fields.bedLeveled = true end
			return fields
		end,
	},
	{
		id = "tolerance",
		title = "TOLERANCE TEST",
		short = "TOLERANCE",
		blurb = "Smallest clearance that still slides free.",
		steps = {
			{ type = "info", title = "TOLERANCE GAUGE",
				text = "Print a tolerance gauge: pegs in holes with clearances from 0.05 to 0.50 mm. Try to free every peg without tools." },
			{ type = "pick", title = "SMALLEST FREE GAP", field = "tolerance", label = "CLEARANCE",
				style = "tower", fmt = "%.2f", unit = "mm",
				values = function() return { 0.50, 0.40, 0.30, 0.25, 0.20, 0.15, 0.10, 0.05 } end,
				default = function(ctx) return prof(ctx, "tolerance", 0.2) end,
				hint = "Crank to the tightest peg that moved." },
			{ type = "summary" },
		},
		compute = function(r)
			return { tolerance = r.tolerance }
		end,
	},
}

CalibDefs.byId = {}
for _, p in ipairs(CalibDefs.list) do CalibDefs.byId[p.id] = p end
