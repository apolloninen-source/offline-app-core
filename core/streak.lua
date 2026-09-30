-- Daily streaks. Works on a plain table kept in the save:
--   { last_day = number|nil, current = number, best = number, days = number }
-- Pure functions; the caller passes today's day number (core.day).

local M = {}

local function norm(state)
	state.current = state.current or 0
	state.best = state.best or 0
	state.days = state.days or 0
	return state
end

--- Records that the player played on `day`. Playing twice on one day
--- counts once; missing a day restarts the streak at 1.
function M.record(state, day)
	norm(state)
	if state.last_day == day then
		return state
	end
	if state.last_day == day - 1 then
		state.current = state.current + 1
	else
		state.current = 1
	end
	state.last_day = day
	state.days = state.days + 1
	if state.current > state.best then
		state.best = state.current
	end
	return state
end

--- The streak as it stands on `today`: still alive if the player played
--- today or yesterday, otherwise 0.
function M.current(state, today)
	norm(state)
	if state.last_day and state.last_day >= today - 1 then
		return state.current
	end
	return 0
end

--- True if the player has already played on `today`.
function M.played_today(state, today)
	return state.last_day == today
end

return M
