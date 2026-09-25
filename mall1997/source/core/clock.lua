-- Calendar and clock. World time is W.t = minutes since 00:00 on day 0.
-- Day 0 is Friday, August 29, 1997: the last weekend of summer.

Clock = {}

Clock.EPOCH = { y = 1997, m = 8, d = 29, wd = 5 } -- wd: 0=Sun .. 6=Sat
Clock.MONTHS = { "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }
Clock.MONTH_NAMES = { "January", "February", "March", "April", "May", "June", "July",
  "August", "September", "October", "November", "December" }
Clock.DAYS = { "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" }
Clock.DAY_NAMES = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }

local function isLeap(y) return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0 end
local function monthLen(y, m)
  local l = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  if m == 2 and isLeap(y) then return 29 end
  return l[m]
end
Clock.monthLen = monthLen

local dateCache = {}
function Clock.date(day)
  local c = dateCache[day]
  if c then return c end
  local y, m, d = Clock.EPOCH.y, Clock.EPOCH.m, Clock.EPOCH.d
  local n = day
  while n > 0 do
    local left = monthLen(y, m) - d
    if n <= left then d = d + n; n = 0
    else
      n = n - left - 1
      d = 1; m = m + 1
      if m > 12 then m = 1; y = y + 1 end
    end
  end
  local r = { y = y, m = m, d = d, wd = (Clock.EPOCH.wd + day) % 7 }
  dateCache[day] = r
  return r
end

-- day index for a calendar date (only used for dates on/after the epoch)
function Clock.dayOf(y, m, d)
  local day = 0
  local cy, cm, cd = Clock.EPOCH.y, Clock.EPOCH.m, Clock.EPOCH.d
  while cy < y or (cy == y and cm < m) do
    day = day + monthLen(cy, cm) - cd + 1
    cd = 1; cm = cm + 1
    if cm > 12 then cm = 1; cy = cy + 1 end
  end
  return day + (d - cd)
end

