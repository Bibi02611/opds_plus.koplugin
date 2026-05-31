-- Offline Pack Service
-- Archives an OPDS catalog tree for offline reading.
--
-- Uses a BFS queue of {url, depth} pairs.  For each page fetched we:
--   • write the XML to FeedFetcher's disk cache (transparent via parseFeed)
--   • collect cover thumbnail URLs
--   • enqueue navigation sub-catalog links (link.type = atom+xml) up to max_depth
--   • enqueue "next" pagination links at the same depth
--
-- After all pages are visited, every unique cover URL is downloaded into
-- CoverCache (skipping any that are already cached).
--
-- Each I/O operation is separated by UIManager:nextTick so the event loop
-- (and any Cancel button) stays responsive between blocking HTTP calls.

local FeedFetcher = require("core.feed_fetcher")
local CoverCache  = require("services.cover_cache")
local HttpClient  = require("services.http_client")
local UrlUtils    = require("utils.url_utils")
local UIManager   = require("ui/uimanager")
local Constants   = require("models.constants")
local Debug       = require("utils.debug")

-- Acquire / release Android's PARTIAL_WAKE_LOCK via android.setWakeLock().
-- This is the definitive wakelock: prevents Android from cutting CPU + WiFi
-- even when the screen turns off. Device.screen:keepAlive is an abstraction
-- that may not map to the correct wakelock type on all builds.
-- Wrapped in pcall so it silently no-ops on non-Android platforms.
local function setWakeLock(enable)
	pcall(function()
		local ok, android = pcall(require, "android")
		if ok and android and type(android.setWakeLock) == "function" then
			android.setWakeLock(enable)
		end
	end)
end

local OfflinePack = {}

-- Return the preferred cover URL from a parsed entry (thumbnail preferred).
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

-- Return the sub-catalog URL for an entry (navigation link, atom+xml type).
local function getNavUrl(entry, base_url)
	for _, link in ipairs(entry.link or {}) do
		if link.type and link.type:find(Constants.CATALOG_TYPE) and link.href then
			return UrlUtils.buildAbsolute(base_url, link.href)
		end
	end
	return nil
end

-- Find the "next" pagination link in a raw feed table.
local function nextPageUrl(raw_feed, base_url)
	for _, link in ipairs(raw_feed.link or {}) do
		if link.rel == "next" and link.href then
			return UrlUtils.buildAbsolute(base_url, link.href)
		end
	end
	return nil
end

