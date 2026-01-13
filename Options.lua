---@class ECMOptionsModule
local _, ns = ...

local EnhancedCooldownManager = ns.Addon
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
    local powerBars = EnhancedCooldownManager.PowerBars
    local segmentBar = EnhancedCooldownManager.SegmentBar
    local buffBars = EnhancedCooldownManager.BuffBars

    if powerBars and powerBars.UpdateLayout then
        pcall(powerBars.UpdateLayout, powerBars)
    end
    if segmentBar and segmentBar.UpdateLayout then
        pcall(segmentBar.UpdateLayout, segmentBar)
    end
    if buffBars and buffBars.UpdateLayout then
        pcall(buffBars.UpdateLayout, buffBars)
    end
end

--------------------------------------------------------------------------------
-- Build LibSharedMedia dropdown values
--------------------------------------------------------------------------------
local function GetLSMStatusbarValues()
    local values = {}
    if LSM and LSM.List then
        for _, name in ipairs(LSM:List("statusbar")) do
            values[name] = name
        end
    end
    -- Fallback if empty
    if not next(values) then
        values["Blizzard"] = "Blizzard"
    end
    return values
end

local function GetLSMFontValues()
    local values = {}
    if LSM and LSM.List then
        for _, name in ipairs(LSM:List("font")) do
            values[name] = name
        end
    end
    if not next(values) then
        values["Friz Quadrata TT"] = "Friz Quadrata TT"
    end
    return values
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
            header = {
                type = "header",
                name = "General Settings",
                order = 1,
            },
            enabled = {
                type = "toggle",
                name = "Enable Addon",
                desc = "Enable or disable the entire addon.",
                order = 10,
                width = "double",
                get = function() return db.profile.enabled end,
                set = function(_, val)
                    if val then
                        db.profile.enabled = true
                        RefreshAllBars()
                        return
                    end

                    -- Disabling requires a UI reload to fully undo hooks/styling.
                    EnhancedCooldownManager:ConfirmDisableAndReload(function()
                        -- Re-sync the toggle if the user cancels.
                        AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
                    end)

                    -- Keep the toggle visually enabled unless the user confirms.
                    AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
                end,
            },
            debug = {
                type = "toggle",
                name = "Debug Mode",
                desc = "Enable trace logging for /ecm bug reports.",
                order = 20,
                width = "double",
                get = function() return db.profile.debug end,
                set = function(_, val) db.profile.debug = val end,
            },
            hideWhenMounted = {
                type = "toggle",
                name = "Hide When Mounted",
                desc = "Hide resource bars when mounted.",
                order = 30,
                width = "double",
                get = function() return db.profile.hideWhenMounted end,
                set = function(_, val)
                    db.profile.hideWhenMounted = val
                    RefreshAllBars()
                end,
            },
            updateFrequency = {
                type = "range",
                name = "Update Frequency",
                desc = "How often bars update (seconds). Lower = smoother but more CPU.",
                order = 40,
                width = "double",
                min = 0.016,
                max = 0.2,
                step = 0.001,
                isPercent = false,
                get = function() return db.profile.updateFrequency end,
                set = function(_, val) db.profile.updateFrequency = val end,
            },
            updateFrequencyReset = {
                type = "execute",
                name = "X",
                desc = "Reset to default",
                order = 41,
                width = 0.3,
                hidden = function() return not IsValueChanged("updateFrequency") end,
                func = MakeResetHandler("updateFrequency"),
            },
            offsetY = {
                type = "range",
                name = "Vertical Offset",
                desc = "Vertical gap between the cooldown viewer and the first bar.",
                order = 50,
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
                desc = "Reset to default",
                order = 51,
                width = 0.3,
                hidden = function() return not IsValueChanged("offsetY") end,
                func = MakeResetHandler("offsetY"),
            },
        },
    }
end

