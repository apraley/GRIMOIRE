# CRANKING IT — machine designs

Premise: every machine finds a different *physical metaphor* for the crank.
The table below is the contract that keeps them mechanically distinct. When
adding features, preserve each machine's crank model and its difference from
its neighbours.

| # | Machine | The crank is… | Physical model | What makes it unlike the others |
|---|---|---|---|---|
| 1 | SAFECRACKER | the combination dial | wheel pack with pin slack; gates; fence; bolt | absolute position + direction history matter; precision stops |
| 2 | FISHING LINE | the reel handle | line tension = stretch between rod tip and a live fish; drag slip; rod flex | an opponent pulls back; you modulate tension, not position |
| 3 | FILM CAMERA | the film-advance knob | ratchet film transport with frame spacing read through a red window; shutter cocking | discrete, precise *amount* of rotation between actions |
| 4 | MICROFICHE | the reader's spool | inertial spool with gearing: slow = page by page, fast = years fly by with blur | navigation through an enormous space; momentum + braking |
| 5 | NUMBERS STATION | the tuning capacitor | analog tuning with backlash, drift, vernier (fine) gearing | tiny, continuous corrections against drift; signal peaks |
| 6 | ELEVATOR OPERATOR | the car-switch lever | crank angle from rest = motor power/direction; car mass, inertia, brake distance | crank as a *lever position* (throttle), not a spinner |
| 7 | PROJECTIONIST | the projector's drive | direct drive film transport at 2 turns/sec; frame rate from crank speed; loop size | sustaining a rhythm / constant speed; jams |
| 8 | THE LIGHTHOUSE | pushing the heavy lens carriage | huge inertia flywheel on a mercury bath, torque impulses; flash timing | managing momentum you can barely change; delayed response |
| 9 | SAILBOAT WINCH | the winch handle | two-speed winch hauling/easing a sheet under load; sail aerodynamics, heel | load-dependent mechanical advantage; furious grinding at tacks |
| 10 | THE WELL | the windlass | gravity-driven rope drum; you restrain the descent, grip can slip; haul heavy water | the load drives *you*; braking a fall; jiggling to fill |
| 11 | CLOCKMAKER | turning the train / winding the mainspring | gear-train ratios computed from tooth counts; mainspring torque with click | the crank tests a mechanism you built; ratio reasoning |
| 12 | HAND-CRANKED CIVILIZATION | the wheel of history | each turn = one generation whose length depends on era; pushing fast breeds unrest | speed is a *political* variable; history has friction |
| 13 | ONE BILLION YEARS | geological time | crank speed maps logarithmically to time scale (years → megayears) | the rate itself is the instrument; contemplative |

---

## 2. FISHING LINE

* Side view: a jetty or rowing boat at left, the water surface, depth below.
  Fish visible as a dim dithered silhouette when near the surface.
* **Cast**: hold A to open the bail, flick the crank backward-then-forward
  (use `Crank.Flick` or crank velocity) — cast distance from flick speed.
  Release/close bail on A release. Lure sinks.
* **Attract**: small twitches of the crank jig the lure. Fish approach,
  nibble (bobber/rod tip quivers), then bite. Strike (sharp crank burst) in
  the bite window to set the hook; late or early spooks the fish.
