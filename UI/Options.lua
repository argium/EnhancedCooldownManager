-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

---@class ECMOptionsModule Options module.
local _, ns = ...

local ECM = ns.Addon
local Util = ns.Util
local C = ns.Constants
local Options = ECM:NewModule("Options")

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")
local LSM = LibStub("LibSharedMedia-3.0", true)

-- Constants
local SIDEBAR_BG_COLOR = { r = 0.1, g = 0.1, b = 0.1, a = 0.9 }
local POSITION_MODE_TEXT = {
    [C.ANCHORMODE_CHAIN] = "Position Automatically",
    [C.ANCHORMODE_FREE] = "Free Positioning",
}

local function ApplyPositionModeToBar(cfg, mode)
    if mode == C.ANCHORMODE_FREE then
        if cfg.width == nil then
            cfg.width = C.DEFAULT_BAR_WIDTH
        end
    end

    cfg.anchorMode = mode
end

local function IsAnchorModeFree(cfg)
    return cfg and cfg.anchorMode == C.ANCHORMODE_FREE
end

local function SetModuleEnabled(moduleName, enabled)
    local module = ECM:GetModule(moduleName, true)
    if not module then
        return
    end

    if enabled then
        if not module:IsEnabled() then
            ECM:EnableModule(moduleName)
        end
    else
        if module:IsEnabled() then
            ECM:DisableModule(moduleName)
        end
    end
end

