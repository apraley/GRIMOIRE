-- CRANKING IT :: No.IV MICROFICHE
--
-- The crank drives the reader's film spool through a gear train into a
-- heavy, freewheeling spool:
--   * the hand only pushes the spool when it turns faster than the spool
--     is already going (a freewheel clutch); let go and the spool COASTS,
--     slowing only by bearing friction.
--   * cranking against the motion presses a brake shoe: counter-cranking
--     harder brakes harder, and once stopped the clutch engages backwards.
--   * A toggles the gear: LOW = 3 frames per turn (page by page, with a
--     sprung detent that clicks each frame into the gate), HIGH = 45 frames
--     per turn (years fly past, pages smear into streaks, counter races).
--   * the reel has ends: hit one at speed and the tail flaps off the spool.
--
-- The archive (four reels: the Gazette, the light log, the harbour
-- registry and the parish register - over 2,700 frames) is never stored.
-- Each frame is generated on demand from (world seed, reel, frame) into a
-- small cache of six slots. A case "plants" a handful of lines into that
-- generated space; the case generator guarantees that the chain of records
-- resolves to exactly one answer and scatters red herrings (near-identical
-- ship names, two keepers with the same initials, storms on other nights).

local gfx <const> = playdate.graphics
local floor <const> = math.floor
local abs <const> = math.abs
local min <const>, max <const> = math.min, math.max
local sin <const>, cos <const>, rad <const> = math.sin, math.cos, math.rad
local exp <const> = math.exp
local fmt <const> = string.format

------------------------------------------------------------------------
-- the archive: calendar, names, pools
------------------------------------------------------------------------
local GAZ <const>, LOG <const>, REG <const>, PAR <const> = 1, 2, 3, 4
local REEL_TAG <const> = { "GAZETTE", "LIGHT LOG", "REGISTRY", "PARISH" }
local REEL_SPAN <const> = { "1880-1899", "1880-1899", "SHIPS A-Z", "NAMES A-Z" }

