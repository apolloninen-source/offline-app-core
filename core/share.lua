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

--- Opens WhatsApp (or the browser) with the message. Returns false if the
--- system could not open the link.
function M.to_whatsapp(text)
	return sys.open_url(M.whatsapp_url(text))
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
