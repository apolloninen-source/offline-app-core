-- Offline reader for a long text split into parts and sections, such as the
-- Mahabharata (18 Parvas) or the Ramayana (6 books). Moved here from
-- games-of-dharma so every app can use it.
--
-- Data layout, as written by the apps' splitter tools and bundled through
-- project.custom_resources:
--   <dir>/index.json    { title, parts = [ { number, name, file, sections } ] }
--                       ("parvas" is accepted as another name for "parts")
--   <dir>/<file>        { number, name, sections = [ { n, label, sub, paras, notes } ] }
-- A paragraph marks footnotes as "[^N]"; notes are in the section's notes table.
--
--   local reader = require "core.reader"
--   local book = reader.open("/shared/reader/data/")
--   book:index().parts, book:part(3), book:section(3, 12), reader.pieces(para)

local M = {}

--- Opens a book stored under dir (a resource path ending in "/").
function M.open(dir)
	local book = { dir = dir }
	-- Only one part is kept in memory at a time: some parts are several MB of
	-- text, and the target phones have 2 GB of RAM.
	local index, cached_number, cached_part

	local function load_json(name)
		local raw = sys.load_resource(dir .. name)
		assert(raw, "reader data missing: " .. dir .. name)
		return json.decode(raw)
	end

	--- Title, preface and the list of parts.
	function book:index()
		if not index then
			index = load_json("index.json")
			index.parts = index.parts or index.parvas
		end
		return index
	end

	--- One part, loaded on demand.
	function book:part(number)
		if cached_number ~= number then
			local entry = self:index().parts[number]
			assert(entry, "no part " .. tostring(number))
			cached_part = load_json(entry.file)
			cached_number = number
		end
		return cached_part
	end

	function book:section(part_number, n)
		return self:part(part_number).sections[n]
	end

	--- Loads every part and checks it against the index; returns a summary
	--- line or raises an error naming the first problem.
	function book:selftest()
		local idx = self:index()
		local sections, notes = 0, 0
		for _, entry in ipairs(idx.parts) do
			local part = self:part(entry.number)
			assert(#part.sections == entry.sections, entry.name .. ": section count differs from index")
			for _, section in ipairs(part.sections) do
				assert(#section.paras > 0, entry.name .. " section " .. section.label .. " is empty")
				for _, para in ipairs(section.paras) do
					for _, piece in ipairs(M.pieces(para)) do
						if piece.note then
							assert(section.notes[piece.note],
								entry.name .. " section " .. section.label .. ": note " .. piece.note .. " missing")
							notes = notes + 1
						end
					end
				end
			end
			sections = sections + #part.sections
		end
		return string.format("reader ok: %d parts, %d sections, %d footnotes", #idx.parts, sections, notes)
	end

	return book
end

--- Splits a paragraph at its footnote markers: "water[^96] and" ->
--- { { text = "water" }, { note = "96" }, { text = " and" } }.
function M.pieces(paragraph)
	local out, pos = {}, 1
	for s, num, e in paragraph:gmatch("()%[%^(%d+)%]()") do
		if s > pos then
			out[#out + 1] = { text = paragraph:sub(pos, s - 1) }
		end
		out[#out + 1] = { note = num }
		pos = e
	end
	if pos <= #paragraph then
		out[#out + 1] = { text = paragraph:sub(pos) }
	end
	return out
end

return M
