-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()
local EditModeManagerFrame
local UtilityCooldownViewer
local EssentialCooldownViewer
local makeHookableFrame = TestHelpers.makeHookableFrame

describe("ExtraIcons", function()
    local originalGlobals
    local ns

    local CAPTURED_GLOBALS = {
        "EditModeManagerFrame",
        "UtilityCooldownViewer",
        "EssentialCooldownViewer",
    }

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals(CAPTURED_GLOBALS)
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    local function makeExtraIcons()
        local mod = {
            Name = "ExtraIcons",
            _viewers = {
                utility = {
                    container = TestHelpers.makeFrame({ shown = true }),
                    iconPool = {},
                    originalPoint = nil,
                    hooked = false,
                },
                main = {
                    container = TestHelpers.makeFrame({ shown = true }),
                    iconPool = {},
                    originalPoint = nil,
                    hooked = false,
                },
            },
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
                if self._viewers then
                    for _, vs in pairs(self._viewers) do
                        vs.container:Hide()
                    end
                end
                if self:IsEnabled() then
                    ns.Runtime.RequestLayout("ExtraIcons:EnterEditMode")
                end
            end)

            editModeManager:HookScript("OnHide", function()
                self._isEditModeActive = false
                if self:IsEnabled() then
                    ns.Runtime.RequestLayout("ExtraIcons:ExitEditMode")
                end
            end)
        end

        function mod:_hookViewer(viewerKey)
            local registry = {
                utility = { blizzFrameKey = "UtilityCooldownViewer" },
                main    = { blizzFrameKey = "EssentialCooldownViewer" },
            }
            local reg = registry[viewerKey]
            local blizzFrame = _G[reg.blizzFrameKey]
            local vs = self._viewers and self._viewers[viewerKey]
            if not blizzFrame or not vs or vs.hooked then
                return
            end
            vs.hooked = true

            blizzFrame:HookScript("OnShow", function()
                ns.Runtime.RequestLayout("ExtraIcons:OnShow")
            end)

            blizzFrame:HookScript("OnHide", function()
                if vs.container then
                    vs.container:Hide()
                end
                if self:IsEnabled() then
                    ns.Runtime.RequestLayout("ExtraIcons:OnHide")
                end
            end)

            blizzFrame:HookScript("OnSizeChanged", function()
                ns.Runtime.RequestLayout("ExtraIcons:OnSizeChanged")
            end)
        end

        function mod:OnDisable()
            self:UnregisterAllEvents()
            self:UpdateLayout("OnDisable")

            ns.Runtime.UnregisterFrame(self)

            if self._viewers then
                for _, vs in pairs(self._viewers) do
                    vs.originalPoint = nil
                end
            end
            self._isEditModeActive = nil
            self._trackedEquipSlots = nil
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
        EssentialCooldownViewer = makeHookableFrame(true)
        _G.EditModeManagerFrame = EditModeManagerFrame
        _G.UtilityCooldownViewer = UtilityCooldownViewer
        _G.EssentialCooldownViewer = EssentialCooldownViewer
    end)

    describe("hook lifecycle", function()
        it("keeps hook guards set across disable cycles", function()
            local mod = makeExtraIcons()

            mod:HookEditMode()
            mod:_hookViewer("utility")

            assert.are.equal(1, EditModeManagerFrame:GetHookCount("OnShow"))
            assert.are.equal(1, EditModeManagerFrame:GetHookCount("OnHide"))
            assert.are.equal(1, UtilityCooldownViewer:GetHookCount("OnShow"))
            assert.are.equal(1, UtilityCooldownViewer:GetHookCount("OnHide"))
            assert.are.equal(1, UtilityCooldownViewer:GetHookCount("OnSizeChanged"))

            mod:OnDisable()
            mod:HookEditMode()
            mod:_hookViewer("utility")

            assert.is_true(mod._editModeHooked)
            assert.is_true(mod._viewers.utility.hooked)
            assert.are.equal(1, EditModeManagerFrame:GetHookCount("OnShow"))
            assert.are.equal(1, EditModeManagerFrame:GetHookCount("OnHide"))
            assert.are.equal(1, UtilityCooldownViewer:GetHookCount("OnShow"))
            assert.are.equal(1, UtilityCooldownViewer:GetHookCount("OnHide"))
            assert.are.equal(1, UtilityCooldownViewer:GetHookCount("OnSizeChanged"))
        end)
    end)
end)

