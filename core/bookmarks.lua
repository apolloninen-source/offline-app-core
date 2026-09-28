-- Where the reader left off, and the reader's bookmarks with notes. Pure
-- functions on a plain table kept in a save (see core/reader_ui/):
--
--   state = {
--     last  = { part, section, chunk },                 -- where reading stopped
--     marks = { { part, section, chunk, excerpt, note, day }, ... },
--   }
--
-- A place is a part, a section and a chunk: the reader cuts long paragraphs
-- into chunks, numbered from 1 through the whole section.

local M = {}

local function before(a, b)
	if a.part ~= b.part then
		return a.part < b.part
	elseif a.section ~= b.section then
		return a.section < b.section
	end
	return a.chunk < b.chunk
end

--- Remembers where reading stopped.
function M.set_last(state, part, section, chunk)
	state.last = { part = part, section = section, chunk = chunk or 1 }
end

--- The index of the bookmark at a place, or nil.
function M.find(state, part, section, chunk)
	for i, m in ipairs(state.marks or {}) do
		if m.part == part and m.section == section and m.chunk == chunk then
			return i
		end
	end
end

--- Adds a bookmark, or updates the note of the one already at that place.
--- The list stays in book order. Returns the bookmark.
function M.add(state, mark)
	state.marks = state.marks or {}
	local i = M.find(state, mark.part, mark.section, mark.chunk)
	if i then
		state.marks[i].note = mark.note
		return state.marks[i]
	end
	local pos = #state.marks + 1
	for j, m in ipairs(state.marks) do
		if before(mark, m) then
			pos = j
			break
		end
	end
	table.insert(state.marks, pos, mark)
	return mark
end

function M.remove(state, index)
	table.remove(state.marks, index)
end

--- The bookmarks in one section, by chunk number.
function M.in_section(state, part, section)
	local out = {}
	for _, m in ipairs(state.marks or {}) do
		if m.part == part and m.section == section then
			out[m.chunk] = m
		end
	end
	return out
end

--- The start of a text, cut at a word and marked with "…" if cut.
function M.excerpt(text, max_bytes)
	max_bytes = max_bytes or 90
	text = text:gsub("%s+", " "):gsub("^ ", "")
	-- the reader adds its own quotation marks around an excerpt
	local stripped
	repeat
		stripped = false
		for _, q in ipairs({ "“", "‘", "\"", "'" }) do
			if text:sub(1, #q) == q then
				text, stripped = text:sub(#q + 1), true
			end
		end
	until not stripped
	if #text <= max_bytes then
		return text
	end
	local cut = text:sub(1, max_bytes):match("^(.*) ") or text:sub(1, max_bytes)
	return cut:gsub("[%s,;:%.]+$", "") .. "…"
end

--- Bookmarks as entries for core.notes_export: place, excerpt, note.
function M.export_entries(state)
	local out = {}
	for _, m in ipairs(state.marks or {}) do
		local entry = { m.place or string.format("Part %d, section %d", m.part, m.section) }
		if m.excerpt and m.excerpt ~= "" then
			entry[#entry + 1] = "“" .. m.excerpt .. "”"
		end
		if m.note and m.note ~= "" then
			entry[#entry + 1] = "Note: " .. m.note
		end
		out[#out + 1] = entry
	end
	return out
end

return M
