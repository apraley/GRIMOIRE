-- Static Playdate API check: every playdate.* / gfx.* reference in source/
-- must be a documented function, constant or namespace (from the SDK's
-- documented API list). Runtime coverage of method calls on images/fonts/
-- synths comes from the strict mock (tools/pdmock.lua) during smoke tests.
-- usage: lua5.4 tools/apicheck.lua

local dir = (arg[0]:match("(.*/)") or "./")
local known, namespaces = {}, {}
for line in io.lines(dir .. "pd_api_functions.txt") do
  known[line:gsub(":", ".")] = true
  local ns = line:match("^(.*)[.:]")
  while ns do namespaces[ns] = true; ns = ns:match("^(.*)%.") end
end
for line in io.lines(dir .. "pd_api_constants.txt") do
  local cls, k = line:match("^(%S+) (%S+)")
  if cls then known[cls .. "." .. k] = true end
end
local p = io.popen('find "' .. dir .. '../source" -name "*.lua"')
local bad, refs = {}, 0
for file in p:lines() do
  local n = 0
  for line in io.lines(file) do
    n = n + 1
    local code = line:gsub("%-%-.*$", "")
    for ref in code:gmatch("playdate%.[%w_%.]+") do
      refs = refs + 1
      ref = ref:gsub("%.$", "")
      if not known[ref] and not namespaces[ref] and ref ~= "playdate.update" and ref ~= "playdate.gameWillTerminate"
        and ref ~= "playdate.deviceWillSleep" then
        bad[#bad + 1] = file:match("source/(.*)") .. ":" .. n .. "  " .. ref
      end
    end
    for ref in code:gmatch("[^%w_%.]gfx%.([%w_%.]+)") do
      refs = refs + 1
      local full = "playdate.graphics." .. ref:gsub("%.$", "")
      if not known[full] and not namespaces[full] then bad[#bad + 1] = file:match("source/(.*)") .. ":" .. n .. "  gfx." .. ref end
    end
  end
end
p:close()
for _, b in ipairs(bad) do print("UNDOCUMENTED: " .. b) end
print(("%d references checked, %d problems"):format(refs, #bad))
os.exit(#bad == 0 and 0 or 1)
