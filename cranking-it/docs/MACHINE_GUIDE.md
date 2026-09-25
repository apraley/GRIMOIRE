# Machine implementation guide

This is the contract every machine in CRANKING IT follows. Read
`source/machines/safecracker.lua` first — it is the reference implementation
and exercises everything described here.

## Files

* One machine = one file in `source/machines/<id>.lua`. It is imported by
  `source/main.lua` (already wired for all 13).
* Do **not** edit shared files (`source/core/*`, `source/scenes/*`,
  `source/main.lua`, `tools/*`) from a machine task. If you need something
  from them, work around it locally in your machine file and mention it in
  your report.
* Machine-private helpers go at the top of the machine file as `local`s.
  Only the machine class itself becomes global (via `Machine.define`).

## Definition

```lua
local M = Machine.define({
  id = "fishing", number = 2, title = "FISHING LINE",
  tagline = "Short, <= 28 characters.",
  description = "<= ~110 characters. Shown on the placard (4 lines at 244px).",
  howto = "<= ~220 characters. Shown on the in-game 'how to play' card.",
  controls = { { "CRANK", "reel in" }, { "DPAD", "rod angle" }, { "A", "set drag" } },
  modes = { "tutorial", "standard", "endless" },   -- endless where appropriate
  medals = { standard = { brass, silver, gold }, endless = { ... } },
  scoreLabel = "POUNDS",           -- what the score counts
  unlockCost = 0,                  -- keep the value already in the stub file
  needsCrank = true,               -- default; PlayScene pauses when docked
  achievements = { { id = "x", name = "NAME", desc = "Short desc (<= 34 chars)." }, ... }, -- 4-5
  challenges = {                   -- 2-3, bought with gears after a brass medal
    { id = "c1", name = "NAME", desc = "...", mode = "standard", difficulty = 2,
      mods = { rusty = true }, goal = 1234, reward = 2, cost = 2 },
  },
  records = { { "statKey", "Label" }, { "k2", "Label", function(v) return fmt end } },
  drawIcon = function(cx, cy) ... end,  -- 48x48 cabinet art centred on cx, cy
})
```

Glyph names for `controls` / `UI.hints`: `"CRANK"`, `"DPAD"`, `"A"`, `"B"`
or any short word.

Medals: brass = a new player who finished the tutorial can get it on the
first or second try; silver = competent; gold = expert. Gears are paid on
each new medal tier, so thresholds matter for the economy.

## Lifecycle (all methods optional, defaults are no-ops)

| method | when |
|---|---|
| `init()` | once when the instance is created (before `enter`) |
| `enter(params)` | start a run. `self.mode` (`tutorial`/`standard`/`endless`), `self.difficulty` (1-3), `self.rng` (seeded `U.rng`), `self.mods`, `self.params` are already set |
| `exit()` | leaving; stop every `Audio.Hum` you started |
| `update(dt)` | fixed timestep, `dt = 1/30` (maybe 1.35x under the HASTE mod). Keep simulation work bounded per call |
| `draw()` | draw the **whole** screen (clear it yourself) |
| `cranked(change, accel)` | raw crank degrees since the last frame (clockwise positive). Called once per frame before `update` |
| `buttonDown(b)` / `buttonUp(b)` | `b` is one of `Input.A, Input.B, Input.UP, Input.DOWN, Input.LEFT, Input.RIGHT` |
| `serialize()` | return a JSON-safe table with the in-progress run (for suspend on quit/sleep), or nil |
| `deserialize(t)` | restore from that table (called after `enter(params)`) |

Held buttons: `Input.held(Input.LEFT)`, `Input.axisX()`, `Input.holdTime(b)`,
`Input.repeated(b)` (auto-repeat).

Ending a run: `self:finish({ success = bool, score = int, title = "STAMP TEXT", lines = { "up to 5 short lines" }, delay = 1.4 })`.
PlayScene keeps calling `update` for `delay` seconds (animate the ending), then
records medals/bests/gears and shows the results card.

Tutorial mode: in `enter`, set `self.coach = UI.Coach.new(steps, opts)`.
Each step `{ text = "...", check = function(dt) return bool end, hold = secs }`.
PlayScene updates/draws the coach and finishes the run with "LESSON LEARNED"
when the last step passes. The tutorial must teach the real mechanic by
making the player do it, step by step, on a gentle version of the machine.
Coach opts: `{ y = 22, h = 46, x = 8, w = 384, anchor = "bottom", inverted = false }`.
Keep step text short (it wraps; about 2 lines).

Helpers on `self`: `award(achId)`, `statAdd(key, n)`, `statMax(key, v)`,
`shake(mag)`, `flash(frames)`, `best(mode)`, `mod(name)`.

## Shared modules

* `U` (core/util): `clamp lerp remap approach damp smoothstep angleDiff dist round
  commas timeStr roman copy deepcopy hash rng(seed) class(parent) ring(n) cached(key, fmt, v)`.
  `U.rng(seed)` → `:float() :range(a,b) :between(a,b) :chance(p) :pick(t) :shuffle(t) :gauss() :weighted(w) :state() :setState(s)`.
* `Crank` (core/crank): `Crank.Tracker` (velocity, reversals, idle), `Crank.Detent`
  (notch crossings), `Crank.Flywheel` (inertia + coupling), `Crank.Flick`, `Crank.Jiggle`.
