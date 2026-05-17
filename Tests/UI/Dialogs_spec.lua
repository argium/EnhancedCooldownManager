-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("Dialogs", function()
    local originalGlobals
    local frames, ns, mod, printed, controlDown, reloadConfirm

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "C_Timer",
            "CLOSE",
            "CANCEL",
            "CreateFrame",
            "GameFontHighlight",
            "GameFontHighlightLarge",
            "GameFontNormal",
            "GameFontNormalLarge",
            "IsControlKeyDown",
            "OKAY",
            "StaticPopupDialogs",
            "StaticPopup_Show",
            "UIParent",
            "UISpecialFrames",
            "YES",
            "NO",
            "strtrim",
            "tinsert",
            "unpack",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    local function makeDialogFrame(name)
        local frame = TestHelpers.makeFrame({ name = name })
        frame.__hooks = {}

        function frame:HookScript(event, callback)
            self.__hooks[event] = self.__hooks[event] or {}
            self.__hooks[event][#self.__hooks[event] + 1] = callback
        end

        function frame:SetText(text)
            self.__text = text
            if self.__scripts.OnTextChanged then
                self.__scripts.OnTextChanged(self)
            end
            for _, callback in ipairs(self.__hooks.OnTextChanged or {}) do
                callback(self)
            end
        end

        function frame:HighlightText()
            self.__highlighted = true
        end

        function frame:IsTextHighlighted()
            return self.__highlighted == true
        end

        function frame:SetParent(parent)
            self.__parent = parent
        end

        function frame:GetParent()
            return self.__parent
        end

        frame.SetBackdrop = function() end
        frame.SetBackdropColor = function() end
        frame.SetBackdropBorderColor = function() end
        frame.SetClampedToScreen = function() end
        frame.SetMovable = function() end
        frame.RegisterForDrag = function() end
        frame.StartMoving = function(self) self.__moving = true end
        frame.StopMovingOrSizing = function(self) self.__moving = false; self.__sizing = false end
        frame.SetResizable = function(self, resizable) self.__resizable = resizable end
        frame.SetResizeBounds = function(self, minWidth, minHeight) self.__resizeBounds = { minWidth, minHeight } end
        frame.StartSizing = function(self, point) self.__sizing = point end
        frame.GetLeft = function() return 10 end
        frame.GetTop = function() return 500 end

        return frame
    end

    local function installDialogGlobals()
        frames = {}
        printed = {}
        controlDown = false
        reloadConfirm = nil

        _G.UIParent = makeDialogFrame("UIParent")
        _G.UIParent.GetTop = function() return 600 end
        _G.UISpecialFrames = {}
        _G.StaticPopupDialogs = {}
        _G.StaticPopup_Show = function(name, text1, text2, data)
            _G.StaticPopupDialogs._lastShow = { name = name, text1 = text1, text2 = text2, data = data }
        end
        _G.YES = "Yes"
        _G.NO = "No"
        _G.CLOSE = "Close"
        _G.OKAY = "Okay"
        _G.CANCEL = "Cancel"
        _G.tinsert = table.insert
        _G.unpack = table.unpack
        _G.strtrim = function(text)
            return (text or ""):match("^%s*(.-)%s*$")
        end
        _G.IsControlKeyDown = function()
            return controlDown
        end
        _G.C_Timer = {
            After = function(_, callback)
                callback()
            end,
        }
        _G.GameFontHighlight = {}
        _G.GameFontHighlightLarge = {}
        _G.GameFontNormal = {}
        _G.GameFontNormalLarge = {}
        _G.CreateFrame = function(_, name, parent, template)
            local frame = makeDialogFrame(name)
            frame.__template = template
            if name then
                frames[name] = frame
            end
            if parent and parent._children then
                parent._children[#parent._children + 1] = frame
            end
            if template == "ScrollingEditBoxTemplate" then
                frame.ScrollBox = { EditBox = makeDialogFrame() }
            end
            return frame
        end
    end

    local function loadDialogs()
        installDialogGlobals()
        ns = {
            Addon = {},
            DebugAssert = function() end,
            GetGlobalConfig = function()
                return { releasePopupSeenVersion = nil }
            end,
            ImportExport = {},
            Print = function(message)
                printed[#printed + 1] = message
            end,
        }
        mod = ns.Addon
        mod.ConfirmReloadUI = function(_, message, onAccept)
            reloadConfirm = { message = message, onAccept = onAccept }
        end
        mod.ChatCommand = function() end

        TestHelpers.LoadLiveConstants(ns)
        TestHelpers.LoadChunk("UI/Dialogs.lua", "Unable to load UI/Dialogs.lua")(nil, ns)
    end

    local function findButton(frame, text)
        for _, child in ipairs(frame._children or {}) do
            if child:GetText() == text then
                return child
            end
        end
    end

    before_each(function()
        loadDialogs()
    end)

    it("ShowConfirmDialog creates, reuses, updates, and forwards callbacks", function()
        local accepted, cancelled
        mod:ShowConfirmDialog("ECM_TEST_CONFIRM", "First", "Do it", "Stop", function()
            accepted = true
        end, function()
            cancelled = true
        end)

        local dialog = assert(_G.StaticPopupDialogs.ECM_TEST_CONFIRM)
        assert.are.equal("First", dialog.text)
        assert.are.equal("Do it", dialog.button1)
        assert.are.equal("Stop", dialog.button2)
        assert.are.equal("ECM_TEST_CONFIRM", _G.StaticPopupDialogs._lastShow.name)

        dialog.OnAccept(nil, _G.StaticPopupDialogs._lastShow.data)
        dialog.OnCancel(nil, _G.StaticPopupDialogs._lastShow.data)
        assert.is_true(accepted)
        assert.is_true(cancelled)

        mod:ShowConfirmDialog("ECM_TEST_CONFIRM", "Second", "Proceed", "Don't proceed")
        assert.are.equal(dialog, _G.StaticPopupDialogs.ECM_TEST_CONFIRM)
        assert.are.equal("Second", dialog.text)
        assert.are.equal("Proceed", dialog.button1)
        assert.are.equal("Don't proceed", dialog.button2)
    end)

    it("ShowExportDialog rejects empty strings and copy-closes populated exports", function()
        mod:ShowExportDialog("")
        assert.are.same({ ns.L["INVALID_EXPORT_STRING"] }, printed)
        assert.is_nil(frames.ECMExportFrame)

        mod:ShowExportDialog("export-payload")
        local frame = assert(frames.ECMExportFrame)
        local editBox = frame.Scroll.ScrollBox.EditBox
        assert.are.equal("export-payload", editBox:GetText())
        assert.is_true(editBox:IsTextHighlighted())
        assert.is_true(editBox:HasFocus())

        controlDown = true
        editBox:GetScript("OnKeyDown")(editBox, "C")

        assert.is_false(frame:IsShown())
        assert.are.equal(ns.L["IMPORT_COPIED"], printed[#printed])
    end)

    it("ShowCopyTextDialog ignores empty text and reuses the copy frame with updated titles", function()
        mod:ShowCopyTextDialog("")
        assert.is_nil(frames.ECMCopyTextFrame)

        mod:ShowCopyTextDialog("https://example.test")
        local frame = assert(frames.ECMCopyTextFrame)
        assert.are.equal(ns.L["COPY_LINK"], frame.title:GetText())
        assert.are.equal("https://example.test", frame.Scroll.ScrollBox.EditBox:GetText())

        mod:ShowCopyTextDialog("https://example.test/next", "Docs")
        assert.are.equal(frame, frames.ECMCopyTextFrame)
        assert.are.equal("Docs", frame.title:GetText())
        assert.are.equal("https://example.test/next", frame.Scroll.ScrollBox.EditBox:GetText())
    end)

    it("ShowMigrationLogDialog restores edits in its read-only text box", function()
        mod:ShowMigrationLogDialog("original log")
        local frame = assert(frames.ECMMigrationLogFrame)
        local editBox = frame.Scroll.ScrollBox.EditBox

        editBox:SetText("mutated log")

        assert.are.equal("original log", editBox:GetText())
    end)

    it("ShowImportDialog handles empty and invalid imports without applying data", function()
        local validateCalls = 0
        ns.ImportExport.ValidateImportString = function()
            validateCalls = validateCalls + 1
            return nil, "bad payload"
        end
        ns.ImportExport.ApplyImportData = function()
            error("unexpected apply")
        end

        mod:ShowImportDialog()
        local frame = assert(frames.ECMImportFrame)
        local editBox = frame.Scroll.ScrollBox.EditBox
        local okButton = assert(findButton(frame, "Okay"))

        okButton:GetScript("OnClick")(okButton)
        assert.are.equal(ns.L["IMPORT_CANCELLED"], printed[#printed])
        assert.are.equal(0, validateCalls)

        editBox:SetText("not valid")
        okButton:GetScript("OnClick")(okButton)
        assert.are.equal(1, validateCalls)
        assert.are.equal(string.format(ns.L["IMPORT_FAILED"], "bad payload"), printed[#printed])
        assert.is_true(frame:IsShown())
    end)

    it("ShowImportDialog confirms valid imports and reports apply failures", function()
        local appliedData
        local importData = { metadata = { addonVersion = "1.2.3" } }
        ns.ImportExport.ValidateImportString = function()
            return importData
        end
        ns.ImportExport.ApplyImportData = function(data)
            appliedData = data
            return false, "apply broke"
        end

        mod:ShowImportDialog()
        local frame = assert(frames.ECMImportFrame)
        frame.Scroll.ScrollBox.EditBox:SetText("valid")
        assert(findButton(frame, "Okay")):GetScript("OnClick")()

        assert.is_false(frame:IsShown())
        assert.are.equal(string.format(ns.L["IMPORT_CONFIRM"], "1.2.3"), reloadConfirm.message)

        reloadConfirm.onAccept()

        assert.are.equal(importData, appliedData)
        assert.are.equal(string.format(ns.L["IMPORT_APPLY_FAILED"], "apply broke"), printed[#printed])
    end)
end)
