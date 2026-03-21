-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

ECM = ECM or {}

-- Locale table with fallback: missing keys return the key name itself.
local L = setmetatable({}, { __index = function(_, k) return k end })
ECM.L = L

--------------------------------------------------------------------------------
-- General
--------------------------------------------------------------------------------

L["ADDON_NAME"] = "Enhanced Cooldown Manager"
L["ADDON_ABRV"] = "ECM"
L["BETA_LOGIN_MESSAGE"] = "You are using a pre-release version of this addon. Some features may not work as expected and you will encounter bugs. Your settings may have been migrated. If you encounter oddidies, you can restore your settings from the last stable version. Type /ecm migration for details."

--------------------------------------------------------------------------------
-- Position Modes
--------------------------------------------------------------------------------

L["POSITION_MODE_DESC"] = "Choose how this module is positioned.\n\n- Automatic: Keeps this module in the main stack next to Blizzard's cooldown icons. Uses the shared spacing and grow direction settings.\n- Detached automatic: Places this module in a separate shared stack. Move the detached stack anchor in Edit Mode. Width, spacing, and grow direction are shared by all detached modules.\n- Free placement: Places this module independently. Drag this module directly in Edit Mode to position it."
L["POSITION_MODE_AUTOMATIC"] = "Automatic"
L["POSITION_MODE_DETACHED"] = "Automatic (detached)"
L["POSITION_MODE_FREE"] = "Free placement"
L["POSITION_MODE_EXPLAINER_TITLE_ATTACHED"] = "Attached"
L["POSITION_MODE_EXPLAINER_TITLE_DETACHED"] = "Detached stack"
L["POSITION_MODE_EXPLAINER_TITLE_FREE"] = "Free placement"
L["POSITION_MODE_EXPLAINER_CAPTION_ATTACHED"] = "Bars stay with the main cooldown icons."
L["POSITION_MODE_EXPLAINER_CAPTION_DETACHED"] = "Bars stay grouped together, but move as a separate stack."
L["POSITION_MODE_EXPLAINER_CAPTION_FREE"] = "Each bar can be positioned independently."

--------------------------------------------------------------------------------
-- Layout Settings
--------------------------------------------------------------------------------

L["LAYOUT_SUBCATEGORY"] = "Layout"
L["LAYOUT_PAGE_MOVED_BUTTON_TEXT"] = "Open"
L["MODULE_LAYOUT_HEADER"] = "Positioning"

L["WIDTH"] = "Width"
L["SPACING"] = "Spacing"
L["GROW_DIRECTION"] = "Grow Direction"
L["DOWN"] = "Down"
L["UP"] = "Up"

L["DETACHED_WIDTH_DESC"] = "Shared width for all modules using Detached Automatic mode."
L["DETACHED_SPACING_DESC"] = "Vertical spacing between modules in the detached stack."
L["DETACHED_GROW_DIRECTION_DESC"] = "Whether the detached stack grows upward or downward from its anchor."

L["VERTICAL_OFFSET"] = "Vertical Offset"
L["VERTICAL_OFFSET_DESC"] = "Vertical gap between the main cooldown icons and the first attached bar."
L["VERTICAL_SPACING"] = "Vertical Spacing"
L["VERTICAL_SPACING_DESC"] = "Vertical spacing between attached modules. Spacing between aura bars is controlled separately."
L["GROW_DIRECTION_ATTACHED_DESC"] = "Whether the attached stack grows above or below the main cooldown icons."

--------------------------------------------------------------------------------
-- Module Names
--------------------------------------------------------------------------------

L["POWER_BAR"] = "Power Bar"
L["RESOURCE_BAR"] = "Resource Bar"
L["RUNE_BAR"] = "Rune Bar"
L["AURA_BARS"] = "Aura Bars"
L["ITEM_ICONS"] = "Item Icons"

--------------------------------------------------------------------------------
-- Module Shared
--------------------------------------------------------------------------------

L["APPEARANCE"] = "Appearance"
L["SHOW_TEXT"] = "Show text"
L["SHOW_TEXT_DESC"] = "Display the current value on the bar."

