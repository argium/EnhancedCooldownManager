---@class ECMOptionsModule
local _, ns = ...

local EnhancedCooldownManager = ns.Addon
local Util = ns.Util
local Options = EnhancedCooldownManager:NewModule("Options")

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")
local LSM = LibStub("LibSharedMedia-3.0", true)

-- Constants
local SIDEBAR_BG_COLOR = { 0.1, 0.1, 0.1, 0.9 }

--------------------------------------------------------------------------------
-- Utility: Deep compare for detecting changes from defaults
--------------------------------------------------------------------------------
local function DeepEquals(a, b)
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
local function GetNestedValue(tbl, path)
    local current = tbl
    for segment in path:gmatch("[^.]+") do
        if type(current) ~= "table" then return nil end
        current = current[segment]
    end
    return current
end

--------------------------------------------------------------------------------
-- Utility: Set nested value in table using dot-separated path
--------------------------------------------------------------------------------
local function SetNestedValue(tbl, path, value)
    local segments = {}
    for segment in path:gmatch("[^.]+") do
        table.insert(segments, segment)
    end
    local current = tbl
    for i = 1, #segments - 1 do
        local key = segments[i]
        if tonumber(key) then key = tonumber(key) end
        if current[key] == nil then
            current[key] = {}
        end
        current = current[key]
    end
    local lastKey = segments[#segments]
    if tonumber(lastKey) then lastKey = tonumber(lastKey) end
    current[lastKey] = value
end

--------------------------------------------------------------------------------
-- Utility: Check if value differs from default
--------------------------------------------------------------------------------
local function IsValueChanged(path)
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local defaults = ns.defaults and ns.defaults.profile
    if not profile or not defaults then return false end

    local currentVal = GetNestedValue(profile, path)
    local defaultVal = GetNestedValue(defaults, path)

    return not DeepEquals(currentVal, defaultVal)
end

--------------------------------------------------------------------------------
-- Utility: Reset value to default
--------------------------------------------------------------------------------
local function ResetToDefault(path)
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local defaults = ns.defaults and ns.defaults.profile
    if not profile or not defaults then return end

    local defaultVal = GetNestedValue(defaults, path)
    -- Deep copy for tables (recursive to handle nested tables)
    SetNestedValue(profile, path, DeepCopy(defaultVal))
end

--------------------------------------------------------------------------------
-- Refresh all bar modules
--------------------------------------------------------------------------------
local function RefreshAllBars()
    for _, modName in ipairs({ "PowerBars", "SegmentBar", "BuffBars" }) do
        local mod = EnhancedCooldownManager[modName]
        if mod and mod.UpdateLayout then
            mod:UpdateLayout()
        end
    end
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

local function GetLSMFontValues()
    return GetLSMValues("font", "Friz Quadrata TT")
end

--------------------------------------------------------------------------------
-- Utility: Get current class and spec, localised.
--------------------------------------------------------------------------------

--- Gets current class and spec IDs.
---@return number|nil classID
---@return number|nil specID
---@return string className
---@return string specName
local function GetCurrentClassSpec()
    local localisedClassName, className, classID = UnitClass("player")
    local specIndex = GetSpecialization()
    local specID, specName
    if specIndex then
        specID, specName = GetSpecializationInfo(specIndex)
    end
    return classID, specID, localisedClassName or "Unknown", specName or "None"
end


--------------------------------------------------------------------------------
-- Options table generators for each section
--------------------------------------------------------------------------------
local function MakeResetHandler(path, refreshFunc)
    return function()
        ResetToDefault(path)
        if refreshFunc then refreshFunc() end
        RefreshAllBars()
        AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
    end
end

local function GeneralOptionsTable()
    local db = EnhancedCooldownManager.db
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
                        name = "Automatically hide icons and bars when mounted and show them when dismounted.",
                        order = 3,
                    },
                    hideWhenMounted = {
                        type = "toggle",
                        name = "Hide when mounted",
                        order = 4,
                        width = "full",
                        get = function() return db.profile.hideWhenMounted end,
                        set = function(_, val)
                            db.profile.hideWhenMounted = val
                            RefreshAllBars()
                        end,
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
                        get = function() return db.profile.offsetY end,
                        set = function(_, val)
                            db.profile.offsetY = val
                            RefreshAllBars()
                        end,
                    },
                    offsetYReset = {
                        type = "execute",
                        name = "X",
                        order = 3,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("offsetY") end,
                        func = MakeResetHandler("offsetY"),
                    },
                },
            },
            widthSettings = {
                type = "group",
                name = "Width",
                inline = true,
                order = 3,
                args = {
                    autoWidthDesc = {
                        type = "description",
                        name = "Automatically resize bars to match the cooldown manager width.",
                        order = 1,
                    },
                    autoWidth = {
                        type = "toggle",
                        name = "Automatically resize to match cooldown manager",
                        order = 2,
                        width = "full",
                        get = function() return db.profile.width.auto end,
                        set = function(_, val)
                            db.profile.width.auto = val
                            RefreshAllBars()
                        end,
                    },
                    widthDesc = {
                        type = "description",
                        name = "\nWidth of bars when automatic resizing is disabled.",
                        order = 3,
                    },
                    widthValue = {
                        type = "range",
                        name = "Width",
                        order = 4,
                        width = "double",
                        min = 150,
                        max = 600,
                        step = 1,
                        disabled = function() return db.profile.width.auto end,
                        get = function() return db.profile.width.value end,
                        set = function(_, val)
                            db.profile.width.value = val
                            RefreshAllBars()
                        end,
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
                        name = "Automatically fade icons and bars in and out when you enter and leave combat.",
                        order = 1,
                    },
                    combatFadeEnabled = {
                        type = "toggle",
                        name = "Fade when out of combat",
                        order = 2,
                        width = "full",
                        get = function() return db.profile.combatFade.enabled end,
                        set = function(_, val)
                            db.profile.combatFade.enabled = val
                            if ns.UpdateCombatFade then
                                ns.UpdateCombatFade()
                            end
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
                        disabled = function() return not db.profile.combatFade.enabled end,
                        get = function() return db.profile.combatFade.opacity end,
                        set = function(_, val)
                            db.profile.combatFade.opacity = val
                            if ns.UpdateCombatFade then
                                ns.UpdateCombatFade()
                            end
                        end,
                    },
                    combatFadeOpacityReset = {
                        type = "execute",
                        name = "X",
                        order = 5,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("combatFade.opacity") end,
                        disabled = function() return not db.profile.combatFade.enabled end,
                        func = MakeResetHandler("combatFade.opacity", function()
                            if ns.UpdateCombatFade then
                                ns.UpdateCombatFade()
                            end
                        end),
                    },
                    combatFadeExceptInInstanceDesc = {
                        type = "description",
                        name = "\nWhen enabled, bars will not fade in instanced content (raids, dungeons, battlegrounds, arenas).",
                        order = 6,
                    },
                    combatFadeExceptInInstance = {
                        type = "toggle",
                        name = "Don't fade in instances",
                        order = 7,
                        width = "full",
                        disabled = function() return not db.profile.combatFade.enabled end,
                        get = function() return db.profile.combatFade.exceptInInstance end,
                        set = function(_, val)
                            db.profile.combatFade.exceptInInstance = val
                            if ns.UpdateCombatFade then
                                ns.UpdateCombatFade()
                            end
                        end,
                    },
                },
            },
        },
    }
