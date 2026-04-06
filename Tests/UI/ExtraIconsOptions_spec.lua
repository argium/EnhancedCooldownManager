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

    setup(function()
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
        TestHelpers.LoadLiveConstants(ns)
        ns.L = setmetatable({}, { __index = function(_, k) return k end })
        ns.OptionUtil = {
            GetIsDisabledDelegate = function() return function() return false end end,
            CreateModuleEnabledHandler = function() return function() end end,
            MakeConfirmDialog = function() return {} end,
        }
        ns.SettingsBuilder = { RegisterSection = function(_, _, section) ns.ExtraIconsOptions = section end }
        TestHelpers.LoadChunk("UI/ExtraIconsOptions.lua", "ExtraIconsOptions")(nil, ns)
        ExtraIconsOptions = ns.ExtraIconsOptions
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
        local savedCSpell

        before_each(function()
            savedCSpell = _G.C_Spell
            _G.C_Spell = {
                GetSpellName = function(spellId)
                    if spellId == 59752 then return "Every Man for Himself" end
                    return nil
                end,
            }
        end)

        after_each(function()
            _G.C_Spell = savedCSpell
        end)

        it("returns builtin stack label", function()
            assert.are.equal("Trinket 1", ExtraIconsOptions._getEntryName({ stackKey = "trinket1" }))
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

        it("returns generic item label", function()
            assert.are.equal("Item 99999",
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
    end)

    describe("_parseIds", function()
        it("parses single ID", function()
            assert.are.same({ 12345 }, ExtraIconsOptions._parseIds("12345"))
        end)

        it("parses comma-separated IDs", function()
            assert.are.same({ 100, 200, 300 }, ExtraIconsOptions._parseIds("100, 200, 300"))
        end)

        it("returns nil for empty string", function()
            assert.is_nil(ExtraIconsOptions._parseIds(""))
        end)

        it("returns nil for nil", function()
            assert.is_nil(ExtraIconsOptions._parseIds(nil))
        end)

        it("returns nil for non-numeric input", function()
            assert.is_nil(ExtraIconsOptions._parseIds("abc"))
        end)

        it("returns nil for negative numbers", function()
            assert.is_nil(ExtraIconsOptions._parseIds("-5"))
        end)

        it("returns nil for decimals", function()
            assert.is_nil(ExtraIconsOptions._parseIds("1.5"))
        end)

        it("returns nil if any value is invalid", function()
            assert.is_nil(ExtraIconsOptions._parseIds("100, abc, 200"))
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
end)

--------------------------------------------------------------------------------
-- Settings Page (full options environment)
--------------------------------------------------------------------------------

describe("ExtraIconsOptions settings page", function()
    local originalGlobals
    local profile, defaults, SB, ns

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals(TestHelpers.OPTIONS_GLOBALS)
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        TestHelpers.SetupOptionsGlobals()
        _G.UnitRace = function() return "Human", "Human", 1 end
        profile, defaults = TestHelpers.MakeOptionsProfile()
        SB, ns = TestHelpers.SetupOptionsEnv(profile, defaults)

        TestHelpers.LoadChunk("UI/ExtraIconsOptions.lua", "ExtraIconsOptions")(nil, ns)
        ns.OptionsSections.ExtraIcons.RegisterSettings(SB)
    end)

    describe("canvas creation", function()
        it("canvas is stored on ExtraIconsOptions", function()
            local canvas = ns.ExtraIconsOptions._canvas
            assert.is_not_nil(canvas)
        end)

        it("canvas exposes viewer state", function()
            local canvas = ns.ExtraIconsOptions._canvas
            assert.is_table(canvas._viewerRowPools)
            assert.is_table(canvas._customForm)
            assert.is_table(canvas._viewerHeaders)
            assert.is_table(canvas._viewerEmptyLabels)
        end)

        it("canvas has enabled checkbox", function()
            local canvas = ns.ExtraIconsOptions._canvas
            assert.is_not_nil(canvas._enabledCheck)
        end)

        it("canvas has content region", function()
            local canvas = ns.ExtraIconsOptions._canvas
            assert.is_not_nil(canvas._contentRegion)
        end)

        it("creates a canvas subcategory", function()
            assert.is_not_nil(SB.GetSubcategory(ns.L["EXTRA_ICONS"]))
        end)
    end)
end)
