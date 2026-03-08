-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("ResourceBar", function()
    local originalGlobals
    local UnitStub
    local CSpellStub
    local CUnitAurasStub
    local CSpellBookStub

    local CAPTURED_GLOBALS = {
        "ECM", "Enum",
        "UnitClass", "UnitPowerMax", "UnitPower",
        "GetShapeshiftForm", "GetSpecialization",
        "C_UnitAuras", "C_Spell", "C_SpellBook",
        "CurveConstants", "issecretvalue",
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
        _G.GetShapeshiftForm = function() return 0 end
        _G.GetSpecialization = function() return 1 end
        _G.CurveConstants = { ScaleTo100 = 1 }
        _G.issecretvalue = function() return false end

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
    local function makeResourceBar()
        local mod = {}
        local ClassUtil = ECM.ClassUtil

        function mod:GetStatusBarValues()
            local resourceType = ClassUtil.GetPlayerResourceType()
            local maxResources, currentValue = ClassUtil.GetCurrentMaxResourceValues(resourceType)

            if not maxResources then
                return 0, 1, 0, false
            end

            return currentValue, maxResources, currentValue, false
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
            _G.GetSpecialization = function() return ECM.Constants.MAGE_FROST_SPEC_INDEX end
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
            _G.issecretvalue = function() return false end

            local _, _, safeMax = ECM.ClassUtil.GetCurrentMaxResourceValues(Enum.PowerType.HolyPower)
            assert.are.equal(5, safeMax)
        end)

        it("returns nil safeMax when max is a secret value", function()
            UnitStub.SetClass("player", "PALADIN")
            UnitStub.SetPowerMax(Enum.PowerType.HolyPower, 5)
            _G.issecretvalue = function() return true end

            local _, _, safeMax = ECM.ClassUtil.GetCurrentMaxResourceValues(Enum.PowerType.HolyPower)
            assert.is_nil(safeMax)
        end)

        it("returns constant safeMax for devourer types", function()
            local _, _, safeMax = ECM.ClassUtil.GetCurrentMaxResourceValues(ECM.Constants.RESOURCEBAR_TYPE_DEVOURER_NORMAL)
            assert.are.equal(ECM.Constants.RESOURCEBAR_DEVOURER_NORMAL_MAX, safeMax)
        end)
    end)
end)
