-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("ItemIcons", function()
    local originalGlobals

    local CAPTURED_GLOBALS = {
        "ECM",
        "EditModeManagerFrame",
        "UtilityCooldownViewer",
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

        function mod:ThrottledUpdateLayout() end

        function mod:UnregisterAllEvents() end

        function mod:UpdateLayout() end

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

describe("ItemIcons real source", function()
    local originalGlobals
    local ItemIcons
    local ns
    local createdCooldowns

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "ECM",
            "EditModeManagerFrame",
            "UtilityCooldownViewer",
            "UIParent",
            "CreateFrame",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    local function makeHookableFrame(shown)
        local frame = TestHelpers.makeFrame({ shown = shown })
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

    before_each(function()
        createdCooldowns = {}
        _G.ECM = {
            Log = function() end,
            UnregisterFrame = function() end,
            FrameMixin = {
                ShouldShow = function()
                    return true
                end,
            },
        }
        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
        _G.UIParent = TestHelpers.makeFrame({ name = "UIParent" })
        _G.EditModeManagerFrame = makeHookableFrame(false)
        _G.UtilityCooldownViewer = makeHookableFrame(true)
        _G.CreateFrame = function(frameType)
            local frame = TestHelpers.makeFrame({ shown = true })
            frame.SetFrameStrata = function() end
            frame.SetSize = function(self, width, height)
                self:SetWidth(width)
                self:SetHeight(height)
            end
            frame.CreateTexture = function()
                local texture = TestHelpers.makeTexture()
                texture.SetPoint = function() end
                texture.SetSize = function() end
                texture.SetAtlas = function() end
                texture.AddMaskTexture = function() end
                texture.Hide = function(self)
                    self.__hidden = true
                end
                return texture
            end
            frame.CreateMaskTexture = function()
                local texture = TestHelpers.makeTexture()
                texture.SetAtlas = function() end
                texture.SetPoint = function() end
                texture.SetSize = function() end
                return texture
            end
            frame.SetAllPoints = function() end
            frame.SetDrawEdge = function() end
            frame.SetDrawSwipe = function() end
            frame.SetHideCountdownNumbers = function() end
            frame.SetSwipeTexture = function() end
            frame.SetEdgeTexture = function() end
            frame.Clear = function(self)
                self.__cleared = true
            end
            frame.SetCooldown = function(self, start, duration)
                self.__cooldown = { start, duration }
            end
            frame.GetRegions = function()
                return
            end
            if frameType == "Cooldown" then
                createdCooldowns[#createdCooldowns + 1] = frame
            end
            return frame
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

        TestHelpers.LoadChunk("Modules/ItemIcons.lua", "Unable to load Modules/ItemIcons.lua")(nil, ns)
        ItemIcons = assert(ns.Addon.ItemIcons, "ItemIcons module did not initialize")
        function ItemIcons:IsEnabled()
            return true
        end
    end)

    it("requires the utility viewer to be visible in ShouldShow", function()
        assert.is_true(ItemIcons:ShouldShow())

        UtilityCooldownViewer:Hide()
        assert.is_false(ItemIcons:ShouldShow())
    end)

    it("only triggers layout updates for trinket slot equipment changes", function()
        local reasons = {}
        function ItemIcons:ThrottledUpdateLayout(reason)
            reasons[#reasons + 1] = reason
        end

        ItemIcons:OnPlayerEquipmentChanged(nil, 1)
        ItemIcons:OnPlayerEquipmentChanged(nil, ECM.Constants.TRINKET_SLOT_1)
        ItemIcons:OnPlayerEquipmentChanged(nil, ECM.Constants.TRINKET_SLOT_2)

        assert.same({ "OnPlayerEquipmentChanged", "OnPlayerEquipmentChanged" }, reasons)
    end)

    it("hooks edit mode only once", function()
        ItemIcons:HookEditMode()
        ItemIcons:HookEditMode()

        assert.is_true(ItemIcons._editModeHooked)
        assert.are.equal(1, EditModeManagerFrame:GetHookCount("OnShow"))
        assert.are.equal(1, EditModeManagerFrame:GetHookCount("OnHide"))
    end)

    it("hooks the utility viewer only once", function()
        ItemIcons:HookUtilityViewer()
        ItemIcons:HookUtilityViewer()

        assert.is_true(ItemIcons._viewerHooked)
        assert.are.equal(1, UtilityCooldownViewer:GetHookCount("OnShow"))
        assert.are.equal(1, UtilityCooldownViewer:GetHookCount("OnHide"))
        assert.are.equal(1, UtilityCooldownViewer:GetHookCount("OnSizeChanged"))
    end)

    it("preallocates the icon pool in CreateFrame", function()
        local frame = ItemIcons:CreateFrame()

        assert.are.equal(ECM.Constants.ITEM_ICONS_MAX, #frame._iconPool)
        assert.are.equal(ECM.Constants.DEFAULT_ITEM_ICON_SIZE, frame._iconPool[1]:GetWidth())
        assert.are.equal(ECM.Constants.ITEM_ICONS_MAX, #createdCooldowns)
    end)

    it("only refreshes bag cooldowns when the frame exists", function()
        local reasons = {}
        function ItemIcons:ThrottledRefresh(reason)
            reasons[#reasons + 1] = reason
        end

        ItemIcons:OnBagUpdateCooldown()
        ItemIcons.InnerFrame = TestHelpers.makeFrame({ shown = true })
        ItemIcons:OnBagUpdateCooldown()

        assert.same({ "OnBagUpdateCooldown" }, reasons)
    end)

    it("edit mode callbacks toggle state and defer layout", function()
        local reasons = {}
        ItemIcons.InnerFrame = TestHelpers.makeFrame({ shown = true })
        function ItemIcons:ThrottledUpdateLayout(reason)
            reasons[#reasons + 1] = reason
        end

        ItemIcons:HookEditMode()
        EditModeManagerFrame._hooks.OnShow[1]()
        EditModeManagerFrame._hooks.OnHide[1]()

        assert.is_false(ItemIcons.InnerFrame:IsShown())
        assert.is_false(ItemIcons._isEditModeActive)
        assert.same({ "EnterEditMode", "ExitEditMode" }, reasons)
    end)

    it("utility viewer callbacks hide the frame and defer layout", function()
        local reasons = {}
        ItemIcons.InnerFrame = TestHelpers.makeFrame({ shown = true })
        function ItemIcons:ThrottledUpdateLayout(reason)
            reasons[#reasons + 1] = reason
        end

        ItemIcons:HookUtilityViewer()
        UtilityCooldownViewer._hooks.OnShow[1]()
        UtilityCooldownViewer._hooks.OnHide[1]()
        UtilityCooldownViewer._hooks.OnSizeChanged[1]()

        assert.is_false(ItemIcons.InnerFrame:IsShown())
        assert.same({ "OnShow", "OnHide", "OnSizeChanged" }, reasons)
    end)
end)
