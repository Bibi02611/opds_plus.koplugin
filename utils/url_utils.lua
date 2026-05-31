-- URL utility functions for OPDS operations
-- Handles URL construction, parsing, and manipulation

local logger = require("logger")
local url = require("socket.url")

local UrlUtils = {}

-- Decode a base64 string (used by RFC 2047 B-encoding)
local function decodeBase64(text)
	local b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	text = text:gsub("[^" .. b64 .. "=]", "")
	local result = {}
	for i = 1, #text, 4 do
		local a = (b64:find(text:sub(i,   i),   1, true) or 1) - 1
		local b = (b64:find(text:sub(i+1, i+1), 1, true) or 1) - 1
		local c = (b64:find(text:sub(i+2, i+2), 1, true) or 1) - 1
		local d = (b64:find(text:sub(i+3, i+3), 1, true) or 1) - 1
		local n = a * 262144 + b * 4096 + c * 64 + d
		local b1 = math.floor(n / 65536)
		local b2 = math.floor((n % 65536) / 256)
		local b3 = n % 256
		if text:sub(i+3, i+3) == "=" then
			if text:sub(i+2, i+2) == "=" then
				table.insert(result, string.char(b1))
			else
				table.insert(result, string.char(b1, b2))
			end
		else
			table.insert(result, string.char(b1, b2, b3))
		end
	end
	return table.concat(result)
end

-- Decode RFC 2047 encoded words: =?charset?Q|B?text?=
-- Handles both Quoted-Printable (Q) and Base64 (B) encodings.
-- Multiple consecutive encoded words are concatenated.
-- NOTE: in Q-encoding, _ → space MUST be done before =XX → byte,
-- because _ is never a valid hex digit so it cannot appear inside =XX.
-- The order is preserved intentionally here.
local function decodeMimeWords(str)
	local decoded = str:gsub("=%?[^%?]+%?([QqBb])%?([^%?]*)%?=", function(enc, text)
		if enc:upper() == "Q" then
			text = text:gsub("_", " ")              -- step 1: underscore → space
			text = text:gsub("=(%x%x)", function(hex) -- step 2: =XX → byte
				return string.char(tonumber(hex, 16))
			end)
			return text
		else -- "B"
			return decodeBase64(text)
		end
	end)
	return decoded
end

--- Build an absolute URL from a base URL and relative href
-- @param base_url string Base URL
-- @param href string Relative or absolute URL
-- @return string Absolute URL
function UrlUtils.buildAbsolute(base_url, href)
	return url.absolute(base_url, href)
end

--- Extract filename from URL, handling query parameters and URL decoding
-- @param item_url string URL to extract filename from
-- @return string Extracted and decoded filename
function UrlUtils.extractFilename(item_url)
	-- Remove query parameters and fragments
	local filename = item_url:gsub("?.*", ""):gsub("#.*", "")

	-- Extract just the filename part
	filename = filename:gsub(".*/", "")

	-- URL decode the filename
	filename = url.unescape(filename)

	return filename
end

