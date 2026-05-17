-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("ItemStacksOptions settings page", function()
    local originalGlobals
    local profile, defaults, SB, ns, page, registeredPage, refreshCalls, scheduledReasons, previewCalls

    local function getRow(rowId)
        for _, row in ipairs(page.rows) do
            if row.id == rowId then
                return row
            end
        end
    end

    local function buildSections()
        return getRow("itemStackItems").sections()
    end

    local function getSection()
        return buildSections()[1]
    end

    local function getTrailerValue(trailer, key)
        local value = trailer[key]
        if type(value) == "function" then
            return value()
        end
        return value
    end

    local function createStack(name)
        TestHelpers.InstallPopupAutoAccept(name or "Potions")
        getRow("createItemStack").onClick({ page = registeredPage })
        refreshCalls = {}
        scheduledReasons = {}
    end

    local function getStackAction(text)
        if text == ns.L["DELETE"] then
            return getRow("deleteItemStack")
        elseif text == ns.L["REVERT"] then
            return getRow("revertItemStack")
        end
    end

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals(TestHelpers.OPTIONS_GLOBALS)
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        TestHelpers.SetupOptionsGlobals()
        profile, defaults = TestHelpers.MakeOptionsProfile()
        SB, ns = TestHelpers.SetupOptionsEnv(profile, defaults)
        refreshCalls = {}
        scheduledReasons = {}
        previewCalls = {}
        profile.extraIcons.itemStacks = { nextId = 1, order = {}, byId = {} }
        profile.extraIcons.viewers = { utility = {}, main = {} }

        ns.Runtime.ScheduleLayoutUpdate = function(_, reason)
            scheduledReasons[#scheduledReasons + 1] = reason
        end
        ns.Runtime.SetLayoutPreview = function(active)
            previewCalls[#previewCalls + 1] = active
        end

        TestHelpers.CollectSettings(function()
            TestHelpers.LoadChunk("UI/ExtraIconsShared.lua", "ExtraIconsShared")(nil, ns)
            TestHelpers.LoadChunk("UI/ExtraIconsOptions.lua", "ExtraIconsOptions")(nil, ns)
            TestHelpers.LoadChunk("UI/ItemStacksOptions.lua", "ItemStacksOptions")(nil, ns)
            page = ns.ItemStacksOptions.page
            local _, _, registered = TestHelpers.RegisterSectionSpec(SB, {
                key = "extraIcons",
                name = ns.L["EXTRA_ICONS"],
                pages = { page },
            })
            registeredPage = registered
            ns.ItemStacksOptions.OnInitialize()
        end)
        ns.ItemStacksOptions.EnsureItemLoadFrame()
        registeredPage.Refresh = function()
            refreshCalls[#refreshCalls + 1] = registeredPage._category
        end
    end)

    it("registers declarative rows for the item stack form", function()
        assert.are.equal("itemStacks", page.key)
        assert.are.equal("button", getRow("createItemStack").type)
        assert.are.equal("dropdown", getRow("selectedManagedItemStack").type)
        assert.are.equal("checkbox", getRow("hideStackInInstances").type)
        assert.are.equal("checkbox", getRow("hideStackInRatedPvp").type)
        assert.are.equal("checkbox", getRow("showStackIfMissing").type)
        assert.are.equal("sectionList", getRow("itemStackItems").type)
        assert.are.equal("button", getRow("renameItemStack").type)
        assert.are.equal("button", getRow("deleteItemStack").type)
        assert.are.equal("button", getRow("revertItemStack").type)

        local ratedIndex, missingIndex, itemsIndex, renameIndex, deleteIndex, revertIndex
        for index, row in ipairs(page.rows) do
            if row.id == "hideStackInRatedPvp" then
                ratedIndex = index
            elseif row.id == "showStackIfMissing" then
                missingIndex = index
            elseif row.id == "itemStackItems" then
                itemsIndex = index
            elseif row.id == "renameItemStack" then
                renameIndex = index
            elseif row.id == "deleteItemStack" then
                deleteIndex = index
            elseif row.id == "revertItemStack" then
                revertIndex = index
            end
        end
        assert.are.equal(ratedIndex + 1, missingIndex)
        assert.are.equal(missingIndex + 1, itemsIndex)
        assert.are.equal(renameIndex + 1, deleteIndex)
        assert.are.equal(deleteIndex + 1, revertIndex)
    end)

    it("shows the layout preview while the item stacks page is open", function()
        page.onShow()
        page.onHide()

        assert.are.same({ true, false }, previewCalls)
    end)

    it("validates create names and stores stable stack ids", function()
        TestHelpers.InstallPopupAutoAccept("   ")
        getRow("createItemStack").onClick({ page = registeredPage })
        assert.are.equal(0, #profile.extraIcons.itemStacks.order)

        TestHelpers.InstallPopupAutoAccept("Potions")
        getRow("createItemStack").onClick({ page = registeredPage })

        assert.are.equal(1, profile.extraIcons.itemStacks.order[1])
        assert.are.equal(2, profile.extraIcons.itemStacks.nextId)
        assert.are.equal("Potions", profile.extraIcons.itemStacks.byId[1].name)
        assert.are.same({ "OptionsChanged" }, scheduledReasons)
    end)

    it("renames an item stack without changing viewer references", function()
        createStack("Potions")
        profile.extraIcons.viewers.utility = { { kind = "itemStack", itemStackId = 1 } }

        TestHelpers.InstallPopupAutoAccept("Better Potions")
        getRow("renameItemStack").onClick({ page = registeredPage })

        assert.are.equal("Better Potions", profile.extraIcons.itemStacks.byId[1].name)
        assert.same({ { kind = "itemStack", itemStackId = 1 } }, profile.extraIcons.viewers.utility)
    end)

    it("adds resolved items, blocks duplicates, reorders, and removes with confirmation", function()
        createStack("Potions")
        local itemNames = { [101] = "Potion A", [202] = "Potion B" }
        _G.C_Item.GetItemNameByID = function(itemId) return itemNames[itemId] end
        _G.C_Item.GetItemIconByID = function(itemId) return "icon-" .. tostring(itemId) end
        _G.C_Item.DoesItemExistByID = function(itemId) return itemNames[itemId] ~= nil end

        local footer = assert(getSection().footer)
        footer.onTextChanged("101")
        assert.are.equal("Potion A", getTrailerValue(footer, "previewText"))
        assert.is_true(getTrailerValue(footer, "submitEnabled"))
        assert.is_true(footer.onSubmit())

        footer = assert(getSection().footer)
        footer.onTextChanged("101")
        assert.are.equal(ns.L["ITEM_STACK_DUPLICATE_ITEM"], getTrailerValue(footer, "previewText"))
        assert.is_false(getTrailerValue(footer, "submitEnabled"))

        footer.onTextChanged("202")
        assert.is_true(footer.onSubmit())
        assert.same({ { itemID = 101 }, { itemID = 202 } }, profile.extraIcons.itemStacks.byId[1].ids)

        local firstRow = getSection().items[1]
        assert.is_nil(firstRow.actions.missing)
        firstRow.actions.down.onClick()
        assert.same({ { itemID = 202 }, { itemID = 101 } }, profile.extraIcons.itemStacks.byId[1].ids)

        getSection().items[1].actions.delete.onClick()
        assert.same({ { itemID = 101 } }, profile.extraIcons.itemStacks.byId[1].ids)
    end)

    it("refreshes pending item previews when item data arrives", function()
        createStack("Potions")
        local itemNames = {}
        _G.C_Item.DoesItemExistByID = function(itemId) return itemId == 303 end
        _G.C_Item.GetItemNameByID = function(itemId) return itemNames[itemId] end
        _G.C_Item.GetItemIconByID = function(itemId) return itemId == 303 and "icon-303" or nil end

        local footer = assert(getSection().footer)
        footer.onTextChanged("303")
        assert.are.equal("...", getTrailerValue(footer, "previewText"))
        assert.is_false(getTrailerValue(footer, "submitEnabled"))

        itemNames[303] = "Loaded Item"
        ns.ItemStacksOptions._itemLoadFrame:GetScript("OnEvent")(ns.ItemStacksOptions._itemLoadFrame, "GET_ITEM_INFO_RECEIVED", 303)

        footer = assert(getSection().footer)
        assert.are.equal("Loaded Item", getTrailerValue(footer, "previewText"))
        assert.are.same({ registeredPage._category }, refreshCalls)
    end)

    it("refreshes pending item row labels when requested item data finishes loading", function()
        createStack("Potions")
        profile.extraIcons.itemStacks.byId[1].ids = { { itemID = 303 } }
        local itemNames = {}
        _G.C_Item.DoesItemExistByID = function(itemId) return itemId == 303 end
        _G.C_Item.GetItemNameByID = function(itemId) return itemNames[itemId] end

        assert.is_true(ns.ItemStacksOptions._itemLoadFrame:IsEventRegistered("ITEM_DATA_LOAD_RESULT"))
        assert.are.equal(ns.L["EXTRA_ICONS_ITEM_LOADING"] .. " |cff808080{303}|r", getSection().items[1].label)

        itemNames[303] = "Loaded Item"
        ns.ItemStacksOptions._itemLoadFrame:GetScript("OnEvent")(
            ns.ItemStacksOptions._itemLoadFrame,
            "ITEM_DATA_LOAD_RESULT",
            303,
            true
        )

        assert.are.equal("Loaded Item |cff808080{303}|r", getSection().items[1].label)
        assert.are.same({ registeredPage._category }, refreshCalls)
    end)

    it("refreshes pending item row labels again after item data settles", function()
        createStack("Potions")
        profile.extraIcons.itemStacks.byId[1].ids = { { itemID = 303 } }
        local itemNames = {}
        _G.C_Item.DoesItemExistByID = function(itemId) return itemId == 303 end
        _G.C_Item.GetItemNameByID = function(itemId) return itemNames[itemId] end

        assert.are.equal(ns.L["EXTRA_ICONS_ITEM_LOADING"] .. " |cff808080{303}|r", getSection().items[1].label)

        ns.ItemStacksOptions._itemLoadFrame:GetScript("OnEvent")(ns.ItemStacksOptions._itemLoadFrame, "GET_ITEM_INFO_RECEIVED", "303")
        assert.are.equal(1, #refreshCalls)

        itemNames[303] = "Loaded Item"
        TestHelpers.RunAllTimers()

        assert.are.equal("Loaded Item |cff808080{303}|r", getSection().items[1].label)
        assert.are.equal(2, #refreshCalls)
    end)

    it("adds quality rank markup after item row names", function()
        createStack("Potions")
        profile.extraIcons.itemStacks.byId[1].ids = { { itemID = 101, quality = 2 } }
        _G.C_Item.GetItemNameByID = function(itemId) return itemId == 101 and "Potion A" or nil end

        assert.are.equal(
            "Potion A |AProfessions-ChatIcon-Quality-12-Tier2|a |cff808080{101}|r",
            getSection().items[1].label
        )
        assert.are.equal(22, getSection().rowHeight)
    end)

    it("uses WoW profession quality info in previews and newly added rows", function()
        createStack("Potions")
        _G.C_Item.GetItemNameByID = function(itemId)
            return (itemId == 241288 or itemId == 241289) and "Potion of Recklessness" or nil
        end
        _G.C_Item.GetItemIconByID = function(itemId) return "icon-" .. tostring(itemId) end
        _G.C_Item.DoesItemExistByID = function(itemId) return itemId == 241288 or itemId == 241289 end
        _G.C_TradeSkillUI.GetItemCraftedQualityInfo = function(itemId)
            if itemId == 241288 then
                return { quality = 2, iconChat = "Professions-ChatIcon-Quality-12-Tier2" }
            end
            if itemId == 241289 then
                return { quality = 1, iconChat = "Professions-ChatIcon-Quality-12-Tier1" }
            end
        end

        local footer = assert(getSection().footer)
        footer.onTextChanged("241288")

        assert.are.equal(
            "Potion of Recklessness |AProfessions-ChatIcon-Quality-12-Tier2|a",
            getTrailerValue(footer, "previewText")
        )
        assert.is_true(footer.onSubmit())
        assert.same({ { itemID = 241288 } }, profile.extraIcons.itemStacks.byId[1].ids)
        assert.are.equal(
            "Potion of Recklessness |AProfessions-ChatIcon-Quality-12-Tier2|a |cff808080{241288}|r",
            getSection().items[1].label
        )

        footer = assert(getSection().footer)
        footer.onTextChanged("241289")

        assert.are.equal(
            "Potion of Recklessness |AProfessions-ChatIcon-Quality-12-Tier1|a",
            getTrailerValue(footer, "previewText")
        )
        assert.is_true(footer.onSubmit())
        assert.same({ { itemID = 241288 }, { itemID = 241289 } }, profile.extraIcons.itemStacks.byId[1].ids)
        assert.are.equal(
            "Potion of Recklessness |AProfessions-ChatIcon-Quality-12-Tier1|a |cff808080{241289}|r",
            getSection().items[2].label
        )
    end)

    it("deletes an item stack and removes viewer references", function()
        createStack("Potions")
        profile.extraIcons.viewers.utility = { { kind = "itemStack", itemStackId = 1 } }
        profile.extraIcons.viewers.main = { { kind = "itemStack", itemStackId = 1 } }

        local deleteAction = getStackAction(ns.L["DELETE"])
        assert.is_false(deleteAction.hidden())
        assert.is_true(getStackAction(ns.L["REVERT"]).hidden())
        deleteAction.onClick()

        assert.is_nil(profile.extraIcons.itemStacks.byId[1])
        assert.same({}, profile.extraIcons.itemStacks.order)
        assert.same({}, profile.extraIcons.viewers.utility)
        assert.same({}, profile.extraIcons.viewers.main)
    end)

    it("defaults selection to the first stack alphabetically and remembers valid selections", function()
        profile.extraIcons.itemStacks = {
            nextId = 4,
            order = { 1, 2, 3 },
            byId = {
                [1] = { name = "Zed", ids = {} },
                [2] = { name = "Alpha", ids = {} },
                [3] = { name = "Middle", ids = {} },
            },
        }

        local picker = getRow("selectedManagedItemStack")
    local values = picker.values()
    assert.are.equal("Alpha", values["2"])
    assert.is_nil(values[2])
        assert.are.equal("2", picker.get())

        picker.set(3)
        assert.are.equal("3", picker.get())

        profile.extraIcons.itemStacks.byId[3] = nil
        assert.are.equal("2", picker.get())
    end)

    it("updates top-level checkboxes for the selected stack", function()
        createStack("Potions")

        local instances = getRow("hideStackInInstances")
        local rated = getRow("hideStackInRatedPvp")
        local missing = getRow("showStackIfMissing")
        assert.is_false(instances.get())
        assert.is_false(rated.get())
        assert.is_false(missing.get())

        instances.set(true)
        rated.set(true)
        missing.set(true)

        assert.is_true(profile.extraIcons.itemStacks.byId[1].hideInInstances)
        assert.is_true(profile.extraIcons.itemStacks.byId[1].hideInRatedPvp)
        assert.is_true(profile.extraIcons.itemStacks.byId[1].showIfMissing)

        missing.set(false)
        assert.is_nil(profile.extraIcons.itemStacks.byId[1].showIfMissing)
    end)

    it("protects default stacks and reverts them to defaults", function()
        ns.Addon.db.defaults = { profile = { extraIcons = { itemStacks = { byId = {} } } } }
        ns.defaults = { profile = defaults }
        profile.extraIcons.itemStacks = TestHelpers.deepClone(defaults.extraIcons.itemStacks)
        profile.extraIcons.itemStacks.byId.combatPotions.name = "Custom Combat"
        profile.extraIcons.itemStacks.byId.combatPotions.ids = { { itemID = 999 } }
        profile.extraIcons.itemStacks.byId.combatPotions.hideInInstances = true

        local picker = getRow("selectedManagedItemStack")
        picker.set("combatPotions")

        assert.is_true(getRow("renameItemStack").disabled())
        assert.is_nil(getRow("renameItemStack").hidden)
        assert.is_true(getStackAction(ns.L["DELETE"]).hidden())
        assert.is_false(getStackAction(ns.L["REVERT"]).hidden())

        getRow("renameItemStack").onClick({ page = registeredPage })
        getStackAction(ns.L["DELETE"]).onClick()
        assert.is_not_nil(profile.extraIcons.itemStacks.byId.combatPotions)

        local getShownPopupName = TestHelpers.InstallPopupAutoAccept()
        getStackAction(ns.L["REVERT"]).onClick()

        assert.are.equal("ECM_CONFIRM_REVERT_ITEM_STACK", getShownPopupName())
        assert.are.equal("Combat Potions", profile.extraIcons.itemStacks.byId.combatPotions.name)
        assert.are.equal(245898, profile.extraIcons.itemStacks.byId.combatPotions.ids[1].itemID)
        assert.is_false(profile.extraIcons.itemStacks.byId.combatPotions.hideInInstances)
        assert.is_true(profile.extraIcons.itemStacks.byId.combatPotions.hideInRatedPvp)
    end)
end)