* **Fight**: line length `L` (shortens when cranking forward, via spool
  radius & gearing). Distance rod-tip→fish `D`. Stretch `D - L` drives
  tension through a spring (line stiffness) plus rod flex: rod angle (d-pad
  up/down raises/lowers the rod; left/right leans) changes how much of a
  sudden surge the rod absorbs. **Drag** (A cycles LOW/MED/HIGH or hold A to
  tighten, B to loosen): when tension exceeds the drag setting, the spool
  slips and line pays out (drag scream sound, spool spins, handle can't gain).
  Tension > line strength (for a short time) → SNAP. Slack (tension ≈ 0) for
  too long → the fish throws the hook.
* **Fish species** with distinct behaviour state machines (at least 5):
  perch (quick darts, light), pike (long powerful runs then rests),
  eel (rolls/twists: rapid tension oscillation), catfish (dives and sulks on
  the bottom: dead weight, must lift with rod), swordfish/sea-trout (jumps:
  when airborne you must give slack or the hook tears), plus a rare
  legendary. Each has weight, stamina, strength; stamina drains while
  pulling against tension. Landing: bring the fish to the net zone near the
  boat when stamina is low.
* Standard: a timed trip (e.g., 4 in-game hours = ~4 minutes) — score is
  total weight landed (+ species variety bonus). Endless: fish until 3 lines
  snap or lost. Difficulty raises fish strength and lowers line strength.
* HUD: tension gauge with snap zone, drag setting, line out (metres), a
  species card when hooked.

## 3. FILM CAMERA

* A viewfinder view of a wide panoramic scene (harbour town / pier / cliff
  with lighthouse) with moving subjects (ferry, gulls, cyclist, dog, a
  couple, lighthouse beam at dusk, a strange figure at one frame).
  D-pad pans the viewfinder (left/right, and a little up/down).
* **Advance**: crank clockwise winds the film. The back of the camera has a
  red window showing the backing paper numbers/arrows scrolling by; a frame
  is correctly advanced when the next number is centred (e.g., 1.25 turns of
  the knob per frame with a light ratchet click every ~15°). Counter-clockwise
  does nothing (ratchet) except in rewind mode. There is **no** double-
  exposure interlock: shooting without advancing → full double exposure;
  under-advancing → the new frame overlaps part of the previous one;
  over-advancing wastes film (roll has fixed length: e.g., 12 frames on
  standard).
* **Exposure**: B + d-pad (or a mode toggle) sets aperture (f/2.8–f/22) and
  shutter (1/500–1s). A light meter needle shows over/under exposure for the
  current framing; light changes (clouds, dusk). Slow shutters blur moving
  subjects. A = release shutter.
* **Brief**: a client's shot list for the roll (e.g., "the ferry, centred",
  "a gull in flight", "the lighthouse lit at dusk", "two people on the
  pier"), generated per roll.
* **Develop**: at the end of the roll, rewind (crank counter-clockwise many
  turns — a different physical action) then the contact sheet: each frame
  rendered as a thumbnail (render the scene state captured at exposure into
  a small image with exposure darkness/brightness via dithering, motion
  blur as smear, double exposures as two overlaid frames offset by the
  under-advance). Score each frame vs. the brief: subject in frame and
  centred, exposure within ±1 stop, sharpness. Grease-pencil circles on the
  good ones.
* Standard: one roll with a brief, scored. Endless: successive rolls while
  light fades; ends on a roll scoring below a threshold.

## 4. MICROFICHE

* The archive: several reels (e.g., "Ninefold Gazette 1880–1899",
  "Harbour Registry", "Parish Records", "Lighthouse Logs") each hundreds of
  frames. Everything is generated deterministically from seed + frame index
  (don't store pages; generate and cache the few on screen).
* **Crank**: drives the film spool through a gear train with inertia.
  Slow cranking moves frame by frame (a detent click per frame); fast
  cranking spins the spool with momentum, pages blur into streaks, the
  date counter races; the spool coasts after you stop — braking by
  counter-cranking. A toggles high/low gear (coarse / fine). The date/page
  counter at the top tells you where you are.
* D-pad pans the magnified page (the reader shows only part of a page); B
  zooms between full-frame (layout, headlines legible) and magnified (small
  text legible).
* **Cases**: procedurally generated mysteries needing 3–4 records, each
  giving the key to the next: e.g., "Who kept the Grey Rock light the night
  the schooner *Aster* was lost?" → find the wreck report (only the month is
  given, so browse the Gazette) → it names the date → the Lighthouse Log for
  that date names the keeper on watch by initials → the Parish register
  resolves the initials to a full name. Case generation must guarantee a
  unique solution and plant red herrings (similar ships, two keepers with
  the same initials in different years).
* Evidence: press A on the relevant line (a cursor highlights lines when
  magnified) to clip it to the case file. When the file has the chain, the
  accusation screen offers 4 names; correct → next case.
* Standard: 3 cases against a clock; score from time and wrong accusations.
  Endless: cases until 3 wrong accusations.

## 5. NUMBERS STATION

* A valve receiver: a big tuning scale (MHz) with a sliding needle, a
  signal-strength meter, a noisy oscilloscope trace, and a notepad.
* **Crank**: turns the tuning capacitor through a reduction with backlash
  (a few degrees of dead play when reversing), and a vernier: A toggles
  FINE (10:1). Stations drift slowly (thermal drift), so you keep correcting.
  Signal = gaussian around each station's current frequency; audio is noise
  (`Audio.NOISE` hum) whose volume falls as signal rises, with a tone whose
  pitch is the beat frequency (detune) — true to real receivers.
* Stations broadcast looping transmissions: a call-sign/tune, then groups of
  five digits read out (beeps / shown as digits appearing on the "voice"
  display). Low signal corrupts digits (shown as `?`). The notepad records
  the best-quality copy of each digit across repeats, so re-tuning precisely
  fills gaps.
* **Ciphers** (procedural, difficulty-scaled): A1Z26 pairs; additive
  one-time pad with a key read from a *second* station (subtract mod 10);
  a date-derived shift; a small codebook. Decoding UI: select a group,
  apply key; the plaintext appears letter by letter only when correct.
* Chain: a decoded message gives the frequency (or an instruction) for the
  next station. The final message is a word or place; pick it from a list
  to complete the "night".
* Standard: one night = 3 messages before dawn (clock). Endless: nights
  keep coming, stations get weaker/drift faster.

## 6. ELEVATOR OPERATOR

* Cutaway of a 9–12 floor building (brass cage, cables, counterweight),
  scrolling with the car; a semicircular floor-indicator dial above the
  doors.
* **Crank = car switch lever.** The crank's *angle from its rest position*
  (captured at run start: pointing forward/up = centre) is the lever: rotate
  forward (clockwise) up to ~90° = UP power, backward = DOWN power, near
  centre (±12°) = neutral with brake. Accumulate `change` into a lever
  angle clamped to ±100°, so it behaves like a physical lever with stops.
  Motor torque ∝ lever; the car has mass (passengers add load), inertia,
  counterweight imbalance, cable stretch (slight bounce), and brake
  deceleration when neutral. Skill = anticipating stops, feathering to
  level. Show the lever visually.
* Stop level with the floor (±2px = perfect, ±6 = acceptable, worse =
  passengers trip). Hard decelerations/accelerations (jerk) upset
  passengers ("don't slam them"). A opens/closes the scissor gate (only
  when stopped); passengers board/alight only when the gate is open.
* Passengers: appear on floors with destinations (speech bubble), patience
  meters, weight; the car has capacity. Types: businessman (impatient),
  grandmother (hates jerks), bellhop with trolley (heavy), child (presses
  wrong floors?), a ghost on the 13th floor at night.
* Standard: a shift (e.g., 3 minutes) — score from deliveries, tips for
  smoothness and levelling, penalties for anger. Endless: until 3 passengers
  storm out.

## 7. PROJECTIONIST

* A cinema: the screen (big, top), the audience silhouettes (bottom), and a
  side inset of the projector with feed reel, take-up reel, the film loop
  above the gate and the frame counter.
* **Crank = hand-cranked projector drive**: 1 turn = 8 frames, so 2 turns/s
  = 16 fps (silent standard). The film's intended speed is shown (16, 18,
  20, 24 fps; some reels change speed mid-reel — slow for romance, fast for
  chase). The on-screen animation advances by crank-driven frames, so the
  player literally projects the film: too slow → flicker (black frames
  between), sluggish; too fast → comic speed-up.