--- Parse filename from Content-Disposition header
-- Supports RFC 5987 (filename*=UTF-8''...), RFC 2047 (=?charset?Q/B?...?=),
-- plain quoted/unquoted filenames, and malformed Komga-style headers like:
--   filename==?UTF-8?Q?T17_-_Le_domaine_des_dieux.cbz?=
-- @param disposition string Content-Disposition header value
-- @return string|nil Decoded filename or nil
function UrlUtils.parseContentDisposition(disposition)
	if not disposition then return nil end

	-- RFC 5987: filename*=UTF-8''percent%2Dencoded (highest priority, unambiguous)
	local filename = disposition:match("filename%*=%s*[Uu][Tt][Ff]%-8''([^;%s]+)")
	if filename then
		local result = url.unescape(filename)
		logger.dbg("OPDS parseContentDisposition RFC5987:", result)
		return result
	end

	-- Capture EVERYTHING after filename= to end of string (case-insensitive key)
	local raw = disposition:match("[Ff][Ii][Ll][Ee][Nn][Aa][Mm][Ee]=(.+)$")
	if not raw then return nil end

	-- Remove everything from the first ; onward (other header params)
	raw = raw:match("^([^;]+)") or raw
	-- Strip CR/LF that may trail HTTP header lines
	raw = raw:gsub("[\r\n]", "")
	-- Trim leading/trailing whitespace
	raw = raw:match("^%s*(.-)%s*$")

	logger.dbg("OPDS parseContentDisposition raw:", raw)

	-- Remove surrounding double-quotes if present: "example.epub" → example.epub
	local value = raw:match('^"(.*)"$') or raw

	-- Decode based on content
	local decoded
	if value:find("=%?") then
		-- RFC 2047 encoded word(s) detected
		decoded = decodeMimeWords(value)
		-- Also percent-decode in case of mixed encoding after MIME decode
		decoded = url.unescape(decoded)
	else
		-- Plain value: just percent-decode
		decoded = url.unescape(value)
	end

	-- Strip any quotes that survived decoding
	decoded = decoded:match('^"(.*)"$') or decoded
	-- Final whitespace trim
	decoded = decoded:match("^%s*(.-)%s*$")

	logger.dbg("OPDS parseContentDisposition final:", decoded)

	if decoded ~= "" then
		return decoded
	end
	return nil
end

--- Decode a raw filename that may contain RFC 2047 MIME words and/or percent-encoding.
-- Use this when a filename comes from a Location URL path segment or a bare URL,
-- not from a Content-Disposition header (use parseContentDisposition for that).
-- @param filename string Raw filename string
-- @return string Decoded filename (never nil, returns original if nothing to decode)
function UrlUtils.decodeFilename(filename)
	if not filename or filename == "" then return filename or "" end
	-- RFC 2047 MIME word decoding (=?charset?Q/B?...?=)
	if filename:find("=%?") then
		filename = filename:gsub("=%?[^%?]+%?([QqBb])%?([^%?]*)%?=", function(enc, text)
			if enc:upper() == "Q" then
				text = text:gsub("_", " ")
				text = text:gsub("=(%x%x)", function(hex)
					return string.char(tonumber(hex, 16))
				end)
				return text
			else
				return decodeBase64(text)
			end
		end)
	end
	-- Percent-encoding decode
	filename = url.unescape(filename)
	return filename
end

--- Determine if a URL is searchable (contains %s placeholder)
-- @param catalog_url string URL to check
-- @return boolean True if URL contains search placeholder
function UrlUtils.isSearchable(catalog_url)
	return catalog_url and catalog_url:match("%%s") and true or false
end

--- Create a search URL by replacing search terms placeholder
-- @param template string URL template with {searchTerms} or %s
-- @param search_query string Search query (already URL encoded)
-- @return string Search URL with query inserted
function UrlUtils.buildSearchUrl(template, search_query)
	if not template or not search_query then return nil end

	-- Handle both {searchTerms} and %s patterns
	local search_url = template:gsub("{searchTerms}", search_query)
	search_url = search_url:gsub("%%s", search_query)

	return search_url
end

--- Check if a link should be treated as a catalog navigation link
-- @param link table Link object from OPDS feed
-- @param catalog_type string Expected catalog MIME type pattern
-- @return boolean True if link is a navigation link
function UrlUtils.isCatalogNavigationLink(link, catalog_type)
	if not link.type or not link.type:find(catalog_type) then
		return false
	end

	-- Check if rel is not set or is a subsection/sort type
	return not link.rel
		or link.rel == "subsection"
		or link.rel == "http://opds-spec.org/subsection"
		or link.rel == "http://opds-spec.org/sort/popular"
		or link.rel == "http://opds-spec.org/sort/new"
end

--- Check if a link should be treated as an acquisition link
-- @param link table Link object from OPDS feed
-- @param acquisition_pattern string Pattern to match acquisition rel
-- @return boolean True if link is an acquisition link
function UrlUtils.isAcquisitionLink(link, acquisition_pattern)
	return link.rel and link.rel:match(acquisition_pattern)
end

return UrlUtils
