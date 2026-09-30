-- The one-time "Remove ads" purchase, through Defold's official IAP extension
-- (https://github.com/defold/extension-iap). Priced in Google Play Console:
-- €2 in Europe, ₹79–99 in India (Games of Dharma; other series may differ).
--
--   purchase.init(save_data, "remove_ads")   -- product id from Play Console
--   purchase.buy()                           -- from the "Remove ads" button
--   purchase.restore()                       -- from "Restore purchase"
--
-- Without the IAP extension (desktop, tests) buy() and restore() do nothing.
-- The entitlement is stored in the save as ads_removed = true, which
-- core.ads reads.

local M = {}

local save, product_id

local function grant()
	if save.values.ads_removed ~= true then
		save.values.ads_removed = true
		save:write()
		-- a banner may be on screen right now
		local ads = package.loaded["core.ads"]
		if ads and ads.remove_all then
			ads.remove_all()
		end
	end
end

local function listener(self, transaction, error)
	if error then
		-- Bought before (another phone, a reinstall): ask the store again,
		-- which answers with a restored purchase.
		if error.reason == iap.REASON_ITEM_ALREADY_OWNED then
			iap.restore()
		end
		return -- otherwise cancelled or failed: nothing changes
	end
	if transaction.ident ~= product_id then
		return
	end
	if transaction.state == iap.TRANS_STATE_PURCHASED then
		grant()
		-- "Remove ads" is owned forever, so it is acknowledged, never
		-- finished: on Google Play, finishing consumes the purchase.
		-- Requires iap.auto_finish_transactions = 0 in game.project.
		iap.acknowledge(transaction)
	elseif transaction.state == iap.TRANS_STATE_RESTORED then
		grant()
	end
end

--- Starts listening for purchases. save_data is a core.save object.
function M.init(save_data, id)
	save = save_data
	product_id = id or "remove_ads"
	if iap then
		iap.set_listener(listener)
	end
end

--- True once the player owns "Remove ads".
function M.owned()
	return save ~= nil and save.values.ads_removed == true
end

function M.buy()
	if iap and not M.owned() then
		iap.buy(product_id)
	end
end

function M.restore()
	if iap then
		iap.restore()
	end
end

--- For tests and support: grant the entitlement directly.
M._grant = grant

return M
