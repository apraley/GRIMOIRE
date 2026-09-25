-- THE BENCHY CAPTAIN's phrase banks.
--
-- Lines are assembled as  OPENER + BODY + CLOSER  where the body comes from a
-- topic bank and {slots} are filled from shop data. With ~24 openers, ~20
-- closers and 3-12 bodies per topic (many with several slots), the Captain
-- has tens of thousands of distinct lines, chosen deterministically from the
-- shop's state (see services/captain.lua).
--
-- Keep lines free of '*' and '_' only for readability on 400x240; the pixel
-- font renders them fine.

Phrases = {}

Phrases.openers = {
	"Arrr.", "Ahoy!", "Avast!", "Ho there, shipwright.", "Blow me down!", "Heave ho.",
	"Aye.", "Well, well.", "Shiver me extruders!", "Yo ho.", "Listen close.", "Hark!",
	"By Benchy's chimney!", "Belay that.", "Ahoy, matey.", "Hrmm.", "Mark me words.",
	"Ship's log, today:", "Scuttle me hull!", "Batten the hatches.", "Sea's calm today.",
	"Weigh anchor!", "Oi, deckhand.", "Crow's nest reports:",
}

Phrases.moodOpeners = {
	happy = { "Huzzah!", "Yo ho ho!", "Splendid!", "Hoist the colours!", "Now THAT'S a print!" },
	worried = { "Man overboard!", "Blast!", "Barnacles.", "Oh, me timbers.", "Rough seas, matey." },
	stern = { "Attention on deck!", "Listen here.", "Don't make me say it twice.", "Captain's orders:" },
}

Phrases.closers = {
	"Fair winds.", "Now back to work, ye bilge rat.", "Keep yer nozzle clean.",
	"The sea rewards the patient.", "Arrr.", "Mind the brim.", "I'll be on the bow.",
	"Hoist the filament!", "That's the Benchy way.", "Trust the layers.",
	"Don't sink me boat.", "Yo ho ho.", "Steady as she prints.", "Aye, that's all.",
	"Now fetch me a snack.", "Carry on.", "", "", "", "",
}

Phrases.topics = {}
local T = Phrases.topics

T.greet_morning = {
	"Mornin'! Coffee first, then the first layer.",
	"Early tide, eh? The bed's cold and so's me tea.",
	"Sun's up over the build plate.",
}
T.greet_day = {
	"Good day for printing. They all are, mind.",
	"Afternoon! The workshop smells of warm {material}.",
	"Back in the shop, I see.",
}
T.greet_evening = {
	"Evening. Perfect time to start a long print and sleep on it.",
	"Sun's setting. Queue something slow.",
	"Evenin'. The shop hums nicely at dusk.",
}
T.greet_night = {
	"Burning the midnight filament?",
	"Night watch, eh? I'll keep an eye on the nozzle.",
	"Late, matey. Printers don't sleep, but ye should.",
}

T.complete = {
	"{job} came off the plate clean as a whistle.",
	"Another {job} for the fleet! {grams} of {material} well spent.",
	"{job} finished in {duration}. Not a layer out of place.",
	"Look at that {job}. I'd sail it.",
	"That's {prints} prints on this old tub. {job} is a fine addition.",
	"{job} is done. {spoolLeft} left on the {spool} spool.",
	"{job} complete, and the {project} project grows.",
	"Pop {job} off the plate gently. Flex, don't pry.",
}
T.complete_streak = {
	"{streak} clean prints in a row! The sea gods smile.",
	"That's {streak} without a failure. Don't jinx it.",
	"A streak of {streak}! Mark it in the log.",
}
T.complete_after_fail = {
	"{job} made it this time. Persistence beats spaghetti.",
	"Second time lucky with {job}. What changed? Write it down.",
	"{job} redeemed itself. The retry was worth it.",
}
T.cancelled = {
	"{job} scrapped. Sometimes the wise sailor turns back.",
	"Cancelled {job}. No shame in it; no filament wasted further.",
}