end

local function BarDefaultsArgs()
    local db = EnhancedCooldownManager.db
    return {
        barAppearance = {
            type = "group",
            name = "Bar Appearance",
            inline = true,
            order = 1,
            args = {
                desc = {
                    type = "description",
                    name = "These settings apply to all bars unless overridden in individual bar settings.",
                    order = 1,
                },
                barHeightDesc = {
                    type = "description",
                    name = "\nDefault height for all bars in pixels.",
                    order = 2,
                },
                barHeight = {
                    type = "range",
                    name = "Bar Height",
                    order = 3,
                    width = "double",
                    min = 8,
                    max = 40,
                    step = 1,
                    get = function() return db.profile.global.barHeight end,
                    set = function(_, val)
                        db.profile.global.barHeight = val
                        RefreshAllBars()
                    end,
                },
                barHeightReset = {
                    type = "execute",
                    name = "X",
                    order = 4,
                    width = 0.3,
                    hidden = function() return not IsValueChanged("global.barHeight") end,
                    func = MakeResetHandler("global.barHeight"),
                },

                textureDesc = {
                    type = "description",
                    name = "\nDefault statusbar texture for all bars.",
                    order = 5,
                },
                texture = {
                    type = "select",
                    name = "Bar Texture",
                    order = 6,
                    width = "double",
                    dialogControl = LSM and "LSM30_Statusbar" or nil,
                    values = GetLSMStatusbarValues,
                    get = function() return db.profile.global.texture end,
                    set = function(_, val)
                        db.profile.global.texture = val
                        RefreshAllBars()
                    end,
                },
                textureReset = {
                    type = "execute",
                    name = "X",
                    order = 7,
                    width = 0.3,
                    hidden = function()
                        local current = db.profile.global.texture
                        local default = ns.GetDefaultTexture and ns.GetDefaultTexture()
                        return current == default
                    end,
                    func = function()
                        db.profile.global.texture = ns.GetDefaultTexture and ns.GetDefaultTexture()
                        RefreshAllBars()
                        AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
                    end,
                },
                barBgColorDesc = {
                    type = "description",
                    name = "\nDefault background colour for all bars.",
                    order = 8,
                },
                barBgColor = {
                    type = "color",
                    name = "Background Colour",
                    order = 9,
                    width = "double",
                    hasAlpha = true,
                    get = function()
                        local c = db.profile.global.barBgColor
                        return c[1], c[2], c[3], c[4] or 1
                    end,
                    set = function(_, r, g, b, a)
                        db.profile.global.barBgColor = { r, g, b, a }
                        RefreshAllBars()
                    end,
                },
                barBgColorReset = {
                    type = "execute",
                    name = "X",
                    order = 10,
                    width = 0.3,
                    hidden = function() return not IsValueChanged("global.barBgColor") end,
                    func = MakeResetHandler("global.barBgColor"),
                },
            },
        },
        fontSettings = {
            type = "group",
            name = "Font Style",
            inline = true,
            order = 2,
            args = {
                fontDesc = {
                    type = "description",
                    name = "Default font for all bar text.",
                    order = 1,
                },
                font = {
                    type = "select",
                    name = "Font",
                    order = 2,
                    width = "double",
                    dialogControl = LSM and "LSM30_Font" or nil,
                    values = GetLSMFontValues,
                    get = function() return db.profile.global.font end,
                    set = function(_, val)
                        db.profile.global.font = val
                        RefreshAllBars()
                    end,
                },
                fontReset = {
                    type = "execute",
                    name = "X",
                    order = 3,
                    width = 0.3,
                    hidden = function() return not IsValueChanged("global.font") end,
                    func = MakeResetHandler("global.font"),
                },
                fontSize = {
                    type = "range",
                    name = "Font Size",
                    order = 4,
                    width = "double",
                    min = 6,
                    max = 24,
                    step = 1,
                    get = function() return db.profile.global.fontSize end,
                    set = function(_, val)
                        db.profile.global.fontSize = val
                        RefreshAllBars()
                    end,
                },
                fontSizeReset = {
                    type = "execute",
                    name = "X",
                    order = 5,
                    width = 0.3,
                    hidden = function() return not IsValueChanged("global.fontSize") end,
                    func = MakeResetHandler("global.fontSize"),
                },
                fontOutline = {
                    type = "select",
                    name = "Font outline",
                    order = 6,
                    width = "double",
                    values = {
                        ["NONE"] = "None",
                        ["OUTLINE"] = "Outline",
                        ["THICKOUTLINE"] = "Thick Outline",
                        ["MONOCHROME"] = "Monochrome",
                    },
                    get = function() return db.profile.global.fontOutline end,
                    set = function(_, val)
                        db.profile.global.fontOutline = val
                        RefreshAllBars()
                    end,
                },
                fontOutlineReset = {
                    type = "execute",
                    name = "X",
                    order = 7,
                    width = 0.3,
                    hidden = function() return not IsValueChanged("global.fontOutline") end,
                    func = MakeResetHandler("global.fontOutline"),
                },
                fontShadowDesc = {
                    type = "description",
                    name = "\nAdd a shadow behind bar text for better readability.",
                    order = 8,
                },
                fontShadow = {
                    type = "toggle",
                    name = "Enable font shadow",
                    order = 9,
                    width = "full",
                    get = function() return db.profile.global.fontShadow end,
                    set = function(_, val)
                        db.profile.global.fontShadow = val
                        RefreshAllBars()
                    end,
                }
            },
        },
    }
