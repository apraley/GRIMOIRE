-- Project templates. Each returns a record tree (no ids) seeded with the
-- fields a crew of that kind would fill first, so a new project is usable
-- before anything is typed.

Templates = {}

local function shot(num, size, move, subject, desc, pri, est, lens)
	return Schema.new("shot", { num = num, size = size, move = move, subject = subject or "", desc = desc or "",
		priority = pri or 2, est = est or 10, lens = lens or "" })
end

local function setup(letter, fields, shots)
	local s = Schema.new("setup", fields)
	s.letter = letter
	s.shots = shots or {}
	return s
end

local function scene(number, desc, location, cast, setups)
	local s = Schema.new("scene", { number = number, desc = desc, location = location or "", cast = cast or "" })
	s.setups = setups or {}
	return s
end

local function day(label, date, location, call, scenes)
	local d = Schema.new("day", { label = label, date = date or "", location = location or "", call = call or "07:00" })
	d.scenes = scenes or {}
	return d
end

local function project(fields, days)
	local p = Schema.new("project", fields)
	p.days = days or {}
	return p
end

local function today() return Util.fmtDate(Util.now()) end

-- Technical defaults per template
local TECH = {
	COMMERCIAL = { fps = "23.976", res = "DCI 4K", wb = "5600K", iso = "800", shutter = "180", nd = "ND.6", support = "DOLLY" },
	INTERVIEW = { fps = "23.976", res = "UHD 4K", wb = "5600K", iso = "800", shutter = "180", nd = "ND.3", support = "STICKS",
		audio = "BOOM+LAV" },
	DOCUMENTARY = { fps = "23.976", res = "UHD 4K", wb = "5600K", iso = "800", shutter = "180", nd = "VND", support = "SHOULDER",
		audio = "BOOM" },
	NARRATIVE = { fps = "23.976", res = "4.6K", wb = "3200K", iso = "800", shutter = "180", nd = "ND.6", support = "DOLLY",
		audio = "BOOM+LAV" },
	SOCIAL = { fps = "29.97", res = "4K 9:16", wb = "5600K", iso = "800", shutter = "180", nd = "VND", support = "GIMBAL",
		audio = "LAV" },
	PRODUCT = { fps = "23.976", res = "DCI 4K", wb = "5600K", iso = "400", shutter = "180", nd = "CLEAR", support = "TABLETOP",
		audio = "MOS" },
	["B-ROLL"] = { fps = "59.94", res = "UHD 4K", wb = "5600K", iso = "800", shutter = "180", nd = "VND", support = "GIMBAL",
		audio = "SCRATCH" },
}

local function tech(kind, extra)
	local t = Util.copy(TECH[kind])
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end

Templates.BUILDERS = {}

Templates.BUILDERS.COMMERCIAL = function()
	return project({ title = "NEW COMMERCIAL", client = "", template = "COMMERCIAL",
		notes = ":30 + :15 cutdown. Hero product must be clean and label-forward.", cast = { "TALENT", "PRODUCT" } }, {
		day("DAY 1", today(), "", "07:00", {
			scene("01", "HERO PRODUCT MOMENT", "", "PRODUCT", {
				setup("A", tech("COMMERCIAL", { camera = "A CAM", lens = "50" }), {
					shot("01", "WS", "PUSH", "TALENT", "WIDE ESTABLISHING", 1, 20),
					shot("02", "MS", "LOCKED", "TALENT", "", 1, 15),
					shot("03", "CU", "PUSH", "PRODUCT", "HERO PRODUCT", 1, 20, "100"),
					shot("04", "INSERT", "LOCKED", "PRODUCT", "LOGO / PACKSHOT", 1, 15, "100"),
				}),
			}),
		}),
	})
end