T.fail_spaghetti = {
	"Spaghetti off the port bow! {job} let go at layer {layer}.",
	"{job} turned to noodles. Check yer first layer and supports before blaming the filament.",
	"Spaghetti's fine for supper, not for a {material} print.",
	"The nozzle knitted a bird's nest from {job}. Adhesion or supports, likely.",
}
T.fail_adhesion = {
	"{job} lost its grip on the plate. Wash it with soap and water, and try a warmer bed.",
	"The corners lifted on {job}. Fingerprints are greasy devils.",
	"Adhesion, again. I'd run the first layer check on {material} / {maker}.",
	"{job} popped loose at {pct}. A brim is cheap insurance.",
}
T.fail_layershift = {
	"Layer shift! {job} lurched like a ship in a squall. Check yer belts.",
	"{job} stepped sideways at layer {layer}. Loose belt or a nozzle crash.",
	"Shifted layers. Look for a collision, then belt tension.",
}
T.fail_stringing = {
	"Stringing off the port bow. I'd inspect yer temperature before blaming the filament.",
	"Cobwebs on {job}! {material} that strings is often {material} that's thirsty. Dry that spool.",
	"Wisps and strings on {job}. Try the retraction test, or drop the nozzle five degrees.",
	"{job} looks like a haunted ship. Dry the {spool} and tune retraction.",
}
T.fail_underext = {
	"Thin walls on {job}. Under extrusion. Check the extruder gears and yer flow ratio.",
	"{job} came out starved. Partial clog, wet filament, or flow too low.",
	"Gaps in the walls of {job}. The extruder's not keeping up.",
}
T.fail_overext = {
	"Blobby {job}! Too much plastic. A flow calibration will sort it.",
	"{job} is oozing at the seams. Flow ratio's too generous.",
}
T.fail_clog = {
	"Clog in the nozzle! The extruder's clicking like a crab. Time for a cold pull.",
	"{job} stopped extruding at layer {layer}. Clogs happen. Clean or swap the nozzle.",
	"Nothing coming out of the nozzle. Heat it, push, pull, pray.",
}
T.fail_support = {
	"Supports gave way on {job}. Check support interface and clearance.",
	"The scaffolding fell on {job}. Tree supports hold better on tall bits.",
}
T.fail_dimension = {
	"{job} came out the wrong size. Measure a cube and run the dimensional check.",
	"Bits don't fit on {job}. Tolerance test, then XY compensation.",
}
T.fail_unknown = {
	"{job} failed, and even I can't say why. Log what ye saw; patterns show up over time.",
	"A mystery failure on {job}. Keep notes. The sea gives up her secrets slowly.",
}
T.fail_generic = {
	"That's {failures} {cause} failures on {material} / {maker} lately.",
}

T.maint_due = {
	"{task} is due {when}. A clean ship is a fast ship.",
	"Yer {task} is overdue. Barnacles build up, matey.",
	"The log says {task}: {when}. Do it before the next long print.",
	"Time for {task}. The printer won't ask, so I will.",
}
T.maint_soon = {
	"{task} coming due soon: {when}.",
	"Heads up: {task} in {when}.",
	"Plan for {task} this week. {when}.",
}
T.maint_done = {
	"{task} done. The old girl thanks ye.",
	"Logged {task}. Shipshape and Bristol fashion.",
}

T.low_spool = {
	"Yer {spool} is running low: {grams} left.",
	"Only {grams} of {spool} left. Stock up before the next voyage.",
	"{spool} is nearly bare. {grams} won't cover a {next}.",
	"The {spool} spool is getting light. {days}",
}
T.empty_spool = {
	"{spool} is empty. Into the scrap bin, and restock.",
	"Not a gram left on the {spool}. Pour one out.",
}
T.damp_spool = {
	"{spool} has been sitting open. It'll be thirsty by now. Dry it before printing.",
	"Yer {spool} is {dryness}. Wet filament pops and strings.",
	"Dry the {spool}. {material} drinks the sea air like a sailor drinks grog.",
}

T.suggest_calib = {
	"{count} {cause} failures on {material} / {maker} lately. I'd run the {procedure}.",
	"Seeing {cause} with {material} / {maker}. The {procedure} will tell us more.",
	"Before ye blame the {maker} spool, try the {procedure}.",
}
T.suggest_maint = {
	"{cause} failures lately. When did ye last do {task}?",
	"{cause} again. I'd do {task} before the next print.",
}
T.no_profile = {
	"No calibration for {material} / {maker} yet. The temp tower is a good start.",
	"Printing {material} without a profile is sailing without a chart.",
}

T.idle = {
	"The printer's been idle {days} days. A ship in harbour is safe, but that's not what ships are for.",
	"{days} days since the last print. The nozzle misses ye.",
}
T.queue_status = {
	"{n} jobs in the queue. Next up: {next}, about {duration}.",
	"Queue holds {n}, about {hours} of printing and {grams} of plastic.",
	"Next on the plate: {next}. Using {spool}.",
}
T.queue_empty = {
	"Nothing queued! Add a job, or print me another Benchy.",
	"An empty queue. Time to dream up a project.",
}
T.shortfall = {
	"{job} needs {need} but {spool} has only {have}. Expect a runout.",
}
T.printing = {
	"{job} is at {pct}, layer {layer} of {layers}. Steady as she goes.",
	"{job}: {remaining} to go. I'll keep watch.",
	"The nozzle's dancing on {job}. {pct} done.",
}
T.stats = {
	"{prints} prints logged, {meters} metres of filament. Longer than me boat, many times over.",
	"Success rate {rate}. {failures} failures taught us plenty.",
	"This shop has printed {kg} of plastic. That's a lot of Benchies.",
}
T.combo = {
	"{material} / {maker}: {prints} prints, {failures} failures. Most trouble: {cause}. Best nozzle: {temp}.",
}
T.calib_saved = {
	"New {procedure} results for {material} / {maker}. Future jobs will use them.",
	"Profile updated. {jobs} queued jobs now use the new settings.",
	"Calibrated! A charted sea is a safe sea.",
}
T.retry = {
	"Back on the horse, eh? {job} goes back in the queue with the latest profile.",
	"Retrying {job}. Change one thing at a time, matey.",
}

