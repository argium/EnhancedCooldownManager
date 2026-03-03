-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

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
-- Media helpers
---------------------------------------------------------------------------

local LSM = LibStub("LibSharedMedia-3.0", true)

local function get_lsm_media(mediaType, key)
    if LSM and LSM.Fetch and key then
        return LSM:Fetch(mediaType, key, true)
    end
    return nil
end

local function get_font_path(fontKey)
    return get_lsm_media("font", fontKey) or ECM.Constants.DEFAULT_FONT
end

--- Returns a statusbar texture path (LSM-resolved when available).
---@param texture string|nil Name of the texture in LSM or a file path.
---@return string
function ECM_GetTexture(texture)
    if texture then
        local fetched = get_lsm_media("statusbar", texture)
        if fetched then
            return fetched
        end

        -- Treat it as a file path
        if texture:find("\\") then
            return texture
        end
    end

    return get_lsm_media("statusbar", "Blizzard") or ECM.Constants.DEFAULT_STATUSBAR_TEXTURE
end

--- Applies font settings to a FontString.
---@param fontString FontString
---@param globalConfig table|nil
---@param moduleConfig table|nil
function ECM_ApplyFont(fontString, globalConfig, moduleConfig)
    local config = globalConfig or (ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.global)
    local useModuleOverride = moduleConfig and moduleConfig.overrideFont == true
    local fontPath = get_font_path((useModuleOverride and moduleConfig.font) or (config and config.font))
    local fontSize = (useModuleOverride and moduleConfig.fontSize) or (config and config.fontSize) or 11
    local fontOutline = (config and config.fontOutline)

    if fontOutline == "NONE" then
        fontOutline = ""
    end

    local hasShadow = config and config.fontShadow

    ECM.DebugAssert(fontPath, "Font path cannot be nil")
    ECM.DebugAssert(fontSize, "Font size cannot be nil")
    ECM.DebugAssert(fontOutline, "Font outline cannot be nil")

    fontString:SetFont(fontPath, fontSize, fontOutline)

    if hasShadow then
        fontString:SetShadowColor(0, 0, 0, 1)
        fontString:SetShadowOffset(1, -1)
    else
        fontString:SetShadowOffset(0, 0)
    end
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

--- Creates a proper deep clone of a value, preserving types.
---@param value any
---@return any
function ECM_CloneValue(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = ECM_CloneValue(v)
    end
    return copy
end

--- Prints a chat message with a colorful ECM prefix.
---@param ... any
function ECM_print(...)
    local prefix = ColorUtil.Sparkle(ECM.Constants.ADDON_ABRV .. ":")
    local args = {...}
    for i = 1, #args do args[i] = tostring(args[i]) end
    local message = table.concat(args, " ")
    print(prefix .. " " .. message)
end
