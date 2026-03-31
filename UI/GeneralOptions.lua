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
    SB.RegisterFromTable({
        name = L["GENERAL"],
        path = "global",
        args = {
            -- Visibility
            visHeader = { type = "header", name = L["VISIBILITY"], order = 10 },
            hideWhenMounted = {
                type = "toggle",
                path = "hideWhenMounted",
                name = L["HIDE_WHEN_MOUNTED"],
                desc = L["HIDE_WHEN_MOUNTED_DESC"],
                order = 11,
            },
            hideInRestAreas = {
                type = "toggle",
                path = "hideOutOfCombatInRestAreas",
                name = L["HIDE_IN_REST_AREAS"],
                desc = L["HIDE_IN_REST_AREAS_DESC"],
                order = 12,
            },
            fade = {
                type = "toggle",
                path = "global.outOfCombatFade.enabled",
                name = L["FADE_OUT_OF_COMBAT"],
                desc = L["FADE_OUT_OF_COMBAT_DESC"],
                order = 13,
            },
            fadeOpacity = {
                type = "range",
                path = "global.outOfCombatFade.opacity",
                name = L["OUT_OF_COMBAT_OPACITY"],
                desc = L["OUT_OF_COMBAT_OPACITY_DESC"],
                min = 0,
                max = 100,
                step = 5,
                parent = "fade",
                order = 14,
            },
            fadeExceptInstance = {
                type = "toggle",
                path = "global.outOfCombatFade.exceptInInstance",
                name = L["EXCEPT_INSIDE_INSTANCES"],
                parent = "fade",
                order = 15,
            },
            fadeExceptHostile = {
                type = "toggle",
                path = "global.outOfCombatFade.exceptIfTargetCanBeAttacked",
                name = L["EXCEPT_TARGET_HOSTILE"],
                parent = "fade",
                order = 16,
            },
            fadeExceptFriendly = {
                type = "toggle",
                path = "global.outOfCombatFade.exceptIfTargetCanBeHelped",
                name = L["EXCEPT_TARGET_FRIENDLY"],
                parent = "fade",
                order = 17,
            },

            -- Appearance
            appearHeader = { type = "header", name = L["APPEARANCE"], order = 20 },
            texture = {
                type = "custom",
                path = "texture",
                name = L["BAR_TEXTURE"],
                desc = L["BAR_TEXTURE_DESC"],
                template = LSMW.TEXTURE_PICKER_TEMPLATE,
                order = 21,
            },
            font = {
                type = "custom",
                path = "font",
                name = L["FONT"],
                desc = L["FONT_DESC"],
                template = LSMW.FONT_PICKER_TEMPLATE,
                order = 22,
            },
            fontSize = {
                type = "range",
                path = "fontSize",
                name = L["FONT_SIZE"],
                min = 6,
                max = 32,
                step = 1,
                getTransform = function(value)
                    return value or 11
                end,
                order = 23,
            },
            fontOutline = {
                type = "select",
                path = "fontOutline",
                name = L["FONT_OUTLINE"],
                values = {
                    NONE = L["FONT_OUTLINE_NONE"],
                    OUTLINE = L["FONT_OUTLINE_OUTLINE"],
                    THICKOUTLINE = L["FONT_OUTLINE_THICK"],
                    MONOCHROME = L["FONT_OUTLINE_MONOCHROME"],
                },
                order = 24,
            },
            fontShadow = {
                type = "toggle",
                path = "fontShadow",
                name = L["FONT_SHADOW"],
                desc = L["FONT_SHADOW_DESC"],
                order = 25,
            },

            -- Sizing
            layoutHeader = { type = "header", name = L["SIZING"], order = 30 },
            barHeight = {
                type = "range",
                path = "barHeight",
                name = L["BAR_HEIGHT"],
                desc = L["BAR_HEIGHT_DESC"],
                min = 10,
                max = 40,
                step = 1,
                order = 31,
            },
        },
    })
end

ns.SettingsBuilder.RegisterSection(ns, "General", GeneralOptions)

local AdvancedOptions = {}

function AdvancedOptions.RegisterSettings(SB)
    SB.RegisterFromTable({
        name = L["ADVANCED_OPTIONS"],
        path = "global",
        args = {
            troubleshootHeader = { type = "header", name = L["TROUBLESHOOTING"], order = 10 },
            debug = {
                type = "toggle",
                path = "debug",
                name = L["DEBUG_MODE"],
                desc = L["DEBUG_MODE_DESC"],
                order = 11,
            },
            debugToChat = {
                type = "toggle",
                path = "debugToChat",
                name = L["DEBUG_TO_CHAT"],
                desc = L["DEBUG_TO_CHAT_DESC"],
                order = 12,
                disabled = function()
                    local gc = getGlobalConfig()
                    return not (gc and gc.debug)
                end,
            },
            updatesHeader = { type = "header", name = L["UPDATES"], order = 20 },
            showWhatsNew = {
                type = "button",
                name = " ",
                buttonText = L["SHOW_WHATS_NEW"],
                tooltip = L["SHOW_WHATS_NEW_DESC"],
                onClick = function()
                    if ns.Addon and type(ns.Addon.ShowReleasePopup) == "function" then
                        ns.Addon:ShowReleasePopup(true)
                    end
                end,
                order = 21,
            },
            perfHeader = { type = "header", name = L["PERFORMANCE"], order = 30 },
            updateFrequency = {
                type = "range",
                path = "updateFrequency",
                name = L["UPDATE_FREQUENCY"],
                desc = L["UPDATE_FREQUENCY_DESC"],
                min = 0.04,
                max = 0.5,
                step = 0.04, -- TODO: this step doesn't work correctly with the slider widget.
                order = 31,
            },
        },
    })
end

ns.SettingsBuilder.RegisterSection(ns, "Advanced Options", AdvancedOptions)
