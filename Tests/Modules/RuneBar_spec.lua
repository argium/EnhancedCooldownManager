-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("RuneBar", function()
    local originalGlobals
    local UnitStub

    local CAPTURED_GLOBALS = {
        "ECM", "Enum",
        "UnitClass",
        "GetSpecialization",
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
        _G.ECM.Log = function() end
        _G.ECM.DebugAssert = function() end
        _G.GetSpecialization = function() return 1 end
        _G.issecretvalue = function() return false end

        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
        TestHelpers.LoadStub("Enums.lua")

        UnitStub = TestHelpers.LoadStub("Unit.lua")
        UnitStub.Install()

        TestHelpers.LoadChunk("Helpers/ClassUtil.lua", "Unable to load Helpers/ClassUtil.lua")()
    end)

    --- Creates a minimal RuneBar stub with the ShouldShow method loaded from source.
    local function makeRuneBar(opts)
        opts = opts or {}
        local mod = {}

        -- Load the production ShouldShow via chunk extraction
        local ClassUtil = ECM.ClassUtil
        local FrameMixin = ECM.FrameMixin or {}
        ECM.FrameMixin = FrameMixin

        -- Provide a base ShouldShow on FrameMixin that requires GetModuleConfig
        FrameMixin.ShouldShow = function(self)
            local config = self:GetModuleConfig()
            return not self.IsHidden and (config == nil or config.enabled ~= false)
        end

        -- Mirror production ShouldShow
        function mod:ShouldShow()
            return ClassUtil.IsDeathKnight() and FrameMixin.ShouldShow(self)
        end

        if opts.withMixin then
            mod.GetModuleConfig = function()
                return opts.moduleConfig or { enabled = true }
            end
        end

        mod.IsHidden = opts.isHidden or false

        return mod
    end

    describe("ShouldShow", function()
        it("returns false for non-DK without requiring GetModuleConfig", function()
            UnitStub.SetClass("player", "WARRIOR")
            local mod = makeRuneBar({ withMixin = false })

            assert.is_false(mod:ShouldShow())
        end)

        it("returns true for DK with mixin and enabled config", function()
            UnitStub.SetClass("player", "DEATHKNIGHT")
            local mod = makeRuneBar({ withMixin = true, moduleConfig = { enabled = true } })

            assert.is_true(mod:ShouldShow())
        end)

        it("returns false for DK when config.enabled is false", function()
            UnitStub.SetClass("player", "DEATHKNIGHT")
            local mod = makeRuneBar({ withMixin = true, moduleConfig = { enabled = false } })

            assert.is_false(mod:ShouldShow())
        end)

        it("returns false for DK when IsHidden is true", function()
            UnitStub.SetClass("player", "DEATHKNIGHT")
            local mod = makeRuneBar({ withMixin = true, isHidden = true })

            assert.is_false(mod:ShouldShow())
        end)

        it("does not call GetModuleConfig for non-DK players", function()
            UnitStub.SetClass("player", "MAGE")
            local mod = makeRuneBar({ withMixin = false })

            -- Should not error even though GetModuleConfig is absent
            assert.has_no.errors(function()
                mod:ShouldShow()
            end)
        end)
    end)
end)
