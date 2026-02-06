-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

local ECM = ns.Addon
local C = ns.Constants

local Util = ns.Util or {}
ns.Util = Util

local LSM = LibStub("LibSharedMedia-3.0", true)

local function FetchLSM(mediaType, key)
    if LSM and LSM.Fetch and key and type(key) == "string" then
        return LSM:Fetch(mediaType, key, true)
    end
    return nil
end

function Util.DebugAssert(condition, message)
    local debug = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.debug
    if not debug then
        return
    end
    assert(condition, message)
end

--- Compares two ECM_Color tables for equality.
--- @param c1 ECM_Color|nil
--- @param c2 ECM_Color|nil
--- @return boolean
function Util.AreColorsEqual(c1, c2)
    if c1 == nil and c2 == nil then
        return true
    end
    if c1 == nil or c2 == nil then
        return false
    end
    local c1m = CreateColor(c1.r, c1.g, c1.b, c1.a)
    local c2m = CreateColor(c2.r, c2.g, c2.b, c2.a)
    return c1m:IsEqualTo(c2m)
end

--- Returns a statusbar texture path (LSM-resolved when available).
---@param texture string|nil Name of the texture in LSM or a file path.
---@return string
function Util.GetTexture(texture)
    if texture and type(texture) == "string" then
        local fetched = FetchLSM("statusbar", texture)
        if fetched then
            return fetched
        end

        -- Treat it as a file path
        if texture:find("\\") then
            return texture
        end
    end

    return FetchLSM("statusbar", "Blizzard") or C.DEFAULT_STATUSBAR_TEXTURE
end

--- Returns a font file path (LSM-resolved when available).
---@param fontKey string|nil
---@param fallback string|nil
---@return string
function Util.GetFontPath(fontKey, fallback)
    local fallbackPath = fallback or "Interface\\AddOns\\EnhancedCooldownManager\\media\\Fonts\\Expressway.ttf"

    return FetchLSM("font", fontKey) or fallbackPath
end

--- Applies font settings to a FontString.
---@param fontString FontString
---@param globalConfig table|nil Full global configuration table
function Util.ApplyFont(fontString, globalConfig)
    if not fontString then
        return
    end

    Util.DebugAssert(type(globalConfig) == "table" or globalConfig == nil, "Util.ApplyFont: globalConfig must be a table or nil")
    Util.DebugAssert(
        not (type(globalConfig) == "table" and globalConfig.global ~= nil and globalConfig.font == nil),
        "Util.ApplyFont: expected global config block, received profile root"
    )

    local fontPath = Util.GetFontPath(globalConfig and globalConfig.font)
    local fontSize = (globalConfig and globalConfig.fontSize) or 11
    local fontOutline = (globalConfig and globalConfig.fontOutline) or "OUTLINE"

    if fontOutline == "NONE" then
        fontOutline = ""
    end

    local hasShadow = globalConfig and globalConfig.fontShadow

    fontString:SetFont(fontPath, fontSize, fontOutline)

    if hasShadow then
        fontString:SetShadowColor(0, 0, 0, 1)
        fontString:SetShadowOffset(1, -1)
    else
        fontString:SetShadowOffset(0, 0)
    end
end

--- Pixel-snaps a number to the nearest pixel for the current UI scale.
---@param v number|nil
---@return number
function Util.PixelSnap(v)
    local scale = UIParent:GetEffectiveScale()
    local snapped = math.floor(((tonumber(v) or 0) * scale) + 0.5)
    return snapped / scale
end