--------------------------------------------------------------------------------
-- Utility: Deep compare for detecting changes from defaults
--------------------------------------------------------------------------------
local function DeepEquals(a, b)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not DeepEquals(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

--------------------------------------------------------------------------------
-- Utility: Deep copy a value (handles nested tables)
--------------------------------------------------------------------------------
local function DeepCopy(val)
    if type(val) ~= "table" then return val end
    local copy = {}
    for k, v in pairs(val) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

--------------------------------------------------------------------------------
-- Utility: Get nested value from table using dot-separated path
--------------------------------------------------------------------------------
local NormalizePathKey

local function GetNestedValue(tbl, path)
    local current = tbl
    for resource in path:gmatch("[^.]+") do
        if type(current) ~= "table" then return nil end
        current = current[NormalizePathKey(resource)]
    end
    return current
end

NormalizePathKey = function(key)
    local numberKey = tonumber(key)
    if numberKey then
        return numberKey
    end
    return key
end

local function SplitPath(path)
    local resources = {}
    for resource in path:gmatch("[^.]+") do
        table.insert(resources, resource)
    end
    return resources
end

--------------------------------------------------------------------------------
-- Utility: Set nested value in table using dot-separated path
--------------------------------------------------------------------------------
local function SetNestedValue(tbl, path, value)
    local resources = SplitPath(path)
    local current = tbl
    for i = 1, #resources - 1 do
        local key = NormalizePathKey(resources[i])
        if current[key] == nil then
            current[key] = {}
        end
        current = current[key]
    end
    current[NormalizePathKey(resources[#resources])] = value
end

--------------------------------------------------------------------------------
-- Utility: Check if value differs from default
--------------------------------------------------------------------------------
local function IsValueChanged(path)
    local profile = ECM.db and ECM.db.profile
    local defaults = ECM.db and ECM.db.defaults and ECM.db.defaults.profile
    if not profile or not defaults then return false end

    local currentVal = GetNestedValue(profile, path)
    local defaultVal = GetNestedValue(defaults, path)

    Util.Log("Options", "IsValueChanged", {
        path = path,
        currentVal = currentVal,
        defaultVal = defaultVal,
    })
    return not DeepEquals(currentVal, defaultVal)
end

--------------------------------------------------------------------------------
-- Utility: Reset value to default
--------------------------------------------------------------------------------
local function ResetToDefault(path)
    local profile = ECM.db and ECM.db.profile
    local defaults = ns.defaults and ns.defaults.profile
    if not profile or not defaults then return end

    local defaultVal = GetNestedValue(defaults, path)
    -- Deep copy for tables (recursive to handle nested tables)
    SetNestedValue(profile, path, DeepCopy(defaultVal))
end

--------------------------------------------------------------------------------
-- Build LibSharedMedia dropdown values
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- Utility: Get current class and spec, localised.
--------------------------------------------------------------------------------

--- Gets current class and spec IDs.
---@return number|nil classID, number|nil specIndex, string className, string specName
local function GetCurrentClassSpec()
    local localisedClassName, className, classID = UnitClass("player")
    local specIndex = GetSpecialization()
    local specName
    if specIndex then
        _, specName = GetSpecializationInfo(specIndex)
    end
    return classID, specIndex, localisedClassName or "Unknown", specName or "None"
end

local function IsDeathKnight()
    local _, className = UnitClass("player")
    return className == "DEATHKNIGHT"
end


--------------------------------------------------------------------------------
-- Options table generators for each section
--------------------------------------------------------------------------------
local function MakeResetHandler(path, refreshFunc)
    return function()
        ResetToDefault(path)
        if refreshFunc then refreshFunc() end
        ECM.ScheduleLayoutUpdate(0)
        AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
    end
end

--------------------------------------------------------------------------------
-- Helper: Generate positioning settings args (width, offsetX, offsetY)
--------------------------------------------------------------------------------
--- Generates positioning settings for a bar (width, offsetX, offsetY with reset buttons).
--- @param configPath string The config path (e.g., "powerBar", "buffBars")
--- @param options table Options: { includeOffsets = true, widthLabel = "Width", widthDesc = "..." }
--- @return table args table for positioning settings
local function MakePositioningSettingsArgs(configPath, options)
    options = options or {}
    local includeOffsets = options.includeOffsets ~= false  -- Default true
    local widthLabel = options.widthLabel or "Width"
    local widthDesc = options.widthDesc or "Width when free positioning is enabled."
    local offsetXDesc = options.offsetXDesc or "\nHorizontal offset when free positioning is enabled."
    local offsetYDesc = options.offsetYDesc or "\nVertical offset when free positioning is enabled."

    local db = ECM.db
    local configTable = GetNestedValue(db.profile, configPath)

    local args = {
        widthDesc = {
            type = "description",
            name = widthDesc,
            order = 3,
            hidden = function() return not IsAnchorModeFree(GetNestedValue(db.profile, configPath)) end,
        },
        width = {
            type = "range",
            name = widthLabel,
            order = 4,
            width = "double",
            min = 100,
            max = 600,
            step = 10,
            hidden = function() return not IsAnchorModeFree(GetNestedValue(db.profile, configPath)) end,
            get = function()
                local cfg = GetNestedValue(db.profile, configPath)
                return cfg.width or C.DEFAULT_BAR_WIDTH
            end,
            set = function(_, val)
                local cfg = GetNestedValue(db.profile, configPath)
                cfg.width = val
                ECM.ScheduleLayoutUpdate(0)
            end,
        },
        widthReset = {
            type = "execute",
            name = "X",
            order = 5,
            width = 0.3,
            hidden = function()
                return not IsAnchorModeFree(GetNestedValue(db.profile, configPath))
                    or not IsValueChanged(configPath .. ".width")
            end,
            func = MakeResetHandler(configPath .. ".width"),
        },
    }

    if includeOffsets then
        args.offsetXDesc = {
            type = "description",
            name = offsetXDesc,
            order = 6,
            hidden = function() return not IsAnchorModeFree(GetNestedValue(db.profile, configPath)) end,
        }
        args.offsetX = {
            type = "range",
            name = "Offset X",
            order = 7,
            width = "double",
            min = -800,
            max = 800,
            step = 1,
            hidden = function() return not IsAnchorModeFree(GetNestedValue(db.profile, configPath)) end,
            get = function()
                local cfg = GetNestedValue(db.profile, configPath)
                return cfg.offsetX or 0
            end,
            set = function(_, val)
                local cfg = GetNestedValue(db.profile, configPath)
                cfg.offsetX = val ~= 0 and val or nil
                ECM.ScheduleLayoutUpdate(0)
            end,
        }
        args.offsetXReset = {
            type = "execute",
            name = "X",
            order = 8,
            width = 0.3,
            hidden = function()
                return not IsAnchorModeFree(GetNestedValue(db.profile, configPath))
                    or not IsValueChanged(configPath .. ".offsetX")
            end,
            func = MakeResetHandler(configPath .. ".offsetX"),
        }
        args.offsetYDesc = {
            type = "description",
            name = offsetYDesc,
            order = 9,
            hidden = function() return not IsAnchorModeFree(GetNestedValue(db.profile, configPath)) end,
        }
        args.offsetY = {
            type = "range",
            name = "Offset Y",
            order = 10,
            width = "double",
            min = -800,
            max = 800,
            step = 1,
            hidden = function() return not IsAnchorModeFree(GetNestedValue(db.profile, configPath)) end,
            get = function()
                local cfg = GetNestedValue(db.profile, configPath)
                return cfg.offsetY or 0
            end,
            set = function(_, val)
                local cfg = GetNestedValue(db.profile, configPath)
                cfg.offsetY = val ~= 0 and val or nil
                ECM.ScheduleLayoutUpdate(0)
            end,
        }
        args.offsetYReset = {
            type = "execute",
            name = "X",
            order = 11,
            width = 0.3,
            hidden = function()
                return not IsAnchorModeFree(GetNestedValue(db.profile, configPath))
                    or not IsValueChanged(configPath .. ".offsetY")
            end,
            func = MakeResetHandler(configPath .. ".offsetY"),
        }
    end

    return args
end

local function GeneralOptionsTable()
    local db = ECM.db
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
                            ECM.ScheduleLayoutUpdate(0)
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
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    texture = {
                        type = "select",
                        name = "Bar Texture",
                        order = 8,
                        width = "double",
                        dialogControl = "LSM30_Statusbar",
                        values = GetLSMStatusbarValues,
                        get = function() return db.profile.global.texture end,
                        set = function(_, val)
                            db.profile.global.texture = val
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    textureReset = {
                        type = "execute",
                        name = "X",
                        order = 9,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("global.texture") end,
                        func = MakeResetHandler("global.texture"),
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
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    offsetYReset = {
                        type = "execute",
                        name = "X",
                        order = 3,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("global.offsetY") end,
                        func = MakeResetHandler("global.offsetY"),
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
                            ECM.ScheduleLayoutUpdate(0)
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
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    combatFadeOpacityReset = {
                        type = "execute",
                        name = "X",
                        order = 5,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("global.outOfCombatFade.opacity") end,
                        disabled = function() return not db.profile.global.outOfCombatFade.enabled end,
                        func = MakeResetHandler("global.outOfCombatFade.opacity"),
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
                            ECM.ScheduleLayoutUpdate(0)
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
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                },
            },
        },
    }
end


-- Forward declarations (these are defined later, but referenced by option-table builders)
local TickMarksOptionsTable
local ColoursOptionsTable

local function PowerBarOptionsTable()
    local db = ECM.db
    local tickMarks = TickMarksOptionsTable()
    tickMarks.name = "Tick Marks"
    tickMarks.inline = true
    tickMarks.order = 4
    return {
        type = "group",
        name = "Power Bar",
        order = 2,
        args = {
            basicSettings = {
                type = "group",
                name = "Basic Settings",
                inline = true,
                order = 1,
                args = {
                    enabled = {
                        type = "toggle",
                        name = "Enable power bar",
                        order = 2,
                        width = "full",
                        get = function() return db.profile.powerBar.enabled end,
                        set = function(_, val)
                            db.profile.powerBar.enabled = val
                            SetModuleEnabled("PowerBar", val)
                            ECM.ScheduleLayoutUpdate(0)
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
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    heightReset = {
                        type = "execute",
                        name = "X",
                        order = 5,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("powerBar.height") end,
                        func = MakeResetHandler("powerBar.height"),
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
                            ECM.ScheduleLayoutUpdate(0)
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
                            ECM.ScheduleLayoutUpdate(0)
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
                            ECM.ScheduleLayoutUpdate(0)
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
                            ECM.ScheduleLayoutUpdate(0)
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
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                },
            },
            positioningSettings = (function()
                local positioningArgs = {
                    modeDesc = {
                        type = "description",
                        name = "Choose how the bar is positioned. Automatic keeps the bar attached to the Cooldown Manager. Custom lets you position it anywhere on the screen and configure its size.",
                        order = 1,
                        fontSize = "medium",
                    },
                    modeSelector = {
                        type = "select",
                        name = "",
                        order = 2,
                        width = "full",
                        dialogControl = "ECM_PositionModeSelector",
                        values = POSITION_MODE_TEXT,
                        get = function()
                            return db.profile.powerBar.anchorMode
                        end,
                        set = function(_, val)
                            ApplyPositionModeToBar(db.profile.powerBar, val)
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    spacer1 = {
                        type = "description",
                        name = " ",
                        order = 2.5,
                    },
                }

                -- Add width, offsetX, offsetY settings
                local positioningSettings = MakePositioningSettingsArgs("powerBar")
                for k, v in pairs(positioningSettings) do
                    positioningArgs[k] = v
                end

                return {
                    type = "group",
                    name = "Positioning",
                    inline = true,
                    order = 3,
                    args = positioningArgs,
                }
            end)(),
            tickMarks = tickMarks,
        },
    }
end

local function ResourceBarOptionsTable()
    local db = ECM.db
    return {
        type = "group",
        name = "Resource Bar",
        order = 3,
        args = {
            basicSettings = {
                type = "group",
                name = "Basic Settings",
                inline = true,
                order = 1,
                args = {
                    enabled = {
                        type = "toggle",
                        name = "Enable resource bar",
                        order = 3,
                        width = "full",
                        get = function() return db.profile.resourceBar.enabled end,
                        set = function(_, val)
                            db.profile.resourceBar.enabled = val
                            SetModuleEnabled("ResourceBar", val)
                            ECM.ScheduleLayoutUpdate(0)
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
                        order = 5,
                        width = "double",
                        min = 0,
                        max = 40,
                        step = 1,
                        get = function() return db.profile.resourceBar.height or 0 end,
                        set = function(_, val)
                            db.profile.resourceBar.height = val > 0 and val or nil
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    heightReset = {
                        type = "execute",
                        name = "X",
                        order = 6,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("resourceBar.height") end,
                        func = MakeResetHandler("resourceBar.height"),
                    },
                },
            },
            positioningSettings = (function()
                local positioningArgs = {
                    modeDesc = {
                        type = "description",
                        name = "Choose how the bar is positioned. Automatic keeps the bar attached to the Cooldown Manager. Custom lets you position it anywhere on the screen and configure its size.",
                        order = 1,
                        fontSize = "medium",
                    },
                    modeSelector = {
                        type = "select",
                        name = "",
                        order = 2,
                        width = "full",
                        dialogControl = "ECM_PositionModeSelector",
                        values = POSITION_MODE_TEXT,
                        get = function()
                            return db.profile.resourceBar.anchorMode
                        end,
                        set = function(_, val)
                            ApplyPositionModeToBar(db.profile.resourceBar, val)
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    spacer1 = {
                        type = "description",
                        name = " ",
                        order = 2.5,
                    },
                }

                -- Add width, offsetX, offsetY settings
                local positioningSettings = MakePositioningSettingsArgs("resourceBar")
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
            resourceColors = {
                type = "group",
                name = "Display Options",
                inline = true,
                order = 3,
                args = {
                    borderEnabled = {
                        type = "toggle",
                        name = "Show border",
                        order = 1,
                        width = "full",
                        get = function() return db.profile.resourceBar.border.enabled end,
                        set = function(_, val)
                            db.profile.resourceBar.border.enabled = val
                            ECM.ScheduleLayoutUpdate(0)
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
                            ECM.ScheduleLayoutUpdate(0)
                        end,
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
                            ECM.ScheduleLayoutUpdate(0)
                        end,
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
                    colorDemonHunterSouls = {
                        type = "color",
                        name = "Soul Fragments (Demon Hunter)",
                        order = 10,
                        width = "double",
                        get = function()
                            local c = db.profile.resourceBar.colors.souls
                            return c.r, c.g, c.b
                        end,
                        set = function(_, r, g, b)
                            db.profile.resourceBar.colors.souls = { r = r, g = g, b = b, a = 1 }
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    colorDemonHunterSoulsReset = {
                        type = "execute",
                        name = "X",
                        order = 11,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("resourceBar.colors.souls") end,
                        func = MakeResetHandler("resourceBar.colors.souls"),
                    },
                    colorDevourerNormal = {
                        type = "color",
                        name = "Devourer Souls (Normal)",
                        order = 12,
                        width = "double",
                        get = function()
                            local c = db.profile.resourceBar.colors.devourerNormal
                            return c.r, c.g, c.b
                        end,
                        set = function(_, r, g, b)
                            db.profile.resourceBar.colors.devourerNormal = { r = r, g = g, b = b, a = 1 }
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    colorDevourerNormalReset = {
                        type = "execute",
                        name = "X",
                        order = 13,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("resourceBar.colors.devourerNormal") end,
                        func = MakeResetHandler("resourceBar.colors.devourerNormal"),
                    },
                    colorDevourerMeta = {
                        type = "color",
                        name = "Devourer Souls (Neon)",
                        order = 14,
                        width = "double",
                        get = function()
                            local c = db.profile.resourceBar.colors.devourerMeta
                            return c.r, c.g, c.b
                        end,
                        set = function(_, r, g, b)
                            db.profile.resourceBar.colors.devourerMeta = { r = r, g = g, b = b, a = 1 }
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    colorDevourerMetaReset = {
                        type = "execute",
                        name = "X",
                        order = 15,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("resourceBar.colors.devourerMeta") end,
                        func = MakeResetHandler("resourceBar.colors.devourerMeta"),
                    },
                    colorComboPoints = {
                        type = "color",
                        name = "Combo Points",
                        order = 16,
                        width = "double",
                        get = function()
                            local c = db.profile.resourceBar.colors[Enum.PowerType.ComboPoints]
                            return c.r, c.g, c.b
                        end,
                        set = function(_, r, g, b)
                            db.profile.resourceBar.colors[Enum.PowerType.ComboPoints] = { r = r, g = g, b = b, a = 1 }
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    colorComboPointsReset = {
                        type = "execute",
                        name = "X",
                        order = 17,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("resourceBar.colors." .. Enum.PowerType.ComboPoints) end,
                        func = MakeResetHandler("resourceBar.colors." .. Enum.PowerType.ComboPoints),
                    },
                    colorChi = {
                        type = "color",
                        name = "Chi",
                        order = 18,
                        width = "double",
                        get = function()
                            local c = db.profile.resourceBar.colors[Enum.PowerType.Chi]
                            return c.r, c.g, c.b
                        end,
                        set = function(_, r, g, b)
                            db.profile.resourceBar.colors[Enum.PowerType.Chi] = { r = r, g = g, b = b, a = 1 }
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    colorChiReset = {
                        type = "execute",
                        name = "X",
                        order = 19,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("resourceBar.colors." .. Enum.PowerType.Chi) end,
                        func = MakeResetHandler("resourceBar.colors." .. Enum.PowerType.Chi),
                    },
                    colorHolyPower = {
                        type = "color",
                        name = "Holy Power",
                        order = 20,
                        width = "double",
                        get = function()
                            local c = db.profile.resourceBar.colors[Enum.PowerType.HolyPower]
                            return c.r, c.g, c.b
                        end,
                        set = function(_, r, g, b)
                            db.profile.resourceBar.colors[Enum.PowerType.HolyPower] = { r = r, g = g, b = b, a = 1 }
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    colorHolyPowerReset = {
                        type = "execute",
                        name = "X",
                        order = 21,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("resourceBar.colors." .. Enum.PowerType.HolyPower) end,
                        func = MakeResetHandler("resourceBar.colors." .. Enum.PowerType.HolyPower),
                    },
                    colorSoulShards = {
                        type = "color",
                        name = "Soul Shards",
                        order = 22,
                        width = "double",
                        get = function()
                            local c = db.profile.resourceBar.colors[Enum.PowerType.SoulShards]
                            return c.r, c.g, c.b
                        end,
                        set = function(_, r, g, b)
                            db.profile.resourceBar.colors[Enum.PowerType.SoulShards] = { r = r, g = g, b = b, a = 1 }
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    colorSoulShardsReset = {
                        type = "execute",
                        name = "X",
                        order = 23,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("resourceBar.colors." .. Enum.PowerType.SoulShards) end,
                        func = MakeResetHandler("resourceBar.colors." .. Enum.PowerType.SoulShards),
                    },
                    colorEssence = {
                        type = "color",
                        name = "Essence",
                        order = 24,
                        width = "double",
                        get = function()
                            local c = db.profile.resourceBar.colors[Enum.PowerType.Essence]
                            return c.r, c.g, c.b
                        end,
                        set = function(_, r, g, b)
                            db.profile.resourceBar.colors[Enum.PowerType.Essence] = { r = r, g = g, b = b, a = 1 }
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    colorEssenceReset = {
                        type = "execute",
                        name = "X",
                        order = 25,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("resourceBar.colors." .. Enum.PowerType.Essence) end,
                        func = MakeResetHandler("resourceBar.colors." .. Enum.PowerType.Essence),
                    },
                },
            },
        },
    }
end

local function RuneBarOptionsTable()
    local db = ECM.db
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
                            SetModuleEnabled("RuneBar", val)
                            ECM.ScheduleLayoutUpdate(0)
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
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    heightReset = {
                        type = "execute",
                        name = "X",
                        order = 5,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("runeBar.height") end,
                        func = MakeResetHandler("runeBar.height"),
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
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    colorReset = {
                        type = "execute",
                        name = "X",
                        order = 22,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("runeBar.color") end,
                        func = MakeResetHandler("runeBar.color"),
                    },
                },
            },
            positioningSettings = (function()
                local positioningArgs = {
                    modeDesc = {
                        type = "description",
                        name = "Choose how the bar is positioned. Automatic keeps the bar attached to the Cooldown Manager. Custom lets you position it anywhere on the screen and configure its size.",
                        order = 1,
                        fontSize = "medium",
                    },
                    modeSelector = {
                        type = "select",
                        name = "",
                        order = 2,
                        width = "full",
                        dialogControl = "ECM_PositionModeSelector",
                        values = POSITION_MODE_TEXT,
                        get = function() return db.profile.runeBar.anchorMode end,
                        set = function(_, val)
                            ApplyPositionModeToBar(db.profile.runeBar, val)
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    spacer1 = {
                        type = "description",
                        name = " ",
                        order = 2.5,
                    },
                }

                -- Add width, offsetX, offsetY settings
                local positioningSettings = MakePositioningSettingsArgs("runeBar", {
                    widthDesc = "Width when custom positioning is enabled.",
                    offsetXDesc = "\nHorizontal offset when custom positioning is enabled.",
                    offsetYDesc = "\nVertical offset when custom positioning is enabled.",
                })
                for k, v in pairs(positioningSettings) do
                    positioningArgs[k] = v
                end

                return {
                    type = "group",
                    name = "Positioning",
                    inline = true,
                    order = 3,
                    args = positioningArgs,
                }
            end)(),
        },
    }
end

local function AuraBarsOptionsTable()
    local db = ECM.db

    local spells = SpellOptionsTable()
    spells.name = ""
    spells.inline = true
    spells.order = 5

    local colors = ColoursOptionsTable()
    colors.name = ""
    colors.inline = true
    colors.order = 6

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
                            SetModuleEnabled("BuffBars", val)
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
                        values = POSITION_MODE_TEXT,
                        get = function() return db.profile.buffBars.anchorMode end,
                        set = function(_, val)
                            ApplyPositionModeToBar(db.profile.buffBars, val)
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
                local positioningSettings = MakePositioningSettingsArgs("buffBars", {
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
            colors = colors,
        },
    }
end

--------------------------------------------------------------------------------
-- Spell Options (top-level section for per-spell color customization)
--------------------------------------------------------------------------------
SpellOptionsTable = function()
    local db = ECM.db
    return {
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
                name = "Customize colors for individual spells. Colors are saved per class and spec. Spells will appear here after they've been visible at least once.\n\n",
                order = 2,
                fontSize = "medium",
            },
            currentSpec = {
                type = "description",
                name = function()
                    local _, _, className, specName = GetCurrentClassSpec()
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
                    local c = db.profile.buffBars.colors.defaultColor
                    return c.r, c.g, c.b
                end,
                set = function(_, r, g, b)
                    db.profile.buffBars.colors.defaultColor = { r = r, g = g, b = b, a = 1 }
                    ECM.ScheduleLayoutUpdate(0)
                end,
            },
            defaultColorReset = {
                type = "execute",
                name = "X",
                desc = "Reset to default",
                order = 11,
                width = 0.3,
                hidden = function() return not IsValueChanged("buffBars.colors.defaultColor") end,
                func = MakeResetHandler("buffBars.colors.defaultColor"),
            },

            spellColorsGroup = {
                type = "group",
                name = "",
                order = 30,
                inline = true,
                args = {},
            },
        },
    }
end

--------------------------------------------------------------------------------
-- Colours Options (top-level section for per-bar color customization)
--------------------------------------------------------------------------------
ColoursOptionsTable = function()
    local db = ECM.db
    return {
        type = "group",
        name = "Colours",
        order = 3,
        args = {
            header = {
                type = "header",
                name = "Per-bar Colors",
                order = 1,
            },
            desc = {
                type = "description",
                name = "Customize colors for individual buff bars. Colors are saved per class and spec. Bars appear here after they've been visible at least once.\n\n",
                order = 2,
                fontSize = "medium",
            },
            currentSpec = {
                type = "description",
                name = function()
                    local _, _, className, specName = GetCurrentClassSpec()
                    return "|cff00ff00Current: " .. (className or "Unknown") .. " " .. specName .. "|r"
                end,
                order = 3,
            },
            spacer1 = {
                type = "description",
                name = " ",
                order = 4,
            },
            refreshBarList = {
                type = "execute",
                name = "Refresh Bar List",
                desc = "Scan current buffs to update the bar list below.",
                order = 21,
                width = "normal",
                func = function()
                    local buffBars = ECM.BuffBars
                    if buffBars then
                        buffBars:ResetStyledMarkers()
                        buffBars:UpdateLayout()
                    end
                    AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
                end,
            },
            barColorsGroup = {
                type = "group",
                name = "",
                order = 30,
                inline = true,
                args = {},
            },
        },
    }
end

--- Generates dynamic per-spell color options.
---@return table args
local function GenerateSpellColorArgs()
    local args = {}
    local buffBars = ECM.BuffBars
    local db = ECM.db
    if not buffBars then
        return args
    end

    local cachedBars = buffBars:GetCachedBars()
    if not cachedBars or not next(cachedBars) then
        args.noData = {
            type = "description",
            name = "|cffaaaaaa(No buff bars cached yet. Cast a buff and click 'Refresh Bar List'.)|r",
            order = 1,
        }
        return args
    end

    local spellSettings = buffBars:GetSpellSettings()

    if spellSettings then

        local spells = {}

        for spellName, v in pairs(spellSettings) do
            spells[spellName] = {}
        end

        for i, c in ipairs(cachedBars) do
            if c and c.spellName then
                spells[c.spellName] = {}
            end
        end

        local i = 1
        for spellName, v in pairs(spells) do
            local colorKey = "spellColor" .. i
            local resetKey = "spellColor" .. i .. "Reset"

            args[colorKey] = {
                type = "color",
                name = spellName,
                desc = "Color for " .. spellName,
                order = i * 10,
                width = "double",
                get = function()
                    return buffBars:GetSpellColor(spellName)
                end,
                set = function(_, r, g, b)
                    buffBars:SetSpellColor(spellName, r, g, b)
                end,
            }

            args[resetKey] = {
                type = "execute",
                name = "X",
                desc = "Reset to default",
                order = i * 10 + 1,
                width = 0.3,
                hidden = function()
                    return not buffBars:HasCustomSpellColor(spellName)
                end,
                func = function()
                    buffBars:ResetSpellColor(spellName)
                    AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
                end,
            }

            i = i + 1
        end
    end

    return args
end

-- Hook into options refresh to update bar color list
local _originalSpellOptionsTable = SpellOptionsTable
SpellOptionsTable = function()
    local result = _originalSpellOptionsTable()
    -- Inject dynamic bar color args
    if result.args and result.args.spellColorsGroup then
        result.args.spellColorsGroup.args = GenerateSpellColorArgs()
    end
    return result
end

--- Generates dynamic per-bar color options based on cached bars.
---@return table args
local function GenerateBarColorArgs()
    local args = {}
    local buffBars = ECM.BuffBars
    local db = ECM.db
    if not buffBars then
        return args
    end

    local cachedBars = buffBars:GetCachedBars()
    if not cachedBars or not next(cachedBars) then
        args.noData = {
            type = "description",
            name = "|cffaaaaaa(No buff bars cached yet. Cast a buff and click 'Refresh Bar List'.)|r",
            order = 1,
        }
        return args
    end

    -- Sort bar indices
    local indices = {}
    for idx in pairs(cachedBars) do
        table.insert(indices, idx)
    end
    table.sort(indices)

    for i, barIndex in ipairs(indices) do
        local metadata = cachedBars[barIndex]
        local displayName = "Bar " .. barIndex
        if metadata and metadata.spellName then
            displayName = "Bar " .. barIndex .. ": " .. metadata.spellName
        end

        local colorKey = "barColor" .. barIndex
        local resetKey = "barColor" .. barIndex .. "Reset"

        args[colorKey] = {
            type = "description",
            name = displayName,
            order = i * 100,
        }
    end

    return args
end
-- Hook into options refresh to update bar color list
local _originalColoursOptionsTable = ColoursOptionsTable
ColoursOptionsTable = function()
    local result = _originalColoursOptionsTable()
    -- Inject dynamic bar color args
    if result.args and result.args.barColorsGroup then
        result.args.barColorsGroup.args = GenerateBarColorArgs()
    end
    return result
end


local function ItemIconsOptionsTable()
    local db = ECM.db
    return {
        type = "group",
        name = "Item Icons",
        order = 6,
        args = {
            basicSettings = {
                type = "group",
                name = "Basic Settings",
                inline = true,
                order = 1,
                args = {
                    desc = {
                        type = "description",
                        name = "Displays icons for equipped trinkets with on-use effects and combat consumables next to the Utility Cooldown Viewer. Icon size automatically matches the viewer's Edit Mode settings.",
                        order = 1,
                        fontSize = "medium",
                    },
                    enabled = {
                        type = "toggle",
                        name = "Enable item icons",
                        order = 2,
                        width = "full",
                        get = function() return db.profile.itemIcons.enabled end,
                        set = function(_, val)
                            db.profile.itemIcons.enabled = val
                            local module = ECM:GetModule("ItemIcons", true)
                            if val then
                                if module and not module:IsEnabled() then
                                    ECM:EnableModule("ItemIcons")
                                end
                            else
                                if module and module:IsEnabled() then
                                    ECM:DisableModule("ItemIcons")
                                end
                            end
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                },
            },
            slotSettings = {
                type = "group",
                name = "Trinket Slots",
                inline = true,
                order = 2,
                args = {
                    slotsDesc = {
                        type = "description",
                        name = "Choose which trinket slots to display. Icons only appear for trinkets with on-use effects.",
                        order = 1,
                    },
                    showTrinket1 = {
                        type = "toggle",
                        name = "Show Trinket 1 (top slot)",
                        order = 2,
                        width = "full",
                        get = function() return db.profile.itemIcons.showTrinket1 end,
                        set = function(_, val)
                            db.profile.itemIcons.showTrinket1 = val
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    showTrinket2 = {
                        type = "toggle",
                        name = "Show Trinket 2 (bottom slot)",
                        order = 3,
                        width = "full",
                        get = function() return db.profile.itemIcons.showTrinket2 end,
                        set = function(_, val)
                            db.profile.itemIcons.showTrinket2 = val
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                },
            },
            consumableSettings = {
                type = "group",
                name = "Consumables",
                inline = true,
                order = 3,
                args = {
                    consumableDesc = {
                        type = "description",
                        name = "Display combat consumables you have in your bags. Only the best quality of each type is shown.",
                        order = 1,
                    },
                    showCombatPotion = {
                        type = "toggle",
                        name = "Show Combat Potion (Tempered Potion)",
                        order = 2,
                        width = "full",
                        get = function() return db.profile.itemIcons.showCombatPotion end,
                        set = function(_, val)
                            db.profile.itemIcons.showCombatPotion = val
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    showHealthPotion = {
                        type = "toggle",
                        name = "Show Health Potion (Algari/Cavedweller's)",
                        order = 3,
                        width = "full",
                        get = function() return db.profile.itemIcons.showHealthPotion end,
                        set = function(_, val)
                            db.profile.itemIcons.showHealthPotion = val
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                    showHealthstone = {
                        type = "toggle",
                        name = "Show Healthstone",
                        order = 4,
                        width = "full",
                        get = function() return db.profile.itemIcons.showHealthstone end,
                        set = function(_, val)
                            db.profile.itemIcons.showHealthstone = val
                            ECM.ScheduleLayoutUpdate(0)
                        end,
                    },
                },
            },
        },
    }
end

local function ProfileOptionsTable()
    local db = ECM.db
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
                name = "Export your current profile to share or back up. Import will replace all current settings and require a UI reload.\n\n" ..
                       "|cffff6666Note:|r The buff bar cache (spell names) is not included in exports.",
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
                    local exportString, err = ns.ImportExport.ExportCurrentProfile()
                    if not exportString then
                        ECM:Print("Export failed: " .. (err or "Unknown error"))
                        return
                    end

                    ECM:ShowExportDialog(exportString)
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
                        ECM:Print("Cannot import during combat (reload blocked)")
                        return
                    end

                    ECM:ShowImportDialog()
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
    local db = ECM.db
    local classID, specIndex = GetCurrentClassSpec()
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
    local db = ECM.db
    local classID, specIndex = GetCurrentClassSpec()
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
        powerBarCfg.ticks = { mappings = {}, defaultColor = { r = 0, g = 0, b = 0, a = 0.5 }, defaultWidth = 1 }
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
    local db = ECM.db
    local powerBarCfg = db.profile.powerBar
    if not powerBarCfg then
        db.profile.powerBar = {}
        powerBarCfg = db.profile.powerBar
    end

    local ticksCfg = powerBarCfg.ticks
    if not ticksCfg then
        powerBarCfg.ticks = { mappings = {}, defaultColor = { r = 0, g = 0, b = 0, a = 0.5 }, defaultWidth = 1 }
        ticksCfg = powerBarCfg.ticks
    end

    local newTick = {
        value = value,
        color = color or DeepCopy(ticksCfg.defaultColor),
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
    local db = ECM.db

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
                    ECM.ScheduleLayoutUpdate(0)
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
                    ECM.ScheduleLayoutUpdate(0)
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
                    ECM.ScheduleLayoutUpdate(0)
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
                    ECM.ScheduleLayoutUpdate(0)
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
                    local _, _, className, specName = GetCurrentClassSpec()
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
                    local c = db.profile.powerBar.ticks.defaultColor
                    return c.r or 0, c.g or 0, c.b or 0, c.a or 0.5
                end,
                set = function(_, r, g, b, a)
                    db.profile.powerBar.ticks.defaultColor = { r = r, g = g, b = b, a = a }
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
                get = function() return db.profile.powerBar.ticks.defaultWidth end,
                set = function(_, val)
                    db.profile.powerBar.ticks.defaultWidth = val
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
                    ECM.ScheduleLayoutUpdate(0)
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
                    ECM.ScheduleLayoutUpdate(0)
                    AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
                end,
            },
        },
    }
    return options
end

local function AboutOptionsTable()
    local db = ECM.db
    local authorColored = "|cffa855f7S|r|cff7a84f7o|r|cff6b9bf7l|r|cff4cc9f0ä|r|cff22c55er|r"
    local version = C_AddOns.GetAddOnMetadata("EnhancedCooldownManager", "Version") or "unknown"
    return {
        type = "group",
        name = "About",
        order = 8,
        args = {
            info = {
                type = "group",
                name = "Addon Information",
                inline = true,
                order = 1,
                args = {
                    author = {
                        type = "description",
                        name = "An addon by " .. authorColored,
                        order = 1,
                        fontSize = "medium",
                    },
                    version = {
                        type = "description",
                        name = "\nVersion: " .. version,
                        order = 2,
                        fontSize = "medium",
                    },
                },
            },
            troubleshooting = {
                type = "group",
                name = "Troubleshooting",
                inline = true,
                order = 2,
                args = {
                    debugDesc = {
                        type = "description",
                        name = "Enable trace logging for bug reports. This will generate more detailed logs in the chat window.",
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
                order = 3,
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
                        hidden = function() return not IsValueChanged("global.updateFrequency") end,
                        func = MakeResetHandler("global.updateFrequency"),
                    },
                },
            },
            reset = {
                type = "group",
                name = "Reset Settings",
                inline = true,
                order = 4,
                args = {
                    resetDesc = {
                        type = "description",
                        name = "Reset all Enhanced Cooldown Manager settings to their default values and reload the UI. This action cannot be undone.",
                        order = 1,
                    },
                    resetAll = {
                        type = "execute",
                        name = "Reset Everything to Default",
                        order = 2,
                        width = "full",
                        confirm = true,
                        confirmText = "This will reset ALL Enhanced Cooldown Manager settings to their defaults and reload the UI. This cannot be undone. Are you sure?",
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
        name = "Enhanced Cooldown Manager",
        childGroups = "tree",
        args = {
            general = GeneralOptionsTable(),
            powerBar = PowerBarOptionsTable(),
            resourceBar = ResourceBarOptionsTable(),
            runeBar = RuneBarOptionsTable(),
            auraBars = AuraBarsOptionsTable(),
            itemIcons = ItemIconsOptionsTable(),
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

    -- Apply custom styling to the options frame when shown
    if self.optionsFrame then
        self.optionsFrame:HookScript("OnShow", function(frame)
            self:StyleOptionsFrame(frame)
        end)
    end

    -- Register callbacks for profile changes to refresh bars
    local db = ECM.db
    db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
end

function Options:OnProfileChanged()
    ECM.ScheduleLayoutUpdate(0)
    AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
end

function Options:OnEnable()
    -- Nothing special needed
end

function Options:OnDisable()
    -- Nothing special needed
end

--------------------------------------------------------------------------------
-- Apply custom styling to AceConfigDialog frame
--------------------------------------------------------------------------------
function Options:StyleOptionsFrame(frame)
    -- Find the tree group and style the sidebar
    C_Timer.After(0.05, function()
        self:ApplySidebarStyling()
    end)
end

function Options:ApplySidebarStyling()
    -- The tree is inside the options container
    local container = self.optionsFrame and self.optionsFrame.obj
    if not container then return end

    -- Try to find the tree frame
    local treeframe = container.treeframe
    if not treeframe then return end

    -- Apply dark background with rounded borders using backdrop
    if not treeframe.ecmStyled then
        treeframe.ecmStyled = true

        -- Create a backdrop frame for rounded corners
        local backdropFrame = CreateFrame("Frame", nil, treeframe, "BackdropTemplate")
        backdropFrame:SetAllPoints()
        backdropFrame:SetFrameLevel(treeframe:GetFrameLevel() - 1)
        backdropFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        backdropFrame:SetBackdropColor(SIDEBAR_BG_COLOR.r, SIDEBAR_BG_COLOR.g, SIDEBAR_BG_COLOR.b, SIDEBAR_BG_COLOR.a)
        backdropFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    end
end

--------------------------------------------------------------------------------
-- Slash command to open options
--------------------------------------------------------------------------------
function Options:OpenOptions()
    if self.optionsFrame then
        Settings.OpenToCategory(self.optionsFrame.name)
    end
end
