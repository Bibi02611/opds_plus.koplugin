-- Plugin-specific French translations for OPDS Plus
-- Wraps KOReader's gettext() with a plugin-level table so that strings
-- not yet in KOReader's standard .po files are displayed in French.
--
-- Usage (replaces `local _ = require("gettext")`):
--   local _ = require("utils.locale")
--   local N_ = _.ngettext   -- for plural forms

local gettext = require("gettext")

local FR = {
	-- ── App identity ──────────────────────────────────────────────────────────
	["OPDS Plus"]                          = "OPDS Plus",
	["OPDS Plus Catalog"]                  = "Catalogue OPDS Plus",
	["About OPDS Plus v%1"]               = "À propos d'OPDS Plus v%1",
	["OPDS Plus: Sync all catalogs"]      = "OPDS Plus : Synchroniser tous les catalogues",
	["OPDS Plus: Force sync all catalogs"] = "OPDS Plus : Forcer la synchronisation de tous les catalogues",
	["OPDS Plus Plugin\nVersion: %1\n\nAn enhanced OPDS catalog browser with cover display support.\n\nFeatures:\n• List and Grid view modes\n• Customizable covers and fonts\n• Grid border options\n\nBased on KOReader's OPDS plugin"]
		= "Plugin OPDS Plus\nVersion : %1\n\nNavigateur de catalogues OPDS amélioré avec affichage des couvertures.\n\nFonctionnalités :\n• Modes vue liste et grille\n• Couvertures et polices personnalisables\n• Options de bordure de grille\n\nBasé sur le plugin OPDS de KOReader",

	-- ── Catalog management ────────────────────────────────────────────────────
	["Browse Catalogs"]                    = "Parcourir les catalogues",
	["Add catalog"]                        = "Ajouter un catalogue",
	["Add OPDS catalog"]                   = "Ajouter un catalogue OPDS",
	["Edit OPDS catalog"]                  = "Modifier le catalogue OPDS",
	["Delete OPDS catalog?"]              = "Supprimer le catalogue OPDS ?",
	["Catalog name"]                       = "Nom du catalogue",
	["Catalog name cannot be empty"]       = "Le nom du catalogue ne peut pas être vide",
	["Catalog URL"]                        = "URL du catalogue",
	["Invalid URL: "]                      = "URL invalide : ",
	["Sync catalog"]                       = "Synchroniser le catalogue",
	["Use server filenames"]               = "Utiliser les noms de fichiers du serveur",
	["Copy of "]                           = "Copie de ",
	["Search OPDS catalog"]               = "Rechercher dans le catalogue OPDS",
	["Search results"]                     = "Résultats de recherche",
	["Alexandre Dumas"]                    = "Alexandre Dumas",
	["%s in url will be replaced by your input"] = "%s dans l'URL sera remplacé par votre saisie",
	["%1 (%2)"]                           = "%1 (%2)",

	-- ── View / display modes ──────────────────────────────────────────────────
	["Display Mode"]                       = "Mode d'affichage",
	["List View"]                          = "Vue liste",
	["Grid View"]                          = "Vue grille",
	["Switch to Grid View"]               = "Passer en vue grille",
	["Switch to List View"]               = "Passer en vue liste",
	["Switched to %1"]                    = "Basculé vers %1",
	["List View Settings"]                = "Paramètres de la vue liste",
	["Grid View Settings"]                = "Paramètres de la vue grille",
	["Display mode set to List View.\n\nChanges will apply when you next browse a catalog."]
		= "Mode d'affichage : Vue liste.\n\nLes modifications s'appliqueront lors de la prochaine navigation.",
	["Display mode set to Grid View.\n\nChanges will apply when you next browse a catalog."]
		= "Mode d'affichage : Vue grille.\n\nLes modifications s'appliqueront lors de la prochaine navigation.",

	-- ── Cover settings ────────────────────────────────────────────────────────
	["Cover Settings"]                     = "Paramètres des couvertures",
	["Cover Size"]                         = "Taille des couvertures",
	["Cover Size Settings\n\nSelect a preset or choose custom size"]
		= "Taille des couvertures\n\nSélectionnez un préréglage ou une taille personnalisée",
	["Cover size set to %1 (%2%).\n\n%3\n\nChanges will apply when you next browse a catalog."]
		= "Taille des couvertures : %1 (%2%).\n\n%3\n\nLes modifications s'appliqueront lors de la prochaine navigation.",
	["Cover size set to Custom (%1%).\n\nChanges will apply when you next browse a catalog."]
		= "Taille des couvertures : Personnalisé (%1%).\n\nLes modifications s'appliqueront lors de la prochaine navigation.",
	["Custom Cover Size"]                  = "Taille de couverture personnalisée",
	["Adjust the size of book covers as a percentage of screen height.\n\n• Smaller values = more books per page\n• Larger values = bigger covers, fewer books per page\n\nRecommended: 8-12% for compact, 15-20% for large"]
		= "Taille des couvertures en pourcentage de la hauteur d'écran.\n\n• Valeurs faibles = plus de livres par page\n• Valeurs élevées = couvertures plus grandes, moins de livres\n\nRecommandé : 8-12 % compact, 15-20 % grand",
	["Prefer Large Covers"]               = "Préférer les grandes couvertures",
	["High-quality cover source enabled.\n\nChanges apply on next catalog browse."]
		= "Source haute qualité activée.\n\nLes modifications s'appliqueront lors de la prochaine navigation.",
	["Fast thumbnail cover source enabled.\n\nChanges apply on next catalog browse."]
		= "Source miniatures rapides activée.\n\nLes modifications s'appliqueront lors de la prochaine navigation.",
	["More books per page, smaller covers"] = "Plus de livres par page, couvertures réduites",
	["Good balance of size and quantity"]  = "Bon équilibre taille / quantité",
	["Fewer books, larger covers"]         = "Moins de livres, couvertures agrandies",
	["Book cover"]                         = "Couverture",
	["Full Cover"]                         = "Couverture pleine page",
	["No Cover"]                           = "Pas de couverture",
	["Loading..."]                         = "Chargement...",
	["Failed"]                             = "Échec",

	-- ── Cover cache ───────────────────────────────────────────────────────────
	["Enable Cover Cache"]                 = "Activer le cache des couvertures",
	["Cover Cache Size"]                   = "Taille du cache des couvertures",
	["Cover Cache TTL"]                    = "Durée du cache des couvertures",
	["Cover cache size set to %1 MB."]    = "Cache des couvertures : %1 Mo.",
	["Cover cache TTL set to %1 minutes."] = "Durée du cache des couvertures : %1 minute(s).",
	["Cover cache cleared."]              = "Cache des couvertures vidé.",
	["Cover cache enabled.\n\nPreviously downloaded covers can be reused."]
		= "Cache des couvertures activé.\n\nLes couvertures déjà téléchargées peuvent être réutilisées.",
	["Cover cache disabled.\n\nCovers will be fetched from the server each time."]
		= "Cache des couvertures désactivé.\n\nLes couvertures seront récupérées du serveur à chaque fois.",
	["Clear Cover Cache"]                  = "Vider le cache des couvertures",
	["Cache Size (MB)"]                    = "Taille du cache (Mo)",
	["Cache TTL (minutes)"]               = "Durée du cache (minutes)",
	["Set the maximum disk space used for cached cover images.\n\nLarger values improve offline reuse and reduce refetching after browsing."]
		= "Espace disque maximum pour les couvertures en cache.\n\nDes valeurs plus élevées améliorent la réutilisation hors ligne.",
	["Set how long cached covers remain fresh before revalidation by refetching.\n\nShorter TTL picks up changed covers sooner. Longer TTL reduces network requests."]
		= "Durée de validité des couvertures en cache avant revalidation.\n\nUn TTL court détecte les changements plus vite ; un TTL long réduit les requêtes réseau.",
	["min"]                                = "min",

	-- ── Grid layout ───────────────────────────────────────────────────────────
	["Grid Layout"]                        = "Disposition en grille",
	["Grid Layout Presets\n\nChoose how books are displayed in grid view"]
		= "Préréglages de grille\n\nChoisissez comment les livres sont affichés",
	["Grid layout set to %1\n\n%2\n\nChanges will apply when you next browse a catalog in grid view."]
		= "Disposition en grille : %1\n\n%2\n\nLes modifications s'appliqueront lors de la prochaine navigation.",
	["Custom Grid Columns\n\nManually choose column count"]
		= "Colonnes personnalisées\n\nChoisissez manuellement le nombre de colonnes",
	["Grid columns set to %1 (Custom).\n\nChanges will apply when you next browse a catalog in grid mode."]
		= "Nombre de colonnes : %1 (personnalisé).\n\nLes modifications s'appliqueront lors de la prochaine navigation.",
	["cols"]                               = "col.",
	["columns (wider)"]                    = "colonnes (larges)",
	["columns (balanced)"]                 = "colonnes (équilibrées)",
	["columns (compact)"]                  = "colonnes (compact)",
	["Custom"]                             = "Personnalisé",
	["Back to Presets"]                    = "Retour aux préréglages",

	-- ── Grid borders ──────────────────────────────────────────────────────────
	["Grid Borders"]                       = "Bordures de grille",
	["Grid Border Settings\n\nCustomize the appearance of grid borders"]
		= "Bordures de grille\n\nPersonnalisez l'apparence des bordures",
	["Border Style"]                       = "Style de bordure",
	["Customize Borders"]                  = "Personnaliser les bordures",
	["Border Thickness"]                   = "Épaisseur de bordure",
	["Border Thickness: %1px"]            = "Épaisseur : %1 px",
	["Border Color: %1"]                  = "Couleur : %1",
	["Border Color\n\nChoose the color for grid borders"]
		= "Couleur de bordure\n\nChoisissez la couleur des bordures",
	["Border style set to: %1\n\n%2\n\nChanges will apply when you next browse a catalog in grid view."]
		= "Style de bordure : %1\n\n%2\n\nLes modifications s'appliqueront lors de la prochaine navigation.",
	["Border thickness set to %1px.\n\nChanges will apply when you next browse a catalog in grid view."]
		= "Épaisseur de bordure : %1 px.\n\nLes modifications s'appliqueront lors de la prochaine navigation.",
	["Border color set to: %1\n\n%2\n\nChanges will apply when you next browse a catalog in grid view."]
		= "Couleur de bordure : %1\n\n%2\n\nLes modifications s'appliqueront lors de la prochaine navigation.",
	["Adjust the thickness of grid borders.\n\n• Thinner borders = more subtle\n• Thicker borders = more defined\n\nRecommended: 2-3px"]
		= "Épaisseur des bordures de la grille.\n\n• Fins = plus discret\n• Épais = plus défini\n\nRecommandé : 2-3 px",
	["Back to Borders"]                    = "Retour aux bordures",
	["Back to Border Settings"]            = "Retour aux paramètres de bordure",
	-- Border style names & descriptions
	["No Borders"]                         = "Aucune bordure",
	["Clean, borderless grid"]             = "Grille propre, sans bordure",
	["Hash Grid"]                          = "Grille croisée",
	["Shared borders like # pattern"]      = "Bordures partagées, motif #",
	["Individual Tiles"]                   = "Tuiles individuelles",
	["Each book has its own border"]       = "Chaque livre a sa propre bordure",
	-- Border color names & descriptions
	["Light Gray"]                         = "Gris clair",
	["Subtle, minimal contrast"]           = "Subtil, contraste minimal",
	["Dark Gray"]                          = "Gris foncé",
	["Balanced, clear definition"]         = "Équilibré, définition nette",
	["Black"]                              = "Noir",
	["High contrast, bold borders"]        = "Fort contraste, bordures marquées",
	["Dark Gray (Subtle)"]                 = "Gris foncé (subtil)",
	["Black (High Contrast)"]             = "Noir (fort contraste)",

	-- ── Font & text settings ──────────────────────────────────────────────────
	["Font & Text"]                        = "Police & Texte",
	["Use Same Font for All"]             = "Même police pour tout",
	["Now using the same font for title and details.\n\nChanges apply on next catalog browse."]
		= "Même police pour le titre et les détails.\n\nLes modifications s'appliqueront lors de la prochaine navigation.",
	["Now using separate fonts for title and details.\n\nChanges apply on next catalog browse."]
		= "Polices séparées pour le titre et les détails.\n\nLes modifications s'appliqueront lors de la prochaine navigation.",
	["Title Settings"]                     = "Paramètres du titre",
	["Title Font"]                         = "Police du titre",
	["Title Size"]                         = "Taille du titre",
	["Title Font Size"]                    = "Taille de la police du titre",
	["Title Bold"]                         = "Titre en gras",
	["Title is now bold."]                 = "Titre en gras activé.",
	["Title is now regular weight."]       = "Titre en grammage normal.",
	["Information Settings"]              = "Paramètres des détails",
	["Info Font"]                          = "Police des détails",
	["Info Size"]                          = "Taille des détails",
	["Info Bold"]                          = "Détails en gras",
	["Info Color"]                         = "Couleur des détails",
	["Information Font"]                   = "Police des informations",
	["Information Font Size"]             = "Taille de la police des informations",
	["Information text is now bold."]      = "Texte des informations en gras activé.",
	["Information text is now regular weight."] = "Texte des informations en grammage normal.",
	["Information text color set to black."]     = "Couleur du texte des informations : noir.",
	["Information text color set to dark gray."] = "Couleur du texte des informations : gris foncé.",
	["%1 Selection\n\nChoose a font"]      = "%1 — Sélectionner une police",
	["%1 set to:\n%2\n\nChanges will apply when you next browse a catalog."]
		= "%1 : %2\n\nLes modifications s'appliqueront lors de la prochaine navigation.",
	["%1 set to %2pt.\n\nChanges will apply when you next browse a catalog."]
		= "%1 : %2 pt\n\nLes modifications s'appliqueront lors de la prochaine navigation.",
	["Adjust the font size.\n\nChanges will apply when you next browse a catalog."]
		= "Taille de la police.\n\nLes modifications s'appliqueront lors de la prochaine navigation.",

	-- ── Developer / debug ─────────────────────────────────────────────────────
	["Developer"]                          = "Développeur",
	["Debug Mode"]                         = "Mode débogage",
	["Debug mode enabled.\n\nDetailed logging is now active."]
		= "Mode débogage activé.\n\nJournalisation détaillée active.",
	["Debug mode disabled.\n\nNormal logging restored."]
		= "Mode débogage désactivé.\n\nJournalisation normale restaurée.",
	["Advanced"]                           = "Avancé",

	-- ── Download & queue ──────────────────────────────────────────────────────
	["Download"]                           = "Télécharger",
	["Download all"]                       = "Tout télécharger",
	["Download all books?\nExisting files will be overwritten."]
		= "Télécharger tous les livres ?\nLes fichiers existants seront écrasés.",
	["Downloads"]                          = "Téléchargements",
	["Downloads (%1)"]                     = "Téléchargements (%1)",
	["Downloading…"]                       = "Téléchargement…",
	["Downloading… (tap to cancel)"]       = "Téléchargement… (toucher pour annuler)",
	["Queue all"]                          = "Tout mettre en file",
	["Queue all — select format"]          = "Tout mettre en file — choisir le format",
	["Queue all in series"]               = "Toute la série en file",
	["Queue %1 books (%2)?%3"]            = "Mettre en file %1 livre(s) (%2) ?%3",
	["%1 books added to queue."]          = "%1 livre(s) ajouté(s) à la file.",
	["Queue"]                              = "File",
	["Queue…"]                             = "File…",
	["Select format to download"]          = "Choisir le format à télécharger",
	["Select format to queue"]             = "Choisir le format à mettre en file",
	["Added to queue:\n%1"]               = "Ajouté à la file :\n%1",
	["1 book downloaded"]                  = "1 livre téléchargé",
	["%1 books downloaded"]               = "%1 livres téléchargés",
	["No downloadable books found in current view."] = "Aucun livre téléchargeable dans la vue actuelle.",
	["No %1 books found."]                 = "Aucun livre %1 trouvé.",
	["Read now"]                           = "Lire maintenant",
	["Borrow"]                             = "Emprunter",

	-- ── Download dialog options ───────────────────────────────────────────────
	["Choose folder"]                      = "Choisir un dossier",
	["Change filename"]                    = "Modifier le nom de fichier",
	["Enter filename"]                     = "Entrer le nom de fichier",
	["Set filename"]                       = "Définir le nom de fichier",
	["Download folder:\n%1\n\nDownload filename:\n%2\n\nDownload file type:"]
		= "Dossier de téléchargement :\n%1\n\nNom de fichier :\n%2\n\nType de fichier :",
	["Download Options\n\nDestination:\n%1\nFilename: %2"]
		= "Options de téléchargement\n\nDestination :\n%1\nFichier : %2",
	["Base folder…"]                       = "Dossier de base…",
	["Base folder (session)"]             = "Dossier de base (session)",
	["Subfolder…"]                         = "Sous-dossier…",
	["Subfolder name"]                     = "Nom du sous-dossier",
	["Series name"]                        = "Nom de la série",
	["(auto)"]                             = "(auto)",
	["(none)"]                             = "(aucun)",
	["Folder: "]                           = "Dossier : ",
	["File saved to:\n%1\nWould you like to read the downloaded book now?"]
		= "Fichier enregistré dans :\n%1\nVoulez-vous lire le livre téléchargé maintenant ?",
	["Remove all"]                         = "Tout supprimer",
	["Remove all downloads?"]              = "Supprimer tous les téléchargements ?",

	-- ── Sync ─────────────────────────────────────────────────────────────────
	["Sync"]                               = "Synchroniser",
	["Sync all catalogs"]                  = "Synchroniser tous les catalogues",
	["Force sync all catalogs"]           = "Forcer la synchronisation de tous les catalogues",
	["Force sync"]                         = "Forcer la synchronisation",
	["Synchronizing lists…"]              = "Synchronisation des listes…",
	["Up to date!"]                        = "À jour !",
	["Set sync folder"]                    = "Choisir le dossier de synchronisation",
	["Set max number of files to sync"]   = "Nombre maximum de fichiers à synchroniser",
	["Set the max number of books to download at a time"]
		= "Nombre maximum de livres à télécharger simultanément",
	["Set maximum sync size"]             = "Taille maximale de synchronisation",
	["Set file types to sync"]            = "Types de fichiers à synchroniser",
	["File types to sync"]                = "Types de fichiers à synchroniser",
	["A comma separated list of desired filetypes"] = "Liste de types de fichiers séparés par des virgules",
	["epub, mobi"]                         = "epub, mobi",
	["Please choose a folder for sync downloads first"]
		= "Veuillez d'abord choisir un dossier pour les téléchargements synchronisés",
	["These files are already on the device:"] = "Ces fichiers sont déjà présents sur l'appareil :",
	["Duplicate files"]                    = "Fichiers en double",
	["Do nothing"]                         = "Ne rien faire",
	["Overwrite"]                          = "Écraser",
	["Download copies"]                    = "Télécharger les copies",

	-- ── Book info dialog ──────────────────────────────────────────────────────
	["Book information"]                   = "Informations sur le livre",
	["Book Information"]                   = "Informations sur le livre",
	["Description"]                        = "Description",
	["No description available."]          = "Aucune description disponible.",
	["None available"]                     = "Aucun disponible",
	["Stream"]                             = "Flux",
	["Stream from page"]                   = "Flux depuis la page",
	["Resume stream from page"]           = "Reprendre le flux depuis la page",
	["Resume"]                             = "Reprendre",
	["Page stream"]                        = "Flux de pages",
	["Fetching series pages…"]            = "Récupération des pages de la série…",
	["Enter page number"]                  = "Entrer le numéro de page",
	["Options…"]                           = "Options…",
	["Close"]                              = "Fermer",
	["Unknown"]                            = "Inconnu",
	["Filters"]                            = "Filtres",
	["Folder"]                             = "Dossier",
	["File"]                               = "Fichier",

	-- ── Error / status messages ───────────────────────────────────────────────
	["Authentication required for catalog. Please add a username and password."]
		= "Authentification requise. Veuillez saisir un nom d'utilisateur et un mot de passe.",
	["Failed to authenticate. Please check your username and password."]
		= "Authentification échouée. Vérifiez votre nom d'utilisateur et votre mot de passe.",
	["Catalog not found."]                 = "Catalogue introuvable.",
	["Cannot get catalog. Server refuses to serve uncompressed content."]
		= "Impossible d'obtenir le catalogue. Le serveur refuse de servir du contenu non compressé.",
	["Cannot get catalog. Server response status: %1."]
		= "Impossible d'obtenir le catalogue. Statut de la réponse du serveur : %1.",
	["Cannot get catalog info from %1"]   = "Impossible d'obtenir les informations du catalogue depuis %1",
	["The catalog has been permanently moved. Please update catalog URL to '%1'."]
		= "Le catalogue a été déplacé définitivement. Veuillez mettre à jour l'URL du catalogue vers '%1'.",
	["Insecure HTTPS → HTTP downgrade attempted by redirect from:\n\n'%1'\n\nto\n\n'%2'.\n\nPlease inform the server administrator that many clients disallow this because it could be a downgrade attack."]
		= "Tentative de rétrogradation HTTPS → HTTP non sécurisée via une redirection de :\n\n'%1'\n\nvers\n\n'%2'.\n\nVeuillez informer l'administrateur du serveur que de nombreux clients n'autorisent pas cela (risque d'attaque de rétrogradation).",
	["Cannot create file:\n%1\n%2"]       = "Impossible de créer le fichier :\n%1\n%2",
	["Cannot download file:\n%1\n%2"]     = "Impossible de télécharger le fichier :\n%1\n%2",
	["Could not save file to:\n%1\n%2"]   = "Impossible d'enregistrer le fichier dans :\n%1\n%2",
	["Invalid protocol:\n%1"]             = "Protocole invalide :\n%1",
	["The file %1 already exists. Do you want to overwrite it?"]
		= "Le fichier %1 existe déjà. Voulez-vous l'écraser ?",

	-- ── Common UI ─────────────────────────────────────────────────────────────
	["Cancel"]                             = "Annuler",
	["Save"]                               = "Enregistrer",
	["Apply"]                              = "Appliquer",
	["Clear"]                              = "Effacer",
	["Set"]                                = "Définir",
	["Delete"]                             = "Supprimer",
	["Remove"]                             = "Supprimer",
	["Edit"]                               = "Modifier",
	["Search"]                             = "Rechercher",
	["Reset"]                              = "Réinitialiser",
	["Settings"]                           = "Paramètres",

	-- ── Username / password ───────────────────────────────────────────────────
	["Username (optional)"]               = "Nom d'utilisateur (optionnel)",
	["Password (optional)"]               = "Mot de passe (optionnel)",

	-- ── Misc ──────────────────────────────────────────────────────────────────
	["pages"]                              = "pages",
	["Author"]                             = "Auteur",
	["Formats"]                            = "Formats",
}

-- Callable table — same pattern as KOReader's own gettext module.
-- In Lua you cannot set fields on a plain function, so we use setmetatable
-- to make the table callable via __call while exposing .ngettext as a field.
local Locale = setmetatable({}, {
	__call = function(_, str)
		local lang = G_reader_settings and G_reader_settings:readSetting("language") or ""
		if lang:sub(1, 2) == "fr" and FR[str] then
			return FR[str]
		end
		return gettext(str)
	end,
})

function Locale.ngettext(singular, plural, n)
	local lang = G_reader_settings and G_reader_settings:readSetting("language") or ""
	if lang:sub(1, 2) == "fr" then
		local fr_singular = FR[singular] or singular
		local fr_plural   = FR[plural]   or plural
		return n <= 1 and fr_singular or fr_plural
	end
	return gettext.ngettext and gettext.ngettext(singular, plural, n)
		or (n == 1 and singular or plural)
end

return Locale
