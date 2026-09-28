-- A scrolling page of text, buttons and panels for app screens, inside a
-- gui_script. The first piece of the UI kit: plain layout and touch
-- handling only. Each app gives it its own colours and fonts.
--
--   local page = require "core.ui.page"
--   self.page = page.new({ width = 720, height = 1280, top = 170,
--                          ink = vmath.vector4(0, 0, 0, 1) })
--   self.page:clear()
--   self.page:text("A question?", { font = "title", align = "center" })
--   self.page:button("An answer", function() ... end, { fill = ..., color = ... })
--   self.page:done()                       -- after adding everything
--   -- in on_input: if self.page:on_input(action_id, action) then return true end
--
-- The gui scene needs the fonts it names ("body" and "title" by default;
-- /core/fonts/ has both). Items are placed top to bottom; the page scrolls
-- when they do not fit between `top` and `bottom`. Only items on screen
-- (or nearly) are drawn.

local M = {}

local Page = {}
Page.__index = Page

local TOUCH = hash("mouse_button_left")
local WHEEL_UP = hash("mouse_wheel_up")
local WHEEL_DOWN = hash("mouse_wheel_down")
local TAP_SLOP = 14

--- A new page. opts: width, height (the display), top and bottom (space
--- kept free for a header or a bar), margin, gap, ink (default text
--- colour), fonts = { body, title }, parent (a node to put the page under),
--- below (a node the page must stay under, such as a header: nodes created
--- later are drawn on top, and the page recreates its nodes on clear()).
function M.new(opts)
	local self = setmetatable({}, Page)
	self.width = opts.width
	self.height = opts.height
	self.top = opts.top or 0
	self.bottom = opts.bottom or 0
	self.margin = opts.margin or 44
	self.gap = opts.gap or 22
	self.ink = opts.ink or vmath.vector4(0, 0, 0, 1)
	self.fonts = opts.fonts or { body = "body", title = "title" }
	self.parent = opts.parent
	self.below = opts.below
	self.font_res = {}
	self.items = {}
	self:clear()
	return self
end

--- Size of a text in a font, with line breaks at `width` (0 = one line).
function Page:measure(font, str, width, leading)
	self.font_res[font] = self.font_res[font] or gui.get_font_resource(font)
	return resource.get_text_metrics(self.font_res[font], str,
		{ width = width or 0, leading = leading or 1.15, line_break = (width or 0) > 0 })
end

function Page:viewport()
	return self.height - self.top - self.bottom
end

--- Removes everything and scrolls back to the top.
function Page:clear()
	if self.content then
		gui.delete_node(self.content)
	end
	self.content = gui.new_box_node(vmath.vector3(0, 0, 0), vmath.vector3(0, 0, 0))
	if self.parent then
		gui.set_parent(self.content, self.parent)
	end
	if self.below then
		gui.move_below(self.content, self.below)
	end
	self.items = {}
	self.cursor = 24
	self.scroll = 0
	self:set_scroll(0)
end

