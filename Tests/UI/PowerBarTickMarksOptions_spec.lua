-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("PowerBarTickMarksOptions", function()
    local originalGlobals

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "ECM",
            "StaticPopupDialogs", "YES", "NO", "SETTINGS_DEFAULTS",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    it("module loads and exposes RegisterSettings and Store", function()
        TestHelpers.SetupPowerBarTickMarksEnv()

        assert.is_table(ECM.PowerBarTickMarksOptions)
        assert.is_function(ECM.PowerBarTickMarksOptions.RegisterSettings)

        assert.is_table(ECM.PowerBarTickMarksStore)
        assert.is_function(ECM.PowerBarTickMarksStore.GetCurrentTicks)
        assert.is_function(ECM.PowerBarTickMarksStore.AddTick)
    end)
end)
