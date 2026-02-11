-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants

---------------------------------------------------------------------------
-- String helpers
---------------------------------------------------------------------------

local function safe_str_tostring(x)
    if x == nil then
        return "nil"
    elseif issecretvalue(x) then
        return "[secret]"
    else
        return tostring(x)
    end
end

local function safe_table_tostring(tbl, depth, seen)
    if issecrettable(tbl) then
        return "[secrettable]"
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

            local keyStr = issecretvalue(k) and "[secret]" or tostring(k)
            local valueStr = type(x) == "table" and safe_table_tostring(x, depth + 1, seen) or safe_str_tostring(x)
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

ECM_tostring = function(v)
    if type(v) == "table" then
        return safe_table_tostring(v, 0, {})
    end

    return safe_str_tostring(v)
end

---------------------------------------------------------------------------
-- Debug helpers
---------------------------------------------------------------------------

ECM_SYS = {
    Layout = "Layout",
    Bars = "Bars",
    SecretedStore = "SecretedStore",
}

ECM_log = function (subsystem, message, data)
    local prefix = "ECM:" .. subsystem .. ":"
    message = prefix .. " " .. message

    -- Add to trace log buffer for /ecm bug
    if ns.AddToTraceLog then
        local logLine = message
        if data ~= nil then
            if type(data) == "table" then
                local parts = {}
                for k, v in pairs(data) do
                    parts[#parts + 1] = tostring(k) .. "=" .. ECM_tostring(v)
                end
                logLine = logLine .. ": {" .. table.concat(parts, ", ") .. "}"
            else
                logLine = logLine .. ": " .. ECM_tostring(data)
            end
        end
        ns.AddToTraceLog(logLine)
    end

    prefix = ECM_sparkle(
        prefix,
        { r = 0.25, g = 0.82, b = 1.00, a = 1 },
        { r = 0.62, g = 0.45, b = 1.00, a = 1 },
        { r = 0.13, g = 0.77, b = 0.37, a = 1 })

    message = prefix .. " " .. message
    print(message)
end

ECM_is_debug_enabled  = function()
    return ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.debug
end

ECM_debug_assert = function(condition, message)
    if not ECM_is_debug_enabled() then
        return
    end
    assert(condition, message)
end

---------------------------------------------------------------------------
-- Media helpers
---------------------------------------------------------------------------

local LSM = LibStub("LibSharedMedia-3.0", true)

local function get_lsm_media(mediaType, key)
    if LSM and LSM.Fetch and key and type(key) == "string" then
        return LSM:Fetch(mediaType, key, true)
    end
    return nil
end

local function get_font_path(fontKey, fallback)
    ECM_debug_assert(fallback, "fallback cannot be nil")
    local fallbackPath = fallback or "Interface\\AddOns\\EnhancedCooldownManager\\media\\Fonts\\Expressway.ttf"
    return get_lsm_media("font", fontKey) or fallbackPath
end

--- Returns a statusbar texture path (LSM-resolved when available).
---@param texture string|nil Name of the texture in LSM or a file path.
---@return string
ECM_GetTexture = function(texture)
    if texture and type(texture) == "string" then
        local fetched = get_lsm_media("statusbar", texture)
        if fetched then
            return fetched
        end

        -- Treat it as a file path
        if texture:find("\\") then
            return texture
        end
    end

    return get_lsm_media("statusbar", "Blizzard") or C.DEFAULT_STATUSBAR_TEXTURE
end

--- Applies font settings to a FontString.
---@param fontString FontString
---@param globalConfig table|nil Full global configuration table
ECM_ApplyFont = function(fontString, globalConfig)
    if not fontString then
        return
    end

    ECM_debug_assert(type(globalConfig) == "table" or globalConfig == nil, "ECM_ApplyFont: globalConfig must be a table or nil")
    ECM_debug_assert(
        not (type(globalConfig) == "table" and globalConfig.global ~= nil and globalConfig.font == nil),
        "ECM_ApplyFont: expected global config block, received profile root"
    )

    local fontPath = get_font_path(globalConfig and globalConfig.font)
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

--- Compares two ECM_Color tables for equality.
--- @param c1 ECM_Color|nil
--- @param c2 ECM_Color|nil
--- @return boolean
ECM_AreColorsEqual = function(c1, c2)
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



---------------------------------------------------------------------------
-- Layout helpers
---------------------------------------------------------------------------

--- Pixel-snaps a number to the nearest pixel for the current UI scale.
---@param v number|nil
---@return number
ECM_PixelSnap = function(v)
    local scale = UIParent:GetEffectiveScale()
    local snapped = math.floor(((tonumber(v) or 0) * scale) + 0.5)
    return snapped / scale
end

--- Concatenates two lists.
---@param a any[]
---@param b any[]
ECM_Concat = function(a, b)
    local out = {}
    for i = 1, #a do
        out[#out + 1] = a[i]
    end
    for i = 1, #b do
        out[#out + 1] = b[i]
    end
    return out
end



---------------------------------------------------------------------------
-- List helpers
---------------------------------------------------------------------------

--- Merges two lists of strings into one with unique entries.
--- @param a string[]
--- @param b string[]
ECM_MergeUniqueLists = function(a, b)
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

--- Performs a deep equality check between two values
--- @param a any
--- @param b any
--- @return boolean
ECM_DeepEquals = function(a, b)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not ECM_DeepEquals(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

--- Creates a deep copy of a table with cycle detection and depth limit.
---@param tbl any
---@param seen table|nil
---@param depth number|nil
---@return any
ECM_DeepCopy = function(tbl, seen, depth)
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
        if issecretvalue(k) then
            copy["[secret]"] = "[secret]"
        elseif type(v) == "table" then
            copy[k] = ECM_DeepCopy(v, seen, depth)
        else
            copy[k] = safe_str_tostring(v)
        end
    end

    seen[tbl] = nil
    return copy
end

--- Unified debug logging: sends to DevTool and trace buffer when debug mode is ON.
---@param moduleName string
---@param message string
---@param data any|nil
function ECM_log(moduleName, message, data)
    return
    -- local addon = ns.Addon
    -- local profile = addon and addon.db and addon.db.profile
    -- if not profile or not profile.debug then
    --     return
    -- end

    -- local prefix = "ECM:" .. moduleName .. " - " .. message

    -- -- Add to trace log buffer for /ecm bug
    -- if ns.AddToTraceLog then
    --     local logLine = prefix
    --     if data ~= nil then
    --         if type(data) == "table" then
    --             local parts = {}
    --             for k, v in pairs(data) do
    --                 parts[#parts + 1] = tostring(k) .. "=" .. ECM_safe_tostring(v)
    --             end
    --             logLine = logLine .. ": {" .. table.concat(parts, ", ") .. "}"
    --         else
    --             logLine = logLine .. ": " .. ECM_safe_tostring(data)
    --         end
    --     end
    --     ns.AddToTraceLog(logLine)
    -- end

    -- -- Send to DevTool when available
    -- if DevTool and DevTool.AddData then
    --     local payload = {
    --         module = moduleName,
    --         message = message,
    --         timestamp = GetTime(),
    --         data = type(data) == "table" and ECM_DeepCopy(data) or ECM_safe_tostring(data),
    --     }
    --     pcall(DevTool.AddData, DevTool, payload, prefix)
    -- end

    -- prefix = "|cffaaaaaa[" .. moduleName .. "]:|r" .. " " .. message
    -- ECM_print(prefix,  ECM_safe_tostring(data))
end

--- Prints a chat message with a colorful ECM prefix.
---@param ... any
ECM_print = function (...)
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



-- ---@param oldA table|nil
-- ---@param newA table|nil
-- ---@param oldB table|nil
-- ---@param newB table|nil
-- ---@param comparer fun(oldValue:any, newValue:any, index:any, oldB:table|nil, newB:table|nil):boolean|nil
-- ---@return boolean
-- function Util.HasIndexedMapsChanged(oldA, newA, oldB, newB, comparer)
--     if type(oldA) ~= "table" then
--         return true
--     end

--     local resolvedNewA = type(newA) == "table" and newA or {}
--     if CountEntries(oldA) ~= CountEntries(resolvedNewA) then
--         return true
--     end

--     for index, newValue in pairs(resolvedNewA) do
--         local oldValue = oldA[index]
--         if oldValue == nil then
--             return true
--         end

--         local equivalent = nil
--         if type(comparer) == "function" then
--             equivalent = comparer(oldValue, newValue, index, oldB, newB)
--         else
--             equivalent = oldValue == newValue
--         end

--         if not equivalent then
--             return true
--         end

--         local oldSecond = type(oldB) == "table" and oldB[index] or nil
--         local newSecond = type(newB) == "table" and newB[index] or nil
--         if oldSecond ~= newSecond then
--             return true
--         end
--     end

--     return false
-- end