--------------------------------------------------------------------------------
-- General Options
--------------------------------------------------------------------------------

L["GENERAL"] = "General"
L["VISIBILITY"] = "Visibility"
L["SIZING"] = "Sizing"

L["HIDE_WHEN_MOUNTED"] = "Hide when Mounted"
L["HIDE_WHEN_MOUNTED_DESC"] = "Automatically hide icon and bars while mounted."
L["HIDE_IN_REST_AREAS"] = "Hide in Rest Areas"
L["HIDE_IN_REST_AREAS_DESC"] = "Automatically hide icon and bars when in rest areas. Bars will reappear if you enter combat."
L["FADE_OUT_OF_COMBAT"] = "Fade when Out of Combat"
L["FADE_OUT_OF_COMBAT_DESC"] = "Automatically fade bars when out of combat to reduce screen clutter."
L["OUT_OF_COMBAT_OPACITY"] = "Out of Combat Opacity"
L["OUT_OF_COMBAT_OPACITY_DESC"] = "How visible the bars are when faded (0%% = invisible, 100%% = fully visible)."
L["EXCEPT_INSIDE_INSTANCES"] = "Except Inside Instances"
L["EXCEPT_TARGET_HOSTILE"] = "Except if Target is Hostile"
L["EXCEPT_TARGET_FRIENDLY"] = "Except if Target is Friendly"

L["BAR_TEXTURE"] = "Bar Texture"
L["BAR_TEXTURE_DESC"] = "Select the texture used for bars."
L["FONT"] = "Font"
L["FONT_DESC"] = "Select the font used for bar text."
L["FONT_SIZE"] = "Font Size"
L["FONT_OUTLINE"] = "Font Outline"
L["FONT_SHADOW"] = "Font Shadow"
L["FONT_SHADOW_DESC"] = "Enable a shadow behind bar text."
L["FONT_OUTLINE_NONE"] = "None"
L["FONT_OUTLINE_OUTLINE"] = "Outline"
L["FONT_OUTLINE_THICK"] = "Thick Outline"
L["FONT_OUTLINE_MONOCHROME"] = "Monochrome"

L["BAR_HEIGHT"] = "Bar Height"
L["BAR_HEIGHT_DESC"] = "Default height for all bars."

--------------------------------------------------------------------------------
-- Power Bar Options
--------------------------------------------------------------------------------

L["ENABLE_POWER_BAR"] = "Enable power bar"
L["SHOW_MANA_AS_PERCENT"] = "Show mana as percent"
L["SHOW_MANA_AS_PERCENT_DESC"] = "Display mana as percentage instead of raw value."
L["COLORS"] = "Colors"

-- Power type display names
L["POWER_MANA"] = "Mana"
L["POWER_RAGE"] = "Rage"
L["POWER_FOCUS"] = "Focus"
L["POWER_ENERGY"] = "Energy"
L["POWER_RUNIC_POWER"] = "Runic Power"
L["POWER_LUNAR_POWER"] = "Lunar Power"
L["POWER_MAELSTROM"] = "Maelstrom"
L["POWER_INSANITY"] = "Insanity"
L["POWER_FURY"] = "Fury"

--------------------------------------------------------------------------------
-- Resource Bar Options
--------------------------------------------------------------------------------

L["ENABLE_RESOURCE_BAR"] = "Enable resource bar"
L["USE_ALTERNATE_COLOR_WHEN_CAPPED"] = "Use alternate color when capped"
L["ALTERNATE_COLORS"] = "Alternate Colors"
L["ALTERNATE_COLOR_TOOLTIP"] = "Use an alternate color when this resource is at its maximum value."

