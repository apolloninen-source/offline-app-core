-- "Export notes": the player's notes (readings, bookmarks, reflections) as
-- one plain .txt file they can keep outside the app.
--
--   local notes_export = require "core.notes_export"
--   local txt = notes_export.text("Yaksha's Riddles: my notes", {
--       { heading = "Readings", entries = { { "line", "line" }, ... } },
--       { heading = "Bookmarks", entries = ... },
--   })
--   local path, shared = notes_export.export("yaksha", "yaksha-notes.txt", txt)
--
-- The file is written in the app's own save folder. Android does not let an
-- app write into the player's Downloads folder, so when the Sharing
-- extension is in the project (https://github.com/britzl/defold-sharing,
-- global `share`) the phone's share sheet opens with the file, and the
-- player chooses where it goes (Files, Drive, email, a chat). Without the
-- extension (desktop builds) the file is only written. The extension is a
-- native one: add it with the other extensions for release builds.

local M = {}

--- Today as YYYY-MM-DD, for file names and the export header.
function M.date(t)
	t = t or os.date("*t")
	return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

--- The whole export as text. groups: { heading, entries = { {lines}, ... } };
--- empty groups are left out.
function M.text(title, groups, date)
	local out = { title, "Exported " .. (date or M.date()), "" }
	for _, g in ipairs(groups) do
		if #g.entries > 0 then
			out[#out + 1] = ""
			out[#out + 1] = g.heading:upper()
			out[#out + 1] = ""
			for _, entry in ipairs(g.entries) do
				for _, line in ipairs(entry) do
					out[#out + 1] = line
				end
				out[#out + 1] = ""
			end
		end
	end
	return table.concat(out, "\n")
end

--- Writes the text to the app's save folder. Returns the full path, or nil
--- and an error.
function M.write(app_id, file_name, text)
	local path = sys.get_save_file(app_id, file_name)
	local f, err = io.open(path, "wb")
	if not f then
		return nil, err
	end
	f:write(text)
	f:close()
	return path
end

--- Writes the file and, where the Sharing extension exists, opens the share
--- sheet with it. Returns path (or nil, error) and whether it was shared.
function M.export(app_id, file_name, text)
	local path, err = M.write(app_id, file_name, text)
	if not path then
		return nil, err
	end
	-- the extension's global; apps often have a local `share` (core.share)
	local sharing = rawget(_G, "share")
	if type(sharing) == "table" and sharing.file then
		sharing.file(path, file_name)
		return path, true
	end
	return path, false
end

return M
