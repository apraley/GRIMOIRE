-- CRANKING IT :: No.V NUMBERS STATION
--
-- The crank turns a valve receiver's tuning capacitor:
--   * crank -> drive shaft, directly (COARSE, 600 kHz a turn) or through a
--     10:1 vernier (FINE, A toggles it: 60 kHz a turn).
--   * between the drive and the capacitor sits BACKLASH: a few degrees of
--     dead play. Reverse direction and the knob turns while the needle
--     stays put until the gear teeth bite again (you hear them).
--   * every station DRIFTS (slow thermal wander, plus the set warming up),
--     so holding a signal means tiny continuous corrections.
--   * signal = a gaussian around each station's current frequency. The
--     static (a noise voice) falls away as signal rises; a beat-frequency
--     whistle sings at the detune and drops to a growl at zero-beat.
-- Numbers stations loop a tune, their call, then groups of five digits.
-- The notepad keeps the best copy of every digit across repeats. The first
-- group is the indicator: 1 PLAIN (A1Z26 pairs), 2 DATE (tonight's DDMM
-- added digit by digit), 3 PAD (subtract a one-time pad read out by a
-- second station, whose frequency follows the 3), 4 BOOK (codebook words).
-- A decoded message names the next frequency (QSY); the last names a place.

local gfx <const> = playdate.graphics
local floor <const> = math.floor
local abs <const> = math.abs
local min <const>, max <const> = math.min, math.max
local sin <const>, cos <const>, rad <const> = math.sin, math.cos, math.rad
local exp <const> = math.exp
local fmt <const> = string.format

local BAND_LO <const>, BAND_HI <const> = 3000, 9000   -- kHz
local KHZ_PER_DEG <const> = 600 / 360                 -- per drive degree
local SLOT <const> = 0.45                             -- seconds per spoken digit
local GROUP_GAP <const> = 0.5
local NIGHT_MIN <const> = 450                         -- 22:00 -> 05:30

