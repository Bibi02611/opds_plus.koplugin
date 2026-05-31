local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local _ = require("utils.locale")
local T = ffiUtil.template

-- Import the custom cover menu for displaying book covers
local OPDSCoverMenu = require("ui.menus.cover_menu")

-- Import constants and utilities
local Constants = require("models.constants")

-- Import the OPDS menu builder
local OPDSMenuBuilder = require("ui.dialogs.menu_builder")

-- Import the download manager
local DownloadManager = require("core.download_manager")
local DownloadDialogBuilder = require("ui.dialogs.download_builder")

-- Import the book info dialog
local BookInfoDialog = require("ui.dialogs.book_info_dialog")

-- Import the feed fetcher
local FeedFetcher = require("core.feed_fetcher")

-- Import the catalog manager
local CatalogManager = require("core.catalog_manager")

-- Import the navigation handler
local NavigationHandler = require("core.navigation_handler")

-- Import the browser context factory
local BrowserContext = require("core.browser_context")

-- Import the sync manager
local SyncManager = require("core.sync_manager")

-- Import the state manager
local StateManager = require("core.state_manager")

-- Import the debug utility
local Debug = require("utils.debug")
local UrlUtils = require("utils.url_utils")

-- Changed from Menu:extend to OPDSCoverMenu:extend to support cover images
local OPDSBrowser = OPDSCoverMenu:extend {
    catalog_type             = Constants.CATALOG_TYPE,
    search_type              = Constants.SEARCH_TYPE,
    search_template_type     = Constants.SEARCH_TEMPLATE_TYPE,
    acquisition_rel          = Constants.ACQUISITION_REL,
    borrow_rel               = Constants.BORROW_REL,
    stream_rel               = Constants.STREAM_REL,
    facet_rel                = Constants.FACET_REL,
    image_rel                = Constants.IMAGE_REL,
    thumbnail_rel            = Constants.THUMBNAIL_REL,

    root_catalog_title       = nil,
    root_catalog_username    = nil,
    root_catalog_password    = nil,
    facet_groups             = nil,

    title_shrink_font_to_fit = true,
}

function OPDSBrowser:init()
    self.item_table = self:genItemTableFromRoot()
    self.catalog_title = nil
    self.title_bar_left_icon = Constants.ICONS.MENU
    self.onLeftButtonTap = function()
        self:showOPDSMenu()
    end

    self.title_bar_right_icon = nil
    self.facet_groups = nil
    OPDSCoverMenu.init(self)
end

function OPDSBrowser:_debugLog(...)
    Debug.log("Browser:", ...)
end

