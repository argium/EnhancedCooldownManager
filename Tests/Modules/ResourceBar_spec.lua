-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("ResourceBar", function()
    local originalGlobals
    local UnitStub
    local CSpellStub
    local CUnitAurasStub
    local CSpellBookStub

    local CAPTURED_GLOBALS = {
        "ECM",
        "Enum",
        "UnitClass",
        "UnitPowerMax",
        "UnitPower",
        "GetShapeshiftForm",
        "GetSpecialization",
        "C_UnitAuras",
        "C_Spell",
        "C_SpellBook",
        "CurveConstants",
        "issecretvalue",
    }

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals(CAPTURED_GLOBALS)
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        _G.ECM = {}
        _G.ECM.DebugAssert = function() end
        _G.ECM.Log = function() end
        _G.GetShapeshiftForm = function()
            return 0
        end
        _G.GetSpecialization = function()
            return 1
        end
        _G.CurveConstants = { ScaleTo100 = 1 }
        _G.issecretvalue = function()
            return false
        end

        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
        TestHelpers.LoadStub("Enums.lua")

        UnitStub = TestHelpers.LoadStub("Unit.lua")
        CSpellStub = TestHelpers.LoadStub("C_Spell.lua")
        CUnitAurasStub = TestHelpers.LoadStub("C_UnitAuras.lua")
        CSpellBookStub = TestHelpers.LoadStub("C_SpellBook.lua")

        UnitStub.Install()
        CSpellStub.Install()
        CUnitAurasStub.Install()
        CSpellBookStub.Install()

        TestHelpers.LoadChunk("Helpers/ClassUtil.lua", "Unable to load Helpers/ClassUtil.lua")()
    end)

    --- Creates a minimal ResourceBar stub with the changed methods loaded.
    local function makeResourceBar(moduleConfig)
        local mod = {}
        local ClassUtil = ECM.ClassUtil

        function mod:GetModuleConfig()
            return moduleConfig or {}
        end

        function mod:GetStatusBarValues()
            local resourceType = ClassUtil.GetPlayerResourceType()
            local maxResources, currentValue = ClassUtil.GetCurrentMaxResourceValues(resourceType)

            if not maxResources then
                return 0, 1, 0, false
            end

            return currentValue, maxResources, currentValue, false
        end

        function mod:GetStatusBarColor()
            local cfg = self:GetModuleConfig()
            local resourceType = ClassUtil.GetPlayerResourceType()

            if
                ECM.Constants.RESOURCEBAR_MAX_COLOR_TYPES[resourceType]
                and cfg.maxColorsEnabled
                and cfg.maxColorsEnabled[resourceType]
            then
                local _, current, safeMax = ClassUtil.GetCurrentMaxResourceValues(resourceType)
                if safeMax and current == safeMax then
                    return cfg.maxColors and cfg.maxColors[resourceType] or ECM.Constants.COLOR_WHITE
                end
            end

            local color = cfg.colors and cfg.colors[resourceType]
            return color or ECM.Constants.COLOR_WHITE
        end

        return mod
    end

    describe("GetStatusBarValues", function()
        it("returns fallback when no resource type exists", function()
            UnitStub.SetClass("player", "WARRIOR")
            local mod = makeResourceBar()
            local current, max, display, isFraction = mod:GetStatusBarValues()

            assert.are.equal(0, current)
            assert.are.equal(1, max)
            assert.are.equal(0, display)
            assert.are.equal(false, isFraction)
        end)

        it("returns resource values for standard discrete types", function()
            UnitStub.SetClass("player", "PALADIN")
            UnitStub.SetPowerMax(Enum.PowerType.HolyPower, 5)
            UnitStub.SetPower(Enum.PowerType.HolyPower, 3)
            local mod = makeResourceBar()
            local current, max, display, isFraction = mod:GetStatusBarValues()

            assert.are.equal(3, current)
            assert.are.equal(5, max)
            assert.are.equal(3, display)
            assert.are.equal(false, isFraction)
        end)

        it("returns resource values for special types", function()
            UnitStub.SetClass("player", "MAGE")
            _G.GetSpecialization = function()
                return ECM.Constants.MAGE_FROST_SPEC_INDEX
            end
            CUnitAurasStub.SetAura(ECM.Constants.RESOURCEBAR_ICICLES_SPELLID, { applications = 4 })
            local mod = makeResourceBar()
            local current, max, display, isFraction = mod:GetStatusBarValues()

            assert.are.equal(4, current)
            assert.are.equal(ECM.Constants.RESOURCEBAR_ICICLES_MAX, max)
            assert.are.equal(4, display)
            assert.are.equal(false, isFraction)
        end)

        it("does not perform boolean coercion on secret values", function()
            -- When maxResources is returned from UnitPowerMax (potentially secret),
            -- GetStatusBarValues should not use 'or 0' coercion or '<= 0' comparison
            UnitStub.SetClass("player", "PALADIN")
            UnitStub.SetPowerMax(Enum.PowerType.HolyPower, 5)
            UnitStub.SetPower(Enum.PowerType.HolyPower, 0)
            local mod = makeResourceBar()
            local current, max, display, isFraction = mod:GetStatusBarValues()

            -- current is 0 from UnitPower, max is 5 — both passed through without coercion
            assert.are.equal(0, current)
            assert.are.equal(5, max)
            assert.are.equal(false, isFraction)
        end)
    end)

    describe("safeMax (3rd return) integration", function()
        it("returns non-secret safeMax for tick layout", function()
            UnitStub.SetClass("player", "PALADIN")
            UnitStub.SetPowerMax(Enum.PowerType.HolyPower, 5)
            _G.issecretvalue = function()
                return false
            end

            local _, _, safeMax = ECM.ClassUtil.GetCurrentMaxResourceValues(Enum.PowerType.HolyPower)
            assert.are.equal(5, safeMax)
        end)

        it("returns nil safeMax when max is a secret value", function()
            UnitStub.SetClass("player", "PALADIN")
            UnitStub.SetPowerMax(Enum.PowerType.HolyPower, 5)
            _G.issecretvalue = function()
                return true
            end

            local _, _, safeMax = ECM.ClassUtil.GetCurrentMaxResourceValues(Enum.PowerType.HolyPower)
            assert.is_nil(safeMax)
        end)

        it("returns constant safeMax for devourer types", function()
            local _, _, safeMax =
                ECM.ClassUtil.GetCurrentMaxResourceValues(ECM.Constants.RESOURCEBAR_TYPE_DEVOURER_NORMAL)
            assert.are.equal(ECM.Constants.RESOURCEBAR_DEVOURER_NORMAL_MAX, safeMax)
        end)
    end)

    describe("GetStatusBarColor", function()
        local C

        before_each(function()
            C = ECM.Constants
        end)

        it("returns max color when type supported, enabled, and at max", function()
            UnitStub.SetClass("player", "MAGE")
            _G.GetSpecialization = function()
                return C.MAGE_FROST_SPEC_INDEX
            end
            CUnitAurasStub.SetAura(C.RESOURCEBAR_ICICLES_SPELLID, { applications = C.RESOURCEBAR_ICICLES_MAX })

            local maxColor = { r = 0.5, g = 0.5, b = 0.5, a = 1 }
            local mod = makeResourceBar({
                colors = { [C.RESOURCEBAR_TYPE_ICICLES] = { r = 0.72, g = 0.9, b = 1.0, a = 1 } },
                maxColorsEnabled = { [C.RESOURCEBAR_TYPE_ICICLES] = true },
                maxColors = { [C.RESOURCEBAR_TYPE_ICICLES] = maxColor },
            })

            local color = mod:GetStatusBarColor()
            assert.are.equal(maxColor, color)
        end)

        it("returns normal color when enabled but not at max", function()
            UnitStub.SetClass("player", "MAGE")
            _G.GetSpecialization = function()
                return C.MAGE_FROST_SPEC_INDEX
            end
            CUnitAurasStub.SetAura(C.RESOURCEBAR_ICICLES_SPELLID, { applications = 3 })

            local normalColor = { r = 0.72, g = 0.9, b = 1.0, a = 1 }
            local mod = makeResourceBar({
                colors = { [C.RESOURCEBAR_TYPE_ICICLES] = normalColor },
                maxColorsEnabled = { [C.RESOURCEBAR_TYPE_ICICLES] = true },
                maxColors = { [C.RESOURCEBAR_TYPE_ICICLES] = { r = 0.5, g = 0.5, b = 0.5, a = 1 } },
            })

            local color = mod:GetStatusBarColor()
            assert.are.equal(normalColor, color)
        end)

        it("returns normal color when max color is disabled even at max", function()
            UnitStub.SetClass("player", "MAGE")
            _G.GetSpecialization = function()
                return C.MAGE_FROST_SPEC_INDEX
            end
            CUnitAurasStub.SetAura(C.RESOURCEBAR_ICICLES_SPELLID, { applications = C.RESOURCEBAR_ICICLES_MAX })

            local normalColor = { r = 0.72, g = 0.9, b = 1.0, a = 1 }
            local mod = makeResourceBar({
                colors = { [C.RESOURCEBAR_TYPE_ICICLES] = normalColor },
                maxColorsEnabled = { [C.RESOURCEBAR_TYPE_ICICLES] = false },
                maxColors = { [C.RESOURCEBAR_TYPE_ICICLES] = { r = 0.5, g = 0.5, b = 0.5, a = 1 } },
            })

            local color = mod:GetStatusBarColor()
            assert.are.equal(normalColor, color)
        end)

        it("returns normal color for types not in RESOURCEBAR_MAX_COLOR_TYPES", function()
            UnitStub.SetClass("player", "PALADIN")
            UnitStub.SetPowerMax(Enum.PowerType.HolyPower, 5)
            UnitStub.SetPower(Enum.PowerType.HolyPower, 5)
            _G.issecretvalue = function()
                return false
            end

            local normalColor = { r = 0.88, g = 0.82, b = 0.24, a = 1 }
            local mod = makeResourceBar({
                colors = { [Enum.PowerType.HolyPower] = normalColor },
                maxColorsEnabled = { [Enum.PowerType.HolyPower] = true },
                maxColors = { [Enum.PowerType.HolyPower] = { r = 1, g = 0, b = 0, a = 1 } },
            })

            local color = mod:GetStatusBarColor()
            assert.are.equal(normalColor, color)
        end)

        it("falls back to COLOR_WHITE when no colors configured", function()
            UnitStub.SetClass("player", "MAGE")
            _G.GetSpecialization = function()
                return C.MAGE_FROST_SPEC_INDEX
            end
            CUnitAurasStub.SetAura(C.RESOURCEBAR_ICICLES_SPELLID, { applications = 2 })

            local mod = makeResourceBar({})
            local color = mod:GetStatusBarColor()
            assert.are.equal(C.COLOR_WHITE, color)
        end)

        it("falls back to COLOR_WHITE when max color enabled but maxColors table missing", function()
            UnitStub.SetClass("player", "MAGE")
            _G.GetSpecialization = function()
                return C.MAGE_FROST_SPEC_INDEX
            end
            CUnitAurasStub.SetAura(C.RESOURCEBAR_ICICLES_SPELLID, { applications = C.RESOURCEBAR_ICICLES_MAX })

            local mod = makeResourceBar({
                maxColorsEnabled = { [C.RESOURCEBAR_TYPE_ICICLES] = true },
            })

            local color = mod:GetStatusBarColor()
            assert.are.equal(C.COLOR_WHITE, color)
        end)
    end)
