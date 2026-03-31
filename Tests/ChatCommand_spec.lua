-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("ChatCommand migration", function()
    local originalGlobals
    local mod
    local fakeAddon
    local printedMessages
    local confirmReloadCalls
    local printInfoCalled
    local getLogTextResult
    local shownMigrationLog
    local openOptionsCalls
    local scheduleLayoutCalls
    local ns

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "LibStub",
            "InCombatLockdown",
            "StaticPopupDialogs",
            "StaticPopup_Show",
            "YES",
            "NO",
            "ReloadUI",
            "strtrim",
            "issecretvalue",
            "issecrettable",
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
            "UnitExists",
            "UnitIsDead",
            "UnitCanAttack",
            "UnitCanAssist",
            "IsInInstance",
            "Enum",
            "print",
            "DevTool",
            "AddonCompartmentFrame",
            "CLOSE",
            "CANCEL",
            "OKAY",
            "CooldownViewerSettings",
            "SlashCmdList",
            "hash_SlashCmdList",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        ns = {}
        printedMessages = {}
        confirmReloadCalls = {}
        printInfoCalled = false
        getLogTextResult = nil
        shownMigrationLog = nil
        openOptionsCalls = 0
        scheduleLayoutCalls = {}

        _G.strtrim = function(s)
            return tostring(s):match("^%s*(.-)%s*$")
        end
        _G.InCombatLockdown = function()
            return false
        end
        _G.IsMounted = function()
            return false
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
        _G.StaticPopupDialogs = {}
        _G.StaticPopup_Show = function() end
        _G.YES = "Yes"
        _G.NO = "No"
        _G.ReloadUI = function() end
        _G.GetTime = function()
            return 0
        end
        _G.C_Timer = {
            After = function(_, callback)
                callback()
            end,
            NewTicker = function() end,
        }
        _G.C_AddOns = {
            GetAddOnMetadata = function()
                return "v0.0.0"
            end,
        }
        _G.C_CVar = {
            GetCVarBool = function()
                return true
            end,
            SetCVar = function() end,
        }
        _G.Enum = {}
        _G.DevTool = nil
        _G.AddonCompartmentFrame = nil
        _G.CLOSE = "Close"
        _G.CANCEL = "Cancel"
        _G.OKAY = "Okay"
        _G.CooldownViewerSettings = nil
        _G.SlashCmdList = {}
        _G.hash_SlashCmdList = {}
        _G.print = function(...) end
        _G.UIParent = TestHelpers.makeFrame({ name = "UIParent" })
        _G.CreateFrame = function(_, name)
            local frame = TestHelpers.makeFrame({ name = name })
            frame.SetScript = function() end
            frame.RegisterEvent = function() end
            frame.UnregisterEvent = function() end
            frame.SetFrameStrata = function() end
            frame.SetBackdrop = function() end
            frame.SetBackdropColor = function() end
            frame.SetBackdropBorderColor = function() end
            frame.EnableMouse = function() end
            frame.CreateFontString = function()
                local fontString = TestHelpers.makeRegion("FontString")
                fontString.SetPoint = function() end
                fontString.SetText = function() end
                fontString.SetJustifyH = function() end
                fontString.SetJustifyV = function() end
                return fontString
            end
            frame.SetSize = function() end
            frame.SetPoint = function() end
            frame.Hide = function(self)
                self.__shown = false
            end
            frame.Show = function(self)
                self.__shown = true
            end
            frame.IsShown = function(self)
                return self.__shown ~= false
            end
            frame.HookScript = function() end
            return frame
        end

        ns.Log = function() end
        ns.ColorUtil = {
            Sparkle = function(s)
                return s
            end,
        }
        ns.Runtime = { ScheduleLayoutUpdate = function(delay, reason)
            scheduleLayoutCalls[#scheduleLayoutCalls + 1] = { delay = delay, reason = reason }
        end }

        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")(nil, ns)
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")(nil, ns)
        TestHelpers.LoadChunk("Tests/stubs/Enums.lua", "Unable to load Enums.lua")()
        TestHelpers.LoadChunk("ECM_Defaults.lua", "Unable to load ECM_Defaults.lua")(nil, ns)

        ns.Migration = {
            PrepareDatabase = function() end,
            Run = function() end,
            FlushLog = function() end,
            PrintInfo = function()
                printInfoCalled = true
            end,
            GetLogText = function()
                return getLogTextResult
            end,
            ValidateRollback = function()
                return false, "mock error"
            end,
            Rollback = function() end,
        }
        ns.EditMode = {
            Lib = {
                IsInEditMode = function()
                    return false
                end,
                RegisterFrame = function() end,
                GetActiveLayoutName = function()
                    return "Modern"
                end,
            },
            GetPosition = function()
                return { point = "CENTER", x = 0, y = 0 }
            end,
            SavePosition = function() end,
            RegisterFrame = function() end,
            GetActiveLayoutName = function()
                return "Modern"
            end,
        }

        TestHelpers.SetupLibStub()
        TestHelpers.SetupLibEditModeStub()
        TestHelpers.LoadChunk("Libs/LibEvent/LibEvent.lua", "Unable to load LibEvent.lua")()
        TestHelpers.LoadChunk("Helpers/FrameUtil.lua", "Unable to load Helpers/FrameUtil.lua")(nil, ns)
        TestHelpers.LoadChunk("Helpers/BarMixin.lua", "Unable to load Helpers/BarMixin.lua")(nil, ns)
        TestHelpers.LoadChunk("Libs/LibConsole/LibConsole.lua", "Unable to load LibConsole.lua")()

        -- Minimal AceAddon mock
        fakeAddon = {
            db = { profile = { global = { debug = false } } },
        }
        fakeAddon.RegisterEvent = function() end
        fakeAddon.UnregisterEvent = function() end
        fakeAddon.GetModule = function(_, name)
            if name == "Options" then
                return {
                    OpenOptions = function()
                        openOptionsCalls = openOptionsCalls + 1
                    end,
                }
            end
            return nil
        end
        fakeAddon.ConfirmReloadUI = function(_, text, onAccept)
            confirmReloadCalls[#confirmReloadCalls + 1] = { text = text, onAccept = onAccept }
        end
        fakeAddon.SetDefaultModuleLibraries = function() end

        local aceAddon = _G.LibStub:NewLibrary("AceAddon-3.0", 1)
        aceAddon.NewAddon = function(_, name)
            fakeAddon._name = name
            return fakeAddon
        end

        ns.Addon = fakeAddon
        TestHelpers.LoadChunk("ECM.lua", "Unable to load ECM.lua")("EnhancedCooldownManager", ns)

        fakeAddon.ConfirmReloadUI = function(_, text, onAccept)
            confirmReloadCalls[#confirmReloadCalls + 1] = { text = text, onAccept = onAccept }
        end
        ns.Runtime.ScheduleLayoutUpdate = function(delay, reason)
            scheduleLayoutCalls[#scheduleLayoutCalls + 1] = { delay = delay, reason = reason }
        end

        local originalPrint = ns.Print
        ns.Print = function(...)
            local args = { ... }
            for i = 1, #args do
                args[i] = tostring(args[i])
            end
            printedMessages[#printedMessages + 1] = table.concat(args, " ")
        end
        mod = fakeAddon
        mod._testOriginalPrint = originalPrint
    end)

    it("/ecm migration calls PrintInfo", function()
        mod:ChatCommand("migration")
        assert.is_true(printInfoCalled)
        assert.is_nil(shownMigrationLog)
    end)

    it("/ecm migration log shows dialog when log has entries", function()
        getLogTextResult = "2024-01-01 00:00:00  migrated V2 to V3"
        mod.ShowMigrationLogDialog = function(_, text)
            shownMigrationLog = text
        end
        mod:ChatCommand("migration log")
        assert.equal(getLogTextResult, shownMigrationLog)
        assert.is_false(printInfoCalled)
    end)

    it("/ecm migration log prints message when log is empty", function()
        getLogTextResult = nil
        mod:ChatCommand("migration log")
        assert.is_nil(shownMigrationLog)
        assert.truthy(#printedMessages > 0)
    end)

    it("/ecm migration with unrecognized subcmd calls PrintInfo", function()
        mod:ChatCommand("migration foo")
        assert.is_true(printInfoCalled)
    end)

    it("/ecm migration rollback with valid version calls ValidateRollback and ConfirmReloadUI", function()
        local validatedVersion
        ns.Migration.ValidateRollback = function(n)
            validatedVersion = n
            return true, "Will delete V10 and re-migrate from V8."
        end

        mod:ChatCommand("migration rollback 8")

        assert.are.equal(8, validatedVersion)
        assert.are.equal(1, #confirmReloadCalls)
        assert.are.equal("Will delete V10 and re-migrate from V8.", confirmReloadCalls[1].text)
    end)

    it("/ecm migration rollback -1 translates to CURRENT - 1", function()
        local validatedVersion
        ns.Migration.ValidateRollback = function(n)
            validatedVersion = n
            return true, "Will delete V10 and re-migrate from V9."
        end

        mod:ChatCommand("migration rollback -1")

        assert.are.equal(ns.Constants.CURRENT_SCHEMA_VERSION - 1, validatedVersion)
        assert.are.equal(1, #confirmReloadCalls)
    end)

    it("/ecm migration rollback 0 is rejected", function()
        mod:ChatCommand("migration rollback 0")

        assert.are.equal(0, #confirmReloadCalls)
        assert.is_not_nil(printedMessages[1])
        assert.is_not_nil(string.find(printedMessages[1], "not valid", 1, true))
    end)

    it("/ecm migration rollback without number shows usage", function()
        mod:ChatCommand("migration rollback")

        assert.are.equal(0, #confirmReloadCalls)
        assert.is_not_nil(string.find(printedMessages[1], "Usage", 1, true))
    end)

    it("/ecm migration rollback with non-numeric arg shows usage", function()
        mod:ChatCommand("migration rollback abc")

        assert.are.equal(0, #confirmReloadCalls)
        assert.is_not_nil(string.find(printedMessages[1], "Usage", 1, true))
    end)

    it("/ecm migration rollback with failed validation prints error", function()
        ns.Migration.ValidateRollback = function()
            return false, "No prior version exists."
        end

        mod:ChatCommand("migration rollback 5")

        assert.are.equal(0, #confirmReloadCalls)
        assert.are.equal("No prior version exists.", printedMessages[1])
    end)

    it("ConfirmReloadUI onAccept calls Migration.Rollback with correct version", function()
        local rolledBackVersion
        ns.Migration.ValidateRollback = function(_)
            return true, "Will delete V10."
        end
        ns.Migration.Rollback = function(n)
            rolledBackVersion = n
        end

        mod:ChatCommand("migration rollback 8")

        assert.are.equal(1, #confirmReloadCalls)
        -- Simulate the user clicking Yes
        confirmReloadCalls[1].onAccept()
        assert.are.equal(8, rolledBackVersion)
    end)

    it("ConfirmReloadUI onAccept after -1 calls Rollback with translated version", function()
        local rolledBackVersion
        ns.Migration.ValidateRollback = function(_)
            return true, "Will delete."
        end
        ns.Migration.Rollback = function(n)
            rolledBackVersion = n
        end

        mod:ChatCommand("migration rollback -1")

        confirmReloadCalls[1].onAccept()
        assert.are.equal(ns.Constants.CURRENT_SCHEMA_VERSION - 1, rolledBackVersion)
    end)

    it("/ecm help includes migration command", function()
        mod:ChatCommand("help")

        local hasMigration = false
        for _, msg in ipairs(printedMessages) do
            if string.find(msg, "/ecm migration", 1, true) then
                hasMigration = true
                break
            end
        end
        assert.is_true(hasMigration)
    end)

    it("/ecm help includes clearseen command", function()
        mod:ChatCommand("help")

        local hasClearSeen = false
        for _, msg in ipairs(printedMessages) do
            if string.find(msg, "/ecm clearseen", 1, true) then
                hasClearSeen = true
                break
            end
        end
        assert.is_true(hasClearSeen)
    end)

    it("/ecm help does not include migrationlog", function()
        mod:ChatCommand("help")

        for _, msg in ipairs(printedMessages) do
            assert.is_nil(string.find(msg, "migrationlog", 1, true), "Help should not mention migrationlog")
        end
    end)

    it("/ecm settings defers opening options during combat", function()
        _G.InCombatLockdown = function()
            return true
        end

        mod:ChatCommand("settings")

        assert.are.equal(0, openOptionsCalls)
        assert.are.equal(1, #printedMessages)
        assert.are.equal("Options cannot be opened during combat. They will open when combat ends.", printedMessages[1])
        assert.is_true(mod._openOptionsAfterCombat)
    end)

    it("queued options open after combat ends", function()
        mod._openOptionsAfterCombat = true

        mod:HandleOpenOptionsAfterCombat()

        assert.are.equal(1, openOptionsCalls)
        assert.is_nil(mod._openOptionsAfterCombat)
    end)

    it("/ecm rl schedules a layout update through the real addon implementation", function()
        mod:ChatCommand("rl")

        assert.are.equal(1, #scheduleLayoutCalls)
        assert.are.equal(0, scheduleLayoutCalls[1].delay)
        assert.are.equal("ChatCommand", scheduleLayoutCalls[1].reason)
        assert.are.equal("Refreshing all modules.", printedMessages[1])
    end)

    it("/ecm clearseen clears the persisted What's New version and prints reload guidance", function()
        fakeAddon.db.profile.global.releasePopupSeenVersion = "v1.2.3"

        mod:ChatCommand("clearseen")

        assert.is_nil(fakeAddon.db.profile.global.releasePopupSeenVersion)
        assert.are.equal(
            "What's New seen flag cleared. Reload or relog to show the popup again.",
            printedMessages[1]
        )
    end)

    describe("events command", function()
        local addonStats
        local moduleStats
        local modules

        before_each(function()
            addonStats = {}
            moduleStats = {}
            modules = {}
            mod.GetEventStats = function() return addonStats end
            mod.ResetEventStats = function() addonStats = {} end
            mod.IterateModules = function() return pairs(modules) end
        end)

        it("/ecm events prints no-events message when nothing recorded", function()
            mod:ChatCommand("events")
            assert.are.equal(1, #printedMessages)
            assert.are.equal("No events recorded.", printedMessages[1])
        end)

        it("/ecm events prints sorted counts descending", function()
            addonStats.UNIT_POWER_UPDATE = 10
            addonStats.PLAYER_ENTERING_WORLD = 2

            mod:ChatCommand("events")

            assert.are.equal("Event fire counts:", printedMessages[1])
            assert.is_not_nil(string.find(printedMessages[2], "UNIT_POWER_UPDATE: 10", 1, true))
            assert.is_not_nil(string.find(printedMessages[3], "PLAYER_ENTERING_WORLD: 2", 1, true))
        end)

        it("/ecm events aggregates stats from addon and modules", function()
            addonStats.UNIT_POWER_UPDATE = 5
            modules.TestModule = {
                GetEventStats = function() return { UNIT_POWER_UPDATE = 3, UNIT_AURA = 7 } end,
            }

            mod:ChatCommand("events")

            assert.are.equal("Event fire counts:", printedMessages[1])
            -- UNIT_POWER_UPDATE = 5+3 = 8, UNIT_AURA = 7 → UNIT_POWER_UPDATE first
            assert.is_not_nil(string.find(printedMessages[2], "UNIT_POWER_UPDATE: 8", 1, true))
            assert.is_not_nil(string.find(printedMessages[3], "UNIT_AURA: 7", 1, true))
        end)

        it("/ecm events skips modules without GetEventStats", function()
            addonStats.TEST_EVENT = 1
            modules.NoStats = {}

            mod:ChatCommand("events")

            assert.are.equal("Event fire counts:", printedMessages[1])
            assert.is_not_nil(string.find(printedMessages[2], "TEST_EVENT: 1", 1, true))
        end)

        it("/ecm events reset clears addon and module stats", function()
            local moduleResetCalled = false
            addonStats.SOME_EVENT = 42
            moduleStats.OTHER_EVENT = 10
            modules.TestModule = {
                GetEventStats = function() return moduleStats end,
                ResetEventStats = function()
                    moduleResetCalled = true
                    moduleStats = {}
                end,
            }

            mod:ChatCommand("events reset")

            assert.are.equal("Event stats reset.", printedMessages[1])
            assert.is_true(moduleResetCalled)
            assert.same({}, addonStats)

            -- Verify subsequent display shows no events.
            printedMessages = {}
            mod:ChatCommand("events")
            assert.are.equal("No events recorded.", printedMessages[1])
        end)

        it("/ecm events reset skips modules without ResetEventStats", function()
            modules.NoReset = {}

            mod:ChatCommand("events reset")

            assert.are.equal("Event stats reset.", printedMessages[1])
        end)

        it("/ecm events reset works when global config is nil", function()
            addonStats.SOME_EVENT = 5
            fakeAddon.db = nil

            mod:ChatCommand("events reset")

            assert.are.equal("Event stats reset.", printedMessages[1])
            assert.same({}, addonStats)
        end)

        it("/ecm help includes events command", function()
            mod:ChatCommand("help")

            local hasEvents = false
            for _, msg in ipairs(printedMessages) do
                if string.find(msg, "/ecm events", 1, true) then
                    hasEvents = true
                    break
                end
            end
            assert.is_true(hasEvents)
        end)
    end)
end)
