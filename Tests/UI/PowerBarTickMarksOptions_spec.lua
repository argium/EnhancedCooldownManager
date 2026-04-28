-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("PowerBarTickMarksOptions", function()
    local originalGlobals
    local currentClassID
    local currentSpecIndex
    local ns

    local function getRow(page, rowId)
        for _, row in ipairs(assert(page.rows)) do
            if row.id == rowId then
                return row
            end
        end
    end

    local function setTickMappings(mappings)
        ns.Addon.db.profile.powerBar = {
            ticks = {
                mappings = mappings,
                defaultColor = ns.Constants.DEFAULT_POWERBAR_TICK_COLOR,
                defaultWidth = 1,
            },
        }
    end

    local function registerPageSpec()
        local captured = assert(ns.PowerBarTickMarksOptions)
        local refreshCalls = {}
        local fakePage = {
            Refresh = function()
                refreshCalls[#refreshCalls + 1] = true
            end,
        }

        if captured.SetRegisteredPage then
            captured.SetRegisteredPage(fakePage)
        end

        return captured, refreshCalls, fakePage
    end

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "StaticPopupDialogs",
            "StaticPopup_Show",
            "YES",
            "NO",
            "SETTINGS_DEFAULTS",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        currentClassID = 1
        currentSpecIndex = 2

        ns = TestHelpers.SetupPowerBarTickMarksEnv({
            getCurrentClassSpec = function()
                return currentClassID, currentSpecIndex, "Warrior", "Fury", "WARRIOR"
            end,
        })
    end)

    it("module loads and exposes only the page spec", function()
        assert.is_table(ns.PowerBarTickMarksOptions)
        assert.are.equal("tickMarks", ns.PowerBarTickMarksOptions.key)
        assert.is_nil(ns.PowerBarTickMarksStore)
    end)

    it("exports a page with list-based tick editors", function()
        local captured = registerPageSpec()

        assert.are.equal("Tick Marks", captured.name)
        assert.is_nil(getRow(captured, "tickMarksPageActions"))
        assert.are.equal("list", getRow(captured, "tickCollection").type)
        assert.are.equal("editor", getRow(captured, "tickCollection").variant)
        assert.are.equal(320, getRow(captured, "tickCollection").height)
    end)

    it("shows an empty collection when class/spec is unavailable", function()
        currentClassID = nil
        currentSpecIndex = nil

        local captured = registerPageSpec()
        local tickCollection = getRow(captured, "tickCollection")

        assert.are.same({}, tickCollection.items())
    end)

    it("add button appends a tick using the current defaults", function()
        local scheduledReason
        ns.Runtime = {
            ScheduleLayoutUpdate = function(_, reason)
                scheduledReason = reason
            end,
        }

        local captured, refreshCalls, fakePage = registerPageSpec()
        local defaultColor = { r = 0.1, g = 0.2, b = 0.3, a = 0.4 }
        local tickCollection = getRow(captured, "tickCollection")

        getRow(captured, "defaultWidth").set(3)
        getRow(captured, "defaultColor").set(defaultColor)

        getRow(captured, "addTick").onClick({ page = fakePage })

        local items = tickCollection.items()
        assert.are.equal(1, #items)
        assert.are.equal(50, items[1].fields[1].value)
        assert.are.equal(3, items[1].fields[2].value)
        assert.are.same(defaultColor, items[1].color.value)
        assert.are.equal("OptionsChanged", scheduledReason)
        assert.are.same({ true }, refreshCalls)
    end)

    it("collection editor callbacks update color, values, widths, and removal without touching another spec", function()
        local scheduledReasons = {}
        local pickedColor = { r = 0.25, g = 0.5, b = 0.75, a = 1 }

        setTickMappings({
            [1] = {
                [1] = {
                    { value = 20, width = 1, color = { r = 0.5, g = 0.5, b = 0.5, a = 1 } },
                },
                [2] = {
                    { value = 50, width = 2, color = { r = 1, g = 1, b = 1, a = 1 } },
                    { value = 80, width = 3, color = { r = 0, g = 0, b = 0, a = 1 } },
                },
            },
        })

        ns.Runtime = {
            ScheduleLayoutUpdate = function(_, reason)
                scheduledReasons[#scheduledReasons + 1] = reason
            end,
        }
        ns.OptionUtil.OpenColorPicker = function(current, withAlpha, onChanged)
            assert.are.same({ r = 1, g = 1, b = 1, a = 1 }, current)
            assert.is_true(withAlpha)
            onChanged(pickedColor)
        end

        local captured, refreshCalls = registerPageSpec()
        local tickCollection = getRow(captured, "tickCollection")
        local item = tickCollection.items()[1]

        item.color.onClick()
        local items = tickCollection.items()
        assert.are.same(pickedColor, items[1].color.value)

        item = items[1]

        item.fields[1].onValueChanged(75)
        item.fields[2].onValueChanged(4)

        items = tickCollection.items()
        assert.are.equal(75, items[1].fields[1].value)
        assert.are.equal(4, items[1].fields[2].value)

        item = items[1]

        item.remove.onClick()

        items = tickCollection.items()
        assert.are.equal(1, #items)
        assert.are.equal(80, items[1].fields[1].value)

        currentSpecIndex = 1
        items = tickCollection.items()
        assert.are.equal(1, #items)
        assert.are.equal(20, items[1].fields[1].value)
        assert.are.same({ "OptionsChanged", "OptionsChanged", "OptionsChanged", "OptionsChanged" }, scheduledReasons)
        assert.are.equal(4, #refreshCalls)
    end)

    it("rescales the value field range for large resource values", function()
        setTickMappings({
            [1] = {
                [2] = {
                    { value = 50000, width = 2, color = { r = 1, g = 1, b = 1, a = 1 } },
                },
            },
        })

        local captured = registerPageSpec()
        local item = getRow(captured, "tickCollection").items()[1]
        local minValue, maxValue, step = item.fields[1].getRange(item, 50000)
        local nextMin, nextMax, nextStep = item.fields[1].getRange(item, 120000)

        assert.are.equal(1, minValue)
        assert.are.equal(50000, maxValue)
        assert.are.equal(250, step)
        assert.are.equal(1, nextMin)
        assert.are.equal(500000, nextMax)
        assert.are.equal(2500, nextStep)
    end)
end)
