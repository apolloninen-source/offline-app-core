-- The reader's marks: where reading stopped, and one growing list of
-- bookmarks and highlights, each with an optional note (the player's own
-- annotation). Pure functions on a plain table kept in a save (see
-- core/reader_ui/):
--
--   state = {
--     last  = { part, section, chunk },   -- where reading stopped
--     marks = {                           -- in book order
--       { kind = "bookmark",  part, section, chunk, excerpt, place, note, day },
--       { kind = "highlight", part, section, chunk, from, to, quote, place, note, day },
--     },
--   }
--
-- A place is a part, a section and a chunk: the reader cuts long paragraphs
-- into chunks, numbered from 1 through the whole section. A highlight covers
-- sentences from..to of its chunk. Marks saved before highlights existed
-- have no kind: they are bookmarks.

local M = {}

function M.kind(m)
	return m.kind or "bookmark"
end

local function before(a, b)
	if a.part ~= b.part then
		return a.part < b.part
	elseif a.section ~= b.section then
		return a.section < b.section
	elseif a.chunk ~= b.chunk then
		return a.chunk < b.chunk
	end
	-- in one paragraph: the bookmark first, then highlights in text order
	return (a.from or 0) < (b.from or 0)
end

local function insert(state, mark)
	state.marks = state.marks or {}
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

--- Remembers where reading stopped.
function M.set_last(state, part, section, chunk)
	state.last = { part = part, section = section, chunk = chunk or 1 }
end

--- The index of the bookmark at a place, or nil.
function M.find(state, part, section, chunk)
	for i, m in ipairs(state.marks or {}) do
		if M.kind(m) == "bookmark" and m.part == part and m.section == section and m.chunk == chunk then
			return i
		end
	end
end

--- Adds a bookmark, or updates the note of the one already at that place.
--- Returns the bookmark.
function M.add(state, mark)
	local i = M.find(state, mark.part, mark.section, mark.chunk)
	if i then
		state.marks[i].note = mark.note
		return state.marks[i]
	end
	mark.kind = "bookmark"
	return insert(state, mark)
end

--- The text of sentences from..to, without footnote markers.
function M.quote(sentences, from, to)
	local parts = {}
	for i = from, to do
		parts[#parts + 1] = (sentences[i] or ""):gsub("%[%^%d+%]", "")
	end
	return (table.concat(parts, " "):gsub("%s+", " "))
end

--- Adds a highlight of sentences mark.from..mark.to in its chunk. A highlight
--- that overlaps or touches others in the same chunk joins them into one,
--- keeping their notes. `sentences` are the chunk's sentences (for the
--- quote). Returns the highlight.
function M.add_highlight(state, mark, sentences)
	state.marks = state.marks or {}
	local notes = {}
	if mark.note and mark.note ~= "" then
		notes[1] = mark.note
	end
	local i = 1
	while i <= #state.marks do
		local m = state.marks[i]
		if M.kind(m) == "highlight" and m.part == mark.part and m.section == mark.section
			and m.chunk == mark.chunk and m.from <= mark.to + 1 and m.to >= mark.from - 1 then
			mark.from = math.min(mark.from, m.from)
			mark.to = math.max(mark.to, m.to)
			if m.note and m.note ~= "" and m.note ~= notes[1] then
				notes[#notes + 1] = m.note
			end
			mark.day = mark.day or m.day
			table.remove(state.marks, i)
		else
			i = i + 1
		end
	end
	mark.kind = "highlight"
	mark.note = table.concat(notes, "\n\n")
	mark.quote = M.quote(sentences, mark.from, mark.to)
	return insert(state, mark)
end

--- The index of a mark in the list (by identity), or nil.
function M.index_of(state, mark)
	for i, m in ipairs(state.marks or {}) do
		if m == mark then
			return i
		end
	end
end

function M.remove(state, index)
	table.remove(state.marks, index)
end

--- The bookmarks in one section, by chunk number.
function M.in_section(state, part, section)
	local out = {}
	for _, m in ipairs(state.marks or {}) do
		if M.kind(m) == "bookmark" and m.part == part and m.section == section then
			out[m.chunk] = m
		end
	end
	return out
end

--- The highlights in one section: chunk number -> list in text order.
function M.highlights_in(state, part, section)
	local out = {}
	for _, m in ipairs(state.marks or {}) do
		if M.kind(m) == "highlight" and m.part == part and m.section == section then
			out[m.chunk] = out[m.chunk] or {}
			table.insert(out[m.chunk], m)
		end
	end
	return out
end

--- The highlight covering sentence n of a chunk, if any.
function M.highlight_at(list, n)
	for _, m in ipairs(list or {}) do
		if n >= m.from and n <= m.to then
			return m
		end
	end
end

M.FILTERS = { "all", "highlight", "bookmark", "annotated" }

--- The marks shown under a filter: "all", "highlight", "bookmark" or
--- "annotated" (with a note). Returns the marks, in book order.
function M.filter(state, which)
	local out = {}
	for _, m in ipairs(state.marks or {}) do
		if which == "all" or which == M.kind(m)
			or (which == "annotated" and m.note and m.note ~= "") then
			out[#out + 1] = m
		end
	end
	return out
end

--- How many marks a filter shows.
function M.count(state, which)
	return #M.filter(state, which)
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

local function place_of(m)
	return m.place or string.format("Part %d, section %d", m.part, m.section)
end

--- Marks as entries for core.notes_export: place, quote or excerpt, note.
function M.export_entries(state)
	local out = {}
	for _, m in ipairs(state.marks or {}) do
		local entry
		if M.kind(m) == "highlight" then
			entry = { place_of(m), "“" .. (m.quote or "") .. "”" }
		else
			entry = { "Bookmark: " .. place_of(m) }
			if m.excerpt and m.excerpt ~= "" then
				entry[#entry + 1] = "“" .. m.excerpt .. "”"
			end
		end
		if m.note and m.note ~= "" then
			entry[#entry + 1] = "Note: " .. m.note
		end
		out[#out + 1] = entry
	end
	return out
end

--- One highlight as a message to share: the quote, where it is, the note.
function M.share_text(m, book_title)
	local lines = { "“" .. (m.quote or m.excerpt or "") .. "”", "— " .. (book_title and (book_title .. ", ") or "") .. place_of(m) }
	if m.note and m.note ~= "" then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "My note: " .. m.note
	end
	return table.concat(lines, "\n")
end

return M
