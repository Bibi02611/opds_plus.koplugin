-- Download Manager for OPDS Browser
-- Handles all file download operations, queuing, and progress tracking

local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local url = require("socket.url")
local util = require("util")
local _ = require("utils.locale")
local N_ = _.ngettext
local T = require("ffi/util").template

local Constants = require("models.constants")
local FileUtils = require("utils.file_utils")
local StateManager = require("core.state_manager")
local UrlUtils = require("utils.url_utils")

local DownloadManager = {}

-- Extract filetype from an acquisition link
-- @param link table Acquisition link with href and type
-- @return string|nil File extension or nil if unsupported
function DownloadManager.getFiletype(link)
	local filetype = util.getFileNameSuffix(link.href)
	if not DocumentRegistry:hasProvider("dummy." .. filetype) then
		filetype = nil
	end
	if not filetype and DocumentRegistry:hasProvider(nil, link.type) then
		filetype = DocumentRegistry:mimeToExt(link.type)
	end
	return filetype
end

-- Get the current download directory based on context
-- @param browser table OPDSBrowser instance
-- @return string Download directory path
function DownloadManager.getCurrentDownloadDir(browser)
	if browser.sync then
		return browser.settings.sync_dir
	else
		-- Session-level override (set by user in OPDS+ for this session) takes
		-- priority over the global KOReader download_dir so that BD vs livres
		-- base folders can be switched without touching global settings.
		return browser._session_download_dir
			or G_reader_settings:readSetting("download_dir")
			or G_reader_settings:readSetting("lastdir")
	end
end

-- Build local download path for a file
-- @param browser table OPDSBrowser instance
-- @param filename string|nil Suggested filename (nil → resolved from server headers/URL)
-- @param filetype string File extension (e.g. "cbz")
-- @param remote_url string Acquisition URL
-- @return string Absolute local file path
function DownloadManager.getLocalDownloadPath(browser, filename, filetype, remote_url)

	-- ── Step 1 : base download directory ────────────────────────────────────
	local base_dir = DownloadManager.getCurrentDownloadDir(browser)

	logger.dbg("[OPDS Plus] getLocalDownloadPath in: filename=", filename or "(nil)",
		" filetype=", filetype or "(nil)", " url=", remote_url or "(nil)")

	-- ── Step 2 : series/folder detection ────────────────────────────────────────
	-- Priority 1: browser._default_download_subfolder — set explicitly by the user
	--             for the session; applies to all books until changed or cleared.
	-- Priority 2: browser._download_series — auto-detected from item metadata
	--             (set by BookInfoDialog; may be wrong for edge cases).
	local series_name = browser._default_download_subfolder or browser._download_series
	if series_name and series_name ~= "" then
		series_name = util.replaceAllInvalidChars(series_name)
		logger.dbg("[OPDS Plus] Dossier cible : " .. series_name)
	else
		series_name = nil
	end

	-- ── Step 3 : filename resolution ─────────────────────────────────────────
	local final_filename
	if filename and filename ~= "" then
		-- Suggested name: decode any RFC 2047 MIME words (=?UTF-8?Q?...?=)
		-- then ensure the correct extension is present without doubling it
		final_filename = UrlUtils.decodeFilename(filename)
		final_filename = FileUtils.ensureExtension(final_filename, filetype)
	else
		-- No suggested name: resolve from server Content-Disposition / URL
		-- getServerFileName already applies UrlUtils.decodeFilename internally
		final_filename = browser:getServerFileName(remote_url, filetype)
	end

	logger.dbg("[OPDS Plus] getLocalDownloadPath nom résolu : " .. (final_filename or "(nil)"))

	-- ── Step 4 : path construction & directory creation ──────────────────────
	local target_dir
	if series_name then
		target_dir = base_dir .. "/" .. series_name
		FileUtils.makeDirectory(target_dir)
	else
		target_dir = base_dir
	end

	final_filename = util.getSafeFilename(final_filename, target_dir)
	local full_path = target_dir .. "/" .. final_filename
	full_path = util.fixUtf8(full_path, "_")
	logger.dbg("[OPDS Plus] Chemin final de stockage : " .. full_path)
	return full_path
end

