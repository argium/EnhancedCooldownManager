-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = {}

function TestHelpers.loadChunk(paths, errorMessage)
    for _, path in ipairs(paths) do
        local chunk = loadfile(path)
        if chunk then
            return chunk
        end
    end
    error(errorMessage)
end

function TestHelpers.captureGlobals(names)
    local snapshot = {}
    for _, name in ipairs(names) do
        snapshot[name] = _G[name]
    end
    return snapshot
end

function TestHelpers.restoreGlobals(snapshot)
    for name, value in pairs(snapshot) do
        _G[name] = value
    end
end

return TestHelpers