local MON <const> = { "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }
local WDAY <const> = { "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" }
local DIM <const> = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
local YEAR0 <const> = 1880
local NYEARS <const> = 20

local MSTART, MLEN, YEARSTR, DAYSTR = {}, {}, {}, {}
local TOTAL_DAYS = 0
do
  local dn = 0
  for yi = 0, NYEARS - 1 do
    local y = YEAR0 + yi
    local leap = (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0
    for m = 1, 12 do
      local len = DIM[m]
      if m == 2 and leap then len = 29 end
      MSTART[yi * 12 + m] = dn
      MLEN[yi * 12 + m] = len
      dn = dn + len
    end
    YEARSTR[y] = tostring(y)
  end
  TOTAL_DAYS = dn
  for d = 1, 31 do DAYSTR[d] = tostring(d) end
end

-- day number (0 = 1 Jan 1880) -> year, month, day
local function dateOf(dn)
  local yi = min(NYEARS - 1, max(0, floor(dn / 365.25)))
  while yi > 0 and MSTART[yi * 12 + 1] > dn do yi = yi - 1 end
  while yi < NYEARS - 1 and MSTART[(yi + 1) * 12 + 1] <= dn do yi = yi + 1 end
  local m = 12
  while m > 1 and MSTART[yi * 12 + m] > dn do m = m - 1 end
  return YEAR0 + yi, m, dn - MSTART[yi * 12 + m] + 1
end
local function dayNum(y, m, d) return MSTART[(y - YEAR0) * 12 + m] + d - 1 end
local function wday(dn) return WDAY[(dn + 4) % 7 + 1] end   -- 1 Jan 1880 was a Thursday

-- the Gazette came out on Saturdays (first issue 3 Jan 1880); the log keeps one week per frame
local function issueDay(i) return 2 + 7 * i end
local function issueAfter(dn) if dn < 2 then return 0 end return (dn - 2) // 7 + 1 end

-- registry and parish register are alphabetical. Names are built from
-- sorted, prefix-free syllables so frame order IS alphabetical order.
local SH1 <const> = { "AL", "AR", "BEL", "CAL", "COR", "DAR", "EL", "FAL", "GAL", "HAL",
  "IS", "KEL", "LOR", "MAR", "NOR", "OR", "PEL", "ROS", "SEL", "TAR" }
local SH2 <const> = { "A", "E", "I", "O" }
local SH3 <const> = { "DA", "LA", "NA", "RA", "TA" }
local SP1 <const> = { "ALDER", "ASH", "BAR", "BRE", "CAR", "COL", "DAR", "DUN", "FEN", "GAR", "HAL", "HAR",
  "KEL", "LAN", "MAR", "MOR", "NEL", "PEL", "QUIN", "RAV", "SAL", "TAR", "VOS", "WEL" }
local SP2 <const> = { "BY", "DEN", "ETT", "FORD", "INS", "LEY", "LOW", "MAN", "SON", "TON", "WICK" }
local SHIPS, SURN, SHIPTAB, SURNTAB = {}, {}, {}, {}
for a = 1, #SH1 do for b = 1, #SH2 do for c = 1, #SH3 do
  SHIPS[#SHIPS + 1] = SH1[a] .. SH2[b] .. SH3[c]
  SHIPTAB[#SHIPTAB + 1] = SH1[a] .. "-"
end end end
for a = 1, #SP1 do for b = 1, #SP2 do
  SURN[#SURN + 1] = SP1[a] .. SP2[b]
  SURNTAB[#SURNTAB + 1] = SP1[a] .. "-"
end end

local N_FRAMES <const> = { (TOTAL_DAYS - 3) // 7 + 1, (TOTAL_DAYS + 6) // 7, #SHIPS, #SURN }

local MALE <const> = {
  A = { "ALBERT", "ARTHUR", "AMOS" }, E = { "EDWIN", "EDWARD", "ELIAS" }, G = { "GEORGE", "GILBERT" },
  H = { "HENRY", "HUGH", "HORACE" }, J = { "JAMES", "JOSEPH", "JOHN", "JONAH" }, S = { "SAMUEL", "SILAS" },
  T = { "THOMAS", "TOBIAS" }, W = { "WALTER", "WILLIAM" }, R = { "ROBERT", "RUFUS", "RICHARD" },
}
local MALE_INIT <const> = { "A", "E", "G", "H", "J", "S", "T", "W" }
local FEMALE <const> = {
  A = { "ADA", "AGNES" }, E = { "EDITH", "ELLEN", "ELSIE" }, M = { "MARY", "MAUD", "MARTHA", "MARGARET" },
  R = { "ROSE", "RUTH" }, J = { "JANE", "JUDITH" }, H = { "HANNAH", "HARRIET" }, S = { "SARAH", "SUSAN" },
}
local FEMALE_INIT <const> = { "A", "E", "M", "R", "J", "H", "S" }
local OCC <const> = { "fisherman", "net-mender", "cooper", "baker", "ferryman", "ropemaker", "sailmaker",
  "carter", "draper", "schoolmistress", "gull warden", "organist", "pilot", "smith", "widow", "gravedigger" }
local SHIPTYPE <const> = { "schooner", "ketch", "brig", "smack", "barque", "lugger", "drifter" }
local PORTS <const> = { "Leith", "Whitby", "Arbroath", "Ninefold", "Peterhead", "Hull", "Bideford", "Wick" }
local FARPLACE <const> = { "the Skerries", "Cape Wrath", "Fair Isle", "the Bass", "Duncansby" }
local WEATHER <const> = { "NE4 FAIR", "SW5 RAIN", "W6 RAIN", "CALM FOG", "N3 CLEAR", "SE4 HAZE", "S3 FAIR", "E4 SLEET", "NW5 MIST" }
local HEADLINES <const> = {
  "HERRING RETURN", "FOG FOR NINE DAYS", "BELL BUOY SILENT", "NEW LENS AT GREY ROCK", "SOCIETY DINNER",
  "TIDE CLOCK STOPS", "THE FERRY QUESTION", "A WHALE IN THE SOUND", "COAL PRICES RISE", "LANTERNS AT SEA",
  "HARBOUR WALL MENDED", "STRANGER ON THE STAIRS", "THE WELL IS DEEPER", "CHOIR OUTING", "PIER TO BE PAINTED",
  "A CLOCK FOR THE CHAPEL", "NO BOAT SCHEDULED", "GULLS NESTING EARLY",
}
local NOTICES <const> = {
  "No boat is scheduled.", "Keep the stairs clear.", "Do not lower the Keeper.", "A crank found on the steps.",
  "The ferry will not run.", "The museum is closed.", "Hands must be kept warm.", "Nothing moves by itself.",
}
local LOSTS <const> = { "brass key", "left glove", "pocket watch", "hymn book", "tin whistle", "crank handle" }
local CARGO <const> = { "coal", "salt", "timber", "lamp oil", "slate", "barrels", "rope", "mail" }
local TOPICS <const> = { "patience", "tides", "the hand", "momentum", "thrift", "the deep" }
local WINDS <const> = { "NE", "SW", "W", "N", "SE", "E" }
local SKIES <const> = { "fair", "rain", "fog", "haze", "squalls" }

local function titleCase(s) return s:sub(1, 1) .. s:sub(2):lower() end

-- patterns (8 rows + 8 mask rows: white streaks, transparent elsewhere)
local STREAK <const> = { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44 }
local STREAK2 <const> = { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x40, 0x04, 0x40, 0x04, 0x40, 0x04, 0x40, 0x04 }
local DIAG <const> = { 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01 }
local DOTS <const> = { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x80, 0x00, 0x08, 0x00, 0x80, 0x00, 0x08, 0x00 }

------------------------------------------------------------------------
-- physics / layout constants
------------------------------------------------------------------------
local LO_RATIO <const> = 1 / 120   -- frames per crank degree (3 frames a turn)
local HI_RATIO <const> = 1 / 8     -- 45 frames a turn
local BRAKE <const> = 0.42         -- frames/s^2 per deg/s of counter-crank
local VMAX <const> = 160
local FP <const> = 104             -- full view frame pitch (px)
local MP <const> = 270             -- magnified frame pitch (px)
local FX <const>, FW <const>, FH <const> = 28, 244, 92
local CY <const> = 120
local LH <const> = 17
local FILM_W <const> = 300
local NSLOT <const> = 6
local STD_CASES <const> = 3

local Fiche = Machine.define({
  id = "microfiche",
  number = 4,
  title = "MICROFICHE",
  tagline = "Years fly by on the spool.",
  description = "Four reels of the Ninefold archive on a heavy spool. Spin through decades, brake on a page, follow the trail.",
  howto = "Crank to spool the film: slow for one page, HIGH gear and hard for years. It coasts - crank back to brake. B magnifies, A clips a line. Chain the records, then accuse from the case file (UP).",
  controls = { { "CRANK", "spool the film" }, { "A", "gear / clip a line" }, { "B", "magnify" }, { "DPAD", "reel, case file, cursor" } },
  modes = { "tutorial", "standard", "endless" },
  medals = { standard = { 1000, 3300, 4800 }, endless = { 2500, 6000, 10000 } },
  scoreLabel = "POINTS",
  unlockCost = 4,
  achievements = {
    { id = "first", name = "FIRST FILE", desc = "Solve your first case." },
    { id = "clean", name = "CLEAN HANDS", desc = "Solve a case with no bad clips." },
    { id = "blur", name = "YEARS FLY", desc = "Spool at 100 frames a second." },
    { id = "quick", name = "PAPER TRAIL", desc = "Solve a 4-record case in 75s." },
    { id = "archive", name = "THE WHOLE ARCHIVE", desc = "Solve all three Standard cases." },
  },
  challenges = {
    { id = "dim", name = "DIM BULB", desc = "The lamp is failing. It flickers.", mode = "standard", difficulty = 2, goal = 2500, reward = 2, cost = 2 },
    { id = "slip", name = "SLIPPED GEAR", desc = "Stuck in HIGH gear. Brake well.", mode = "standard", difficulty = 2, goal = 2500, reward = 3, cost = 2 },
    { id = "night", name = "NIGHT READING", desc = "Endless, four-record cases only.", mode = "endless", difficulty = 3, goal = 5000, reward = 3, cost = 3 },
  },
  records = {
    { "solved", "Cases solved" },
    { "fastest", "Fastest case", function(v) return v > 0 and string.format("%.1fs", v / 10) or "-" end },
    { "frames", "Frames spooled" },
    { "topspeed", "Top speed", function(v) return v .. " fr/s" end },
  },
  drawIcon = function(cx, cy)
    -- reader screen with a projected page, sprocket film and the spool
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(cx - 22, cy - 20, 32, 40)
    gfx.setColor(gfx.kColorWhite)
    for y = cy - 18, cy + 16, 6 do
      gfx.fillRect(cx - 21, y, 2, 3)
      gfx.fillRect(cx + 7, y, 2, 3)
    end
    gfx.drawRect(cx - 17, cy - 16, 22, 32)
    gfx.fillRect(cx - 15, cy - 13, 16, 3)
    for i = 0, 4 do gfx.fillRect(cx - 15, cy - 7 + i * 4, 8 + (i * 5) % 9, 1) end
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(cx + 16, cy + 6, 8)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(cx + 16, cy + 6, 2)
    gfx.drawLine(cx + 16, cy + 6, cx + 21, cy + 1)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    gfx.drawLine(cx + 16, cy + 6, cx + 22, cy - 8)
    gfx.setLineWidth(1)
    gfx.fillCircleAtPoint(cx + 22, cy - 9, 3)
    gfx.drawLine(cx + 10, cy - 20, cx + 10, cy + 20)
  end,
})

-- exposed for the scripted tests
Fiche.REELS = { GAZ = GAZ, LOG = LOG, REG = REG, PAR = PAR }
Fiche.N_FRAMES = N_FRAMES
Fiche.dateOf = dateOf
Fiche.dayNum = dayNum
Fiche.issueAfter = issueAfter
Fiche.SHIPS = SHIPS
Fiche.SURN = SURN
Fiche.MON = MON
Fiche.RATIOS = { LO_RATIO, HI_RATIO }
Fiche.BRAKE = BRAKE

------------------------------------------------------------------------
-- world: the keepers of Grey Rock, derived from the run seed
------------------------------------------------------------------------
function Fiche:makeWorld(seed)
  local r = U.rng(seed)
  local used = {}
  self.roster = {}
  self.people = {}
  for e = 1, 5 do
    local ro = {}
    for k = 1, 3 do
      local s
      repeat s = r:range(0, #SURN - 1) until not used[s]
      used[s] = true
      local init = r:pick(MALE_INIT)
      local names = MALE[init]
      local i1 = r:range(1, #names)
      local i2 = i1 % #names + 1
      local from = YEAR0 + (e - 1) * 4
      local born = from - r:range(24, 40)
      local kp = { first = names[i1], init = init, sur = s, from = from, to = from + 3, born = born, keeper = true }
      kp.abbrev = init .. "." .. SURN[s + 1]
      kp.full = kp.first .. " " .. SURN[s + 1]
      -- a relative with the same initial: an older keeper or a brother ashore
      local rel = { first = names[i2], init = init, sur = s }
      if r:chance(0.55) then
        rel.keeper = true
        rel.born = born - r:range(22, 30)
        rel.from = r:range(1846, 1860)
        rel.to = rel.from + r:range(6, 12)
      else
        rel.keeper = false
        rel.born = born + r:range(2, 8)
        rel.occ = OCC[r:range(1, 14)]
      end
      rel.full = rel.first .. " " .. SURN[s + 1]
      kp.rel = rel
      ro[k] = kp
      self.people[s] = { kp, rel }
    end
    self.roster[e] = ro
  end
  self.keeperSurs = used
end

function Fiche:keeperOn(dn)
  local y = dateOf(dn)
  local e = min(5, (y - YEAR0) // 4 + 1)
  return self.roster[e][dn % 3 + 1]
end

------------------------------------------------------------------------
-- case generation. Every case returns:
--   q, steps = { {reel, label, summary, read?} }, options, answer,
--   plants (lines placed into the generated archive), reserved ships
------------------------------------------------------------------------
-- an event day whose next Gazette issue falls in the same month
local function pickEventDay(r, y0, y1, avoidY, avoidM)
  for _ = 1, 60 do
    local y = r:range(y0, y1)
    local m = r:range(1, 12)
    if not (y == avoidY and m == avoidM) then
      local d = r:range(2, MLEN[(y - YEAR0) * 12 + m])
      local dn = dayNum(y, m, d)
      local gi = issueAfter(dn)
      local iy, im = dateOf(issueDay(gi))
      if iy == y and im == m then return dn, gi, y, m, d end
    end
  end
  local dn = dayNum(y0, 3, 3)
  return dn, issueAfter(dn), y0, 3, 3
end

local function lossItem(fi, dn, ship, stype, key)
  local _, m, d = dateOf(dn)
  return { reel = GAZ, frame = fi, key = key, title = "LOSS OF THE " .. SHIPS[ship + 1],
    body = { "The " .. stype .. " " .. SHIPS[ship + 1] .. " went", "down off Grey Rock on the",
      "night of " .. wday(dn) .. " " .. d .. " " .. MON[m] .. "." } }
end

local function fatePlant(ship, dn, key, master)
  local y, m = dateOf(dn)
  return { reel = REG, frame = ship, key = key, master = master,
    fate1 = "FATE: lost off Grey Rock,", fate2 = "  " .. MON[m] .. " " .. y .. ", all hands." }
end

local function similarShip(s)
  if s % 5 < 4 then return s + 1 end
  return s - 1
end

local function addOption(opts, v)
  for i = 1, #opts do if opts[i] == v then return false end end
  opts[#opts + 1] = v
  return true
end

-- kinds: "tutor" (2 records), "lost3", "gale" (3), "lost4", "watch" (4)
function Fiche:makeCase(kind, caseSeed, level)
  local r = U.rng(caseSeed)
  local c = { kind = kind, seed = caseSeed, level = level, plants = {}, reserved = {}, steps = {} }
  local P = c.plants
  local extra = level >= 3
  if kind == "tutor" then
    local dn, gi, y, m, d = pickEventDay(r, 1884, 1884)
    for _ = 1, 30 do
      if m == 3 then break end
      dn, gi, y, m, d = pickEventDay(r, 1884, 1884)
    end
    if m ~= 3 then d = 5 m = 3 dn = dayNum(1884, 3, 5) gi = issueAfter(dn) end
    local s = r:range(0, #SHIPS - 1)
    local stype = r:pick(SHIPTYPE)
    c.reserved[s] = true
    P[#P + 1] = lossItem(gi, dn, s, stype, 1)
    P[#P + 1] = { reel = LOG, day = dn, weather = "NW8 STORM", key = 0 }
    local K = self:keeperOn(dn)
    c.q = "The " .. SHIPS[s + 1] .. " was lost in MAR 1884. Who was on watch at Grey Rock that night?"
    c.steps[1] = { reel = GAZ, label = "GAZETTE: report of the loss", summary = "Lost night of " .. d .. " " .. MON[m] .. " " .. y }
    c.steps[2] = { reel = LOG, label = "LOG: who kept the watch", read = true }
    local opts = { K.abbrev }
    addOption(opts, self:keeperOn(dn + 1).abbrev)
    addOption(opts, self:keeperOn(dn + 2).abbrev)
    addOption(opts, self.roster[1 + (((y - YEAR0) // 4 + 2) % 5)][1].abbrev)
    c.options, c.answerText = opts, K.abbrev
    c.eventDay, c.issue, c.logFrame, c.ship = dn, gi, dn // 7, s
  elseif kind == "lost3" or kind == "lost4" then
    local dn, gi, y, m, d = pickEventDay(r, 1881, 1898)
    local s = r:range(0, #SHIPS - 1)
    local h = similarShip(s)
    local o
    repeat o = r:range(0, #SHIPS - 1) until o ~= s and o ~= h
    c.reserved[s], c.reserved[h], c.reserved[o] = true, true, true
    local stype, htype, otype = r:pick(SHIPTYPE), r:pick(SHIPTYPE), r:pick(SHIPTYPE)
    local four = kind == "lost4"
    local kG, kL = four and 2 or 1, four and 3 or 2
    -- the real loss
    P[#P + 1] = lossItem(gi, dn, s, stype, kG)
    P[#P + 1] = fatePlant(s, dn, four and 1 or 0)
    P[#P + 1] = { reel = LOG, day = dn, weather = "NW8 STORM", key = kL }
    -- herring 1: a near-identical name lost in another month
    local dn3, gi3 = pickEventDay(r, 1881, 1898, y, m)
    P[#P + 1] = lossItem(gi3, dn3, h, htype, -1)
    P[#P + 1] = fatePlant(h, dn3, -1)
    P[#P + 1] = { reel = LOG, day = dn3, weather = "NW8 STORM", key = -1 }
    -- herring 2: another vessel lost the same month on a different night
    local d2 = d
    for _ = 1, 40 do
      d2 = r:range(2, MLEN[(y - YEAR0) * 12 + m])
      local iy, im = dateOf(issueDay(issueAfter(dayNum(y, m, d2))))
      if d2 ~= d and abs(d2 - d) > 1 and iy == y and im == m then break end
    end
    if d2 ~= d then
      local dn2 = dayNum(y, m, d2)
      P[#P + 1] = lossItem(issueAfter(dn2), dn2, o, otype, -1)
      P[#P + 1] = fatePlant(o, dn2, -1)
      P[#P + 1] = { reel = LOG, day = dn2, weather = "NW8 STORM", key = -1 }
    end
    if extra then
      -- herring 3: an anxious notice the week before
      local prev = gi - 1
      if prev >= 0 then
        P[#P + 1] = { reel = GAZ, frame = prev, key = -1, title = "FEARS FOR THE " .. SHIPS[s + 1],
          body = { "The " .. SHIPS[s + 1] .. " is overdue.", "Her owners are anxious." } }
      end
    end
    local K = self:keeperOn(dn)
    local name = SHIPS[s + 1]
    if four then
      c.q = "The " .. stype .. " " .. name .. " was lost off Grey Rock. Who kept the light that night?"
      c.steps[1] = { reel = REG, label = "REGISTRY: the " .. name .. "'s fate", summary = name .. " lost " .. MON[m] .. " " .. y }
    else
      c.q = "The " .. stype .. " " .. name .. " was lost off Grey Rock in " .. MON[m] .. " " .. y .. ". Who kept the light that night?"
    end
    c.steps[#c.steps + 1] = { reel = GAZ, label = "GAZETTE: the night of the loss", summary = "Lost night of " .. d .. " " .. MON[m] .. " " .. y }
    c.steps[#c.steps + 1] = { reel = LOG, label = "LOG: the watch that night", summary = "On watch: " .. K.abbrev }
    c.steps[#c.steps + 1] = { reel = PAR, label = "PARISH: the keeper's name", read = true }
    local opts = { K.full }
    addOption(opts, K.rel.full)
    addOption(opts, self:keeperOn(dn - 1).full)
    addOption(opts, self:keeperOn(dn + 1).full)
    c.options, c.answerText = opts, K.full
    c.eventDay, c.issue, c.logFrame, c.ship, c.parishFrame = dn, gi, dn // 7, s, K.sur
  elseif kind == "gale" then
    local dn, gi, y, m, d = pickEventDay(r, 1881, 1898)
    local K = self:keeperOn(dn)
    local g1i = r:pick({ "E", "M", "H", "S" })
    local grp = FEMALE[g1i]
    local a = r:range(1, #grp)
    local g1, g3 = grp[a], grp[a % #grp + 1]
    local g2
    repeat
      local gi2 = r:pick(FEMALE_INIT)
      local gg = FEMALE[gi2]
      g2 = gg[r:range(1, #gg)]
    until g2 ~= g1 and g2 ~= g3
    local m3 = (m + r:range(2, 9) - 1) % 12 + 1
    local d3 = r:range(1, 28)
    P[#P + 1] = { reel = PAR, frame = K.sur, key = 0, first = g1, born = y + m / 13,
      bornStr = d .. " " .. MON[m] .. " " .. y, occ = "  dau. of " .. titleCase(K.first) }
    P[#P + 1] = { reel = PAR, frame = K.sur, key = 0, first = g2, born = y - 2,
      bornStr = YEARSTR[y - 2] or tostring(y - 2), occ = "  dau. of " .. titleCase(K.first) }
    P[#P + 1] = { reel = PAR, frame = K.sur, key = 0, first = g3, born = y + m3 / 13,
      bornStr = d3 .. " " .. MON[m3] .. " " .. y, occ = "  dau. of " .. titleCase(K.rel.first) }
    P[#P + 1] = { reel = GAZ, frame = gi, key = 1, title = "THE GREAT GALE",
      body = { "Grey Rock light stood firm", "through the great gale on", "the night of " .. wday(dn) .. " " .. d .. " " .. MON[m] .. "." } }
    -- herring: a warning in another issue that year
    local fy = issueAfter(dayNum(y, 1, 1))
    local ly = issueAfter(dayNum(y, 12, 1)) - 1
    local wi = gi
    for _ = 1, 20 do
      wi = r:range(fy, ly)
      if abs(wi - gi) > 2 then break end
    end
    P[#P + 1] = { reel = GAZ, frame = wi, key = -1, title = "GALE WARNING",
      body = { "A gale is feared. The", "glass is falling fast." } }
    if extra then
      local wi2 = min(ly, gi + 2)
      P[#P + 1] = { reel = GAZ, frame = wi2, key = -1, title = "AFTER THE GALE",
        body = { "Slates are down on the", "chapel roof again." } }
    end
    P[#P + 1] = { reel = LOG, day = dn, weather = "W10 GALE", note = "   daughter born to keeper", key = 2 }
    local sur = SURN[K.sur + 1]
    c.q = "A girl was born at Grey Rock light in the great gale of " .. y .. ". What was she christened?"
    c.steps[1] = { reel = GAZ, label = "GAZETTE: the great gale", summary = "Gale: night of " .. d .. " " .. MON[m] .. " " .. y }
    c.steps[2] = { reel = LOG, label = "LOG: the keeper that night", summary = "Father on watch: " .. K.abbrev }
    c.steps[3] = { reel = PAR, label = "PARISH: his daughter", read = true }
    local opts = { g1 .. " " .. sur }
    addOption(opts, g3 .. " " .. sur)
    addOption(opts, g2 .. " " .. sur)
    for _ = 1, 20 do
      local gg = FEMALE[r:pick(FEMALE_INIT)]
      if addOption(opts, gg[r:range(1, #gg)] .. " " .. sur) then break end
    end
    c.options, c.answerText = opts, g1 .. " " .. sur
    c.eventDay, c.issue, c.logFrame, c.parishFrame = dn, gi, dn // 7, K.sur
  else -- "watch"
    local dn, gi, y, m, d = pickEventDay(r, 1881, 1898)
    local K = self:keeperOn(dn)
    local s = r:range(0, #SHIPS - 1)
    local h = similarShip(s)
    local o
    repeat o = r:range(0, #SHIPS - 1) until o ~= s and o ~= h
    c.reserved[s], c.reserved[h], c.reserved[o] = true, true, true
    local ms
    repeat ms = r:range(0, #SURN - 1) until not self.keeperSurs[ms]
    local rn = MALE.R
    local ra = r:range(1, #rn)
    local rn1, rn2 = rn[ra], rn[ra % #rn + 1]
    local master = "R." .. SURN[ms + 1]
    local name, hname = SHIPS[s + 1], SHIPS[h + 1]
    P[#P + 1] = { reel = PAR, frame = ms, key = 1, first = rn1, born = r:range(1830, 1850), occ = "  drowned with the " .. name }
    P[#P + 1] = { reel = PAR, frame = ms, key = -1, first = rn2, born = r:range(1830, 1850), occ = "  master of the " .. hname }
    P[#P + 1] = fatePlant(s, dn, 2, master)
    P[#P + 1] = { reel = REG, frame = h, key = -1, master = master, fate1 = "FATE: sold abroad " .. (y + r:range(1, 3)), fate2 = nil }
    P[#P + 1] = lossItem(gi, dn, s, r:pick(SHIPTYPE), 3)
    P[#P + 1] = { reel = LOG, day = dn, weather = "NW8 STORM", key = 0 }
    local d2 = d
    for _ = 1, 40 do
      d2 = r:range(2, MLEN[(y - YEAR0) * 12 + m])
      local iy, im = dateOf(issueDay(issueAfter(dayNum(y, m, d2))))
      if abs(d2 - d) > 1 and iy == y and im == m then break end
    end
    if d2 ~= d then
      local dn2 = dayNum(y, m, d2)
      P[#P + 1] = lossItem(issueAfter(dn2), dn2, o, r:pick(SHIPTYPE), -1)
      P[#P + 1] = fatePlant(o, dn2, -1)
    end
    c.q = "Capt. " .. master .. " went down with his ship. Who kept the Grey Rock light that night?"
    c.steps[1] = { reel = PAR, label = "PARISH: the drowned captain", summary = titleCase(rn1) .. " drowned: the " .. name }
    c.steps[2] = { reel = REG, label = "REGISTRY: his ship's fate", summary = name .. " lost " .. MON[m] .. " " .. y }
    c.steps[3] = { reel = GAZ, label = "GAZETTE: the night", summary = "Lost night of " .. d .. " " .. MON[m] .. " " .. y }
    c.steps[4] = { reel = LOG, label = "LOG: who kept the watch", read = true }
    local opts = { K.abbrev }
    addOption(opts, self:keeperOn(dn - 1).abbrev)
    addOption(opts, self:keeperOn(dn + 1).abbrev)
    local e = (y - YEAR0) // 4 + 1
    local other = self.roster[e % 5 + 1]
    for i = 1, 3 do if #opts < 4 then addOption(opts, other[i].abbrev) end end
    c.options, c.answerText = opts, K.abbrev
    c.eventDay, c.issue, c.logFrame, c.ship, c.parishFrame = dn, gi, dn // 7, s, ms
  end
  -- shuffle the options and remember where the truth landed
  r:shuffle(c.options)
  for i = 1, #c.options do if c.options[i] == c.answerText then c.answer = i end end
  c.records = #c.steps
  c.ask = (kind == "gale") and "WHAT WAS HER NAME?" or ((kind == "lost3" or kind == "lost4") and "WHO KEPT THE LIGHT?" or "WHO KEPT THE WATCH?")
  c.qLines = UI.wrap(c.q, 232, UI.font)
  for i = 1, #c.steps do c.steps[i].done = false end
  return c
end

------------------------------------------------------------------------
-- frame generation into cache slots (no storage of the archive)
------------------------------------------------------------------------
local function addLine(s, str, key)
  local n = s.n + 1
  s.n = n
  s.lines[n] = str
  s.keys[n] = key or 0
end

function Fiche:initSlots()
  self.slots = {}
  for i = 1, NSLOT do
    self.slots[i] = { reel = 0, frame = -1, use = 0, top = "", headline = "", hkey = 0, n = 0, lines = {}, keys = {}, lw = {}, maxW = 0 }
  end
  self.useClock = 0
  self.grng = U.rng(1)
end

function Fiche:flushSlots()
  for i = 1, NSLOT do self.slots[i].frame = -1 end
end

function Fiche:getFrame(reel, fi)
  self.useClock = self.useClock + 1
  local slots = self.slots
  local lru, lruUse = slots[1], 1e12
  for i = 1, NSLOT do
    local s = slots[i]
    if s.reel == reel and s.frame == fi then s.use = self.useClock return s end
    if s.use < lruUse then lru, lruUse = s, s.use end
  end
  self:genFrame(lru, reel, fi)
  lru.reel, lru.frame, lru.use = reel, fi, self.useClock
  return lru
end

function Fiche:genFrame(s, reel, fi)
  s.n = 0
  s.hkey = 0
  local r = self.grng
  r:seed((self.worldSeed + reel * 7919 + fi * 104729) % 2147483647 + 1)
  if reel == GAZ then self:genGazette(s, fi, r)
  elseif reel == LOG then self:genLog(s, fi, r)
  elseif reel == REG then self:genRegistry(s, fi, r)
  else self:genParish(s, fi, r) end
  local mw = 0
  for i = 1, s.n do
    local w = UI.width(s.lines[i])
    if w > mw then mw = w end
    s.lw[i] = min(FW - 20, floor(w * 0.72))
  end
  s.maxW = max(mw, UI.width(s.headline, UI.bold))
end

function Fiche:plantsFor(reel)
  return self.case and self.case.plants or nil
end

function Fiche:fillerItem(s, r, y)
  local k = r:range(1, 11)
  if k == 1 then addLine(s, "FISH PRICES") addLine(s, fmt("Herring %ds the cran.", r:range(8, 30)))
  elseif k == 2 then addLine(s, "WEATHER") addLine(s, fmt("Wind %s, %s.", r:pick(WINDS), r:pick(SKIES)))
  elseif k == 3 then addLine(s, "HAND-TURNERS") addLine(s, "The Society meets Thurs.") addLine(s, "Bring your own oil.")
  elseif k == 4 then addLine(s, "LOST") addLine(s, fmt("A %s, by the quay.", r:pick(LOSTS)))
  elseif k == 5 then
    local sh = r:range(0, #SHIPS - 1)
    local res = self.case and self.case.reserved
    for _ = 1, 8 do if res and res[sh] then sh = (sh + 7) % #SHIPS end end
    if res and res[sh] then sh = (sh + 3) % #SHIPS end
    addLine(s, "ARRIVED") addLine(s, fmt("The %s, with %s.", SHIPS[sh + 1], r:pick(CARGO)))
  elseif k == 6 then addLine(s, "TIDES") addLine(s, fmt("High water %d.%02d.", r:range(1, 12), r:range(0, 59)))
  elseif k == 7 or k == 11 then addLine(s, "NOTICE") addLine(s, r:pick(NOTICES))
  elseif k == 8 then addLine(s, "BIRTHS") addLine(s, fmt("A son, to Mrs %s.", SURN[r:range(1, #SURN)]))
  elseif k == 9 then addLine(s, "LAMP OIL") addLine(s, fmt("Paraffin %dd the gallon.", r:range(6, 14)))
  else addLine(s, "SERMON") addLine(s, fmt("Rev. %s on %s.", SURN[r:range(1, #SURN)], r:pick(TOPICS))) end
end

function Fiche:genGazette(s, fi, r)
  local dn = issueDay(fi)
  local y, m, d = dateOf(dn)
  s.top = fmt("GAZETTE  SAT %d %s %d", d, MON[m], y)
  local P = self:plantsFor(GAZ)
  local lead = false
  local later = 0
  if P then
    for i = 1, #P do
      local p = P[i]
      if p.reel == GAZ and p.frame == fi then
        if not lead then
          lead = true
          s.headline, s.hkey = p.title, p.key
          for j = 1, #p.body do addLine(s, p.body[j], p.key) end
        else
          later = later + 1
        end
      end
    end
  end
  if not lead then s.headline = HEADLINES[r:range(1, #HEADLINES)] end
  self:fillerItem(s, r, y)
  if later > 0 then
    local seen = 0
    for i = 1, #P do
      local p = P[i]
      if p.reel == GAZ and p.frame == fi then
        seen = seen + 1
        if seen > 1 then
          addLine(s, p.title, p.key)
          for j = 1, #p.body do addLine(s, p.body[j], p.key) end
        end
      end
    end
  end
  local guard = 0
  while s.n < 9 and guard < 5 do
    guard = guard + 1
    self:fillerItem(s, r, y)
  end
end

function Fiche:genLog(s, fi, r)
  local d0 = fi * 7
  local d1 = min(TOTAL_DAYS - 1, d0 + 6)
  local y0, m0, dd0 = dateOf(d0)
  local y1, m1, dd1 = dateOf(d1)
  s.top = "GREY ROCK LIGHT LOG"
  if m0 == m1 then s.headline = fmt("WEEK %d-%d %s %d", dd0, dd1, MON[m0], y0)
  else s.headline = fmt("%d %s-%d %s %d", dd0, MON[m0], dd1, MON[m1], y1) end
  local P = self:plantsFor(LOG)
  for dn = d0, d1 do
    local _, _, d = dateOf(dn)
    local kp = self:keeperOn(dn)
    local weather = WEATHER[r:range(1, #WEATHER)]
    local key, note = 0, nil
    if P then
      for i = 1, #P do
        local p = P[i]
        if p.reel == LOG and p.day == dn then
          weather = p.weather or weather
          if p.key ~= 0 then key = p.key end
          note = p.note or note
        end
      end
    end
    addLine(s, fmt("%2d %s %s %s", d, wday(dn), kp.abbrev, weather), key)
    if note then addLine(s, note, key) end
  end
end

function Fiche:genRegistry(s, fi, r)
  s.top = fmt("HARBOUR REGISTRY  No.%d", fi + 1)
  s.headline = SHIPS[fi + 1]
  local stype = SHIPTYPE[r:range(1, #SHIPTYPE)]
  local tons = r:range(18, 420)
  local port = PORTS[r:range(1, #PORTS)]
  local built = r:range(1838, 1884)
  local master = MALE_INIT[r:range(1, #MALE_INIT)] .. "." .. SURN[r:range(1, #SURN)]
  local plant = nil
  local P = self:plantsFor(REG)
  if P then
    for i = 1, #P do
      local p = P[i]
      if p.reel == REG and p.frame == fi then plant = p end
    end
  end
  if plant and plant.master then master = plant.master end
  addLine(s, fmt("%s, %d tons", stype, tons))
  addLine(s, fmt("built %s %d", port, built))
  addLine(s, "master " .. master)
  addLine(s, "port of " .. PORTS[r:range(1, #PORTS)])
  if plant then
    addLine(s, plant.fate1, plant.key)
    if plant.fate2 then addLine(s, plant.fate2, plant.key) end
  else
    local f = r:range(1, 4)
    if f == 1 then addLine(s, "FATE: in service")
    elseif f == 2 then addLine(s, fmt("FATE: broken up %d", r:range(1880, 1899)))
    elseif f == 3 then addLine(s, fmt("FATE: sold abroad %d", r:range(1880, 1899)))
    else
      addLine(s, "FATE: lost off " .. FARPLACE[r:range(1, #FARPLACE)] .. ",")
      addLine(s, fmt("  %s %d.", MON[r:range(1, 12)], r:range(built + 1, 1879)))
    end
  end
end

-- parish: people are gathered into a scratch list, sorted by birth, then written
local scratchPeople = {}
local scratchNames = {}
local function byBorn(a, b) return a.born < b.born end

function Fiche:genParish(s, fi, r)
  s.top = "PARISH REGISTER"
  s.headline = SURN[fi + 1]
  local list = scratchPeople
  for i = #list, 1, -1 do list[i] = nil end
  local names = scratchNames
  for k in pairs(names) do names[k] = nil end
  local world = self.people[fi]
  if world then
    for i = 1, #world do list[#list + 1] = world[i] names[world[i].first] = true end
  end
  local P = self:plantsFor(PAR)
  if P then
    for i = 1, #P do
      local p = P[i]
      if p.reel == PAR and p.frame == fi then list[#list + 1] = p names[p.first] = true end
    end
  end
  local want = min(6, #list + r:range(2, 4))
  local guard = 0
  while #list < want and guard < 20 do
    guard = guard + 1
    local female = r:chance(0.5)
    local tab = female and FEMALE or MALE
    local inits = female and FEMALE_INIT or MALE_INIT
    local grp = tab[inits[r:range(1, #inits)]]
    local first = grp[r:range(1, #grp)]
    if not names[first] then
      names[first] = true
      list[#list + 1] = { first = first, born = r:range(1808, 1878), occ = OCC[r:range(1, #OCC)], filler = true }
    end
  end
  table.sort(list, byBorn)
  for i = 1, #list do
    local p = list[i]
    local key = p.key or 0
    addLine(s, fmt("%s  b.%s", p.first, p.bornStr or tostring(floor(p.born))), key)
    if p.keeper then
      addLine(s, fmt("  Grey Rock keeper %d-%02d", p.from, p.to % 100), key)
    elseif p.filler then
      addLine(s, "  " .. p.occ, key)
    else
      addLine(s, p.occ:sub(1, 2) == "  " and p.occ or ("  " .. p.occ), key)
    end
  end
end

-- plain-text dump of a frame for tests: top, headline, lines..., keys
function Fiche:frameText(reel, fi)
  local s = self:getFrame(reel, fi)
  local lines, keys = {}, {}
  for i = 1, s.n do lines[i] = s.lines[i] keys[i] = s.keys[i] end
  return { top = s.top, headline = s.headline, hkey = s.hkey, lines = lines, keys = keys }
end

------------------------------------------------------------------------
-- lifecycle
------------------------------------------------------------------------
function Fiche:enter(params)
  self.t = 0
  self.worldSeed = self.rng:range(1, 1000000000)
  self:makeWorld(self.worldSeed)
  self:initSlots()
  self.reel = GAZ
  self.pos = { 0, 0, 0, 0 }
  self.vel = 0
  self.pend = 0
  self.gear = 1
  self.mag = false
  self.cursor = 0
  self.scrollY = 0
  self.panX = 0
  self.view = "reel"
  self.loadT = 0
  self.nextReel = GAZ
  self.blur = 0
  self.lastFi = 0
  self.clicks = 0
  self.framesMoved = 0
  self.topSpeed = 0
  self.braking = 0
  self.brakeFromSpeed = false
  self.brakedStop = false
  self.flap = 0
  self.accSel = 1
  self.msg, self.msgT = nil, 0
  self.score = 0
  self.solved = 0
  self.strikes = 0
  self.caseIdx = 0
  self.mistakes = 0
  self.caseMistakes = 0
  self.caseT = 0
  self.caseState = "open"
  self.caseEndT = 0
  self.flicker = 0
  self.hdrSec = -1
  self.hdrStr = ""
  self.stuckHigh = self.params.challengeId == "slip"
  if self.stuckHigh then self.gear = 2 end
  if self.mode == "standard" then
    self.timeLeft = ({ 480, 420, 390 })[self.difficulty] or 420
  else
    self.timeLeft = 0
  end
  self.hum = Audio.Hum.new(Audio.TRIANGLE)
  self.rustle = Audio.Hum.new(Audio.NOISE)
  self.squeal = Audio.Hum.new(Audio.SINE)
  self:nextCase(true)
  if self.mode == "tutorial" then self:setupCoach() end
end

function Fiche:exit()
  self.hum:stop()
  self.rustle:stop()
  self.squeal:stop()
end

function Fiche:caseKind(idx)
  local lvl = self.difficulty - 1
  if self.mode == "endless" then
    lvl = lvl + (idx - 1) // 2
    if self.params.challengeId == "night" then lvl = max(lvl, 3) end
  end
  if self.mode == "tutorial" then return "tutor", 0 end
  local kinds
  if lvl <= 0 then kinds = { "lost3", "gale", "lost3" }
  elseif lvl == 1 then kinds = { "lost3", "gale", "watch" }
  else kinds = { "lost4", "watch", "gale" } end
  if self.params.challengeId == "night" then kinds = { "lost4", "watch", "lost4" } end
  return kinds[(idx - 1) % 3 + 1], lvl
end

function Fiche:nextCase(first)
  self.caseIdx = self.caseIdx + 1
  local kind, lvl = self:caseKind(self.caseIdx)
  self.caseSeed = self.rng:range(1, 1000000000)
  self.case = self:makeCase(kind, self.caseSeed, lvl)
  self:flushSlots()
  self.caseT = 0
  self.caseMistakes = 0
  self.caseState = "open"
  self.caseEndT = 0
  self.accSel = 1
  self.caseLimit = max(110, 200 - (self.caseIdx - 1) * 8 - (self.difficulty - 1) * 15)
  if not first or self.mode ~= "tutorial" then self.view = "file" end
  if self.mode == "tutorial" then self.view = "reel" end
  if not first then Audio.sfx.whoosh(0.2) end
end

------------------------------------------------------------------------
-- tutorial
------------------------------------------------------------------------
function Fiche:setupCoach()
  local s = self
  local c = self.case
  local iy, im, id = dateOf(issueDay(c.issue))
  local issueName = "SAT " .. id .. " " .. MON[im] .. " " .. iy
  self.coach = UI.Coach.new({
    { text = "Crank slowly. Each click is one frame of film: one week of the Gazette.",
      check = function() return s.clicks >= 3 end },
    { text = "Press A for HIGH gear, then crank hard. Watch the years fly past.",
      check = function() return s.gear == 2 and abs(s.vel) > 35 end },
    { text = "Let go: the spool coasts on. Crank BACKWARDS to brake it to a stop.",
      check = function() return s.brakedStop end },
    { text = "Find the Gazette of " .. issueName .. ". A for LOW gear to creep the last frames.",
      check = function() return s.reel == GAZ and s:curFrame() == c.issue and abs(s.vel) < 0.5 end, hold = 0.3 },
    { text = "B magnifies. UP/DOWN moves the cursor. Press A on the report to clip it.",
      check = function() return c.steps[1].done end },
    { text = "It names the night. B to step back, then RIGHT to load the LIGHT LOG reel.",
      check = function() return s.reel == LOG and s.view == "reel" end },
    { text = "Find the week of that night in the log. Magnify it and read who kept watch.",
      check = function() return s.reel == LOG and s.mag and s:curFrame() == c.logFrame and abs(s.vel) < 0.5 end, hold = 0.6 },
    { text = "B, then UP opens the case file. A to accuse: pick the keeper, press A.",
      check = function() return s.solved > 0 end },
  }, { y = 20, h = 46, anchor = "top" })
end

------------------------------------------------------------------------
-- mechanics
------------------------------------------------------------------------
function Fiche:curFrame()
  local N = N_FRAMES[self.reel]
  return U.clamp(floor(self.pos[self.reel] + 0.5), 0, N - 1)
end

function Fiche:say(text, secs)
  self.msg, self.msgT = text, secs or 1.4
end

function Fiche:cranked(change)
  if self.view == "loading" or self.finished then return end
  self.pend = self.pend + change
end

function Fiche:physics(dt)
  local reel = self.reel
  local ratio = (self.gear == 2) and HI_RATIO or LO_RATIO
  local crankRate = self.pend / dt           -- deg/s at the handle
  self.pend = 0
  local hand = crankRate * ratio             -- frames/s the hand asks for
  local v = self.vel
  local driving = false
  local brakeDec = 0
  if hand ~= 0 then
    if abs(v) < 0.05 or (hand > 0) == (v > 0) then
      if abs(hand) >= abs(v) then
        -- freewheel clutch engages: the hand accelerates the spool
        local k = (self.gear == 2) and 6.5 or 22
        v = v + (hand - v) * min(1, k * dt)
        driving = true
      end
    else
      -- counter-crank: brake shoe
      brakeDec = abs(crankRate) * BRAKE
      local dv = brakeDec * dt
      if dv >= abs(v) then v = 0 else v = v - U.sign(v) * dv end
      if abs(self.vel) > 20 then self.brakeFromSpeed = true end
    end
  end
  self.braking = U.damp(self.braking, U.clamp(brakeDec / 200, 0, 1), 14, dt)
  if not driving then
    -- bearing friction: the gear train drags harder in LOW
    local fr = (self.gear == 2) and 0.45 or 2.6
    v = v * exp(-fr * dt)
    local c = 1.2 * dt
    if abs(v) <= c then v = 0 else v = v - U.sign(v) * c end
    -- sprung detent pulls the nearest frame into the gate
    if abs(v) < 3 then
      local p = self.pos[reel]
      local target = floor(p + 0.5)
      v = v + (target - p) * 60 * dt
      v = v * exp(-8 * dt)
      if abs(v) < 0.04 and abs(target - p) < 0.01 then v = 0 self.pos[reel] = target end
    end
  end
  if v > VMAX then v = VMAX elseif v < -VMAX then v = -VMAX end
  local p = self.pos[reel] + v * dt
  local N = N_FRAMES[reel]
  if p < 0 or p > N - 1 then
    p = U.clamp(p, 0, N - 1)
    if abs(v) > 12 then
      -- the tail runs off the spool
      Audio.sfx.thud(0.6)
      Audio.sfx.clack(0.4)
      self:shake(min(6, abs(v) / 18))
      self.flap = 1
      self:say(p <= 0 and "START OF REEL" or "END OF REEL", 1)
    end
    v = 0
  end
  self.pos[reel] = p
  self.vel = v
  if self.brakeFromSpeed and abs(v) < 0.3 then self.brakedStop = true end
  local av = abs(v)
  if av > self.topSpeed then self.topSpeed = av end
  if av >= 100 and not self.blurAward then self.blurAward = true self:award("blur") end
  -- blur: text smears at speed (sooner when magnified)
  local b
  if self.mag then b = U.clamp((av - 1.2) / 3, 0, 1) else b = U.clamp((av - 5) / 12, 0, 1) end
  self.blur = b
  -- detent click per frame
  local fi = floor(p + 0.5)
  if fi ~= self.lastFi then
    local moved = abs(fi - self.lastFi)
    self.framesMoved = self.framesMoved + moved
    self.clicks = self.clicks + 1
    if av < 28 then
      Audio.sfx.tick(1500 + min(900, av * 30), 0.1 + min(0.12, av * 0.01))
    end
    self.lastFi = fi
  end
end

function Fiche:changeReel(dir)
  if abs(self.vel) > 1 then
    Audio.sfx.denied()
    self:say("BRAKE THE SPOOL FIRST")
    return
  end
  local nr = (self.reel - 1 + dir) % 4 + 1
  self.nextReel = nr
  self.view = "loading"
  self.loadT = 0
  self.vel = 0
  Audio.sfx.whoosh(0.25)
  Audio.sfx.click(0.3)
end

function Fiche:clip()
  local c = self.case
  if self.blur > 0.2 or abs(self.vel) > 1.2 then
    Audio.sfx.denied()
    self:say("HOLD THE FILM STILL")
    return
  end
  local s = self:getFrame(self.reel, self:curFrame())
  local key = (self.cursor == 0) and s.hkey or (s.keys[self.cursor] or 0)
  local st = key > 0 and c.steps[key] or nil
  if st and not st.read then
    if st.done then
      Audio.sfx.menuMove()
      self:say("ALREADY IN THE FILE")
      return
    end
    st.done = true
    Audio.sfx.snap(0.5)
    Audio.sfx.stamp()
    self:flash(1)
    self:shake(1.5)
    self.clipFlash = 1
    if self:ready() then self:say("CHAIN COMPLETE - UP: FILE", 2.2) Audio.sfx.gear()
    else self:say("CLIPPED TO THE FILE") end
  else
    Audio.sfx.denied()
    self:shake(2)
    self.mistakes = self.mistakes + 1
    self.caseMistakes = self.caseMistakes + 1
    if self.mode == "standard" then
      self.timeLeft = self.timeLeft - 10
      self.score = max(0, self.score - 25)
      self:say("DOESN'T FIT  -10s")
    elseif self.mode == "endless" then
      self.caseT = self.caseT + 10
      self:say("DOESN'T FIT  -10s")
    else
      self:say("DOESN'T FIT THE CASE")
    end
  end
end

function Fiche:ready()
  local c = self.case
  for i = 1, #c.steps do
    if not c.steps[i].read and not c.steps[i].done then return false end
  end
  return true
end

function Fiche:accuse(i)
  local c = self.case
  if i == c.answer then
    local secs = self.caseT
    local gained = 1000 + max(0, floor(600 - 4 * secs))
    if self.mode == "endless" then gained = gained + 100 * (self.caseIdx - 1) end
    if self.caseMistakes == 0 then gained = gained + 150 end
    self.lastGain = gained
    if self.mode ~= "tutorial" then self.score = self.score + gained end
    self.solved = self.solved + 1
    self.caseState = "solved"
    Audio.sfx.success()
    self:shake(3)
    self:statAdd("solved", 1)
    local rec = Save.machine(self.def.id).stats
    local tenths = floor(secs * 10)
    if self.mode ~= "tutorial" and (not rec.fastest or rec.fastest == 0 or tenths < rec.fastest) then rec.fastest = tenths Save.markDirty() end
    self:award("first")
    if self.caseMistakes == 0 and self.mode ~= "tutorial" then self:award("clean") end
    if c.records >= 4 and secs < 75 then self:award("quick") end
  else
    self.caseState = "wrong"
    self.lastGain = 0
    self.strikes = self.strikes + 1
    Audio.sfx.fail()
    self:shake(5)
  end
  self.caseEndT = 0
  self.view = "reel"
  if self.mode == "tutorial" and self.caseState == "wrong" then
    -- a gentle lesson: let them try again
    self.caseState = "open"
    self.view = "file"
    self:say("NOT THEM. READ THE LOG AGAIN.", 2)
  end
end

function Fiche:caseCold()
  self.caseState = "cold"
  self.strikes = self.strikes + 1
  self.caseEndT = 0
  self.lastGain = 0
  self.view = "reel"
  Audio.sfx.fail()
end

function Fiche:advanceCase()
  if self.mode == "standard" then
    if self.caseIdx >= STD_CASES then self:endRun(true) return end
  elseif self.mode == "endless" then
    if self.strikes >= 3 then self:endRun(true) return end
  end
  self:nextCase(false)
end

function Fiche:endRun(complete)
  if self.finished then return end
  self:statAdd("frames", self.framesMoved)
  self.framesMoved = 0
  self:statMax("topspeed", floor(self.topSpeed))
  self.hum:stop() self.rustle:stop() self.squeal:stop()
  if self.mode == "standard" then
    local bonus = max(0, floor(self.timeLeft)) * 3
    if self.solved > 0 then self.score = self.score + bonus else bonus = 0 end
    if self.solved >= STD_CASES then self:award("archive") end
    self:finish({ success = self.solved > 0, score = self.score,
      title = self.solved >= STD_CASES and "ARCHIVE CLOSED" or (self.timeLeft <= 0 and "ROOM CLOSED" or "CASES CLOSED"),
      lines = { "Cases solved: " .. self.solved .. "/" .. STD_CASES, "Bad clips: " .. self.mistakes, "Time bonus: " .. bonus } })
  else
    self:finish({ success = self.solved > 0, score = self.score, title = "THREE STRIKES",
      lines = { "Cases solved: " .. self.solved, "Bad clips: " .. self.mistakes, "Top speed: " .. floor(self.topSpeed) .. " fr/s" } })
  end
end

------------------------------------------------------------------------
-- input
------------------------------------------------------------------------
function Fiche:buttonDown(b)
  if self.view == "loading" then return end
  if self.caseState ~= "open" then
    if b == Input.A and self.caseEndT > 0.8 and self.mode ~= "tutorial" then self:advanceCase() end
    return
  end
  if self.view == "file" then
    if b == Input.A then
      if self:ready() then
        self.view = "accuse"
        Audio.sfx.menuSelect()
      else
        Audio.sfx.denied()
        self:say("THE CHAIN IS NOT COMPLETE")
      end
    elseif b == Input.B or b == Input.UP or b == Input.DOWN then
      self.view = "reel"
      Audio.sfx.back()
    end
    return
  end
  if self.view == "accuse" then
    local n = #self.case.options
    if b == Input.UP then self.accSel = (self.accSel - 2) % n + 1 Audio.sfx.menuMove()
    elseif b == Input.DOWN then self.accSel = self.accSel % n + 1 Audio.sfx.menuMove()
    elseif b == Input.A then self:accuse(self.accSel)
    elseif b == Input.B then self.view = "file" Audio.sfx.back() end
    return
  end
  -- the reader
  if b == Input.B then
    self.mag = not self.mag
    self.scrollY = 0
    self.panX = 0
    self.cursor = 0
    Audio.sfx.clack(0.25)
    Audio.play(Audio.SINE, self.mag and 520 or 390, 0.18, 0.08)
  elseif b == Input.A then
    if self.mag then
      self:clip()
    elseif self.stuckHigh then
      Audio.sfx.denied()
      self:say("THE GEAR IS STUCK")
    else
      self.gear = 3 - self.gear
      Audio.sfx.clank(0.35)
      self:say(self.gear == 2 and "HIGH GEAR" or "LOW GEAR", 0.8)
    end
  elseif b == Input.LEFT or b == Input.RIGHT then
    local d = (b == Input.LEFT) and -1 or 1
    if self.mag then
      self:pan(d)
    else
      self:changeReel(d)
    end
  elseif b == Input.UP or b == Input.DOWN then
    if self.mag then
      self:moveCursor(b == Input.UP and -1 or 1)
    else
      self.view = "file"
      Audio.sfx.menuSelect()
    end
  end
end

function Fiche:moveCursor(d)
  local s = self:getFrame(self.reel, self:curFrame())
  local c = U.clamp(self.cursor + d, 0, s.n)
  if c ~= self.cursor then self.cursor = c Audio.sfx.menuMove() end
end

function Fiche:pan(d)
  local s = self:getFrame(self.reel, self:curFrame())
  local maxPan = max(0, s.maxW + 40 - (FW + 8))
  local p = U.clamp(self.panX + d * 40, 0, maxPan)
  if p ~= self.panX then self.panX = p Audio.sfx.menuMove() end
end

------------------------------------------------------------------------
-- update
------------------------------------------------------------------------
function Fiche:update(dt)
  self.t = self.t + dt
  if self.msgT > 0 then self.msgT = self.msgT - dt end
  if self.clipFlash and self.clipFlash > 0 then self.clipFlash = max(0, self.clipFlash - dt * 2) end
  self.flap = max(0, self.flap - dt * 1.4)
  if self.flap > 0 and floor(self.t * 20) % 2 == 0 and self.flap > 0.3 then Audio.sfx.tick(300, 0.12) end

  if self.view == "loading" then
    self.loadT = self.loadT + dt
    if self.loadT > 0.35 and self.reel ~= self.nextReel then
      self.reel = self.nextReel
      self.lastFi = self:curFrame()
      self.cursor = 0
      Audio.sfx.clank(0.3)
    end
    if self.loadT > 0.8 then self.view = "reel" end
    self.pend = 0
  end
  self:physics(dt)
  if self.finished then
    self.hum:set(0, 0) self.rustle:set(0, 0) self.squeal:set(0, 0)
    return
  end

  -- held d-pad: cursor auto-repeat while magnified
  if self.view == "reel" and self.mag then
    if Input.holdTime(Input.DOWN) > 0.3 and Input.repeated(Input.DOWN) then self:moveCursor(1) end
    if Input.holdTime(Input.UP) > 0.3 and Input.repeated(Input.UP) then self:moveCursor(-1) end
    local s = self:getFrame(self.reel, self:curFrame())
    if self.cursor > s.n then self.cursor = s.n end
    -- keep the cursor row in view (page top sits at y=20 when scroll is 0)
    local pageH = 56 + s.n * LH
    local tut = self.mode == "tutorial"
    local rowY = (self.cursor == 0) and 26 or (48 + (self.cursor - 1) * LH)
    local minS = tut and -48 or 0
    local want = U.clamp(20 + rowY - (tut and 140 or 120), minS, max(minS, pageH - 190))
    self.scrollY = U.damp(self.scrollY, want, 14, dt)
  end

  -- sound: spool whirr tracks speed, film rustle at blur, brake squeal
  local av = abs(self.vel)
  self.hum:set(70 + min(av, 140) * 6, min(0.2, av * 0.006))
  self.rustle:set(1800 + av * 10, self.blur * 0.1)
  self.squeal:set(1400 + av * 4, (av > 4) and self.braking * 0.12 or 0)

  if self.params.challengeId == "dim" then
    self.flicker = U.damp(self.flicker, 0, 6, dt)
    if self.rng:chance(dt * 0.9) then self.flicker = 0.6 + self.rng:float() * 0.4 Audio.sfx.click(0.1) end
  end

  -- case clock
  if self.caseState == "open" then
    self.caseT = self.caseT + dt
    if self.mode == "standard" then
      self.timeLeft = self.timeLeft - dt
      if self.timeLeft <= 0 then
        self.timeLeft = 0
        Audio.sfx.fail()
        self:endRun(false)
        return
      end
    elseif self.mode == "endless" and self.caseT > self.caseLimit then
      self:caseCold()
    end
  else
    self.caseEndT = self.caseEndT + dt
    if self.mode ~= "tutorial" and self.caseEndT > 3.2 then self:advanceCase() end
  end
end

------------------------------------------------------------------------
-- drawing
------------------------------------------------------------------------
local bigCache = {}
local function bigLabel(str)
  local img = bigCache[str]
  if img then return img end
  local w = UI.width(str, UI.bold) + 4
  img = gfx.image.new(w, 18, gfx.kColorClear)
  gfx.pushContext(img)
  UI.textW(str, 2, 1, "left", UI.bold)
  gfx.popContext()
  bigCache[str] = img
  return img
end

function Fiche:drawSprockets(pitch)
  local p = self.pos[self.reel]
  local o = (-(p * pitch)) % 18
  gfx.setColor(gfx.kColorWhite)
  local y = 18 + o - 18
  while y < 222 do
    if y >= 19 and y + 6 <= 221 then
      gfx.fillRoundRect(6, y, 9, 6, 2)
      gfx.fillRoundRect(FILM_W - 15, y, 9, 6, 2)
    end
    y = y + 18
  end
  gfx.setPattern(DOTS)
  gfx.fillRect(18, 18, 2, 204)
  gfx.fillRect(FILM_W - 20, 18, 2, 204)
  gfx.setColor(gfx.kColorBlack)
end

function Fiche:drawLeader(y0, h)
  gfx.setPattern(DIAG)
  gfx.fillRect(FX, y0, FW, h)
  gfx.setColor(gfx.kColorBlack)
end

-- zoomed out: three frames of film with legible headers, greeked body
function Fiche:drawFull()
  local reel = self.reel
  local pos = self.pos[reel]
  local N = N_FRAMES[reel]
  local base = floor(pos + 0.5)
  local b = self.blur
  for k = -2, 2 do
    local fi = base + k
    local y0 = floor(CY + (fi - pos) * FP - FH / 2)
    if y0 + FH >= 18 and y0 <= 222 then
      if fi < 0 or fi >= N then
        self:drawLeader(y0 - 6, FH + 12)
      elseif b < 0.3 then
        local s = self:getFrame(reel, fi)
        gfx.setColor(gfx.kColorWhite)
        gfx.drawRect(FX, y0, FW, FH)
        UI.textW(s.top, FX + 6, y0 + 3)
        UI.textW(s.headline, FX + 6, y0 + 20, "left", UI.bold)
        gfx.setColor(gfx.kColorWhite)
        local n = min(s.n, 6)
        for j = 1, n do
          local w = s.lw[j]
          if s.keys[j] ~= 0 and self.case.steps[s.keys[j]] and self.case.steps[s.keys[j]].done then
            gfx.drawRect(FX + 5, y0 + 40 + j * 7 - 2, w + 6, 5)
          end
          gfx.fillRect(FX + 8, y0 + 40 + j * 7, w, 2)
        end
        if b > 0 then
          -- the smear begins: ghost copies trailing the motion
          local off = floor(b * 10) * U.sign(self.vel)
          gfx.setPattern(STREAK2)
          gfx.fillRect(FX + 6, y0 + 20 + off, FW - 12, FH - 24)
        end
      else
        -- motion blur: the page smears into vertical streaks
        gfx.setPattern(b > 0.8 and STREAK or STREAK2)
        local smear = floor(b * 46)
        gfx.fillRect(FX, y0 - smear, FW, 3 + smear)
        for j = 1, 5 do
          local w = 40 + ((fi * 37 + j * 53) % 170)
          gfx.fillRect(FX + 8, y0 + 18 + j * 11 - smear, w, 3 + smear)
        end
      end
    end
  end
  gfx.setColor(gfx.kColorBlack)
end

-- magnified: one frame at reading size with a line cursor
function Fiche:drawMag()
  local reel = self.reel
  local pos = self.pos[reel]
  local N = N_FRAMES[reel]
  local base = floor(pos + 0.5)
  local b = self.blur
  local cur = self:curFrame()
  local x = FX + 4 - floor(self.panX)
  for k = -1, 1 do
    local fi = base + k
    local y0 = floor(CY - 100 + (fi - pos) * MP - self.scrollY)
    if y0 < 222 and y0 + MP > 18 then
      if fi < 0 or fi >= N then
        self:drawLeader(y0, MP - 10)
      elseif b < 0.3 then
        local s = self:getFrame(reel, fi)
        local pageH = 56 + s.n * LH
        gfx.setColor(gfx.kColorWhite)
        gfx.drawRect(FX - 4, y0, FW + 8, pageH)
        UI.textW(s.top, x, y0 + 6)
        local isCur = fi == cur and self.view == "reel"
        -- rows: 0 = headline, then lines
        for row = 0, s.n do
          local ry = (row == 0) and (y0 + 26) or (y0 + 48 + (row - 1) * LH)
          if ry > 2 and ry < 222 then
            local str = (row == 0) and s.headline or s.lines[row]
            local key = (row == 0) and s.hkey or s.keys[row]
            local font = (row == 0) and UI.bold or UI.font
            if isCur and row == self.cursor then
              gfx.setColor(gfx.kColorWhite)
              gfx.fillRect(FX - 2, ry - 1, FW + 4, LH)
              UI.text(str, x, ry, "left", font)
              local cf = self.clipFlash or 0
              if cf > 0 then
                -- the clipping lifts off the page
                local g = floor((1 - cf) * 10)
                gfx.setColor(gfx.kColorWhite)
                gfx.drawRect(FX - 4 - g, ry - 3 - g, FW + 8 + 2 * g, LH + 4 + 2 * g)
              end
            else
              UI.textW(str, x, ry, "left", font)
            end
            if key > 0 and self.case.steps[key] and self.case.steps[key].done then
              -- clipped: a filed-tick in the margin
              gfx.setColor(gfx.kColorWhite)
              gfx.fillTriangle(FX - 11, ry + 3, FX - 11, ry + 11, FX - 6, ry + 7)
            end
          end
        end
        if b > 0 then
          gfx.setPattern(STREAK2)
          gfx.fillRect(FX, y0 + 20, FW, pageH - 20)
        end
      else
        gfx.setPattern(b > 0.8 and STREAK or STREAK2)
        local smear = floor(b * 80)
        gfx.fillRect(FX, y0 - smear, FW, 4 + smear)
        for j = 1, 9 do
          local w = 60 + ((fi * 41 + j * 67) % 150)
          gfx.fillRect(FX + 4, y0 + 30 + j * 17 - smear, w, 6 + smear)
        end
      end
    end
  end
  gfx.setColor(gfx.kColorBlack)
end

function Fiche:drawLens()
  -- projected light falls off toward the edges of the screen
  local img = Art.cached("fiche_lens", FILM_W, 204, function(w, h)
    gfx.setColor(gfx.kColorBlack)
    for i = 0, 5 do
      gfx.setDitherPattern(0.85 - i * 0.14, gfx.kDitherTypeBayer4x4)
      gfx.drawRect(i, i, w - 2 * i, h - 2 * i)
    end
    gfx.setColor(gfx.kColorBlack)
    for i = 0, 7 do
      local r = 8 - i
      gfx.fillRect(0, i, r, 1) gfx.fillRect(w - r, i, r, 1)
      gfx.fillRect(0, h - 1 - i, r, 1) gfx.fillRect(w - r, h - 1 - i, r, 1)
    end
  end)
  img:draw(0, 18)
end

function Fiche:drawSpeedLabel()
  -- years (or letters) flying past: a big counter in the gate
  local b = self.blur
  if b < 0.35 then return end
  local reel = self.reel
  local fi = self:curFrame()
  local str
  if reel == GAZ then str = YEARSTR[(dateOf(issueDay(fi)))]
  elseif reel == LOG then str = YEARSTR[(dateOf(fi * 7))]
  elseif reel == REG then str = SHIPTAB[fi + 1]
  else str = SURNTAB[fi + 1] end
  local img = bigLabel(str)
  local w, h = img:getSize()
  local bx = floor(FILM_W / 2 - w)
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(bx - 8, CY - 22, w * 2 + 16, h * 2 + 8)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawRect(bx - 6, CY - 20, w * 2 + 12, h * 2 + 4)
  img:drawScaled(bx, CY - 18, 2)
  gfx.setColor(gfx.kColorBlack)
end

function Fiche:drawPanel()
  local x0 = FILM_W
  gfx.setPattern(Art.pat.gray25)
  gfx.fillRect(x0, 18, 100, 204)
  gfx.setColor(gfx.kColorBlack)
  gfx.setLineWidth(2)
  gfx.drawLine(x0, 18, x0, 222)
  gfx.setLineWidth(1)
  -- reel label
  gfx.fillRect(x0 + 6, 22, 88, 30)
  UI.textW(REEL_TAG[self.reel], x0 + 50, 22, "center", UI.bold)
  UI.textW(REEL_SPAN[self.reel], x0 + 50, 36, "center")
  -- spool
  local cx, cy = x0 + 50, 80
  local frac = self.pos[self.reel] / N_FRAMES[self.reel]
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(cx, cy, 23)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawCircleAtPoint(cx, cy, 23)
  gfx.fillCircleAtPoint(cx, cy, 8 + floor(13 * (1 - frac)))
  local b = self.blur
  if b > 0.6 then
    gfx.setDitherPattern(0.5, gfx.kDitherTypeBayer4x4)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(cx, cy, 20)
    gfx.setColor(gfx.kColorBlack)
  end
  gfx.setColor(gfx.kColorWhite)
  gfx.fillCircleAtPoint(cx, cy, 6)
  local ang = self.pos[self.reel] * 24
  gfx.setColor(gfx.kColorBlack)
  for i = 0, 2 do
    local a = rad(ang + i * 120)
    gfx.drawLine(cx, cy, cx + sin(a) * 6, cy - cos(a) * 6)
  end
  if b <= 0.6 then
    gfx.setColor(gfx.kColorWhite)
    for i = 0, 2 do
      local a = rad(ang + i * 120 + 60)
      gfx.fillCircleAtPoint(cx + sin(a) * 15, cy - cos(a) * 15, 2)
    end
    gfx.setColor(gfx.kColorBlack)
  end
  -- counter window
  local reel = self.reel
  local fi = self:curFrame()
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x0 + 6, 108, 88, 36)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(x0 + 6, 108, 88, 36)
  if reel == GAZ or reel == LOG then
    local y, m, d = dateOf(reel == GAZ and issueDay(fi) or fi * 7)
    UI.text(YEARSTR[y], x0 + 50, 110, "center", UI.bold)
    UI.text(DAYSTR[d], x0 + 44, 126, "right")
    UI.text(MON[m], x0 + 50, 126, "left")
  else
    local name = (reel == REG) and SHIPS[fi + 1] or SURN[fi + 1]
    UI.text(name, x0 + 50, 110, "center", UI.bold)
    UI.text(U.cached("fiche_no", "No.%d", fi + 1), x0 + 50, 126, "center")
  end
  -- gear
  local g = self.gear
  for i = 1, 2 do
    local bx = x0 + 8 + (i - 1) * 44
    if g == i then
      gfx.fillRect(bx, 150, 40, 16)
      UI.textW(i == 1 and "LOW" or "HIGH", bx + 20, 150, "center", UI.bold)
    else
      gfx.setColor(gfx.kColorWhite)
      gfx.fillRect(bx, 150, 40, 16)
      gfx.setColor(gfx.kColorBlack)
      gfx.drawRect(bx, 150, 40, 16)
      UI.text(i == 1 and "LOW" or "HIGH", bx + 20, 150, "center")
    end
  end
  -- speed
  UI.gauge(x0 + 8, 172, 84, 9, abs(self.vel) / 120, nil, nil, nil, nil)
  if self.braking > 0.15 then
    gfx.setPattern(Art.pat.hatch)
    gfx.fillRect(x0 + 8, 183, floor(84 * self.braking), 3)
    gfx.setColor(gfx.kColorBlack)
  end
  -- case chain
  local c = self.case
  local n = #c.steps
  local sx = x0 + 50 - n * 10
  for i = 1, n do
    local st = c.steps[i]
    local bx = sx + (i - 1) * 20
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(bx, 192, 16, 16)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(bx, 192, 16, 16)
    if st.read then
      UI.text("?", bx + 8, 192, "center", UI.bold)
    elseif st.done then
      gfx.fillRect(bx + 3, 195, 10, 10)
    end
  end
  if self.mode == "endless" then
    for i = 1, 3 do
      local bx = x0 + 22 + (i - 1) * 22
      gfx.drawRect(bx, 210, 12, 9)
      if i <= self.strikes then
        gfx.drawLine(bx, 210, bx + 12, 219) gfx.drawLine(bx + 12, 210, bx, 219)
      end
    end
  end
end

function Fiche:drawFile()
  local c = self.case
  UI.popup(10, 24, 282, 194, "paper")
  UI.text(U.cached("fiche_case", "CASE No.%d", self.caseIdx), 22, 32, "left", UI.bold)
  UI.text(U.cached("fiche_rec", "%d records", c.records), 280, 32, "right")
  local y = 50
  local ql = c.qLines
  for i = 1, #ql do UI.text(ql[i], 22, y) y = y + 15 end
  y = y + 4
  gfx.drawLine(22, y, 280, y)
  y = y + 4
  for i = 1, #c.steps do
    local st = c.steps[i]
    gfx.drawRect(22, y + 2, 11, 11)
    if st.done then
      gfx.fillRect(24, y + 4, 7, 7)
      UI.text(st.summary, 40, y)
    elseif st.read then
      UI.text("?", 27, y, "center")
      UI.text(st.label, 40, y)
    else
      UI.text(st.label, 40, y)
    end
    y = y + 17
  end
  if self:ready() then
    gfx.fillRoundRect(70, 189, 162, 21, 4)
    UI.textW("A: ACCUSE", 151, 191, "center", UI.bold)
  else
    UI.text("clip each record with A", 150, 194, "center")
  end
end

function Fiche:drawAccuse()
  local c = self.case
  UI.popup(24, 40, 254, 160, "ink")
  UI.textW(c.ask, 151, 50, "center", UI.bold)
  for i = 1, #c.options do
    local y = 74 + (i - 1) * 24
    if i == self.accSel then
      gfx.setColor(gfx.kColorWhite)
      gfx.fillRect(38, y - 2, 226, 20)
      UI.text(c.options[i], 151, y, "center", UI.bold)
      gfx.setColor(gfx.kColorBlack)
    else
      UI.textW(c.options[i], 151, y, "center")
    end
  end
  UI.textW("A: accuse   B: back", 151, 176, "center")
end

function Fiche:drawCaseEnd()
  local st = self.caseState
  local t = self.caseEndT
  local title = st == "solved" and "SOLVED" or (st == "wrong" and "WRONG" or "GONE COLD")
  UI.panel(40, 70, 220, 90, "paper")
  UI.stamp(title, 150, 96, t)
  if st == "solved" then
    if self.mode ~= "tutorial" then UI.text(U.cached("fiche_gain", "+%d", self.lastGain or 0), 150, 118, "center", UI.bold) end
  else
    UI.text(self.case.answerText, 150, 118, "center", UI.bold)
  end
  if self.mode ~= "tutorial" and t > 0.8 then UI.text("A: next case", 150, 138, "center") end
end

function Fiche:headerRight()
  local sec
  if self.mode == "standard" then sec = floor(self.timeLeft)
  elseif self.mode == "endless" then sec = max(0, floor(self.caseLimit - self.caseT))
  else return "LESSON" end
  if sec ~= self.hdrSec or self.hdrCase ~= self.caseIdx then
    self.hdrSec, self.hdrCase = sec, self.caseIdx
    if self.mode == "standard" then
      self.hdrStr = fmt("CASE %d/%d  %d:%02d", self.caseIdx, STD_CASES, sec // 60, sec % 60)
    else
      self.hdrStr = fmt("CASE %d  %d:%02d", self.caseIdx, sec // 60, sec % 60)
    end
  end
  return self.hdrStr
end

Fiche.HINTS_FULL = { { "CRANK", "SPOOL" }, { "A", "GEAR" }, { "B", "MAGNIFY" }, { "DPAD", "REEL / FILE" } }
Fiche.HINTS_MAG = { { "CRANK", "SPOOL" }, { "A", "CLIP" }, { "B", "BACK" }, { "DPAD", "CURSOR" } }
Fiche.HINTS_FILE = { { "A", "ACCUSE" }, { "B", "CLOSE" }, { "CRANK", "SPOOL" } }

function Fiche:draw()
  gfx.clear(gfx.kColorBlack)
  gfx.setClipRect(0, 18, FILM_W, 204)
  if self.view == "loading" then
    -- the reel is swapped: the gate goes bright, sprockets stop
    local t = self.loadT
    gfx.setColor(gfx.kColorWhite)
    local w = floor(FW * (1 - abs(t - 0.4) / 0.4))
    if w > 0 then
      gfx.setDitherPattern(0.5, gfx.kDitherTypeBayer4x4)
      gfx.fillRect(FILM_W / 2 - w / 2, 30, w, 180)
    end
    gfx.setColor(gfx.kColorBlack)
    self:drawSprockets(FP)
    UI.textW(REEL_TAG[self.nextReel], FILM_W / 2, 112, "center", UI.bold)
  else
    if self.mag then self:drawMag() else self:drawFull() end
    self:drawSprockets(self.mag and MP or FP)
    self:drawSpeedLabel()
    if self.flap > 0 then
      -- the loose tail slapping round
      gfx.setColor(gfx.kColorWhite)
      local a = self.t * 40
      local fy = CY + sin(a) * 60 * self.flap
      gfx.fillRect(FX, floor(fy), FW, 3)
      gfx.setColor(gfx.kColorBlack)
    end
    if self.flicker > 0.05 then
      gfx.setColor(gfx.kColorBlack)
      gfx.setDitherPattern(self.flicker, gfx.kDitherTypeBayer4x4)
      gfx.fillRect(0, 18, FILM_W, 204)
      gfx.setColor(gfx.kColorBlack)
    end
    self:drawLens()
  end
  gfx.clearClipRect()
  -- the gate pointer: a notch marking the reading line
  gfx.setColor(gfx.kColorWhite)
  if not self.mag then
    gfx.fillTriangle(20, CY - 5, 20, CY + 5, 25, CY)
    gfx.fillTriangle(FILM_W - 20, CY - 5, FILM_W - 20, CY + 5, FILM_W - 25, CY)
  end
  gfx.setColor(gfx.kColorBlack)
  self:drawPanel()
  if self.view == "file" then self:drawFile()
  elseif self.view == "accuse" then self:drawAccuse() end
  if self.caseState ~= "open" then self:drawCaseEnd() end
  UI.header(4, "MICROFICHE", self:headerRight())
  if self.msgT > 0 and self.msg then
    local w = UI.width(self.msg, UI.bold) + 20
    UI.panel(150 - w / 2, 190, w, 24, "ink")
    UI.textW(self.msg, 150, 194, "center", UI.bold)
  end
  if self.mode ~= "tutorial" then
    if self.view == "file" or self.view == "accuse" then UI.hints(Fiche.HINTS_FILE)
    elseif self.mag then UI.hints(Fiche.HINTS_MAG)
    else UI.hints(Fiche.HINTS_FULL) end
  end
end

------------------------------------------------------------------------
-- suspend / resume
------------------------------------------------------------------------
function Fiche:serialize()
  local done = {}
  for i = 1, #self.case.steps do done[i] = self.case.steps[i].done end
  return {
    rng = self.rng:state(), caseIdx = self.caseIdx, caseSeed = self.caseSeed, kind = self.case.kind,
    level = self.case.level, done = done, score = self.score, solved = self.solved, strikes = self.strikes,
    timeLeft = self.timeLeft, caseT = self.caseT, mistakes = self.mistakes, caseMistakes = self.caseMistakes,
    reel = self.reel, pos = { self.pos[1], self.pos[2], self.pos[3], self.pos[4] }, gear = self.gear,
    framesMoved = self.framesMoved, caseState = self.caseState,
  }
end

function Fiche:deserialize(t)
  self.rng:setState(t.rng)
  self.caseIdx = t.caseIdx
  self.caseSeed = t.caseSeed
  self.case = self:makeCase(t.kind, t.caseSeed, t.level or 0)
  for i = 1, #self.case.steps do self.case.steps[i].done = t.done[i] == true end
  self:flushSlots()
  self.score, self.solved, self.strikes = t.score or 0, t.solved or 0, t.strikes or 0
  self.timeLeft, self.caseT = t.timeLeft or self.timeLeft, t.caseT or 0
  self.mistakes, self.caseMistakes = t.mistakes or 0, t.caseMistakes or 0
  self.reel = t.reel or GAZ
  for i = 1, 4 do self.pos[i] = U.clamp(t.pos[i] or 0, 0, N_FRAMES[i] - 1) end
  self.gear = t.gear or 1
  if self.stuckHigh then self.gear = 2 end
  self.framesMoved = t.framesMoved or 0
  self.vel = 0
  self.lastFi = self:curFrame()
  self.view = "file"
  self.caseLimit = max(110, 200 - (self.caseIdx - 1) * 8 - (self.difficulty - 1) * 15)
  if t.caseState and t.caseState ~= "open" then
    self.caseState = t.caseState
    self.caseEndT = 2
    self.view = "reel"
  end
  if self.mode == "tutorial" then self.view = "reel" self:setupCoach() end
end
