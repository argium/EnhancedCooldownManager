local _, ns = ...

local Util = ns.Util or {}
ns.Util = Util

--- Pixel-snaps a number to the nearest pixel for the current UI scale.
---@param v number|nil
---@return number
function Util.PixelSnap(v)
    local scale = UIParent:GetEffectiveScale()
    local snapped = math.floor(((tonumber(v) or 0) * scale) + 0.5)
    return snapped / scale
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
---@param tbl any Value to copy
---@param seen table|nil Table tracking visited tables (for recursion)
---@param depth number|nil Current depth (for recursion)
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
---@param moduleName string Module name for prefix (e.g., "PowerBar", "ResourceBar")
---@param message string Log message describing the event
---@param data any|nil Optional data to log (tables are deep-copied for DevTool)
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
                    parts[#parts + 1] = tostring(k) .. "=" .. addon:SafeGetDebugValue(v)
                end
                logLine = logLine .. ": {" .. table.concat(parts, ", ") .. "}"
            else
                logLine = logLine .. ": " .. addon:SafeGetDebugValue(data)
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
end
