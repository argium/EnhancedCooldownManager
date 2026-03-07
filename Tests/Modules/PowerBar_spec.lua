-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("PowerBar", function()
    local originalGlobals
    local UnitStub

    local CAPTURED_GLOBALS = {
        "ECM", "Enum",
        "UnitClass", "UnitPowerMax", "UnitPower", "UnitPowerType",
        "GetSpecialization", "GetSpecializationRole",
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
        _G.ECM.Log = function() end
        _G.ECM.DebugAssert = function() end
        _G.GetSpecialization = function() return 1 end
        _G.GetSpecializationRole = function() return "DAMAGER" end
        _G.CurveConstants = { ScaleTo100 = 1 }
        _G.issecretvalue = function() return false end

        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
        TestHelpers.LoadStub("Enums.lua")

        UnitStub = TestHelpers.LoadStub("Unit.lua")
        UnitStub.Install()

        _G.UnitPowerType = function() return Enum.PowerType.Energy end

        TestHelpers.LoadChunk("Helpers/ClassUtil.lua", "Unable to load Helpers/ClassUtil.lua")()
    end)

    --- Creates a minimal PowerBar stub that mirrors the Refresh tick logic.
    local function makePowerBar()
        local mod = {
            InnerFrame = {
                StatusBar = {},
                TicksFrame = {},
            },
            tickPool = {},
            _updateTicksCalled = false,
            _updateTicksMax = nil,
        }

        function mod:UpdateTicks(frame, powerType, max)
            self._updateTicksCalled = true
            self._updateTicksMax = max
        end

        -- Mirror the production Refresh tick logic
        function mod:RefreshTicks()
            local powerType = ECM.ClassUtil.GetCurrentPowerType()
            local max = UnitPowerMax("player", powerType)
            if not issecretvalue(max) then
                self:UpdateTicks(self.InnerFrame, powerType, max)
            end
        end

        return mod
    end

    describe("Refresh tick updates", function()
        it("calls UpdateTicks when max is not a secret value", function()
            UnitStub.SetClass("player", "ROGUE")
            _G.UnitPowerType = function() return Enum.PowerType.Energy end
            UnitStub.SetPowerMax(Enum.PowerType.Energy, 100)
            _G.issecretvalue = function() return false end

            local mod = makePowerBar()
            mod:RefreshTicks()

            assert.is_true(mod._updateTicksCalled)
            assert.are.equal(100, mod._updateTicksMax)
        end)

        it("skips UpdateTicks when max is a secret value", function()
            UnitStub.SetClass("player", "ROGUE")
            _G.UnitPowerType = function() return Enum.PowerType.Energy end
            UnitStub.SetPowerMax(Enum.PowerType.Energy, 100)
            _G.issecretvalue = function() return true end

            local mod = makePowerBar()
            mod:RefreshTicks()

            assert.is_false(mod._updateTicksCalled)
            assert.is_nil(mod._updateTicksMax)
        end)

        it("calls UpdateTicks with correct max value", function()
            UnitStub.SetClass("player", "ROGUE")
            _G.UnitPowerType = function() return Enum.PowerType.Energy end
            UnitStub.SetPowerMax(Enum.PowerType.Energy, 150)
            _G.issecretvalue = function() return false end

            local mod = makePowerBar()
            mod:RefreshTicks()

            assert.are.equal(150, mod._updateTicksMax)
        end)
    end)
end)
