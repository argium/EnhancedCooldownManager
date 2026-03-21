-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("FrameMixin", function()
    local originalGlobals
    local FrameUtil
    local fakeTime

    local getCalls = TestHelpers.getCalls
    local color = TestHelpers.color
    local makeFrame = TestHelpers.makeFrame
    local makeTexture = TestHelpers.makeTexture

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "ECM",
            "C_Timer",
            "GetTime",
            "UIParent",
            "issecretvalue",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        fakeTime = 0

        _G.ECM = {}
        _G.ECM.IsDebugEnabled = function() return false end
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
        _G.ECM.DebugAssert = function(condition, message)
            if not condition then
                error(message or "ECM.DebugAssert failed")
            end
        end
        _G.C_Timer = {
            After = function(_, callback)
                callback()
            end,
        }
        _G.GetTime = function()
            return fakeTime
        end
        _G.UIParent = makeFrame({ name = "UIParent" })
        _G.issecretvalue = function()
            return false
        end

        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
        TestHelpers.LoadChunk("Helpers/FrameUtil.lua", "Unable to load Helpers/FrameUtil.lua")()
        FrameUtil = assert(ECM.FrameUtil, "FrameUtil module did not initialize")
    end)

    describe("UpdateLayout", function()
        local function makeModule(opts)
            local anchor = opts.anchor or makeFrame({ name = "Anchor" })
            local innerFrame = opts.innerFrame or makeFrame({ shown = opts.shown ~= false })
            innerFrame.Background = makeTexture()

            local selfObj = {
                Name = opts.name or "TestModule",
                InnerFrame = innerFrame,
                _lastUpdate = 0,
                ShouldShow = function()
                    return opts.shouldShow
                end,
                CalculateLayoutParams = function()
                    return {
                        mode = ECM.Constants.ANCHORMODE_CHAIN,
                        anchor = anchor,
                        anchorPoint = "TOPLEFT",
                        anchorRelativePoint = "BOTTOMLEFT",
                        offsetX = 0,
                        offsetY = 0,
                        height = opts.height or 20,
                    }
                end,
                GetGlobalConfig = function()
                    return { barBgColor = color(0, 0, 0, 0.5), updateFrequency = 0 }
                end,
                GetModuleConfig = function()
                    return { bgColor = color(0, 0, 0, 0.5) }
                end,
                Refresh = function() end,
            }

            function selfObj:UpdateLayout(why)
                if not self:ShouldShow() then
                    self.InnerFrame:Hide()
                    return false
                end
                if not self.InnerFrame:IsShown() then
                    self.InnerFrame:Show()
                end
                local params = self:CalculateLayoutParams()
                if params.height then
                    FrameUtil.LazySetHeight(self.InnerFrame, params.height)
                end
                if params.width then
                    FrameUtil.LazySetWidth(self.InnerFrame, params.width)
                end
                local mc = self:GetModuleConfig()
                local gc = self:GetGlobalConfig()
                local bgColor = (mc and mc.bgColor) or (gc and gc.barBgColor)
                if bgColor then
                    FrameUtil.LazySetBackgroundColor(self.InnerFrame, bgColor)
                end
                self:ThrottledRefresh("UpdateLayout(" .. (why or "") .. ")")
                return true
            end
            function selfObj:ThrottledRefresh(why)
                local gc = self:GetGlobalConfig()
                local freq = (gc and gc.updateFrequency) or ECM.Constants.DEFAULT_REFRESH_FREQUENCY
                if GetTime() - (self._lastUpdate or 0) < freq then
                    return false
                end
                self:Refresh(why)
                self._lastUpdate = GetTime()
                return true
            end
            return selfObj
        end

        it("re-hides a frame that was externally shown while ShouldShow is false", function()
            local mod = makeModule({ shouldShow = false, shown = true })

            mod:UpdateLayout("initial")
            assert.is_false(mod.InnerFrame:IsShown())
            assert.are.equal(1, getCalls(mod.InnerFrame, "Hide"))

            mod.InnerFrame:Show()

            mod:UpdateLayout("re-check")
            assert.is_false(mod.InnerFrame:IsShown())
            assert.are.equal(2, getCalls(mod.InnerFrame, "Hide"))
        end)

        it("re-applies height via lazy setter when externally mutated", function()
            local mod = makeModule({ shouldShow = true })

            mod:UpdateLayout("initial")
            assert.are.equal(20, mod.InnerFrame:GetHeight())

            mod.InnerFrame:SetHeight(999)
            mod:UpdateLayout("re-check")
            assert.are.equal(20, mod.InnerFrame:GetHeight())
        end)

        it("shows a hidden frame when ShouldShow becomes true", function()
            local mod = makeModule({ shouldShow = false, shown = true })

            mod:UpdateLayout("hide")
            assert.is_false(mod.InnerFrame:IsShown())

            mod.ShouldShow = function()
                return true
            end
            mod:UpdateLayout("show")
            assert.is_true(mod.InnerFrame:IsShown())
        end)
    end)
