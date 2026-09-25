-- UI workflow tests: builder, browser, gear, slate, system menu, undo, import.
local H = dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]+$") or ".") .. "/uiharness.lua")
H.boot("wf")
Sim.tap("A") -- demo
H.eq(H.topName(), "LiveScreen", "live")

-- system menu: Playdate OS allows three custom items; all five actions reachable
H.eq(#Sim.menuItems, 3, "three system menu items")
local titles = {}
for _, it in ipairs(Sim.menuItems) do titles[#titles + 1] = it.title end
H.eq(table.concat(titles, ","), "NEXT SHOT,ADD TAKE,GO", "menu items")
local cur = App.cursorShot()
Sim.menu("ADD TAKE")
H.eq(#cur.takes, 1, "menu ADD TAKE logs a take")
Sim.menu("GO", "SLATE")
H.eq(H.topName(), "SlateScreen", "menu GO SLATE")
H.eq(Sim.menuItems[3].value, "-", "GO option resets after use")
Sim.tap("A")
H.eq(#cur.takes, 2, "slate A logs a take")
H.eq(Model.maxTakeN(cur) + 1, 3, "slate now reads TAKE 3")
Sim.crank(45, 3)
H.check(App.cursorShot() ~= cur, "slate crank moves shot")
Sim.tap("B")
App.setCursor(cur)
Sim.menu("GO", "PICKUP")
H.eq(cur.status, "PICKUP", "menu PICKUP")
Sim.menu("GO", "WRAP")
H.eq(H.topName(), "ReportScreen", "menu WRAP")
Sim.tap("B")
Sim.menu("NEXT SHOT")
H.check(App.cursorShot() ~= cur, "menu NEXT SHOT moves")

-- undo through the hub (UP, then UNDO is pre-selected after an undoable action)
local s = App.cursorShot()
Sim.tap("RIGHT") -- GOT IT
H.eq(s.status, "GOT IT", "got it")
Sim.tap("UP")
H.eq(App.top().sel, 2, "hub opens on UNDO right after an undoable action")
Sim.tap("A")
H.check(s.status ~= "GOT IT", "undo reverted GOT IT")
H.eq(App.cursorShot(), s, "undo returns cursor to the shot")
-- B right after GOT IT must NOT undo (it opens details)
Sim.tap("RIGHT")
H.eq(s.status, "GOT IT", "got it again")
App.setCursor(s)
Sim.tap("B")
H.eq(H.topName(), "DetailsScreen", "B opens details")
H.eq(s.status, "GOT IT", "B did not undo")
Sim.tap("B")

-- builder: save & new with carried fields, auto numbering
local setup = Model.parentOf[s.id]
local n0 = #setup.shots
App.setCursor(s)
H.hub("NEW SHOT")
H.eq(H.topName(), "BuilderScreen", "builder")
Sim.tap("RIGHT") -- size +1
Sim.hold("A", 600)
Sim.hold("A", 600)
H.eq(#setup.shots, n0 + 2, "builder added two shots")
H.eq(setup.shots[#setup.shots].num, Util.pad2(n0 + 2), "auto numbered")
H.eq(setup.shots[#setup.shots].size, setup.shots[#setup.shots - 1].size, "fields carry over")
Sim.tap("B")
H.eq(H.topName(), "LiveScreen", "builder closes without prompt when nothing changed")
H.eq(App.cursorShot(), setup.shots[#setup.shots], "cursor on last added shot")

-- browser: add a scene then a setup (inherits camera settings)
H.hub("SHOT LIST")
Sim.tap("B") -- setups
Sim.tap("B") -- scenes
H.eq(App.top().title, "SCENES", "scenes level")
local day = Model.currentDay()
local nScenes = #day.scenes
H.row("add")
H.eq(#day.scenes, nScenes + 1, "scene added")
H.eq(H.topName(), "FormScreen", "scene form opens")
Sim.tap("B")
H.row(day.scenes[#day.scenes].id)
H.eq(App.top().title, "SETUPS", "into new scene")
H.row("add")
local sc = day.scenes[#day.scenes]
H.eq(#sc.setups, 1, "setup added")
Sim.tap("B")
H.row("add") -- second setup copies the first
H.eq(sc.setups[2].letter, "B", "letter B")
H.eq(sc.setups[2].fps, sc.setups[1].fps, "copied tech")
Sim.tap("B")
App.home()

-- gear: add a preset via keyboard
H.hub("GEAR")
H.row("lenses")
local before = #Model.db.gear.lists.lenses
H.row("add")
Sim.type("Petzval 58")
H.eq(#Model.db.gear.lists.lenses, before + 1, "lens preset added")
H.eq(Model.db.gear.lists.lenses[before + 1], "PETZVAL 58", "uppercased")
App.home()

-- settings: hold time applies immediately
H.hub("SETTINGS")
H.row("holdMs")
H.eq(H.topName(), "PickerOverlay", "enum picker")
Sim.tap("DOWN"); Sim.tap("A")
H.eq(Model.db.settings.holdMs, 600, "hold time set")
H.eq(Input.holdMs, 600, "input uses new hold time")
App.home()

-- import: flat document in /import
playdate.file.mkdir("import")
local f = playdate.file.open("import/csv-convert.json", playdate.file.kFileWrite)
f:write(json.encode({ format = "shotlist.shots", version = 1, project = { title = "Imported Promo", client = "ACME" },
	shots = { { scene = "1", setup = "A", size = "Wide", move = "Static", desc = "Opener", priority = "A" },
		{ scene = "1", setup = "A", size = "CU", move = "handheld", desc = "Face" },
		{ scene = "2", setup = "A", size = "Insert", move = "Push In", desc = "Logo" } } }))
f:close()
H.hub("DATA")
H.row("IMPORT FROM /IMPORT")
H.eq(H.topName(), "PickerOverlay", "import picker")
Sim.tap("A")
H.eq(Model.project().title, "Imported Promo", "imported project active")
H.eq(#Model.flat(), 3, "imported 3 shots")
H.eq(Model.code(App.cursorShot()), "1A-01", "cursor at first imported shot")
H.eq(#Model.db.projects, 2, "both projects kept")

-- switching back
H.hub("PROJECT")
H.row("SWITCH PROJECT")
Sim.tap("UP") -- first project
Sim.tap("A")
H.eq(Model.project().title, "FIRST LIGHT :30", "switched back")

H.done("test_workflows")
