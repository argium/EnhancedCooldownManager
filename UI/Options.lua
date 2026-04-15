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

ns.Settings = LSB:New({
    name = L["ADDON_NAME"],
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
ns.SettingsBuilder = ns.Settings

--------------------------------------------------------------------------------
-- About section
--------------------------------------------------------------------------------

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
    },
}

--------------------------------------------------------------------------------
-- Options module
--------------------------------------------------------------------------------

local Options = ns.Addon:NewModule("Options")

local function isTrackedECMCategory(category)
    local root = ns.Settings
    return root ~= nil and root:HasCategory(category)
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
    local root = ns.Settings
    local section = root and root:GetSection("general")
    local page = section and section:GetPage("main")
    if page then
        return page:GetID()
    end

    return nil
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
    ns.Settings:Register({
        page = ns.AboutPage,
        sections = {
            ns.GeneralOptions,
            ns.LayoutOptions,
            ns.PowerBarOptions,
            ns.ResourceBarOptions,
            ns.RuneBarOptions,
            ns.BuffBarsOptions,
            ns.ExtraIconsOptions,
            ns.ProfileOptions,
            ns.AdvancedOptions,
        },
    })

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
