-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants

---------------------------------------------------------------------------
-- String helpers
---------------------------------------------------------------------------


--- Converts a string to a readable format handling nil and secret values.
--- @param x string|nil
--- @return string
local function safe_str_tostring(x)
    if x == nil then
        return "nil"
    elseif issecretvalue(x) then
        return "[secret]"
    else
        return tostring(x)
    end
end

--- Converts a table to a string with cycle detection, depth limit, and secret value handling.
--- @param tbl table
--- @param depth number
--- @param seen table
--- @return string
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

--- Converts a value to a string.
--- @param v any
--- @return string
function ECM_tostring(v)
    if type(v) == "table" then
        return safe_table_tostring(v, 0, {})
    end

    return safe_str_tostring(v)
end

---------------------------------------------------------------------------
-- Debug helpers
---------------------------------------------------------------------------

--- Logs a debug message to the console, internal buffer, and DevTool.
--- @param subsystem SUBSYSTEM Subsystem name for categorization
--- @param module string|nil Module name
--- @param message string Debug message
--- @param data any|nil Optional additional data to log (will be stringified)
function ECM_log(subsystem, module, message, data)
    ECM_debug_assert(subsystem and type(subsystem) == "string", "ECM_log: subsystem must be a string")
    ECM_debug_assert(message and type(message) == "string", "ECM_log: message must be a string")
    ECM_debug_assert(module == nil or type(module) == "string", "ECM_log: module must be a string or nil")

    local prefix = "[" .. C.ADDON_ABRV .. " " .. subsystem ..  (module and " " .. module or "") .. "]"

    -- Add to trace log buffer for /ecm bug
    if ns.AddToTraceLog then
        local logLine = prefix .. " " .. message
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

    if DevTool and DevTool.AddData then
        local payload = {
            subsystem = subsystem,
            module = module or "nil",
            message = message,
            timestamp = GetTime(),
            data = ECM_tostring(data),
        }
        pcall(DevTool.AddData, DevTool, payload, "|cff".. C.DEBUG_COLOR ..  prefix .. "|r " .. message)
    end

    if ECM_is_debug_enabled() then
        print("|cff".. C.DEBUG_COLOR ..  prefix .. "|r " .. message)
    end
end

function ECM_is_debug_enabled()
    return ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.debug
end

function ECM_debug_assert(condition, message, data)
    if not ECM_is_debug_enabled() then
        return
    end

    if data and not condition and DevTool and DevTool.AddData then
        pcall(DevTool.AddData, DevTool, data, "|cff".. C.DEBUG_COLOR .. "[ASSERT]|r " .. message)
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

local function get_font_path(fontKey)
    return get_lsm_media("font", fontKey) or C.DEFAULT
end

--- Returns a statusbar texture path (LSM-resolved when available).
---@param texture string|nil Name of the texture in LSM or a file path.
---@return string
function ECM_GetTexture(texture)
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
function ECM_ApplyFont(fontString)
    if not fontString then
        return
    end

    local globalConfig = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.global
    local fontPath = get_font_path(globalConfig and globalConfig.font)
    local fontSize = (globalConfig and globalConfig.fontSize)
    local fontOutline = (globalConfig and globalConfig.fontOutline)

    if fontOutline == "NONE" then
        fontOutline = ""
    end

    local hasShadow = globalConfig and globalConfig.fontShadow

    ECM_debug_assert(fontPath, "Font path cannot be nil")
    ECM_debug_assert(fontSize, "Font size cannot be nil")
    ECM_debug_assert(fontOutline, "Font outline cannot be nil")

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
function ECM_AreColorsEqual(c1, c2)
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
function ECM_PixelSnap(v)
    local scale = UIParent:GetEffectiveScale()
    local snapped = math.floor(((tonumber(v) or 0) * scale) + 0.5)
    return snapped / scale
end

--- Concatenates two lists.
---@param a any[]
---@param b any[]
function ECM_Concat(a, b)
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
function ECM_MergeUniqueLists(a, b)
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
function ECM_DeepEquals(a, b)
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
function ECM_DeepCopy(tbl, seen, depth)
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

--- Prints a chat message with a colorful ECM prefix.
---@param ... any
function ECM_print(...)
    local prefix = ECM_sparkle(C.ADDON_NAME .. ":")
    local message = table.concat({...}, " ")
    print(prefix .. " " .. message)
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
