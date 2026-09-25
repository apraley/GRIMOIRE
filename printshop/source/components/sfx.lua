-- Tiny square-wave sound effects. One synth per voice, created lazily.
-- Respects settings.sound.

Sfx = { voices = {} }

local NOTES = {
	move = { 880, 0.02 },
	tick = { 1320, 0.012 },
	ok = { 660, 0.05, 990, 0.06 },
	back = { 520, 0.04 },
	error = { 180, 0.12 },
	done = { 523, 0.08, 659, 0.08, 784, 0.08, 1046, 0.16 },
	fail = { 392, 0.1, 330, 0.1, 262, 0.2 },
	type = { 1800, 0.008 },
	flip = { 300, 0.02 },
}

local function voice(i)
	local v = Sfx.voices[i]
	if v == nil then
		v = playdate.sound.synth.new(playdate.sound.kWaveSquare)
		Sfx.voices[i] = v
	end
	return v
end

function Sfx.play(name)
	if Store.data and not Store.settings().sound then return end
	local seq = NOTES[name]
	if seq == nil then return end
	-- Multi-note jingles are spread across voices with start offsets.
	local now = playdate.sound.getCurrentTime()
	local t = 0
	local vi = 1
	for i = 1, #seq, 2 do
		local v = voice(vi)
		v:playNote(seq[i], 0.25, seq[i + 1], now + t)
		t = t + seq[i + 1]
		vi = vi % 4 + 1
	end
end