Templates.BUILDERS.INTERVIEW = function()
	return project({ title = "NEW INTERVIEW", template = "INTERVIEW",
		notes = "Two-camera sit-down. Room tone 30s before wrap. Release forms.", cast = { "SUBJECT", "INTERVIEWER" } }, {
		day("DAY 1", today(), "", "08:00", {
			scene("01", "SIT-DOWN INTERVIEW", "", "SUBJECT", {
				setup("A", tech("INTERVIEW", { camera = "A CAM", lens = "50", lighting = "KEY + NEG FILL + HAIR" }), {
					shot("01", "MS", "LOCKED", "SUBJECT", "A CAM MEDIUM - INTERVIEW", 1, 45),
					shot("02", "CU", "LOCKED", "SUBJECT", "B CAM CLOSE - INTERVIEW", 1, 0, "85"),
				}),
				setup("B", tech("INTERVIEW", { camera = "A CAM", lens = "24", audio = "ROOM TONE" }), {
					shot("01", "WS", "LOCKED", "", "ROOM TONE 30S", 1, 2),
					shot("02", "INSERT", "HANDHELD", "SUBJECT", "HANDS / DETAILS", 3, 10, "85"),
					shot("03", "MWS", "GIMBAL", "SUBJECT", "WALK-IN B-ROLL", 2, 15),
				}),
			}),
		}),
	})
end

Templates.BUILDERS.DOCUMENTARY = function()
	return project({ title = "NEW DOCUMENTARY", template = "DOCUMENTARY",
		notes = "Observational. Get releases. Log locations for archive.", cast = { "SUBJECT" } }, {
		day("DAY 1", today(), "", "07:30", {
			scene("01", "VERITE - ARRIVAL", "", "SUBJECT", {
				setup("A", tech("DOCUMENTARY", { camera = "A CAM", lens = "24-70" }), {
					shot("01", "WS", "HANDHELD", "SUBJECT", "ARRIVAL / ESTABLISH", 1, 20),
					shot("02", "MS", "HANDHELD", "SUBJECT", "FOLLOW ACTION", 1, 30),
					shot("03", "CU", "HANDHELD", "SUBJECT", "REACTIONS", 2, 15),
				}),
			}),
			scene("02", "INTERVIEW", "", "SUBJECT", {
				setup("A", tech("DOCUMENTARY", { camera = "A CAM", lens = "50", support = "STICKS", audio = "BOOM+LAV" }), {
					shot("01", "MCU", "LOCKED", "SUBJECT", "INTERVIEW", 1, 60),
				}),
			}),
			scene("03", "B-ROLL / TEXTURE", "", "", {
				setup("A", tech("DOCUMENTARY", { camera = "A CAM", lens = "24-70" }), {
					shot("01", "EWS", "LOCKED", "", "LOCATION WIDE / TIMELAPSE", 2, 20),
					shot("02", "INSERT", "HANDHELD", "", "DETAILS", 3, 15),
				}),
			}),
		}),
	})
end

Templates.BUILDERS.NARRATIVE = function()
	return project({ title = "NEW NARRATIVE", template = "NARRATIVE",
		notes = "Coverage per scene: master, mediums, singles, inserts.", cast = { "LEAD", "SUPPORT" } }, {
		day("DAY 1", today(), "", "06:30", {
			scene("01", "INT. LOCATION - DAY", "", "LEAD, SUPPORT", {
				setup("A", tech("NARRATIVE", { camera = "A CAM", lens = "32", lighting = "SOFT KEY THROUGH WINDOW" }), {
					shot("01", "WS", "DOLLY", "LEAD, SUPPORT", "MASTER", 1, 30),
				}),
				setup("B", tech("NARRATIVE", { camera = "A CAM", lens = "50" }), {
					shot("01", "MS", "LOCKED", "LEAD", "MEDIUM - LEAD", 1, 20),
					shot("02", "MS", "LOCKED", "SUPPORT", "MEDIUM - SUPPORT", 1, 20),
				}),
				setup("C", tech("NARRATIVE", { camera = "A CAM", lens = "85" }), {
					shot("01", "CU", "LOCKED", "LEAD", "SINGLE - LEAD", 1, 15),
					shot("02", "CU", "LOCKED", "SUPPORT", "SINGLE - SUPPORT", 2, 15),
					shot("03", "INSERT", "LOCKED", "", "INSERT - PROP", 3, 10, "100"),
				}),
			}),
		}),
	})
