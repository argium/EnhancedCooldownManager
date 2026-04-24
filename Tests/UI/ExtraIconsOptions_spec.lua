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
    local originalCreateColor

    setup(function()
        originalCreateColor = _G.CreateColor
        _G.CreateColor = function(r, g, b, a)
            return { r = r, g = g, b = b, a = a or 1 }
        end

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
        TestHelpers.LoadChunk("UI/ExtraIconsOptions.lua", "ExtraIconsOptions")(nil, ns)
        ExtraIconsOptions = ns.ExtraIconsOptions
    end)

    teardown(function()
        _G.CreateColor = originalCreateColor
    end)

    describe("_isStackKeyPresent", function()
        it("finds stackKey in utility viewer", function()
            local viewers = { utility = { { stackKey = "trinket1" } }, main = {} }
            assert.is_true(ExtraIconsOptions._isStackKeyPresent(viewers, "trinket1"))
        end)

        it("finds stackKey in main viewer", function()
            local viewers = { utility = {}, main = { { stackKey = "healthstones" } } }
            assert.is_true(ExtraIconsOptions._isStackKeyPresent(viewers, "healthstones"))
        end)

        it("returns false when absent", function()
            local viewers = { utility = { { stackKey = "trinket1" } }, main = {} }
            assert.is_false(ExtraIconsOptions._isStackKeyPresent(viewers, "trinket2"))
        end)
    end)

    describe("_isRacialPresent", function()
        it("finds racial by spellId", function()
            local viewers = { utility = { { kind = "spell", ids = { 59752 } } }, main = {} }
            assert.is_true(ExtraIconsOptions._isRacialPresent(viewers, 59752))
        end)

        it("finds racial with table-style ids", function()
            local viewers = { utility = { { kind = "spell", ids = { { spellId = 33697 } } } }, main = {} }
            assert.is_true(ExtraIconsOptions._isRacialPresent(viewers, 33697))
        end)

        it("returns false when absent", function()
            local viewers = { utility = { { kind = "spell", ids = { 59752 } } }, main = {} }
            assert.is_false(ExtraIconsOptions._isRacialPresent(viewers, 33697))
        end)

        it("skips non-spell entries", function()
            local viewers = { utility = { { stackKey = "trinket1" } }, main = {} }
            assert.is_false(ExtraIconsOptions._isRacialPresent(viewers, 59752))
        end)
    end)

    describe("_getEntryName", function()
        local savedCSpell, savedCItem, savedInventoryItemID

        before_each(function()
            savedCSpell = _G.C_Spell
            savedCItem = _G.C_Item
            savedInventoryItemID = _G.GetInventoryItemID
            _G.C_Spell = {
                GetSpellName = function(spellId)
                    if spellId == 59752 then return "Every Man for Himself" end
                    return nil
                end,
            }
            _G.C_Item = {
                GetItemNameByID = function(itemId)
                    if itemId == 99999 then return "Test Item" end
                    if itemId == 10001 then return "Gladiator's Badge" end
                    return nil
                end,
                DoesItemExistByID = function(itemId)
                    return itemId == 99999 or itemId == 10001
                end,
                RequestLoadItemDataByID = function() end,
            }
            _G.GetInventoryItemID = function(_, slotId)
                return slotId == 13 and 10001 or nil
            end
        end)

        after_each(function()
            _G.C_Spell = savedCSpell
            _G.C_Item = savedCItem
            _G.GetInventoryItemID = savedInventoryItemID
        end)

        it("returns builtin stack label", function()
            assert.are.equal("Trinket 1 [Gladiator's Badge]", ExtraIconsOptions._getEntryName({ stackKey = "trinket1" }))
            assert.are.equal("Combat Potions", ExtraIconsOptions._getEntryName({ stackKey = "combatPotions" }))
        end)

        it("returns spell name from API for racial spells", function()
            assert.are.equal("Every Man for Himself",
                ExtraIconsOptions._getEntryName({ kind = "spell", ids = { 59752 } }))
        end)

        it("falls back to spell ID when API returns nil", function()
            assert.are.equal("Spell 12345",
                ExtraIconsOptions._getEntryName({ kind = "spell", ids = { 12345 } }))
        end)

        it("returns item name from API for item entries", function()
            assert.are.equal("Test Item",
                ExtraIconsOptions._getEntryName({ kind = "item", ids = { { itemID = 99999 } } }))
        end)

        it("returns Unknown for unrecognized entry", function()
            assert.are.equal("Unknown", ExtraIconsOptions._getEntryName({}))
        end)
    end)

    describe("_addStackKey", function()
        it("appends to viewer", function()
            local profile = { extraIcons = { viewers = { utility = {}, main = {} } } }
            ExtraIconsOptions._addStackKey(profile, "utility", "trinket1")
            assert.are.equal(1, #profile.extraIcons.viewers.utility)
            assert.are.equal("trinket1", profile.extraIcons.viewers.utility[1].stackKey)
        end)

        it("creates viewer array if missing", function()
            local profile = { extraIcons = { viewers = {} } }
            ExtraIconsOptions._addStackKey(profile, "main", "healthstones")
            assert.are.equal(1, #profile.extraIcons.viewers.main)
        end)

        it("skips duplicate builtin entries across viewers", function()
            local profile = {
                extraIcons = {
                    viewers = {
                        utility = { { stackKey = "trinket1" } },
                        main = {},
                    },
                },
            }

            ExtraIconsOptions._addStackKey(profile, "main", "trinket1")

            assert.are.equal(1, #profile.extraIcons.viewers.utility)
            assert.are.equal(0, #profile.extraIcons.viewers.main)
        end)
    end)

    describe("_addRacial", function()
        it("adds spell entry with racial id", function()
            local profile = { extraIcons = { viewers = { utility = {}, main = {} } } }
            ExtraIconsOptions._addRacial(profile, "utility", 59752)
            local entry = profile.extraIcons.viewers.utility[1]
            assert.are.equal("spell", entry.kind)
            assert.are.same({ 59752 }, entry.ids)
        end)
    end)

    describe("_addCustomEntry", function()
        it("adds item entry with itemID wrappers", function()
            local profile = { extraIcons = { viewers = { utility = {}, main = {} } } }
            ExtraIconsOptions._addCustomEntry(profile, "utility", "item", { 12345 })
            local entry = profile.extraIcons.viewers.utility[1]
            assert.are.equal("item", entry.kind)
            assert.are.same({ { itemID = 12345 } }, entry.ids)
        end)

        it("adds spell entry with raw ids", function()
            local profile = { extraIcons = { viewers = { utility = {}, main = {} } } }
            ExtraIconsOptions._addCustomEntry(profile, "main", "spell", { 100, 200 })
            local entry = profile.extraIcons.viewers.main[1]
            assert.are.equal("spell", entry.kind)
            assert.are.same({ 100, 200 }, entry.ids)
        end)

        it("skips duplicate custom entries across viewers", function()
            local profile = {
                extraIcons = {
                    viewers = {
                        utility = { { kind = "spell", ids = { 12345 } } },
                        main = {},
                    },
                },
            }

            ExtraIconsOptions._addCustomEntry(profile, "main", "spell", { 12345 })

            assert.are.equal(1, #profile.extraIcons.viewers.utility)
            assert.are.equal(0, #profile.extraIcons.viewers.main)
        end)
    end)

    describe("_setEntryDisabled", function()
        it("sets and clears the disabled flag", function()
            local profile = { extraIcons = { viewers = { utility = { { stackKey = "trinket1" } } } } }

            ExtraIconsOptions._setEntryDisabled(profile, "utility", 1, true)
            assert.is_true(profile.extraIcons.viewers.utility[1].disabled)

            ExtraIconsOptions._setEntryDisabled(profile, "utility", 1, false)
            assert.is_nil(profile.extraIcons.viewers.utility[1].disabled)
        end)
    end)

    describe("_toggleBuiltinRow", function()
        it("toggles the disabled flag for persisted builtin rows", function()
            local profile = { extraIcons = { viewers = { utility = { { stackKey = "trinket1" } } } } }

            ExtraIconsOptions._toggleBuiltinRow(profile, "utility", 1, "trinket1")
            assert.is_true(profile.extraIcons.viewers.utility[1].disabled)

            ExtraIconsOptions._toggleBuiltinRow(profile, "utility", 1, "trinket1")
            assert.is_nil(profile.extraIcons.viewers.utility[1].disabled)
        end)

        it("adds missing builtin rows when toggled from a placeholder", function()
            local profile = { extraIcons = { viewers = { utility = {}, main = {} } } }

            ExtraIconsOptions._toggleBuiltinRow(profile, "utility", nil, "trinket1")

            assert.are.equal(1, #profile.extraIcons.viewers.utility)
            assert.are.equal("trinket1", profile.extraIcons.viewers.utility[1].stackKey)
            assert.is_nil(profile.extraIcons.viewers.utility[1].disabled)
        end)
    end)

    describe("_toggleCurrentRacialRow", function()
        it("adds the current racial when toggled from a placeholder", function()
            local profile = { extraIcons = { viewers = { utility = {}, main = {} } } }

            ExtraIconsOptions._toggleCurrentRacialRow(profile, "utility", nil, 59752)

            assert.are.equal(1, #profile.extraIcons.viewers.utility)
            assert.are.same({ 59752 }, profile.extraIcons.viewers.utility[1].ids)
        end)

        it("removes a persisted racial row when toggled", function()
            local profile = { extraIcons = { viewers = { utility = { { kind = "spell", ids = { 59752 } } }, main = {} } } }

            ExtraIconsOptions._toggleCurrentRacialRow(profile, "utility", 1, 59752)

            assert.are.equal(0, #profile.extraIcons.viewers.utility)
        end)
    end)

    describe("_removeEntry", function()
        it("removes at given index", function()
            local profile = { extraIcons = { viewers = { utility = {
                { stackKey = "a" }, { stackKey = "b" }, { stackKey = "c" },
            } } } }
            ExtraIconsOptions._removeEntry(profile, "utility", 2)
            assert.are.equal(2, #profile.extraIcons.viewers.utility)
            assert.are.equal("a", profile.extraIcons.viewers.utility[1].stackKey)
            assert.are.equal("c", profile.extraIcons.viewers.utility[2].stackKey)
        end)

        it("is a no-op for out-of-range index", function()
            local profile = { extraIcons = { viewers = { utility = { { stackKey = "a" } } } } }
            ExtraIconsOptions._removeEntry(profile, "utility", 5)
            assert.are.equal(1, #profile.extraIcons.viewers.utility)
        end)
    end)

    describe("_reorderEntry", function()
        it("swaps entry down", function()
            local profile = { extraIcons = { viewers = { utility = {
                { stackKey = "a" }, { stackKey = "b" },
            } } } }
            ExtraIconsOptions._reorderEntry(profile, "utility", 1, 1)
            assert.are.equal("b", profile.extraIcons.viewers.utility[1].stackKey)
            assert.are.equal("a", profile.extraIcons.viewers.utility[2].stackKey)
        end)

        it("swaps entry up", function()
            local profile = { extraIcons = { viewers = { utility = {
                { stackKey = "a" }, { stackKey = "b" },
            } } } }
            ExtraIconsOptions._reorderEntry(profile, "utility", 2, -1)
            assert.are.equal("b", profile.extraIcons.viewers.utility[1].stackKey)
            assert.are.equal("a", profile.extraIcons.viewers.utility[2].stackKey)
        end)

        it("is a no-op at boundary", function()
            local profile = { extraIcons = { viewers = { utility = {
                { stackKey = "a" }, { stackKey = "b" },
            } } } }
            ExtraIconsOptions._reorderEntry(profile, "utility", 1, -1)
            assert.are.equal("a", profile.extraIcons.viewers.utility[1].stackKey)
        end)
    end)

    describe("_moveEntry", function()
        it("transfers entry to other viewer", function()
            local profile = { extraIcons = { viewers = {
                utility = { { stackKey = "a" }, { stackKey = "b" } },
                main = { { stackKey = "c" } },
            } } }
            ExtraIconsOptions._moveEntry(profile, "utility", "main", 1)
            assert.are.equal(1, #profile.extraIcons.viewers.utility)
            assert.are.equal("b", profile.extraIcons.viewers.utility[1].stackKey)
            assert.are.equal(2, #profile.extraIcons.viewers.main)
            assert.are.equal("a", profile.extraIcons.viewers.main[2].stackKey)
        end)

        it("creates target array if missing", function()
            local profile = { extraIcons = { viewers = { utility = { { stackKey = "a" } } } } }
            ExtraIconsOptions._moveEntry(profile, "utility", "main", 1)
            assert.are.equal(0, #profile.extraIcons.viewers.utility)
            assert.are.equal(1, #profile.extraIcons.viewers.main)
        end)

        it("is a no-op for invalid index", function()
            local profile = { extraIcons = { viewers = { utility = { { stackKey = "a" } }, main = {} } } }
            ExtraIconsOptions._moveEntry(profile, "utility", "main", 5)
            assert.are.equal(1, #profile.extraIcons.viewers.utility)
            assert.are.equal(0, #profile.extraIcons.viewers.main)
        end)

        it("is a no-op when the target viewer already has the same entry", function()
            local profile = {
                extraIcons = {
                    viewers = {
                        utility = { { kind = "spell", ids = { 12345 } } },
                        main = { { kind = "spell", ids = { 12345 } } },
                    },
                },
            }

            ExtraIconsOptions._moveEntry(profile, "utility", "main", 1)

            assert.are.equal(1, #profile.extraIcons.viewers.utility)
            assert.are.equal(1, #profile.extraIcons.viewers.main)
        end)
    end)

    describe("_parseSingleId", function()
        it("parses a single integer ID", function()
            assert.are.equal(12345, ExtraIconsOptions._parseSingleId("12345"))
        end)

        it("returns nil for empty or invalid input", function()
            assert.is_nil(ExtraIconsOptions._parseSingleId(""))
            assert.is_nil(ExtraIconsOptions._parseSingleId("abc"))
            assert.is_nil(ExtraIconsOptions._parseSingleId("1.5"))
            assert.is_nil(ExtraIconsOptions._parseSingleId("-4"))
        end)
    end)

    describe("_resolveDraftEntryPreview", function()
        local savedCSpell, savedCItem

        before_each(function()
            savedCSpell = _G.C_Spell
            savedCItem = _G.C_Item
            _G.C_Spell = {
                GetSpellName = function(spellId)
                    return spellId == 12345 and "Test Spell" or nil
                end,
                GetSpellTexture = function(spellId)
                    return spellId == 12345 and "spell-tex" or nil
                end,
            }
            _G.C_Item = {
                DoesItemExistByID = function(itemId)
                    return itemId == 777
                end,
                GetItemNameByID = function(itemId)
                    return itemId == 777 and "Test Item" or nil
                end,
                GetItemIconByID = function(itemId)
                    return itemId == 777 and "item-tex" or nil
                end,
                RequestLoadItemDataByID = function() end,
            }
        end)

        after_each(function()
            _G.C_Spell = savedCSpell
            _G.C_Item = savedCItem
        end)

        it("returns spell preview text and icon", function()
            local status, name, icon = ExtraIconsOptions._resolveDraftEntryPreview("spell", "12345")
            assert.are.equal("resolved", status)
            assert.are.equal("Test Spell", name)
            assert.are.equal("spell-tex", icon)
        end)

        it("returns item preview text and icon", function()
            local status, name, icon = ExtraIconsOptions._resolveDraftEntryPreview("item", "777")
            assert.are.equal("resolved", status)
            assert.are.equal("Test Item", name)
            assert.are.equal("item-tex", icon)
        end)

        it("returns pending for items that exist but are not loaded yet", function()
            _G.C_Item = {
                DoesItemExistByID = function(itemId)
                    return itemId == 555
                end,
                GetItemNameByID = function()
                    return nil
                end,
                GetItemIconByID = function(itemId)
                    return itemId == 555 and "pending-item-tex" or nil
                end,
                RequestLoadItemDataByID = function() end,
            }

            local status, name, icon = ExtraIconsOptions._resolveDraftEntryPreview("item", "555")
            assert.are.equal("pending", status)
            assert.is_nil(name)
            assert.are.equal("pending-item-tex", icon)
        end)
    end)

    describe("_otherViewer", function()
        it("utility returns main", function()
            assert.are.equal("main", ExtraIconsOptions._otherViewer("utility"))
        end)

        it("main returns utility", function()
            assert.are.equal("utility", ExtraIconsOptions._otherViewer("main"))
        end)
    end)

    describe("_getEntryIcon", function()
        local savedTexture, savedCItem, savedCSpell

        before_each(function()
            savedTexture = _G.GetInventoryItemTexture
            savedCItem = _G.C_Item
            savedCSpell = _G.C_Spell
            _G.GetInventoryItemTexture = function(_, slotId)
                return slotId == 13 and "trinket1-tex" or nil
            end
            _G.C_Item = {
                GetItemIconByID = function(itemId)
                    if itemId == 245898 then return "potion-tex" end
                    if itemId == 99999 then return "custom-item-tex" end
                    return nil
                end,
            }
            _G.C_Spell = {
                GetSpellTexture = function(spellId)
                    if spellId == 59752 then return "racial-tex" end
                    if spellId == 12345 then return "spell-tex" end
                    return nil
                end,
            }
        end)

        after_each(function()
            _G.GetInventoryItemTexture = savedTexture
            _G.C_Item = savedCItem
            _G.C_Spell = savedCSpell
        end)

        it("returns equip slot texture for trinket stacks", function()
            assert.are.equal("trinket1-tex",
                ExtraIconsOptions._getEntryIcon({ stackKey = "trinket1" }))
        end)

        it("returns item icon for item stacks", function()
            assert.are.equal("potion-tex",
                ExtraIconsOptions._getEntryIcon({ stackKey = "combatPotions" }))
        end)

        it("returns spell texture for spell entries", function()
            assert.are.equal("racial-tex",
                ExtraIconsOptions._getEntryIcon({ kind = "spell", ids = { 59752 } }))
        end)

        it("returns spell texture for table-style spell ids", function()
            assert.are.equal("spell-tex",
                ExtraIconsOptions._getEntryIcon({ kind = "spell", ids = { { spellId = 12345 } } }))
        end)

        it("returns item icon for custom item entries", function()
            assert.are.equal("custom-item-tex",
                ExtraIconsOptions._getEntryIcon({ kind = "item", ids = { { itemID = 99999 } } }))
        end)

        it("returns nil for unknown entry", function()
            assert.is_nil(ExtraIconsOptions._getEntryIcon({}))
        end)

        it("returns nil for unknown stackKey", function()
            assert.is_nil(ExtraIconsOptions._getEntryIcon({ stackKey = "nonexistent" }))
        end)
    end)

    describe("_isRacialForCurrentPlayer", function()
        local savedUnitRace

        before_each(function()
            savedUnitRace = _G.UnitRace
        end)

        after_each(function()
            _G.UnitRace = savedUnitRace
        end)

        it("returns true for non-spell entries", function()
            _G.UnitRace = function() return "Human", "Human", 1 end
            assert.is_true(ExtraIconsOptions._isRacialForCurrentPlayer({ stackKey = "trinket1" }))
        end)

        it("returns true for current race's racial", function()
            _G.UnitRace = function() return "Human", "Human", 1 end
            assert.is_true(ExtraIconsOptions._isRacialForCurrentPlayer({ kind = "spell", ids = { 59752 } }))
        end)

        it("returns false for another race's racial", function()
            _G.UnitRace = function() return "Human", "Human", 1 end
            -- Orc racial (Blood Fury = 33697)
            assert.is_false(ExtraIconsOptions._isRacialForCurrentPlayer({ kind = "spell", ids = { 33697 } }))
        end)

        it("returns true for non-racial spell entries", function()
            _G.UnitRace = function() return "Human", "Human", 1 end
            assert.is_true(ExtraIconsOptions._isRacialForCurrentPlayer({ kind = "spell", ids = { 12345 } }))
        end)

        it("returns false for table-style racial ids from another race", function()
            _G.UnitRace = function() return "Orc", "Orc", 2 end
            -- Human racial (Every Man for Himself = 59752)
            assert.is_false(ExtraIconsOptions._isRacialForCurrentPlayer(
                { kind = "spell", ids = { { spellId = 59752 } } }))
        end)

        it("returns true when UnitRace returns unknown race", function()
            _G.UnitRace = function() return "Unknown", "Unknown", 99 end
            assert.is_true(ExtraIconsOptions._isRacialForCurrentPlayer({ kind = "spell", ids = { 33697 } }))
        end)
    end)

    describe("_isCurrentRacialEntry", function()
        local savedUnitRace

        before_each(function()
            savedUnitRace = _G.UnitRace
            _G.UnitRace = function() return "Human", "Human", 1 end
        end)

        after_each(function()
            _G.UnitRace = savedUnitRace
        end)

        it("returns true for the current player's racial", function()
            assert.is_true(ExtraIconsOptions._isCurrentRacialEntry({ kind = "spell", ids = { 59752 } }))
        end)

        it("returns false for non-racial entries", function()
            assert.is_false(ExtraIconsOptions._isCurrentRacialEntry({ stackKey = "trinket1" }))
        end)
    end)

    describe("_buildViewerRows", function()
        local savedUnitRace
        local savedCSpellBook
        local savedGetInventoryItemID
        local savedCItem

        before_each(function()
            savedUnitRace = _G.UnitRace
            savedCSpellBook = _G.C_SpellBook
            savedGetInventoryItemID = _G.GetInventoryItemID
            savedCItem = _G.C_Item
            _G.UnitRace = function() return "Human", "Human", 1 end
            _G.C_SpellBook = {
                IsSpellKnown = function()
                    return false
                end,
            }
            _G.GetInventoryItemID = function(_, slotId)
                if slotId == 13 then return 10001 end
                if slotId == 14 then return 10002 end
                return nil
            end
            _G.C_Item = {
                GetItemSpell = function(itemId)
                    if itemId == 10001 then return "Trinket 1 Use", 90001 end
                    if itemId == 10002 then return "Trinket 2 Use", 90002 end
                    return nil, nil
                end,
            }
        end)

        after_each(function()
            _G.UnitRace = savedUnitRace
            _G.C_SpellBook = savedCSpellBook
            _G.GetInventoryItemID = savedGetInventoryItemID
            _G.C_Item = savedCItem
        end)

        it("adds builtin and current-racial placeholders to utility when absent", function()
            local viewers = {
                utility = { { stackKey = "trinket1" } },
                main = {},
            }

            local rows = ExtraIconsOptions._buildViewerRows(viewers, "utility")

            assert.are.equal("entry", rows[1].rowType)
            assert.are.equal("builtinPlaceholder", rows[2].rowType)
            assert.are.equal("trinket2", rows[2].stackKey)
            assert.are.equal("racialPlaceholder", rows[#rows].rowType)
            assert.are.equal(59752, rows[#rows].spellId)
        end)

        it("hides foreign-race racials from built rows", function()
            local viewers = {
                utility = {
                    { kind = "spell", ids = { 33697 } },
                    { stackKey = "trinket1" },
                },
                main = {},
            }

            local rows = ExtraIconsOptions._buildViewerRows(viewers, "utility")

            assert.are.equal("entry", rows[1].rowType)
            assert.are.equal("trinket1", rows[1].displayEntry.stackKey)
        end)

        it("hides stored trinket rows without an on-use spell", function()
            local viewers = {
                utility = {
                    { stackKey = "trinket1" },
                    { stackKey = "healthstones" },
                },
                main = {},
            }

            _G.C_Item = {
                GetItemSpell = function(itemId)
                    if itemId == 10002 then return "Trinket 2 Use", 90002 end
                    return nil, nil
                end,
            }

            local rows = ExtraIconsOptions._buildViewerRows(viewers, "utility")
            local hasTrinket1 = false
            for _, row in ipairs(rows) do
                if row.displayEntry and row.displayEntry.stackKey == "trinket1" then
                    hasTrinket1 = true
                    break
                end
            end

            assert.is_false(hasTrinket1)
            assert.are.equal("healthstones", rows[1].displayEntry.stackKey)
        end)

        it("keeps disabled builtins in default order", function()
            local viewers = {
                utility = {},
                main = {
                    { stackKey = "healthstones", disabled = true },
                    { kind = "spell", ids = { 59752 } },
                    { stackKey = "trinket1", disabled = true },
                },
            }

            local rows = ExtraIconsOptions._buildViewerRows(viewers, "main")

            assert.are.equal("Spell 59752", ExtraIconsOptions._getEntryName(rows[1].displayEntry))
            assert.are.equal("trinket1", rows[2].displayEntry.stackKey)
            assert.are.equal("healthstones", rows[3].displayEntry.stackKey)
        end)

        it("matches Shadowmeld from the UnitRace race file token", function()
            local viewers = {
                utility = {},
                main = {},
            }

            _G.UnitRace = function() return "Night Elf", "NightElf", 4 end

            local rows = ExtraIconsOptions._buildViewerRows(viewers, "utility")

            assert.are.equal("racialPlaceholder", rows[#rows].rowType)
            assert.are.equal(58984, rows[#rows].spellId)
        end)

        it("does not synthesize a racial placeholder when UnitRace has no matching race file token", function()
            local viewers = {
                utility = {},
                main = {},
            }

            _G.UnitRace = function() return "Night Elf", nil, 4 end
            local rows = ExtraIconsOptions._buildViewerRows(viewers, "utility")

            assert.are_not.equal("racialPlaceholder", rows[#rows].rowType)
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

        TestHelpers.LoadChunk("UI/ExtraIconsOptions.lua", "ExtraIconsOptions")(nil, ns)
        capturedPage = ns.ExtraIconsOptions.pages[1]
        local _, _, page = TestHelpers.RegisterSectionSpec(SB, ns.ExtraIconsOptions)
        registeredPage = page
        ns.ExtraIconsOptions.SetRegisteredPage(page)
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

    it("registers canonical rows and a section list instead of a canvas", function()
        local opts = ns.ExtraIconsOptions

        assert.is_table(opts._draftStates)
        assert.are.equal("checkbox", getRow("enabled").type)
        assert.are.equal("info", getRow("specialRowsLegend").type)
        assert.are.equal("sectionList", getRow("viewers").type)
        assert.are.equal(ns.L["EXTRA_ICONS_SPECIAL_ROWS_LEGEND"], getRow("specialRowsLegend").value)
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

    it("maps row actions to built-in button icons", function()
        _G.C_Spell = {
            GetSpellName = function(spellId)
                return spellId == 12345 and "Test Spell" or nil
            end,
            GetSpellTexture = function(spellId)
                return spellId == 12345 and "spell-12345" or nil
            end,
        }
        profile.extraIcons.viewers.utility = {
            { stackKey = "healthstones" },
            { kind = "spell", ids = { 12345 } },
        }

        local custom = assert(findItem("utility", function(item)
            return item.label == "Test Spell"
        end))
        assert.are.equal(
            "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up",
            custom.actions.up.iconTexture
        )
        assert.are.equal(
            "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up",
            custom.actions.down.iconTexture
        )
        assert.are.equal(
            "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
            custom.actions.move.iconTexture
        )
        assert.are.equal(
            "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
            custom.actions.delete.iconTexture
        )
        assert.is_nil(custom.actions.delete.buttonTextures)

        local activeBuiltin = assert(findItem("utility", function(item)
            return item.label == "Healthstones"
        end))
        assert.are.equal(
            "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
            activeBuiltin.actions.delete.iconTexture
        )

        local builtinPlaceholder = assert(findItem("utility", function(item)
            return item.actions.delete.tooltip == ns.L["ENABLE_TOOLTIP"]
        end))
        assert.are.equal(
            "Interface\\Buttons\\UI-PlusButton-Up",
            builtinPlaceholder.actions.delete.iconTexture
        )
    end)

    it("hides trinket rows in the table when the equipped trinket has no on-use spell", function()
        profile.extraIcons.viewers.utility = {
            { stackKey = "trinket1" },
            { stackKey = "healthstones" },
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
            return item.label == "Healthstones"
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

    it("reorder, move, and remove actions operate on the stored viewers", function()
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
        spellA.actions.down.onClick()
        assert.are.same({ 23456 }, profile.extraIcons.viewers.utility[1].ids)

        spellA = assert(findItem("utility", function(item)
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

    it("reorders against the next visible row when hidden entries sit in between", function()
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
        _G.GetInventoryItemID = function(_, slotId)
            return slotId == 13 and 10001 or nil
        end
        _G.C_Item = {
            GetItemSpell = function(itemId)
                if itemId == 10001 then
                    return nil, nil
                end

                return nil, nil
            end,
            DoesItemExistByID = function()
                return false
            end,
            GetItemIconByID = function(itemId)
                return itemId == 10001 and "passive-trinket" or nil
            end,
            GetItemNameByID = function(itemId)
                return itemId == 10001 and "Passive Trinket" or nil
            end,
            RequestLoadItemDataByID = function() end,
        }

        profile.extraIcons.viewers.utility = {
            { kind = "spell", ids = { 12345 } },
            { stackKey = "trinket1" },
            { kind = "spell", ids = { 23456 } },
        }

        local spellA = assert(findItem("utility", function(item)
            return item.label == "Spell A"
        end))
        spellA.actions.down.onClick()

        assert.are.same({ 23456 }, profile.extraIcons.viewers.utility[1].ids)
        assert.are.equal("trinket1", profile.extraIcons.viewers.utility[2].stackKey)
        assert.are.same({ 12345 }, profile.extraIcons.viewers.utility[3].ids)

        spellA = assert(findItem("utility", function(item)
            return item.label == "Spell A"
        end))
        spellA.actions.up.onClick()

        assert.are.same({ 12345 }, profile.extraIcons.viewers.utility[1].ids)
        assert.are.equal("trinket1", profile.extraIcons.viewers.utility[2].stackKey)
        assert.are.same({ 23456 }, profile.extraIcons.viewers.utility[3].ids)
    end)

    it("keeps disabled builtins at the end of the active list in builtin order", function()
        profile.extraIcons.viewers.main = {
            { stackKey = "healthstones", disabled = true },
            { kind = "spell", ids = { 59752 } },
            { stackKey = "trinket1", disabled = true },
        }

        local labels = {}
        for _, item in ipairs(assert(getSection("main")).items) do
            labels[#labels + 1] = item.label
        end

        assert.are.same({
            "Spell 59752",
            "Trinket 1 [On-use Trinket 1]",
            "Healthstones",
        }, labels)
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
        placeholder.onEnter(CreateFrame("Frame"))
        assert.are.equal("ANCHOR_CURSOR", _G.GameTooltip._anchor)
        assert.are.equal(ns.L["EXTRA_ICONS_BUILTIN_PLACEHOLDER_TOOLTIP"], _G.GameTooltip._lines[1])

        local duplicateMove = assert(findItem("utility", function(item)
            return item.label == "Test Spell"
        end))
        assert.are.equal(
            ns.L["EXTRA_ICONS_DUPLICATE_MOVE_TOOLTIP"]:format(ns.L["MAIN_VIEWER_SHORT"]),
            duplicateMove.actions.move.tooltip()
        )
    end)
end)
