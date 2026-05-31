local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local OPDSBrowser = require("ui.browser")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("utils.locale")
local T = require("ffi/util").template

-- Import constants
local Constants = require("models.constants")

-- Import settings manager
local Settings = require("config.settings")
local SettingsMenu = require("config.settings_menu")

-- Import settings dialogs
local SettingsDialogs = require("ui.dialogs.settings_dialogs")

-- Import state manager
local StateManager = require("core.state_manager")

local _cached_fonts = nil  -- populated lazily, survives the plugin session

local OPDS = WidgetContainer:extend {
    name = "opdsplus",
    opds_settings_file = DataStorage:getSettingsDir() .. "/opdsplus.lua",
    settings = nil,
    servers = nil,
    downloads = nil,
}

function OPDS:init()
    -- Initialize settings
    local settings_manager = Settings:new(self.opds_settings_file)
    self.opds_settings = settings_manager.storage
    self.settings = settings_manager.data

    -- Initialize defaults
    settings_manager:initializeDefaults()

    if settings_manager.is_first_run then
        self.updated = true -- first run, force flush
    end

    -- Initialize state manager singleton
    StateManager.getInstance(self)

    -- Load servers, downloads, pending syncs, and series continuation data
    self.servers = self.opds_settings:readSetting("servers", Constants.DEFAULT_SERVERS)
    self.downloads = self.opds_settings:readSetting("downloads", {})
    self.pending_syncs = self.opds_settings:readSetting("pending_syncs", {})
    self.pending_series = self.opds_settings:readSetting("pending_series", {})

    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function OPDS:getCoverHeightRatio()
    return self.settings.cover_height_ratio or Constants.DEFAULT_COVER_HEIGHT_RATIO
end

function OPDS:setCoverHeightRatio(ratio, preset_name)
    self.settings.cover_height_ratio = ratio
    self.settings.cover_size_preset = preset_name or "Custom"
    self.opds_settings:saveSetting("settings", self.settings)
    self.opds_settings:flush()
end

function OPDS:getCurrentPresetName()
    return self.settings.cover_size_preset or "Regular"
end

function OPDS:saveSetting(key, value)
    self.settings[key] = value
    self.opds_settings:saveSetting("settings", self.settings)
    self.opds_settings:flush()
end

function OPDS:getSetting(key)
    if self.settings[key] ~= nil then
        return self.settings[key]
    end
    return Constants.DEFAULT_FONT_SETTINGS[key]
end

function OPDS:getAvailableFonts()
    if _cached_fonts then return _cached_fonts end

    local fonts = {}
    table.insert(fonts, { name = "Default UI (Noto Sans)", value = "smallinfofont" })
    table.insert(fonts, { name = "Alternative UI", value = "infofont" })

    local font_dirs = { "./fonts" }
    local user_font_dir = DataStorage:getDataDir() .. "/fonts"
    if lfs.attributes(user_font_dir, "mode") == "directory" then
        table.insert(font_dirs, user_font_dir)
    end

    local font_extensions = { [".ttf"] = true, [".otf"] = true, [".ttc"] = true }
    local seen_fonts = {}

    local function add_font(name)
        if not seen_fonts[name] then
            seen_fonts[name] = true
            table.insert(fonts, {
                name  = name:gsub("%-", " "):gsub("_", " "),
                value = name,
            })
        end
    end

    for _, font_dir in ipairs(font_dirs) do
        if lfs.attributes(font_dir, "mode") == "directory" then
            local ok, iter, state = pcall(lfs.dir, font_dir)
            if ok and iter then
                for entry in iter, state do
                    if entry ~= "." and entry ~= ".." then
                        local path = font_dir .. "/" .. entry
                        local mode = lfs.attributes(path, "mode")
                        if mode == "file" then
                            local ext = entry:match("(%.%a+)$")
                            if ext and font_extensions[ext:lower()] then
                                local n = entry:match("^(.+)%.")
                                if n then add_font(n) end
                            end
                        elseif mode == "directory" then
                            local ok2, iter2, state2 = pcall(lfs.dir, path)
                            if ok2 and iter2 then
                                for sub in iter2, state2 do
                                    if sub ~= "." and sub ~= ".." then
                                        local ext2 = sub:match("(%.%a+)$")
                                        if ext2 and font_extensions[ext2:lower()] then
                                            local n = sub:match("^(.+)%.")
                                            if n then add_font(n) end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(fonts, function(a, b) return a.name < b.name end)
    _cached_fonts = fonts
    return fonts
end

function OPDS:onDispatcherRegisterActions()
    Dispatcher:registerAction("opdsplus_show_catalog",
        { category = "none", event = "ShowOPDSPlusCatalog", title = _("OPDS Plus Catalog"), filemanager = true, }
    )

    Dispatcher:registerAction("opdsplus_sync_all",
        { category = "none", event = "StartOPDSSyncAllCatalogs", title = _("OPDS Plus: Sync all catalogs"), filemanager = true, }
    )

    Dispatcher:registerAction("opdsplus_force_sync_all",
        { category = "none", event = "StartOPDSForceSyncAllCatalogs", title = _("OPDS Plus: Force sync all catalogs"), filemanager = true, }
    )
end

