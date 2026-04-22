-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ns.L

local CURSEFORGE_URL = "https://www.curseforge.com/wow/addons/enhanced-cooldown-manager"
local GITHUB_URL = "https://github.com/argium/EnhancedCooldownManager"

--------------------------------------------------------------------------------
-- SettingsBuilder instance
--------------------------------------------------------------------------------

local LSB = LibStub("LibSettingsBuilder-1.0")

ns.Settings = LSB:New({
    name = L["ADDON_NAME"],
    store = function()
        return ns.Addon.db and ns.Addon.db.profile
    end,
    defaults = function()
        return ns.Addon.db and ns.Addon.db.defaults and ns.Addon.db.defaults.profile
    end,
    onChanged = function(ctx)
        if ctx.spec.layout ~= false then
            ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
        end
    end,
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
    local page = root and root:GetPage("general", "main")
    if page then
        return page:GetId()
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
    local sections = {
        ns.GeneralOptions,
        ns.LayoutOptions,
        ns.PowerBarOptions,
        ns.ResourceBarOptions,
        ns.RuneBarOptions,
        ns.BuffBarsOptions,
        ns.ExtraIconsOptions,
    }

    if ns.ExternalBarsOptions then
        sections[#sections + 1] = ns.ExternalBarsOptions
    end

    sections[#sections + 1] = {
        key = "spellColors",
        name = L["SPELL_COLORS_SUBCAT"],
        pages = { ns.SpellColorsPage.CreatePage(L["SPELL_COLORS_SUBCAT"]) },
    }

    sections[#sections + 1] = ns.ProfileOptions
    sections[#sections + 1] = ns.AdvancedOptions

    ns.Settings:_registerTree({
        page = ns.AboutPage,
        sections = sections,
    })

    if ns.ExtraIconsOptionsUtil then
        ns.ExtraIconsOptionsUtil.SetRegisteredPage(ns.Settings:GetPage("extraIcons", "main"))
        ns.ExtraIconsOptionsUtil.EnsureItemLoadFrame()
    end
    if ns.PowerBarTickMarksOptions and ns.PowerBarTickMarksOptions.SetRegisteredPage then
        ns.PowerBarTickMarksOptions.SetRegisteredPage(ns.Settings:GetPage("powerBar", "tickMarks"))
    end
    if ns.SpellColorsPage and ns.SpellColorsPage.SetRegisteredPage then
        ns.SpellColorsPage.SetRegisteredPage(ns.Settings:GetPage("spellColors", "spellColors"))
    end

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
