-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ns.L

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
        return ns.Addon.db.defaults.profile
    end,
    onChanged = function(ctx)
        if ctx.spec.layout ~= false then
            ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
        end
    end,
    defaultsConfirmation = function(pageName, onAccept)
        ns.OptionUtil.ConfirmPageDefaultsReset(pageName, onAccept)
    end,
})
ns.SettingsBuilder = ns.Settings


local Options = ns.Addon:NewModule("Options")

local function isTrackedECMCategory(category)
    local root = ns.Settings
    return root ~= nil and root:HasCategory(category)
end

local function getCategoryOpenToken(category)
    if category then
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

    self._categoryTrackingInstalled = true
    hooksecurefunc(SettingsPanel, "DisplayCategory", function(panel)
        rememberTrackedCategory(self, panel:GetCurrentCategory())
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

    local function initializeOptionsTable(optionsTable)
        optionsTable.OnInitialize()
    end

    initializeOptionsTable(ns.BuffBarsOptions)

    if ns.ExternalBarsOptions then
        initializeOptionsTable(ns.ExternalBarsOptions)
        sections[#sections + 1] = ns.ExternalBarsOptions
    end

    sections[#sections + 1] = {
        key = "spellColors",
        name = L["SPELL_COLORS_SUBCAT"],
        pages = { ns.SpellColorsPage:CreatePage(L["SPELL_COLORS_SUBCAT"]) },
    }

    sections[#sections + 1] = ns.ProfileOptions
    sections[#sections + 1] = ns.AdvancedOptions

    ns.Settings:_registerTree({
        page = ns.AboutPage,
        sections = sections,
    })

    initializeOptionsTable(ns.ExtraIconsOptions)
    initializeOptionsTable(ns.ItemStacksOptions)
    initializeOptionsTable(ns.PowerBarTickMarksOptions)
    ns.SpellColorsPage:OnInitialize()

    self:InstallCategoryTracking()
end

function Options:OpenOptions()
    self:InstallCategoryTracking()

    rememberTrackedCategory(self, SettingsPanel:GetCurrentCategory())

    local categoryToken = self._lastOpenedCategoryToken or getDefaultOptionsCategoryToken()
    if categoryToken then
        Settings.OpenToCategory(categoryToken)
    end
end
