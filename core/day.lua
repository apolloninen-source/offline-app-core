-- Calendar days as plain numbers: day 0 is 1970-01-01, 20724 is 2026-09-28.
--
-- The daily challenge follows the player's own calendar date, as Wordle does:
-- everyone gets the same challenge on the same date, and it changes at local
-- midnight. The arithmetic is pure (no os.time), so it cannot drift with time
-- zones or daylight saving.

local M = {}

-- The clock can be replaced in tests.
local clock = function()
	return os.date("*t")
end

--- Days since 1970-01-01 for a civil date (Howard Hinnant's algorithm).
function M.from_date(year, month, day)
	local y = year - (month <= 2 and 1 or 0)
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = month > 2 and month - 3 or month + 9
	local doy = math.floor((153 * mp + 2) / 5) + day - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

--- The inverse: year, month, day for a day number.
function M.to_date(n)
	local z = n + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local d = doy - math.floor((153 * mp + 2) / 5) + 1
	local m = mp < 10 and mp + 3 or mp - 9
	return y + (m <= 2 and 1 or 0), m, d
end

--- Today's day number, in the player's local calendar.
function M.today()
	local t = clock()
	return M.from_date(t.year, t.month, t.day)
end

--- The challenge number shown to players: day 1 is the app's launch day.
function M.challenge_number(day, launch_day)
	return day - launch_day + 1
end

--- For tests: replace the clock with a function returning {year, month, day}.
function M.set_clock(fn)
	clock = fn or function()
		return os.date("*t")
	end
end

return M
