-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("FrameMixin", function()
    local originalGlobals
    local FrameUtil
    local fakeTime
    local ns

    local getCalls = TestHelpers.getCalls
    local color = TestHelpers.color
    local makeFrame = TestHelpers.makeFrame
    local makeTexture = TestHelpers.makeTexture

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
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

        ns = {}
        ns.IsDebugEnabled = function() return false end
        ns.ColorUtil = {
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
        ns.DebugAssert = function(condition, message)
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

        TestHelpers.LoadChunk("Constants.lua", "Unable to load Constants.lua")(nil, ns)
        TestHelpers.LoadChunk("FrameUtil.lua", "Unable to load FrameUtil.lua")(nil, ns)
        FrameUtil = assert(ns.FrameUtil, "FrameUtil module did not initialize")
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
                        mode = ns.Constants.ANCHORMODE_CHAIN,
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
                local freq = (gc and gc.updateFrequency) or ns.Constants.DEFAULT_REFRESH_FREQUENCY
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
    local BarMixin, FrameProto
    local Migration
    local ns
    local timerQueue
    local assertAbsolutePositionPreserved = TestHelpers.assertAbsolutePositionPreserved
    local getAbsoluteAnchorPosition = TestHelpers.getAbsoluteAnchorPosition
    local makeFrame = TestHelpers.makeFrame
    local color = TestHelpers.color

    local LEGACY_FREE_POSITION_DEFAULTS = {
        powerBar = { point = "CENTER", x = 0, y = -275 },
        resourceBar = { point = "CENTER", x = 0, y = -300 },
        runeBar = { point = "CENTER", x = 0, y = -325 },
        buffBars = { point = "CENTER", x = 0, y = -350 },
    }

    local function assertFreeFramePositionPreserved(frame, expectedX, expectedY)
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
        assert.are.equal(_G.UIParent, relativeTo)
        assert.are.equal(point, relativePoint)

        local actualX, actualY = getAbsoluteAnchorPosition(ns, point, x, y)
        assert.are.equal(expectedX, actualX)
        assert.are.equal(expectedY, actualY)
    end

    local function makeFreeModeModule(name, globalConfig, moduleConfig)
        local mod = {
            Name = name,
            InnerFrame = makeFrame({ name = "ECM" .. name, shown = true }),
            IsEnabled = function()
                return true
            end,
            ShouldRegisterEditMode = function()
                return false
            end,
            GetGlobalConfig = function()
                return globalConfig
            end,
            GetModuleConfig = function()
                return moduleConfig
            end,
            Refresh = function() end,
        }

        BarMixin.AddFrameMixin(mod, name)
        return mod
    end

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "C_EditMode",
            "C_Timer",
            "GetTime",
            "UIParent",
            "EssentialCooldownViewer",
            "LibStub",
            "date",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        timerQueue = {}

        ns = {
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
        _G.date = function()
            return "2026-03-23 00:00:00"
        end
        _G.UIParent = makeFrame({ name = "UIParent" })
        _G.EssentialCooldownViewer = makeFrame({ name = "EssentialCooldownViewer" })
        _G.UIParent:SetWidth(1920)
        _G.UIParent:SetHeight(1080)
        _G.C_EditMode = {
            GetLayouts = function()
                return { activeLayout = 1, layouts = {} }
            end,
        }

        TestHelpers.LoadChunk("Constants.lua", "Unable to load Constants.lua")(nil, ns)
        ns.Runtime = { ScheduleLayoutUpdate = function() end }
        TestHelpers.SetupLibStub()
        TestHelpers.SetupLibEditModeStub()
        ns.Addon = {}
        TestHelpers.LoadChunk("FrameUtil.lua", "Unable to load FrameUtil.lua")(nil, ns)
        TestHelpers.LoadChunk("BarMixin.lua", "Unable to load BarMixin.lua")(nil, ns)
        TestHelpers.LoadChunk("Migration.lua", "Unable to load Migration.lua")(nil, ns)
        BarMixin = assert(ns.BarMixin, "BarMixin did not initialize")
        FrameProto = BarMixin.FrameProto
        Migration = assert(ns.Migration, "Migration did not initialize")
    end)

    it("GetNextChainAnchor returns the nearest earlier chain module", function()
        local order = ns.Constants.CHAIN_ORDER
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
                    return { anchorMode = ns.Constants.ANCHORMODE_CHAIN }
                end,
                InnerFrame = previousFrame,
            },
        }
        ns.Addon.GetECMModule = function(_, name)
            return modules[name]
        end

        local anchor, isFirst = FrameProto.GetNextChainAnchor({ Name = "TestModule" }, order[3])

        assert.are.equal(previousFrame, anchor)
        assert.is_false(isFirst)
    end)

    it("GetNextChainAnchor falls back to the viewer when no prior module is valid", function()
        ns.Addon.GetECMModule = function()
            return nil
        end

        local anchor, isFirst = FrameProto.GetNextChainAnchor({ Name = "TestModule" }, ns.Constants.CHAIN_ORDER[1])

        assert.are.equal(_G.EssentialCooldownViewer, anchor)
        assert.is_true(isFirst)
    end)

    it("CalculateLayoutParams keeps the first chained module anchored below the viewer", function()
        ns.Addon.GetECMModule = function()
            return nil
        end

        local mod = {
            Name = ns.Constants.CHAIN_ORDER[1],
            GetGlobalConfig = function()
                return {
                    moduleGrowDirection = ns.Constants.GROW_DIRECTION_DOWN,
                    offsetY = 4,
                    barHeight = 20,
                }
            end,
            GetModuleConfig = function()
                return { anchorMode = ns.Constants.ANCHORMODE_CHAIN }
            end,
            GetNextChainAnchor = FrameProto.GetNextChainAnchor,
            NormalizeGrowDirection = FrameProto.NormalizeGrowDirection,
        }

        local params = FrameProto.CalculateLayoutParams(mod)

        assert.are.equal(ns.Constants.ANCHORMODE_CHAIN, params.mode)
        assert.are.equal(_G.EssentialCooldownViewer, params.anchor)
        assert.is_true(params.isFirst)
        assert.are.equal("TOPLEFT", params.anchorPoint)
        assert.are.equal("BOTTOMLEFT", params.anchorRelativePoint)
        assert.are.equal(-4, params.offsetY)
    end)

    it("GetNextChainAnchor with detached mode finds nearest prior detached module", function()
        local order = ns.Constants.CHAIN_ORDER
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
                    return { anchorMode = ns.Constants.ANCHORMODE_CHAIN }
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
                    return { anchorMode = ns.Constants.ANCHORMODE_DETACHED }
                end,
                InnerFrame = detachedFrame,
            },
        }
        ns.Addon.GetECMModule = function(_, name)
            return modules[name]
        end

        local anchor, isFirst =
            FrameProto.GetNextChainAnchor({ Name = "TestModule" }, order[3], ns.Constants.ANCHORMODE_DETACHED)

        assert.are.equal(detachedFrame, anchor)
        assert.is_false(isFirst)
    end)

    it("GetNextChainAnchor with detached mode falls back to DetachedAnchor", function()
        ns.Addon.GetECMModule = function()
            return nil
        end

        local detachedAnchor = makeFrame({ name = "ECMDetachedAnchor" })
        ns.Runtime.DetachedAnchor = detachedAnchor

        local anchor, isFirst = FrameProto.GetNextChainAnchor(
            { Name = "TestModule" },
            ns.Constants.CHAIN_ORDER[1],
            ns.Constants.ANCHORMODE_DETACHED
        )

        assert.are.equal(detachedAnchor, anchor)
        assert.is_true(isFirst)

        ns.Runtime.DetachedAnchor = nil
    end)

    it("SetHidden hides immediately and defers showing", function()
        local layoutCalls = {}
        local innerFrame = makeFrame({ shown = true })
        ns.Runtime.RequestLayout = function(reason)
            layoutCalls[#layoutCalls + 1] = reason
        end
        local mod = {
            InnerFrame = innerFrame,
        }

        FrameProto.SetHidden(mod, true)
        assert.is_true(mod.IsHidden)
        assert.is_false(innerFrame:IsShown())
        assert.are.equal(0, #layoutCalls)

        FrameProto.SetHidden(mod, false)
        assert.is_false(mod.IsHidden)
        assert.same({ "SetHidden" }, layoutCalls)
    end)

    it("EditMode.GetPosition returns default coordinates when the active layout has no saved position", function()
        local position = ns.EditMode.GetPosition({
            Legacy = { point = "TOP", x = 12, y = -34 },
        })

        assert.are.equal("CENTER", position.point)
        assert.are.equal(0, position.x)
        assert.are.equal(0, position.y)
    end)

    it("EditMode.GetPosition returns the saved coordinates for the active layout", function()
        local lib = LibStub("LibEditMode")

        lib.GetActiveLayoutName = function()
            return "Modern"
        end

        local position = ns.EditMode.GetPosition({
            Modern = { point = "TOP", x = 42, y = -17 },
        })

        assert.are.equal("TOP", position.point)
        assert.are.equal(42, position.x)
        assert.are.equal(-17, position.y)
    end)

    it("GetActiveLayoutName delegates to LibEditMode", function()
        local lib = LibStub("LibEditMode")
        lib.GetActiveLayoutName = function()
            return "Modern"
        end
        assert.are.equal("Modern", ns.EditMode.GetActiveLayoutName())
    end)

    it("EditMode callbacks schedule runtime layout updates without an extra timer hop", function()
        local lib = LibStub("LibEditMode")
        local scheduled = {}

        ns.Runtime.ScheduleLayoutUpdate = function(delay, reason)
            scheduled[#scheduled + 1] = {
                delay = delay,
                reason = reason,
            }
        end

        lib.callbacks.enter()
        lib.callbacks.exit()
        lib.callbacks.layout()

        assert.same({
            { delay = 0, reason = "EditModeEnter" },
            { delay = 0, reason = "EditModeExit" },
            { delay = 0, reason = "EditModeLayout" },
        }, scheduled)
        assert.are.equal(0, #timerQueue)
    end)

    it("UpdateLayout preserves final frame placement for V11 seeded legacy free-mode defaults", function()
        local globalConfig = {
            barHeight = 20,
            barWidth = 180,
            barBgColor = color(0, 0, 0, 0.5),
            updateFrequency = 0,
        }
        local profile = {
            schemaVersion = 10,
            global = globalConfig,
            powerBar = { enabled = true, anchorMode = ns.Constants.ANCHORMODE_FREE, bgColor = color(1, 0, 0, 1) },
            resourceBar = { enabled = true, anchorMode = ns.Constants.ANCHORMODE_FREE, bgColor = color(0, 1, 0, 1) },
            runeBar = { enabled = true, anchorMode = ns.Constants.ANCHORMODE_FREE, bgColor = color(0, 0, 1, 1) },
            buffBars = { enabled = true, anchorMode = ns.Constants.ANCHORMODE_FREE, bgColor = color(1, 1, 0, 1) },
        }

        Migration.Run(profile)

        for section, expected in pairs(LEGACY_FREE_POSITION_DEFAULTS) do
            local expectedX, expectedY = getAbsoluteAnchorPosition(ns, expected.point, expected.x, expected.y)
            local mod = makeFreeModeModule(section, globalConfig, profile[section])

            assert.is_true(mod:UpdateLayout("V11SeededLegacyDefaults"))
            assertFreeFramePositionPreserved(mod.InnerFrame, expectedX, expectedY)
        end
    end)

    it("UpdateLayout preserves final frame placement for V11 migrated free-mode anchors", function()
        local globalConfig = {
            barHeight = 20,
            barWidth = 180,
            barBgColor = color(0, 0, 0, 0.5),
            updateFrequency = 0,
        }
        local profile = {
            schemaVersion = 10,
            global = globalConfig,
            powerBar = {
                enabled = true,
                anchorMode = ns.Constants.ANCHORMODE_FREE,
                anchorPoint = "TOPLEFT",
                relativePoint = "BOTTOM",
                offsetX = 150,
                offsetY = -50,
                bgColor = color(1, 0, 0, 1),
            },
        }
        Migration.Run(profile)
        local migrated = profile.powerBar.editModePositions.Modern

        local mod = makeFreeModeModule("powerBar", globalConfig, profile.powerBar)
        assert.is_true(mod:UpdateLayout("V11MigratedFreePosition"))
        assertAbsolutePositionPreserved(ns, "TOPLEFT", "BOTTOM", 150, -50, migrated)
        assertFreeFramePositionPreserved(
            mod.InnerFrame,
            getAbsoluteAnchorPosition(ns, migrated.point, migrated.x, migrated.y)
        )
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

        BarMixin.AddFrameMixin(mod, "ExternalFrameModule")
        mod:EnsureFrame()

        assert.are.equal(0, registerCalls)
        assert.are.equal("ExternalFrame", mod.InnerFrame:GetName())
    end)

    it("EnsureFrame registers Edit Mode only once per frame", function()
        local registerCalls = 0
        local mod = {
            CreateFrame = function()
                return makeFrame({ name = "TestFrame" })
            end,
            ShouldRegisterEditMode = function()
                return true
            end,
            _RegisterEditMode = function(self)
                registerCalls = registerCalls + 1
                self._editModeRegisteredFrame = self.InnerFrame
            end,
            GetGlobalConfig = function()
                return {}
            end,
            GetModuleConfig = function()
                return {}
            end,
        }

        BarMixin.AddFrameMixin(mod, "TestModule")

        mod:EnsureFrame()
        mod:EnsureFrame()

        assert.are.equal(1, registerCalls)
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

        BarMixin.AddFrameMixin(mod, "TestModule")

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

        BarMixin.AddFrameMixin(mod, "TestModule")

        assert.are.equal(aceEnabled, mod.IsEnabled)
        assert.is_function(mod.UpdateLayout)
        assert.is_function(mod.GetModuleConfig)
        assert.is_function(mod.EnsureFrame)
    end)

    it("AddMixin is idempotent — second call is a no-op", function()
        local mod = {
            ShouldRegisterEditMode = function() return false end,
        }

        BarMixin.AddFrameMixin(mod, "TestModule")
        local mt1 = getmetatable(mod)

        BarMixin.AddFrameMixin(mod, "TestModule")
        local mt2 = getmetatable(mod)

        assert.are.equal(mt1, mt2)
        assert.is_true(mod._mixinApplied)
    end)
end)
