-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

if type(describe) ~= "function" or type(it) ~= "function" then
    return
end

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("PowerBarTickMarksOptions", function()
    local originalGlobals

    setup(function()
        originalGlobals = TestHelpers.captureGlobals({ "ECM" })
    end)

    teardown(function()
        TestHelpers.restoreGlobals(originalGlobals)
    end)

    it("module loads and exposes RegisterSettings", function()
        _G.ECM = {
            Constants = {
                DEFAULT_POWERBAR_TICK_COLOR = { r = 1, g = 1, b = 1, a = 1 },
                CLASS_COLORS = {},
                COLOR_WHITE_HEX = "FFFFFF",
            },
            OptionUtil = {
                GetCurrentClassSpec = function()
                    return 1, 2, "Warrior", "Fury", "WARRIOR"
                end,
            },
            PowerBarTickMarksStore = {
                GetCurrentTicks = function() return {} end,
                SetCurrentTicks = function() end,
                AddTick = function() end,
                RemoveTick = function() end,
                UpdateTick = function() end,
                GetDefaultColor = function() return { r = 1, g = 1, b = 1, a = 1 } end,
                SetDefaultColor = function() end,
                GetDefaultWidth = function() return 1 end,
                SetDefaultWidth = function() end,
            },
            ScheduleLayoutUpdate = function() end,
        }

        local addonNS = { Addon = {} }
        local chunk = TestHelpers.loadChunk(
            { "Options/PowerBarTickMarksOptions.lua", "../Options/PowerBarTickMarksOptions.lua" },
            "Unable to load PowerBarTickMarksOptions.lua"
        )
        chunk(nil, addonNS)

        assert.is_table(ECM.PowerBarTickMarksOptions)
        assert.is_function(ECM.PowerBarTickMarksOptions.RegisterSettings)
    end)
end)