describe("ExtraIcons real source", function()
    local originalGlobals
    local ExtraIcons
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
    local knownSpells
    local spellTextures
    local spellCooldowns
    local spellCooldownInfos
    local spellCharges
    local applyFontCalls
    local globalConfig
    local ratedMap
    local inInstance
    local instanceType
    local errorLogs
    local inaccessibleTables
    local COMBAT_POTION_ID = 245898
    local HEALTH_POTION_ID = 241305
    local DEMONIC_HEALTHSTONE_ID = 224464
    local HEALTHSTONE_ID = 5512

    local function installCooldownViewerItemFrameStub(viewer)
        function viewer:GetItemFrames()
            for _, child in ipairs(self._children or {}) do
                if child.isActive == nil and child.IsShown then
                    child.isActive = child:IsShown()
                end
            end
            return self._children
        end
    end

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "EditModeManagerFrame",
            "UtilityCooldownViewer",
            "EssentialCooldownViewer",
            "UIParent",
            "CreateFrame",
            "C_Timer",
            "C_Spell",
            "C_SpellBook",
            "GetInventoryItemID",
            "GetInventoryItemTexture",
            "GetInventoryItemCooldown",
            "C_Item",
            "C_PvP",
            "canaccesstable",
            "issecretvalue",
            "ipairs",
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
        knownSpells = {}
        spellTextures = {}
        spellCooldowns = {}
        spellCooldownInfos = {}
        spellCharges = {}
        applyFontCalls = {}
        globalConfig = { font = "Global Font", fontSize = 11, fontOutline = "OUTLINE", fontShadow = false }
        ratedMap = false
        inInstance = false
        instanceType = "none"
        errorLogs = {}
        inaccessibleTables = {}
        _G.C_SpellBook = {
            IsSpellKnown = function(spellId)
                return knownSpells[spellId] or false
            end,
        }
        ns = {
            Log = function() end,
            ErrorLogOnce = function(module, key, message, data)
                errorLogs[#errorLogs + 1] = { module = module, key = key, message = message, data = data }
            end,
            IsDebugEnabled = function() return false end,
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
            GetGlobalConfig = function()
                return globalConfig
            end,
            -- ECM.lua is not loaded in this isolated source spec.
            GetFrameValue = function(frame, methodName)
                if not frame or type(frame[methodName]) ~= "function" then
                    return nil
                end
                local ok, value = pcall(frame[methodName], frame)
                if ok then return value end
                return nil
            end,
        }
        TestHelpers.LoadChunk("Constants.lua", "Unable to load Constants.lua")(nil, ns)
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")(nil, ns)
        _G.issecretvalue = function() return false end
        TestHelpers.LoadChunk("FrameUtil.lua", "Unable to load FrameUtil.lua")(nil, ns)
        ns.FrameUtil.ApplyFont = function(fontString, appliedGlobalConfig, moduleConfig)
            applyFontCalls[#applyFontCalls + 1] = {
                fontString = fontString,
                globalConfig = appliedGlobalConfig,
                moduleConfig = moduleConfig,
            }
        end
        _G.UIParent = TestHelpers.makeFrame({ name = "UIParent" })
        EditModeManagerFrame = TestHelpers.makeHookableFrame(false)
        UtilityCooldownViewer = TestHelpers.makeHookableFrame(true)
        EssentialCooldownViewer = TestHelpers.makeHookableFrame(true)
        installCooldownViewerItemFrameStub(UtilityCooldownViewer)
        installCooldownViewerItemFrameStub(EssentialCooldownViewer)
        _G.EditModeManagerFrame = EditModeManagerFrame
        _G.UtilityCooldownViewer = UtilityCooldownViewer
        _G.EssentialCooldownViewer = EssentialCooldownViewer
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
        _G.C_Spell = {
            GetSpellTexture = function(spellId)
                return spellTextures[spellId]
            end,
            GetSpellCooldown = function(spellId)
                return spellCooldownInfos[spellId]
            end,
            GetSpellCooldownDuration = function(spellId)
                return spellCooldowns[spellId]
            end,
            GetSpellCharges = function(spellId)
                return spellCharges[spellId]
            end,
            GetSpellChargeDuration = function(spellId)
                return spellCooldowns[spellId]
            end,
        }
        _G.C_PvP = {
            IsRatedMap = function()
                return ratedMap
            end,
        }
        _G.IsInInstance = function()
            return inInstance, instanceType
        end
        _G.canaccesstable = function(value)
            return inaccessibleTables[value] ~= true
        end
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
                texture.SetSize = function(self, width, height)
                    self.__width = width
                    self.__height = height
                end
                texture.GetWidth = function(self)
                    return self.__width
                end
                texture.GetHeight = function(self)
                    return self.__height
                end
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
                texture.SetSize = function(self, width, height)
                    self.__width = width
                    self.__height = height
                end
                return texture
            end
            frame.CreateFontString = function(_, name, drawLayer, template)
                local fontString = TestHelpers.makeRegion("FontString")
                fontString.__name = name
                fontString.__drawLayer = drawLayer
                fontString.__template = template
                fontString.SetPoint = function() end
                fontString.SetJustifyH = function() end
                fontString.SetJustifyV = function() end
                fontString.SetText = function(self, text)
                    self.__text = text
                end
                fontString.Show = function(self)
                    self.__shown = true
                end
                fontString.Hide = function(self)
                    self.__shown = false
                end
                fontString.IsShown = function(self)
                    return self.__shown == true
                end
                return fontString
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
            frame.SetCooldownFromDurationObject = function(self, durObj)
                self.__durObj = durObj
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

        _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

        TestHelpers.LoadChunk("Modules/ExtraIcons.lua", "Unable to load Modules/ExtraIcons.lua")(nil, ns)
        ExtraIcons = assert(ns.Addon.ExtraIcons, "ExtraIcons module did not initialize")
        ExtraIcons.GetGlobalConfig = ns.GetGlobalConfig
        function ExtraIcons:IsEnabled()
            return true
        end
        function ExtraIcons:ThrottledRefresh() end
    end)

    local function makeViewersConfig(utilityStacks, mainStacks, itemStacks)
        return {
            itemStacks = itemStacks or {
                nextId = 1,
                order = { "combatPotions", "healthPotions", "healthstones" },
                byId = {
                    combatPotions = {
                        name = "Combat Potions",
                        hideInRatedPvp = true,
                        ids = { { itemID = COMBAT_POTION_ID } },
                    },
                    healthPotions = {
                        name = "Health Potions",
                        hideInRatedPvp = true,
                        ids = { { itemID = HEALTH_POTION_ID } },
                    },
                    healthstones = {
                        name = "Healthstones",
                        hideInRatedPvp = false,
                        ids = { { itemID = DEMONIC_HEALTHSTONE_ID }, { itemID = HEALTHSTONE_ID } },
                    },
                },
            },
            viewers = {
                utility = utilityStacks or {},
                main = mainStacks or {},
            },
        }
    end

    it("requires at least one viewer to be visible in ShouldShow", function()
        assert.is_true(ExtraIcons:ShouldShow())

        UtilityCooldownViewer:Hide()
        assert.is_true(ExtraIcons:ShouldShow())

        EssentialCooldownViewer:Hide()
        assert.is_false(ExtraIcons:ShouldShow())
    end)

    it("only triggers layout for tracked equipment slot changes", function()
        local reasons = {}
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end

        ExtraIcons._trackedEquipSlots = { [13] = true, [14] = true }

        ExtraIcons:OnPlayerEquipmentChanged(1)
        ExtraIcons:OnPlayerEquipmentChanged(13)
        ExtraIcons:OnPlayerEquipmentChanged(14)

        assert.same({ "ExtraIcons:OnPlayerEquipmentChanged", "ExtraIcons:OnPlayerEquipmentChanged" }, reasons)
    end)

    it("rebuilds tracked equipment slots from config", function()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig(
                { { stackKey = "trinket1" }, { kind = "itemStack", itemStackId = "healthstones" } },
                { { stackKey = "trinket2" } }
            )
        end

        ExtraIcons:_rebuildTrackedSlots()

        assert.is_true(ExtraIcons._trackedEquipSlots[13])
        assert.is_true(ExtraIcons._trackedEquipSlots[14])
        assert.is_nil(ExtraIcons._trackedEquipSlots[1])
    end)

    it("ignores disabled entries when rebuilding tracked equipment slots", function()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig(
                { { stackKey = "trinket1", disabled = true } },
                { { stackKey = "trinket2" } }
            )
        end

        ExtraIcons:_rebuildTrackedSlots()

        assert.is_nil(ExtraIcons._trackedEquipSlots[13])
        assert.is_true(ExtraIcons._trackedEquipSlots[14])
    end)

    it("hooks edit mode only once", function()
        ExtraIcons:HookEditMode()
        ExtraIcons:HookEditMode()

        assert.is_true(ExtraIcons._editModeHooked)
        assert.are.equal(1, EditModeManagerFrame:GetHookCount("OnShow"))
        assert.are.equal(1, EditModeManagerFrame:GetHookCount("OnHide"))
    end)

    it("hooks viewers only once", function()
        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()

        local utilityHookConfig = { key = "utility", blizzKey = "UtilityCooldownViewer" }
        ExtraIcons:_hookViewer(utilityHookConfig)
        ExtraIcons:_hookViewer(utilityHookConfig)

        assert.is_true(ExtraIcons._viewers.utility.hooked)
        assert.are.equal(1, UtilityCooldownViewer:GetHookCount("OnShow"))
        assert.are.equal(1, UtilityCooldownViewer:GetHookCount("OnHide"))
        assert.are.equal(1, UtilityCooldownViewer:GetHookCount("OnSizeChanged"))
    end)

    it("creates on-demand icon pool when needed", function()
        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        local vs = ExtraIcons._viewers.utility
        assert.are.equal(0, #vs.iconPool)

        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function() return 1 end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        itemCounts[HEALTHSTONE_ID] = 1
        itemIconsByID[HEALTHSTONE_ID] = "healthstone"

        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { kind = "itemStack", itemStackId = "healthstones" } })
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        assert.is_true(#vs.iconPool >= 1)
    end)

    it("refreshes cooldowns via ThrottledRefresh", function()
        local reasons = {}
        function ExtraIcons:ThrottledRefresh(reason)
            reasons[#reasons + 1] = reason
        end

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons:OnBagUpdateCooldown()
        assert.same({ "OnBagUpdateCooldown" }, reasons)
    end)

    it("edit mode callbacks toggle state and defer layout", function()
        local reasons = {}
        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end

        ExtraIcons:HookEditMode()
        EditModeManagerFrame._hooks.OnShow[1]()
        EditModeManagerFrame._hooks.OnHide[1]()

        assert.is_false(ExtraIcons._viewers.utility.container:IsShown())
        assert.is_false(ExtraIcons._viewers.main.container:IsShown())
        assert.is_false(ExtraIcons._isEditModeActive)
        assert.same({ "ExtraIcons:EnterEditMode", "ExtraIcons:ExitEditMode" }, reasons)
    end)

    it("viewer callbacks hide the container and defer layout", function()
        local reasons = {}
        local enabled = true
        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end
        function ExtraIcons:IsEnabled()
            return enabled
        end

        ExtraIcons:_hookViewer({ key = "utility", blizzKey = "UtilityCooldownViewer" })
        UtilityCooldownViewer._hooks.OnShow[1]()
        UtilityCooldownViewer._hooks.OnHide[1]()
        UtilityCooldownViewer._hooks.OnSizeChanged[1]()
        enabled = false
        UtilityCooldownViewer._hooks.OnShow[1]()
        UtilityCooldownViewer._hooks.OnHide[1]()
        UtilityCooldownViewer._hooks.OnSizeChanged[1]()

        assert.is_false(ExtraIcons._viewers.utility.container:IsShown())
        assert.same({ "ExtraIcons:OnShow", "ExtraIcons:OnHide", "ExtraIcons:OnSizeChanged" }, reasons)
    end)

    it("edit mode callbacks do nothing while disabled", function()
        local reasons = {}
        function ExtraIcons:IsEnabled() return false end
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end

        ExtraIcons:HookEditMode()
        ExtraIcons._isEditModeActive = nil
        EditModeManagerFrame._hooks.OnShow[1]()
        EditModeManagerFrame._hooks.OnHide[1]()

        assert.is_nil(ExtraIcons._isEditModeActive)
        assert.same({}, reasons)
    end)

    it("returns false from UpdateLayout when frame or config is missing", function()
        ExtraIcons.InnerFrame = nil
        assert.is_false(ExtraIcons:UpdateLayout("test"))

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function() return nil end
        assert.is_false(ExtraIcons:UpdateLayout("test"))
    end)

    it("hides InnerFrame and restores viewers when ShouldShow is false", function()
        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { stackKey = "trinket1" } })
        end
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 100, 50)
        ExtraIcons._viewers.utility.originalPoint = { "CENTER", UIParent, "CENTER", 10, 20 }

        -- Hide both viewers so ShouldShow returns false
        UtilityCooldownViewer:Hide()
        EssentialCooldownViewer:Hide()

        assert.is_false(ExtraIcons:UpdateLayout("test"))
        assert.is_false(ExtraIcons.InnerFrame:IsShown())
        assert.is_false(ExtraIcons._viewers.utility.container:IsShown())

        -- Viewer position restored
        local point, _, _, x, y = UtilityCooldownViewer:GetPoint(1)
        assert.are.equal("CENTER", point)
        assert.are.equal(10, x)
        assert.are.equal(20, y)
    end)

    it("re-shows InnerFrame after a hide cycle", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function() return 1 end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        itemCounts[HEALTHSTONE_ID] = 1
        itemIconsByID[HEALTHSTONE_ID] = "healthstone"

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { kind = "itemStack", itemStackId = "healthstones" } })
        end

        -- First layout: icons placed, InnerFrame shown
        assert.is_true(ExtraIcons:UpdateLayout("test"))
        assert.is_true(ExtraIcons.InnerFrame:IsShown())

        -- Simulate global hide cycle (e.g. mounting or entering rest area)
        ExtraIcons.InnerFrame:Hide()
        UtilityCooldownViewer:Hide()
        EssentialCooldownViewer:Hide()
        assert.is_false(ExtraIcons:UpdateLayout("hidden"))
        assert.is_false(ExtraIcons.InnerFrame:IsShown())

        -- Restore viewers — simulates unmount / leaving rest area
        UtilityCooldownViewer:Show()
        EssentialCooldownViewer:Show()
        assert.is_true(ExtraIcons:UpdateLayout("unhidden"))
        assert.is_true(ExtraIcons.InnerFrame:IsShown())
        assert.is_true(ExtraIcons._viewers.utility.container:IsShown())
    end)

    it("returns false from UpdateLayout during live edit mode and restores viewer", function()
        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { stackKey = "trinket1" } })
        end
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 100, 50)
        ExtraIcons._viewers.utility.originalPoint = { "CENTER", UIParent, "CENTER", 10, 20 }
        ExtraIcons._isEditModeActive = nil
        EditModeManagerFrame:Show()

        assert.is_false(ExtraIcons:UpdateLayout("test"))
        assert.is_false(ExtraIcons._viewers.utility.container:IsShown())
        assert.is_nil(ExtraIcons._viewers.utility.originalPoint)

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

        ExtraIcons:OnBagUpdateDelayed()
        ExtraIcons:OnPlayerEnteringWorld()

        assert.same({ "ExtraIcons:OnBagUpdateDelayed", "ExtraIcons:OnPlayerEnteringWorld" }, reasons)
    end)

    it("registers with the frame system and schedules initial hooks on enable", function()
        local reasons = {}
        function ExtraIcons:RegisterEvent() end
        function ExtraIcons:GetModuleConfig() return makeViewersConfig() end
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end

        ExtraIcons:OnInitialize()
        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons:OnEnable()
        assert.are.equal(1, addMixinCalls)
        assert.are.equal(1, registerFrameCalls)
        assert.are.equal(1, #timerCallbacks)

        timerCallbacks[1]()

        assert.same({ "ExtraIcons:OnEnable" }, reasons)
        assert.is_true(ExtraIcons._editModeHooked)
        assert.is_true(ExtraIcons._viewers.utility.hooked)
        assert.is_true(ExtraIcons._viewers.main.hooked)
    end)

    it("skips delayed initial hooks when disabled before the callback runs", function()
        local reasons = {}
        function ExtraIcons:RegisterEvent() end
        function ExtraIcons:GetModuleConfig() return makeViewersConfig() end
        function ExtraIcons:IsEnabled() return false end
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end

        ExtraIcons:OnInitialize()
        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons:OnEnable()

        assert.are.equal(1, #timerCallbacks)
        timerCallbacks[1]()

        assert.same({}, reasons)
        assert.is_nil(ExtraIcons._editModeHooked)
        assert.is_false(ExtraIcons._viewers.utility.hooked)
        assert.is_false(ExtraIcons._viewers.main.hooked)
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

        inventoryItemBySlot[13] = 101
        inventoryTextureBySlot[13] = "trinket-1"
        inventorySpellByItem[101] = 9001
        inventoryItemBySlot[14] = 102
        inventoryTextureBySlot[14] = "trinket-2"
        inventorySpellByItem[102] = 9002
        itemCounts[COMBAT_POTION_ID] = 3
        itemIconsByID[COMBAT_POTION_ID] = "combat-potion"
        itemCounts[HEALTHSTONE_ID] = 1
        itemIconsByID[HEALTHSTONE_ID] = "healthstone"

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({
                { stackKey = "trinket1" },
                { stackKey = "trinket2" },
                { kind = "itemStack", itemStackId = "combatPotions" },
                { kind = "itemStack", itemStackId = "healthstones" },
            })
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        local vs = ExtraIcons._viewers.utility
        assert.is_true(vs.container:IsShown())
        assert.are.equal(1.25, vs.container.__scale)
        assert.are.equal((4 * 18) + (3 * 6), vs.container:GetWidth())
        assert.are.equal(18, vs.container:GetHeight())
        assert.are.equal(101, vs.iconPool[1].itemId)
        assert.are.equal(13, vs.iconPool[1].slotId)
        assert.are.equal(102, vs.iconPool[2].itemId)
        assert.are.equal(14, vs.iconPool[2].slotId)
        assert.are.equal(COMBAT_POTION_ID, vs.iconPool[3].itemId)
        assert.are.equal(HEALTHSTONE_ID, vs.iconPool[4].itemId)

        local point, relativeTo, relativePoint, x, y = UtilityCooldownViewer:GetPoint(1)
        assert.are.equal("CENTER", point)
        assert.are.equal(UIParent, relativeTo)
        assert.are.equal("CENTER", relativePoint)
        assert.are.equal(40, x)
        assert.are.equal(50, y)
    end)

    it("uses GetItemFrames and isActive to detect icon size and anchor container", function()
        local activeFrame = TestHelpers.makeFrame({ shown = true, width = 22, height = 22 })
        activeFrame.isActive = true
        local inactiveFrame = TestHelpers.makeFrame({ shown = false, width = 22, height = 22 })
        inactiveFrame.isActive = false
        UtilityCooldownViewer.childXPadding = 4
        UtilityCooldownViewer.iconScale = 1.0
        UtilityCooldownViewer:SetWidth(22)
        UtilityCooldownViewer.GetItemFrames = function()
            return { inactiveFrame, activeFrame }
        end
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 100, 0)

        itemCounts[HEALTHSTONE_ID] = 1
        itemIconsByID[HEALTHSTONE_ID] = "healthstone"

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { kind = "itemStack", itemStackId = "healthstones" } })
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        local vs = ExtraIcons._viewers.utility
        assert.are.equal(22, vs.container:GetWidth())
        local _, anchorFrame = vs.container:GetPoint(1)
        assert.are.equal(activeFrame, anchorFrame)
        local _, _, _, x = UtilityCooldownViewer:GetPoint(1)
        assert.are.equal(87, x)
    end)

    it("anchors to the viewer when active item frames are hidden", function()
        local activeFrame = TestHelpers.makeFrame({ shown = false, width = 22, height = 22 })
        activeFrame.isActive = true
        UtilityCooldownViewer.childXPadding = 4
        UtilityCooldownViewer.iconScale = 1.0
        UtilityCooldownViewer:SetWidth(22)
        UtilityCooldownViewer.GetItemFrames = function()
            return { activeFrame }
        end
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 100, 0)

        itemCounts[HEALTHSTONE_ID] = 1
        itemIconsByID[HEALTHSTONE_ID] = "healthstone"

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { kind = "itemStack", itemStackId = "healthstones" } })
        end

        assert.is_true(ExtraIcons:UpdateLayout("hidden-active-frame"))

        local _, anchorFrame = ExtraIcons._viewers.utility.container:GetPoint(1)
        assert.are.equal(UtilityCooldownViewer, anchorFrame)
    end)

    it("does not reapply unchanged anchors on repeated layouts", function()
        local activeFrame = TestHelpers.makeFrame({ shown = true, width = 22, height = 22 })
        activeFrame.isActive = true
        UtilityCooldownViewer.childXPadding = 4
        UtilityCooldownViewer.iconScale = 1.0
        UtilityCooldownViewer:SetWidth(22)
        UtilityCooldownViewer.GetItemFrames = function()
            return { activeFrame }
        end
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 100, 0)

        itemCounts[HEALTHSTONE_ID] = 1
        itemIconsByID[HEALTHSTONE_ID] = "healthstone"

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { kind = "itemStack", itemStackId = "healthstones" } })
        end

        assert.is_true(ExtraIcons:UpdateLayout("initial"))

        local vs = ExtraIcons._viewers.utility
        local viewerSetPoints = TestHelpers.getCalls(UtilityCooldownViewer, "SetPoint")
        local viewerClears = TestHelpers.getCalls(UtilityCooldownViewer, "ClearAllPoints")
        local containerSetPoints = TestHelpers.getCalls(vs.container, "SetPoint")
        local containerClears = TestHelpers.getCalls(vs.container, "ClearAllPoints")
        local iconSetPoints = TestHelpers.getCalls(vs.iconPool[1], "SetPoint")
        local iconClears = TestHelpers.getCalls(vs.iconPool[1], "ClearAllPoints")

        assert.is_true(ExtraIcons:UpdateLayout("unchanged"))

        assert.are.equal(viewerSetPoints, TestHelpers.getCalls(UtilityCooldownViewer, "SetPoint"))
        assert.are.equal(viewerClears, TestHelpers.getCalls(UtilityCooldownViewer, "ClearAllPoints"))
        assert.are.equal(containerSetPoints, TestHelpers.getCalls(vs.container, "SetPoint"))
        assert.are.equal(containerClears, TestHelpers.getCalls(vs.container, "ClearAllPoints"))
        assert.are.equal(iconSetPoints, TestHelpers.getCalls(vs.iconPool[1], "SetPoint"))
        assert.are.equal(iconClears, TestHelpers.getCalls(vs.iconPool[1], "ClearAllPoints"))
    end)

    it("does not iterate inaccessible GetItemFrames results", function()
        local inaccessibleFrames = {}
        UtilityCooldownViewer.childXPadding = 4
        UtilityCooldownViewer.iconScale = 1.0
        UtilityCooldownViewer:SetWidth(22)
        UtilityCooldownViewer.GetItemFrames = function()
            return inaccessibleFrames
        end
        inaccessibleTables[inaccessibleFrames] = true
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 100, 0)

        itemCounts[HEALTHSTONE_ID] = 1
        itemIconsByID[HEALTHSTONE_ID] = "healthstone"

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { kind = "itemStack", itemStackId = "healthstones" } })
        end

        assert.is_true(ExtraIcons:UpdateLayout("rated-bg"))

        local vs = ExtraIcons._viewers.utility
        assert.is_true(vs.container:IsShown())
        local _, anchorFrame = vs.container:GetPoint(1)
        assert.are.equal(UtilityCooldownViewer, anchorFrame)
        assert.are.equal(1, #errorLogs)
        assert.are.equal("ExtraIcons", errorLogs[1].module)
        assert.are.equal("InaccessibleItemFrames:utility", errorLogs[1].key)
        assert.are.equal("Cooldown viewer item frames are inaccessible for utility during rated-bg", errorLogs[1].message)
        assert.are.equal("rated-bg", errorLogs[1].data.reason)
        assert.are.equal("utility", errorLogs[1].data.viewerKey)
        assert.are.equal("UtilityCooldownViewer", errorLogs[1].data.blizzardFrameKey)
        assert.is_true(errorLogs[1].data.viewerExists)
        assert.is_true(errorLogs[1].data.viewerShown)
        assert.are.equal(22, errorLogs[1].data.viewerWidth)
        assert.are.equal(1.0, errorLogs[1].data.viewerIconScale)
        assert.are.equal("table", errorLogs[1].data.itemFramesType)
        assert.is_false(errorLogs[1].data.itemFramesAccessible)
    end)

    it("logs viewer diagnostics when GetItemFrames fails", function()
        UtilityCooldownViewer.childXPadding = 4
        UtilityCooldownViewer.iconScale = 1.0
        UtilityCooldownViewer:SetWidth(22)
        UtilityCooldownViewer.GetItemFrames = function()
            error("GetItemFrames blocked")
        end
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 100, 0)

        itemCounts[HEALTHSTONE_ID] = 1
        itemIconsByID[HEALTHSTONE_ID] = "healthstone"

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { kind = "itemStack", itemStackId = "healthstones" } })
        end

        assert.has_no.errors(function()
            ExtraIcons:UpdateLayout("rated-bg")
        end)

        assert.are.equal(1, #errorLogs)
        assert.are.equal("ExtraIcons", errorLogs[1].module)
        assert.are.equal("GetItemFrames:utility", errorLogs[1].key)
        assert.is_truthy(errorLogs[1].message:find(
            "Unable to read cooldown viewer item frames for utility during rated-bg:", 1, true))
        assert.are.equal("rated-bg", errorLogs[1].data.reason)
        assert.are.equal("utility", errorLogs[1].data.viewerKey)
        assert.are.equal("UtilityCooldownViewer", errorLogs[1].data.blizzardFrameKey)
        assert.is_true(errorLogs[1].data.viewerExists)
        assert.is_true(errorLogs[1].data.viewerShown)
        assert.are.equal(22, errorLogs[1].data.viewerWidth)
        assert.are.equal(1.0, errorLogs[1].data.viewerIconScale)
        assert.is_truthy(errorLogs[1].data.error:find("GetItemFrames blocked", 1, true))
    end)

    it("continues conservatively when GetItemFrames iteration fails", function()
        local taintedFrames = {}
        UtilityCooldownViewer.childXPadding = 4
        UtilityCooldownViewer.iconScale = 1.0
        UtilityCooldownViewer:SetWidth(22)
        UtilityCooldownViewer.GetItemFrames = function()
            return taintedFrames
        end
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 100, 0)

        itemCounts[HEALTHSTONE_ID] = 1
        itemIconsByID[HEALTHSTONE_ID] = "healthstone"

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { kind = "itemStack", itemStackId = "healthstones" } })
        end

        local originalIpairs = _G.ipairs
        _G.ipairs = function(value)
            if value == taintedFrames then
                error("attempted to iterate a table that cannot be accessed while tainted")
            end
            return originalIpairs(value)
        end

        local ok, err = pcall(function()
            return ExtraIcons:UpdateLayout("rated-bg")
        end)
        _G.ipairs = originalIpairs

        assert.is_true(ok, err)
        local vs = ExtraIcons._viewers.utility
        assert.is_true(vs.container:IsShown())
        local _, anchorFrame = vs.container:GetPoint(1)
        assert.are.equal(UtilityCooldownViewer, anchorFrame)
        assert.are.equal(1, #errorLogs)
        assert.are.equal("ExtraIcons", errorLogs[1].module)
        assert.are.equal("IterateItemFrames:utility", errorLogs[1].key)
        assert.is_truthy(errorLogs[1].message:find(
            "Unable to iterate cooldown viewer item frames for utility during rated-bg:", 1, true))
        assert.is_truthy(errorLogs[1].message:find("attempted to iterate", 1, true))
        assert.are.equal("rated-bg", errorLogs[1].data.reason)
        assert.are.equal("utility", errorLogs[1].data.viewerKey)
        assert.are.equal("UtilityCooldownViewer", errorLogs[1].data.blizzardFrameKey)
        assert.is_true(errorLogs[1].data.viewerExists)
        assert.is_true(errorLogs[1].data.viewerShown)
        assert.are.equal(22, errorLogs[1].data.viewerWidth)
        assert.are.equal("table", errorLogs[1].data.itemFramesType)
        assert.is_true(errorLogs[1].data.itemFramesAccessible)
        assert.is_truthy(errorLogs[1].data.error:find("attempted to iterate", 1, true))
    end)

    it("matches the utility viewer's square overlay footprint", function()
        local activeFrame = TestHelpers.makeFrame({ shown = true, width = 30, height = 30 })
        activeFrame.isActive = true
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1.0
        UtilityCooldownViewer:SetWidth(30)
        UtilityCooldownViewer.GetItemFrames = function()
            return { activeFrame }
        end
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        itemCounts[HEALTHSTONE_ID] = 1
        itemIconsByID[HEALTHSTONE_ID] = "healthstone"

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { kind = "itemStack", itemStackId = "healthstones" } })
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        local icon = ExtraIcons._viewers.utility.iconPool[1]
        assert.are.equal(42, icon.Border.__width)
        assert.are.equal(42, icon.Border.__height)
    end)

    it("skips disabled entries during layout resolution", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function() return 1 end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        inventoryItemBySlot[13] = 101
        inventoryTextureBySlot[13] = "trinket-1"
        inventorySpellByItem[101] = 9001
        inventoryItemBySlot[14] = 102
        inventoryTextureBySlot[14] = "trinket-2"
        inventorySpellByItem[102] = 9002

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({
                { stackKey = "trinket1", disabled = true },
                { stackKey = "trinket2" },
            })
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        assert.are.equal(14, ExtraIcons._viewers.utility.iconPool[1].slotId)
        assert.are.equal(18, ExtraIcons._viewers.utility.container:GetWidth())
    end)

    it("publishes a combined main-viewer anchor when main extra icons are shown", function()
        local activeFrame = TestHelpers.makeFrame({ shown = true, width = 22, height = 22 })
        activeFrame.isActive = true
        EssentialCooldownViewer.childXPadding = 4
        EssentialCooldownViewer.iconScale = 1.0
        EssentialCooldownViewer:SetWidth(46)
        EssentialCooldownViewer.GetItemFrames = function()
            return { activeFrame }
        end
        EssentialCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 100, 0)

        inventoryItemBySlot[13] = 101
        inventoryTextureBySlot[13] = "trinket-1"
        inventorySpellByItem[101] = 9001

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({}, { { stackKey = "trinket1" } })
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))

        local vs = ExtraIcons._viewers.main
        local anchor = ExtraIcons:GetMainViewerAnchor()
        assert.are.equal(vs.anchorFrame, anchor)
        assert.is_true(anchor:IsShown())
        assert.same({
            { "LEFT", EssentialCooldownViewer, "LEFT", 0, 0 },
            { "RIGHT", vs.container, "RIGHT", 0, 0 },
            { "TOP", EssentialCooldownViewer, "TOP", 0, 0 },
            { "BOTTOM", EssentialCooldownViewer, "BOTTOM", 0, 0 },
        }, anchor.__anchors)
    end)

    it("restores the utility viewer when an icon moves to main", function()
        local utilityActiveFrame = TestHelpers.makeFrame({ shown = true, width = 22, height = 22 })
        utilityActiveFrame.isActive = true
        UtilityCooldownViewer.childXPadding = 4
        UtilityCooldownViewer.iconScale = 1.0
        UtilityCooldownViewer:SetWidth(22)
        UtilityCooldownViewer.GetItemFrames = function()
            return { utilityActiveFrame }
        end

        local mainActiveFrame = TestHelpers.makeFrame({ shown = true, width = 22, height = 22 })
        mainActiveFrame.isActive = true
        EssentialCooldownViewer.childXPadding = 4
        EssentialCooldownViewer.iconScale = 1.0
        EssentialCooldownViewer:SetWidth(22)
        EssentialCooldownViewer.GetItemFrames = function()
            return { mainActiveFrame }
        end
        EssentialCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 100, 0)
        UtilityCooldownViewer:SetPoint("LEFT", EssentialCooldownViewer, "RIGHT", 8, 0)

        inventoryItemBySlot[13] = 101
        inventoryTextureBySlot[13] = "trinket-1"
        inventorySpellByItem[101] = 9001

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()

        local config = makeViewersConfig({ { stackKey = "trinket1" } }, {})
        ExtraIcons.GetModuleConfig = function()
            return config
        end

        assert.is_true(ExtraIcons:UpdateLayout("utility"))

        local utilityBeforePoint, utilityBeforeRelativeTo, utilityBeforeRelativePoint, utilityBeforeX, utilityBeforeY = UtilityCooldownViewer:GetPoint(1)
        assert.are.equal("LEFT", utilityBeforePoint)
        assert.are.equal(EssentialCooldownViewer, utilityBeforeRelativeTo)
        assert.are.equal("RIGHT", utilityBeforeRelativePoint)
        assert.are.equal(-5, utilityBeforeX)
        assert.are.equal(0, utilityBeforeY)

        config.viewers.utility = {}
        config.viewers.main = { { stackKey = "trinket1" } }

        assert.is_true(ExtraIcons:UpdateLayout("main"))

        local utilityAfterPoint, utilityAfterRelativeTo, utilityAfterRelativePoint, utilityAfterX, utilityAfterY = UtilityCooldownViewer:GetPoint(1)
        local _, _, _, mainAfterX = EssentialCooldownViewer:GetPoint(1)

        assert.are.equal("LEFT", utilityAfterPoint)
        assert.are.equal(EssentialCooldownViewer, utilityAfterRelativeTo)
        assert.are.equal("RIGHT", utilityAfterRelativePoint)
        assert.are.equal(8, utilityAfterX)
        assert.are.equal(0, utilityAfterY)
        assert.are.equal(87, mainAfterX)
        assert.is_false(ExtraIcons._viewers.utility.container:IsShown())
        assert.is_true(ExtraIcons._viewers.main.container:IsShown())
    end)

    it("prefers demonic healthstone over the legacy healthstone", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function() return 1 end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        itemCounts[DEMONIC_HEALTHSTONE_ID] = 1
        itemIconsByID[DEMONIC_HEALTHSTONE_ID] = "demonic-healthstone"
        itemCounts[HEALTHSTONE_ID] = 1
        itemIconsByID[HEALTHSTONE_ID] = "healthstone"

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { kind = "itemStack", itemStackId = "healthstones" } })
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        assert.are.equal(DEMONIC_HEALTHSTONE_ID, ExtraIcons._viewers.utility.iconPool[1].itemId)
    end)

    it("resolves item stack entries through their priority list", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function() return 1 end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        itemCounts[202] = 3
        itemIconsByID[101] = "missing-potion"
        itemIconsByID[202] = "owned-potion"
        itemCooldownByID[202] = { 20, 40, true }

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { kind = "itemStack", itemStackId = 1 } }, nil, {
                nextId = 2,
                order = { 1 },
                byId = {
                    [1] = { name = "Potions", ids = { { itemID = 101 }, { itemID = 202 } } },
                },
            })
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        local icon = ExtraIcons._viewers.utility.iconPool[1]
        assert.are.equal(202, icon.itemId)
        assert.are.equal("owned-potion", icon.Icon.__texture)
        assert.same({ 20, 40 }, icon.Cooldown.__cooldown)
        assert.are.equal("3", icon.Count.__text)
    end)

    it("prefers owned item stack entries over the missing fallback", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function() return 1 end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        itemCounts[202] = 3
        itemIconsByID[101] = "missing-potion"
        itemIconsByID[202] = "owned-potion"

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { kind = "itemStack", itemStackId = 1 } }, nil, {
                nextId = 2,
                order = { 1 },
                byId = {
                    [1] = {
                        name = "Potions",
                        showIfMissing = true,
                        ids = { { itemID = 101 }, { itemID = 202 } },
                    },
                },
            })
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        local icon = ExtraIcons._viewers.utility.iconPool[1]
        assert.are.equal(202, icon.itemId)
        assert.are.equal("owned-potion", icon.Icon.__texture)
        assert.is_false(icon.Icon:IsDesaturated())
        assert.are.equal("3", icon.Count.__text)
    end)

    it("shows missing item stack entries as greyscale when configured", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function() return 1 end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        itemIconsByID[101] = "missing-potion"

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { kind = "itemStack", itemStackId = 1 } }, nil, {
                nextId = 2,
                order = { 1 },
                byId = {
                    [1] = {
                        name = "Potions",
                        showIfMissing = true,
                        ids = { { itemID = 101 }, { itemID = 202 } },
                    },
                },
            })
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        local icon = ExtraIcons._viewers.utility.iconPool[1]
        assert.are.equal(101, icon.itemId)
        assert.are.equal("missing-potion", icon.Icon.__texture)
        assert.is_true(icon.Icon:IsDesaturated())
        assert.is_nil(icon.Count.__text)
    end)

    it("skips missing and empty item stack entries", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function() return 1 end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({
                { kind = "itemStack", itemStackId = 1 },
                { kind = "itemStack", itemStackId = 2 },
            }, nil, {
                nextId = 3,
                order = { 1 },
                byId = {
                    [1] = { name = "Empty", ids = {} },
                },
            })
        end

        assert.is_false(ExtraIcons:UpdateLayout("test"))
        assert.is_false(ExtraIcons._viewers.utility.container:IsShown())
    end)

    it("suppresses combat and health potions on rated maps while still showing healthstones", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function() return 1 end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        ratedMap = true
        itemCounts[COMBAT_POTION_ID] = 1
        itemIconsByID[COMBAT_POTION_ID] = "combat-potion"
        itemCounts[HEALTH_POTION_ID] = 1
        itemIconsByID[HEALTH_POTION_ID] = "health-potion"
        itemCounts[HEALTHSTONE_ID] = 1
        itemIconsByID[HEALTHSTONE_ID] = "healthstone"

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({
                { kind = "itemStack", itemStackId = "combatPotions" },
                { kind = "itemStack", itemStackId = "healthPotions" },
                { kind = "itemStack", itemStackId = "healthstones" },
            })
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        assert.are.equal(HEALTHSTONE_ID, ExtraIcons._viewers.utility.iconPool[1].itemId)
        assert.are.equal(18, ExtraIcons._viewers.utility.container:GetWidth())
    end)

    it("suppresses item stacks in non-PvP instances when configured", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function() return 1 end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        inInstance = true
        instanceType = "party"
        itemCounts[COMBAT_POTION_ID] = 1
        itemIconsByID[COMBAT_POTION_ID] = "combat-potion"
        itemCounts[HEALTHSTONE_ID] = 1
        itemIconsByID[HEALTHSTONE_ID] = "healthstone"

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({
                { kind = "itemStack", itemStackId = "combatPotions" },
                { kind = "itemStack", itemStackId = "healthstones" },
            }, nil, {
                nextId = 1,
                order = { "combatPotions", "healthstones" },
                byId = {
                    combatPotions = {
                        name = "Combat Potions",
                        hideInInstances = true,
                        ids = { { itemID = COMBAT_POTION_ID } },
                    },
                    healthstones = {
                        name = "Healthstones",
                        hideInInstances = false,
                        ids = { { itemID = HEALTHSTONE_ID } },
                    },
                },
            })
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        assert.are.equal(HEALTHSTONE_ID, ExtraIcons._viewers.utility.iconPool[1].itemId)
    end)

    it("anchors container to last active item frame when viewer layout is stale", function()
        local staleFrame = TestHelpers.makeFrame({ shown = false, width = 22, height = 22 })
        staleFrame.isActive = false
        local activeFrame = TestHelpers.makeFrame({ shown = true, width = 22, height = 22 })
        activeFrame.isActive = true
        UtilityCooldownViewer.childXPadding = 2
        UtilityCooldownViewer.iconScale = 1.0
        UtilityCooldownViewer:SetWidth(46)
        UtilityCooldownViewer.GetItemFrames = function()
            return { staleFrame, activeFrame }
        end
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 100, 0)

        inventoryItemBySlot[13] = 101
        inventoryTextureBySlot[13] = "trinket-1"
        inventorySpellByItem[101] = 9001

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { stackKey = "trinket1" } })
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        local _, anchorFrame = ExtraIcons._viewers.utility.container:GetPoint(1)
        assert.are.equal(activeFrame, anchorFrame)
        local _, _, _, x = UtilityCooldownViewer:GetPoint(1)
        assert.are.equal(88, x)
    end)

    it("restores the viewer and hides the container when no items are available", function()
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 100, 50)
        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({
                { stackKey = "trinket1" },
                { stackKey = "trinket2" },
                { kind = "itemStack", itemStackId = "combatPotions" },
                { kind = "itemStack", itemStackId = "healthPotions" },
                { kind = "itemStack", itemStackId = "healthstones" },
            })
        end
        ExtraIcons._viewers.utility.originalPoint = { "CENTER", UIParent, "CENTER", 10, 20 }

        assert.is_false(ExtraIcons:UpdateLayout("test"))
        assert.is_false(ExtraIcons._viewers.utility.container:IsShown())

        local point, relativeTo, relativePoint, x, y = UtilityCooldownViewer:GetPoint(1)
        assert.are.equal("CENTER", point)
        assert.are.equal(UIParent, relativeTo)
        assert.are.equal("CENTER", relativePoint)
        assert.are.equal(10, x)
        assert.are.equal(20, y)
    end)

    it("applies cooldowns during UpdateLayout so throttled refresh cannot skip them", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function() return 1 end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        itemCounts[HEALTHSTONE_ID] = 1
        itemIconsByID[HEALTHSTONE_ID] = "healthstone"
        itemCooldownByID[HEALTHSTONE_ID] = { 100, 60, true }

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { kind = "itemStack", itemStackId = "healthstones" } })
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        assert.same({ 100, 60 }, ExtraIcons._viewers.utility.iconPool[1].Cooldown.__cooldown)
    end)

    it("shows item stack counts when enabled", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function() return 1 end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        itemCounts[HEALTHSTONE_ID] = 5
        itemIconsByID[HEALTHSTONE_ID] = "healthstone"

        local config = makeViewersConfig({ { kind = "itemStack", itemStackId = "healthstones" } })
        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return config
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        local count = ExtraIcons._viewers.utility.iconPool[1].Count
        assert.are.equal("5", count.__text)
        assert.is_true(count:IsShown())
        assert.are.equal(count, applyFontCalls[#applyFontCalls].fontString)
        assert.are.equal(globalConfig, applyFontCalls[#applyFontCalls].globalConfig)
        assert.are.equal(config, applyFontCalls[#applyFontCalls].moduleConfig)
        assert.is_nil(count.__template)

        config.showStackCount = false
        assert.is_true(ExtraIcons:UpdateLayout("test"))
        assert.is_nil(count.__text)
        assert.is_false(count:IsShown())
    end)

    it("reapplies count font config during layout updates", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function() return 1 end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        itemCounts[HEALTHSTONE_ID] = 5
        itemIconsByID[HEALTHSTONE_ID] = "healthstone"

        local config = makeViewersConfig({ { kind = "itemStack", itemStackId = "healthstones" } })
        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return config
        end

        assert.is_true(ExtraIcons:UpdateLayout("initial"))
        local count = ExtraIcons._viewers.utility.iconPool[1].Count
        local previousApplyCount = #applyFontCalls

        config.overrideFont = true
        config.font = "Expressway"
        config.fontSize = 18
        assert.is_true(ExtraIcons:UpdateLayout("OptionsChanged"))

        assert.is_true(#applyFontCalls > previousApplyCount)
        assert.are.equal(count, applyFontCalls[#applyFontCalls].fontString)
        assert.are.equal(globalConfig, applyFontCalls[#applyFontCalls].globalConfig)
        assert.are.equal(config, applyFontCalls[#applyFontCalls].moduleConfig)
        assert.is_true(applyFontCalls[#applyFontCalls].moduleConfig.overrideFont)
        assert.are.equal("Expressway", applyFontCalls[#applyFontCalls].moduleConfig.font)
        assert.are.equal(18, applyFontCalls[#applyFontCalls].moduleConfig.fontSize)
        assert.are.equal("5", count.__text)
    end)

    it("shows spell charges when enabled and refreshes them", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function() return 1 end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        knownSpells[59752] = true
        spellTextures[59752] = "racial-icon"
        spellCharges[59752] = { currentCharges = 2, maxCharges = 3 }

        local config = makeViewersConfig({ { kind = "spell", ids = { { spellId = 59752 } } } })
        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return config
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        local count = ExtraIcons._viewers.utility.iconPool[1].Count
        assert.are.equal("2", count.__text)
        assert.is_true(count:IsShown())

        spellCharges[59752] = { currentCharges = 1, maxCharges = 3 }
        assert.is_true(ExtraIcons:Refresh("test"))
        assert.are.equal("1", count.__text)

        config.showCharges = false
        assert.is_true(ExtraIcons:Refresh("test"))
        assert.is_nil(count.__text)
        assert.is_false(count:IsShown())
    end)

    it("refreshes cooldowns for visible icons across viewers", function()
        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        local vs = ExtraIcons._viewers.utility
        for i = 1, 3 do
            vs.iconPool[i] = TestHelpers.makeFrame({ shown = true })
            vs.iconPool[i].Cooldown = {
                SetCooldown = function(self, start, duration)
                    self.__cooldown = { start, duration }
                end,
                Clear = function(self)
                    self.__cleared = true
                end,
                GetRegions = function() return nil end,
            }
        end
        vs.iconPool[1].slotId = 13
        vs.iconPool[2].itemId = 5001
        vs.iconPool[3].itemId = 5002
        vs.container:Show()

        inventoryCooldownBySlot[13] = { 10, 30, 1 }
        itemCooldownByID[5001] = { 20, 40, true }
        itemCooldownByID[5002] = { 0, 0, false }

        assert.is_true(ExtraIcons:Refresh("test"))
        assert.same({ 10, 30 }, vs.iconPool[1].Cooldown.__cooldown)
        assert.same({ 20, 40 }, vs.iconPool[2].Cooldown.__cooldown)
        assert.is_true(vs.iconPool[3].Cooldown.__cleared)
    end)

    it("resolves spell entries and tracks spell cooldowns", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function() return 1 end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        knownSpells[59752] = true
        spellTextures[59752] = "racial-icon"
        spellCooldowns[59752] = "durObj:59752"
        spellCooldownInfos[59752] = { isOnGCD = false }

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { kind = "spell", ids = { { spellId = 59752 } } } })
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        local vs = ExtraIcons._viewers.utility
        assert.are.equal(59752, vs.iconPool[1].spellId)
        assert.same({ 0, 0 }, vs.iconPool[1].Cooldown.__cooldown)
        assert.are.equal("durObj:59752", vs.iconPool[1].Cooldown.__durObj)
    end)

    it("resolves spells known via C_SpellBook.IsSpellKnown", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function() return 1 end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        knownSpells[59752] = true
        spellTextures[59752] = "racial-icon"
        spellCooldowns[59752] = "durObj:59752"
        spellCooldownInfos[59752] = { isOnGCD = false }

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { kind = "spell", ids = { { spellId = 59752 } } } })
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        local vs = ExtraIcons._viewers.utility
        assert.are.equal(59752, vs.iconPool[1].spellId)
        assert.are.equal("racial-icon", vs.iconPool[1].Icon:GetTexture())
    end)

    it("resolves saved racial spell ids through alternate racial ids", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function() return 1 end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        knownSpells[357214] = true
        spellTextures[357214] = "tail-swipe-icon"

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { kind = "spell", ids = { { spellId = 368970 } } } })
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        local vs = ExtraIcons._viewers.utility
        assert.are.equal(357214, vs.iconPool[1].spellId)
        assert.are.equal("tail-swipe-icon", vs.iconPool[1].Icon:GetTexture())
    end)

    it("skips spell cooldown swipe when only on GCD", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function() return 1 end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        knownSpells[59752] = true
        spellTextures[59752] = "racial-icon"
        spellCooldowns[59752] = "durObj:59752"
        spellCooldownInfos[59752] = { isOnGCD = true }

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { kind = "spell", ids = { { spellId = 59752 } } } })
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        local vs = ExtraIcons._viewers.utility
        assert.same({ 0, 0 }, vs.iconPool[1].Cooldown.__cooldown)
        assert.is_nil(vs.iconPool[1].Cooldown.__durObj)
    end)

    it("uses charge duration for multi-charge spells", function()
        local utilityIconChild = TestHelpers.makeFrame({ shown = true, width = 18, height = 18 })
        utilityIconChild.GetSpellID = function() return 1 end
        UtilityCooldownViewer.childXPadding = 0
        UtilityCooldownViewer.iconScale = 1
        UtilityCooldownViewer._children = { utilityIconChild }
        UtilityCooldownViewer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        knownSpells[108853] = true
        spellTextures[108853] = "fire-blast-icon"
        spellCooldowns[108853] = "chargeDurObj:108853"
        spellCooldownInfos[108853] = { isOnGCD = false }
        spellCharges[108853] = { maxCharges = 2 }

        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons.GetModuleConfig = function()
            return makeViewersConfig({ { kind = "spell", ids = { { spellId = 108853 } } } })
        end

        assert.is_true(ExtraIcons:UpdateLayout("test"))
        local vs = ExtraIcons._viewers.utility
        assert.same({ 0, 0 }, vs.iconPool[1].Cooldown.__cooldown)
        assert.are.equal("chargeDurObj:108853", vs.iconPool[1].Cooldown.__durObj)
    end)

    it("defers layout for spell change events", function()
        local reasons = {}
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end

        ExtraIcons:OnSpellsChanged()
        assert.same({ "ExtraIcons:OnSpellsChanged" }, reasons)
    end)

    it("cleans up module state on disable", function()
        ExtraIcons.InnerFrame = ExtraIcons:CreateFrame()
        ExtraIcons._viewers.utility.originalPoint = { "TOP", UIParent, "TOP", 0, 0 }
        ExtraIcons._isEditModeActive = true
        ExtraIcons._trackedEquipSlots = { [13] = true }
        local updateReasons = {}
        function ExtraIcons:UnregisterAllEvents()
            self._eventsUnregistered = true
        end
        function ExtraIcons:UpdateLayout(reason)
            updateReasons[#updateReasons + 1] = reason
            return false
        end

        ExtraIcons:OnDisable()

        assert.is_true(ExtraIcons._eventsUnregistered)
        assert.same({ "OnDisable" }, updateReasons)
        assert.is_nil(ExtraIcons._viewers.utility.originalPoint)
        assert.is_nil(ExtraIcons._isEditModeActive)
        assert.is_nil(ExtraIcons._trackedEquipSlots)
    end)
end)
