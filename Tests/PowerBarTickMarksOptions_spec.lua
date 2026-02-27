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
    local addonNS
    local ticks
    local updateCalls
    local addCalls
    local removeCalls
    local setCalls
    local layoutCalls
    local notifyCalls

    local function MakeOptionBuilderStub()
        local stub = {}

        function stub.LayoutChanged()
            layoutCalls = layoutCalls + 1
        end

        function stub.NotifyOptionsChanged()
            notifyCalls = notifyCalls + 1
        end

        function stub.MakeLayoutSetHandler(fn, opts)
            opts = opts or {}
            return function(...)
                fn(...)
                if opts.layout ~= false then
                    stub.LayoutChanged()
                end
                if opts.notify then
                    stub.NotifyOptionsChanged()
                end
            end
        end

        function stub.MakeControl(spec)
            local option = {
                type = spec.type,
                name = spec.name,
                desc = spec.desc,
                order = spec.order,
                width = spec.width,
                min = spec.min,
                max = spec.max,
                step = spec.step,
                hasAlpha = spec.hasAlpha,
                hidden = spec.hidden,
                disabled = spec.disabled,
                confirm = spec.confirm,
                confirmText = spec.confirmText,
                get = spec.get,
            }

            if spec.set then
                if spec.layout ~= nil or spec.notify ~= nil then
                    option.set = stub.MakeLayoutSetHandler(spec.set, {
                        layout = spec.layout,
                        notify = spec.notify,
                    })
                else
                    option.set = spec.set
                end
            end

            if spec.func then
                if spec.layout ~= nil or spec.notify ~= nil then
                    option.func = stub.MakeLayoutSetHandler(spec.func, {
                        layout = spec.layout,
                        notify = spec.notify,
                    })
                else
                    option.func = spec.func
                end
            end

            return option
        end

        function stub.MakeActionButton(spec)
            local copy = {}
            for k, v in pairs(spec) do
                copy[k] = v
            end
            copy.type = "execute"
            return stub.MakeControl(copy)
        end

        function stub.MakeHeader(spec)
            return {
                type = "header",
                name = spec.name,
                order = spec.order,
            }
        end

        function stub.MakeDescription(spec)
            return {
                type = "description",
                name = spec.name,
                order = spec.order,
                fontSize = spec.fontSize,
                width = spec.width,
                hidden = spec.hidden,
                disabled = spec.disabled,
            }
        end

        function stub.MakeSpacer(order, opts)
            opts = opts or {}
            return {
                type = "description",
                name = opts.name or " ",
                order = order,
                hidden = opts.hidden,
            }
        end

        function stub.MakeInlineGroup(name, order, args, opts)
            opts = opts or {}
            return {
                type = "group",
                name = name,
                order = order,
                inline = true,
                args = args,
                disabled = opts.disabled,
                hidden = opts.hidden,
            }
        end

        return stub
    end

    setup(function()
        originalGlobals = TestHelpers.captureGlobals({ "ECM" })
    end)

    teardown(function()
        TestHelpers.restoreGlobals(originalGlobals)
    end)

    before_each(function()
        ticks = {
            { value = 50, width = 2, color = { r = 0.2, g = 0.4, b = 0.6, a = 0.8 } },
        }
        updateCalls = {}
        addCalls = {}
        removeCalls = {}
        setCalls = {}
        layoutCalls = 0
        notifyCalls = 0

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
            OptionBuilder = MakeOptionBuilderStub(),
            PowerBarTickMarksStore = {
                GetCurrentTicks = function()
                    return ticks
                end,
                SetCurrentTicks = function(newTicks)
                    setCalls[#setCalls + 1] = newTicks
                    ticks = newTicks
                end,
                AddTick = function(value, color, width)
                    addCalls[#addCalls + 1] = { value = value, color = color, width = width }
                    ticks[#ticks + 1] = { value = value, width = width or 1, color = color or { r = 1, g = 1, b = 1, a = 1 } }
                end,
                RemoveTick = function(index)
                    removeCalls[#removeCalls + 1] = index
                    table.remove(ticks, index)
                end,
                UpdateTick = function(index, field, value)
                    updateCalls[#updateCalls + 1] = { index = index, field = field, value = value }
                    ticks[index][field] = value
                end,
                GetDefaultColor = function()
                    return { r = 0.9, g = 0.8, b = 0.7, a = 0.6 }
                end,
                SetDefaultColor = function(color)
                    setCalls[#setCalls + 1] = { defaultColor = color }
                end,
                GetDefaultWidth = function()
                    return 3
                end,
                SetDefaultWidth = function(width)
                    setCalls[#setCalls + 1] = { defaultWidth = width }
                end,
            },
        }

        addonNS = {
            Addon = {},
        }

        local chunk = TestHelpers.loadChunk(
            { "Options/PowerBarTickMarksOptions.lua", "../Options/PowerBarTickMarksOptions.lua" },
            "Unable to load Options/PowerBarTickMarksOptions.lua"
        )
        chunk(nil, addonNS)
    end)

    it("builds dynamic tick args and updates ticks with refresh", function()
        local group = ECM.PowerBarTickMarksOptions.GetOptionsGroup()
        local tickArgs = group.args.ticks.args

        assert.is_table(tickArgs.tickValue1)
        assert.is_table(tickArgs.tickWidth1)
        assert.is_table(tickArgs.tickColor1)
        assert.is_table(tickArgs.tickRemove1)
        assert.are.equal("header", tickArgs.tickHeader1.type)

        tickArgs.tickValue1.set(nil, 60)
        assert.are.equal(1, #updateCalls)
        assert.are.same({ index = 1, field = "value", value = 60 }, updateCalls[1])
        assert.are.equal(1, layoutCalls)
        assert.are.equal(1, notifyCalls)
    end)

    it("add and clear actions call store and refresh", function()
        local group = ECM.PowerBarTickMarksOptions.GetOptionsGroup()

        group.args.addTick.func()
        assert.are.equal(1, #addCalls)
        assert.are.equal(50, addCalls[1].value)

        group.args.clearAll.func()
        assert.are.equal(1, #setCalls)
        assert.are.same({}, setCalls[1])

        assert.are.equal(2, layoutCalls)
        assert.are.equal(2, notifyCalls)
    end)

    it("default color/default width setters preserve no-refresh behavior", function()
        local group = ECM.PowerBarTickMarksOptions.GetOptionsGroup()

        group.args.defaultColor.set(nil, 0.1, 0.2, 0.3, 0.4)
        group.args.defaultWidth.set(nil, 4)

        assert.are.equal(2, #setCalls)
        assert.are.same({ defaultColor = { r = 0.1, g = 0.2, b = 0.3, a = 0.4 } }, setCalls[1])
        assert.are.same({ defaultWidth = 4 }, setCalls[2])
        assert.are.equal(0, layoutCalls)
        assert.are.equal(0, notifyCalls)
    end)

    it("current spec label and empty count message render safely", function()
        local group = ECM.PowerBarTickMarksOptions.GetOptionsGroup()
        local specLabel = group.args.currentSpec.name()
        local countLabel = group.args.tickCount.name()

        assert.is_truthy(string.find(specLabel, "Warrior", 1, true))
        assert.is_truthy(string.find(specLabel, "Fury", 1, true))
        assert.is_truthy(string.find(countLabel, "1 tick mark", 1, true))

        ticks = {}
        assert.is_truthy(string.find(group.args.tickCount.name(), "No tick marks", 1, true))
        assert.is_true(group.args.clearAll.disabled())
    end)
end)