end

-- Forward declarations (these are defined later, but referenced by option-table builders)
local TickMarksOptionsTable
local ColoursOptionsTable

local function PowerBarOptionsTable()
    local db = EnhancedCooldownManager.db
    local tickMarks = TickMarksOptionsTable()
    tickMarks.name = "Tick Marks"
    tickMarks.inline = true
    tickMarks.order = 3
    return {
        type = "group",
        name = "Power Bar",
        order = 3,
        args = {
            basicSettings = {
                type = "group",
                name = "Basic Settings",
                inline = true,
                order = 1,
                args = {
                    desc = {
                        type = "description",
                        name = "Settings for the primary resource bar (mana, rage, energy, runic power, etc.).",
                        order = 1,
                    },
                    enabled = {
                        type = "toggle",
                        name = "Enable power bar",
                        order = 2,
                        width = "full",
                        get = function() return db.profile.powerBar.enabled end,
                        set = function(_, val)
                            db.profile.powerBar.enabled = val
                            RefreshAllBars()
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
                            RefreshAllBars()
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
                            RefreshAllBars()
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
                            RefreshAllBars()
                        end,
                    },
                },
            },
            tickMarks = tickMarks,
        },
    }
end

local function SegmentBarOptionsTable()
    local db = EnhancedCooldownManager.db
    return {
        type = "group",
        name = "Segment Bar",
        order = 4,
        args = {
            basicSettings = {
                type = "group",
                name = "Basic Settings",
                inline = true,
                order = 1,
                args = {
                    desc = {
                        type = "description",
                        name = "Settings for segmented resources (Death Knight runes, combo points, Holy Power, Demon Hunter souls).",
                        order = 1,
                    },
                    enabledDesc = {
                        type = "description",
                        name = "\nShow the segment bar.",
                        order = 2,
                    },
                    enabled = {
                        type = "toggle",
                        name = "Enable segment bar",
                        order = 3,
                        width = "full",
                        get = function() return db.profile.segmentBar.enabled end,
                        set = function(_, val)
                            db.profile.segmentBar.enabled = val
                            RefreshAllBars()
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
                        get = function() return db.profile.segmentBar.height or 0 end,
                        set = function(_, val)
                            db.profile.segmentBar.height = val > 0 and val or nil
                            RefreshAllBars()
                        end,
                    },
                    heightReset = {
                        type = "execute",
                        name = "X",
                        order = 6,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("segmentBar.height") end,
                        func = MakeResetHandler("segmentBar.height"),
                    },
                },
            },
            segmentColors = {
                type = "group",
                name = "Colours",
                inline = true,
                order = 2,
                args = {
                    desc = {
                        type = "description",
                        name = "Customize the color for each segment type. These settings only apply to the relevant class/spec.\n\n",
                        order = 1,
                        fontSize = "medium",
                    },
                    colorDemonHunterSouls = {
                        type = "color",
                        name = "Demon Hunter Souls",
                        order = 6,
                        width = "double",
                        get = function()
                            local c = db.profile.segmentBar.colors.souls
                            return c[1], c[2], c[3]
                        end,
                        set = function(_, r, g, b)
                            db.profile.segmentBar.colors.souls = { r, g, b }
                            RefreshAllBars()
                        end,
                    },
                    colorDemonHunterSoulsReset = {
                        type = "execute",
                        name = "X",
                        order = 7,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("segmentBar.colors.souls") end,
                        func = MakeResetHandler("segmentBar.colors.souls"),
                    },
                    colorComboPoints = {
                        type = "color",
                        name = "Combo Points",
                        order = 9,
                        width = "double",
                        get = function()
                            local c = db.profile.segmentBar.colors[Enum.PowerType.ComboPoints]
                            return c[1], c[2], c[3]
                        end,
                        set = function(_, r, g, b)
                            db.profile.segmentBar.colors[Enum.PowerType.ComboPoints] = { r, g, b }
                            RefreshAllBars()
                        end,
                    },
                    colorComboPointsReset = {
                        type = "execute",
                        name = "X",
                        order = 10,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("segmentBar.colors." .. Enum.PowerType.ComboPoints) end,
                        func = MakeResetHandler("segmentBar.colors." .. Enum.PowerType.ComboPoints),
                    },
                    colorChi = {
                        type = "color",
                        name = "Chi",
                        order = 12,
                        width = "double",
                        get = function()
                            local c = db.profile.segmentBar.colors[Enum.PowerType.Chi]
                            return c[1], c[2], c[3]
                        end,
                        set = function(_, r, g, b)
                            db.profile.segmentBar.colors[Enum.PowerType.Chi] = { r, g, b }
                            RefreshAllBars()
                        end,
                    },
                    colorChiReset = {
                        type = "execute",
                        name = "X",
                        order = 13,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("segmentBar.colors." .. Enum.PowerType.Chi) end,
                        func = MakeResetHandler("segmentBar.colors." .. Enum.PowerType.Chi),
                    },
                    colorHolyPower = {
                        type = "color",
                        name = "Holy Power",
                        order = 15,
                        width = "double",
                        get = function()
                            local c = db.profile.segmentBar.colors[Enum.PowerType.HolyPower]
                            return c[1], c[2], c[3]
                        end,
                        set = function(_, r, g, b)
                            db.profile.segmentBar.colors[Enum.PowerType.HolyPower] = { r, g, b }
                            RefreshAllBars()
                        end,
                    },
                    colorHolyPowerReset = {
                        type = "execute",
                        name = "X",
                        order = 16,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("segmentBar.colors." .. Enum.PowerType.HolyPower) end,
                        func = MakeResetHandler("segmentBar.colors." .. Enum.PowerType.HolyPower),
                    },
                    colorSoulShards = {
                        type = "color",
                        name = "Soul Shards",
                        order = 18,
                        width = "double",
                        get = function()
                            local c = db.profile.segmentBar.colors[Enum.PowerType.SoulShards]
                            return c[1], c[2], c[3]
                        end,
                        set = function(_, r, g, b)
                            db.profile.segmentBar.colors[Enum.PowerType.SoulShards] = { r, g, b }
                            RefreshAllBars()
                        end,
                    },
                    colorSoulShardsReset = {
                        type = "execute",
                        name = "X",
                        order = 19,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("segmentBar.colors." .. Enum.PowerType.SoulShards) end,
                        func = MakeResetHandler("segmentBar.colors." .. Enum.PowerType.SoulShards),
                    },
                    colorEssence = {
                        type = "color",
                        name = "Essence",
                        order = 21,
                        width = "double",
                        get = function()
                            local c = db.profile.segmentBar.colors[Enum.PowerType.Essence]
                            return c[1], c[2], c[3]
                        end,
                        set = function(_, r, g, b)
                            db.profile.segmentBar.colors[Enum.PowerType.Essence] = { r, g, b }
                            RefreshAllBars()
                        end,
                    },
                    colorEssenceReset = {
                        type = "execute",
                        name = "X",
                        order = 22,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("segmentBar.colors." .. Enum.PowerType.Essence) end,
                        func = MakeResetHandler("segmentBar.colors." .. Enum.PowerType.Essence),
                    },
                },
            },
        },
    }
