-- Feed Fetcher for OPDS Browser
-- Handles all HTTP requests, caching, and feed parsing

local BD = require("ui/bidi")
local Cache = require("cache")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local _ = require("utils.locale")
local T = require("ffi/util").template

local OPDSParser = require("core.parser")
local Constants = require("models.constants")
local UrlUtils = require("utils.url_utils")
local FileUtils = require("utils.file_utils")
local Result = require("utils.result")

local FeedFetcher = {}

-- In-memory catalog cache (keyed by URL + Last-Modified header)
local CatalogCache = Cache:new {
	slots = Constants.CACHE_SLOTS,
}

-- Disk-based offline cache directory
local OFFLINE_CACHE_DIR = DataStorage:getDataDir() .. "/cache/opds_plus/offline"

-- Map a URL to a filesystem-safe filename inside OFFLINE_CACHE_DIR.
-- Sanitize non-alphanumeric chars, cap at 180 chars, append URL length to avoid
-- collisions between two URLs that share the same first 180 sanitized chars.
local function offlineCachePath(url)
	local sanitized = (url or ""):gsub("[^%w%-_%.%~]", "_")
	local len_tag = "_L" .. tostring(#(url or ""))
	if #sanitized > 180 then sanitized = sanitized:sub(1, 180) end
	return OFFLINE_CACHE_DIR .. "/" .. sanitized .. len_tag .. ".xml"
end

local function readOfflineCache(url)
	local path = offlineCachePath(url)
	local ok, f = pcall(io.open, path, "r")
	if not ok or not f then return nil end
	local content = f:read("*a")
	f:close()
	return (content and content ~= "") and content or nil
end

local function writeOfflineCache(url, content)
	FileUtils.makeDirectory(OFFLINE_CACHE_DIR)
	local path = offlineCachePath(url)
	local ok, f = pcall(io.open, path, "w")
	if not ok or not f then return end
	f:write(content)
	f:close()
end

-- Public: true if a disk-cached feed exists for this URL (survives restarts).
function FeedFetcher.hasOfflineCache(url)
	return lfs.attributes(offlineCachePath(url), "mode") == "file"
end

-- Fetch raw XML feed from URL
-- @param item_url string URL to fetch from
-- @param headers_only boolean If true, only fetch headers (HEAD request)
-- @param username string|nil Optional HTTP auth username
-- @param password string|nil Optional HTTP auth password
-- @return string|table XML content or headers, nil on error
function FeedFetcher.fetchFeed(item_url, headers_only, username, password)
	local sink = {}
	socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
	local request = {
		url      = item_url,
		method   = headers_only and "HEAD" or "GET",
		headers  = {
			["Accept-Encoding"] = "identity",
		},
		sink     = ltn12.sink.table(sink),
		user     = username,
		password = password,
	}
	local code, headers, status
	local req_ok, req_err = pcall(function()
		code, headers, status = socket.skip(1, http.request(request))
	end)
	socketutil:reset_timeout()
	if not req_ok then
		logger.dbg(string.format("OPDS: fetchFeed network error for `%s`: %s", item_url, req_err))
		return nil
	end

	if headers_only then
		return headers
	end

	if code == Constants.HTTP_STATUS.OK then
		local xml = table.concat(sink)
		return xml ~= "" and xml
	end

	-- Handle errors
	local text, icon
	if headers and code == Constants.HTTP_STATUS.MOVED_PERMANENTLY then
		text = T(_("The catalog has been permanently moved. Please update catalog URL to '%1'."),
			BD.url(headers.location))
	elseif headers and code == Constants.HTTP_STATUS.FOUND
		and item_url:match("^https")
		and headers.location:match("^http[^s]") then
		text = T(
			_(
				"Insecure HTTPS → HTTP downgrade attempted by redirect from:\n\n'%1'\n\nto\n\n'%2'.\n\nPlease inform the server administrator that many clients disallow this because it could be a downgrade attack."),
			BD.url(item_url), BD.url(headers.location))
		icon = "notice-warning"
	else
		local error_message = {
			["401"] = _("Authentication required for catalog. Please add a username and password."),
			["403"] = _("Failed to authenticate. Please check your username and password."),
			["404"] = _("Catalog not found."),
			["406"] = _("Cannot get catalog. Server refuses to serve uncompressed content."),
		}
		text = code and error_message[tostring(code)] or
			T(_("Cannot get catalog. Server response status: %1."), status or code)
	end

	UIManager:show(InfoMessage:new {
		text = text,
		icon = icon,
	})
	logger.dbg(string.format("OPDS: Failed to fetch catalog `%s`: %s", item_url, text))

	return nil
end

-- Parse feed with caching support
-- @param item_url string URL to fetch and parse
-- @param username string|nil Optional HTTP auth username
-- @param password string|nil Optional HTTP auth password
-- @param debug_callback function|nil Optional debug logging callback
-- @return table Parsed feed or nil on error
function FeedFetcher.parseFeed(item_url, username, password, debug_callback)
	-- Fast offline path: skip all network I/O when the device has no connection.
	local net_ok, is_connected = pcall(function() return NetworkMgr:isConnected() end)
	if not (net_ok and is_connected) then
		local cached = readOfflineCache(item_url)
		if cached then
			logger.info("OPDS: offline, serving disk cache for", item_url)
			UIManager:show(InfoMessage:new {
				text = _("Mode hors-ligne : catalogue mis en cache utilisé."),
				timeout = 3,
			})
			return OPDSParser:parse(cached)
		end
		-- No cache and no network — caller will show an appropriate error.
		return nil
	end

	-- Network is available: try to fetch a fresh feed.
	local headers = FeedFetcher.fetchFeed(item_url, true, username, password)
	local feed_last_modified = headers and headers["last-modified"]
	local feed

	if feed_last_modified then
		local hash = "opds|catalog|" .. item_url .. "|" .. feed_last_modified
		feed = CatalogCache:check(hash)
		if feed then
			if debug_callback then debug_callback("Cache hit for", item_url) end
		else
			if debug_callback then debug_callback("Cache miss, fetching", item_url) end
			feed = FeedFetcher.fetchFeed(item_url, false, username, password)
			if feed then
				CatalogCache:insert(hash, feed)
				writeOfflineCache(item_url, feed)
			end
		end
	else
		feed = FeedFetcher.fetchFeed(item_url, false, username, password)
		if feed then
			writeOfflineCache(item_url, feed)
		end
	end

	-- Network fetch failed (timeout, HTTP error, etc.) — try disk fallback.
	if not feed then
		feed = readOfflineCache(item_url)
		if feed then
			logger.info("OPDS: network error, serving disk cache for", item_url)
			UIManager:show(InfoMessage:new {
				text = _("Mode hors-ligne : catalogue mis en cache utilisé."),
				timeout = 3,
			})
		end
	end

	if feed then
		return OPDSParser:parse(feed)
	end
	return nil
end

-- Parse feed with Result-based error handling
-- @param item_url string URL to fetch and parse
-- @param username string|nil Optional HTTP auth username
-- @param password string|nil Optional HTTP auth password
-- @param debug_callback function|nil Optional debug logging callback
-- @return Result Result with parsed feed or error
function FeedFetcher.parseFeedResult(item_url, username, password, debug_callback)
	local result = Result.wrapPcall(FeedFetcher.parseFeed)(item_url, username, password, debug_callback)

	-- Convert nil success to error
	if result:isOk() and result.value == nil then
		return Result.err("Failed to fetch or parse feed")
	end

	return result
end

-- Extract server filename from URL headers
-- @param item_url string URL to check
-- @param filetype string|nil Desired file extension
-- @param username string|nil Optional HTTP auth username
-- @param password string|nil Optional HTTP auth password
-- @return string Filename extracted from server or URL
function FeedFetcher.getServerFileName(item_url, filetype, username, password)
	local headers = FeedFetcher.fetchFeed(item_url, true, username, password)
	local filename
	local source  -- for debug logging

	if headers then
		local cd = headers["content-disposition"]
		logger.dbg("OPDS getServerFileName content-disposition:", cd or "(nil)")

		filename = UrlUtils.parseContentDisposition(cd)
		if filename then
			source = "content-disposition"
		end

		if not filename and headers["location"] then
			-- Location may contain a MIME-encoded or URL-encoded filename in the path
			local loc = headers["location"]
			logger.dbg("OPDS getServerFileName location:", loc)
			local raw = loc:gsub(".*/", "")
			filename = UrlUtils.decodeFilename(raw)
			source = "location"
		end
	end

	if not filename then
		filename = UrlUtils.decodeFilename(UrlUtils.extractFilename(item_url))
		source = "url"
	end

	logger.dbg("OPDS getServerFileName source=" .. (source or "?") .. " raw filename:", filename)

	filename = FileUtils.ensureExtension(filename, filetype)

	logger.dbg("OPDS getServerFileName final:", filename)

	return filename
end

-- Get OpenSearch template from descriptor URL
-- @param osd_url string OpenSearch descriptor URL
-- @param search_template_type string Expected template MIME type pattern
-- @param username string|nil Optional HTTP auth username
-- @param password string|nil Optional HTTP auth password
-- @param debug_callback function|nil Optional debug logging callback
-- @return string|nil Search template URL with {searchTerms} placeholder
function FeedFetcher.getSearchTemplate(osd_url, search_template_type, username, password, debug_callback)
	local search_descriptor = FeedFetcher.parseFeed(osd_url, username, password, debug_callback)

	---@diagnostic disable-next-line: undefined-field
	if search_descriptor and search_descriptor.OpenSearchDescription and search_descriptor.OpenSearchDescription.Url then
		---@diagnostic disable-next-line: undefined-field
		for _, candidate in ipairs(search_descriptor.OpenSearchDescription.Url) do
			if candidate.type and candidate.template and candidate.type:find(search_template_type) then
				return candidate.template:gsub("{searchTerms}", "%%s")
			end
		end
	end

	return nil
end

-- Generate item table from URL (wrapper for common pattern)
-- @param item_url string URL to fetch catalog from
-- @param username string|nil Optional HTTP auth username
-- @param password string|nil Optional HTTP auth password
-- @param debug_callback function|nil Optional debug logging callback
-- @param catalog_parser function Function to parse catalog into item table
-- @return table Item table suitable for menu display
function FeedFetcher.genItemTableFromURL(item_url, username, password, debug_callback, catalog_parser)
	local result = FeedFetcher.parseFeedResult(item_url, username, password, debug_callback)

	local catalog = result:unwrapOrElse(function(err)
		logger.info("Cannot get catalog info from", item_url, err)
		UIManager:show(InfoMessage:new {
			text = T(_("Cannot get catalog info from %1"), (item_url and BD.url(item_url) or "nil")),
		})
		return nil
	end)

	-- Call the provided catalog parser function
	-- Pass catalog and the item_url
	return catalog_parser(catalog, item_url)
end

-- Clear the catalog cache (in-memory) and the disk-based offline cache.
function FeedFetcher.clearCache()
	CatalogCache:clear()
	local ok, iter, state = pcall(lfs.dir, OFFLINE_CACHE_DIR)
	if ok and iter then
		for entry in iter, state do
			if entry ~= "." and entry ~= ".." then
				os.remove(OFFLINE_CACHE_DIR .. "/" .. entry)
			end
		end
	end
end

-- Get cache statistics: (used, total) counts combining in-memory and disk entries.
function FeedFetcher.getCacheStats()
	local disk_count = 0
	local ok, iter, state = pcall(lfs.dir, OFFLINE_CACHE_DIR)
	if ok and iter then
		for entry in iter, state do
			if entry ~= "." and entry ~= ".." and entry:match("%.xml$") then
				disk_count = disk_count + 1
			end
		end
	end
	return CatalogCache:used_size() + disk_count, CatalogCache.slots + disk_count
end

return FeedFetcher