end)

describe("ResourceBar real source", function()
    local originalGlobals
    local ResourceBar
    local ns
    local currentResourceType
    local currentValues

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({ "ECM" })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        currentResourceType = "icicles"
        currentValues = { 5, 2, 5 }

        _G.ECM = {
            FrameMixin = {
                ShouldShow = function()
                    return true
                end,
            },
            BarMixin = {
                Refresh = function()
                    return true
                end,
            },
            ClassUtil = {
                GetPlayerResourceType = function()
                    return currentResourceType
                end,
                GetCurrentMaxResourceValues = function()
                    return currentValues[1], currentValues[2], currentValues[3]
                end,
            },
            Log = function() end,
        }
        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()

        ns = {
            Addon = {
                NewModule = function(self, name)
                    local module = { Name = name }
                    self[name] = module
                    return module
                end,
            },
        }

        TestHelpers.LoadChunk("Modules/ResourceBar.lua", "Unable to load Modules/ResourceBar.lua")(nil, ns)
        ResourceBar = assert(ns.Addon.ResourceBar, "ResourceBar module did not initialize")
    end)

    it("ShouldShow requires a current resource type", function()
        assert.is_true(ResourceBar:ShouldShow())

        currentResourceType = nil
        assert.is_false(ResourceBar:ShouldShow())
    end)

    it("Refresh lays out ticks for safe discrete resources", function()
        local ensureCount
        local layoutCount
        local hidePoolKey
        ResourceBar.InnerFrame = { TicksFrame = {} }
        function ResourceBar:EnsureTicks(count)
            ensureCount = count
        end
        function ResourceBar:LayoutResourceTicks(maxResources)
            layoutCount = maxResources
        end
        function ResourceBar:HideAllTicks(poolKey)
            hidePoolKey = poolKey
        end

        assert.is_true(ResourceBar:Refresh("test"))
        assert.are.equal(4, ensureCount)
        assert.are.equal(5, layoutCount)
        assert.is_nil(hidePoolKey)
    end)

    it("Refresh hides ticks for devourer resources", function()
        local hidePoolKey
        currentResourceType = ECM.Constants.RESOURCEBAR_TYPE_DEVOURER_NORMAL
        currentValues = { 30, 4, 30 }
        ResourceBar.InnerFrame = { TicksFrame = {} }
        function ResourceBar:EnsureTicks()
            error("EnsureTicks should not be called for devourer resources")
        end
        function ResourceBar:LayoutResourceTicks()
            error("LayoutResourceTicks should not be called for devourer resources")
        end
        function ResourceBar:HideAllTicks(poolKey)
            hidePoolKey = poolKey
        end

        assert.is_true(ResourceBar:Refresh("test"))
        assert.are.equal("tickPool", hidePoolKey)
    end)
end)
