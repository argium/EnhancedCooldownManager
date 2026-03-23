-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ECM.L
local LSMW = LibStub("LibLSMSettingsWidgets-1.0")

local OU = ECM.OptionUtil
local getGlobalConfig = ECM.GetGlobalConfig or function()
    local db = ns.Addon and ns.Addon.db
    local profile = db and db.profile
    return profile and profile.global
end

--------------------------------------------------------------------------------
-- SettingsBuilder instance
--------------------------------------------------------------------------------

local LSB = LibStub("LibSettingsBuilder-1.0")

ECM.SettingsBuilder = LSB:New({
    pathAdapter = LSB.PathAdapter({
        getStore = function()
            return ns.Addon.db and ns.Addon.db.profile
        end,
        getDefaults = function()
            return ns.Addon.db and ns.Addon.db.defaults and ns.Addon.db.defaults.profile
        end,
        getNestedValue = OU.GetNestedValue,
        setNestedValue = OU.SetNestedValue,
    }),
    varPrefix = "ECM",
    onChanged = function(spec)
        if spec.layout ~= false then
            ECM.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
        end
    end,
    compositeDefaults = {
        FontOverrideGroup = {
            fontValues = LSMW.GetFontValues,
            fontFallback = function()
                local gc = getGlobalConfig()
                return gc and gc.font
            end,
            fontSizeFallback = function()
                local gc = getGlobalConfig()
                return gc and gc.fontSize
            end,
            fontTemplate = LSMW.FONT_PICKER_TEMPLATE,
        },
    },
})

--------------------------------------------------------------------------------
-- Options module
--------------------------------------------------------------------------------

ns.OptionsSections = ns.OptionsSections or {}

local Options = ns.Addon:NewModule("Options")

function Options:OnInitialize()
    local SB = ECM.SettingsBuilder
    SB.CreateRootCategory(L["ADDON_NAME"])

    -- About section renders on the root category (no subcategory entry)
    ns.OptionsSections["About"].RegisterSettings(SB)

    -- Register subcategory sections in display order
    local sectionOrder = {
        "General",
        "Layout",
        "PowerBar",
        "ResourceBar",
        "RuneBar",
        "BuffBars",
        "ItemIcons",
        "Profile",
        "Advanced Options",
    }

    for _, key in ipairs(sectionOrder) do
        local section = ns.OptionsSections[key]
        if section and section.RegisterSettings then
            section.RegisterSettings(SB)
        end
    end

    SB.RegisterCategories()
end

function Options:OpenOptions()
    local categoryID = ECM.SettingsBuilder.GetSubcategoryID(L["GENERAL"]) or ECM.SettingsBuilder.GetRootCategoryID()
    if categoryID then
        Settings.OpenToCategory(categoryID)
    end
end
