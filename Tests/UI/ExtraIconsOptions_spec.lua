-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

--------------------------------------------------------------------------------
-- Data Helpers (lightweight: only Constants needed)
--------------------------------------------------------------------------------

describe("ExtraIconsOptions data helpers", function()
    local ExtraIconsOptions, ns
    local originalCreateAtlasMarkup, originalCreateColor, originalCTradeSkillUI

    setup(function()
        originalCreateAtlasMarkup = _G.CreateAtlasMarkup
        originalCreateColor = _G.CreateColor
        originalCTradeSkillUI = _G.C_TradeSkillUI
        _G.CreateAtlasMarkup = function(atlas)
            return "|A" .. tostring(atlas) .. "|a"
        end
        _G.CreateColor = function(r, g, b, a)
            return { r = r, g = g, b = b, a = a or 1 }
        end
        _G.C_TradeSkillUI = {
            GetItemCraftedQualityInfo = function(itemId)
                return itemId == 245898 and { quality = 2, iconChat = "Professions-ChatIcon-Quality-12-Tier2" } or nil
            end,
            GetItemReagentQualityInfo = function()
                return nil
            end,
        }

        ns = {}
        _G.Enum = {
            PowerType = {
                Mana = 0, Rage = 1, Focus = 2, Energy = 3, RunicPower = 6,
                LunarPower = 8, Maelstrom = 11, Insanity = 13, Fury = 17,
                ArcaneCharges = 16, Chi = 12, ComboPoints = 4, Essence = 19,
                HolyPower = 9, SoulShards = 7,
            },
        }
        _G.StaticPopupDialogs = _G.StaticPopupDialogs or {}
        _G.C_SpellBook = {
            IsSpellKnown = function()
                return false
            end,
        }
        TestHelpers.LoadLiveConstants(ns)
        ns.L = setmetatable({}, { __index = function(_, k) return k end })
        ns.OptionUtil = {
            GetIsDisabledDelegate = function() return function() return false end end,
            CreateModuleEnabledHandler = function() return function() end end,
            MakeConfirmDialog = function() return {} end,
        }
        ns.Addon = {
            db = {
                profile = {
                    extraIcons = {
                        itemStacks = {
                            nextId = 1,
                            order = { "combatPotions" },
                            byId = {
                                combatPotions = {
                                    name = "Combat Potions",
                                    ids = { { itemID = 245898 } },
                                },
                                healthstones = {
                                    name = "Healthstones",
                                    ids = { { itemID = 5512 } },
                                },
                            },
                        },
                    },
                },
            },
        }
        TestHelpers.LoadChunk("UI/ExtraIconsShared.lua", "ExtraIconsShared")(nil, ns)
        TestHelpers.LoadChunk("UI/ExtraIconsOptions.lua", "ExtraIconsOptions")(nil, ns)
        ExtraIconsOptions = ns.ExtraIconsOptions
    end)

    teardown(function()
        _G.CreateAtlasMarkup = originalCreateAtlasMarkup
        _G.CreateColor = originalCreateColor
        _G.C_TradeSkillUI = originalCTradeSkillUI
    end)

    describe("ExtraIconsShared.ParseSingleId", function()
        it("parses a single integer ID", function()
            assert.are.equal(12345, ns.ExtraIconsShared.ParseSingleId("12345"))
        end)

        it("returns nil for empty or invalid input", function()
            assert.is_nil(ns.ExtraIconsShared.ParseSingleId(""))
            assert.is_nil(ns.ExtraIconsShared.ParseSingleId("abc"))
            assert.is_nil(ns.ExtraIconsShared.ParseSingleId("1.5"))
            assert.is_nil(ns.ExtraIconsShared.ParseSingleId("-4"))
        end)
    end)

    describe("GetItemQualityMarkup", function()
        it("formats quality rank markup for item entries", function()
            assert.are.equal(
                "|AProfessions-ChatIcon-Quality-12-Tier2|a",
                ExtraIconsOptions.GetItemQualityMarkup({ itemID = 245898 })
            )
            assert.is_nil(ExtraIconsOptions.GetItemQualityMarkup({ itemID = 5512 }))
        end)
    end)
end)

--------------------------------------------------------------------------------
-- Settings Page (full options environment)
--------------------------------------------------------------------------------

