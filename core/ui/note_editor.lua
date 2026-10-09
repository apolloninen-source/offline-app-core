-- A full-screen editor for a short note: a riddle reading, a bookmark's
-- note, a reflection. It sits high on the screen, above where the phone's
-- keyboard opens, and keeps the end of a long note in view.
--
--   local note_editor = require "core.ui.note_editor"
--   self.editor = note_editor.open({
--       width = 720, height = 1280, header = 150, parent = root_node,
--       title = "Your reading", prompt = "What is fleeter than the wind?",
--       text = saved_text, max = 400,
--       colors = { panel = ..., field = ..., ink = ..., muted = ..., accent = ... },
--   })
--   -- in update:   note_editor.update(self.editor, dt)
--   -- in on_input: local result = note_editor.on_input(self.editor, action_id, action)
--   --              result is nil while writing, "done" or "cancel" at the end:
--   --              then read note_editor.value(self.editor) and note_editor.close(self.editor)
--
-- "Done" (top right) and the Android back key keep the note; "‹ Cancel"
-- (top left) drops the changes. The gui scene needs the fonts "body" and
-- "title" (core/fonts/).

local text_input = require "core.ui.text_input"

local M = {}

local TOUCH = hash("mouse_button_left")
local BACK = hash("key_back")
local MARGIN = 44

local function measure(e, font, str, width)
	e.fonts[font] = e.fonts[font] or gui.get_font_resource(font)
	return resource.get_text_metrics(e.fonts[font], str,
		{ width = width, leading = 1.15, line_break = width > 0 })
end

local function layout(e)
	gui.set_text(e.text, text_input.display(e.field, e.caret))
	local left = text_input.remaining(e.field)
	gui.set_text(e.counter, left < 60 and (left .. " left") or "")
	local h = measure(e, "body", text_input.display(e.field, true), e.text_w).height * e.scale
	local over = math.max(0, h - e.box_h + 40)
	gui.set_position(e.text, vmath.vector3(-e.text_w * e.scale / 2, e.box_h / 2 - 20 + over, 0))
end

--- Opens the editor and the phone's keyboard. Returns the editor.
function M.open(o)
	local W, H = o.width, o.height
	local header = o.header or 150
	local c = o.colors
	local e = {
		field = text_input.new({ max = o.max or 400, text = o.text or "" }),
		caret = true, blink = 0, scale = 0.9, fonts = {}, width = W, height = H, header = header,
	}
	e.panel = gui.new_box_node(vmath.vector3(W / 2, H / 2, 0), vmath.vector3(W, H, 0))
	gui.set_color(e.panel, c.panel)
	if o.parent then
		gui.set_parent(e.panel, o.parent)
	end

	local function add_text(str, font, x, y, pivot, tint, scale, width)
		local node = gui.new_text_node(vmath.vector3(x - W / 2, y - H / 2, 0), str)
		gui.set_font(node, font)
		gui.set_pivot(node, pivot)
		gui.set_color(node, tint)
		gui.set_inherit_alpha(node, false)
		if width then
			gui.set_line_break(node, true)
			gui.set_size(node, vmath.vector3(width / (scale or 1), 0, 0))
		end
		if scale then
			gui.set_scale(node, vmath.vector3(scale, scale, 1))
		end
		gui.set_parent(node, e.panel)
		return node
	end
	add_text(o.title or "Note", "title", MARGIN, H - 78, gui.PIVOT_NW, c.ink)
	add_text("Done", "body", W - MARGIN, H - 34, gui.PIVOT_NE, c.accent)
	add_text("‹ Cancel", "body", MARGIN, H - 34, gui.PIVOT_NW, c.muted)
	local qh = 0
	if o.prompt and o.prompt ~= "" then
		add_text(o.prompt, "body", MARGIN, H - header - 20, gui.PIVOT_NW, c.muted, 0.85, W - 2 * MARGIN)
		qh = measure(e, "body", o.prompt, (W - 2 * MARGIN) / 0.85).height * 0.85
	end

	-- the box sits high, above where the phone's keyboard opens
	local top = H - header - 40 - qh
	e.box_h = math.max(160, math.min(400, top - 700))
	local box = gui.new_box_node(vmath.vector3(0, top - e.box_h / 2 - H / 2, 0),
		vmath.vector3(W - 2 * MARGIN, e.box_h, 0))
	gui.set_color(box, c.field)
	gui.set_inherit_alpha(box, false)
	gui.set_clipping_mode(box, gui.CLIPPING_MODE_STENCIL)
	gui.set_parent(box, e.panel)
	e.box_top = top
	e.text_w = (W - 2 * MARGIN - 40) / e.scale
	e.text = gui.new_text_node(vmath.vector3(0, 0, 0), "")
	gui.set_font(e.text, "body")
	gui.set_pivot(e.text, gui.PIVOT_NW)
	gui.set_line_break(e.text, true)
	gui.set_size(e.text, vmath.vector3(e.text_w, 0, 0))
	gui.set_leading(e.text, 1.15)
	gui.set_scale(e.text, vmath.vector3(e.scale, e.scale, 1))
	gui.set_color(e.text, c.ink)
	gui.set_inherit_alpha(e.text, false)
	gui.set_parent(e.text, box)
	e.counter = add_text("", "body", W - MARGIN, top - e.box_h - 12, gui.PIVOT_NE, c.muted, 0.8)
	layout(e)
	gui.show_keyboard(gui.KEYBOARD_TYPE_DEFAULT, true)
	return e
end

--- Blinks the caret. Call from update().
function M.update(e, dt)
	e.blink = e.blink + dt
	if e.blink > 0.55 then
		e.blink = 0
		e.caret = not e.caret
		layout(e)
	end
end

--- Handles input; returns nil while writing, "done" or "cancel".
function M.on_input(e, action_id, action)
	if action_id == BACK and action.released then
		return "done"
	elseif action_id == TOUCH then
		if action.released then
			if action.y > e.height - e.header then
				return action.x > e.width / 2 and "done" or "cancel"
			elseif action.y < e.box_top and action.y > e.box_top - e.box_h then
				-- the keyboard may have been put away: bring it back
				gui.show_keyboard(gui.KEYBOARD_TYPE_DEFAULT, true)
			end
		end
	elseif text_input.on_input(e.field, action_id, action) then
		e.caret, e.blink = true, 0
		layout(e)
	end
	return nil
end

--- The note as written, trimmed ("" when empty).
function M.value(e)
	return text_input.value(e.field)
end

--- Removes the editor and puts the keyboard away.
function M.close(e)
	gui.hide_keyboard()
	gui.delete_node(e.panel)
end

return M