--- Start a full catalog archive operation.
--
-- Traversal strategy (BFS):
--   depth 0  – the starting page
--   depth 1  – sub-catalog pages linked from depth 0  (e.g. series folders)
--   depth 2  – sub-catalog pages linked from depth 1  (e.g. books in a series)
--   …up to max_depth
--   Pagination ("next") links are always followed at the same depth.
--
-- Typical Komga/Kavita topology:
--   root → "All series" (depth 1) → each series (depth 2) → books + covers
-- → starting from "root"  : max_depth=2 reaches all book covers
-- → starting from "All series" : max_depth=1 already reaches book covers
-- → starting from one series   : max_depth=0 still collects covers (no sub-links)
--
-- @param cfg table {
--   start_url  string        Entry-point catalog URL
--   username   string|nil    HTTP auth username
--   password   string|nil    HTTP auth password
--   max_depth  number|nil    Sub-catalog recursion depth   (default 2)
--   max_pages  number|nil    Hard limit on page fetches    (default 200)
--   on_progress function(phase, done, total)
--   on_done     function(pages, total_covers, new_covers)
--   on_cancel   function()
-- }
-- @return function  cancel()
function OfflinePack.start(cfg)
	local max_depth = cfg.max_depth or 2
	local max_pages = cfg.max_pages or 1000

	local state = {
		-- BFS queue
		queue         = { { url = cfg.start_url, depth = 0 } },
		visited       = { [cfg.start_url] = true },
		pages_done    = 0,
		-- Cover collection
		all_covers    = {},
		seen_covers   = {},
		phase         = "pages",
		cover_idx     = 1,
		covers_new    = 0,
		cancelled     = false,
		wakelock_held = false,   -- acquired on first HTTP call, not at startup
	}

	local function tick()
		if state.cancelled then
			setWakeLock(false)
			if cfg.on_cancel then cfg.on_cancel() end
			return
		end

		-- Signal continuous activity to both KOReader and Android:
		--   resetTickler : resets KOReader's inactivity / screensaver timer
		--   forceRePaint : produces visible screen activity that Android's Doze
		--                  mode detects as "app is active" and won't suspend
		pcall(function() UIManager:resetTickler() end)
		UIManager:forceRePaint()

		-- ── Phase 1 : BFS page walk ──────────────────────────────────────────
		if state.phase == "pages" then
			local item = table.remove(state.queue, 1)

			if not item or state.pages_done >= max_pages then
				-- Transition to cover-download phase
				state.phase = "covers"
				if cfg.on_progress then
					cfg.on_progress("covers", 0, #state.all_covers)
				end
				UIManager:nextTick(tick)
				return
			end

			-- Acquire wakelock just before the first real HTTP call.
			-- Acquiring it at plugin startup is too early: Android may not
			-- yet associate it with active network I/O and can still reclaim it.
			if not state.wakelock_held then
				setWakeLock(true)
				state.wakelock_held = true
			end

			Debug.log("OfflinePack:", "fetch depth=" .. item.depth, item.url)

			-- One blocking HTTP call (XML page, typically < 50 KB)
			local feed = FeedFetcher.parseFeed(item.url, cfg.username, cfg.password)
			state.pages_done = state.pages_done + 1

			if feed then
				local raw = feed.feed or feed

				for _, entry in ipairs(raw.entry or {}) do
					-- Collect cover thumbnail
					local cover = bestCoverUrl(entry, item.url)
					if cover and not state.seen_covers[cover] then
						table.insert(state.all_covers, cover)
						state.seen_covers[cover] = true
					end

					-- Enqueue sub-catalog links if depth budget allows
					if item.depth < max_depth then
						local nav = getNavUrl(entry, item.url)
						if nav and not state.visited[nav] then
							state.visited[nav] = true
							table.insert(state.queue, { url = nav, depth = item.depth + 1 })
						end
					end
				end

				-- Always follow pagination at the same depth
				local nxt = nextPageUrl(raw, item.url)
				if nxt and not state.visited[nxt] then
					state.visited[nxt] = true
					table.insert(state.queue, { url = nxt, depth = item.depth })
				end
			end

			if cfg.on_progress then
				cfg.on_progress("pages", state.pages_done, #state.all_covers)
			end
			UIManager:nextTick(tick)

		-- ── Phase 2 : cover download (batched, scheduleIn) ──────────────────
		-- Process covers in small batches of COVER_BATCH_SIZE.
		-- Between batches we use scheduleIn(0.1) instead of nextTick: a time-based
		-- wakeup fires correctly after a device sleep/resume cycle (accumulated time
		-- triggers it immediately), whereas nextTick only fires on active event-loop
		-- iterations and can stall when the screen is off.
		-- Each cover uses a short timeout (5 s / 8 s) so a dropped network
		-- connection during sleep never causes an indefinite hang.
		elseif state.phase == "covers" then
			local total      = #state.all_covers
			local batch_end  = math.min(state.cover_idx + Constants.ARCHIVE_COVER_BATCH - 1, total)

			for i = state.cover_idx, batch_end do
				if state.cancelled then
					if cfg.on_cancel then cfg.on_cancel() end
					return
				end

				local cover_url = state.all_covers[i]
				local cached = CoverCache.get(cover_url, nil)
				if not cached then
					local ok, content = HttpClient.getUrlContent(
						cover_url,
						Constants.TIMEOUTS.ARCHIVE_COVER,
						Constants.TIMEOUTS.ARCHIVE_COVER_MAX,
						cfg.username,
						cfg.password
					)
					if ok and content then
						CoverCache.put(cover_url, content)
						state.covers_new = state.covers_new + 1
					end
				end
			end

			state.cover_idx = batch_end + 1

			if cfg.on_progress then
				cfg.on_progress("covers", math.min(state.cover_idx - 1, total), total)
			end

			if state.cover_idx > total then
				setWakeLock(false)
				Debug.log("OfflinePack:", "done —",
					state.pages_done, "pages,", total, "covers,",
					state.covers_new, "newly downloaded")
				if cfg.on_done then
					cfg.on_done(state.pages_done, total, state.covers_new)
				end
			else
				-- Time-based wakeup: fires even after a device sleep/resume cycle
				UIManager:scheduleIn(0.1, tick)
			end
		end
	end

	UIManager:nextTick(tick)
	return function() state.cancelled = true end
end

return OfflinePack
