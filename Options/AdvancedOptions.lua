-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon

local AdvancedOptions = {}

function AdvancedOptions.RegisterSettings(SB)
    SB.RegisterFromTable({
        name = "Advanced Options",
        path = "global",
        args = {
            troubleshootHeader = { type = "header", name = "Troubleshooting", order = 10 },
            debug = {
                type = "toggle",
                path = "debug",
                name = "Debug Mode",
                desc = "Enable debug logging to the chat frame and Dev Tools addon (if installed).",
                order = 11,
            },
            perfHeader = { type = "header", name = "Performance", order = 20 },
            updateFrequency = {
                type = "range",
                path = "updateFrequency",
                name = "Update Frequency",
                desc = "How often (in seconds) to refresh bar displays. Lower values are smoother but use more CPU.",
                min = 0.04, max = 0.5, step = 0.04,  -- TODO: this step doesn't work correctly with the slider widget.
                order = 21,
            },
        },
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "Advanced Options", AdvancedOptions)
