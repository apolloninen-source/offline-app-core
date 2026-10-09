-- Sharing results as text, mainly to WhatsApp.
--
-- No extension is needed: a wa.me link opens WhatsApp with the text filled
-- in, and falls back to the browser if WhatsApp is not installed.

local M = {}

--- Joins lines into one message, e.g.
--- share.text({ "Yaksha's Riddles #42", "🟩🟩🟨⬛🟩", "Streak: 12 🔥" })
function M.text(lines)
	return table.concat(lines, "\n")
end

--- Percent-encodes a UTF-8 string for use in a URL.
function M.url_encode(text)
	return (text:gsub("[^%w%-%._~]", function(c)
		return string.format("%%%02X", c:byte())
	end))
end

--- The WhatsApp link for a message.
function M.whatsapp_url(text)
	return "https://wa.me/?text=" .. M.url_encode(text)
end

--- The link that opens the WhatsApp app itself with the message.
function M.whatsapp_app_url(text)
	return "whatsapp://send?text=" .. M.url_encode(text)
end

--- Opens WhatsApp with the message. The app link comes first: WhatsApp's
--- web page (wa.me) garbles emoji such as the result squares. Without
--- WhatsApp: the phone's share sheet (the Sharing extension, global
--- `share`), else the web link. Returns false if nothing could be opened.
function M.to_whatsapp(text)
	if sys.open_url(M.whatsapp_app_url(text)) then
		return true
	end
	local sharing = rawget(_G, "share")
	if type(sharing) == "table" and sharing.text then
		sharing.text(text)
		return true
	end
	return sys.open_url(M.whatsapp_url(text))
end

--- Opens the phone's share sheet with the text: any app, or Copy. Without
--- the Sharing extension, WhatsApp.
function M.sheet(text)
	local sharing = rawget(_G, "share")
	if type(sharing) == "table" and sharing.text then
		sharing.text(text)
		return true
	end
	return M.to_whatsapp(text)
end

--- A row of squares for a result, e.g. { true, true, false } -> "🟩🟩⬛".
function M.squares(results, yes, no)
	local out = {}
	for i, r in ipairs(results) do
		out[i] = r and (yes or "🟩") or (no or "⬛")
	end
	return table.concat(out)
end

return M