function OPDS:_createBrowserInstance()
    return OPDSBrowser:new {
        servers = self.servers,
        downloads = self.downloads,
        settings = self.settings,
        pending_syncs = self.pending_syncs,
        pending_series = self.pending_series,
        title = _("OPDS Plus Catalog"),
        is_popout = false,
        is_borderless = true,
        title_bar_fm_style = true,
        show_covers = true,
        _manager = self,
        file_downloaded_callback = function(file)
            self:showFileDownloadedDialog(file)
        end,
        close_callback = function()
            if self.opds_browser.download_list then
                self.opds_browser.download_list.close_callback()
            end
            UIManager:close(self.opds_browser)
            self.opds_browser = nil
            if self.last_downloaded_file then
                if self.ui.file_chooser then
                    local pathname = util.splitFilePathName(self.last_downloaded_file)
                    self.ui.file_chooser:changeToPath(pathname, self.last_downloaded_file)
                end
                self.last_downloaded_file = nil
            end
        end,
    }
end

function OPDS:_startSyncFromDispatcher(force_sync)
    -- For gesture-triggered actions, create an off-screen browser context if needed.
    if not self.opds_browser then
        self.opds_browser = self:_createBrowserInstance()
    end

    self.opds_browser.sync_force = force_sync
    self.opds_browser:checkSyncDownload()
end

function OPDS:onStartOPDSSyncAllCatalogs()
    self:_startSyncFromDispatcher(false)
end

function OPDS:onStartOPDSForceSyncAllCatalogs()
    self:_startSyncFromDispatcher(true)
end

function OPDS:addToMainMenu(menu_items)
    if not self.ui.document then -- FileManager menu only
        menu_items.opdsplus = {
            text = _("OPDS Plus Catalog"),
            sub_item_table = SettingsMenu.create(self)
        }
    end
end

function OPDS:showCoverSizeMenu()
    SettingsDialogs.showCoverSizeMenu(self)
end

function OPDS:showCustomSizeDialog()
    SettingsDialogs.showCustomSizeDialog(self)
end

function OPDS:showFontSelectionMenu(setting_key, title)
    SettingsDialogs.showFontSelectionMenu(self, setting_key, title)
end

function OPDS:showSizeSelectionMenu(setting_key, title, min_size, max_size, default_size)
    SettingsDialogs.showSizeSelectionMenu(self, setting_key, title, min_size, max_size, default_size)
end

function OPDS:showGridLayoutMenu()
    SettingsDialogs.showGridLayoutMenu(self)
end

function OPDS:showGridColumnsMenu()
    SettingsDialogs.showGridColumnsMenu(self)
end

function OPDS:showGridBorderMenu()
    SettingsDialogs.showGridBorderMenu(self)
end

function OPDS:showGridBorderSizeMenu()
    SettingsDialogs.showGridBorderSizeMenu(self)
end

function OPDS:showGridBorderColorMenu()
    SettingsDialogs.showGridBorderColorMenu(self)
end

function OPDS:showCoverCacheSizeDialog()
    SettingsDialogs.showCoverCacheSizeDialog(self)
end

function OPDS:showCoverCacheTTLDialog()
    SettingsDialogs.showCoverCacheTTLDialog(self)
end

function OPDS:clearCoverCache()
    SettingsDialogs.clearCoverCache()
end

function OPDS:onShowOPDSPlusCatalog()
    self.opds_browser = self:_createBrowserInstance()
    UIManager:show(self.opds_browser)
end

function OPDS:showFileDownloadedDialog(file)
    self.last_downloaded_file = file
    UIManager:show(ConfirmBox:new {
        text = T(_("File saved to:\n%1\nWould you like to read the downloaded book now?"), BD.filepath(file)),
        ok_text = _("Read now"),
        ok_callback = function()
            self.last_downloaded_file = nil
            self.opds_browser.close_callback()
            if self.ui.document then
                self.ui:switchDocument(file)
            else
                self.ui:openFile(file)
            end
        end,
    })
end

function OPDS:onFlushSettings()
    if self.updated then
        self.opds_settings:flush()
        self.updated = nil
    end
end

function OPDS:onDocumentClose()
    local doc_path = self.ui and self.ui.document and self.ui.document.file
    if not doc_path then return end

    local sync_info   = self.pending_syncs  and self.pending_syncs[doc_path]
    local series_info = self.pending_series and self.pending_series[doc_path]
    if not sync_info and not series_info then return end

    -- Determine current page and completion state (shared by both branches)
    local current_page, completed = nil, false
    local ok_page, page_val = pcall(function()
        return self.ui.document:getCurrentPage()
    end)
    if ok_page and page_val then
        current_page = page_val
        local ok_total, total = pcall(function()
            return self.ui.document:getPageCount()
        end)
        if ok_total and total and total > 0 then
            completed = (page_val >= total)
        end
    end

    -- Komga sync: push reading progress
    if sync_info then
        self.pending_syncs[doc_path] = nil
        self.opds_settings:saveSetting("pending_syncs", self.pending_syncs)
        self.opds_settings:flush()
        local KomgaSync = require("services.komga_sync")
        local ok, err = pcall(KomgaSync.updateReadProgress,
            sync_info.base_url, sync_info.book_id,
            current_page, completed,
            sync_info.username, sync_info.password)
        if not ok then
            require("logger").dbg("OPDS+: Komga sync push failed:", err)
        end
    end

    -- Series continuation: notify when the book is fully read
    if series_info then
        self.pending_series[doc_path] = nil
        self.opds_settings:saveSetting("pending_series", self.pending_series)
        self.opds_settings:flush()
        if completed then
            local T_fn = require("ffi/util").template
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new {
                text = T_fn(_("Série : %1\nSuivant : %2"), series_info.series, series_info.next_title),
                timeout = 5,
            })
        end
    end
end

return OPDS