* **Loop**: the Latham loop shrinks/grows with speed *changes* (jerky
  cranking); if it vanishes the film jams → the frame freezes and starts to
  burn (a white hole spreading) unless you stop cranking immediately; then
  repair: B opens the gate, the d-pad re-threads (a short sequence shown on
  the inset), A closes.
* **Reel changes**: two projectors. Cue marks (a dot in the top-right corner
  of the screen image) appear 8 s and 1 s before the reel ends. At the first
  cue, press B to strike projector 2's arc; at the second, press A to change
  over. Timing error shows as a black flash / repeated frames and annoys
  the audience. The crank then drives the new projector (which must be
  brought up to speed).
* Audience meter: silhouettes react (heads slump, boo text, hats thrown,
  people leave). Films are procedurally animated vignettes (train arriving,
  a chase over rooftops, the sea, a romance on a pier, a strange ending
  where the audience appears on screen).
* Standard: one programme (3 reels). Endless: programmes continue until the
  house empties.

## 8. THE LIGHTHOUSE

* Top-down chart of the coast at night: headland, the lighthouse, rocks
  (black blobs with surf), a harbour channel between buoys. The beam is a
  rotating wedge of light; dithered sea; fog as white dither patches
  drifting; storms add rain streaks and waves.
* **Crank = pushing the lens carriage**: the Fresnel lens floats on
  mercury — enormous inertia, almost no friction. Crank rotation applies
  torque impulses (via `Crank.Flywheel` with high inertia & low coupling);
  counter-cranking brakes. The lens has panels, so it flashes N times per
  revolution. Tonight's characteristic (e.g. "Fl(2) 10s") specifies a period;
  keep the rotation speed inside the tolerance band. A clockwork weight
  alternative is **not** used — the challenge is momentum.
