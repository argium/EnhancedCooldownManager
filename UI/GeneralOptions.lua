-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ns.L
local LSMW = LibStub("LibLSMSettingsWidgets-1.0")
local getGlobalConfig = ns.GetGlobalConfig or function()
    local db = ns.Addon and ns.Addon.db
    local profile = db and db.profile
    return profile and profile.global
end

local GeneralOptions = {}

function GeneralOptions.RegisterSettings(SB)
    SB.RegisterPage({
        name = L["GENERAL"],
        path = "global",
        rows = {
            -- Visibility
            { type = "header", name = L["VISIBILITY"] },
            {
                type = "checkbox",
                path = "hideWhenMounted",
                name = L["HIDE_WHEN_MOUNTED"],
                desc = L["HIDE_WHEN_MOUNTED_DESC"],
            },
            {
                type = "checkbox",
                path = "hideOutOfCombatInRestAreas",
                name = L["HIDE_IN_REST_AREAS"],
                desc = L["HIDE_IN_REST_AREAS_DESC"],
            },
            {
                id = "fade",
                type = "checkbox",
                path = "global.outOfCombatFade.enabled",
                name = L["FADE_OUT_OF_COMBAT"],
                desc = L["FADE_OUT_OF_COMBAT_DESC"],
            },
            {
                type = "slider",
                path = "global.outOfCombatFade.opacity",
                name = L["OUT_OF_COMBAT_OPACITY"],
                desc = L["OUT_OF_COMBAT_OPACITY_DESC"],
                min = 0,
                max = 100,
                step = 5,
                parent = "fade",
            },
            {
                type = "checkbox",
                path = "global.outOfCombatFade.exceptInInstance",
                name = L["EXCEPT_INSIDE_INSTANCES"],
                parent = "fade",
            },
            {
                type = "checkbox",
                path = "global.outOfCombatFade.exceptIfTargetCanBeAttacked",
                name = L["EXCEPT_TARGET_HOSTILE"],
                parent = "fade",
            },
            {
                type = "checkbox",
                path = "global.outOfCombatFade.exceptIfTargetCanBeHelped",
                name = L["EXCEPT_TARGET_FRIENDLY"],
                parent = "fade",
            },

            -- Appearance
            { type = "header", name = L["APPEARANCE"] },
            {
                type = "custom",
                path = "texture",
                name = L["BAR_TEXTURE"],
                desc = L["BAR_TEXTURE_DESC"],
                template = LSMW.TEXTURE_PICKER_TEMPLATE,
            },
            {
                type = "custom",
                path = "font",
                name = L["FONT"],
                desc = L["FONT_DESC"],
                template = LSMW.FONT_PICKER_TEMPLATE,
            },
            {
                type = "slider",
                path = "fontSize",
                name = L["FONT_SIZE"],
                min = 6,
                max = 32,
                step = 1,
                getTransform = function(value)
                    return value or 11
                end,
            },
            {
                type = "dropdown",
                path = "fontOutline",
                name = L["FONT_OUTLINE"],
                values = {
                    NONE = L["FONT_OUTLINE_NONE"],
                    OUTLINE = L["FONT_OUTLINE_OUTLINE"],
                    THICKOUTLINE = L["FONT_OUTLINE_THICK"],
                    MONOCHROME = L["FONT_OUTLINE_MONOCHROME"],
                },
            },
            {
                type = "checkbox",
                path = "fontShadow",
                name = L["FONT_SHADOW"],
                desc = L["FONT_SHADOW_DESC"],
            },

            -- Sizing
            { type = "header", name = L["SIZING"] },
            {
                type = "slider",
                path = "barHeight",
                name = L["BAR_HEIGHT"],
                desc = L["BAR_HEIGHT_DESC"],
                min = 10,
                max = 40,
                step = 1,
            },
        },
    })
end

ns.SettingsBuilder.RegisterSection(ns, "General", GeneralOptions)

local AdvancedOptions = {}

function AdvancedOptions.RegisterSettings(SB)
    SB.RegisterPage({
        name = L["ADVANCED_OPTIONS"],
        path = "global",
        rows = {
            { type = "header", name = L["TROUBLESHOOTING"] },
            {
                type = "checkbox",
                path = "debug",
                name = L["DEBUG_MODE"],
                desc = L["DEBUG_MODE_DESC"],
            },
            {
                type = "checkbox",
                path = "debugToChat",
                name = L["DEBUG_TO_CHAT"],
                desc = L["DEBUG_TO_CHAT_DESC"],
                disabled = function()
                    local gc = getGlobalConfig()
                    return not (gc and gc.debug)
                end,
            },
            { type = "header", name = L["UPDATES"] },
            {
                type = "button",
                name = " ",
                buttonText = L["SHOW_WHATS_NEW"],
                tooltip = L["SHOW_WHATS_NEW_DESC"],
                onClick = function()
                    if ns.Addon and type(ns.Addon.ShowReleasePopup) == "function" then
                        ns.Addon:ShowReleasePopup(true)
                    end
                end,
            },
            { type = "header", name = L["PERFORMANCE"] },
            {
                type = "slider",
                path = "updateFrequency",
                name = L["UPDATE_FREQUENCY"],
                desc = L["UPDATE_FREQUENCY_DESC"],
                min = 0.04,
                max = 0.5,
                step = 0.02,
            },
        },
    })
end

ns.SettingsBuilder.RegisterSection(ns, "Advanced Options", AdvancedOptions)
