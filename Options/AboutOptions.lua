-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local C = ECM.Constants
local OB = ECM.OptionBuilder

local AboutOptions = {}

function AboutOptions.GetOptionsTable()
    local db = mod.db
    local authorColored = "|cffa855f7S|r|cff7a84f7o|r|cff6b9bf7l|r|cff4cc9f0ä|r|cff22c55er|r"
    local version = C_AddOns.GetAddOnMetadata("EnhancedCooldownManager", "Version") or "unknown"

    local troubleshootingArgs = {
        debugDesc = OB.MakeDescription({
            name = "Enable debug mode. This will generate more detailed logs in the chat window.",
            order = 1,
        }),
        debug = OB.MakePathToggle({
            path = "debug",
            name = "Debug mode",
            order = 2,
            width = "full",
            layout = false,
        }),
    }

    local performanceArgs = {
        updateFrequencyDesc = OB.MakeDescription({
            name = "How often bars update (seconds). Lower values makes the bars smoother but use more CPU.",
            order = 1,
        }),
    }
    OB.MergeArgs(performanceArgs, OB.BuildPathRangeWithReset("updateFrequency", {
        path = "global.updateFrequency",
        name = "Update Frequency",
        order = 2,
        width = "double",
        min = 0.04,
        max = 0.5,
        step = 0.04,
        layout = false,
        resetOrder = 3,
    }))

    local resetArgs = {
        resetDesc = OB.MakeDescription({
            name = "Reset all settings to their default values and reload the UI. This action cannot be undone.",
            order = 1,
        }),
        resetAll = OB.MakeActionButton({
            name = "Reset Everything to Default",
            order = 2,
            width = "full",
            confirm = true,
            confirmText = "This will reset ALL settings to their defaults and reload the UI. This cannot be undone. Are you sure?",
            func = function()
                db:ResetProfile()
                ReloadUI()
            end,
        }),
    }

    return OB.MakeGroup({
        name = "About",
        order = 8,
        args = {
            author = OB.MakeDescription({
                name = "An addon by " .. authorColored,
                order = 1,
                fontSize = "medium",
            }),
            version = OB.MakeDescription({
                name = "\nVersion: |cff67dbf8" .. version .. "|r",
                order = 2,
                fontSize = "medium",
            }),
            spacer1 = OB.MakeSpacer(2.5),
            troubleshooting = OB.MakeInlineGroup("Troubleshooting", 3, troubleshootingArgs),
            performanceSettings = OB.MakeInlineGroup("Performance", 4, performanceArgs),
            reset = OB.MakeInlineGroup("Reset Settings", 5, resetArgs),
        },
    })
end

OB.RegisterSection(ns, "About", AboutOptions)
