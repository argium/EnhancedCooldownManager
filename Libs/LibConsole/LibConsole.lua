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
    local key = "LIBCONSOLE_" .. command:upper()
    SlashCmdList[key] = handler
    _G["SLASH_" .. key .. "1"] = "/" .. command:lower()
    lib.commands[command] = key
end

--- Unregister a previously registered slash command.
--- @param command string Command name without leading "/".
function lib:UnregisterCommand(command)
    local key = lib.commands[command]
    if not key then
        return
    end
    SlashCmdList[key] = nil
    _G["SLASH_" .. key .. "1"] = nil
    hash_SlashCmdList["/" .. command:upper()] = nil
    lib.commands[command] = nil
end

--- Create a print function that formats varargs then delegates the final string.
--- @param delegate function Called with (formattedMessage) for each Print() call.
--- @return function Print(...) Accepts any number of arguments, converts to strings, joins with spaces.
function lib:NewPrinter(delegate)
    local buf = {}
    return function(...)
        local n = select("#", ...)
        for i = 1, n do
            buf[i] = tostring(select(i, ...))
        end
        delegate(tconcat(buf, " ", 1, n))
    end
end
