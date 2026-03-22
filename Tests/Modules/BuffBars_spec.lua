-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("BuffBars real source", function()
    local originalGlobals
    local BuffBars
    local ns
    local makeFrame = TestHelpers.makeFrame
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

    local function stubChildLayoutEnvironment()
        ECM.SpellColors.GetColorForBar = function()
            return { r = 0.4, g = 0.5, b = 0.6, a = 1 }
        end
        ECM.SpellColors.GetDefaultColor = function()
            return { r = 1, g = 1, b = 1, a = 1 }
        end
        ECM.ColorUtil = {
            ColorToHex = function()
                return "abcdef"
            end,
        }
        ECM.ToString = tostring
        ECM.GetTexture = function()
            return "Interface\\TargetingFrame\\UI-StatusBar"
        end
        ECM.ApplyFont = function() end
        ECM.DebugAssert = function(condition)
            assert.is_true(condition)
        end
        ECM.FrameUtil.GetBarBackground = function()
            return nil
        end
        ECM.FrameUtil.GetIconTexture = function()
            return nil
        end
        ECM.FrameUtil.GetIconOverlay = function()
            return nil
        end
        ECM.FrameUtil.LazySetHeight = function(frame, value)
            frame.__height = value
        end
        ECM.FrameUtil.LazySetWidth = function(frame, value)
            frame.__width = value
        end
        ECM.FrameUtil.LazySetStatusBarTexture = function(bar, texture)
            bar.__texture = texture
        end
        ECM.FrameUtil.LazySetStatusBarColor = function(bar, r, g, b, a)
            bar.__color = { r, g, b, a }
        end
        ECM.FrameUtil.LazySetAnchors = function(frame, anchors)
            frame.__ecmAnchorCache = anchors
            frame.__anchors = anchors
        end
        ECM.FrameUtil.LazySetAlpha = function(frame, value)
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
        timerCallbacks = {}
        _G.ECM = {
            Log = function() end,
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
                SavePosition = function(container, fieldName, layoutName, point, x, y)
                    container[fieldName] = container[fieldName] or {}
                    container[fieldName][layoutName] = { point = point, x = x, y = y }
                end,
            },
            FrameUtil = {
                NormalizePosition = function(point, _, x, y)
                    return point, x, y
                end,
                GetIconTextureFileID = function(frame)
                    return frame.iconTextureFileID
                end,
            },
            FrameMixin = {
                Proto = {
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
                AddMixin = function(target)
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
                SetConfigAccessor = function() end,
                ClearDiscoveredKeys = function() end,
                DiscoverBar = function() end,
            },
            Runtime = {
                RegisterFrame = function()
                    registerFrameCalls = registerFrameCalls + 1
                end,
                UnregisterFrame = function()
                    unregisterFrameCalls = unregisterFrameCalls + 1
                end,
            },
        }
        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")()

        _G.UIParent = makeFrame({ name = "UIParent" })
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
        }
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

    it("uses FrameMixin positioning for detached mode", function()
        local detachedAnchor = makeHookableFrame({ name = "ECMDetachedAnchor" })
        ECM.Runtime.DetachedAnchor = detachedAnchor
        local originalCalculateLayoutParams = ECM.FrameMixin.Proto.CalculateLayoutParams
        local originalLazySetAnchors = ECM.FrameUtil.LazySetAnchors

        ECM.FrameMixin.Proto.CalculateLayoutParams = function(self)
            local gc = self:GetGlobalConfig()
            return {
                mode = ECM.Constants.ANCHORMODE_DETACHED,
                anchor = ECM.Runtime.DetachedAnchor,
                anchorPoint = "TOPLEFT",
                anchorRelativePoint = "BOTTOMLEFT",
                offsetX = 0,
                offsetY = -2,
                height = (gc and gc.barHeight) or 22,
            }
        end
        ECM.FrameUtil.LazySetAnchors = function(frame, anchors)
            frame.__ecmAnchorCache = anchors
            frame.__anchors = anchors
        end

        BuffBars.GetModuleConfig = function()
            return {
                anchorMode = ECM.Constants.ANCHORMODE_DETACHED,
            }
        end
        BuffBars.GetGlobalConfig = function()
            return {
                barHeight = 22,
                detachedGrowDirection = ECM.Constants.GROW_DIRECTION_DOWN,
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

        ECM.Runtime.DetachedAnchor = nil
        ECM.FrameMixin.Proto.CalculateLayoutParams = originalCalculateLayoutParams
        ECM.FrameUtil.LazySetAnchors = originalLazySetAnchors
    end)

    it("applies free-mode width from baseBarWidth and barWidthScale", function()
        local appliedWidths = {}
        ECM.FrameUtil.LazySetWidth = function(frame, value)
            appliedWidths[#appliedWidths + 1] = { frame = frame, value = value }
        end
        ECM.FrameUtil.LazySetAnchors = function(frame, anchors)
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
                anchorMode = ECM.Constants.ANCHORMODE_FREE,
                editModePositions = {
                    Modern = { point = "CENTER", x = 12, y = -34 },
                },
            }
        end
        function BuffBars:GetGlobalConfig()
            return { texture = "Solid", barHeight = 18, barWidth = 250 }
        end
        function BuffBars:GetEditModePosition()
            return { point = "CENTER", x = 12, y = -34 }
        end
        function BuffBars:ShouldShow()
            return true
        end

        local result = BuffBars:UpdateLayout("test")

        assert.is_true(result)
        assert.are.equal(1, #appliedWidths)
        assert.are.equal(BuffBarCooldownViewer, appliedWidths[1].frame)
        assert.are.equal(225, appliedWidths[1].value)
        assert.same({ "CENTER", UIParent, "CENTER", 12, -34 }, BuffBarCooldownViewer.__anchors[1])
    end)

    it("ignores removed free grow direction config in free mode", function()
        stubChildLayoutEnvironment()

        local first = makeStyledChild("First", true, 1)
        local second = makeStyledChild("Second", true, 2)

        function BuffBarCooldownViewer:GetChildren()
            return first, second
        end
        function BuffBars:GetModuleConfig()
            return {
                anchorMode = ECM.Constants.ANCHORMODE_FREE,
                freeGrowDirection = ECM.Constants.GROW_DIRECTION_UP,
                showIcon = false,
                showSpellName = true,
                showDuration = true,
            }
        end
        function BuffBars:GetGlobalConfig()
            return { texture = "Solid", barHeight = 18, barWidth = 250 }
        end
        function BuffBars:GetEditModePosition()
            return { point = "CENTER", x = 12, y = -34 }
        end
        function BuffBars:ShouldShow()
            return true
        end

        assert.is_true(BuffBars:UpdateLayout("test"))
        assert.same({ "TOPLEFT", BuffBarCooldownViewer, "TOPLEFT", 0, 0 }, first.__anchors[1])
        assert.same({ "TOPLEFT", first, "BOTTOMLEFT", 0, 0 }, second.__anchors[1])
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

    it("viewer SetPoint hook persists free-mode positions during Edit Mode", function()
        local cfg = {
            anchorMode = ECM.Constants.ANCHORMODE_FREE,
            editModePositions = {},
        }

        function BuffBars:GetModuleConfig()
            return cfg
        end

        ECM.EditMode.Lib.IsInEditMode = function()
            return true
        end

        BuffBars:HookViewer()

        BuffBarCooldownViewer:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -350)

        local saved = cfg.editModePositions.Modern
        assert.is_not_nil(saved)
        assert.are.equal("TOPLEFT", saved.point)
        assert.are.equal(10, saved.x)
        assert.are.equal(-350, saved.y)
    end)

    it("viewer SetPoint hook saves the normalized position returned by EditMode", function()
        local cfg = {
            anchorMode = ECM.Constants.ANCHORMODE_FREE,
            editModePositions = {},
        }

        local normalizeCalls = {}

        function BuffBars:GetModuleConfig()
            return cfg
        end

        ECM.EditMode.Lib.IsInEditMode = function()
            return true
        end
        ECM.FrameUtil.NormalizePosition = function(point, relativePoint, x, y)
            normalizeCalls[#normalizeCalls + 1] = { point, relativePoint, x, y }
            return "TOPLEFT", 10, -1430
        end

        BuffBars:HookViewer()

        BuffBarCooldownViewer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 10, -350)

        assert.same({ { "TOPLEFT", "BOTTOMLEFT", 10, -350 } }, normalizeCalls)
        local saved = cfg.editModePositions.Modern
        assert.is_not_nil(saved)
        assert.are.equal("TOPLEFT", saved.point)
        assert.are.equal(10, saved.x)
        assert.are.equal(-1430, saved.y)
    end)

    it("viewer SetPoint hook ignores non-free modes and internal layout writes", function()
        local cfg = {
            anchorMode = ECM.Constants.ANCHORMODE_CHAIN,
            editModePositions = {},
        }

        function BuffBars:GetModuleConfig()
            return cfg
        end

        ECM.EditMode.Lib.IsInEditMode = function()
            return true
        end

        BuffBars:HookViewer()
        BuffBarCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 12, -34)
        assert.is_nil(cfg.editModePositions.Modern)

        cfg.anchorMode = ECM.Constants.ANCHORMODE_FREE
        BuffBars._layoutRunning = true
        BuffBarCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 50, 60)
        BuffBars._layoutRunning = nil
        assert.is_nil(cfg.editModePositions.Modern)
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
                anchorMode = ECM.Constants.ANCHORMODE_CHAIN,
                showIcon = false,
                showSpellName = true,
                showDuration = true,
            }
        end
        function BuffBars:ShouldShow()
            return true
        end
        function BuffBars:ThrottledUpdateLayout(reason)
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

        assert.same({ "SetPoint:hook" }, reasons)
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
                anchorMode = ECM.Constants.ANCHORMODE_CHAIN,
                showIcon = false,
                showSpellName = true,
                showDuration = true,
            }
        end
        function BuffBars:ShouldShow()
            return true
        end
        function BuffBars:ThrottledUpdateLayout(reason)
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

        assert.same({ "OnShow:child", "OnHide:child" }, reasons)
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

        BuffBars:OnInitialize()
        BuffBars:OnEnable()

        assert.are.equal(1, addMixinCalls)
        assert.are.equal(1, registerFrameCalls)
        assert.are.equal(1, #timerCallbacks)

        timerCallbacks[1]()

        assert.same({ "ModuleInit" }, reasons)
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
        ECM.SpellColors.ClearDiscoveredKeys = function()
            cleared = cleared + 1
        end
        ECM.SpellColors.DiscoverBar = function(frame)
            discovered[#discovered + 1] = frame
        end
        ECM.SpellColors.GetColorForBar = function()
            return { r = 0.4, g = 0.5, b = 0.6, a = 1 }
        end
        ECM.SpellColors.GetDefaultColor = function()
            return { r = 1, g = 1, b = 1, a = 1 }
        end
        ECM.ColorUtil = {
            ColorToHex = function()
                return "abcdef"
            end,
        }
        ECM.ToString = tostring
        ECM.GetTexture = function()
            return "Interface\\TargetingFrame\\UI-StatusBar"
        end
        ECM.ApplyFont = function() end
        ECM.DebugAssert = function(condition)
            assert.is_true(condition)
        end
        ECM.FrameUtil.GetBarBackground = function()
            return nil
        end
        ECM.FrameUtil.GetIconTexture = function()
            return nil
        end
        ECM.FrameUtil.GetIconOverlay = function()
            return nil
        end
        ECM.FrameUtil.LazySetHeight = function(frame, value)
            frame.__height = value
        end
        ECM.FrameUtil.LazySetWidth = function(frame, value)
            frame.__width = value
        end
        ECM.FrameUtil.LazySetStatusBarTexture = function(bar, texture)
            appliedTextures[#appliedTextures + 1] = { bar = bar, texture = texture }
        end
        ECM.FrameUtil.LazySetStatusBarColor = function(bar, r, g, b, a)
            appliedColors[#appliedColors + 1] = { bar = bar, color = { r, g, b, a } }
        end
        ECM.FrameUtil.LazySetAnchors = function(frame, anchors)
            frame.__ecmAnchorCache = anchors
            frame.__anchors = anchors
        end
        ECM.FrameUtil.LazySetAlpha = function(frame, value)
            frame.__alpha = value
        end

        local function makeChild(name, shown, layoutIndex)
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
            }
            child.Icon = makeHookableFrame({ shown = false, width = 20, height = 20 })
            child.Icon.SetShown = function(self, value)
                self.__shown = value
            end
            child.Icon.Applications = {}
            child.cooldownInfo = { spellID = layoutIndex }
            child.cooldownID = 1000 + layoutIndex
            child.iconTextureFileID = 2000 + layoutIndex
            return child
        end

        local first = makeChild("First", true, 2)
        local second = makeChild("Second", false, 1)
        local ignored = makeChild("Ignored", true, 99)
        ignored.ignoreInLayout = true
        function BuffBarCooldownViewer:GetChildren()
            return first, ignored, second
        end
        function BuffBars:GetGlobalConfig()
            return { texture = "Solid", barHeight = 18, barWidth = 250 }
        end
        function BuffBars:GetModuleConfig()
            return {
                anchorMode = ECM.Constants.ANCHORMODE_CHAIN,
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
        assert.is_true(first.__ecmHooked)
        assert.is_true(second.__ecmHooked)
        assert.are.equal(2, #appliedTextures)
        assert.are.equal(2, #appliedColors)
        assert.is_true(BuffBarCooldownViewer:IsShown())
    end)
end)
