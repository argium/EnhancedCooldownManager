-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local Options = mod:NewModule("Options")
local C = ECM.Constants

ns.OptionsSections = ns.OptionsSections or {}

function Options:OnInitialize()
    local SB = ECM.SettingsBuilder
    SB.CreateRootCategory(C.ADDON_NAME)

    -- Register sections in display order (About is on the root page)
    local sectionOrder = {
        "About",
        "General",
        "PowerBar",
        "ResourceBar",
        "RuneBar",
        "BuffBars",
        "ItemIcons",
        "Profile",
    }

    for _, key in ipairs(sectionOrder) do
        local section = ns.OptionsSections[key]
        if section and section.RegisterSettings then
            section.RegisterSettings(SB)
        end
    end

    SB.RegisterCategories()

    local db = mod.db
    db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
end

function Options:OnProfileChanged()
    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
end

function Options:OpenOptions()
    local categoryID = ECM.SettingsBuilder.GetSubcategoryID("General")
        or ECM.SettingsBuilder.GetRootCategoryID()
    if categoryID then
        Settings.OpenToCategory(categoryID)
    end
end
