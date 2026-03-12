-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("BuffBars", function()
    local originalGlobals
    local makeFrame = TestHelpers.makeFrame

    local timerCallbacks
    local registeredFrames
    local unregisteredFrames

    local CAPTURED_GLOBALS = {
        "ECM",
        "C_Timer",
        "GetTime",
        "UIParent",
        "CreateFrame",
        "issecretvalue",
        "InCombatLockdown",
        "hooksecurefunc",
        "EditModeManagerFrame",
    }

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals(CAPTURED_GLOBALS)
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        timerCallbacks = {}
        registeredFrames = {}
        unregisteredFrames = {}

        _G.GetTime = function()
            return 0
        end
        _G.UIParent = makeFrame({ name = "UIParent" })
        _G.CreateFrame = function(_, name)
            return makeFrame({ name = name })
        end
        _G.issecretvalue = function()
            return false
        end
        _G.InCombatLockdown = function()
            return false
        end
        _G.hooksecurefunc = function() end
        _G.EditModeManagerFrame = nil

        -- Capture timer callbacks without executing them
        _G.C_Timer = {
            After = function(_, callback)
                timerCallbacks[#timerCallbacks + 1] = callback
            end,
        }

        -- Minimal ECM setup
        _G.ECM = {}
        _G.ECM.ColorUtil = {
            AreEqual = function(a, b)
                if a == nil and b == nil then
                    return true
                end
                if a == nil or b == nil then
                    return false
                end
                return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
            end,
        }
        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
        TestHelpers.LoadChunk("Helpers/FrameUtil.lua", "Unable to load Helpers/FrameUtil.lua")()
        TestHelpers.LoadChunk("Helpers/ModuleMixin.lua", "Unable to load Helpers/ModuleMixin.lua")()
        TestHelpers.LoadChunk("Helpers/FrameMixin.lua", "Unable to load Helpers/FrameMixin.lua")()

        _G.ECM.Log = function() end
        _G.ECM.DebugAssert = function(condition, message)
            if not condition then
                error(message or "ECM.DebugAssert failed")
            end
        end

        ECM.RegisterFrame = function(frame)
            ECM.FrameMixin.AssertValid(frame)
            registeredFrames[#registeredFrames + 1] = frame
        end
        ECM.UnregisterFrame = function(frame)
            unregisteredFrames[#unregisteredFrames + 1] = frame
        end

        -- Remove any prior viewer global
        _G["BuffBarCooldownViewer"] = nil
    end)

    --- Creates a minimal BuffBars module stub with the methods under test.
    local function loadBuffBarsModule()
        local mod = {
            _events = {},
            _viewerHooked = false,
            _editModeHooked = false,
            _registered = false,
        }
        function mod:RegisterEvent(event, handler)
            self._events[event] = handler
        end
        function mod:UnregisterAllEvents()
            self._events = {}
        end
        function mod:IsEnabled()
            return true
        end
        function mod:ThrottledUpdateLayout() end
        function mod:GetGlobalConfig()
            return { barHeight = 22, texture = "Solid" }
        end
        function mod:GetModuleConfig()
            return { enabled = true }
        end

        -- Load the CreateFrame override
        -- Simulate what BuffBars.lua defines
        function mod:CreateFrame()
            return _G["BuffBarCooldownViewer"]
        end

        return mod
    end

    local function flushTimers()
        for _, cb in ipairs(timerCallbacks) do
            cb()
        end
        timerCallbacks = {}
    end

    describe("CreateFrame", function()
        it("returns BuffBarCooldownViewer when it exists", function()
            local viewer = makeFrame({ name = "BuffBarCooldownViewer" })
            _G["BuffBarCooldownViewer"] = viewer

            local mod = loadBuffBarsModule()
            local result = mod:CreateFrame()

            assert.are.equal(viewer, result)
        end)

        it("returns nil when BuffBarCooldownViewer does not exist", function()
            local mod = loadBuffBarsModule()
            local result = mod:CreateFrame()

            assert.is_nil(result)
        end)
    end)

    describe("OnEnable", function()
        local function enableModule(mod)
            -- Simulate OnEnable flow
            ECM.FrameMixin.AddMixin(mod, "BuffBars")

            mod:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnZoneChanged")

            C_Timer.After(0.1, function()
                if not mod.InnerFrame then
                    mod.InnerFrame = _G["BuffBarCooldownViewer"]
                end

                if mod.InnerFrame and not mod._registered then
                    ECM.RegisterFrame(mod)
                    mod._registered = true
                end
            end)
        end

        it("sets InnerFrame to viewer when viewer exists at AddMixin time", function()
            local viewer = makeFrame({ name = "BuffBarCooldownViewer" })
            _G["BuffBarCooldownViewer"] = viewer

            local mod = loadBuffBarsModule()
            enableModule(mod)

            -- InnerFrame set immediately by AddMixin calling CreateFrame
            assert.are.equal(viewer, mod.InnerFrame)
        end)

        it("defers InnerFrame assignment when viewer does not exist at AddMixin time", function()
            local mod = loadBuffBarsModule()
            enableModule(mod)

            -- InnerFrame is nil before timer fires
            assert.is_nil(mod.InnerFrame)
            assert.are.equal(0, #registeredFrames)

            -- Viewer appears before timer fires
            local viewer = makeFrame({ name = "BuffBarCooldownViewer" })
            _G["BuffBarCooldownViewer"] = viewer

            flushTimers()

            assert.are.equal(viewer, mod.InnerFrame)
        end)

        it("does not register when viewer never appears", function()
            local mod = loadBuffBarsModule()
            enableModule(mod)

            flushTimers()

            assert.is_nil(mod.InnerFrame)
            assert.are.equal(0, #registeredFrames)
            assert.is_false(mod._registered)
        end)

        it("registers frame after timer when viewer exists", function()
            local viewer = makeFrame({ name = "BuffBarCooldownViewer" })
            _G["BuffBarCooldownViewer"] = viewer

            local mod = loadBuffBarsModule()
            enableModule(mod)

            -- Not registered yet (timer hasn't fired)
            assert.are.equal(0, #registeredFrames)

            flushTimers()

            assert.are.equal(1, #registeredFrames)
            assert.are.equal(mod, registeredFrames[1])
            assert.is_true(mod._registered)
        end)

        it("does not double-register on repeated timer callbacks", function()
            local viewer = makeFrame({ name = "BuffBarCooldownViewer" })
            _G["BuffBarCooldownViewer"] = viewer

            local mod = loadBuffBarsModule()
            enableModule(mod)
            -- Queue a second timer to simulate re-entry
            enableModule(mod)

            flushTimers()

            assert.are.equal(1, #registeredFrames)
        end)
    end)

    describe("OnDisable", function()
        local function disableModule(mod)
            mod:UnregisterAllEvents()
            if mod._registered then
                ECM.UnregisterFrame(mod)
                mod._registered = false
            end
        end

        it("unregisters when previously registered", function()
            local viewer = makeFrame({ name = "BuffBarCooldownViewer" })
            _G["BuffBarCooldownViewer"] = viewer

            local mod = loadBuffBarsModule()
            ECM.FrameMixin.AddMixin(mod, "BuffBars")
            mod._registered = true
            mod.InnerFrame = viewer

            disableModule(mod)

            assert.are.equal(1, #unregisteredFrames)
            assert.is_false(mod._registered)
        end)

        it("does not error when never registered", function()
            local mod = loadBuffBarsModule()
            ECM.FrameMixin.AddMixin(mod, "BuffBars")

            -- OnDisable before timer fires — no registration occurred
            assert.has_no.errors(function()
                disableModule(mod)
            end)
            assert.are.equal(0, #unregisteredFrames)
        end)
    end)

    describe("InnerFrame identity", function()
        it("AddMixin sets InnerFrame to the viewer via CreateFrame override", function()
            local viewer = makeFrame({ name = "BuffBarCooldownViewer" })
            _G["BuffBarCooldownViewer"] = viewer

            local mod = loadBuffBarsModule()
            ECM.FrameMixin.AddMixin(mod, "BuffBars")

            -- AddMixin calls mod:CreateFrame() which returns the viewer
            assert.are.equal(viewer, mod.InnerFrame)
        end)

        it("AddMixin leaves InnerFrame nil when viewer absent", function()
            local mod = loadBuffBarsModule()
            ECM.FrameMixin.AddMixin(mod, "BuffBars")

            -- CreateFrame returned nil, so InnerFrame stays nil
            assert.is_nil(mod.InnerFrame)
        end)
    end)

    describe("child hook _layoutRunning guard", function()
        --- Simulates hookChildFrame's hook pattern: installs SetPoint, OnShow,
        --- and OnHide hooks on a child frame that check module._layoutRunning.
        --- SetPoint and OnShow synchronously call styleChild before deferring;
        --- OnHide only defers.
        ---@param styleChild fun(child: table)|nil Optional callback simulating styleChildFrame
        local function installChildHooks(child, module, styleChild)
            local origSetPoint = child.SetPoint
            child.SetPoint = function(self, ...)
                origSetPoint(self, ...)
                if module._layoutRunning then
                    return
                end
                module._layoutRunning = true
                if styleChild then
                    styleChild(child)
                end
                module._layoutRunning = nil
                module:ThrottledUpdateLayout("SetPoint:hook", { secondPass = true })
            end

            local origShow = child.Show
            child.Show = function(self)
                origShow(self)
                if module._layoutRunning then
                    return
                end
                module._layoutRunning = true
                if styleChild then
                    styleChild(child)
                end
                module._layoutRunning = nil
                module:ThrottledUpdateLayout("OnShow:child", { secondPass = true })
            end

            local origHide = child.Hide
            child.Hide = function(self)
                origHide(self)
                if module._layoutRunning then
                    return
                end
                module:ThrottledUpdateLayout("OnHide:child", { secondPass = true })
            end
        end

        it("suppresses SetPoint hook during layout", function()
            local mod = loadBuffBarsModule()
            local calls = {}
            function mod:ThrottledUpdateLayout(reason)
                calls[#calls + 1] = reason
            end

            local child = makeFrame({ name = "bar1" })
            installChildHooks(child, mod)

            mod._layoutRunning = true
            child:SetPoint("TOPLEFT", nil, "TOPLEFT", 0, 0)

            assert.are.equal(0, #calls)
        end)

        it("allows SetPoint hook when layout is not running", function()
            local mod = loadBuffBarsModule()
            local calls = {}
            function mod:ThrottledUpdateLayout(reason)
                calls[#calls + 1] = reason
            end

            local child = makeFrame({ name = "bar1" })
            installChildHooks(child, mod)

            child:SetPoint("TOPLEFT", nil, "TOPLEFT", 0, 0)

            assert.are.equal(1, #calls)
            assert.are.equal("SetPoint:hook", calls[1])
        end)

        it("suppresses OnShow hook during layout", function()
            local mod = loadBuffBarsModule()
            local calls = {}
            function mod:ThrottledUpdateLayout(reason)
                calls[#calls + 1] = reason
            end

            local child = makeFrame({ name = "bar1", shown = false })
            installChildHooks(child, mod)

            mod._layoutRunning = true
            child:Show()

            assert.are.equal(0, #calls)
        end)

        it("allows OnShow hook when layout is not running", function()
            local mod = loadBuffBarsModule()
            local calls = {}
            function mod:ThrottledUpdateLayout(reason)
                calls[#calls + 1] = reason
            end

            local child = makeFrame({ name = "bar1", shown = false })
            installChildHooks(child, mod)

            child:Show()

            assert.are.equal(1, #calls)
            assert.are.equal("OnShow:child", calls[1])
        end)

        it("suppresses OnHide hook during layout", function()
            local mod = loadBuffBarsModule()
            local calls = {}
            function mod:ThrottledUpdateLayout(reason)
                calls[#calls + 1] = reason
            end

            local child = makeFrame({ name = "bar1" })
            installChildHooks(child, mod)

            mod._layoutRunning = true
            child:Hide()

            assert.are.equal(0, #calls)
        end)

        it("allows OnHide hook when layout is not running", function()
            local mod = loadBuffBarsModule()
            local calls = {}
            function mod:ThrottledUpdateLayout(reason)
                calls[#calls + 1] = reason
            end

            local child = makeFrame({ name = "bar1" })
            installChildHooks(child, mod)

            child:Hide()

            assert.are.equal(1, #calls)
            assert.are.equal("OnHide:child", calls[1])
        end)

        it("resumes hook dispatch after layout completes", function()
            local mod = loadBuffBarsModule()
            local calls = {}
            function mod:ThrottledUpdateLayout(reason)
                calls[#calls + 1] = reason
            end

            local child = makeFrame({ name = "bar1" })
            installChildHooks(child, mod)

            -- During layout: suppressed
            mod._layoutRunning = true
            child:SetPoint("TOPLEFT", nil, "TOPLEFT", 0, 0)
            assert.are.equal(0, #calls)

            -- Layout ends
            mod._layoutRunning = nil

            -- After layout: dispatched
            child:SetPoint("TOPLEFT", nil, "TOPLEFT", 10, 10)
            assert.are.equal(1, #calls)
            assert.are.equal("SetPoint:hook", calls[1])
        end)

        it("SetPoint hook synchronously re-styles before deferring", function()
            local mod = loadBuffBarsModule()
            local sequence = {}
            function mod:ThrottledUpdateLayout(reason)
                sequence[#sequence + 1] = "deferred:" .. reason
            end

            local child = makeFrame({ name = "bar1" })
            installChildHooks(child, mod, function(c)
                sequence[#sequence + 1] = "styled:" .. c:GetName()
            end)

            child:SetPoint("TOPLEFT", nil, "TOPLEFT", 0, 0)

            assert.are.equal(2, #sequence)
            assert.are.equal("styled:bar1", sequence[1])
            assert.are.equal("deferred:SetPoint:hook", sequence[2])
        end)

        it("OnShow hook synchronously re-styles before deferring", function()
            local mod = loadBuffBarsModule()
            local sequence = {}
            function mod:ThrottledUpdateLayout(reason)
                sequence[#sequence + 1] = "deferred:" .. reason
            end

            local child = makeFrame({ name = "bar2", shown = false })
            installChildHooks(child, mod, function(c)
                sequence[#sequence + 1] = "styled:" .. c:GetName()
            end)

            child:Show()

            assert.are.equal(2, #sequence)
            assert.are.equal("styled:bar2", sequence[1])
            assert.are.equal("deferred:OnShow:child", sequence[2])
        end)

        it("OnHide hook does not synchronously re-style", function()
            local mod = loadBuffBarsModule()
            local styleCalls = 0
            local deferCalls = {}
            function mod:ThrottledUpdateLayout(reason)
                deferCalls[#deferCalls + 1] = reason
            end

            local child = makeFrame({ name = "bar1" })
            installChildHooks(child, mod, function()
                styleCalls = styleCalls + 1
            end)

            child:Hide()

            assert.are.equal(0, styleCalls)
            assert.are.equal(1, #deferCalls)
            assert.are.equal("OnHide:child", deferCalls[1])
        end)

        it("synchronous restyle suppresses nested hooks via _layoutRunning", function()
            local mod = loadBuffBarsModule()
            local outerCalls = {}
            function mod:ThrottledUpdateLayout(reason)
                outerCalls[#outerCalls + 1] = reason
            end

            local child = makeFrame({ name = "bar1" })
            local nestedHookFired = false

            installChildHooks(child, mod, function()
                -- Simulate styleChildFrame calling SetPoint on a sub-frame
                -- that somehow triggers the child's SetPoint again.
                -- The _layoutRunning guard should prevent re-entry.
                nestedHookFired = mod._layoutRunning == true
            end)

            child:SetPoint("TOPLEFT", nil, "TOPLEFT", 0, 0)

            -- styleChild ran while _layoutRunning was true
            assert.is_true(nestedHookFired)
            -- Only one deferred call (not two)
            assert.are.equal(1, #outerCalls)
        end)
    end)
end)