-- Download a file from remote URL to local path
-- @param browser table OPDSBrowser instance
-- @param local_path string Local file path to save to
-- @param remote_url string URL to download from
-- @param username string|nil Optional HTTP auth username
-- @param password string|nil Optional HTTP auth password
-- @param caller_callback function|nil Callback function on success
-- @return boolean True if download succeeded
function DownloadManager.downloadFile(browser, local_path, remote_url, username, password, caller_callback)
	logger.dbg("Downloading file", local_path, "from", remote_url)
	local code, headers, status
	local parsed = url.parse(remote_url)

	if parsed.scheme == "http" or parsed.scheme == "https" then
		-- Ensure the target directory exists. This is defensive: it was created
		-- at queue-build time in the main process, but the download may run in a
		-- subprocess where a prior mkdir failure would silently leave no directory.
		local target_dir = local_path:match("^(.+)/[^/]+$")
		if target_dir then
			FileUtils.makeDirectory(target_dir)
		end

		local file_handle, open_err = io.open(local_path, "w")
		if not file_handle then
			logger.warn("[OPDS Plus] downloadFile: cannot open for writing:", local_path, open_err)
			-- Show error only in main-process context (single-book download)
			UIManager:show(InfoMessage:new {
				text = T(_("Cannot create file:\n%1\n%2"),
					BD.filepath(local_path), open_err or ""),
			})
			return false
		end

		socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
		local req_ok, req_err = pcall(function()
			code, headers, status = socket.skip(1, http.request {
				url      = remote_url,
				headers  = {
					["Accept-Encoding"] = "identity",
				},
				sink     = ltn12.sink.file(file_handle),
				user     = username,
				password = password,
			})
		end)
		socketutil:reset_timeout()
		if not req_ok then
			pcall(file_handle.close, file_handle)
			util.removeFile(local_path)
			logger.warn("[OPDS Plus] downloadFile: network error:", req_err)
			UIManager:show(InfoMessage:new {
				text = T(_("Cannot download file:\n%1\n%2"),
					BD.filepath(local_path), req_err or ""),
			})
			return false
		end
	else
		UIManager:show(InfoMessage:new {
			text = T(_("Invalid protocol:\n%1"), parsed.scheme),
		})
		return false
	end

	if code == 200 then
		logger.dbg("File downloaded to", local_path)
		if caller_callback then
			caller_callback(local_path)
		end
		return true
	elseif code == Constants.HTTP_STATUS.FOUND and remote_url:match("^https") and headers.location:match("^http[^s]") then
		util.removeFile(local_path)
		UIManager:show(InfoMessage:new {
			text = T(_("Insecure HTTPS → HTTP downgrade attempted by redirect from:\n\n'%1'\n\nto\n\n'%2'.\n\nPlease inform the server administrator that many clients disallow this because it could be a downgrade attack."),
				BD.url(remote_url), BD.url(headers.location)),
			icon = "notice-warning",
		})
	else
		util.removeFile(local_path)
		logger.dbg("DownloadManager:downloadFile: Request failed:", status or code)
		logger.dbg("DownloadManager:downloadFile: Response headers:", headers)
		UIManager:show(InfoMessage:new {
			text = T(_("Could not save file to:\n%1\n%2"),
				BD.filepath(local_path),
				status or code or "network unreachable"),
		})
	end

	return false
end

-- Check if file exists and prompt user, then download
-- @param browser table OPDSBrowser instance
-- @param local_path string Local file path to save to
-- @param remote_url string URL to download from
-- @param username string|nil Optional HTTP auth username
-- @param password string|nil Optional HTTP auth password
-- @param caller_callback function|nil Callback function on success
function DownloadManager.checkDownloadFile(browser, local_path, remote_url, username, password, caller_callback)
	local function download()
		UIManager:scheduleIn(Constants.UI_TIMING.DOWNLOAD_SCHEDULE_DELAY, function()
			DownloadManager.downloadFile(browser, local_path, remote_url, username, password, caller_callback)
		end)
		UIManager:show(InfoMessage:new {
			text = _("Downloading…"),
			timeout = Constants.UI_TIMING.NOTIFICATION_TIMEOUT,
		})
	end

	if lfs.attributes(local_path) then
		UIManager:show(ConfirmBox:new {
			text = T(_("The file %1 already exists. Do you want to overwrite it?"), BD.filepath(local_path)),
			ok_text = _("Overwrite"),
			ok_callback = function()
				download()
			end,
		})
	else
		download()
	end
end

