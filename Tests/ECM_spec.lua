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

        it("OnEnable retries migration when initialization left the profile on an older schema", function()
            local migrationProfiles = {}
            local origRun = ECM.Migration.Run
            ECM.Migration.Run = function(profile)
                migrationProfiles[#migrationProfiles + 1] = profile
            end

            _G._testDB.profile.schemaVersion = 10
            fakeAddon:OnEnable()

            assert.same({ _G._testDB.profile }, migrationProfiles)

            ECM.Migration.Run = origRun
        end)
    end)

    describe("initialization wiring", function()
        it("defines the reload popup constant used by ConfirmReloadUI", function()
            local shownName
            _G.StaticPopup_Show = function(name)
                shownName = name
            end

            fakeAddon:ConfirmReloadUI("Reload now?")

            assert.are.equal("ECM_CONFIRM_RELOAD_UI", ECM.Constants.POPUP_CONFIRM_RELOAD_UI)
            assert.are.equal(ECM.Constants.POPUP_CONFIRM_RELOAD_UI, shownName)
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
