-- CRANKING IT :: core/audio
-- Fully synthesized audio: pooled one-shot voices, continuous "hum" voices
-- for motors/wind/static, short jingles, and a tiny music-box sequencer.
-- No sample assets are needed.

Audio = {}

local snd <const> = playdate.sound
local pools = {}
local poolIndex = {}
local POOL_SIZES <const> = {
  [snd.kWaveSquare] = 4, [snd.kWaveTriangle] = 4, [snd.kWaveSine] = 4,
  [snd.kWaveNoise] = 5, [snd.kWaveSawtooth] = 2,
}

Audio.enabled = true
Audio.master = 0.8

Audio.SQUARE = snd.kWaveSquare
Audio.TRIANGLE = snd.kWaveTriangle
Audio.SINE = snd.kWaveSine
Audio.NOISE = snd.kWaveNoise
Audio.SAW = snd.kWaveSawtooth

function Audio.init()
  for wave, n in pairs(POOL_SIZES) do
    pools[wave] = {}
    poolIndex[wave] = 0
    for i = 1, n do pools[wave][i] = snd.synth.new(wave) end
  end
end

local function nextVoice(wave)
  local p = pools[wave]
  local i = poolIndex[wave] % #p + 1
  poolIndex[wave] = i
  return p[i]
end

-- One-shot note. Envelope defaults give a plucky percussive shape.
function Audio.play(wave, freq, vol, len, attack, decay, sustain, release, delay)
  if not Audio.enabled or freq <= 0 then return end
  local v = nextVoice(wave)
  v:setADSR(attack or 0.002, decay or 0.08, sustain or 0.0, release or 0.05)
  local when = nil
  if delay and delay > 0 then when = snd.getCurrentTime() + delay end
  v:playNote(freq, U.clamp((vol or 0.5) * Audio.master, 0, 1), len or 0.1, when)
end

------------------------------------------------------------------------
-- Hum: a continuous voice whose pitch/volume can glide every frame.
------------------------------------------------------------------------
local Hum = U.class()
Audio.Hum = Hum
local allHums = {}

