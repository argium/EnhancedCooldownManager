-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ECM.Constants

local RuneBarOptions = {}

local function isNotDeathKnight()
    return not ECM.SettingsBuilder.IsPlayerClass(C.CLASS.DEATHKNIGHT)
end

function RuneBarOptions.RegisterSettings(SB)
    SB.CreateSubcategory("Rune Bar")

    SB.Header("Rune Bar")

    SB.ModuleEnabledCheckbox("RuneBar", {
        path = "runeBar.enabled",
        name = "Enable rune bar",
        hidden = isNotDeathKnight,
    })

    SB.HeightOverrideSlider("runeBar", { hidden = isNotDeathKnight })

    SB.Header("Font Override")
    SB.FontOverrideGroup("runeBar", { hidden = isNotDeathKnight })

    SB.Header("Positioning")
    SB.PositioningGroup("runeBar", { hidden = isNotDeathKnight })

    -- Colors
    SB.Header("Colors")

    local specInit, specSetting = SB.PathControl({
        type = "checkbox",
        path = "runeBar.useSpecColor",
        name = "Use specialization color",
        tooltip = "Use your current specialization's color for the rune bar. If disabled, you can set a custom color below.",
        hidden = isNotDeathKnight,
    })

    SB.PathControl({
        type = "color",
        path = "runeBar.color",
        name = "Rune color",
        hidden = isNotDeathKnight,
        parent = specInit,
        parentCheck = function() return not specSetting:GetValue() end,
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "RuneBar", RuneBarOptions)
