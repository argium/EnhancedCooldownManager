-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()
local EditModeManagerFrame
local UtilityCooldownViewer
local makeHookableFrame = TestHelpers.makeHookableFrame

describe("ItemIcons", function()
    local originalGlobals
    local ns

    local CAPTURED_GLOBALS = {
        "EditModeManagerFrame",
        "UtilityCooldownViewer",
    }

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals(CAPTURED_GLOBALS)
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

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
                    ns.Runtime.RequestLayout("ItemIcons:EnterEditMode")
                end
            end)

            editModeManager:HookScript("OnHide", function()
                self._isEditModeActive = false
                if self:IsEnabled() then
                    ns.Runtime.RequestLayout("ItemIcons:ExitEditMode")
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
                ns.Runtime.RequestLayout("ItemIcons:OnShow")
            end)

            utilityViewer:HookScript("OnHide", function()
                if self.InnerFrame then
                    self.InnerFrame:Hide()
                end
                if self:IsEnabled() then
                    ns.Runtime.RequestLayout("ItemIcons:OnHide")
                end
            end)

            utilityViewer:HookScript("OnSizeChanged", function()
                ns.Runtime.RequestLayout("ItemIcons:OnSizeChanged")
            end)
        end

        function mod:OnDisable()
            self:UnregisterAllEvents()
            self:UpdateLayout("OnDisable")

            ns.Runtime.UnregisterFrame(self)

            self._viewerOriginalPoint = nil
            self._isEditModeActive = nil
            self._layoutRetryPending = nil
            self._layoutRetryCount = 0
        end

        return mod
    end

    before_each(function()
        ns = {
            Runtime = {
                UnregisterFrame = function() end,
                RequestLayout = function() end,
            },
        }
        EditModeManagerFrame = makeHookableFrame(false)
        UtilityCooldownViewer = makeHookableFrame(true)
        _G.EditModeManagerFrame = EditModeManagerFrame
        _G.UtilityCooldownViewer = UtilityCooldownViewer
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
    local registerFrameCalls
    local addMixinCalls
    local timerCallbacks
    local inventoryItemBySlot
    local inventorySpellByItem
    local inventoryTextureBySlot
    local inventoryCooldownBySlot
    local itemCounts
    local itemIconsByID
    local itemCooldownByID

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "EditModeManagerFrame",
            "UtilityCooldownViewer",
            "UIParent",
            "CreateFrame",
            "C_Timer",
            "GetInventoryItemID",
            "GetInventoryItemTexture",
            "GetInventoryItemCooldown",
            "C_Item",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        createdCooldowns = {}
        registerFrameCalls = 0
        addMixinCalls = 0
        timerCallbacks = {}
        inventoryItemBySlot = {}
        inventorySpellByItem = {}
        inventoryTextureBySlot = {}
        inventoryCooldownBySlot = {}
        itemCounts = {}
        itemIconsByID = {}
        itemCooldownByID = {}
        ns = {
            Log = function() end,
            BarMixin = {
                FrameProto = {
                    ShouldShow = function()
                        return true
                    end,
                    Refresh = function()
                        return true
                    end,
                },
                AddFrameMixin = function(target)
                    addMixinCalls = addMixinCalls + 1
                    target.EnsureFrame = target.EnsureFrame or function() end
                end,
            },
            Runtime = {
                RegisterFrame = function()
                    registerFrameCalls = registerFrameCalls + 1
                end,
                UnregisterFrame = function() end,
                RequestLayout = function() end,
            },
        }
        TestHelpers.LoadChunk("Constants.lua", "Unable to load Constants.lua")(nil, ns)
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")(nil, ns)
        _G.UIParent = TestHelpers.makeFrame({ name = "UIParent" })
        EditModeManagerFrame = makeHookableFrame(false)
        UtilityCooldownViewer = makeHookableFrame(true)
        _G.EditModeManagerFrame = EditModeManagerFrame
        _G.UtilityCooldownViewer = UtilityCooldownViewer
        _G.C_Timer = {
            After = function(_, callback)
                timerCallbacks[#timerCallbacks + 1] = callback
            end,
        }
        _G.GetInventoryItemID = function(_, slotId)
            return inventoryItemBySlot[slotId]
        end
        _G.GetInventoryItemTexture = function(_, slotId)
            return inventoryTextureBySlot[slotId]
        end
        _G.GetInventoryItemCooldown = function(_, slotId)
            local cooldown = inventoryCooldownBySlot[slotId] or { 0, 0, 0 }
            return cooldown[1], cooldown[2], cooldown[3]
        end
        _G.C_Item = {
            GetItemSpell = function(itemId)
                return nil, inventorySpellByItem[itemId]
            end,
            GetItemCount = function(itemId)
                return itemCounts[itemId] or 0
            end,
            GetItemIconByID = function(itemId)
                return itemIconsByID[itemId]
            end,
            GetItemCooldown = function(itemId)
                local cooldown = itemCooldownByID[itemId] or { 0, 0, false }
                return cooldown[1], cooldown[2], cooldown[3]
            end,
        }
        _G.CreateFrame = function(frameType)
            local frame = TestHelpers.makeFrame({ shown = true })
            frame.SetFrameStrata = function() end
            frame.SetSize = function(self, width, height)
                self:SetWidth(width)
                self:SetHeight(height)
            end
            frame.SetScale = function(self, scale)
                self.__scale = scale
            end
            frame.GetScale = function(self)
                return self.__scale or 1
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
            frame.__fontRegion = TestHelpers.makeRegion("FontString")
            frame.__fontRegion.SetFont = function(self, path, size, flags)
                self.__font = { path, size, flags }
            end
            frame.__fontRegion.GetFont = function(self)
                return unpack(self.__font or {})
            end
            frame.GetRegions = function(self)
                if frameType == "Cooldown" then
                    return self.__fontRegion
                end
                return
            end
            if frameType == "Cooldown" then
                createdCooldowns[#createdCooldowns + 1] = frame
            end
            return frame
        end

        ns.Addon = {
            NewModule = function(self, name)
                local module = { Name = name }
                self[name] = module
                return module
            end,
        }

        TestHelpers.LoadChunk("Modules/ItemIcons.lua", "Unable to load Modules/ItemIcons.lua")(nil, ns)
        ItemIcons = assert(ns.Addon.ItemIcons, "ItemIcons module did not initialize")
        function ItemIcons:IsEnabled()
            return true
        end
        function ItemIcons:ThrottledRefresh() end
    end)

    it("requires the utility viewer to be visible in ShouldShow", function()
        assert.is_true(ItemIcons:ShouldShow())

        UtilityCooldownViewer:Hide()
        assert.is_false(ItemIcons:ShouldShow())
    end)

    it("only triggers layout updates for trinket slot equipment changes", function()
        local reasons = {}
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end

        ItemIcons:OnPlayerEquipmentChanged(nil, 1)
        ItemIcons:OnPlayerEquipmentChanged(nil, ns.Constants.TRINKET_SLOT_1)
        ItemIcons:OnPlayerEquipmentChanged(nil, ns.Constants.TRINKET_SLOT_2)

        assert.same({ "ItemIcons:OnPlayerEquipmentChanged", "ItemIcons:OnPlayerEquipmentChanged" }, reasons)
    end)

    it("registered equipment callback drops LibEvent target and forwards slotId", function()
        local captured = {}
        function ItemIcons:RegisterEvent(event, cb)
            captured[event] = cb
        end
        function ItemIcons:UnregisterAllEvents() end
        function ItemIcons:EnsureFrame() end

        local origRegister = ns.Runtime.RegisterFrame
        ns.Runtime.RegisterFrame = function() end

        ItemIcons:OnEnable()

        ns.Runtime.RegisterFrame = origRegister

        local reasons = {}
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end

        -- LibEvent dispatches cb(target, event, ...wowArgs)
        local cb = assert(captured["PLAYER_EQUIPMENT_CHANGED"], "expected PLAYER_EQUIPMENT_CHANGED registration")
        cb(ItemIcons, "PLAYER_EQUIPMENT_CHANGED", ns.Constants.TRINKET_SLOT_1)
        assert.same({ "ItemIcons:OnPlayerEquipmentChanged" }, reasons)
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

        assert.are.equal(ns.Constants.ITEM_ICONS_MAX, #frame._iconPool)
        assert.are.equal(ns.Constants.DEFAULT_ITEM_ICON_SIZE, frame._iconPool[1]:GetWidth())
        assert.are.equal(ns.Constants.ITEM_ICONS_MAX, #createdCooldowns)
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
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end

        ItemIcons:HookEditMode()
        EditModeManagerFrame._hooks.OnShow[1]()
        EditModeManagerFrame._hooks.OnHide[1]()

        assert.is_false(ItemIcons.InnerFrame:IsShown())
        assert.is_false(ItemIcons._isEditModeActive)
        assert.same({ "ItemIcons:EnterEditMode", "ItemIcons:ExitEditMode" }, reasons)
    end)

    it("utility viewer callbacks hide the frame and defer layout", function()
        local reasons = {}
        ItemIcons.InnerFrame = TestHelpers.makeFrame({ shown = true })
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end

        ItemIcons:HookUtilityViewer()
        UtilityCooldownViewer._hooks.OnShow[1]()
        UtilityCooldownViewer._hooks.OnHide[1]()
        UtilityCooldownViewer._hooks.OnSizeChanged[1]()

        assert.is_false(ItemIcons.InnerFrame:IsShown())
        assert.same({ "ItemIcons:OnShow", "ItemIcons:OnHide", "ItemIcons:OnSizeChanged" }, reasons)
    end)

    it("returns false from UpdateLayout when the frame is missing or config is unavailable", function()
        ItemIcons.InnerFrame = nil
        assert.is_false(ItemIcons:UpdateLayout("test"))

        ItemIcons.InnerFrame = TestHelpers.makeFrame({ shown = true })
        ItemIcons.GetModuleConfig = function()
            return nil
        end
        assert.is_false(ItemIcons:UpdateLayout("test"))
    end)

    it("returns false from UpdateLayout during live edit mode and restores the viewer", function()
        ItemIcons.InnerFrame = TestHelpers.makeFrame({ shown = true })
        ItemIcons.GetModuleConfig = function()
            return { enabled = true }
        end
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 100, 50)
        ItemIcons._viewerOriginalPoint = { "CENTER", UIParent, "CENTER", 10, 20 }
        ItemIcons._isEditModeActive = nil
        EditModeManagerFrame:Show()

        assert.is_false(ItemIcons:UpdateLayout("test"))
        assert.is_false(ItemIcons.InnerFrame:IsShown())
        assert.is_nil(ItemIcons._viewerOriginalPoint)

        local point, relativeTo, relativePoint, x, y = UtilityCooldownViewer:GetPoint(1)
        assert.are.equal("CENTER", point)
        assert.are.equal(UIParent, relativeTo)
        assert.are.equal("CENTER", relativePoint)
        assert.are.equal(10, x)
        assert.are.equal(20, y)
    end)

    it("defers layout for delayed bag and world events", function()
        local reasons = {}
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end

        ItemIcons:OnBagUpdateDelayed()
        ItemIcons:OnPlayerEnteringWorld()

        assert.same({ "ItemIcons:OnBagUpdateDelayed", "ItemIcons:OnPlayerEnteringWorld" }, reasons)
    end)

    it("registers with the frame system and schedules initial hooks on enable", function()
        local reasons = {}
        function ItemIcons:RegisterEvent() end
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end

        ItemIcons:OnInitialize()
        ItemIcons:OnEnable()
        assert.are.equal(1, addMixinCalls)
        assert.are.equal(1, registerFrameCalls)
        assert.are.equal(1, #timerCallbacks)

        timerCallbacks[1]()

        assert.same({ "ItemIcons:OnEnable" }, reasons)
        assert.is_true(ItemIcons._editModeHooked)
        assert.is_true(ItemIcons._viewerHooked)
    end)

    it("lays out display items using utility viewer sizing and copies cooldown fonts", function()
        local utilityFontRegion = TestHelpers.makeRegion("FontString")
        utilityFontRegion.GetFont = function()
            return "Fonts\\FRIZQT__.TTF", 17, "OUTLINE"
        end
        local utilityCooldown = {
            GetRegions = function()
                return utilityFontRegion
            end,
        }
        local utilityFontChild = {
            Cooldown = utilityCooldown,
            IsShown = function()
                return false
            end,
        }
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function()
            return 12345
        end
        UtilityCooldownViewer.childXPadding = 6
        UtilityCooldownViewer.iconScale = 1.25
        UtilityCooldownViewer._children = { utilityFontChild, utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 100, 50)

        inventoryItemBySlot[ns.Constants.TRINKET_SLOT_1] = 101
        inventoryTextureBySlot[ns.Constants.TRINKET_SLOT_1] = "trinket-1"
        inventorySpellByItem[101] = 9001
        inventoryItemBySlot[ns.Constants.TRINKET_SLOT_2] = 102
        inventoryTextureBySlot[ns.Constants.TRINKET_SLOT_2] = "trinket-2"
        inventorySpellByItem[102] = 9002
        itemCounts[ns.Constants.COMBAT_POTIONS[1].itemID] = 3
        itemIconsByID[ns.Constants.COMBAT_POTIONS[1].itemID] = "combat-potion"
        itemCounts[ns.Constants.HEALTHSTONE_ITEM_ID] = 1
        itemIconsByID[ns.Constants.HEALTHSTONE_ITEM_ID] = "healthstone"

        ItemIcons.InnerFrame = ItemIcons:CreateFrame()
        ItemIcons.GetModuleConfig = function()
            return {
                showTrinket1 = true,
                showTrinket2 = true,
                showCombatPotion = true,
                showHealthPotion = false,
                showHealthstone = true,
            }
        end

        assert.is_true(ItemIcons:UpdateLayout("test"))
        assert.is_true(ItemIcons.InnerFrame:IsShown())
        assert.are.equal(1.25, ItemIcons.InnerFrame.__scale)
        assert.are.equal((4 * 18) + (3 * 6), ItemIcons.InnerFrame:GetWidth())
        assert.are.equal(18, ItemIcons.InnerFrame:GetHeight())
        assert.are.equal(101, ItemIcons.InnerFrame._iconPool[1].itemId)
        assert.are.equal(ns.Constants.TRINKET_SLOT_1, ItemIcons.InnerFrame._iconPool[1].slotId)
        assert.are.equal(102, ItemIcons.InnerFrame._iconPool[2].itemId)
        assert.are.equal(ns.Constants.TRINKET_SLOT_2, ItemIcons.InnerFrame._iconPool[2].slotId)
        assert.are.equal(ns.Constants.COMBAT_POTIONS[1].itemID, ItemIcons.InnerFrame._iconPool[3].itemId)
        assert.are.equal(ns.Constants.HEALTHSTONE_ITEM_ID, ItemIcons.InnerFrame._iconPool[4].itemId)
        assert.same(
            { "Fonts\\FRIZQT__.TTF", 17, "OUTLINE" },
            ItemIcons.InnerFrame._iconPool[1].Cooldown.__fontRegion.__font
        )

        local point, relativeTo, relativePoint, x, y = UtilityCooldownViewer:GetPoint(1)
        assert.are.equal("CENTER", point)
        assert.are.equal(UIParent, relativeTo)
        assert.are.equal("CENTER", relativePoint)
        assert.are.equal(40.75, x)
        assert.are.equal(50, y)
    end)

    it("uses GetItemFrames and isActive to detect icon size and anchor container", function()
        local activeFrame = TestHelpers.makeFrame({ shown = true, width = 22, height = 22 })
        activeFrame.isActive = true
        local inactiveFrame = TestHelpers.makeFrame({ shown = false, width = 22, height = 22 })
        inactiveFrame.isActive = false
        UtilityCooldownViewer.childXPadding = 4
        UtilityCooldownViewer.iconScale = 1.0
        UtilityCooldownViewer:SetWidth(22) -- 1 active icon, no stale space
        UtilityCooldownViewer.GetItemFrames = function()
            return { inactiveFrame, activeFrame }
        end
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 100, 0)

        itemCounts[ns.Constants.HEALTHSTONE_ITEM_ID] = 1
        itemIconsByID[ns.Constants.HEALTHSTONE_ITEM_ID] = "healthstone"

        ItemIcons.InnerFrame = ItemIcons:CreateFrame()
        ItemIcons.GetModuleConfig = function()
            return { showTrinket1 = false, showTrinket2 = false, showCombatPotion = false, showHealthPotion = false, showHealthstone = true }
        end

        assert.is_true(ItemIcons:UpdateLayout("test"))
        -- Icon size taken from active frame, not default
        assert.are.equal(22, ItemIcons.InnerFrame:GetWidth())
        -- Container anchors to the last active item frame, not the viewer
        local _, anchorFrame = ItemIcons.InnerFrame:GetPoint(1)
        assert.are.equal(activeFrame, anchorFrame)
        -- With no stale space: viewerOffsetX = (22 - 22 - 4 - 22) / 2 = -13, so x = 100 - 13 = 87
        local _, _, _, x = UtilityCooldownViewer:GetPoint(1)
        assert.are.equal(87, x)
    end)

    it("prefers demonic healthstone over the legacy healthstone", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function()
            return 1
        end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        itemCounts[ns.Constants.DEMONIC_HEALTHSTONE_ITEM_ID] = 1
        itemIconsByID[ns.Constants.DEMONIC_HEALTHSTONE_ITEM_ID] = "demonic-healthstone"
        itemCounts[ns.Constants.HEALTHSTONE_ITEM_ID] = 1
        itemIconsByID[ns.Constants.HEALTHSTONE_ITEM_ID] = "healthstone"

        ItemIcons.InnerFrame = ItemIcons:CreateFrame()
        ItemIcons.GetModuleConfig = function()
            return {
                showTrinket1 = false,
                showTrinket2 = false,
                showCombatPotion = false,
                showHealthPotion = false,
                showHealthstone = true,
            }
        end

        assert.is_true(ItemIcons:UpdateLayout("test"))
        assert.are.equal(ns.Constants.DEMONIC_HEALTHSTONE_ITEM_ID, ItemIcons.InnerFrame._iconPool[1].itemId)
    end)

    it("anchors container to last active item frame when viewer layout is stale", function()
        -- Viewer frame is wider than its single active icon (stale layout: 2-icon width).
        local staleFrame = TestHelpers.makeFrame({ shown = false, width = 22, height = 22 })
        staleFrame.isActive = false
        local activeFrame = TestHelpers.makeFrame({ shown = true, width = 22, height = 22 })
        activeFrame.isActive = true
        UtilityCooldownViewer.childXPadding = 2
        UtilityCooldownViewer.iconScale = 1.0
        UtilityCooldownViewer:SetWidth(46) -- stale: 2 * 22 + 2 spacing
        UtilityCooldownViewer.GetItemFrames = function()
            return { staleFrame, activeFrame }
        end
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 100, 0)

        inventoryItemBySlot[ns.Constants.TRINKET_SLOT_1] = 101
        inventoryTextureBySlot[ns.Constants.TRINKET_SLOT_1] = "trinket-1"
        inventorySpellByItem[101] = 9001

        ItemIcons.InnerFrame = ItemIcons:CreateFrame()
        ItemIcons.GetModuleConfig = function()
            return { showTrinket1 = true, showTrinket2 = false, showCombatPotion = false, showHealthPotion = false, showHealthstone = false }
        end

        assert.is_true(ItemIcons:UpdateLayout("test"))
        -- Container must anchor to activeFrame, not the viewer (which has stale/wider width)
        local _, anchorFrame = ItemIcons.InnerFrame:GetPoint(1)
        assert.are.equal(activeFrame, anchorFrame)
        -- Stale layout width is 46, with a single 22px icon and 2px padding on each side:
        -- (46 - 22 - 2 - 22) / 2 = 0 unused space, so the viewer's x-offset stays at its original 100.
        local _, _, _, x = UtilityCooldownViewer:GetPoint(1)
        assert.are.equal(100, x) -- x should remain at the original SetPoint x-position
    end)

    it("restores the utility viewer and hides the frame when no items are available", function()
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 100, 50)
        ItemIcons.InnerFrame = ItemIcons:CreateFrame()
        ItemIcons.GetModuleConfig = function()
            return {
                showTrinket1 = true,
                showTrinket2 = true,
                showCombatPotion = true,
                showHealthPotion = true,
                showHealthstone = true,
            }
        end
        ItemIcons._viewerOriginalPoint = { "CENTER", UIParent, "CENTER", 10, 20 }

        assert.is_false(ItemIcons:UpdateLayout("test"))
        assert.is_false(ItemIcons.InnerFrame:IsShown())

        local point, relativeTo, relativePoint, x, y = UtilityCooldownViewer:GetPoint(1)
        assert.are.equal("CENTER", point)
        assert.are.equal(UIParent, relativeTo)
        assert.are.equal("CENTER", relativePoint)
        assert.are.equal(10, x)
        assert.are.equal(20, y)
    end)

    it("applies cooldowns during UpdateLayout so throttled refresh cannot skip them", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function()
            return 1
        end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        itemCounts[ns.Constants.HEALTHSTONE_ITEM_ID] = 1
        itemIconsByID[ns.Constants.HEALTHSTONE_ITEM_ID] = "healthstone"
        -- Healthstone has an active shared cooldown (e.g. health potion just used)
        itemCooldownByID[ns.Constants.HEALTHSTONE_ITEM_ID] = { 100, 60, true }

        ItemIcons.InnerFrame = ItemIcons:CreateFrame()
        ItemIcons.GetModuleConfig = function()
            return {
                showTrinket1 = false,
                showTrinket2 = false,
                showCombatPotion = false,
                showHealthPotion = false,
                showHealthstone = true,
            }
        end

        assert.is_true(ItemIcons:UpdateLayout("test"))
        -- Cooldown must be set directly in UpdateLayout, not deferred to ThrottledRefresh
        assert.same({ 100, 60 }, ItemIcons.InnerFrame._iconPool[1].Cooldown.__cooldown)
    end)

    it("refreshes cooldowns for visible trinket and bag icons", function()
        local frame = ItemIcons:CreateFrame()
        frame._iconPool[1]:Show()
        frame._iconPool[1].slotId = ns.Constants.TRINKET_SLOT_1
        frame._iconPool[2]:Show()
        frame._iconPool[2].itemId = 5001
        frame._iconPool[3]:Show()
        frame._iconPool[3].itemId = 5002
        ItemIcons.InnerFrame = frame

        inventoryCooldownBySlot[ns.Constants.TRINKET_SLOT_1] = { 10, 30, 1 }
        itemCooldownByID[5001] = { 20, 40, true }
        itemCooldownByID[5002] = { 0, 0, false }

        assert.is_true(ItemIcons:Refresh("test"))
        assert.same({ 10, 30 }, frame._iconPool[1].Cooldown.__cooldown)
        assert.same({ 20, 40 }, frame._iconPool[2].Cooldown.__cooldown)
        assert.is_true(frame._iconPool[3].Cooldown.__cleared)
    end)

    it("cleans up real module state on disable", function()
        local updateReasons = {}
        ItemIcons._viewerOriginalPoint = { "TOP", UIParent, "TOP", 0, 0 }
        ItemIcons._isEditModeActive = true
        function ItemIcons:UnregisterAllEvents()
            self._eventsUnregistered = true
        end
        function ItemIcons:UpdateLayout(reason)
            updateReasons[#updateReasons + 1] = reason
            return false
        end

        ItemIcons:OnDisable()

        assert.is_true(ItemIcons._eventsUnregistered)
        assert.same({ "OnDisable" }, updateReasons)
        assert.is_nil(ItemIcons._viewerOriginalPoint)
        assert.is_nil(ItemIcons._isEditModeActive)
    end)
end)
