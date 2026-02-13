-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")

local function ResetStyledMarkers()
    local buffBars = ECM.BuffBars
    if buffBars then
        buffBars:ResetStyledMarkers()
    end
end

--- Generates dynamic AceConfig args for per-spell color pickers.
--- Merges spells from persisted custom colors (SpellColors) and the
--- currently-visible aura bars (BuffBars) so that both customized and
--- newly-seen spells appear in the options panel.  Deduplication follows
--- the FallbackKeyMap convention: spell name is preferred over texture
--- file ID.
---@return table args AceConfig args table with color pickers and reset buttons
local function GenerateSpellColorArgs()
    local args = {}

    -- Build an ordered, deduplicated list of spell keys.
    -- Active bars come first (in viewer top-to-bottom order), then any
    -- persisted-only colours that aren't currently visible.
    local seen = {}
    local ordered = {}

    -- 1) Currently-visible aura bars — prefer spellName, fall back to
    --    textureFileID (consistent with FallbackKeyMap's primary/fallback).
    local activeBars = ECM.BuffBars:GetActiveSpellData()
    for _, bar in ipairs(activeBars) do
        local key = bar.spellName or bar.textureFileID
        if key and not seen[key] then
            seen[key] = true
            ordered[#ordered + 1] = key
        end
    end

    -- 2) Persisted custom colors — appended so users can manage colours
    --    for spells that aren't currently active.
    local savedColors = ECM.SpellColors.GetAllColors()
    for colorKey in pairs(savedColors) do
        if not seen[colorKey] then
            seen[colorKey] = true
            ordered[#ordered + 1] = colorKey
        end
    end

    if #ordered == 0 then
        args.noData = {
            type = "description",
            name = "|cffaaaaaa(No aura bars found. Cast a buff and click 'Refresh Spell List'.)|r",
            order = 1,
        }
        return args
    end

    for i, colorKey in ipairs(ordered) do
        local optKey = "spellColor" .. i
        local resetKey = "spellColor" .. i .. "Reset"
        local displayName = type(colorKey) == "string" and colorKey or ("|T" .. colorKey .. ":14:14|t Bar (" .. colorKey .. ")")
        local spellName = type(colorKey) == "string" and colorKey or nil
        local textureId = type(colorKey) == "number" and colorKey or nil

        args[optKey] = {
            type = "color",
            name = displayName,
            desc = "Color for " .. displayName,
            order = i * 10,
            width = "double",
            get = function()
                local c = ECM.SpellColors.GetColor(spellName, textureId)
                if c then return c.r, c.g, c.b end
                return ECM.SpellColors.GetDefaultColor()
            end,
            set = function(_, r, g, b)
                ECM.SpellColors.SetColor(spellName, textureId, { r = r, g = g, b = b, a = 1 })
                ResetStyledMarkers()
                ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
            end,
        }

        args[resetKey] = {
            type = "execute",
            name = "X",
            desc = "Reset to default",
            order = i * 10 + 1,
            width = 0.3,
            hidden = function()
                return ECM.SpellColors.GetColor(spellName, textureId) == nil
            end,
            func = function()
                ECM.SpellColors.ResetColor(spellName, textureId)
                ResetStyledMarkers()
                ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
            end,
        }

    end

    return args
end

local function SpellOptionsTable()
    local db = ns.Addon.db
    local result = {
        type = "group",
        name = "Spells",
        order = 3,
        args = {
            header = {
                type = "header",
                name = "Per-spell Colors",
                order = 1,
            },
            desc = {
                type = "description",
                name = "Customize colors for individual spells. Colors are saved per class and spec. Use 'Refresh Spell List' to rescan active aura bars.\n\n",
                order = 2,
                fontSize = "medium",
            },
            currentSpec = {
                type = "description",
                name = function()
                    local _, _, className, specName = ECM.OptionUtil.GetCurrentClassSpec()
                    return "|cff00ff00Current: " .. (className or "Unknown") .. " " .. specName .. "|r"
                end,
                order = 3,
            },
            spacer1 = {
                type = "description",
                name = " ",
                order = 4,
            },
            defaultColor = {
                type = "color",
                name = "Default color",
                desc = "Default color for spells without a custom color.",
                order = 10,
                width = "double",
                get = function()
                    return ECM.SpellColors.GetDefaultColor()
                end,
                set = function(_, r, g, b)
                    ECM.SpellColors.SetDefaultColor(r, g, b)
                    ResetStyledMarkers()
                    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                end,
            },
            defaultColorReset = {
                type = "execute",
                name = "X",
                desc = "Reset to default",
                order = 11,
                width = 0.3,
                hidden = function() return not ECM.OptionUtil.IsValueChanged("buffBars.colors.defaultColor") end,
                func = ECM.OptionUtil.MakeResetHandler("buffBars.colors.defaultColor"),
            },
            spellColorsGroup = {
                type = "group",
                name = "",
                order = 20,
                inline = true,
                args = GenerateSpellColorArgs(),
            },
            refreshSpellList = {
                type = "execute",
                name = "Refresh Spell List",
                desc = "Scan current buffs to refresh discovered spell names.",
                order = 100,
                width = "normal",
                func = function()
                    AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
                end,
            },
        },
    }

    return result
end

--------------------------------------------------------------------------------
-- Options Table
--------------------------------------------------------------------------------

local BuffBarsOptions = {}
ns.BuffBarsOptions = BuffBarsOptions

function BuffBarsOptions.GetOptionsTable()
    local db = ns.Addon.db

    local spells = SpellOptionsTable()
    spells.name = ""
    spells.inline = true
    spells.order = 5

    return {
        type = "group",
        name = "Aura Bars",
        order = 5,
        args = {
            displaySettings = {
                type = "group",
                name = "Basic Settings",
                inline = true,
                order = 1,
                args = {
                    desc = {
                        type = "description",
                        name = "Styles and repositions Blizzard's aura duration bars that are part of the Cooldown Manager.",
                        order = 1,
                        fontSize = "medium",
                    },
                    enabled = {
                        type = "toggle",
                        name = "Enable aura bars",
                        order = 2,
                        width = "full",
                        get = function() return db.profile.buffBars.enabled end,
                        set = function(_, val)
                            db.profile.buffBars.enabled = val
                            if val then
                                ECM.OptionUtil.SetModuleEnabled("BuffBars", true)
                                ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                            else
                                ECM:ConfirmReloadUI(
                                    "Disabling aura bars requires a UI reload. Reload now?",
                                    nil,
                                    function() db.profile.buffBars.enabled = true end
                                )
                            end
                        end,
                    },
                    showIcon = {
                        type = "toggle",
                        name = "Show icon",
                        order = 3,
                        width = "full",
                        get = function() return db.profile.buffBars.showIcon end,
                        set = function(_, val)
                            db.profile.buffBars.showIcon = val
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    showSpellName = {
                        type = "toggle",
                        name = "Show spell name",
                        order = 5,
                        width = "full",
                        get = function() return db.profile.buffBars.showSpellName end,
                        set = function(_, val)
                            db.profile.buffBars.showSpellName = val
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    showDuration = {
                        type = "toggle",
                        name = "Show remaining duration",
                        order = 7,
                        width = "full",
                        get = function() return db.profile.buffBars.showDuration end,
                        set = function(_, val)
                            db.profile.buffBars.showDuration = val
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    heightDesc = {
                        type = "description",
                        name = "\nOverride the default bar height. Set to 0 to use the global default.",
                        order = 8,
                    },
                    height = {
                        type = "range",
                        name = "Height Override",
                        order = 9,
                        width = "double",
                        min = 0,
                        max = 40,
                        step = 1,
                        get = function() return db.profile.buffBars.height or 0 end,
                        set = function(_, val)
                            db.profile.buffBars.height = val > 0 and val or nil
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    heightReset = {
                        type = "execute",
                        name = "X",
                        order = 10,
                        width = 0.3,
                        hidden = function() return not ECM.OptionUtil.IsValueChanged("buffBars.height") end,
                        func = ECM.OptionUtil.MakeResetHandler("buffBars.height"),
                    },
                },
            },
            positioningSettings = ECM.OptionUtil.MakePositioningGroup("buffBars", 2, {
                modeDesc = "Choose how the aura bars are positioned. Automatic keeps them attached to the Cooldown Manager. Custom lets you position them anywhere on the screen and configure their size.",
                includeOffsets = false,
                widthLabel = "Buff Bar Width",
                widthDesc = "\nWidth of the buff bars when automatic positioning is disabled.",
            }),
            spells = spells,
        },
    }
end
