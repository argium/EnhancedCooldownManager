-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR, MINOR = "LibConsole-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)

if not lib then
    return
end

local tostring = tostring
local select = select
local tconcat = table.concat

lib.commands = lib.commands or {}

--- Register a slash command.
--- @param command string Command name without leading "/".
--- @param handler function Called with (input, editBox) when the command is used.
function lib:RegisterCommand(command, handler)
    assert(type(command) == "string" and command ~= "", "Usage: RegisterCommand(command, handler)")
    assert(type(handler) == "function", "handler must be a function")

    local normalized = command:lower()
    local key = "LIBCONSOLE_" .. command:upper()
    SlashCmdList[key] = handler
    _G["SLASH_" .. key .. "1"] = "/" .. normalized
    lib.commands[normalized] = key
end

--- Unregister a previously registered slash command.
--- @param command string Command name without leading "/".
function lib:UnregisterCommand(command)
    assert(type(command) == "string" and command ~= "", "Usage: UnregisterCommand(command)")

    local normalized = command:lower()
    local key = lib.commands[normalized]
    if not key then
        return
    end
    SlashCmdList[key] = nil
    _G["SLASH_" .. key .. "1"] = nil
    hash_SlashCmdList["/" .. command:upper()] = nil
    lib.commands[normalized] = nil
end

--- Create a print function that formats varargs then delegates the final string.
--- @param delegate function Called with (formattedMessage) for each Print() call.
--- @return function Print(...) Accepts any number of arguments, converts to strings, joins with spaces.
function lib:NewPrinter(delegate)
    assert(type(delegate) == "function", "delegate must be a function")

    local buf = {}
    local lastN = 0
    return function(...)
        local n = select("#", ...)
        for i = 1, n do
            buf[i] = tostring((select(i, ...)))
        end
        for i = n + 1, lastN do
            buf[i] = nil
        end
        lastN = n
        delegate(tconcat(buf, " ", 1, n))
    end
end
