-- The player's saved state, on the phone only.
--
--   local save = require "core.save"
--   local data = save.open("yaksha", { streak = {}, ads = {} })
--   data.values.streak.best = 3
--   data:write()
--
-- Stored with sys.save in the app's own save folder. Missing keys are filled
-- from the defaults, so new fields can be added in later versions.

local M = {}

local VERSION = 1

local function copy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = copy(v)
	end
	return out
end

local function fill(target, defaults)
	for k, v in pairs(defaults) do
		if target[k] == nil then
			target[k] = copy(v)
		elseif type(v) == "table" and type(target[k]) == "table" then
			fill(target[k], v)
		end
	end
	return target
end

--- Opens (or creates) the save for an app. app_id names the save folder.
function M.open(app_id, defaults)
	local path = sys.get_save_file(app_id, "save")
	local values = sys.load(path) or {}
	fill(values, defaults or {})
	values.version = values.version or VERSION

	local data = { path = path, values = values }

	--- Writes the save to disk. Returns true on success.
	function data:write()
		return sys.save(self.path, self.values)
	end

	--- Clears everything back to the defaults (and writes).
	function data:reset()
		self.values = fill({ version = VERSION }, defaults or {})
		return self:write()
	end

	return data
end

return M
