-- Deterministic random numbers: the same seed gives the same sequence on
-- every phone and every platform, so a daily challenge is the same for
-- everyone. Never use math.random for anything that must match across
-- players.
--
-- FNV-1a (32 bit) turns a string into a seed; mulberry32 generates numbers.
-- tools/rng_reference.py is the reference implementation; the tests compare
-- against it.

local bit = bit or require("bit")

local M = {}

local TWO32 = 4294967296

-- 32-bit multiply that stays exact in doubles: split into 16-bit halves.
local function imul(a, b)
	a = a % TWO32
	b = b % TWO32
	local ah, al = math.floor(a / 65536), a % 65536
	local bh, bl = math.floor(b / 65536), b % 65536
	return bit.tobit(((ah * bl + al * bh) % 65536) * 65536 + al * bl)
end

--- FNV-1a hash of a string, as an unsigned 32-bit number.
function M.hash(text)
	local h = 2166136261
	for i = 1, #text do
		h = imul(bit.bxor(h, text:byte(i)), 16777619)
	end
	return h % TWO32
end

--- A generator seeded with a number or a string.
--- gen:next() returns a float in [0, 1).
function M.new(seed)
	if type(seed) == "string" then
		seed = M.hash(seed)
	end
	local gen = { state = bit.tobit(seed % TWO32) }

	function gen:next()
		self.state = bit.tobit(self.state + 0x6D2B79F5)
		local a = self.state
		local t = imul(bit.bxor(a, bit.rshift(a, 15)), bit.bor(1, a))
		t = bit.bxor(bit.tobit(t + imul(bit.bxor(t, bit.rshift(t, 7)), bit.bor(61, t))), t)
		return (bit.bxor(t, bit.rshift(t, 14)) % TWO32) / TWO32
	end

	--- An integer in [lo, hi].
	function gen:int(lo, hi)
		return lo + math.floor(self:next() * (hi - lo + 1))
	end

	--- One element of a list.
	function gen:pick(list)
		return list[self:int(1, #list)]
	end

	--- A shuffled copy of a list (Fisher-Yates).
	function gen:shuffle(list)
		local out = {}
		for i = 1, #list do
			out[i] = list[i]
		end
		for i = #out, 2, -1 do
			local j = self:int(1, i)
			out[i], out[j] = out[j], out[i]
		end
		return out
	end

	return gen
end

--- The generator for one app's challenge on one day, e.g. daily("yaksha", 20724).
function M.daily(app_key, day)
	return M.new(app_key .. ":" .. tostring(day))
end

return M
