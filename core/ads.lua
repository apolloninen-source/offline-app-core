-- The ad rules shared by every app, and the link to Defold's official AdMob
-- extension (https://github.com/defold/extension-admob).
--
-- The rules (decided for all three series):
--   * at most one App open ad a day, when the app starts;
--   * at most one interstitial a day, when the first game of the day starts;
--   * never any banner;
--   * nothing at all once the player has bought "Remove ads".
-- An app may opt out of either ad (Paths of Dharma shows no interstitial:
-- never during or right after practice).
--
-- Without the AdMob extension (desktop builds, tests) every call is a
-- harmless no-op, but the rules still run, so they can be tested.
--
--   ads.init(save_data, {
--       app_open_unit = "...", interstitial_unit = "...",   -- real IDs at release
--       interstitial = true,                               -- false in calm apps
--       max_rating = "PG",                                 -- G, PG (default), T or MA
--       on_consent = function(can_request_ads) end,        -- optional: refresh a "Privacy choices" link
--       consent_debug = { debug_eea = true, test_device = "..." },  -- testing the form outside the EU
--   })
--
-- EU consent: where the law asks for it (EEA, UK, Switzerland), Google's
-- consent form (the "consent" extension in this library, /consent) is shown
-- before any ad is requested, and AdMob starts only once ads are allowed.
-- The form itself is written in AdMob, under Privacy & messaging. Where
-- M.privacy_options_required() is true, the app must offer a "Privacy
-- choices" link that calls M.show_privacy_options().
--   ads.on_game_start()   -- when a game (not the menu) begins

local M = {}

-- Google's official test ad units for Android. Real IDs replace these only
-- in release builds.
M.TEST_APP_OPEN = "ca-app-pub-3940256099942544/9257395921"
M.TEST_INTERSTITIAL = "ca-app-pub-3940256099942544/1033173712"

local save, opts
local started = false
local today_fn = function()
	return require("core.day").today()
end

local function state()
	save.values.ads = save.values.ads or {}
	return save.values.ads
end

--- True once "Remove ads" has been bought (see core.purchase).
function M.removed()
	return save ~= nil and save.values.ads_removed == true
end

--- The rules, as pure functions of the saved state and today's day number.
function M.should_show_app_open(ads_state, today, removed)
	return not removed and ads_state.last_app_open_day ~= today
end

function M.should_show_interstitial(ads_state, today, removed)
	return not removed and ads_state.last_interstitial_day ~= today
end

local function mark(field)
	state()[field] = today_fn()
	save:write()
end

local function on_admob(self, message_id, message)
	if message_id == admob.MSG_INITIALIZATION then
		if opts.app_open and M.should_show_app_open(state(), today_fn(), M.removed()) then
			admob.load_appopen(opts.app_open_unit)
		end
		if opts.interstitial and M.should_show_interstitial(state(), today_fn(), M.removed()) then
			admob.load_interstitial(opts.interstitial_unit)
		end
	elseif message_id == admob.MSG_APPOPEN then
		if message.event == admob.EVENT_LOADED
			and M.should_show_app_open(state(), today_fn(), M.removed()) then
			admob.show_appopen()
		elseif message.event == admob.EVENT_OPENING then
			mark("last_app_open_day")
		end
	elseif message_id == admob.MSG_INTERSTITIAL then
		if message.event == admob.EVENT_OPENING then
			mark("last_interstitial_day")
		end
	end
end

--- Starts ads for the app. save_data is a core.save object.
function M.init(save_data, options)
	save = save_data
	opts = options or {}
	opts.app_open_unit = opts.app_open_unit or M.TEST_APP_OPEN
	opts.interstitial_unit = opts.interstitial_unit or M.TEST_INTERSTITIAL
	if opts.app_open == nil then opts.app_open = true end
	if opts.interstitial == nil then opts.interstitial = true end
	if not admob or M.removed() then
		return false
	end
	-- The strictest rating the audience needs: the apps are for 13+ and
	-- about scripture, so PG unless an app says otherwise.
	local rating = admob["MAX_AD_CONTENT_RATING_" .. (opts.max_rating or "PG")]
	if rating and admob.set_max_ad_content_rating then
		admob.set_max_ad_content_rating(rating)
	end
	local function start()
		if not started then
			started = true
			admob.set_callback(on_admob)
			admob.initialize()
		end
	end
	if consent then
		consent.request(function(self, can_request_ads, err)
			if err then
				print("consent: " .. err)
			end
			if can_request_ads then
				start()
			end
			if opts.on_consent then
				opts.on_consent(can_request_ads)
			end
		end, opts.consent_debug)
		-- answered on an earlier day: no need to wait for the update
		if consent.can_request_ads() then
			start()
		end
	else
		start() -- no consent extension (desktop): nothing to ask
	end
	return true
end

--- True where the player must be able to change their consent choice: the
--- app then shows a "Privacy choices" link.
function M.privacy_options_required()
	return consent ~= nil and not M.removed() and consent.privacy_options_required()
end

--- Opens Google's form for changing the consent choice.
function M.show_privacy_options()
	if consent then
		consent.show_privacy_options(function(self, can_request_ads, err)
			if err then
				print("consent: " .. err)
			end
		end)
	end
end

--- Call when a game (not the menu) starts. Shows the day's interstitial if
--- it is due and loaded. Returns true if an ad was shown.
function M.on_game_start()
	if not admob or not opts or not opts.interstitial then
		return false
	end
	if M.should_show_interstitial(state(), today_fn(), M.removed())
		and admob.is_interstitial_loaded() then
		admob.show_interstitial()
		return true
	end
	return false
end

--- For tests: replace how "today" is found.
function M.set_today(fn)
	today_fn = fn
end

return M