-- Places a node whose top edge is at the cursor. anchor = "top" (pivot N
-- or NW nodes) or "center" (pivot CENTER nodes).
function Page:place(node, x, h, o, anchor, x0, x1)
	local top = -self.cursor - (o.space_before or 0)
	local y = anchor == "center" and top - h / 2 or top
	gui.set_position(node, vmath.vector3(x, y, 0))
	gui.set_parent(node, self.content)
	local item = { node = node, top = top, height = h, on_tap = o.on_tap,
		x0 = x0 or 0, x1 = x1 or self.width, enabled = true }
	self.items[#self.items + 1] = item
	self.cursor = -top + h + (o.space_after or self.gap)
	return item
end

local function text_node(self, str, font, color, width, scale, align, leading)
	local node = gui.new_text_node(vmath.vector3(0, 0, 0), str)
	gui.set_font(node, font)
	gui.set_line_break(node, true)
	gui.set_size(node, vmath.vector3(width / scale, 0, 0))
	gui.set_leading(node, leading)
	gui.set_color(node, color)
	gui.set_scale(node, vmath.vector3(scale, scale, 1))
	if align == "center" then
		gui.set_pivot(node, gui.PIVOT_N)
	elseif align == "right" then
		gui.set_pivot(node, gui.PIVOT_NE)
	else
		gui.set_pivot(node, gui.PIVOT_NW)
	end
	return node, self:measure(font, str, width / scale, leading).height * scale
end

--- Adds a block of text. o: font, color, scale, align ("left", "center",
--- "right"), indent, width, leading, space_before, space_after, on_tap.
function Page:text(str, o)
	o = o or {}
	local indent = o.indent or 0
	local width = o.width or (self.width - 2 * self.margin - indent)
	local left = self.margin + indent
	local node, h = text_node(self, str, o.font or self.fonts.body, o.color or self.ink,
		width, o.scale or 1, o.align, o.leading or 1.15)
	local x = left
	if o.align == "center" then
		x = left + width / 2
	elseif o.align == "right" then
		x = left + width
	end
	return self:place(node, x, h, o, "top", left, left + width)
end

--- Adds a button: a filled box with a centred label. o: fill, color (label),
--- border (colour of a 3 px edge; the fill is then drawn opaque), font,
--- scale, width, pad, min_height, x (centre), align ("left" for list rows
--- and fields; the label stays vertically centred), and the spacing options of
--- text(). Returns the item; item.box is the box node.
function Page:button(label, on_tap, o)
	o = o or {}
	local width = o.width or (self.width - 2 * self.margin)
	local pad = o.pad or 26
	local scale = o.scale or 1
	local label_node, th = text_node(self, label, o.font or self.fonts.body, o.color or self.ink,
		width - 2 * pad, scale, o.align == "left" and "left" or "center", o.leading or 1.1)
	local h = math.max(o.min_height or 0, th + 2 * pad)
	local fill = o.fill or vmath.vector4(1, 1, 1, 0.12)
	local box = gui.new_box_node(vmath.vector3(0, 0, 0), vmath.vector3(width, h, 0))
	gui.set_color(box, fill)
	if o.border then
		-- children are drawn over their parent, so the edge is the parent
		-- and the fill sits inside it
		local inner = box
		box = gui.new_box_node(vmath.vector3(0, 0, 0), vmath.vector3(width + 6, h + 6, 0))
		gui.set_color(box, o.border)
		gui.set_parent(inner, box)
		gui.set_inherit_alpha(inner, false)
		gui.set_position(inner, vmath.vector3(0, 0, 0))
		if fill.w < 1 then
			-- a see-through fill would show the edge colour: cut it out
			gui.set_color(inner, vmath.vector4(fill.x, fill.y, fill.z, 1))
		end
	end
	gui.set_parent(label_node, box)
	gui.set_inherit_alpha(label_node, false)
	gui.set_position(label_node, vmath.vector3(o.align == "left" and pad - width / 2 or 0, th / 2, 0))
	local x = o.x or self.width / 2
	local item = self:place(box, x, h, { on_tap = on_tap, space_before = o.space_before,
		space_after = o.space_after }, "center", x - width / 2, x + width / 2)
	item.box, item.label = box, label_node
	return item
end

--- Adds an empty band (a spacer, or a coloured panel if o.fill is given).
function Page:band(h, o)
	o = o or {}
	local box = gui.new_box_node(vmath.vector3(0, 0, 0), vmath.vector3(o.width or self.width, h, 0))
	gui.set_color(box, o.fill or vmath.vector4(0, 0, 0, 0))
	return self:place(box, self.width / 2, h, o, "center")
end

--- Call after adding items: sets the scroll range and draws what is visible.
function Page:done()
	self:set_scroll(self.scroll)
end

function Page:max_scroll()
	return math.max(0, self.cursor + 60 - self:viewport())
end

-- Draws only the items on screen (or nearly).
function Page:cull()
	local view = self:viewport()
	for _, item in ipairs(self.items) do
		local top = item.top + self.scroll
		local visible = top > -view - 400 and top - item.height < 400
		if visible ~= item.enabled then
			gui.set_enabled(item.node, visible)
			item.enabled = visible
		end
	end
end

function Page:set_scroll(value)
	self.scroll = math.max(0, math.min(self:max_scroll(), value))
	gui.set_position(self.content, vmath.vector3(0, self.height - self.top + self.scroll, 0))
	self:cull()
end

--- Scrolls so that an item is on screen.
function Page:reveal(item)
	local top = -item.top
	if top - self.scroll < 0 or top + item.height - self.scroll > self:viewport() then
		self:set_scroll(top - 40)
	end
end

--- The item under a screen point, if it can be tapped.
function Page:hit(x, y)
	if y > self.height - self.top or y < self.bottom then
		return nil
	end
	local cy = y - (self.height - self.top) - self.scroll
	for _, item in ipairs(self.items) do
		if item.on_tap and cy <= item.top + 8 and cy >= item.top - item.height - 8
			and x >= item.x0 - 8 and x <= item.x1 + 8 then
			return item
		end
	end
end

--- Handles dragging (scroll) and tapping. Returns true if it used the action.
function Page:on_input(action_id, action)
	if action_id == TOUCH then
		-- A quick tap can arrive as pressed and released in the same frame.
		if action.pressed then
			self.drag = { last = action.y, moved = 0 }
		end
		if action.released then
			local drag = self.drag
			self.drag = nil
			if drag and drag.moved < TAP_SLOP then
				local item = self:hit(action.x, action.y)
				if item then
					item.on_tap(item)
				end
			end
		elseif not action.pressed and self.drag then
			self:drag_to(action.y)
		end
		return true
	elseif action_id == nil and self.drag then
		self:drag_to(action.y)
		return true
	elseif action_id == WHEEL_UP and action.pressed then
		self:set_scroll(self.scroll - 90)
		return true
	elseif action_id == WHEEL_DOWN and action.pressed then
		self:set_scroll(self.scroll + 90)
		return true
	end
	return false
end

function Page:drag_to(y)
	local dy = y - self.drag.last
	self.drag.last = y
	self.drag.moved = self.drag.moved + math.abs(dy)
	if self.drag.moved >= TAP_SLOP then
		self:set_scroll(self.scroll + dy)
	end
end

return M
