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

describe("PowerBarTickMarksStore", function()
    local originalGlobals
    local addonNS
    local currentClassID
    local currentSpecIndex

    local function deepClone(value)
        if type(value) ~= "table" then
            return value
        end

        local out = {}
        for k, v in pairs(value) do
            out[k] = deepClone(v)
        end
        return out
    end

    setup(function()
        originalGlobals = TestHelpers.captureGlobals({
            "ECM",
            "ECM_CloneValue",
        })
    end)

    teardown(function()
        TestHelpers.restoreGlobals(originalGlobals)
    end)

    before_each(function()
        currentClassID = 1
        currentSpecIndex = 2

        _G.ECM = {
            Constants = {
                DEFAULT_POWERBAR_TICK_COLOR = { r = 0.9, g = 0.8, b = 0.7, a = 0.6 },
            },
            OptionUtil = {
                GetCurrentClassSpec = function()
                    return currentClassID, currentSpecIndex, "Warrior", "Fury", "WARRIOR"
                end,
            },
        }
        _G.ECM_CloneValue = deepClone

        addonNS = {
            Addon = {
                db = {
                    profile = {},
                },
            },
        }

        local chunk = TestHelpers.loadChunk(
            { "Options/PowerBarTickMarksStore.lua", "../Options/PowerBarTickMarksStore.lua" },
            "Unable to load Options/PowerBarTickMarksStore.lua"
        )
        chunk(nil, addonNS)
    end)

    it("returns empty ticks when class/spec is unavailable", function()
        currentClassID = nil
        currentSpecIndex = nil

        local ticks = ECM.PowerBarTickMarksStore.GetCurrentTicks()
        assert.are.same({}, ticks)
    end)

    it("adds ticks using default color and width", function()
        ECM.PowerBarTickMarksStore.SetDefaultWidth(3)
        ECM.PowerBarTickMarksStore.SetDefaultColor({ r = 0.1, g = 0.2, b = 0.3, a = 0.4 })

        ECM.PowerBarTickMarksStore.AddTick(50, nil, nil)
        local ticks = ECM.PowerBarTickMarksStore.GetCurrentTicks()

        assert.are.equal(1, #ticks)
        assert.are.equal(50, ticks[1].value)
        assert.are.same({ r = 0.1, g = 0.2, b = 0.3, a = 0.4 }, ticks[1].color)
        assert.are.equal(3, ticks[1].width)
    end)

    it("updates and removes ticks for the current spec only", function()
        ECM.PowerBarTickMarksStore.SetCurrentTicks({
            { value = 40, width = 1, color = { r = 1, g = 1, b = 1, a = 1 } },
            { value = 80, width = 2, color = { r = 0, g = 0, b = 0, a = 1 } },
        })

        currentSpecIndex = 1
        ECM.PowerBarTickMarksStore.SetCurrentTicks({
            { value = 20, width = 1, color = { r = 0.5, g = 0.5, b = 0.5, a = 1 } },
        })

        currentSpecIndex = 2
        ECM.PowerBarTickMarksStore.UpdateTick(1, "value", 45)
        ECM.PowerBarTickMarksStore.RemoveTick(2)

        local spec2 = ECM.PowerBarTickMarksStore.GetCurrentTicks()
        assert.are.equal(1, #spec2)
        assert.are.equal(45, spec2[1].value)

        currentSpecIndex = 1
        local spec1 = ECM.PowerBarTickMarksStore.GetCurrentTicks()
        assert.are.equal(1, #spec1)
        assert.are.equal(20, spec1[1].value)
    end)

    it("clearing current ticks does not affect another class mapping", function()
        ECM.PowerBarTickMarksStore.SetCurrentTicks({ { value = 10, width = 1, color = { r = 1, g = 0, b = 0, a = 1 } } })

        currentClassID = 2
        currentSpecIndex = 1
        ECM.PowerBarTickMarksStore.SetCurrentTicks({ { value = 30, width = 2, color = { r = 0, g = 1, b = 0, a = 1 } } })

        ECM.PowerBarTickMarksStore.SetCurrentTicks({})
        assert.are.equal(0, #ECM.PowerBarTickMarksStore.GetCurrentTicks())

        currentClassID = 1
        currentSpecIndex = 2
        local ticks = ECM.PowerBarTickMarksStore.GetCurrentTicks()
        assert.are.equal(1, #ticks)
        assert.are.equal(10, ticks[1].value)
    end)
end)
