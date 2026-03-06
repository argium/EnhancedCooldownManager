-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("ItemIconsStore", function()
    local originalGlobals
    local addonNS

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "ECM",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        _G.ECM = {
            Constants = {},
            OptionUtil = {
                SetModuleEnabled = function() end,
            },
            ScheduleLayoutUpdate = function() end,
            SettingsBuilder = { RegisterSection = function() end },
        }
        TestHelpers.SetupItemIconsConstants(_G.ECM.Constants)
        _G.ECM.Constants.RACE_RACIALS = {
            Tauren = { 20549 },
        }

        _G.StaticPopupDialogs = _G.StaticPopupDialogs or {}
        _G.StaticPopup_Show = function() end
        _G.YES = "Yes"
        _G.NO = "No"
        _G.UnitRace = function() return "Tauren", "Tauren" end
        _G.GameTooltip = {
            SetOwner = function() end,
            SetItemByID = function() end,
            SetSpellByID = function() end,
            Show = function() end,
            Hide = function() end,
        }

        addonNS = {
            Addon = {
                db = {
                    profile = {
                        itemIcons = {
                            enabled = true,
                            essential = {},
                            utility = {},
                        },
                    },
                },
            },
        }

        TestHelpers.LoadChunk("UI/ItemIconsStore.lua", "Unable to load UI/ItemIconsStore.lua")(nil, addonNS)
    end)

    it("returns empty table when viewer key has no entries", function()
        local entries = ECM.ItemIconsStore.GetEntries("essential")
        assert.are.same({}, entries)
    end)

    it("adds an item entry", function()
        local ok = ECM.ItemIconsStore.AddEntry("utility", "item", 12345)
        assert.is_true(ok)

        local entries = ECM.ItemIconsStore.GetEntries("utility")
        assert.are.equal(1, #entries)
        assert.are.equal("item", entries[1].type)
        assert.are.equal(12345, entries[1].id)
    end)

    it("prevents duplicate entries", function()
        ECM.ItemIconsStore.AddEntry("utility", "item", 99)
        local ok = ECM.ItemIconsStore.AddEntry("utility", "item", 99)
        assert.is_false(ok)
        assert.are.equal(1, #ECM.ItemIconsStore.GetEntries("utility"))
    end)

    it("allows same id with different type", function()
        ECM.ItemIconsStore.AddEntry("utility", "item", 99)
        local ok = ECM.ItemIconsStore.AddEntry("utility", "spell", 99)
        assert.is_true(ok)
        assert.are.equal(2, #ECM.ItemIconsStore.GetEntries("utility"))
    end)

    it("removes an entry by index", function()
        ECM.ItemIconsStore.AddEntry("essential", "item", 1)
        ECM.ItemIconsStore.AddEntry("essential", "item", 2)
        ECM.ItemIconsStore.AddEntry("essential", "item", 3)

        ECM.ItemIconsStore.RemoveEntry("essential", 2)

        local entries = ECM.ItemIconsStore.GetEntries("essential")
        assert.are.equal(2, #entries)
        assert.are.equal(1, entries[1].id)
        assert.are.equal(3, entries[2].id)
    end)

    it("moves an entry up", function()
        ECM.ItemIconsStore.AddEntry("utility", "item", 10)
        ECM.ItemIconsStore.AddEntry("utility", "item", 20)
        ECM.ItemIconsStore.AddEntry("utility", "item", 30)

        ECM.ItemIconsStore.MoveEntry("utility", 3, 1)

        local entries = ECM.ItemIconsStore.GetEntries("utility")
        assert.are.equal(30, entries[1].id)
        assert.are.equal(10, entries[2].id)
        assert.are.equal(20, entries[3].id)
    end)

    it("moves an entry down", function()
        ECM.ItemIconsStore.AddEntry("utility", "item", 10)
        ECM.ItemIconsStore.AddEntry("utility", "item", 20)
        ECM.ItemIconsStore.AddEntry("utility", "item", 30)

        ECM.ItemIconsStore.MoveEntry("utility", 1, 2)

        local entries = ECM.ItemIconsStore.GetEntries("utility")
        assert.are.equal(20, entries[1].id)
        assert.are.equal(10, entries[2].id)
        assert.are.equal(30, entries[3].id)
    end)

    it("ignores out-of-bounds move", function()
        ECM.ItemIconsStore.AddEntry("utility", "item", 10)
        ECM.ItemIconsStore.MoveEntry("utility", 0, 1)
        ECM.ItemIconsStore.MoveEntry("utility", 1, 5)

        local entries = ECM.ItemIconsStore.GetEntries("utility")
        assert.are.equal(1, #entries)
        assert.are.equal(10, entries[1].id)
    end)

    describe("TransferEntry", function()
        it("moves entry between viewers", function()
            ECM.ItemIconsStore.AddEntry("essential", "item", 10)
            ECM.ItemIconsStore.AddEntry("essential", "item", 20)
            ECM.ItemIconsStore.AddEntry("utility", "item", 30)

            ECM.ItemIconsStore.TransferEntry("essential", 1, "utility", 1)

            local ess = ECM.ItemIconsStore.GetEntries("essential")
            local util = ECM.ItemIconsStore.GetEntries("utility")
            assert.are.equal(1, #ess)
            assert.are.equal(20, ess[1].id)
            assert.are.equal(2, #util)
            assert.are.equal(10, util[1].id)
            assert.are.equal(30, util[2].id)
        end)

        it("clamps toIndex to list bounds", function()
            ECM.ItemIconsStore.AddEntry("essential", "item", 10)

            ECM.ItemIconsStore.TransferEntry("essential", 1, "utility", 99)

            assert.are.equal(0, #ECM.ItemIconsStore.GetEntries("essential"))
            local util = ECM.ItemIconsStore.GetEntries("utility")
            assert.are.equal(1, #util)
            assert.are.equal(10, util[1].id)
        end)

        it("is no-op for invalid source index", function()
            ECM.ItemIconsStore.AddEntry("essential", "item", 10)
            ECM.ItemIconsStore.TransferEntry("essential", 5, "utility", 1)

            assert.are.equal(1, #ECM.ItemIconsStore.GetEntries("essential"))
            assert.are.equal(0, #ECM.ItemIconsStore.GetEntries("utility"))
        end)
    end)

    describe("HasEntry", function()
        it("finds entry across viewers", function()
            ECM.ItemIconsStore.AddEntry("essential", "spell", 100)
            assert.is_true(ECM.ItemIconsStore.HasEntry("spell", 100))
        end)

        it("returns false for missing entry", function()
            assert.is_false(ECM.ItemIconsStore.HasEntry("spell", 99999))
        end)

        it("distinguishes by type", function()
            ECM.ItemIconsStore.AddEntry("utility", "item", 100)
            assert.is_true(ECM.ItemIconsStore.HasEntry("item", 100))
            assert.is_false(ECM.ItemIconsStore.HasEntry("spell", 100))
        end)
    end)

    describe("HasAllDefaults", function()
        it("returns true when all defaults present in utility", function()
            ECM.ItemIconsStore.SetEntries("utility", {
                { type = "item", id = 245898 },
                { type = "item", id = 5512 },
                { type = "item", id = 999 },
            })
            assert.is_true(ECM.ItemIconsStore.HasAllDefaults(ECM.Constants.ITEM_ICONS_DEFAULT_UTILITY))
        end)

        it("returns false when some defaults missing", function()
            ECM.ItemIconsStore.SetEntries("utility", {
                { type = "item", id = 245898 },
            })
            assert.is_false(ECM.ItemIconsStore.HasAllDefaults(ECM.Constants.ITEM_ICONS_DEFAULT_UTILITY))
        end)

        it("returns true when defaults are split across viewers", function()
            ECM.ItemIconsStore.SetEntries("essential", {
                { type = "item", id = 245898 },
            })
            ECM.ItemIconsStore.SetEntries("utility", {
                { type = "item", id = 5512 },
            })
            assert.is_true(ECM.ItemIconsStore.HasAllDefaults(ECM.Constants.ITEM_ICONS_DEFAULT_UTILITY))
        end)

        it("returns true when all defaults in essential only", function()
            ECM.ItemIconsStore.SetEntries("essential", {
                { type = "item", id = 245898 },
                { type = "item", id = 5512 },
            })
            assert.is_true(ECM.ItemIconsStore.HasAllDefaults(ECM.Constants.ITEM_ICONS_DEFAULT_UTILITY))
        end)
    end)

    it("restores defaults at the top without duplicating", function()
        ECM.ItemIconsStore.AddEntry("utility", "item", 245898)

        ECM.ItemIconsStore.RestoreDefaults("utility", ECM.Constants.ITEM_ICONS_DEFAULT_UTILITY)

        local entries = ECM.ItemIconsStore.GetEntries("utility")
        assert.are.equal(2, #entries)
        assert.are.equal(245898, entries[1].id)
        assert.are.equal(5512, entries[2].id)
    end)

    it("restores racials defaults", function()
        ECM.ItemIconsStore.RestoreDefaults("essential", ECM.Constants.ITEM_ICONS_DEFAULT_RACIALS)

        local entries = ECM.ItemIconsStore.GetEntries("essential")
        assert.are.equal(2, #entries)
        assert.are.equal(20549, entries[1].id)
        assert.are.equal(26297, entries[2].id)
    end)

    it("moves custom entries below restored defaults", function()
        ECM.ItemIconsStore.AddEntry("utility", "item", 999)
        ECM.ItemIconsStore.AddEntry("utility", "item", 245898)
        ECM.ItemIconsStore.AddEntry("utility", "item", 888)

        ECM.ItemIconsStore.RestoreDefaults("utility", ECM.Constants.ITEM_ICONS_DEFAULT_UTILITY)

        local entries = ECM.ItemIconsStore.GetEntries("utility")
        assert.are.equal(4, #entries)
        assert.are.equal(245898, entries[1].id)
        assert.are.equal(5512, entries[2].id)
        assert.are.equal(999, entries[3].id)
        assert.are.equal(888, entries[4].id)
    end)

    it("set entries replaces all entries", function()
        ECM.ItemIconsStore.AddEntry("utility", "item", 1)
        ECM.ItemIconsStore.AddEntry("utility", "item", 2)

        ECM.ItemIconsStore.SetEntries("utility", { { type = "spell", id = 999 } })

        local entries = ECM.ItemIconsStore.GetEntries("utility")
        assert.are.equal(1, #entries)
        assert.are.equal("spell", entries[1].type)
        assert.are.equal(999, entries[1].id)
    end)

    it("essential and utility viewers are independent", function()
        ECM.ItemIconsStore.AddEntry("essential", "spell", 100)
        ECM.ItemIconsStore.AddEntry("utility", "item", 200)

        assert.are.equal(1, #ECM.ItemIconsStore.GetEntries("essential"))
        assert.are.equal(1, #ECM.ItemIconsStore.GetEntries("utility"))
        assert.are.equal(100, ECM.ItemIconsStore.GetEntries("essential")[1].id)
        assert.are.equal(200, ECM.ItemIconsStore.GetEntries("utility")[1].id)
    end)

    it("initializes itemIcons table if nil", function()
        addonNS.Addon.db.profile.itemIcons = nil

        ECM.ItemIconsStore.AddEntry("utility", "item", 42)

        assert.is_table(addonNS.Addon.db.profile.itemIcons)
        assert.are.equal(1, #addonNS.Addon.db.profile.itemIcons.utility)
    end)
end)