T.wisdom = {
	"Never trust a first layer ye didn't watch.",
	"The brim is the anchor of the print.",
	"A dry spool is a happy spool.",
	"Measure twice, slice once.",
	"Every Benchy is a lesson.",
	"Supports are like crew: ye only notice them when they fail.",
	"PETG loves the bed a little too much. Glue stick makes a fine release.",
	"TPU likes it slow. So do I.",
	"Don't fight the warp. Build an enclosure.",
	"Temperature first, retraction second, blame third.",
	"A clean nozzle tells no tales.",
	"If it looks like spaghetti, it's already too late.",
	"Save yer failures. They're the best teachers.",
	"Layer lines are the rings of a tree. Every one tells a story.",
	"Silk filament hides nothing but sins.",
	"Grease the Z screw, not yer ego.",
	"A 0.4 nozzle holds back the whole ocean.",
	"ASA hates a draft. Close the door.",
	"Print the calibration cube before the cathedral.",
	"Orient for strength: layers are weakest when pulled apart.",
	"Bridges want cold air and fast feet.",
	"When in doubt, slow the outer wall.",
	"Wash the plate. No, really. Wash it.",
	"Ironing is for shirts and top surfaces.",
	"The best support is the one ye designed out.",
	"A spool on the floor gathers dust, and dust clogs nozzles.",
	"Chamfer the bottom edge; elephants have feet enough.",
	"Holes print small. Add a little clearance.",
	"Three walls beat more infill, most days.",
	"The slicer preview is free. Scrub through it.",
	"Label yer spools. Future ye will be grateful.",
	"Never leave a first print unattended. Or a lasagna.",
	"Hot nozzle, cold beer, patient sailor.",
	"A print that fails at layer one costs a minute. At layer five hundred, a day.",
	"Log every failure. Patterns hide in the logbook.",
	"Z seam goes in the corner, where the sea can't see it.",
	"Humidity is the kraken of filament.",
	"Benchy was designed to torture printers. I take it personally.",
	"The first layer is the keel. Build it true.",
	"Pressure advance is sorcery. Calibrate the sorcery.",
}

-- Captain's tutorials, one per feature (multiple pages each).
Phrases.explain = {
	home = {
		"This be the WORKSHOP. The printer on the left shows what it's doing: idle, heating, printing, paused, error or done.",
		"When idle, turn the crank to walk between stations. When printing, the crank scrubs through the layers of the part.",
		"Press A to enter a station. The banner up top warns of maintenance due and spools running dry.",
	},
	watch = {
		"PRINT WATCH shows the current print in detail: progress, layers, time, temperatures and filament used so far.",
		"The part grows layer by layer in the little window. Crank to scrub back through its history.",
		"Press A for printer controls: pause, resume, cancel, clear the plate or swap a spool after a runout.",
	},
	queue = {
		"The PRINT QUEUE holds every job, from idea to finished.",
		"Press A on a job for actions: print, edit, duplicate, retry, mark done or failed, archive.",
		"Choose MOVE and turn the crank to slide the job up or down the line. Left and right change the filter.",
		"New jobs copy the recommended calibration profile for their spool. Keeps the settings honest.",
	},
	rolodex = {
		"The FILAMENT ROLODEX keeps a card for every spool. Crank to flip through them.",
		"Each card tracks grams left, cost per gram, dryness, location, favourite temps and how well it prints.",
		"Left and right filter by material. B then UP cycles the sort. Low spools get a warning flag.",
		"Every finished print eats filament from its spool automatically. Weigh-ins fix any drift.",
	},
	calibrate = {
		"The CALIBRATION WIZARD walks ye through test prints. I can't calibrate the printer for ye, but I can keep score.",
		"Turn the crank to dial in what ye measured or saw. Results go into a profile for printer, material and maker.",
		"Recommended profiles feed straight into new queue jobs and spool favourites.",
	},
	maint = {
		"The MAINTENANCE LOG tracks chores by print hours and by calendar days, whichever comes first.",
		"Every finished print adds hours to the odometer. Tasks coming due appear on the workshop banner.",
		"Press A on a task to log it done, change its interval or read its history.",
	},
	captain = {
		"That's me! Captain of the good ship Benchy. I read yer logbook and speak me mind.",
		"I remember failures, finished prints, low spools and chores, and I'll tell ye what I'd do next.",
		"No magic here, mind: just rules, a deck of phrases and a keen eye.",
	},
	stats = {
		"The STATS office crunches yer history: success rates per material and maker, common failure causes and project totals.",
		"Use it to spot patterns, like a spool that always strings or a project eating all yer white.",
	},
	settings = {
		"SETTINGS picks yer printer and how PRINT SHOP talks to it: the DEMO sim, a LOCAL BRIDGE, or BAMBU via the bridge.",
		"Ye can also change the demo speed, low-spool warning, theme, and reset the shop.",
	},
}

Phrases.procedureNames = {
	bedlevel = "bed leveling checklist",
	flow = "flow calibration",
	temptower = "temperature tower",
	retraction = "retraction test",
	dimension = "dimensional check",
	firstlayer = "first layer check",
	tolerance = "tolerance test",
}
