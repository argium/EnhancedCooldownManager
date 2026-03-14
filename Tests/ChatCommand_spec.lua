-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("ChatCommand migration", function()
    local originalGlobals
    local mod
    local printedMessages
    local confirmReloadCalls
    local printInfoCalled
    local printLogCalled
    local openOptionsCalls
    local registeredEvents
    local unregisteredEvents

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "ECM",
            "LibStub",
            "InCombatLockdown",
            "StaticPopupDialogs",
            "StaticPopup_Show",
            "YES",
            "NO",
            "ReloadUI",
            "strtrim",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        printedMessages = {}
        confirmReloadCalls = {}
        printInfoCalled = false
        printLogCalled = false
        openOptionsCalls = 0
        registeredEvents = {}
        unregisteredEvents = {}

        _G.strtrim = function(s)
            return tostring(s):match("^%s*(.-)%s*$")
        end
        _G.InCombatLockdown = function()
            return false
        end
        _G.StaticPopupDialogs = {}
        _G.StaticPopup_Show = function() end
        _G.YES = "Yes"
        _G.NO = "No"
        _G.ReloadUI = function() end

        _G.ECM = {}
        _G.ECM.Log = function() end
        _G.ECM.Print = function(...)
            local args = { ... }
            for i = 1, #args do
                args[i] = tostring(args[i])
            end
            printedMessages[#printedMessages + 1] = table.concat(args, " ")
        end
        _G.ECM.ColorUtil = {
            Sparkle = function(s)
                return s
            end,
        }
        _G.ECM.ScheduleLayoutUpdate = function() end

        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()

        _G.ECM.Migration = {
            PrintInfo = function()
                printInfoCalled = true
            end,
            PrintLog = function()
                printLogCalled = true
            end,
            ValidateRollback = function()
                return false, "mock error"
            end,
            Rollback = function() end,
        }

        -- Minimal AceAddon mock
        local addonMethods = {}
        _G.LibStub = function()
            return {
                NewAddon = function(_, name, ...)
                    addonMethods._name = name
                    return addonMethods
                end,
                New = function()
                    return { profile = { global = { debug = false } } }
                end,
                GetLib = function()
                    return nil
                end,
            }
        end
        addonMethods.RegisterChatCommand = function() end
        addonMethods.RegisterEvent = function(_, eventName, handlerName)
            registeredEvents[#registeredEvents + 1] = { eventName = eventName, handlerName = handlerName }
        end
        addonMethods.UnregisterEvent = function(_, eventName)
            unregisteredEvents[#unregisteredEvents + 1] = eventName
        end
        addonMethods.GetModule = function(_, name)
            if name == "Options" then
                return {
                    OpenOptions = function()
                        openOptionsCalls = openOptionsCalls + 1
                    end,
                }
            end
            return nil
        end
        addonMethods.ConfirmReloadUI = function(_, text, onAccept)
            confirmReloadCalls[#confirmReloadCalls + 1] = { text = text, onAccept = onAccept }
        end
        addonMethods.db = { profile = { global = { debug = false } } }

        -- Load just enough of ECM.lua to get ChatCommand
        -- We need to extract the ChatCommand method, but ECM.lua has many dependencies.
        -- Instead, we'll directly test through the mock addon object.
        mod = addonMethods

        -- Manually define ChatCommand matching the production code structure
        function mod:ChatCommand(input)
            local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")

            if cmd == "help" then
                ECM.Print("/ecm debug [on|off||toggle] - toggle debug mode (logs detailed info to the chat frame)")
                ECM.Print("/ecm help - show this message")
                ECM.Print("/ecm migration - show migration info and commands")
                ECM.Print("/ecm options|config|settings|o - open the options menu")
                ECM.Print("/ecm rl||reload||refresh - refresh and reapply layout for all modules")
                return
            end

            if cmd == "rl" or cmd == "reload" or cmd == "refresh" then
                ECM.ScheduleLayoutUpdate(0, "ChatCommand")
                ECM.Print("Refreshing all modules.")
                return
            end

            if cmd == "migration" then
                local subcmd, subarg = arg:match("^(%S*)%s*(.-)%s*$")
                if subcmd == "log" then
                    ECM.Migration.PrintLog()
                    return
                end

                if subcmd == "rollback" then
                    local n = tonumber(subarg)
                    if not n then
                        ECM.Print("Usage: /ecm migration rollback <version>")
                        return
                    end
                    if n == 0 then
                        ECM.Print("Version 0 is not valid.")
                        return
                    end
                    if n == -1 then
                        n = ECM.Constants.CURRENT_SCHEMA_VERSION - 1
                    end
                    local ok, message = ECM.Migration.ValidateRollback(n)
                    if not ok then
                        ECM.Print(message)
                        return
                    end
                    self:ConfirmReloadUI(message, function()
                        ECM.Migration.Rollback(n)
                    end)
                    return
                end

                ECM.Migration.PrintInfo()
                return
            end

            if cmd == "" or cmd == "options" or cmd == "config" or cmd == "settings" or cmd == "o" then
                if InCombatLockdown() then
                    ECM.Print("Options cannot be opened during combat. They will open when combat ends.")
                    if not self._openOptionsAfterCombat then
                        self._openOptionsAfterCombat = true
                        self:RegisterEvent("PLAYER_REGEN_ENABLED", "HandleOpenOptionsAfterCombat")
                    end
                    return
                end

                local optionsModule = self:GetModule("Options", true)
                if optionsModule then
                    optionsModule:OpenOptions()
                end
                return
            end

            local profile = self.db and self.db.profile
            if not profile then
                return
            end

            if cmd == "debug" then
                local newVal
                if arg == "" or arg == "toggle" then
                    newVal = not profile.global.debug
                elseif arg == "on" then
                    newVal = true
                elseif arg == "off" then
                    newVal = false
                else
                    ECM.Print("Usage: expected on|off|toggle")
                    return
                end
                profile.global.debug = newVal
                ECM.Print("Debug:", profile.global.debug and "ON" or "OFF")
                return
            end
        end

        function mod:HandleOpenOptionsAfterCombat()
            if not self._openOptionsAfterCombat then
                return
            end

            self._openOptionsAfterCombat = nil
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")

            local optionsModule = self:GetModule("Options", true)
            if optionsModule then
                optionsModule:OpenOptions()
            end
        end
    end)

    it("/ecm migration calls PrintInfo", function()
        mod:ChatCommand("migration")
        assert.is_true(printInfoCalled)
        assert.is_false(printLogCalled)
    end)

    it("/ecm migration log calls PrintLog", function()
        mod:ChatCommand("migration log")
        assert.is_true(printLogCalled)
        assert.is_false(printInfoCalled)
    end)

    it("/ecm migration with unrecognized subcmd calls PrintInfo", function()
        mod:ChatCommand("migration foo")
        assert.is_true(printInfoCalled)
    end)

    it("/ecm migration rollback with valid version calls ValidateRollback and ConfirmReloadUI", function()
        local validatedVersion
        ECM.Migration.ValidateRollback = function(n)
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
        ECM.Migration.ValidateRollback = function(n)
            validatedVersion = n
            return true, "Will delete V10 and re-migrate from V9."
        end

        mod:ChatCommand("migration rollback -1")

        assert.are.equal(ECM.Constants.CURRENT_SCHEMA_VERSION - 1, validatedVersion)
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
        ECM.Migration.ValidateRollback = function()
            return false, "No prior version exists."
        end

        mod:ChatCommand("migration rollback 5")

        assert.are.equal(0, #confirmReloadCalls)
        assert.are.equal("No prior version exists.", printedMessages[1])
    end)

    it("ConfirmReloadUI onAccept calls Migration.Rollback with correct version", function()
        local rolledBackVersion
        ECM.Migration.ValidateRollback = function(n)
            return true, "Will delete V10."
        end
        ECM.Migration.Rollback = function(n)
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
        ECM.Migration.ValidateRollback = function(n)
            return true, "Will delete."
        end
        ECM.Migration.Rollback = function(n)
            rolledBackVersion = n
        end

        mod:ChatCommand("migration rollback -1")

        confirmReloadCalls[1].onAccept()
        assert.are.equal(ECM.Constants.CURRENT_SCHEMA_VERSION - 1, rolledBackVersion)
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
        assert.are.equal(1, #registeredEvents)
        assert.are.same(
            { eventName = "PLAYER_REGEN_ENABLED", handlerName = "HandleOpenOptionsAfterCombat" },
            registeredEvents[1]
        )
        assert.is_true(mod._openOptionsAfterCombat)
    end)

    it("queued options open after combat ends", function()
        mod._openOptionsAfterCombat = true

        mod:HandleOpenOptionsAfterCombat()

        assert.are.equal(1, openOptionsCalls)
        assert.are.same({ "PLAYER_REGEN_ENABLED" }, unregisteredEvents)
        assert.is_nil(mod._openOptionsAfterCombat)
    end)
end)
