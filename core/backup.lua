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

-- Several apps in one ------------------------------------------------------------
--
-- An app that holds several games keeps each game's saves under the game's
-- own id, and backs them up together as one file:
--
--   local PARTS = { { app = "dharma", names = { "save", "reader" } },
--                   { app = "yaksha", names = { "save" } }, ... }
--   backup.export_set("dharma", PARTS)
--   backup.restore_set("dharma", PARTS, text, "dharma")
--
-- restore_set also takes a backup that one of the games made on its own,
-- before it joined the set, so no player's old backup file is lost.

--- Everything in the parts' save files, as one table.
function M.collect_set(id, parts)
	local apps = {}
	for _, p in ipairs(parts) do
		local files = {}
		for _, name in ipairs(p.names) do
			files[name] = sys.load(sys.get_save_file(p.app, name))
		end
		apps[p.app] = files
	end
	return { format = M.FORMAT, version = M.VERSION, app = id, date = notes_export.date(), apps = apps }
end

--- Saves a backup file of all the parts and opens the share sheet with it.
function M.export_set(id, parts)
	local file = id .. "-backup-" .. notes_export.date() .. ".json"
	return notes_export.export(id, file, json.encode(M.collect_set(id, parts)))
end

--- Restores a backup of the set, or of one app in it. `reader` is the app
--- whose "reader" file holds the reader's marks in the set (a game's own
--- backup kept them under the game's id). Returns true and the backup's
--- date, or nil and a message for the player.
function M.restore_set(id, parts, text, reader)
	local ok, t = pcall(json.decode, text or "")
	if not ok or type(t) ~= "table" or t.format ~= M.FORMAT then
		return nil, "This is not a backup file from these apps."
	end
	if (t.version or 0) > M.VERSION then
		return nil, "This backup file is from a newer version of the app."
	end
	local known = {}
	for _, p in ipairs(parts) do
		known[p.app] = true
	end
	local function put(app, name, values)
		if type(values) == "table" then
			sys.save(sys.get_save_file(app, name), values)
		end
	end
	if t.app == id and type(t.apps) == "table" then
		for app, files in pairs(t.apps) do
			if known[app] and type(files) == "table" then
				for name, values in pairs(files) do
					put(app, name, values)
				end
			end
		end
		return true, t.date
	elseif known[t.app] and type(t.files) == "table" then
		for name, values in pairs(t.files) do
			put(name == "reader" and reader or t.app, name, values)
		end
		return true, t.date
	end
	return nil, "This backup belongs to another app (" .. tostring(t.app) .. ")."
end

return M
