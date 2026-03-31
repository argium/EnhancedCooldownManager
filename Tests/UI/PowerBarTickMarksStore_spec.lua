-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("PowerBarTickMarksStore", function()
    local originalGlobals
    local currentClassID
    local currentSpecIndex
    local ns

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({})
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        currentClassID = 1
        currentSpecIndex = 2

        ns = TestHelpers.SetupPowerBarTickMarksEnv({
            constants = {
                DEFAULT_POWERBAR_TICK_COLOR = { r = 0.9, g = 0.8, b = 0.7, a = 0.6 },
                CLASS_COLORS = { WARRIOR = "C79C6E" },
                COLOR_WHITE_HEX = "FFFFFF",
            },
            getCurrentClassSpec = function()
                return currentClassID, currentSpecIndex, "Warrior", "Fury", "WARRIOR"
            end,
        })
    end)

    it("returns empty ticks when class/spec is unavailable", function()
        currentClassID = nil
        currentSpecIndex = nil

        local ticks = ns.PowerBarTickMarksStore.GetCurrentTicks()
        assert.are.same({}, ticks)
    end)

    it("adds ticks using default color and width", function()
        ns.PowerBarTickMarksStore.SetDefaultWidth(3)
        ns.PowerBarTickMarksStore.SetDefaultColor({ r = 0.1, g = 0.2, b = 0.3, a = 0.4 })

        ns.PowerBarTickMarksStore.AddTick(50, nil, nil)
        local ticks = ns.PowerBarTickMarksStore.GetCurrentTicks()

        assert.are.equal(1, #ticks)
        assert.are.equal(50, ticks[1].value)
        assert.are.same({ r = 0.1, g = 0.2, b = 0.3, a = 0.4 }, ticks[1].color)
        assert.are.equal(3, ticks[1].width)
    end)

    it("updates and removes ticks for the current spec only", function()
        ns.PowerBarTickMarksStore.SetCurrentTicks({
            { value = 40, width = 1, color = { r = 1, g = 1, b = 1, a = 1 } },
            { value = 80, width = 2, color = { r = 0, g = 0, b = 0, a = 1 } },
        })

        currentSpecIndex = 1
        ns.PowerBarTickMarksStore.SetCurrentTicks({
            { value = 20, width = 1, color = { r = 0.5, g = 0.5, b = 0.5, a = 1 } },
        })

        currentSpecIndex = 2
        ns.PowerBarTickMarksStore.UpdateTick(1, "value", 45)
        ns.PowerBarTickMarksStore.RemoveTick(2)

        local spec2 = ns.PowerBarTickMarksStore.GetCurrentTicks()
        assert.are.equal(1, #spec2)
        assert.are.equal(45, spec2[1].value)

        currentSpecIndex = 1
        local spec1 = ns.PowerBarTickMarksStore.GetCurrentTicks()
        assert.are.equal(1, #spec1)
        assert.are.equal(20, spec1[1].value)
    end)

    it("clearing current ticks does not affect another class mapping", function()
        ns.PowerBarTickMarksStore.SetCurrentTicks({ { value = 10, width = 1, color = { r = 1, g = 0, b = 0, a = 1 } } })

        currentClassID = 2
        currentSpecIndex = 1
        ns.PowerBarTickMarksStore.SetCurrentTicks({ { value = 30, width = 2, color = { r = 0, g = 1, b = 0, a = 1 } } })

        ns.PowerBarTickMarksStore.SetCurrentTicks({})
        assert.are.equal(0, #ns.PowerBarTickMarksStore.GetCurrentTicks())

        currentClassID = 1
        currentSpecIndex = 2
        local ticks = ns.PowerBarTickMarksStore.GetCurrentTicks()
        assert.are.equal(1, #ticks)
        assert.are.equal(10, ticks[1].value)
    end)
end)
