-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local C = ECM.Constants
local unlabeledBarsPresent = false

local function IsEditLocked()
    local locked, _ = ECM.BuffBars:IsEditLocked()
    return locked
end

local function EditLockedReason()
    local _, reason = ECM.BuffBars:IsEditLocked()
    return reason
end

--- Generates dynamic AceConfig args for per-spell color pickers.
--- Merges spells from persisted custom colors (SpellColors) and the
--- currently-visible aura bars (BuffBars) so that both customized and
--- newly-seen spells appear in the options panel.  Deduplication follows
--- the PriorityKeyMap convention: spell name is preferred, then spellID,
--- cooldownID, and finally texture file ID.
---@param activeBars ECM_SpellColorKey[]|nil
---@param savedEntries { key: ECM_SpellColorKey }[]|nil
---@return { key: ECM_SpellColorKey, textureFileID: number|nil }[]
local function BuildSpellColorRows(activeBars, savedEntries)
    ---@type { key: ECM_SpellColorKey, textureFileID: number|nil }[]
    local rows = {}

    ---@param key ECM_SpellColorKey|nil
    local function AddDiscoveredKey(key)
        local normalized = ECM.SpellColors.NormalizeKey(key)
        if not normalized then
            return
        end

        for _, row in ipairs(rows) do
            if row.key:Matches(normalized) then
                row.key = row.key:Merge(normalized) or row.key
                row.textureFileID = row.key.textureFileID or row.textureFileID
                return
            end
        end

        rows[#rows + 1] = {
            key = normalized,
            textureFileID = normalized.textureFileID,
        }
    end

    if type(activeBars) == "table" then
        for _, key in ipairs(activeBars) do
            AddDiscoveredKey(key)
        end
    end

    if type(savedEntries) == "table" then
        for _, entry in ipairs(savedEntries) do
            AddDiscoveredKey(type(entry) == "table" and entry.key or nil)
        end
    end

    return rows
end

---@param rows { key: ECM_SpellColorKey, textureFileID: number|nil }[]
---@return table args AceConfig args table with color pickers and reset buttons
local function BuildSpellColorArgsFromRows(rows)
    local args = {}

    if #rows == 0 then
        args.noData = {
            type = "description",
            name = "|cffaaaaaa(No aura bars found. Cast a buff and click 'Refresh Spell List'.)|r",
            order = 1,
        }
        return args
    end

    unlabeledBarsPresent = false
    for i, row in ipairs(rows) do
        local optKey = "spellColor" .. i
        local resetKey = "spellColor" .. i .. "Reset"
        local rowKey = row.key
        local colorKey = rowKey.primaryKey
        local texture = row.textureFileID
        local label = type(colorKey) == "string" and colorKey or ("Bar |cff555555(" .. colorKey .. ")|r")
        local displayName = texture and ("|T" .. texture .. ":14:14|t " .. label) or label

        -- If there are any entries without valid names, display a warning message to the user.
        unlabeledBarsPresent = unlabeledBarsPresent
            or (type(colorKey) == "string" and (issecretvalue(colorKey) or colorKey == ""))

        args[optKey] = {
            type = "color",
            name = displayName,
            desc = "Color for " .. displayName,
            order = i * 10,
            width = "double",
            get = function()
                local c = ECM.SpellColors.GetColorByKey(rowKey)
                if c then return c.r, c.g, c.b end
                local dc = ECM.SpellColors.GetDefaultColor()
                return dc.r, dc.g, dc.b
            end,
            set = function(_, r, g, b)
                ECM.SpellColors.SetColorByKey(rowKey, { r = r, g = g, b = b, a = 1 })
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
                return ECM.SpellColors.GetColorByKey(rowKey) == nil
            end,
            func = function()
                ECM.SpellColors.ResetColorByKey(rowKey)
                ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
            end,
        }
    end

    return args
end

---@return table args AceConfig args table with color pickers and reset buttons
local function GenerateSpellColorArgs()
    -- Active rows come first in viewer order, then persisted-only rows.
    local rows = BuildSpellColorRows(
        ECM.BuffBars:GetActiveSpellData(),
        ECM.SpellColors.GetAllColorEntries()
    )
    return BuildSpellColorArgsFromRows(rows)
end