* `Audio`: `Audio.sfx.<name>()` (tick click clack thunk clank thud whoosh splash
  creak snap bell horn menuMove menuSelect back denied coin gear success fail
  achievement stamp type), `Audio.play(wave, freq, vol, len, a, d, s, r, delay)`,
  `Audio.Hum.new(wave)` → `:set(freq, vol)` every frame, `:stop()`;
  waves `Audio.SQUARE TRIANGLE SINE NOISE SAW`; `Audio.note("A4")`;
  `Audio.MusicBox.new(notes, bpm, wave, vol)`.
* `Art`: patterns `Art.pat.<name>` (white gray6 gray12 gray25 gray50 gray75 gray87
  black hatch hatchR hatchD cross hlines hlines2 vlines dots wood grain bricks waves
  scales weave grid stipple) with `gfx.setPattern(Art.pat.x)`, `Art.setShade(0..1)`,
  `Art.cached(key, w, h, builderFn)` (render static art once), `Art.gear`,
  `Art.frame`, `Art.rivet`, `Art.plate`, `Art.sea`, `Art.line`, `Art.haloText`,
  `Art.crankGlyph`, `Art.poly` + `Art.polyFill(n)` (scratch polygon buffer).
* `UI`: `UI.font`, `UI.bold`, `UI.lineH`; `UI.text(str, x, y, align, font)`,
  `UI.textW` (white), `UI.width`, `UI.wrap`, `UI.textBlock`, `UI.textLines`,
  `UI.panel(x,y,w,h,"paper"|"ink"|"plain")`, `UI.popup`, `UI.header(number, title, rightText)`
  (18px strip at top), `UI.hints(list)` (18px strip at bottom), `UI.glyph`,
  `UI.gauge`, `UI.vgauge`, `UI.meter(cx, cy, r, v, a0, a1, ticks, redFrom)`,
  `UI.crankPrompt`, `UI.stamp(text, x, y, t)`, `UI.counter`, `UI.Dialog`, `UI.Menu`, `UI.Coach`.
* `Scene.shake(mag)`, `Scene.flash(frames)` — via `self:shake/flash`.

Screen: 400x240, 1-bit, 30 fps. Use `UI.header` at the top and `UI.hints`
at the bottom of every machine so the anthology feels like one family, but
give the play area its own visual identity (layout, patterns, motifs).

## Rules that matter

1. **The crank must model something physical.** Feed `change` into a
   simulation (momentum, tension, gearing, ratchets, detents, torque,
   rates). Never use crank angle as a mere left/right cursor.
2. **No per-frame allocation.** No table literals, closures or string
   building in `update`/`draw` hot paths. Preallocate arrays in `enter`,
   reuse them. Use `U.cached(key, fmt, v)` for HUD numbers and constant
   tables at file scope. The test harness fails a machine that allocates more
   than 2 KB/frame while cranking.
3. **Static art is cached.** Backgrounds or sprites that don't change →
   `Art.cached(...)` once, then `img:draw(x, y)`.
4. **Bounded work.** Cap particle counts, entity counts, loop iterations and
   substeps.
5. **32-bit safety.** Playdate Lua may use 32-bit numbers. Keep counters well
   under 2^31, never `string.format("%d", x)` with a non-integer x (use
   `math.floor`), and don't rely on float precision past ~7 digits (use
   split accumulators for huge quantities, e.g. millions + remainder).
6. **Text.** `font:drawText` / `UI.text` do not interpret markup. Only
   `playdate.graphics.drawText` treats `*` and `_` as bold/italic — avoid it.
   Measure with `UI.width`; never assume glyph widths. The system font is
   about 16px tall; the bold is wider.
7. **JSON-safe serialize.** Only string keys or dense 1..n arrays, numbers,
   strings, booleans. No functions, no nil holes, no mixed tables, no
   non-finite numbers. Store RNG state with `self.rng:state()`.
8. **Deterministic procedure.** All procedural generation draws from
   `self.rng` so the Daily Machine (same seed for everyone) is fair.
9. **Difficulty.** Respect `self.difficulty` (1-3): challenges and the daily
   use 2-3.
10. **Audio.** Give the machine a sonic identity (hums, ticks, bells). Stop
    hums in `exit()` and when finished.
11. **Only use SDK APIs that exist.** The official API list (from Panic's
    docs via playdate-luacats) is at
    `tools/sdk_stub.lua` (not committed; regenerate from github.com/notpeter/playdate-luacats).
    Grep it before using anything not already used by safecracker/core.
    Don't import extra CoreLibs (only `CoreLibs/graphics` is loaded; no sprites, timers, animators, geometry).
    Angles for `drawArc` are degrees with 0 at 12 o'clock, clockwise.
12. Keep each machine file self-contained and commented at the top with a
    short explanation of its crank model.

## Testing

Run from `cranking-it/`:

```
lua5.4 tools/test_machine.lua <id>          # fuzz every mode, serialize round-trip,
                                            # alloc probe, screenshots in shots/<id>/
```

Write your own scripted test too (see `tools/test_safecracker_solve.lua`):
drive the crank/buttons with `H.frame(crankDegrees)`, `H.press("a")`,
`H.hold("left")`, `H.crank(deg, frames)`, `H.shot(name)`, and assert the
tutorial can be completed and that a skilled scripted player can win and
an idle player loses. Look at the screenshots (PNG, 2x) and iterate on the
art until it reads clearly at 1-bit. The mock renders an approximate font,
so leave slack in text layout.

The mock (`tools/mock_playdate.lua`) implements a subset of the SDK. If you
hit a missing function that *is* in the official stub, report it rather than
editing the mock.
