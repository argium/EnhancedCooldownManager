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

describe("Options sections and root assembly", function()
    local originalGlobals

    setup(function()
        originalGlobals = TestHelpers.captureGlobals({
            "ECM",
            "LibStub",
            "ColorUtil",
            "Settings",
            "UnitClass",
            "Enum",
        })
    end)

    teardown(function()
        TestHelpers.restoreGlobals(originalGlobals)
    end)

    it("root Options module assembles expected top-level sections", function()
        local registeredOptionsFactory
        local createdModule

        _G.ECM = {
            Constants = { ADDON_NAME = "EnhancedCooldownManager" },
            ScheduleLayoutUpdate = function() end,
        }
        _G.ColorUtil = {
            Sparkle = function(name)
                return name
            end,
        }
        _G.Settings = {
            OpenToCategory = function() end,
        }
        _G.LibStub = function(name)
            if name == "AceConfigRegistry-3.0" then
                return {
                    RegisterOptionsTable = function(_, _, factory)
                        registeredOptionsFactory = factory
                    end,
                }
            end
            if name == "AceConfigDialog-3.0" then
                return {
                    AddToBlizOptions = function()
                        return { name = "Enhanced Cooldown Manager" }
                    end,
                }
            end
            return {}
        end

        local dbCallbacks = {}
        local mod = {
            db = {
                RegisterCallback = function(_, owner, eventName, methodName)
                    dbCallbacks[#dbCallbacks + 1] = { owner = owner, eventName = eventName, methodName = methodName }
                end,
            },
            ItemIconsOptions = {
                GetOptionsTable = function()
                    return { type = "group", name = "Item Icons", order = 6, args = {} }
                end,
            },
            NewModule = function(self, name)
                createdModule = { moduleName = name }
                return createdModule
            end,
        }

        local ns = {
            Addon = mod,
            BuffBarsOptions = {
                GetOptionsTable = function()
                    return { type = "group", name = "Aura Bars", order = 5, args = {} }
                end,
            },
            OptionsSections = {
                General = { GetOptionsTable = function() return { order = 1 } end },
                PowerBar = { GetOptionsTable = function() return { order = 2 } end },
                ResourceBar = { GetOptionsTable = function() return { order = 3 } end },
                RuneBar = { GetOptionsTable = function() return { order = 4 } end },
                Profile = { GetOptionsTable = function() return { order = 7 } end },
                About = { GetOptionsTable = function() return { order = 8 } end },
            },
        }

        local chunk = TestHelpers.loadChunk(
            { "Options/Options.lua", "../Options/Options.lua" },
            "Unable to load Options/Options.lua"
        )
        chunk(nil, ns)

        assert.is_table(createdModule)
        createdModule:OnInitialize()

        assert.is_function(registeredOptionsFactory)
        local root = registeredOptionsFactory()
        assert.is_table(root.args)
        assert.is_not_nil(root.args.general)
        assert.is_not_nil(root.args.powerBar)
        assert.is_not_nil(root.args.resourceBar)
        assert.is_not_nil(root.args.runeBar)
        assert.is_not_nil(root.args.auraBars)
        assert.is_not_nil(root.args.itemIcons)
        assert.is_not_nil(root.args.profile)
        assert.is_not_nil(root.args.about)
        assert.are.equal("tree", root.childGroups)
        assert.are.equal(3, #dbCallbacks)
    end)

    it("resource/rune sections preserve Death Knight gating", function()
        local className = "WARRIOR"

        _G.Enum = {
            PowerType = {
                ArcaneCharges = 1,
                Chi = 2,
                ComboPoints = 3,
                Essence = 4,
                HolyPower = 5,
                SoulShards = 6,
            },
        }
        _G.UnitClass = function()
            return "Player", className, 1
        end
        _G.ECM = {
            Constants = {
                CLASS = { DEATHKNIGHT = "DEATHKNIGHT" },
                RESOURCEBAR_TYPE_MAELSTROM_WEAPON = "maelstromWeapon",
            },
            OptionBuilder = {
                MergeArgs = function(target, source)
                    for k, v in pairs(source or {}) do
                        target[k] = v
                    end
                    return target
                end,
                MakeGroup = function(spec)
                    return {
                        type = "group",
                        name = spec.name,
                        order = spec.order,
                        args = spec.args or {},
                        inline = spec.inline,
                        disabled = spec.disabled,
                        hidden = spec.hidden,
                    }
                end,
                MakeInlineGroup = function(name, order, args, opts)
                    opts = opts or {}
                    return {
                        type = "group",
                        name = name,
                        order = order,
                        inline = true,
                        args = args or {},
                        disabled = opts.disabled,
                        hidden = opts.hidden,
                    }
                end,
                MakeDescription = function(spec)
                    return {
                        type = "description",
                        name = spec.name,
                        order = spec.order,
                    }
                end,
                MakeSpacer = function(order, opts)
                    opts = opts or {}
                    return {
                        type = "description",
                        name = opts.name or " ",
                        order = order,
                    }
                end,
                BuildModuleEnabledToggle = function(_, _, label, order)
                    return { type = "toggle", name = label, order = order }
                end,
                BuildHeightOverrideArgs = function()
                    return {
                        heightDesc = { type = "description", order = 3 },
                        height = { type = "range", order = 4 },
                        heightReset = { type = "execute", order = 5 },
                    }
                end,
                BuildBorderArgs = function()
                    return {}
                end,
                BuildColorPickerList = function()
                    return {}
                end,
                BuildPathColorWithReset = function(key, spec)
                    local args = {}
                    args[key] = {
                        type = "color",
                        name = spec.name,
                        order = spec.order,
                        disabled = spec.disabled,
                    }
                    args[key .. "Reset"] = {
                        type = "execute",
                        order = spec.resetOrder,
                        disabled = spec.resetDisabled,
                    }
                    return args
                end,
                MakePathToggle = function(spec)
                    return { type = "toggle", name = spec.name, order = spec.order }
                end,
                DisabledWhenPathTrue = function(_)
                    return function()
                        return false
                    end
                end,
                DisabledIfPlayerClass = function(classToken)
                    return function()
                        local _, playerClass = UnitClass("player")
                        return playerClass == classToken
                    end
                end,
                DisabledUnlessPlayerClass = function(classToken)
                    return function()
                        local _, playerClass = UnitClass("player")
                        return playerClass ~= classToken
                    end
                end,
                RegisterSection = function(namespace, key, section)
                    namespace.OptionsSections = namespace.OptionsSections or {}
                    namespace.OptionsSections[key] = section
                    return section
                end,
            },
            OptionUtil = {
                MakePositioningGroup = function(_, order)
                    return { type = "group", order = order, args = {} }
                end,
                GetNestedValue = function(tbl, path)
                    local current = tbl
                    for key in path:gmatch("[^.]+") do
                        if type(current) ~= "table" then
                            return nil
                        end
                        current = current[key]
                    end
                    return current
                end,
            },
        }

        local ns = {
            Addon = {
                db = {
                    profile = {
                        runeBar = { useSpecColor = false },
                    },
                },
            },
            OptionsSections = {},
        }

        local resourceChunk = TestHelpers.loadChunk(
            { "Options/ResourceBarOptions.lua", "../Options/ResourceBarOptions.lua" },
            "Unable to load Options/ResourceBarOptions.lua"
        )
        resourceChunk(nil, ns)

        local runeChunk = TestHelpers.loadChunk(
            { "Options/RuneBarOptions.lua", "../Options/RuneBarOptions.lua" },
            "Unable to load Options/RuneBarOptions.lua"
        )
        runeChunk(nil, ns)

        local resourceOptions = ns.OptionsSections.ResourceBar.GetOptionsTable()
        local runeOptions = ns.OptionsSections.RuneBar.GetOptionsTable()

        assert.are.equal(3, resourceOptions.order)
        assert.are.equal(4, runeOptions.order)
        assert.is_false(resourceOptions.disabled())
        assert.is_true(runeOptions.disabled())

        className = "DEATHKNIGHT"
        assert.is_true(resourceOptions.disabled())
        assert.is_false(runeOptions.disabled())
    end)
end)