-- Download all items in the download queue
-- @param browser table OPDSBrowser instance
-- @return number Count of successfully downloaded files
function DownloadManager.downloadDownloadList(browser)
	local info = InfoMessage:new { text = _("Downloading… (tap to cancel)") }
	UIManager:show(info)
	UIManager:forceRePaint()

	local completed, downloaded = Trapper:dismissableRunInSubprocess(function()
		local dl = {}
		for _, item in ipairs(browser.downloads) do
			if DownloadManager.downloadFile(browser, item.file, item.url, item.username, item.password) then
				dl[item.file] = true
			end
		end
		return dl
	end, info)

	if completed then
		UIManager:close(info)
	end

	local dl_count = #browser.downloads
	for i = dl_count, 1, -1 do
		local item = browser.downloads[i]
		if downloaded and downloaded[item.file] then
			table.remove(browser.downloads, i)
		else -- if subprocess has been interrupted, check for the downloaded file
			local attr = lfs.attributes(item.file)
			if attr then
				if attr.size > 0 then
					table.remove(browser.downloads, i)
				else -- incomplete download
					os.remove(item.file)
				end
			end
		end
	end

	dl_count = dl_count - #browser.downloads
	if dl_count > 0 then
		browser:updateDownloadListItemTable()
		browser.download_list_updated = true
		StateManager.getInstance():markDirty()
		UIManager:show(InfoMessage:new {
			text = T(N_("1 book downloaded", "%1 books downloaded", dl_count), dl_count)
		})
	end

	return dl_count
end

-- Download pending sync items
-- @param browser table OPDSBrowser instance
-- @param dl_list table List of items to download
-- @return table|nil List of duplicate files or nil
function DownloadManager.downloadPendingSyncs(browser, dl_list)
	local function dismissable_download()
		local info = InfoMessage:new { text = _("Downloading… (tap to cancel)") }
		UIManager:show(info)
		UIManager:forceRePaint()

		local completed, downloaded, duplicate_list = Trapper:dismissableRunInSubprocess(function()
			local dl = {}
			local dupe_list = {}
			for _, item in ipairs(dl_list) do
				if browser.sync_server_list[item.catalog] then
					if lfs.attributes(item.file) and not browser.sync_force then
						table.insert(dupe_list, item)
					else
						if DownloadManager.downloadFile(browser, item.file, item.url, item.username, item.password) then
							dl[item.file] = true
						end
					end
				end
			end
			return dl, dupe_list
		end, info)

		if completed then
			UIManager:close(info)
		end

		local dl_count = 0
		local dl_size = #dl_list
		for i = dl_size, 1, -1 do
			local item = dl_list[i]
			if downloaded and downloaded[item.file] then
				dl_count = dl_count + 1
				table.remove(dl_list, i)
			else -- if subprocess has been interrupted, check for the downloaded file
				local attr = lfs.attributes(item.file)
				if attr then
					if attr.size > 0 then
						table.remove(dl_list, i)
						-- Only count files touched within the freshness window
						if attr.modification > os.time() - Constants.SYNC.DOWNLOAD_FRESHNESS_SECONDS then
							dl_count = dl_count + 1
						end
					else -- incomplete download
						os.remove(item.file)
					end
				end
			end
		end

		local duplicate_count = duplicate_list and #duplicate_list or 0
		dl_count = dl_count - duplicate_count

		-- Make downloaded count timeout if there's a duplicate file prompt
		local timeout = nil
		if duplicate_count > 0 then
			timeout = Constants.UI_TIMING.DUPLICATE_NOTIFICATION_TIMEOUT
		end

		if dl_count > 0 then
			UIManager:show(InfoMessage:new {
				text = T(N_("1 book downloaded", "%1 books downloaded", dl_count), dl_count),
				timeout = timeout,
			})
		end

		StateManager.getInstance():markDirty()
		return duplicate_list
	end

	return dismissable_download()
end

-- Add item to download queue
-- @param browser table OPDSBrowser instance
-- @param download_item table Item with file, url, username, password, info, catalog
function DownloadManager.addToDownloadQueue(browser, download_item)
	table.insert(browser.downloads, download_item)
	StateManager.getInstance():markDirty()
end

-- Remove item from download queue
-- @param browser table OPDSBrowser instance
-- @param index number Index of item to remove
function DownloadManager.removeFromDownloadQueue(browser, index)
	table.remove(browser.downloads, index)
	StateManager.getInstance():markDirty()
end

-- Clear all items from download queue
-- @param browser table OPDSBrowser instance
function DownloadManager.clearDownloadQueue(browser)
	for i in ipairs(browser.downloads) do
		browser.downloads[i] = nil
	end
	browser.download_list_updated = true
	StateManager.getInstance():markDirty()
end

return DownloadManager
