-- File utility functions for OPDS operations
-- Handles filename manipulation and validation

local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local FileUtils = {}

--- Add file extension if the filename does not already end with the correct one.
-- A dot in the middle of the title (e.g. "Vol.1", "Tome 1.5") must not prevent
-- the real extension from being appended.
-- @param filename string Original filename (may come from OPDS metadata)
-- @param filetype string Desired file extension without dot (e.g. "cbz")
-- @return string Filename ending with .filetype
function FileUtils.ensureExtension(filename, filetype)
	if not filename or not filetype then return filename end
	local current_suffix = util.getFileNameSuffix(filename)
	-- Only skip if the filename already ends with exactly the right extension
	if current_suffix and current_suffix:lower() == filetype:lower() then
		return filename
	end
	return filename .. "." .. filetype:lower()
end

--- Create a directory, including any missing parent directories.
-- @param path string Absolute directory path to create
function FileUtils.makeDirectory(path)
	if not path or path == "" or path == "/" then return end
	if lfs.attributes(path) then return end  -- already exists
	-- Ensure parent exists first (recursive)
	local parent = path:match("^(.+)/[^/]+/?$")
	if parent and parent ~= path then
		FileUtils.makeDirectory(parent)
	end
	lfs.mkdir(path)
end

--- Sanitize filename for safe filesystem usage
-- @param filename string Original filename
-- @param directory string Target directory path
-- @return string Safe filename
function FileUtils.sanitize(filename, directory)
	return util.getSafeFilename(filename, directory)
end

--- Fix UTF-8 encoding issues in filename
-- @param filename string Filename to fix
-- @param replacement string Character to replace invalid UTF-8 (default: "_")
-- @return string Fixed filename
function FileUtils.fixUtf8(filename, replacement)
	return util.fixUtf8(filename, replacement or "_")
end

return FileUtils