local function BarDefaultsArgs()
    local db = EnhancedCooldownManager.db
    return {
        header = {
            type = "header",
            name = "Default Bar Appearance",
            order = 1,
        },
        desc = {
            type = "description",
            name = "These settings apply to all bars unless overridden below.",
            order = 2,
        },
            barHeight = {
                type = "range",
                name = "Bar Height",
                desc = "Default height for all bars in pixels.",
                order = 10,
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
                desc = "Reset to default",
                order = 11,
                width = 0.3,
                hidden = function() return not IsValueChanged("global.barHeight") end,
                func = MakeResetHandler("global.barHeight"),
            },
            texture = {
                type = "select",
                name = "Bar Texture",
                desc = "Default statusbar texture for all bars.",
                order = 20,
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
                desc = "Reset to default",
                order = 21,
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
            barBgColor = {
                type = "color",
                name = "Background Colour",
                desc = "Default background colour for all bars.",
                order = 25,
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
                desc = "Reset to default",
                order = 26,
                width = 0.3,
                hidden = function() return not IsValueChanged("global.barBgColor") end,
                func = MakeResetHandler("global.barBgColor"),
            },
            fontsHeader = {
                type = "header",
                name = "Fonts",
                order = 29,
            },
            font = {
                type = "select",
                name = "Font",
                desc = "Default font for all bar text.",
                order = 30,
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
                desc = "Reset to default",
                order = 31,
                width = 0.3,
                hidden = function() return not IsValueChanged("global.font") end,
                func = MakeResetHandler("global.font"),
            },
            fontSize = {
                type = "range",
                name = "Font Size",
                desc = "Default font size for all bar text.",
                order = 40,
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
                desc = "Reset to default",
                order = 41,
                width = 0.3,
                hidden = function() return not IsValueChanged("global.fontSize") end,
                func = MakeResetHandler("global.fontSize"),
            },
            fontOutline = {
                type = "select",
                name = "Font Outline",
                desc = "Outline style for bar text.",
                order = 42,
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
                desc = "Reset to default",
                order = 43,
                width = 0.3,
                hidden = function() return not IsValueChanged("global.fontOutline") end,
                func = MakeResetHandler("global.fontOutline"),
            },
            fontShadow = {
                type = "toggle",
                name = "Font Shadow",
                desc = "Add a shadow behind bar text for better readability.",
                order = 44,
                width = "double",
                get = function() return db.profile.global.fontShadow end,
                set = function(_, val)
                    db.profile.global.fontShadow = val
                    RefreshAllBars()
                end,
            },
            fontShadowReset = {
                type = "execute",
                name = "X",
                desc = "Reset to default",
                order = 45,
                width = 0.3,
                hidden = function() return not IsValueChanged("global.fontShadow") end,
                func = MakeResetHandler("global.fontShadow"),
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
    tickMarks.order = 41
    return {
        type = "group",
        name = "Power Bar",
        order = 2,
        args = {
            header = {
                type = "header",
                name = "Power Bar Settings",
                order = 1,
            },
            desc = {
                type = "description",
                name = "Settings specific to the primary resource bar (mana, rage, energy, etc.).",
                order = 2,
            },
            enabled = {
                type = "toggle",
                name = "Enable Power Bar",
                desc = "Show the power bar.",
                order = 10,
                width = "double",
                get = function() return db.profile.powerBar.enabled end,
                set = function(_, val)
                    db.profile.powerBar.enabled = val
                    RefreshAllBars()
                end,
            },
            height = {
                type = "range",
                name = "Height Override",
                desc = "Override the default bar height. Set to 0 to use default.",
                order = 20,
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
                desc = "Reset to default",
                order = 21,
                width = 0.3,
                hidden = function() return not IsValueChanged("powerBar.height") end,
                func = MakeResetHandler("powerBar.height"),
            },
            showText = {
                type = "toggle",
                name = "Show Text",
                desc = "Display power value text on the bar.",
                order = 30,
                width = "double",
                get = function() return db.profile.powerBar.showText end,
                set = function(_, val)
                    db.profile.powerBar.showText = val
                    RefreshAllBars()
                end,
            },
            showManaAsPercent = {
                type = "toggle",
                name = "Show Mana as Percent",
                desc = "Display mana as percentage instead of raw value.",
                order = 40,
                width = "double",
                get = function() return db.profile.powerBar.showManaAsPercent end,
                set = function(_, val)
                    db.profile.powerBar.showManaAsPercent = val
                    RefreshAllBars()
                end,
            },

            tickMarksSpacer = {
                type = "description",
                name = " ",
                order = 40.5,
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
        order = 3,
        args = {
            header = {
                type = "header",
                name = "Segment Bar Settings",
                order = 1,
            },
            desc = {
                type = "description",
                name = "Settings for segmented resources (DK runes, combo points, Holy Power, DH souls, Frost Mage icicles).",
                order = 2,
            },
            enabled = {
                type = "toggle",
                name = "Enable Segment Bar",
                desc = "Show the segment bar.",
                order = 10,
                width = "double",
                get = function() return db.profile.segmentBar.enabled end,
                set = function(_, val)
                    db.profile.segmentBar.enabled = val
                    RefreshAllBars()
                end,
            },
            height = {
                type = "range",
                name = "Height Override",
                desc = "Override the default bar height. Set to 0 to use default.",
                order = 20,
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
                desc = "Reset to default",
                order = 21,
                width = 0.3,
                hidden = function() return not IsValueChanged("segmentBar.height") end,
                func = MakeResetHandler("segmentBar.height"),
            },
            colorHeader = {
                type = "header",
                name = "Segment Colors",
                order = 40,
            },
            colorDkRunes = {
                type = "color",
                name = "Death Knight Runes",
                desc = "Color for DK rune segments.",
                order = 50,
                width = "double",
                get = function()
                    local c = db.profile.segmentBar.colorDkRunes
                    return c[1], c[2], c[3]
                end,
                set = function(_, r, g, b)
                    db.profile.segmentBar.colorDkRunes = { r, g, b }
                    RefreshAllBars()
                end,
            },
            colorDkRunesReset = {
                type = "execute",
                name = "X",
                desc = "Reset to default",
                order = 51,
                width = 0.3,
                hidden = function() return not IsValueChanged("segmentBar.colorDkRunes") end,
                func = MakeResetHandler("segmentBar.colorDkRunes"),
            },
            colorDemonHunterSouls = {
                type = "color",
                name = "Demon Hunter Souls",
                desc = "Color for DH soul segments.",
                order = 60,
                width = "double",
                get = function()
                    local c = db.profile.segmentBar.colorDemonHunterSouls
                    return c[1], c[2], c[3]
                end,
                set = function(_, r, g, b)
                    db.profile.segmentBar.colorDemonHunterSouls = { r, g, b }
                    RefreshAllBars()
                end,
            },
            colorDemonHunterSoulsReset = {
                type = "execute",
                name = "X",
                desc = "Reset to default",
                order = 61,
                width = 0.3,
                hidden = function() return not IsValueChanged("segmentBar.colorDemonHunterSouls") end,
                func = MakeResetHandler("segmentBar.colorDemonHunterSouls"),
            },
            colorComboPoints = {
                type = "color",
                name = "Combo Points",
                desc = "Color for combo point segments.",
                order = 70,
                width = "double",
                get = function()
                    local c = db.profile.segmentBar.colorComboPoints
                    return c[1], c[2], c[3]
                end,
                set = function(_, r, g, b)
                    db.profile.segmentBar.colorComboPoints = { r, g, b }
                    RefreshAllBars()
                end,
            },
            colorComboPointsReset = {
                type = "execute",
                name = "X",
                desc = "Reset to default",
                order = 71,
                width = 0.3,
                hidden = function() return not IsValueChanged("segmentBar.colorComboPoints") end,
                func = MakeResetHandler("segmentBar.colorComboPoints"),
            },
            colorFrostMageIcicles = {
                type = "color",
                name = "Frost Mage Icicles",
                desc = "Color for Frost Mage icicle segments.",
                order = 80,
                width = "double",
                get = function()
                    local c = db.profile.segmentBar.colorFrostMageIcicles
                    return c[1], c[2], c[3]
                end,
                set = function(_, r, g, b)
                    db.profile.segmentBar.colorFrostMageIcicles = { r, g, b }
                    RefreshAllBars()
                end,
            },
            colorFrostMageIciclesReset = {
                type = "execute",
                name = "X",
                desc = "Reset to default",
                order = 81,
                width = 0.3,
                hidden = function() return not IsValueChanged("segmentBar.colorFrostMageIcicles") end,
                func = MakeResetHandler("segmentBar.colorFrostMageIcicles"),
            },
        },
    }
end

local function AuraBarsOptionsTable()
    local db = EnhancedCooldownManager.db
    local colours = ColoursOptionsTable()
    colours.name = ""
    colours.inline = true
    colours.order = 100

    return {
        type = "group",
        name = "Aura Bars",
        order = 4,
        args = {
            header = {
                type = "header",
                name = "Buff Bar Settings",
                order = 1,
            },
            desc = {
                type = "description",
                name = "Settings for Blizzard's BuffBarCooldownViewer bars restyled by ECM.",
                order = 2,
            },
            showIcon = {
                type = "toggle",
                name = "Show Icon",
                desc = "Display spell icon on buff bars.",
                order = 10,
                width = "double",
                get = function() return db.profile.dynamicBars.showIcon end,
                set = function(_, val)
                    db.profile.dynamicBars.showIcon = val
                    RefreshAllBars()
                end,
            },
            showSpellName = {
                type = "toggle",
                name = "Show Spell Name",
                desc = "Display spell name on buff bars.",
                order = 20,
                width = "double",
                get = function() return db.profile.dynamicBars.showSpellName end,
                set = function(_, val)
                    db.profile.dynamicBars.showSpellName = val
                    RefreshAllBars()
                end,
            },
            showDuration = {
                type = "toggle",
                name = "Show Duration",
                desc = "Display remaining duration on buff bars.",
                order = 30,
                width = "double",
                get = function() return db.profile.dynamicBars.showDuration end,
                set = function(_, val)
                    db.profile.dynamicBars.showDuration = val
                    RefreshAllBars()
                end,
            },

            coloursSpacer = {
                type = "description",
                name = " ",
                order = 99,
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
                name = "Colours",
                order = 1,
            },
            desc = {
                type = "description",
                name = "Customize colours for individual buff bars. Colours are saved per class and spec. Bars appear here after they've been visible at least once.",
                order = 2,
            },
            currentSpec = {
                type = "description",
                name = function()
                    local spec = GetSpecialization()
                    local specName = spec and select(2, GetSpecializationInfo(spec)) or "None"
                    local _, className = UnitClass("player")
                    return "|cff00ff00Current: " .. (className or "Unknown") .. " " .. specName .. "|r"
                end,
                order = 3,
                fontSize = "medium",
            },
            defaultColor = {
                type = "color",
                name = "Default Colour",
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
            barListHeader = {
                type = "header",
                name = "Per-Bar Colours",
                order = 20,
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

local function StyleOptionsTable()
    local db = EnhancedCooldownManager.db
    local powerTypes = {
        [Enum.PowerType.Mana] = "Mana",
        [Enum.PowerType.Rage] = "Rage",
        [Enum.PowerType.Focus] = "Focus",
        [Enum.PowerType.Energy] = "Energy",
        [Enum.PowerType.RunicPower] = "Runic Power",
        [Enum.PowerType.LunarPower] = "Lunar Power",
        [Enum.PowerType.Fury] = "Fury",
        [Enum.PowerType.Maelstrom] = "Maelstrom",
        [Enum.PowerType.Essence] = "Essence",
        [Enum.PowerType.ArcaneCharges] = "Arcane Charges",
        [Enum.PowerType.Chi] = "Chi",
        [Enum.PowerType.HolyPower] = "Holy Power",
        [Enum.PowerType.SoulShards] = "Soul Shards",
    }

    local args = {}
    local defaultsArgs = BarDefaultsArgs()
    for key, value in pairs(defaultsArgs) do
        args["defaults_" .. key] = value
    end

    local powerTypeArgs = {
        desc = {
            type = "description",
            name = "Customize the color for each resource type.",
            order = 1,
        },
    }

    local order = 10
    -- Sort power types by name for consistent display
    local sortedTypes = {}
    for pt, name in pairs(powerTypes) do
        table.insert(sortedTypes, { pt = pt, name = name })
    end
    table.sort(sortedTypes, function(a, b) return a.name < b.name end)

    for _, entry in ipairs(sortedTypes) do
        local pt = entry.pt
        local name = entry.name
        local key = tostring(pt)

        powerTypeArgs["color" .. key] = {
            type = "color",
            name = name,
            order = order,
            width = "double",
            get = function()
                local c = db.profile.powerTypeColors.colors[pt]
                if c then return c[1], c[2], c[3] end
                return 1, 1, 1
            end,
            set = function(_, r, g, b)
                db.profile.powerTypeColors.colors[pt] = { r, g, b }
                RefreshAllBars()
            end,
        }
        powerTypeArgs["color" .. key .. "Reset"] = {
            type = "execute",
            name = "X",
            desc = "Reset to default",
            order = order + 1,
            width = 0.3,
            hidden = function()
                return not IsValueChanged("powerTypeColors.colors." .. key)
            end,
            func = MakeResetHandler("powerTypeColors.colors." .. key),
        }
        order = order + 10
    end

    args.powerTypeColoursSpacer = {
        type = "description",
        name = " ",
        order = 99,
    }

    args.powerTypeColours = {
        type = "group",
        name = "Power Type Colours",
        order = 100,
        inline = true,
        args = powerTypeArgs,
    }

    return {
        type = "group",
        name = "Style",
        order = 5,
        args = args,
    }
end

local function ProfileOptionsTable()
    local db = EnhancedCooldownManager.db
    -- Use AceDBOptions to generate a full profile management UI
    local profileOptions = AceDBOptions:GetOptionsTable(db)
    profileOptions.order = 7
    return profileOptions
end

--------------------------------------------------------------------------------
-- Tick Marks Options (per-class/per-spec)
--------------------------------------------------------------------------------

--- Gets current class and spec IDs.
---@return number|nil classID
---@return number|nil specID
---@return string className
---@return string specName
local function GetCurrentClassSpec()
    local _, className, classID = UnitClass("player")
    local specIndex = GetSpecialization()
    local specID, specName
    if specIndex then
        specID, specName = GetSpecializationInfo(specIndex)
    end
    return classID, specID, className or "Unknown", specName or "None"
end

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
                name = "Configure tick marks on the power bar for specific resource thresholds. " ..
                       "Settings are saved per class and specialization.\n",
                order = 2,
                fontSize = "medium",
            },
            currentSpec = {
                type = "description",
                name = function()
                    local _, _, className, specName = GetCurrentClassSpec()
                    return string.format("|cff888888Current: %s - %s|r", className, specName)
                end,
                order = 3,
            },
            spacer1 = {
                type = "description",
                name = " ",
                order = 4,
            },
            defaultsHeader = {
                type = "header",
                name = "Default Appearance",
                order = 10,
            },
            defaultColor = {
                type = "color",
                name = "Default Color",
                desc = "Default color for new tick marks.",
                order = 11,
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
                name = "Default Width",
                desc = "Default width for new tick marks.",
                order = 12,
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
            ticksHeader = {
                type = "header",
                name = "Tick Marks for Current Spec",
                order = 20,
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

--------------------------------------------------------------------------------
-- Proc Overlay Options (Experimental feature)
--------------------------------------------------------------------------------
local function ProcOverlayOptionsTable()
    local db = EnhancedCooldownManager.db
    local procOverlay = EnhancedCooldownManager.ProcOverlay

    --- Generates dropdown values for target icon indices.
    local function GetTargetIconValues()
        local values = { [0] = "None" }
        local _, targetCount = procOverlay:GetIconCounts()
        for i = 1, math.max(targetCount, 10) do
            values[i] = "Icon " .. i
        end
        return values
    end

    --- Generates per-buff-icon mapping options dynamically.
    local function GenerateMappingArgs()
        local args = {}
        local buffCount, _ = procOverlay:GetIconCounts()
        local mappings = procOverlay:GetAllMappings()

        -- Show at least 5 slots, or as many as there are buff icons
        local slotCount = math.max(buffCount, 5)

        for i = 1, slotCount do
            local currentTarget = mappings[i] or 0
            args["buffIcon" .. i] = {
                type = "select",
                name = "Buff Icon " .. i,
                desc = "Select which Essential Cooldown icon this buff should overlay when active.",
                order = i,
                width = "double",
                values = GetTargetIconValues,
                get = function()
                    return procOverlay:GetMapping(i) or 0
                end,
                set = function(_, val)
                    if val == 0 then
                        procOverlay:SetMapping(i, nil)
                    else
                        local success = procOverlay:SetMapping(i, val)
                        if not success then
                            -- Target already mapped to another buff
                            EnhancedCooldownManager:Print("Target icon " .. val .. " is already mapped to another buff icon.")
                        end
                    end
                end,
            }
        end

        return args
    end

    return {
        type = "group",
        name = "Proc Overlay",
        order = 6,
        args = {
            header = {
                type = "header",
                name = "Proc Overlay (Experimental)",
                order = 1,
            },
            description = {
                type = "description",
                name = "|cffffcc00Experimental Feature:|r When a buff icon in the Buff Icon Cooldown Viewer becomes visible, " ..
                       "it can be repositioned to overlay on top of an icon in the Essential Cooldown Viewer. " ..
                       "This creates the illusion that the ability icon has changed to show the proc.\n\n" ..
                       "|cffff6666Requirements:|r\n" ..
                       "• Buff icons must have 'Hide when inactive' enabled in Blizzard's Cooldown Viewer settings\n" ..
                       "• One buff icon can only map to one target icon\n",
                order = 2,
                fontSize = "medium",
            },
            enabled = {
                type = "toggle",
                name = "Enable Proc Overlay",
                desc = "Enable the proc overlay feature.",
                order = 10,
                width = "full",
                get = function() return db.profile.procOverlay.enabled end,
                set = function(_, val)
                    db.profile.procOverlay.enabled = val
                    procOverlay:UpdateLayout()
                end,
            },
            spacer1 = {
                type = "description",
                name = " ",
                order = 15,
            },
            mappingsHeader = {
                type = "header",
                name = "Icon Mappings",
                order = 20,
            },
            mappingsDescription = {
                type = "description",
                name = "Configure which buff icons overlay which Essential Cooldown icons. " ..
                       "Icons are numbered left-to-right starting at 1.\n",
                order = 21,
            },
            iconCounts = {
                type = "description",
                name = function()
                    local buffCount, targetCount = procOverlay:GetIconCounts()
                    return string.format("|cff888888Current visible icons: %d buff icons, %d target icons|r", buffCount, targetCount)
                end,
                order = 22,
            },
            refreshCounts = {
                type = "execute",
                name = "Refresh Icon Counts",
                desc = "Rescan visible icons in both viewers.",
                order = 23,
                width = "normal",
                func = function()
                    procOverlay:UpdateLayout()
                    AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
                end,
            },
            spacer2 = {
                type = "description",
                name = " ",
                order = 24,
            },
            mappings = {
                type = "group",
                name = "Buff Icon Mappings",
                order = 30,
                inline = true,
                args = GenerateMappingArgs(),
            },
            spacer3 = {
                type = "description",
                name = " ",
                order = 40,
            },
            clearAll = {
                type = "execute",
                name = "Clear All Mappings",
                desc = "Remove all buff-to-target icon mappings for the current spec.",
                order = 50,
                width = "normal",
                confirm = true,
                confirmText = "Are you sure you want to clear all proc overlay mappings for this spec?",
                func = function()
                    procOverlay:ClearAllMappings()
                    AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
                end,
            },
        },
    }
end

local function AboutOptionsTable()
    local authorColored = "|cffa855f7S|r|cff7a84f7o|r|cff6b9bf7l|r|cff4cc9f0ä|r|cff22c55er|r"
    local version = C_AddOns.GetAddOnMetadata("EnhancedCooldownManager", "Version")  or "unknown"
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
                name = "Version: " .. version,
                order = 2,
                fontSize = "medium",
            },
            spacer1 = {
                type = "description",
                name = " ",
                order = 3,
            },
            linksHeader = {
                type = "header",
                name = "Other Addons",
                order = 4,
            },
            -- Add links to other addons here
            -- Example:
            -- addonLink1 = {
            --     type = "description",
            --     name = "|cff4cc9f0My Other Addon|r - Description here",
            --     order = 11,
            -- },
            placeholder = {
                type = "description",
                name = "|cffaaaaaa(Coming soon)|r",
                order = 5,
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
            globalStyle = (function()
                local style = StyleOptionsTable()
                style.name = "Global Style"
                style.order = 2
                return style
            end)(),
            powerBar = PowerBarOptionsTable(),
            segmentBar = SegmentBarOptionsTable(),
            auraBars = AuraBarsOptionsTable(),
            procOverlay = ProcOverlayOptionsTable(),
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
    -- Use the stored category from AceConfigDialog
    if self.optionsFrame then
        -- Modern WoW: use the category stored by AceConfigDialog
        local categoryID = self.optionsFrame.name or "Enhanced Cooldown Manager"
        if Settings and Settings.OpenToCategory then
            -- Try using the frame's registered category
            pcall(Settings.OpenToCategory, categoryID)
        end
    end
    -- Fallback: use AceConfigDialog to open directly
    AceConfigDialog:Open("EnhancedCooldownManager")
end
