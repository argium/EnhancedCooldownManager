-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("ClassUtil", function()
    local originalGlobals

    local UnitStub
    local CSpellStub
    local CUnitAurasStub
    local CSpellBookStub

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "ClassUtil",
            "ECM",
            "Enum",
            "UnitClass",
            "UnitPowerMax",
            "UnitPower",
            "GetShapeshiftForm",
            "C_UnitAuras",
            "C_Spell",
            "C_SpellBook",
            "CurveConstants",
            "issecretvalue",
        })

        _G.ECM = {}
        _G.ECM.DebugAssert = function() end
        _G.GetShapeshiftForm = function()
            return 0
        end
        _G.CurveConstants = { ScaleTo100 = 1 }
        _G.issecretvalue = function() return false end

        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")()
        TestHelpers.LoadStub("Enums.lua")

        UnitStub = TestHelpers.LoadStub("Unit.lua")
        CSpellStub = TestHelpers.LoadStub("C_Spell.lua")
        CUnitAurasStub = TestHelpers.LoadStub("C_UnitAuras.lua")
        CSpellBookStub = TestHelpers.LoadStub("C_SpellBook.lua")

        UnitStub.Install()
        CSpellStub.Install()
        CUnitAurasStub.Install()
        CSpellBookStub.Install()

        local chunk = assert(loadfile("Helpers/ClassUtil.lua"))
        chunk()
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        UnitStub.Reset()
        CSpellStub.Reset()
        CUnitAurasStub.Reset()
        CSpellBookStub.Reset()

        _G.GetShapeshiftForm = function()
            return 0
        end
    end)

    describe("GetResourceType", function()
        local function setAvailablePowerType(powerType)
            UnitStub.Reset()
            if powerType then
                UnitStub.SetPowerMax(powerType, 10)
            end
        end

        local function assertResourceType(classToken, specIndex, expectedResourceType, shapeshiftForm)
            local resourceType = ECM.ClassUtil.GetResourceType(classToken, specIndex, shapeshiftForm or 0)
            if expectedResourceType == nil then
                assert.is_nil(resourceType)
            else
                assert.are.equal(expectedResourceType, resourceType)
            end
        end

        local function assertResourceForSpecs(classToken, specIndexes, expectedResourceType, shapeshiftForm)
            for _, specIndex in ipairs(specIndexes) do
                assertResourceType(classToken, specIndex, expectedResourceType, shapeshiftForm)
            end
        end

        it("returns nil for all death knight specs", function()
            -- I'm not sure what the live game returns so test all
            setAvailablePowerType(Enum.PowerType.Runes)
            assertResourceForSpecs("DEATHKNIGHT", { 1, 2, 3 }, nil)
            setAvailablePowerType(Enum.PowerType.RuneBlood)
            assertResourceForSpecs("DEATHKNIGHT", { 1, 2, 3 }, nil)
            setAvailablePowerType(Enum.PowerType.RuneFrost)
            assertResourceForSpecs("DEATHKNIGHT", { 1, 2, 3 }, nil)
            setAvailablePowerType(Enum.PowerType.RuneUnholy)
            assertResourceForSpecs("DEATHKNIGHT", { 1, 2, 3 }, nil)
        end)

        it("returns souls for vengeance demon hunters", function()
            assertResourceType(
                "DEMONHUNTER",
                ECM.Constants.DEMONHUNTER_VENGEANCE_SPEC_INDEX,
                ECM.Constants.RESOURCEBAR_TYPE_VENGEANCE_SOULS
            )
        end)

        it("returns devourerNormal for devourer demon hunters when void meta aura is absent", function()
            assertResourceType(
                "DEMONHUNTER",
                ECM.Constants.DEMONHUNTER_DEVOURER_SPEC_INDEX,
                ECM.Constants.RESOURCEBAR_TYPE_DEVOURER_NORMAL
            )
        end)

        it("returns devourerMeta for devourer demon hunters when void meta aura is present", function()
            CUnitAurasStub.SetAura(ECM.Constants.SPELLID_VOID_META, { applications = 1 })
            assertResourceType(
                "DEMONHUNTER",
                ECM.Constants.DEMONHUNTER_DEVOURER_SPEC_INDEX,
                ECM.Constants.RESOURCEBAR_TYPE_DEVOURER_META
            )
        end)

        it("returns combo points for feral druids in cat form", function()
            setAvailablePowerType(Enum.PowerType.ComboPoints)
            assertResourceType("DRUID", 2, Enum.PowerType.ComboPoints, ECM.Constants.DRUID_CAT_FORM_INDEX)
        end)

        it("returns essence for all evoker specs", function()
            setAvailablePowerType(Enum.PowerType.Essence)
            assertResourceForSpecs("EVOKER", { 1, 2, 3 }, Enum.PowerType.Essence)
        end)

        it("returns nil for all hunter specs", function()
            assertResourceForSpecs("HUNTER", { 1, 2, 3 }, nil)
        end)

        it("returns arcane charges for arcane mages, nil for fire, and icicles for frost", function()
            assertResourceType("MAGE", 1, Enum.PowerType.ArcaneCharges)
            assertResourceType("MAGE", 2, nil)
            assertResourceType("MAGE", 3, ECM.Constants.RESOURCEBAR_TYPE_ICICLES)
        end)

        it("returns chi for windwalker monks, nil for brewmaster and mistweaver", function()
            setAvailablePowerType(Enum.PowerType.Chi)
            assertResourceType("MONK", ECM.Constants.MONK_WINDWALKER_SPEC_INDEX, Enum.PowerType.Chi)
            assertResourceType("MONK", ECM.Constants.MONK_BREWMASTER_SPEC_INDEX, nil)
            assertResourceType("MONK", ECM.Constants.MONK_MISTWEAVER_SPEC_INDEX, nil)
        end)

        it("returns holy power for all paladin specs", function()
            setAvailablePowerType(Enum.PowerType.HolyPower)
            assertResourceForSpecs("PALADIN", { 1, 2, 3 }, Enum.PowerType.HolyPower)
        end)

        it("returns nil for all priest specs", function()
            assertResourceForSpecs("PRIEST", { 1, 2, 3 }, nil)
        end)

        it("returns combo points for all rogue specs", function()
            setAvailablePowerType(Enum.PowerType.ComboPoints)
            assertResourceForSpecs("ROGUE", { 1, 2, 3 }, Enum.PowerType.ComboPoints)
        end)

        it("returns maelstrom weapon for enhancement shamans and nil for elemental/restoration", function()
            setAvailablePowerType(Enum.PowerType.Maelstrom)
            assertResourceType(
                "SHAMAN",
                ECM.Constants.SHAMAN_ENHANCEMENT_SPEC_INDEX,
                ECM.Constants.RESOURCEBAR_TYPE_MAELSTROM_WEAPON
            )
            assertResourceType("SHAMAN", ECM.Constants.SHAMAN_ELEMENTAL_SPEC_INDEX, nil)
            assertResourceType("SHAMAN", ECM.Constants.SHAMAN_RESTORATION_SPEC_INDEX, nil)
        end)

        it("returns soul shards for all warlock specs", function()
            setAvailablePowerType(Enum.PowerType.SoulShards)
            assertResourceForSpecs("WARLOCK", { 1, 2, 3 }, Enum.PowerType.SoulShards)
        end)

        it("returns nil for all warrior specs", function()
            assertResourceForSpecs("WARRIOR", { 1, 2, 3 }, nil)
        end)
    end)

    describe("GetCurrentMaxResourceValues", function()
        local function assertValues(resourceType, expectedMax, expectedCurrent)
            local maxValue, currentValue = ECM.ClassUtil.GetCurrentMaxResourceValues(resourceType)
            assert.are.equal(expectedMax, maxValue)
            assert.are.equal(expectedCurrent, currentValue)
        end

        it("returns souls values from spell cast count", function()
            CSpellStub.SetSpellCastCount(ECM.Constants.RESOURCEBAR_SPIRIT_BOMB_SPELLID, 4)
            assertValues(ECM.Constants.RESOURCEBAR_TYPE_VENGEANCE_SOULS, ECM.Constants.RESOURCEBAR_VENGEANCE_SOULS_MAX, 4)
        end)

        it("returns souls current value as zero when spell cast count is unavailable", function()
            assertValues(ECM.Constants.RESOURCEBAR_TYPE_VENGEANCE_SOULS, ECM.Constants.RESOURCEBAR_VENGEANCE_SOULS_MAX, 0)
        end)

        it("returns icicles values from aura stacks for frost mage", function()
            CUnitAurasStub.SetAura(ECM.Constants.RESOURCEBAR_ICICLES_SPELLID, { applications = 3 })
            assertValues(ECM.Constants.RESOURCEBAR_TYPE_ICICLES, ECM.Constants.RESOURCEBAR_ICICLES_MAX, 3)
        end)

        it("returns icicles zero stacks when no aura is present", function()
            assertValues(ECM.Constants.RESOURCEBAR_TYPE_ICICLES, ECM.Constants.RESOURCEBAR_ICICLES_MAX, 0)
        end)

        it("returns devourer meta values when collapsing star aura is active", function()
            CUnitAurasStub.SetAura(ECM.Constants.SPELLID_DEVOURER_SOUL_FRAGMENTS, { applications = 11 })
            CUnitAurasStub.SetAura(ECM.Constants.SPELLID_COLLAPSING_STAR, { applications = 15 })
            assertValues(ECM.Constants.RESOURCEBAR_TYPE_DEVOURER_META, ECM.Constants.RESOURCEBAR_COLLAPSING_STAR_MAX / 5, 3)
        end)

        it("returns devourer normal values from void fragments divided by 5", function()
            CUnitAurasStub.SetAura(ECM.Constants.SPELLID_DEVOURER_SOUL_FRAGMENTS, { applications = 10 })
            assertValues(ECM.Constants.RESOURCEBAR_TYPE_DEVOURER_NORMAL, ECM.Constants.RESOURCEBAR_DEVOURER_SOUL_FRAGMENTS_MAX / 5, 2)
        end)

        it("returns devourer normal zero stacks when no aura is present", function()
            assertValues(ECM.Constants.RESOURCEBAR_TYPE_DEVOURER_NORMAL, ECM.Constants.RESOURCEBAR_DEVOURER_SOUL_FRAGMENTS_MAX / 5, 0)
        end)

        it("returns base maelstrom max when raging maelstrom talent is unknown", function()
            CSpellBookStub.SetSpellKnown(ECM.Constants.RESOURCEBAR_RAGING_MAELSTROM_SPELLID, false)
            CUnitAurasStub.SetAura(ECM.Constants.SPELLID_MAELSTROM_WEAPON, { applications = 3 })
            assertValues(
                ECM.Constants.RESOURCEBAR_TYPE_MAELSTROM_WEAPON,
                ECM.Constants.RESOURCEBAR_MAELSTROM_WEAPON_MAX_BASE,
                3
            )
        end)

        it("returns talented maelstrom max when raging maelstrom is known", function()
            CSpellBookStub.SetSpellKnown(ECM.Constants.RESOURCEBAR_RAGING_MAELSTROM_SPELLID, true)
            CUnitAurasStub.SetAura(ECM.Constants.SPELLID_MAELSTROM_WEAPON, { applications = 6 })
            assertValues(
                ECM.Constants.RESOURCEBAR_TYPE_MAELSTROM_WEAPON,
                ECM.Constants.RESOURCEBAR_MAELSTROM_WEAPON_MAX_TALENTED,
                6
            )
        end)

        it("returns numeric resource values using UnitPowerMax and UnitPower", function()
            UnitStub.SetPowerMax(Enum.PowerType.HolyPower, 5)
            UnitStub.SetPower(Enum.PowerType.HolyPower, 2)
            assertValues(Enum.PowerType.HolyPower, 5, 2)
        end)

        it("returns zero current value when UnitPower returns nil", function()
            UnitStub.SetPowerMax(Enum.PowerType.ComboPoints, 5)
            UnitStub.SetPower(Enum.PowerType.ComboPoints, nil)
            assertValues(Enum.PowerType.ComboPoints, 5, 0)
        end)

        it("returns nil values when no resource type is provided", function()
            local maxValue, currentValue = ECM.ClassUtil.GetCurrentMaxResourceValues(nil)
            assert.is_nil(maxValue)
            assert.is_nil(currentValue)
        end)
    end)

    describe("GetCurrentMaxResourceValues safeMax (3rd return)", function()
        it("returns vengeance souls max as safeMax", function()
            local _, _, safeMax = ECM.ClassUtil.GetCurrentMaxResourceValues(ECM.Constants.RESOURCEBAR_TYPE_VENGEANCE_SOULS)
            assert.are.equal(ECM.Constants.RESOURCEBAR_VENGEANCE_SOULS_MAX, safeMax)
        end)

        it("returns icicles max as safeMax", function()
            local _, _, safeMax = ECM.ClassUtil.GetCurrentMaxResourceValues(ECM.Constants.RESOURCEBAR_TYPE_ICICLES)
            assert.are.equal(ECM.Constants.RESOURCEBAR_ICICLES_MAX, safeMax)
        end)

        it("returns devourer normal max as safeMax", function()
            local _, _, safeMax = ECM.ClassUtil.GetCurrentMaxResourceValues(ECM.Constants.RESOURCEBAR_TYPE_DEVOURER_NORMAL)
            assert.are.equal(ECM.Constants.RESOURCEBAR_DEVOURER_SOUL_FRAGMENTS_MAX / 5, safeMax)
        end)

        it("returns devourer meta max as safeMax", function()
            _G.C_UnitAuras = { GetUnitAuraBySpellID = function(_, spellID)
                if spellID == ECM.Constants.SPELLID_COLLAPSING_STAR then
                    return { applications = 10 }
                end
            end }
            local _, _, safeMax = ECM.ClassUtil.GetCurrentMaxResourceValues(ECM.Constants.RESOURCEBAR_TYPE_DEVOURER_META)
            assert.are.equal(ECM.Constants.RESOURCEBAR_COLLAPSING_STAR_MAX / 5, safeMax)
        end)

        it("returns base maelstrom max when talent is unknown", function()
            CSpellBookStub.SetSpellKnown(ECM.Constants.RESOURCEBAR_RAGING_MAELSTROM_SPELLID, false)
            local _, _, safeMax = ECM.ClassUtil.GetCurrentMaxResourceValues(ECM.Constants.RESOURCEBAR_TYPE_MAELSTROM_WEAPON)
            assert.are.equal(ECM.Constants.RESOURCEBAR_MAELSTROM_WEAPON_MAX_BASE, safeMax)
        end)

        it("returns talented maelstrom max when raging maelstrom is known", function()
            CSpellBookStub.SetSpellKnown(ECM.Constants.RESOURCEBAR_RAGING_MAELSTROM_SPELLID, true)
            local _, _, safeMax = ECM.ClassUtil.GetCurrentMaxResourceValues(ECM.Constants.RESOURCEBAR_TYPE_MAELSTROM_WEAPON)
            assert.are.equal(ECM.Constants.RESOURCEBAR_MAELSTROM_WEAPON_MAX_TALENTED, safeMax)
        end)

        it("returns UnitPowerMax as safeMax for standard types when not secret", function()
            UnitStub.SetPowerMax(Enum.PowerType.HolyPower, 5)
            _G.issecretvalue = function() return false end
            local _, _, safeMax = ECM.ClassUtil.GetCurrentMaxResourceValues(Enum.PowerType.HolyPower)
            assert.are.equal(5, safeMax)
        end)

        it("returns nil safeMax for standard types when value is secret", function()
            UnitStub.SetPowerMax(Enum.PowerType.HolyPower, 5)
            _G.issecretvalue = function() return true end
            local _, _, safeMax = ECM.ClassUtil.GetCurrentMaxResourceValues(Enum.PowerType.HolyPower)
            assert.is_nil(safeMax)
        end)

        it("returns nil for nil resource type", function()
            local max, current, safeMax = ECM.ClassUtil.GetCurrentMaxResourceValues(nil)
            assert.is_nil(max)
            assert.is_nil(current)
            assert.is_nil(safeMax)
        end)
    end)
end)