* Ships approach from the sea edge along routes. Each ship "reads" the
  flashes it sees: it measures intervals between flashes (it only sees the
  flash when the beam sweeps across it and fog doesn't block it). Correct
  characteristic → confidence rises → it identifies the harbour and steers
  for the channel. Wrong or irregular → it wanders (steers toward a
  plausible but wrong landmark — the rocks). A ship lit by the beam while
  near rocks also sees the danger and turns away (a tactical use of the
  beam's position). B = fog horn (limited uses; ships nearby turn away from
  the headland).
* Standard: one night (e.g., 3–4 minutes, weather worsens); score = ships
  safely in − wrecks. Endless: until 3 wrecks.

## 9. SAILBOAT WINCH  (flagship — must feel like a sailing winch)

* Top-down view of the boat (hull polygon, mast, boom + mainsail, jib) on
  water with wind ripples; gust patches (darker ripple fields) sweep across.
  A wind arrow and a heel inclinometer. Race course with marks (upwind/
  downwind legs) and a rival boat.
* **Wind**: direction with shifts, speed with gusts. Apparent wind from
  boat velocity. **Sails**: each sail angle is limited by its sheet length;
  the wind pushes it out to that limit (or it luffs if the sheet is too
  loose for the apparent wind). Angle of attack → lift/drag curve: optimal
  ~15–25°, too small = luffing (sail drawn flapping, tell-tales flutter, no
  drive), too big = stall (drag, heel, slow). Driving force → boat speed
  (with hull drag); side force → heel. Too much heel → the boat rounds up /
  slows; extreme → knockdown.
* **Winch**: two-speed. **A** toggles gear: HIGH (fast, 1 turn = lots of
  line, little power) / LOW (slow, powerful). The sheet **load** (from the
  sail force) resists: if load exceeds what the gear can pull, the drum
  stalls — the handle turns with no effect and makes a straining sound. So
  in light load (sail flogging during a tack) you grind in HIGH gear
  furiously; as the sail fills and load climbs you must switch to LOW to
  finish trimming. **B** selects the active line (JIB-P / JIB-S / MAIN).
  Crank **clockwise hauls** (shortens the sheet); **counter-clockwise eases**
  (lets line out under control — load pays it out).
* **Tacking**: d-pad left/right steers (tiller). Turning through the wind:
  the jib flogs, the old sheet must be **released** (B to select it, hold B
  to cast off — it runs free with a whirr) and the new jib sheet ground in
  fast before the boat loses speed. This is the "furious grinding" moment.
  **Gybe**: bearing away through downwind — the boom slams across; if the
  mainsheet is eased out, it's a crash gybe (damage/penalty); haul the main
  in first.
* HUD: line selector with sheet lengths, gear indicator, load gauge (red
  = stall zone for the current gear), speed (knots), heel, tell-tales.
* Standard: a race around 3–4 marks against a rival; score from finish time
  and position. Endless: keep sailing a patrol through weather while
  collecting checkpoint buoys; ends on knockdown or time.

## 10. THE WELL

* Side cross-section of a well shaft going down, far down: stone, then rock,
  then strange carved stone, roots, bones, eyes. At top: the windlass and
  you. Light falls off with depth (dither to black; only the bucket's
  immediate area is visible).
* **Crank = windlass handle.** The bucket's weight (and water, and the
  rope's own weight) creates torque that wants to unwind the drum. When you
  hold still, your grip holds it — until the torque exceeds grip, then the
  handle slips and the drum free-spins, bucket plummeting (you must grab by
  cranking against it hard or pressing A for the pawl/brake, which wears).
  Lowering = letting it unwind under control (counter-clockwise), with
  momentum; slamming into the water surface splashes and may crack the
  bucket. At the water: the bucket floats; **jiggle** the rope (small
  alternating crank motions, `Crank.Jiggle`) to tip and fill it. Hauling up
  full is heavy; jerky hauling spills water (slosh = acceleration).
* Depth varies per well/day; the water surface is unseen — you hear the
  splash (sound delay proportional to depth) and see the rope go slack.
* **Things live down there**: tugs on the rope (something grabs; hold
  steady or lose the bucket), fish in the bucket, coins, a ring, a note,
  and as nights progress: scratching, whispers, the bucket coming up with
  things that shouldn't be (a child's shoe, a photograph of you, warm
  water), eyes in the dark that follow the lantern, the well getting deeper
  every night, text scratched on the bucket from below. It must become
  genuinely unsettling but stay understated.
