-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ns.L

local CURSEFORGE_URL = "https://www.curseforge.com/wow/addons/enhanced-cooldown-manager"
local GITHUB_URL = "https://github.com/argium/EnhancedCooldownManager"

local function getAddonVersion()
    return (C_AddOns.GetAddOnMetadata("EnhancedCooldownManager", "Version") or "Unknown"):gsub("^v", "")
end

ns.AboutPage = {
    key = "about",
    rows = {
        {
            type = "info",
            name = L["AUTHOR"],
            value = function()
                return ns.ColorUtil.Sparkle("Argi")
            end,
        },
        {
            type = "info",
            name = L["CONTRIBUTORS"],
            value = "kayti-wow",
        },
        {
            type = "info",
            name = L["VERSION"],
            value = getAddonVersion,
        },
        {
            type = "subheader",
            name = L["LINKS"],
        },
        {
            type = "button",
            name = L["CURSEFORGE"],
            buttonText = L["CURSEFORGE"],
            onClick = function()
                ns.Addon:ShowCopyTextDialog(CURSEFORGE_URL, L["CURSEFORGE"])
            end,
        },
        {
            type = "button",
            name = L["GITHUB"],
            buttonText = L["GITHUB"],
            onClick = function()
                ns.Addon:ShowCopyTextDialog(GITHUB_URL, L["GITHUB"])
            end,
        },
        {
            type = "header",
            name = L["WHATS_NEW"],
        },
        {
            type = "button",
            name = L["WHATS_NEW"],
            buttonText = L["WHATS_NEW"],
            onClick = function()
                ns.Addon:ShowReleasePopup(true)
            end,
        },
    },
}
