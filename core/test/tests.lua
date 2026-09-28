-- Unit tests for the core, run inside the Defold engine:
--   dmengine --config=core.selftest=1 ./game.projectc   (see README)
-- Returns the number of failures.

local rng = require "core.rng"
local day = require "core.day"
local streak = require "core.streak"
local share = require "core.share"
local save = require "core.save"
local ads = require "core.ads"
local purchase = require "core.purchase"
local reader = require "core.reader"

local M = {}

local failures, passed = 0, 0

local function check(name, cond, detail)
	if cond then
		passed = passed + 1
	else
		failures = failures + 1
		print("FAIL: " .. name .. (detail and (" (" .. tostring(detail) .. ")") or ""))
	end
end

local function near(a, b)
	return math.abs(a - b) < 1e-9
end

local function test_rng()
	-- Values from tools/rng_reference.py
	check("fnv1a empty", rng.hash("") == 2166136261, rng.hash(""))
	check("fnv1a a", rng.hash("a") == 3826002220, rng.hash("a"))
	check("fnv1a yaksha", rng.hash("yaksha:20724") == 2725094681, rng.hash("yaksha:20724"))
	local g = rng.daily("yaksha", 20724)
	local want = { 0.961110831471, 0.324665984837, 0.226291638566, 0.933860970428, 0.9901127005 }
	for i, w in ipairs(want) do
		local v = g:next()
		check("mulberry32 daily #" .. i, near(math.floor(v * 1e12 + 0.5) / 1e12, w), v)
	end
	local z = rng.new(0)
	for i, w in ipairs({ 0.266429208685, 0.000329745701, 0.223272027448 }) do
		local v = z:next()
		check("mulberry32 zero #" .. i, near(math.floor(v * 1e12 + 0.5) / 1e12, w), v)
	end
	local a = rng.new("same"):shuffle({ 1, 2, 3, 4, 5, 6, 7, 8 })
	local b = rng.new("same"):shuffle({ 1, 2, 3, 4, 5, 6, 7, 8 })
	check("shuffle repeatable", table.concat(a, ",") == table.concat(b, ","))
	local r = rng.new(7)
	local ok = true
	for _ = 1, 1000 do
		local n = r:int(3, 5)
		ok = ok and n >= 3 and n <= 5 and n == math.floor(n)
	end
	check("int in range", ok)
end

local function test_day()
	check("epoch", day.from_date(1970, 1, 1) == 0)
	check("2000-03-01", day.from_date(2000, 3, 1) == 11017)
	check("2024-02-29", day.from_date(2024, 2, 29) == 19782)
	check("2026-09-28", day.from_date(2026, 9, 28) == 20724)
	local ok = true
	for n = -1000, 30000, 7 do
		local y, m, d = day.to_date(n)
		ok = ok and day.from_date(y, m, d) == n
	end
	check("round trip", ok)
	day.set_clock(function() return { year = 2026, month = 9, day = 28 } end)
	check("today", day.today() == 20724)
	day.set_clock(nil)
	check("challenge number", day.challenge_number(20724, 20700) == 25)
end

local function test_streak()
	local s = {}
	streak.record(s, 100)
	check("first day", s.current == 1 and s.best == 1 and s.days == 1)
	streak.record(s, 100)
	check("same day once", s.current == 1 and s.days == 1)
	streak.record(s, 101); streak.record(s, 102)
	check("three in a row", s.current == 3 and s.best == 3)
	check("alive next day", streak.current(s, 103) == 3)
	check("broken after gap", streak.current(s, 104) == 0)
	streak.record(s, 105)
	check("restart", s.current == 1 and s.best == 3 and s.days == 4)
	check("played today", streak.played_today(s, 105) and not streak.played_today(s, 106))
end

local function test_share()
	check("encode", share.url_encode("a b&c") == "a%20b%26c", share.url_encode("a b&c"))
	check("encode utf8", share.url_encode("é") == "%C3%A9", share.url_encode("é"))
	check("url", share.whatsapp_url("hi there") == "https://wa.me/?text=hi%20there")
	check("squares", share.squares({ true, false, true }) == "🟩⬛🟩")
	check("text", share.text({ "a", "b" }) == "a\nb")
end

local function test_ads_and_purchase()
	check("app open due", ads.should_show_app_open({}, 10, false))
	check("app open once a day", not ads.should_show_app_open({ last_app_open_day = 10 }, 10, false))
	check("app open next day", ads.should_show_app_open({ last_app_open_day = 10 }, 11, false))
	check("interstitial once a day", not ads.should_show_interstitial({ last_interstitial_day = 10 }, 10, false))
	check("no ads when removed", not ads.should_show_app_open({}, 10, true)
		and not ads.should_show_interstitial({}, 10, true))

	local data = save.open("offline-app-core-test", { ads = {} })
	data:reset()
	ads.init(data, {})
	purchase.init(data, "remove_ads")
	check("not removed at start", not ads.removed() and not purchase.owned())
	purchase._grant()
	check("removed after purchase", ads.removed() and purchase.owned())
	check("no interstitial without admob", ads.on_game_start() == false)
end

local function test_save()
	local data = save.open("offline-app-core-test", { streak = { best = 0 }, name = "x" })
	data:reset()
	data.values.streak.best = 7
	data.values.extra = { list = { 1, 2, 3 } }
	check("write", data:write())
	local again = save.open("offline-app-core-test", { streak = { best = 0, current = 0 }, name = "x", added = true })
	check("read back", again.values.streak.best == 7 and again.values.extra.list[3] == 3)
	check("new defaults filled", again.values.added == true and again.values.streak.current == 0)
	check("version", again.values.version == 1)
end

local function test_reader()
	local book = reader.open("/core/test/fixture/")
	check("index", book:index().title == "Test Book" and #book:index().parts == 1)
	check("section", book:section(1, 2).label == "II")
	local p = reader.pieces("They touched water[^1] and rested.")
	check("pieces", #p == 3 and p[1].text == "They touched water" and p[2].note == "1" and p[3].text == " and rested.")
	local ok, summary = pcall(function() return book:selftest() end)
	check("selftest", ok and summary == "reader ok: 1 parts, 2 sections, 1 footnotes", summary)
end

function M.run()
	failures, passed = 0, 0
	test_rng()
	test_day()
	test_streak()
	test_share()
	test_ads_and_purchase()
	test_save()
	test_reader()
	print(string.format("core tests: %d passed, %d failed", passed, failures))
	return failures
end

return M
