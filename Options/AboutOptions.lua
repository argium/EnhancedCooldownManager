-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon

local AboutOptions = {}

function AboutOptions.RegisterSettings(SB)
    SB.RegisterFromTable({
        name = "About",
        path = "global",
        args = {
            troubleshootHeader = { type = "header", name = "Troubleshooting", order = 10 },
            debug = {
                type = "toggle",
                path = "debug",
                name = "Debug Mode",
                desc = "Enable debug logging to the chat frame.",
                order = 11,
            },
            perfHeader = { type = "header", name = "Performance", order = 20 },
            updateFrequency = {
                type = "range",
                path = "updateFrequency",
                name = "Update Frequency",
                desc = "How often (in seconds) to refresh bar displays. Lower values are smoother but use more CPU.",
                min = 0.04, max = 0.5, step = 0.04,
                order = 21,
            },
            resetHeader = { type = "header", name = "Reset Settings", order = 30 },
            reset = {
                type = "execute",
                name = "Reset Everything to Default",
                buttonText = "Reset",
                desc = "Reset the current profile to default values and reload the UI. This cannot be undone.",
                confirm = "This will reset ALL settings to their defaults and reload the UI. This cannot be undone. Are you sure?",
                onClick = function()
                    mod.db:ResetProfile()
                    ReloadUI()
                end,
                order = 31,
            },
        },
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "About", AboutOptions)
