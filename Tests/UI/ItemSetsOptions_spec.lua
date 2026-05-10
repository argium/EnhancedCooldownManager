-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("ItemSetsOptions settings page", function()
    local originalGlobals
    local profile, defaults, SB, ns, page, registeredPage, refreshCalls, scheduledReasons

    local function getRow(rowId)
        for _, row in ipairs(page.rows) do
            if row.id == rowId then
                return row
            end
        end
    end

    local function buildSections()
        return getRow("itemSetItems").sections()
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
        profile.extraIcons.itemSets = { nextId = 1, order = {}, byId = {} }
        profile.extraIcons.viewers = { utility = {}, main = {} }

        ns.Runtime.ScheduleLayoutUpdate = function(_, reason)
            scheduledReasons[#scheduledReasons + 1] = reason
        end

        TestHelpers.CollectSettings(function()
            TestHelpers.LoadChunk("UI/ItemSetsOptions.lua", "ItemSetsOptions")(nil, ns)
            page = ns.ItemSetsOptions.page
            local _, _, registered = TestHelpers.RegisterSectionSpec(SB, {
                key = "extraIcons",
                name = ns.L["EXTRA_ICONS"],
                pages = { page },
            })
            registeredPage = registered
            ns.ItemSetsOptions.SetRegisteredPage(registeredPage)
        end)
        ns.ItemSetsOptions.EnsureItemLoadFrame()
        registeredPage.Refresh = function()
            refreshCalls[#refreshCalls + 1] = registeredPage._category
        end
    end)

    it("registers declarative rows for the item set form", function()
        assert.are.equal("itemSets", page.key)
        assert.are.equal("button", getRow("createItemSet").type)
        assert.are.equal("dropdown", getRow("selectedItemSet").type)
        assert.are.equal("sectionList", getRow("itemSetItems").type)
        assert.are.equal("button", getRow("renameItemSet").type)
        assert.are.equal("button", getRow("deleteItemSet").type)
    end)

    it("validates create names and stores stable set ids", function()
        TestHelpers.InstallPopupAutoAccept("   ")
        getRow("createItemSet").onClick({ page = registeredPage })
        assert.are.equal(0, #profile.extraIcons.itemSets.order)

        TestHelpers.InstallPopupAutoAccept("Potions")
        getRow("createItemSet").onClick({ page = registeredPage })

        assert.are.equal(1, profile.extraIcons.itemSets.order[1])
        assert.are.equal(2, profile.extraIcons.itemSets.nextId)
        assert.are.equal("Potions", profile.extraIcons.itemSets.byId[1].name)
        assert.are.same({ "OptionsChanged" }, scheduledReasons)
    end)

    it("renames a set without changing viewer references", function()
        ns.ItemSetsOptions._createSet(profile, "Potions")
        profile.extraIcons.viewers.utility = { { kind = "itemSet", itemSetId = 1 } }

        TestHelpers.InstallPopupAutoAccept("Better Potions")
        getRow("renameItemSet").onClick({ page = registeredPage })

        assert.are.equal("Better Potions", profile.extraIcons.itemSets.byId[1].name)
        assert.same({ { kind = "itemSet", itemSetId = 1 } }, profile.extraIcons.viewers.utility)
    end)

    it("adds resolved items, blocks duplicates, reorders, and removes with confirmation", function()
        ns.ItemSetsOptions._createSet(profile, "Potions")
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
        assert.are.equal(ns.L["ITEM_SET_DUPLICATE_ITEM"], getTrailerValue(footer, "previewText"))
        assert.is_false(getTrailerValue(footer, "submitEnabled"))

        footer.onTextChanged("202")
        assert.is_true(footer.onSubmit())
        assert.same({ { itemID = 101 }, { itemID = 202 } }, profile.extraIcons.itemSets.byId[1].ids)

        local firstRow = getSection().items[1]
        firstRow.actions.down.onClick()
        assert.same({ { itemID = 202 }, { itemID = 101 } }, profile.extraIcons.itemSets.byId[1].ids)

        getSection().items[1].actions.delete.onClick()
        assert.same({ { itemID = 101 } }, profile.extraIcons.itemSets.byId[1].ids)
    end)

    it("refreshes pending item previews when item data arrives", function()
        ns.ItemSetsOptions._createSet(profile, "Potions")
        local itemNames = {}
        _G.C_Item.DoesItemExistByID = function(itemId) return itemId == 303 end
        _G.C_Item.GetItemNameByID = function(itemId) return itemNames[itemId] end
        _G.C_Item.GetItemIconByID = function(itemId) return itemId == 303 and "icon-303" or nil end

        local footer = assert(getSection().footer)
        footer.onTextChanged("303")
        assert.are.equal("...", getTrailerValue(footer, "previewText"))
        assert.is_false(getTrailerValue(footer, "submitEnabled"))

        itemNames[303] = "Loaded Item"
        ns.ItemSetsOptions._itemLoadFrame:GetScript("OnEvent")(ns.ItemSetsOptions._itemLoadFrame, "GET_ITEM_INFO_RECEIVED", 303)

        footer = assert(getSection().footer)
        assert.are.equal("Loaded Item", getTrailerValue(footer, "previewText"))
        assert.are.same({ registeredPage._category }, refreshCalls)
    end)

    it("deletes a set and removes viewer references", function()
        ns.ItemSetsOptions._createSet(profile, "Potions")
        profile.extraIcons.viewers.utility = { { kind = "itemSet", itemSetId = 1 } }
        profile.extraIcons.viewers.main = { { kind = "itemSet", itemSetId = 1 } }

        getRow("deleteItemSet").onClick({ page = registeredPage })

        assert.is_nil(profile.extraIcons.itemSets.byId[1])
        assert.same({}, profile.extraIcons.itemSets.order)
        assert.same({}, profile.extraIcons.viewers.utility)
        assert.same({}, profile.extraIcons.viewers.main)
    end)
end)
