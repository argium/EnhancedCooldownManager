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

describe("OptionBuilder", function()
    local originalGlobals
    local addonNS
    local layoutUpdateCalls
    local notifyChangeCalls

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

    local function deepEquals(a, b)
        if type(a) ~= type(b) then
            return false
        end
        if type(a) ~= "table" then
            return a == b
        end

        for k, v in pairs(a) do
            if not deepEquals(v, b[k]) then
                return false
            end
        end
        for k in pairs(b) do
            if a[k] == nil then
                return false
            end
        end
        return true
    end

    setup(function()
        originalGlobals = TestHelpers.captureGlobals({
            "ECM",
            "ECM_CloneValue",
            "ECM_DeepEquals",
            "LibStub",
            "UnitClass",
            "GetSpecialization",
            "GetSpecializationInfo",
        })
    end)

    teardown(function()
        TestHelpers.restoreGlobals(originalGlobals)
    end)

    before_each(function()
        layoutUpdateCalls = 0
        notifyChangeCalls = 0

        _G.ECM = {
            Constants = {
                ANCHORMODE_CHAIN = 1,
                ANCHORMODE_FREE = 2,
                DEFAULT_BAR_WIDTH = 300,
            },
            SharedMediaOptions = {
                GetFontValues = function()
                    return {
                        Expressway = "Expressway",
                        ["Global Font"] = "Global Font",
                        ["Module Font"] = "Module Font",
                    }
                end,
            },
            ScheduleLayoutUpdate = function()
                layoutUpdateCalls = layoutUpdateCalls + 1
            end,
        }
        _G.ECM_CloneValue = deepClone
        _G.ECM_DeepEquals = deepEquals
        _G.UnitClass = function()
            return "Warrior", "WARRIOR", 1
        end
        _G.GetSpecialization = function()
            return 1
        end
        _G.GetSpecializationInfo = function()
            return nil, "Arms"
        end
        _G.LibStub = function(name)
            if name == "AceConfigRegistry-3.0" then
                return {
                    NotifyChange = function()
                        notifyChangeCalls = notifyChangeCalls + 1
                    end,
                }
            end
            return {}
        end

        addonNS = {
            Addon = {
                db = {
                    profile = {
                        debug = false,
                        global = {
                            hideWhenMounted = true,
                            value = 5,
                            mode = "solid",
                            font = "Global Font",
                            fontSize = 11,
                            color = { r = 0.1, g = 0.2, b = 0.3, a = 1 },
                            nested = {
                                enabled = true,
                            },
                        },
                        powerBar = {
                            height = 10,
                            overrideFont = false,
                        },
                    },
                    defaults = {
                        profile = {
                            debug = false,
                            global = {
                                hideWhenMounted = true,
                                value = 5,
                                mode = "solid",
                                font = "Global Font",
                                fontSize = 11,
                                color = { r = 0.1, g = 0.2, b = 0.3, a = 1 },
                                nested = {
                                    enabled = true,
                                },
                            },
                            powerBar = {
                                height = 10,
                                overrideFont = false,
                            },
                        },
                    },
                },
            },
        }

        local optionUtilChunk = TestHelpers.loadChunk(
            { "Options/OptionUtil.lua", "../Options/OptionUtil.lua" },
            "Unable to load Options/OptionUtil.lua"
        )
        optionUtilChunk(nil, addonNS)

        local optionBuilderChunk = TestHelpers.loadChunk(
            { "Options/OptionBuilder.lua", "../Options/OptionBuilder.lua" },
            "Unable to load Options/OptionBuilder.lua"
        )
        optionBuilderChunk(nil, addonNS)
    end)

    it("MergeArgs merges source into target and returns target", function()
        local target = { a = 1 }
        local result = ECM.OptionBuilder.MergeArgs(target, { b = 2, c = 3 })

        assert.are.same(target, result)
        assert.are.same({ a = 1, b = 2, c = 3 }, target)
    end)

    it("MakeGroup and MakeInlineGroup build group shells", function()
        local group = ECM.OptionBuilder.MakeGroup({
            name = "Root",
            order = 1,
            args = { foo = { type = "description" } },
            childGroups = "tree",
        })
        local inlineGroup = ECM.OptionBuilder.MakeInlineGroup("Inline", 2, {}, {
            disabled = function() return false end,
        })

        assert.are.equal("group", group.type)
        assert.are.equal("Root", group.name)
        assert.are.equal(1, group.order)
        assert.are.equal("tree", group.childGroups)
        assert.is_table(group.args)

        assert.are.equal("group", inlineGroup.type)
        assert.are.equal("Inline", inlineGroup.name)
        assert.are.equal(2, inlineGroup.order)
        assert.is_true(inlineGroup.inline)
        assert.is_function(inlineGroup.disabled)
    end)

    it("MakeDescription, MakeSpacer and MakeHeader build expected controls", function()
        local desc = ECM.OptionBuilder.MakeDescription({
            name = function() return "dynamic" end,
            order = 1,
            fontSize = "medium",
        })
        local spacer = ECM.OptionBuilder.MakeSpacer(2)
        local header = ECM.OptionBuilder.MakeHeader({ name = "Header", order = 3 })

        assert.are.equal("description", desc.type)
        assert.is_function(desc.name)
        assert.are.equal("medium", desc.fontSize)
        assert.are.equal("\n", spacer.name)
        assert.are.equal("header", header.type)
        assert.are.equal("Header", header.name)
    end)

    it("MakeControl preserves fields and wraps set when refresh flags are provided", function()
        local setCalls = 0
        local opt = ECM.OptionBuilder.MakeControl({
            type = "range",
            name = "Value",
            order = 1,
            min = 1,
            max = 5,
            step = 1,
            hasAlpha = false,
            set = function(_, value)
                setCalls = setCalls + value
            end,
            notify = true,
        })

        assert.are.equal("range", opt.type)
        assert.are.equal(1, opt.min)
        assert.are.equal(5, opt.max)
        assert.are.equal(1, opt.step)

        opt.set(nil, 3)
        assert.are.equal(3, setCalls)
        assert.are.equal(1, layoutUpdateCalls)
        assert.are.equal(1, notifyChangeCalls)
    end)

    it("MakeActionButton wraps func refresh semantics", function()
        local invoked = 0
        local button = ECM.OptionBuilder.MakeActionButton({
            name = "Do it",
            order = 1,
            func = function()
                invoked = invoked + 1
            end,
            layout = false,
            notify = true,
        })

        assert.are.equal("execute", button.type)
        button.func()

        assert.are.equal(1, invoked)
        assert.are.equal(0, layoutUpdateCalls)
        assert.are.equal(1, notifyChangeCalls)
    end)

    it("MakePathToggle reads/writes nested values and triggers layout", function()
        local opt = ECM.OptionBuilder.MakePathToggle({
            path = "global.hideWhenMounted",
            name = "Hide",
            order = 1,
        })

        assert.is_true(opt.get())
        opt.set(nil, false)

        assert.is_false(addonNS.Addon.db.profile.global.hideWhenMounted)
        assert.are.equal(1, layoutUpdateCalls)
    end)

    it("MakePathRange preserves nil from setTransform (height sentinel)", function()
        local opt = ECM.OptionBuilder.MakePathRange({
            path = "powerBar.height",
            name = "Height",
            order = 1,
            min = 0,
            max = 40,
            step = 1,
            setTransform = function(value)
                return value > 0 and value or nil
            end,
            getTransform = function(value)
                return value or 0
            end,
        })

        assert.are.equal(10, opt.get())
        opt.set(nil, 0)

        assert.is_nil(addonNS.Addon.db.profile.powerBar.height)
    end)

    it("MakePathColor writes color tuples and defaults alpha when omitted", function()
        local opt = ECM.OptionBuilder.MakePathColor({
            path = "global.color",
            name = "Color",
            order = 1,
        })

        opt.set(nil, 0.4, 0.5, 0.6)

        assert.are.same({ r = 0.4, g = 0.5, b = 0.6, a = 1 }, addonNS.Addon.db.profile.global.color)
        assert.are.equal(1, layoutUpdateCalls)
    end)

    it("MakeResetButton hidden tracks default equality", function()
        local button = ECM.OptionBuilder.MakeResetButton({
            path = "global.value",
            order = 1,
        })

        assert.is_true(button.hidden())

        addonNS.Addon.db.profile.global.value = 8
        assert.is_false(button.hidden())
    end)

    it("notify=true triggers AceConfig notify", function()
        local opt = ECM.OptionBuilder.MakePathToggle({
            path = "global.hideWhenMounted",
            name = "Hide",
            order = 1,
            notify = true,
        })

        opt.set(nil, false)
        assert.are.equal(1, notifyChangeCalls)
    end)

    it("layout=false skips layout refresh", function()
        local opt = ECM.OptionBuilder.MakePathToggle({
            path = "global.hideWhenMounted",
            name = "Hide",
            order = 1,
            layout = false,
        })

        opt.set(nil, false)
        assert.are.equal(0, layoutUpdateCalls)
    end)

    it("BuildPath*WithReset produces paired controls and reset buttons", function()
        local rangeArgs = ECM.OptionBuilder.BuildPathRangeWithReset("height", {
            path = "powerBar.height",
            name = "Height",
            order = 4,
            min = 0,
            max = 40,
            step = 1,
            getTransform = function(value)
                return value or 0
            end,
            setTransform = function(value)
                return value > 0 and value or nil
            end,
            resetOrder = 5,
        })
        local selectArgs = ECM.OptionBuilder.BuildPathSelectWithReset("mode", {
            path = "global.mode",
            name = "Mode",
            order = 6,
            values = { solid = "Solid", flat = "Flat" },
            resetOrder = 7,
        })
        local colorArgs = ECM.OptionBuilder.BuildPathColorWithReset("tint", {
            path = "global.color",
            name = "Tint",
            order = 8,
            hasAlpha = true,
            resetOrder = 9,
        })

        assert.is_table(rangeArgs.height)
        assert.is_table(rangeArgs.heightReset)
        assert.is_table(selectArgs.mode)
        assert.is_table(selectArgs.modeReset)
        assert.is_table(colorArgs.tint)
        assert.is_table(colorArgs.tintReset)

        rangeArgs.height.set(nil, 0)
        assert.is_nil(addonNS.Addon.db.profile.powerBar.height)

        selectArgs.mode.set(nil, "flat")
        assert.are.equal("flat", addonNS.Addon.db.profile.global.mode)

        colorArgs.tint.set(nil, 0.9, 0.8, 0.7, 0.6)
        assert.are.same({ r = 0.9, g = 0.8, b = 0.7, a = 0.6 }, addonNS.Addon.db.profile.global.color)
    end)

    it("BuildFontOverrideArgs builds module font controls with global fallback getters", function()
        local args = ECM.OptionBuilder.BuildFontOverrideArgs("powerBar", 20)

        assert.is_table(args.fontOverrideDesc)
        assert.is_table(args.overrideFont)
        assert.is_table(args.font)
        assert.is_table(args.fontReset)
        assert.is_table(args.fontSize)
        assert.is_table(args.fontSizeReset)

        assert.is_true(args.font.disabled())
        assert.is_true(args.fontReset.disabled())
        assert.is_true(args.fontSize.disabled())
        assert.is_true(args.fontSizeReset.disabled())
        assert.are.equal("Global Font", args.font.get())
        assert.are.equal(11, args.fontSize.get())

        addonNS.Addon.db.profile.powerBar.overrideFont = true
        addonNS.Addon.db.profile.global.fontSize = 13
        assert.is_false(args.font.disabled())
        assert.is_false(args.fontReset.disabled())
        assert.is_false(args.fontSize.disabled())
        assert.is_false(args.fontSizeReset.disabled())
        assert.are.equal("Global Font", args.font.get())
        assert.are.equal(13, args.fontSize.get())

        args.font.set(nil, "Module Font")
        args.fontSize.set(nil, 20)
        assert.are.equal("Module Font", addonNS.Addon.db.profile.powerBar.font)
        assert.are.equal(20, addonNS.Addon.db.profile.powerBar.fontSize)
        assert.are.equal("Module Font", args.font.get())
        assert.are.equal(20, args.fontSize.get())

        addonNS.Addon.db.profile.powerBar.fontSize = nil
        assert.are.equal(13, args.fontSize.get())
    end)

    it("DisabledWhenPathFalse/True evaluate current profile values", function()
        local disabledWhenFalse = ECM.OptionBuilder.DisabledWhenPathFalse("global.nested.enabled")
        local disabledWhenTrue = ECM.OptionBuilder.DisabledWhenPathTrue("global.nested.enabled")

        assert.is_false(disabledWhenFalse())
        assert.is_true(disabledWhenTrue())

        addonNS.Addon.db.profile.global.nested.enabled = false
        assert.is_true(disabledWhenFalse())
        assert.is_false(disabledWhenTrue())
    end)

    it("class predicates reflect UnitClass token", function()
        assert.is_true(ECM.OptionBuilder.IsPlayerClass("WARRIOR"))
        assert.is_false(ECM.OptionBuilder.IsPlayerClass("DEATHKNIGHT"))
        assert.is_false(ECM.OptionBuilder.DisabledIfPlayerClass("DEATHKNIGHT")())
        assert.is_true(ECM.OptionBuilder.DisabledUnlessPlayerClass("DEATHKNIGHT")())

        _G.UnitClass = function()
            return "Death Knight", "DEATHKNIGHT", 6
        end

        assert.is_true(ECM.OptionBuilder.IsPlayerClass("DEATHKNIGHT"))
        assert.is_true(ECM.OptionBuilder.DisabledIfPlayerClass("DEATHKNIGHT")())
        assert.is_false(ECM.OptionBuilder.DisabledUnlessPlayerClass("DEATHKNIGHT")())
    end)

    it("RegisterSection initializes namespace and stores section", function()
        local ns = {}
        local section = { GetOptionsTable = function() return {} end }

        local result = ECM.OptionBuilder.RegisterSection(ns, "Foo", section)

        assert.are.same(section, result)
        assert.is_table(ns.OptionsSections)
        assert.are.same(section, ns.OptionsSections.Foo)
    end)

    it("MakeLayoutSetHandler supports notify without layout", function()
        local invoked = false
        local handler = ECM.OptionBuilder.MakeLayoutSetHandler(function()
            invoked = true
        end, {
            layout = false,
            notify = true,
        })

        handler()

        assert.is_true(invoked)
        assert.are.equal(0, layoutUpdateCalls)
        assert.are.equal(1, notifyChangeCalls)
    end)
end)
