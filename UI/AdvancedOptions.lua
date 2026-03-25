-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ECM.L
local AdvancedOptions = {}
local getGlobalConfig = ECM.GetGlobalConfig or function()
    local db = ns.Addon and ns.Addon.db
    local profile = db and db.profile
    return profile and profile.global
end

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
            showReleasePopupOnUpdate = {
                type = "toggle",
                path = "showReleasePopupOnUpdate",
                name = L["SHOW_WHATS_NEW_ON_UPDATE"],
                desc = L["SHOW_WHATS_NEW_ON_UPDATE_DESC"],
                order = 21,
            },
            showWhatsNew = {
                type = "button",
                name = " ",
                buttonText = L["SHOW_WHATS_NEW"],
                tooltip = L["SHOW_WHATS_NEW_DESC"],
                onClick = function()
                    if ns.Addon and type(ns.Addon.ShowReleasePopup) == "function" then
                        ns.Addon:ShowReleasePopup(true)
                        return
                    end
                    ECM.Print(L["WHATS_NEW_UNAVAILABLE"])
                end,
                order = 22,
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

ECM.SettingsBuilder.RegisterSection(ns, "Advanced Options", AdvancedOptions)
