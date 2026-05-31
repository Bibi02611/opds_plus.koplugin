-- Book Info Dialog Builder for OPDS Browser
-- Displays book information with download/queue actions

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local MovableContainer = require("ui/widget/container/movablecontainer")
local RenderImage = require("ui/renderimage")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local url = require("socket.url")
local util = require("util")
local T_get = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

local Constants = require("models.constants")
local OPDSPSE = require("services.kavita")
local UrlUtils = require("utils.url_utils")

local BookInfoDialog = {}

--- Format available download formats as a string
-- @param acquisitions table List of acquisition links
-- @param DownloadManager table DownloadManager module
-- @return string Formatted list of available formats
local function formatAvailableFormats(acquisitions, DownloadManager)
	local formats = {}
	for i, acquisition in ipairs(acquisitions) do
		if acquisition.count then
			-- PSE streaming
			table.insert(formats, T_get("Stream") .. " (" .. acquisition.count .. " " .. T_get("pages") .. ")")
		elseif acquisition.type == "borrow" then
			table.insert(formats, T_get("Borrow"))
		else
			local filetype = DownloadManager.getFiletype(acquisition)
			if filetype then
				table.insert(formats, string.upper(filetype))
			end
		end
	end
	if #formats == 0 then
		return T_get("None available")
	end
	return table.concat(formats, ", ")
end

--- Check if item has PSE streaming available
-- @param acquisitions table List of acquisitions
-- @return table|nil PSE acquisition or nil
local function getPSEAcquisition(acquisitions)
	for _, acquisition in ipairs(acquisitions) do
		if acquisition.count then
			return acquisition
		end
	end
	return nil
end

--- Get downloadable acquisitions (non-PSE, non-borrow)
-- @param acquisitions table List of acquisitions
-- @param DownloadManager table DownloadManager module
-- @return table List of downloadable acquisitions with filetype
local function getDownloadableAcquisitions(acquisitions, DownloadManager)
	local downloadable = {}
	for _, acquisition in ipairs(acquisitions) do
		if not acquisition.count and acquisition.type ~= "borrow" then
			local filetype = DownloadManager.getFiletype(acquisition)
			if filetype then
				table.insert(downloadable, {
					acquisition = acquisition,
					filetype = filetype,
				})
			end
		end
	end
	return downloadable
end

--- Show format selection dialog for download
-- @param browser table OPDSBrowser instance
-- @param item table Book item
-- @param downloadable table List of downloadable acquisitions
-- @param add_to_queue boolean If true, add to queue instead of download
-- @param parent_dialog table Parent dialog to close
local function showFormatSelectionDialog(browser, item, downloadable, add_to_queue, parent_dialog)
	local DownloadManager = require("core.download_manager")
	-- Capture BEFORE any UIManager:close() — onCloseWidget clears both fields
	local series_snapshot = browser._download_series
	local buttons = {}

	for _, dl in ipairs(downloadable) do
		local text = url.unescape(dl.acquisition.title or string.upper(dl.filetype))
		table.insert(buttons, {
			{
				text = text,
				callback = function()
					-- IMPORTANT: Capture BEFORE closing — onCloseWidget clears these fields
					local filename = browser._custom_filename

					UIManager:close(browser.format_dialog)
					if parent_dialog then
						UIManager:close(parent_dialog)
					end

					-- Restore series after onCloseWidget cleared it
					browser._download_series = series_snapshot

					local local_path = DownloadManager.getLocalDownloadPath(
						browser, filename, dl.filetype, dl.acquisition.href)

					if add_to_queue then
						DownloadManager.addToDownloadQueue(browser, {
							file     = local_path,
							url      = dl.acquisition.href,
							info     = type(item.content) == "string" and util.htmlToPlainTextIfHtml(item.content) or "",
							catalog  = browser.root_catalog_title,
							username = browser.root_catalog_username,
							password = browser.root_catalog_password,
						})
						UIManager:show(InfoMessage:new {
							text = T(T_get("Added to queue:\n%1"), item.title or T_get("Unknown")),
							timeout = 2,
						})
					else
						DownloadManager.checkDownloadFile(browser, local_path, dl.acquisition.href,
							browser.root_catalog_username, browser.root_catalog_password,
							browser.file_downloaded_callback)
					end
				end,
			},
		})
	end

	-- Add cancel button
	table.insert(buttons, {})
	table.insert(buttons, {
		{
			text = T_get("Cancel"),
			callback = function()
				UIManager:close(browser.format_dialog)
			end,
		},
	})

	local title = add_to_queue and T_get("Select format to queue") or T_get("Select format to download")

	browser.format_dialog = ButtonDialog:new {
		title = title,
		buttons = buttons,
	}
	UIManager:show(browser.format_dialog)
