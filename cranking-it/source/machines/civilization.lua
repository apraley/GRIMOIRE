-- CRANKING IT :: No.12 HAND-CRANKED CIVILIZATION (placeholder - to be implemented)
local gfx <const> = playdate.graphics
local M = Machine.define({
  id = "civilization", number = 12, title = "HAND-CRANKED CIVILIZATION", tagline = "Coming soon.",
  description = "Placeholder.", controls = { { "CRANK", "turn" } },
  modes = { "tutorial", "standard" }, medals = { standard = { 100, 200, 300 } },
  unlockCost = 12,
  drawIcon = function(cx, cy) gfx.drawRect(cx - 20, cy - 20, 40, 40) end,
})
function M:enter() self.t = 0 end
function M:update(dt) self.t = self.t + dt if self.t > 3 then self:finish({ success = true, score = 150 }) end end
function M:draw() gfx.clear(gfx.kColorWhite) UI.header(12, "HAND-CRANKED CIVILIZATION", "") end
