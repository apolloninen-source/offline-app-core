-- "Backup file" and "Restore from a backup file": everything an app keeps
-- (progress, notes, highlights, bookmarks) as one JSON file the player can
-- save anywhere (Files, Drive, email) and bring back on any phone. No
-- account and no server: the file goes where the player sends it.
--
--   local backup = require "core.backup"
--   local path, shared = backup.export("yaksha", { "save", "reader" })
--   -- restoring: filepicker.open(function(self, text, err) ... backup.restore("yaksha", text) end)
--
-- The files named are the app's save files (core.save names them; the
-- reader's is "reader"). Restoring replaces them all; the app then reloads
-- its state (the reader takes the message "reload").

local notes_export = require "core.notes_export"

local M = {}

M.FORMAT = "offline-app-core backup"
M.VERSION = 1

--- Everything in the app's save files, as one table.
function M.collect(app_id, names)
	local files = {}
	for _, name in ipairs(names) do
		files[name] = sys.load(sys.get_save_file(app_id, name))
	end
	return { format = M.FORMAT, version = M.VERSION, app = app_id, date = notes_export.date(), files = files }
end

--- Checks a backup file's text. Returns the backup, or nil and a message
--- for the player.
function M.decode(text, app_id)
	local ok, t = pcall(json.decode, text or "")
	if not ok or type(t) ~= "table" or t.format ~= M.FORMAT then
		return nil, "This is not a backup file from these apps."
	end
	if t.app ~= app_id then
		return nil, "This backup belongs to another app (" .. tostring(t.app) .. ")."
	end
	if type(t.files) ~= "table" or (t.version or 0) > M.VERSION then
		return nil, "This backup file is damaged, or from a newer version of the app."
	end
	return t
end

--- Writes a checked backup over the app's save files.
function M.apply(app_id, t)
	for name, values in pairs(t.files) do
		if type(values) == "table" then
			sys.save(sys.get_save_file(app_id, name), values)
		end
	end
end

--- Decodes and applies a backup file's text. Returns true and the backup's
--- date, or nil and a message.
function M.restore(app_id, text)
	local t, err = M.decode(text, app_id)
	if not t then
		return nil, err
	end
	M.apply(app_id, t)
	return true, t.date
end

--- Saves a backup file in the app's folder and opens the share sheet with
--- it (see core.notes_export). Returns path (or nil, error), shared.
function M.export(app_id, names)
	local file = app_id .. "-backup-" .. notes_export.date() .. ".json"
	return notes_export.export(app_id, file, json.encode(M.collect(app_id, names)))
end

return M
