# First build on real hardware: checklist

Everything in this project was built and tested against a headless mock of
the Playdate runtime (`tools/`), because the SDK could not be downloaded in
the build environment. The mock checks every API call against the official
API list and runs every machine, but it cannot answer the questions below.
Work through them on the first Simulator / device build.

## Build

```sh
pdc source CrankingIt.pdx
```

* [ ] `pdc` compiles with no errors or warnings (watch for `<const>` locals,
      integer division and bitwise operators, all standard Lua 5.4).
* [ ] The game boots to the title screen; cranking lifts the portcullis.

## Performance (device, not Simulator)

Enable **Show FPS** in the Simulator's Device menu or use `playdate.drawFPS`.
`lua5.4 tools/perf_estimate.lua` predicts every machine at roughly 1–12 ms of
game Lua per frame, except ONE BILLION YEARS (~21 ms, globe rendered at 15 Hz).

* [ ] ONE BILLION YEARS holds 30 fps while cranking fast (continents drifting)
      and on the red-giant ending.
* [ ] THE LIGHTHOUSE: the beam is drawn with `fillEllipseInRect` start/end
      angles (pie slices). Confirm it renders as a wedge and holds 30 fps in fog.
* [ ] CLOCKMAKER: gear images are cached per tooth phase; confirm no hitch the
      first time a new gear appears.
* [ ] No visible hitch when a results card appears (the save is written then).

## Crank feel (the part the mock cannot judge)

| Machine | Check |
|---|---|
| SAFECRACKER | Can you hear/see each wheel's click and stop on it? Is the gate tolerance fair at 100 numbers? |
| FISHING LINE | Does the flick-cast register naturally? Is the drag scream readable? |
| FILM CAMERA | Is stopping on the red-window number satisfying, not fiddly? |
| MICROFICHE | Does a fast spin coast believably and brake with counter-cranking? |
| NUMBERS STATION | Is the backlash noticeable but not annoying? Is FINE tuning precise enough? |
| ELEVATOR OPERATOR | Does the crank feel like a lever with stops? Is levelling achievable? |
| PROJECTIONIST | Is 2 turns/s sustainable for a whole reel? Is jam sensitivity fair (tuned in simulation only)? |
| THE LIGHTHOUSE | Does the lens feel heavy and late, but controllable? |
| SAILBOAT WINCH | Does grinding in the new jib sheet after a tack feel frantic in HIGH and heavy in LOW? |
| THE WELL | Is the slip-and-catch readable? Can you jiggle to fill without spilling? |
| CLOCKMAKER | Is the bind/stutter felt through the crank? Is winding to the FULL band clear? |
| HAND-CRANKED CIVILIZATION | Is lingering in a sector a comfortable, deliberate motion? |
| ONE BILLION YEARS | Is the slow end slow enough to witness city lights without frustration? |

## Difficulty

Medal thresholds were calibrated against scripted players (see
`tools/calibrate.py`). For each machine, note whether a first-time player
who finished the tutorial gets BRASS within two tries, and adjust
`medals = { standard = { brass, silver, gold } }` in the machine file.

## Sound (the mock is silent)

`tools/test_audio.lua` checks sound mechanically: every machine makes
sound while cranked, volumes stay in range, hums stop on exit.

* [ ] Listen on the **built-in speaker**, not only headphones: impacts (the
      safe's fence, the well's heartbeat, the elevator's floor bell) must be
      audible. Very low sines (< ~200 Hz) are inaudible on the speaker.
* [ ] No stuck notes after leaving a machine via the system menu.

## Saves

* [ ] Quit from the system menu mid-machine; relaunch; the title offers RESUME.
* [ ] Lock the device mid-machine; unlock; progress intact.
* [ ] Progress survives a relaunch (gears, unlocked cabinets, daily streak).
