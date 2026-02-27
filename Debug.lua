-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

local function is_debug_enabled()
    return ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.debug
end

--- Logs a debug message to DevTool and, when debug mode is enabled, to the chat window.
--- @param module string|nil Module name
--- @param message string Debug message
--- @param data any|nil Optional additional data to log (will be stringified)
function ECM.Log(module, message, data)
    if not is_debug_enabled() then
        return
    end

    ECM.DebugAssert(message and type(message) == "string", "ECM.Log: message must be a string")
    ECM.DebugAssert(module == nil or type(module) == "string", "ECM.Log: module must be a string or nil")

    local prefix = "[" .. ECM.Constants.ADDON_ABRV .. (module and (" " .. module) or "") .. "]"

    if DevTool and DevTool.AddData then
        local payload = {
            module = module or "nil",
            message = message,
            timestamp = GetTime(),
            data = ECM_tostring(data),
        }
        pcall(DevTool.AddData, DevTool, payload, "|cff".. ECM.Constants.DEBUG_COLOR ..  prefix .. "|r " .. message)
    end

    print("|cff".. ECM.Constants.DEBUG_COLOR ..  prefix .. "|r " .. message)
end

function ECM.DebugAssert(condition, message, data)
    if not is_debug_enabled() then
        return
    end

    if data and not condition and DevTool and DevTool.AddData then
        pcall(DevTool.AddData, DevTool, data, "|cff".. ECM.Constants.DEBUG_COLOR .. "[ASSERT]|r " .. message)
    end
    assert(condition, message)
end