function Hum:init(wave, attack, release)
  self.synth = snd.synth.new(wave)
  self.synth:setADSR(attack or 0.05, 0.01, 1.0, release or 0.12)
  self.synth:setLegato(true)
  self.freq, self.vol = 0, 0
  self.on = false
  allHums[#allHums + 1] = self
end

function Hum:set(freq, vol)
  vol = vol * Audio.master
  if not Audio.enabled or vol < 0.01 or freq <= 0 then
    if self.on then self.synth:noteOff() self.on = false end
    self.freq, self.vol = 0, 0
    return
  end
  -- only retrigger when something audibly changed (saves CPU / calls)
  if (not self.on) or math.abs(freq - self.freq) > self.freq * 0.004 or math.abs(vol - self.vol) > 0.02 then
    self.synth:playNote(freq, U.clamp(vol, 0, 1))
    self.freq, self.vol = freq, vol
    self.on = true
  end
end

function Hum:stop()
  if self.on then self.synth:noteOff() end
  self.on = false
  self.freq, self.vol = 0, 0
end

function Audio.stopAllHums()
  for i = 1, #allHums do allHums[i]:stop() end
end

------------------------------------------------------------------------
-- Sound effect library (shared UI & mechanical sounds)
------------------------------------------------------------------------
local P = Audio.play
local SQ, TR, SI, NO, SA = snd.kWaveSquare, snd.kWaveTriangle, snd.kWaveSine, snd.kWaveNoise, snd.kWaveSawtooth

Audio.sfx = {
  tick = function(pitch, vol) P(SQ, pitch or 1800, vol or 0.18, 0.01, 0.001, 0.015, 0, 0.01) end,
  click = function(vol) P(NO, 4000, vol or 0.35, 0.01, 0.001, 0.02, 0, 0.01) end,
  clack = function(vol) P(NO, 1500, vol or 0.45, 0.03, 0.001, 0.05, 0, 0.02) P(SQ, 180, (vol or 0.45) * 0.4, 0.03, 0.001, 0.04, 0, 0.02) end,
  -- low impacts carry an upper harmonic and a click: the Playdate speaker
  -- barely reproduces anything below ~200 Hz
  thunk = function(vol) P(SI, 90, vol or 0.7, 0.12, 0.001, 0.15, 0, 0.05) P(TR, 270, (vol or 0.7) * 0.45, 0.08, 0.001, 0.09, 0, 0.04) P(NO, 600, (vol or 0.7) * 0.5, 0.04, 0.001, 0.06, 0, 0.02) end,
  clank = function(vol) P(TR, 320, vol or 0.5, 0.2, 0.001, 0.25, 0, 0.1) P(TR, 473, (vol or 0.5) * 0.6, 0.2, 0.001, 0.2, 0, 0.1) P(NO, 3000, (vol or 0.5) * 0.4, 0.03) end,
  thud = function(vol) P(SI, 60, vol or 0.8, 0.2, 0.001, 0.2, 0, 0.05) P(TR, 240, (vol or 0.8) * 0.4, 0.07, 0.001, 0.08, 0, 0.03) P(NO, 900, (vol or 0.8) * 0.25, 0.02, 0.001, 0.03, 0, 0.01) end,
  whoosh = function(vol) P(NO, 800, vol or 0.25, 0.25, 0.08, 0.2, 0, 0.1) end,
  splash = function(vol) P(NO, 1200, vol or 0.5, 0.35, 0.005, 0.4, 0, 0.2) P(SI, 140, (vol or 0.5) * 0.4, 0.1, 0.001, 0.12) end,
  creak = function(vol) P(SA, 70 + math.random() * 20, vol or 0.2, 0.3, 0.05, 0.3, 0.2, 0.1) end,
  snap = function(vol) P(NO, 5000, vol or 0.8, 0.05, 0.0, 0.08, 0, 0.02) P(SQ, 1200, (vol or 0.8) * 0.3, 0.03) end,
  bell = function(pitch, vol) P(SI, pitch or 880, vol or 0.5, 0.6, 0.001, 0.8, 0, 0.4) P(SI, (pitch or 880) * 2.76, (vol or 0.5) * 0.25, 0.3, 0.001, 0.3, 0, 0.2) end,
  horn = function(len, vol) P(SA, 110, vol or 0.5, len or 1.2, 0.15, 0.1, 0.9, 0.3) P(SQ, 55, (vol or 0.5) * 0.3, len or 1.2, 0.2, 0.1, 0.9, 0.3) end,
  menuMove = function() P(SQ, 1320, 0.12, 0.015, 0.001, 0.02, 0, 0.01) end,
  menuSelect = function() P(SQ, 880, 0.2, 0.04) P(SQ, 1320, 0.2, 0.06, nil, nil, nil, nil, 0.05) end,
  back = function() P(SQ, 660, 0.18, 0.04) P(SQ, 440, 0.18, 0.06, nil, nil, nil, nil, 0.05) end,
  denied = function() P(SQ, 150, 0.3, 0.12, 0.001, 0.1, 0.4, 0.05) end,
  coin = function() P(SQ, 988, 0.25, 0.06) P(SQ, 1319, 0.25, 0.25, nil, 0.2, 0, 0.1, 0.06) end,
  gear = function(delay)
    P(TR, 523, 0.35, 0.08, 0.001, 0.1, 0, 0.05, delay)
    P(TR, 784, 0.35, 0.08, 0.001, 0.1, 0, 0.05, (delay or 0) + 0.07)
    P(TR, 1047, 0.35, 0.2, 0.001, 0.25, 0, 0.1, (delay or 0) + 0.14)
  end,
  success = function()
    local n = { 523, 659, 784, 1047 }
    for i = 1, 4 do P(SQ, n[i], 0.25, 0.09, 0.002, 0.1, 0.3, 0.05, (i - 1) * 0.09) end
    P(TR, 1047, 0.3, 0.5, 0.002, 0.4, 0.3, 0.3, 0.36)
  end,
  fail = function()
    local n = { 392, 370, 349, 262 }
    for i = 1, 4 do P(SQ, n[i], 0.25, 0.14, 0.002, 0.1, 0.4, 0.05, (i - 1) * 0.15) end
  end,
  achievement = function()
    local n = { 784, 988, 1175, 1568 }
    for i = 1, 4 do P(TR, n[i], 0.35, 0.08, 0.001, 0.1, 0.2, 0.05, (i - 1) * 0.06) end
    P(SI, 1568, 0.3, 0.6, 0.001, 0.6, 0, 0.3, 0.26)
  end,
  stamp = function() P(NO, 400, 0.8, 0.06, 0.001, 0.1, 0, 0.05) P(SI, 70, 0.8, 0.15, 0.001, 0.15, 0, 0.05) P(TR, 210, 0.35, 0.08, 0.001, 0.08, 0, 0.03) end,
  type = function() P(NO, 2600 + math.random() * 800, 0.08, 0.008, 0.001, 0.01, 0, 0.005) end,
}

------------------------------------------------------------------------
-- Music box: a tiny looping sequencer for ambient tunes (hub, title).
------------------------------------------------------------------------
local MusicBox = U.class()
Audio.MusicBox = MusicBox

-- notes: array of {freq, beats}; freq 0 = rest
function MusicBox:init(notes, bpm, wave, vol)
  self.notes = notes
  self.beat = 60 / (bpm or 90)
  self.wave = wave or snd.kWaveTriangle
  self.vol = vol or 0.18
  self.i = 0
  self.t = 0
  self.playing = false
end
function MusicBox:start() self.playing = true self.t = 0 self.i = 0 end
function MusicBox:stop() self.playing = false end
function MusicBox:update(dt, rate)
  if not self.playing then return end
  self.t = self.t - dt * (rate or 1)
  if self.t <= 0 then
    self.i = self.i % #self.notes + 1
    local n = self.notes[self.i]
    local len = n[2] * self.beat
    if n[1] > 0 then
      Audio.play(self.wave, n[1], self.vol, len * 0.9, 0.003, len * 0.6, 0.15, len * 0.5)
    end
    self.t = self.t + len
  end
end

-- note name helper: Audio.note("A4") -> 440
local NOTE_OFF = { C = -9, D = -7, E = -5, F = -4, G = -2, A = 0, B = 2 }
function Audio.note(name)
  local l, acc, oct = name:match("^(%u)([#b]?)(%d)$")
  local n = NOTE_OFF[l] + (acc == "#" and 1 or (acc == "b" and -1 or 0)) + (tonumber(oct) - 4) * 12
  return 440 * 2 ^ (n / 12)
end
