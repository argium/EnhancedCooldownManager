-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

if type(describe) ~= "function" or type(it) ~= "function" then
    return
end

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
        originalGlobals = TestHelpers.captureGlobals({
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
            "ECM_debug_assert",
        })

        _G.ECM = {}
        _G.ECM.DebugAssert = function() end
        _G.GetShapeshiftForm = function()
            return 0
        end

        local constantsChunk = TestHelpers.loadChunk(
            {
                "Constants.lua",
                "../Constants.lua",
            },
            "Unable to load Constants.lua"
        )
        constantsChunk()

        local enumChunk = TestHelpers.loadChunk(
            {
                "Tests/stubs/Enums.lua",
                "stubs/Enums.lua",
                "Enums.lua",
            },
            "Unable to load Tests/stubs/Enums.lua"
        )
        enumChunk()

        UnitStub = TestHelpers.loadChunk(
            {
                "Tests/stubs/Unit.lua",
                "stubs/Unit.lua",
                "Unit.lua",
            },
            "Unable to load Tests/stubs/Unit.lua"
        )()
        CSpellStub = TestHelpers.loadChunk(
            {
                "Tests/stubs/C_Spell.lua",
                "stubs/C_Spell.lua",
                "C_Spell.lua",
            },
            "Unable to load Tests/stubs/C_Spell.lua"
        )()
        CUnitAurasStub = TestHelpers.loadChunk(
            {
                "Tests/stubs/C_UnitAuras.lua",
                "stubs/C_UnitAuras.lua",
                "C_UnitAuras.lua",
            },
            "Unable to load Tests/stubs/C_UnitAuras.lua"
        )()
        CSpellBookStub = TestHelpers.loadChunk(
            {
                "Tests/stubs/C_SpellBook.lua",
                "stubs/C_SpellBook.lua",
                "C_SpellBook.lua",
            },
            "Unable to load Tests/stubs/C_SpellBook.lua"
        )()

        UnitStub.Install()
        CSpellStub.Install()
        CUnitAurasStub.Install()
        CSpellBookStub.Install()

        local chunk = assert(loadfile("Modules/ClassUtil.lua"))
        chunk()
    end)

    teardown(function()
        TestHelpers.restoreGlobals(originalGlobals)
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

        local function setAura(spellID, aura)
            CUnitAurasStub.SetAura(spellID, aura)
        end

        local function setSpellKnown(spellID, isKnown)
            CSpellBookStub.SetSpellKnown(spellID, isKnown)
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
            assertResourceForSpecs(ECM.Constants.CLASS.DEATHKNIGHT, { 1, 2, 3 }, nil)
            setAvailablePowerType(Enum.PowerType.RuneBlood)
            assertResourceForSpecs(ECM.Constants.CLASS.DEATHKNIGHT, { 1, 2, 3 }, nil)
            setAvailablePowerType(Enum.PowerType.RuneFrost)
            assertResourceForSpecs(ECM.Constants.CLASS.DEATHKNIGHT, { 1, 2, 3 }, nil)
            setAvailablePowerType(Enum.PowerType.RuneUnholy)
            assertResourceForSpecs(ECM.Constants.CLASS.DEATHKNIGHT, { 1, 2, 3 }, nil)
        end)

        it("returns souls for vengeance demon hunters", function()
            assertResourceType(
                ECM.Constants.CLASS.DEMONHUNTER,
                ECM.Constants.DEMONHUNTER_VENGEANCE_SPEC_INDEX,
                "souls"
            )
        end)

        it("returns devourerNormal for devourer demon hunters when void fragments are inactive", function()
            setAura(ECM.Constants.SPELLID_VOID_FRAGMENTS, nil)
            setSpellKnown(ECM.Constants.SPELLID_VOID_FRAGMENTS, false)
            assertResourceType(
                ECM.Constants.CLASS.DEMONHUNTER,
                ECM.Constants.DEMONHUNTER_DEVOURER_SPEC_INDEX,
                "devourerNormal"
            )
        end)

        it("returns devourerMeta for devourer demon hunters when void fragments are active", function()
            setAura(ECM.Constants.SPELLID_VOID_FRAGMENTS, { applications = 1 })
            setSpellKnown(ECM.Constants.SPELLID_VOID_FRAGMENTS, true)
            assertResourceType(
                ECM.Constants.CLASS.DEMONHUNTER,
                ECM.Constants.DEMONHUNTER_DEVOURER_SPEC_INDEX,
                "devourerMeta"
            )
        end)

        it("returns combo points for feral druids in cat form", function()
            setAvailablePowerType(Enum.PowerType.ComboPoints)
            assertResourceType(ECM.Constants.CLASS.DRUID, 2, Enum.PowerType.ComboPoints, ECM.Constants.DRUID_CAT_FORM_INDEX)
        end)

        it("returns essence for all evoker specs", function()
            setAvailablePowerType(Enum.PowerType.Essence)
            assertResourceForSpecs(ECM.Constants.CLASS.EVOKER, { 1, 2, 3 }, Enum.PowerType.Essence)
        end)

        it("returns nil for all hunter specs", function()
            assertResourceForSpecs(ECM.Constants.CLASS.HUNTER, { 1, 2, 3 }, nil)
        end)

        it("returns arcane charges for arcane mages and nil for fire/frost", function()
            assertResourceType(ECM.Constants.CLASS.MAGE, 1, Enum.PowerType.ArcaneCharges)
            assertResourceType(ECM.Constants.CLASS.MAGE, 2, nil)
            assertResourceType(ECM.Constants.CLASS.MAGE, 3, nil)
        end)

        it("returns chi for windwalker monks, nil for brewmaster and mistweaver", function()
            setAvailablePowerType(Enum.PowerType.Chi)
            assertResourceType(ECM.Constants.CLASS.MONK, ECM.Constants.MONK_WINDWALKER_SPEC_INDEX, Enum.PowerType.Chi)
            assertResourceType(ECM.Constants.CLASS.MONK, ECM.Constants.MONK_BREWMASTER_SPEC_INDEX, nil)
            assertResourceType(ECM.Constants.CLASS.MONK, ECM.Constants.MONK_MISTWEAVER_SPEC_INDEX, nil)
        end)

        it("returns holy power for all paladin specs", function()
            setAvailablePowerType(Enum.PowerType.HolyPower)
            assertResourceForSpecs(ECM.Constants.CLASS.PALADIN, { 1, 2, 3 }, Enum.PowerType.HolyPower)
        end)

        it("returns nil for all priest specs", function()
            assertResourceForSpecs(ECM.Constants.CLASS.PRIEST, { 1, 2, 3 }, nil)
        end)

        it("returns combo points for all rogue specs", function()
            setAvailablePowerType(Enum.PowerType.ComboPoints)
            assertResourceForSpecs(ECM.Constants.CLASS.ROGUE, { 1, 2, 3 }, Enum.PowerType.ComboPoints)
        end)

        it("returns maelstrom weapon for enhancement shamans and nil for elemental/restoration", function()
            setAvailablePowerType(Enum.PowerType.Maelstrom)
            assertResourceType(
                ECM.Constants.CLASS.SHAMAN,
                ECM.Constants.SHAMAN_ENHANCEMENT_SPEC_INDEX,
                ECM.Constants.RESOURCEBAR_TYPE_MAELSTROM_WEAPON
            )
            assertResourceType(ECM.Constants.CLASS.SHAMAN, ECM.Constants.SHAMAN_ELEMENTAL_SPEC_INDEX, nil)
            assertResourceType(ECM.Constants.CLASS.SHAMAN, ECM.Constants.SHAMAN_RESTORATION_SPEC_INDEX, nil)
        end)

        it("returns soul shards for all warlock specs", function()
            setAvailablePowerType(Enum.PowerType.SoulShards)
            assertResourceForSpecs(ECM.Constants.CLASS.WARLOCK, { 1, 2, 3 }, Enum.PowerType.SoulShards)
        end)

        it("returns nil for all warrior specs", function()
            assertResourceForSpecs(ECM.Constants.CLASS.WARRIOR, { 1, 2, 3 }, nil)
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
            assertValues("souls", ECM.Constants.RESOURCEBAR_VENGEANCE_SOULS_MAX, 4)
        end)

        it("returns souls current value as zero when spell cast count is unavailable", function()
            assertValues("souls", ECM.Constants.RESOURCEBAR_VENGEANCE_SOULS_MAX, 0)
        end)

        it("returns devourer meta values when collapsing star aura is active", function()
            CUnitAurasStub.SetAura(ECM.Constants.SPELLID_VOID_FRAGMENTS, { applications = 11 })
            CUnitAurasStub.SetAura(ECM.Constants.SPELLID_COLLAPSING_STAR, { applications = 7 })
            assertValues("devourerMeta", ECM.Constants.RESOURCEBAR_DEVOURER_META_MAX, 7)
        end)

        it("returns devourer normal values from void fragments when meta aura is inactive", function()
            CUnitAurasStub.SetAura(ECM.Constants.SPELLID_VOID_FRAGMENTS, { applications = 12 })
            assertValues("devourerNormal", ECM.Constants.RESOURCEBAR_DEVOURER_NORMAL_MAX, 12)
        end)

        it("returns devourer normal zero stacks when no aura is present", function()
            assertValues("devourerNormal", ECM.Constants.RESOURCEBAR_DEVOURER_NORMAL_MAX, 0)
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
end)
