-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ECM.Constants

local RuneBarOptions = {}

local function isNotDeathKnight()
    local _, classToken = UnitClass("player")
    return classToken ~= C.CLASS.DEATHKNIGHT
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

    SB.Header("Layout")
    SB.PositioningGroup("runeBar", { disabled = isNotDeathKnight })

    SB.Header("Appearance")
    SB.HeightOverrideSlider("runeBar", { disabled = isNotDeathKnight })
    SB.FontOverrideGroup("runeBar", { disabled = isNotDeathKnight })

    local colorLabel = SB.Label({ name = "Colors", disabled = isNotDeathKnight })
    local specInit, specSetting = SB.PathControl({
        type = "checkbox",
        path = "runeBar.useSpecColor",
        name = "Use specialization color",
        tooltip = "Use your current specialization's color for the rune bar. If disabled, you can set a custom color below.",
        disabled = isNotDeathKnight,
        parent = colorLabel,
    })
    SB.PathControl({
        type = "color",
        path = "runeBar.color",
        name = "Rune color",
        disabled = isNotDeathKnight,
        parent = specInit,
        parentCheck = function() return not specSetting:GetValue() end,
    })
    SB.PathControl({
        type = "color",
        path = "runeBar.colorBlood",
        name = "Blood color",
        disabled = isNotDeathKnight,
        parent = specInit,
        parentCheck = function() return specSetting:GetValue() end,
    })
    SB.PathControl({
        type = "color",
        path = "runeBar.colorFrost",
        name = "Frost color",
        disabled = isNotDeathKnight,
        parent = specInit,
        parentCheck = function() return specSetting:GetValue() end,
    })
    SB.PathControl({
        type = "color",
        path = "runeBar.colorUnholy",
        name = "Unholy color",
        disabled = isNotDeathKnight,
        parent = specInit,
        parentCheck = function() return specSetting:GetValue() end,
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "RuneBar", RuneBarOptions)