function OPDSBrowser:toggleViewMode()
    -- Get current mode using StateManager
    local state = StateManager.getInstance()
    local current_mode = state:getDisplayMode()

    -- Toggle to opposite mode
    local new_mode = (current_mode == "list") and "grid" or "list"

    -- Save new mode via StateManager (handles persistence)
    state:setDisplayMode(new_mode)

    self:_debugLog("Toggling view mode from", current_mode, "to", new_mode)

    -- Show notification (2 s — e-ink refresh takes ~300 ms, 1 s is too brief to read)
    local mode_text = new_mode == "grid" and _("Grid View") or _("List View")
    UIManager:show(InfoMessage:new {
        text = T(_("Switched to %1"), mode_text),
        timeout = 2,
    })

    -- Remember the first visible item so we can land on the equivalent page after
    -- the mode switch (perpage differs between list and grid).
    -- Passing first_item_idx as select_number lets Menu.updateItems() compute the
    -- correct page in one shot — avoids a second updateItems() call and second e-ink flash.
    local first_item_idx = self.page and self.perpage
        and ((self.page - 1) * self.perpage + 1) or 1

    if #self.paths > 0 then
        local current_url = self.paths[#self.paths].url
        self:updateCatalog(current_url, true, first_item_idx)
    else
        self:switchItemTable(self.catalog_title, self.item_table, first_item_idx)
    end
end

function OPDSBrowser:showOPDSMenu()
    local dialog = OPDSMenuBuilder.buildOPDSMenu(self)
    UIManager:show(dialog)
end

-- Shows facet menu for OPDS catalogs with facets/search support
function OPDSBrowser:showFacetMenu()
    local catalog_url = self.paths[#self.paths].url
    local has_covers = OPDSMenuBuilder.hasCovers(self.item_table)

    local dialog = OPDSMenuBuilder.buildFacetMenu(self, catalog_url, has_covers)
    UIManager:show(dialog)
end

-- Shows menu for catalogs without facets but with covers (for view toggle)
function OPDSBrowser:showCatalogMenu()
    local catalog_url = self.paths[#self.paths].url
    local has_covers = OPDSMenuBuilder.hasCovers(self.item_table)

    local dialog = OPDSMenuBuilder.buildCatalogMenu(self, catalog_url, has_covers)
    UIManager:show(dialog)
end

-- Archive the full catalog tree for offline use.
-- BFS walk: follows both "next" pagination and sub-catalog navigation links
-- up to 2 levels deep, so it works from any catalog level (root, series list,
-- individual series).  Shows a progress dialog with a Cancel button.
function OPDSBrowser:archiveFullCatalog()
    local catalog_url = self.paths and self.paths[#self.paths] and self.paths[#self.paths].url
    if not catalog_url then return end

    local ButtonDialog = require("ui/widget/buttondialog")
    local ConfirmBox   = require("ui/widget/confirmbox")
    local OfflinePack  = require("services.offline_pack")

    local cancel_fn       = nil
    local progress_dialog = nil

    local function closeProgress()
        if progress_dialog then
            UIManager:close(progress_dialog)
            progress_dialog = nil
        end
    end

    local function showProgress(text)
        closeProgress()
        progress_dialog = ButtonDialog:new {
            title = text,
            buttons = { { {
                text = _("Annuler"),
                callback = function()
                    if cancel_fn then cancel_fn() end
                    closeProgress()
                end,
            } } },
        }
        UIManager:show(progress_dialog)
        UIManager:forceRePaint()
    end

    local function startArchive()
        NetworkMgr:runWhenConnected(function()
            UIManager:preventSuspend()
            showProgress(_("Analyse du catalogue…"))

            cancel_fn = OfflinePack.start {
                start_url = catalog_url,
                username  = self.root_catalog_username,
                password  = self.root_catalog_password,
                max_depth = 2,    -- root → sections → series → books with covers
                max_pages = 1000, -- hard cap to prevent runaway on huge libraries

                on_progress = function(phase, done, total)
                    if phase == "pages" then
                        showProgress(T(_("Pages : %1  ·  %2 couvertures trouvées…"), done, total))
                    else
                        showProgress(T(_("Couvertures : %1 / %2…"), done, total))
                    end
                end,

                on_done = function(pages, total_covers, new_covers)
                    UIManager:allowSuspend()
                    closeProgress()
                    UIManager:show(InfoMessage:new {
                        text = T(
                            _("Archivage terminé !\n%1 pages  ·  %2 couvertures  (%3 nouvelles)"),
                            pages, total_covers, new_covers),
                        timeout = 5,
                    })
                end,

                on_cancel = function()
                    UIManager:allowSuspend()
                    closeProgress()
                end,
            }
        end)
    end

    -- Warn before a potentially long operation
    UIManager:show(ConfirmBox:new {
        text = _("Archiver ce catalogue pour le mode avion ?\n\nToutes les pages et couvertures accessibles depuis ce niveau seront mises en cache (jusqu'à 1000 pages, 2 niveaux de profondeur).\n\nCela peut prendre plusieurs minutes pour une grande bibliothèque."),
        ok_text = _("Archiver"),
        ok_callback = startArchive,
    })
end

function OPDSBrowser:genItemTableFromRoot()
    return CatalogManager.genItemTableFromRoot(self.servers, self.downloads, _)
end

function OPDSBrowser:addEditCatalog(item)
    local dialog = OPDSMenuBuilder.buildCatalogEditDialog(self, item)
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function OPDSBrowser:addSubCatalog(item_url)
    local dialog = OPDSMenuBuilder.buildSubCatalogDialog(self, item_url)
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function OPDSBrowser:editCatalogFromInput(fields, item, no_refresh)
    -- luacheck: ignore new_idx
    local new_idx, itemnumber, should_refresh = CatalogManager.editCatalogFromInput(
        self.servers, self.item_table, fields, item, no_refresh)

    if should_refresh then
        self:switchItemTable(nil, self.item_table, itemnumber)
    end
    StateManager.getInstance():markDirty()
end

function OPDSBrowser:deleteCatalog(item)
    self.item_table = CatalogManager.deleteCatalog(self.servers, self.item_table, item)
    self:switchItemTable(nil, self.item_table, -1)
    StateManager.getInstance():markDirty()
end

function OPDSBrowser:fetchFeed(item_url, headers_only)
    return FeedFetcher.fetchFeed(item_url, headers_only,
        self.root_catalog_username, self.root_catalog_password)
end

function OPDSBrowser:parseFeed(item_url)
    return FeedFetcher.parseFeed(item_url,
        self.root_catalog_username, self.root_catalog_password,
        function(...) self:_debugLog(...) end)
end

function OPDSBrowser:getServerFileName(item_url, filetype)
    return FeedFetcher.getServerFileName(item_url, filetype,
        self.root_catalog_username, self.root_catalog_password)
end

function OPDSBrowser:getSearchTemplate(osd_url)
    return FeedFetcher.getSearchTemplate(osd_url, self.search_template_type,
        self.root_catalog_username, self.root_catalog_password,
        function(...) self:_debugLog(...) end)
end

function OPDSBrowser:genItemTableFromURL(item_url)
    return FeedFetcher.genItemTableFromURL(item_url,
        self.root_catalog_username, self.root_catalog_password,
        function(...) self:_debugLog(...) end,
        function(catalog, catalog_url)
            return self:genItemTableFromCatalog(catalog, catalog_url)
        end)
end

function OPDSBrowser:genItemTableFromCatalog(catalog, item_url)
    local context = BrowserContext.fromBrowser(self)

    local item_table, facet_groups, search_url = NavigationHandler.genItemTableFromCatalog(
        catalog, item_url, context,
        function(...) self:_debugLog(...) end)

    self.facet_groups = facet_groups
    self.search_url = search_url

    return item_table
end

function OPDSBrowser:updateCatalog(item_url, paths_updated, select_number)
    return NavigationHandler.updateCatalog(item_url, self, paths_updated, select_number)
end

function OPDSBrowser:appendCatalog(item_url)
    return NavigationHandler.appendCatalog(item_url, self)
end

function OPDSBrowser:searchCatalog(item_url)
    local dialog = OPDSMenuBuilder.buildSearchDialog(self, item_url)
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- Shows dialog to download / stream a book
function OPDSBrowser:showDownloads(item)
    -- luacheck: ignore filename_orig
    local filename, filename_orig = self:getFileName(item)

    local function createTitle(path, file)
        return T(_("Download folder:\n%1\n\nDownload filename:\n%2\n\nDownload file type:"),
            BD.dirpath(path), file or _(Constants.DEFAULT_FILENAME))
    end

    self.download_dialog = DownloadDialogBuilder.buildDownloadDialog(self, item, filename, createTitle)
    UIManager:show(self.download_dialog)
end

-- Returns user selected or last opened folder
function OPDSBrowser:getCurrentDownloadDir()
    return DownloadManager.getCurrentDownloadDir(self)
end

function OPDSBrowser:getLocalDownloadPath(filename, filetype, remote_url)
    return DownloadManager.getLocalDownloadPath(self, filename, filetype, remote_url)
end

-- Menu action on item tap (Download a book / Show subcatalog / Search in catalog)
function OPDSBrowser:onMenuSelect(item)
    if item.acquisitions then
        for i = #item.acquisitions, 1, -1 do
            if item.acquisitions[i].href and not item.acquisitions[i].type then
                table.remove(item.acquisitions, i)
            end
        end
    end
    if item.acquisitions and item.acquisitions[1] then -- book
        logger.dbg("Downloads available:", item)
        -- Show book info dialog first, allowing user to see details before downloading
        local book_info_dialog = BookInfoDialog.build(self, item)
        UIManager:show(book_info_dialog)
    else                         -- catalog or Search item
        if #self.paths == 0 then -- root list
            if item.idx == 1 then
                if #self.downloads > 0 then
                    self:showDownloadList()
                end
                return true
            end
            self.root_catalog_title     = item.text
            self.root_catalog_username  = item.username
            self.root_catalog_password  = item.password
            self.root_catalog_raw_names = item.raw_names
        end
        local connect_callback
        if item.searchable then
            connect_callback = function()
                self:searchCatalog(item.url)
            end
        else
            self.catalog_title = item.text or self.catalog_title or self.root_catalog_title
            connect_callback = function()
                -- Show a loading indicator for the duration of the network/parse call.
                local loading = InfoMessage:new { text = _("Chargement…") }
                UIManager:show(loading)
                UIManager:forceRePaint()
                self:updateCatalog(item.url)
                UIManager:close(loading)
            end
        end
        -- Bypass the "enable WiFi?" dialog when a disk-cached feed is available.
        -- parseFeed will detect the offline state and serve from cache directly.
        if not item.searchable and FeedFetcher.hasOfflineCache(item.url) then
            connect_callback()
        else
            NetworkMgr:runWhenConnected(connect_callback)
        end
    end
    return true
end

-- Menu action on item long-press (dialog Edit / Delete catalog)
function OPDSBrowser:onMenuHold(item)
    if #self.paths > 0 or item.idx == 1 then return true end -- not root list or Downloads item
    local dialog
    dialog = ButtonDialog:new {
        title = item.text,
        title_align = "center",
        buttons = {
            {
                {
                    text = _("Force sync"),
                    callback = function()
                        UIManager:close(dialog)
                        NetworkMgr:runWhenConnected(function()
                            self.sync_force = true
                            self:checkSyncDownload(item.idx)
                        end)
                    end,
                },
                {
                    text = _("Sync"),
                    callback = function()
                        UIManager:close(dialog)
                        NetworkMgr:runWhenConnected(function()
                            self.sync_force = false
                            self:checkSyncDownload(item.idx)
                        end)
                    end,
                },
            },
            {},
            {
                {
                    text = _("Delete"),
                    callback = function()
                        UIManager:show(ConfirmBox:new {
                            text = _("Delete OPDS catalog?"),
                            ok_text = _("Delete"),
                            ok_callback = function()
                                UIManager:close(dialog)
                                self:deleteCatalog(item)
                            end,
                        })
                    end,
                },
                {
                    text = _("Edit"),
                    callback = function()
                        UIManager:close(dialog)
                        self:addEditCatalog(item)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    return true
end

-- Menu action on return-arrow tap (go to one-level upper catalog)
function OPDSBrowser:onReturn()
    table.remove(self.paths)
    local path = self.paths[#self.paths]
    if path then
        -- return to last path
        self.catalog_title = path.title
        self:updateCatalog(path.url, true)
    else
        -- return to root path, we simply reinit opdsbrowser
        self:init()
    end
    return true
end

-- Menu action on return-arrow long-press (return to root path)
function OPDSBrowser:onHoldReturn()
    self:init()
    return true
end

-- Menu action on next-page chevron tap (request and show more catalog entries)
function OPDSBrowser:onNextPage(fill_only)
    -- self.page_num comes from menu.lua
    local page_num = self.page_num
    -- fetch more entries until we fill out one page or reach the end
    while page_num == self.page_num do
        local hrefs = self.item_table.hrefs
        if hrefs and hrefs.next then
            if not self:appendCatalog(hrefs.next) then
                break -- reach end of paging
            end
        else
            break
        end
    end
    if not fill_only then
        -- We also *do* want to paginate, so call the base class.
        OPDSCoverMenu.onNextPage(self)
    end
    return true
end

function OPDSBrowser:showDownloadList()
    self.download_list = Menu:new {
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        onMenuSelect = self.showDownloadListItemDialog,
        _manager = self,
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = self.showDownloadListMenu
    }
    self.download_list.close_callback = function()
        UIManager:close(self.download_list)
        self.download_list = nil
        if self.download_list_updated then
            self.download_list_updated = nil
            self.item_table[1].mandatory = #self.downloads
            self:updateItems(1, true)
        end
    end
    self:updateDownloadListItemTable()
    UIManager:show(self.download_list)
end

function OPDSBrowser:showDownloadListMenu()
    local dialog = DownloadDialogBuilder.buildDownloadListMenu(self)
    UIManager:show(dialog)
end

function OPDSBrowser:updateDownloadListItemTable(item_table)
    if item_table == nil then
        item_table = {}
        for i, item in ipairs(self.downloads) do
            item_table[i] = {
                text      = item.file:gsub(".*/", ""),
                mandatory = item.catalog,
            }
        end
    end
    local title = T(_("Downloads (%1)"), #item_table)
    self.download_list:switchItemTable(title, item_table)
end

function OPDSBrowser:confirmDownloadDownloadList()
    local dialog = DownloadDialogBuilder.buildDownloadAllConfirmation(self)
    UIManager:show(dialog)
end

function OPDSBrowser:confirmClearDownloadList()
    local dialog = DownloadDialogBuilder.buildClearQueueConfirmation(self)
    UIManager:show(dialog)
end

function OPDSBrowser:showDownloadListItemDialog(item)
    return DownloadDialogBuilder.buildDownloadListItemDialog(self, item)
end

-- Download whole download list
function OPDSBrowser:downloadDownloadList()
    return DownloadManager.downloadDownloadList(self)
end

function OPDSBrowser:setMaxSyncDownload()
    SyncManager.showMaxSyncDialog(self)
end

function OPDSBrowser:setSyncDir()
    SyncManager.showSyncDirChooser(self)
end

function OPDSBrowser:setSyncFiletypes()
    SyncManager.showFiletypesDialog(self)
end

-- Helper function to get filename and set nil if using raw names
function OPDSBrowser:getFileName(item)
    local filename = UrlUtils.decodeFilename(item.title or "")
    if item.author then
        filename = UrlUtils.decodeFilename(item.author) .. " - " .. filename
    end
    local filename_orig = filename
    if self.root_catalog_raw_names then
        filename = nil
    end
    logger.dbg("OPDS getFileName: title_raw=", item.title or "(nil)",
        "decoded=", filename_orig or "(nil)")
    return util.replaceAllInvalidChars(filename), util.replaceAllInvalidChars(filename_orig)
end

function OPDSBrowser:updateFieldInCatalog(item, name, value)
    CatalogManager.updateCatalogField(item, name, value)
    StateManager.getInstance():markDirty()
end

function OPDSBrowser:checkSyncDownload(idx)
    SyncManager.checkAndStartSync(self, idx)
end

-- Fetch all pages of the current catalog and add every downloadable book to the queue.
-- Shows format picker when multiple formats exist, then a confirmation before queuing.
function OPDSBrowser:queueAllInCatalog()
    local catalog_url = self.paths[#self.paths] and self.paths[#self.paths].url
    if not catalog_url then return end

    -- Proposed subfolder: session default if already set, otherwise current catalog title
    local proposed_subfolder = self._default_download_subfolder or self.catalog_title

    -- Scan currently loaded items to discover available formats
    local format_counts = {}
    for _, item in ipairs(self.item_table) do
        if item.acquisitions then
            for _, acq in ipairs(item.acquisitions) do
                if not acq.count and acq.type ~= "borrow" then
                    local ft = DownloadManager.getFiletype(acq)
                    if ft then
                        format_counts[ft] = (format_counts[ft] or 0) + 1
                    end
                end
            end
        end
    end

    if next(format_counts) == nil then
        UIManager:show(InfoMessage:new {
            text = _("No downloadable books found in current view."),
            timeout = 3,
        })
        return
    end

    -- Sort formats by frequency (most common first)
    local formats = {}
    for ft, count in pairs(format_counts) do
        table.insert(formats, { filetype = ft, count = count })
    end
    table.sort(formats, function(a, b) return a.count > b.count end)

    -- Fetch all pages then show confirmation and queue
    local function fetchAndQueue(chosen_filetype)
        local fetch_info = InfoMessage:new { text = _("Fetching series pages…") }
        UIManager:show(fetch_info)
        UIManager:forceRePaint()

        -- Collect items from every page of the catalog
        local all_items = {}
        local context = BrowserContext.fromBrowser(self)
        local debug_cb = function(...) self:_debugLog(...) end

        for _, item in ipairs(self.item_table) do   -- items already in memory
            table.insert(all_items, item)
        end

        local next_url = self.item_table.hrefs and self.item_table.hrefs.next
        local page_cap = 50  -- safety limit
        local pages_fetched = 0
        while next_url and pages_fetched < page_cap do
            pages_fetched = pages_fetched + 1
            local page_items = FeedFetcher.genItemTableFromURL(
                next_url,
                context.username,
                context.password,
                debug_cb,
                function(catalog, u)
                    -- Use genItemTableFromCatalog without touching browser state
                    local items = NavigationHandler.genItemTableFromCatalog(
                        catalog, u, context, debug_cb)
                    return items
                end
            )
            if not page_items or #page_items == 0 then break end
            for _, item in ipairs(page_items) do
                table.insert(all_items, item)
            end
            next_url = page_items.hrefs and page_items.hrefs.next
        end

        UIManager:close(fetch_info)

        -- Keep only items that have the chosen format
        local to_queue = {}
        for _, item in ipairs(all_items) do
            if item.acquisitions then
                for _, acq in ipairs(item.acquisitions) do
                    if not acq.count and acq.type ~= "borrow" then
                        if DownloadManager.getFiletype(acq) == chosen_filetype then
                            table.insert(to_queue, { item = item, acq = acq })
                            break
                        end
                    end
                end
            end
        end

        if #to_queue == 0 then
            UIManager:show(InfoMessage:new {
                text = T(_("No %1 books found."), string.upper(chosen_filetype)),
                timeout = 3,
            })
            return
        end

        local subfolder_line = proposed_subfolder
            and ("\n" .. _("Folder: ") .. proposed_subfolder)
            or ""
        UIManager:show(ConfirmBox:new {
            text = T(_("Queue %1 books (%2)?%3"),
                #to_queue, string.upper(chosen_filetype), subfolder_line),
            ok_text = _("Queue all"),
            ok_callback = function()
                -- Lock in the subfolder for the session if not already explicit
                if not self._default_download_subfolder
                        and proposed_subfolder and proposed_subfolder ~= "" then
                    self._default_download_subfolder =
                        util.replaceAllInvalidChars(proposed_subfolder)
                end

                for _, dl in ipairs(to_queue) do
                    local filename = dl.item.title
                    if dl.item.author then
                        filename = dl.item.author .. " - " .. filename
                    end
                    filename = filename and util.replaceAllInvalidChars(filename) or nil

                    local local_path = DownloadManager.getLocalDownloadPath(
                        self, filename, chosen_filetype, dl.acq.href)
                    DownloadManager.addToDownloadQueue(self, {
                        file     = local_path,
                        url      = dl.acq.href,
                        info     = type(dl.item.content) == "string"
                                    and util.htmlToPlainTextIfHtml(dl.item.content) or "",
                        catalog  = self.root_catalog_title,
                        username = self.root_catalog_username,
                        password = self.root_catalog_password,
                    })
                end

                UIManager:show(InfoMessage:new {
                    text = T(_("%1 books added to queue."), #to_queue),
                    timeout = 3,
                })
            end,
        })
    end

    -- Single format → straight to fetch; multiple formats → picker first
    if #formats == 1 then
        NetworkMgr:runWhenConnected(function()
            fetchAndQueue(formats[1].filetype)
        end)
    else
        local format_dialog
        local fmt_buttons = {}
        for _, fmt in ipairs(formats) do
            local ft = fmt.filetype
            table.insert(fmt_buttons, { {
                text = string.upper(ft),
                callback = function()
                    UIManager:close(format_dialog)
                    NetworkMgr:runWhenConnected(function()
                        fetchAndQueue(ft)
                    end)
                end,
                align = "left",
            } })
        end
        table.insert(fmt_buttons, {})
        table.insert(fmt_buttons, { {
            text = _("Cancel"),
            callback = function() UIManager:close(format_dialog) end,
            align = "left",
        } })
        format_dialog = ButtonDialog:new {
            title = _("Queue all — select format"),
            buttons = fmt_buttons,
        }
        UIManager:show(format_dialog)
    end
end

return OPDSBrowser
