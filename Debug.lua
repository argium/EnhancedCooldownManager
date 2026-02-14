-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

--- Logs a debug message to DevTool and, when debug mode is enabled, to the chat window.
--- @param subsystem SUBSYSTEM Subsystem name for categorization
--- @param module string|nil Module name
--- @param message string Debug message
--- @param data any|nil Optional additional data to log (will be stringified)
function ECM_log(subsystem, module, message, data)
    ECM_debug_assert(subsystem and type(subsystem) == "string", "ECM_log: subsystem must be a string")
    ECM_debug_assert(message and type(message) == "string", "ECM_log: message must be a string")
    ECM_debug_assert(module == nil or type(module) == "string", "ECM_log: module must be a string or nil")

    local prefix = "[" .. ECM.Constants.ADDON_ABRV .. " " .. subsystem ..  (module and " " .. module or "") .. "]"

    if DevTool and DevTool.AddData then
        local payload = {
            subsystem = subsystem,
            module = module or "nil",
            message = message,
            timestamp = GetTime(),
            data = ECM_tostring(data),
        }
        pcall(DevTool.AddData, DevTool, payload, "|cff".. ECM.Constants.DEBUG_COLOR ..  prefix .. "|r " .. message)
    end

    if ECM_is_debug_enabled() then
        print("|cff".. ECM.Constants.DEBUG_COLOR ..  prefix .. "|r " .. message)
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
        pcall(DevTool.AddData, DevTool, data, "|cff".. ECM.Constants.DEBUG_COLOR .. "[ASSERT]|r " .. message)
    end
    assert(condition, message)
end
