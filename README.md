![OPDS Plus Banner](.github/assets/hero_banner.png)

<div align="center">

![GitHub release (latest by date)](https://img.shields.io/github/v/release/Bibi02611/opds_plus.koplugin?style=for-the-badge&color=orange)
![GitHub all releases](https://img.shields.io/github/downloads/Bibi02611/opds_plus.koplugin/total?style=for-the-badge&color=yellow)
![GitHub](https://img.shields.io/github/license/Bibi02611/opds_plus.koplugin?style=for-the-badge&color=blue)
![Platform](https://img.shields.io/badge/Platform-KOReader-success?style=for-the-badge&logo=koreader)

</div>

# OPDS Plus - Enhanced OPDS Browser for KOReader

**Version:** 1.3.1

**OPDS Plus** is a feature-rich enhancement of KOReader's built-in OPDS catalog browser, providing visual book cover displays, multiple viewing modes, and extensive customization options for browsing online book catalogs.

## ✨ Features

### 🌍 French Translation *(New in 1.3.1)*

- All plugin-specific UI strings are now fully translated into French when KOReader's language is set to French
- Covers every label, dialog, menu, button, and status message added by OPDS Plus — queue management, folder controls, series detection, grid/cover/font settings, error messages, and more
- Standard KOReader strings (already translated by the core app) are handled by KOReader's own translation layer; OPDS Plus strings fall back gracefully if French translation is missing

### 🛡️ Robustness Improvements *(New in 1.3.1)*

- **No more crash on network drop**: all `http.request` calls (feed fetcher, cover loader, download manager, Kavita streaming) are now wrapped in `pcall` — a socket error no longer leaves the timeout active or crashes the plugin
- **XML parser depth guard**: recursion capped at 100 levels to prevent stack overflow on malformed OPDS feeds
- **Kavita integration hardened**: nil guards on URL regex extractions and bearer token parsing; invalid/missing values return `0` instead of raising an error
- **Blitbuffer leak fixed**: old cover image buffer is freed before replacement in the cover loader
- **Series metadata extraction**: `dc:series` / `dc:seriesIndex` fields are now properly parsed from OPDS entries and populated on list/grid items
- **Debug log hygiene**: 11 diagnostic traces demoted from `logger.warn` to `logger.dbg` (only visible in debug mode)
- **Bug fix**: `auto_series` / `series_snapshot` confusion in the book info dialog — download callbacks now always use the correct pre-captured series name
- **Bug fix**: removed a stray debug "ITEM DUMP" block that logged all item fields with `logger.warn` on every book tap

---

### 📥 Series Download Management *(New in 1.3.0)*

#### Queue All in Series
- **One-tap bulk download**: tap ≡ in any book-list view → **Queue all in series**
- Fetches all pages of the current OPDS catalog automatically (pagination followed transparently)
- **Format picker** when multiple formats are available (CBZ, PDF…); auto-selects if only one
- Confirmation dialog shows exact book count and destination folder before queuing
- Path is locked **at queue time** — changing the folder later only affects new additions

#### Smart Folder Organisation
- **Session base folder** (`Base folder`): choose where downloads go for this session (e.g. `/BD/` vs `/livres/`) without touching KOReader's global download directory
- **Session subfolder**: a subfolder name applied to every book queued until changed (e.g. `Blacksad`)
- **Auto-detection** from OPDS metadata in priority order: parent navigation link → `dc:series` field → title prefix → current catalog name
- Full effective destination displayed in real time: `Base/Subfolder/filename.cbz`
- **Visible directly** in the book info dialog as a two-button row — no sub-menu needed:
  - Left button → folder picker for the base directory
  - Right button → keyboard input for the subfolder name
- Also accessible from the download queue's ≡ menu

#### Bug Fixes in Download Pipeline
- **File extension always preserved** from the server: titles containing dots (`Vol.1`, `T.3`, `Tome 1.5`) no longer block the correct extension from being appended — KOReader can now open every downloaded file
- **Empty folder fixed**: `makeDirectory` is now recursive (creates missing parent directories); the download subprocess recreates the target folder if needed and explicitly validates `io.open` before issuing the HTTP request — no more false-positive "X books downloaded" with an empty folder

---

### 📚 Enhanced Catalog Browsing
- **Visual Book Covers**: Browse catalogs with book cover images displayed alongside titles
- **Dual View Modes**: Switch between List View and Grid View layouts
- **Multiple Display Options**: Customize how books are presented
- **Book Info Dialog**: Open an at-a-glance details dialog with improved cover handling
- **Sync Gesture Actions**: Trigger sync-related actions directly from configured gestures
- **Cover Quality + Cache**: Improved cover rendering pipeline with disk-backed caching

### 🖼️ List View
- Book covers displayed alongside title and author information
- Adjustable cover sizes with presets (Compact, Regular, Large, Extra Large)
- Custom size option (5-25% of screen height)
- Clean, readable layout optimized for e-readers

### 📊 Grid View
- Display books in a grid layout for visual browsing
- Flexible column options (2-4 columns)
- Layout presets: Compact (4 cols), Balanced (3 cols), Spacious (2 cols)
- Customizable grid borders:
  - No Borders: Clean, borderless grid
  - Hash Grid: Shared borders in a # pattern
  - Individual Tiles: Each book has its own border
- Adjustable border thickness (1-5px) and color (Light Gray, Dark Gray, Black)

### 🎨 Customization Options
- **Font Selection**: Choose from KOReader's built-in fonts or your custom fonts
- **Independent Font Settings**: Separate customization for titles and details
  - Font family selection
  - Font size adjustment
  - Bold/regular weight toggle
  - Color options (Dark Gray, Black)
- **Same Font Mode**: Option to use matching fonts for consistent appearance
- **Persistent Settings**: All preferences are saved between sessions

### 📖 Default Catalogs Included
- Project Gutenberg
- Standard Ebooks
- ManyBooks
- Internet Archive
- textos.info (Spanish)
- Gallica (French)

## 📸 Screenshots

|                        **List View**                        |                        **Grid View**                        |
| :---------------------------------------------------------: | :---------------------------------------------------------: |
| ![List View with Covers](.github/screenshots/list_view.png) | ![Grid View with Covers](.github/screenshots/grid_view.png) |
|          *Classic list view with cover thumbnails*          |            *Immersive grid layout for browsing*             |

|                       **View Options**                        |                    **Customization**                    |
| :-----------------------------------------------------------: | :-----------------------------------------------------: |
| ![View Toggle Menu](.github/screenshots/view_toggle_menu.png) | ![Settings Menu](.github/screenshots/settings_menu.png) |
|             *Switch views instantly via the menu*             |            *Extensive customization options*            |

## 📥 Installation

### Method 1: Manual Installation (Recommended)

1. **Download the latest release**:
   - Go to the [Releases](https://github.com/Bibi02611/opds_plus.koplugin/releases) page
   - Download the `opds_plus.koplugin.zip` file from the latest release

2. **Extract to KOReader plugins directory**:

   The location depends on your device:

   - **Kindle/Kobo/Android**: Extract to `/koreader/plugins/`
   - **Linux**: Extract to `~/.config/koreader/plugins/`
   - **Windows**: Extract to `%APPDATA%/koreader/plugins/`
   - **macOS**: Extract to `~/Library/Application Support/koreader/plugins/`

  For complete platform-specific install/upgrade paths, see the KOReader wiki:
  [KOReader Installation/Upgrading](https://github.com/koreader/koreader/wiki#installationupgrading)

   The archive should extract to create an `opds_plus.koplugin` directory containing all plugin files.

3. **Restart KOReader**: Close and reopen KOReader to load the plugin

4. **Verify installation**:
   - Open KOReader's File Browser
   - Tap the menu icon (⋮ or ≡)
   - You should see "OPDS Plus Catalog" in the menu

### Method 2: Git Clone (For Developers)

```bash
# Navigate to KOReader plugins directory
cd ~/.config/koreader/plugins/  # Adjust path for your system

# Clone the repository
git clone https://github.com/Bibi02611/opds_plus.koplugin.git

# Restart KOReader
```

### Troubleshooting Installation
- Ensure the directory is named exactly `opds_plus.koplugin`
- Verify all `.lua` files are present in the plugin directory
- Check that you have write permissions to the plugins directory
- If the plugin doesn't appear, check KOReader's crash.log for errors

## 🚀 Usage

### Accessing OPDS Plus

1. Open KOReader's **File Browser**
2. Tap the **menu icon** (⋮ or ≡)
3. Select **OPDS Plus Catalog**

### Browsing Catalogs

#### First Time Setup
- The plugin comes with several default catalogs pre-configured
- Simply select a catalog to start browsing

#### Browsing Books
1. Select a catalog from the list
2. Navigate through categories and books
3. Tap a book to view details and download options
4. Downloaded books are saved to your configured download directory

### Customizing Settings

Access settings from: **OPDS Plus Catalog → Settings**

#### Display Mode
- **List View**: Traditional list with covers on the left
- **Grid View**: Visual grid layout with larger covers

#### List View Settings
- **Cover Size**: Choose from presets or set custom size
  - Compact (8%): More books per page
  - Regular (10%): Default balanced view
  - Large (15%): Easier to see cover details
  - Extra Large (20%): Maximum cover visibility
  - Custom: Fine-tune between 5-25%

#### Cover Settings
- **Prefer Large Covers**:
  - Enabled: prioritizes higher-quality cover sources when available.
  - Disabled: prefers faster thumbnail sources.
- **Enable Cover Cache**:
  - Enabled: reuses previously downloaded covers.
  - Disabled: fetches covers from the server each time.
- **Advanced Cache Controls**:
  - Cache Size (MB)
  - Cache TTL (minutes)
  - Clear Cover Cache

#### Grid View Settings
- **Grid Layout**:
  - Compact: 4 columns, more books visible
  - Balanced: 3 columns, good middle ground (default)
  - Spacious: 2 columns, larger covers
  - Custom: Manual column selection (2-4)

- **Grid Borders**:
  - Style: None, Hash Grid, or Individual Tiles
  - Thickness: 1-5 pixels
  - Color: Light Gray, Dark Gray, or Black

#### Font & Text Settings
- **Use Same Font for All**: Match title and detail fonts
- **Title Settings**:
  - Font family
  - Font size (12-24pt)
  - Bold/regular weight
- **Information Settings**:
  - Font family (independent if same font disabled)
  - Font size (10-20pt)
  - Bold/regular weight
  - Color: Dark Gray or Black

### Sync Actions & Settings

- **Direct Sync Actions**:
  - Sync all catalogs
  - Force sync all catalogs
- **Gesture Integration**:
  - Actions are registered in KOReader's dispatcher as:
    - `OPDS Plus: Sync all catalogs`
    - `OPDS Plus: Force sync all catalogs`
  - These can be assigned in KOReader's gesture/action configuration.
- **Catalog Sync Controls**:
  - Per-catalog sync and force-sync via catalog long-press actions.
  - Sync folder selection.
  - Maximum sync download count.
  - Filetype filtering for sync downloads.

### Book Info Dialog

- Tapping a book opens a book info dialog before download.
- Dialog includes cover preview and at-a-glance metadata for faster decisions.
- Download actions are available directly from the dialog flow.

### Adding Your Own Catalogs

1. Go to **OPDS Plus Catalog → Settings → Manage Catalogs**
2. Select **Add Catalog**
3. Enter:
   - Catalog name
   - OPDS feed URL
4. The new catalog will appear in your catalog list

## 🔧 Technical Details

### Requirements
- KOReader v2025.10, minimum
- Network connectivity for browsing online catalogs

### File Structure
```
opds_plus.koplugin/
├── _meta.lua
├── main.lua
├── opds_plus_version.lua
├── config/
│   ├── settings.lua
│   └── settings_menu.lua
├── core/
│   ├── browser_context.lua
│   ├── catalog_manager.lua
│   ├── download_manager.lua
│   ├── feed_fetcher.lua
│   ├── navigation_handler.lua
│   ├── parser.lua
│   ├── state_manager.lua
│   └── sync_manager.lua
├── models/
│   └── constants.lua
├── services/
│   ├── cover_cache.lua
│   ├── cover_loader.lua
│   ├── http_client.lua
│   ├── image_loader.lua
│   └── kavita.lua
├── ui/
│   ├── browser.lua
│   ├── utils.lua
│   ├── dialogs/
│   │   ├── book_info_dialog.lua
│   │   ├── download_builder.lua
│   │   ├── menu_builder.lua
│   │   └── settings_dialogs.lua
│   └── menus/
│       ├── cover_menu.lua
│       ├── grid_menu.lua
│       └── list_menu.lua
└── utils/
    ├── button_dialog_builder.lua
    ├── catalog_utils.lua
    ├── debug.lua
    ├── file_utils.lua
    ├── locale.lua
    ├── result.lua
    └── url_utils.lua
```

### Settings Storage
Settings are stored in: `<KOReader data dir>/settings/opdsplus.lua`

This file contains:
- Catalog list
- Download history
- Display preferences
- Font settings
- Grid layout configuration

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

1. **Report Bugs**: Open an issue describing the problem
2. **Suggest Features**: Share your ideas via GitHub issues
3. **Submit Pull Requests**:
   - Fork the repository
   - Create a feature branch
   - Make your changes
   - Submit a PR with a clear description

### Development Guidelines
- Follow KOReader's Lua coding conventions
- Test on multiple screen sizes if possible
- Ensure compatibility with existing OPDS catalogs
- Document new features in the README

## 📝 Known Issues & Limitations

- Cover loading depends on catalog providing image URLs
- Some OPDS feeds may not include cover images
- Large catalogs may take time to load initially
- Grid view performance varies with device capabilities

## 🙏 Credits

- **Original OPDS Plugin**: KOReader development team
- **Enhancement Development**: greywolf1499
- **v1.3.x improvements**: Bibi02611
- Built upon the excellent [KOReader](https://github.com/koreader/koreader) e-reader software

## 📜 License

This plugin is released under the same license as KOReader: **GNU Affero General Public License v3.0 (AGPL-3.0)**

See the [LICENSE](LICENSE) file for details.

## 📞 Support

- **Issues & Bug Reports**: [GitHub Issues](https://github.com/Bibi02611/opds_plus.koplugin/issues)
- **KOReader Documentation**: [KOReader Wiki](https://github.com/koreader/koreader/wiki)
- **OPDS Specification**: [OPDS Spec](https://specs.opds.io/)

## 🔄 Version History

### v1.3.1
- **French translation**: all plugin-specific UI strings translated — queue, folder controls, series detection, grid/cover/font settings, error messages and more (`utils/locale.lua`, callable table with ~200 strings, graceful fallback to KOReader gettext)
- **Robustness**: `pcall` wrapper around every `http.request` — socket timeout can no longer leak on network error; applies to feed fetcher, download manager, cover loader, and Kavita streaming
- **XML parser**: recursion depth capped at 100 levels to prevent stack overflow on malformed feeds
- **Kavita hardening**: nil guards on URL regex and bearer token extraction; errors return `0` instead of crashing
- **Blitbuffer leak**: old cover `blitbuffer` is now freed before replacement in the cover loader
- **Series metadata**: `dc:series` / `dc:seriesIndex` OPDS fields now properly extracted and available on items
- **Fix**: `series_snapshot` correctly captured before any `UIManager:close()` in the book info dialog — download callbacks no longer use a stale/nil series name
- **Fix**: removed debug "ITEM DUMP" block that polluted logs on every book tap
- **Log hygiene**: 11 diagnostic traces demoted from `logger.warn` to `logger.dbg`

### v1.3.0
- **Queue all in series**: one-tap bulk download of an entire OPDS catalog (all pages, format picker, confirmation)
- **Session folder management**: separate base folder and subfolder controls, visible directly in the book info dialog
- **Auto-detection of series name** from OPDS metadata for automatic subfolder naming
- **Fix**: file extension now always preserved from the server declaration (titles with dots like `Vol.1` no longer lose their `.cbz`)
- **Fix**: download to subfolder now reliable — `makeDirectory` is recursive, download subprocess validates file creation before HTTP request

### v1.2.0 and earlier
See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

---

**Enjoy enhanced OPDS browsing with OPDS Plus! 📚✨**