end

local function AuraBarsOptionsTable()
    local db = EnhancedCooldownManager.db
    local colours = ColoursOptionsTable()
    colours.name = ""
    colours.inline = true
    colours.order = 5

    return {
        type = "group",
        name = "Aura Bars",
        order = 4,
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
                    showIcon = {
                        type = "toggle",
                        name = "Show icon",
                        order = 3,
                        width = "full",
                        get = function() return db.profile.dynamicBars.showIcon end,
                        set = function(_, val)
                            db.profile.dynamicBars.showIcon = val
                            RefreshAllBars()
                        end,
                    },
                    showSpellName = {
                        type = "toggle",
                        name = "Show spell name",
                        order = 5,
                        width = "full",
                        get = function() return db.profile.dynamicBars.showSpellName end,
                        set = function(_, val)
                            db.profile.dynamicBars.showSpellName = val
                            RefreshAllBars()
                        end,
                    },
                    showDuration = {
                        type = "toggle",
                        name = "Show remaining duration",
                        order = 7,
                        width = "full",
                        get = function() return db.profile.dynamicBars.showDuration end,
                        set = function(_, val)
                            db.profile.dynamicBars.showDuration = val
                            RefreshAllBars()
                        end,
                    },
                },
            },
            positioningSettings = {
                type = "group",
                name = "Positioning",
                inline = true,
                order = 2,
                args = {
                    autoPositionDesc = {
                        type = "description",
                        name = "When enabled, the buff bar viewer is automatically anchored below the other ECM bars. When disabled, you can position it freely using Blizzard's Edit Mode.",
                        order = 1,
                        fontSize = "medium",
                    },
                    autoPosition = {
                        type = "toggle",
                        name = "Automatically Position Below Other Bars",
                        order = 2,
                        width = "full",
                        get = function() return db.profile.buffBars.autoPosition end,
                        set = function(_, val)
                            db.profile.buffBars.autoPosition = val
                            RefreshAllBars()
                        end,
                    },
                    barWidthDesc = {
                        type = "description",
                        name = "\nWidth of the buff bars when automatic positioning is disabled.",
                        order = 3,
                    },
                    barWidth = {
                        type = "range",
                        name = "Buff Bar Width",
                        order = 4,
                        width = "double",
                        min = 100,
                        max = 600,
                        step = 10,
                        disabled = function() return db.profile.buffBars.autoPosition end,
                        get = function() return db.profile.buffBars.barWidth end,
                        set = function(_, val)
                            db.profile.buffBars.barWidth = val
                            RefreshAllBars()
                        end,
                    },
                    barWidthReset = {
                        type = "execute",
                        name = "X",
                        order = 5,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("buffBars.barWidth") end,
                        disabled = function() return db.profile.buffBars.autoPosition end,
                        func = MakeResetHandler("buffBars.barWidth"),
                    },
                },
            },
            colours = colours,
        },
    }
