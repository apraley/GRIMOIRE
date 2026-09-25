-- Renders source/launcher/card.png (350x155) and icon.png (32x32) with the
-- app's own sprites via the test rasterizer:
--   lua5.4 tools/make_launcher.lua && python3 tools/make_launcher.py
TEST_DIR = "tests/"
SOURCE_DIR = "source/"
dofile(TEST_DIR .. "mock_playdate.lua")
dofile(TEST_DIR .. "raster.lua")
import "main"
local gfx = playdate.graphics
os.execute("mkdir -p tests/out")
-- Card
gfx.clear(gfx.kColorWhite)
Draw.fillPattern("brick", 0, 0, 350, 155)
Draw.fillPattern("wood", 0, 141, 350, 14)
gfx.setColor(gfx.kColorBlack)
gfx.drawLine(0, 141, 350, 141)
Sprites.printer(14, 36, "COMPLETE", 0, { progress = 1, shape = "benchy", color = "ORANGE", spoolFrac = 0.8 })
Draw.window(130, 6, 208, 64)
Text.draw("PRINT", 234, 14, { align = "center", scale = 3 })
Text.draw("SHOP", 234, 42, { align = "center", scale = 3 })
Sprites.sea(122, 126, 228, 15, 0)
Sprites.benchy(206, 80, 0, { mood = "happy" })
Raster.save("tests/out/card.pbm")
-- Icon: a spool with a benchy-orange fill
gfx.clear(gfx.kColorWhite)
Sprites.spool(16, 16, 15, 0.75, "ORANGE")
Raster.save("tests/out/icon.pbm")
print("launcher rendered")
