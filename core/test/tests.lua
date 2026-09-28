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
local text = require "core.reader_ui.text"
local text_input = require "core.ui.text_input"
local page = require "core.ui.page"
local note_editor = require "core.ui.note_editor"
local bookmarks = require "core.bookmarks"
local notes_export = require "core.notes_export"

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

local function test_reader_text()
	check("superscript", text.superscript("96") == "⁹⁶")
	local shown, notes = text.render("water[^96] and fire[^97].")
	check("render", shown == "water⁹⁶ and fire⁹⁷." and #notes == 2 and notes[2] == "97", shown)
	check("short stays whole", #text.chunks("One sentence.", 700) == 1)
	local long = string.rep("This is a sentence of some length. ", 60)
	local pieces = text.chunks(long, 300)
	local ok = #pieces > 1
	for _, p in ipairs(pieces) do
		ok = ok and #p <= 300 and p:sub(-1) == "."
	end
	check("chunks end at sentences", ok, #pieces)
	check("chunks keep all text", table.concat(pieces, " ") == long:gsub("%s+$", ""))
	local nospace = string.rep("x", 1000)
	local hard = text.chunks(nospace, 300)
	check("chunks without spaces", #hard == 4 and table.concat(hard) == nospace, #hard)
	local marked = text.chunks("First part[^1] here. " .. string.rep("more words ", 80), 200)
	check("markers stay in their chunk", marked[1]:find("%[%^1%]") ~= nil)
	local c = text.color("#FF8000")
	check("color", math.abs(c.x - 1) < 1e-6 and math.abs(c.y - 128 / 255) < 1e-6 and c.z == 0 and c.w == 1)
end

local function test_text_input()
	check("page module loads", type(page.new) == "function")
	check("utf8 length", text_input.length("aé€😀") == 4, text_input.length("aé€😀"))
	check("utf8 first", text_input.first("aé€😀", 3) == "aé€" and text_input.first("ab", 5) == "ab")
	local f = text_input.new({ max = 5 })
	text_input.insert(f, "héllo world")
	check("insert cuts at max", f.text == "héllo", f.text)
	check("full field refuses", text_input.insert(f, "x") == false and text_input.remaining(f) == 0)
	text_input.backspace(f)
	text_input.backspace(f)
	text_input.backspace(f)
	text_input.backspace(f)
	check("backspace removes whole characters", f.text == "h", f.text)
	text_input.backspace(f)
	check("backspace on empty", text_input.backspace(f) == false and f.text == "")

	local g = text_input.new({ text = "  Line\r\ntwo\t " })
	check("cleans control characters", g.text == "  Line\ntwo ", g.text)
	check("value trims", text_input.value(g) == "Line\ntwo", text_input.value(g))
	local one = text_input.new({ multiline = false, text = "a\nb" })
	check("one-line field", one.text == "a b", one.text)

	local TEXT, MARKED = hash("text"), hash("marked_text")
	local h = text_input.new({ max = 100 })
	text_input.on_input(h, TEXT, { text = "The mind" })
	text_input.on_input(h, MARKED, { text = " is flee" })
	check("composing shown, not kept", text_input.display(h, true) == "The mind is flee|" and h.text == "The mind")
	text_input.on_input(h, TEXT, { text = " is fleeter" })
	check("composed word committed", h.text == "The mind is fleeter" and h.marked == "", h.text)
	text_input.on_input(h, hash("key_backspace"), { pressed = true })
	check("backspace action", h.text == "The mind is fleete", h.text)
	text_input.on_input(h, hash("key_enter"), { pressed = true })
	check("enter adds a line", h.text:sub(-1) == "\n")
	local n = #h.text
	text_input.on_input(h, TEXT, { text = "\n" })
	check("enter as key then text: one line break", #h.text == n, #h.text - n)
	text_input.on_input(h, TEXT, { text = "x" })
	text_input.on_input(h, TEXT, { text = "\n" })
	text_input.on_input(h, hash("key_enter"), { pressed = true })
	check("enter as text then key: one line break", h.text:sub(-2) == "x\n", h.text:sub(-3))
	local _, done = text_input.on_input(one, hash("key_enter"), { pressed = true })
	check("enter finishes a one-line field", done == true)
end

local function test_bookmarks()
	check("note editor module loads", type(note_editor.open) == "function")
	local st = { marks = {} }
	bookmarks.set_last(st, 3, 311, 4)
	check("last place", st.last.part == 3 and st.last.section == 311 and st.last.chunk == 4)
	bookmarks.add(st, { part = 5, section = 2, chunk = 1, note = "b" })
	bookmarks.add(st, { part = 3, section = 311, chunk = 7, note = "a" })
	bookmarks.add(st, { part = 3, section = 311, chunk = 2, note = "" })
	check("marks in book order", st.marks[1].chunk == 2 and st.marks[2].chunk == 7 and st.marks[3].part == 5)
	bookmarks.add(st, { part = 3, section = 311, chunk = 7, note = "changed" })
	check("same place updates the note", #st.marks == 3 and st.marks[2].note == "changed")
	local here = bookmarks.in_section(st, 3, 311)
	check("marks in a section", here[2] ~= nil and here[7] ~= nil and here[1] == nil)
	check("find", bookmarks.find(st, 5, 2, 1) == 3 and bookmarks.find(st, 5, 2, 9) == nil)
	bookmarks.remove(st, 1)
	check("remove", #st.marks == 2 and st.marks[1].chunk == 7)
	check("excerpt drops opening quotes", bookmarks.excerpt("“‘Never do, O Karna", 90) == "Never do, O Karna")
	check("short excerpt whole", bookmarks.excerpt("Day after day.", 90) == "Day after day.")
	local ex = bookmarks.excerpt("Day after day countless creatures are going to the abode of Yama, yet those", 40)
	check("excerpt cut at a word", ex == "Day after day countless creatures are…", ex)
end

local function test_notes_export()
	check("export date", notes_export.date({ year = 2026, month = 9, day = 8 }) == "2026-09-08")
	local st = { marks = {} }
	bookmarks.add(st, { part = 3, section = 311, chunk = 2, place = "Vana Parva · Section CCCXI",
		excerpt = "Day after day", note = "Read again" })
	bookmarks.add(st, { part = 1, section = 1, chunk = 1, excerpt = "", note = "" })
	local entries = bookmarks.export_entries(st)
	check("bookmark entries", #entries == 2 and entries[1][1] == "Part 1, section 1" and #entries[1] == 1
		and entries[2][3] == "Note: Read again", entries[1][1])
	local txt = notes_export.text("My notes", {
		{ heading = "Readings", entries = { { "Q", "A" } } },
		{ heading = "Empty", entries = {} },
		{ heading = "Bookmarks", entries = entries },
	}, "2026-09-28")
	check("export text", txt:find("My notes\nExported 2026-09-28", 1, true) ~= nil
		and txt:find("READINGS\n\nQ\nA\n", 1, true) ~= nil and txt:find("EMPTY", 1, true) == nil
		and txt:find("BOOKMARKS", 1, true) ~= nil)
	local path = notes_export.write("offline-app-core-test", "notes-test.txt", txt)
	local f = path and io.open(path, "rb")
	local back = f and f:read("*a")
	if f then f:close() end
	check("export file written", back == txt, path)
	local _, shared = notes_export.export("offline-app-core-test", "notes-test.txt", txt)
	check("no sharing extension on desktop", shared == false)
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
	test_reader_text()
	test_text_input()
	test_bookmarks()
	test_notes_export()
	print(string.format("core tests: %d passed, %d failed", passed, failures))
	return failures
end

return M
