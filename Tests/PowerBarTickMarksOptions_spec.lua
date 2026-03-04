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
        originalGlobals = TestHelpers.captureGlobals({
            "ECM", "ECM_CloneValue",
            "StaticPopupDialogs", "YES", "NO", "SETTINGS_DEFAULTS",
        })
    end)

    teardown(function()
        TestHelpers.restoreGlobals(originalGlobals)
    end)

    it("module loads and exposes RegisterSettings and Store", function()
        _G.StaticPopupDialogs = _G.StaticPopupDialogs or {}
        _G.YES = "Yes"
        _G.NO = "No"
        _G.SETTINGS_DEFAULTS = "Defaults"
        _G.ECM_CloneValue = TestHelpers.deepClone
        _G.ECM = {
            Constants = {
                DEFAULT_POWERBAR_TICK_COLOR = { r = 1, g = 1, b = 1, a = 1 },
                CLASS_COLORS = { WARRIOR = "C79C6E" },
                COLOR_WHITE_HEX = "FFFFFF",
            },
            OptionUtil = {
                GetCurrentClassSpec = function()
                    return 1, 2, "Warrior", "Fury", "WARRIOR"
                end,
            },
            ScheduleLayoutUpdate = function() end,
        }

        local addonNS = {
            Addon = {
                db = { profile = {} },
            },
        }
        local chunk = TestHelpers.loadChunk(
            { "Options/PowerBarTickMarksOptions.lua", "../Options/PowerBarTickMarksOptions.lua" },
            "Unable to load PowerBarTickMarksOptions.lua"
        )
        chunk(nil, addonNS)

        assert.is_table(ECM.PowerBarTickMarksOptions)
        assert.is_function(ECM.PowerBarTickMarksOptions.RegisterSettings)

        assert.is_table(ECM.PowerBarTickMarksStore)
        assert.is_function(ECM.PowerBarTickMarksStore.GetCurrentTicks)
        assert.is_function(ECM.PowerBarTickMarksStore.AddTick)
    end)
end)