end

--- Build the book info dialog
-- Shows book information with action buttons and cover image
-- @param browser table OPDSBrowser instance
-- @param item table Book item with acquisitions
-- @return table Dialog widget
function BookInfoDialog.build(browser, item)
	local DownloadManager = require("core.download_manager")
	local ImageLoader = require("services.image_loader")

	-- Store custom filename in the browser context for this item
	-- Initialize with default filename
	local base_filename = item.title
	if item.author then
		base_filename = item.author .. " - " .. base_filename
	end
	if browser.root_catalog_raw_names then
		browser._custom_filename = nil
	else
		browser._custom_filename = browser._custom_filename or util.replaceAllInvalidChars(base_filename)
	end

	-- ── Dump item fields for Komga inspection (temporary debug) ────────────────
	logger.warn("[OPDS Plus] ── ITEM DUMP ──")
	for k, v in pairs(item) do
		local tv = type(v)
		if tv == "string" or tv == "number" or tv == "boolean" then
			logger.warn("[OPDS Plus] ITEM DATA: " .. tostring(k) .. " = " .. tostring(v))
		else
			logger.warn("[OPDS Plus] ITEM DATA: " .. tostring(k) .. " = [" .. tv .. "]")
		end
	end
	logger.warn("[OPDS Plus] ── FIN DUMP ──")

	-- ── Series detection for subdirectory organisation ───────────────────────
	-- Priority 1 : item.links (rel="up" / "collection") — authoritative server metadata
	--              The server (Komga) sets the title on the parent link; this is
	--              the true series name regardless of how the user arrived here.
	-- Priority 2 : item.series — explicit OPDS dc:series field (when sent by server)
	-- Priority 3 : title prefix — text before " - " or " N:" in the decoded title
	--              (fallback for servers that don't expose navigation links)
	-- Priority 4 : catalog_title — current navigation context, only if not a
	--              generic collection name (Keep Reading, On Deck, etc.)
	-- The root catalog title (server name) is never used as a series name.
	local GENERIC_CATALOG_BLACKLIST = {
		["Keep Reading"]    = true,
		["On Deck"]         = true,
		["Recently Added"]  = true,
		["Bibliothèque"]    = true,
	}

	local raw_series = nil
	local series_source = nil

	-- Priority 1 : parent / collection links — most authoritative source
	if item.links then
		for _, link in ipairs(item.links) do
			if link.title and link.title ~= "" then
				local candidate = UrlUtils.decodeFilename(link.title)
				if not GENERIC_CATALOG_BLACKLIST[candidate] then
					raw_series = candidate
					series_source = "lien parent (" .. (link.rel or "?") .. ")"
					logger.warn("[OPDS Plus] Série identifiée via lien parent : " .. tostring(raw_series))
					break
				end
			end
		end
	end

	-- Priority 2 : explicit series field
	if not raw_series and item.series and item.series ~= "" then
		raw_series = item.series
		series_source = "item.series"
	end

	-- Priority 3 : title prefix (fallback when server omits navigation links)
	-- Pattern A: "Series - Title"   e.g. "Blacksad - Tome 01"  → "Blacksad"
	-- Pattern B: "Series N: Title"  e.g. "Largo Winch 6: ..."  → "Largo Winch"
	if not raw_series then
		local decoded_title = UrlUtils.decodeFilename(item.title or "")
		local prefix = decoded_title:match("^(.-)%s+%-%s+")
		if not prefix or prefix == "" then
			prefix = decoded_title:match("^(.-)%s+%d[%d%.]*%s*:")
		end
		if prefix and prefix ~= "" then
			raw_series = UrlUtils.decodeFilename(prefix)
			series_source = "titre (extraction)"
		end
	end

	-- Priority 4 : catalog_title, only if not generic and not the root catalog
	if not raw_series then
		local cat = browser.catalog_title
		if cat and cat ~= "" and cat ~= browser.root_catalog_title and not GENERIC_CATALOG_BLACKLIST[cat] then
			raw_series = cat
			series_source = "catalog_title"
		end
	end

	browser._download_series = raw_series and UrlUtils.decodeFilename(raw_series) or nil
	logger.warn("[OPDS Plus] Source du nom de dossier choisie : " .. (series_source or "(aucune)"))
	logger.warn("[OPDS Plus] _download_series = " .. (browser._download_series or "(nil)"))
	-- Snapshot for callbacks: onCloseWidget clears browser._download_series before
	-- getLocalDownloadPath runs, so every download callback must restore it.
	local series_snapshot = browser._download_series

	-- Get PSE and downloadable acquisitions
	local pse_acquisition = getPSEAcquisition(item.acquisitions)
	local downloadable = getDownloadableAcquisitions(item.acquisitions, DownloadManager)

	-- Dialog dimensions
	local screen_width = Screen:getWidth()
	local screen_height = Screen:getHeight()
	local dialog_width = math.floor(screen_width * 0.9)
	local dialog_height = math.floor(screen_height * 0.85)

	-- Cover image dimensions - larger for the dialog
	local cover_height = math.floor(screen_height * 0.25)
	local cover_width = math.floor(cover_height * (2 / 3)) -- book aspect ratio

	-- Cover link for full view and high-res loading
	local cover_link = item.image or item.thumbnail

	-- Function to show full cover
	local function showFullCover()
		if cover_link then
			OPDSPSE:streamPages(cover_link, 1, false,
				browser.root_catalog_username, browser.root_catalog_password)
		end
	end

	-- Build cover widget - make it tappable
	local cover_container
	local dialog_cover_bb = nil -- Track our high-res cover for cleanup

	if item.cover_bb or cover_link then
		-- Create the image widget (start with low-res if available, or placeholder)
		local initial_cover_widget
		if item.cover_bb then
			initial_cover_widget = ImageWidget:new {
				image = item.cover_bb,
				width = cover_width,
				height = cover_height,
				scale_factor = 0,
				alpha = true,
				image_disposable = false, -- Don't free the menu's cover_bb
			}
		else
			-- Placeholder while loading
			initial_cover_widget = CenterContainer:new {
				dimen = Geom:new { w = cover_width, h = cover_height },
				TextWidget:new {
					text = "📖",
					face = Font:getFace("cfont", 48),
				},
			}
		end

		-- Wrap in InputContainer to make it tappable
		cover_container = InputContainer:new {
			dimen = Geom:new { w = cover_width, h = cover_height },
			initial_cover_widget,
		}
		cover_container.ges_events = {
			TapCover = {
				GestureRange:new {
					ges = "tap",
					range = cover_container.dimen,
				},
			},
		}
		function cover_container:onTapCover()
			showFullCover()
			return true
		end

		-- Load high-res cover asynchronously if we have a URL
		if cover_link then
			local function updateCoverWidget(content)
				-- Render at higher resolution for the dialog
				local target_height = cover_height * 2 -- 2x resolution
				local target_width = cover_width * 2
				local ok, hi_res_bb = pcall(function()
					return RenderImage:renderImageData(
						content,
						#content,
						false,
						target_width,
						target_height
					)
				end)

				if ok and hi_res_bb then
					-- Store for cleanup
					dialog_cover_bb = hi_res_bb

					-- Create new high-res image widget
					local new_cover_widget = ImageWidget:new {
						image = hi_res_bb,
						width = cover_width,
						height = cover_height,
						scale_factor = 0,
						alpha = true,
						image_disposable = false, -- We'll free it ourselves
					}

					-- Update the container
					cover_container[1] = new_cover_widget

					-- Refresh the dialog
					UIManager:setDirty(browser.book_info_dialog, "ui")
				end
			end

			-- Start async load
			ImageLoader:loadImages(
				{ cover_link },
				function(loaded_url, content)
					updateCoverWidget(content)
				end,
				browser.root_catalog_username,
				browser.root_catalog_password,
				browser.settings and browser.settings.cover_cache_enabled ~= false,
				browser.settings and browser.settings.cover_cache_max_mb,
				browser.settings and browser.settings.cover_cache_ttl_minutes
			)
		end
	end

	-- Build info text parts
	local info_parts = {}

	-- Author
	if item.author then
		table.insert(info_parts, {
			label = T_get("Author"),
			value = item.author,
		})
	end

	-- Available formats
	table.insert(info_parts, {
		label = T_get("Formats"),
		value = formatAvailableFormats(item.acquisitions, DownloadManager),
	})

	-- Build the text info widget
	local text_width = dialog_width - cover_width - Size.padding.large * 4
	if not cover_container then
		text_width = dialog_width - Size.padding.large * 2
	end

	local info_text_parts = {}
	for _, part in ipairs(info_parts) do
		table.insert(info_text_parts, TextBoxWidget.PTF_BOLD_START .. part.label .. ":" .. TextBoxWidget.PTF_BOLD_END)
		table.insert(info_text_parts, " " .. part.value .. "\n")
	end

	local info_widget = TextBoxWidget:new {
		text = TextBoxWidget.PTF_HEADER .. table.concat(info_text_parts),
		width = text_width,
		face = Font:getFace("x_smallinfofont"),
		alignment = "left",
	}

	-- Header row with cover and info
	local header_content
	if cover_container then
		header_content = HorizontalGroup:new {
			align = "top",
			CenterContainer:new {
				dimen = Geom:new { w = cover_width + Size.padding.default, h = cover_height },
				cover_container,
			},
			HorizontalSpan:new { width = Size.padding.default },
			info_widget,
		}
	else
		header_content = info_widget
	end

	-- Description section
	local description_text = T_get("No description available.")
	if item.content and type(item.content) == "string" then
		description_text = util.htmlToPlainTextIfHtml(item.content)
	end

	-- Calculate remaining height for description
	local title_bar_height = Size.padding.large * 3 -- approximate
	local header_height = cover_container and cover_height or info_widget:getSize().h
	local button_height = Size.padding.large * 4 -- approximate for buttons
	local description_height = dialog_height - title_bar_height - header_height - button_height - Size.padding.large * 4

	local description_widget = ScrollableContainer:new {
		dimen = Geom:new {
			w = dialog_width - Size.padding.large * 2,
			h = math.max(description_height, 100),
		},
		show_parent = browser,
		VerticalGroup:new {
			align = "left",
			VerticalSpan:new { height = Size.padding.small },
			TextBoxWidget:new {
				text = TextBoxWidget.PTF_HEADER .. TextBoxWidget.PTF_BOLD_START .. T_get("Description") .. TextBoxWidget.PTF_BOLD_END,
				width = dialog_width - Size.padding.large * 4,
				face = Font:getFace("x_smallinfofont"),
			},
			VerticalSpan:new { height = Size.padding.small },
			TextBoxWidget:new {
				text = description_text,
				width = dialog_width - Size.padding.large * 4,
				face = Font:getFace("x_smallinfofont"),
				alignment = "left",
			},
		},
	}

	-- Build buttons
	local buttons_table = {}

	-- Row 1: Stream buttons (if PSE available)
	if pse_acquisition then
		local stream_row = {
			{
				text = Constants.ICONS.STREAM_START .. " " .. T_get("Stream"),
				callback = function()
					UIManager:close(browser.book_info_dialog)
					OPDSPSE:streamPages(pse_acquisition.href, pse_acquisition.count, false,
						browser.root_catalog_username, browser.root_catalog_password)
				end,
			},
			{
				text = T_get("Stream from page") .. " " .. Constants.ICONS.STREAM_NEXT,
				callback = function()
					UIManager:close(browser.book_info_dialog)
					OPDSPSE:streamPages(pse_acquisition.href, pse_acquisition.count, true,
						browser.root_catalog_username, browser.root_catalog_password)
				end,
			},
		}

		if pse_acquisition.last_read then
			table.insert(buttons_table, stream_row)
			table.insert(buttons_table, {
				text = Constants.ICONS.STREAM_RESUME .. " " .. T_get("Resume") .. " (" .. pse_acquisition.last_read .. ")",
				callback = function()
					UIManager:close(browser.book_info_dialog)
					OPDSPSE:streamPages(pse_acquisition.href, pse_acquisition.count, false,
						browser.root_catalog_username, browser.root_catalog_password,
						pse_acquisition.last_read)
				end,
			})
		else
			table.insert(buttons_table, stream_row)
		end
	end

	-- Row 2: Download and Queue buttons
	if #downloadable > 0 then
		local action_row = {}

		-- Download button
		if #downloadable == 1 then
			local dl = downloadable[1]
			table.insert(action_row, {
				text = Constants.ICONS.DOWNLOAD .. " " .. T_get("Download") .. " (" .. string.upper(dl.filetype) .. ")",
				callback = function()
					-- Capture BEFORE closing — onCloseWidget clears these fields
					local filename = browser._custom_filename
					UIManager:close(browser.book_info_dialog)
					browser._download_series = series_snapshot  -- restore after onCloseWidget
					local local_path = DownloadManager.getLocalDownloadPath(
						browser, filename, dl.filetype, dl.acquisition.href)
					DownloadManager.checkDownloadFile(browser, local_path, dl.acquisition.href,
						browser.root_catalog_username, browser.root_catalog_password,
						browser.file_downloaded_callback)
				end,
			})
		else
			table.insert(action_row, {
				text = Constants.ICONS.DOWNLOAD .. " " .. T_get("Download…"),
				callback = function()
					showFormatSelectionDialog(browser, item, downloadable, false, browser.book_info_dialog)
				end,
			})
		end

		-- Add to queue button
		if #downloadable == 1 then
			local dl = downloadable[1]
			table.insert(action_row, {
				text = "+" .. " " .. T_get("Queue"),
				callback = function()
					-- Capture BEFORE closing — onCloseWidget clears these fields
					local filename = browser._custom_filename
					local book_title = item.title or T_get("Unknown")
					UIManager:close(browser.book_info_dialog)
					browser._download_series = series_snapshot  -- restore after onCloseWidget
					local local_path = DownloadManager.getLocalDownloadPath(
						browser, filename, dl.filetype, dl.acquisition.href)
					DownloadManager.addToDownloadQueue(browser, {
						file     = local_path,
						url      = dl.acquisition.href,
						info     = type(item.content) == "string" and util.htmlToPlainTextIfHtml(item.content) or "",
						catalog  = browser.root_catalog_title,
						username = browser.root_catalog_username,
						password = browser.root_catalog_password,
					})
					UIManager:show(InfoMessage:new {
						text = T(T_get("Added to queue:\n%1"), book_title),
						timeout = 2,
					})
				end,
			})
		else
			table.insert(action_row, {
				text = "+" .. " " .. T_get("Queue…"),
				callback = function()
					showFormatSelectionDialog(browser, item, downloadable, true, browser.book_info_dialog)
				end,
			})
		end

		table.insert(buttons_table, action_row)

		-- Two-button row showing the full effective destination.
		-- Left button  → choose base folder (session override, does not touch global KOReader setting)
		-- Right button → edit the subfolder name
		local function getBaseDirLabel()
			local d = browser._session_download_dir
				or G_reader_settings:readSetting("download_dir")
				or G_reader_settings:readSetting("lastdir")
				or "?"
			-- Show only the last path component so it fits in the button
			return d:match("[^/]+/?$") or d
		end

		local function getSubfolderLabel()
			if browser._default_download_subfolder then
				return browser._default_download_subfolder
			elseif auto_series then
				return auto_series .. " " .. T_get("(auto)")
			else
				return T_get("(none)")
			end
		end

		table.insert(buttons_table, {
			-- Left: base directory
			{
				text = getBaseDirLabel(),
				callback = function()
					require("ui/downloadmgr"):new {
						onConfirm = function(path)
							logger.dbg("Session download dir set to", path)
							browser._session_download_dir = path
						end,
					}:chooseDir(DownloadManager.getCurrentDownloadDir(browser))
				end,
			},
			-- Right: subfolder name
			{
				text = getSubfolderLabel(),
				callback = function()
					local current = browser._default_download_subfolder or auto_series or ""
					local subfolder_dialog
					subfolder_dialog = InputDialog:new {
						title = T_get("Subfolder name"),
						input = current,
						input_hint = auto_series or "",
						buttons = {
							{
								{
									text = T_get("Cancel"),
									id = "close",
									callback = function()
										UIManager:close(subfolder_dialog)
									end,
								},
								{
									text = T_get("Clear"),
									callback = function()
										browser._default_download_subfolder = nil
										UIManager:close(subfolder_dialog)
									end,
								},
								{
									text = T_get("Set"),
									is_enter_default = true,
									callback = function()
										local val = subfolder_dialog:getInputText()
										if val and val ~= "" then
											browser._default_download_subfolder = util.replaceAllInvalidChars(val)
										else
											browser._default_download_subfolder = nil
										end
										UIManager:close(subfolder_dialog)
									end,
								},
							}
						},
					}
					UIManager:show(subfolder_dialog)
					subfolder_dialog:onShowKeyboard()
				end,
			},
		})
	end

	-- Row 3: Additional options
	local options_row = {}

	-- View full cover button (only if cover exists)
	if cover_link then
		table.insert(options_row, {
			text = T_get("Full Cover"),
			callback = showFullCover,
		})
	end

	-- Download options button
	table.insert(options_row, {
		text = T_get("Options…"),
		callback = function()
			BookInfoDialog.showDownloadOptionsDialog(browser, item)
		end,
	})

	-- Close button
	table.insert(options_row, {
		text = T_get("Close"),
		callback = function()
			UIManager:close(browser.book_info_dialog)
		end,
	})

	if #options_row > 0 then
		table.insert(buttons_table, options_row)
	end

	-- Create button table widget
	local button_table = ButtonTable:new {
		width = dialog_width - Size.padding.large * 2,
		buttons = buttons_table,
		zero_sep = true,
		show_parent = browser,
	}

	-- Main content layout
	local content = VerticalGroup:new {
		align = "center",
		VerticalSpan:new { height = Size.padding.default },
		header_content,
		VerticalSpan:new { height = Size.padding.default },
		description_widget,
		VerticalSpan:new { height = Size.padding.default },
		button_table,
	}

	-- Title bar
	local title_bar = TitleBar:new {
		title = item.title or T_get("Book Information"),
		fullscreen = true,
		width = dialog_width,
		with_bottom_line = true,
		bottom_line_color = Blitbuffer.COLOR_DARK_GRAY,
		bottom_line_h_padding = Size.padding.large,
		close_callback = function()
			UIManager:close(browser.book_info_dialog)
		end,
		show_parent = browser,
	}

	-- Frame the content
	local content_frame = FrameContainer:new {
		padding = Size.padding.default,
		padding_top = 0,
		margin = 0,
		bordersize = 0,
		background = Blitbuffer.COLOR_WHITE,
		content,
	}

	-- Complete dialog layout
	local dialog_frame = FrameContainer:new {
		radius = Size.radius.window,
		bordersize = Size.border.window,
		background = Blitbuffer.COLOR_WHITE,
		padding = 0,
		margin = 0,
		VerticalGroup:new {
			align = "center",
			title_bar,
			content_frame,
		},
	}

	-- Create the dialog as an InputContainer for gesture handling
	browser.book_info_dialog = InputContainer:new {
		ignore_events = { "swipe", "pan", "pan_release" },
	}
	browser.book_info_dialog.dimen = Geom:new {
		w = dialog_width,
		h = dialog_height,
	}
	browser.book_info_dialog.movable = MovableContainer:new {
		dialog_frame,
	}
	browser.book_info_dialog[1] = CenterContainer:new {
		dimen = Geom:new {
			w = screen_width,
			h = screen_height,
		},
		browser.book_info_dialog.movable,
	}

	-- Add close on tap outside
	browser.book_info_dialog.ges_events = {
		TapClose = {
			GestureRange:new {
				ges = "tap",
				range = Geom:new {
					x = 0, y = 0,
					w = screen_width,
					h = screen_height,
				},
			},
		},
	}

	function browser.book_info_dialog:onTapClose(arg, ges)
		if ges.pos:notIntersectWith(self.movable.dimen) then
			UIManager:close(self)
			return true
		end
		return false
	end

	function browser.book_info_dialog:onClose()
		UIManager:close(self)
		return true
	end

	function browser.book_info_dialog:onCloseWidget()
		-- Clean up custom filename and series when dialog closes
		browser._custom_filename = nil
		browser._download_series = nil
		-- Clean up our high-res dialog cover if we created one
		if dialog_cover_bb then
			dialog_cover_bb:free()
			dialog_cover_bb = nil
		end
		UIManager:setDirty(nil, "ui")
	end

	return browser.book_info_dialog
end

--- Show download options dialog (folder and filename)
-- @param browser table OPDSBrowser instance
-- @param item table Book item
function BookInfoDialog.showDownloadOptionsDialog(browser, item)
	local DownloadManager = require("core.download_manager")

	-- Generate original filename for reset
	local filename_orig = item.title
	if item.author then
		filename_orig = item.author .. " - " .. filename_orig
	end
	filename_orig = util.replaceAllInvalidChars(filename_orig)

	-- Current custom filename or default
	local current_filename = browser._custom_filename or filename_orig

	-- Capture auto-detected series now (before any dialog close clears it)
	local auto_series = browser._download_series

	-- Helper: build the full effective destination path for display
	local function effectivePath()
		local base = DownloadManager.getCurrentDownloadDir(browser)
		local sub  = browser._default_download_subfolder or auto_series
		return sub and (base .. "/" .. sub .. "/") or (base .. "/")
	end

	local buttons = {
		{
			{
				-- Sets session-level base folder (does not touch global KOReader setting)
				text = T_get("Base folder (session)"),
				callback = function()
					UIManager:close(browser.options_dialog)
					require("ui/downloadmgr"):new {
						onConfirm = function(path)
							logger.dbg("Session download dir set to", path)
							browser._session_download_dir = path
						end,
					}:chooseDir(DownloadManager.getCurrentDownloadDir(browser))
				end,
			},
		},
		{
			{
				text = T_get("Subfolder name"),
				callback = function()
					UIManager:close(browser.options_dialog)
					local current = browser._default_download_subfolder or auto_series or ""
					local subfolder_dialog
					subfolder_dialog = InputDialog:new {
						title = T_get("Subfolder name"),
						input = current,
						input_hint = auto_series or "",
						buttons = {
							{
								{
									text = T_get("Cancel"),
									id = "close",
									callback = function()
										UIManager:close(subfolder_dialog)
									end,
								},
								{
									text = T_get("Clear"),
									callback = function()
										browser._default_download_subfolder = nil
										UIManager:close(subfolder_dialog)
									end,
								},
								{
									text = T_get("Set"),
									is_enter_default = true,
									callback = function()
										local val = subfolder_dialog:getInputText()
										if val and val ~= "" then
											browser._default_download_subfolder = util.replaceAllInvalidChars(val)
										else
											browser._default_download_subfolder = nil
										end
										UIManager:close(subfolder_dialog)
									end,
								},
							}
						},
					}
					UIManager:show(subfolder_dialog)
					subfolder_dialog:onShowKeyboard()
				end,
			},
		},
		{
			{
				text = T_get("Change filename"),
				callback = function()
					UIManager:close(browser.options_dialog)
					local dialog
					dialog = InputDialog:new {
						title = T_get("Enter filename"),
						input = current_filename,
						input_hint = filename_orig,
						buttons = {
							{
								{
									text = T_get("Cancel"),
									id = "close",
									callback = function()
										UIManager:close(dialog)
									end,
								},
								{
									text = T_get("Reset"),
									callback = function()
										browser._custom_filename = filename_orig
										UIManager:close(dialog)
									end,
								},
								{
									text = T_get("Set"),
									is_enter_default = true,
									callback = function()
										local new_filename = dialog:getInputText()
										if new_filename and new_filename ~= "" then
											browser._custom_filename = util.replaceAllInvalidChars(new_filename)
										end
										UIManager:close(dialog)
									end,
								},
							}
						},
					}
					UIManager:show(dialog)
					dialog:onShowKeyboard()
				end,
			},
		},
		{}, -- separator
		{
			{
				text = T_get("Close"),
				callback = function()
					UIManager:close(browser.options_dialog)
				end,
			},
		},
	}

	browser.options_dialog = ButtonDialog:new {
		title = T(T_get("Download Options\n\nDestination:\n%1\nFilename: %2"),
			BD.dirpath(effectivePath()), current_filename),
		buttons = buttons,
	}
	UIManager:show(browser.options_dialog)
end

--- Show the book info dialog
-- Convenience function to build and display the dialog
-- @param browser table OPDSBrowser instance
-- @param item table Book item
function BookInfoDialog.show(browser, item)
	local dialog = BookInfoDialog.build(browser, item)
	UIManager:show(dialog)
end

return BookInfoDialog
