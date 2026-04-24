-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("ExternalBarsOptions", function()
    local originalGlobals
    local ExternalBarsOptions
    local ns

    local function getRow(rows, rowID)
        for _, row in ipairs(rows or {}) do
            if row.id == rowID then
                return row
            end
        end
        return nil
    end

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals(TestHelpers.OPTIONS_GLOBALS)
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        TestHelpers.SetupOptionsGlobals()

        local profile, defaults = TestHelpers.MakeOptionsProfile()
        profile.externalBars.enabled = true
        defaults.externalBars.enabled = true
        ns = select(2, TestHelpers.SetupOptionsEnv(profile, defaults))

        ns.Addon.ExternalBars = {
            IsEditLocked = function()
                return false
            end,
        }

        TestHelpers.LoadChunk("UI/SpellColorsPage.lua", "Unable to load UI/SpellColorsPage.lua")(nil, ns)
        TestHelpers.LoadChunk("UI/ExternalBarsOptions.lua", "Unable to load UI/ExternalBarsOptions.lua")(nil, ns)
        ExternalBarsOptions = ns.ExternalBarsOptions
    end)

    it("exports the external cooldowns section with only the main page", function()
        assert.are.equal("externalBars", ExternalBarsOptions.key)
        assert.are.equal(ns.L["EXTERNAL_BARS"], ExternalBarsOptions.name)
        assert.are.equal(1, #ExternalBarsOptions.pages)
        assert.are.equal("main", ExternalBarsOptions.pages[1].key)
    end)

    it("does not duplicate the default color row on the main page", function()
        assert.is_nil(getRow(ExternalBarsOptions.pages[1].rows, "defaultColor"))
        assert.is_not_nil(getRow(ExternalBarsOptions.pages[1].rows, "hideOriginalIcons"))
        assert.is_not_nil(getRow(ExternalBarsOptions.pages[1].rows, "showIcon"))
        assert.is_not_nil(getRow(ExternalBarsOptions.pages[1].rows, "showSpellName"))
        assert.is_not_nil(getRow(ExternalBarsOptions.pages[1].rows, "showDuration"))
        assert.is_not_nil(getRow(ExternalBarsOptions.pages[1].rows, "height"))
        assert.is_not_nil(getRow(ExternalBarsOptions.pages[1].rows, "verticalSpacing"))
        assert.is_not_nil(getRow(ExternalBarsOptions.pages[1].rows, "fontOverride"))
    end)

    it("registers the external bars section with the shared spell colors page", function()
        local sharedPage = ns.SpellColorsPage.CreatePage(ns.L["SPELL_COLORS_SUBCAT"])

        assert.are.equal("spellColors", sharedPage.key)
        assert.are.equal("spellColorsPageActions", sharedPage.rows[1].id)
        assert.are.equal("pageActions", sharedPage.rows[1].type)
        assert.are.equal("spellColorsDescription", sharedPage.rows[2].id)
        assert.is_not_nil(getRow(sharedPage.rows, "externalBarsSpellColorsHeader"))
        assert.is_not_nil(getRow(sharedPage.rows, "externalBarsSpellColorsWarning"))
        assert.is_not_nil(getRow(sharedPage.rows, "externalBarsSpellColorCollection"))
        assert.is_not_nil(getRow(sharedPage.rows, "externalBarsSecretNameDescription"))
    end)
end)
