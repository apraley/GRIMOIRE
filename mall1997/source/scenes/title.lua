-- Title screen, new-game setup and the opening crawl.

Title = {}

local NAMES = { "Alex", "Sam", "Jordan", "Casey", "Jamie", "Robin", "Taylor", "Morgan", "Chris", "Dana" }

function Title.start()
  local sc = { t = 0, hasSave = Save.exists() }
  function sc:update()
    self.t = self.t + 1
    if not self.menu and self.t > 20 then
      self.menu = true
      local opts = {}
      if self.hasSave then opts[#opts + 1] = "Continue" end
      opts[#opts + 1] = "New mall"
      opts[#opts + 1] = "About"
      Choose(nil, opts, function(i)
        local o = opts[i]
        if o == "Continue" then Title.continue()
        elseif o == "New mall" then Title.newGame()
        else
          Say({ "THE MALL, 1997. A life simulation. There is no goal.",
            "Get a job. Fall in love. Set the NEON SERPENT record. Get banned from the Cineplex. Find out what's under the fountain.",
            "The mall keeps living whether you're there or not." }, { after = function() self.menu = false end })
        end
      end, { x = 140, y = 150, w = 120, cancel = function() self.menu = false end })
    end
  end
  function sc:draw()
    local gfx = playdate.graphics
    Gfx.clear("black")
    -- a neon sign over a parking lot at dusk
    for i = 0, 40 do Gfx.fill((i * 97) % 400, (i * 37) % 90, 1, 1, "white") end
    Gfx.neon(58, 28, 284, 4, 1); Gfx.neon(58, 96, 284, 4, 2)
    Gfx.neon(58, 28, 4, 72, 3); Gfx.neon(338, 28, 4, 72, 4)
    Gfx.text("THE MALL", 200, 40, { white = true, bold = true, align = "center" })
    Gfx.text("~ 1 9 9 7 ~", 200, 66, { white = true, align = "center" })
    for i = 0, 9 do
      gfx.setColor(gfx.kColorWhite)
      gfx.drawLine(i * 44, 240, 200 + (i - 4.5) * 12, 110)
    end
    Gfx.fill(0, 108, 400, 3, "white")
  end
  Scene.reset(sc)
end

function Title.continue()
  if not Save.read() then Say("That save is from a different version of the mall. Start a new one.") return end
  if W.p.atMall then Explore.start() else Day.morning() end
end

function Title.newGame()
  Choose("YOUR NAME", NAMES, function(i)
    local name = NAMES[i]
    local seed = (playdate.getSecondsSinceEpoch() or 1997) % 2147483647
    Title.generate(seed, name)
  end, { x = 150, y = 40, w = 110, visible = 8 })
end

function Title.generate(seed, name)
  local sc = { stage = "Pouring the foundations...", done = false }
  sc.co = coroutine.create(function()
    World.new(seed, name)
    sc.stage = "Opening the stores..."
    coroutine.yield()
    -- the morning before you arrive
    WorldSim.advance(15 * 60 + 25, 5, 6)
  end)
  function sc:update()
    if coroutine.status(self.co) ~= "dead" then
      local ok, err = coroutine.resume(self.co)
      if not ok then error(err) end
    else
      Scene.pop()
      Title.intro()
    end
  end
  function sc:draw()
    Gfx.clear("black")
    Gfx.box(60, 90, 280, 60, "dark")
    Gfx.text(self.stage, 200, 104, { white = true, align = "center" })
    if W and W.t then Gfx.text(Clock.hhmm(Clock.minute(W.t)), 200, 124, { white = true, align = "center" }) end
  end
  Scene.push(sc)
end

function Title.intro()
  local p = W.p
  local friends = {}
  for _, id in ipairs(p.friends) do friends[#friends + 1] = W.npcs[id].first end
  Say({
    "Friday, August 29, 1997. The last weekend of summer.",
    "You are " .. p.name .. ". You're sixteen. You have $22, a pager, a backpack, and a curfew.",
    "Your friends are " .. U.join(friends, ", ", " and ") .. ". Your mom is dropping you off at the " .. W.mall.name .. ".",
    "There are " .. #W.stores .. " stores, a food court, an arcade, a six-screen Cineplex, and about " .. #W.npcs .. " people who are here more than they should be.",
    "Nobody needs you to save anything. You just have to live here.",
  }, { after = function()
    p.atMall = true
    p.area = "lot"
    p.x, p.y = 4 * 16 + 8, 19 * 16 + 8
    Explore.start()
  end })
end