local K_PLAIN <const>, K_DATE <const>, K_PAD <const>, K_BOOK <const> = 1, 2, 3, 4
local KEY_NAME <const> = { "PLAIN", "DATE", "PAD", "BOOK" }
local MON <const> = { "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }
local PLACES <const> = { "THE WELL", "THE CELLAR", "LAMP ROOM", "NORTH STAIR", "BELL BUOY", "BOATHOUSE",
  "THE CHAPEL", "FOG HORN", "EAST GALLERY", "THE LEDGER", "GREY ROCK", "THE STAIRS" }
local PREFIX <const> = { "", "GULL ", "TIDE ", "ROCK ", "LAMP ", "HAND " }
local DIGITSTR, CHARSTR = {}, {}
for d = 0, 9 do DIGITSTR[d] = tostring(d) end
for c = 65, 90 do CHARSTR[c] = string.char(c) end
CHARSTR[32] = " "
for c = 48, 57 do CHARSTR[c] = string.char(c) end
local PENTA <const> = { 392, 440, 523, 587, 659, 784, 880, 1047 }
local MORSE <const> = { 1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0 }

-- noise table for the oscilloscope (visual only, never touches self.rng)
local NOISE = {}
do
  local r = U.rng(77)
  for i = 1, 128 do NOISE[i] = r:float() * 2 - 1 end
end

local Num = Machine.define({
  id = "numbers",
  number = 5,
  title = "NUMBERS STATION",
  tagline = "Somebody is reading digits.",
  description = "A valve receiver in the east gallery. Hold drifting stations on the peak, copy their digits, break the key.",
  howto = "Crank to tune. A toggles FINE (10:1). The gears have play: reversing, the needle waits. Stations drift - keep the whistle low and the needle high. B opens the notepad: the first group names the key.",
  controls = { { "CRANK", "tune the dial" }, { "A", "fine vernier / apply" }, { "B", "notepad" }, { "DPAD", "choose key" } },
  modes = { "tutorial", "standard", "endless" },
  medals = { standard = { 1500, 3000, 4200 }, endless = { 3000, 7000, 12000 } },
  scoreLabel = "POINTS",
  unlockCost = 5,
  achievements = {
    { id = "first", name = "FIRST CONTACT", desc = "Decode your first message." },
    { id = "zero", name = "ZERO BEAT", desc = "Hold 97% signal for 5 seconds." },
    { id = "clean", name = "CLEAN COPY", desc = "Copy a message on its first pass." },
    { id = "pad", name = "ONE-TIME PAD", desc = "Decode a message with a pad key." },
    { id = "dawn", name = "BEFORE DAWN", desc = "Finish a night 2 hours early." },
  },
  challenges = {
    { id = "storm", name = "SOLAR STORM", desc = "Deep fades roll across the band.", mode = "standard", difficulty = 2, goal = 2500, reward = 2, cost = 2 },
    { id = "slop", name = "WORN GEARS", desc = "Triple backlash in the dial.", mode = "standard", difficulty = 2, goal = 2500, reward = 3, cost = 2 },
    { id = "grave", name = "GRAVEYARD SHIFT", desc = "Endless. Weak stations from dusk.", mode = "endless", difficulty = 3, goal = 5000, reward = 3, cost = 3 },
  },
  records = {
    { "decoded", "Messages decoded" },
    { "nights", "Nights completed" },
    { "digits", "Digits copied" },
    { "zerobeat", "Longest zero-beat", function(v) return string.format("%.1fs", v / 10) end },
  },
  drawIcon = function(cx, cy)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRoundRect(cx - 23, cy - 18, 46, 38, 5)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(cx - 19, cy - 14, 38, 12)
    gfx.setColor(gfx.kColorBlack)
    for i = 0, 8 do gfx.drawLine(cx - 17 + i * 4, cy - 14, cx - 17 + i * 4, cy - 14 + ((i % 2 == 0) and 5 or 3)) end
    gfx.setLineWidth(2)
    gfx.drawLine(cx + 3, cy - 15, cx + 3, cy - 2)
    gfx.setLineWidth(1)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(cx + 10, cy + 9, 8)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(cx + 10, cy + 9, 5)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillCircleAtPoint(cx + 12, cy + 6, 1)
    for i = 0, 3 do gfx.drawLine(cx - 18, cy + 3 + i * 4, cx - 4, cy + 3 + i * 4) end
    gfx.setColor(gfx.kColorBlack)
  end,
})

------------------------------------------------------------------------
-- ciphers (pure functions, also used by the tests)
------------------------------------------------------------------------
-- A1Z26 with space = 00 and digits = 30..39
local function pairValue(b)
  if b == 32 then return 0 end
  if b >= 48 and b <= 57 then return 30 + (b - 48) end
  return b - 64
end
local function pairChar(v)
  if v == 0 then return 32 end
  if v >= 30 and v <= 39 then return 48 + v - 30 end
  if v >= 1 and v <= 26 then return 64 + v end
  return nil
end

-- decode a full transmission (indicator + body) given the key material
--   keyType: 1..4; dateKey: 4 digits; pad: digit array (body length); book: code -> word
function Num.decode(digits, keyType, dateKey, pad, book)
  local out = {}
  local nb = #digits - 5
  local plain = {}
  for i = 1, nb do
    local c = digits[5 + i]
    if keyType == K_DATE then c = (c - dateKey[(i - 1) % 4 + 1]) % 10
    elseif keyType == K_PAD then
      if not pad or not pad[i] then return nil end
      c = (c - pad[i]) % 10
    end
    plain[i] = c
  end
  if keyType == K_BOOK then
    for i = 1, nb - 2, 3 do
      local code = plain[i] * 100 + plain[i + 1] * 10 + plain[i + 2]
      if code ~= 0 then
        local w = book and book[code]
        if not w then return nil end
        out[#out + 1] = w
      end
    end
    return table.concat(out, " ")
  end
  for i = 1, nb - 1, 2 do
    local ch = pairChar(plain[i] * 10 + plain[i + 1])
    if not ch then return nil end
    out[#out + 1] = string.char(ch)
  end
  return (table.concat(out):gsub("%s+$", ""))
end

------------------------------------------------------------------------
-- night generation
------------------------------------------------------------------------
-- build the transmission timeline for a numbers station
local function buildTimeline(st, r)
  local ts, tk, tv, tp = {}, {}, {}, {}
  local t = 0
  local function add(kind, val, pos, len)
    ts[#ts + 1] = t tk[#tk + 1] = kind tv[#tv + 1] = val tp[#tp + 1] = pos
    t = t + len
  end
  -- interval signal: five notes
  for i = 1, 5 do add(1, st.tune[i], 0, 0.3) end
  add(0, 0, 0, 0.5)
  for rep = 1, 2 do
    for i = 1, 3 do add(2, st.call[i], 0, 0.4) end
    add(0, 0, 0, 0.5)
  end
  for i = 1, #st.digits do
    add(3, st.digits[i], i, SLOT)
    if i % 5 == 0 then add(0, 0, 0, GROUP_GAP) end
  end
  add(0, 0, 0, 1.2)
  st.ts, st.tk, st.tv, st.tp = ts, tk, tv, tp
  st.loopLen = t
  st.offset = r:float() * t
end

local function freqDigits(khz, out)
  local s = fmt("%04d", khz)
  for i = 1, 4 do out[#out + 1] = s:byte(i) - 48 end
end

function Num:makeNight(seed, level, tutorial)
  local r = U.rng(seed)
  local night = { seed = seed, level = level, stations = {}, msgs = {} }
  local S = night.stations
  night.day = r:range(1, 28)
  night.month = r:range(1, 12)
  night.dateKey = { night.day // 10, night.day % 10, night.month // 10, night.month % 10 }
  night.dateStr = night.day .. " " .. MON[night.month]
  local L = level
  local sigma = tutorial and 4.2 or ({ 2.7, 2.3, 1.9, 1.6, 1.4 })[min(5, L + 1)]
  local drift = tutorial and 0.35 or (0.7 + 0.25 * L)
  local strength = tutorial and 1 or max(0.72, 1 - 0.06 * L)
  local fade = tutorial and 0.05 or min(0.4, 0.12 + 0.06 * L)
  if self.params.challengeId == "storm" then fade = 0.7 end
  if self.params.challengeId == "grave" then strength = 0.78 sigma = sigma * 0.85 end
  night.sigma, night.warm = sigma, tutorial and 0 or (4 + r:float() * 6) * (r:chance(0.5) and 1 or -1)
  -- thermal drift of the receiver's oscillator: every station seems to wander together
  night.da1, night.dw1, night.dp1 = drift * r:between(2.4, 3.6), r:between(0.08, 0.13), r:float() * 6.28
  night.da2, night.dw2, night.dp2 = drift * r:between(0.6, 1.2), r:between(0.3, 0.5), r:float() * 6.28
  local used = {}
  local function freeFreq(lo, hi)
    for _ = 1, 200 do
      local f = r:range(lo, hi) * 5
      local ok = true
      for i = 1, #used do if abs(used[i] - f) < 60 then ok = false end end
      if ok then used[#used + 1] = f return f end
    end
    local f = r:range(lo, hi) * 5
    used[#used + 1] = f
    return f
  end
  local function newStation(kind, nominal, str)
    local st = { kind = kind, nominal = nominal, strength = str or strength, sigma = sigma * (kind == "num" and 1 or r:between(1.2, 2)),
      calib = tutorial and 0 or r:range(-5, 5),
      a1 = drift * r:between(0.2, 0.5), w1 = r:between(0.2, 0.4), p1 = r:float() * 6.28,
      fade = fade, fw = r:between(0.15, 0.35), fp = r:float() * 6.28 }
    S[#S + 1] = st
    return st, #S
  end
  local function numbersStation(nominal, digits, str)
    local st, idx = newStation("num", nominal, str)
    st.call = { r:range(1, 9), r:range(0, 9), r:range(0, 9) }
    st.tune = {}
    for i = 1, 5 do st.tune[i] = PENTA[r:range(1, #PENTA)] end
    st.digits = digits
    st.callStr = DIGITSTR[st.call[1]] .. DIGITSTR[st.call[2]] .. DIGITSTR[st.call[3]]
    buildTimeline(st, r)
    return st, idx
  end

  -- cipher plan
  local plan
  if tutorial then plan = { K_PLAIN, K_PLAIN }
  elseif L <= 0 then plan = { K_PLAIN, K_DATE, K_PLAIN }
  elseif L == 1 then plan = { K_PLAIN, K_DATE, K_PAD }
  elseif L == 2 then plan = { K_DATE, K_PAD, K_BOOK }
  else
    plan = { r:pick({ K_DATE, K_PAD }), r:pick({ K_PAD, K_BOOK }), r:pick({ K_DATE, K_BOOK, K_PAD }) }
  end
  local nMsg = #plan
  -- frequencies first so each message can name the next
  local freqs = {}
  for i = 1, nMsg do freqs[i] = freeFreq(BAND_LO // 5 + 30, BAND_HI // 5 - 30) end
  if tutorial then freqs[1], freqs[2] = 4625, 5140 used[1], used[2] = 4625, 5140 end
  -- codebook for BOOK messages
  local book, codeOf = {}, {}
  local function codeFor(word)
    if codeOf[word] then return codeOf[word] end
    local c
    repeat c = r:range(101, 989) until not book[c]
    book[c] = word
    codeOf[word] = c
    return c
  end
  night.book, night.bookList = book, {}
  -- final place and decoys
  local place = PLACES[r:range(1, #PLACES)]
  night.place = place
  local opts = { place }
  while #opts < 4 do
    local p = PLACES[r:range(1, #PLACES)]
    local dup = false
    for i = 1, #opts do if opts[i] == p then dup = true end end
    if not dup then opts[#opts + 1] = p end
  end
  r:shuffle(opts)
  night.options = opts
  for i = 1, #opts do if opts[i] == place then night.answer = i end end

  for i = 1, nMsg do
    local keyType = plan[i]
    local final = i == nMsg
    local text
    if final then text = place
    else text = PREFIX[r:range(1, #PREFIX)] .. "QSY " .. fmt("%04d", freqs[i + 1]) end
    if tutorial and not final then text = "QSY 5140" end
    local digits = {}
    -- indicator group
    digits[1] = keyType
    local padSt
    if keyType == K_PLAIN then for _ = 1, 4 do digits[#digits + 1] = 0 end
    elseif keyType == K_DATE then for k = 1, 4 do digits[#digits + 1] = night.dateKey[k] end
    elseif keyType == K_PAD then
      local pf = freeFreq(BAND_LO // 5 + 30, BAND_HI // 5 - 30)
      freqDigits(pf, digits)
      padSt = pf
    else
      local page = r:range(100, 999)
      freqDigits(page, digits)
    end
    -- body
    local body = {}
    local units = { str = {}, d0 = {}, n = {} }
    if keyType == K_BOOK then
      local words = {}
      for w in text:gmatch("%S+") do
        if w:match("^%d+$") then
          for k = 1, #w do words[#words + 1] = w:sub(k, k) end
        else
          words[#words + 1] = w
        end
      end
      if final then words = { place } end
      for k = 1, #words do
        local code = codeFor(words[k])
        units.str[#units.str + 1] = words[k]
        units.d0[#units.d0 + 1] = #body + 1
        units.n[#units.n + 1] = 3
        body[#body + 1] = code // 100
        body[#body + 1] = (code // 10) % 10
        body[#body + 1] = code % 10
      end
      while (#body + 5) % 5 ~= 0 do body[#body + 1] = 0 body[#body + 1] = 0 body[#body + 1] = 0 end
    else
      for k = 1, #text do
        local b = text:byte(k)
        local v = pairValue(b)
        units.str[#units.str + 1] = CHARSTR[b]
        units.d0[#units.d0 + 1] = #body + 1
        units.n[#units.n + 1] = 2
        body[#body + 1] = v // 10
        body[#body + 1] = v % 10
      end
      while (#body + 5) % 5 ~= 0 do body[#body + 1] = 0 end
    end
    -- encipher
    local pad
    if keyType == K_PAD then
      pad = {}
      for k = 1, #body do pad[k] = r:range(0, 9) end
    end
    for k = 1, #body do
      local c = body[k]
      if keyType == K_DATE then c = (c + night.dateKey[(k - 1) % 4 + 1]) % 10
      elseif keyType == K_PAD then c = (c + pad[k]) % 10 end
      digits[#digits + 1] = c
    end
    local st, idx = numbersStation(freqs[i], digits)
    st.msg = { index = i, key = keyType, text = text, units = units, final = final, next = (not final) and freqs[i + 1] or nil }
    if keyType == K_PAD then
      local ps, pidx = numbersStation(padSt, pad, strength * 0.9)
      ps.kind = "pad"
      ps.padFor = idx
      st.msg.padStation = pidx
    end
    night.msgs[i] = idx
  end
  -- book page shown on the notepad: the needed words plus a few strangers
  for code, word in pairs(book) do night.bookList[#night.bookList + 1] = { code = code, word = word, codeStr = fmt("%03d", code) } end
  table.sort(night.bookList, function(a, b) return a.code < b.code end)

  -- decoys: other numbers stations close to the real ones (level >= 1)
  if not tutorial and L >= 1 then
    for i = 1, nMsg do
      local st = S[night.msgs[i]]
      local off = r:range(10, 16) * (r:chance(0.5) and 1 or -1)
      local dd = {}
      for k = 1, 20 do dd[k] = r:range(0, 9) end
      local ds = numbersStation(st.nominal + off, dd, strength * 0.85)
      ds.kind = "decoy"
      ds.calib = st.calib
    end
  end
  -- background carriers across the band
  local nbg = tutorial and 6 or 12
  for _ = 1, nbg do
    local st = newStation(({ "beacon", "music", "carrier" })[r:range(1, 3)], freeFreq(BAND_LO // 5 + 5, BAND_HI // 5 - 5), r:between(0.35, 0.9))
    st.sigma = r:between(3, 7)
    st.mpitch = r:between(0.8, 1.3)
  end
  night.start = tutorial and 4300 or (freeFreq(BAND_LO // 5 + 20, BAND_HI // 5 - 20))
  return night
end

------------------------------------------------------------------------
-- lifecycle
------------------------------------------------------------------------
function Num:enter(params)
  self.t = 0
  self.score = 0
  self.nightNo = 0
  self.decodedCount = 0
  self.noise = Audio.Hum.new(Audio.NOISE)
  self.beat = Audio.Hum.new(Audio.SINE)
  self.bl = ({ 1.6, 2.0, 2.4 })[self.difficulty] or 2.0
  if self.mode == "tutorial" then self.bl = 2.0 end
  if self.params.challengeId == "slop" then self.bl = self.bl * 3 end
  self.pend = 0
  self.knob = 0
  self.fine = false
  self.pushDir = 1
  self.slackT = 0
  self.backlashEvents = 0
  self.meter = 0
  self.sig = 0
  self.heard = 0
  self.detune = 99
  self.zeroT = 0
  self.bestZero = 0
  self.scopePh = 0
  self.toneT = 0
  self.voiceDigit = nil
  self.voiceT = 0
  self.voiceCall = nil
  self.pad = false
  self.keySel = 1
  self.msg, self.msgT = nil, 0
  self.nonsenseT = 0
  self.pickSel = 1
  self.state = "night"
  self.endT = 0
  self.hdrMin = -1
  self:startNight(true)
  if self.mode == "tutorial" then self:setupCoach() end
end

function Num:exit()
  self.noise:stop()
  self.beat:stop()
end

function Num:nightLength()
  if self.mode == "tutorial" then return 99999 end
  if self.mode == "endless" then return max(240, 330 - 15 * (self.nightNo - 1)) end
  return ({ 360, 330, 300 })[self.difficulty] or 330
end

function Num:startNight(first)
  self.nightNo = self.nightNo + 1
  local level = self.difficulty - 1
  if self.mode == "endless" then level = level + (self.nightNo - 1) end
  if self.params.challengeId == "grave" then level = max(level, 2) end
  self.nightSeed = self.rng:range(1, 1000000000)
  self.night = self:makeNight(self.nightSeed, level, self.mode == "tutorial")
  self:resetNightState()
  self:setFreq(self.night.start)
  if not first then Audio.sfx.bell(660, 0.3) end
end

function Num:resetNightState()
  local n = self.night
  self.nightT = 0
  self.nightLen = self:nightLength()
  self.msgIdx = 1
  self.viewMsg = 1
  self.recs = {}
  for i = 1, #n.stations do
    local st = n.stations[i]
    st.curSlot = -1
    if st.kind == "num" or st.kind == "pad" then
      local best = {}
      for k = 1, #st.digits do best[k] = 0 end
      self.recs[i] = { best = best, passes = 0, lockSum = 0, lockN = 0, heardDigits = 0 }
    end
  end
  self.keyOK = {}
  self.decoded = {}
  self.reveal = {}
  for i = 1, #n.msgs do self.keyOK[i] = false self.decoded[i] = false self.reveal[i] = 0 end
  self.marks = { n.msgs[1] }
  self.markPad = {}
  self.state = "night"
  self.pickSel = 1
  self.keySel = 1
  self.pad = false
end

function Num:setFreq(f)
  self.cap = (f - BAND_LO) / KHZ_PER_DEG
  self.drive = self.cap
  self.freq = f
end

------------------------------------------------------------------------
-- tutorial
------------------------------------------------------------------------
function Num:setupCoach()
  local s = self
  local st1 = self.night.stations[self.night.msgs[1]]
  local st2i = self.night.msgs[2]
  self.coach = UI.Coach.new({
    { text = "Crank to sweep the needle. Find the pencil mark at 4.625 MHz on the dial.",
      check = function() return abs(s.freq - st1.nominal) < 25 end },
    { text = "Hear the whistle? Press A for FINE: the vernier turns ten times slower.",
      check = function() return s.fine end },
    { text = "Tune for the LOWEST whistle and the HIGHEST needle. Hold it there.",
      check = function() return s.heard == s.night.msgs[1] and s.sig > 0.8 end, hold = 1.0 },
    { text = "Turn back a little. The gears have play: the needle waits, then bites.",
      enter = function() s.biteBase = s.backlashEvents end,
      check = function() return s.backlashEvents - (s.biteBase or 0) >= 2 end },
    { text = "It drifts. Keep it peaked until every digit is on the notepad.",
      check = function() return s:recComplete(s.night.msgs[1]) end },
    { text = "B opens the notepad. The first group starts with 1: key PLAIN. A to apply.",
      check = function() return s.decoded[1] end },
    { text = "QSY means change frequency. B back to the dial and tune 5.140 MHz.",
      check = function() return s.heard == st2i and s.sig > 0.7 end, hold = 1.0 },
  }, { y = 164, h = 56, x = 4, w = 392, anchor = "bottom" })
end

------------------------------------------------------------------------
-- receiver simulation
------------------------------------------------------------------------
function Num:cranked(change)
  if self.finished then return end
  self.pend = self.pend + change
end

function Num:commonDrift()
  local n, t = self.night, self.t
  return n.da1 * sin(n.dw1 * t + n.dp1) + n.da2 * sin(n.dw2 * t + n.dp2) + n.warm * (1 - exp(-self.nightT / 50))
end

function Num:stationFreq(st)
  return st.nominal + st.calib + st.a1 * sin(st.w1 * self.t + st.p1) + self.drift
end

function Num:tune(dt)
  local ch = self.pend
  self.pend = 0
  self.knob = self.knob + ch
  local dd = self.fine and ch / 10 or ch
  self.drive = self.drive + dd
  local half = self.bl / 2
  local gap = self.drive - self.cap
  local moved = false
  if gap > half then
    self.cap = self.drive - half
    if self.pushDir < 0 then self:bite() end
    self.pushDir = 1
    moved = true
  elseif gap < -half then
    self.cap = self.drive + half
    if self.pushDir > 0 then self:bite() end
    self.pushDir = -1
    moved = true
  elseif ch ~= 0 then
    self.slackT = 0.25 -- turning inside the dead zone
  end
  self.slackT = max(0, self.slackT - dt)
  -- end stops of the capacitor
  local capMax = (BAND_HI - BAND_LO) / KHZ_PER_DEG
  if self.cap < 0 or self.cap > capMax then
    local c = U.clamp(self.cap, 0, capMax)
    self.drive = self.drive + (c - self.cap)
    self.cap = c
    if not self.atStop then Audio.sfx.thunk(0.5) self:shake(2) end
    self.atStop = true
  else
    self.atStop = false
  end
  local before = self.freq
  self.freq = BAND_LO + self.cap * KHZ_PER_DEG
  -- faint friction ticks on the dial cord every 10 kHz in COARSE
  if moved and not self.fine and floor(before / 10) ~= floor(self.freq / 10) then
    Audio.sfx.tick(2400, 0.03)
  end
end

-- gear teeth engaging after crossing the backlash gap
function Num:bite()
  self.backlashEvents = self.backlashEvents + 1
  Audio.play(Audio.SQUARE, 900, 0.12, 0.012, 0.001, 0.015, 0, 0.01)
  Audio.sfx.click(0.15)
end

function Num:receive(dt)
  local n = self.night
  local S = n.stations
  local f = self.freq
  self.drift = self:commonDrift()
  local best, bi, bd = 0, 0, 99
  for i = 1, #S do
    local st = S[i]
    local d = f - self:stationFreq(st)
    if abs(d) < st.sigma * 5 then
      local fd = 1 - st.fade * (0.5 + 0.5 * sin(st.fw * self.t + st.fp))
      local s = st.strength * fd * exp(-0.5 * (d / st.sigma) * (d / st.sigma))
      if s > best then best, bi, bd = s, i, d end
    end
  end
  self.sig = best
  self.detune = bd
  if best < 0.1 then bi = 0 end
  if bi ~= self.heard then
    if self.heard > 0 then S[self.heard].curSlot = -1 end
    self.heard = bi
  end
  self.meter = U.damp(self.meter, best, 7, dt)
  -- zero-beat hold
  if best > 0.97 then
    self.zeroT = self.zeroT + dt
    if self.zeroT >= 5 and not self.zeroAward then self.zeroAward = true self:award("zero") end
    if self.zeroT > self.bestZero then self.bestZero = self.zeroT end
  else
    self.zeroT = 0
  end
  -- audio: static falls away as signal rises; the beat whistles at the detune
  local st = bi > 0 and S[bi] or nil
  local nv = 0.03 + 0.17 * (1 - best) ^ 1.5
  self.noise:set(1200 + 600 * (1 - best), nv)
  if st then
    local wide = st.strength * exp(-0.5 * (bd / (st.sigma * 3)) ^ 2)
    local pitch = 45 + abs(bd) * 320
    local vol = 0.16 * wide
    if st.kind == "beacon" then
      local k = MORSE[floor(self.t * 8) % #MORSE + 1]
      vol = vol * k
    elseif st.kind == "music" then
      pitch = pitch * (1 + 0.04 * sin(self.t * 11)) * st.mpitch
    end
    self.beat:set(min(2600, pitch), vol)
  else
    self.beat:set(0, 0)
  end
  -- numbers transmissions
  if st and st.digits then self:listen(bi, st, best, dt) end
end

-- follow the heard station's transmission; copy digits into its record
function Num:listen(idx, st, s, dt)
  local ph = (self.t + st.offset) % st.loopLen
  local ts = st.ts
  local j = st.curSlot
  if j < 1 or ts[j] > ph or (j < #ts and ts[j + 1] <= ph) then
    -- find the slot (bounded: timelines are ~80 slots)
    local k = 1
    while k < #ts and ts[k + 1] <= ph do k = k + 1 end
    if j >= 1 then self:endSlot(idx, st) end
    if st.curSlot == -1 then
      -- just tuned in: no credit for a digit already under way
      st.curSlot = k
      st.qAcc, st.qN, st.fresh = 0, 0, false
    else
      st.curSlot = k
      st.qAcc, st.qN, st.fresh = 0, 0, true
      self:startSlot(st, k, s)
    end
  end
  st.qAcc = st.qAcc + s
  st.qN = st.qN + 1
end

function Num:startSlot(st, k, s)
  local kind, val = st.tk[k], st.tv[k]
  self.voiceCall = st.callStr
  if kind == 1 then
    Audio.play(Audio.TRIANGLE, val, 0.28 * s, 0.25, 0.01, 0.1, 0.6, 0.08)
    self.toneT = 0.25
    self.voiceDigit = nil
  elseif kind == 2 or kind == 3 then
    local v = 0.34 * s
    Audio.play(Audio.SINE, 330 + val * 55, v, 0.28, 0.01, 0.08, 0.7, 0.06)
    Audio.play(Audio.TRIANGLE, 660 + val * 110, v * 0.35, 0.2, 0.01, 0.06, 0.4, 0.05)
    self.toneT = 0.3
    self.voiceDigit = val
    self.voiceKind = kind
    self.voiceT = 0.4
    self.voiceQ = s
  end
  if k == 1 then
    local rec = self.recs[self.heard]
    if rec then rec.passes = rec.passes + 1 end
  end
end

function Num:endSlot(idx, st)
  local k = st.curSlot
  if not st.fresh or st.tk[k] ~= 3 or st.qN == 0 then return end
  local rec = self.recs[idx]
  if not rec then return end
  local q = st.qAcc / st.qN
  local pos = st.tp[k]
  local thr = self:cleanThreshold()
  local was = rec.best[pos] >= thr
  if q > rec.best[pos] then rec.best[pos] = q end
  rec.lockSum = rec.lockSum + q
  rec.lockN = rec.lockN + 1
  if not was and rec.best[pos] >= thr then
    rec.heardDigits = rec.heardDigits + 1
    self.digitsCopied = (self.digitsCopied or 0) + 1
    Audio.sfx.type()
    if pos <= 5 and st.msg and st.msg.key == K_PAD and self:indicatorClean(idx) then
      self:markPadStation(st)
    end
    if self:recComplete(idx) and not rec.completeNoted then
      rec.completeNoted = true
      Audio.sfx.gear()
      self:say(st.kind == "pad" and "PAD COPIED" or "COPY COMPLETE - B: NOTEPAD", 2)
      if rec.passes <= 1 and st.kind == "num" then self:award("clean") end
    end
  end
end

function Num:cleanThreshold()
  if self.mode == "tutorial" then return 0.5 end
  return ({ 0.55, 0.6, 0.66 })[self.difficulty] or 0.6
end

function Num:indicatorClean(idx)
  local rec = self.recs[idx]
  local thr = self:cleanThreshold()
  for i = 1, 5 do if rec.best[i] < thr then return false end end
  return true
end

function Num:markPadStation(st)
  local pi = st.msg.padStation
  for i = 1, #self.marks do if self.marks[i] == pi then return end end
  self.marks[#self.marks + 1] = pi
  self:say("PAD ON THE DIAL", 1.6)
end

function Num:recComplete(idx)
  local rec = self.recs[idx]
  if not rec then return false end
  local thr = self:cleanThreshold()
  for i = 1, #rec.best do if rec.best[i] < thr then return false end end
  return true
end

function Num:digitClean(idx, pos)
  local rec = self.recs[idx]
  return rec and rec.best[pos] and rec.best[pos] >= self:cleanThreshold()
end

-- is plaintext unit u of message i readable (key right, digits copied)?
function Num:unitReady(i, u)
  local n = self.night
  local st = n.stations[n.msgs[i]]
  local m = st.msg
  local d0, len = m.units.d0[u], m.units.n[u]
  for k = d0, d0 + len - 1 do
    if not self:digitClean(n.msgs[i], 5 + k) then return false end
    if m.key == K_PAD and not self:digitClean(m.padStation, k) then return false end
  end
  return true
end

function Num:msgAt(i)
  local n = self.night
  return n.stations[n.msgs[i]].msg, n.msgs[i]
end

function Num:currentMsg()
  local n = self.night
  return n.stations[n.msgs[self.msgIdx]].msg, n.msgs[self.msgIdx]
end

function Num:applyKey()
  local m = self:currentMsg()
  if self.keyOK[self.msgIdx] then return end
  if self.keySel == m.key then
    self.keyOK[self.msgIdx] = true
    Audio.sfx.menuSelect()
    self:say("KEY " .. KEY_NAME[m.key] .. " APPLIED", 1.2)
  else
    self.nonsenseT = 1.6
    Audio.sfx.denied()
    self:shake(2)
    if self.mode ~= "tutorial" then
      self.nightT = self.nightT + 8
      self.score = max(0, self.score - 50)
      self:say("NONSENSE  -8 MIN", 1.4)
    else
      self:say("NONSENSE. READ THE FIRST DIGIT.", 1.8)
    end
  end
end

function Num:messageDecoded()
  local i = self.msgIdx
  local n = self.night
  local st = n.stations[n.msgs[i]]
  local m = st.msg
  local rec = self.recs[n.msgs[i]]
  self.decoded[i] = true
  self.decodedCount = self.decodedCount + 1
  self:statAdd("decoded", 1)
  self:award("first")
  if m.key == K_PAD then self:award("pad") end
  local lock = rec.lockN > 0 and rec.lockSum / rec.lockN or 0.6
  local gain = 600 + floor(400 * U.clamp((lock - 0.5) / 0.5, 0, 1)) + (rec.passes <= 1 and 200 or 0) + 100 * (n.level)
  if self.mode ~= "tutorial" then self.score = self.score + gain end
  self.lastGain = gain
  Audio.sfx.success()
  self:shake(2)
  if m.final then
    self.state = "pick"
    self.pickSel = 1
    self:say("THE LAST WORD IS A PLACE", 2)
  else
    -- QSY: the next station's frequency goes on the dial in pencil
    self.msgIdx = i + 1
    self.viewMsg = i -- the decoded page stays open until the operator turns it
    self.marks[#self.marks + 1] = n.msgs[i + 1]
    self.keySel = 1
    self:say(fmt("QSY %d.%03d MHz", m.next // 1000, m.next % 1000), 2.4)
  end
end

function Num:pick(i)
  local n = self.night
  if i == n.answer then
    Audio.sfx.success()
    Audio.sfx.bell(880, 0.4)
    local left = max(0, self.nightLen - self.nightT)
    local bonus = 1000 + floor(left) * 3
    self.score = self.score + bonus
    self.lastGain = bonus
    self:statAdd("nights", 1)
    if left / self.nightLen >= 120 / NIGHT_MIN then self:award("dawn") end
    self.state = "done"
    self.endT = 0
    self.nightWon = true
  else
    Audio.sfx.fail()
    self:shake(4)
    self.score = max(0, self.score - 500)
    self.state = "done"
    self.endT = 0
    self.nightWon = false
  end
end

function Num:say(text, secs) self.msg, self.msgT = text, secs or 1.4 end

------------------------------------------------------------------------
-- input
------------------------------------------------------------------------
function Num:buttonDown(b)
  if self.state == "done" then
    if b == Input.A and self.endT > 1 then self:afterNight() end
    return
  end
  if self.state == "pick" then
    local n = #self.night.options
    if b == Input.UP then self.pickSel = (self.pickSel - 2) % n + 1 Audio.sfx.menuMove()
    elseif b == Input.DOWN then self.pickSel = self.pickSel % n + 1 Audio.sfx.menuMove()
    elseif b == Input.A then self:pick(self.pickSel) end
    return
  end
  if b == Input.B then
    self.pad = not self.pad
    self.viewMsg = self.msgIdx
    Audio.sfx.whoosh(0.12)
    return
  end
  if self.pad and self.viewMsg ~= self.msgIdx then
    if b == Input.A or b == Input.LEFT or b == Input.RIGHT then
      self.viewMsg = self.msgIdx
      Audio.sfx.menuMove()
    end
    return
  end
  if self.pad then
    if b == Input.LEFT then self.keySel = (self.keySel - 2) % 4 + 1 Audio.sfx.menuMove()
    elseif b == Input.RIGHT then self.keySel = self.keySel % 4 + 1 Audio.sfx.menuMove()
    elseif b == Input.A then self:applyKey() end
  else
    if b == Input.A then
      self.fine = not self.fine
      Audio.sfx.clank(0.25)
      self:say(self.fine and "FINE 10:1" or "COARSE", 0.7)
    end
  end
end

------------------------------------------------------------------------
-- update
------------------------------------------------------------------------
function Num:update(dt)
  self.t = self.t + dt
  if self.msgT > 0 then self.msgT = self.msgT - dt end
  self.nonsenseT = max(0, self.nonsenseT - dt)
  self.toneT = max(0, self.toneT - dt)
  self.voiceT = max(0, self.voiceT - dt)
  self:tune(dt)
  self:receive(dt)
  if self.coach then
    -- the lesson card moves out of the way while the notepad is open
    if self.pad then self.coach.y, self.coach.anchor = 20, "top"
    else self.coach.y, self.coach.anchor = 164, "bottom" end
  end
  self.scopePh = self.scopePh + dt * (4 + min(30, abs(self.detune) * 3))
  if self.finished then
    self.noise:set(0, 0) self.beat:set(0, 0)
    return
  end
  -- decoding: letters appear one by one once the key is right
  local i = self.msgIdx
  if self.state == "night" and self.keyOK[i] and not self.decoded[i] then
    local m = self:currentMsg()
    local nu = #m.units.str
    local r = self.reveal[i]
    local nr = min(nu, r + dt * 9)
    if floor(nr) > floor(r) then
      local u = floor(nr)
      if self:unitReady(i, u) then Audio.sfx.type() else nr = r end
    end
    self.reveal[i] = nr
    if floor(nr) >= nu then
      local all = true
      for u = 1, nu do if not self:unitReady(i, u) then all = false end end
      if all then self:messageDecoded() end
    end
  end
  if self.state == "done" then
    self.endT = self.endT + dt
    if self.endT > 3.5 then self:afterNight() end
    return
  end
  -- the night runs toward dawn
  self.nightT = self.nightT + dt
  if self.mode ~= "tutorial" and self.nightT >= self.nightLen then
    self.nightT = self.nightLen
    Audio.sfx.fail()
    Audio.sfx.horn(1.0, 0.3)
    self.state = "done"
    self.endT = 0
    self.nightWon = false
    self.dawn = true
  end
end

function Num:afterNight()
  if self.finished then return end
  self:statAdd("digits", self.digitsCopied or 0)
  self.digitsCopied = 0
  self:statMax("zerobeat", floor(self.bestZero * 10))
  if self.mode == "endless" and self.nightWon then
    self:startNight(false)
    return
  end
  self.noise:stop() self.beat:stop()
  local lines = { "Messages decoded: " .. self.decodedCount, "Nights: " .. (self.nightNo - (self.nightWon and 0 or 1)) }
  if self.mode == "standard" then
    self:finish({ success = self.decodedCount > 0, score = self.score,
      title = self.nightWon and "NIGHT READ" or (self.dawn and "DAWN BROKE" or "WRONG PLACE"), lines = lines })
  else
    self:finish({ success = self.decodedCount > 0, score = self.score,
      title = self.dawn and "DAWN BROKE" or "WRONG PLACE", lines = lines })
  end
end

------------------------------------------------------------------------
-- drawing
------------------------------------------------------------------------
local SX0 <const>, SX1 <const> = 12, 388
local function scaleX(f) return SX0 + (f - BAND_LO) * (SX1 - SX0) / (BAND_HI - BAND_LO) end

local digitImg = {}
local function bigDigit(str)
  local img = digitImg[str]
  if img then return img end
  img = gfx.image.new(UI.width(str, UI.bold) + 2, 18, gfx.kColorClear)
  gfx.pushContext(img)
  UI.textW(str, 1, 1, "left", UI.bold)
  gfx.popContext()
  digitImg[str] = img
  return img
end

local MHZ = { "3", "4", "5", "6", "7", "8", "9" }
local KHZLABEL = {}

function Num:drawScale()
  -- the lit glass tuning scale
  local img = Art.cached("num_scale", 400, 56, function(w, h)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRoundRect(2, 1, w - 4, h - 2, 6)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawRoundRect(4, 3, w - 8, h - 6, 5)
    for k = 0, 60 do
      local f = BAND_LO + k * 100
      local x = floor(scaleX(f))
      local len = (k % 10 == 0) and 9 or ((k % 5 == 0) and 6 or 3)
      gfx.drawLine(x, 7, x, 7 + len)
    end
    for m = 0, 6 do
      local x = floor(scaleX(BAND_LO + m * 1000))
      UI.textW(MHZ[m + 1], x, 16, "center", UI.bold)
    end
    UI.textW("MHz", w - 30, 16, "center")
    gfx.setColor(gfx.kColorWhite)
    gfx.drawLine(8, 35, w - 8, 35)
  end)
  img:draw(0, 19)
  local y0 = 19
  -- pencil marks for known stations
  local n = self.night
  gfx.setColor(gfx.kColorWhite)
  for i = 1, #self.marks do
    local st = n.stations[self.marks[i]]
    local x = floor(scaleX(st.nominal))
    gfx.fillTriangle(x - 3, y0 + 31, x + 3, y0 + 31, x, y0 + 26)
  end
  -- needle with a glow
  local nx = floor(scaleX(self.freq))
  gfx.setDitherPattern(0.5, gfx.kDitherTypeBayer4x4)
  gfx.fillRect(nx - 3, y0 + 4, 7, 30)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(nx - 1, y0 + 3, 2, 32)
  -- vernier strip: +-44 kHz around the needle, 4 px per kHz
  local vy = y0 + 38
  local f = self.freq
  gfx.setColor(gfx.kColorWhite)
  local k0 = floor(f - 46)
  for k = k0, k0 + 92 do
    local x = floor(200 + (k - f) * 4)
    if x > 8 and x < 392 then
      local len = (k % 10 == 0) and 5 or ((k % 5 == 0) and 3 or 1)
      gfx.drawLine(x, vy, x, vy + len)
      if k % 20 == 0 and x > 24 and x < 376 then
        local s = KHZLABEL[k]
        if not s then s = tostring(k) KHZLABEL[k] = s end
        UI.textW(s, x, vy + 3, "center")
      end
    end
  end
  for i = 1, #self.marks do
    local st = n.stations[self.marks[i]]
    local x = floor(200 + (st.nominal - f) * 4)
    if x > 8 and x < 392 then
      gfx.fillTriangle(x - 4, vy + 17, x + 4, vy + 17, x, vy + 12)
    end
  end
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(199, vy - 2, 2, 16)
  if self.fine then
    gfx.drawRect(150, vy - 3, 100, 18)
  end
  gfx.setColor(gfx.kColorBlack)
end

function Num:drawScope()
  local x0, y0, w, h = 4, 76, 130, 86
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRoundRect(x0, y0, w, h, 8)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawRoundRect(x0 + 2, y0 + 2, w - 4, h - 4, 7)
  -- graticule
  gfx.setDitherPattern(0.75, gfx.kDitherTypeBayer4x4)
  for i = 1, 3 do gfx.drawLine(x0 + i * w / 4, y0 + 6, x0 + i * w / 4, y0 + h - 6) end
  gfx.drawLine(x0 + 6, y0 + h / 2, x0 + w - 6, y0 + h / 2)
  gfx.setColor(gfx.kColorWhite)
  local s = self.sig
  local cy = y0 + h / 2
  local amp = 6 + 26 * s
  if self.toneT > 0 then amp = amp + 6 * s end
  local nAmp = 3 + 22 * (1 - s)
  local k = 0.25 + min(1.4, abs(self.detune) * 0.18)
  local off = floor(self.t * 90) % 128
  local px, py = x0 + 8, cy
  for i = 0, 56 do
    local x = x0 + 8 + i * 2
    local y = cy + amp * sin(self.scopePh + i * k) * min(1, s * 1.6) + nAmp * NOISE[(i * 3 + off) % 128 + 1]
    y = U.clamp(y, y0 + 5, y0 + h - 5)
    if i > 0 then gfx.drawLine(px, py, x, y) end
    px, py = x, y
  end
  gfx.setColor(gfx.kColorBlack)
end

function Num:drawKnob()
  -- tuning knob (turns with the crank) and the capacitor it works through the gear play
  local cx, cy = 30, 196
  gfx.setColor(gfx.kColorBlack)
  gfx.fillCircleAtPoint(cx, cy, 23)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawCircleAtPoint(cx, cy, 21)
  local a = self.knob
  for i = 0, 11 do
    local r = rad(a + i * 30)
    gfx.drawLine(cx + sin(r) * 17, cy - cos(r) * 17, cx + sin(r) * 21, cy - cos(r) * 21)
  end
  local r = rad(a)
  gfx.fillCircleAtPoint(cx + sin(r) * 11, cy - cos(r) * 11, 3)
  gfx.setColor(gfx.kColorBlack)
  -- the capacitor: rotor plates swing into the stator
  local kx, ky = 100, 200
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(70, 166, 62, 52)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(70, 166, 62, 52)
  -- stator plates (fixed, lower half) and the rotor swinging with the capacitor
  gfx.setPattern(Art.pat.gray50)
  gfx.fillEllipseInRect(kx - 22, ky - 22, 44, 44, 90, 270)
  local ang = -90 + 180 * (self.cap / ((BAND_HI - BAND_LO) / KHZ_PER_DEG))
  gfx.setPattern(Art.pat.hlines2)
  gfx.fillEllipseInRect(kx - 19, ky - 19, 38, 38, ang - 90, ang + 90)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawArc(kx, ky, 19, ang - 90, ang + 90)
  local a1, a2 = rad(ang - 90), rad(ang + 90)
  gfx.drawLine(kx + sin(a1) * 19, ky - cos(a1) * 19, kx + sin(a2) * 19, ky - cos(a2) * 19)
  gfx.fillCircleAtPoint(kx, ky, 3)
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(71, 167, 60, 12)
  gfx.setColor(gfx.kColorBlack)
  if self.slackT > 0 then
    gfx.fillRect(71, 167, 60, 12)
    UI.textW("PLAY", kx, 164, "center", UI.bold)
  else
    UI.text("CAP", kx, 164, "center")
  end
  -- FINE lamp
  if self.fine then
    gfx.fillRoundRect(6, 164, 50, 15, 3)
    UI.textW("FINE", 31, 163, "center", UI.bold)
  else
    UI.text("COARSE", 31, 163, "center")
  end
end

function Num:drawMeter()
  UI.meter(196, 124, 38, self.meter, -65, 65, 10, 0.8)
  UI.text("SIGNAL", 196, 130, "center")
  -- two valves glowing with the signal
  for i = 0, 1 do
    local vx = (i == 0) and 144 or 236
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRoundRect(vx, 80, 16, 30, 7)
    Art.setShade(1 - 0.2 - 0.6 * self.meter)
    gfx.fillRoundRect(vx + 3, 84, 10, 20, 4)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(vx + 2, 110, 12, 4)
  end
end

function Num:drawVoice()
  local x0, y0 = 138, 162
  gfx.setColor(gfx.kColorBlack)
  gfx.fillRect(x0, y0, 116, 58)
  gfx.setColor(gfx.kColorWhite)
  gfx.drawRect(x0 + 2, y0 + 2, 112, 54)
  UI.textW("VOICE", x0 + 8, y0 + 4)
  if self.heard > 0 and self.voiceCall and self.night.stations[self.heard].digits then
    UI.textW(self.voiceCall, x0 + 108, y0 + 4, "right", UI.bold)
  end
  if self.voiceT > 0 and self.voiceDigit then
    local q = self.voiceQ or 0
    local str = (q >= self:cleanThreshold()) and DIGITSTR[self.voiceDigit] or "?"
    local img = bigDigit(str)
    local iw = img:getSize()
    img:drawScaled(x0 + 58 - iw, y0 + 20, 2)
  elseif self.sig < 0.1 then
    -- hiss
    gfx.setColor(gfx.kColorWhite)
    local off = floor(self.t * 60) % 128
    for i = 0, 18 do
      local nx = x0 + 10 + ((i * 37 + off * 7) % 96)
      local ny = y0 + 22 + ((i * 13 + off * 3) % 28)
      gfx.drawPixel(nx, ny)
      gfx.drawPixel(nx + 1, ny)
    end
  end
  gfx.setColor(gfx.kColorBlack)
end

-- draw one record's digits as groups; returns next y
function Num:drawGroups(idx, x0, y0, perRow, gw, gh, white)
  local st = self.night.stations[idx]
  local rec = self.recs[idx]
  local thr = self:cleanThreshold()
  local draw = white and UI.textW or UI.text
  local nd = #st.digits
  local live = (self.heard == idx) and st.curSlot > 0 and st.tk[st.curSlot] == 3 and st.tp[st.curSlot] or -1
  local cw = floor((gw - 6) / 5)
  local rows = 0
  for g = 0, (nd - 1) // 5 do
    local col = g % perRow
    local row = g // perRow
    rows = row + 1
    local gx = x0 + col * gw
    local gy = y0 + row * gh
    for k = 1, 5 do
      local pos = g * 5 + k
      if pos <= nd then
        local x = gx + (k - 1) * cw
        local str = rec.best[pos] >= thr and DIGITSTR[st.digits[pos]] or "?"
        draw(str, x, gy)
        if pos == live then
          if white then gfx.setColor(gfx.kColorWhite) else gfx.setColor(gfx.kColorBlack) end
          gfx.fillRect(x, gy + 15, cw - 1, 2)
          gfx.setColor(gfx.kColorBlack)
        end
      end
    end
  end
  return y0 + rows * gh
end

function Num:drawPadSmall()
  local x0, y0 = 258, 74
  gfx.setColor(gfx.kColorWhite)
  gfx.fillRect(x0, y0, 138, 146)
  gfx.setColor(gfx.kColorBlack)
  gfx.drawRect(x0, y0, 138, 146)
  gfx.setPattern(Art.pat.hlines)
  gfx.fillRect(x0 + 1, y0 + 36, 136, 1)
  gfx.setColor(gfx.kColorBlack)
  local m, idx = self:currentMsg()
  local st = self.night.stations[idx]
  UI.text(U.cached("num_f", "%.3f", st.nominal / 1000), x0 + 6, y0 + 3, "left", UI.bold)
  UI.text(U.cached("num_msg", "MSG %d", self.msgIdx) , x0 + 132, y0 + 3, "right")
  UI.text("CALL", x0 + 6, y0 + 19)
  UI.text(st.callStr, x0 + 50, y0 + 19, "left", UI.bold)
  local y = self:drawGroups(idx, x0 + 8, y0 + 42, 2, 64, 17, false)
  if m.key == K_PAD and self:indicatorClean(idx) then
    UI.text("+ PAD", x0 + 6, y + 2, "left", UI.bold)
    local ps = self.night.stations[m.padStation]
    UI.text(U.cached("num_pf", "%.3f", ps.nominal / 1000), x0 + 132, y + 2, "right")
    local rec = self.recs[m.padStation]
    UI.gauge(x0 + 8, y + 20, 122, 7, rec.heardDigits / #ps.digits)
  end
  if self.decoded[self.msgIdx] then
    UI.stamp("DECODED", x0 + 69, y0 + 120, 1)
  end
end

function Num:drawPadBig()
  local x0, y0, w, h = 4, 74, 392, 146
  UI.panel(x0, y0, w, h, "plain")
  local vi = self.viewMsg or self.msgIdx
  local m, idx = self:msgAt(vi)
  local st = self.night.stations[idx]
  UI.text(U.cached("num_bf", "MSG %d", vi), x0 + 8, y0 + 4, "left", UI.bold)
  UI.text("CALL", x0 + 80, y0 + 4, "left", UI.bold)
  UI.text(st.callStr, x0 + 130, y0 + 4, "left", UI.bold)
  UI.text(self.night.dateStr, x0 + w - 8, y0 + 4, "right", UI.bold)
  UI.text("1 PLAIN  2 DATE  3 PAD+FREQ  4 BOOK", x0 + 8, y0 + 20)
  gfx.drawLine(x0 + 6, y0 + 37, x0 + w - 6, y0 + 37)
  local y = self:drawGroups(idx, x0 + 10, y0 + 42, 5, 72, 17, false)
  if m.key == K_PAD and self:indicatorClean(idx) then
    UI.text("PAD", x0 + 10, y, "left", UI.bold)
    self:drawPadDigitsRow(m.padStation, x0 + 50, y)
    y = y + 17
  end
  -- key selector
  y = max(y + 2, y0 + 96)
  local ok = self.keyOK[vi]
  UI.text("KEY", x0 + 10, y, "left", UI.bold)
  if ok then
    gfx.fillRoundRect(x0 + 50, y - 1, 70, 17, 3)
    UI.textW(KEY_NAME[m.key], x0 + 85, y, "center", UI.bold)
  else
    UI.text("<", x0 + 52, y, "left", UI.bold)
    UI.text(KEY_NAME[self.keySel], x0 + 85, y, "center", UI.bold)
    UI.text(">", x0 + 112, y, "left", UI.bold)
    UI.text("A: apply", x0 + 132, y)
  end
  if vi ~= self.msgIdx then
    UI.stamp("DECODED", x0 + w - 64, y0 + 124, 1)
    UI.text("A: next page", x0 + w - 10, y, "right")
  end
  -- plaintext
  local py = y + 20
  local px = x0 + 10
  local units = m.units
  local rev = self.reveal[vi]
  if self.nonsenseT > 0 then
    local off = floor(self.t * 30)
    for u = 1, #units.str do
      local c = CHARSTR[65 + (u * 7 + off) % 26]
      UI.text(c, px, py, "left", UI.bold)
      px = px + 12
      if px > x0 + w - 20 then break end
    end
  elseif ok then
    for u = 1, #units.str do
      local s = units.str[u]
      if u <= rev then
        if self:unitReady(vi, u) then
          UI.text(s, px, py, "left", UI.bold)
          px = px + UI.width(s, UI.bold) + ((m.key == K_BOOK) and 8 or 0)
        else
          UI.text("?", px, py, "left", UI.bold)
          px = px + 12
        end
      else
        UI.text("_", px, py, "left", UI.bold)
        px = px + 12
      end
      if px > x0 + w - 24 then px = x0 + 10 py = py + 18 end
    end
  else
    UI.text("the first digit names the key", x0 + 10, py)
  end
  if m.key == K_BOOK and ok then
    -- the codebook page
    local bl = self.night.bookList
    local bx = x0 + w - 108
    UI.text("CODEBOOK", bx, y0 + 96, "left", UI.bold)
    for i = 1, min(3, #bl) do
      UI.text(bl[i].codeStr, bx, y0 + 96 + i * 15)
      UI.text(bl[i].word, bx + 34, y0 + 96 + i * 15)
    end
  end
end

function Num:drawPadDigitsRow(pidx, x, y)
  local ps = self.night.stations[pidx]
  local rec = self.recs[pidx]
  local thr = self:cleanThreshold()
  for k = 1, min(#ps.digits, 30) do
    local str = rec.best[k] >= thr and DIGITSTR[ps.digits[k]] or "?"
    UI.text(str, x + (k - 1) * 10 + ((k - 1) // 5) * 4, y)
  end
end

function Num:drawPick()
  local n = self.night
  UI.popup(210, 78, 182, 136, "ink")
  UI.textW("WHERE?", 301, 84, "center", UI.bold)
  for i = 1, #n.options do
    local y = 106 + (i - 1) * 24
    if i == self.pickSel then
      gfx.setColor(gfx.kColorWhite)
      gfx.fillRect(218, y - 2, 166, 20)
      UI.text(n.options[i], 301, y, "center", UI.bold)
      gfx.setColor(gfx.kColorBlack)
    else
      UI.textW(n.options[i], 301, y, "center")
    end
  end
end

function Num:drawDone()
  UI.panel(90, 76, 220, 96, "paper")
  local title = self.nightWon and "NIGHT READ" or (self.dawn and "DAWN" or "WRONG PLACE")
  UI.stamp(title, 200, 102, self.endT)
  if self.nightWon then
    UI.text(U.cached("num_gain", "+%d", self.lastGain or 0), 200, 124, "center", UI.bold)
  else
    UI.text(self.night.place, 200, 124, "center", UI.bold)
  end
  if self.endT > 1 then UI.text("A: continue", 200, 146, "center") end
end

function Num:headerRight()
  if self.mode == "tutorial" then return "LESSON" end
  local mins = floor(self.nightT / self.nightLen * NIGHT_MIN)
  if mins ~= self.hdrMin or self.hdrMsg ~= self.msgIdx then
    self.hdrMin, self.hdrMsg = mins, self.msgIdx
    local clock = (22 * 60 + mins) % (24 * 60)
    local prefix = self.mode == "endless" and fmt("NIGHT %d  ", self.nightNo) or ""
    self.hdrStr = fmt("%sMSG %d/%d  %02d:%02d", prefix, self.msgIdx, #self.night.msgs, clock // 60, clock % 60)
  end
  return self.hdrStr
end

Num.HINTS_RADIO = { { "CRANK", "TUNE" }, { "A", "FINE" }, { "B", "NOTEPAD" } }
Num.HINTS_PAD = { { "DPAD", "KEY" }, { "A", "APPLY" }, { "B", "DIAL" }, { "CRANK", "TUNE" } }
Num.HINTS_PICK = { { "DPAD", "CHOOSE" }, { "A", "CONFIRM" } }

function Num:draw()
  gfx.clear(gfx.kColorWhite)
  -- cabinet: walnut veneer
  gfx.setPattern(Art.pat.wood)
  gfx.fillRect(0, 18, 400, 204)
  gfx.setColor(gfx.kColorBlack)
  self:drawScale()
  if self.pad or self.state == "pick" then
    self:drawPadBig()
  else
    self:drawScope()
    self:drawKnob()
    self:drawMeter()
    self:drawVoice()
    self:drawPadSmall()
  end
  if self.state == "pick" then self:drawPick() end
  if self.state == "done" then self:drawDone() end
  UI.header(5, "NUMBERS STATION", self:headerRight())
  if self.msgT > 0 and self.msg then
    local w = UI.width(self.msg, UI.bold) + 20
    local my = (self.pad or self.state == "pick") and 40 or 194
    UI.panel(200 - w / 2, my, w, 24, "ink")
    UI.textW(self.msg, 200, my + 4, "center", UI.bold)
  end
  if self.mode ~= "tutorial" then
    if self.state == "pick" then UI.hints(Num.HINTS_PICK)
    elseif self.pad then UI.hints(Num.HINTS_PAD)
    else UI.hints(Num.HINTS_RADIO) end
  end
end

------------------------------------------------------------------------
-- suspend / resume
------------------------------------------------------------------------
function Num:serialize()
  local recs = {}
  local n = self.night
  for i = 1, #n.stations do
    local rec = self.recs[i]
    if rec then
      local b = {}
      for k = 1, #rec.best do b[k] = floor(rec.best[k] * 100 + 0.5) / 100 end
      recs[#recs + 1] = { i = i, best = b, passes = rec.passes, heard = rec.heardDigits, ls = rec.lockSum, ln = rec.lockN }
    end
  end
  local keyOK, decoded = {}, {}
  for i = 1, #n.msgs do keyOK[i] = self.keyOK[i] decoded[i] = self.decoded[i] end
  return {
    rng = self.rng:state(), nightNo = self.nightNo, nightSeed = self.nightSeed, level = n.level,
    score = self.score, decodedCount = self.decodedCount, nightT = self.nightT, msgIdx = self.msgIdx,
    recs = recs, keyOK = keyOK, decoded = decoded, freq = self.freq, fine = self.fine, t = self.t,
    marks = self.marks, state = self.state,
  }
end

function Num:deserialize(s)
  self.rng:setState(s.rng)
  self.nightNo = s.nightNo
  self.nightSeed = s.nightSeed
  self.night = self:makeNight(s.nightSeed, s.level or 0, self.mode == "tutorial")
  self:resetNightState()
  self.score, self.decodedCount = s.score or 0, s.decodedCount or 0
  self.nightT, self.msgIdx = s.nightT or 0, s.msgIdx or 1
  self.t = s.t or 0
  for _, r in ipairs(s.recs or {}) do
    local rec = self.recs[r.i]
    if rec then
      for k = 1, #rec.best do rec.best[k] = r.best[k] or 0 end
      rec.passes, rec.heardDigits, rec.lockSum, rec.lockN = r.passes or 0, r.heard or 0, r.ls or 0, r.ln or 0
    end
  end
  for i = 1, #self.night.msgs do
    self.keyOK[i] = s.keyOK and s.keyOK[i] == true
    self.decoded[i] = s.decoded and s.decoded[i] == true
    if self.decoded[i] then self.reveal[i] = #self.night.stations[self.night.msgs[i]].msg.units.str end
  end
  if s.marks then self.marks = s.marks end
  self:setFreq(s.freq or self.night.start)
  self.fine = s.fine == true
  if s.state == "pick" then self.state = "pick" end
  if self.mode == "tutorial" then self:setupCoach() end
end
