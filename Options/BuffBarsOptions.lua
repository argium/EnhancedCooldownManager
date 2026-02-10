-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

local ECM = ns.Addon
local BuffBarColors = ns.BuffBarColors
local OH = ECM.OptionHelpers

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function ResetStyledMarkers()
    local buffBars = ECM.BuffBars
    if buffBars then
        buffBars:ResetStyledMarkers()
    end
end

--------------------------------------------------------------------------------
-- Spell Options
--------------------------------------------------------------------------------

--- Generates dynamic AceConfig args for per-spell color pickers.
--- Merges spells from perSpell settings (persisted custom colors) and the bar
--- metadata cache (recently discovered bars) so that both customized and
--- newly-seen spells appear in the options panel.
---@return table args AceConfig args table with color pickers and reset buttons
local function GenerateSpellColorArgs()
    local args = {}

    local cachedBars = BuffBarColors.GetBarCache()
    local cachedTextures = BuffBarColors.GetBarTextureMap()
    if not cachedBars or not next(cachedBars) then
        args.noData = {
            type = "description",
            name = "|cffaaaaaa(No buff bars cached yet. Cast a buff and click 'Refresh Spell List'.)|r",
            order = 1,
        }
        return args
    end

    local spellSettings = BuffBarColors.GetPerSpellColors()

    if spellSettings then

        local spells = {}

        for spellName, v in pairs(spellSettings) do
            spells[spellName] = {}
        end

        local cacheIndices = {}
        for index in pairs(cachedBars) do
            cacheIndices[#cacheIndices + 1] = index
        end
        table.sort(cacheIndices)

        -- Use the spell name if available; fall back to the icon texture file ID
        -- (from the separate textureMap) as a stable identifier for bars whose names
        -- are secret. Bars with neither are skipped entirely.
        for _, index in ipairs(cacheIndices) do
            local c = cachedBars[index]
            if c then
                local key = c.spellName or cachedTextures[index]
                if key then
                    spells[key] = {}
                end
            end
        end

        local i = 1
        for colorKey, v in pairs(spells) do
            local optKey = "spellColor" .. i
            local resetKey = "spellColor" .. i .. "Reset"
            local displayName = type(colorKey) == "string" and colorKey or "Bar"

            args[optKey] = {
                type = "color",
                name = displayName,
                desc = "Color for " .. displayName,
                order = i * 10,
                width = "double",
                get = function()
                    return BuffBarColors.GetSpellColor(colorKey)
                end,
                set = function(_, r, g, b)
                    BuffBarColors.SetSpellColor(colorKey, r, g, b)
                    ResetStyledMarkers()
                    ECM.ScheduleLayoutUpdate(0)
                end,
            }

            args[resetKey] = {
                type = "execute",
                name = "X",
                desc = "Reset to default",
                order = i * 10 + 1,
                width = 0.3,
                hidden = function()
                    return not BuffBarColors.HasCustomSpellColor(colorKey)
                end,
                func = function()
                    BuffBarColors.ResetSpellColor(colorKey)
                    ResetStyledMarkers()
                    ECM.ScheduleLayoutUpdate(0)
                end,
            }

            i = i + 1
        end
    end

    return args
end

local function SpellOptionsTable()
    local db = ECM.db
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
                    local _, _, className, specName = OH.GetCurrentClassSpec()
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
                    return BuffBarColors.GetDefaultColor()
                end,
                set = function(_, r, g, b)
                    BuffBarColors.SetDefaultColor(r, g, b)
                    ResetStyledMarkers()
                    ECM.ScheduleLayoutUpdate(0)
                end,
            },
            defaultColorReset = {
                type = "execute",
                name = "X",
                desc = "Reset to default",
                order = 11,
                width = 0.3,
                hidden = function() return not OH.IsValueChanged("buffBars.colors.defaultColor") end,
                func = OH.MakeResetHandler("buffBars.colors.defaultColor"),
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
                    local buffBars = ECM.BuffBars
                    if buffBars then
                        buffBars:RefreshBarCache()
                    end
                    AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
                end,
            },
        },
    }

    -- Inject dynamic bar color args
    if result.args and result.args.spellColorsGroup then
        result.args.spellColorsGroup.args = GenerateSpellColorArgs()
    end

    return result
end

--------------------------------------------------------------------------------
-- Options Table
--------------------------------------------------------------------------------

local BuffBarsOptions = {}
ns.BuffBarsOptions = BuffBarsOptions

function BuffBarsOptions.GetOptionsTable()
    local db = ECM.db

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
                            OH.SetModuleEnabled("BuffBars", val)
                            ECM.ScheduleLayoutUpdate(0)
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
                            ECM.ScheduleLayoutUpdate(0)
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
                            ECM.ScheduleLayoutUpdate(0)
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
                            ECM.ScheduleLayoutUpdate(0)
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
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    heightReset = {
                        type = "execute",
                        name = "X",
                        order = 10,
                        width = 0.3,
                        hidden = function() return not OH.IsValueChanged("buffBars.height") end,
                        func = OH.MakeResetHandler("buffBars.height"),
                    },
                },
            },
            positioningSettings = (function()
                local positioningArgs = {
                    modeDesc = {
                        type = "description",
                        name = "Choose how the aura bars are positioned. Automatic keeps them attached to the Cooldown Manager. Custom lets you position them anywhere on the screen and configure their size.",
                        order = 1,
                        fontSize = "medium",
                    },
                    modeSelector = {
                        type = "select",
                        name = "",
                        order = 3,
                        width = "full",
                        dialogControl = "ECM_PositionModeSelector",
                        values = OH.POSITION_MODE_TEXT,
                        get = function() return db.profile.buffBars.anchorMode end,
                        set = function(_, val)
                            OH.ApplyPositionModeToBar(db.profile.buffBars, val)
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    spacer1 = {
                        type = "description",
                        name = " ",
                        order = 2.5,
                    },
                }

                -- Add width setting only (no offsets for BuffBars)
                local positioningSettings = OH.MakePositioningSettingsArgs("buffBars", {
                    includeOffsets = false,
                    widthLabel = "Buff Bar Width",
                    widthDesc = "\nWidth of the buff bars when automatic positioning is disabled.",
                })
                for k, v in pairs(positioningSettings) do
                    positioningArgs[k] = v
                end

                return {
                    type = "group",
                    name = "Positioning",
                    inline = true,
                    order = 2,
                    args = positioningArgs,
                }
            end)(),
            spells = spells,
        },
    }
end
