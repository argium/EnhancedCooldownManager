-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("BuffBars real source", function()
    local originalGlobals
    local BuffBars
    local BuffBarCooldownViewer
    local ns
    local makeFrame = TestHelpers.makeFrame
    local makeTexture = TestHelpers.makeTexture
    local registerFrameCalls
    local unregisterFrameCalls
    local addMixinCalls
    local spellColorStore
    local spellColorGetScopes
    local timerCallbacks
    local errorLogs

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "UIParent",
            "BuffBarCooldownViewer",
            "hooksecurefunc",
            "InCombatLockdown",
            "issecretvalue",
            "C_Timer",
            "GetTime",
            "CreateFrame",
            "LibStub",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    local makeHookableFrame = TestHelpers.makeHookableFrame

    local function stubChildLayoutEnvironment()
        spellColorStore.GetColorForBar = function(_, _)
            return { r = 0.4, g = 0.5, b = 0.6, a = 1 }
        end
        spellColorStore.GetDefaultColor = function(_)
            return { r = 1, g = 1, b = 1, a = 1 }
        end
        ns.ColorUtil = {
            ColorToHex = function()
                return "abcdef"
            end,
        }
        ns.ToString = tostring
        ns.FrameUtil.GetTexture = function()
            return "Interface\\TargetingFrame\\UI-StatusBar"
        end
        ns.FrameUtil.ApplyFont = function() end
        ns.DebugAssert = function(condition)
            assert.is_true(condition)
        end
        ns.FrameUtil.GetBarBackground = function()
            return nil
        end
        ns.FrameUtil.GetIconTexture = function()
            return nil
        end
        ns.FrameUtil.GetIconOverlay = function()
            return nil
        end
        ns.FrameUtil.LazySetHeight = function(frame, value)
            frame.__height = value
        end
        ns.FrameUtil.LazySetWidth = function(frame, value)
            frame.__width = value
        end
        ns.FrameUtil.LazySetStatusBarTexture = function(bar, texture)
            bar.__texture = texture
        end
        ns.FrameUtil.LazySetStatusBarColor = function(bar, r, g, b, a)
            bar.__color = { r, g, b, a }
        end
        ns.FrameUtil.LazySetAnchors = function(frame, anchors)
            frame.__ecmAnchorCache = anchors
            frame.__anchors = anchors
        end
        ns.FrameUtil.LazySetAlpha = function(frame, value)
            frame.__alpha = value
        end
    end

    local function makeStyledChild(name, shown, layoutIndex)
        local child = makeHookableFrame({ name = name, shown = shown, width = 200, height = 20 })
        child.layoutIndex = layoutIndex
        child.Bar = {
            Name = {
                GetText = function()
                    return name
                end,
                SetShown = function(self, value)
                    self.__shown = value
                end,
            },
            Duration = {
                SetShown = function(self, value)
                    self.__shown = value
                end,
            },
            Pip = {
                Hide = function() end,
                SetTexture = function() end,
            },
            SetShown = function(self, value)
                self.__shown = value
            end,
        }
        child.Icon = makeHookableFrame({ shown = false, width = 20, height = 20 })
        child.Icon.SetShown = function(self, value)
            self.__shown = value
        end
        child.Icon.Applications = {
            SetShown = function(self, value)
                self.__shown = value
            end,
        }
        child.cooldownInfo = { spellID = layoutIndex }
        child.cooldownID = 1000 + layoutIndex
        child.iconTextureFileID = 2000 + layoutIndex
        return child
    end

    before_each(function()
        registerFrameCalls = 0
        unregisterFrameCalls = 0
        addMixinCalls = 0
        spellColorGetScopes = {}
        timerCallbacks = {}
        errorLogs = {}
        spellColorStore = {
            GetColorForBar = function()
                return nil
            end,
            GetDefaultColor = function()
                return { r = 1, g = 1, b = 1, a = 1 }
            end,
            ClearDiscoveredKeys = function() end,
            DiscoverBar = function() end,
        }
        ns = {
            Log = function() end,
            ErrorLogOnce = function(module, key, message, data)
                errorLogs[#errorLogs + 1] = { module = module, key = key, message = message, data = data }
            end,
            DebugAssert = function() end,
            IsDebugEnabled = function() return false end,
            Constants = nil,
            EditMode = {
                Lib = {
                    IsInEditMode = function()
                        return false
                    end,
                },
                GetActiveLayoutName = function()
                    return "Modern"
                end,
                GetPosition = function(positions, layoutName)
                    local activeLayoutName = layoutName or "Modern"
                    local position = positions and positions[activeLayoutName]
                    if position then
                        return position
                    end
                    return { point = "CENTER", x = 0, y = 0 }
                end,
                SavePosition = function(container, fieldName, layoutName, point, x, y)
                    container[fieldName] = container[fieldName] or {}
                    container[fieldName][layoutName] = { point = point, x = x, y = y }
                end,
            },
            FrameUtil = {
                NormalizePosition = function(point, _, x, y)
                    return point, x, y
                end,
                GetParentSize = function(parent)
                    if parent and parent.GetSize then
                        return parent:GetSize()
                    end
                    return 0, 0
                end,
                GetIconTextureFileID = function(frame)
                    return frame.iconTextureFileID
                end,
            },
            BarMixin = {
                FrameProto = {
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
                },
                AddFrameMixin = function(target)
                    addMixinCalls = addMixinCalls + 1
                    target.EnsureFrame = target.EnsureFrame or function() end
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
                Get = function(scope)
                    spellColorGetScopes[#spellColorGetScopes + 1] = scope
                    return spellColorStore
                end,
            },
            Runtime = {
                ScheduleLayoutUpdate = function() end,
                RegisterFrame = function()
                    registerFrameCalls = registerFrameCalls + 1
                end,
                UnregisterFrame = function()
                    unregisterFrameCalls = unregisterFrameCalls + 1
                end,
                RequestLayout = function() end,
            },
        }
        TestHelpers.LoadChunk("Constants.lua", "Unable to load Constants.lua")(nil, ns)
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")(nil, ns)

        _G.GetTime = function()
            return 0
        end
        _G.CreateFrame = function(_, name)
            local frame = makeFrame({ name = name })
            frame.CreateTexture = function()
                return makeTexture()
            end
            frame.CreateFontString = function()
                local fs = makeTexture()
                fs.SetText = function() end
                fs.SetJustifyH = function() end
                fs.SetJustifyV = function() end
                fs.SetPoint = function() end
                return fs
            end
            frame.SetFrameStrata = function() end
            frame.SetFrameLevel = function() end
            frame.GetFrameLevel = function()
                return 1
            end
            frame.SetAllPoints = function() end
            frame.SetMinMaxValues = function() end
            frame.SetValue = function() end
            frame.SetStatusBarTexture = function() end
            frame.SetStatusBarColor = function() end
            return frame
        end
        TestHelpers.SetupLibStub()
        TestHelpers.SetupLibEditModeStub()
        TestHelpers.LoadChunk("BarMixin.lua", "Unable to load BarMixin.lua")(nil, ns)
        TestHelpers.LoadChunk("BarStyle.lua", "Unable to load BarStyle.lua")(nil, ns)
        assert(ns.BarMixin, "BarMixin module did not initialize")
        assert(ns.BarStyle, "BarStyle module did not initialize")
        ns.BarMixin = {
            FrameProto = {
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
            },
            AddFrameMixin = function(target)
                addMixinCalls = addMixinCalls + 1
                target.EnsureFrame = target.EnsureFrame or function() end
            end,
        }

        _G.UIParent = makeFrame({ name = "UIParent", width = 1920, height = 1080 })
        _G.hooksecurefunc = function(object, methodName, callback)
            local original = object[methodName]
            object[methodName] = function(self, ...)
                if original then
                    original(self, ...)
                end
                callback(self, ...)
            end
        end
        _G.C_Timer = {
            After = function(_, callback)
                timerCallbacks[#timerCallbacks + 1] = callback
            end,
            NewTimer = function(_, callback)
                timerCallbacks[#timerCallbacks + 1] = callback
                return { Cancel = function() end }
            end,
        }
        _G.InCombatLockdown = function()
            return false
        end
        _G.issecretvalue = function()
            return false
        end

        ns.Addon = {
            NewModule = function(self, name)
                local module = { Name = name }
                self[name] = module
                return module
            end,
        }

        BuffBarCooldownViewer = makeHookableFrame({ name = "BuffBarCooldownViewer", shown = true })
        _G.BuffBarCooldownViewer = BuffBarCooldownViewer
        function BuffBarCooldownViewer:GetChildren()
            return
        end

        TestHelpers.LoadChunk("Modules/BuffBars.lua", "Unable to load Modules/BuffBars.lua")(nil, ns)
        BuffBars = assert(ns.Addon.BuffBars, "BuffBars module did not initialize")
    end)

    it("returns the Blizzard buff bar viewer from CreateFrame", function()
        assert.are.equal(BuffBarCooldownViewer, BuffBars:CreateFrame())
    end)

    it("opts out of generic Edit Mode registration", function()
        assert.is_false(BuffBars:ShouldRegisterEditMode())
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


    it("hides the viewer when UpdateLayout decides not to show", function()
        function BuffBars:GetGlobalConfig()
            return { texture = "Solid" }
        end
        function BuffBars:GetModuleConfig()
            return { anchorMode = ns.Constants.ANCHORMODE_CHAIN }
        end
        function BuffBars:ShouldShow()
            return false
        end

        local result = BuffBars:UpdateLayout("test")

        assert.is_false(result)
        assert.is_false(BuffBarCooldownViewer:IsShown())
    end)

    it("returns false from IsReady when the viewer is missing or cannot enumerate children", function()
        BuffBarCooldownViewer = nil
        _G.BuffBarCooldownViewer = nil
        assert.is_false(BuffBars:IsReady())

        BuffBarCooldownViewer = makeHookableFrame({ name = "BuffBarCooldownViewer", shown = true })
        _G.BuffBarCooldownViewer = BuffBarCooldownViewer
        function BuffBarCooldownViewer:GetChildren()
            error("forbidden")
        end
        assert.is_false(BuffBars:IsReady())
    end)

    it("logs and returns false when layout cannot enumerate viewer children", function()
        function BuffBars:GetGlobalConfig()
            return {}
        end
        function BuffBars:GetModuleConfig()
            return {}
        end
        function BuffBarCooldownViewer:GetChildren()
            error("attempted to iterate a table that cannot be accessed while tainted")
        end

        assert.has_no.errors(function()
            assert.is_false(BuffBars:UpdateLayout("rated-bg"))
        end)

        assert.are.equal(1, #errorLogs)
        assert.are.equal("BuffBars", errorLogs[1].module)
        assert.are.equal("GetChildren", errorLogs[1].key)
        assert.are.equal("rated-bg", errorLogs[1].data.reason)
        assert.is_truthy(errorLogs[1].data.error:find("attempted to iterate", 1, true))
    end)

    it("uses FrameMixin positioning for detached mode", function()
        local detachedAnchor = makeHookableFrame({ name = "ECMDetachedAnchor" })
        ns.Runtime.DetachedAnchor = detachedAnchor
        local originalCalculateLayoutParams = ns.BarMixin.FrameProto.CalculateLayoutParams
        local originalLazySetAnchors = ns.FrameUtil.LazySetAnchors

        ns.BarMixin.FrameProto.CalculateLayoutParams = function(self)
            local gc = self:GetGlobalConfig()
            return {
                mode = ns.Constants.ANCHORMODE_DETACHED,
                anchor = ns.Runtime.DetachedAnchor,
                anchorPoint = "TOPLEFT",
                anchorRelativePoint = "BOTTOMLEFT",
                offsetX = 0,
                offsetY = -2,
                height = (gc and gc.barHeight) or 22,
            }
        end
        ns.FrameUtil.LazySetAnchors = function(frame, anchors)
            frame.__ecmAnchorCache = anchors
            frame.__anchors = anchors
        end

        BuffBars.GetModuleConfig = function()
            return {
                anchorMode = ns.Constants.ANCHORMODE_DETACHED,
            }
        end
        BuffBars.GetGlobalConfig = function()
            return {
                barHeight = 22,
                detachedGrowDirection = ns.Constants.GROW_DIRECTION_DOWN,
                detachedModuleSpacing = 2,
            }
        end
        function BuffBarCooldownViewer:GetChildren()
            return
        end
        function BuffBars:ShouldShow()
            return true
        end

        local result = BuffBars:UpdateLayout("test")

        assert.is_true(result)
        assert.are.equal("TOPLEFT", BuffBarCooldownViewer.__anchors[1][1])
        assert.are.equal(detachedAnchor, BuffBarCooldownViewer.__anchors[1][2])
        assert.are.equal("BOTTOMLEFT", BuffBarCooldownViewer.__anchors[1][3])
        assert.are.equal(-2, BuffBarCooldownViewer.__anchors[1][5])

        ns.Runtime.DetachedAnchor = nil
        ns.BarMixin.FrameProto.CalculateLayoutParams = originalCalculateLayoutParams
        ns.FrameUtil.LazySetAnchors = originalLazySetAnchors
    end)

    it("free mode sets width from baseBarWidth*barWidthScale without touching viewer anchors", function()
        local appliedWidths = {}
        local anchorCalls = {}
        ns.FrameUtil.LazySetWidth = function(frame, value)
            appliedWidths[#appliedWidths + 1] = { frame = frame, value = value }
        end
        local originalLazySetAnchors = ns.FrameUtil.LazySetAnchors
        ns.FrameUtil.LazySetAnchors = function(frame, anchors)
            anchorCalls[#anchorCalls + 1] = frame
            frame.__ecmAnchorCache = anchors
            frame.__anchors = anchors
        end

        BuffBarCooldownViewer.baseBarWidth = 180
        BuffBarCooldownViewer.barWidthScale = 1.25

        function BuffBarCooldownViewer:GetChildren()
            return
        end
        function BuffBars:GetModuleConfig()
            return {
                anchorMode = ns.Constants.ANCHORMODE_FREE,
            }
        end
        function BuffBars:GetGlobalConfig()
            return { texture = "Solid", barHeight = 18, barWidth = 250 }
        end
        function BuffBars:ShouldShow()
            return true
        end

        local result = BuffBars:UpdateLayout("test")

        assert.is_true(result)
        -- Width should be set from baseBarWidth * barWidthScale
        assert.are.equal(1, #appliedWidths)
        assert.are.equal(BuffBarCooldownViewer, appliedWidths[1].frame)
        assert.are.equal(225, appliedWidths[1].value)
        -- Viewer anchors must NOT be touched in free mode
        for _, frame in ipairs(anchorCalls) do
            assert.are_not.equal(BuffBarCooldownViewer, frame,
                "Free mode must not set anchors on the viewer")
        end

        ns.FrameUtil.LazySetAnchors = originalLazySetAnchors
    end)

    it("free mode does not clobber Blizzard-managed viewer position across edit mode cycles", function()
        stubChildLayoutEnvironment()

        local first = makeStyledChild("First", true, 1)
        function BuffBarCooldownViewer:GetChildren()
            return first
        end

        -- Simulate Blizzard placing the viewer at a specific position
        BuffBarCooldownViewer.__anchors = { { "CENTER", UIParent, "CENTER", 100, -200 } }
        BuffBarCooldownViewer.__width = 300

        function BuffBars:GetModuleConfig()
            return {
                anchorMode = ns.Constants.ANCHORMODE_FREE,
                showIcon = false,
                showSpellName = true,
                showDuration = true,
            }
        end
        function BuffBars:GetGlobalConfig()
            return { texture = "Solid", barHeight = 18, barWidth = 250 }
        end
        function BuffBars:ShouldShow()
            return true
        end

        -- Run multiple layout passes (simulating edit mode enter/exit)
        BuffBars:UpdateLayout("EditModeEnter")
        BuffBars:UpdateLayout("EditModeExit")
        BuffBars:UpdateLayout("SecondPass")

        -- Verify the viewer's own anchor was never replaced with a chain anchor
        local pt = BuffBarCooldownViewer.__anchors[1]
        assert.are.equal("CENTER", pt[1])
        assert.are.equal(UIParent, pt[2])
        assert.are.equal("CENTER", pt[3])
    end)

    it("free mode infers downward growth from non-BOTTOM viewer anchor", function()
        stubChildLayoutEnvironment()

        local first = makeStyledChild("First", true, 1)
        local second = makeStyledChild("Second", true, 2)
        function BuffBarCooldownViewer:GetChildren()
            return first, second
        end
        -- Simulate viewer anchored at TOP (should grow down)
        BuffBarCooldownViewer.__anchors = { { "TOP", UIParent, "CENTER", 0, -50 } }

        function BuffBars:GetModuleConfig()
            return {
                anchorMode = ns.Constants.ANCHORMODE_FREE,
                showIcon = false,
                showSpellName = true,
                showDuration = true,
            }
        end
        function BuffBars:GetGlobalConfig()
            return { texture = "Solid", barHeight = 18, barWidth = 250 }
        end
        function BuffBars:ShouldShow()
            return true
        end

        BuffBars:UpdateLayout("test")

        -- growsUp=false → children anchored TOP edge
        assert.are.equal("TOPLEFT", first.__anchors[1][1])
        assert.are.equal("TOPLEFT", second.__anchors[1][1])
        assert.are.equal("BOTTOMLEFT", second.__anchors[1][3])
    end)

    it("viewer hooks defer layout and respect the layout-running guard", function()
        local reasons = {}
        local enabled = true
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end
        function BuffBars:IsEnabled()
            return enabled
        end

        BuffBars:HookViewer()
        BuffBarCooldownViewer._hooks.OnShow[1]()
        BuffBars._layoutRunning = true
        BuffBarCooldownViewer._hooks.OnSizeChanged[1]()
        BuffBars._layoutRunning = nil
        BuffBarCooldownViewer._hooks.OnSizeChanged[1]()
        enabled = false
        BuffBarCooldownViewer._hooks.OnShow[1]()
        BuffBarCooldownViewer._hooks.OnSizeChanged[1]()

        assert.same({ "BuffBars:viewer:OnShow", "BuffBars:viewer:OnSizeChanged" }, reasons)
    end)

    it("child SetPoint hooks restore cached anchors and respect the layout-running guard", function()
        local reasons = {}
        stubChildLayoutEnvironment()

        local child = makeStyledChild("Child", true, 1)
        function BuffBarCooldownViewer:GetChildren()
            return child
        end
        function BuffBars:GetGlobalConfig()
            return { texture = "Solid", barHeight = 18, barWidth = 250 }
        end
        function BuffBars:GetModuleConfig()
            return {
                anchorMode = ns.Constants.ANCHORMODE_CHAIN,
                showIcon = false,
                showSpellName = true,
                showDuration = true,
            }
        end
        function BuffBars:ShouldShow()
            return true
        end
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end

        assert.is_true(BuffBars:UpdateLayout("test"))
        assert.is_true(child.__ecmHooked)
        assert.is_not_nil(child.__ecmAnchorCache)

        BuffBars._layoutRunning = true
        child:SetPoint("CENTER", nil, "CENTER", 99, 99)
        assert.are.equal(0, #reasons)

        BuffBars._layoutRunning = nil
        child:SetPoint("CENTER", nil, "CENTER", 99, 99)

        assert.same({ "BuffBars:SetPoint:hook" }, reasons)
        assert.are.equal(child.__ecmAnchorCache, child.__anchors)
    end)

    it("child OnShow and OnHide hooks defer relayout through the real module hooks", function()
        local reasons = {}
        stubChildLayoutEnvironment()

        local child = makeStyledChild("Child", false, 1)
        function BuffBarCooldownViewer:GetChildren()
            return child
        end
        function BuffBars:GetGlobalConfig()
            return { texture = "Solid", barHeight = 18, barWidth = 250 }
        end
        function BuffBars:GetModuleConfig()
            return {
                anchorMode = ns.Constants.ANCHORMODE_CHAIN,
                showIcon = false,
                showSpellName = true,
                showDuration = true,
            }
        end
        function BuffBars:ShouldShow()
            return true
        end
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end

        assert.is_true(BuffBars:UpdateLayout("test"))
        assert.is_true(child.__ecmHooked)

        BuffBars._layoutRunning = true
        child._hooks.OnShow[1]()
        child._hooks.OnHide[1]()
        assert.are.equal(0, #reasons)

        BuffBars._layoutRunning = nil
        child._hooks.OnShow[1]()
        child._hooks.OnHide[1]()

        assert.same({ "BuffBars:OnShow:child", "BuffBars:OnHide:child" }, reasons)
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
        spellColorStore.GetColorForBar = function()
            secretColorRequested = true
            return nil
        end
        spellColorStore.GetDefaultColor = function()
            return { r = 1, g = 1, b = 1, a = 1 }
        end
        ns.ColorUtil = {
            ColorToHex = function()
                return "ffffff"
            end,
        }
        ns.ToString = tostring
        ns.FrameUtil.GetTexture = function()
            return "Solid"
        end
        ns.FrameUtil.ApplyFont = function() end
        ns.DebugAssert = function() end
        ns.FrameUtil.GetBarBackground = function()
            return nil
        end
        ns.FrameUtil.GetIconTexture = function()
            return nil
        end
        ns.FrameUtil.GetIconOverlay = function()
            return nil
        end
        ns.FrameUtil.LazySetHeight = function() end
        ns.FrameUtil.LazySetWidth = function() end
        ns.FrameUtil.LazySetStatusBarTexture = function() end
        ns.FrameUtil.LazySetStatusBarColor = function() end
        ns.FrameUtil.LazySetAnchors = function() end
        ns.FrameUtil.LazySetAlpha = function() end
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
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end
        function BuffBars:GetModuleConfig()
            return { enabled = true }
        end

        BuffBars:OnInitialize()
        BuffBars:OnEnable()

        assert.are.equal(1, addMixinCalls)
        assert.are.equal(1, registerFrameCalls)
        assert.are.equal(1, #timerCallbacks)

        timerCallbacks[1]()

        assert.same({ "BuffBars:ModuleInit" }, reasons)
        assert.is_true(BuffBars._viewerHooked)
    end)

    it("unregisters on disable", function()
        function BuffBars:UnregisterAllEvents() end

        BuffBars:OnDisable()

        assert.are.equal(1, unregisterFrameCalls)
    end)

    it("runs the main UpdateLayout hot path, discovers bars, and clears colors on spec changes", function()
        local discovered = {}
        local cleared = 0
        local appliedTextures = {}
        local appliedColors = {}
        spellColorGetScopes = {}
        spellColorStore.ClearDiscoveredKeys = function()
            cleared = cleared + 1
        end
        spellColorStore.DiscoverBar = function(_, frame)
            discovered[#discovered + 1] = frame
        end
        spellColorStore.GetColorForBar = function()
            return { r = 0.4, g = 0.5, b = 0.6, a = 1 }
        end
        spellColorStore.GetDefaultColor = function()
            return { r = 1, g = 1, b = 1, a = 1 }
        end
        ns.ColorUtil = {
            ColorToHex = function()
                return "abcdef"
            end,
        }
        ns.ToString = tostring
        ns.FrameUtil.GetTexture = function()
            return "Interface\\TargetingFrame\\UI-StatusBar"
        end
        ns.FrameUtil.ApplyFont = function() end
        ns.DebugAssert = function(condition)
            assert.is_true(condition)
        end
        ns.FrameUtil.GetBarBackground = function()
            return nil
        end
        ns.FrameUtil.GetIconTexture = function()
            return nil
        end
        ns.FrameUtil.GetIconOverlay = function()
            return nil
        end
        ns.FrameUtil.LazySetHeight = function(frame, value)
            frame.__height = value
        end
        ns.FrameUtil.LazySetWidth = function(frame, value)
            frame.__width = value
        end
        ns.FrameUtil.LazySetStatusBarTexture = function(bar, texture)
            appliedTextures[#appliedTextures + 1] = { bar = bar, texture = texture }
        end
        ns.FrameUtil.LazySetStatusBarColor = function(bar, r, g, b, a)
            appliedColors[#appliedColors + 1] = { bar = bar, color = { r, g, b, a } }
        end
        ns.FrameUtil.LazySetAnchors = function(frame, anchors)
            frame.__ecmAnchorCache = anchors
            frame.__anchors = anchors
        end
        ns.FrameUtil.LazySetAlpha = function(frame, value)
            frame.__alpha = value
        end

        local first = makeStyledChild("First", true, 2)
        local second = makeStyledChild("Second", false, 1)
        local ignored = makeStyledChild("Ignored", true, 99)
        ignored.ignoreInLayout = true
        function BuffBarCooldownViewer:GetChildren()
            return first, ignored, second
        end
        function BuffBars:GetGlobalConfig()
            return { texture = "Solid", barHeight = 18, barWidth = 250 }
        end
        function BuffBars:GetModuleConfig()
            return {
                anchorMode = ns.Constants.ANCHORMODE_CHAIN,
                showIcon = false,
                showSpellName = true,
                showDuration = true,
            }
        end
        function BuffBars:ShouldShow()
            return true
        end

        local result = BuffBars:UpdateLayout("PLAYER_SPECIALIZATION_CHANGED")

        assert.is_true(result)
        assert.are.equal(1, cleared)
        assert.same({ second, first }, discovered)
        assert.is_true(#spellColorGetScopes > 0)
        for _, scope in ipairs(spellColorGetScopes) do
            assert.are.equal(ns.Constants.SCOPE_BUFFBARS, scope)
        end
        assert.is_true(first.__ecmHooked)
        assert.is_true(second.__ecmHooked)
        assert.are.equal(2, #appliedTextures)
        assert.are.equal(2, #appliedColors)
        assert.is_true(BuffBarCooldownViewer:IsShown())
    end)

    it("clears _layoutRunning even when styleChildFrame throws", function()
        spellColorStore.DiscoverBar = function() end
        spellColorStore.GetColorForBar = function()
            error("simulated style error")
        end
        spellColorStore.GetDefaultColor = function()
            return { r = 1, g = 1, b = 1, a = 1 }
        end
        ns.ColorUtil = { ColorToHex = function() return "ffffff" end }
        ns.ToString = tostring
        ns.FrameUtil.GetTexture = function() return "Solid" end
        ns.FrameUtil.ApplyFont = function() end
        local assertedCondition
        ns.DebugAssert = function(cond) assertedCondition = cond end
        ns.FrameUtil.GetBarBackground = function() return nil end
        ns.FrameUtil.GetIconTexture = function() return nil end
        ns.FrameUtil.GetIconOverlay = function() return nil end
        ns.FrameUtil.LazySetHeight = function() end
        ns.FrameUtil.LazySetWidth = function() end
        ns.FrameUtil.LazySetStatusBarTexture = function() end
        ns.FrameUtil.LazySetStatusBarColor = function() end
        ns.FrameUtil.LazySetAnchors = function(frame, anchors)
            frame.__ecmAnchorCache = anchors
        end
        ns.FrameUtil.LazySetAlpha = function() end

        local child = makeStyledChild("Boom", true, 1)
        function BuffBarCooldownViewer:GetChildren() return child end
        function BuffBars:GetGlobalConfig()
            return { texture = "Solid", barHeight = 18 }
        end
        function BuffBars:GetModuleConfig()
            return {
                anchorMode = ns.Constants.ANCHORMODE_CHAIN,
                showIcon = false, showSpellName = true, showDuration = true,
            }
        end
        function BuffBars:ShouldShow() return true end

        -- Should not propagate the error
        assert.has_no.errors(function()
            BuffBars:UpdateLayout("test-error")
        end)

        -- Critical: the flag must be cleared so future layouts aren't blocked
        assert.is_nil(BuffBars._layoutRunning)
        -- DebugAssert was called with a failure condition
        assert.is_false(assertedCondition)
    end)

    -- Helper: runs a single child through UpdateLayout and returns it styled.
    local function layoutSingleChild(child, moduleConfig, globalConfig)
        stubChildLayoutEnvironment()
        spellColorStore.DiscoverBar = function() end
        function BuffBarCooldownViewer:GetChildren() return child end
        function BuffBars:ShouldShow() return true end
        function BuffBars:GetGlobalConfig() return globalConfig end
        function BuffBars:GetModuleConfig() return moduleConfig end
        BuffBars:UpdateLayout("test")
    end

    local function defaultGlobal(overrides)
        local g = { texture = "Solid", barHeight = 18, barBgColor = { r = 0, g = 0, b = 0, a = 0.8 } }
        if overrides then for k, v in pairs(overrides) do g[k] = v end end
        return g
    end

    local function defaultModule(overrides)
        local m = {
            anchorMode = ns.Constants.ANCHORMODE_CHAIN,
            showIcon = true, showSpellName = true, showDuration = true,
        }
        if overrides then for k, v in pairs(overrides) do m[k] = v end end
        return m
    end

    describe("styleBarHeight", function()
        it("propagates height to frame, bar, and icon", function()
            local child = makeStyledChild("H", true, 1)
            layoutSingleChild(child, defaultModule(), defaultGlobal({ barHeight = 24 }))

            assert.are.equal(24, child.__height)
            assert.are.equal(24, child.Bar.__height)
            assert.are.equal(24, child.Icon.__height)
            assert.are.equal(24, child.Icon.__width)
        end)

        it("uses module config height when provided", function()
            local child = makeStyledChild("H", true, 1)
            layoutSingleChild(child, defaultModule({ height = 30 }), defaultGlobal({ barHeight = 18 }))

            assert.are.equal(30, child.__height)
        end)
    end)

    describe("styleBarBackground", function()
        it("applies background color and texture", function()
            local bgRegion = {
                SetParent = function() end,
                SetPoint = function() end,
                SetTexture = function(self, t) self.__texture = t end,
                SetVertexColor = function(self, r, g, b, a) self.__vcolor = { r, g, b, a } end,
                ClearAllPoints = function() end,
                SetAllPoints = function() end,
                SetDrawLayer = function(self, layer, sub) self.__drawLayer = { layer, sub } end,
            }

            local child = makeStyledChild("BG", true, 1)
            local bgColor = { r = 0.1, g = 0.2, b = 0.3, a = 0.5 }
            stubChildLayoutEnvironment()
            spellColorStore.DiscoverBar = function() end
            ns.FrameUtil.GetBarBackground = function() return bgRegion end
            function BuffBarCooldownViewer:GetChildren() return child end
            function BuffBars:ShouldShow() return true end
            function BuffBars:GetGlobalConfig() return defaultGlobal() end
            function BuffBars:GetModuleConfig() return defaultModule({ bgColor = bgColor }) end
            BuffBars:UpdateLayout("test")

            assert.are.equal(ns.Constants.FALLBACK_TEXTURE, bgRegion.__texture)
            assert.same({ 0.1, 0.2, 0.3, 0.5 }, bgRegion.__vcolor)
            assert.same({ "BACKGROUND", 0 }, bgRegion.__drawLayer)
        end)
    end)

    describe("styleBarColor", function()
        it("applies spell color to the status bar", function()
            local appliedColor
            local child = makeStyledChild("C", true, 1)
            stubChildLayoutEnvironment()
            spellColorGetScopes = {}
            spellColorStore.DiscoverBar = function() end
            spellColorStore.GetColorForBar = function()
                return { r = 0.4, g = 0.5, b = 0.6, a = 1 }
            end
            ns.FrameUtil.LazySetStatusBarColor = function(_, r, g, b, a)
                appliedColor = { r, g, b, a }
            end
            function BuffBarCooldownViewer:GetChildren() return child end
            function BuffBars:ShouldShow() return true end
            function BuffBars:GetGlobalConfig() return defaultGlobal() end
            function BuffBars:GetModuleConfig() return defaultModule() end
            BuffBars:UpdateLayout("test")

            assert.is_not_nil(appliedColor)
            assert.same({ 0.4, 0.5, 0.6, 1.0 }, appliedColor)
            assert.is_true(#spellColorGetScopes > 0)
            for _, scope in ipairs(spellColorGetScopes) do
                assert.are.equal(ns.Constants.SCOPE_BUFFBARS, scope)
            end
        end)

        it("schedules retry when all identifiers are secret", function()
            local child = makeStyledChild("S", true, 1)
            _G.issecretvalue = function() return true end

            layoutSingleChild(child, defaultModule(), defaultGlobal())

            assert.are.equal(1, #timerCallbacks, "expected one retry timer")
        end)
    end)

    describe("styleBarIcon", function()
        it("hides icon when showIcon is false", function()
            local child = makeStyledChild("I", true, 1)
            layoutSingleChild(child, defaultModule({ showIcon = false }), defaultGlobal())

            assert.is_false(child.Icon.__shown)
        end)

        it("shows icon when showIcon is true", function()
            local child = makeStyledChild("I", true, 1)
            layoutSingleChild(child, defaultModule({ showIcon = true }), defaultGlobal())

            assert.is_true(child.Icon.__shown)
        end)

        it("hides DebuffBorder with zero alpha", function()
            local child = makeStyledChild("I", true, 1)
            child.DebuffBorder = makeFrame({ shown = true })
            child.DebuffBorder.Hide = function(self) self.__hidden = true end

            layoutSingleChild(child, defaultModule(), defaultGlobal())

            assert.are.equal(0, child.DebuffBorder.__alpha)
        end)
    end)

    describe("styleBarAnchors", function()
        it("anchors bar to icon right edge when icon is visible", function()
            local child = makeStyledChild("A", true, 1)
            child.Icon.__shown = true
            child.Icon.IsShown = function() return true end

            layoutSingleChild(child, defaultModule({ showIcon = true }), defaultGlobal())

            local barAnchors = child.Bar.__anchors
            assert.is_not_nil(barAnchors)
            assert.are.equal("TOPRIGHT", barAnchors[1][3])
            assert.are.equal(child.Icon, barAnchors[1][2])
        end)

        it("anchors bar to frame left edge when icon is hidden", function()
            local child = makeStyledChild("A", true, 1)
            layoutSingleChild(child, defaultModule({ showIcon = false }), defaultGlobal())

            local barAnchors = child.Bar.__anchors
            assert.is_not_nil(barAnchors)
            assert.are.equal("TOPLEFT", barAnchors[1][3])
            assert.are.equal(child, barAnchors[1][2])
        end)

        it("hides spell name when showSpellName is false", function()
            local child = makeStyledChild("A", true, 1)
            layoutSingleChild(child, defaultModule({ showSpellName = false }), defaultGlobal())

            assert.is_false(child.Bar.Name.__shown)
        end)

        it("hides duration when showDuration is false", function()
            local child = makeStyledChild("A", true, 1)
            layoutSingleChild(child, defaultModule({ showDuration = false }), defaultGlobal())

            assert.is_false(child.Bar.Duration.__shown)
        end)
    end)
end)