-- Resource type display names
L["RESOURCE_SOUL_FRAGMENTS_DH"] = "Soul Fragments (Demon Hunter)"
L["RESOURCE_SOUL_FRAGMENTS_DEVOURER"] = "Soul Fragments (Devourer)"
L["RESOURCE_VOID_FRAGMENTS_DEVOURER"] = "Void Fragments (Devourer)"
L["RESOURCE_ICICLES"] = "Icicles (Frost Mage)"
L["RESOURCE_ARCANE_CHARGES"] = "Arcane Charges"
L["RESOURCE_CHI"] = "Chi"
L["RESOURCE_COMBO_POINTS"] = "Combo Points"
L["RESOURCE_ESSENCE"] = "Essence"
L["RESOURCE_HOLY_POWER"] = "Holy Power"
L["RESOURCE_MAELSTROM_WEAPON"] = "Maelstrom Weapon (Enhancement)"
L["RESOURCE_SOUL_SHARDS"] = "Soul Shards"

--------------------------------------------------------------------------------
-- Rune Bar Options
--------------------------------------------------------------------------------

L["DK_ONLY_WARNING"] = "|cffFF8800These settings are only applicable to Death Knights.|r"
L["ENABLE_RUNE_BAR"] = "Enable rune bar"
L["USE_SPEC_COLOR"] = "Use specialization color"
L["USE_SPEC_COLOR_DESC"] = "Use your current specialization's color for the rune bar. If disabled, you can set a custom color below."
L["RUNE_COLOR"] = "Rune color"
L["BLOOD_COLOR"] = "Blood color"
L["FROST_COLOR"] = "Frost color"
L["UNHOLY_COLOR"] = "Unholy color"

--------------------------------------------------------------------------------
-- Buff / Aura Bars Options
--------------------------------------------------------------------------------

L["ENABLE_AURA_BARS"] = "Enable aura bars"
L["ENABLE_AURA_BARS_DESC"] = "Styles and repositions Blizzard's aura duration bars that are part of the Cooldown Manager."
L["DISABLE_AURA_BARS_RELOAD"] = "Disabling aura bars requires a UI reload. Reload now?"
L["SHOW_ICON"] = "Show icon"
L["SHOW_SPELL_NAME"] = "Show spell name"
L["SHOW_REMAINING_DURATION"] = "Show remaining duration"
L["HEIGHT_OVERRIDE"] = "Height Override"
L["HEIGHT_OVERRIDE_DESC"] = "Override the default bar height. Set to 0 to use the global default."
L["AURA_VERTICAL_SPACING"] = "Vertical Spacing"
L["AURA_VERTICAL_SPACING_DESC"] = "Vertical gap between aura bars. Set to 0 for no spacing."
L["CONFIGURE_SPELL_COLORS"] = "Configure Spell Colors"
L["OPEN"] = "Open"

L["SPELL_COLORS_SUBCAT"] = "Spell Colors"
L["SPELL_COLORS_DESC"] = "Customize colors for individual spells. Colors are saved per class and specialization."
L["SPELL_COLORS_SECRET_NAMES_DESC"] = "One or more spell names have become secret. This can be cleared by reloading the UI outside of restricted area, typically dungeons, raids, delves, and PVP."
L["SPELL_COLORS_RELOAD_BUTTON"] = "Reload UI"
L["SPELL_COLORS_RESET_CONFIRM"] = "Are you sure you want to reset all spell colors for this spec?"
L["SPELL_COLORS_COMBAT_WARNING"] = "|cffFF0000These settings cannot be changed while in combat lockdown.|r"
L["SPELL_COLORS_SECRETS_WARNING"] = "|cffFFDD3CSpell names are currently secret. Changes are blocked until you reload your UI out of combat.|r"
L["DEFAULT_COLOR"] = "Default color"

--------------------------------------------------------------------------------
-- Tick Marks Options
--------------------------------------------------------------------------------

L["TICK_MARKS_DESC"] = "Customize tick marks for the power bar. Marks are saved per class and specialization."
L["TICK_MARKS_CLEAR_CONFIRM"] = "Are you sure you want to remove all tick marks for this spec?"
L["DEFAULT_WIDTH"] = "Default width"
L["ADD_TICK_MARK"] = "Add Tick Mark"
L["ADD"] = "Add"
L["REMOVE"] = "Remove"
L["TICK_N"] = "Tick %d"
L["NO_TICK_MARKS"] = "%s - no tick marks configured."
L["TICK_COUNT"] = "%s - %d tick mark(s) configured."

