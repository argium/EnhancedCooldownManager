-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ECM.L
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
            perfHeader = { type = "header", name = L["PERFORMANCE"], order = 20 },
            updateFrequency = {
                type = "range",
                path = "updateFrequency",
                name = L["UPDATE_FREQUENCY"],
                desc = L["UPDATE_FREQUENCY_DESC"],
                min = 0.04,
                max = 0.5,
                step = 0.04, -- TODO: this step doesn't work correctly with the slider widget.
                order = 21,
            },
        },
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "Advanced Options", AdvancedOptions)