end)

describe("FrameMixin real source", function()
    local originalGlobals
    local FrameMixin
    local ns
    local timerQueue
    local makeFrame = TestHelpers.makeFrame

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "ECM",
            "C_Timer",
            "GetTime",
            "UIParent",
            "EssentialCooldownViewer",
            "LibStub",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        timerQueue = {}

        _G.ECM = {
            IsDebugEnabled = function() return false end,
            Log = function() end,
            DebugAssert = function(condition, message)
                if not condition then
                    error(message or "ECM.DebugAssert failed")
                end
            end,
            ColorUtil = {
                AreEqual = function(a, b)
                    if a == nil and b == nil then
                        return true
                    end
                    if a == nil or b == nil then
                        return false
                    end
                    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
                end,
            },
        }
        _G.C_Timer = {
            After = function(delay, callback)
                timerQueue[#timerQueue + 1] = { delay = delay, callback = callback }
            end,
        }
        _G.GetTime = function()
            return 0
        end
        _G.UIParent = makeFrame({ name = "UIParent" })
        _G.EssentialCooldownViewer = makeFrame({ name = "EssentialCooldownViewer" })

        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
        _G.ECM.Runtime = { ScheduleLayoutUpdate = function() end }
        TestHelpers.SetupLibStub()
        TestHelpers.SetupLibEQOLEditModeStub()
        ns = { Addon = {} }
        TestHelpers.LoadChunk("Helpers/FrameUtil.lua", "Unable to load Helpers/FrameUtil.lua")()
        TestHelpers.LoadChunk("Helpers/ModuleMixin.lua", "Unable to load Helpers/ModuleMixin.lua")(nil, ns)
        TestHelpers.LoadChunk("Helpers/FrameMixin.lua", "Unable to load Helpers/FrameMixin.lua")(nil, ns)
        FrameMixin = assert(ECM.FrameMixin, "FrameMixin did not initialize")
    end)

    it("GetNextChainAnchor returns the nearest earlier chain module", function()
        local order = ECM.Constants.CHAIN_ORDER
        local previousFrame = makeFrame({ name = order[2] })
        local modules = {
            [order[2]] = {
                IsEnabled = function()
                    return true
                end,
                ShouldShow = function()
                    return true
                end,
                GetModuleConfig = function()
                    return { anchorMode = ECM.Constants.ANCHORMODE_CHAIN }
                end,
                InnerFrame = previousFrame,
            },
        }
        ns.Addon.GetECMModule = function(_, name)
            return modules[name]
        end

        local anchor, isFirst = FrameMixin.GetNextChainAnchor({ Name = "TestModule" }, order[3])

        assert.are.equal(previousFrame, anchor)
        assert.is_false(isFirst)
    end)

    it("GetNextChainAnchor falls back to the viewer when no prior module is valid", function()
        ns.Addon.GetECMModule = function()
            return nil
        end

        local anchor, isFirst = FrameMixin.GetNextChainAnchor({ Name = "TestModule" }, ECM.Constants.CHAIN_ORDER[1])

        assert.are.equal(_G.EssentialCooldownViewer, anchor)
        assert.is_true(isFirst)
    end)

    it("CalculateLayoutParams keeps the first chained module anchored below the viewer", function()
        ns.Addon.GetECMModule = function()
            return nil
        end

        local mod = {
            Name = ECM.Constants.CHAIN_ORDER[1],
            GetGlobalConfig = function()
                return {
                    moduleGrowDirection = ECM.Constants.GROW_DIRECTION_DOWN,
                    offsetY = 4,
                    barHeight = 20,
                }
            end,
            GetModuleConfig = function()
                return { anchorMode = ECM.Constants.ANCHORMODE_CHAIN }
            end,
            GetNextChainAnchor = FrameMixin.GetNextChainAnchor,
            NormalizeGrowDirection = FrameMixin.NormalizeGrowDirection,
        }

        local params = FrameMixin.CalculateLayoutParams(mod)

        assert.are.equal(ECM.Constants.ANCHORMODE_CHAIN, params.mode)
        assert.are.equal(_G.EssentialCooldownViewer, params.anchor)
        assert.is_true(params.isFirst)
        assert.are.equal("TOPLEFT", params.anchorPoint)
        assert.are.equal("BOTTOMLEFT", params.anchorRelativePoint)
        assert.are.equal(-4, params.offsetY)
    end)

    it("GetNextChainAnchor with detached mode finds nearest prior detached module", function()
        local order = ECM.Constants.CHAIN_ORDER
        local detachedFrame = makeFrame({ name = order[2] })
        local modules = {
            [order[1]] = {
                IsEnabled = function()
                    return true
                end,
                ShouldShow = function()
                    return true
                end,
                GetModuleConfig = function()
                    return { anchorMode = ECM.Constants.ANCHORMODE_CHAIN }
                end,
                InnerFrame = makeFrame({ name = order[1] }),
            },
            [order[2]] = {
                IsEnabled = function()
                    return true
                end,
                ShouldShow = function()
                    return true
                end,
                GetModuleConfig = function()
                    return { anchorMode = ECM.Constants.ANCHORMODE_DETACHED }
                end,
                InnerFrame = detachedFrame,
            },
        }
        ns.Addon.GetECMModule = function(_, name)
            return modules[name]
        end

        local anchor, isFirst =
            FrameMixin.GetNextChainAnchor({ Name = "TestModule" }, order[3], ECM.Constants.ANCHORMODE_DETACHED)

        assert.are.equal(detachedFrame, anchor)
        assert.is_false(isFirst)
    end)

    it("GetNextChainAnchor with detached mode falls back to DetachedAnchor", function()
        ns.Addon.GetECMModule = function()
            return nil
        end

        local detachedAnchor = makeFrame({ name = "ECMDetachedAnchor" })
        ECM.Runtime.DetachedAnchor = detachedAnchor

        local anchor, isFirst = FrameMixin.GetNextChainAnchor(
            { Name = "TestModule" },
            ECM.Constants.CHAIN_ORDER[1],
            ECM.Constants.ANCHORMODE_DETACHED
        )

        assert.are.equal(detachedAnchor, anchor)
        assert.is_true(isFirst)

        ECM.Runtime.DetachedAnchor = nil
    end)

    it("SetHidden hides immediately and defers showing", function()
        local layoutCalls = {}
        local innerFrame = makeFrame({ shown = true })
        local mod = {
            InnerFrame = innerFrame,
            ThrottledUpdateLayout = function(_, reason)
                layoutCalls[#layoutCalls + 1] = reason
            end,
        }

        FrameMixin.SetHidden(mod, true)
        assert.is_true(mod.IsHidden)
        assert.is_false(innerFrame:IsShown())
        assert.are.equal(0, #layoutCalls)

        FrameMixin.SetHidden(mod, false)
        assert.is_false(mod.IsHidden)
        assert.same({ "SetHidden" }, layoutCalls)
    end)

    it("ThrottledUpdateLayout coalesces queued work and schedules second pass", function()
        local updateReasons = {}
        local mod = {
            Name = "TestModule",
            InnerFrame = makeFrame({ shown = true }),
            IsEnabled = function()
                return true
            end,
            IsReady = function()
                return true
            end,
            GetGlobalConfig = function()
                return {}
            end,
            GetModuleConfig = function()
                return {}
            end,
            UpdateLayout = function(_, why)
                updateReasons[#updateReasons + 1] = why
            end,
        }
        mod.ThrottledUpdateLayout = FrameMixin.ThrottledUpdateLayout

        FrameMixin.ThrottledUpdateLayout(mod, "First", { secondPass = true })
        FrameMixin.ThrottledUpdateLayout(mod, "Second", { secondPass = true })

        assert.are.equal(1, #timerQueue)

        timerQueue[1].callback()
        assert.same({ "First" }, updateReasons)
        assert.are.equal(2, #timerQueue)

        timerQueue[2].callback()
        assert.are.equal(3, #timerQueue)

        timerQueue[3].callback()
        assert.same({ "First", "SecondPass" }, updateReasons)
    end)

    it("GetEditModePosition falls back to the migrated layout entry", function()
        local mod = {
            GetModuleConfig = function()
                return {
                    editModePositions = {
                        [ECM.Constants.EDIT_MODE_MIGRATED_KEY] = { point = "TOP", x = 12, y = -34 },
                    },
                }
            end,
        }

        local position = FrameMixin.GetEditModePosition(mod)

        assert.are.equal("TOP", position.point)
        assert.are.equal(12, position.x)
        assert.are.equal(-34, position.y)
    end)

    it("AddMixin skips Edit Mode registration when the module opts out", function()
        local registerCalls = 0
        local mod = {
            Name = "ExternalFrameModule",
            CreateFrame = function()
                return makeFrame({ name = "ExternalFrame" })
            end,
            ShouldRegisterEditMode = function()
                return false
            end,
            _RegisterEditMode = function()
                registerCalls = registerCalls + 1
            end,
            GetGlobalConfig = function()
                return {}
            end,
            GetModuleConfig = function()
                return {}
            end,
        }

        FrameMixin.AddMixin(mod, "ExternalFrameModule")
        mod:EnsureFrame()

        assert.are.equal(0, registerCalls)
        assert.are.equal("ExternalFrame", mod.InnerFrame:GetName())
    end)

    it("resolves mixin methods via metatable __index", function()
        local mod = {
            CreateFrame = function()
                return makeFrame({ name = "TestFrame" })
            end,
            ShouldRegisterEditMode = function()
                return false
            end,
        }

        FrameMixin.AddMixin(mod, "TestModule")

        assert.is_nil(rawget(mod, "UpdateLayout"))
        assert.is_function(mod.UpdateLayout)
        assert.is_nil(rawget(mod, "GetModuleConfig"))
        assert.is_function(mod.GetModuleConfig)
        assert.is_function(mod.EnsureFrame)
    end)

    it("preserves existing metatable chain (AceAddon compatibility)", function()
        local aceEnabled = function() return true end
        local aceMt = { __index = { IsEnabled = aceEnabled } }
        local mod = setmetatable({
            CreateFrame = function()
                return makeFrame({ name = "TestFrame" })
            end,
            ShouldRegisterEditMode = function()
                return false
            end,
        }, aceMt)

        FrameMixin.AddMixin(mod, "TestModule")

        assert.are.equal(aceEnabled, mod.IsEnabled)
        assert.is_function(mod.UpdateLayout)
        assert.is_function(mod.GetModuleConfig)
        assert.is_function(mod.EnsureFrame)
    end)

    it("AddMixin is idempotent — second call is a no-op", function()
        local mod = {
            ShouldRegisterEditMode = function() return false end,
        }

        FrameMixin.AddMixin(mod, "TestModule")
        local mt1 = getmetatable(mod)

        FrameMixin.AddMixin(mod, "TestModule")
        local mt2 = getmetatable(mod)

        assert.are.equal(mt1, mt2)
        assert.is_true(mod._mixinApplied)
    end)
end)