-- Sakamoto's day-of-week (0 = Sunday), valid for any Gregorian date
local function weekday(y, m, d)
  local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
  if m < 3 then y = y - 1 end
  return (y + y // 4 - y // 100 + y // 400 + t[m] + d) % 7
end
Clock.weekday = weekday

local function nthWeekday(y, m, wd, n)
  -- n-th (1-based) weekday wd of month; n = -1 means last
  local first = weekday(y, m, 1)
  if n > 0 then
    local d = 1 + ((wd - first) % 7) + (n - 1) * 7
    return d
  end
  local len = monthLen(y, m)
  local lastWd = (first + len - 1) % 7
  return len - ((lastWd - wd) % 7)
end

local function easter(y)
  local a = y % 19
  local b = y // 100
  local c = y % 100
  local d = b // 4
  local e = b % 4
  local f = (b + 8) // 25
  local g = (b - f + 1) // 3
  local h = (19 * a + b - d - g + 15) % 30
  local i = c // 4
  local k = c % 4
  local l = (32 + 2 * e + 2 * i - h - k) % 7
  local m = (a + 11 * h + 22 * l) // 451
  local month = (h + l - 7 * m + 114) // 31
  local day = ((h + l - 7 * m + 114) % 31) + 1
  return month, day
end

local infoCache = {}
-- Everything the simulation needs to know about a given day.
function Clock.info(day)
  local c = infoCache[day]
  if c then return c end
  local dt = Clock.date(day)
  local y, m, d, wd = dt.y, dt.m, dt.d, dt.wd
  local r = { y = y, m = m, d = d, wd = wd, weekend = (wd == 0 or wd == 6) }
  local hol
  if m == 9 and d == nthWeekday(y, 9, 1, 1) then hol = "Labor Day" end
  if m == 10 and d == 31 then hol = "Halloween" end
  if m == 11 and d == nthWeekday(y, 11, 4, 4) then hol = "Thanksgiving"; r.closed = true end
  if m == 11 and d == nthWeekday(y, 11, 4, 4) + 1 then hol = "Black Friday" end
  if m == 12 and d == 24 then hol = "Christmas Eve" end
  if m == 12 and d == 25 then hol = "Christmas"; r.closed = true end
  if m == 12 and d == 31 then hol = "New Year's Eve" end
  if m == 1 and d == 1 then hol = "New Year's Day" end
  if m == 1 and d == nthWeekday(y, 1, 1, 3) then hol = "MLK Day" end
  if m == 2 and d == 14 then hol = "Valentine's Day" end
  if m == 2 and d == nthWeekday(y, 2, 1, 3) then hol = "Presidents' Day" end
  local em, ed = easter(y)
  if m == em and d == ed then hol = "Easter"; r.closed = true end
  if m == 5 and d == nthWeekday(y, 5, 0, 2) then hol = "Mother's Day" end
  if m == 5 and d == nthWeekday(y, 5, 1, -1) then hol = "Memorial Day" end
  if m == 6 and d == nthWeekday(y, 6, 0, 3) then hol = "Father's Day" end
  if m == 7 and d == 4 then hol = "Independence Day" end
  r.holiday = hol

  -- school calendar
  local school = not r.weekend
  local laborDay = nthWeekday(y, 9, 1, 1)
  if m == 7 or (m == 8) or (m == 9 and d <= laborDay) then school = false end
  if m == 6 and d >= 12 then school = false end
  if (m == 12 and d >= 22) or (m == 1 and d <= 2) then school = false end
  if m == 11 and (d == nthWeekday(y, 11, 4, 4) or d == nthWeekday(y, 11, 4, 4) + 1) then school = false end
  local sbStart = nthWeekday(y, 3, 1, 4)
  if m == 3 and d >= sbStart and d <= sbStart + 4 then school = false; r.springBreak = true end
  if hol == "MLK Day" or hol == "Presidents' Day" or hol == "Memorial Day" or hol == "Labor Day" then school = false end
  r.school = school
  r.summer = (m == 7 or m == 8 or (m == 6 and d >= 12) or (m == 9 and d <= laborDay))

  -- mall hours (minutes of day)
  local open, close = 10 * 60, 21 * 60
  if wd == 0 then open, close = 11 * 60, 18 * 60 end
  local thanks = nthWeekday(y, 11, 4, 4)
  local holidaySeason = (m == 11 and d > thanks) or (m == 12 and d <= 23)
  if holidaySeason then
    if wd == 0 then open, close = 10 * 60, 19 * 60 else open, close = 9 * 60, 22 * 60 end
  end
  r.holidaySeason = holidaySeason
  if hol == "Black Friday" then open = 7 * 60 end
  if hol == "Christmas Eve" or hol == "New Year's Eve" then close = 18 * 60 end
  if hol == "New Year's Day" or hol == "Independence Day" then open, close = 12 * 60, 18 * 60 end
  r.open, r.close = open, close
  r.walkersOpen = 7 * 60   -- concourse doors open early for mall walkers

  if m == 12 or m <= 2 then r.season = "winter"
  elseif m <= 5 then r.season = "spring"
  elseif m <= 8 then r.season = "summer"
  else r.season = "fall" end

  infoCache[day] = r
  return r
end

function Clock.day(t) return math.floor(t / 1440) end
function Clock.minute(t) return math.floor(t) % 1440 end
function Clock.week(t) return math.floor((math.floor(t / 1440) + 5) / 7) end -- weeks roll on Sunday

function Clock.hhmm(mins)
  mins = math.floor(mins) % 1440
  local h, m = mins // 60, mins % 60
  local ap = h >= 12 and "PM" or "AM"
  local hh = h % 12
  if hh == 0 then hh = 12 end
  return string.format("%d:%02d%s", hh, m, ap)
end

function Clock.dateStr(day)
  local dt = Clock.date(day)
  return string.format("%s %s %d, %d", Clock.DAYS[dt.wd + 1], Clock.MONTHS[dt.m], dt.d, dt.y)
end

function Clock.shortDate(day)
  local dt = Clock.date(day)
  return string.format("%d/%d/%02d", dt.m, dt.d, dt.y % 100)
end

function Clock.stamp(t)
  return Clock.dateStr(Clock.day(t)) .. "  " .. Clock.hhmm(Clock.minute(t))
end
