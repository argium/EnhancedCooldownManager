-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("ItemIcons", function()
    local originalGlobals

    local CAPTURED_GLOBALS = {
        "ECM", "EditModeManagerFrame", "UtilityCooldownViewer",
    }

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals(CAPTURED_GLOBALS)
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    local function makeHookableFrame(shown)
        local frame = TestHelpers.makeFrame({ shown = shown })
        frame._hookCounts = {}

        function frame:HookScript(scriptName)
            self._hookCounts[scriptName] = (self._hookCounts[scriptName] or 0) + 1
        end

        function frame:GetHookCount(scriptName)
            return self._hookCounts[scriptName] or 0
        end

        return frame
    end

    local function makeItemIcons()
        local mod = {
            Name = "ItemIcons",
            InnerFrame = TestHelpers.makeFrame({ shown = true }),
            _layoutRetryCount = 2,
            _layoutRetryPending = true,
            _viewerOriginalPoint = { "TOP" },
            _viewerHooked = nil,
            _editModeHooked = nil,
        }

        function mod:IsEnabled()
            return true
        end

        function mod:ThrottledUpdateLayout()
        end

        function mod:UnregisterAllEvents()
        end

        function mod:UpdateLayout()
        end

        function mod:HookEditMode()
            local editModeManager = _G.EditModeManagerFrame
            if not editModeManager or self._editModeHooked then
                return
            end

            self._editModeHooked = true
            self._isEditModeActive = editModeManager:IsShown()

            editModeManager:HookScript("OnShow", function()
                self._isEditModeActive = true
                if self.InnerFrame then
                    self.InnerFrame:Hide()
                end
                if self:IsEnabled() then
                    self:ThrottledUpdateLayout("EnterEditMode")
                end
            end)

            editModeManager:HookScript("OnHide", function()
                self._isEditModeActive = false
                if self:IsEnabled() then
                    self:ThrottledUpdateLayout("ExitEditMode")
                end
            end)
        end

        function mod:HookUtilityViewer()
            local utilityViewer = _G.UtilityCooldownViewer
            if not utilityViewer or self._viewerHooked then
                return
            end

            self._viewerHooked = true

            utilityViewer:HookScript("OnShow", function()
                self:ThrottledUpdateLayout("OnShow")
            end)

            utilityViewer:HookScript("OnHide", function()
                if self.InnerFrame then
                    self.InnerFrame:Hide()
                end
                if self:IsEnabled() then
                    self:ThrottledUpdateLayout("OnHide")
                end
            end)

            utilityViewer:HookScript("OnSizeChanged", function()
                self:ThrottledUpdateLayout("OnSizeChanged")
            end)
        end

        function mod:OnDisable()
            self:UnregisterAllEvents()
            self:UpdateLayout("OnDisable")

            ECM.UnregisterFrame(self)

            self._viewerOriginalPoint = nil
            self._isEditModeActive = nil
            self._layoutRetryPending = nil
            self._layoutRetryCount = 0
        end

        return mod
    end

    before_each(function()
        _G.ECM = {
            UnregisterFrame = function() end,
        }
        _G.EditModeManagerFrame = makeHookableFrame(false)
        _G.UtilityCooldownViewer = makeHookableFrame(true)
    end)

    describe("hook lifecycle", function()
        it("keeps hook guards set across disable cycles", function()
            local mod = makeItemIcons()

            mod:HookEditMode()
            mod:HookUtilityViewer()

            assert.are.equal(1, EditModeManagerFrame:GetHookCount("OnShow"))
            assert.are.equal(1, EditModeManagerFrame:GetHookCount("OnHide"))
            assert.are.equal(1, UtilityCooldownViewer:GetHookCount("OnShow"))
            assert.are.equal(1, UtilityCooldownViewer:GetHookCount("OnHide"))
            assert.are.equal(1, UtilityCooldownViewer:GetHookCount("OnSizeChanged"))

            mod:OnDisable()
            mod:HookEditMode()
            mod:HookUtilityViewer()

            assert.is_true(mod._editModeHooked)
            assert.is_true(mod._viewerHooked)
            assert.are.equal(1, EditModeManagerFrame:GetHookCount("OnShow"))
            assert.are.equal(1, EditModeManagerFrame:GetHookCount("OnHide"))
            assert.are.equal(1, UtilityCooldownViewer:GetHookCount("OnShow"))
            assert.are.equal(1, UtilityCooldownViewer:GetHookCount("OnHide"))
            assert.are.equal(1, UtilityCooldownViewer:GetHookCount("OnSizeChanged"))
        end)
    end)
end)
