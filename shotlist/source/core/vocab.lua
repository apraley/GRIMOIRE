-- Controlled vocabularies. These are the canonical values written to disk and
-- exchanged with companion tools; see docs/SCHEMA.md. Keep them uppercase ASCII
-- except where the industry notation needs otherwise.

Vocab = {}

Vocab.STATUS = { "NOT SHOT", "UP NEXT", "SHOOTING", "GOT IT", "PICKUP", "CUT" }
Vocab.STATUS_SHORT = {
	["NOT SHOT"] = "TODO", ["UP NEXT"] = "NEXT", ["SHOOTING"] = "ROLL",
	["GOT IT"] = "GOT", ["PICKUP"] = "P/U", ["CUT"] = "CUT",
}
-- icon names in ui/icons.lua
Vocab.STATUS_ICON = {
	["NOT SHOT"] = "todo", ["UP NEXT"] = "upnext", ["SHOOTING"] = "rec",
	["GOT IT"] = "check", ["PICKUP"] = "pickup", ["CUT"] = "cut",
}

Vocab.SIZE = { "ECU", "CU", "MCU", "MS", "MWS", "WS", "EWS", "INSERT", "OTS", "POV", "2-SHOT" }

Vocab.MOVE = { "LOCKED", "PAN", "TILT", "DOLLY", "PUSH", "PULL", "TRACK", "HANDHELD", "GIMBAL", "CRANE", "DRONE" }

Vocab.LENS = { "14", "18", "21", "24", "28", "32", "35", "40", "50", "65", "75", "85", "100", "135", "CUSTOM" }

Vocab.PRIORITY = { 1, 2, 3 }
Vocab.PRIORITY_LABEL = { [1] = "A", [2] = "B", [3] = "C" }
Vocab.PRIORITY_LONG = { [1] = "A MUST", [2] = "B SHOULD", [3] = "C NICE" }

-- Take ratings. Order here is the display order in pickers.
Vocab.RATING = { "GREAT", "GOOD", "BAD", "TECH" }
Vocab.RATING_SCORE = { GREAT = 3, GOOD = 2, BAD = 1, TECH = 0 }
Vocab.RATING_ICON = { GREAT = "star", GOOD = "check", BAD = "x", TECH = "wrench" }

Vocab.TECH_ISSUE = { "FOCUS", "EXPOSURE", "FRAMING", "OPERATING", "BOOM IN", "AUDIO", "FLARE", "REFLECTION",
	"CAMERA FAULT", "MEDIA", "SLATE", "OTHER" }
Vocab.PERF_ISSUE = { "LINE", "TIMING", "BLOCKING", "EYELINE", "ENERGY", "CONTINUITY", "PRODUCT HANDLING", "OTHER" }

Vocab.CONT_TAG = { "WARDROBE", "PROP", "HAIR", "POSITION", "EYELINE", "LIGHT", "CAMERA", "AUDIO" }

Vocab.FPS = { "23.976", "24", "25", "29.97", "30", "48", "50", "59.94", "60", "96", "100", "119.88", "120", "180", "240" }
Vocab.RES = { "UHD 4K", "DCI 4K", "4.6K", "6K", "8K", "3.2K", "2K", "HD 1080", "4K 9:16", "HD 9:16" }
Vocab.WB = { "2700K", "3200K", "3800K", "4300K", "5000K", "5600K", "6500K", "7500K", "AUTO" }
Vocab.ISO = { "100", "200", "400", "640", "800", "1000", "1250", "1600", "2000", "2500", "3200", "4000", "5000",
	"6400", "12800" }
Vocab.SHUTTER = { "180", "172.8", "144", "90", "45", "360", "1/48", "1/50", "1/60", "1/100", "1/120", "1/250", "1/500" }
Vocab.ND = { "CLEAR", "ND.3", "ND.6", "ND.9", "ND1.2", "ND1.5", "ND1.8", "ND2.1", "VND", "IRND.6", "IRND.9", "POLA" }
Vocab.SUPPORT = { "STICKS", "HI-HAT", "SLIDER", "DOLLY", "GIMBAL", "EASYRIG", "SHOULDER", "HANDHELD", "JIB",
	"CRANE", "CAR MOUNT", "DRONE", "TABLETOP" }
Vocab.AUDIO = { "BOOM", "LAV", "BOOM+LAV", "PLANT", "SCRATCH", "MOS", "ROOM TONE", "VO" }

Vocab.GEAR_LISTS = { "cameras", "lenses", "filters", "support", "audio", "lighting" }
Vocab.GEAR_LABEL = { cameras = "CAMERAS", lenses = "LENSES", filters = "FILTERS", support = "SUPPORT",
	audio = "AUDIO", lighting = "LIGHTING" }

Vocab.TEMPLATE = { "COMMERCIAL", "INTERVIEW", "DOCUMENTARY", "NARRATIVE", "SOCIAL", "PRODUCT", "B-ROLL" }

-- Shutter values without a slash are angles; display adds the unit.
function Vocab.fmtShutter(v)
	if v == nil or v == "" then return "" end
	if tostring(v):find("/") then return tostring(v) end
	return tostring(v) .. "\194\176"
end

-- Lens values that are bare numbers are focal lengths in mm.
function Vocab.fmtLens(v)
	if v == nil or v == "" then return "" end
	v = tostring(v)
	if v:match("^%d+%.?%d*$") then return v .. "MM" end
	return Util.upper(v)
end

-- Normalise a free-typed value onto the vocabulary when it clearly matches one.
function Vocab.normalize(list, value)
	if value == nil then return nil end
	local u = Util.upper(Util.trim(value))
	u = u:gsub("MM$", "")
	for i = 1, #list do
		if Util.upper(tostring(list[i])) == u then return list[i] end
	end
	-- common aliases from other shot-list tools
	local alias = {
		["CLOSE UP"] = "CU", ["CLOSEUP"] = "CU", ["CLOSE-UP"] = "CU", ["EXTREME CLOSE UP"] = "ECU",
		["MEDIUM CLOSE UP"] = "MCU", ["MEDIUM"] = "MS", ["MEDIUM SHOT"] = "MS", ["MEDIUM WIDE"] = "MWS",
		["WIDE"] = "WS", ["WIDE SHOT"] = "WS", ["EXTREME WIDE"] = "EWS", ["TWO SHOT"] = "2-SHOT",
		["2 SHOT"] = "2-SHOT", ["TWO-SHOT"] = "2-SHOT", ["OVER THE SHOULDER"] = "OTS", ["STATIC"] = "LOCKED",
		["LOCKED OFF"] = "LOCKED", ["STEADICAM"] = "GIMBAL", ["TRACKING"] = "TRACK", ["PUSH IN"] = "PUSH",
		["PULL OUT"] = "PULL", ["HAND HELD"] = "HANDHELD", ["JIB"] = "CRANE", ["INSERT SHOT"] = "INSERT",
		["DONE"] = "GOT IT", ["COMPLETE"] = "GOT IT", ["COMPLETED"] = "GOT IT", ["SHOT"] = "GOT IT",
		["TODO"] = "NOT SHOT", ["NOT STARTED"] = "NOT SHOT", ["OMIT"] = "CUT", ["OMITTED"] = "CUT",
		["NEXT"] = "UP NEXT", ["IN PROGRESS"] = "SHOOTING", ["PICK UP"] = "PICKUP", ["PICK-UP"] = "PICKUP",
	}
	local a = alias[u]
	if a and Util.indexOf(list, a) then return a end
	return nil
end

return Vocab
