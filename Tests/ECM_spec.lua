-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("ECM layout system", function()
    local originalGlobals
    local fakeTime
    local isMounted
    local inCombat
    local cvarEnabled
    local addonVersion
    local printedMessages
    local fakeAddon
    local defaultModuleLibraries
    local createdFrames
    local createdTickers
    local makeFrame = TestHelpers.makeFrame

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
        addonVersion = "v0.6.1"
        printedMessages = {}
        defaultModuleLibraries = {}
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

        _G.C_CVar = {
            GetCVarBool = function(name)
                return name == "cooldownViewerEnabled" and cvarEnabled
            end,
            SetCVar = function() end,
        }
        _G.C_AddOns = {
            GetAddOnMetadata = function(_, key)
                if key == "Version" then
                    return addonVersion
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
        _G.UIParent = makeFrame({ name = "UIParent" })
        local function makeFontString()
            local fontString = { _anchors = {} }

            function fontString:SetPoint(...)
                self._anchors[#self._anchors + 1] = { ... }
            end

            function fontString:GetNumPoints()
                return #self._anchors
            end

            function fontString:GetPoint(index)
                local point = self._anchors[index]
                if point then
                    return point[1], point[2], point[3], point[4], point[5]
                end
            end

            function fontString:ClearAllPoints()
                self._anchors = {}
            end

            function fontString:SetText(text)
                self._text = text
            end

            function fontString:GetText()
                return self._text
            end

            function fontString:SetWidth(width)
                self._width = width
            end

            function fontString:GetWidth()
                return self._width
            end

            function fontString:SetJustifyH(justifyH)
                self._justifyH = justifyH
            end

            function fontString:SetJustifyV(justifyV)
                self._justifyV = justifyV
            end

            function fontString:SetTextColor(...)
                self._textColor = { ... }
            end

            function fontString:SetWordWrap(wordWrap)
                self._wordWrap = wordWrap
            end

            return fontString
        end

        _G.CreateFrame = function(frameType, name, parent, template)
            local frame = makeFrame({ name = name })
            frame._frameType = frameType
            frame._parent = parent
            frame._template = template

            function frame:SetBackdrop(backdrop)
                self._backdrop = backdrop
            end

            function frame:SetBackdropColor(...)
                self._backdropColor = { ... }
            end

            function frame:SetBackdropBorderColor(...)
                self._backdropBorderColor = { ... }
            end

            function frame:EnableMouse(enabled)
                self._mouseEnabled = enabled
            end

            function frame:SetMovable(movable)
                self._movable = movable
            end

            function frame:RegisterForDrag(...)
                self._dragButtons = { ... }
            end

            function frame:SetClampedToScreen(clamped)
                self._clampedToScreen = clamped
            end

            function frame:StartMoving()
                self._startedMoving = true
            end

            function frame:StopMovingOrSizing()
                self._stoppedMoving = true
            end

            function frame:SetText(text)
                self._text = text
            end

            function frame:GetText()
                return self._text
            end

            function frame:CreateFontString()
                local fontString = makeFontString()
                self._fontStrings = self._fontStrings or {}
                self._fontStrings[#self._fontStrings + 1] = fontString
                return fontString
            end

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
        fakeAddon.SetDefaultModuleLibraries = function(_, ...)
            defaultModuleLibraries = { ... }
        end
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
        TestHelpers.SetupLibEditModeStub()
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

    describe("beta login warning", function()
        it("prints the pre-release warning on beta versions", function()
            addonVersion = "v0.6.1-beta"

            fakeAddon:OnEnable()

            assert.is_truthy(printedMessages[#printedMessages])
            assert.is_truthy(printedMessages[#printedMessages]:find(ECM.L["BETA_LOGIN_MESSAGE"], 1, true))
        end)

        it("does not print the pre-release warning on stable versions", function()
            addonVersion = "v0.6.1"

            fakeAddon:OnEnable()

            for _, message in ipairs(printedMessages) do
                assert.is_nil(message:find(ECM.L["BETA_LOGIN_MESSAGE"], 1, true))
            end
        end)
    end)

    describe("release popup", function()
        local function getWhatsNewFrame()
            for _, frame in ipairs(createdFrames) do
                if frame:GetName() == ECM.Constants.WHATS_NEW_FRAME_NAME then
                    return frame
                end
            end
        end

        before_each(function()
            addonVersion = "v1.2.3"
            ECM.Constants.RELEASE_POPUP_VERSION = addonVersion
            ECM.L["WHATS_NEW_BODY"] = "New version notes"
            _G._testDB.profile.global.releasePopupSeenVersion = ""
        end)

        it("shows the popup when enabled and unseen", function()
            fakeAddon:OnEnable()

            assert.is_true(assert(getWhatsNewFrame()):IsShown())
        end)

        it("does not show the popup when the current version has already been seen", function()
            _G._testDB.profile.global.releasePopupSeenVersion = addonVersion

            fakeAddon:OnEnable()

            assert.is_nil(getWhatsNewFrame())
        end)

        it("does not show the popup when the addon version is unavailable", function()
            addonVersion = nil

            fakeAddon:OnEnable()

            assert.is_true(assert(getWhatsNewFrame()):IsShown())
        end)

        it("does not show the popup when RELEASE_POPUP_VERSION is nil", function()
            ECM.Constants.RELEASE_POPUP_VERSION = nil

            fakeAddon:OnEnable()

            assert.is_nil(getWhatsNewFrame())
        end)

        it("does not show the popup when RELEASE_POPUP_VERSION is empty", function()
            ECM.Constants.RELEASE_POPUP_VERSION = ""

            assert.is_false(fakeAddon:ShowReleasePopup(true))
            assert.is_nil(getWhatsNewFrame())
        end)

        it("does not automatically show the popup twice in the same session", function()
            fakeAddon:OnEnable()
            local frame = assert(getWhatsNewFrame())
            fakeAddon:OnEnable()

            assert.are.equal(1, TestHelpers.getCalls(frame, "Show"))
        end)

        it("persists the seen version when the popup is acknowledged", function()
            fakeAddon:OnEnable()
            local frame = assert(getWhatsNewFrame())
            frame.CloseButton:GetScript("OnClick")(frame.CloseButton)
            fakeAddon:OnEnable()

            assert.are.equal(addonVersion, _G._testDB.profile.global.releasePopupSeenVersion)
            assert.are.equal(1, TestHelpers.getCalls(frame, "Show"))
            assert.is_false(frame:IsShown())
        end)

        it("marks the popup seen and opens settings from the secondary button", function()
            local chatInputs = {}
            fakeAddon.ChatCommand = function(_, input)
                chatInputs[#chatInputs + 1] = input
            end

            assert.is_true(fakeAddon:ShowReleasePopup(true))
            local frame = assert(getWhatsNewFrame())

            frame.SettingsButton:GetScript("OnClick")(frame.SettingsButton)

            assert.are.equal(addonVersion, _G._testDB.profile.global.releasePopupSeenVersion)
            assert.is_false(frame:IsShown())
            assert.same({ "options" }, chatInputs)
        end)

        it("formats markdown headings and list items for the popup body", function()
            ECM.L["WHATS_NEW_BODY"] = "### Header\nBody line\n- First item\n- Second item"

            assert.is_true(fakeAddon:ShowReleasePopup(true))
            local frame = assert(getWhatsNewFrame())
            assert.are.equal(
                "|cff" .. ECM.Constants.WHATS_NEW_HEADER_COLOR .. "Header|r\n"
                    .. "Body line\n"
                    .. ECM.Constants.WHATS_NEW_LIST_BULLET .. " First item\n"
                    .. ECM.Constants.WHATS_NEW_LIST_BULLET .. " Second item",
                frame.Body:GetText()
            )
        end)

        it("uses the standard popup button labels", function()
            assert.is_true(fakeAddon:ShowReleasePopup(true))
            local frame = assert(getWhatsNewFrame())
            assert.are.equal("Close", frame.CloseButton:GetText())
            assert.are.equal("Open settings", frame.SettingsButton:GetText())
        end)

        it("creates a dedicated header and left-aligned body text", function()
            assert.is_true(fakeAddon:ShowReleasePopup(true))
            local frame = assert(getWhatsNewFrame())

            assert.are.equal(ECM.Constants.WHATS_NEW_FRAME_WIDTH, frame:GetWidth())
            assert.are.equal(ECM.Constants.WHATS_NEW_FRAME_HEIGHT, frame:GetHeight())
            assert.are.equal(ECM.L["ADDON_NAME"], frame.Title:GetText())
            assert.are.equal(string.format(ECM.L["WHATS_NEW_TITLE_FORMAT"], addonVersion), frame.Subtitle:GetText())
            assert.are.equal("LEFT", frame.Title._justifyH)
            assert.are.equal("LEFT", frame.Subtitle._justifyH)
            assert.are.equal("LEFT", frame.Body._justifyH)
            assert.are.equal("TOP", frame.Body._justifyV)
            assert.same(
                {
                    { "TOPLEFT", frame, "TOPLEFT", ECM.Constants.WHATS_NEW_FRAME_PADDING,
                        -ECM.Constants.WHATS_NEW_FRAME_PADDING },
                    { "TOPRIGHT", frame, "TOPRIGHT", -ECM.Constants.WHATS_NEW_FRAME_PADDING,
                        -ECM.Constants.WHATS_NEW_FRAME_PADDING },
                },
                frame.Title._anchors
            )
            assert.same(
                {
                    { "TOPLEFT", frame.Title, "BOTTOMLEFT", 0, -ECM.Constants.WHATS_NEW_SUBTITLE_SPACING },
                    { "TOPRIGHT", frame.Title, "BOTTOMRIGHT", 0, -ECM.Constants.WHATS_NEW_SUBTITLE_SPACING },
                },
                frame.Subtitle._anchors
            )
            assert.same(
                {
                    { "TOPLEFT", frame.Subtitle, "BOTTOMLEFT", 0, -ECM.Constants.WHATS_NEW_BODY_SPACING },
                    { "TOPRIGHT", frame.Subtitle, "BOTTOMRIGHT", 0, -ECM.Constants.WHATS_NEW_BODY_SPACING },
                },
                frame.Body._anchors
            )
        end)

        it("does not show an empty popup when release notes are unavailable", function()
            ECM.L["WHATS_NEW_BODY"] = ""

            assert.is_false(fakeAddon:ShowReleasePopup(true))
            assert.is_nil(getWhatsNewFrame())
        end)

        it("force showing ignores the seen flag", function()
            _G._testDB.profile.global.releasePopupSeenVersion = addonVersion

            assert.is_true(fakeAddon:ShowReleasePopup(true))
            local frame = assert(getWhatsNewFrame())
            assert.are.equal(
                string.format(ECM.L["WHATS_NEW_TITLE_FORMAT"], addonVersion),
                frame.Subtitle:GetText()
            )
            assert.are.equal("New version notes", frame.Body:GetText())
        end)

        it("clearseen allows the popup to show again after a reload", function()
            _G._testDB.profile.global.releasePopupSeenVersion = addonVersion

            fakeAddon:ChatCommand("clearseen")
            fakeAddon:OnEnable()

            assert.is_true(assert(getWhatsNewFrame()):IsShown())
            assert.is_nil(_G._testDB.profile.global.releasePopupSeenVersion)
        end)
    end)

    describe("profile change handling", function()
        it("registers AceDB profile callbacks on enable", function()
            local registeredEvents = {}
            _G._testDB.RegisterCallback = function(_target, event, _handler)
                registeredEvents[#registeredEvents + 1] = event
            end

            fakeAddon:OnEnable()

            table.sort(registeredEvents)
            assert.same({ "OnProfileChanged", "OnProfileCopied", "OnProfileReset" }, registeredEvents)
        end)

        it("OnProfileChangedHandler re-evaluates module states and schedules layout", function()
            local enableCalls = {}
            local layoutReasons = {}
            fakeAddon.EnableModule = function(_, name) enableCalls[#enableCalls + 1] = { "enable", name } end
            fakeAddon.DisableModule = function(_, name) enableCalls[#enableCalls + 1] = { "disable", name } end

            local origSchedule = ECM.Runtime.ScheduleLayoutUpdate
            ECM.Runtime.ScheduleLayoutUpdate = function(_, reason)
                layoutReasons[#layoutReasons + 1] = reason
            end

            fakeAddon:OnEnable()
            enableCalls = {}

            -- Disable PowerBar in the profile and trigger handler
            _G._testDB.profile.powerBar.enabled = false
            fakeAddon:OnProfileChangedHandler()

            -- Should have re-evaluated: PowerBar disabled, others enabled
            local disabledPowerBar = false
            for _, call in ipairs(enableCalls) do
                if call[1] == "disable" and call[2] == "PowerBar" then
                    disabledPowerBar = true
                end
            end
            assert.is_true(disabledPowerBar)
            assert.is_truthy(layoutReasons[#layoutReasons] == "ProfileChanged")

            ECM.Runtime.ScheduleLayoutUpdate = origSchedule
        end)

        it("OnInitialize runs migration for older schema profiles", function()
            local migrationProfiles = {}
            local aceDB = _G.LibStub:NewLibrary("AceDB-3.0", 1)
            local profile = TestHelpers.deepClone(ECM.defaults.profile)
            profile.schemaVersion = 10
            aceDB.New = function()
                return { profile = profile, RegisterCallback = function() end }
            end

            local origRun = ECM.Migration.Run
            ECM.Migration.Run = function(activeProfile)
                migrationProfiles[#migrationProfiles + 1] = activeProfile
            end

            fakeAddon:OnInitialize()

            assert.same({ profile }, migrationProfiles)

            ECM.Migration.Run = origRun
        end)
    end)

    describe("initialization wiring", function()
        it("defines the reload popup constant used by ConfirmReloadUI", function()
            local getShownNames = TestHelpers.InstallPopupRecorder()

            fakeAddon:ConfirmReloadUI("Reload now?")

            local shownNames = getShownNames()

            assert.are.equal("ECM_CONFIRM_RELOAD_UI", ECM.Constants.POPUP_CONFIRM_RELOAD_UI)
            assert.are.equal(ECM.Constants.POPUP_CONFIRM_RELOAD_UI, shownNames[1])
            assert.is_table(StaticPopupDialogs[ECM.Constants.POPUP_CONFIRM_RELOAD_UI])
            assert.are.equal("Reload now?", StaticPopupDialogs[ECM.Constants.POPUP_CONFIRM_RELOAD_UI].text)
        end)

        it("sets LibEvent as the default module library on addon creation", function()
            assert.same({ "LibEvent-1.0" }, defaultModuleLibraries)
        end)

        it("registers layout events via Runtime on enable", function()
            local libEvent = LibStub("LibEvent-1.0")

            fakeAddon:OnEnable()
            inCombat = true
            fakeAddon:ChatCommand("options")

            local addonFrame = assert(libEvent.embeds[fakeAddon].frame)
            assert.is_true(addonFrame.__registeredEvents.ZONE_CHANGED)
            assert.is_true(addonFrame.__registeredEvents.PLAYER_REGEN_ENABLED)
        end)

        it("cleans up layout events via Runtime on disable", function()
            local libEvent = LibStub("LibEvent-1.0")

            fakeAddon:OnEnable()

            local addonFrame = assert(libEvent.embeds[fakeAddon].frame)

            assert.is_false(createdTickers[1].cancelled)

            fakeAddon:OnDisable()

            assert.is_nil(addonFrame.__registeredEvents.ZONE_CHANGED)
            assert.is_nil(addonFrame.__registeredEvents.PLAYER_REGEN_ENABLED)
            assert.is_true(addonFrame.__unregisteredEvents.ZONE_CHANGED)
            assert.is_true(addonFrame.__unregisteredEvents.PLAYER_REGEN_ENABLED)
            assert.is_true(createdTickers[1].cancelled)
        end)

        it("registers the addon compartment entry once and opens options from it", function()
            local registrationCount = 0
            local registeredEntry
            local chatInputs = {}
            _G.AddonCompartmentFrame = {
                RegisterAddon = function(_, entry)
                    registrationCount = registrationCount + 1
                    registeredEntry = entry
                end,
            }
            fakeAddon.ChatCommand = function(_, input)
                chatInputs[#chatInputs + 1] = input
            end

            fakeAddon:OnEnable()
            fakeAddon:OnEnable()

            assert.are.equal(1, registrationCount)
            assert.are.equal(ECM.Constants.ADDON_ICON_TEXTURE, registeredEntry.icon)
            assert.is_true(registeredEntry.notCheckable)
            registeredEntry.func()
            assert.same({ "options" }, chatInputs)
        end)

        it("retries addon compartment registration after a failure", function()
            local registrationCount = 0
            _G.AddonCompartmentFrame = {
                RegisterAddon = function()
                    registrationCount = registrationCount + 1
                    error("boom")
                end,
            }

            fakeAddon:OnEnable()
            fakeAddon:OnEnable()

            assert.are.equal(2, registrationCount)
        end)

        it("registers both slash commands through LibConsole during OnInitialize", function()
            local chatInputs = {}
            local aceDB = _G.LibStub:NewLibrary("AceDB-3.0", 1)
            aceDB.New = function()
                return { profile = TestHelpers.deepClone(ECM.defaults.profile) }
            end

            function fakeAddon:ChatCommand(input)
                chatInputs[#chatInputs + 1] = input
            end

            fakeAddon:OnInitialize()

            assert.is_function(SlashCmdList.LIBCONSOLE_ENHANCEDCOOLDOWNMANAGER)
            assert.is_function(SlashCmdList.LIBCONSOLE_ECM)
            assert.are.equal("/enhancedcooldownmanager", _G.SLASH_LIBCONSOLE_ENHANCEDCOOLDOWNMANAGER1)
            assert.are.equal("/ecm", _G.SLASH_LIBCONSOLE_ECM1)

            SlashCmdList.LIBCONSOLE_ENHANCEDCOOLDOWNMANAGER("from-long")
            SlashCmdList.LIBCONSOLE_ECM("from-short")

            assert.same({ "from-long", "from-short" }, chatInputs)
        end)
    end)
end)
