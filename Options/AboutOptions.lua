-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon

local AboutOptions = {}

function AboutOptions.RegisterSettings(SB)
    SB.UseRootCategory()

    SB.Header("Troubleshooting")

    SB.PathControl({
        type = "checkbox",
        path = "global.debug",
        name = "Debug Mode",
        tooltip = "Enable debug logging to the chat frame.",
    })

    SB.Header("Performance")

    SB.PathControl({
        type = "slider",
        path = "global.updateFrequency",
        name = "Update Frequency",
        tooltip = "How often (in seconds) to refresh bar displays. Lower values are smoother but use more CPU.",
        min = 0.04,
        max = 0.5,
        step = 0.04,
    })

    SB.Header("Reset Settings")

    SB.Button({
        name = "Reset Everything to Default",
        buttonText = "Reset",
        tooltip = "Reset the current profile to default values and reload the UI. This cannot be undone.",
        confirm = "This will reset ALL settings to their defaults and reload the UI. This cannot be undone. Are you sure?",
        onClick = function()
            mod.db:ResetProfile()
            ReloadUI()
        end,
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "About", AboutOptions)
