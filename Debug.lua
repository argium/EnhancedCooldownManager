-- Trace log buffer (circular buffer for last 200 debug messages)

local _, ns = ...
local C = ns.Constants

local traceLogBuffer = {}
local traceLogIndex = 0
local traceLogCount = 0


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

--- Adds a message to the trace log buffer.
---@param message string
local function AddToTraceLog(message)
    traceLogIndex = (traceLogIndex % C.TRACE_LOG_MAX) + 1
    traceLogBuffer[traceLogIndex] = string.format("[%s] %s", date("%H:%M:%S"), message)
    if traceLogCount < C.TRACE_LOG_MAX then
        traceLogCount = traceLogCount + 1
    end
end

--- Returns the trace log contents as a single string.
---@return string
local function GetTraceLog()
    if traceLogCount == 0 then
        return "(No trace logs recorded)"
    end

    local lines = {}
    local startIdx = (traceLogCount < C.TRACE_LOG_MAX) and 1 or (traceLogIndex + 1)
    for i = 1, traceLogCount do
        local idx = ((startIdx - 2 + i) % C.TRACE_LOG_MAX) + 1
        lines[i] = traceLogBuffer[idx]
    end
    return table.concat(lines, "\n")
end

ns.AddToTraceLog = AddToTraceLog
ns.GetTraceLog = GetTraceLog
