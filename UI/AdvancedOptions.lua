-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ns.L

local AdvancedOptions = {
    key = "advancedOptions",
    name = L["ADVANCED_OPTIONS"],
    path = "global",
    pages = {
        {
            key = "main",
            rows = {
                { type = "header", name = L["TROUBLESHOOTING"] },
                {
                    type = "checkbox",
                    path = "debug",
                    name = L["DEBUG_MODE"],
                    tooltip = L["DEBUG_MODE_DESC"],
                },
                {
                    type = "checkbox",
                    path = "debugToChat",
                    name = L["DEBUG_TO_CHAT"],
                    tooltip = L["DEBUG_TO_CHAT_DESC"],
                    disabled = function()
                        local gc = ns.GetGlobalConfig()
                        return not (gc and gc.debug)
                    end,
                },
                { type = "header", name = L["PERFORMANCE"] },
                {
                    type = "slider",
                    path = "updateFrequency",
                    name = L["UPDATE_FREQUENCY"],
                    tooltip = L["UPDATE_FREQUENCY_DESC"],
                    min = 0.04,
                    max = 0.5,
                    step = 0.02,
                },
            },
        },
    },
}
ns.AdvancedOptions = AdvancedOptions
