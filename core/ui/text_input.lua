-- A text field's contents and editing, for notes the player writes: an own
-- explanation of a riddle, a reflection after a practice. Pure Lua, so it
-- is tested in core/test/tests.lua; drawing and the keyboard are the
-- caller's (see core/ui/page.lua and the apps).
--
--   local text_input = require "core.ui.text_input"
--   local field = text_input.new({ max = 400, text = saved })
--   -- in on_input:
--   local changed, done = text_input.on_input(field, action_id, action)
--   gui.set_text(node, text_input.display(field, caret_on))
--
-- Typed text arrives through the "text" and "marked_text" actions of
-- Defold's builtin input binding (/builtins/input/all.input_binding), and
-- the phone's keyboard is opened with
-- gui.show_keyboard(gui.KEYBOARD_TYPE_DEFAULT, true). "marked_text" is a
-- word the keyboard is still composing (autocorrect, predictions): it is
-- shown but not yet part of the text.
--
-- Lengths are counted in characters (UTF-8 code points), not bytes.

local M = {}

local TEXT = hash("text")
local MARKED = hash("marked_text")
local BACKSPACE = hash("key_backspace")
local ENTER = hash("key_enter")
local NUMPAD_ENTER = hash("key_numpad_enter")

-- One UTF-8 character.
local CHAR = "[%z\1-\127\194-\244][\128-\191]*"

--- Number of characters in a UTF-8 string.
function M.length(s)
	local n = 0
	for _ in s:gmatch(CHAR) do
		n = n + 1
	end
	return n
end

--- The first n characters of a UTF-8 string.
function M.first(s, n)
	if n <= 0 then
		return ""
	end
	local count, stop = 0, #s
	for start, char in s:gmatch("()(" .. CHAR .. ")") do
		count = count + 1
		if count == n then
			stop = start + #char - 1
			break
		end
	end
	return s:sub(1, stop)
end

--- A new field. opts: max (characters, default 500), text (initial),
--- multiline (default true: Enter adds a line break; false: Enter is "done").
function M.new(opts)
	opts = opts or {}
	local field = {
		max = opts.max or 500,
		multiline = opts.multiline ~= false,
		text = "",
		marked = "",
	}
	M.insert(field, opts.text or "")
	return field
end

--- Cleans typed text: line breaks normalised (or turned into spaces in a
--- one-line field), other control characters dropped.
local function clean(field, s)
	s = s:gsub("\r\n?", "\n")
	if not field.multiline then
		s = s:gsub("\n", " ")
	end
	return (s:gsub("[%z\1-\9\11-\31\127]", ""))
end

--- Adds text at the end, cut to fit the field's maximum. Returns true if
--- anything was added.
function M.insert(field, s)
	s = clean(field, s)
	local room = field.max - M.length(field.text)
	if room <= 0 or s == "" then
		return false
	end
	field.text = field.text .. M.first(s, room)
	return true
end

--- Removes the last character. Returns true if anything was removed.
function M.backspace(field)
	if field.text == "" then
		return false
	end
	local last = field.text:match(CHAR .. "$") or field.text:sub(-1)
	field.text = field.text:sub(1, #field.text - #last)
	return true
end

--- The text without leading and trailing spaces or blank lines.
function M.value(field)
	return (field.text:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Characters left before the maximum.
function M.remaining(field)
	return field.max - M.length(field.text)
end

--- What to draw: the text, the word being composed, and a caret.
function M.display(field, caret)
	return field.text .. field.marked .. (caret and "|" or "")
end

--- Handles one input action. Returns changed, done: changed when the text
--- (or the composed word) changed, done when Enter was pressed in a
--- one-line field.
function M.on_input(field, action_id, action)
	if action_id == TEXT then
		field.marked = ""
		local typed = action.text or ""
		-- A keyboard may send Enter as a key, as a typed line break, or as
		-- both: one press must give one line break.
		if typed == "\n" or typed == "\r" then
			if field.enter_key then
				field.enter_key = false
				return false, false
			end
			field.enter_text = true
		else
			field.enter_key, field.enter_text = false, false
		end
		return M.insert(field, typed) or true, false
	elseif action_id == MARKED then
		field.marked = clean(field, action.text or "")
		return true, false
	elseif action_id == BACKSPACE and (action.pressed or action.repeated) then
		if field.marked ~= "" then
			-- the keyboard sends the shortened composed word itself
			return false, false
		end
		return M.backspace(field), false
	elseif (action_id == ENTER or action_id == NUMPAD_ENTER) and action.pressed then
		if not field.multiline then
			return false, true
		end
		if field.enter_text then
			field.enter_text = false
			return false, false
		end
		field.enter_key = true
		return M.insert(field, "\n"), false
	end
	return false, false
end

return M
