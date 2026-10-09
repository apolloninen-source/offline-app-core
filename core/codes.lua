-- Short codes people can read aloud, type or paste: a few numbers packed
-- into letters and digits (Crockford's base 32: no I, L, O or U, so nothing
-- is mistaken for 1 or 0), with a checksum that catches typing mistakes.
-- No server: a code carries everything it means.
--
--   local codes = require "core.codes"
--   local code = codes.encode("YR", { { 2, 1 }, { 14, 1307 } })   -- { bits, value } pairs
--   -- "YR-0A3K-7M"  (grouped by four)
--   local reader, err = codes.decode("YR", code)                  -- err: "typo" or "other"
--   reader:take(2), reader:take(14)                                 --> 1, 1307

local rng = require "core.rng"

local M = {}

local ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
local VALUE = {}
for i = 1, #ALPHABET do
	VALUE[ALPHABET:sub(i, i)] = i - 1
end
-- what people type by mistake reads as what they meant
VALUE["O"], VALUE["I"], VALUE["L"] = 0, 1, 1

local function checksum(body)
	return rng.hash(body) % 1024
end

local function to_chars(bits)
	local out = {}
	for i = 1, #bits, 5 do
		local v = 0
		for j = 0, 4 do
			v = v * 2 + (bits[i + j] or 0)
		end
		out[#out + 1] = ALPHABET:sub(v + 1, v + 1)
	end
	return table.concat(out)
end

local function group(s)
	local out = {}
	for i = 1, #s, 4 do
		out[#out + 1] = s:sub(i, i + 3)
	end
	return table.concat(out, "-")
end

--- A code from { bits, value } fields (values must fit their bits).
function M.encode(prefix, fields)
	local bits = {}
	for _, f in ipairs(fields) do
		local n, v = f[1], f[2]
		assert(v >= 0 and v < 2 ^ n, "value does not fit its bits")
		for i = n - 1, 0, -1 do
			bits[#bits + 1] = math.floor(v / 2 ^ i) % 2
		end
	end
	local body = to_chars(bits)
	local sum = checksum(body)
	body = body .. ALPHABET:sub(math.floor(sum / 32) + 1, math.floor(sum / 32) + 1) .. ALPHABET:sub(sum % 32 + 1, sum % 32 + 1)
	return prefix .. "-" .. group(body)
end

--- Reads a code back. Returns a reader with :take(bits) and :left(), or
--- nil and "other" (not this kind of code) or "typo" (checksum wrong).
function M.decode(prefix, code)
	local s = (code or ""):upper():gsub("[%s%-]", "")
	if s:sub(1, #prefix) ~= prefix:upper() then
		return nil, "other"
	end
	s = s:sub(#prefix + 1)
	if #s < 3 then
		return nil, "typo"
	end
	local chars = {}
	for i = 1, #s do
		local v = VALUE[s:sub(i, i)]
		if not v then
			return nil, "typo"
		end
		chars[i] = ALPHABET:sub(v + 1, v + 1)
	end
	local body = table.concat(chars, "", 1, #chars - 2)
	local sum = VALUE[chars[#chars - 1]] * 32 + VALUE[chars[#chars]]
	if checksum(body) ~= sum then
		return nil, "typo"
	end
	local bits = {}
	for i = 1, #body do
		local v = VALUE[body:sub(i, i)]
		for j = 4, 0, -1 do
			bits[#bits + 1] = math.floor(v / 2 ^ j) % 2
		end
	end
	local pos = 0
	local reader = {}
	function reader:take(n)
		local v = 0
		for _ = 1, n do
			pos = pos + 1
			v = v * 2 + (bits[pos] or 0)
		end
		return v
	end
	function reader:left()
		return #bits - pos
	end
	return reader
end

return M
