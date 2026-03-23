-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("ECM.Runtime layout system", function()
    local originalGlobals
    local fakeTime
    local isMounted
    local inCombat
    local cvarEnabled
    local printedMessages
    local fakeAddon
    local createdFrames
    local createdTickers
    local makeFrame = TestHelpers.makeFrame

    local function makeModule(name)
        local innerFrame = makeFrame({ name = "ECM" .. name, shown = true })
        innerFrame.Background = makeFrame()
        innerFrame.Border = makeFrame({ shown = false })

        local mod = {
            Name = name,
            InnerFrame = innerFrame,
            IsHidden = false,
            _lastUpdate = 0,
            _configKey = ECM.Constants.ConfigKeyForModule(name),
        }

        function mod:SetHidden(hide)
            self.IsHidden = hide
        end
        function mod:ShouldShow()
            return not self.IsHidden
        end
        function mod:IsEnabled()
            return true
        end
        function mod:GetGlobalConfig()
            local p = _G._testDB and _G._testDB.profile
            return p and p.global
        end
        function mod:GetModuleConfig()
            local p = _G._testDB and _G._testDB.profile
            return p and p[self._configKey]
        end
        function mod:CalculateLayoutParams()
            local gc = self:GetGlobalConfig()
            local mc = self:GetModuleConfig()
            return {
                mode = mc.anchorMode,
                anchor = _G.UIParent,
                isFirst = true,
                anchorPoint = "TOPLEFT",
                anchorRelativePoint = "BOTTOMLEFT",
                offsetX = 0,
                offsetY = -((gc and gc.offsetY) or 0),
                height = (mc and mc.height) or (gc and gc.barHeight),
                width = mc.anchorMode == ECM.Constants.ANCHORMODE_FREE and ((mc and mc.width) or (gc and gc.barWidth))
                    or nil,
            }
        end
        function mod:GetNextChainAnchor()
            return _G.UIParent, true
        end
        function mod:UpdateLayout(why)
            if not self:ShouldShow() then
                self.InnerFrame:Hide()
                return false
            end
            if not self.InnerFrame:IsShown() then
                self.InnerFrame:Show()
            end
            local params = self:CalculateLayoutParams()
            if params.height then
                ECM.FrameUtil.LazySetHeight(self.InnerFrame, params.height)
            end
            if params.width then
                ECM.FrameUtil.LazySetWidth(self.InnerFrame, params.width)
            end
            self:ThrottledRefresh("UpdateLayout(" .. (why or "") .. ")")
            return true
        end
        function mod:Refresh()
            return true
        end
        function mod:ThrottledRefresh(why)
            local gc = self:GetGlobalConfig()
            local freq = (gc and gc.updateFrequency) or ECM.Constants.DEFAULT_REFRESH_FREQUENCY
            if GetTime() - (self._lastUpdate or 0) < freq then
                return false
            end
            self:Refresh(why)
            self._lastUpdate = GetTime()
            return true
        end
        function mod:ThrottledUpdateLayout(reason)
            if self:IsEnabled() then
                self:UpdateLayout(reason)
            end
        end

        return mod
    end

    local function makeRegisteredModule(name)
        local mod = makeModule(name or "PowerBar")
        ECM.Runtime.RegisterFrame(mod)
        return mod
    end

    local function makeFadeConfig(opacity)
        return {
            enabled = true,
            opacity = opacity,
            exceptIfTargetCanBeAttacked = false,
            exceptIfTargetCanBeHelped = false,
            exceptInInstance = false,
        }
    end

    local CAPTURED_GLOBALS = {
        "ECM",
        "LibStub",
        "C_Timer",
        "C_AddOns",
        "C_CVar",
        "GetTime",
        "UIParent",
        "CreateFrame",
        "IsMounted",
        "UnitInVehicle",
        "UnitOnTaxi",
        "IsResting",
        "InCombatLockdown",
        "UnitExists",
        "UnitIsDead",
        "UnitCanAttack",
        "UnitCanAssist",
        "IsInInstance",
        "issecretvalue",
        "issecrettable",
        "Enum",
        "print",
        "StaticPopupDialogs",
        "StaticPopup_Show",
        "YES",
        "NO",
        "DevTool",
        "tinsert",
        "strtrim",
        "ReloadUI",
        "AddonCompartmentFrame",
        "CLOSE",
        "CANCEL",
        "OKAY",
        "CooldownViewerSettings",
        "SlashCmdList",
        "hash_SlashCmdList",
    }

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals(CAPTURED_GLOBALS)
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        fakeTime = 100
        isMounted = false
        inCombat = false
        cvarEnabled = true
        printedMessages = {}
        createdFrames = {}
        createdTickers = {}

        _G.GetTime = function()
            return fakeTime
        end
        _G.IsMounted = function()
            return isMounted
        end
        _G.UnitInVehicle = function()
            return false
        end
        _G.UnitOnTaxi = function()
            return false
        end
        _G.IsResting = function()
            return false
        end
        _G.InCombatLockdown = function()
            return inCombat
        end
        _G.UnitExists = function()
            return false
        end
        _G.UnitIsDead = function()
            return false
        end
        _G.UnitCanAttack = function()
            return false
        end
        _G.UnitCanAssist = function()
            return false
        end
        _G.IsInInstance = function()
            return false
        end
        _G.issecretvalue = function()
            return false
        end
        _G.issecrettable = function()
            return false
        end
        _G.tinsert = table.insert
        _G.strtrim = function(s)
            return (s:gsub("^%s+", ""):gsub("%s+$", ""))
        end
        _G.print = function(message)
            printedMessages[#printedMessages + 1] = message
        end
        _G.StaticPopupDialogs = {}
        _G.StaticPopup_Show = function() end
        _G.YES = "Yes"
        _G.NO = "No"
        _G.DevTool = nil
        _G.ReloadUI = function() end
        _G.AddonCompartmentFrame = nil
        _G.CLOSE = "Close"
        _G.CANCEL = "Cancel"
        _G.OKAY = "Okay"
        _G.CooldownViewerSettings = nil
        _G.EssentialCooldownViewer = nil
        _G.UtilityCooldownViewer = nil
        _G.BuffIconCooldownViewer = nil
        _G.BuffBarCooldownViewer = nil

        _G.C_CVar = {
            GetCVarBool = function(name)
                return name == "cooldownViewerEnabled" and cvarEnabled
            end,
            SetCVar = function() end,
        }
        _G.C_AddOns = {
            GetAddOnMetadata = function(_, key)
                if key == "Version" then
                    return "v0.6.1"
                end
            end,
        }
        _G.C_Timer = {
            After = function(_, callback)
                callback()
            end,
            NewTicker = function(_, callback)
                local ticker = {
                    cancelled = false,
                    callback = callback,
                }

                function ticker:Cancel()
                    self.cancelled = true
                end

                createdTickers[#createdTickers + 1] = ticker
                return ticker
            end,
        }
        _G.UIParent = makeFrame({ name = "UIParent", width = 1000, height = 800 })
        _G.CreateFrame = function()
            local frame = makeFrame()
            createdFrames[#createdFrames + 1] = frame
            return frame
        end

        fakeAddon = {
            RegisterChatCommand = function() end,
            RegisterEvent = function() end,
            SetDefaultModuleLibraries = function() end,
            UnregisterEvent = function() end,
            EnableModule = function() end,
            DisableModule = function() end,
            GetModule = function() end,
        }
        TestHelpers.SetupLibStub()
        _G.SlashCmdList = {}
        _G.hash_SlashCmdList = {}
        TestHelpers.LoadChunk("Libs/LibEvent/LibEvent.lua", "Unable to load LibEvent.lua")()
        local aceAddon = _G.LibStub:NewLibrary("AceAddon-3.0", 1)
        aceAddon.NewAddon = function(_, n, ...)
            fakeAddon.name = n
            for _, libraryName in ipairs({ ... }) do
                local library = _G.LibStub(libraryName)
                if library and library.Embed then
                    library:Embed(fakeAddon)
                end
            end
            return fakeAddon
        end
        TestHelpers.SetupLibEQOLEditModeStub()
        TestHelpers.LoadChunk("Libs/LibConsole/LibConsole.lua", "Unable to load LibConsole.lua")()

        TestHelpers.LoadChunk("Tests/stubs/Enums.lua", "Unable to load Enums.lua")()
        _G.ECM = {}
        _G.ECM.ColorUtil = {
            Sparkle = function(text)
                return text
            end,
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
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")()
        TestHelpers.LoadChunk("ECM_Defaults.lua", "Unable to load ECM_Defaults.lua")()
        _G.ECM.Migration = {
            PrepareDatabase = function() end,
            Run = function() end,
            FlushLog = function() end,
            PrintLog = function() end,
        }
        _G.ECM.Runtime = { ScheduleLayoutUpdate = function() end }
        TestHelpers.LoadChunk("Helpers/FrameUtil.lua", "Unable to load Helpers/FrameUtil.lua")()
        TestHelpers.LoadChunk("Helpers/ModuleMixin.lua", "Unable to load Helpers/ModuleMixin.lua")(
            nil,
            { Addon = fakeAddon }
        )
        TestHelpers.LoadChunk("Helpers/FrameMixin.lua", "Unable to load Helpers/FrameMixin.lua")(
            nil,
            { Addon = fakeAddon }
        )

        local profile = TestHelpers.deepClone(ECM.defaults.profile)
        _G._testDB = { profile = profile, RegisterCallback = function() end }
        fakeAddon.db = _G._testDB

        TestHelpers.LoadChunk("ECM.lua", "Unable to load ECM.lua")("EnhancedCooldownManager", { Addon = fakeAddon })
        TestHelpers.LoadChunk("ECM_Runtime.lua", "Unable to load ECM_Runtime.lua")(
            "EnhancedCooldownManager",
            { Addon = fakeAddon }
        )
    end)

    describe("automatic layout enforcement", function()
        it("hides registered module frames when mounted", function()
            local mod = makeRegisteredModule()
            isMounted = true

            ECM.Runtime.ScheduleLayoutUpdate(0, "mount")

            assert.is_true(mod.IsHidden)
            assert.is_false(mod.InnerFrame:IsShown())
        end)

        it("applies fade alpha when out of combat", function()
            local mod = makeRegisteredModule()
            _G._testDB.profile.global.outOfCombatFade = makeFadeConfig(50)

            ECM.Runtime.ScheduleLayoutUpdate(0, "fade")

            assert.are.equal(0.5, mod.InnerFrame:GetAlpha())
        end)

        it("re-shows module frames after dismounting", function()
            local mod = makeRegisteredModule()

            isMounted = true
            ECM.Runtime.ScheduleLayoutUpdate(0, "mount")
            assert.is_false(mod.InnerFrame:IsShown())

            fakeTime = fakeTime + 1
            isMounted = false
            ECM.Runtime.ScheduleLayoutUpdate(0, "dismount")
            assert.is_true(mod.InnerFrame:IsShown())
        end)

        it("restores full alpha when combat fade is disabled", function()
            local mod = makeRegisteredModule()
            _G._testDB.profile.global.outOfCombatFade = makeFadeConfig(30)
            ECM.Runtime.ScheduleLayoutUpdate(0, "fade-on")
            assert.are.equal(0.3, mod.InnerFrame:GetAlpha())

            fakeTime = fakeTime + 1
            _G._testDB.profile.global.outOfCombatFade.enabled = false
            ECM.Runtime.ScheduleLayoutUpdate(0, "fade-off")
            assert.are.equal(1, mod.InnerFrame:GetAlpha())
        end)

        it("hides all registered modules when cvar is disabled", function()
            local mod1 = makeRegisteredModule("PowerBar")
            local mod2 = makeRegisteredModule("ResourceBar")

            cvarEnabled = false
            ECM.Runtime.ScheduleLayoutUpdate(0, "cvar-off")

            assert.is_true(mod1.IsHidden)
            assert.is_true(mod2.IsHidden)
        end)

        it("re-hides a module frame that was externally shown while hidden", function()
            local mod = makeRegisteredModule()
            isMounted = true
            ECM.Runtime.ScheduleLayoutUpdate(0, "mount")

            mod.InnerFrame:Show()

            fakeTime = fakeTime + 1
            ECM.Runtime.ScheduleLayoutUpdate(0, "re-enforce")
            assert.is_false(mod.InnerFrame:IsShown())
        end)

        it("forces a layout pass when layout preview is toggled on", function()
            local mod = makeRegisteredModule()
            local reasons = {}

            mod.ThrottledUpdateLayout = function(_, reason)
                reasons[#reasons + 1] = reason
            end

            ECM.Runtime.SetLayoutPreview(true)

            assert.same({ "LayoutPreviewOn" }, reasons)
        end)
    end)

    describe("synchronous layout", function()
        it("UpdateLayoutImmediately runs layout without C_Timer", function()
            local mod = makeRegisteredModule()
            local reasons = {}
            mod.ThrottledUpdateLayout = function(_, reason)
                reasons[#reasons + 1] = reason
            end

            local timerCalled = false
            local origAfter = _G.C_Timer.After
            _G.C_Timer.After = function(_, cb)
                timerCalled = true
                cb()
            end

            ECM.Runtime.UpdateLayoutImmediately("SyncTest")

            assert.same({ "SyncTest" }, reasons)
            assert.is_false(timerCalled)
            _G.C_Timer.After = origAfter
        end)

        it("UpdateLayoutImmediately clears pending flag so ScheduleLayoutUpdate is not blocked", function()
            local mod = makeRegisteredModule()
            local reasons = {}
            mod.ThrottledUpdateLayout = function(_, reason)
                reasons[#reasons + 1] = reason
            end

            -- Schedule a deferred update (fires immediately in test due to stub)
            ECM.Runtime.ScheduleLayoutUpdate(0, "Deferred")
            -- Now do synchronous
            ECM.Runtime.UpdateLayoutImmediately("Sync")
            -- Schedule again — should not be blocked
            fakeTime = fakeTime + 1
            ECM.Runtime.ScheduleLayoutUpdate(0, "AfterSync")

            assert.same({ "Deferred", "Sync", "AfterSync" }, reasons)
        end)
    end)

    describe("detached anchor layout handling", function()
        it("normalizes legacy center-saved detached positions to a stable top anchor", function()
            local mod = makeRegisteredModule("PowerBar")
            local lib = LibStub("LibEQOLEditMode-1.0")
            local originalLazySetAnchors = ECM.FrameUtil.LazySetAnchors

            _G._testDB.profile.powerBar.anchorMode = ECM.Constants.ANCHORMODE_DETACHED
            _G._testDB.profile.global.detachedGrowDirection = ECM.Constants.GROW_DIRECTION_DOWN
            _G._testDB.profile.global.detachedAnchorPositions = {
                Modern = { point = "CENTER", x = 0, y = -265 },
            }
            mod.InnerFrame:SetHeight(24)
            fakeAddon.GetECMModule = function(_, name)
                return name == mod.Name and mod or nil
            end

            ECM.FrameUtil.LazySetAnchors = function(frame, anchors)
                frame.__ecmAnchorCache = anchors
                frame.__anchors = anchors
            end

            lib.GetActiveLayoutName = function()
                return "Modern"
            end

            ECM.Runtime.ScheduleLayoutUpdate(0, "detached-center-normalize")

            local anchor = ECM.Runtime.DetachedAnchor
            assert.same({ "TOP", UIParent, "TOP", 0, -654 }, anchor.__anchors[1])

            ECM.FrameUtil.LazySetAnchors = originalLazySetAnchors
        end)

        it("positions the detached anchor before detached modules update", function()
            local mod = makeRegisteredModule("PowerBar")
            local lib = LibStub("LibEQOLEditMode-1.0")
            local originalLazySetAnchors = ECM.FrameUtil.LazySetAnchors
            local anchorDuringLayout

            _G._testDB.profile.powerBar.anchorMode = ECM.Constants.ANCHORMODE_DETACHED
            _G._testDB.profile.global.detachedBarWidth = 321
            _G._testDB.profile.global.detachedAnchorPositions = {
                Modern = { point = "TOPLEFT", x = 10, y = 20 },
            }
            mod.InnerFrame:SetHeight(24)
            fakeAddon.GetECMModule = function(_, name)
                return name == mod.Name and mod or nil
            end

            ECM.FrameUtil.LazySetAnchors = function(frame, anchors)
                frame.__ecmAnchorCache = anchors
                frame.__anchors = anchors
            end

            lib.GetActiveLayoutName = function()
                return "Modern"
            end

            mod.ThrottledUpdateLayout = function(_, reason)
                local anchor = ECM.Runtime.DetachedAnchor
                anchorDuringLayout = {
                    anchors = anchor and anchor.__anchors and anchor.__anchors[1] or nil,
                    width = anchor and anchor:GetWidth() or nil,
                    reason = reason,
                }
            end

            ECM.Runtime.ScheduleLayoutUpdate(0, "detached-order")

            assert.are.equal("detached-order", anchorDuringLayout.reason)
            assert.same({ "TOPLEFT", UIParent, "TOPLEFT", 10, 20 }, anchorDuringLayout.anchors)
            assert.are.equal(321, anchorDuringLayout.width)

            ECM.FrameUtil.LazySetAnchors = originalLazySetAnchors
        end)

        it("keeps the detached anchor position when the active layout name is temporarily unavailable", function()
            local mod = makeRegisteredModule("PowerBar")
            local lib = LibStub("LibEQOLEditMode-1.0")
            local originalLazySetAnchors = ECM.FrameUtil.LazySetAnchors

            _G._testDB.profile.powerBar.anchorMode = ECM.Constants.ANCHORMODE_DETACHED
            _G._testDB.profile.global.detachedAnchorPositions = {
                Modern = { point = "TOPLEFT", x = 10, y = 20 },
                Raid = { point = "TOPRIGHT", x = 30, y = 40 },
            }
            mod.InnerFrame:SetHeight(24)
            fakeAddon.GetECMModule = function(_, name)
                return name == mod.Name and mod or nil
            end

            ECM.FrameUtil.LazySetAnchors = function(frame, anchors)
                frame.__ecmAnchorCache = anchors
                frame.__anchors = anchors
            end

            lib.GetActiveLayoutName = function()
                return "Modern"
            end
            ECM.Runtime.ScheduleLayoutUpdate(0, "detached-initial")

            local anchor = ECM.Runtime.DetachedAnchor
            assert.same({ "TOPLEFT", UIParent, "TOPLEFT", 10, 20 }, anchor.__anchors[1])

            lib.GetActiveLayoutName = function()
                return nil
            end
            ECM.Runtime.ScheduleLayoutUpdate(0, "detached-transition")
            assert.same({ "TOPLEFT", UIParent, "TOPLEFT", 10, 20 }, anchor.__anchors[1])

            lib.GetActiveLayoutName = function()
                return "Raid"
            end
            ECM.Runtime.ScheduleLayoutUpdate(0, "detached-layout-switch")
            assert.same({ "TOPRIGHT", UIParent, "TOPRIGHT", 30, 40 }, anchor.__anchors[1])

            ECM.FrameUtil.LazySetAnchors = originalLazySetAnchors
        end)
    end)

    describe("lifecycle", function()
        it("registers layout events on enable", function()
            local libEvent = LibStub("LibEvent-1.0")

            ECM.Runtime.Enable(fakeAddon)

            local addonFrame = assert(libEvent.embeds[fakeAddon].frame)
            assert.is_true(addonFrame.__registeredEvents.ZONE_CHANGED)
            assert.is_true(addonFrame.__registeredEvents.PLAYER_REGEN_ENABLED)
        end)

        it("cleans up layout events on disable", function()
            local libEvent = LibStub("LibEvent-1.0")

            ECM.Runtime.Enable(fakeAddon)

            local addonFrame = assert(libEvent.embeds[fakeAddon].frame)
            assert.is_false(createdTickers[1].cancelled)

            ECM.Runtime.Disable(fakeAddon)

            assert.is_nil(addonFrame.__registeredEvents.ZONE_CHANGED)
            assert.is_nil(addonFrame.__registeredEvents.PLAYER_REGEN_ENABLED)
            assert.is_true(addonFrame.__unregisteredEvents.ZONE_CHANGED)
            assert.is_true(addonFrame.__unregisteredEvents.PLAYER_REGEN_ENABLED)
            assert.is_true(createdTickers[1].cancelled)
        end)

        it("calls OnCombatEnd callback on PLAYER_REGEN_ENABLED", function()
            local called = false
            ECM.Runtime.OnCombatEnd = function()
                called = true
            end

            ECM.Runtime.Enable(fakeAddon)

            local libEvent = LibStub("LibEvent-1.0")
            local addonFrame = assert(libEvent.embeds[fakeAddon].frame)

            -- Simulate PLAYER_REGEN_ENABLED via the registered handler
            local handler = addonFrame.__scripts and addonFrame.__scripts["OnEvent"]
            if handler then
                handler(addonFrame, "PLAYER_REGEN_ENABLED")
            end

            assert.is_true(called)
        end)
    end)

    describe("watchdog graceful degradation", function()
        --- Creates a Blizzard frame stub in _G with HookScript call tracking.
        local function makeBlizzardFrame(name)
            local frame = makeFrame({ name = name })
            frame._hookScriptCalls = 0
            local origHookScript = frame.HookScript
            function frame:HookScript(...)
                self._hookScriptCalls = self._hookScriptCalls + 1
                return origHookScript(self, ...)
            end
            _G[name] = frame
            return frame
        end

        --- Places all 4 Blizzard frames + CooldownViewerSettings in _G.
        local function createAllBlizzardFrames()
            local frames = {}
            for _, name in ipairs(ECM.Constants.BLIZZARD_FRAMES) do
                frames[name] = makeBlizzardFrame(name)
            end
            local settings = makeFrame({ name = "CooldownViewerSettings" })
            settings._hookScriptCalls = 0
            local origHS = settings.HookScript
            function settings:HookScript(...)
                self._hookScriptCalls = self._hookScriptCalls + 1
                return origHS(self, ...)
            end
            _G.CooldownViewerSettings = settings
            frames.CooldownViewerSettings = settings
            return frames
        end

        it("skips setup calls once all frames hooked and settings bound", function()
            local frames = createAllBlizzardFrames()
            ECM.Runtime.Enable(fakeAddon)

            local ticker = createdTickers[1]

            -- First tick: hooks all frames + settings
            ticker.callback()
            for _, name in ipairs(ECM.Constants.BLIZZARD_FRAMES) do
                assert.are.equal(1, frames[name]._hookScriptCalls,
                    name .. " should be hooked exactly once after first tick")
            end
            assert.are.equal(1, frames.CooldownViewerSettings._hookScriptCalls,
                "CooldownViewerSettings should be hooked once")

            -- Second tick: setup should be skipped
            ticker.callback()
            for _, name in ipairs(ECM.Constants.BLIZZARD_FRAMES) do
                assert.are.equal(1, frames[name]._hookScriptCalls,
                    name .. " should still be hooked exactly once after second tick")
            end
            assert.are.equal(1, frames.CooldownViewerSettings._hookScriptCalls,
                "CooldownViewerSettings should still be hooked once after second tick")
        end)

        it("still enforces Blizzard frame state after setup is complete", function()
            local frames = createAllBlizzardFrames()
            ECM.Runtime.Enable(fakeAddon)

            local ticker = createdTickers[1]
            ticker.callback() -- complete all setup

            -- Simulate a Blizzard frame being externally hidden
            frames[ECM.Constants.BLIZZARD_FRAMES[1]]:Hide()
            assert.is_false(frames[ECM.Constants.BLIZZARD_FRAMES[1]]:IsShown())

            -- Enforcement tick should re-show it
            ticker.callback()
            assert.is_true(frames[ECM.Constants.BLIZZARD_FRAMES[1]]:IsShown(),
                "Enforcement should re-show externally hidden Blizzard frame")
        end)

        it("continues setup when frames appear late", function()
            -- Start with only 2 of 4 Blizzard frames
            local firstTwo = {}
            for i = 1, 2 do
                local name = ECM.Constants.BLIZZARD_FRAMES[i]
                firstTwo[name] = makeBlizzardFrame(name)
            end

            ECM.Runtime.Enable(fakeAddon)
            local ticker = createdTickers[1]

            -- First tick: hooks 2 frames, but no CooldownViewerSettings yet
            ticker.callback()
            for _, name in ipairs({ ECM.Constants.BLIZZARD_FRAMES[1], ECM.Constants.BLIZZARD_FRAMES[2] }) do
                assert.are.equal(1, firstTwo[name]._hookScriptCalls)
            end

            -- Second tick: still runs setup (incomplete)
            ticker.callback()

            -- Now add remaining frames + settings
            local laterFrames = {}
            for i = 3, 4 do
                local name = ECM.Constants.BLIZZARD_FRAMES[i]
                laterFrames[name] = makeBlizzardFrame(name)
            end
            local settings = makeFrame({ name = "CooldownViewerSettings" })
            settings._hookScriptCalls = 0
            local origHS = settings.HookScript
            function settings:HookScript(...)
                self._hookScriptCalls = self._hookScriptCalls + 1
                return origHS(self, ...)
            end
            _G.CooldownViewerSettings = settings

            -- Third tick: hooks remaining frames + settings, setup completes
            ticker.callback()
            for _, name in ipairs({ ECM.Constants.BLIZZARD_FRAMES[3], ECM.Constants.BLIZZARD_FRAMES[4] }) do
                assert.are.equal(1, laterFrames[name]._hookScriptCalls,
                    name .. " should be hooked on third tick")
            end
            assert.are.equal(1, settings._hookScriptCalls)

            -- Fourth tick: setup skipped, no additional hooks
            ticker.callback()
            for _, name in ipairs({ ECM.Constants.BLIZZARD_FRAMES[3], ECM.Constants.BLIZZARD_FRAMES[4] }) do
                assert.are.equal(1, laterFrames[name]._hookScriptCalls,
                    name .. " should not be re-hooked after setup complete")
            end
        end)
    end)
end)