--------------------------------------------------------------------------------
-- Item Icons Options
--------------------------------------------------------------------------------

L["ENABLE_ITEM_ICONS"] = "Enable item icons"
L["ENABLE_ITEM_ICONS_DESC"] = "Display icons for equipped on-use trinkets and select consumables to the right of utility cooldowns."
L["EQUIPMENT"] = "Equipment"
L["CONSUMABLES"] = "Consumables"
L["SHOW_FIRST_TRINKET"] = "Show first trinket"
L["SHOW_FIRST_TRINKET_DESC"] = "Display icons for usable equipment. Trinkets without an on-use effect are never shown."
L["SHOW_SECOND_TRINKET"] = "Show second trinket"
L["SHOW_HEALTH_POTIONS"] = "Show health potions"
L["SHOW_COMBAT_POTIONS"] = "Show combat potions"
L["SHOW_HEALTHSTONE"] = "Show healthstone"

--------------------------------------------------------------------------------
-- About
--------------------------------------------------------------------------------

L["AUTHOR"] = "Author"
L["CONTRIBUTORS"] = "Contributors"
L["VERSION"] = "Version"
L["LINKS"] = "Links"
L["CURSEFORGE"] = "CurseForge"
L["GITHUB"] = "GitHub"

--------------------------------------------------------------------------------
-- Advanced Options
--------------------------------------------------------------------------------

L["ADVANCED_OPTIONS"] = "Advanced Options"
L["TROUBLESHOOTING"] = "Troubleshooting"
L["DEBUG_MODE"] = "Debug Mode"
L["DEBUG_MODE_DESC"] = "Enable debug logging to the chat frame and Dev Tools addon (if installed)."
L["PERFORMANCE"] = "Performance"
L["UPDATE_FREQUENCY"] = "Update Frequency"
L["UPDATE_FREQUENCY_DESC"] = "How often (in seconds) to refresh bar displays. Lower values are smoother but use more CPU."

--------------------------------------------------------------------------------
-- Profile Options
--------------------------------------------------------------------------------

L["PROFILES"] = "Profiles"
L["ACTIVE_PROFILE"] = "Active Profile"
L["SWITCH_PROFILE"] = "Switch Profile"
L["CREATE_NEW_PROFILE"] = "Create a new profile"
L["NEW_PROFILE"] = "New Profile"
L["NEW_PROFILE_DESC"] = "Create a new profile using your current character name."
L["PROFILE_ACTIONS"] = "Profile Actions"
L["COPY_FROM"] = "Copy From"
L["COPY_FROM_DESC"] = "Select a profile to copy settings from."
L["APPLY_COPY"] = "Apply copy from selected profile"
L["COPY"] = "Copy"
L["COPY_DESC"] = "Copy all settings from the selected profile into the current one."
L["DELETE_PROFILE"] = "Delete Profile"
L["DELETE_PROFILE_SELECT_DESC"] = "Select a profile to delete."
L["DELETE"] = "Delete"
L["DELETE_DESC"] = "Delete the selected profile. The active profile cannot be deleted."
L["DELETE_PROFILE_CONFIRM"] = "Are you sure you want to delete the profile '%s'?"
L["RESET"] = "Reset"
L["RESET_PROFILE"] = "Reset current profile to defaults"
L["RESET_PROFILE_BUTTON"] = "Reset Profile"
L["RESET_PROFILE_DESC"] = "Reset the current profile back to default settings. This cannot be undone."
L["RESET_PROFILE_CONFIRM"] = "Are you sure you want to reset the current profile to defaults?"
L["IMPORT_EXPORT"] = "Import / Export"
L["IMPORT_PROFILE"] = "Import profile from clipboard"
L["IMPORT"] = "Import"
L["IMPORT_DESC"] = "Paste a previously exported profile string to import settings."
L["EXPORT_PROFILE"] = "Export profile to clipboard"
L["EXPORT"] = "Export"
L["EXPORT_DESC"] = "Generate a shareable string that can be imported on another character."
L["CANNOT_IMPORT_IN_COMBAT"] = "Cannot import during combat (reload blocked)"
L["EXPORT_FAILED"] = "Export failed: %s"

