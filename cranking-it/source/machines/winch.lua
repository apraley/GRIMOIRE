-- CRANKING IT :: No.9 SAILBOAT WINCH (placeholder - to be implemented)
local gfx <const> = playdate.graphics
local M = Machine.define({
  id = "winch", number = 9, title = "SAILBOAT WINCH", tagline = "Coming soon.",
  description = "Placeholder.", controls = { { "CRANK", "turn" } },
  modes = { "tutorial", "standard" }, medals = { standard = { 100, 200, 300 } },
  unlockCost = 8,
  drawIcon = function(cx, cy) gfx.drawRect(cx - 20, cy - 20, 40, 40) end,
})
function M:enter() self.t = 0 end
function M:update(dt) self.t = self.t + dt if self.t > 3 then self:finish({ success = true, score = 150 }) end end
function M:draw() gfx.clear(gfx.kColorWhite) UI.header(9, "SAILBOAT WINCH", "") end
