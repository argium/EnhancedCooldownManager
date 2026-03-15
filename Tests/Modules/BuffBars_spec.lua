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
        --- SetPoint restores cached anchors and re-styles; OnShow re-styles;
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
                local cached = child.__ecmAnchorCache
                if cached then
                    ECM.FrameUtil.LazySetAnchors(child, cached)
                end
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
            child.__ecmAnchorCache = {
                { "TOPLEFT", child, "BOTTOMLEFT", 0, -2 },
            }
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
            child.__ecmAnchorCache = {
                { "TOPLEFT", child, "BOTTOMLEFT", 10, 10 },
            }
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
            child.__ecmAnchorCache = {
                { "TOPLEFT", child, "BOTTOMLEFT", 0, -2 },
            }
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
            child.__ecmAnchorCache = {
                { "TOPLEFT", child, "BOTTOMLEFT", 0, -2 },
            }

            local baseSetPoint = child.SetPoint
            child.SetPoint = function(self, ...)
                baseSetPoint(self, ...)
                if mod._layoutRunning then
                    nestedHookFired = true
                end
            end

            installChildHooks(child, mod, function()
                nestedHookFired = mod._layoutRunning == true
            end)

            child:SetPoint("CENTER", nil, "CENTER", 0, 0)

            assert.is_true(nestedHookFired)
            assert.are.equal(1, #outerCalls)
        end)

        it("SetPoint hook restores cached anchors from __ecmAnchorCache", function()
            local mod = loadBuffBarsModule()
            function mod:ThrottledUpdateLayout() end

            local child = makeFrame({ name = "bar1" })
            -- Simulate a prior layoutBars pass having cached the correct anchors
            local anchor = child -- use child itself as relative-to frame for simplicity
            child.__ecmAnchorCache = {
                { "TOPLEFT", anchor, "BOTTOMLEFT", 0, -2 },
                { "TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2 },
            }
            installChildHooks(child, mod)

            -- Blizzard repositions the child to a wrong location
            child:SetPoint("CENTER", nil, "CENTER", 99, 99)

            -- The hook should have restored from cache
            local anchors = child.__anchors
            assert.are.equal(2, #anchors)
            assert.are.equal("TOPLEFT", anchors[1][1])
            assert.are.equal("BOTTOMLEFT", anchors[1][3])
            assert.are.equal(-2, anchors[1][5])
            assert.are.equal("TOPRIGHT", anchors[2][1])
            assert.are.equal("BOTTOMRIGHT", anchors[2][3])
        end)

        it("SetPoint hook skips anchor restoration when cache is absent", function()
            local mod = loadBuffBarsModule()
            function mod:ThrottledUpdateLayout() end

            local child = makeFrame({ name = "bar1" })
            -- No __ecmAnchorCache set
            installChildHooks(child, mod)

            child:SetPoint("TOPLEFT", nil, "TOPLEFT", 5, 5)

            -- Should keep the point that was set (no cache to restore from)
            local anchors = child.__anchors
            assert.are.equal(1, #anchors)
            assert.are.equal("TOPLEFT", anchors[1][1])
            assert.are.equal(5, anchors[1][4])
        end)
    end)
end)

describe("BuffBars real source", function()
    local originalGlobals
    local BuffBars
    local ns
    local makeFrame = TestHelpers.makeFrame
    local secureHooks
    local registerFrameCalls
    local unregisterFrameCalls
    local addMixinCalls
    local timerCallbacks

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "ECM",
            "UIParent",
            "BuffBarCooldownViewer",
            "hooksecurefunc",
            "EditModeManagerFrame",
            "InCombatLockdown",
            "issecretvalue",
            "C_Timer",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    local function makeHookableFrame(opts)
        local frame = makeFrame(opts)
        frame._hooks = {}

        function frame:HookScript(scriptName, callback)
            self._hooks[scriptName] = self._hooks[scriptName] or {}
            self._hooks[scriptName][#self._hooks[scriptName] + 1] = callback
        end

        function frame:GetHookCount(scriptName)
            return self._hooks[scriptName] and #self._hooks[scriptName] or 0
        end

        return frame
    end

    before_each(function()
        secureHooks = {}
        registerFrameCalls = 0
        unregisterFrameCalls = 0
        addMixinCalls = 0
        timerCallbacks = {}
        _G.ECM = {
            Log = function() end,
            Constants = nil,
            FrameUtil = {
                GetIconTextureFileID = function(frame)
                    return frame.iconTextureFileID
                end,
            },
            FrameMixin = {
                ChainRightPoint = function(point, fallback)
                    if point == "TOPLEFT" then
                        return "TOPRIGHT"
                    end
                    if point == "BOTTOMLEFT" then
                        return "BOTTOMRIGHT"
                    end
                    return fallback
                end,
                NormalizeGrowDirection = function(direction)
                    return direction
                end,
                CalculateLayoutParams = function()
                    return {}
                end,
                IsReady = function()
                    return true
                end,
                AddMixin = function()
                    addMixinCalls = addMixinCalls + 1
                end,
            },
            SpellColors = {
                MakeKey = function(name, spellID, cooldownID, textureFileID)
                    if not name and not spellID and not cooldownID and not textureFileID then
                        return nil
                    end
                    return {
                        name = name,
                        spellID = spellID,
                        cooldownID = cooldownID,
                        textureFileID = textureFileID,
                    }
                end,
                SetConfigAccessor = function() end,
                ClearDiscoveredKeys = function() end,
                DiscoverBar = function() end,
            },
            RegisterFrame = function()
                registerFrameCalls = registerFrameCalls + 1
            end,
            UnregisterFrame = function()
                unregisterFrameCalls = unregisterFrameCalls + 1
            end,
        }
        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()

        _G.UIParent = makeFrame({ name = "UIParent" })
        _G.hooksecurefunc = function(target, scriptName, callback)
            secureHooks[#secureHooks + 1] = { target = target, scriptName = scriptName, callback = callback }
        end
        _G.C_Timer = {
            After = function(_, callback)
                timerCallbacks[#timerCallbacks + 1] = callback
            end,
        }
        _G.EditModeManagerFrame = makeHookableFrame({ name = "EditModeManagerFrame", shown = false })
        _G.InCombatLockdown = function()
            return false
        end
        _G.issecretvalue = function()
            return false
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

        _G.BuffBarCooldownViewer = makeHookableFrame({ name = "BuffBarCooldownViewer", shown = true })
        function BuffBarCooldownViewer:GetChildren()
            return
        end

        TestHelpers.LoadChunk("Modules/BuffBars.lua", "Unable to load Modules/BuffBars.lua")(nil, ns)
        BuffBars = assert(ns.Addon.BuffBars, "BuffBars module did not initialize")
    end)

    it("returns the Blizzard buff bar viewer from CreateFrame", function()
        assert.are.equal(BuffBarCooldownViewer, BuffBars:CreateFrame())
    end)

    it("orders active spell data by layoutIndex and skips hidden bars", function()
        local firstBar = makeFrame({ shown = true })
        firstBar.Bar = {
            Name = {
                GetText = function()
                    return "First"
                end,
            },
        }
        firstBar.cooldownInfo = { spellID = 17 }
        firstBar.iconTextureFileID = 170
        firstBar.layoutIndex = 2
        firstBar.GetTop = function()
            return 50
        end

        local secondBar = makeFrame({ shown = true })
        secondBar.Bar = {
            Name = {
                GetText = function()
                    return "Second"
                end,
            },
        }
        secondBar.cooldownInfo = { spellID = 18 }
        secondBar.iconTextureFileID = 180
        secondBar.layoutIndex = 1
        secondBar.GetTop = function()
            return 200
        end

        local hiddenBar = makeFrame({ shown = false })
        hiddenBar.Bar = {
            Name = {
                GetText = function()
                    return "Hidden"
                end,
            },
        }
        hiddenBar.cooldownInfo = { spellID = 19 }
        hiddenBar.iconTextureFileID = 190
        hiddenBar.layoutIndex = 0
        hiddenBar.GetTop = function()
            return 300
        end

        local ignoredChild = makeFrame({ shown = true })
        ignoredChild.ignoreInLayout = true
        ignoredChild.layoutIndex = -1

        function BuffBarCooldownViewer:GetChildren()
            return firstBar, hiddenBar, ignoredChild, secondBar
        end

        local active = BuffBars:GetActiveSpellData()

        assert.are.equal(2, #active)
        assert.are.equal("Second", active[1].name)
        assert.are.equal("First", active[2].name)
    end)

    it("hooks the viewer only once", function()
        BuffBars:HookViewer()
        BuffBars:HookViewer()

        assert.is_true(BuffBars._viewerHooked)
        assert.are.equal(1, BuffBarCooldownViewer:GetHookCount("OnShow"))
        assert.are.equal(1, BuffBarCooldownViewer:GetHookCount("OnSizeChanged"))
    end)

    it("hooks edit mode only once", function()
        BuffBars:HookEditMode()
        BuffBars:HookEditMode()

        assert.is_true(BuffBars._editModeHooked)
        assert.are.equal(2, #secureHooks)
        assert.are.equal("ExitEditMode", secureHooks[1].scriptName)
        assert.are.equal("EnterEditMode", secureHooks[2].scriptName)
    end)

    it("only relayouts for player auras", function()
        local reasons = {}
        function BuffBars:ThrottledUpdateLayout(reason)
            reasons[#reasons + 1] = reason
        end

        BuffBars:OnUnitAura(nil, "target")
        BuffBars:OnUnitAura(nil, "player")

        assert.same({ "OnUnitAura" }, reasons)
    end)

    it("hides the viewer when UpdateLayout decides not to show", function()
        function BuffBars:GetGlobalConfig()
            return { texture = "Solid" }
        end
        function BuffBars:GetModuleConfig()
            return { anchorMode = ECM.Constants.ANCHORMODE_CHAIN }
        end
        function BuffBars:ShouldShow()
            return false
        end

        local result = BuffBars:UpdateLayout("test")

        assert.is_false(result)
        assert.is_false(BuffBarCooldownViewer:IsShown())
    end)

    it("returns false from IsReady when the viewer is missing or cannot enumerate children", function()
        _G.BuffBarCooldownViewer = nil
        assert.is_false(BuffBars:IsReady())

        _G.BuffBarCooldownViewer = makeHookableFrame({ name = "BuffBarCooldownViewer", shown = true })
        function BuffBarCooldownViewer:GetChildren()
            error("forbidden")
        end
        assert.is_false(BuffBars:IsReady())
    end)

    it("returns free-mode layout params from module config", function()
        BuffBars.GetModuleConfig = function()
            return {
                anchorMode = ECM.Constants.ANCHORMODE_FREE,
                anchorPoint = "TOP",
                relativePoint = "BOTTOM",
                offsetX = 10,
                offsetY = 20,
                width = 345,
            }
        end

        local params = BuffBars:CalculateLayoutParams()

        assert.are.equal(ECM.Constants.ANCHORMODE_FREE, params.mode)
        assert.are.equal("TOP", params.anchorPoint)
        assert.are.equal("BOTTOM", params.anchorRelativePoint)
        assert.are.equal(10, params.offsetX)
        assert.are.equal(20, params.offsetY)
        assert.are.equal(345, params.width)
    end)

    it("viewer hooks defer layout and respect the layout-running guard", function()
        local reasons = {}
        function BuffBars:ThrottledUpdateLayout(reason)
            reasons[#reasons + 1] = reason
        end

        BuffBars:HookViewer()
        BuffBarCooldownViewer._hooks.OnShow[1]()
        BuffBars._layoutRunning = true
        BuffBarCooldownViewer._hooks.OnSizeChanged[1]()
        BuffBars._layoutRunning = nil
        BuffBarCooldownViewer._hooks.OnSizeChanged[1]()

        assert.same({ "viewer:OnShow", "viewer:OnSizeChanged" }, reasons)
    end)

    it("edit mode hooks defer layout on enter and exit", function()
        local reasons = {}
        function BuffBars:ThrottledUpdateLayout(reason)
            reasons[#reasons + 1] = reason
        end

        BuffBars:HookEditMode()
        secureHooks[2].callback()
        secureHooks[1].callback()

        assert.same({ "EditModeEnter", "EditModeExit" }, reasons)
    end)

    it("reports edit lock reasons for combat and secret values", function()
        _G.InCombatLockdown = function()
            return true
        end
        assert.same({ true, "combat" }, { BuffBars:IsEditLocked() })

        _G.InCombatLockdown = function()
            return false
        end
        local secretColorRequested = false
        ECM.SpellColors.GetColorForBar = function()
            secretColorRequested = true
            return nil
        end
        ECM.SpellColors.GetDefaultColor = function()
            return { r = 1, g = 1, b = 1, a = 1 }
        end
        ECM.ColorUtil = {
            ColorToHex = function()
                return "ffffff"
            end,
        }
        ECM.ToString = tostring
        ECM.GetTexture = function()
            return "Solid"
        end
        ECM.ApplyFont = function() end
        ECM.DebugAssert = function() end
        ECM.FrameUtil.GetBarBackground = function()
            return nil
        end
        ECM.FrameUtil.GetIconTexture = function()
            return nil
        end
        ECM.FrameUtil.GetIconOverlay = function()
            return nil
        end
        ECM.FrameUtil.LazySetHeight = function() end
        ECM.FrameUtil.LazySetWidth = function() end
        ECM.FrameUtil.LazySetStatusBarTexture = function() end
        ECM.FrameUtil.LazySetStatusBarColor = function() end
        ECM.FrameUtil.LazySetAnchors = function() end
        ECM.FrameUtil.LazySetAlpha = function() end
        _G.issecretvalue = function()
            return true
        end

        local frame = makeFrame({ shown = true })
        frame.__ecmHooked = true
        frame.Bar = {
            Name = {
                GetText = function()
                    return "Spell"
                end,
                SetShown = function() end,
            },
            Duration = { SetShown = function() end },
            Pip = { Hide = function() end, SetTexture = function() end },
            SetShown = function() end,
        }
        frame.Icon = makeFrame({ shown = false })
        frame.Icon.SetShown = function() end
        frame.Icon.Applications = { SetShown = function() end }
        function BuffBars:GetModuleConfig()
            return { showIcon = false, showSpellName = true, showDuration = true }
        end
        function BuffBars:GetGlobalConfig()
            return { barHeight = 20, texture = "Solid" }
        end
        function BuffBars:ShouldShow()
            return true
        end
        function BuffBarCooldownViewer:GetChildren()
            return frame
        end

        BuffBars:UpdateLayout("test")

        assert.is_true(secretColorRequested)
        assert.same({ true, "secrets" }, { BuffBars:IsEditLocked() })
    end)

    it("registers immediately and schedules initial hooks on enable", function()
        local reasons = {}
        function BuffBars:RegisterEvent() end
        function BuffBars:ThrottledUpdateLayout(reason)
            reasons[#reasons + 1] = reason
        end
        function BuffBars:GetModuleConfig()
            return { enabled = true }
        end

        BuffBars:OnEnable()

        assert.are.equal(1, addMixinCalls)
        assert.are.equal(1, registerFrameCalls)
        assert.are.equal(1, #timerCallbacks)

        timerCallbacks[1]()

        assert.same({ "ModuleInit" }, reasons)
        assert.is_true(BuffBars._viewerHooked)
        assert.is_true(BuffBars._editModeHooked)
    end)

    it("unregisters on disable", function()
        function BuffBars:UnregisterAllEvents() end

        BuffBars:OnDisable()

        assert.are.equal(1, unregisterFrameCalls)
    end)
end)
