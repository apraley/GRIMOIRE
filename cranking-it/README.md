# CRANKING IT

*An anthology of thirteen crank-powered machines in a strange museum by the sea.*

A game for [Playdate](https://play.date), written in Lua against Panic's
official Playdate SDK: 400×240, 1-bit, 30 fps.

You climb out of the sea onto a rock called Ninefold and find the Museum of
Hand-Turned Things. Its Keeper is old and the machines need turning. Every
machine is a different **physical metaphor for the crank**:

| No. | Machine | The crank is… |
|---|---|---|
| I | SAFECRACKER | the combination dial, driving a simulated wheel pack |
| II | FISHING LINE | the reel, against a fish that pulls back |
| III | FILM CAMERA | the film-advance knob; wind exactly one frame |
| IV | MICROFICHE | an inertial, geared spool through an enormous archive |
| V | NUMBERS STATION | a drifting analog tuning capacitor |
| VI | ELEVATOR OPERATOR | the car-switch lever: an angle, not a spin |
| VII | PROJECTIONIST | the projector drive; keep 16 frames a second |
| VIII | THE LIGHTHOUSE | a colossal lens floating on mercury |
| IX | SAILBOAT WINCH | a two-speed sheet winch under load |
| X | THE WELL | a windlass the bucket's weight wants to spin |
| XI | CLOCKMAKER | turning the gear train you built, winding the spring |
| XII | HAND-CRANKED CIVILIZATION | the wheel of history |
| XIII | ONE BILLION YEARS | geological time, on a logarithmic scale |

The design of each machine is in [docs/DESIGN.md](docs/DESIGN.md). What to verify on the
first real-hardware build is in [docs/PLAYTEST.md](docs/PLAYTEST.md).

## The museum

* **The gallery**: a long hall with a conveyor floor that you crank along (or
  walk with the d-pad). Each machine is a cabinet; covered cabinets cost gears.
* **Gears** are earned from tutorials, medals (brass / silver / gold per mode),
  achievements, challenges and the daily machine. They buy machines,
  challenge permits, exhibit restorations, visual themes and the Keeper's
  stories.
* **The Keeper's desk**: stories (lore), lamps & wallpaper (themes), the
  museum ledger (statistics) and settings.
* **The Exhibit Hall**: a carousel of display cases restored with gears once
  you have mastered the matching machine.
* **The Daily Machine**: one machine per day with a date-derived seed,
  difficulty, modifier and goal, identical for every player. Streaks pay
  extra gears.

Every machine has a **tutorial**, a **standard** mode, an **endless** mode
where it makes sense, achievements, records and **challenges** that combine
difficulty with shared modifiers (RUSTY CRANK, SEA FOG, HASTE).

## Building

With the Playdate SDK installed (`PLAYDATE_SDK_PATH` set):

```sh
pdc source CrankingIt.pdx
# then open CrankingIt.pdx in the Playdate Simulator or sideload it
```

There are no image, font or sound assets: all art is drawn procedurally with
the SDK's drawing API (with static art cached into images at first use), and
all sound is synthesized with `playdate.sound.synth`.

## Project layout

```
source/
  main.lua              entry point: update loop, system callbacks, pause card
  core/                 shared systems
    util.lua            math, deterministic RNG (32/64-bit safe), class helper
    crank.lua           crank tracker, detents, flywheel, flick, jiggle
    input.lua           button polling, auto-repeat
    audio.lua           synth voice pool, hums, SFX library, music box
    save.lua            dual-slot checksummed datastore saves, stats, gears
    art.lua             1-bit pattern library, gears, frames, cached images
    ui.lua              header, hints, gauges, meters, dialog, menu, tutorial coach
    scene.lua           scene manager, transitions, shake, flash
    machine.lua         Machine base class, registry, medals/gears, PlayScene
    achievements.lua    per-machine and museum-wide achievements
    challenge.lua       modifiers, challenges, the daily machine
    themes.lua          museum visual themes
    lore.lua            the Keeper's stories and the exhibit catalogue
  scenes/               title, hub (gallery), lobby (placard), results,
                        exhibits, curator
  machines/             one file per machine
docs/
  DESIGN.md             per-machine designs and the distinctness table
  MACHINE_GUIDE.md      the contract every machine implements
tools/                  headless test harness (not shipped)
```

### Machine contract

Every machine implements `init() enter() exit() update(dt) draw()
cranked(change, acceleratedChange) buttonDown(button) serialize()
deserialize()`; see [docs/MACHINE_GUIDE.md](docs/MACHINE_GUIDE.md).
`serialize()` powers suspend/resume: quitting or sleeping mid-run saves the
run and the title screen offers to resume it.

### Saves

`playdate.datastore` writes alternate between two slots. Each slot stores a
sequence number, an FNV-1a checksum and the JSON payload; loading picks the
newest slot whose checksum verifies, so an interrupted write can never
corrupt progress. Writes are debounced and flushed on results, purchases,
pause, lock, sleep and quit.

## Testing without a device

`tools/` contains a headless mock of the Playdate Lua runtime with a small
1-bit rasterizer, so the whole game can be booted, driven with scripted
crank/button input and screenshotted with desktop Lua 5.4.

```sh
lua5.4 tools/test_wrapper.lua              # museum flow, saves, suspend/resume
lua5.4 tools/test_machine.lua safecracker  # any machine id: fuzz all modes,
                                           # serialize round-trip, allocation probe
lua5.4 tools/test_safecracker_solve.lua    # machine-specific scripted play
python3 tools/check_api.py                 # every SDK call exists in the official API
lua5.4 tools/perf_estimate.lua             # per-frame Lua cost of each machine, with a
                                           # rough on-device estimate (rasterization excluded)
sh tools/run_all.sh                        # everything above, for all machines
```

`check_api.py` needs the official API list as `tools/sdk_stub.lua`
(`library/stub.lua` from
[playdate-luacats](https://github.com/notpeter/playdate-luacats), generated
from *Inside Playdate*). Screenshots land in `shots/` (requires Pillow).
The mock also fails a machine that allocates more than 2 KB per frame while
being cranked.
