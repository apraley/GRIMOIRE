-- World tick orchestration. The same code path runs while the player walks
-- around (1 game minute per real second), during skipped time (shifts,
-- movies), overnight, and in the headless 30-day inspection harness.

WorldSim = {}

local DAWN = 5 * 60

-- one-time setup after World.new (needs every module loaded)
function WorldSim.bootstrap()
  local r = RNG.new(W.seed + 17)
  local tw = Stores.totalWeight()
  for _, s in ipairs(W.stores) do Stores.calibrateRent(s, tw) end
  Events.seed(r)
  CinemaSim.init()
  ArcadeSim.seedBoards()
  W.mall.basePop = 0
  for _, n in ipairs(W.npcs) do if n.status == "active" then W.mall.basePop = W.mall.basePop + 1 end end
  W.lastDay = Clock.day(W.t)
  NPCAI.newDay(W.lastDay)
  W.lastSocial = W.t
end

function WorldSim.newDay(day)
  local info = Clock.info(day)
  Stores.daily(day - 1)
  Econ.daily(day - 1)
  if info.wd == 0 then
    Stores.weekly(day)
    MusicSim.weekly(day)
    Trends.weekly(day)
    Security.weekly(day)
  end
  if info.wd == 5 then CinemaSim.weekly(day) end
  Stores.staffing(day)
  Rumors.daily()
  Social.daily(day)
  ArcadeSim.daily()
  Events.daily(day)
  Jobs.daily(day)
  PlayerSim.daily(day)
  NPCAI.newDay(day)
  W.lastDay = day
end

-- advance the world by dt minutes (dt <= 10)
function WorldSim.tick(dt)
  local before = W.t
  W.t = W.t + dt
  -- day rolls over at dawn
  local d = math.floor((W.t - DAWN) / 1440)
  if d > W.lastDay then
    for day = W.lastDay + 1, d do WorldSim.newDay(day) end
  end
  NPCAI.update(dt)
  if W.t - (W.lastSocial or 0) >= 10 then
    W.lastSocial = W.t
    Social.update()
  end
  if W.p.atMall then PlayerSim.tick(dt) end
end

-- run the world forward to time t in steps of `step` minutes.
-- yieldEvery: call coroutine.yield() every N steps when running inside a
-- coroutine (keeps the device responsive during long skips)
function WorldSim.advance(t, step, yieldEvery)
  step = step or 5
  local n = 0
  while W.t < t do
    WorldSim.tick(math.min(step, t - W.t))
    n = n + 1
    if yieldEvery and n % yieldEvery == 0 and coroutine.isyieldable() then coroutine.yield() end
  end
end