describe("ExtraIconsOptions settings page", function()
    local originalGlobals
    local profile, defaults, SB, ns, capturedPage, registeredPage, refreshCalls, scheduledReasons, previewCalls

    local function getRow(rowId)
        local rows = assert(capturedPage and capturedPage.rows)
        for _, row in ipairs(rows) do
            if row.id == rowId then
                return row
            end
        end
    end

    local function buildSections()
        local row = assert(getRow("viewers"))
        return assert(row.sections())
    end

    local function getSection(sectionKey)
        for _, section in ipairs(buildSections()) do
            if section.key == sectionKey then
                return section
            end
        end
    end

    local function getTrailerValue(trailer, key)
        local value = trailer[key]
        if type(value) == "function" then
            return value()
        end
        return value
    end

    local function findItem(sectionKey, predicate)
        local section = assert(getSection(sectionKey))
        for _, item in ipairs(section.items) do
            if predicate(item) then
                return item
            end
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
        _G.UnitRace = function() return "Human", "Human", 1 end
        _G.GetInventoryItemID = function(_, slotId)
            if slotId == 13 then return 10001 end
            if slotId == 14 then return 10002 end
            return nil
        end
        _G.C_Item.GetItemNameByID = function(itemId)
            if itemId == 10001 then return "On-use Trinket 1" end
            if itemId == 10002 then return "On-use Trinket 2" end
            return nil
        end
        _G.C_Item.GetItemSpell = function(itemId)
            if itemId == 10001 then return "Trinket 1 Use", 90001 end
            if itemId == 10002 then return "Trinket 2 Use", 90002 end
            return nil, nil
        end
        profile, defaults = TestHelpers.MakeOptionsProfile()
        SB, ns = TestHelpers.SetupOptionsEnv(profile, defaults)
        refreshCalls = {}
        scheduledReasons = {}
        previewCalls = {}

        profile.extraIcons = {
            enabled = true,
            showStackCount = true,
            showCharges = true,
            itemStacks = { nextId = 2, order = { 1 }, byId = { [1] = { name = "Potions", ids = { { itemID = 777 } } } } },
            viewers = {
                utility = {},
                main = {},
            },
        }
        defaults.extraIcons = TestHelpers.deepClone(profile.extraIcons)

        ns.Runtime.ScheduleLayoutUpdate = function(_, reason)
            scheduledReasons[#scheduledReasons + 1] = reason
        end
        ns.Runtime.SetLayoutPreview = function(active)
            previewCalls[#previewCalls + 1] = active
        end

        TestHelpers.CollectSettings(function()
            TestHelpers.LoadChunk("UI/ExtraIconsShared.lua", "ExtraIconsShared")(nil, ns)
            TestHelpers.LoadChunk("UI/ExtraIconsOptions.lua", "ExtraIconsOptions")(nil, ns)
            capturedPage = ns.ExtraIconsOptions.pages[1]
            local _, _, page = TestHelpers.RegisterSectionSpec(SB, ns.ExtraIconsOptions)
            registeredPage = page
            ns.ExtraIconsOptions.OnInitialize()
        end)
        ns.ExtraIconsOptions.EnsureItemLoadFrame()
        registeredPage.Refresh = function()
            refreshCalls[#refreshCalls + 1] = registeredPage._category
        end
    end)

    it("registers a page category", function()
        assert.is_not_nil(registeredPage._category)
    end)

    it("registers page-level onShow and onHide callbacks", function()
        assert.is_function(capturedPage.onShow)
        assert.is_function(capturedPage.onHide)

        capturedPage.onShow()
        capturedPage.onHide()

        assert.are.same({ true, false }, previewCalls)
    end)

    it("registers page-level defaults for the section list state", function()
        assert.is_function(capturedPage.onDefault)
        assert.is_function(capturedPage.onDefaultEnabled)
        assert.is_true(capturedPage.onDefaultEnabled())
    end)

    it("registers canonical rows and a section list instead of a canvas", function()
        local opts = ns.ExtraIconsOptions

        assert.is_table(opts._draftStates)
        assert.are.equal("checkbox", getRow("enabled").type)
        assert.are.equal("checkbox", getRow("showStackCount").type)
        assert.are.equal("checkbox", getRow("showCharges").type)
        assert.is_nil(getRow("selectedItemStack"))
        assert.is_nil(getRow("fontOverride"))
        assert.are.equal("sectionList", getRow("viewers").type)
        assert.are.equal(4, getRow("viewers").footerSpacing)
        assert.are.equal(4, #capturedPage.rows)
    end)

    it("builds utility and main sections with placeholder rows and footers", function()
        local utility = assert(getSection("utility"))
        local main = assert(getSection("main"))

        assert.are.equal(ns.L["UTILITY_VIEWER_ICONS"], utility.title)
        assert.are.equal(ns.L["MAIN_VIEWER_ICONS"], main.title)
        assert.is_not_nil(utility.footer)
        assert.is_not_nil(main.footer)
        assert.is_not_nil(findItem("utility", function(item)
            return item.actions.delete.tooltip == ns.L["ENABLE_TOOLTIP"]
        end))
        assert.is_not_nil(findItem("utility", function(item)
            return item.actions.delete.tooltip == ns.L["ADD_ENTRY"]
        end))
    end)

    it("defaults button restores extra icon settings and clears draft input", function()
        profile.extraIcons.showStackCount = false
        profile.extraIcons.viewers.utility = {
            { kind = "spell", ids = { 12345 } },
        }
        defaults.extraIcons.showStackCount = true
        defaults.extraIcons.viewers.utility = {
            { stackKey = "trinket1" },
        }

        local utilityFooter = assert(getSection("utility").footer)
        utilityFooter.onTextChanged("98765")
        utilityFooter.onToggleMode()

        capturedPage.onDefault()

        assert.is_true(profile.extraIcons.showStackCount)
        assert.are.same({ { stackKey = "trinket1" } }, profile.extraIcons.viewers.utility)
        utilityFooter = assert(getSection("utility").footer)
        assert.are.equal("Spell", utilityFooter.modeText())
        assert.are.equal("", utilityFooter.inputText())
        assert.are.same({ "OptionsChanged" }, scheduledReasons)
        assert.are.same({ registeredPage._category }, refreshCalls)
    end)

    it("keeps active racial entries fully enabled after replacing the placeholder", function()
        _G.UnitRace = function() return "Night Elf", "NightElf", 4 end
        _G.C_Spell = {
            GetSpellName = function(spellId)
                return spellId == 58984 and "Shadowmeld" or nil
            end,
            GetSpellTexture = function(spellId)
                return spellId == 58984 and "shadowmeld-tex" or nil
            end,
        }

        local racialPlaceholder = assert(findItem("utility", function(item)
            return item.actions.delete.tooltip == ns.L["ADD_ENTRY"]
        end))
        assert.is_true(racialPlaceholder.disabled)
        racialPlaceholder.actions.delete.onClick()

        local activeRacial = assert(findItem("utility", function(item)
            return item.label == "Shadowmeld"
        end))
        assert.is_false(activeRacial.disabled)
        assert.is_true(activeRacial.actions.delete.enabled)
        assert.are.equal("Interface\\Buttons\\UI-GroupLoot-Pass-Up", activeRacial.actions.delete.buttonTextures.normal)

        local popupShown = false
        _G.StaticPopup_Show = function()
            popupShown = true
        end
        activeRacial.actions.delete.onClick()

        assert.is_false(popupShown)
        assert.are.same({}, profile.extraIcons.viewers.utility)
    end)

    it("hides racial spell entries that belong to another race", function()
        _G.UnitRace = function() return "Human", "Human", 1 end
        _G.C_Spell = {
            GetSpellName = function(spellId)
                return spellId == 58984 and "Shadowmeld" or nil
            end,
            GetSpellTexture = function(spellId)
                return spellId == 58984 and "shadowmeld-tex" or nil
            end,
        }
        profile.extraIcons.viewers.utility = {
            { kind = "spell", ids = { 58984 } },
        }

        assert.is_nil(findItem("utility", function(item)
            return item.label == "Shadowmeld"
        end))
        assert.is_not_nil(findItem("utility", function(item)
            return item.actions.delete.tooltip == ns.L["ADD_ENTRY"]
        end))
    end)

    it("recognizes current racial entries stored under alternate spell ids", function()
        _G.UnitRace = function() return "Dracthyr", "Dracthyr", 52 end
        _G.C_Spell = {
            GetSpellName = function(spellId)
                return (spellId == 357214 or spellId == 368970) and "Tail Swipe" or nil
            end,
            GetSpellTexture = function(spellId)
                return (spellId == 357214 or spellId == 368970) and "tail-swipe-tex" or nil
            end,
        }
        profile.extraIcons.viewers.utility = {
            { kind = "spell", ids = { { spellId = 368970 } } },
        }

        local currentRacial = assert(findItem("utility", function(item)
            return item.label == "Tail Swipe"
        end))
        assert.are.equal(ns.L["REMOVE_TOOLTIP"], currentRacial.actions.delete.tooltip)
        assert.is_nil(findItem("utility", function(item)
            return item.actions.delete.tooltip == ns.L["ADD_ENTRY"]
        end))

        local popupShown = false
        _G.StaticPopup_Show = function()
            popupShown = true
        end
        currentRacial.actions.delete.onClick()

        assert.is_false(popupShown)
        assert.are.same({}, profile.extraIcons.viewers.utility)
    end)

    it("maps row actions to built-in button texture states", function()
        _G.C_Spell = {
            GetSpellName = function(spellId)
                return spellId == 12345 and "Test Spell" or nil
            end,
            GetSpellTexture = function(spellId)
                return spellId == 12345 and "spell-12345" or nil
            end,
        }
        profile.extraIcons.viewers.utility = {
            { stackKey = "trinket1" },
            { kind = "spell", ids = { 12345 } },
        }

        local custom = assert(findItem("utility", function(item)
            return item.label == "Test Spell"
        end))
        assert.are.equal(
            "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up",
            custom.actions.up.buttonTextures.normal
        )
        assert.are.equal(
            "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Down",
            custom.actions.up.buttonTextures.pushed
        )
        assert.are.equal(
            "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up",
            custom.actions.down.buttonTextures.normal
        )
        assert.are.equal(
            "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
            custom.actions.move.buttonTextures.normal
        )
        assert.are.equal(
            "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
            custom.actions.delete.buttonTextures.normal
        )
        assert.is_nil(custom.actions.delete.iconTexture)
        assert.are.equal("", custom.actions.up.text)
        assert.are.equal("", custom.actions.down.text)
        assert.are.equal("", custom.actions.move.text)
        assert.are.equal("", custom.actions.delete.text)

        local activeBuiltin = assert(findItem("utility", function(item)
            return type(item.label) == "string" and item.label:match("^Trinket 1") ~= nil
        end))
        assert.are.equal(
            "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
            activeBuiltin.actions.delete.buttonTextures.normal
        )
        assert.are.equal(ns.L["EXTRA_ICONS_HIDE_TOOLTIP"], activeBuiltin.actions.delete.tooltip)

        local builtinPlaceholder = assert(findItem("utility", function(item)
            return item.actions.delete.tooltip == ns.L["ENABLE_TOOLTIP"]
        end))
        assert.are.equal(
            "Interface\\Buttons\\UI-PlusButton-Up",
            builtinPlaceholder.actions.delete.buttonTextures.normal
        )
    end)

    it("hides trinket rows in the table when the equipped trinket has no on-use spell", function()
        profile.extraIcons.viewers.utility = {
            { stackKey = "trinket1" },
            { kind = "itemStack", itemStackId = 1 },
        }

        _G.GetInventoryItemID = function(_, slotId)
            return slotId == 13 and 10001 or nil
        end
        _G.C_Item.GetItemSpell = function()
            return nil, nil
        end
        _G.C_Item.GetItemNameByID = function(itemId)
            return itemId == 10001 and "Passive Trinket" or nil
        end

        assert.are.equal("trinket1", profile.extraIcons.viewers.utility[1].stackKey)
        assert.is_nil(findItem("utility", function(item)
            return type(item.label) == "string" and item.label:match("^Trinket 1") ~= nil
        end))
        assert.is_not_nil(findItem("utility", function(item)
            return item.label == "Potions"
        end))
    end)

    it("uses footer callbacks to add custom entries per viewer", function()
        _G.C_Spell = {
            GetSpellName = function(spellId)
                return spellId == 12345 and "Test Spell" or nil
            end,
            GetSpellTexture = function(spellId)
                return spellId == 12345 and "spell-tex" or nil
            end,
        }

        local footer = assert(getSection("main")).footer
        footer.onTextChanged("12345")
        assert.are.same({}, refreshCalls)

        footer = assert(getSection("main")).footer
        assert.are.equal("Test Spell", getTrailerValue(footer, "previewText"))
        assert.is_true(getTrailerValue(footer, "submitEnabled"))
        assert.is_true(footer.onSubmit())

        assert.are.equal("", ns.ExtraIconsOptions._draftStates.main.idText)
        assert.are.equal(1, #profile.extraIcons.viewers.main)
        assert.are.equal("spell", profile.extraIcons.viewers.main[1].kind)
        assert.are.same({ 12345 }, profile.extraIcons.viewers.main[1].ids)
        local category = registeredPage._category
        assert.are.same({ category }, refreshCalls)
        assert.are.same({ "OptionsChanged" }, scheduledReasons)
    end)

    it("keeps footer add disabled until the draft ID resolves", function()
        _G.C_Spell = {
            GetSpellName = function(spellId)
                return spellId == 12345 and "Test Spell" or nil
            end,
            GetSpellTexture = function(spellId)
                return spellId == 12345 and "spell-tex" or nil
            end,
        }

        local footer = assert(getSection("main")).footer
        assert.is_false(getTrailerValue(footer, "submitEnabled"))
        assert.is_false(footer.onSubmit())
        assert.are.equal(0, #profile.extraIcons.viewers.main)

        footer.onTextChanged("99999")
        footer = assert(getSection("main")).footer
        assert.is_false(getTrailerValue(footer, "submitEnabled"))
        assert.is_false(footer.onSubmit())
        assert.are.equal(0, #profile.extraIcons.viewers.main)

        footer.onTextChanged("12345")
        footer = assert(getSection("main")).footer
        assert.is_true(getTrailerValue(footer, "submitEnabled"))
    end)

    it("shows pending item previews and refreshes when item data arrives", function()
        local itemNames = {}

        _G.C_Item = {
            GetItemSpell = function(itemId)
                if itemId == 10001 then return "Trinket 1 Use", 90001 end
                if itemId == 10002 then return "Trinket 2 Use", 90002 end
                return nil, nil
            end,
            DoesItemExistByID = function(itemId)
                return itemId == 777
            end,
            GetItemNameByID = function(itemId)
                return itemNames[itemId]
            end,
            GetItemIconByID = function(itemId)
                return itemId == 777 and "item-tex" or nil
            end,
            RequestLoadItemDataByID = function() end,
        }

        local footer = assert(getSection("utility")).footer
        footer.onToggleMode()
        footer = assert(getSection("utility")).footer
        footer.onTextChanged("777")

        footer = assert(getSection("utility")).footer
        assert.are.equal("...", getTrailerValue(footer, "previewText"))
        assert.is_false(getTrailerValue(footer, "submitEnabled"))

        itemNames[777] = "Loaded Item"
        ns.ExtraIconsOptions._itemLoadFrame:GetScript("OnEvent")(
            ns.ExtraIconsOptions._itemLoadFrame,
            "GET_ITEM_INFO_RECEIVED",
            777,
            true
        )

        footer = assert(getSection("utility")).footer
        assert.are.equal("Loaded Item", getTrailerValue(footer, "previewText"))
        assert.is_true(getTrailerValue(footer, "submitEnabled"))
    end)

    it("refreshes the category when trinket equipment changes", function()
        local category = registeredPage._category
        local eventHandler = ns.ExtraIconsOptions._itemLoadFrame:GetScript("OnEvent")

        eventHandler(ns.ExtraIconsOptions._itemLoadFrame, "PLAYER_EQUIPMENT_CHANGED", 13, true)
        eventHandler(ns.ExtraIconsOptions._itemLoadFrame, "PLAYER_EQUIPMENT_CHANGED", 1, true)

        assert.are.same({ category }, refreshCalls)
    end)

    it("blocks duplicate entries and shows which viewer already owns them", function()
        _G.C_Spell = {
            GetSpellName = function(spellId)
                return spellId == 12345 and "Test Spell" or nil
            end,
            GetSpellTexture = function(spellId)
                return spellId == 12345 and "spell-tex" or nil
            end,
        }
        profile.extraIcons.viewers.utility = {
            { kind = "spell", ids = { 12345 } },
        }

        local footer = assert(getSection("main")).footer
        footer.onTextChanged("12345")
        footer = assert(getSection("main")).footer

        assert.are.equal(
            ns.L["EXTRA_ICONS_DUPLICATE_ENTRY"]:format(ns.L["UTILITY_VIEWER_SHORT"]),
            getTrailerValue(footer, "previewText")
        )
        assert.is_false(getTrailerValue(footer, "submitEnabled"))
    end)

    it("adds selected item stacks through the Stack footer picker and blocks duplicates", function()
        _G.C_Item.GetItemIconByID = function(itemId)
            return itemId == 777 and "potion-icon" or nil
        end

        local footer = assert(getSection("main")).footer
        footer.onToggleMode()
        footer.onToggleMode()
        footer = assert(getSection("main")).footer

        assert.are.equal(ns.L["ITEM_STACK"], getTrailerValue(footer, "modeText"))
        assert.are.equal("dropdown", getTrailerValue(footer, "inputType"))
        assert.are.equal("1", getTrailerValue(footer, "inputValue"))
        assert.are.equal("Potions", getTrailerValue(footer, "inputText"))
        assert.are.equal("Potions", getTrailerValue(footer, "previewText"))
        assert.are.equal("potion-icon", getTrailerValue(footer, "previewIcon"))
        assert.is_true(getTrailerValue(footer, "submitEnabled"))
        assert.is_true(footer.onSubmit())
        assert.same({ { kind = "itemStack", itemStackId = 1 } }, profile.extraIcons.viewers.main)

        footer = assert(getSection("utility")).footer
        footer.onToggleMode()
        footer.onToggleMode()
        footer = assert(getSection("utility")).footer

        assert.are.equal(
            ns.L["EXTRA_ICONS_DUPLICATE_ENTRY"]:format(ns.L["MAIN_VIEWER_SHORT"]),
            getTrailerValue(footer, "previewText")
        )
        assert.is_false(getTrailerValue(footer, "submitEnabled"))
    end)

    it("move and remove actions operate on the stored viewers", function()
        _G.C_Spell = {
            GetSpellName = function(spellId)
                return ({
                    [12345] = "Spell A",
                    [23456] = "Spell B",
                })[spellId]
            end,
            GetSpellTexture = function(spellId)
                return "spell-" .. tostring(spellId)
            end,
        }
        profile.extraIcons.viewers.utility = {
            { kind = "spell", ids = { 12345 } },
            { kind = "spell", ids = { 23456 } },
        }

        local spellA = assert(findItem("utility", function(item)
            return item.label == "Spell A"
        end))
        spellA.actions.move.onClick()
        assert.are.equal(1, #profile.extraIcons.viewers.utility)
        assert.are.equal(1, #profile.extraIcons.viewers.main)

        local moved = assert(findItem("main", function(item)
            return item.label == "Spell A"
        end))
        moved.actions.delete.onClick()
        assert.are.equal(0, #profile.extraIcons.viewers.main)
    end)

    it("shows placeholder tooltips and duplicate-move tooltips", function()
        _G.C_Spell = {
            GetSpellName = function(spellId)
                return spellId == 12345 and "Test Spell" or nil
            end,
            GetSpellTexture = function(spellId)
                return "spell-" .. tostring(spellId)
            end,
        }
        profile.extraIcons.viewers.utility = {
            { kind = "spell", ids = { 12345 } },
        }
        profile.extraIcons.viewers.main = {
            { kind = "spell", ids = { 12345 } },
        }

        local placeholder = assert(findItem("utility", function(item)
            return item.actions.delete.tooltip == ns.L["ENABLE_TOOLTIP"]
        end))
        local tooltipOwner = CreateFrame("Frame")
        placeholder.onEnter(tooltipOwner)
        assert.are.equal("ANCHOR_NONE", _G.GameTooltip._anchor)
        assert.are.same({ "BOTTOMLEFT", tooltipOwner, "TOPRIGHT", 0, 0 }, _G.GameTooltip._point)
        assert.are.equal(ns.L["EXTRA_ICONS_BUILTIN_PLACEHOLDER_TOOLTIP"], _G.GameTooltip._lines[1])

        local duplicateMove = assert(findItem("utility", function(item)
            return item.label == "Test Spell"
        end))
        assert.are.equal(
            ns.L["EXTRA_ICONS_DUPLICATE_MOVE_TOOLTIP"]:format(ns.L["MAIN_VIEWER_SHORT"]),
            duplicateMove.actions.move.tooltip()
        )
    end)

    it("uses the generic move tooltip when the destination viewer can accept the row", function()
        _G.C_Spell = {
            GetSpellName = function(spellId)
                return spellId == 12345 and "Test Spell" or nil
            end,
            GetSpellTexture = function(spellId)
                return "spell-" .. tostring(spellId)
            end,
        }
        profile.extraIcons.viewers.utility = {
            { kind = "spell", ids = { 12345 } },
        }

        local row = assert(findItem("utility", function(item)
            return item.label == "Test Spell"
        end))
        assert.are.equal(ns.L["MOVE_TO_VIEWER_TOOLTIP"], row.actions.move.tooltip())
    end)
end)
