-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("LibConsole", function()
    local originalGlobals
    local lib

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "LibStub",
            "SlashCmdList",
            "hash_SlashCmdList",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        _G.SlashCmdList = {}
        _G.hash_SlashCmdList = {}

        TestHelpers.SetupLibStub()

        TestHelpers.LoadChunk("Libs/LibConsole/LibConsole.lua", "Unable to load LibConsole")()
        lib = _G.LibStub("LibConsole-1.0")
    end)

    describe("RegisterCommand", function()
        it("registers a slash command handler in SlashCmdList", function()
            local called = false
            lib:RegisterCommand("test", function()
                called = true
            end)

            assert.is_function(SlashCmdList["LIBCONSOLE_TEST"])
            SlashCmdList["LIBCONSOLE_TEST"]("")
            assert.is_true(called)
        end)

        it("sets the SLASH_ global for the command", function()
            lib:RegisterCommand("mycommand", function() end)

            assert.are.equal("/mycommand", _G["SLASH_LIBCONSOLE_MYCOMMAND1"])
        end)

        it("lowercases the slash global regardless of input case", function()
            lib:RegisterCommand("MyCmd", function() end)

            assert.are.equal("/mycmd", _G["SLASH_LIBCONSOLE_MYCMD1"])
        end)

        it("passes input and editBox to the handler", function()
            local receivedInput, receivedEditBox
            lib:RegisterCommand("cmd", function(input, editBox)
                receivedInput = input
                receivedEditBox = editBox
            end)

            local fakeEditBox = {}
            SlashCmdList["LIBCONSOLE_CMD"]("hello world", fakeEditBox)

            assert.are.equal("hello world", receivedInput)
            assert.are.equal(fakeEditBox, receivedEditBox)
        end)

        it("tracks the command in lib.commands", function()
            lib:RegisterCommand("track", function() end)

            assert.are.equal("LIBCONSOLE_TRACK", lib.commands["track"])
        end)

        it("replaces an existing handler for the same command", function()
            local firstCalled, secondCalled = false, false
            lib:RegisterCommand("dup", function()
                firstCalled = true
            end)
            lib:RegisterCommand("dup", function()
                secondCalled = true
            end)

            SlashCmdList["LIBCONSOLE_DUP"]("")
            assert.is_false(firstCalled)
            assert.is_true(secondCalled)
        end)
    end)

    describe("UnregisterCommand", function()
        it("removes a previously registered command", function()
            lib:RegisterCommand("removeme", function() end)
            lib:UnregisterCommand("removeme")

            assert.is_nil(SlashCmdList["LIBCONSOLE_REMOVEME"])
            assert.is_nil(_G["SLASH_LIBCONSOLE_REMOVEME1"])
            assert.is_nil(lib.commands["removeme"])
        end)

        it("clears hash_SlashCmdList entry", function()
            _G.hash_SlashCmdList["/REMOVEME"] = true
            lib:RegisterCommand("removeme", function() end)
            lib:UnregisterCommand("removeme")

            assert.is_nil(hash_SlashCmdList["/REMOVEME"])
        end)

        it("is a no-op for unknown commands", function()
            assert.has_no.errors(function()
                lib:UnregisterCommand("nonexistent")
            end)
        end)
    end)

    describe("NewPrinter", function()
        it("returns a function", function()
            local printer = lib:NewPrinter(function() end)
            assert.is_function(printer)
        end)

        it("delegates a single string argument", function()
            local received
            local printer = lib:NewPrinter(function(msg)
                received = msg
            end)

            printer("hello")
            assert.are.equal("hello", received)
        end)

        it("joins multiple arguments with spaces", function()
            local received
            local printer = lib:NewPrinter(function(msg)
                received = msg
            end)

            printer("a", "b", "c")
            assert.are.equal("a b c", received)
        end)

        it("converts non-string arguments to strings", function()
            local received
            local printer = lib:NewPrinter(function(msg)
                received = msg
            end)

            printer(42, true, nil)
            assert.are.equal("42 true nil", received)
        end)

        it("handles a single nil argument", function()
            local received
            local printer = lib:NewPrinter(function(msg)
                received = msg
            end)

            printer(nil)
            assert.are.equal("nil", received)
        end)

        it("creates independent printers with different delegates", function()
            local out1, out2
            local p1 = lib:NewPrinter(function(msg) out1 = msg end)
            local p2 = lib:NewPrinter(function(msg) out2 = msg end)

            p1("first")
            p2("second")

            assert.are.equal("first", out1)
            assert.are.equal("second", out2)
        end)
    end)
end)