--------------------------------------------------------------------------------
-- Chat Commands
--------------------------------------------------------------------------------

L["CMD_HELP_DEBUG"] = "/ecm debug [on|off|toggle] - toggle debug mode (logs detailed info to the chat frame)"
L["CMD_HELP_HELP"] = "/ecm help - show this message"
L["CMD_HELP_MIGRATION"] = "/ecm migration - show migration info and commands"
L["CMD_HELP_OPTIONS"] = "/ecm options|config|settings|o - open the options menu"
L["CMD_HELP_REFRESH"] = "/ecm rl|reload|refresh - refresh and reapply layout for all modules"
L["REFRESHING_ALL_MODULES"] = "Refreshing all modules."
L["OPTIONS_BLOCKED_COMBAT"] = "Options cannot be opened during combat. They will open when combat ends."
L["MIGRATION_ROLLBACK_USAGE"] = "Usage: /ecm migration rollback <version>"
L["VERSION_ZERO_INVALID"] = "Version 0 is not valid."
L["DEBUG_USAGE"] = "Usage: expected on|off|toggle"
L["DEBUG_STATUS"] = "Debug:"
L["DEBUG_ON"] = "ON"
L["DEBUG_OFF"] = "OFF"
L["MODULE_NOT_FOUND"] = "Module not found:"

--------------------------------------------------------------------------------
-- Import / Export Dialogs
--------------------------------------------------------------------------------

L["EXPORT_PROFILE_TITLE"] = "Export Profile"
L["COPY_CTRL_C"] = "Press Ctrl+C to copy. The dialog will close automatically."
L["IMPORT_COPIED"] = "Copied to clipboard."
L["COPY_LINK"] = "Copy Link"
L["IMPORT_PROFILE_TITLE"] = "Import Profile"
L["IMPORT_PASTE_PROMPT"] = "Paste your import string below and click Import."
L["IMPORT_CANCELLED"] = "Import cancelled: no string provided"
L["IMPORT_FAILED"] = "Import failed: %s"
L["IMPORT_APPLY_FAILED"] = "Import apply failed: %s"
L["IMPORT_CONFIRM"] = "Import profile settings (exported from v%s)?\n\nThis will replace your current profile and reload the UI."
L["INVALID_EXPORT_STRING"] = "Invalid export string provided"
L["RELOAD_BLOCKED_COMBAT"] = "Cannot reload the UI right now: UI reload is blocked during combat."
L["RELOAD_UI_PROMPT"] = "Reload the UI?"

--------------------------------------------------------------------------------
-- Import / Export Errors
--------------------------------------------------------------------------------

L["ENCODE_NO_DATA"] = "No data provided for encoding"
L["ENCODE_SERIALIZATION_FAILED"] = "Serialization failed"
L["ENCODE_COMPRESSION_FAILED"] = "Compression failed"
L["ENCODE_ENCODING_FAILED"] = "Encoding failed"
L["DECODE_EMPTY"] = "Import string is empty"
L["DECODE_INVALID_FORMAT"] = "Invalid import string format"
L["DECODE_WRONG_ADDON"] = "This import string is not for Enhanced Cooldown Manager (prefix: %s)"
L["DECODE_INCOMPATIBLE_VERSION"] = "Incompatible import string version (expected %d, got %s)"
L["DECODE_CORRUPTED"] = "Failed to decode string - it may be corrupted or incomplete"
L["DECODE_DECOMPRESS_FAILED"] = "Failed to decompress data - the string may be corrupted"
L["DECODE_DESERIALIZE_FAILED"] = "Failed to deserialize data - the string may be corrupted"
L["IMPORT_NO_PROFILE"] = "No active profile found"
L["IMPORT_NO_PROFILE_DATA"] = "Import string does not contain profile data"
L["IMPORT_INVALID_DATA"] = "Invalid import data"
L["IMPORT_NO_ACTIVE_PROFILE"] = "No active profile to import into"
