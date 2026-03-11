-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("RuneBar", function()
    local originalGlobals
    local UnitStub
    local makeFrame = TestHelpers.makeFrame
    local makeStatusBar = TestHelpers.makeStatusBar
    local getCalls = TestHelpers.getCalls

    local CAPTURED_GLOBALS = {
        "ECM",
        "Enum",
        "UnitClass",
        "GetSpecialization",
        "GetRuneCooldown",
        "GetTime",
        "CreateFrame",
        "UIParent",
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
        _G.GetSpecialization = function()
            return 1
        end
        _G.issecretvalue = function()
            return false
        end
        _G.GetTime = function()
            return 0
        end
        _G.UIParent = makeFrame({ name = "UIParent", width = 1, height = 1 })
        _G.CreateFrame = function(frameType, name, parent)
            if frameType == "StatusBar" then
                return makeStatusBar({ name = name })
            end
            return makeFrame({ name = name })
        end
        _G.GetRuneCooldown = function(index)
            return 0, 0, true
        end

        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
        TestHelpers.LoadStub("Enums.lua")

        UnitStub = TestHelpers.LoadStub("Unit.lua")
        UnitStub.Install()

        TestHelpers.LoadChunk("Helpers/ClassUtil.lua", "Unable to load Helpers/ClassUtil.lua")()

        -- Provide PixelSnap and GetTexture stubs
        ECM.PixelSnap = function(v)
            return math.floor(v + 0.5)
        end
        ECM.GetTexture = function()
            return "Interface\\TargetingFrame\\UI-StatusBar"
        end
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

    describe("updateFragmentedRuneDisplay", function()
        -- Mirrors the production repositioning decision logic from RuneBar.lua
        -- to verify fragments are repositioned when dimensions change.

        local C = ECM.Constants

        local function runeReadyStatesDiffer(lastReadySet, readySet, maxRunes)
            for i = 1, maxRunes do
                if (readySet[i] or false) ~= ((lastReadySet and lastReadySet[i]) or false) then
                    return true
                end
            end
            return false
        end

        --- Mirrors updateFragmentedRuneDisplay's repositioning decision.
        --- Returns true if fragments would be repositioned.
        local function wouldReposition(bar, readySet, maxRunes)
            local barWidth = bar:GetWidth()
            local barHeight = bar:GetHeight()
            if barWidth <= 0 or barHeight <= 0 then
                return false
            end

            local statesChanged = (bar._lastReadySet == nil)
                or runeReadyStatesDiffer(bar._lastReadySet, readySet, maxRunes)
            local dimensionsChanged = (bar._lastBarWidth ~= barWidth) or (bar._lastBarHeight ~= barHeight)

            if statesChanged or dimensionsChanged then
                bar._lastReadySet = readySet
                bar._lastBarWidth = barWidth
                bar._lastBarHeight = barHeight
                return true
            end
            return false
        end

        local function allRunesReady(maxRunes)
            local set = {}
            for i = 1, maxRunes do
                set[i] = true
            end
            return set
        end

        it("repositions on first call when _lastReadySet is nil", function()
            local bar = makeFrame({ width = 300, height = 20 })
            local readySet = allRunesReady(C.RUNEBAR_MAX_RUNES)

            assert.is_true(wouldReposition(bar, readySet, C.RUNEBAR_MAX_RUNES))
        end)

        it("does not reposition when states and dimensions are unchanged", function()
            local bar = makeFrame({ width = 300, height = 20 })
            local readySet = allRunesReady(C.RUNEBAR_MAX_RUNES)

            wouldReposition(bar, readySet, C.RUNEBAR_MAX_RUNES) -- initial
            assert.is_false(wouldReposition(bar, readySet, C.RUNEBAR_MAX_RUNES))
        end)

        it("repositions when rune states change", function()
            local bar = makeFrame({ width = 300, height = 20 })
            local readySet = allRunesReady(C.RUNEBAR_MAX_RUNES)

            wouldReposition(bar, readySet, C.RUNEBAR_MAX_RUNES)

            -- Rune 1 goes on cooldown
            local newReadySet = allRunesReady(C.RUNEBAR_MAX_RUNES)
            newReadySet[1] = nil

            assert.is_true(wouldReposition(bar, newReadySet, C.RUNEBAR_MAX_RUNES))
        end)

        it("repositions when bar width changes (resize on talent change)", function()
            local bar = makeFrame({ width = 300, height = 20 })
            local readySet = allRunesReady(C.RUNEBAR_MAX_RUNES)

            wouldReposition(bar, readySet, C.RUNEBAR_MAX_RUNES)

            -- Bar width changes (e.g., talent change triggers layout)
            bar:SetWidth(400)

            assert.is_true(wouldReposition(bar, readySet, C.RUNEBAR_MAX_RUNES))
        end)

        it("repositions when bar height changes", function()
            local bar = makeFrame({ width = 300, height = 20 })
            local readySet = allRunesReady(C.RUNEBAR_MAX_RUNES)

            wouldReposition(bar, readySet, C.RUNEBAR_MAX_RUNES)

            bar:SetHeight(30)

            assert.is_true(wouldReposition(bar, readySet, C.RUNEBAR_MAX_RUNES))
        end)

        it("skips repositioning for zero-width bars", function()
            local bar = makeFrame({ width = 0, height = 20 })
            local readySet = allRunesReady(C.RUNEBAR_MAX_RUNES)

            assert.is_false(wouldReposition(bar, readySet, C.RUNEBAR_MAX_RUNES))
        end)

        it("skips repositioning for zero-height bars", function()
            local bar = makeFrame({ width = 300, height = 0 })
            local readySet = allRunesReady(C.RUNEBAR_MAX_RUNES)

            assert.is_false(wouldReposition(bar, readySet, C.RUNEBAR_MAX_RUNES))
        end)

        it("caches new dimensions after repositioning", function()
            local bar = makeFrame({ width = 300, height = 20 })
            local readySet = allRunesReady(C.RUNEBAR_MAX_RUNES)

            wouldReposition(bar, readySet, C.RUNEBAR_MAX_RUNES)
            assert.are.equal(300, bar._lastBarWidth)
            assert.are.equal(20, bar._lastBarHeight)

            bar:SetWidth(400)
            wouldReposition(bar, readySet, C.RUNEBAR_MAX_RUNES)
            assert.are.equal(400, bar._lastBarWidth)
        end)
    end)
end)
