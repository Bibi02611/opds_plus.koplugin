-- Komga Read Progress Sync Service for OPDS Plus
-- Fetches and pushes reading progress for books served by a Komga OPDS catalog.
-- Uses Komga's REST API with the same Basic-auth credentials as OPDS.
-- All functions fail silently if not connected to a Komga server.

local http      = require("socket.http")
local ltn12     = require("ltn12")
local socket    = require("socket")
local socketutil = require("socketutil")
local logger    = require("logger")

local KomgaSync = {}

--- Detect whether a catalog URL looks like a Komga OPDS endpoint.
-- @param catalog_url string Root catalog URL
-- @return boolean
function KomgaSync.isKomga(catalog_url)
	return catalog_url ~= nil and (
		catalog_url:find("/opds/v1%.2", 1, true) ~= nil or
		catalog_url:find("/opds/v2",   1, true) ~= nil
	)
end

--- Extract Komga book UUID from an acquisition download URL.
-- Komga format: http://server/opds/v1.2/books/{uuid}/download/filename
-- @param href string Acquisition link href
-- @return string|nil UUID or nil
function KomgaSync.getBookId(href)
	if not href then return nil end
	return href:match("/books/([a-f0-9%-]+)/download/")
		or href:match("/books/([a-f0-9%-]+)/file/")
end

--- Derive the Komga REST API base URL from the OPDS catalog URL.
-- @param catalog_url string OPDS catalog URL
-- @return string|nil scheme+host+port or nil
function KomgaSync.getBaseUrl(catalog_url)
	if not catalog_url then return nil end
	return catalog_url:match("^(https?://[^/]+)")
end

--- Fetch read progress for a book from the Komga REST API.
-- @param base_url  string  e.g. "http://komga:7070"
-- @param book_id   string  Book UUID
-- @param username  string|nil  Basic-auth username
-- @param password  string|nil  Basic-auth password
-- @return table|nil { page=number|nil, completed=boolean } or nil on failure
function KomgaSync.getReadProgress(base_url, book_id, username, password)
	if not base_url or not book_id then return nil end

	local api_url = base_url .. "/api/v1/books/" .. book_id .. "/read-progress"
	local sink = {}
	socketutil:set_timeout(8, 15)
	local code
	local ok, err = pcall(function()
		code = socket.skip(1, http.request {
			url      = api_url,
			method   = "GET",
			headers  = {
				["Accept"]          = "application/json",
				["Accept-Encoding"] = "identity",
			},
			sink     = ltn12.sink.table(sink),
			user     = username,
			password = password,
		})
	end)
	socketutil:reset_timeout()

	if not ok or code ~= 200 then
		logger.dbg("KomgaSync: getReadProgress failed:", err or tostring(code))
		return nil
	end

	local body = table.concat(sink)
	local page = tonumber(body:match('"page"%s*:%s*(%d+)'))
	local completed = body:match('"completed"%s*:%s*(true)') ~= nil

	return { page = page, completed = completed }
end

--- Push read progress to the Komga REST API.
-- @param base_url   string   API base URL
-- @param book_id    string   Book UUID
-- @param page       number|nil  Current page (nil = completed only)
-- @param completed  boolean  Whether the book is finished
-- @param username   string|nil
-- @param password   string|nil
-- @return boolean True on success (HTTP 200 or 204)
function KomgaSync.updateReadProgress(base_url, book_id, page, completed, username, password)
	if not base_url or not book_id then return false end

	local api_url = base_url .. "/api/v1/books/" .. book_id .. "/read-progress"
	local payload
	if page then
		payload = string.format('{"page":%d,"completed":%s}', page, completed and "true" or "false")
	else
		payload = string.format('{"completed":%s}', completed and "true" or "false")
	end

	local sink = {}
	socketutil:set_timeout(8, 15)
	local code
	local ok, err = pcall(function()
		code = socket.skip(1, http.request {
			url     = api_url,
			method  = "PATCH",
			headers = {
				["Content-Type"]    = "application/json",
				["Content-Length"]  = tostring(#payload),
				["Accept-Encoding"] = "identity",
			},
			source   = ltn12.source.string(payload),
			sink     = ltn12.sink.table(sink),
			user     = username,
			password = password,
		})
	end)
	socketutil:reset_timeout()

	if not ok then
		logger.dbg("KomgaSync: updateReadProgress error:", err)
		return false
	end
	return code == 200 or code == 204
end

return KomgaSync
