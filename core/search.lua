-- Searching the reader's book: every place a word or phrase appears, with a
-- little context, part by part so it stays light on cheap phones (the
-- reader searches one part per frame and shows its progress).
--
--   local search = require "core.search"
--   local q = search.normalize(" Dharma ")          -- "dharma"
--   for each part: search.in_part(part, part_number, q, results, limit)
--
-- A result: { part, section, chunk, snippet }. `chunk` is the reader's
-- paragraph piece (core.reader_ui.text.chunks), so a result opens the text
-- right where the match is.

local text = require "core.reader_ui.text"

local M = {}

M.LIMIT = 300

local function plain(s)
	return (s:gsub("%[%^%d+%]", ""))
end

--- The query as searched: trimmed, one space between words, lower case.
--- Returns nil for a query too short to be useful.
function M.normalize(query)
	local q = (query or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""):lower()
	if #q < 2 then
		return nil
	end
	return q
end

--- A few words around position pos (a match of length len), cut at spaces
--- and marked with "…" where cut.
function M.snippet(s, pos, len, before, after)
	before, after = before or 70, after or 110
	local from = math.max(1, pos - before)
	local to = math.min(#s, pos + len + after)
	if from > 1 then
		local space = s:find(" ", from, true)
		from = (space and space < pos) and space + 1 or from
	end
	if to < #s then
		local cut = s:sub(1, to):match("^.*() ")
		to = (cut and cut > pos + len) and cut - 1 or to
	end
	return (from > 1 and "…" or "") .. s:sub(from, to) .. (to < #s and "…" or "")
end

--- The chunk number (in the whole section) of a match at byte `pos` of
--- paragraph `p` (in text without footnote markers).
function M.chunk_of(paras, p, pos)
	local n = 0
	for i = 1, p - 1 do
		n = n + #text.chunks(paras[i], 700)
	end
	local seen = 0
	for i, piece in ipairs(text.chunks(paras[p], 700)) do
		local len = #plain(piece)
		if pos <= seen + len + 1 then
			return n + i
		end
		seen = seen + len + 1 -- the space the cut removed
	end
	return n + 1
end

--- Adds the matches of query q in one part to results, at most limit in all
--- (one per paragraph, its first match). Returns true when the limit is hit.
function M.in_part(part, part_number, q, results, limit)
	limit = limit or M.LIMIT
	for s, section in ipairs(part.sections) do
		for p, para in ipairs(section.paras) do
			local body = plain(para)
			local pos = body:lower():find(q, 1, true)
			if pos then
				results[#results + 1] = {
					part = part_number, section = s,
					chunk = M.chunk_of(section.paras, p, pos),
					snippet = M.snippet(body, pos, #q),
				}
				if #results >= limit then
					return true
				end
			end
		end
	end
	return false
end

return M