* Standard: 7 nights, a water quota each night (narrative beats between
  nights). Endless: descend as deep as you dare for a depth record; it gets
  stranger.

## 11. CLOCKMAKER

* A clock movement on a workbench: the plate with arbor positions (pivot
  holes), a tray of gears (wheels with tooth counts, pinions), the
  mainspring barrel (power), the escapement, the hands.
* **Assembly puzzles**: place gears on arbors (d-pad selects arbor / gear,
  A places/removes). Gears mesh when centre distance ≈ r1 + r2 (radius ∝
  tooth count; same module). Compound arbors (wheel + pinion). Goal ratio:
  e.g., minute arbor must turn 12× the hour arbor; the escape wheel must
  turn at the right rate. Procedurally generate arbor layouts + tooth-count
  goals that have a solution (generate the solution first, then scatter
  distractor gears).
* **Crank = turning the train by hand** to test: turning the barrel/crank
  shows every gear rotating at its computed ratio, hands moving, a mesh
  that binds (wrong spacing) jams with a clunk. **Diagnosis**: clocks
  arrive "running fast/slow/stopped/stuttering"; crank slowly and watch —
  a broken tooth causes a periodic stutter on one gear; a wrong gear shows
  hands at the wrong ratio. Replace the culprit.
* **Winding**: finish by winding the mainspring (crank with click-spring
  ticks, the torque rises; overwinding past the limit breaks the spring —
  stop when the resistance peaks). Then the clock runs: the escapement ticks
  and the hands move in real time for a moment of satisfaction.
