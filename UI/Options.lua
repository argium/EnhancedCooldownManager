-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ns.L
local LSMW = LibStub("LibLSMSettingsWidgets-1.0")

local OU = ns.OptionUtil
local getGlobalConfig = ns.GetGlobalConfig or function()
    local db = ns.Addon and ns.Addon.db
    local profile = db and db.profile
    return profile and profile.global
end

local CURSEFORGE_URL = "https://www.curseforge.com/wow/addons/enhanced-cooldown-manager"
local GITHUB_URL = "https://github.com/argium/EnhancedCooldownManager"

--------------------------------------------------------------------------------
-- SettingsBuilder instance
--------------------------------------------------------------------------------

local LSB = LibStub("LibSettingsBuilder-1.0")

ns.SettingsBuilder = LSB:New({
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
            ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
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
-- About section
--------------------------------------------------------------------------------

local About = {}

function About.RegisterSettings(SB)
    local version = (C_AddOns.GetAddOnMetadata("EnhancedCooldownManager", "Version") or "Unknown"):gsub("^v", "")
    local authorText = ns.ColorUtil.Sparkle("Argi")

    SB.RegisterFromTable({
        name = L["ADDON_NAME"],
        rootCategory = true,
        args = {
            author = {
                type = "info",
                name = L["AUTHOR"],
                value = authorText,
                order = 1,
            },
            contributors = {
                type = "info",
                name = L["CONTRIBUTORS"],
                value = "kayti-wow",
                order = 2,
            },
            version = {
                type = "info",
                name = L["VERSION"],
                value = version,
                order = 3,
            },
            linksHeader = {
                type = "description",
                name = L["LINKS"],
                order = 9,
            },
            curseforge = {
                type = "button",
                name = L["CURSEFORGE"],
                buttonText = L["CURSEFORGE"],
                onClick = function()
                    ns.Addon:ShowCopyTextDialog(CURSEFORGE_URL, L["CURSEFORGE"])
                end,
                order = 10,
            },
            github = {
                type = "button",
                name = L["GITHUB"],
                buttonText = L["GITHUB"],
                onClick = function()
                    ns.Addon:ShowCopyTextDialog(GITHUB_URL, L["GITHUB"])
                end,
                order = 11,
            },
        },
    })
end

--------------------------------------------------------------------------------
-- Options module
--------------------------------------------------------------------------------

ns.OptionsSections = ns.OptionsSections or {}
ns.OptionsSections["About"] = About

local Options = ns.Addon:NewModule("Options")

local function isTrackedECMCategory(category)
    local SB = ns.SettingsBuilder
    return SB ~= nil and SB.HasCategory(category)
end

local function getCategoryOpenToken(category)
    if category and type(category.GetID) == "function" then
        return category:GetID()
    end
end

local function rememberTrackedCategory(module, category)
    if not isTrackedECMCategory(category) then
        return
    end

    local token = getCategoryOpenToken(category)
    if token ~= nil then
        module._lastOpenedCategoryToken = token
    end
end

local function getDefaultOptionsCategoryToken()
    local SB = ns.SettingsBuilder
    local category = SB.GetSubcategory(L["GENERAL"]) or SB.GetRootCategory()
    return getCategoryOpenToken(category)
end

function Options:InstallCategoryTracking()
    if self._categoryTrackingInstalled then
        return
    end

    if type(SettingsPanel) ~= "table" or type(SettingsPanel.DisplayCategory) ~= "function" then
        if self._categoryTrackingDeferred or type(CreateFrame) ~= "function" then
            return
        end

        self._categoryTrackingDeferred = true
        local tracker = CreateFrame("Frame")
        tracker:RegisterEvent("ADDON_LOADED")
        tracker:SetScript("OnEvent", function(frame)
            if type(SettingsPanel) == "table" and type(SettingsPanel.DisplayCategory) == "function" then
                self._categoryTrackingDeferred = nil
                self:InstallCategoryTracking()
                if frame.UnregisterAllEvents then
                    frame:UnregisterAllEvents()
                end
            end
        end)
        return
    end

    self._categoryTrackingInstalled = true
    hooksecurefunc(SettingsPanel, "DisplayCategory", function(panel)
        local category = panel.GetCurrentCategory and panel:GetCurrentCategory() or nil
        rememberTrackedCategory(self, category)
    end)
end

function Options:OnInitialize()
    local SB = ns.SettingsBuilder
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
        "ExtraIcons",
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
    self:InstallCategoryTracking()
end

function Options:OpenOptions()
    self:InstallCategoryTracking()

    local currentCategory = SettingsPanel and SettingsPanel.GetCurrentCategory and SettingsPanel:GetCurrentCategory() or nil
    rememberTrackedCategory(self, currentCategory)

    local categoryToken = self._lastOpenedCategoryToken or getDefaultOptionsCategoryToken()
    if categoryToken then
        Settings.OpenToCategory(categoryToken)
    end
end
