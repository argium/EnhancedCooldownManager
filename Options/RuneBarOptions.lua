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

    -- Show a message for non-DK players and disable all controls
    if isNotDeathKnight() then
        SB.Header("|cffFF8800These settings are only applicable to Death Knights.|r")
    end

    SB.ModuleEnabledCheckbox("RuneBar", {
        path = "runeBar.enabled",
        name = "Enable rune bar",
        disabled = isNotDeathKnight,
    })

    SB.Header("Appearance")

    SB.HeightOverrideSlider("runeBar", { disabled = isNotDeathKnight })
    SB.FontOverrideGroup("runeBar", { disabled = isNotDeathKnight })

    SB.Header("Positioning")
    SB.PositioningGroup("runeBar", { disabled = isNotDeathKnight })

    SB.Header("Colors")

    local specInit, specSetting = SB.PathControl({
        type = "checkbox",
        path = "runeBar.useSpecColor",
        name = "Use specialization color",
        tooltip = "Use your current specialization's color for the rune bar. If disabled, you can set a custom color below.",
        disabled = isNotDeathKnight,
    })

    SB.PathControl({
        type = "color",
        path = "runeBar.color",
        name = "Rune color",
        disabled = isNotDeathKnight,
        parent = specInit,
        parentCheck = function() return not specSetting:GetValue() end,
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "RuneBar", RuneBarOptions)