end

--------------------------------------------------------------------------------
-- Colours Options (top-level section for per-bar color customization)
--------------------------------------------------------------------------------
ColoursOptionsTable = function()
    local db = EnhancedCooldownManager.db
    return {
        type = "group",
        name = "Colours",
        order = 3,
        args = {
            header = {
                type = "header",
                name = "Per-bar Colours",
                order = 1,
            },
            desc = {
                type = "description",
                name = "Customize colours for individual buff bars. Colours are saved per class and spec. Bars appear here after they've been visible at least once.\n\n",
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
                name = "Default colour",
                desc = "Default colour for bars without custom colours.",
                order = 10,
                width = "double",
                get = function()
                    local c = db.profile.buffBarColors.defaultColor
                    return c[1], c[2], c[3]
                end,
                set = function(_, r, g, b)
                    db.profile.buffBarColors.defaultColor = { r, g, b }
                    RefreshAllBars()
                end,
            },
            defaultColorReset = {
                type = "execute",
                name = "X",
                desc = "Reset to default",
                order = 11,
                width = 0.3,
                hidden = function() return not IsValueChanged("buffBarColors.defaultColor") end,
                func = MakeResetHandler("buffBarColors.defaultColor"),
            },

            refreshBarList = {
                type = "execute",
                name = "Refresh Bar List",
                desc = "Scan current buffs to update the bar list below.",
                order = 21,
                width = "normal",
                func = function()
                    local buffBars = EnhancedCooldownManager.BuffBars
                    if buffBars then
                        buffBars:ResetStyledMarkers()
                        buffBars:RescanBars()
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

--- Generates dynamic per-bar color options based on cached bars.
---@return table args AceConfig args table
local function GenerateBarColorArgs()
    local args = {}
    local buffBars = EnhancedCooldownManager.BuffBars
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
            type = "color",
            name = displayName,
            desc = "Color for bar at position " .. barIndex,
            order = i * 10,
            width = "double",
            get = function()
                return buffBars:GetBarColor(barIndex)
            end,
            set = function(_, r, g, b)
                buffBars:SetBarColor(barIndex, r, g, b)
            end,
        }

        args[resetKey] = {
            type = "execute",
            name = "X",
            desc = "Reset to default",
            order = i * 10 + 1,
            width = 0.3,
            hidden = function()
                return not buffBars:HasCustomBarColor(barIndex)
            end,
            func = function()
                buffBars:ResetBarColor(barIndex)
                AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
            end,
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


local function ProfileOptionsTable()
    local db = EnhancedCooldownManager.db
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
                        EnhancedCooldownManager:Print("Export failed: " .. (err or "Unknown error"))
                        return
                    end

                    EnhancedCooldownManager:ShowExportDialog(exportString)
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
                        EnhancedCooldownManager:Print("Cannot import during combat (reload blocked)")
                        return
                    end

                    EnhancedCooldownManager:ShowImportDialog()
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
    local db = EnhancedCooldownManager.db
    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then
        return {}
    end

    local ticksCfg = db.profile.powerBarTicks
    if not ticksCfg or not ticksCfg.mappings then
        return {}
    end

    local classMappings = ticksCfg.mappings[classID]
    if not classMappings then
        return {}
    end

    return classMappings[specID] or {}
end

--- Sets tick marks for the current class/spec.
---@param ticks ECM_TickMark[]
local function SetCurrentTicks(ticks)
    local db = EnhancedCooldownManager.db
    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then
        return
    end

    local ticksCfg = db.profile.powerBarTicks
    if not ticksCfg then
        db.profile.powerBarTicks = { mappings = {}, defaultColor = { 0, 0, 0, 0.5 }, defaultWidth = 1 }
        ticksCfg = db.profile.powerBarTicks
    end
    if not ticksCfg.mappings then
        ticksCfg.mappings = {}
    end
    if not ticksCfg.mappings[classID] then
        ticksCfg.mappings[classID] = {}
    end

    ticksCfg.mappings[classID][specID] = ticks
end

--- Adds a new tick mark for the current class/spec.
---@param value number
---@param color number[]|nil
---@param width number|nil
local function AddTick(value, color, width)
    local ticks = GetCurrentTicks()
    local db = EnhancedCooldownManager.db
    local ticksCfg = db.profile.powerBarTicks

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
    local db = EnhancedCooldownManager.db

    --- Generates per-tick options dynamically.
    local function GenerateTickArgs()
        local args = {}
        local ticks = GetCurrentTicks()
        local ticksCfg = db.profile.powerBarTicks

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
                    RefreshAllBars()
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
                    RefreshAllBars()
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
                    return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 0.5
                end,
                set = function(_, r, g, b, a)
                    UpdateTick(i, "color", { r, g, b, a })
                    RefreshAllBars()
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
                    RefreshAllBars()
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
                name = "Default  color",
                desc = "Default color for new tick marks.",
                order = 10,
                width = "normal",
                hasAlpha = true,
                get = function()
                    local c = db.profile.powerBarTicks.defaultColor
                    return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 0.5
                end,
                set = function(_, r, g, b, a)
                    db.profile.powerBarTicks.defaultColor = { r, g, b, a }
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
                get = function() return db.profile.powerBarTicks.defaultWidth end,
                set = function(_, val)
                    db.profile.powerBarTicks.defaultWidth = val
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
                    RefreshAllBars()
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
                    RefreshAllBars()
                    AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
                end,
            },
        },
    }
    return options
end

local function AboutOptionsTable()
    local db = EnhancedCooldownManager.db
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
                        get = function() return db.profile.updateFrequency end,
                        set = function(_, val) db.profile.updateFrequency = val end,
                    },
                    updateFrequencyReset = {
                        type = "execute",
                        name = "X",
                        order = 3,
                        width = 0.3,
                        hidden = function() return not IsValueChanged("updateFrequency") end,
                        func = MakeResetHandler("updateFrequency"),
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
            segmentBar = SegmentBarOptionsTable(),
            auraBars = AuraBarsOptionsTable(),
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
    local db = EnhancedCooldownManager.db
    db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
end

function Options:OnProfileChanged()
    RefreshAllBars()
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
        backdropFrame:SetBackdropColor(SIDEBAR_BG_COLOR[1], SIDEBAR_BG_COLOR[2], SIDEBAR_BG_COLOR[3], SIDEBAR_BG_COLOR[4])
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