end

Templates.BUILDERS.SOCIAL = function()
	return project({ title = "NEW SOCIAL", template = "SOCIAL",
		notes = "Vertical 9:16. Hook in the first 2s. Safe zones for captions.", cast = { "CREATOR", "PRODUCT" } }, {
		day("DAY 1", today(), "", "09:00", {
			scene("01", "HOOK", "", "CREATOR", {
				setup("A", tech("SOCIAL", { camera = "A CAM", lens = "24" }), {
					shot("01", "MCU", "PUSH", "CREATOR", "HOOK TO CAMERA", 1, 10),
					shot("02", "CU", "HANDHELD", "PRODUCT", "PRODUCT REVEAL", 1, 10, "35"),
				}),
			}),
			scene("02", "DEMO + CTA", "", "CREATOR", {
				setup("A", tech("SOCIAL", { camera = "A CAM", lens = "24" }), {
					shot("01", "MS", "GIMBAL", "CREATOR", "DEMO WALKTHROUGH", 1, 15),
					shot("02", "INSERT", "LOCKED", "PRODUCT", "DETAIL CUTAWAYS", 2, 10, "50"),
					shot("03", "MCU", "LOCKED", "CREATOR", "CALL TO ACTION", 1, 5),
				}),
			}),
		}),
	})
end

Templates.BUILDERS.PRODUCT = function()
	return project({ title = "NEW PRODUCT", template = "PRODUCT",
		notes = "Tabletop. Gloves on. Check dust + fingerprints every take.", cast = { "PRODUCT", "HANDS" } }, {
		day("DAY 1", today(), "STUDIO", "08:00", {
			scene("01", "PACKSHOTS", "STUDIO", "PRODUCT", {
				setup("A", tech("PRODUCT", { camera = "A CAM", lens = "100", lighting = "TOP SOFTBOX + STRIP RIM" }), {
					shot("01", "WS", "LOCKED", "PRODUCT", "HERO PACKSHOT", 1, 20),
					shot("02", "CU", "LOCKED", "PRODUCT", "LABEL DETAIL", 1, 15),
					shot("03", "ECU", "PUSH", "PRODUCT", "MACRO TEXTURE", 2, 20),
				}),
				setup("B", tech("PRODUCT", { camera = "A CAM", lens = "50", support = "SLIDER" }), {
					shot("01", "MS", "TRACK", "PRODUCT", "SLIDER REVEAL", 2, 20),
					shot("02", "INSERT", "LOCKED", "HANDS", "HAND INTERACTION", 2, 15, "85"),
				}),
			}),
		}),
	})
end

Templates.BUILDERS["B-ROLL"] = function()
	return project({ title = "NEW B-ROLL", template = "B-ROLL",
		notes = "Shoot in sequences: wide, medium, tight, detail. 10s holds minimum.", cast = {} }, {
		day("DAY 1", today(), "", "07:00", {
			scene("01", "LOCATION SEQUENCE", "", "", {
				setup("A", tech("B-ROLL", { camera = "A CAM", lens = "24-70" }), {
					shot("01", "EWS", "DRONE", "", "AERIAL ESTABLISH", 2, 20),
					shot("02", "WS", "GIMBAL", "", "WIDE MOVEMENT", 1, 10),
					shot("03", "MS", "HANDHELD", "", "MEDIUM ACTION", 1, 10),
					shot("04", "CU", "LOCKED", "", "TIGHT DETAIL", 2, 10),
					shot("05", "INSERT", "PUSH", "", "TEXTURE / MACRO", 3, 10, "100"),
				}),
			}),
		}),
	})
end

function Templates.build(kind)
	local b = Templates.BUILDERS[kind]
	if b == nil then return nil end
	local p = b()
	Schema.normalize(p)
	return p
end

---------------------------------------------------------------------------
-- Demo: a 60-shot, two-camera, one-day coffee commercial. Used for the
-- first-run demo and by the headless friction simulation.
---------------------------------------------------------------------------

