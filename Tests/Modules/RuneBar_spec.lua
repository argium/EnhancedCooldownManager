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

describe("RuneBar real source", function()
    local originalGlobals
    local RuneBar
    local ns
    local isDeathKnight
    local addMixinCalls
    local registerFrameCalls
    local tickerCount
    local unregisterFrameCalls
    local makeFrame = TestHelpers.makeFrame
    local createFrameCalls
    local frameRefreshResult
    local now

    setup(function()
        originalGlobals =
            TestHelpers.CaptureGlobals({
                "ECM",
                "C_Timer",
                "CreateFrame",
                "GetSpecialization",
                "UIParent",
                "GetRuneCooldown",
                "GetTime",
            })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        isDeathKnight = false
        addMixinCalls = 0
        registerFrameCalls = 0
        tickerCount = 0
        unregisterFrameCalls = 0
        createFrameCalls = 0
        frameRefreshResult = true
        now = 100

        _G.ECM = {
            FrameMixin = {
                ShouldShow = function()
                    return true
                end,
                Refresh = function()
                    return frameRefreshResult
                end,
                CreateFrame = function(self)
                    local frame = makeFrame({ name = self.Name, shown = true, width = 300, height = 20 })
                    frame.GetFrameLevel = function()
                        return 1
                    end
                    frame.SetFrameLevel = function() end
                    return frame
                end,
            },
            BarMixin = {
                AddMixin = function()
                    addMixinCalls = addMixinCalls + 1
                end,
            },
            ClassUtil = {
                IsDeathKnight = function()
                    return isDeathKnight
                end,
            },
            RegisterFrame = function()
                registerFrameCalls = registerFrameCalls + 1
            end,
            UnregisterFrame = function()
                unregisterFrameCalls = unregisterFrameCalls + 1
            end,
            Log = function() end,
        }
        _G.C_Timer = {
            NewTicker = function(_, callback)
                tickerCount = tickerCount + 1
                return {
                    callback = callback,
                    cancelled = false,
                    Cancel = function(self)
                        self.cancelled = true
                    end,
                }
            end,
        }
        _G.UIParent = makeFrame({ name = "UIParent" })
        _G.GetSpecialization = function()
            return 1
        end
        _G.GetTime = function()
            return now
        end
        _G.GetRuneCooldown = function()
            return 0, 0, true
        end
        _G.CreateFrame = function(frameType, name, parent)
            createFrameCalls = createFrameCalls + 1
            local frame = makeFrame({ name = name, shown = true, width = 300, height = 20 })
            frame.SetFrameLevel = function() end
            frame.GetFrameLevel = function()
                return 1
            end
            frame.SetStatusBarTexture = function() end
            frame.SetMinMaxValues = function() end
            frame.SetValue = function() end
            frame.SetStatusBarColor = function() end
            frame.SetSize = function(self, width, height)
                self:SetWidth(width)
                self:SetHeight(height)
            end
            return frame
        end
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

        TestHelpers.LoadChunk("Modules/RuneBar.lua", "Unable to load Modules/RuneBar.lua")(nil, ns)
        RuneBar = assert(ns.Addon.RuneBar, "RuneBar module did not initialize")
        function RuneBar:IsEnabled()
            return true
        end
        function RuneBar:RegisterEvent() end
        function RuneBar:UnregisterAllEvents() end
    end)

    it("only returns true from ShouldShow for death knights", function()
        assert.is_false(RuneBar:ShouldShow())

        isDeathKnight = true
        assert.is_true(RuneBar:ShouldShow())
    end)

    it("returns early from OnEnable for non-death-knights", function()
        RuneBar:OnEnable()

        assert.are.equal(0, addMixinCalls)
        assert.are.equal(0, registerFrameCalls)
        assert.are.equal(0, tickerCount)
    end)

    it("creates a ticker and registers the frame for death knights", function()
        isDeathKnight = true

        RuneBar:OnEnable()

        assert.are.equal(1, addMixinCalls)
        assert.are.equal(1, registerFrameCalls)
        assert.are.equal(1, tickerCount)
        assert.is_not_nil(RuneBar._valueTicker)
    end)

    it("defers a layout refresh on rune power updates", function()
        local reasons = {}
        function RuneBar:ThrottledUpdateLayout(reason)
            reasons[#reasons + 1] = reason
        end

        RuneBar:OnRunePowerUpdate()

        assert.same({ "RUNE_POWER_UPDATE" }, reasons)
    end)

    it("unregisters the frame and cancels the ticker on disable when needed", function()
        local ticker = {
            cancelled = false,
            Cancel = function(self)
                self.cancelled = true
            end,
        }
        RuneBar.InnerFrame = makeFrame({ shown = true })
        RuneBar._valueTicker = ticker

        RuneBar:OnDisable()

        assert.are.equal(1, unregisterFrameCalls)
        assert.is_true(ticker.cancelled)
        assert.is_nil(RuneBar._valueTicker)
    end)

    it("skips unregistering on disable when no frame exists", function()
        RuneBar:OnDisable()

        assert.are.equal(0, unregisterFrameCalls)
    end)

    it("creates a frame with status and tick containers", function()
        local frame = RuneBar:CreateFrame()

        assert.is_not_nil(frame.StatusBar)
        assert.is_not_nil(frame.TicksFrame)
        assert.same({}, frame.FragmentedBars)
        assert.are.equal(2, createFrameCalls)
    end)

    it("Refresh initializes fragmented bars and lays out ticks", function()
        local ensureTicksCount
        local layoutTicksMax
        local updateArgs
        local frame = {
            StatusBar = {
                SetMinMaxValues = function() end,
                GetWidth = function()
                    return 300
                end,
                GetHeight = function()
                    return 20
                end,
            },
            TicksFrame = {},
            FragmentedBars = {},
            GetWidth = function()
                return 300
            end,
            GetHeight = function()
                return 20
            end,
            GetFrameLevel = function()
                return 1
            end,
            Show = function(self)
                self.__shown = true
            end,
        }
        RuneBar.InnerFrame = frame
        RuneBar.GetModuleConfig = function()
            return { useSpecColor = false, color = { r = 1, g = 0, b = 0 }, texture = "Solid" }
        end
        RuneBar.GetGlobalConfig = function()
            return { texture = "Solid", updateFrequency = 0.04 }
        end
        RuneBar.EnsureTicks = function(_, count)
            ensureTicksCount = count
        end
        RuneBar.LayoutResourceTicks = function(_, maxRunes)
            layoutTicksMax = maxRunes
        end
        ECM.GetTexture = function()
            return "Interface\\TargetingFrame\\UI-StatusBar"
        end
        ECM.PixelSnap = function(v)
            return math.floor(v + 0.5)
        end
        _G.GetRuneCooldown = function(index)
            return 0, 0, true
        end

        assert.is_true(RuneBar:Refresh("test"))
        assert.are.equal(ECM.Constants.RUNEBAR_MAX_RUNES - 1, ensureTicksCount)
        assert.are.equal(ECM.Constants.RUNEBAR_MAX_RUNES, layoutTicksMax)
        assert.is_true(frame.__shown == true)
    end)

    it("returns false from Refresh when the base frame refresh stops the update", function()
        frameRefreshResult = false
        RuneBar.InnerFrame = makeFrame({ shown = true })

        assert.is_false(RuneBar:Refresh("test"))
    end)

    it("ticker hot path updates fragment values without relayout when rune states are unchanged", function()
        local frags = {}
        for i = 1, ECM.Constants.RUNEBAR_MAX_RUNES do
            frags[i] = {
                SetValue = function(self, value)
                    self.__value = value
                end,
                SetStatusBarColor = function(self, r, g, b)
                    self.__color = { r, g, b }
                end,
            }
        end
        RuneBar.InnerFrame = makeFrame({ shown = true, width = 300, height = 20 })
        RuneBar.InnerFrame.FragmentedBars = frags
        RuneBar.InnerFrame._maxResources = ECM.Constants.RUNEBAR_MAX_RUNES
        RuneBar.InnerFrame._lastReadySet = {}
        for i = 1, ECM.Constants.RUNEBAR_MAX_RUNES do
            RuneBar.InnerFrame._lastReadySet[i] = true
        end
        RuneBar.GetModuleConfig = function()
            return { useSpecColor = false, color = { r = 0.8, g = 0.1, b = 0.2 }, texture = "Solid" }
        end
        RuneBar.GetGlobalConfig = function()
            return { updateFrequency = 0.04, texture = "Solid" }
        end
        _G.GetRuneCooldown = function()
            return 0, 0, true
        end
        isDeathKnight = true

        RuneBar:OnEnable()
        RuneBar._valueTicker.callback()

        assert.are.equal(1, frags[1].__value)
        assert.same({ 0.8, 0.1, 0.2 }, frags[1].__color)
    end)

    it("ticker hot path requests relayout when rune ready states change", function()
        local reasons = {}
        local frags = {}
        for i = 1, ECM.Constants.RUNEBAR_MAX_RUNES do
            frags[i] = {
                SetValue = function() end,
                SetStatusBarColor = function() end,
            }
        end
        RuneBar.InnerFrame = makeFrame({ shown = true, width = 300, height = 20 })
        RuneBar.InnerFrame.FragmentedBars = frags
        RuneBar.InnerFrame._maxResources = ECM.Constants.RUNEBAR_MAX_RUNES
        RuneBar.InnerFrame._lastReadySet = {}
        for i = 1, ECM.Constants.RUNEBAR_MAX_RUNES do
            RuneBar.InnerFrame._lastReadySet[i] = true
        end
        RuneBar.GetModuleConfig = function()
            return { useSpecColor = false, color = { r = 0.8, g = 0.1, b = 0.2 }, texture = "Solid" }
        end
        RuneBar.GetGlobalConfig = function()
            return { updateFrequency = 0.04, texture = "Solid" }
        end
        function RuneBar:ThrottledUpdateLayout(reason)
            reasons[#reasons + 1] = reason
        end
        _G.GetRuneCooldown = function(index)
            if index == 1 then
                return 90, 10, false
            end
            return 0, 0, true
        end
        isDeathKnight = true

        RuneBar:OnEnable()
        RuneBar._valueTicker.callback()

        assert.same({ "RuneStateChange" }, reasons)
    end)
end)
