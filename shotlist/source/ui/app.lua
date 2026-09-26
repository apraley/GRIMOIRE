-- App shell: screen stack, global shortcuts (NEXT), toasts with undo, the
-- system keyboard bridge, the Playdate system menu, and the frame loop.

App = {}

---------------------------------------------------------------------------
-- Screen base class
---------------------------------------------------------------------------
Screen = {}
Screen.__index = Screen

function Screen:extend()
	local c = setmetatable({}, { __index = self })
	c.__index = c
	return c
end

function Screen:new(...)
	local o = setmetatable({}, self)
	o:init(...)
	return o
end

function Screen:init() end
function Screen:enter() end      -- became top of stack (also on return from a child)
function Screen:leave() end      -- about to be popped
function Screen:update() end     -- every frame while on top
function Screen:draw() end
function Screen:event(ev) return false end
function Screen:crank(change, accel) end

---------------------------------------------------------------------------
-- Stack
---------------------------------------------------------------------------
App.stack = {}
App.toastMsg = nil
App.dirty = true
App.frame = 0
App.kb = nil

function App.top() return App.stack[#App.stack] end

function App.push(s)
	if s.overlay then App.toastMsg = nil end
	App.stack[#App.stack + 1] = s
	Input.reset()
	s:enter()
	App.dirty = true
	return s
end

function App.pop()
	local s = table.remove(App.stack)
	if s then s:leave() end
	local t = App.top()
	if t then t:enter() end
	Input.reset()
	App.dirty = true
	return s
end

-- Pop down to (and including) screen s.
function App.popTo(s)
	while #App.stack > 1 and App.top() ~= s do App.pop() end
end

function App.replace(s)
	local old = table.remove(App.stack)
	if old then old:leave() end
	return App.push(s)
end

-- Clear everything above the root LIVE screen.
function App.home()
	while #App.stack > 1 do
		local s = table.remove(App.stack)
		s:leave()
	end
	local t = App.top()
	if t then t:enter() end
	Input.reset()
	App.dirty = true
	return t
end

function App.redraw() App.dirty = true end

-- Root screen: LIVE when a project exists, otherwise WELCOME.
function App.resetRoot()
	for i = #App.stack, 1, -1 do App.stack[i]:leave() end
	App.stack = {}
	if Model.db and Model.project() then
		App.push(LiveScreen:new())
	else
		App.push(WelcomeScreen:new())
	end
end

---------------------------------------------------------------------------
-- Toasts (bottom banner). opts.undo = true lets B undo the last op while shown.
---------------------------------------------------------------------------
function App.toast(msg, opts)
	opts = opts or {}
	App.toastMsg = { text = Util.upper(msg), untilMs = Util.nowMs() + (opts.ms or (opts.undo and 3000 or 1600)),
		undo = opts.undo, icon = opts.icon }
	App.dirty = true
end

---------------------------------------------------------------------------
-- Production actions shared by LIVE, SLATE, the system menu and the hub
---------------------------------------------------------------------------
function App.commit(op)
	local inv, err = Store.commit(op)
	if inv == nil then App.toast("ERROR: " .. tostring(err)) end
	App.dirty = true
	return inv
end

function App.cursorShot()
	local s = Model.byId[Model.db.settings.cursor]
	if s and s.k == "shot" and Model.ctx(s.id).project == Model.project() then return s end
	local flat = Model.flat()
	if #flat > 0 then
		Model.db.settings.cursor = flat[1].shot.id
		return flat[1].shot
	end
	return nil
end

function App.setCursor(shot)
	if shot == nil then return end
	if Model.db.settings.cursor ~= shot.id then
		Model.db.settings.cursor = shot.id
		Store.touchSession()
	end
	App.dirty = true
end

-- Log a take on the cursor shot. Returns the take record.
function App.addTake(shot)
	shot = shot or App.cursorShot()
	if shot == nil then App.toast("NO SHOT SELECTED"); return nil end
	local op, take = Model.opTake(shot, Util.now())
	if App.commit(op) then return Model.get(take.id) end
	return nil
end

function App.setStatus(shot, status, undo)
	App.commit(Model.opStatus(shot, status, Util.now()))
	App.toast(Model.code(shot) .. " " .. status, { undo = undo ~= false, icon = Vocab.STATUS_ICON[status] })
end

-- NEXT from anywhere. Pressing again within a few seconds (while the cursor
-- still sits on the last suggestion) cycles to the next-ranked candidate.
App.nextState = nil
function App.goNext(opts)
	opts = opts or {}
	local cur = App.cursorShot()
	local ns = App.nextState
	local idx = 1
	local fromId = cur and cur.id
	-- cycling only makes sense while looking at LIVE's NEXT banner
	local onLive = getmetatable(App.top()) == LiveScreen
	if ns and not opts.fresh and onLive and Util.nowMs() - ns.at < 8000 and cur and cur.id == ns.shotId then
		idx = ns.idx + 1
		fromId = ns.fromId
	end
	local cands = Model.nextCandidates(fromId)
	if #cands == 0 then
		App.home()
		App.toast("NOTHING LEFT TO SHOOT", { icon = "check" })
		return nil
	end
	if idx > #cands then idx = 1 end
	local c = cands[idx]
	App.setCursor(c.shot)
	App.nextState = { at = Util.nowMs(), shotId = c.shot.id, idx = idx, fromId = fromId }
	local live = App.home()
	if live and live.showNext then live:showNext(c, idx, #cands) end
	return c.shot
end

---------------------------------------------------------------------------
-- Keyboard bridge (the only place text is typed)
---------------------------------------------------------------------------
function App.keyboard(title, initial, onDone)
	App.kb = { title = Util.upper(title or "TEXT"), text = initial or "", onDone = onDone }
	playdate.keyboard.keyboardWillHideCallback = function(ok)
		local kb = App.kb
		App.kb = nil
		if kb and ok and kb.onDone then kb.onDone(Util.trim(playdate.keyboard.text or "")) end
		App.dirty = true
	end
	playdate.keyboard.textChangedCallback = function()
		if App.kb then App.kb.text = playdate.keyboard.text end
		App.dirty = true
	end
	playdate.keyboard.show(initial or "")
	App.dirty = true
end

local function drawKeyboardPanel()
	local kw = playdate.keyboard.width and playdate.keyboard.width() or 180
	local w = Gfx.W - (kw or 180)
	Gfx.fill(0, 0, w, Gfx.H, true)
	Gfx.fill(0, 0, w, 20)
	Gfx.pix(App.kb.title, 8, 7, 1, { white = true })
	local lines = Gfx.wrap((App.kb.text or "") .. "_", w - 16, 9)
	for i, l in ipairs(lines) do Gfx.text(l, 8, 26 + (i - 1) * (Gfx.lineH + 2)) end
end

---------------------------------------------------------------------------
-- System menu (Playdate OS allows at most three custom items)
---------------------------------------------------------------------------
App.MORE_OPTIONS = { "-", "SLATE", "PICKUP", "WRAP", "RUSH" }
App.pendingMenu = nil

function App.setupSystemMenu()
	local menu = playdate.getSystemMenu()
	menu:removeAllMenuItems()
	menu:addMenuItem("NEXT SHOT", function() App.pendingMenu = "NEXT" end)
	menu:addMenuItem("ADD TAKE", function() App.pendingMenu = "TAKE" end)
	App.moreItem = menu:addOptionsMenuItem("GO", App.MORE_OPTIONS, "-", function(v)
		if v and v ~= "-" then App.pendingMenu = v end
	end)
end

function App.runMenuAction(a)
	if App.moreItem and App.moreItem.setValue then App.moreItem:setValue("-") end
	if Model.db == nil or Model.project() == nil then return end
	if a == "NEXT" then
		App.goNext({ fresh = true })
	elseif a == "TAKE" then
		local t = App.addTake()
		if t then
			App.home()
			App.toast("TAKE " .. t.n .. " " .. Model.code(App.cursorShot()), { undo = true })
		end
	elseif a == "SLATE" then
		App.home()
		App.push(SlateScreen:new())
	elseif a == "PICKUP" then
		local s = App.cursorShot()
		if s then App.home(); App.setStatus(s, "PICKUP") end
	elseif a == "RUSH" then
		-- "we're losing the light": toggle strict-priority NEXT, then jump
		local s = Model.db.settings
		local mode = s.nextMode == "RUSH" and "BALANCED" or "RUSH"
		App.commit(Model.opSet(s, "nextMode", mode, "NEXT MODE " .. mode))
		App.goNext({ fresh = true })
		App.toast("NEXT MODE: " .. mode, { icon = "clock", ms = 2500 })
	elseif a == "WRAP" then
		App.home()
		App.push(ReportScreen:new())
	end
end

-- Status card shown on the left half while the system menu is open.
function App.buildMenuImage()
	if Model.db == nil or Model.project() == nil then return nil end
	local img = playdate.graphics.image.new(400, 240, playdate.graphics.kColorWhite)
	playdate.graphics.pushContext(img)
	Gfx.fill(0, 0, 200, 240, true)
	local cur = App.cursorShot()
	Gfx.pix("NOW", 10, 12, 1)
	Gfx.pix(cur and Model.code(cur) or "--", 10, 24, 3)
	local c = cur and Model.nextCandidates(cur.id)[1]
	Gfx.pix("NEXT", 10, 62, 1)
	Gfx.pix(c and Model.code(c.shot) or "DONE", 10, 74, 3)
	if c then Gfx.text(Model.describe(c.shot), 10, 100, { maxW = 180 }) end
	local pr = Model.progress(Model.project(), Model.currentDay())
	Gfx.pix(pr.pct .. "%", 10, 140, 4)
	Gfx.bar(10, 174, 180, 10, pr.total > 0 and pr.done / pr.total or 0, pr.total > 0 and pr.pickups / pr.total or 0)
	Gfx.text(pr.done .. "/" .. pr.total .. " DONE  " .. pr.pickups .. " P/U", 10, 190)
	playdate.graphics.popContext()
	return img
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local function drawToast()
	local t = App.toastMsg
	if t == nil then return end
	local w = Gfx.textW(t.text, true) + (t.icon and 16 or 0) + (t.undo and 70 or 0) + 20
	w = math.min(w, Gfx.W - 20)
	local x, y = (Gfx.W - w) // 2, Gfx.H - 48
	playdate.graphics.setColor(playdate.graphics.kColorBlack)
	playdate.graphics.fillRoundRect(x, y, w, 24, 5)
	playdate.graphics.setColor(playdate.graphics.kColorWhite)
	playdate.graphics.drawRoundRect(x + 2, y + 2, w - 4, 20, 4)
	local tx = x + 10
	if t.icon then Gfx.icon(t.icon, tx, y + 8, { white = true }); tx = tx + 14 end
	Gfx.text(t.text, tx, y + 4, { bold = true, white = true, maxW = w - (tx - x) - (t.undo and 74 or 10) })
	if t.undo then
		Gfx.pix("UP,A UNDO", x + w - 66, y + 9, 1, { white = true })
	end
end

function App.draw()
	local gfx = playdate.graphics
	gfx.clear(gfx.kColorWhite)
	gfx.setColor(gfx.kColorBlack)
	-- draw from the last non-overlay screen upward
	local base = #App.stack
	while base > 1 and App.stack[base].overlay do base = base - 1 end
	for i = base, #App.stack do
		local s = App.stack[i]
		if i > base and s.overlay and not s.noDim then Gfx.dim() end
		Gfx.coverFooter = i > base
		s:draw()
		Gfx.coverFooter = false
	end
	if not (App.top() and App.top().hideToast) then drawToast() end
	if Store.saving > 0 then
		Gfx.fill(Gfx.W - 13, 3, 11, 10, true)
		Gfx.icon("disk", Gfx.W - 12, 4)
	end
	if Store.lastError then
		Gfx.fill(0, 0, Gfx.W, 12)
		Gfx.pix("SAVE ERROR: " .. Store.lastError, 4, 3, 1, { white = true })
	end
	if App.kb then drawKeyboardPanel() end
end

function App.update()
	App.frame = App.frame + 1
	if App.pendingMenu then
		local a = App.pendingMenu
		App.pendingMenu = nil
		App.runMenuAction(a)
	end
	local events = Input.update()
	local top = App.top()
	if App.toastMsg and Util.nowMs() > App.toastMsg.untilMs then
		App.toastMsg = nil
		App.dirty = true
	end
	for _, ev in ipairs(events) do
		App.dirty = true
		top = App.top()
		if top == nil then break end
		local handled = false
		-- Undo is deliberately NOT bound to B while a toast shows: B is "back"
		-- everywhere, and a reflexive back-press must never revert a GOT IT.
		if ev == "BL" and Model.db and Model.project() and not top.noGlobalNext then
			App.goNext()
			handled = true
		end
		if not handled then top:event(ev) end
	end
	top = App.top()
	if top then
		if Input.crankChange ~= 0 then
			App.dirty = true
			top:crank(Input.crankChange, Input.crankAccel)
		end
		top:update()
	end
	if Model.db then Store.tick(Input.idleMs()) end
	-- clock/animation refresh: once a second, or every frame when asked
	if App.frame % 30 == 0 or (top and top.animating) or Input.isDown("A") or Input.isDown("B") then
		App.dirty = true
	end
	if App.dirty then
		App.draw()
		App.dirty = false
	end
end

return App
