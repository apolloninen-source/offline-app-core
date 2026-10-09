-- Text helpers for the reader screen: footnote marks as superscripts, and
-- long paragraphs cut into chunks at sentence ends. Pure functions, tested
-- in core/test/tests.lua.

local M = {}

local SUPERSCRIPT = { ["0"] = "⁰", ["1"] = "¹", ["2"] = "²", ["3"] = "³", ["4"] = "⁴",
	["5"] = "⁵", ["6"] = "⁶", ["7"] = "⁷", ["8"] = "⁸", ["9"] = "⁹" }

--- "96" -> "⁹⁶"
function M.superscript(digits)
	return (digits:gsub("%d", SUPERSCRIPT))
end

--- Replaces footnote markers with superscript numbers and lists the notes
--- the text refers to, in order: "water[^96] and" -> "water⁹⁶ and", { "96" }.
function M.render(paragraph)
	local notes = {}
	local text = paragraph:gsub("%[%^(%d+)%]", function(num)
		notes[#notes + 1] = num
		return M.superscript(num)
	end)
	return text, notes
end

-- Where a chunk may end: after sentence punctuation, optionally followed by
-- a closing quote or bracket, then a space.
local function sentence_end(text, from, to)
	local best
	local pos = from
	while true do
		local s, e = text:find("[%.!%?;:][\"'%)%]]*[’”]* ", pos)
		if not s or e > to then
			break
		end
		best = e
		pos = e + 1
	end
	return best
end

--- Splits a paragraph (with its raw markers) into pieces of about max_bytes,
--- breaking after a sentence where possible, else after a space. Short
--- paragraphs come back whole.
function M.chunks(paragraph, max_bytes)
	max_bytes = max_bytes or 700
	local out = {}
	local start = 1
	local len = #paragraph
	while len - start + 1 > max_bytes do
		local limit = start + max_bytes - 1
		local cut = sentence_end(paragraph, start + math.floor(max_bytes / 3), limit)
		if not cut then
			-- no sentence end in range: break at the last space
			local s = limit
			while s > start and paragraph:sub(s, s) ~= " " do
				s = s - 1
			end
			cut = s > start and s or limit
		end
		out[#out + 1] = paragraph:sub(start, cut):gsub("%s+$", "")
		start = cut + 1
		while paragraph:sub(start, start) == " " do
			start = start + 1
		end
	end
	if start <= len then
		local last = paragraph:sub(start):gsub("%s+$", "")
		if last ~= "" then
			out[#out + 1] = last
		end
	end
	return out
end

--- Splits a chunk into sentences, for highlighting: after . ! or ? (with
--- any closing quotes or brackets, and any footnote markers) followed by a
--- space. The spaces between sentences are dropped: table.concat(result,
--- " ") gives the chunk back (with runs of spaces as one).
function M.sentences(chunk)
	local out, start, pos = {}, 1, 1
	while true do
		local s = chunk:find("[%.!%?]", pos)
		if not s then
			break
		end
		-- the stop, its closing quotes and brackets, and footnote markers
		local e = s
		while true do
			local q = chunk:match("^[\"'%)%]]", e + 1) or chunk:match("^’", e + 1) or chunk:match("^”", e + 1)
				or chunk:match("^%[%^%d+%]", e + 1)
			if not q then
				break
			end
			e = e + #q
		end
		if chunk:sub(e + 1, e + 1):match("%s") then
			local piece = chunk:sub(start, e):gsub("^%s+", "")
			if piece ~= "" then
				out[#out + 1] = piece
			end
			start = e + 2
		end
		pos = e + 1
	end
	local rest = chunk:sub(start):gsub("^%s+", ""):gsub("%s+$", "")
	if rest ~= "" then
		out[#out + 1] = rest
	end
	return out
end

--- "#F3E9D2" -> vmath.vector4 colour (alpha optional as a 4th byte).
function M.color(hex)
	hex = hex:gsub("#", "")
	local r = tonumber(hex:sub(1, 2), 16) / 255
	local g = tonumber(hex:sub(3, 4), 16) / 255
	local b = tonumber(hex:sub(5, 6), 16) / 255
	local a = #hex >= 8 and tonumber(hex:sub(7, 8), 16) / 255 or 1
	return vmath.vector4(r, g, b, a)
end

return M