function Templates.demoCommercial()
	local p = project({ title = "FIRST LIGHT :30", client = "NORTHWIND COFFEE", director = "R. ALVAREZ",
		dp = "K. OKAFOR", producer = "J. PARK", template = "COMMERCIAL",
		notes = ":30 + :15 + 6s cutdowns. Hero bag label must read. Golden hour window 18:40-19:10.",
		cast = { "SAM", "MAYA", "BARISTA", "PRODUCT", "HANDS" }, locations = { "LOFT KITCHEN", "CAFE", "STREET", "ROOFTOP" } }, {})

	local dayRec = day("DAY 1", today(), "LOFT KITCHEN / CAFE / ROOFTOP", "06:00", {})
	dayRec.weather = "CLEAR AM, CLOUD 14:00, SUNSET 19:04"
	dayRec.crewNotes = "LUNCH 12:30. COMPANY MOVE TO CAFE 13:30. ROOFTOP MUST START BY 18:15."
	p.days[1] = dayRec

	local A = function(extra) return tech("COMMERCIAL", extra) end
	local plan = {
		{ "01", "SAM WAKES - DAWN LIGHT", "LOFT KITCHEN", "SAM", {
			{ "A", { camera = "A CAM", lens = "35", support = "DOLLY", lighting = "DAYLIGHT THROUGH BLINDS + 4X4 BOUNCE" }, {
				{ "WS", "PUSH", "SAM", "SAM ROLLS OUT OF BED", 1, 15 },
				{ "MS", "LOCKED", "SAM", "FEET HIT FLOOR", 2, 8 },
				{ "MCU", "PAN", "SAM", "SAM LOOKS TO WINDOW", 2, 8 },
				{ "CU", "LOCKED", "SAM", "EYES OPEN", 1, 6, "85" },
			} },
			{ "B", { camera = "B CAM", lens = "85", support = "STICKS" }, {
				{ "INSERT", "LOCKED", "HANDS", "ALARM CLOCK SWIPE", 3, 5, "100" },
				{ "CU", "TILT", "SAM", "STRETCH SILHOUETTE", 3, 6 },
			} },
		} },
		{ "02", "THE RITUAL - GRIND + POUR", "LOFT KITCHEN", "SAM, PRODUCT", {
			{ "A", { camera = "A CAM", lens = "50", support = "DOLLY", lighting = "WINDOW KEY + NEG FILL" }, {
				{ "MS", "DOLLY", "SAM", "SAM ENTERS KITCHEN", 1, 12 },
				{ "CU", "HANDHELD", "SAM", "SAM ENTERS ROOM", 1, 10 },
				{ "MCU", "LOCKED", "SAM", "REACHES FOR BAG", 1, 8 },
				{ "OTS", "PUSH", "SAM", "OTS TO GRINDER", 2, 8 },
			} },
			{ "B", { camera = "A CAM", lens = "100", support = "SLIDER", lighting = "HARD SIDE LIGHT FOR STEAM" }, {
				{ "INSERT", "PUSH", "PRODUCT", "BAG LABEL HERO", 1, 12 },
				{ "ECU", "LOCKED", "PRODUCT", "BEANS INTO GRINDER", 1, 10 },
				{ "INSERT", "TRACK", "HANDS", "POUR-OVER SPIRAL", 1, 12 },
				{ "ECU", "LOCKED", "PRODUCT", "STEAM RISING", 2, 8 },
				{ "CU", "LOCKED", "PRODUCT", "DRIP INTO CARAFE", 2, 6 },
			} },
			{ "C", { camera = "B CAM", lens = "24", support = "GIMBAL" }, {
				{ "WS", "GIMBAL", "SAM", "ORBIT AROUND COUNTER", 2, 12 },
				{ "POV", "HANDHELD", "SAM", "POV POURING", 3, 6 },
			} },
		} },
		{ "03", "FIRST SIP", "LOFT KITCHEN", "SAM, MAYA", {
			{ "A", { camera = "A CAM", lens = "65", support = "STICKS" }, {
				{ "MCU", "LOCKED", "SAM", "FIRST SIP REACTION", 1, 10 },
				{ "2-SHOT", "LOCKED", "SAM, MAYA", "MAYA STEALS THE MUG", 1, 12 },
				{ "CU", "LOCKED", "MAYA", "MAYA SMILES", 2, 6 },
			} },
			{ "B", { camera = "B CAM", lens = "85", support = "STICKS" }, {
				{ "CU", "LOCKED", "SAM", "SAM MOCK OUTRAGE", 2, 6 },
				{ "INSERT", "LOCKED", "HANDS", "MUG HANDOFF", 2, 6, "100" },
				{ "OTS", "LOCKED", "MAYA", "OTS MAYA TO SAM", 3, 6 },
			} },
		} },
		{ "04", "CAFE - BARISTA CRAFT", "CAFE", "BARISTA, PRODUCT", {
			{ "A", { camera = "A CAM", lens = "35", support = "DOLLY", lighting = "PRACTICALS + SKYPANEL TOP" }, {
				{ "WS", "DOLLY", "BARISTA", "CAFE ESTABLISH", 1, 15 },
				{ "MS", "TRACK", "BARISTA", "BARISTA AT MACHINE", 1, 10 },
			} },
			{ "B", { camera = "A CAM", lens = "100", support = "SLIDER" }, {
				{ "ECU", "LOCKED", "PRODUCT", "ESPRESSO PULL", 1, 12 },
				{ "INSERT", "PUSH", "HANDS", "LATTE ART", 1, 15 },
				{ "ECU", "LOCKED", "PRODUCT", "CREMA SWIRL", 2, 8 },
				{ "INSERT", "LOCKED", "HANDS", "TAMPING", 3, 6 },
			} },
			{ "C", { camera = "B CAM", lens = "50", support = "GIMBAL" }, {
				{ "MWS", "GIMBAL", "BARISTA", "HANDOFF ACROSS COUNTER", 2, 10 },
				{ "CU", "HANDHELD", "BARISTA", "BARISTA NOD", 3, 5 },
			} },
		} },
		{ "05", "CAFE - REGULARS", "CAFE", "SAM, MAYA, BARISTA", {
			{ "A", { camera = "A CAM", lens = "50", support = "STICKS" }, {
				{ "MS", "LOCKED", "SAM, MAYA", "SAM + MAYA ARRIVE", 2, 10 },
				{ "2-SHOT", "PAN", "SAM, MAYA", "ORDERING AT COUNTER", 2, 10 },
				{ "CU", "LOCKED", "BARISTA", "BARISTA KNOWS THEIR ORDER", 2, 6 },
			} },
			{ "B", { camera = "B CAM", lens = "24", support = "HANDHELD" }, {
				{ "WS", "HANDHELD", "", "CAFE ATMOSPHERE", 3, 8 },
				{ "INSERT", "HANDHELD", "HANDS", "CUPS ON TRAY", 3, 5, "85" },
			} },
		} },
		{ "06", "STREET - WALK + SIP", "STREET", "SAM", {
			{ "A", { camera = "A CAM", lens = "35", support = "GIMBAL" }, {
				{ "WS", "TRACK", "SAM", "SAM EXITS CAFE", 1, 10 },
				{ "MS", "GIMBAL", "SAM", "WALK AND SIP", 1, 10 },
				{ "MCU", "GIMBAL", "SAM", "SAM NODS AT NEIGHBOR", 3, 6 },
				{ "CU", "HANDHELD", "HANDS", "CUP SLEEVE LOGO", 2, 6, "85" },
				{ "WS", "LOCKED", "SAM", "CROSSWALK SILHOUETTE", 2, 8 },
			} },
			{ "B", { camera = "B CAM", lens = "135", support = "STICKS" }, {
				{ "MS", "PAN", "SAM", "LONG LENS STREET PASS", 2, 8 },
				{ "CU", "LOCKED", "SAM", "LONG LENS PROFILE", 3, 6 },
				{ "INSERT", "LOCKED", "", "STEAM FROM LID", 3, 5 },
				{ "WS", "LOCKED", "", "STREET ESTABLISH", 2, 6, "24" },
			} },
		} },
		{ "07", "ROOFTOP - GOLDEN HOUR", "ROOFTOP", "SAM, MAYA", {
			{ "A", { camera = "A CAM", lens = "50", support = "DOLLY", lighting = "NATURAL SUN + 8X8 UNBLEACHED" }, {
				{ "WS", "DOLLY", "SAM, MAYA", "ROOFTOP REVEAL", 1, 12 },
				{ "2-SHOT", "PUSH", "SAM, MAYA", "TOAST WITH MUGS", 1, 10 },
				{ "MCU", "LOCKED", "MAYA", "MAYA LAUGHS", 1, 8 },
				{ "MCU", "LOCKED", "SAM", "SAM LOOKS AT SKYLINE", 2, 8 },
			} },
			{ "B", { camera = "B CAM", lens = "85", support = "STICKS" }, {
				{ "CU", "LOCKED", "SAM", "SAM PROFILE FLARE", 2, 6 },
				{ "INSERT", "LOCKED", "PRODUCT", "MUG ON LEDGE + CITY", 1, 8, "100" },
				{ "CU", "LOCKED", "MAYA", "MAYA PROFILE FLARE", 3, 6 },
			} },
			{ "C", { camera = "DRONE", lens = "24", support = "DRONE" }, {
				{ "EWS", "DRONE", "", "PULLBACK TO CITY", 1, 15 },
				{ "EWS", "DRONE", "", "TOP-DOWN ROOF", 3, 10 },
			} },
		} },
		{ "08", "PACKSHOT - TABLETOP", "LOFT KITCHEN", "PRODUCT", {
			{ "A", { camera = "A CAM", lens = "100", support = "TABLETOP", lighting = "TOP SOFTBOX + STRIP RIMS" }, {
				{ "WS", "LOCKED", "PRODUCT", "BAG + MUG HERO", 1, 15 },
				{ "CU", "PUSH", "PRODUCT", "LABEL PUSH-IN", 1, 12 },
				{ "INSERT", "LOCKED", "PRODUCT", "BEANS SPILL", 2, 12 },
				{ "ECU", "LOCKED", "PRODUCT", "ROAST DATE STAMP", 2, 6 },
			} },
			{ "B", { camera = "A CAM", lens = "50", support = "SLIDER" }, {
				{ "MS", "TRACK", "PRODUCT", "LINEUP OF 3 BLENDS", 1, 12 },
				{ "INSERT", "LOCKED", "PRODUCT", "END CARD PLATE", 1, 8 },
			} },
		} },
	}
	local count = 0
	for _, sc in ipairs(plan) do
		local sceneRec = scene(sc[1], sc[2], sc[3], sc[4], {})
		for _, su in ipairs(sc[5]) do
			local setupRec = setup(su[1], A(su[2]), {})
			for i, sh in ipairs(su[3]) do
				setupRec.shots[#setupRec.shots + 1] = shot(Util.pad2(i), sh[1], sh[2], sh[3], sh[4], sh[5], sh[6], sh[7])
				count = count + 1
			end
			sceneRec.setups[#sceneRec.setups + 1] = setupRec
		end
		dayRec.scenes[#dayRec.scenes + 1] = sceneRec
	end
	assert(count == 60, "demo should have 60 shots, has " .. count)
	Schema.normalize(p)
	return p
end

-- Named camera packages that match the demo.
function Templates.demoPackages()
	return {
		Schema.new("pkg", { name = "A CAM", camera = "SONY FX6", lenses = { "24-70", "SIGMA CINE PRIMES" }, filters = { "VND" },
			support = "DOLLY", audio = "BOOM MKH-50", lighting = "" }),
		Schema.new("pkg", { name = "B CAM", camera = "SONY FX3", lenses = { "70-200", "100 MACRO" }, filters = { "BPM 1/8" },
			support = "STICKS", audio = "", lighting = "" }),
		Schema.new("pkg", { name = "DRONE", camera = "DJI INSPIRE 3", lenses = { "24" }, filters = { "ND.9" }, support = "DRONE",
			audio = "", lighting = "" }),
	}
end

return Templates
