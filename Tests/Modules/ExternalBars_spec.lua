-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("ExternalBars real source", function()
    local originalGlobals
    local ExternalBars
    local ns
    local profile
    local viewer
    local fakeTime
    local afterCallbacks
    local retryTimers
    local durationTickers
    local requestLayoutReasons
    local registerFrameCalls
    local unregisterFrameCalls
    local auraDataByInstanceID
    local colorLookupScopes
    local discoveredScopes
    local spellColorStores
    local runtimeAlpha

    local makeFrame = TestHelpers.makeFrame
    local makeHookableFrame = TestHelpers.makeHookableFrame
    local makeTexture = TestHelpers.makeTexture
    local makeStatusBar = TestHelpers.makeStatusBar

    local function makeFontString()
        local fontString = makeFrame({ shown = true })
        fontString.__text = nil

        function fontString:SetText(text)
            self.__text = text
        end

        function fontString:GetText()
            return self.__text
        end

        function fontString:SetWordWrap() end
        function fontString:SetJustifyH() end
        function fontString:SetJustifyV() end
        function fontString:SetFontObject() end
        function fontString:SetShown(shown)
            if shown then
                self:Show()
            else
                self:Hide()
            end
        end

        return fontString
    end

    local function makeTextureRegion()
        local texture = makeTexture()
        local originalSetTexture = texture.SetTexture
        texture.__shown = true
        texture.__alpha = 1

        function texture:SetTexture(value)
            originalSetTexture(self, value)
            if type(value) == "number" then
                self.__textureFileID = value
            end
        end

        function texture:SetShown(shown)
            self.__shown = not not shown
        end

        function texture:Show()
            self.__shown = true
        end

        function texture:Hide()
            self.__shown = false
        end

        function texture:IsShown()
            return self.__shown
        end

        function texture:SetAllPoints() end
        function texture:ClearAllPoints() end
        function texture:SetPoint() end
        function texture:SetTexCoord(...)
            self.__texCoord = { ... }
        end
        function texture:SetAtlas(atlas)
            self.__atlas = atlas
        end
        function texture:SetParent(parent)
            self.__parent = parent
        end
        function texture:SetDrawLayer(layer, subLayer)
            self.__drawLayer = { layer, subLayer }
        end
        function texture:SetAlpha(alpha)
            self.__alpha = alpha
        end
        function texture:GetAlpha()
            return self.__alpha
        end

        return texture
    end

    local function addFrameFeatures(frame, parent)
        frame.__frameLevel = frame.__frameLevel
            or (parent and parent.GetFrameLevel and parent:GetFrameLevel() + 1)
            or 0
        frame.__mouseEnabled = frame.__mouseEnabled ~= false

        if not frame.SetFrameLevel then
            function frame:SetFrameLevel(level)
                self.__frameLevel = level
            end
        end

        if not frame.GetFrameLevel then
            function frame:GetFrameLevel()
                return self.__frameLevel or 0
            end
        end

        if not frame.SetShown then
            function frame:SetShown(shown)
                if shown then
                    self:Show()
                else
                    self:Hide()
                end
            end
        end

        if not frame.EnableMouse then
            function frame:EnableMouse(enabled)
                self.__mouseEnabled = not not enabled
            end
        end

        if not frame.IsMouseEnabled then
            function frame:IsMouseEnabled()
                return self.__mouseEnabled
            end
        end

        function frame:SetParent(newParent)
            self.__parent = newParent
        end

        function frame:CreateTexture()
            local texture = makeTextureRegion()
            self.__textures = self.__textures or {}
            self.__textures[#self.__textures + 1] = texture
            return texture
        end

        function frame:CreateFontString()
            local fontString = makeFontString()
            self.__fontStrings = self.__fontStrings or {}
            self.__fontStrings[#self.__fontStrings + 1] = fontString
            return fontString
        end

        return frame
    end

    local function makeStatusBarFrame(parent)
        local bar = addFrameFeatures(makeStatusBar(), parent)

        function bar:SetMinMaxValues(minValue, maxValue)
            self.__minValue = minValue
            self.__maxValue = maxValue
        end

        function bar:SetValue(value)
            self.__value = value
        end

        function bar:GetValue()
            return self.__value
        end

        return bar
    end

    local function makeCooldownFrame(parent)
        local cooldown = addFrameFeatures(makeFrame({ shown = true }), parent)
        cooldown.__setCooldownDurationCalls = {}
        cooldown.__clearCalls = 0

        function cooldown:SetDrawSwipe(value)
            self.__drawSwipe = value
        end

        function cooldown:SetDrawEdge(value)
            self.__drawEdge = value
        end

        function cooldown:SetDrawBling(value)
            self.__drawBling = value
        end

        function cooldown:SetReverse(value)
            self.__reverse = value
        end

        function cooldown:SetHideCountdownNumbers(value)
            self.__hideCountdownNumbers = value
        end

        function cooldown:SetSwipeColor(r, g, b, a)
            self.__swipeColor = { r, g, b, a }
        end

        function cooldown:SetCooldownDuration(duration, timeMod)
            self.__lastDuration = duration
            self.__lastTimeMod = timeMod
            self.__setCooldownDurationCalls[#self.__setCooldownDurationCalls + 1] = {
                duration = duration,
                timeMod = timeMod,
            }
        end

        function cooldown:Clear()
            self.__clearCalls = self.__clearCalls + 1
            self.__lastDuration = nil
            self.__lastTimeMod = nil
        end

        return cooldown
    end

    local function createFrameStub(frameType, _, parent)
        if frameType == "StatusBar" then
            return makeStatusBarFrame(parent)
        end

        if frameType == "Cooldown" then
            return makeCooldownFrame(parent)
        end

        return addFrameFeatures(makeFrame({ shown = true }), parent)
    end

    local function setViewerAuras(auraDefs)
        viewer.auraInfo = {}
        viewer.auraFrames = {}
        auraDataByInstanceID = {}

        for index, aura in ipairs(auraDefs or {}) do
            viewer.auraInfo[index] = {
                auraInstanceID = aura.auraInstanceID,
                texture = aura.texture,
                duration = aura.duration,
                expirationTime = aura.expirationTime,
                timeMod = aura.timeMod,
            }
            viewer.auraFrames[index] = {
                auraInstanceID = aura.auraInstanceID,
                icon = aura.texture,
            }
            auraDataByInstanceID[aura.auraInstanceID] = aura.auraData
        end
    end

    local function ensureModuleFrame()
        if not ExternalBars.InnerFrame then
            ExternalBars:EnsureFrame()
        end
    end

    local function syncAndLayout(reason)
        ensureModuleFrame()
        ExternalBars:OnExternalAurasUpdated()
        return ExternalBars:UpdateLayout(reason or "test")
    end

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "UIParent",
            "ExternalDefensivesFrame",
            "C_UnitAuras",
            "hooksecurefunc",
            "InCombatLockdown",
            "issecretvalue",
            "canaccesstable",
            "C_Timer",
            "GetTime",
            "CreateFrame",
            "LibStub",
            "SecondsToTimeAbbrev",
            "wipe",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        fakeTime = 100
        afterCallbacks = {}
        retryTimers = {}
        durationTickers = {}
        requestLayoutReasons = {}
        registerFrameCalls = 0
        unregisterFrameCalls = 0
        auraDataByInstanceID = {}
        colorLookupScopes = {}
        discoveredScopes = {}
        spellColorStores = {}
        runtimeAlpha = 1

        ns = {
            Log = function() end,
            DebugAssert = function() end,
            IsDebugEnabled = function()
                return false
            end,
            ToString = tostring,
            Runtime = {
                RegisterFrame = function()
                    registerFrameCalls = registerFrameCalls + 1
                end,
                UnregisterFrame = function()
                    unregisterFrameCalls = unregisterFrameCalls + 1
                end,
                GetDesiredAlpha = function()
                    return runtimeAlpha
                end,
                RequestLayout = function(reason)
                    requestLayoutReasons[#requestLayoutReasons + 1] = reason
                end,
            },
            FrameUtil = {
                GetTexture = function()
                    return "Interface\\TargetingFrame\\UI-StatusBar"
                end,
                ApplyFont = function() end,
                GetBarBackground = function(bar)
                    return bar and bar.__textures and bar.__textures[1] or nil
                end,
                GetIconTexture = function(frame)
                    return frame and frame._iconTexture or nil
                end,
                GetIconOverlay = function()
                    return nil
                end,
                GetIconTextureFileID = function(frame)
                    local iconTexture = frame and frame._iconTexture
                    return iconTexture and iconTexture:GetTextureFileID() or nil
                end,
                LazySetHeight = function(frame, value)
                    frame:SetHeight(value)
                end,
                LazySetWidth = function(frame, value)
                    frame:SetWidth(value)
                end,
                LazySetAnchors = function(frame, anchors)
                    frame.__ecmAnchorCache = anchors
                    frame.__anchors = anchors
                end,
                LazySetStatusBarTexture = function(bar, texture)
                    bar:SetStatusBarTexture(texture)
                end,
                LazySetStatusBarColor = function(bar, r, g, b, a)
                    bar:SetStatusBarColor(r, g, b, a)
                end,
                LazySetAlpha = function(frame, alpha)
                    frame:SetAlpha(alpha)
                end,
            },
            SpellColors = {
                Get = function(scope)
                    local storeKey = scope or false
                    local store = spellColorStores[storeKey]
                    if store then
                        return store
                    end

                    store = {
                        GetColorForBar = function()
                            colorLookupScopes[#colorLookupScopes + 1] = scope
                            return nil
                        end,
                        GetDefaultColor = function()
                            assert.are.equal(ns.Constants.SCOPE_EXTERNALBARS, scope)
                            return { r = 0.40, g = 0.78, b = 0.95, a = 1 }
                        end,
                        DiscoverBar = function()
                            discoveredScopes[#discoveredScopes + 1] = scope
                        end,
                        ClearDiscoveredKeys = function() end,
                    }
                    spellColorStores[storeKey] = store
                    return store
                end,
                MakeKey = function(name, spellID, cooldownID, textureFileID)
                    if not name and not spellID and not cooldownID and not textureFileID then
                        return nil
                    end

                    return {
                        spellName = name,
                        spellID = spellID,
                        cooldownID = cooldownID,
                        textureFileID = textureFileID,
                    }
                end,
            },
        }

        TestHelpers.LoadChunk("Constants.lua", "Unable to load Constants.lua")(nil, ns)
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")(nil, ns)

        profile = {
            global = {
                barHeight = 18,
                barWidth = 240,
                texture = "Solid",
                barBgColor = { r = 0.1, g = 0.1, b = 0.1, a = 0.8 },
                offsetY = 0,
                moduleSpacing = 2,
                detachedModuleSpacing = 2,
                moduleGrowDirection = ns.Constants.GROW_DIRECTION_DOWN,
                detachedGrowDirection = ns.Constants.GROW_DIRECTION_DOWN,
            },
            externalBars = {
                enabled = true,
                hideOriginalIcons = false,
                showIcon = true,
                showSpellName = true,
                showDuration = true,
                anchorMode = ns.Constants.ANCHORMODE_CHAIN,
                height = 0,
                verticalSpacing = 0,
            },
        }

        ns.GetGlobalConfig = function()
            return profile.global
        end

        ns.Addon = {
            db = { profile = profile },
            GetECMModule = function(addon, name)
                return rawget(addon, name)
            end,
            NewModule = function(addon, name)
                local module = {
                    Name = name,
                    _enabled = true,
                }

                function module:IsEnabled()
                    return self._enabled
                end

                function module:RegisterEvent(eventName)
                    self._registeredEvents = self._registeredEvents or {}
                    self._registeredEvents[eventName] = true
                end

                function module:UnregisterAllEvents()
                    self._unregisteredAllEvents = true
                end

                addon[name] = module
                return module
            end,
        }

        _G.GetTime = function()
            return fakeTime
        end
        _G.InCombatLockdown = function()
            return false
        end
        _G.issecretvalue = function()
            return false
        end
        _G.canaccesstable = function(value)
            return type(value) == "table"
        end
        _G.C_UnitAuras = {
            GetAuraDataByAuraInstanceID = function(_, auraInstanceID)
                return auraDataByInstanceID[auraInstanceID]
            end,
        }
        _G.wipe = function(tbl)
            for key in pairs(tbl) do
                tbl[key] = nil
            end
        end
        _G.SecondsToTimeAbbrev = nil
        _G.C_Timer = {
            After = function(_, callback)
                afterCallbacks[#afterCallbacks + 1] = callback
            end,
            NewTimer = function(_, callback)
                local timer = { cancelled = false, callback = callback }

                function timer:Cancel()
                    self.cancelled = true
                end

                retryTimers[#retryTimers + 1] = timer
                return timer
            end,
            NewTicker = function(_, callback)
                local ticker = { cancelled = false, callback = callback }

                function ticker:Cancel()
                    self.cancelled = true
                end

                durationTickers[#durationTickers + 1] = ticker
                return ticker
            end,
        }

        _G.UIParent = addFrameFeatures(makeFrame({ name = "UIParent", shown = true, width = 1920, height = 1080 }))
        _G.CreateFrame = function(frameType, name, parent)
            return createFrameStub(frameType, name, parent)
        end
        _G.hooksecurefunc = function(object, methodName, callback)
            local original = object[methodName]
            object[methodName] = function(self, ...)
                if original then
                    original(self, ...)
                end
                callback(self, ...)
            end
        end

        viewer = addFrameFeatures(makeHookableFrame({ name = "ExternalDefensivesFrame", shown = true }))
        viewer.auraInfo = {}
        viewer.auraFrames = {}

        function viewer:UpdateAuras()
            self._updateAuraCalls = (self._updateAuraCalls or 0) + 1
        end

        _G.ExternalDefensivesFrame = viewer

        TestHelpers.SetupLibStub()
        TestHelpers.SetupLibEditModeStub()
        TestHelpers.LoadChunk("BarMixin.lua", "Unable to load BarMixin.lua")(nil, ns)
        TestHelpers.LoadChunk("BarStyle.lua", "Unable to load BarStyle.lua")(nil, ns)
        TestHelpers.LoadChunk("Modules/ExternalBars.lua", "Unable to load Modules/ExternalBars.lua")(nil, ns)

        ExternalBars = assert(ns.Addon.ExternalBars, "ExternalBars module did not initialize")
        ExternalBars:OnInitialize()
    end)

    it("creates bars from external aura updates and configures cooldown duration", function()
        setViewerAuras({
            {
                auraInstanceID = 11,
                texture = 5011,
                duration = 12,
                expirationTime = 112,
                timeMod = 1.5,
                auraData = { name = "Ironbark", spellId = 102342 },
            },
        })

        assert.is_true(syncAndLayout("test-normal"))

        local bar = assert(ExternalBars._barPool[1])
        assert.is_true(bar:IsShown())
        assert.are.equal(5011, bar._iconTexture:GetTexture())
        assert.are.equal("Ironbark", bar.Bar.Name:GetText())
        assert.are.equal("12", bar.Bar.Duration:GetText())
        assert.is_true(bar.Bar.Duration:IsShown())
        assert.same({ duration = 12, timeMod = 1.5 }, bar.Cooldown.__setCooldownDurationCalls[1])
        assert.same({ "ExternalBars:UpdateAuras" }, requestLayoutReasons)
        assert.same({ ns.Constants.SCOPE_EXTERNALBARS }, colorLookupScopes)
        assert.same({ ns.Constants.SCOPE_EXTERNALBARS }, discoveredScopes)
        assert.same({ 0.40, 0.78, 0.95, 1.0 }, { bar.Bar:GetStatusBarColor() })
        assert.are.equal(1, #durationTickers)
    end)

    it("hides duration text but still configures cooldown and schedules the all-secret color retry path", function()
        _G.issecretvalue = function()
            return true
        end

        setViewerAuras({
            {
                auraInstanceID = 22,
                texture = 6022,
                duration = "secret-duration",
                expirationTime = "secret-expiration",
                timeMod = "secret-mod",
                auraData = { name = "secret-name", spellId = 987654 },
            },
        })

        assert.is_true(syncAndLayout("test-secret"))

        local bar = assert(ExternalBars._barPool[1])
        assert.is_true(bar:IsShown())
        assert.is_false(bar.Bar.Duration:IsShown())
        assert.is_nil(bar.Bar.Duration:GetText())
        assert.same({ duration = "secret-duration", timeMod = "secret-mod" }, bar.Cooldown.__setCooldownDurationCalls[1])
        assert.are.equal(1, #retryTimers)
        assert.same({ true, "secrets" }, { ExternalBars:IsEditLocked() })
        assert.are.equal(0, #durationTickers)
    end)

    it("reuses pooled bars and hides excess bars when aura count shrinks", function()
        setViewerAuras({
            {
                auraInstanceID = 11,
                texture = 5011,
                duration = 12,
                expirationTime = 112,
                timeMod = 1,
                auraData = { name = "Ironbark", spellId = 102342 },
            },
            {
                auraInstanceID = 22,
                texture = 5022,
                duration = 10,
                expirationTime = 110,
                timeMod = 1,
                auraData = { name = "Pain Suppression", spellId = 33206 },
            },
            {
                auraInstanceID = 33,
                texture = 5033,
                duration = 8,
                expirationTime = 108,
                timeMod = 1,
                auraData = { name = "Blessing of Sacrifice", spellId = 6940 },
            },
        })

        assert.is_true(syncAndLayout("three-bars"))

        local secondBar = assert(ExternalBars._barPool[2])
        local thirdBar = assert(ExternalBars._barPool[3])

        setViewerAuras({
            {
                auraInstanceID = 11,
                texture = 5011,
                duration = 12,
                expirationTime = 112,
                timeMod = 1,
                auraData = { name = "Ironbark", spellId = 102342 },
            },
        })

        assert.is_true(syncAndLayout("one-bar"))

        assert.are.equal(secondBar, ExternalBars._barPool[2])
        assert.are.equal(thirdBar, ExternalBars._barPool[3])
        assert.is_false(secondBar:IsShown())
        assert.is_false(thirdBar:IsShown())
        assert.are.equal(3, #ExternalBars._barPool)
    end)

    it("hides the original icons on enable and restores them on disable", function()
        profile.externalBars.hideOriginalIcons = true

        ExternalBars:OnEnable()

        assert.are.equal(1, registerFrameCalls)
        assert.are.equal(1, #afterCallbacks)

        afterCallbacks[1]()

        assert.are.equal(0, viewer:GetAlpha())
        assert.is_false(viewer:IsMouseEnabled())

        requestLayoutReasons = {}

        ExternalBars:OnDisable()

        assert.are.equal(1, unregisterFrameCalls)
        assert.are.equal(1, viewer:GetAlpha())
        assert.is_true(viewer:IsMouseEnabled())
        assert.same({ "ExternalBars:OriginalIconsShown" }, requestLayoutReasons)
    end)

    it("restores the viewer alpha when showing the original icons again", function()
        local setAlphaCalls = {}

        profile.externalBars.hideOriginalIcons = true
        ExternalBars:_RefreshOriginalIconsState()
        requestLayoutReasons = {}
        runtimeAlpha = 0.35

        local originalSetAlpha = viewer.SetAlpha
        function viewer:SetAlpha(alpha)
            setAlphaCalls[#setAlphaCalls + 1] = alpha
            originalSetAlpha(self, alpha)
        end

        profile.externalBars.hideOriginalIcons = false
        ExternalBars:_RefreshOriginalIconsState()

        assert.same({ 0.35 }, setAlphaCalls)
        assert.are.equal(0.35, viewer:GetAlpha())
        assert.is_true(viewer:IsMouseEnabled())
        assert.same({ "ExternalBars:OriginalIconsShown" }, requestLayoutReasons)
    end)

    it("keeps viewer mouse disabled when the runtime fade alpha is zero", function()
        profile.externalBars.hideOriginalIcons = true
        ExternalBars:_RefreshOriginalIconsState()
        requestLayoutReasons = {}
        runtimeAlpha = 0

        profile.externalBars.hideOriginalIcons = false
        ExternalBars:_RefreshOriginalIconsState()

        assert.are.equal(0, viewer:GetAlpha())
        assert.is_false(viewer:IsMouseEnabled())
        assert.same({ "ExternalBars:OriginalIconsShown" }, requestLayoutReasons)
    end)

    it("computes container height from bar count, height, and vertical spacing", function()
        profile.externalBars.height = 20
        profile.externalBars.verticalSpacing = 3

        setViewerAuras({
            {
                auraInstanceID = 11,
                texture = 5011,
                duration = 12,
                expirationTime = 112,
                timeMod = 1,
                auraData = { name = "Ironbark", spellId = 102342 },
            },
            {
                auraInstanceID = 22,
                texture = 5022,
                duration = 10,
                expirationTime = 110,
                timeMod = 1,
                auraData = { name = "Pain Suppression", spellId = 33206 },
            },
            {
                auraInstanceID = 33,
                texture = 5033,
                duration = 8,
                expirationTime = 108,
                timeMod = 1,
                auraData = { name = "Blessing of Sacrifice", spellId = 6940 },
            },
        })

        assert.is_true(syncAndLayout("height"))
        assert.are.equal(66, ExternalBars.InnerFrame:GetHeight())
    end)
end)
