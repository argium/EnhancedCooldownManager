-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("PowerBarTickMarksOptions", function()
    local originalGlobals
    local ns

    local function registerSettings(parentCategory)
        local captured
        local refreshCalls = {}
        local fakeCategory = {}

        local SB = {
            RegisterFromTable = function(tbl)
                captured = tbl
            end,
            GetSubcategory = function(name)
                if name == "Tick Marks" then
                    return fakeCategory
                end
            end,
            RefreshCategory = function(category)
                refreshCalls[#refreshCalls + 1] = category
            end,
        }

        ns.PowerBarTickMarksOptions.RegisterSettings(SB, parentCategory)

        return captured, refreshCalls, fakeCategory
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
        ns = TestHelpers.SetupPowerBarTickMarksEnv()
    end)

    it("module loads and exposes RegisterSettings and Store", function()
        assert.is_table(ns.PowerBarTickMarksOptions)
        assert.is_function(ns.PowerBarTickMarksOptions.RegisterSettings)

        assert.is_table(ns.PowerBarTickMarksStore)
        assert.is_function(ns.PowerBarTickMarksStore.GetCurrentTicks)
        assert.is_function(ns.PowerBarTickMarksStore.AddTick)
    end)

    it("registers a subcategory with collection-based tick editors", function()
        local parentCategory = {}
        local captured = registerSettings(parentCategory)

        assert.are.equal("Tick Marks", captured.name)
        assert.are.equal(parentCategory, captured.parentCategory)
        assert.are.equal("header", captured.args.tickMarksHeader.type)
        assert.are.equal("collection", captured.args.tickCollection.type)
        assert.are.equal("editor", captured.args.tickCollection.preset)
        assert.are.equal(320, captured.args.tickCollection.height)
    end)

    it("add button appends a tick using the current defaults", function()
        local scheduledReason
        ns.Runtime = {
            ScheduleLayoutUpdate = function(_, reason)
                scheduledReason = reason
            end,
        }

        local captured, refreshCalls, fakeCategory = registerSettings({})

        captured.args.addTick.onClick()

        local ticks = ns.PowerBarTickMarksStore.GetCurrentTicks()
        assert.are.equal(1, #ticks)
        assert.are.equal(50, ticks[1].value)
        assert.are.equal(ns.PowerBarTickMarksStore.GetDefaultWidth(), ticks[1].width)
        assert.are.same(ns.PowerBarTickMarksStore.GetDefaultColor(), ticks[1].color)
        assert.are.equal("OptionsChanged", scheduledReason)
        assert.are.same({ fakeCategory }, refreshCalls)
    end)

    it("defaults action clears the current spec ticks after confirmation", function()
        local shownPopup
        local scheduledReason

        _G.StaticPopup_Show = function(name, _, _, data)
            shownPopup = name
            local dialog = _G.StaticPopupDialogs[name]
            dialog.OnAccept(nil, data)
        end
        ns.Runtime = {
            ScheduleLayoutUpdate = function(_, reason)
                scheduledReason = reason
            end,
        }
        ns.PowerBarTickMarksStore.SetCurrentTicks({
            { value = 50, width = 2, color = { r = 1, g = 1, b = 1, a = 1 } },
        })

        local captured, refreshCalls, fakeCategory = registerSettings({})
        local defaultsAction = captured.args.tickMarksHeader.actions[1]

        defaultsAction.onClick()

        assert.are.equal("ECM_CONFIRM_CLEAR_TICKS", shownPopup)
        assert.are.same({}, ns.PowerBarTickMarksStore.GetCurrentTicks())
        assert.are.equal("OptionsChanged", scheduledReason)
        assert.are.same({ fakeCategory }, refreshCalls)
    end)

    it("collection editor callbacks update tick values, widths, and removal", function()
        local scheduledReasons = {}
        ns.Runtime = {
            ScheduleLayoutUpdate = function(_, reason)
                scheduledReasons[#scheduledReasons + 1] = reason
            end,
        }
        ns.PowerBarTickMarksStore.SetCurrentTicks({
            { value = 50, width = 2, color = { r = 1, g = 1, b = 1, a = 1 } },
        })

        local captured, refreshCalls = registerSettings({})
        local item = captured.args.tickCollection.items()[1]

        item.fields[1].onValueChanged(75)
        item.fields[2].onValueChanged(4)

        local ticks = ns.PowerBarTickMarksStore.GetCurrentTicks()
        assert.are.equal(75, ticks[1].value)
        assert.are.equal(4, ticks[1].width)

        item.remove.onClick()

        assert.are.same({}, ns.PowerBarTickMarksStore.GetCurrentTicks())
        assert.are.same({ "OptionsChanged", "OptionsChanged", "OptionsChanged" }, scheduledReasons)
        assert.are.equal(3, #refreshCalls)
    end)

    it("rescales the value field range for large resource values", function()
        ns.PowerBarTickMarksStore.SetCurrentTicks({
            { value = 50000, width = 2, color = { r = 1, g = 1, b = 1, a = 1 } },
        })

        local captured = registerSettings({})
        local item = captured.args.tickCollection.items()[1]
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