* Standard: a day's work (3–4 clocks: assembly and diagnosis mixed), score
  from time, accuracy, and no broken springs. Endless: clocks keep coming.

## 12. HAND-CRANKED CIVILIZATION

* A 1-bit map of a small continent (tiles/regions with terrain: coast,
  plains, forest, hills, mountains, rivers), settlements as dots that grow
  into towns and cities with walls, roads between them, borders (dotted),
  wars (crossed swords), plagues (skull), famine, ships exploring. A
  chronicle ticker at the bottom.
* **Crank = the wheel of history.** One full turn = one generation, whose
  length in years depends on the era (Neolithic ~200 years per turn, medieval
  ~30, industrial ~10, modern ~5). The simulation advances in sub-steps as
  the crank turns (bounded per frame). **Speed matters**: cranking fast
  builds "unrest/strain" (history rushed: revolutions, collapse risk);
  slow, steady cranking lets culture and stability accumulate. Cranking
  backward does not rewind time — it applies "friction" (conservatism:
  stability up, progress down).
* Simulate per region: population, food (climate + farming tech), technology
  (several tracks: agriculture, metallurgy, navigation, medicine, printing,
  industry), war (between polities, based on borders, pressure, government),
  culture (monuments, religions, art), disease (plague events, medicine
  reduces), government (tribe → chiefdom → kingdom → empire → republic /
  theocracy / collapse), climate (long cycles; little ice age; warming if
  industry), exploration (ships discover offshore islands, new lands).
* **Interventions**: occasionally an event pauses the wheel (the crank
  locks with a ratchet) and asks the player to choose (2–3 options with
  trade-offs), e.g., "The river floods: [build levees] [move the capital]
  [pray]". Limited "hand of god" nudges (spend influence).
* A civilization can survive thousands of years; it can also collapse
  (dark age) and recover. Score = years survived + peak population/culture.
  Standard: run until collapse or year 5000 (mark the milestones). Endless:
  successive civilizations rising from each other's ruins.

## 13. ONE BILLION YEARS

* A planet: equirectangular map (or a rotating globe drawn with dithered
  shading) of a height field — oceans, continents, mountains, ice caps; a
  sun on the side whose size/brightness changes near the end.
* **Crank speed = time scale, logarithmic**: very slow = years per degree
  (weather, seasons, tiny changes), medium = thousands, fast = millions.
  Show the scale ("1 degree = 12,000 years") and the date ("2.314 billion
  years"). Use split accumulators (billions + remainder) for precision.
  Backwards crank = pause/slow drift (time does not reverse).
* Processes: plate tectonics (plates as Voronoi-like regions with
  velocities; collisions raise mountains, rifts open oceans; continents
  drift visibly at fast speeds), erosion (mountains wear down), oceans (sea
  level), climate (temperature from sun + CO2 + ice albedo; snowball
  earths; hothouse), life (from first cells → oxygen → complex life →
  land → forests → animals → intelligence), evolution (diversity index,
  named clades generated procedurally), extinctions (asteroids, volcanic
  traps, ice ages) with recovery, civilization (appears only in a narrow
  window near the end and lasts a blink at fast speeds: you must slow down
  to see the city lights on the night side), star changes (the sun
  brightens, oceans boil ~ late, red giant at the end).
* Contemplative: minimal UI, sparse poetic log lines ("The first coast.",
  "Something is breathing out oxygen.", "They have noticed the sky."),
  ambient drone audio tied to time scale. Milestones to witness (at a slow
  enough rate) give achievements.
* Standard: run from barren rock to the red giant; score = milestones
  witnessed (weighted by how rare/narrow). Endless: after the end, a new
  planet coalesces from the debris; continue.
