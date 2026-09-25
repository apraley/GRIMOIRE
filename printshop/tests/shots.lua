-- Renders screenshots of every screen with tests/raster.lua.
--   lua5.4 tests/shots.lua && python3 tools/pbm2png.py
TEST_DIR = "tests/"
SOURCE_DIR = "source/"
dofile(TEST_DIR .. "mock_playdate.lua")
dofile(TEST_DIR .. "raster.lua")
os.execute("mkdir -p tests/out")
MOCK.nowSec = MOCK.nowSec + 14 * 3600   -- 14:00 local-ish
import "main"
Store.data.captain.seenIntro = true
local B = { A = playdate.kButtonA, B = playdate.kButtonB, UP = playdate.kButtonUp, DOWN = playdate.kButtonDown,
	LEFT = playdate.kButtonLeft, RIGHT = playdate.kButtonRight }
local function frames(n) for _ = 1, n or 1 do MOCK.frame(nil, 0) end end
local function press(b) MOCK.frame({ b }, 0) MOCK.frame(nil, 0) end
local function shot(name)
	Toast.current, Toast.queue = nil, {}
	Draw.t = 0  -- blink on
	Draw.blinkOn = true
	Screens.fade = 0
	Screens.draw()
	Raster.save("tests/out/" .. name .. ".pbm")
end
local function push(s) Screens.push(s) frames(8) end

frames(30)
shot("01_home_printing")
Screens.top().sel = 3
shot("02_home_station_rolodex")
push(WatchScreen.new()) shot("03_watch")
Screens.popToRoot()
push(QueueScreen.new()) press(B.DOWN) press(B.DOWN) shot("04_queue")
press(B.A) frames(3) shot("05_queue_menu")
Screens.popToRoot()
push(JobEditScreen.new(Store.job("j2"))) shot("06_job_edit")
Screens.popToRoot()
push(RolodexScreen.new()) shot("07_rolodex")
Screens.top().idx = 3 shot("08_rolodex_low")
push(SpoolLedgerScreen.new(Store.spool("s4"))) shot("09_ledger")
Screens.popToRoot()
push(CalibScreen.new()) shot("10_calib")
press(B.RIGHT) shot("11_profiles")
Screens.popToRoot()
push(CalibRunScreen.new(CalibDefs.byId.temptower, "p1|PLA|BAMBU")) press(B.A) press(B.A) shot("12_calib_tower")
press(B.A) shot("13_calib_dial")
Screens.popToRoot()
push(CalibRunScreen.new(CalibDefs.byId.flow, "p1|PETG|OVERTURE")) press(B.A) press(B.A) press(B.A) shot("14_calib_flow")
Screens.popToRoot()
push(MaintScreen.new()) shot("15_maint")
Screens.popToRoot()
push(CaptainScreen.new()) frames(90) shot("16_captain")
Screens.popToRoot()
push(StatsScreen.new()) shot("17_stats")
press(B.RIGHT) shot("18_stats_materials")
Screens.popToRoot()
push(SettingsScreen.new()) shot("19_settings")
Screens.popToRoot()
push(ProjectScreen.new("GARDEN")) shot("27_project")
Screens.popToRoot()
push(FailureScreen.new({ job = Store.job("j4") })) shot("20_failure")
Screens.popToRoot()
Common.say(Captain.advice()) frames(120) shot("21_home_dialog")
Screens.popToRoot()
Dial.open({ title = "NOZZLE", label = "NOZZLE TEMP", value = 215, min = 190, max = 240, unit = "C" }) frames(3) shot("22_dial")
Screens.popToRoot()
-- idle / complete / error states
local p = Printing.provider
Store.settings().demoChaos = false
for _ = 1, 400 do MOCK.advance(30) MOCK.frame(nil, 0, 500) end
frames(5) shot("23_home_complete")
Printing.acknowledge() frames(5) shot("24_home_idle")
Store.settings().theme = "day" Draw.setTheme("day") shot("25_home_day")
push(QueueScreen.new()) shot("26_queue_day")
print("shots written")
