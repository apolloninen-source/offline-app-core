-- The ad rules shared by every app, and the link to Defold's official AdMob
-- extension (https://github.com/defold/extension-admob).
--
-- The rules (decided for all three series):
--   * at most one App open ad a day, when the app starts;
--   * at most one interstitial a day, when the first game of the day starts;
--   * a banner only while reading a text in the reader, in its own space
--     below the text, never over it (an app can switch it off);
--   * nothing at all once the player has bought "Remove ads".
-- An app may opt out of either ad (Paths of Dharma shows no interstitial:
-- never during or right after practice).
--
-- Without the AdMob extension (desktop builds, tests) every call is a
-- harmless no-op, but the rules still run, so they can be tested.
--
--   ads.init(save_data, {
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
M.TEST_BANNER = "ca-app-pub-3940256099942544/6300978111"

--- The ad units to use. Release builds take the app's own units from
--- game.project ([ads] app_open_unit, interstitial_unit); debug builds
--- always use Google's test units, so no one taps a real ad while testing
--- (AdMob can suspend an account for that). A release build without units
--- set also falls back to the test units.
function M.units(is_debug, config)
	local function pick(key, test)
		local own = not is_debug and config(key) or ""
		return own ~= "" and own or test
	end
	return {
		app_open = pick("ads.app_open_unit", M.TEST_APP_OPEN),
		interstitial = pick("ads.interstitial_unit", M.TEST_INTERSTITIAL),
		banner = pick("ads.banner_unit", M.TEST_BANNER),
	}
end

local save, opts
local started, initialized = false, false

-- The reader's banner: shown only while reading, below the text, never over
-- it. The reader listens for its height to keep that space free.
local banner = { wanted = false, loaded = false, loading = false, height = 0 }
local banner_listener

local function banner_changed()
	if banner_listener then
		banner_listener(banner.wanted and banner.loaded and banner.height or 0)
	end
end

local function load_banner()
	if not banner.loading and not banner.loaded then
		banner.loading = true
		-- the standard 320 x 50 size: small and steady
		admob.load_banner(opts.banner_unit, admob.SIZE_BANNER)
	end
end
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
		initialized = true
		if banner.wanted and opts.banner and not M.removed() then
			load_banner()
		end
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
	elseif message_id == admob.MSG_BANNER then
		if message.event == admob.EVENT_LOADED then
			banner.loading, banner.loaded = false, true
			banner.height = message.height or 0
			if banner.wanted and not M.removed() then
				admob.show_banner(admob.POS_BOTTOM_CENTER)
			else
				admob.hide_banner()
			end
			banner_changed()
		elseif message.event == admob.EVENT_FAILED_TO_LOAD then
			banner.loading = false
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
	local units = M.units(sys.get_engine_info().is_debug, function(key)
		return sys.get_config_string(key, "")
	end)
	opts.app_open_unit, opts.interstitial_unit, opts.banner_unit = units.app_open, units.interstitial, units.banner
	if opts.app_open == nil then opts.app_open = true end
	if opts.interstitial == nil then opts.interstitial = true end
	if opts.banner == nil then opts.banner = true end
	if not admob or M.removed() then
		return false
	end
	-- The strictest rating the audience needs: the apps are for 13+ and
	-- about scripture, so PG unless an app says otherwise.
	local rating = admob["MAX_AD_CONTENT_RATING_" .. (opts.max_rating or "PG")]
	if rating and admob.set_max_ad_content_rating then
		admob.set_max_ad_content_rating(rating)
	end
	-- Never personalized: no ad profile follows the player. Google's
	-- "restricted data processing" makes it serve non-personalized ads and
	-- limit its use of identifiers. The owner's rule; see README.
	if admob.set_privacy_settings then
		admob.set_privacy_settings(true)
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

--- The reader's banner. show_banner() while the text is on screen,
--- hide_banner() when leaving it. The listener gets the banner's height in
--- screen pixels (0 when none shows), to keep that space free of text.
function M.set_banner_listener(fn)
	banner_listener = fn
end

function M.show_banner()
	banner.wanted = true
	if not admob or not opts or not opts.banner or M.removed() or not initialized then
		return -- loaded once AdMob has started, if still wanted
	end
	if banner.loaded then
		admob.show_banner(admob.POS_BOTTOM_CENTER)
		banner_changed()
	else
		load_banner()
	end
end

function M.hide_banner()
	banner.wanted = false
	if admob and banner.loaded then
		admob.hide_banner()
	end
	banner_changed()
end

--- After "Remove ads": take away anything on screen at once.
function M.remove_all()
	if admob and banner.loaded then
		admob.destroy_banner()
	end
	banner.loaded, banner.loading = false, false
	banner_changed()
end

--- For tests: replace how "today" is found.
function M.set_today(fn)
	today_fn = fn
end

return M
