-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local Options = mod:NewModule("Options")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")
local LSM = LibStub("LibSharedMedia-3.0", true)

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Generates LibSharedMedia dropdown values
--- @param mediaType string The type of media to retrieve (e.g., "statusbar", "font")
--- @param fallback string The fallback value to use if no media of the specified type is found
--- @return table A table of media names keyed by name, suitable for use as values in an AceConfig select option
local function GetLSMValues(mediaType, fallback)
    local values = {}
    if LSM and LSM.List then
        for _, name in ipairs(LSM:List(mediaType)) do
            values[name] = name
        end
    end
    if not next(values) then
        values[fallback] = fallback
    end
    return values
end

local function GetLSMStatusbarValues()
    return GetLSMValues("statusbar", "Blizzard")
end

local function IsDeathKnight()
    local _, className = UnitClass("player")
    return className == "DEATHKNIGHT"
end

local function GeneralOptionsTable()
    local db = mod.db
    return {
        type = "group",
        name = "General",
        order = 1,
        args = {
            basicSettings = {
                type = "group",
                name = "Basic Settings",
                inline = true,
                order = 1,
                args = {
                    hideWhenMountedDesc = {
                        type = "description",
                        name = "Automatically hide icons and bars when mounted or in a vehicle, and show them when dismounted or out of vehicle.",
                        order = 3,
                    },
                    hideWhenMounted = {
                        type = "toggle",
                        name = "Hide when mounted or in vehicle",
                        order = 4,
                        width = "full",
                        get = function() return db.profile.global.hideWhenMounted end,
                        set = function(_, val)
                            db.profile.global.hideWhenMounted = val
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    hideOutOfCombatInRestAreas = {
                        type = "toggle",
                        name = "Always hide when out of combat in rest areas",
                        order = 6,
                        width = "full",
                        get = function() return db.profile.global.hideOutOfCombatInRestAreas end,
                        set = function(_, val)
                            db.profile.global.hideOutOfCombatInRestAreas = val
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    texture = {
                        type = "select",
                        name = "Bar Texture",
                        order = 8,
                        width = "double",
                        values = GetLSMStatusbarValues,
                        get = function() return db.profile.global.texture end,
                        set = function(_, val)
                            db.profile.global.texture = val
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    textureReset = {
                        type = "execute",
                        name = "X",
                        order = 9,
                        width = 0.3,
                        hidden = function() return not ECM.OptionUtil.IsValueChanged("global.texture") end,
                        func = ECM.OptionUtil.MakeResetHandler("global.texture"),
                    },
                },
            },
            layoutSettings = {
                type = "group",
                name = "Layout",
                inline = true,
                order = 2,
                args = {
                    offsetYDesc = {
                        type = "description",
                        name = "Vertical gap between the main icons and the first bar.",
                        order = 1,
                    },
                    offsetY = {
                        type = "range",
                        name = "Vertical Offset",
                        order = 2,
                        width = "double",
                        min = 0,
                        max = 20,
                        step = 1,
                        get = function() return db.profile.global.offsetY end,
                        set = function(_, val)
                            db.profile.global.offsetY = val
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    offsetYReset = {
                        type = "execute",
                        name = "X",
                        order = 3,
                        width = 0.3,
                        hidden = function() return not ECM.OptionUtil.IsValueChanged("global.offsetY") end,
                        func = ECM.OptionUtil.MakeResetHandler("global.offsetY"),
                    },
                },
            },
            combatFadeSettings = {
                type = "group",
                name = "Combat Fade",
                inline = true,
                order = 4,
                args = {
                    combatFadeEnabledDesc = {
                        type = "description",
                        name = "Automatically fade bars when out of combat to reduce screen clutter.",
                        order = 1,
                        fontSize = "medium",
                    },
                    combatFadeEnabled = {
                        type = "toggle",
                        name = "Fade when out of combat",
                        order = 2,
                        width = "full",
                        get = function() return db.profile.global.outOfCombatFade.enabled end,
                        set = function(_, val)
                            db.profile.global.outOfCombatFade.enabled = val
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    combatFadeOpacityDesc = {
                        type = "description",
                        name = "\nHow visible the bars are when faded (0% = invisible, 100% = fully visible).",
                        order = 3,
                    },
                    combatFadeOpacity = {
                        type = "range",
                        name = "Out of combat opacity",
                        order = 4,
                        width = "double",
                        min = 0,
                        max = 100,
                        step = 5,
                        disabled = function() return not db.profile.global.outOfCombatFade.enabled end,
                        get = function() return db.profile.global.outOfCombatFade.opacity end,
                        set = function(_, val)
                            db.profile.global.outOfCombatFade.opacity = val
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    combatFadeOpacityReset = {
                        type = "execute",
                        name = "X",
                        order = 5,
                        width = 0.3,
                        hidden = function() return not ECM.OptionUtil.IsValueChanged("global.outOfCombatFade.opacity") end,
                        disabled = function() return not db.profile.global.outOfCombatFade.enabled end,
                        func = ECM.OptionUtil.MakeResetHandler("global.outOfCombatFade.opacity"),
                    },
                    spacer2 = {
                        type = "description",
                        name = " ",
                        order = 6,
                    },
                    combatFadeExceptInInstanceDesc = {
                        type = "description",
                        name = "\nWhen enabled, bars will not fade in instanced content.",
                        order = 7,
                    },
                    combatFadeExceptInInstance = {
                        type = "toggle",
                        name = "Except inside instances",
                        order = 8,
                        width = "full",
                        disabled = function() return not db.profile.global.outOfCombatFade.enabled end,
                        get = function() return db.profile.global.outOfCombatFade.exceptInInstance end,
                        set = function(_, val)
                            db.profile.global.outOfCombatFade.exceptInInstance = val
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    exceptIfTargetCanBeAttackedEnabled ={
                        type = "toggle",
                        name = "Except if current target can be attacked",
                        order = 9,
                        width = "full",
                        disabled = function() return not db.profile.global.outOfCombatFade.enabled end,
                        get = function() return db.profile.global.outOfCombatFade.exceptIfTargetCanBeAttacked end,
                        set = function(_, val)
                            db.profile.global.outOfCombatFade.exceptIfTargetCanBeAttacked = val
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                },
            },
        },
    }
end


-- Forward declarations (these are defined later, but referenced by option-table builders)
local TickMarksOptionsTable

local function PowerBarOptionsTable()
    local db = mod.db
    local tickMarks = TickMarksOptionsTable()
    tickMarks.name = "Tick Marks"
    tickMarks.inline = true
    tickMarks.order = 4
    return {
        type = "group",
        name = "Power Bar",
        order = 2,
        args = {
            -- TODO: ShouldShow returns false if the bar is disabled but would be otherwise, meaning the message shown is incorrect.
            --       Add another function that returns true/false based only on class/spec requirements and use that for the message visibility.
            -- notShownNotice = {
            --     type = "description",
            --     name = "|cfff1e02fNote: This bar is currently not being shown due to your current class or specialization.|r\n\n",
            --     order = 0,
            --     fontSize = "medium",
            --     hidden = function() return mod.PowerBar:ShouldShow() end,
            -- },
            basicSettings = {
                type = "group",
                name = "Basic Settings",
                inline = true,
                order = 1,
                args = {
                    enabled = {
                        type = "toggle",
                        name = "Enable power bar",
                        order = 1,
                        width = "full",
                        get = function() return db.profile.powerBar.enabled end,
                        set = function(_, val)
                            db.profile.powerBar.enabled = val
                            ECM.OptionUtil.SetModuleEnabled("PowerBar", val)
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    heightDesc = {
                        type = "description",
                        name = "\nOverride the default bar height. Set to 0 to use the global default.",
                        order = 3,
                    },
                    height = {
                        type = "range",
                        name = "Height Override",
                        order = 4,
                        width = "double",
                        min = 0,
                        max = 40,
                        step = 1,
                        get = function() return db.profile.powerBar.height or 0 end,
                        set = function(_, val)
                            db.profile.powerBar.height = val > 0 and val or nil
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    heightReset = {
                        type = "execute",
                        name = "X",
                        order = 5,
                        width = 0.3,
                        hidden = function() return not ECM.OptionUtil.IsValueChanged("powerBar.height") end,
                        func = ECM.OptionUtil.MakeResetHandler("powerBar.height"),
                    },
                },
            },
            displaySettings = {
                type = "group",
                name = "Display Options",
                inline = true,
                order = 2,
                args = {
                    showTextDesc = {
                        type = "description",
                        name = "Display the current value on the bar.",
                        order = 1,
                    },
                    showText = {
                        type = "toggle",
                        name = "Show text",
                        order = 2,
                        width = "full",
                        get = function() return db.profile.powerBar.showText end,
                        set = function(_, val)
                            db.profile.powerBar.showText = val
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    showManaAsPercentDesc = {
                        type = "description",
                        name = "\nDisplay mana as percentage instead of raw value.",
                        order = 3,
                    },
                    showManaAsPercent = {
                        type = "toggle",
                        name = "Show mana as percent",
                        order = 4,
                        width = "full",
                        get = function() return db.profile.powerBar.showManaAsPercent end,
                        set = function(_, val)
                            db.profile.powerBar.showManaAsPercent = val
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    borderSpacer = {
                        type = "description",
                        name = " ",
                        order = 5,
                    },
                    borderEnabled = {
                        type = "toggle",
                        name = "Show border",
                        order = 7,
                        width = "full",
                        get = function() return db.profile.powerBar.border.enabled end,
                        set = function(_, val)
                            db.profile.powerBar.border.enabled = val
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    borderThickness = {
                        type = "range",
                        name = "Border width",
                        order = 8,
                        width = "small",
                        min = 1,
                        max = 10,
                        step = 1,
                        disabled = function() return not db.profile.powerBar.border.enabled end,
                        get = function() return db.profile.powerBar.border.thickness end,
                        set = function(_, val)
                            db.profile.powerBar.border.thickness = val
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    borderColor = {
                        type = "color",
                        name = "Border color",
                        order = 9,
                        width = "small",
                        hasAlpha = true,
                        disabled = function() return not db.profile.powerBar.border.enabled end,
                        get = function()
                            local c = db.profile.powerBar.border.color
                            return c.r, c.g, c.b, c.a
                        end,
                        set = function(_, r, g, b, a)
                            db.profile.powerBar.border.color = { r = r, g = g, b = b, a = a }
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    borderThicknessReset = {
                        type = "execute",
                        name = "X",
                        order = 8.5,
                        width = 0.3,
                        hidden = function() return not ECM.OptionUtil.IsValueChanged("powerBar.border.thickness") end,
                        disabled = function() return not db.profile.powerBar.border.enabled end,
                        func = ECM.OptionUtil.MakeResetHandler("powerBar.border.thickness"),
                    },
                    borderColorReset = {
                        type = "execute",
                        name = "X",
                        order = 9.5,
                        width = 0.3,
                        hidden = function() return not ECM.OptionUtil.IsValueChanged("powerBar.border.color") end,
                        disabled = function() return not db.profile.powerBar.border.enabled end,
                        func = ECM.OptionUtil.MakeResetHandler("powerBar.border.color"),
                    },
                },
            },
            positioningSettings = ECM.OptionUtil.MakePositioningGroup("powerBar", 3),
            tickMarks = tickMarks,
        },
    }
end

--- Generates the display options args for the resource bar, including
--- border settings and per-resource-type color pickers with reset buttons.
---@param db AceDBObject-3.0
---@return table args AceConfig args table
local function GenerateResourceColorArgs(db)
    local args = {
        borderEnabled = {
            type = "toggle",
            name = "Show border",
            order = 1,
            width = "full",
            get = function() return db.profile.resourceBar.border.enabled end,
            set = function(_, val)
                db.profile.resourceBar.border.enabled = val
                ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
            end,
        },
        borderThickness = {
            type = "range",
            name = "Border width",
            order = 2,
            width = "small",
            min = 1,
            max = 10,
            step = 1,
            disabled = function() return not db.profile.resourceBar.border.enabled end,
            get = function() return db.profile.resourceBar.border.thickness end,
            set = function(_, val)
                db.profile.resourceBar.border.thickness = val
                ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
            end,
        },
        borderThicknessReset = {
            type = "execute",
            name = "X",
            order = 2.5,
            width = 0.3,
            hidden = function() return not ECM.OptionUtil.IsValueChanged("resourceBar.border.thickness") end,
            disabled = function() return not db.profile.resourceBar.border.enabled end,
            func = ECM.OptionUtil.MakeResetHandler("resourceBar.border.thickness"),
        },
        borderColor = {
            type = "color",
            name = "Border color",
            order = 3,
            width = "small",
            hasAlpha = true,
            disabled = function() return not db.profile.resourceBar.border.enabled end,
            get = function()
                local c = db.profile.resourceBar.border.color
                return c.r, c.g, c.b, c.a
            end,
            set = function(_, r, g, b, a)
                db.profile.resourceBar.border.color = { r = r, g = g, b = b, a = a }
                ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
            end,
        },
        borderColorReset = {
            type = "execute",
            name = "X",
            order = 3.5,
            width = 0.3,
            hidden = function() return not ECM.OptionUtil.IsValueChanged("resourceBar.border.color") end,
            disabled = function() return not db.profile.resourceBar.border.enabled end,
            func = ECM.OptionUtil.MakeResetHandler("resourceBar.border.color"),
        },
        colorsSpacer = {
            type = "description",
            name = " ",
            order = 4,
        },
        colorsDescription = {
            type = "description",
            name = "Customize the color of each resource type. Colors only apply to the relevant class/spec.",
            fontSize = "medium",
            order = 5,
        },
    }

    -- Generate color pickers from definitions
    local colorDefs = {
        { key = "souls", name = "Soul Fragments (Demon Hunter)" },
        { key = "devourerNormal", name = "Souls Fragments (Devourer)" },
        { key = "devourerMeta", name = "Void Fragments (Devourer)" },
        { key = Enum.PowerType.ArcaneCharges, name = "Arcane Charges" },
        { key = Enum.PowerType.Chi, name = "Chi" },
        { key = Enum.PowerType.ComboPoints, name = "Combo Points" },
        { key = Enum.PowerType.Essence, name = "Essence" },
        { key = Enum.PowerType.HolyPower, name = "Holy Power" },
        { key = Enum.PowerType.Maelstrom, name = "Maelstrom" },
        { key = Enum.PowerType.SoulShards, name = "Soul Shards" },
    }

    for i, def in ipairs(colorDefs) do
        local key = def.key
        local configPath = "resourceBar.colors." .. tostring(key)
        local orderBase = 10 + (i - 1) * 2

        args["color" .. tostring(key)] = {
            type = "color",
            name = def.name,
            order = orderBase,
            width = "double",
            get = function()
                local c = db.profile.resourceBar.colors[key]
                return c.r, c.g, c.b
            end,
            set = function(_, r, g, b)
                db.profile.resourceBar.colors[key] = { r = r, g = g, b = b, a = 1 }
                ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
            end,
        }
        args["color" .. tostring(key) .. "Reset"] = {
            type = "execute",
            name = "X",
            order = orderBase + 1,
            width = 0.3,
            hidden = function() return not ECM.OptionUtil.IsValueChanged(configPath) end,
            func = ECM.OptionUtil.MakeResetHandler(configPath),
        }
    end

    return args
end

local function ResourceBarOptionsTable()
    local db = mod.db
    return {
        type = "group",
        name = "Resource Bar",
        order = 3,
        disabled = function() return IsDeathKnight() end,
        args = {
            -- TODO: ShouldShow returns false if the bar is disabled but would be otherwise, meaning the message shown is incorrect.
            --       Add another function that returns true/false based only on class/spec requirements and use that for the message visibility.
            -- notShownNotice = {
            --     type = "description",
            --     name = "|cfff1e02fNote: This bar is currently not being shown due to your current class or specialization.|r\n\n",
            --     order = 0,
            --     fontSize = "medium",
            --     hidden = function() return mod.PowerBar:ShouldShow() end,
            -- },
            basicSettings = {
                type = "group",
                name = "Basic Settings",
                inline = true,
                order = 1,
                args = {
                    enabled = {
                        type = "toggle",
                        name = "Enable resource bar",
                        order = 1,
                        width = "full",
                        get = function() return db.profile.resourceBar.enabled end,
                        set = function(_, val)
                            db.profile.resourceBar.enabled = val
                            ECM.OptionUtil.SetModuleEnabled("ResourceBar", val)
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    showTextDesc = {
                        type = "description",
                        name = "Display the current value on the bar.",
                        order = 2,
                    },
                    showText = {
                        type = "toggle",
                        name = "Show text",
                        order = 3,
                        width = "full",
                        get = function() return db.profile.resourceBar.showText end,
                        set = function(_, val)
                            db.profile.resourceBar.showText = val
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    heightDesc = {
                        type = "description",
                        name = "\nOverride the default bar height. Set to 0 to use the global default.",
                        order = 4,
                    },
                    height = {
                        type = "range",
                        name = "Height Override",
                        order = 6,
                        width = "double",
                        min = 0,
                        max = 40,
                        step = 1,
                        get = function() return db.profile.resourceBar.height or 0 end,
                        set = function(_, val)
                            db.profile.resourceBar.height = val > 0 and val or nil
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    heightReset = {
                        type = "execute",
                        name = "X",
                        order = 7,
                        width = 0.3,
                        hidden = function() return not ECM.OptionUtil.IsValueChanged("resourceBar.height") end,
                        func = ECM.OptionUtil.MakeResetHandler("resourceBar.height"),
                    },
                },
            },
            positioningSettings = ECM.OptionUtil.MakePositioningGroup("resourceBar", 2),
            resourceColors = {
                type = "group",
                name = "Display Options",
                inline = true,
                order = 3,
                args = GenerateResourceColorArgs(db),
            },
        },
    }
end

local function RuneBarOptionsTable()
    local db = mod.db
    return {
        type = "group",
        name = "Rune Bar",
        order = 4,
        disabled = function() return not IsDeathKnight() end,
        args = {
            basicSettings = {
                type = "group",
                name = "Basic Settings",
                inline = true,
                order = 1,
                args = {
                    enabled = {
                        type = "toggle",
                        name = "Enable rune bar",
                        order = 2,
                        width = "full",
                        get = function() return db.profile.runeBar.enabled end,
                        set = function(_, val)
                            db.profile.runeBar.enabled = val
                            ECM.OptionUtil.SetModuleEnabled("RuneBar", val)
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    heightDesc = {
                        type = "description",
                        name = "\nOverride the default bar height. Set to 0 to use the global default.",
                        order = 3,
                    },
                    height = {
                        type = "range",
                        name = "Height Override",
                        order = 4,
                        width = "double",
                        min = 0,
                        max = 40,
                        step = 1,
                        get = function() return db.profile.runeBar.height or 0 end,
                        set = function(_, val)
                            db.profile.runeBar.height = val > 0 and val or nil
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    heightReset = {
                        type = "execute",
                        name = "X",
                        order = 5,
                        width = 0.3,
                        hidden = function() return not ECM.OptionUtil.IsValueChanged("runeBar.height") end,
                        func = ECM.OptionUtil.MakeResetHandler("runeBar.height"),
                    },
                    spacer1 = {
                        type = "description",
                        name = " ",
                        order = 20,
                    },
                    color = {
                        type = "color",
                        name = "Rune color",
                        order = 21,
                        width = "double",
                        get = function()
                            local c = db.profile.runeBar.color
                            return c.r, c.g, c.b
                        end,
                        set = function(_, r, g, b)
                            db.profile.runeBar.color = { r = r, g = g, b = b, a = 1 }
                            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                        end,
                    },
                    colorReset = {
                        type = "execute",
                        name = "X",
                        order = 22,
                        width = 0.3,
                        hidden = function() return not ECM.OptionUtil.IsValueChanged("runeBar.color") end,
                        func = ECM.OptionUtil.MakeResetHandler("runeBar.color"),
                    },
                },
            },
            positioningSettings = ECM.OptionUtil.MakePositioningGroup("runeBar", 3, {
                widthDesc = "Width when custom positioning is enabled.",
                offsetXDesc = "\nHorizontal offset when custom positioning is enabled.",
                offsetYDesc = "\nVertical offset when custom positioning is enabled.",
            }),
        },
    }
end

local function ProfileOptionsTable()
    local db = mod.db
    -- Use AceDBOptions to generate a full profile management UI
    local profileOptions = AceDBOptions:GetOptionsTable(db)
    profileOptions.order = 7

    -- Add Import/Export section at the top
    profileOptions.args = profileOptions.args or {}
    profileOptions.args.importExport = {
        type = "group",
        name = "Import / Export",
        inline = true,
        order = 0,
        args = {
            description = {
                type = "description",
                name = "Export your current profile to share or back up. Import will replace all current settings and require a UI reload.\n\n",
                order = 1,
                fontSize = "medium",
            },
            exportButton = {
                type = "execute",
                name = "Export Profile",
                desc = "Export the current profile to a shareable string.",
                order = 2,
                width = "normal",
                func = function()
                    local exportString, err = ECM.ImportExport.ExportCurrentProfile()
                    if not exportString then
                        mod:Print("Export failed: " .. (err or "Unknown error"))
                        return
                    end

                    mod:ShowExportDialog(exportString)
                end,
            },
            importButton = {
                type = "execute",
                name = "Import Profile",
                desc = "Import a profile from an export string. This will replace all current settings.",
                order = 3,
                width = "normal",
                func = function()
                    if InCombatLockdown() then
                        mod:Print("Cannot import during combat (reload blocked)")
                        return
                    end

                    mod:ShowImportDialog()
                end,
            },
        },
    }

    return profileOptions
end

--------------------------------------------------------------------------------
-- Tick Marks Options (per-class/per-spec)
--------------------------------------------------------------------------------
---
--- Gets tick marks for the current class/spec.
---@return ECM_TickMark[]
local function GetCurrentTicks()
    local db = mod.db
    local classID, specIndex = ECM.OptionUtil.GetCurrentClassSpec()
    if not classID or not specIndex then
        return {}
    end

    local ticksCfg = db.profile.powerBar and db.profile.powerBar.ticks
    if not ticksCfg or not ticksCfg.mappings then
        return {}
    end

    local classMappings = ticksCfg.mappings[classID]
    if not classMappings then
        return {}
    end

    return classMappings[specIndex] or {}
end

--- Sets tick marks for the current class/spec.
---@param ticks ECM_TickMark[]
local function SetCurrentTicks(ticks)
    local db = mod.db
    local classID, specIndex = ECM.OptionUtil.GetCurrentClassSpec()
    if not classID or not specIndex then
        return
    end

    local powerBarCfg = db.profile.powerBar
    if not powerBarCfg then
        db.profile.powerBar = {}
        powerBarCfg = db.profile.powerBar
    end

    local ticksCfg = powerBarCfg.ticks
    if not ticksCfg then
        powerBarCfg.ticks = { mappings = {}, defaultColor = ECM.Constants.DEFAULT_POWERBAR_TICK_COLOR, defaultWidth = 1 }
        ticksCfg = powerBarCfg.ticks
    end
    if not ticksCfg.mappings then
        ticksCfg.mappings = {}
    end
    if not ticksCfg.mappings[classID] then
        ticksCfg.mappings[classID] = {}
    end

    ticksCfg.mappings[classID][specIndex] = ticks
end

--- Adds a new tick mark for the current class/spec.
---@param value number
---@param color ECM_Color|nil
---@param width number|nil
local function AddTick(value, color, width)
    local ticks = GetCurrentTicks()
    local db = mod.db
    local powerBarCfg = db.profile.powerBar
    if not powerBarCfg then
        db.profile.powerBar = {}
        powerBarCfg = db.profile.powerBar
    end

    local ticksCfg = powerBarCfg.ticks
    if not ticksCfg then
        powerBarCfg.ticks = { mappings = {}, defaultColor = ECM.Constants.DEFAULT_POWERBAR_TICK_COLOR, defaultWidth = 1 }
        ticksCfg = powerBarCfg.ticks
    end

    local newTick = {
        value = value,
        color = color or ECM_CloneValue(ticksCfg.defaultColor),
        width = width or ticksCfg.defaultWidth,
    }
    table.insert(ticks, newTick)
    SetCurrentTicks(ticks)
end

--- Removes a tick mark at the given index for the current class/spec.
---@param index number
local function RemoveTick(index)
    local ticks = GetCurrentTicks()
    if ticks[index] then
        table.remove(ticks, index)
        SetCurrentTicks(ticks)
    end
end

--- Updates a tick mark at the given index for the current class/spec.
---@param index number
---@param field string
---@param value any
local function UpdateTick(index, field, value)
    local ticks = GetCurrentTicks()
    if ticks[index] then
        ticks[index][field] = value
        SetCurrentTicks(ticks)
    end
end

TickMarksOptionsTable = function()
    local db = mod.db

    --- Generates per-tick options dynamically.
    local function GenerateTickArgs()
        local args = {}
        local ticks = GetCurrentTicks()
        local ticksCfg = db.profile.powerBar and db.profile.powerBar.ticks

        for i, tick in ipairs(ticks) do
            local orderBase = i * 10

            args["tickHeader" .. i] = {
                type = "header",
                name = "Tick " .. i,
                order = orderBase,
            }

            args["tickValue" .. i] = {
                type = "range",
                name = "Value",
                desc = "Resource value at which to display this tick mark.",
                order = orderBase + 1,
                width = 1.2,
                min = 1,
                max = 200,
                step = 1,
                get = function()
                    local t = GetCurrentTicks()
                    return t[i] and t[i].value or 50
                end,
                set = function(_, val)
                    UpdateTick(i, "value", val)
                    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                    AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
                end,
            }

            args["tickWidth" .. i] = {
                type = "range",
                name = "Width",
                desc = "Width of the tick mark in pixels.",
                order = orderBase + 2,
                width = 0.8,
                min = 1,
                max = 5,
                step = 1,
                get = function()
                    local t = GetCurrentTicks()
                    return t[i] and t[i].width or ticksCfg.defaultWidth
                end,
                set = function(_, val)
                    UpdateTick(i, "width", val)
                    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                    AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
                end,
            }

            args["tickColor" .. i] = {
                type = "color",
                name = "Color",
                desc = "Color of this tick mark.",
                order = orderBase + 3,
                width = 0.6,
                hasAlpha = true,
                get = function()
                    local t = GetCurrentTicks()
                    local c = t[i] and t[i].color or ticksCfg.defaultColor
                    return c.r or 0, c.g or 0, c.b or 0, c.a or 0.5
                end,
                set = function(_, r, g, b, a)
                    UpdateTick(i, "color", { r = r, g = g, b = b, a = a })
                    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                    AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
                end,
            }

            args["tickRemove" .. i] = {
                type = "execute",
                name = "X",
                desc = "Remove this tick mark.",
                order = orderBase + 4,
                width = 0.3,
                confirm = true,
                confirmText = "Remove tick mark at value " .. (tick.value or "?") .. "?",
                func = function()
                    RemoveTick(i)
                    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                    AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
                end,
            }
        end

        return args
    end

    local options = {
        type = "group",
        name = "",
        order = 42,
        inline = true,
        args = {
            description = {
                type = "description",
                name = "Tick marks allow you to place markers at specific values on the power bar. This can be useful for tracking when you will have enough power to cast important abilities.\n\n" ..
                       "These settings are saved per class and specialization.\n\n",
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
                desc = "Default color for new tick marks.",
                order = 10,
                width = "normal",
                hasAlpha = true,
                get = function()
                    local ticksCfg = db.profile.powerBar and db.profile.powerBar.ticks
                    local c = ticksCfg and ticksCfg.defaultColor or ECM.Constants.DEFAULT_POWERBAR_TICK_COLOR
                    return c.r or 0, c.g or 0, c.b or 0, c.a or 0.5
                end,
                set = function(_, r, g, b, a)
                    local powerBarCfg = db.profile.powerBar
                    if not powerBarCfg then
                        db.profile.powerBar = {}
                        powerBarCfg = db.profile.powerBar
                    end
                    local ticksCfg = powerBarCfg.ticks
                    if not ticksCfg then
                        powerBarCfg.ticks = { mappings = {}, defaultColor = ECM.Constants.DEFAULT_POWERBAR_TICK_COLOR, defaultWidth = 1 }
                        ticksCfg = powerBarCfg.ticks
                    end
                    ticksCfg.defaultColor = { r = r, g = g, b = b, a = a }
                end,
            },
            defaultWidth = {
                type = "range",
                name = "Default width",
                desc = "Default width for new tick marks.",
                order = 11,
                width = "normal",
                min = 1,
                max = 5,
                step = 1,
                get = function()
                    local ticksCfg = db.profile.powerBar and db.profile.powerBar.ticks
                    return (ticksCfg and ticksCfg.defaultWidth) or 1
                end,
                set = function(_, val)
                    local powerBarCfg = db.profile.powerBar
                    if not powerBarCfg then
                        db.profile.powerBar = {}
                        powerBarCfg = db.profile.powerBar
                    end
                    local ticksCfg = powerBarCfg.ticks
                    if not ticksCfg then
                        powerBarCfg.ticks = { mappings = {}, defaultColor = ECM.Constants.DEFAULT_POWERBAR_TICK_COLOR, defaultWidth = 1 }
                        ticksCfg = powerBarCfg.ticks
                    end
                    ticksCfg.defaultWidth = val
                end,
            },
            spacer2 = {
                type = "description",
                name = " ",
                order = 19,
            },
            tickCount = {
                type = "description",
                name = function()
                    local ticks = GetCurrentTicks()
                    local count = #ticks
                    if count == 0 then
                        return "|cffaaaaaa(No tick marks configured for this spec)|r"
                    end
                    return string.format("|cff888888%d tick mark(s) configured|r", count)
                end,
                order = 21,
            },
            addTick = {
                type = "execute",
                name = "Add Tick Mark",
                desc = "Add a new tick mark for the current spec.",
                order = 22,
                width = "normal",
                func = function()
                    AddTick(50, nil, nil)
                    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                    AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
                end,
            },
            spacer3 = {
                type = "description",
                name = " ",
                order = 23,
            },
            ticks = {
                type = "group",
                name = "",
                order = 30,
                inline = true,
                args = GenerateTickArgs(),
            },
            spacer4 = {
                type = "description",
                name = " ",
                order = 90,
            },
            clearAll = {
                type = "execute",
                name = "Clear All Ticks",
                desc = "Remove all tick marks for the current spec.",
                order = 100,
                width = "normal",
                confirm = true,
                confirmText = "Are you sure you want to remove all tick marks for this spec?",
                disabled = function()
                    return #GetCurrentTicks() == 0
                end,
                func = function()
                    SetCurrentTicks({})
                    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                    AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
                end,
            },
        },
    }
    return options
end

local function AboutOptionsTable()
    local db = mod.db
    local authorColored = "|cffa855f7S|r|cff7a84f7o|r|cff6b9bf7l|r|cff4cc9f0ä|r|cff22c55er|r"
    local version = C_AddOns.GetAddOnMetadata("EnhancedCooldownManager", "Version") or "unknown"
    return {
        type = "group",
        name = "About",
        order = 8,
        args = {
            author = {
                type = "description",
                name = "An addon by " .. authorColored,
                order = 1,
                fontSize = "medium",
            },
            version = {
                type = "description",
                name = "\nVersion: |cff67dbf8" .. version .. "|r",
                order = 2,
                fontSize = "medium",
            },
            spacer1 = {
                type = "description",
                name = " ",
                order = 2.5,
            },
            troubleshooting = {
                type = "group",
                name = "Troubleshooting",
                inline = true,
                order = 3,
                args = {
                    debugDesc = {
                        type = "description",
                        name = "Enable debug mode. This will generate more detailed logs in the chat window.",
                        order = 1,
                    },
                    debug = {
                        type = "toggle",
                        name = "Debug mode",
                        order = 2,
                        width = "full",
                        get = function() return db.profile.debug end,
                        set = function(_, val) db.profile.debug = val end,
                    },
                },
            },
            performanceSettings = {
                type = "group",
                name = "Performance",
                inline = true,
                order = 4,
                args = {
                    updateFrequencyDesc = {
                        type = "description",
                        name = "How often bars update (seconds). Lower values makes the bars smoother but use more CPU.",
                        order = 1,
                    },
                    updateFrequency = {
                        type = "range",
                        name = "Update Frequency",
                        order = 2,
                        width = "double",
                        min = 0.04,
                        max = 0.5,
                        step = 0.04,
                        get = function() return db.profile.global.updateFrequency end,
                        set = function(_, val) db.profile.global.updateFrequency = val end,
                    },
                    updateFrequencyReset = {
                        type = "execute",
                        name = "X",
                        order = 3,
                        width = 0.3,
                        hidden = function() return not ECM.OptionUtil.IsValueChanged("global.updateFrequency") end,
                        func = ECM.OptionUtil.MakeResetHandler("global.updateFrequency"),
                    },
                },
            },
            reset = {
                type = "group",
                name = "Reset Settings",
                inline = true,
                order = 5,
                args = {
                    resetDesc = {
                        type = "description",
                        name = "Reset all settings to their default values and reload the UI. This action cannot be undone.",
                        order = 1,
                    },
                    resetAll = {
                        type = "execute",
                        name = "Reset Everything to Default",
                        order = 2,
                        width = "full",
                        confirm = true,
                        confirmText = "This will reset ALL settings to their defaults and reload the UI. This cannot be undone. Are you sure?",
                        func = function()
                            db:ResetProfile()
                            ReloadUI()
                        end,
                    },
                },
            },
        },
    }
end

--------------------------------------------------------------------------------
-- Main options table (combines all sections with tree navigation)
--------------------------------------------------------------------------------

local function GetOptionsTable()
    return {
        type = "group",
        name = ColorUtil.Sparkle(ECM.Constants.ADDON_NAME),
        childGroups = "tree",
        args = {
            general = GeneralOptionsTable(),
            powerBar = PowerBarOptionsTable(),
            resourceBar = ResourceBarOptionsTable(),
            runeBar = RuneBarOptionsTable(),
            auraBars = ns.BuffBarsOptions.GetOptionsTable(),
            itemIcons = mod.ItemIconsOptions.GetOptionsTable(),
            profile = ProfileOptionsTable(),
            about = AboutOptionsTable(),
        },
    }
end

--------------------------------------------------------------------------------
-- Module lifecycle
--------------------------------------------------------------------------------
function Options:OnInitialize()
    -- Register the options table
    AceConfigRegistry:RegisterOptionsTable("EnhancedCooldownManager", GetOptionsTable)

    -- Create the options frame linked to Blizzard's settings
    self.optionsFrame = AceConfigDialog:AddToBlizOptions(
        "EnhancedCooldownManager",
        "Enhanced Cooldown Manager"
    )

    -- Register callbacks for profile changes to refresh bars
    local db = mod.db
    db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
end

function Options:OnProfileChanged()
    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
end

function Options:OnEnable()
    -- Nothing special needed
end

function Options:OnDisable()
    -- Nothing special needed
end

--------------------------------------------------------------------------------
-- Slash command to open options
--------------------------------------------------------------------------------
function Options:OpenOptions()
    if self.optionsFrame then
        Settings.OpenToCategory(self.optionsFrame.name)
    end
end