--- Concatenates two lists.
---@param a any[]
---@param b any[]
function Util.Concat(a, b)
    local out = {}
    for i = 1, #a do
        out[#out + 1] = a[i]
    end
    for i = 1, #b do
        out[#out + 1] = b[i]
    end
    return out
end

--- Merges two lists of strings into one with unique entries.
--- @param a string[]
--- @param b string[]
function Util.MergeUniqueLists(a, b)
    local out, seen = {}, {}

    local function add(v, label, i)
        assert(type(v) == "string", ("MergeUniqueLists: %s[%d] not string"):format(label, i))
        if not seen[v] then
            seen[v] = true
            out[#out + 1] = v
        end
    end

    for i = 1, #a do add(a[i], "a", i) end
    for i = 1, #b do add(b[i], "b", i) end

    return out
end

--- Safely converts a value to a copyable form, handling WoW secret values.
---@param v any
---@return any
local function SafeCopyValue(v)
    if type(issecretvalue) == "function" and issecretvalue(v) then
        return (type(canaccessvalue) == "function" and canaccessvalue(v)) and ("s|" .. tostring(v)) or "<secret>"
    end
    if type(issecrettable) == "function" and issecrettable(v) then
        return (type(canaccesstable) == "function" and canaccesstable(v)) and "s|<table>" or "<secrettable>"
    end
    return v
end

--- Creates a deep copy of a table with cycle detection and depth limit.
---@param tbl any
---@param seen table|nil
---@param depth number|nil
---@return any
function Util.DeepCopy(tbl, seen, depth)
    if type(tbl) ~= "table" then
        return tbl
    end

    depth = (depth or 0) + 1
    if depth > 10 then
        return "<max depth>"
    end

    seen = seen or {}
    if seen[tbl] then
        return "<cycle>"
    end
    seen[tbl] = true

    local copy = {}
    for k, v in pairs(tbl) do
        -- Handle secret keys
        if type(issecretvalue) == "function" and issecretvalue(k) then
            copy["<secret_key>"] = "<secret>"
        elseif type(v) == "table" then
            copy[k] = Util.DeepCopy(v, seen, depth)
        else
            copy[k] = SafeCopyValue(v)
        end
    end

    seen[tbl] = nil
    return copy
end

--- Unified debug logging: sends to DevTool and trace buffer when debug mode is ON.
---@param moduleName string
---@param message string
---@param data any|nil
function Util.Log(moduleName, message, data)
    local addon = ns.Addon
    local profile = addon and addon.db and addon.db.profile
    if not profile or not profile.debug then
        return
    end

    local prefix = "ECM:" .. moduleName .. " - " .. message

    -- Add to trace log buffer for /ecm bug
    if ns.AddToTraceLog then
        local logLine = prefix
        if data ~= nil then
            if type(data) == "table" then
                local parts = {}
                for k, v in pairs(data) do
                    parts[#parts + 1] = tostring(k) .. "=" .. Util.SafeGetDebugValue(v)
                end
                logLine = logLine .. ": {" .. table.concat(parts, ", ") .. "}"
            else
                logLine = logLine .. ": " .. Util.SafeGetDebugValue(data)
            end
        end
        ns.AddToTraceLog(logLine)
    end

    -- Send to DevTool when available
    if DevTool and DevTool.AddData then
        local payload = {
            module = moduleName,
            message = message,
            timestamp = GetTime(),
            data = type(data) == "table" and Util.DeepCopy(data) or SafeCopyValue(data),
        }
        pcall(DevTool.AddData, DevTool, payload, prefix)
    end

    -- prefix = "|cffaaaaaa[" .. moduleName .. "]:|r" .. " " .. message
    -- Util.Print(prefix,  Util.SafeGetDebugValue(data))
end

--- Prints a chat message with a colorful ECM prefix.
---@param ... any
function Util.Print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end

    local message = table.concat(parts, " ")
    local prefixText = "Enhanced Cooldown Manager:"
    local sparkle = ns.SparkleUtil
    local coloredPrefix = (sparkle and sparkle.GetText)
        and sparkle.GetText(
            prefixText,
            { r = 0.25, g = 0.82, b = 1.00, a = 1 },
            { r = 0.62, g = 0.45, b = 1.00, a = 1 },
            { r = 0.13, g = 0.77, b = 0.37, a = 1 }
        )
        or prefixText

    if message ~= "" then
        print(coloredPrefix .. " " .. message)
    else
        print(coloredPrefix)
    end
end

function Util.SafeGetDebugValue(v)
    local function IsSecretValue(x)
        return type(issecretvalue) == "function" and issecretvalue(x)
    end

    local function IsSecretTable(x)
        return type(issecrettable) == "function" and issecrettable(x)
    end

    local function CanAccessValue(x)
        return type(canaccessvalue) == "function" and canaccessvalue(x)
    end

    local function CanAccessTable(x)
        return type(canaccesstable) == "function" and canaccesstable(x)
    end

    local function GetSafeScalarString(x)
        if x == nil then
            return "<nil>"
        end

        if IsSecretValue(x) then
            return CanAccessValue(x) and ("s|" .. tostring(x)) or "<secret>"
        end

        if IsSecretTable(x) then
            return CanAccessTable(x) and "s|<table>" or "<secrettable>"
        end

        return tostring(x)
    end

    ---@param tbl table
    ---@param depth number
    ---@param seen table
    ---@return string
    local function TableToString(tbl, depth, seen)
        if IsSecretTable(tbl) then
            return CanAccessTable(tbl) and "s|<table>" or "<secrettable>"
        end

        if seen[tbl] then
            return "<cycle>"
        end

        if depth >= 3 then
            return "{...}"
        end

        seen[tbl] = true

        local ok, pairsOrErr = pcall(function()
            local parts = {}
            local count = 0

            for k, x in pairs(tbl) do
                count = count + 1
                if count > 25 then
                    parts[#parts + 1] = "..."
                    break
                end

                local keyStr
                if IsSecretValue(k) then
                    keyStr = "<secret_key>"
                else
                    keyStr = tostring(k)
                end

                local valueStr
                if type(x) == "table" then
                    valueStr = TableToString(x, depth + 1, seen)
                else
                    valueStr = GetSafeScalarString(x)
                end

                parts[#parts + 1] = keyStr .. "=" .. valueStr
            end

            return "{" .. table.concat(parts, ", ") .. "}"
        end)

        seen[tbl] = nil

        if not ok then
            return "<table_error>"
        end

        return pairsOrErr
    end

    if type(v) == "table" then
        return TableToString(v, 0, {})
    end

    return GetSafeScalarString(v)
end

--- Creates an ECM_Color table from channels.
---@param r number
---@param g number
---@param b number
---@param a number|nil
---@return ECM_Color
function Util.Color(r, g, b, a)
    return { r = r, g = g, b = b, a = a or 1 }
end