local function SpellOptionsTable()
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
                    local _, _, localisedClassName, specName, className = ECM.OptionUtil.GetCurrentClassSpec()
                    local color = C.CLASS_COLORS[className] or C.COLOR_WHITE_HEX
                    return "|cff" .. color .. (localisedClassName or "Unknown") .. "|r " .. (specName or "Unknown")
                end,
                order = 3,
            },
            spacer1 = {
                type = "description",
                name = " ",
                order = 4,
            },
            combatlockdown = {
                type = "description",
                name = "|cffFF0038These settings cannot be changed while in combat lockdown. Leave combat and open the options panel again to make changes.|r\n\n",
                order = 5,
                hidden = function() return not IsEditLocked() or EditLockedReason() ~= "combat" end,
            },
            secretsWarning = {
                type = "description",
                name = "|cffFFDD3CThese settings cannot be changed while spell names or textures are secret. This may persist until you leave an instance or reload your UI out of combat.|r\n\n",
                order = 6,
                hidden = function() return not IsEditLocked() or EditLockedReason() ~= "secrets" end,
            },
            unlabeledBarsWarning = {
                type = "description",
                name = "|cffFFDD3CSome spell names were secret and are displayed as a generic \"Bar\". This may persist until you reload your UI, or they can be safely deleted.|r\n\n",
                order = 7,
                hidden = function() return not unlabeledBarsPresent end
            },
            defaultColor = {
                type = "color",
                name = "Default color",
                desc = "Default color for spells without a custom color.",
                order = 10,
                width = "double",
                disabled =  IsEditLocked,
                get = function()
                    local c = ECM.SpellColors.GetDefaultColor()
                    return c.r, c.g, c.b
                end,
                set = function(_, r, g, b)
                    ECM.SpellColors.SetDefaultColor({ r = r, g = g, b = b, a = 1 })
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
                disabled =  IsEditLocked,
                func = ECM.OptionUtil.MakeResetHandler("buffBars.colors.defaultColor"),
            },
            spellColorsGroup = {
                type = "group",
                name = "",
                order = 20,
                inline = true,
                disabled =  IsEditLocked,
                args = GenerateSpellColorArgs(),
            },
            refreshSpellList = {
                type = "execute",
                name = "Refresh Spell List",
                desc = "Scan current buffs to refresh discovered spell names.",
                order = 100,
                width = "normal",
                disabled =  IsEditLocked,
                func = function()
                    local activeKeys = ECM.BuffBars:GetActiveSpellData()
                    ECM.SpellColors.ReconcileAllKeys(activeKeys)
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
BuffBarsOptions._BuildSpellColorRows = BuildSpellColorRows
BuffBarsOptions._BuildSpellColorArgsFromRows = BuildSpellColorArgsFromRows

function BuffBarsOptions.GetOptionsTable()
    local db = ns.Addon.db

    local spells = SpellOptionsTable()
    spells.name = ""
    spells.inline = true
    spells.order = 5

    local positioningSettings = ECM.OptionUtil.MakePositioningGroup("buffBars", 2, {
        modeDesc = "Choose how the aura bars are positioned. Automatic keeps them attached to the Cooldown Manager. Custom lets you position them anywhere on the screen and configure their size.",
        includeOffsets = false,
        widthLabel = "Buff Bar Width",
        widthDesc = "\nWidth of the buff bars when automatic positioning is disabled.",
    })

    positioningSettings.args.freeGrowDirectionDesc = {
        type = "description",
        name = "\nChoose whether aura bars stack downward or upward in free positioning mode.",
        order = 6,
        hidden = function()
            return (db.profile.buffBars.anchorMode or C.ANCHORMODE_CHAIN) ~= C.ANCHORMODE_FREE
        end,
    }
    positioningSettings.args.freeGrowDirection = {
        type = "select",
        name = "Free Grow Direction",
        order = 7,
        width = "double",
        values = {
            [C.GROW_DIRECTION_DOWN] = "Down",
            [C.GROW_DIRECTION_UP] = "Up",
        },
        hidden = function()
            return (db.profile.buffBars.anchorMode or C.ANCHORMODE_CHAIN) ~= C.ANCHORMODE_FREE
        end,
        get = function()
            return db.profile.buffBars.freeGrowDirection or C.GROW_DIRECTION_DOWN
        end,
        set = function(_, val)
            db.profile.buffBars.freeGrowDirection = val
            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
        end,
    }
    positioningSettings.args.freeGrowDirectionReset = {
        type = "execute",
        name = "X",
        order = 8,
        width = 0.3,
        hidden = function()
            return (db.profile.buffBars.anchorMode or C.ANCHORMODE_CHAIN) ~= C.ANCHORMODE_FREE
                or not ECM.OptionUtil.IsValueChanged("buffBars.freeGrowDirection")
        end,
        func = ECM.OptionUtil.MakeResetHandler("buffBars.freeGrowDirection"),
    }

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
                                mod:ConfirmReloadUI(
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
                    verticalSpacingDesc = {
                        type = "description",
                        name = "\nVertical gap between aura bars. Set to 0 for no spacing.",
                        order = 11,
                    },
                    verticalSpacing = {
                        type = "range",
                        name = "Vertical Spacing",
                        order = 12,
                        width = "double",
                        min = 0,
                        max = 20,
                        step = 1,
                        get = function() return db.profile.buffBars.verticalSpacing or 0 end,
                        set = function(_, val)
                            db.profile.buffBars.verticalSpacing = val
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    verticalSpacingReset = {
                        type = "execute",
                        name = "X",
                        order = 13,
                        width = 0.3,
                        hidden = function() return not ECM.OptionUtil.IsValueChanged("buffBars.verticalSpacing") end,
                        func = ECM.OptionUtil.MakeResetHandler("buffBars.verticalSpacing"),
                    },
                },
            },
            positioningSettings = positioningSettings,
            spells = spells,
        },
    }
end
