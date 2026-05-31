-- Offline Pack Service
-- Walks all pages of an OPDS catalog via "next" links, writes XML to the disk
-- offline cache (handled transparently by FeedFetcher.parseFeed), then downloads
-- every cover thumbnail into CoverCache.
--
-- Each I/O step is scheduled via UIManager:nextTick so the event loop (and any
-- Cancel button) remains responsive between operations.

local FeedFetcher  = require("core.feed_fetcher")
local CoverCache   = require("services.cover_cache")
local HttpClient   = require("services.http_client")
local UrlUtils     = require("utils.url_utils")
local UIManager    = require("ui/uimanager")
local Constants    = require("models.constants")
local Debug        = require("utils.debug")

local OfflinePack = {}

local DEFAULT_MAX_PAGES = 20

-- Return the preferred cover URL from a parsed entry (thumbnail > full image).
local function bestCoverUrl(entry, base_url)
	local thumbnail, image
	for _, link in ipairs(entry.link or {}) do
		if link.rel and link.href then
			local abs = UrlUtils.buildAbsolute(base_url, link.href)
			if Constants.THUMBNAIL_REL[link.rel] then
				thumbnail = abs
			elseif Constants.IMAGE_REL[link.rel] then
				image = abs
			end
		end
	end
	return thumbnail or image
end

-- Find the "next" pagination link in a parsed feed.
local function nextPageUrl(raw_feed, base_url)
	for _, link in ipairs(raw_feed.link or {}) do
		if link.rel == "next" and link.href then
			return UrlUtils.buildAbsolute(base_url, link.href)
		end
	end
	return nil
end

--- Start a full-catalog offline archive operation.
--
-- The operation runs in two phases:
--   1. "pages"  — follows every "next" link, parsing feeds (already written to
--                 FeedFetcher's disk cache by parseFeed) and collecting cover URLs.
--   2. "covers" — downloads each unique cover URL into CoverCache if not already
--                 present, skipping stale-cache hits.
--
-- Both phases use UIManager:nextTick to yield between each network call so the
-- Cancel button and other UI events are processed normally.
--
-- @param cfg table {
--   start_url  string        First catalog page URL
--   username   string|nil    HTTP auth username
--   password   string|nil    HTTP auth password
--   max_pages  number|nil    Page walk limit (default 20)
--   on_progress function(phase, done, total)  called after each step
--   on_done     function(pages, total_covers, new_covers)
--   on_cancel   function()
-- }
-- @return function  cancel()  — call at any time to abort
function OfflinePack.start(cfg)
	local state = {
		phase       = "pages",
		current_url = cfg.start_url,
		pages_done  = 0,
		all_covers  = {},
		seen_covers = {},
		cover_idx   = 1,
		covers_new  = 0,
		cancelled   = false,
		max_pages   = cfg.max_pages or DEFAULT_MAX_PAGES,
	}

	local function tick()
		if state.cancelled then
			if cfg.on_cancel then cfg.on_cancel() end
			return
		end

		-- ── Phase 1 : walk catalog pages ────────────────────────────────────
		if state.phase == "pages" then
			if not state.current_url or state.pages_done >= state.max_pages then
				-- Transition to cover download phase
				state.phase = "covers"
				if cfg.on_progress then
					cfg.on_progress("covers", 0, #state.all_covers)
				end
				UIManager:nextTick(tick)
				return
			end

			-- One blocking HTTP call — brief (single page XML, typically < 50 KB)
			local feed = FeedFetcher.parseFeed(
				state.current_url, cfg.username, cfg.password)
			state.pages_done = state.pages_done + 1

			if feed then
				local raw = feed.feed or feed
				for _, entry in ipairs(raw.entry or {}) do
					local url = bestCoverUrl(entry, state.current_url)
					if url and not state.seen_covers[url] then
						table.insert(state.all_covers, url)
						state.seen_covers[url] = true
					end
				end
				state.current_url = nextPageUrl(raw, state.current_url)
			else
				state.current_url = nil  -- server error or end of feed
			end

			if cfg.on_progress then
				cfg.on_progress("pages", state.pages_done, #state.all_covers)
			end
			UIManager:nextTick(tick)

		-- ── Phase 2 : download covers ────────────────────────────────────────
		elseif state.phase == "covers" then
			local idx = state.cover_idx
			if idx > #state.all_covers then
				-- All done
				Debug.log("OfflinePack:", "done —",
					state.pages_done, "pages,", #state.all_covers, "covers,",
					state.covers_new, "newly downloaded")
				if cfg.on_done then
					cfg.on_done(state.pages_done, #state.all_covers, state.covers_new)
				end
				return
			end

			state.cover_idx = idx + 1
			local url = state.all_covers[idx]

			-- Only download if not already on disk
			local cached = CoverCache.get(url, nil)
			if not cached then
				local ok, content = HttpClient.getUrlContent(
					url,
					Constants.TIMEOUTS.IMAGE_LOAD,
					Constants.TIMEOUTS.IMAGE_MAX_TIME,
					cfg.username,
					cfg.password
				)
				if ok and content then
					CoverCache.put(url, content)
					state.covers_new = state.covers_new + 1
				end
			end

			-- Notify every 10 covers (avoids flooding the UI with repaints)
			if idx % 10 == 1 and cfg.on_progress then
				cfg.on_progress("covers", idx, #state.all_covers)
			end
			UIManager:nextTick(tick)
		end
	end

	UIManager:nextTick(tick)

	return function() state.cancelled = true end
end

return OfflinePack
