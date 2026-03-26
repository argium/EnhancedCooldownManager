-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("PowerBar real source", function()
    local originalGlobals
    local PowerBar
    local ns
    local registerFrameCalls
    local unregisterFrameCalls
    local addMixinCalls
    local unitPowerValue
    local unitPowerMaxValue
    local unitPowerPercentValue
    local isSecretValue

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "ECM",
            "Enum",
            "UnitClass",
            "GetSpecialization",
            "GetSpecializationRole",
            "UnitPower",
            "UnitPowerMax",
            "UnitPowerPercent",
            "CurveConstants",
            "issecretvalue",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        registerFrameCalls = 0
        unregisterFrameCalls = 0
        addMixinCalls = 0
        unitPowerValue = 37
        unitPowerMaxValue = 100
        unitPowerPercentValue = 37
        isSecretValue = false

        _G.ECM = {
            FrameMixin = {
                Proto = {
                    ShouldShow = function()
                        return true
                    end,
                },
            },
            BarMixin = {
                AddMixin = function(target)
                    addMixinCalls = addMixinCalls + 1
                    target.EnsureFrame = target.EnsureFrame or function() end
                end,
            },
            ClassUtil = {
                GetCurrentPowerType = function()
                    return Enum.PowerType.Mana
                end,
            },
            Runtime = {
                RegisterFrame = function()
                    registerFrameCalls = registerFrameCalls + 1
                end,
                UnregisterFrame = function()
                    unregisterFrameCalls = unregisterFrameCalls + 1
                end,
            },
            Log = function() end,
        }
        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
        TestHelpers.LoadStub("Enums.lua")

        _G.UnitClass = function()
            return "Mage", "MAGE", 8
        end
        _G.GetSpecialization = function()
            return 2
        end
        _G.GetSpecializationRole = function()
            return "DAMAGER"
        end
        _G.UnitPower = function()
            return unitPowerValue
        end
        _G.UnitPowerMax = function()
            return unitPowerMaxValue
        end
        _G.UnitPowerPercent = function()
            return unitPowerPercentValue
        end
        _G.CurveConstants = { ScaleTo100 = 1 }
        _G.issecretvalue = function()
            return isSecretValue
        end

        ns = {
            Addon = {
                NewModule = function(self, name)
                    local module = { Name = name }
                    self[name] = module
                    return module
                end,
            },
        }

        TestHelpers.LoadChunk("Modules/PowerBar.lua", "Unable to load Modules/PowerBar.lua")(nil, ns)
        PowerBar = assert(ns.Addon.PowerBar, "PowerBar module did not initialize")
    end)

    it("returns the current class and spec tick mapping", function()
        local expectedTicks = {
            { value = 35 },
            { value = 70 },
        }
        PowerBar.GetModuleConfig = function()
            return {
                ticks = {
                    mappings = {
                        [8] = {
                            [2] = expectedTicks,
                        },
                    },
                },
            }
        end

        assert.are.equal(expectedTicks, PowerBar:GetCurrentTicks())
    end)

    it("hides mana bars for tank specs in ShouldShow", function()
        assert.is_true(PowerBar:ShouldShow())

        _G.GetSpecializationRole = function()
            return "TANK"
        end
        assert.is_false(PowerBar:ShouldShow())
    end)

    it("shows mana bars for configured mana classes and hides them for others", function()
        _G.GetSpecializationRole = function()
            return "DAMAGER"
        end

        _G.UnitClass = function()
            return "Mage", "MAGE", 8
        end
        assert.is_true(PowerBar:ShouldShow())

        _G.UnitClass = function()
            return "Paladin", "PALADIN", 2
        end
        assert.is_false(PowerBar:ShouldShow())
    end)

    it("returns mana percentage text when configured", function()
        unitPowerValue = 40
        unitPowerMaxValue = 100
        unitPowerPercentValue = 40
        PowerBar.GetModuleConfig = function()
            return { showManaAsPercent = true }
        end

        local current, max, display, isFraction = PowerBar:GetStatusBarValues()

        assert.are.equal(40, current)
        assert.are.equal(100, max)
        assert.are.equal("40%", display)
        assert.is_true(isFraction)
    end)

    it("returns raw values when mana percentage is disabled", function()
        unitPowerValue = 55
        unitPowerMaxValue = 120
        PowerBar.GetModuleConfig = function()
            return { showManaAsPercent = false }
        end

        local current, max, display, isFraction = PowerBar:GetStatusBarValues()

        assert.are.equal(55, current)
        assert.are.equal(120, max)
        assert.are.equal(55, display)
        assert.is_false(isFraction)
    end)

    it("returns configured status bar colors and falls back to white", function()
        PowerBar.GetModuleConfig = function()
            return {
                colors = {
                    [Enum.PowerType.Mana] = { r = 0.1, g = 0.2, b = 0.3, a = 1 },
                },
            }
        end
        assert.same({ r = 0.1, g = 0.2, b = 0.3, a = 1 }, PowerBar:GetStatusBarColor())

        PowerBar.GetModuleConfig = function()
            return { colors = {} }
        end
        assert.are.equal(ECM.Constants.COLOR_WHITE, PowerBar:GetStatusBarColor())
    end)

    it("only responds to UNIT_POWER_UPDATE for the player", function()
        local reasons = {}
        function PowerBar:ThrottledUpdateLayout(reason)
            reasons[#reasons + 1] = reason
        end

        PowerBar:OnUnitPowerUpdate("UNIT_POWER_UPDATE", "target")
        PowerBar:OnUnitPowerUpdate("UNIT_POWER_UPDATE", "player")

        assert.same({ "UNIT_POWER_UPDATE" }, reasons)
    end)

    it("registered callback drops LibEvent target and forwards event args", function()
        local captured = {}
        function PowerBar:RegisterEvent(event, cb)
            captured[event] = cb
        end
        function PowerBar:UnregisterAllEvents() end

        PowerBar:OnInitialize()
        PowerBar:OnEnable()

        local reasons = {}
        function PowerBar:ThrottledUpdateLayout(reason)
            reasons[#reasons + 1] = reason
        end

        local cb = assert(captured["UNIT_POWER_UPDATE"], "expected UNIT_POWER_UPDATE registration")
        -- LibEvent dispatches cb(target, event, ...wowArgs)
        cb(PowerBar, "UNIT_POWER_UPDATE", "player")
        assert.same({ "UNIT_POWER_UPDATE" }, reasons)
    end)

    it("registers and unregisters with the frame system", function()
        function PowerBar:RegisterEvent() end
        function PowerBar:UnregisterAllEvents() end

        PowerBar:OnInitialize()
        PowerBar:OnEnable()
        PowerBar:OnDisable()

        assert.are.equal(1, addMixinCalls)
        assert.are.equal(1, registerFrameCalls)
        assert.are.equal(1, unregisterFrameCalls)
    end)

    it("returns nil tick mappings when config, class, or spec data is missing", function()
        PowerBar.GetModuleConfig = function()
            return nil
        end
        assert.is_nil(PowerBar:GetCurrentTicks())

        PowerBar.GetModuleConfig = function()
            return { ticks = { mappings = {} } }
        end
        _G.UnitClass = function()
            return "Mage", "MAGE", nil
        end
        assert.is_nil(PowerBar:GetCurrentTicks())

        _G.UnitClass = function()
            return "Mage", "MAGE", 8
        end
        _G.GetSpecialization = function()
            return nil
        end
        assert.is_nil(PowerBar:GetCurrentTicks())
    end)

    it("UpdateTicks hides ticks when no mappings are configured", function()
        local hiddenPoolKey
        PowerBar.GetCurrentTicks = function()
            return nil
        end
        function PowerBar:HideAllTicks(poolKey)
            hiddenPoolKey = poolKey
        end

        PowerBar:UpdateTicks({ TicksFrame = {}, StatusBar = {} }, 100)

        assert.are.equal("tickPool", hiddenPoolKey)
    end)

    it("UpdateTicks ensures and lays out ticks using configured defaults", function()
        local ensured
        local layoutArgs
        local ticks = {
            { value = 25 },
            { value = 75, color = { r = 1, g = 0, b = 0, a = 1 }, width = 2 },
        }
        PowerBar.GetCurrentTicks = function()
            return ticks
        end
        PowerBar.GetModuleConfig = function()
            return {
                ticks = {
                    defaultColor = { r = 0.3, g = 0.4, b = 0.5, a = 0.6 },
                    defaultWidth = 3,
                },
            }
        end
        function PowerBar:EnsureTicks(count, parent, poolKey)
            ensured = { count = count, parent = parent, poolKey = poolKey }
        end
        function PowerBar:LayoutValueTicks(statusBar, mappedTicks, max, defaultColor, defaultWidth, poolKey)
            layoutArgs = {
                statusBar = statusBar,
                mappedTicks = mappedTicks,
                max = max,
                defaultColor = defaultColor,
                defaultWidth = defaultWidth,
                poolKey = poolKey,
            }
        end

        local frame = { TicksFrame = {}, StatusBar = {} }
        PowerBar:UpdateTicks(frame, 125)

        assert.same({ count = 2, parent = frame.TicksFrame, poolKey = "tickPool" }, ensured)
        assert.are.equal(frame.StatusBar, layoutArgs.statusBar)
        assert.are.equal(ticks, layoutArgs.mappedTicks)
        assert.are.equal(125, layoutArgs.max)
        assert.same({ r = 0.3, g = 0.4, b = 0.5, a = 0.6 }, layoutArgs.defaultColor)
        assert.are.equal(3, layoutArgs.defaultWidth)
        assert.are.equal("tickPool", layoutArgs.poolKey)
    end)

    it("_OnBarRefreshed updates ticks when max power is visible", function()
        local updatedMax
        local hiddenPoolKey
        PowerBar.InnerFrame = { TicksFrame = {}, StatusBar = {} }
        function PowerBar:UpdateTicks(_, max)
            updatedMax = max
        end
        function PowerBar:HideAllTicks(poolKey)
            hiddenPoolKey = poolKey
        end

        PowerBar:_OnBarRefreshed("test")
        assert.are.equal(unitPowerMaxValue, updatedMax)
        assert.is_nil(hiddenPoolKey)
    end)

    it("_OnBarRefreshed hides ticks when max power is secret", function()
        local updatedMax
        local hiddenPoolKey
        isSecretValue = true
        PowerBar.InnerFrame = { TicksFrame = {}, StatusBar = {} }
        function PowerBar:UpdateTicks(_, max)
            updatedMax = max
        end
        function PowerBar:HideAllTicks(poolKey)
            hiddenPoolKey = poolKey
        end

        PowerBar:_OnBarRefreshed("test")
        assert.is_nil(updatedMax)
        assert.are.equal("tickPool", hiddenPoolKey)
    end)

    it("shows non-mana power bars and respects the outer frame visibility guard", function()
        ECM.FrameMixin.Proto.ShouldShow = function()
            return false
        end
        assert.is_false(PowerBar:ShouldShow())

        ECM.FrameMixin.Proto.ShouldShow = function()
            return true
        end
        ECM.ClassUtil.GetCurrentPowerType = function()
            return Enum.PowerType.Energy
        end
        _G.GetSpecializationRole = function()
            return "TANK"
        end

        assert.is_true(PowerBar:ShouldShow())
    end)
end)
